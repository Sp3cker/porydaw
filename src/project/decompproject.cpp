#include "decompproject.h"

#if defined(__APPLE__)
#include <os/log.h>
#include <os/signpost.h>
#endif
#include <QDir>
#include <QFile>
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QTextStream>

#include "project/songregistry.h"
#include "project/songsmk.h"

#if defined(__APPLE__)
namespace {
os_log_t projectIndexingLog()
{
    static os_log_t log = os_log_create("com.huderlem.porydaw", "project-indexing");
    return log;
}
} // namespace
#endif

bool DecompProject::open(const QString &rootDir, QString *error)
{
#if defined(__APPLE__)
    const os_log_t indexingLog = projectIndexingLog();
    const bool signpostsEnabled = os_signpost_enabled(indexingLog);
    const os_signpost_id_t projectIndexingId =
        signpostsEnabled ? os_signpost_id_generate(indexingLog) : OS_SIGNPOST_ID_NULL;
    if (signpostsEnabled)
        os_signpost_interval_begin(indexingLog, projectIndexingId, "ProjectIndexing");
    const auto endProjectIndexing = [&] {
        if (signpostsEnabled)
            os_signpost_interval_end(indexingLog, projectIndexingId, "ProjectIndexing");
    };
#endif

    close();

    const QDir dir(rootDir);
    if (!dir.exists()) {
        if (error)
            *error = QStringLiteral("Directory does not exist: %1").arg(rootDir);
#if defined(__APPLE__)
        endProjectIndexing();
#endif
        return false;
    }
    m_root = dir.absolutePath();

#if defined(__APPLE__)
    const os_signpost_id_t songTableId =
        signpostsEnabled ? os_signpost_id_generate(indexingLog) : OS_SIGNPOST_ID_NULL;
    if (signpostsEnabled)
        os_signpost_interval_begin(indexingLog, songTableId, "SongTable");
#endif
    const QDir midiDir(m_root + QStringLiteral("/sound/songs/midi"));
    const QStringList midiFiles =
        midiDir.entryList({QStringLiteral("*.mid")}, QDir::Files, QDir::Name);
    QSet<QString> midiFileNames;
    for (const QString &fileName : midiFiles)
        midiFileNames.insert(fileName);
    if (!parseSongTable(midiDir, midiFileNames, error)) {
        m_root.clear();
#if defined(__APPLE__)
        if (signpostsEnabled)
            os_signpost_interval_end(indexingLog, songTableId, "SongTable");
        endProjectIndexing();
#endif
        return false;
    }
#if defined(__APPLE__)
    if (signpostsEnabled)
        os_signpost_interval_end(indexingLog, songTableId, "SongTable");
    const os_signpost_id_t songDiscoveryId =
        signpostsEnabled ? os_signpost_id_generate(indexingLog) : OS_SIGNPOST_ID_NULL;
    if (signpostsEnabled)
        os_signpost_interval_begin(indexingLog, songDiscoveryId, "SongDiscovery");
#endif
    parseSongConstants();
    discoverUnregisteredSongs(midiDir, midiFiles);
#if defined(__APPLE__)
    if (signpostsEnabled)
        os_signpost_interval_end(indexingLog, songDiscoveryId, "SongDiscovery");
    const os_signpost_id_t registrationCheckId =
        signpostsEnabled ? os_signpost_id_generate(indexingLog) : OS_SIGNPOST_ID_NULL;
    if (signpostsEnabled)
        os_signpost_interval_begin(indexingLog, registrationCheckId, "RegistrationCheck");
#endif
    // Which registration files still miss each song's entry — one pass over
    // the registration files for the whole project (checkRegistration per
    // song would reopen them hundreds of times).
    const QHash<QString, RegistrationStatus> statuses =
        SongRegistry::checkRegistrations(m_root, m_songs);
    for (SongInfo &song : m_songs) {
        const RegistrationStatus status = statuses.value(song.label);
        song.registrationGaps.clear();
        if (!status.inSongTable)
            song.registrationGaps.append(QStringLiteral("song_table.inc"));
        if (!status.inSongsH)
            song.registrationGaps.append(QStringLiteral("songs.h"));
        if (status.ldApplicable && !status.inLdScript)
            song.registrationGaps.append(QStringLiteral("ld_script.ld"));
        if (status.charmapApplicable && !status.inCharmap)
            song.registrationGaps.append(QStringLiteral("charmap.txt"));
        if (status.debugApplicable && !status.inDebugMenu)
            song.registrationGaps.append(QStringLiteral("src/debug.c"));
    }
#if defined(__APPLE__)
    if (signpostsEnabled)
        os_signpost_interval_end(indexingLog, registrationCheckId, "RegistrationCheck");
    const os_signpost_id_t songConfigurationId =
        signpostsEnabled ? os_signpost_id_generate(indexingLog) : OS_SIGNPOST_ID_NULL;
    if (signpostsEnabled)
        os_signpost_interval_begin(indexingLog, songConfigurationId, "SongConfiguration");
#endif
    if (!parseMidiCfg())
        parseSongsMk();
#if defined(__APPLE__)
    if (signpostsEnabled)
        os_signpost_interval_end(indexingLog, songConfigurationId, "SongConfiguration");
    const os_signpost_id_t musicPlayersId =
        signpostsEnabled ? os_signpost_id_generate(indexingLog) : OS_SIGNPOST_ID_NULL;
    if (signpostsEnabled)
        os_signpost_interval_begin(indexingLog, musicPlayersId, "MusicPlayers");
#endif
    m_players = SongRegistry::musicPlayers(m_root);
#if defined(__APPLE__)
    if (signpostsEnabled)
        os_signpost_interval_end(indexingLog, musicPlayersId, "MusicPlayers");
    endProjectIndexing();
#endif
    return true;
}

int DecompProject::trackBudgetFor(const SongInfo &song) const
{
    for (const MusicPlayer &p : m_players) {
        if (p.name == song.player)
            return p.trackCount >= 0 ? p.trackCount : 16;
    }
    return 16;
}

bool DecompProject::reload(QString *error)
{
    const QString root = m_root;
    return open(root, error);
}

void DecompProject::close()
{
    m_root.clear();
    m_songs.clear();
    m_players.clear();
}

bool DecompProject::parseSongTable(const QDir &midiDir, const QSet<QString> &midiFiles,
                                   QString *error)
{
    const QString path = m_root + QStringLiteral("/sound/song_table.inc");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (error)
            *error = QStringLiteral("Cannot open %1.\n\nIs this a pokeemerald/pokefirered/pokeruby "
                                    "project directory?")
                         .arg(path);
        return false;
    }

    // e.g. "	song mus_dummy, MUSIC_PLAYER_BGM, 0"
    static const QRegularExpression songRe(
        QStringLiteral(R"(^\s*song\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+))"));

    QTextStream in(&file);
    while (!in.atEnd()) {
        const QString line = in.readLine();
        const QRegularExpressionMatch m = songRe.match(line);
        if (!m.hasMatch())
            continue;

        SongInfo song;
        song.id = m_songs.size();
        song.label = m.captured(1);
        song.player = m.captured(2);

        const QString midiFileName = song.label + QStringLiteral(".mid");
        if (midiFiles.contains(midiFileName)) {
            song.midPath = midiDir.filePath(midiFileName);
            song.hasMid = true;
        }
        m_songs.append(song);
    }

    if (m_songs.isEmpty()) {
        if (error)
            *error = QStringLiteral("No songs found in %1").arg(path);
        return false;
    }
    return true;
}

void DecompProject::parseSongConstants()
{
    QFile file(m_root + QStringLiteral("/include/constants/songs.h"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    // e.g. "#define MUS_ABANDONED_SHIP 381"
    static const QRegularExpression defineRe(
        QStringLiteral(R"(^\s*#define\s+([A-Z0-9_]+)\s+(\d+)\s*$)"));

    QHash<int, QString> byId;
    QTextStream in(&file);
    while (!in.atEnd()) {
        const QRegularExpressionMatch m = defineRe.match(in.readLine());
        if (!m.hasMatch())
            continue;
        const int id = m.captured(2).toInt();
        // First definition wins (later defines like PH_* aliases share IDs).
        if (!byId.contains(id))
            byId.insert(id, m.captured(1));
    }

    for (SongInfo &song : m_songs) {
        const auto it = byId.constFind(song.id);
        if (it != byId.constEnd())
            song.constant = it.value();
    }
}

void DecompProject::discoverUnregisteredSongs(const QDir &midiDir, const QStringList &midiFiles)
{
    // .mid files with no song_table.inc entry: songs whose registration
    // never ran (dropped-in files) or failed. Listing them keeps the badge
    // visible across project reopens so Register Song can finish the job.
    // Identity chosen in the wizard comes back from the sidecar; the
    // constant falls back to the label-derived default.
    QSet<QString> known;
    for (const SongInfo &song : m_songs)
        known.insert(song.label);

    for (const QString &fileName : midiFiles) {
        const QString label = fileName.chopped(4);
        if (known.contains(label))
            continue;
        SongInfo song;
        song.id = m_songs.size();
        song.label = label;
        song.registered = false;
        song.midPath = midiDir.filePath(fileName);
        song.hasMid = true;
        song.constant = SongRegistry::constantForLabel(label);
        song.player = QStringLiteral("MUSIC_PLAYER_BGM");
        QString constant, player;
        if (SongRegistry::loadRegistrationMeta(m_root, label, &constant, &player)) {
            if (!constant.isEmpty())
                song.constant = constant;
            if (!player.isEmpty())
                song.player = player;
        }
        m_songs.append(song);
    }
}

// mid2agb parses option letters case-insensitively (-v080 == -V080).
static SongCfg cfgFromFlags(const QStringList &flags)
{
    SongCfg cfg;
    cfg.rawFlags = flags;
    for (const QString &flag : flags) {
        if (flag.size() < 2 || flag[0] != QLatin1Char('-'))
            continue;
        const QChar opt = flag[1].toUpper();
        const QString arg = flag.mid(2);
        switch (opt.toLatin1()) {
        case 'G':
            cfg.voicegroupArg = arg;
            break;
        case 'V':
            cfg.masterVolume = qBound(0, arg.toInt(), 127);
            break;
        case 'R':
            cfg.reverb = qBound(0, arg.toInt(), 127);
            break;
        case 'P':
            cfg.priority = arg.toInt();
            break;
        case 'E':
            cfg.exactGate = true;
            break;
        case 'X':
            cfg.extendedClocks = true;
            break;
        case 'N':
            cfg.noCompression = true;
            break;
        default:
            break; // -L and unknown flags: irrelevant for playback
        }
    }
    return cfg;
}

bool DecompProject::parseMidiCfg()
{
    QFile file(m_root + QStringLiteral("/sound/songs/midi/midi.cfg"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    // e.g. "mus_abandoned_ship.mid: -E -R50 -G_abandoned_ship -V080"
    QHash<QString, SongCfg> byLabel;
    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        const int hash = line.indexOf(QLatin1Char('#'));
        if (hash >= 0)
            line = line.left(hash).trimmed();
        const int colon = line.indexOf(QLatin1Char(':'));
        if (colon <= 0)
            continue;

        QString name = line.left(colon).trimmed();
        if (name.endsWith(QStringLiteral(".mid"), Qt::CaseInsensitive))
            name.chop(4);

        byLabel.insert(
            name, cfgFromFlags(line.mid(colon + 1).split(QLatin1Char(' '), Qt::SkipEmptyParts)));
    }

    for (SongInfo &song : m_songs) {
        const auto it = byLabel.constFind(song.label);
        if (it != byLabel.constEnd()) {
            song.hasCfg = true;
            song.cfg = it.value();
        }
    }
    return true;
}

void DecompProject::parseSongsMk()
{
    // Pre-midi.cfg projects: per-song make rules in <root>/songs.mk.
    const QHash<QString, QStringList> byLabel = SongsMk::parseFlags(SongsMk::path(m_root));
    for (SongInfo &song : m_songs) {
        const auto it = byLabel.constFind(song.label);
        if (it != byLabel.constEnd()) {
            song.hasCfg = true;
            song.cfg = cfgFromFlags(it.value());
        }
    }
}

QStringList DecompProject::voicegroupCandidates(const SongInfo &song)
{
    return voicegroupCandidates(song.cfg);
}

void DecompProject::setSongCfg(int id, const SongCfg &cfg)
{
    if (id >= 0 && id < m_songs.size()) {
        m_songs[id].cfg = cfg;
        m_songs[id].hasCfg = true;
    }
}

QStringList DecompProject::voicegroupCandidates(const SongCfg &cfg)
{
    // mid2agb's default -G argument is "_dummy" (symbol voicegroup_dummy).
    const QString arg = cfg.voicegroupArg.isEmpty() ? QStringLiteral("_dummy") : cfg.voicegroupArg;
    const QString symbol = QStringLiteral("voicegroup") + arg;

    QStringList candidates;
    if (symbol.startsWith(QStringLiteral("voicegroup_")))
        candidates << symbol.mid(11); // e.g. "abandoned_ship"
    candidates << symbol;             // e.g. "voicegroup000" (pokefirered labels)
    if (!arg.isEmpty() && !candidates.contains(arg))
        candidates << arg;
    return candidates;
}
