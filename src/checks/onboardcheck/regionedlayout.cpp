#include <algorithm>

#include <QFile>

#include "context.h"

namespace OnboardCheck {

void runRegionedLayoutChecks(Context &context)
{
    const QString &projectRoot = context.projectRoot;
    const QString tablePath = projectRoot + QStringLiteral("/sound/song_table.inc");
    const QString songsHPath = projectRoot + QStringLiteral("/include/constants/songs.h");
    const QString ldPath = projectRoot + QStringLiteral("/ld_script.ld");
    const QString charmapPath = projectRoot + QStringLiteral("/charmap.txt");
    QString error;
    QString regError;
    int songId = -1;
    // ---- Regioned songs.h layouts (END_SE / START_MUS / END_MUS) ------------
    // Marker-bounded songs.h layouts size ID-indexed arrays from their
    // markers — pre-#9713 checkouts alias the last constant and size
    // src/debug.c's sound-tester arrays (sBGMNames[END_MUS - START_MUS +
    // 1]), the night-music line re-added value-form markers sizing
    // overworld.c's sNightMusicTable — so a song appended past the phoneme
    // block breaks the build or falls outside the feature. On any layout
    // whose END_MUS resolves, registration must insert music at END_MUS + 1
    // (the phoneme block shifts up by one in songs.h and charmap.txt), fill
    // the placeholder gap after END_SE for sound effects, keep each marker
    // on its region's last song — through deletion and free-slot reuse too
    // — and migrate a stranded registration back into the region.
    {
        const QString debugCPath = projectRoot + QStringLiteral("/src/debug.c");
        const QByteArray table0 = readAllBytes(tablePath);
        const QByteArray songsH0 = readAllBytes(songsHPath);
        const QByteArray ld0 = readAllBytes(ldPath);
        const QByteArray charmap0 = readAllBytes(charmapPath);
        const QByteArray debug0 = readAllBytes(debugCPath);

        const auto writeFixture = [&](const QString &path, const QByteArray &bytes) {
            QFile out(path);
            check(out.open(QIODevice::WriteOnly | QIODevice::Truncate) &&
                      out.write(bytes) == bytes.size(),
                  "regioned: fixture write failed");
        };
        // "#define NAME<pad to column 28>VALUE" — the fixture's shared value
        // column, so planned lines pad identically.
        const auto defLine = [](const char *name, const char *value) {
            QByteArray t("#define ");
            t += name;
            t += QByteArray(std::max<qsizetype>(1, 28 - t.size()), ' ');
            return t + value + "\n";
        };
        const auto dbgEntry = [](const char *text, bool continued) {
            QByteArray line(text);
            if (continued)
                line += QByteArray(36 - line.size(), ' ') + "\\";
            return line + "\n";
        };
        const auto songLine = [](const char *lab, const char *player, int n) {
            return QByteArray("\tsong ") + lab + ", " + player + ", " + QByteArray::number(n) +
                   "\n";
        };

        const QByteArray tableHead = QByteArrayLiteral(
            "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n");
        const QByteArray tableFix = tableHead +                                            // index:
                                    songLine("mus_dummy", "MUSIC_PLAYER_BGM", 0) +         // 0
                                    songLine("se_use_item", "MUSIC_PLAYER_SE1", 1) +       // 1
                                    songLine("se_last", "MUSIC_PLAYER_SE1", 1) +           // 2
                                    songLine("dummy_song_header", "MUSIC_PLAYER_BGM", 0) + // 3
                                    songLine("dummy_song_header", "MUSIC_PLAYER_BGM", 0) + // 4
                                    songLine("mus_first", "MUSIC_PLAYER_BGM", 0) +         // 5
                                    songLine("mus_last", "MUSIC_PLAYER_BGM", 0) +          // 6
                                    songLine("ph_one", "MUSIC_PLAYER_SE1", 1) +            // 7
                                    songLine("ph_two", "MUSIC_PLAYER_SE1", 1);             // 8
        const QByteArray songsHFix =
            defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") + defLine("SE_LAST", "2") +
            defLine("END_SE", "SE_LAST") + defLine("START_MUS", "5") + defLine("MUS_FIRST", "5") +
            defLine("MUS_LAST", "6") + defLine("END_MUS", "MUS_LAST") + defLine("PH_ONE", "7") +
            defLine("PH_TWO", "8") + defLine("MUS_NONE", "0xFFFF");
        const QByteArray charmapFix = QByteArrayLiteral(
            "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nMUS_FIRST = 05 00\n"
            "MUS_LAST = 06 00\nPH_ONE = 07 00\nPH_TWO = 08 00\n");
        const QByteArray debugMarkerLine =
            QByteArrayLiteral("static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n");
        const QByteArray debugListsFix =
            dbgEntry("#define SOUND_LIST_BGM", true) + dbgEntry("    X(MUS_FIRST)", true) +
            dbgEntry("    X(MUS_LAST)", false) + "\n" + dbgEntry("#define SOUND_LIST_SE", true) +
            dbgEntry("    X(SE_USE_ITEM)", true) + dbgEntry("    X(SE_LAST)", false);

        writeFixture(tablePath, tableFix);
        writeFixture(songsHPath, songsHFix);
        writeFixture(charmapPath, charmapFix);

        // True modern (post-#9713) has no markers at all — placement
        // appends, exactly as before.
        const QByteArray songsHNoMarkers = defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") +
                                           defLine("SE_LAST", "2") + defLine("MUS_FIRST", "5") +
                                           defLine("MUS_LAST", "6") + defLine("PH_ONE", "7") +
                                           defLine("PH_TWO", "8") + defLine("MUS_NONE", "0xFFFF");
        writeFixture(songsHPath, songsHNoMarkers);
        writeFixture(debugCPath, debugListsFix);
        check(SongRegistry::makePlan(projectRoot, QStringLiteral("mus_oldcheck"),
                                     QStringLiteral("MUS_OLDCHECK"),
                                     QStringLiteral("MUSIC_PLAYER_BGM"))
                      .songId == 9,
              "regioned: markerless modern layout no longer appends");

        // Value-form markers (the night-music line: "#define END_MUS 558"
        // sizing overworld.c's sNightMusicTable) get regioned placement
        // even though debug.c never consumes them — the marker itself
        // renumbers, and with the modern single ID-indexed debug array the
        // SE_-prefix list routing stays cosmetic-and-by-name.
        const QByteArray songsHVal = defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") +
                                     defLine("SE_LAST", "2") + defLine("START_MUS", "5") +
                                     defLine("MUS_FIRST", "5") + defLine("MUS_LAST", "6") +
                                     defLine("END_MUS", "6") + defLine("PH_ONE", "7") +
                                     defLine("PH_TWO", "8") + defLine("MUS_NONE", "0xFFFF");
        writeFixture(songsHPath, songsHVal);
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("mus_valcheck"),
                                         QStringLiteral("MUS_VALCHECK"),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId) &&
                  songId == 7,
              "regioned: value-form markers did not place at END_MUS + 1");
        const QByteArray songsHValAfter =
            defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") + defLine("SE_LAST", "2") +
            defLine("START_MUS", "5") + defLine("MUS_FIRST", "5") + defLine("MUS_LAST", "6") +
            defLine("MUS_VALCHECK", "7") + defLine("END_MUS", "7") + defLine("PH_ONE", "8") +
            defLine("PH_TWO", "9") + defLine("MUS_NONE", "0xFFFF");
        check(readAllBytes(songsHPath) == songsHValAfter,
              "regioned: value-form END_MUS not renumbered with the insert");
        // No END_SE marker, but the placeholder gap survives: the SE
        // boundary derives from the highest define below START_MUS, so the
        // sound effect fills the gap instead of grouping with the music —
        // and END_MUS never comes to rest on an SE.
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("se_valcheck"),
                                         QStringLiteral("SE_VALCHECK"),
                                         QStringLiteral("MUSIC_PLAYER_SE1"), &regError, &songId) &&
                  songId == 3,
              "regioned: markerless SE region not derived from START_MUS");
        const QByteArray songsHValSe =
            defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") + defLine("SE_LAST", "2") +
            defLine("SE_VALCHECK", "3") + defLine("START_MUS", "5") + defLine("MUS_FIRST", "5") +
            defLine("MUS_LAST", "6") + defLine("MUS_VALCHECK", "7") + defLine("END_MUS", "7") +
            defLine("PH_ONE", "8") + defLine("PH_TWO", "9") + defLine("MUS_NONE", "0xFFFF");
        check(readAllBytes(songsHPath) == songsHValSe,
              "regioned: derived-gap SE define misplaced or END_MUS disturbed");
        check(readAllBytes(tablePath).contains("\tsong se_valcheck, MUSIC_PLAYER_SE1, 1\n"
                                               "\tsong dummy_song_header"),
              "regioned: derived-gap SE did not overwrite the placeholder row");
        check(readAllBytes(debugCPath).indexOf("X(SE_VALCHECK)") >
                  readAllBytes(debugCPath).indexOf("#define SOUND_LIST_SE"),
              "regioned: single-array debug.c lost the by-name SE list routing");
        // Deleting the value-form marker's own song renumbers it down.
        check(SongRegistry::unregisterSong(projectRoot, QStringLiteral("mus_valcheck"),
                                           QStringLiteral("MUS_VALCHECK"), &error) &&
                  readAllBytes(songsHPath).contains(defLine("END_MUS", "6")) &&
                  !readAllBytes(songsHPath).contains("MUS_VALCHECK"),
              "regioned: value-form END_MUS not renumbered down on delete");

        // The pre-#9713 alias layout proper: debug.c sizes an array from
        // END_MUS, so the BGM/SE list split is functional. Fresh fixtures —
        // the value-form scenario above mutated them.
        writeFixture(tablePath, tableFix);
        writeFixture(songsHPath, songsHFix);
        writeFixture(charmapPath, charmapFix);
        writeFixture(debugCPath, debugMarkerLine + debugListsFix);

        // Music inserts at END_MUS + 1: the phoneme rows shift down the
        // table, their defines and charmap values shift up by one, and
        // END_MUS follows the new constant.
        RegistrationPlan rp = SongRegistry::makePlan(projectRoot, QStringLiteral("mus_oldcheck"),
                                                     QStringLiteral("MUS_OLDCHECK"),
                                                     QStringLiteral("MUSIC_PLAYER_BGM"));
        check(rp.songId == 7, "regioned: music not proposed at END_MUS + 1");
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("mus_oldcheck"),
                                         QStringLiteral("MUS_OLDCHECK"),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId) &&
                  songId == 7,
              "regioned: music registerSong failed");
        const QByteArray tableMus = tableHead + songLine("mus_dummy", "MUSIC_PLAYER_BGM", 0) +
                                    songLine("se_use_item", "MUSIC_PLAYER_SE1", 1) +
                                    songLine("se_last", "MUSIC_PLAYER_SE1", 1) +
                                    songLine("dummy_song_header", "MUSIC_PLAYER_BGM", 0) +
                                    songLine("dummy_song_header", "MUSIC_PLAYER_BGM", 0) +
                                    songLine("mus_first", "MUSIC_PLAYER_BGM", 0) +
                                    songLine("mus_last", "MUSIC_PLAYER_BGM", 0) +
                                    songLine("mus_oldcheck", "MUSIC_PLAYER_BGM", 0) + // 7
                                    songLine("ph_one", "MUSIC_PLAYER_SE1", 1) +       // 8
                                    songLine("ph_two", "MUSIC_PLAYER_SE1", 1);        // 9
        check(readAllBytes(tablePath) == tableMus,
              "regioned: music row not inserted ahead of the phoneme block");
        const QByteArray songsHMus = defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") +
                                     defLine("SE_LAST", "2") + defLine("END_SE", "SE_LAST") +
                                     defLine("START_MUS", "5") + defLine("MUS_FIRST", "5") +
                                     defLine("MUS_LAST", "6") + defLine("MUS_OLDCHECK", "7") +
                                     defLine("END_MUS", "MUS_OLDCHECK") + defLine("PH_ONE", "8") +
                                     defLine("PH_TWO", "9") + defLine("MUS_NONE", "0xFFFF");
        check(readAllBytes(songsHPath) == songsHMus,
              "regioned: define/END_MUS/phoneme renumbering wrong in songs.h");
        const QByteArray charmapMus = QByteArrayLiteral(
            "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nMUS_FIRST = 05 00\n"
            "MUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nPH_ONE = 08 00\nPH_TWO = 09 00\n");
        check(readAllBytes(charmapPath) == charmapMus,
              "regioned: charmap values did not shift with the phonemes");
        const QByteArray debugMus =
            debugMarkerLine + dbgEntry("#define SOUND_LIST_BGM", true) +
            dbgEntry("    X(MUS_FIRST)", true) + dbgEntry("    X(MUS_LAST)", true) +
            dbgEntry("    X(MUS_OLDCHECK)", false) + "\n" +
            dbgEntry("#define SOUND_LIST_SE", true) + dbgEntry("    X(SE_USE_ITEM)", true) +
            dbgEntry("    X(SE_LAST)", false);
        check(readAllBytes(debugCPath) == debugMus,
              "regioned: music debug entry not appended to SOUND_LIST_BGM");
        if (rp.ldApplicable)
            check(readAllBytes(ldPath).contains("sound/songs/midi/mus_oldcheck.o"),
                  "regioned: ld_script.ld missing the song's object line");
        check(SongRegistry::checkRegistration(projectRoot, QStringLiteral("mus_oldcheck"),
                                              QStringLiteral("MUS_OLDCHECK"))
                  .complete(),
              "regioned: music registration incomplete");

        // Idempotency: registering again is a byte-level no-op.
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("mus_oldcheck"),
                                         QStringLiteral("MUS_OLDCHECK"),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId) &&
                  songId == 7 && readAllBytes(tablePath) == tableMus &&
                  readAllBytes(songsHPath) == songsHMus &&
                  readAllBytes(charmapPath) == charmapMus && readAllBytes(debugCPath) == debugMus,
              "regioned: re-register was not byte-identical");

        // A sound effect fills the placeholder gap after END_SE in place —
        // nothing shifts — and END_SE follows it.
        rp = SongRegistry::makePlan(projectRoot, QStringLiteral("se_oldcheck"),
                                    QStringLiteral("SE_OLDCHECK"),
                                    QStringLiteral("MUSIC_PLAYER_SE1"));
        check(rp.songId == 3, "regioned: SE not proposed at the placeholder slot");
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("se_oldcheck"),
                                         QStringLiteral("SE_OLDCHECK"),
                                         QStringLiteral("MUSIC_PLAYER_SE1"), &regError, &songId) &&
                  songId == 3,
              "regioned: SE registerSong failed");
        const QByteArray tableSe = tableHead + songLine("mus_dummy", "MUSIC_PLAYER_BGM", 0) +
                                   songLine("se_use_item", "MUSIC_PLAYER_SE1", 1) +
                                   songLine("se_last", "MUSIC_PLAYER_SE1", 1) +
                                   songLine("se_oldcheck", "MUSIC_PLAYER_SE1", 1) + // 3
                                   songLine("dummy_song_header", "MUSIC_PLAYER_BGM", 0) +
                                   songLine("mus_first", "MUSIC_PLAYER_BGM", 0) +
                                   songLine("mus_last", "MUSIC_PLAYER_BGM", 0) +
                                   songLine("mus_oldcheck", "MUSIC_PLAYER_BGM", 0) +
                                   songLine("ph_one", "MUSIC_PLAYER_SE1", 1) +
                                   songLine("ph_two", "MUSIC_PLAYER_SE1", 1);
        check(readAllBytes(tablePath) == tableSe,
              "regioned: SE did not overwrite the placeholder row");
        const QByteArray songsHSe =
            defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") + defLine("SE_LAST", "2") +
            defLine("SE_OLDCHECK", "3") + defLine("END_SE", "SE_OLDCHECK") +
            defLine("START_MUS", "5") + defLine("MUS_FIRST", "5") + defLine("MUS_LAST", "6") +
            defLine("MUS_OLDCHECK", "7") + defLine("END_MUS", "MUS_OLDCHECK") +
            defLine("PH_ONE", "8") + defLine("PH_TWO", "9") + defLine("MUS_NONE", "0xFFFF");
        check(readAllBytes(songsHPath) == songsHSe,
              "regioned: SE define/END_SE placement wrong in songs.h");
        const QByteArray charmapSe = QByteArrayLiteral(
            "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\n"
            "MUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nPH_ONE = 08 00\n"
            "PH_TWO = 09 00\n");
        check(readAllBytes(charmapPath) == charmapSe,
              "regioned: SE charmap entry not at its ID position");
        const QByteArray debugSe =
            debugMarkerLine + dbgEntry("#define SOUND_LIST_BGM", true) +
            dbgEntry("    X(MUS_FIRST)", true) + dbgEntry("    X(MUS_LAST)", true) +
            dbgEntry("    X(MUS_OLDCHECK)", false) + "\n" +
            dbgEntry("#define SOUND_LIST_SE", true) + dbgEntry("    X(SE_USE_ITEM)", true) +
            dbgEntry("    X(SE_LAST)", true) + dbgEntry("    X(SE_OLDCHECK)", false);
        check(readAllBytes(debugCPath) == debugSe,
              "regioned: SE debug entry not appended to SOUND_LIST_SE");

        // A registration stranded past the phonemes (an earlier porydaw
        // appended it there) is flagged and migrates into the region on
        // re-register: row, define, and charmap entry move to END_MUS + 1,
        // the phonemes shift again, and the debug entry stays put.
        writeFixture(tablePath, tableSe + songLine("mus_straggler", "MUSIC_PLAYER_BGM", 0));
        QByteArray songsHBroken = songsHSe;
        songsHBroken.replace(defLine("PH_TWO", "9"),
                             defLine("PH_TWO", "9") + defLine("MUS_STRAGGLER", "10"));
        writeFixture(songsHPath, songsHBroken);
        writeFixture(charmapPath, charmapSe + QByteArrayLiteral("MUS_STRAGGLER = 0A 00\n"));
        QByteArray debugBroken = debugSe;
        debugBroken.replace(dbgEntry("    X(MUS_OLDCHECK)", false),
                            dbgEntry("    X(MUS_OLDCHECK)", true) +
                                dbgEntry("    X(MUS_STRAGGLER)", false));
        writeFixture(debugCPath, debugBroken);

        check(!SongRegistry::checkRegistration(projectRoot, QStringLiteral("mus_straggler"),
                                               QStringLiteral("MUS_STRAGGLER"))
                   .inSongsH,
              "regioned: stranded registration not flagged");
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("mus_straggler"),
                                         QStringLiteral("MUS_STRAGGLER"),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId) &&
                  songId == 8,
              "regioned: stranded registerSong did not migrate");
        const QByteArray tableMigrated = tableHead + songLine("mus_dummy", "MUSIC_PLAYER_BGM", 0) +
                                         songLine("se_use_item", "MUSIC_PLAYER_SE1", 1) +
                                         songLine("se_last", "MUSIC_PLAYER_SE1", 1) +
                                         songLine("se_oldcheck", "MUSIC_PLAYER_SE1", 1) +
                                         songLine("dummy_song_header", "MUSIC_PLAYER_BGM", 0) +
                                         songLine("mus_first", "MUSIC_PLAYER_BGM", 0) +
                                         songLine("mus_last", "MUSIC_PLAYER_BGM", 0) +
                                         songLine("mus_oldcheck", "MUSIC_PLAYER_BGM", 0) +
                                         songLine("mus_straggler", "MUSIC_PLAYER_BGM", 0) + // 8
                                         songLine("ph_one", "MUSIC_PLAYER_SE1", 1) +        // 9
                                         songLine("ph_two", "MUSIC_PLAYER_SE1", 1);         // 10
        check(readAllBytes(tablePath) == tableMigrated,
              "regioned: stranded row not moved ahead of the phonemes");
        const QByteArray songsHMigrated =
            defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") + defLine("SE_LAST", "2") +
            defLine("SE_OLDCHECK", "3") + defLine("END_SE", "SE_OLDCHECK") +
            defLine("START_MUS", "5") + defLine("MUS_FIRST", "5") + defLine("MUS_LAST", "6") +
            defLine("MUS_OLDCHECK", "7") + defLine("MUS_STRAGGLER", "8") +
            defLine("END_MUS", "MUS_STRAGGLER") + defLine("PH_ONE", "9") + defLine("PH_TWO", "10") +
            defLine("MUS_NONE", "0xFFFF");
        check(readAllBytes(songsHPath) == songsHMigrated,
              "regioned: stranded define not moved to its ID position");
        const QByteArray charmapMigrated = QByteArrayLiteral(
            "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\n"
            "MUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nMUS_STRAGGLER = 08 00\n"
            "PH_ONE = 09 00\nPH_TWO = 0A 00\n");
        check(readAllBytes(charmapPath) == charmapMigrated,
              "regioned: stranded charmap entry not migrated");
        check(readAllBytes(debugCPath) == debugBroken,
              "regioned: migration should leave the debug entry untouched");
        check(SongRegistry::checkRegistration(projectRoot, QStringLiteral("mus_straggler"),
                                              QStringLiteral("MUS_STRAGGLER"))
                  .complete(),
              "regioned: migrated registration incomplete");

        // Deleting the marker's referent re-points END_MUS to the region's
        // new last song; the freed slot is later reused and the marker
        // follows again.
        check(SongRegistry::unregisterSong(projectRoot, QStringLiteral("mus_straggler"),
                                           QStringLiteral("MUS_STRAGGLER"), &error),
              "regioned: unregisterSong failed");
        const QByteArray songsHDeleted =
            defLine("MUS_DUMMY", "0") + defLine("SE_USE_ITEM", "1") + defLine("SE_LAST", "2") +
            defLine("SE_OLDCHECK", "3") + defLine("END_SE", "SE_OLDCHECK") +
            defLine("START_MUS", "5") + defLine("MUS_FIRST", "5") + defLine("MUS_LAST", "6") +
            defLine("MUS_OLDCHECK", "7") + defLine("END_MUS", "MUS_OLDCHECK") +
            defLine("PH_ONE", "9") + defLine("PH_TWO", "10") + defLine("MUS_NONE", "0xFFFF");
        check(readAllBytes(songsHPath) == songsHDeleted,
              "regioned: END_MUS not re-pointed after deleting its referent");
        const QByteArray tableFreed =
            tableMigrated.left(tableMigrated.indexOf("\tsong mus_straggler")) +
            songLine("mus_dummy", "MUSIC_PLAYER_BGM", 0) +
            songLine("ph_one", "MUSIC_PLAYER_SE1", 1) + songLine("ph_two", "MUSIC_PLAYER_SE1", 1);
        check(readAllBytes(tablePath) == tableFreed,
              "regioned: deleted mid-region row did not become a free slot");
        rp = SongRegistry::makePlan(projectRoot, QStringLiteral("mus_refill"),
                                    QStringLiteral("MUS_REFILL"),
                                    QStringLiteral("MUSIC_PLAYER_BGM"));
        check(rp.songId == 8, "regioned: freed in-region slot not proposed for reuse");
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("mus_refill"),
                                         QStringLiteral("MUS_REFILL"),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId) &&
                  songId == 8,
              "regioned: freed slot not reused");
        check(readAllBytes(songsHPath)
                  .contains(defLine("MUS_REFILL", "8") + defLine("END_MUS", "MUS_REFILL")),
              "regioned: END_MUS does not follow the slot-reusing song");

        // With the placeholder gap exhausted, a sound effect overflows into
        // the music region — and its debug entry must land in
        // SOUND_LIST_BGM, whose array is the one its ID indexes.
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("se_extra"),
                                         QStringLiteral("SE_EXTRA"),
                                         QStringLiteral("MUSIC_PLAYER_SE1"), &regError, &songId) &&
                  songId == 4,
              "regioned: second SE did not take the last placeholder");
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("se_over"),
                                         QStringLiteral("SE_OVER"),
                                         QStringLiteral("MUSIC_PLAYER_SE1"), &regError, &songId) &&
                  songId == 9,
              "regioned: overflow SE not placed at END_MUS + 1");
        const QByteArray debugAfter = readAllBytes(debugCPath);
        const qsizetype seListAt = debugAfter.indexOf("#define SOUND_LIST_SE");
        const qsizetype overAt = debugAfter.indexOf("X(SE_OVER)");
        check(overAt >= 0 && seListAt >= 0 && overAt < seListAt,
              "regioned: overflow SE's debug entry not routed to SOUND_LIST_BGM");
        check(readAllBytes(songsHPath).contains(defLine("END_MUS", "SE_OVER")),
              "regioned: END_MUS does not follow the overflow SE");

        // Restore the scratch project.
        writeFixture(tablePath, table0);
        writeFixture(songsHPath, songsH0);
        writeFixture(ldPath, ld0);
        writeFixture(charmapPath, charmap0);
        if (debug0.isEmpty())
            check(QFile::remove(debugCPath), "regioned: remove src/debug.c fixture");
        else
            writeFixture(debugCPath, debug0);
    }
}

} // namespace OnboardCheck
