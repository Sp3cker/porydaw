#include <QFile>

#include "context.h"

namespace OnboardCheck {

void runDebugLayoutChecks(Context &context, const RegisteredSongFixture &fixture)
{
    const QString &projectRoot = context.projectRoot;
    const QString &label = fixture.label;
    const QString &constant = fixture.constant;
    const RegistrationPlan &plan = fixture.plan;
    DecompProject &project = context.project;
    const QString tablePath = projectRoot + QStringLiteral("/sound/song_table.inc");
    const QString songsHPath = projectRoot + QStringLiteral("/include/constants/songs.h");
    const QString ldPath = projectRoot + QStringLiteral("/ld_script.ld");
    const QString charmapPath = projectRoot + QStringLiteral("/charmap.txt");
    QString error;
    QString regError;
    int songId = -1;
    RegistrationStatus status;
    // ---- src/debug.c sound lists ---------------------------------------------
    // pokeemerald-expansion's debug menu lists every song as an X-macro entry
    // in src/debug.c's SOUND_LIST_BGM / SOUND_LIST_SE. Vanilla has no such
    // file, so the flow runs against a fixture: entries land in the
    // prefix-matching list at their ID position with the macro's '\'
    // continuations rewired at the list ends, and deletion is the exact
    // inverse.
    {
        const QString debugCPath = projectRoot + QStringLiteral("/src/debug.c");
        const QByteArray originalDebug = readAllBytes(debugCPath);
        if (originalDebug.isEmpty())
            check(!plan.debugApplicable, "src/debug.c leg not inapplicable without the file");

        // Entry lines pad their '\' into a shared column like the real file.
        const auto dbgLine = [](const char *text, bool continued) {
            QByteArray line(text);
            if (continued)
                line += QByteArray(36 - line.size(), ' ') + "\\";
            return line + "\n";
        };
        const auto writeDebug = [&](const QByteArray &bytes) {
            QFile out(debugCPath);
            check(out.open(QIODevice::WriteOnly | QIODevice::Truncate) &&
                      out.write(bytes) == bytes.size(),
                  "rewrite src/debug.c fixture");
        };
        // Vanilla songs (IDs 2, 3, 4) with ID 1 unlisted, so both a mid-list
        // and a before-first backfill have a home.
        const QByteArray fixture =
            dbgLine("#define SOUND_LIST_BGM", true) + dbgLine("    X(MUS_GSC_ROUTE38)", true) +
            dbgLine("    X(MUS_CAUGHT)", true) + dbgLine("    X(MUS_VICTORY_WILD)", false) + "\n" +
            dbgLine("#define SOUND_LIST_SE", true) + dbgLine("    X(SE_USE_ITEM)", true) +
            dbgLine("    X(SE_PC_LOGIN)", false);
        writeDebug(fixture);

        const RegistrationPlan dbgPlan = SongRegistry::makePlan(projectRoot, label, constant,
                                                                QStringLiteral("MUSIC_PLAYER_BGM"));
        check(dbgPlan.debugApplicable, "debug.c sound lists not detected");
        check(dbgPlan.debugLine.toUtf8() == dbgLine("    X(MUS_ONBOARDCHECK)", true).chopped(1),
              "debug.c entry line not padded to the '\\' column");

        status = SongRegistry::checkRegistration(projectRoot, label, constant);
        check(status.debugApplicable && !status.inDebugMenu,
              "unlisted song reads as present in the debug menu");
        check(!status.complete(), "missing debug.c entry does not gate completeness");

        // Registering the (otherwise fully registered) song appends its entry
        // to the BGM list alone: the old final entry gains a continuation,
        // the new final line is bare, and no other file changes a byte.
        const QByteArray tableR = readAllBytes(tablePath);
        const QByteArray songsHR = readAllBytes(songsHPath);
        const QByteArray ldR = readAllBytes(ldPath);
        const QByteArray charmapR = readAllBytes(charmapPath);
        check(SongRegistry::registerSong(projectRoot, label, constant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
              "registerSong with debug.c fixture failed");
        const QByteArray afterMain =
            dbgLine("#define SOUND_LIST_BGM", true) + dbgLine("    X(MUS_GSC_ROUTE38)", true) +
            dbgLine("    X(MUS_CAUGHT)", true) + dbgLine("    X(MUS_VICTORY_WILD)", true) +
            dbgLine("    X(MUS_ONBOARDCHECK)", false) + "\n" +
            dbgLine("#define SOUND_LIST_SE", true) + dbgLine("    X(SE_USE_ITEM)", true) +
            dbgLine("    X(SE_PC_LOGIN)", false);
        check(readAllBytes(debugCPath) == afterMain,
              "debug.c entry not appended with the continuation handover");
        check(readAllBytes(tablePath) == tableR && readAllBytes(songsHPath) == songsHR &&
                  readAllBytes(ldPath) == ldR && readAllBytes(charmapPath) == charmapR,
              "debug.c registration touched another file");
        check(SongRegistry::registerSong(projectRoot, label, constant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId) &&
                  readAllBytes(debugCPath) == afterMain,
              "debug.c re-register was not byte-identical");
        status = SongRegistry::checkRegistration(projectRoot, label, constant);
        check(status.inDebugMenu && status.complete(),
              "debug.c entry not reflected in the registration status");
        check(SongRegistry::makeRemovalPlan(projectRoot, label, constant).inDebugMenu,
              "removal plan misses the debug menu entry");

        // The model's per-song gaps name the file — for unlisted songs only.
        check(project.reload(&error), "reload with debug.c fixture");
        const auto gapsFor = [&project](const QString &wanted) {
            for (const SongInfo &s : project.songs()) {
                if (s.label == wanted)
                    return s.registrationGaps;
            }
            return QStringList{QStringLiteral("<absent>")};
        };
        check(gapsFor(QStringLiteral("mus_littleroot_test")) ==
                  QStringList{QStringLiteral("src/debug.c")},
              "unlisted song's gaps do not name src/debug.c");
        check(!gapsFor(QStringLiteral("mus_caught")).contains(QStringLiteral("src/debug.c")),
              "listed song's gaps name src/debug.c anyway");

        // An SE_-prefixed constant routes to SOUND_LIST_SE; unregistering it
        // is the exact inverse, down to the '\' the old final entry sheds.
        const QString seLabel = QStringLiteral("se_onboardcheck");
        const QString seConstant = SongRegistry::constantForLabel(seLabel);
        check(SongRegistry::registerSong(projectRoot, seLabel, seConstant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
              "SE registerSong failed");
        const QByteArray afterSe =
            dbgLine("#define SOUND_LIST_BGM", true) + dbgLine("    X(MUS_GSC_ROUTE38)", true) +
            dbgLine("    X(MUS_CAUGHT)", true) + dbgLine("    X(MUS_VICTORY_WILD)", true) +
            dbgLine("    X(MUS_ONBOARDCHECK)", false) + "\n" +
            dbgLine("#define SOUND_LIST_SE", true) + dbgLine("    X(SE_USE_ITEM)", true) +
            dbgLine("    X(SE_PC_LOGIN)", true) + dbgLine("    X(SE_ONBOARDCHECK)", false);
        check(readAllBytes(debugCPath) == afterSe, "SE entry not routed to SOUND_LIST_SE");
        check(SongRegistry::unregisterSong(projectRoot, seLabel, seConstant, &error),
              "SE unregisterSong failed");
        check(readAllBytes(debugCPath) == afterMain && readAllBytes(tablePath) == tableR &&
                  readAllBytes(songsHPath) == songsHR && readAllBytes(ldPath) == ldR &&
                  readAllBytes(charmapPath) == charmapR,
              "SE song's registration did not round-trip");

        // A mid-list removal needs no continuation rewiring; the ghost label
        // exists nowhere but the fixture, so unregisterSong touches only its
        // line.
        {
            QByteArray withGhost = afterMain;
            const QByteArray anchor = dbgLine("    X(MUS_GSC_ROUTE38)", true);
            withGhost.insert(withGhost.indexOf(anchor) + anchor.size(),
                             dbgLine("    X(MUS_ONBOARDCHECK_GHOST)", true));
            writeDebug(withGhost);
            check(SongRegistry::unregisterSong(projectRoot,
                                               QStringLiteral("mus_onboardcheck_ghost"),
                                               QStringLiteral("MUS_ONBOARDCHECK_GHOST"), &error),
                  "ghost unregisterSong failed");
            check(readAllBytes(debugCPath) == afterMain,
                  "mid-list removal did not excise exactly one line");
        }

        // A stripped mid-list entry backfills at its ID position between its
        // neighbors — byte-identically, like the charmap backfill above.
        {
            QByteArray stripped = afterMain;
            const QByteArray caught = dbgLine("    X(MUS_CAUGHT)", true);
            const qsizetype at = stripped.indexOf(caught);
            check(at >= 0, "debug backfill: entry not in the fixture");
            stripped.remove(at, caught.size());
            writeDebug(stripped);
            check(SongRegistry::registerSong(
                      projectRoot, QStringLiteral("mus_caught"), QStringLiteral("MUS_CAUGHT"),
                      QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
                  "debug backfill: registerSong failed");
            check(readAllBytes(debugCPath) == afterMain,
                  "stripped debug entry not restored at its ID position");
        }

        // An ID preceding every listed entry lands before the first one.
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("mus_littleroot_test"),
                                         QStringLiteral("MUS_LITTLEROOT_TEST"),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
              "debug before-first: registerSong failed");
        QByteArray withLittleroot = afterMain;
        withLittleroot.insert(withLittleroot.indexOf(dbgLine("    X(MUS_GSC_ROUTE38)", true)),
                              dbgLine("    X(MUS_LITTLEROOT_TEST)", true));
        check(readAllBytes(debugCPath) == withLittleroot,
              "smallest-ID entry not inserted before the first entry");

        // List-end edges: removing a list's only entry bares its #define;
        // inserting into an empty list hands the #define the continuation
        // (single-space form — nothing left to align with).
        writeDebug(QByteArrayLiteral("#define SOUND_LIST_BGM\n") +
                   dbgLine("#define SOUND_LIST_SE", true) + "    X(SE_ONBOARDCHECK_GHOST)\n");
        check(SongRegistry::unregisterSong(projectRoot, QStringLiteral("se_onboardcheck_ghost"),
                                           QStringLiteral("SE_ONBOARDCHECK_GHOST"), &error),
              "sole-entry unregisterSong failed");
        check(readAllBytes(debugCPath) == QByteArrayLiteral("#define SOUND_LIST_BGM\n"
                                                            "#define SOUND_LIST_SE\n"),
              "removing a list's only entry left the #define continued");
        check(SongRegistry::registerSong(projectRoot, QStringLiteral("mus_caught"),
                                         QStringLiteral("MUS_CAUGHT"),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
              "empty-list registerSong failed");
        check(readAllBytes(debugCPath) == QByteArrayLiteral("#define SOUND_LIST_BGM \\\n"
                                                            "    X(MUS_CAUGHT)\n"
                                                            "#define SOUND_LIST_SE\n"),
              "empty-list insert did not hand the #define its continuation");

        // Older expansion debug menus (and forks of them) use a two-argument
        // entry form with a quoted display name, per-list column alignment
        // (the BGM and SE lists align differently), every line '\'-continued,
        // and a blank line ending the macro. New entries must match that
        // shape — a field report caught the single-arg form being inserted
        // into (and never recognized in) such a file.
        {
            const auto namedLine = [](const char *constant, int commaCol, int parenCol,
                                      int slashCol) {
                QByteArray t("    X(");
                t += constant;
                t += QByteArray(commaCol - t.size(), ' ') + ", \"";
                QByteArray display(constant);
                display.replace('_', '-');
                t += display + "\"";
                t += QByteArray(parenCol - t.size(), ' ') + ")";
                t += QByteArray(slashCol - t.size(), ' ') + "\\";
                return t + "\n";
            };
            const QByteArray named0 = QByteArrayLiteral("#define SOUND_LIST_BGM \\\n") +
                                      namedLine("MUS_GSC_ROUTE38", 34, 60, 62) +
                                      namedLine("MUS_VICTORY_WILD", 34, 60, 62) + "\n" +
                                      QByteArrayLiteral("#define SOUND_LIST_SE \\\n") +
                                      namedLine("SE_USE_ITEM", 28, 50, 52) + "\n";
            writeDebug(named0);
            check(SongRegistry::checkRegistration(projectRoot, QStringLiteral("mus_gsc_route38"),
                                                  QStringLiteral("MUS_GSC_ROUTE38"))
                      .inDebugMenu,
                  "two-argument debug entry not recognized");

            // Appending keeps the named shape and the BGM list's columns.
            check(SongRegistry::registerSong(projectRoot, label, constant,
                                             QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                             &songId),
                  "named-style registerSong failed");
            const QByteArray namedMain = QByteArrayLiteral("#define SOUND_LIST_BGM \\\n") +
                                         namedLine("MUS_GSC_ROUTE38", 34, 60, 62) +
                                         namedLine("MUS_VICTORY_WILD", 34, 60, 62) +
                                         namedLine("MUS_ONBOARDCHECK", 34, 60, 62) + "\n" +
                                         QByteArrayLiteral("#define SOUND_LIST_SE \\\n") +
                                         namedLine("SE_USE_ITEM", 28, 50, 52) + "\n";
            check(readAllBytes(debugCPath) == namedMain,
                  "named entry not appended in the list's shape");
            check(SongRegistry::registerSong(projectRoot, label, constant,
                                             QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                             &songId) &&
                      readAllBytes(debugCPath) == namedMain,
                  "named entry duplicated on re-register");

            // Mid-list ID order holds in the named shape too.
            check(SongRegistry::registerSong(
                      projectRoot, QStringLiteral("mus_caught"), QStringLiteral("MUS_CAUGHT"),
                      QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
                  "named mid-list registerSong failed");
            const QByteArray namedCaught = QByteArrayLiteral("#define SOUND_LIST_BGM \\\n") +
                                           namedLine("MUS_GSC_ROUTE38", 34, 60, 62) +
                                           namedLine("MUS_CAUGHT", 34, 60, 62) +
                                           namedLine("MUS_VICTORY_WILD", 34, 60, 62) +
                                           namedLine("MUS_ONBOARDCHECK", 34, 60, 62) + "\n" +
                                           QByteArrayLiteral("#define SOUND_LIST_SE \\\n") +
                                           namedLine("SE_USE_ITEM", 28, 50, 52) + "\n";
            check(readAllBytes(debugCPath) == namedCaught, "named backfill not at its ID position");

            // The SE list's own (different) columns drive SE entries, and
            // unregistering round-trips everything.
            check(SongRegistry::registerSong(projectRoot, seLabel, seConstant,
                                             QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                             &songId),
                  "named SE registerSong failed");
            const QByteArray namedSe = QByteArrayLiteral("#define SOUND_LIST_BGM \\\n") +
                                       namedLine("MUS_GSC_ROUTE38", 34, 60, 62) +
                                       namedLine("MUS_CAUGHT", 34, 60, 62) +
                                       namedLine("MUS_VICTORY_WILD", 34, 60, 62) +
                                       namedLine("MUS_ONBOARDCHECK", 34, 60, 62) + "\n" +
                                       QByteArrayLiteral("#define SOUND_LIST_SE \\\n") +
                                       namedLine("SE_USE_ITEM", 28, 50, 52) +
                                       namedLine("SE_ONBOARDCHECK", 28, 50, 52) + "\n";
            check(readAllBytes(debugCPath) == namedSe,
                  "named SE entry not aligned to the SE list's columns");
            check(SongRegistry::unregisterSong(projectRoot, seLabel, seConstant, &error) &&
                      readAllBytes(debugCPath) == namedCaught && readAllBytes(tablePath) == tableR,
                  "named SE registration did not round-trip");
        }

        // A vanilla scratch loses the fixture outright; an expansion checkout
        // gets its own debug.c back (the song's entry was already in the
        // snapshot — registerSong wrote it before this section).
        if (originalDebug.isEmpty())
            check(QFile::remove(debugCPath), "remove src/debug.c fixture");
        else
            writeDebug(originalDebug);
        check(project.reload(&error), "reload after debug.c fixture cleanup");
    }
}

} // namespace OnboardCheck
