#include "songregistry.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <QTextStream>
#include <algorithm>

#include "core/smf.h"
#include "project/sidecar.h"
#include "project/songsmk.h"
#include "project/voicegroupsource.h"

namespace {

QStringList readLines(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QStringList lines;
    QTextStream in(&file);
    while (!in.atEnd())
        lines.append(in.readLine());
    return lines;
}

// "	song mus_dummy, MUSIC_PLAYER_BGM, 0"
const QRegularExpression &songLineRe()
{
    static const QRegularExpression re(
        QStringLiteral(R"(^(\s*)song\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+))"));
    return re;
}

// One pass over song_table.inc's lines, everything the planners and the
// delete path need. A free slot is an entry past index 0 bearing entry 0's
// label: entry 0 is the engine's fallback song (mus_dummy), so a later
// duplicate of it is a placeholder by construction — deletion leaves
// exactly that, and hand-written dummy placeholders count too. Free slots
// keep their index (that is their whole point) but never record a label
// occurrence, so the fallback song's own table index stays 0.
struct SongTableScan {
    int count = 0;         // song entries, free slots included
    int labelIndex = -1;   // the label's index (last non-free occurrence)
    int labelLine = -1;
    QString labelIndent;
    int freeIndex = -1;    // lowest free slot
    int freeLine = -1;
    int lastSongLine = -1;
    QString lastSongLabel; // the final entry's label
    QString indent;        // the last entry's indentation
    // Entry 0's pieces — the template for the free-slot line a deletion
    // leaves behind.
    QString firstLabel, firstPlayer, firstPlayerNum;
};

SongTableScan scanSongTable(const QStringList &lines, const QString &label)
{
    SongTableScan scan;
    for (int i = 0; i < lines.size(); i++) {
        const QRegularExpressionMatch m = songLineRe().match(lines.at(i));
        if (!m.hasMatch())
            continue;
        if (scan.count == 0) {
            scan.firstLabel = m.captured(2);
            scan.firstPlayer = m.captured(3);
            scan.firstPlayerNum = m.captured(4);
        }
        if (scan.count > 0 && m.captured(2) == scan.firstLabel) {
            if (scan.freeLine < 0) {
                scan.freeIndex = scan.count;
                scan.freeLine = i;
            }
        } else if (m.captured(2) == label) {
            scan.labelIndex = scan.count;
            scan.labelLine = i;
            scan.labelIndent = m.captured(1);
        }
        scan.indent = m.captured(1);
        scan.lastSongLine = i;
        scan.lastSongLabel = m.captured(2);
        scan.count++;
    }
    return scan;
}

// "MUS_DUMMY = 00 00" — a charmap.txt entry whose value is two hex bytes.
// Only entries named by a songs.h constant are treated as song-ID mappings;
// other two-byte entries ("PKMN = 53 54", the FD placeholders) are not.
const QRegularExpression &charmapEntryRe()
{
    static const QRegularExpression re(
        QStringLiteral(R"(^(\w+)( *)= *([0-9A-Fa-f]{2}) ([0-9A-Fa-f]{2})\s*$)"));
    return re;
}

// Numeric #define names from songs.h. charmap.txt's sound section mirrors
// these constants (text control codes address songs by ID), which is what
// lets porydaw recognize that section without any marker in the file.
QSet<QString> songsHConstantNames(const QString &projectRoot)
{
    static const QRegularExpression defineRe(
        QStringLiteral(R"(^\s*#define\s+(\w+)\s+\d)"));
    QSet<QString> names;
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/include/constants/songs.h"))) {
        const QRegularExpressionMatch m = defineRe.match(line);
        if (m.hasMatch())
            names.insert(m.captured(1));
    }
    return names;
}

// A song ID as charmap.txt value bytes: little-endian, uppercase hex.
QString charmapIdBytes(int songId)
{
    return QStringLiteral("%1 %2")
        .arg(songId & 0xFF, 2, 16, QLatin1Char('0'))
        .arg((songId >> 8) & 0xFF, 2, 16, QLatin1Char('0'))
        .toUpper();
}

QString sidecarPath(const QString &projectRoot, const QString &label)
{
    return projectRoot + QStringLiteral("/.porydaw/") + label + QStringLiteral(".json");
}

// Raw-byte line model for the registration files, so an edit touches only
// the song's own line: every other line keeps its exact bytes (including
// any CR — these files are normally LF, but a CRLF checkout stays CRLF).
struct RawLines {
    QList<QByteArray> lines;
    bool endsWithNewline = true;
    bool crlf = false;
    bool loaded = false;
    bool dirty = false;

    QString text(int i) const
    {
        const QByteArray &line = lines.at(i);
        return QString::fromUtf8(line.endsWith('\r') ? line.chopped(1) : line);
    }
    void insert(int at, const QString &text)
    {
        QByteArray line = text.toUtf8();
        if (crlf)
            line += '\r';
        lines.insert(at, line);
        dirty = true;
    }
    void replace(int at, const QString &text)
    {
        QByteArray line = text.toUtf8();
        if (lines.at(at).endsWith('\r'))
            line += '\r';
        lines[at] = line;
        dirty = true;
    }
    void removeAt(int at)
    {
        lines.removeAt(at);
        dirty = true;
    }
    QStringList texts() const
    {
        QStringList all;
        all.reserve(lines.size());
        for (int i = 0; i < lines.size(); i++)
            all.append(text(i));
        return all;
    }
};

RawLines readRawLines(const QString &path)
{
    RawLines f;
    QFile in(path);
    if (!in.open(QIODevice::ReadOnly))
        return f;
    const QByteArray content = in.readAll();
    f.loaded = true;
    f.endsWithNewline = content.isEmpty() || content.endsWith('\n');
    f.crlf = content.contains("\r\n");
    f.lines = content.split('\n');
    if (f.endsWithNewline && !f.lines.isEmpty())
        f.lines.removeLast(); // the empty piece after the final newline
    return f;
}

bool writeRawLines(const QString &path, const RawLines &f, QString *error)
{
    if (!f.dirty)
        return true;
    QFile out(path);
    if (!out.open(QIODevice::WriteOnly)) {
        if (error)
            *error = QStringLiteral("Cannot write %1").arg(path);
        return false;
    }
    QByteArray joined = f.lines.join('\n');
    if (f.endsWithNewline)
        joined += '\n';
    out.write(joined);
    return true;
}

} // namespace

namespace SongRegistry {

QStringList voicegroupArgs(const QString &projectRoot)
{
    // The declaration regexes and file listing live with the voicegroup
    // catalog scan, which extracts all its datasets in the same read.
    return VoicegroupSource::catalogScan(projectRoot).groupArgs;
}

QString voicegroupDisplayName(const QString &arg)
{
    return arg.startsWith(QLatin1Char('_')) ? arg.mid(1) : arg;
}

QString voicegroupArgFromDisplay(const QString &text, const QStringList &knownArgs)
{
    if (text.isEmpty() || text.startsWith(QLatin1Char('_')))
        return text;
    if (!knownArgs.contains(QLatin1Char('_') + text) && knownArgs.contains(text))
        return text;
    return QLatin1Char('_') + text;
}

QVector<MusicPlayer> musicPlayers(const QString &projectRoot)
{
    // "	.equiv MUSIC_PLAYER_BGM,0"
    static const QRegularExpression equivRe(
        QStringLiteral(R"(^\s*\.equiv\s+(\w+)\s*,\s*(\d+))"));

    QVector<MusicPlayer> players;
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/sound/song_table.inc"))) {
        const QRegularExpressionMatch m = equivRe.match(line);
        if (m.hasMatch())
            players.append({m.captured(1), m.captured(2).toInt()});
    }
    if (players.isEmpty())
        players.append({QStringLiteral("MUSIC_PLAYER_BGM"), 0});

    // Track budgets from music_player_table.inc: ".equiv NUM_TRACKS_BGM, 10"
    // symbols, then the ordered music_player entries — gMPlayTable index n is
    // player number n (that is how m4aSongNumStart indexes the table).
    // "	music_player gMPlayInfo_BGM, gMPlayTrack_BGM, NUM_TRACKS_BGM, 0"
    static const QRegularExpression playerRe(
        QStringLiteral(R"(^\s*music_player\s+\w+\s*,\s*\w+\s*,\s*(\w+))"));
    QHash<QString, int> equivs;
    QVector<int> counts; // by table order
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/sound/music_player_table.inc"))) {
        const QRegularExpressionMatch eq = equivRe.match(line);
        if (eq.hasMatch()) {
            equivs.insert(eq.captured(1), eq.captured(2).toInt());
            continue;
        }
        const QRegularExpressionMatch mp = playerRe.match(line);
        if (!mp.hasMatch())
            continue;
        const QString arg = mp.captured(1);
        bool literal = false;
        int count = arg.toInt(&literal);
        if (!literal)
            count = equivs.value(arg, -1);
        // MPlayOpen clamps to MAX_MUSICPLAYER_TRACKS; a 0-track player never
        // opens at all, so 0 stays 0 (every track silent).
        counts.append(count < 0 ? -1 : std::min(count, 16));
    }
    for (MusicPlayer &p : players) {
        if (p.number >= 0 && p.number < counts.size())
            p.trackCount = counts[p.number];
    }
    return players;
}

QString constantForLabel(const QString &label)
{
    return label.toUpper();
}

RegistrationPlan makePlan(const QString &projectRoot, const QString &label,
                          const QString &constant, const QString &player)
{
    RegistrationPlan plan;
    plan.label = label;
    plan.constant = constant;
    plan.player = player;

    // song_table.inc: match the existing entries' indentation; the third
    // argument mirrors the player's .equiv number. Once the table entry
    // exists, the proposed ID is its actual index rather than the append
    // position; otherwise a free slot left by a deleted song is reused
    // before growing the table.
    const SongTableScan scan = scanSongTable(
        readLines(projectRoot + QStringLiteral("/sound/song_table.inc")), label);
    const QString indent = scan.count > 0 ? scan.indent : QStringLiteral("\t");
    plan.songId = scan.labelIndex >= 0
                      ? scan.labelIndex
                      : (scan.freeIndex >= 0 ? scan.freeIndex : scan.count);

    int playerNum = 0;
    for (const MusicPlayer &p : musicPlayers(projectRoot)) {
        if (p.name == player)
            playerNum = p.number;
    }
    plan.songTableLine =
        QStringLiteral("%1song %2, %3, %4").arg(indent, label, player).arg(playerNum);

    // songs.h: pad the constant to the file's existing value column.
    static const QRegularExpression defineRe(
        QStringLiteral(R"(^#define\s+([A-Z0-9_]+)(\s+)\d)"));
    int valueColumn = 0;
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/include/constants/songs.h"))) {
        const QRegularExpressionMatch m = defineRe.match(line);
        if (m.hasMatch())
            valueColumn = m.capturedEnd(2);
    }
    QString define = QStringLiteral("#define ") + constant;
    const int pad = valueColumn - define.size();
    define += QString(std::max(1, pad), QLatin1Char(' '));
    plan.songsHLine = define + QString::number(plan.songId);

    // ld_script.ld: one line in the song_data section. A project whose ld
    // script never references per-song objects (modern-only forks) skips
    // this step entirely.
    const QStringList ldLines = readLines(projectRoot + QStringLiteral("/ld_script.ld"));
    QString ldIndent = QStringLiteral("        ");
    plan.ldApplicable = false;
    for (const QString &line : ldLines) {
        const int at = line.indexOf(QStringLiteral("sound/songs/midi/"));
        if (at < 0)
            continue;
        plan.ldApplicable = true;
        ldIndent = line.left(at);
    }
    if (plan.ldApplicable)
        plan.ldLine =
            QStringLiteral("%1sound/songs/midi/%2.o(.rodata);").arg(ldIndent, label);

    // charmap.txt: the sound section mirrors songs.h — each constant maps to
    // its song ID as two little-endian hex bytes, so text control codes like
    // {PLAY_BGM} can name songs. A charmap with no such entries (or no
    // charmap.txt at all) skips this file.
    const QSet<QString> songNames = songsHConstantNames(projectRoot);
    int equalsColumn = -1;
    bool columnAligned = true;
    plan.charmapApplicable = false;
    for (const QString &line : readLines(projectRoot + QStringLiteral("/charmap.txt"))) {
        const QRegularExpressionMatch m = charmapEntryRe().match(line);
        if (!m.hasMatch() || !songNames.contains(m.captured(1)))
            continue;
        plan.charmapApplicable = true;
        if (equalsColumn < 0)
            equalsColumn = m.capturedEnd(2);
        else if (m.capturedEnd(2) != equalsColumn)
            columnAligned = false;
    }
    if (plan.charmapApplicable) {
        // Vanilla emerald puts one space between name and "="; ruby and
        // firered pad "=" into a shared column. Follow the section's style.
        const int pad =
            columnAligned ? std::max(1, equalsColumn - int(constant.size())) : 1;
        plan.charmapLine = constant + QString(pad, QLatin1Char(' '))
                           + QStringLiteral("= ") + charmapIdBytes(plan.songId);
    }
    return plan;
}

bool registerSong(const QString &projectRoot, const QString &label,
                  const QString &constant, const QString &player, QString *error,
                  int *songId)
{
    const RegistrationPlan plan = makePlan(projectRoot, label, constant, player);
    if (songId)
        *songId = plan.songId;

    // song_table.inc: fill the lowest free slot left by a deleted song, or
    // insert after the last entry — either way the new entry's index is
    // exactly plan.songId (makePlan chose the ID from the same scan).
    {
        const QString path = projectRoot + QStringLiteral("/sound/song_table.inc");
        RawLines f = readRawLines(path);
        if (!f.loaded) {
            if (error)
                *error = QStringLiteral("Cannot read %1").arg(path);
            return false;
        }
        const SongTableScan scan = scanSongTable(f.texts(), label);
        if (scan.labelLine < 0) {
            if (scan.lastSongLine < 0) {
                if (error)
                    *error = QStringLiteral("%1 has no song entries").arg(path);
                return false;
            }
            if (scan.freeLine >= 0)
                f.replace(scan.freeLine, plan.songTableLine);
            else
                f.insert(scan.lastSongLine + 1, plan.songTableLine);
        }
        if (!writeRawLines(path, f, error))
            return false;
    }

    // songs.h: insert the define at its position in the file's ID order —
    // after the last define with a smaller value — or correct an existing
    // define whose value drifted from the table index. Appended songs land
    // after the last define as before (their ID exceeds every value); a song
    // reusing a freed slot lands between its ID neighbors, keeping the file
    // sorted like the charmap insertion below. Only whole decimal values
    // count as IDs: the hex sentinels after the real entries (MUS_NONE
    // 0xFFFF, PHONEME_ID_NONE 0xFF) would otherwise read as value 0 and
    // drag every insertion past them to the end of the file.
    {
        const QString path = projectRoot + QStringLiteral("/include/constants/songs.h");
        RawLines f = readRawLines(path);
        if (!f.loaded) {
            if (error)
                *error = QStringLiteral("Cannot read %1").arg(path);
            return false;
        }
        const QRegularExpression ownRe(
            QStringLiteral(R"(^(\s*#define\s+%1\s+)(\d+)(.*)$)").arg(constant));
        static const QRegularExpression anyDefineRe(
            QStringLiteral(R"(^\s*#define\s+\w+\s+(\d+)\b)"));
        static const QRegularExpression endifRe(QStringLiteral(R"(^\s*#endif\b)"));
        int own = -1, insertAfter = -1, firstDefine = -1, firstEndif = -1;
        QRegularExpressionMatch ownMatch;
        for (int i = 0; i < f.lines.size(); i++) {
            const QString text = f.text(i);
            const QRegularExpressionMatch m = ownRe.match(text);
            if (m.hasMatch() && own < 0) {
                own = i;
                ownMatch = m;
            }
            const QRegularExpressionMatch d = anyDefineRe.match(text);
            if (d.hasMatch()) {
                if (firstDefine < 0)
                    firstDefine = i;
                if (d.captured(1).toInt() < plan.songId)
                    insertAfter = i;
            }
            if (firstEndif < 0 && endifRe.match(text).hasMatch())
                firstEndif = i;
        }
        if (own >= 0) {
            if (ownMatch.captured(2).toInt() != plan.songId)
                f.replace(own, ownMatch.captured(1) + QString::number(plan.songId)
                                   + ownMatch.captured(3));
        } else if (insertAfter >= 0) {
            f.insert(insertAfter + 1, plan.songsHLine);
        } else if (firstDefine >= 0) {
            f.insert(firstDefine, plan.songsHLine);
        } else if (firstEndif >= 0) {
            f.insert(firstEndif, plan.songsHLine);
        } else {
            f.insert(f.lines.size(), plan.songsHLine);
        }
        if (!writeRawLines(path, f, error))
            return false;
    }

    // ld_script.ld: one object line after the last per-song line. Projects
    // whose linker script has no per-song lines skip this file.
    if (plan.ldApplicable) {
        const QString path = projectRoot + QStringLiteral("/ld_script.ld");
        RawLines f = readRawLines(path);
        if (!f.loaded) {
            if (error)
                *error = QStringLiteral("Cannot read %1").arg(path);
            return false;
        }
        const QString needle = QStringLiteral("sound/songs/midi/%1.o").arg(label);
        int lastObject = -1;
        bool present = false;
        for (int i = 0; i < f.lines.size(); i++) {
            const QString text = f.text(i);
            if (!text.contains(QStringLiteral("sound/songs/midi/")))
                continue;
            lastObject = i;
            if (text.contains(needle))
                present = true;
        }
        if (!present)
            f.insert(lastObject + 1, plan.ldLine);
        if (!writeRawLines(path, f, error))
            return false;
    }

    // charmap.txt: insert the ID mapping at its position in the sound
    // section's ID order (a backfilled song lands between its neighbors, not
    // appended), or correct an existing entry whose bytes drifted from the
    // table index. Projects whose charmap has no song entries skip this file.
    if (plan.charmapApplicable) {
        const QString path = projectRoot + QStringLiteral("/charmap.txt");
        RawLines f = readRawLines(path);
        if (!f.loaded) {
            if (error)
                *error = QStringLiteral("Cannot read %1").arg(path);
            return false;
        }
        // songs.h was just written, so the set includes this song's constant.
        const QSet<QString> songNames = songsHConstantNames(projectRoot);
        const QRegularExpression ownAnyRe(
            QStringLiteral(R"(^\s*%1\s*=)").arg(constant));
        int own = -1, insertAfter = -1, firstEntry = -1;
        bool ownAnyForm = false;
        QRegularExpressionMatch ownMatch;
        for (int i = 0; i < f.lines.size(); i++) {
            const QString text = f.text(i);
            // An entry in any shape (extra bytes, trailing comment) still
            // counts as present — never insert a duplicate; but only the
            // standard two-byte form is corrected.
            if (ownAnyRe.match(text).hasMatch())
                ownAnyForm = true;
            const QRegularExpressionMatch m = charmapEntryRe().match(text);
            if (!m.hasMatch() || !songNames.contains(m.captured(1)))
                continue;
            if (m.captured(1) == constant && own < 0) {
                own = i;
                ownMatch = m;
            }
            if (firstEntry < 0)
                firstEntry = i;
            const int value = m.captured(3).toInt(nullptr, 16)
                              | m.captured(4).toInt(nullptr, 16) << 8;
            if (value < plan.songId)
                insertAfter = i;
        }
        if (own >= 0) {
            const int value = ownMatch.captured(3).toInt(nullptr, 16)
                              | ownMatch.captured(4).toInt(nullptr, 16) << 8;
            if (value != plan.songId)
                f.replace(own, f.text(own).left(ownMatch.capturedStart(3))
                                   + charmapIdBytes(plan.songId));
        } else if (!ownAnyForm) {
            // After the last entry with a smaller ID; a song whose ID
            // precedes every existing entry goes before the first one.
            if (insertAfter >= 0)
                f.insert(insertAfter + 1, plan.charmapLine);
            else if (firstEntry >= 0)
                f.insert(firstEntry, plan.charmapLine);
        }
        if (!writeRawLines(path, f, error))
            return false;
    }
    return true;
}

RemovalPlan makeRemovalPlan(const QString &projectRoot, const QString &label,
                            const QString &constant)
{
    RemovalPlan plan;
    const SongTableScan scan = scanSongTable(
        readLines(projectRoot + QStringLiteral("/sound/song_table.inc")), label);
    plan.tableIndex = scan.labelIndex;
    plan.tableCount = scan.count;
    plan.lastEntry = scan.labelLine >= 0 && scan.labelLine == scan.lastSongLine;

    const QRegularExpression defineRe(
        QStringLiteral(R"(^\s*#define\s+%1\s+\d)").arg(constant));
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/include/constants/songs.h"))) {
        if (defineRe.match(line).hasMatch())
            plan.inSongsH = true;
    }
    const QString needle = QStringLiteral("sound/songs/midi/%1.o").arg(label);
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/ld_script.ld"))) {
        if (line.contains(needle))
            plan.inLdScript = true;
    }
    for (const QString &line : readLines(projectRoot + QStringLiteral("/charmap.txt"))) {
        const QRegularExpressionMatch m = charmapEntryRe().match(line);
        if (m.hasMatch() && m.captured(1) == constant)
            plan.inCharmap = true;
    }
    return plan;
}

bool unregisterSong(const QString &projectRoot, const QString &label,
                    const QString &constant, QString *error)
{
    // song_table.inc first: the index-0 refusal must precede any edit, and
    // the other files' entries are meaningless once the table entry is gone.
    {
        const QString path = projectRoot + QStringLiteral("/sound/song_table.inc");
        RawLines f = readRawLines(path);
        if (f.loaded) {
            const SongTableScan scan = scanSongTable(f.texts(), label);
            if (scan.labelIndex == 0) {
                if (error)
                    *error = QStringLiteral(
                                 "%1 is the first song_table.inc entry (song ID "
                                 "0), the engine's fallback song — it cannot be "
                                 "deleted.")
                                 .arg(label);
                return false;
            }
            if (scan.labelLine >= 0 && scan.labelLine == scan.lastSongLine) {
                f.removeAt(scan.labelLine);
                // Free slots only hold their index for the songs after them;
                // any now left trailing can go too (never entry 0 itself).
                for (;;) {
                    const SongTableScan tail = scanSongTable(f.texts(), label);
                    if (tail.count <= 1 || tail.lastSongLabel != tail.firstLabel)
                        break;
                    f.removeAt(tail.lastSongLine);
                }
            } else if (scan.labelLine >= 0) {
                // Mid-table: a free slot — a duplicate of entry 0's dummy
                // line — keeps every later song's ID and the table buildable.
                f.replace(scan.labelLine, QStringLiteral("%1song %2, %3, %4")
                                              .arg(scan.labelIndent, scan.firstLabel,
                                                   scan.firstPlayer,
                                                   scan.firstPlayerNum));
            }
            if (!writeRawLines(path, f, error))
                return false;
        }
    }

    // songs.h: drop the constant's define, whatever value it drifted to.
    {
        const QString path = projectRoot + QStringLiteral("/include/constants/songs.h");
        RawLines f = readRawLines(path);
        if (f.loaded) {
            const QRegularExpression ownRe(
                QStringLiteral(R"(^\s*#define\s+%1\s+\d)").arg(constant));
            for (int i = 0; i < f.lines.size(); i++) {
                if (ownRe.match(f.text(i)).hasMatch()) {
                    f.removeAt(i);
                    break;
                }
            }
            if (!writeRawLines(path, f, error))
                return false;
        }
    }

    // ld_script.ld: the song's object line.
    {
        const QString path = projectRoot + QStringLiteral("/ld_script.ld");
        RawLines f = readRawLines(path);
        if (f.loaded) {
            const QString needle = QStringLiteral("sound/songs/midi/%1.o").arg(label);
            for (int i = 0; i < f.lines.size(); i++) {
                if (f.text(i).contains(needle)) {
                    f.removeAt(i);
                    break;
                }
            }
            if (!writeRawLines(path, f, error))
                return false;
        }
    }

    // charmap.txt: the constant's ID mapping.
    {
        const QString path = projectRoot + QStringLiteral("/charmap.txt");
        RawLines f = readRawLines(path);
        if (f.loaded) {
            for (int i = 0; i < f.lines.size(); i++) {
                const QRegularExpressionMatch m = charmapEntryRe().match(f.text(i));
                if (m.hasMatch() && m.captured(1) == constant) {
                    f.removeAt(i);
                    break;
                }
            }
            if (!writeRawLines(path, f, error))
                return false;
        }
    }
    return true;
}

QString deletableVoicegroup(const QString &projectRoot, const QVector<SongInfo> &songs,
                            const QString &songLabel)
{
    const SongInfo *song = nullptr;
    for (const SongInfo &s : songs) {
        if (s.label == songLabel)
            song = &s;
    }
    if (!song)
        return {};
    const QString arg = song->cfg.voicegroupArg;
    if (arg.isEmpty())
        return {}; // mid2agb's default voicegroup_dummy — shared by definition
    for (const SongInfo &s : songs) {
        if (s.label != songLabel && s.cfg.voicegroupArg == arg)
            return {};
    }

    // A file of its own under sound/voicegroups/ — the only layout whose
    // deletion is one file plus one .include line.
    QString name;
    const QDir vgDir(projectRoot + QStringLiteral("/sound/voicegroups"));
    for (const QString &candidate : DecompProject::voicegroupCandidates(song->cfg)) {
        if (vgDir.exists(candidate + QStringLiteral(".inc"))) {
            name = candidate;
            break;
        }
    }
    if (name.isEmpty())
        return {};

    // Not a keysplit/drumkit sub-group of another voicegroup.
    const QString symbol = QStringLiteral("voicegroup") + arg;
    const VgCatalogScan catalog = VoicegroupSource::catalogScan(projectRoot);
    for (const auto &keysplit : catalog.keysplits) {
        if (keysplit.first == symbol)
            return {};
    }
    if (catalog.drumkits.contains(symbol))
        return {};

    // Not referenced from the project's C sources — such a reference would
    // break the link outright, not merely dangle.
    const QByteArray symbolBytes = symbol.toUtf8();
    const auto isIdentChar = [](char c) {
        return c == '_' || (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z')
               || (c >= 'a' && c <= 'z');
    };
    for (const QString &top : {QStringLiteral("/src"), QStringLiteral("/include")}) {
        QDirIterator it(projectRoot + top,
                        {QStringLiteral("*.c"), QStringLiteral("*.h")}, QDir::Files,
                        QDirIterator::Subdirectories);
        while (it.hasNext()) {
            QFile file(it.next());
            if (!file.open(QIODevice::ReadOnly))
                continue;
            const QByteArray content = file.readAll();
            for (qsizetype at = content.indexOf(symbolBytes); at >= 0;
                 at = content.indexOf(symbolBytes, at + 1)) {
                const qsizetype end = at + symbolBytes.size();
                const bool startsClean = at == 0 || !isIdentChar(content.at(at - 1));
                if (startsClean
                    && (end >= content.size() || !isIdentChar(content.at(end))))
                    return {};
            }
        }
    }
    return name;
}

RegistrationStatus checkRegistration(const QString &projectRoot, const QString &label,
                                     const QString &constant)
{
    SongInfo song;
    song.label = label;
    song.constant = constant;
    return checkRegistrations(projectRoot, {song}).value(label);
}

QHash<QString, RegistrationStatus> checkRegistrations(const QString &projectRoot,
                                                      const QVector<SongInfo> &songs)
{
    // song_table.inc: label -> index (a duplicate label's last entry wins).
    // Free slots — entries past index 0 bearing entry 0's label — occupy
    // their index but don't count as the fallback song's entry, whose own
    // index must stay 0.
    QHash<QString, int> tableIndex;
    int count = 0;
    QString firstLabel;
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/sound/song_table.inc"))) {
        const QRegularExpressionMatch m = songLineRe().match(line);
        if (!m.hasMatch())
            continue;
        if (count == 0)
            firstLabel = m.captured(2);
        if (count == 0 || m.captured(2) != firstLabel)
            tableIndex.insert(m.captured(2), count);
        count++;
    }

    // songs.h: name -> first numeric define's value.
    static const QRegularExpression defineRe(
        QStringLiteral(R"(^\s*#define\s+(\w+)\s+(\d+))"));
    QHash<QString, int> defines;
    for (const QString &line :
         readLines(projectRoot + QStringLiteral("/include/constants/songs.h"))) {
        const QRegularExpressionMatch m = defineRe.match(line);
        if (m.hasMatch() && !defines.contains(m.captured(1)))
            defines.insert(m.captured(1), m.captured(2).toInt());
    }

    // ld_script.ld: the per-song object labels.
    static const QRegularExpression ldObjectRe(
        QStringLiteral(R"(sound/songs/midi/(\w+)\.o)"));
    bool ldApplicable = false;
    QSet<QString> ldLabels;
    for (const QString &line : readLines(projectRoot + QStringLiteral("/ld_script.ld"))) {
        if (line.contains(QStringLiteral("sound/songs/midi/")))
            ldApplicable = true;
        QRegularExpressionMatchIterator it = ldObjectRe.globalMatch(line);
        while (it.hasNext())
            ldLabels.insert(it.next().captured(1));
    }

    // charmap.txt: name -> first entry's decoded value; the file is a song
    // section at all only when some entry is named by a songs.h constant.
    QHash<QString, int> charmapValues;
    bool charmapApplicable = false;
    for (const QString &line : readLines(projectRoot + QStringLiteral("/charmap.txt"))) {
        const QRegularExpressionMatch m = charmapEntryRe().match(line);
        if (!m.hasMatch())
            continue;
        if (defines.contains(m.captured(1)))
            charmapApplicable = true;
        if (!charmapValues.contains(m.captured(1)))
            charmapValues.insert(m.captured(1),
                                 m.captured(3).toInt(nullptr, 16)
                                     | m.captured(4).toInt(nullptr, 16) << 8);
    }

    QHash<QString, RegistrationStatus> statuses;
    for (const SongInfo &song : songs) {
        const QString constant =
            song.constant.isEmpty() ? constantForLabel(song.label) : song.constant;
        RegistrationStatus status;
        const int index = tableIndex.value(song.label, -1);
        status.inSongTable = index >= 0;
        // Once the table entry exists, the songs.h define and the charmap
        // entry must carry its real index.
        const auto define = defines.constFind(constant);
        if (define != defines.constEnd())
            status.inSongsH = index < 0 || define.value() == index;
        status.ldApplicable = ldApplicable;
        status.inLdScript = ldLabels.contains(song.label);
        status.charmapApplicable = charmapApplicable;
        const auto charmapValue = charmapValues.constFind(constant);
        if (charmapValue != charmapValues.constEnd())
            status.inCharmap = index < 0 || charmapValue.value() == index;
        statuses.insert(song.label, status);
    }
    return statuses;
}

QStringList mergeCfgFlags(const SongCfg &cfg)
{
    // Updates or inserts "-<letter><value>"; a null value removes the flag.
    // Matching is case-insensitive as in mid2agb's parser.
    QStringList flags = cfg.rawFlags;
    const auto setValue = [&flags](char letter, const QString &value) {
        for (int i = 0; i < flags.size(); i++) {
            if (flags[i].size() >= 2 && flags[i][0] == QLatin1Char('-')
                && flags[i][1].toUpper() == QLatin1Char(letter)) {
                if (value.isNull())
                    flags.removeAt(i);
                else
                    flags[i] = QLatin1Char('-') + QString(QLatin1Char(letter)) + value;
                return;
            }
        }
        if (!value.isNull())
            flags.append(QLatin1Char('-') + QString(QLatin1Char(letter)) + value);
    };
    const auto setBool = [&setValue](char letter, bool present) {
        setValue(letter, present ? QStringLiteral("") : QString());
    };

    setBool('E', cfg.exactGate);
    setValue('R', cfg.reverb >= 0 ? QString::number(cfg.reverb) : QString());
    setValue('G', cfg.voicegroupArg.isEmpty() ? QString() : cfg.voicegroupArg);
    setValue('V', QStringLiteral("%1").arg(cfg.masterVolume, 3, 10, QLatin1Char('0')));
    setValue('P', cfg.priority != 0 ? QString::number(cfg.priority) : QString());
    setBool('X', cfg.extendedClocks);
    setBool('N', cfg.noCompression);
    return flags;
}

bool writeMidiCfgLine(const QString &midiDir, const QString &label,
                      const QStringList &flags, QString *error)
{
    // Binary in/out: only the song's own line may change, byte for byte —
    // including CRLF line endings (vanilla midi.cfg uses them).
    const QString cfgPath = QDir(midiDir).filePath(QStringLiteral("midi.cfg"));
    QByteArray content;
    {
        QFile in(cfgPath);
        if (in.open(QIODevice::ReadOnly))
            content = in.readAll();
    }
    const bool endsWithNewline = content.isEmpty() || content.endsWith('\n');
    const bool crlf = content.contains("\r\n");
    QList<QByteArray> lines = content.split('\n');
    if (endsWithNewline && !lines.isEmpty())
        lines.removeLast(); // the empty piece after the final newline

    const QString fileName = label + QStringLiteral(".mid");
    const QByteArray flagBytes = flags.join(QLatin1Char(' ')).toUtf8();
    bool replaced = false;
    for (QByteArray &line : lines) {
        const bool hadCr = line.endsWith('\r');
        const QString text = QString::fromUtf8(hadCr ? line.chopped(1) : line);
        const int colon = text.indexOf(QLatin1Char(':'));
        if (colon <= 0 || text.left(colon).trimmed() != fileName)
            continue;
        // Keep the original name-column padding.
        int flagStart = colon + 1;
        while (flagStart < text.size() && text[flagStart] == QLatin1Char(' '))
            flagStart++;
        line = text.left(flagStart).toUtf8() + flagBytes;
        if (hadCr)
            line += '\r';
        replaced = true;
        break;
    }
    if (!replaced) {
        QByteArray line = fileName.toUtf8() + ": " + flagBytes;
        if (crlf)
            line += '\r';
        lines.append(line);
    }

    QFile out(cfgPath);
    if (!out.open(QIODevice::WriteOnly)) {
        if (error)
            *error = QStringLiteral("Cannot write %1").arg(cfgPath);
        return false;
    }
    QByteArray joined = lines.join('\n');
    if (endsWithNewline)
        joined += '\n';
    out.write(joined);
    return true;
}

bool writeSongFlags(const QString &midiDir, const QString &label,
                    const QStringList &flags, QString *error)
{
    if (!QFile::exists(QDir(midiDir).filePath(QStringLiteral("midi.cfg")))) {
        const QString mkPath =
            SongsMk::path(QDir::cleanPath(midiDir + QStringLiteral("/../../..")));
        if (QFile::exists(mkPath))
            return SongsMk::writeRule(mkPath, label, flags, error);
    }
    return writeMidiCfgLine(midiDir, label, flags, error);
}

static bool removeMidiCfgLine(const QString &midiDir, const QString &label,
                              QString *error)
{
    // The exact inverse of writeMidiCfgLine's append: the song's own line
    // vanishes, every other byte stays.
    const QString cfgPath = QDir(midiDir).filePath(QStringLiteral("midi.cfg"));
    QByteArray content;
    {
        QFile in(cfgPath);
        if (!in.open(QIODevice::ReadOnly))
            return true; // no midi.cfg — nothing stored here
        content = in.readAll();
    }
    const bool endsWithNewline = content.isEmpty() || content.endsWith('\n');
    QList<QByteArray> lines = content.split('\n');
    if (endsWithNewline && !lines.isEmpty())
        lines.removeLast(); // the empty piece after the final newline

    const QString fileName = label + QStringLiteral(".mid");
    bool removed = false;
    for (int i = 0; i < lines.size(); i++) {
        const QByteArray &line = lines.at(i);
        const QString text =
            QString::fromUtf8(line.endsWith('\r') ? line.chopped(1) : line);
        const int colon = text.indexOf(QLatin1Char(':'));
        if (colon <= 0 || text.left(colon).trimmed() != fileName)
            continue;
        lines.removeAt(i);
        removed = true;
        break;
    }
    if (!removed)
        return true;

    QFile out(cfgPath);
    if (!out.open(QIODevice::WriteOnly)) {
        if (error)
            *error = QStringLiteral("Cannot write %1").arg(cfgPath);
        return false;
    }
    QByteArray joined = lines.join('\n');
    if (endsWithNewline)
        joined += '\n';
    out.write(joined);
    return true;
}

bool removeSongFlags(const QString &midiDir, const QString &label, QString *error)
{
    if (!removeMidiCfgLine(midiDir, label, error))
        return false;
    const QString mkPath =
        SongsMk::path(QDir::cleanPath(midiDir + QStringLiteral("/../../..")));
    if (QFile::exists(mkPath))
        return SongsMk::removeRule(mkPath, label, error);
    return true;
}

void removeSongSidecar(const QString &projectRoot, const QString &label)
{
    QFile::remove(sidecarPath(projectRoot, label));
}

SmfFile blankSong()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24; // vanilla pokeemerald resolution: 1 tick per m4a clock
    const uint64_t oneBar = uint64_t(smf.division) * 4;

    SmfTrack seq; // MTrk chunk 0: the only chunk mid2agb reads seq events from
    SmfEvent tempo;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArray("\x07\xA1\x20", 3); // 500000 us/beat = 120 BPM
    seq.events.push_back(tempo);
    SmfEvent timeSig;
    timeSig.status = 0xFF;
    timeSig.metaType = 0x58;
    timeSig.blob = QByteArray("\x04\x02\x18\x08", 4); // 4/4
    seq.events.push_back(timeSig);
    seq.endTick = oneBar;
    smf.tracks.push_back(seq);

    SmfTrack track;
    SmfEvent program;
    program.status = 0xC0;
    program.data0 = 0; // voice 0
    track.events.push_back(program);
    SmfEvent volume;
    volume.status = 0xB0;
    volume.data0 = 7;
    volume.data1 = 100;
    track.events.push_back(volume);
    track.endTick = oneBar;
    smf.tracks.push_back(track);
    return smf;
}

bool saveRegistrationMeta(const QString &projectRoot, const QString &label,
                          const QString &constant, const QString &player)
{
    const QString path = sidecarPath(projectRoot, label);
    QJsonObject root;
    {
        QFile in(path);
        if (in.open(QIODevice::ReadOnly))
            root = QJsonDocument::fromJson(in.readAll()).object();
    }
    QJsonObject reg;
    reg.insert(QStringLiteral("constant"), constant);
    reg.insert(QStringLiteral("player"), player);
    root.insert(QStringLiteral("registration"), reg);

    Sidecar::ensureDir(projectRoot);
    QFile out(path);
    if (!out.open(QIODevice::WriteOnly))
        return false;
    out.write(QJsonDocument(root).toJson());
    return true;
}

bool loadRegistrationMeta(const QString &projectRoot, const QString &label,
                          QString *constant, QString *player)
{
    QFile in(sidecarPath(projectRoot, label));
    if (!in.open(QIODevice::ReadOnly))
        return false;
    const QJsonObject reg = QJsonDocument::fromJson(in.readAll())
                                .object()
                                .value(QStringLiteral("registration"))
                                .toObject();
    if (reg.isEmpty())
        return false;
    if (constant)
        *constant = reg.value(QStringLiteral("constant")).toString();
    if (player)
        *player = reg.value(QStringLiteral("player")).toString();
    return true;
}

void clearRegistrationMeta(const QString &projectRoot, const QString &label)
{
    const QString path = sidecarPath(projectRoot, label);
    QJsonObject root;
    {
        QFile in(path);
        if (!in.open(QIODevice::ReadOnly))
            return;
        root = QJsonDocument::fromJson(in.readAll()).object();
    }
    root.remove(QStringLiteral("registration"));
    if (root.isEmpty()) {
        QFile::remove(path);
        return;
    }
    QFile out(path);
    if (out.open(QIODevice::WriteOnly))
        out.write(QJsonDocument(root).toJson());
}

} // namespace SongRegistry
