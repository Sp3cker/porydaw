#include "../../third_party/voicegroup-core/include/voicegroup_core.h"
#include "project/voicegroupproject.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QThread>

#include <array>
#include <cstddef>
#include <cstdio>
#include <functional>
#include <type_traits>
#include <utility>

namespace {
static_assert(std::is_default_constructible_v<porydaw::VoicegroupProject>);
static_assert(std::is_nothrow_move_constructible_v<porydaw::VoicegroupProject>);
static_assert(!std::is_copy_constructible_v<porydaw::VoicegroupProject>);
static_assert(std::is_nothrow_move_constructible_v<porydaw::VoicegroupProject::LoadResult>);
static_assert(!std::is_copy_constructible_v<porydaw::VoicegroupProject::LoadResult>);
static_assert(std::is_nothrow_move_constructible_v<porydaw::VoicegroupProject::AssetResult>);
static_assert(!std::is_copy_constructible_v<porydaw::VoicegroupProject::AssetResult>);

constexpr auto VALID_BANK = "voice_group main\n"
                            "\tvoice_directsound 60, 0, DirectSoundWave, 255, 0, 255, 0\n";
constexpr auto CORRUPT_BANK = "voice_group main\n"
                              "\tvoice_directsounnd 60, 0, DirectSoundWave, 255, 0, 255, 0\n";
constexpr auto VOICEGROUP_INCLUDE_HUB = "\t.include \"sound/voicegroups/nested/hub.inc\"\n";
constexpr auto DIRECT_SOUND_DATA = "DirectSoundWave::\n"
                                   "\t.incbin \"sound/direct_sound_samples/kick.bin\"\n";

bool writeFile(const QString &path, QByteArrayView bytes)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;
    auto file = QFile(path);
    return file.open(QIODevice::WriteOnly | QIODevice::Truncate) &&
           file.write(bytes.data(), bytes.size()) == bytes.size();
}

bool replaceFile(const QString &path, QByteArrayView bytes)
{
    auto file = QSaveFile(path);
    return file.open(QIODevice::WriteOnly) &&
           file.write(bytes.data(), bytes.size()) == bytes.size() && file.commit();
}

bool waitUntil(const std::function<bool()> &condition, qint64 timeoutMs = 3000)
{
    auto timer = QElapsedTimer{};
    timer.start();
    while (!condition() && timer.elapsed() < timeoutMs) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        if (!condition())
            QThread::msleep(2);
    }
    QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return condition();
}

void settleEvents(const std::function<int()> &eventCount)
{
    auto total = QElapsedTimer{};
    auto quiet = QElapsedTimer{};
    total.start();
    quiet.start();
    auto previous = eventCount();
    while (total.elapsed() < 1000 && quiet.elapsed() < 100) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        const auto current = eventCount();
        if (current != previous) {
            previous = current;
            quiet.restart();
        }
        QThread::msleep(2);
    }
}

bool hasPath(const QStringList &paths, const QString &path)
{
    return paths.contains(path);
}

} // namespace

int runVoicegroupCoreAbiCheck()
{
    const auto runtime = voicegroup_core_abi_version();
    const auto expected = VOICEGROUP_CORE_ABI_VERSION;
    if (runtime != expected) {
        std::fprintf(stderr,
                     "voicegroup-core-abi: FAIL: runtime ABI %u differs from header ABI %u\n",
                     static_cast<unsigned>(runtime), static_cast<unsigned>(expected));
        return 1;
    }
    std::printf("voicegroup-core-abi: PASS (runtime=%u, header=%u)\n",
                static_cast<unsigned>(runtime), static_cast<unsigned>(expected));
    return 0;
}

int runContextCheck(const QString &scratchDir)
{
    auto failures = 0;
    const auto expect = [&](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "contextcheck: FAIL: %s\n", message);
            ++failures;
        }
    };
    const auto root = QDir(scratchDir).absolutePath();
    const auto includeHubPath = QDir(root).filePath(QStringLiteral("sound/voice_groups.inc"));
    const auto nestedRelativePath = QStringLiteral("sound/voicegroups/nested/hub.inc");
    const auto bankPath = QDir(root).filePath(nestedRelativePath);
    const auto directSoundPath = QDir(root).filePath(QStringLiteral("sound/direct_sound_data.inc"));
    const auto samplePath =
        QDir(root).filePath(QStringLiteral("sound/direct_sound_samples/kick.bin"));
    expect(QDir(root).exists(), "scratch directory exists");
    expect(QFileInfo(root).isWritable(), "scratch directory is writable");
    expect(writeFile(includeHubPath, QByteArrayView(VOICEGROUP_INCLUDE_HUB)),
           "nested discovery: write include hub");
    expect(writeFile(bankPath, QByteArrayView(VALID_BANK)),
           "nested discovery: write nested voice group source");
    expect(writeFile(directSoundPath, QByteArrayView(DIRECT_SOUND_DATA)),
           "nested discovery: write DirectSound catalog");
    expect(writeFile(QDir(root).filePath(QStringLiteral("sound/programmable_wave_data.inc")), {}),
           "write empty programmable-wave catalog");
    expect(writeFile(QDir(root).filePath(QStringLiteral("sound/keysplit_tables.inc")), {}),
           "write empty keysplit catalog");
    auto sample = QByteArray(19, '\0');
    sample[5] = '\x04';
    sample[12] = '\x03';
    sample[16] = '\x11';
    sample[17] = '\x22';
    sample[18] = '\x33';
    expect(writeFile(samplePath, sample), "write DirectSound sample");

    auto project = porydaw::VoicegroupProject{};
    auto staleNotifications = 0;
    project.setStaleCallback([&staleNotifications] { ++staleNotifications; });
    auto snapshot = project.open(root);
    expect(project.isOpen(), "open owns a project handle");
    expect(snapshot.succeeded, "open performs a successful first refresh");
    expect(snapshot.diagnostics.isEmpty(), "initial refresh has no diagnostics");
    expect(!snapshot.catalog.isEmpty(), "initial refresh copies catalog metadata");
    bool nestedCatalogEntry = false;
    for (const auto &entry : snapshot.catalog) {
        if (entry.symbol == QStringLiteral("voicegroup_main") &&
            entry.sourcePath == nestedRelativePath) {
            nestedCatalogEntry = true;
            break;
        }
    }
    expect(nestedCatalogEntry,
           "nested discovery: catalog records the included bank's content path");
    expect(hasPath(snapshot.contentPaths, nestedRelativePath),
           "nested discovery: snapshot copies nested content path");
    expect(hasPath(snapshot.watchPaths, QStringLiteral("sound/voice_groups.inc")),
           "nested discovery: snapshot watches include hub");
    expect(hasPath(snapshot.watchPaths, nestedRelativePath),
           "nested discovery: snapshot watches nested source");
    expect(hasPath(snapshot.watchPaths, QStringLiteral("sound/direct_sound_samples/kick.bin")),
           "nested discovery: snapshot watches catalog dependencies");

    auto context = std::move(project);
    staleNotifications = 0;
    expect(writeFile(bankPath, QByteArray(VALID_BANK) + QByteArray("\n")),
           "invalidation: nested source mutation is observed");
    expect(waitUntil([&] { return staleNotifications > 0; }),
           "invalidation: nested source mutation marks the moved project stale");
    snapshot = context.refresh();
    expect(snapshot.succeeded, "invalidation: nested source refresh succeeds");
    expect(hasPath(snapshot.contentPaths, nestedRelativePath),
           "invalidation: refreshed snapshot retains nested content");

    settleEvents([&] { return staleNotifications; });
    staleNotifications = 0;
    expect(writeFile(directSoundPath, QByteArray(DIRECT_SOUND_DATA) + QByteArray("\n")),
           "invalidation: catalog dependency mutation is observed");
    expect(waitUntil([&] { return staleNotifications > 0; }),
           "invalidation: dependency mutation marks the moved project stale");
    snapshot = context.refresh();
    expect(snapshot.succeeded, "invalidation: dependency refresh succeeds");
    settleEvents([&] { return staleNotifications; });
    staleNotifications = 0;
    expect(writeFile(bankPath, QByteArrayView(CORRUPT_BANK)),
           "invalidation: write corrupt nested source");
    expect(waitUntil([&] { return staleNotifications > 0; }),
           "invalidation: corrupt mutation marks the project stale");
    snapshot = context.refresh();
    expect(!snapshot.succeeded, "invalidation: corrupt refresh reports failure");
    expect(!snapshot.diagnostics.isEmpty(),
           "invalidation: corrupt refresh copies structured diagnostics");
    context.markStale();
    const auto explicitNotificationCount = staleNotifications;
    expect(writeFile(bankPath, QByteArrayView(VALID_BANK)),
           "invalidation: fix corrupt nested source");
    expect(waitUntil([&] { return staleNotifications > explicitNotificationCount; }),
           "invalidation: fixed mutation is observed after explicit stale mark");
    snapshot = context.refresh();
    expect(snapshot.succeeded, "invalidation: stale/fix/retry recovers");

    settleEvents([&] { return staleNotifications; });
    staleNotifications = 0;
    expect(replaceFile(bankPath, QByteArray(VALID_BANK) + QByteArray("\n")),
           "invalidation/re-arm: atomically replace watched nested source");
    expect(waitUntil([&] { return staleNotifications > 0; }),
           "invalidation/re-arm: replacement triggers the parent-directory watch");
    snapshot = context.refresh();
    expect(snapshot.succeeded, "invalidation/re-arm: first replacement refresh succeeds");
    settleEvents([&] { return staleNotifications; });
    staleNotifications = 0;
    expect(replaceFile(bankPath, QByteArray(VALID_BANK) + QByteArray("\n\n")),
           "invalidation/re-arm: atomically replace watched source again");
    expect(waitUntil([&] { return staleNotifications > 0; }),
           "invalidation/re-arm: successful refresh re-arms replacement watching");
    snapshot = context.refresh();
    expect(snapshot.succeeded, "invalidation/re-arm: second replacement refresh succeeds");

    {
        auto load = context.loadSaved(QStringLiteral("main"));
        expect(load.succeeded(), "saved bank loads");
        expect(load.diagnostics().isEmpty(), "saved bank has no diagnostics");
        auto *bank = load.take();
        expect(bank != nullptr, "load result transfers its bank");
        porydaw::VoicegroupProject::freeBank(bank);
    }
    {
        auto untaken = context.loadSaved(QStringLiteral("main"));
        expect(untaken.succeeded(), "untaken bank loads before automatic destruction");
    }
    {
        const auto source =
            QByteArray("voice_group preview\n"
                       "\tvoice_directsound 60, 7, PendingSynth, 255, 0, 255, 242\n");
        const auto overlays = std::array{porydaw::VoicegroupProject::SynthOverlay{
            .name = QStringLiteral("PendingSynth"),
            .descriptor = {0x80, 0x12, 0x34, 0x56, 0x78, 0x9a},
        }};
        auto load =
            context.loadSource(QStringLiteral("preview"),
                               QStringLiteral("sound/voicegroups/preview.inc"), source, overlays);
        expect(load.succeeded(), "source text loads with a transient synth overlay");
        auto *bank = load.take();
        expect(bank != nullptr, "source load transfers its bank");
        porydaw::VoicegroupProject::freeBank(bank);
    }
    {
        auto asset = context.loadAsset(porydaw::VoicegroupProject::AssetKind::DirectSound,
                                       QStringLiteral("DirectSoundWave"));
        expect(asset.diagnostics().isEmpty(), "DirectSound asset loads without diagnostics");
        expect(asset.kind() == porydaw::VoicegroupProject::AssetKind::DirectSound,
               "asset exposes its typed kind");
        expect(asset.symbol() == QStringLiteral("DirectSoundWave"), "asset copies its symbol");
        expect(asset.payload().size() == 3, "asset exposes its arena-backed payload");
        expect(!asset.payload().empty() &&
                   std::to_integer<unsigned char>(asset.payload()[0]) == 0x11,
               "asset payload remains valid for the result lifetime");
        expect(asset.frameCount() == 3, "asset exposes typed frame metadata");
    }

    context.close();
    expect(!context.isOpen(), "close releases the project handle");
    std::printf("contextcheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
