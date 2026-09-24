#include "native_check.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QList>
#include <QProcess>
#include <QRegularExpression>
#include <QStringList>
#include <QTextStream>

#include <array>
#include <cstdint>
#include <memory>
#include <utility>

#include "checks/playback/sustainvoicegroup.h"

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

// Harness-local song metadata: no dependency on the project service or the removed C++ registry.
struct SongInfo {
    QString label;
    QString midPath;
    bool hasMid = false;
    struct {
        QStringList rawFlags;
    } cfg;

    bool isPlayable() const { return hasMid; }
};

QString expandVariables(QString text, const QHash<QString, QString> &variables)
{
    static const QRegularExpression reference(QStringLiteral(R"(\$\(([A-Za-z_][A-Za-z0-9_]*)\))"));
    for (int depth = 0; depth < 8 && text.contains(QLatin1Char('$')); ++depth) {
        QString expanded;
        qsizetype position = 0;
        auto matches = reference.globalMatch(text);
        if (!matches.hasNext())
            break;
        while (matches.hasNext()) {
            const auto match = matches.next();
            expanded += text.mid(position, match.capturedStart() - position);
            expanded += variables.value(match.captured(1));
            position = match.capturedEnd();
        }
        expanded += text.mid(position);
        text = std::move(expanded);
    }
    return text;
}

bool readSongTable(const QString &root, QList<SongInfo> &songs)
{
    QFile table(root + QStringLiteral("/sound/song_table.inc"));
    if (!table.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    static const QRegularExpression songPattern(
        QStringLiteral(R"(^\s*song\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+))"));
    const QString midiDir = root + QStringLiteral("/sound/songs/midi/");
    QTextStream tableLines(&table);
    while (!tableLines.atEnd()) {
        const auto match = songPattern.match(tableLines.readLine());
        if (!match.hasMatch())
            continue;
        SongInfo song;
        song.label = match.captured(1);
        song.midPath = midiDir + song.label + QStringLiteral(".mid");
        song.hasMid = QFile::exists(song.midPath);
        songs.append(std::move(song));
    }
    if (songs.isEmpty())
        return false;

    QHash<QString, QStringList> flagsByLabel;
    QFile cfg(midiDir + QStringLiteral("midi.cfg"));
    if (cfg.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream lines(&cfg);
        while (!lines.atEnd()) {
            QString line = lines.readLine().trimmed();
            const int hash = line.indexOf(QLatin1Char('#'));
            if (hash >= 0)
                line = line.left(hash).trimmed();
            const int colon = line.indexOf(QLatin1Char(':'));
            if (colon <= 0)
                continue;
            QString name = line.left(colon).trimmed();
            if (name.endsWith(QStringLiteral(".mid"), Qt::CaseInsensitive))
                name.chop(4);
            flagsByLabel.insert(name,
                                line.mid(colon + 1).split(QLatin1Char(' '), Qt::SkipEmptyParts));
        }
    } else {
        QFile mk(root + QStringLiteral("/songs.mk"));
        if (mk.open(QIODevice::ReadOnly | QIODevice::Text)) {
            static const QRegularExpression variablePattern(
                QStringLiteral(R"(^([A-Za-z_][A-Za-z0-9_]*)\s*[:?+]?=\s*(.*)$)"));
            static const QRegularExpression rulePattern(
                QStringLiteral(R"(^(?:\$\(MID_SUBDIR\)|sound/songs/midi)/(\w+)\.s\s*:)"));
            static const QRegularExpression whitespace(QStringLiteral("\\s+"));
            QHash<QString, QString> variables;
            QString pendingLabel;
            QTextStream lines(&mk);
            while (!lines.atEnd()) {
                const QString line = lines.readLine();
                if (line.startsWith(QLatin1Char('\t'))) {
                    if (!pendingLabel.isEmpty() && line.contains(QStringLiteral("$(MID)"))) {
                        QStringList flags;
                        for (const QString &token :
                             line.trimmed().split(whitespace, Qt::SkipEmptyParts)) {
                            if (token.startsWith(QLatin1Char('-')))
                                flags << expandVariables(token, variables);
                        }
                        flagsByLabel.insert(pendingLabel, std::move(flags));
                        pendingLabel.clear();
                    }
                    continue;
                }
                const auto rule = rulePattern.match(line);
                if (rule.hasMatch()) {
                    pendingLabel = rule.captured(1);
                    continue;
                }
                pendingLabel.clear();
                QString text = line;
                const int hash = text.indexOf(QLatin1Char('#'));
                if (hash >= 0)
                    text = text.left(hash);
                const auto assignment = variablePattern.match(text);
                if (assignment.hasMatch())
                    variables.insert(assignment.captured(1), assignment.captured(2).trimmed());
            }
        }
    }
    for (SongInfo &song : songs)
        song.cfg.rawFlags = flagsByLabel.value(song.label);
    return true;
}

const SongInfo *songWithLabel(const QList<SongInfo> &songs, const QString &label)
{
    for (const SongInfo &song : songs) {
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

    QList<SongInfo> songs;
    if (!readSongTable(fixtureRoot, songs)) {
        result.projectOpenFailed = 1;
        return result;
    }

    for (size_t index = 0; index < kRoundtripSongs.size(); ++index) {
        const uint32_t bit = uint32_t{1} << index;
        const QString label = QString::fromUtf8(kRoundtripSongs[index]);
        const SongInfo *song = songWithLabel(songs, label);
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

    QList<SongInfo> songs;
    if (!readSongTable(QFile::decodeName(projectRoot), songs))
        return 0;
    const SongInfo *song = songWithLabel(songs, QFile::decodeName(songLabel));
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
