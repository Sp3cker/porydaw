#include <QAction>
#include <QFile>
#include <QList>
#include <QListWidget>
#include <QRegularExpression>
#include <QSettings>
#include <QTemporaryDir>
#include <cstdio>

#include "core/songdocument.h"
#include "mainwindow.h"
#include "pipeline.h"
#include "ui/songlistpanel.h"

namespace OnboardCheck {

RegisteredSongFixture runRegistrationChecks(const QString &projectRoot, const QString &midiDir,
                                            int registeredCount, DecompProject &project,
                                            const SongCfg &cfg, CheckReporter &reporter)
{
    const auto check = [&](bool ok, const char *what) { reporter.check(ok, what); };
    QString error;
    // ---- New Song flow ------------------------------------------------------
    const QString label = QStringLiteral("mus_onboardcheck");
    const QString constant = SongRegistry::constantForLabel(label);
    check(constant == QStringLiteral("MUS_ONBOARDCHECK"), "constantForLabel");

    const SmfFile blank = SongRegistry::blankSong();
    const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(label);
    check(blank.writeFile(midPath, &error), "write blank .mid");
    check(SongRegistry::writeMidiCfgLine(midiDir, label, cfg.rawFlags, &error),
          "write midi.cfg line");
    check(SongRegistry::saveRegistrationMeta(projectRoot, label, constant,
                                             QStringLiteral("MUSIC_PLAYER_BGM")),
          "save sidecar meta");

    // The new song must surface on reload: unregistered, playable, cfg parsed.
    check(project.reload(&error), "project reload after create");
    const SongInfo *created = nullptr;
    for (const SongInfo &s : project.songs()) {
        if (s.label == label)
            created = &s;
    }
    check(created != nullptr, "created song not discovered on reload");
    if (created) {
        check(!created->registered, "created song should be unregistered");
        check(created->isPlayable(), "created song not playable");
        check(created->hasCfg && created->cfg.voicegroupArg == cfg.voicegroupArg,
              "created song cfg line not parsed back");
        check(created->constant == constant &&
                  created->player == QStringLiteral("MUSIC_PLAYER_BGM"),
              "sidecar registration meta not recalled");

        SongDocument doc;
        check(doc.load(*created, &error), "created song fails to open as a document");
    }

    RegistrationStatus status = SongRegistry::checkRegistration(projectRoot, label, constant);
    check(!status.inSongTable && !status.inSongsH && !status.inCharmap && !status.complete(),
          "fresh song already looks registered");

    RegistrationPlan plan =
        SongRegistry::makePlan(projectRoot, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"));
    check(plan.songId == registeredCount, "proposed song ID != registered song count");
    check(plan.songTableLine.contains(QStringLiteral("song mus_onboardcheck, MUSIC_PLAYER_BGM, 0")),
          "song_table line malformed");
    check(plan.songsHLine.startsWith(QStringLiteral("#define MUS_ONBOARDCHECK")) &&
              plan.songsHLine.endsWith(QString::number(plan.songId)),
          "songs.h line malformed");

    // charmap.txt: the constant maps to the ID as little-endian hex bytes.
    const QString charmapPath = projectRoot + QStringLiteral("/charmap.txt");
    const QString charmapBytes = QStringLiteral("%1 %2")
                                     .arg(plan.songId & 0xFF, 2, 16, QLatin1Char('0'))
                                     .arg((plan.songId >> 8) & 0xFF, 2, 16, QLatin1Char('0'))
                                     .toUpper();
    check(plan.charmapApplicable, "charmap.txt song section not detected");
    check(plan.charmapLine.startsWith(constant) &&
              plan.charmapLine.endsWith(QStringLiteral("= ") + charmapBytes),
          "charmap line malformed");

    // A column-aligned sound section (pokeruby, pokefirered) pads "=" into a
    // shared column, and non-song two-byte entries don't disturb the anchor
    // or the alignment. Fixture-swap a tiny aligned charmap and re-plan.
    {
        const QByteArray original = readAllBytes(charmapPath);
        const QByteArray fixtureLine = "MUS_DUMMY                 = 00 00";
        QFile cm(charmapPath);
        check(cm.open(QIODevice::WriteOnly | QIODevice::Truncate), "rewrite charmap.txt fixture");
        cm.write(fixtureLine + "\n"
                               "MUS_LITTLEROOT_TEST       = 5E 01\n"
                               "PKMN = 53 54\n");
        cm.close();
        const RegistrationPlan aligned = SongRegistry::makePlan(projectRoot, label, constant,
                                                                QStringLiteral("MUSIC_PLAYER_BGM"));
        check(aligned.charmapApplicable, "aligned fixture: section not detected");
        const int equalsColumn = fixtureLine.indexOf('=');
        check(aligned.charmapLine == constant +
                                         QString(equalsColumn - constant.size(), QLatin1Char(' ')) +
                                         QStringLiteral("= ") + charmapBytes,
              "aligned fixture: charmap line not padded to the '=' column");
        check(cm.open(QIODevice::WriteOnly | QIODevice::Truncate), "restore charmap.txt");
        cm.write(original);
        cm.close();
    }

    // porydaw writes the registration files itself.
    QString regError;
    int songId = -1;
    check(SongRegistry::registerSong(projectRoot, label, constant,
                                     QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
          "registerSong failed");
    if (!regError.isEmpty())
        std::fprintf(stderr, "onboardcheck: registerSong: %s\n", qUtf8Printable(regError));
    check(songId == registeredCount, "registered song ID != registered song count");

    status = SongRegistry::checkRegistration(projectRoot, label, constant);
    check(status.complete(), "registration incomplete after registerSong");

    const QString tablePath = projectRoot + QStringLiteral("/sound/song_table.inc");
    const QString songsHPath = projectRoot + QStringLiteral("/include/constants/songs.h");
    const QString ldPath = projectRoot + QStringLiteral("/ld_script.ld");
    if (plan.ldApplicable)
        check(readAllBytes(ldPath).contains(
                  QStringLiteral("sound/songs/midi/%1.o").arg(label).toUtf8()),
              "ld_script.ld missing the song's object line");
    if (plan.charmapApplicable)
        check(readAllBytes(charmapPath).contains(plan.charmapLine.toUtf8()),
              "charmap.txt missing the song's ID mapping");

    // Registering again must be a byte-level no-op.
    const QByteArray tableBefore = readAllBytes(tablePath);
    const QByteArray songsHBefore = readAllBytes(songsHPath);
    const QByteArray ldBefore = readAllBytes(ldPath);
    const QByteArray charmapBefore = readAllBytes(charmapPath);
    check(SongRegistry::registerSong(projectRoot, label, constant,
                                     QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
          "second registerSong failed");
    check(songId == registeredCount, "song ID drifted on re-register");
    check(readAllBytes(tablePath) == tableBefore && readAllBytes(songsHPath) == songsHBefore &&
              readAllBytes(ldPath) == ldBefore && readAllBytes(charmapPath) == charmapBefore,
          "re-register was not byte-identical");

    // A songs.h define whose ID drifted from the table index gets corrected.
    {
        QByteArray tampered = songsHBefore;
        const QByteArray goodDefine = QStringLiteral("#define %1").arg(constant).toUtf8();
        const int at = tampered.indexOf(goodDefine);
        check(at >= 0, "tamper: define not found");
        int digits = tampered.indexOf('\n', at);
        QByteArray line = tampered.mid(at, digits - at);
        line.replace(QByteArray::number(songId), QByteArray::number(songId + 500));
        tampered.replace(at, digits - at, line);
        QFile out(songsHPath);
        check(out.open(QIODevice::WriteOnly) && out.write(tampered) == tampered.size(),
              "tamper: rewrite songs.h");
        out.close();

        status = SongRegistry::checkRegistration(projectRoot, label, constant);
        check(!status.inSongsH, "stale define not detected");
        check(SongRegistry::registerSong(projectRoot, label, constant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
              "registerSong after tamper failed");
        check(readAllBytes(songsHPath) == songsHBefore, "stale define not corrected");
    }

    // Likewise a charmap.txt entry whose ID bytes drifted.
    if (plan.charmapApplicable) {
        QByteArray tampered = charmapBefore;
        const int at = tampered.indexOf(plan.charmapLine.toUtf8());
        check(at >= 0, "charmap tamper: entry not found");
        QByteArray line = plan.charmapLine.toUtf8();
        line.replace(charmapBytes.toUtf8(), QByteArrayLiteral("FF 7F"));
        tampered.replace(at, plan.charmapLine.size(), line);
        QFile out(charmapPath);
        check(out.open(QIODevice::WriteOnly) && out.write(tampered) == tampered.size(),
              "charmap tamper: rewrite charmap.txt");
        out.close();

        status = SongRegistry::checkRegistration(projectRoot, label, constant);
        check(!status.inCharmap, "stale charmap bytes not detected");
        check(SongRegistry::registerSong(projectRoot, label, constant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
              "registerSong after charmap tamper failed");
        check(readAllBytes(charmapPath) == charmapBefore, "stale charmap bytes not corrected");
    }

    check(project.reload(&error), "project reload after registration");
    const SongInfo *registered = nullptr;
    for (const SongInfo &s : project.songs()) {
        if (s.label == label)
            registered = &s;
    }
    check(registered && registered->registered, "song not registered after registerSong");
    check(registered && registered->id == registeredCount, "registered song ID wrong");
    check(registered && registered->constant == constant, "constant not matched from songs.h");

    // ---- charmap ID-ordered backfill -----------------------------------------
    // A mid-table song whose charmap line went missing gets it reinserted at
    // its ID position between its neighbors, not appended — proven by the
    // file round-tripping byte-identically through strip + re-register.
    if (plan.charmapApplicable) {
        const QByteArray original = readAllBytes(charmapPath);
        QList<QByteArray> lines = original.split('\n');
        const SongInfo *midSong = nullptr;
        int lineAt = -1;
        for (int id = registeredCount / 2; id < registeredCount && !midSong; id++) {
            const SongInfo &s = project.songs().at(id);
            if (!s.registered || s.constant.isEmpty())
                continue;
            // The song's own line, and only one of it (alias constants that
            // share an ID would make the strip ambiguous).
            int found = -1, hits = 0;
            for (int i = 0; i < lines.size(); i++) {
                if (lines[i].startsWith(s.constant.toUtf8() + ' ')) {
                    found = i;
                    hits++;
                }
            }
            if (hits == 1) {
                midSong = &s;
                lineAt = found;
            }
        }
        check(midSong != nullptr, "ordered backfill: no mid-table candidate song");
        if (midSong) {
            lines.removeAt(lineAt);
            QFile out(charmapPath);
            check(out.open(QIODevice::WriteOnly), "ordered backfill: rewrite charmap.txt");
            out.write(lines.join('\n'));
            out.close();
            check(readAllBytes(charmapPath) != original, "ordered backfill: strip was a no-op");
            check(SongRegistry::registerSong(projectRoot, midSong->label, midSong->constant,
                                             midSong->player.isEmpty()
                                                 ? QStringLiteral("MUSIC_PLAYER_BGM")
                                                 : midSong->player,
                                             &regError, &songId),
                  "ordered backfill: registerSong failed");
            check(readAllBytes(charmapPath) == original,
                  "backfilled charmap line not restored at its ID position");
        }
    }

    // ---- songs.h ID-ordered backfill -----------------------------------------
    // The same strip + re-register proof for songs.h: a mid-table song's
    // define must return to its ID position between its neighbors, not be
    // appended. Vanilla files end with hex-valued sentinels after the last
    // real ID (MUS_NONE 0xFFFF, PHONEME_ID_NONE 0xFF); a backfill must not
    // be dragged past them — their leading digit once parsed as value 0.
    {
        const QByteArray original = readAllBytes(songsHPath);
        QList<QByteArray> lines = original.split('\n');
        const SongInfo *midSong = nullptr;
        int lineAt = -1;
        for (int id = registeredCount / 2; id < registeredCount && !midSong; id++) {
            const SongInfo &s = project.songs().at(id);
            if (!s.registered || s.constant.isEmpty())
                continue;
            // The song's own define, in exactly the shape registerSong would
            // rewrite (no trailing comment), and only one of it. The line
            // directly above must be the ID-1 define — reinserting after the
            // last smaller value is only byte-identical when no section
            // comment or blank line sits between the two (the freed-slot
            // scenario this proves).
            const QRegularExpression exactRe(
                QStringLiteral("^#define %1\\s+%2$").arg(s.constant).arg(id));
            const QRegularExpression prevRe(
                QStringLiteral("^\\s*#define\\s+\\w+\\s+%1\\b").arg(id - 1));
            int found = -1, hits = 0;
            for (int i = 0; i < lines.size(); i++) {
                if (exactRe.match(QString::fromUtf8(lines[i])).hasMatch()) {
                    found = i;
                    hits++;
                }
            }
            if (hits == 1 && found > 0 &&
                prevRe.match(QString::fromUtf8(lines[found - 1])).hasMatch()) {
                midSong = &s;
                lineAt = found;
            }
        }
        check(midSong != nullptr, "songs.h backfill: no mid-table candidate song");
        if (midSong) {
            lines.removeAt(lineAt);
            QFile out(songsHPath);
            check(out.open(QIODevice::WriteOnly), "songs.h backfill: rewrite songs.h");
            out.write(lines.join('\n'));
            out.close();
            check(readAllBytes(songsHPath) != original, "songs.h backfill: strip was a no-op");
            check(SongRegistry::registerSong(projectRoot, midSong->label, midSong->constant,
                                             midSong->player.isEmpty()
                                                 ? QStringLiteral("MUSIC_PLAYER_BGM")
                                                 : midSong->player,
                                             &regError, &songId),
                  "songs.h backfill: registerSong failed");
            check(readAllBytes(songsHPath) == original,
                  "backfilled songs.h define not restored at its ID position");
        }
    }

    // ---- Aliased table entries -----------------------------------------------
    // Forks fill new table slots with copies of real songs (pokezelda field
    // report: mus_rg_mt_moon at both 455 and 498), so a label can own several
    // indices. A songs.h define / charmap entry naming ANY of them is
    // correctly registered — the checker must not flag it, and registerSong
    // must not "correct" the define to the duplicate's index. A define
    // naming none of them still heals, to the label's first entry.
    {
        const QByteArray table0 = readAllBytes(tablePath);
        const QByteArray songsH0 = readAllBytes(songsHPath);
        const QByteArray charmap0 = readAllBytes(charmapPath);
        QFile table(tablePath);
        check(table.open(QIODevice::Append), "alias: append duplicate entry");
        table.write(plan.songTableLine.toUtf8() + "\n");
        table.close();

        status = SongRegistry::checkRegistration(projectRoot, label, constant);
        check(status.complete(), "aliased table entry flagged the song");
        const RegistrationPlan aliased = SongRegistry::makePlan(projectRoot, label, constant,
                                                                QStringLiteral("MUSIC_PLAYER_BGM"));
        check(aliased.songId == plan.songId, "aliased plan abandoned the define's own index");
        check(SongRegistry::registerSong(projectRoot, label, constant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &songId),
              "aliased registerSong failed");
        check(readAllBytes(songsHPath) == songsH0 && readAllBytes(charmapPath) == charmap0,
              "aliased registerSong rewrote the define or charmap entry");

        // Genuine drift heals to the label's FIRST entry, not the alias.
        {
            QByteArray tampered = songsH0;
            const QByteArray goodDefine = QStringLiteral("#define %1").arg(constant).toUtf8();
            const int at = tampered.indexOf(goodDefine);
            check(at >= 0, "alias drift: define not found");
            const int end = tampered.indexOf('\n', at);
            QByteArray line = tampered.mid(at, end - at);
            line.replace(QByteArray::number(plan.songId), QByteArrayLiteral("9999"));
            tampered.replace(at, end - at, line);
            QFile out(songsHPath);
            check(out.open(QIODevice::WriteOnly) && out.write(tampered) == tampered.size(),
                  "alias drift: rewrite songs.h");
            out.close();
            status = SongRegistry::checkRegistration(projectRoot, label, constant);
            check(!status.inSongsH, "drifted define not flagged despite alias");
            check(SongRegistry::registerSong(projectRoot, label, constant,
                                             QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                             &songId),
                  "alias drift: registerSong failed");
            check(readAllBytes(songsHPath) == songsH0,
                  "drifted define not healed to the label's first entry");
        }

        check(table.open(QIODevice::WriteOnly | QIODevice::Truncate) &&
                  table.write(table0) == table0.size(),
              "alias: restore song_table.inc");
        table.close();
    }

    return {label, constant, plan};
}

void runRegisterActionChecks(const QString &projectRoot, const QString &midiDir,
                             const QString &mid2agb, bool haveMid2agb, const SongCfg &cfg,
                             const RegisteredSongFixture &fixture, CheckReporter &reporter)
{
    const auto check = [&](bool ok, const char *what) { reporter.check(ok, what); };
    const QString &label = fixture.label;
    const RegistrationPlan &plan = fixture.plan;
    const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(label);
    const QString charmapPath = projectRoot + QStringLiteral("/charmap.txt");
    // ---- Register Song action wiring ----------------------------------------
    // Strip the song's charmap line — the state of any song registered before
    // porydaw wrote charmap entries. The song still reads as registered from
    // the song table, but File → Register Song must stay enabled, and running
    // it must backfill the line byte-identically.
    if (plan.charmapApplicable) {
        const QByteArray full = readAllBytes(charmapPath);
        QByteArray stripped = full;
        const int at = stripped.indexOf(plan.charmapLine.toUtf8());
        check(at >= 0, "action check: charmap entry not found");
        int end = stripped.indexOf('\n', at);
        end = end < 0 ? stripped.size() : end + 1;
        stripped.remove(at, end - at);
        QFile out(charmapPath);
        check(out.open(QIODevice::WriteOnly) && out.write(stripped) == stripped.size(),
              "action check: rewrite charmap.txt");
        out.close();

        // Redirected settings: the user's real session is never touched.
        QTemporaryDir settingsDir;
        check(settingsDir.isValid(), "action check: no temp dir for settings");
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
        MainWindow window;
        check(window.runRegisterActionCheck(projectRoot, label),
              "register-action check did not run");
        check(readAllBytes(charmapPath) == full,
              "backfill did not restore charmap.txt byte-identically");
    }

    if (haveMid2agb)
        check(compilesThroughMid2agb(mid2agb, midPath, cfg.rawFlags),
              "blank new song does not compile through mid2agb");
}

} // namespace OnboardCheck
