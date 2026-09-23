#include "native_check.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStringList>

#include <array>
#include <cstdint>
#include <memory>

#include "checks/playback/sustainvoicegroup.h"
#include "project/decompproject.h"

extern "C" {
#include "m4a_engine.h"
}

namespace {
QByteArray gFixtureRoot;
QByteArray gMid2agbPath;

constexpr std::array<const char *, 14> kRoundtripSongs = {
    "mus_caught",       "mus_dummy",       "mus_gsc_route38", "mus_gym",      "mus_littleroot_test",
    "mus_oldale",       "mus_petalburg",   "mus_route101",    "mus_route102", "mus_surf",
    "mus_victory_wild", "se_fanfare_1trk", "se_pc_login",     "se_use_item",
};

bool writeFile(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

bool compileMidi(const QString &midiPath, const QStringList &flags, QByteArray &assembly)
{
    const QString outputPath = midiPath.left(midiPath.size() - 4) + QStringLiteral(".s");
    QFile::remove(outputPath);

    QProcess process;
    auto arguments = flags;
    arguments << midiPath << outputPath;
    process.start(QFile::decodeName(gMid2agbPath), arguments);
    if (!process.waitForFinished(15'000) || process.exitStatus() != QProcess::NormalExit ||
        process.exitCode() != 0) {
        return false;
    }

    QFile output(outputPath);
    if (!output.open(QIODevice::ReadOnly))
        return false;
    assembly = output.readAll();
    return true;
}

const SongInfo *songWithLabel(const DecompProject &project, const QString &label)
{
    for (const SongInfo &song : project.songs()) {
        if (song.label == label && song.isPlayable())
            return &song;
    }
    return nullptr;
}
} // namespace

struct PdcPlaybackEngine {
    M4AEngine engine{};
    checks::SustainVoicegroup bank;
    bool initialized = false;

    explicit PdcPlaybackEngine(double sampleRate)
    {
        ToneData &square = bank.voices[2];
        square.type = VOICE_SQUARE_2;
        square.key = 60;
        square.wavePointer = reinterpret_cast<uint32_t *>(uintptr_t{2});
        square.attack = 7;
        square.decay = 0;
        square.sustain = 15;
        square.release = 7;
        initialized = m4a_engine_init(&engine, float(sampleRate));
        if (initialized)
            m4a_engine_set_voicegroup(&engine, bank.voices);
    }

    bool reinitialize(double sampleRate)
    {
        if (initialized)
            m4a_engine_destroy(&engine);
        initialized = m4a_engine_init(&engine, float(sampleRate));
        if (initialized)
            m4a_engine_set_voicegroup(&engine, bank.voices);
        return initialized;
    }

    ~PdcPlaybackEngine()
    {
        if (initialized)
            m4a_engine_destroy(&engine);
    }
};

extern "C" void pdc_check_set_fixture_root(const char *path)
{
    gFixtureRoot = path ? QByteArray(path) : QByteArray();
}

extern "C" const char *pdc_check_fixture_root()
{
    return gFixtureRoot.isEmpty() ? nullptr : gFixtureRoot.constData();
}

extern "C" void pdc_check_set_mid2agb_path(const char *path)
{
    gMid2agbPath = path ? QByteArray(path) : QByteArray();
}

extern "C" PdcMidiExportResult pdc_check_midi_exports()
{
    PdcMidiExportResult result{};
    const QString fixtureRoot = QFile::decodeName(gFixtureRoot);
    const QDir exportRoot(QDir(fixtureRoot).filePath(QStringLiteral("swiftcore-midi-export")));
    const QString originalRoot = exportRoot.filePath(QStringLiteral("original"));
    if (fixtureRoot.isEmpty() || gMid2agbPath.isEmpty() || !QDir().mkpath(originalRoot)) {
        result.projectOpenFailed = 1;
        return result;
    }

    DecompProject project;
    QString projectError;
    if (!project.open(fixtureRoot, &projectError)) {
        result.projectOpenFailed = 1;
        return result;
    }

    for (size_t index = 0; index < kRoundtripSongs.size(); ++index) {
        const uint32_t bit = uint32_t{1} << index;
        const QString label = QString::fromUtf8(kRoundtripSongs[index]);
        const SongInfo *song = songWithLabel(project, label);
        if (!song) {
            result.missingSongBits |= bit;
            continue;
        }

        QFile source(song->midPath);
        const QString fileName = label + QStringLiteral(".mid");
        const QString originalPath = QDir(originalRoot).filePath(fileName);
        const QString encodedPath = exportRoot.filePath(QStringLiteral("encoded/") + fileName);
        if (!source.open(QIODevice::ReadOnly) || !writeFile(originalPath, source.readAll())) {
            result.originalCompileFailureBits |= bit;
            continue;
        }

        QByteArray originalAssembly;
        if (!compileMidi(originalPath, song->cfg.rawFlags, originalAssembly)) {
            result.originalCompileFailureBits |= bit;
            continue;
        }
        QByteArray encodedAssembly;
        if (!compileMidi(encodedPath, song->cfg.rawFlags, encodedAssembly)) {
            result.encodedCompileFailureBits |= bit;
            continue;
        }
        if (originalAssembly == encodedAssembly)
            result.matchingSongBits |= bit;
    }

    QByteArray xcmdAssembly;
    const QString xcmdPath = exportRoot.filePath(QStringLiteral("echo_traffic.mid"));
    if (!compileMidi(xcmdPath, {}, xcmdAssembly)) {
        result.xcmdCompileFailed = 1;
        return result;
    }
    result.xiecvCount = int32_t(xcmdAssembly.count(QByteArrayLiteral("xIECV")));
    result.xieclCount = int32_t(xcmdAssembly.count(QByteArrayLiteral("xIECL")));
    result.xiecv64Count = int32_t(xcmdAssembly.count(QByteArrayLiteral("xIECV , 64")));
    result.xiecl51Count = int32_t(xcmdAssembly.count(QByteArrayLiteral("xIECL , 51")));
    result.unknown127Count = int32_t(xcmdAssembly.count(QByteArrayLiteral("xIECV , 127")) +
                                     xcmdAssembly.count(QByteArrayLiteral("xIECL , 127")));
    return result;
}

extern "C" int32_t pdc_check_compile_saved_midi(const char *projectRoot, const char *songLabel)
{
    if (!projectRoot || !songLabel || gMid2agbPath.isEmpty())
        return 0;

    DecompProject project;
    QString projectError;
    if (!project.open(QFile::decodeName(projectRoot), &projectError))
        return 0;
    const SongInfo *song = songWithLabel(project, QFile::decodeName(songLabel));
    if (!song)
        return 0;

    QByteArray assembly;
    return compileMidi(song->midPath, song->cfg.rawFlags, assembly) ? 1 : 0;
}

extern "C" PdcPlaybackEngine *pdc_playback_engine_create(double sampleRate)
{
    std::unique_ptr<PdcPlaybackEngine> engine = std::make_unique<PdcPlaybackEngine>(sampleRate);
    if (!engine->initialized)
        return nullptr;
    return engine.release();
}

extern "C" int32_t pdc_playback_engine_reinitialize(PdcPlaybackEngine *engine, double sampleRate)
{
    return engine && engine->reinitialize(sampleRate);
}

extern "C" void pdc_playback_engine_destroy(PdcPlaybackEngine *engine)
{
    delete engine;
}

extern "C" void *pdc_playback_engine_pointer(PdcPlaybackEngine *engine)
{
    return engine ? &engine->engine : nullptr;
}
