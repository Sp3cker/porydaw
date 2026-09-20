#include "checks/midi/tst_midiexport.h"

#include <QByteArray>
#include <QFile>
#include <QFileInfo>
#include <QSemaphore>
#include <QTemporaryDir>
#include <QtTest>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <utility>

#include "audio/swift_playback.h"
#include "audio/wavexport.h"
#include "project/swift_project_service.h"

namespace {

struct ProjectServiceDeleter {
    void operator()(PdProjectService *service) const { pd_service_destroy(service); }
};

struct BankLeaseDeleter {
    void operator()(PdBankLease *lease) const { pd_bank_lease_release(lease); }
};

struct OpenWait {
    QSemaphore done;
    bool ok = false;
    QString error;
};

struct SongWait {
    QSemaphore done;
    bool ok = false;
    QString error;
    QString midiPath;
    int masterVolume = 127;
    int reverb = 0;
    PdBankLease *lease = nullptr;
};

struct ExportFixture {
    std::unique_ptr<PdProjectService, ProjectServiceDeleter> service;
    std::unique_ptr<PdBankLease, BankLeaseDeleter> bank;
    std::shared_ptr<const PdPlaybackData> timeline;
    SongSettings settings;
    WavExportOptions options;
};

void openCompletion(void *context, bool ok, const char *error)
{
    auto &wait = *static_cast<OpenWait *>(context);
    wait.ok = ok;
    wait.error = error ? QString::fromUtf8(error) : QString{};
    wait.done.release();
}

void songCompletion(void *context, bool ok, const uint8_t *, size_t, const PdSongMeta *meta,
                    const PdBankView *bank, PdBankLease *lease, const char *error)
{
    auto &wait = *static_cast<SongWait *>(context);
    wait.ok = ok && meta && bank && lease;
    wait.error = error ? QString::fromUtf8(error) : QString{};
    if (wait.ok) {
        wait.midiPath = QString::fromUtf8(meta->midiPath);
        wait.masterVolume = meta->cfg.masterVolume;
        wait.reverb = meta->cfg.reverb;
        wait.lease = lease;
    } else {
        if (lease)
            pd_bank_lease_release(lease);
        if (wait.error.isEmpty())
            wait.error = QStringLiteral("project service returned an incomplete song");
    }
    wait.done.release();
}

uint32_t littleEndianU32(const QByteArray &bytes, qsizetype offset)
{
    return uint32_t(uint8_t(bytes[offset])) | uint32_t(uint8_t(bytes[offset + 1])) << 8 |
           uint32_t(uint8_t(bytes[offset + 2])) << 16 | uint32_t(uint8_t(bytes[offset + 3])) << 24;
}

uint16_t littleEndianU16(const QByteArray &bytes, qsizetype offset)
{
    return uint16_t(uint8_t(bytes[offset])) | uint16_t(uint8_t(bytes[offset + 1])) << 8;
}

int16_t sampleAt(const QByteArray &bytes, uint64_t index)
{
    const qsizetype offset = 44 + static_cast<qsizetype>(index * 2);
    return static_cast<int16_t>(littleEndianU16(bytes, offset));
}

bool readFile(const QString &path, QByteArray &bytes, QString &error)
{
    auto file = QFile{path};
    if (!file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("cannot read %1: %2").arg(path, file.errorString());
        return false;
    }
    bytes = file.readAll();
    return true;
}

std::unique_ptr<ExportFixture> loadExportFixture(const QString &projectRoot,
                                                 const QString &songLabel, QString &error)
{
    auto fixture = std::make_unique<ExportFixture>();
    fixture->service.reset(pd_service_create());
    if (!fixture->service) {
        error = QStringLiteral("cannot allocate project service");
        return nullptr;
    }

    OpenWait opened;
    const QByteArray root = projectRoot.toUtf8();
    pd_service_open(fixture->service.get(), root.constData(), &opened, openCompletion);
    opened.done.acquire();
    if (!opened.ok) {
        error = opened.error;
        return nullptr;
    }

    SongWait song;
    const QByteArray label = songLabel.toUtf8();
    pd_service_open_song(fixture->service.get(), label.constData(), &song, songCompletion);
    song.done.acquire();
    if (!song.ok) {
        error = song.error;
        return nullptr;
    }
    fixture->bank.reset(song.lease);

    fixture->settings.songVolume = static_cast<uint8_t>(song.masterVolume);
    fixture->settings.reverb = static_cast<uint8_t>(song.reverb > 0 ? song.reverb : 0);
    fixture->options.sampleRate = 44100;
    fixture->options.loopCount = 1;
    fixture->options.fadeoutSeconds = 1.0;
    fixture->options.tailSeconds = 1.0;

    PdPlaybackData *publication = nullptr;
    std::array<char, 1024> diagnostic{};
    const QByteArray midiPath = song.midiPath.toUtf8();
    if (!pd_playback_data_load_file(midiPath.constData(), double(fixture->options.sampleRate),
                                    &publication, diagnostic.data(), diagnostic.size())) {
        if (publication)
            pd_playback_data_release(publication);
        error = QString::fromUtf8(diagnostic.data());
        if (error.isEmpty())
            error = QStringLiteral("could not load Swift playback timeline for %1").arg(songLabel);
        return nullptr;
    }
    if (!publication) {
        error = QStringLiteral("Swift playback loader returned no timeline for %1").arg(songLabel);
        return nullptr;
    }
    fixture->timeline =
        std::shared_ptr<const PdPlaybackData>{publication, pd_playback_data_release};
    error.clear();
    return fixture;
}

bool hasLoop(const PdPlaybackData &timeline)
{
    return timeline.loopStartSample != UINT64_MAX && timeline.loopEndSample != UINT64_MAX &&
           timeline.loopEndSample > timeline.loopStartSample;
}

uint64_t expectedTotalSamples(const PdPlaybackData &timeline, const WavExportOptions &options)
{
    if (hasLoop(timeline)) {
        const uint64_t loopDuration = timeline.loopEndSample - timeline.loopStartSample;
        return timeline.loopStartSample + loopDuration + uint64_t(options.sampleRate);
    }
    return timeline.lengthSamples + uint64_t(options.sampleRate);
}

} // namespace

MidiExportTest::MidiExportTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

void MidiExportTest::initTestCase()
{
    QVERIFY2(
        QFileInfo{m_projectRoot}.isDir(),
        qPrintable(
            QStringLiteral("exportcheck project root is not a directory: %1").arg(m_projectRoot)));
    QVERIFY2(!m_songLabel.isEmpty(), "exportcheck requires a song label");
}

void MidiExportTest::durationCalculationMatchesRenderParity()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));

    const WavExportTotals totals = wavExportTotals(*fixture->timeline, fixture->options);
    QCOMPARE(qulonglong(totals.totalSamples),
             qulonglong(expectedTotalSamples(*fixture->timeline, fixture->options)));
}

void MidiExportTest::offlineExportProducesValidRiffPcm()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));
    const WavExportTotals totals = wavExportTotals(*fixture->timeline, fixture->options);

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create WAV export scratch directory");
    const QString path = scratch.filePath(QStringLiteral("export.wav"));
    double lastFraction = -1.0;
    bool strictlyMonotonic = true;
    QVERIFY2(exportWav(
                 path, *fixture->timeline, pd_bank_lease_native(fixture->bank.get()),
                 fixture->settings, fixture->options,
                 [&](double fraction) {
                     strictlyMonotonic = strictlyMonotonic && fraction > lastFraction;
                     lastFraction = fraction;
                     return true;
                 },
                 &error),
             qPrintable(error));
    QVERIFY2(strictlyMonotonic && lastFraction == 1.0,
             "WAV export progress was not strictly monotonic through 1.0");

    auto wav = QByteArray{};
    QVERIFY2(readFile(path, wav, error), qPrintable(error));
    const uint64_t dataSize = totals.totalSamples * 4;
    QVERIFY2(uint64_t(wav.size()) == 44 + dataSize,
             "WAV byte count does not match the rendered frame count");
    QVERIFY(wav.size() >= 44);
    QCOMPARE(wav.left(4), QByteArray("RIFF"));
    QCOMPARE(wav.mid(8, 4), QByteArray("WAVE"));
    QCOMPARE(wav.mid(12, 4), QByteArray("fmt "));
    QCOMPARE(wav.mid(36, 4), QByteArray("data"));
    QCOMPARE(int(littleEndianU16(wav, 20)), 1);
    QCOMPARE(int(littleEndianU16(wav, 22)), 2);
    QCOMPARE(int(littleEndianU16(wav, 34)), 16);
    QCOMPARE(qulonglong(littleEndianU32(wav, 24)), qulonglong(fixture->options.sampleRate));
    QCOMPARE(qulonglong(littleEndianU32(wav, 40)), qulonglong(dataSize));

    int peak = 0;
    for (uint64_t sampleIndex = 0; sampleIndex < totals.totalSamples * 2; ++sampleIndex)
        peak = std::max(peak, std::abs(int(sampleAt(wav, sampleIndex))));
    QVERIFY2(peak >= 256, "offline WAV render is nearly silent");

    if (hasLoop(*fixture->timeline)) {
        QVERIFY2(totals.totalSamples >= 16, "looping export is too short for tail verification");
        int tailPeak = 0;
        for (uint64_t sampleIndex = (totals.totalSamples - 16) * 2;
             sampleIndex < totals.totalSamples * 2; ++sampleIndex) {
            tailPeak = std::max(tailPeak, std::abs(int(sampleAt(wav, sampleIndex))));
        }
        QVERIFY2(tailPeak <= peak / 16, "looping WAV export did not fade to silence");
    }
}

void MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create resonance-export scratch directory");
    const QString baselinePath = scratch.filePath(QStringLiteral("baseline.wav"));
    const QString suppressedPath = scratch.filePath(QStringLiteral("suppressed.wav"));
    QVERIFY2(exportWav(baselinePath, *fixture->timeline, pd_bank_lease_native(fixture->bank.get()),
                       fixture->settings, fixture->options, {}, &error),
             qPrintable(error));
    auto baseline = QByteArray{};
    QVERIFY2(readFile(baselinePath, baseline, error), qPrintable(error));

    fixture->options.resonanceSuppression = true;
    QVERIFY2(exportWav(suppressedPath, *fixture->timeline,
                       pd_bank_lease_native(fixture->bank.get()), fixture->settings,
                       fixture->options, {}, &error),
             qPrintable(error));
    auto suppressed = QByteArray{};
    QVERIFY2(readFile(suppressedPath, suppressed, error), qPrintable(error));
    QCOMPARE(suppressed.size(), baseline.size());
    QVERIFY2(suppressed != baseline, "resonance suppression did not alter exported PCM bytes");
}

void MidiExportTest::cancelledExportRemovesPartialFile()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create cancellation-export scratch directory");
    const QString path = scratch.filePath(QStringLiteral("cancelled.wav"));
    fixture->options.resonanceSuppression = true;
    QVERIFY(!exportWav(
        path, *fixture->timeline, pd_bank_lease_native(fixture->bank.get()), fixture->settings,
        fixture->options, [](double) { return false; }, &error));
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY2(!QFile::exists(path), "cancelled WAV export left a partial file");
}

int runExportCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments)
{
    auto test = MidiExportTest{projectRoot, songLabel};
    auto arguments = QStringList{QStringLiteral("exportcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
