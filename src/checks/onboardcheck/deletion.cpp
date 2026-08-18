#include <QFile>
#include <QRegularExpression>
#include <QSettings>
#include <QTemporaryDir>
#include <cstdio>

#include "context.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "project/voicegroupsource.h"

namespace OnboardCheck {

void runDeletionChecks(Context &context)
{
    const QString &projectRoot = context.projectRoot;
    const QString &midiDir = context.midiDir;
    const SongCfg &cfg = context.cfg;
    const RegistrationPlan plan = SongRegistry::makePlan(
        projectRoot, QStringLiteral("mus_onboardcheck"), QStringLiteral("MUS_ONBOARDCHECK"),
        QStringLiteral("MUSIC_PLAYER_BGM"));
    DecompProject &project = context.project;
    const QString tablePath = projectRoot + QStringLiteral("/sound/song_table.inc");
    const QString songsHPath = projectRoot + QStringLiteral("/include/constants/songs.h");
    const QString ldPath = projectRoot + QStringLiteral("/ld_script.ld");
    const QString charmapPath = projectRoot + QStringLiteral("/charmap.txt");
    const QString importLabel = QStringLiteral("mus_onboardcheck_import");
    QString error;
    QString regError;
    // ---- Delete Song --------------------------------------------------------
    // The inverse of the flows above. A full create→register→delete cycle
    // must leave every file byte-identical; a mid-table delete leaves a free
    // slot — a plain duplicate of entry 0's dummy line — that keeps later
    // IDs stable and is reused by the next registration; entry 0 itself (the
    // fallback song) is untouchable either way.
    const QString cfgPath = midiDir + QStringLiteral("/midi.cfg");
    QString firstLabel; // the song table's entry 0
    {
        const QByteArray table0 = readAllBytes(tablePath);
        const QByteArray songsH0 = readAllBytes(songsHPath);
        const QByteArray ld0 = readAllBytes(ldPath);
        const QByteArray charmap0 = readAllBytes(charmapPath);
        const QByteArray cfg0 = readAllBytes(cfgPath);
        // Empty on vanilla; on an expansion checkout the delete cycle must
        // round-trip the debug menu's sound lists too.
        const QString debugCPath = projectRoot + QStringLiteral("/src/debug.c");
        const QByteArray debug0 = readAllBytes(debugCPath);

        static const QRegularExpression songEntryRe(QStringLiteral(R"(^\s*song\s+(\w+))"));
        int tableEntries = 0;
        for (const QByteArray &line : table0.split('\n')) {
            const QRegularExpressionMatch m = songEntryRe.match(QString::fromUtf8(line));
            if (!m.hasMatch())
                continue;
            if (firstLabel.isEmpty())
                firstLabel = m.captured(1);
            tableEntries++;
        }
        check(!firstLabel.isEmpty(), "delete: no entry 0 in song_table.inc");
        // Entries bearing entry 0's label; one more than at the snapshot
        // means one free slot is open.
        const auto dummyEntries = [&]() {
            int n = 0;
            for (const QByteArray &line : readAllBytes(tablePath).split('\n')) {
                const QRegularExpressionMatch m = songEntryRe.match(QString::fromUtf8(line));
                if (m.hasMatch() && m.captured(1) == firstLabel)
                    n++;
            }
            return n;
        };
        const int dummies0 = dummyEntries();

        const QString labelA = QStringLiteral("mus_onboardcheck_del_a");
        const QString labelB = QStringLiteral("mus_onboardcheck_del_b");
        const QString labelC = QStringLiteral("mus_onboardcheck_del_c");
        const auto createAndRegister = [&](const QString &lab, int *id) {
            const SmfFile smf = SongRegistry::blankSong();
            check(smf.writeFile(midiDir + QStringLiteral("/%1.mid").arg(lab), &error),
                  "delete: write .mid");
            check(SongRegistry::writeSongFlags(midiDir, lab, cfg.rawFlags, &error),
                  "delete: write flags");
            check(SongRegistry::registerSong(projectRoot, lab, SongRegistry::constantForLabel(lab),
                                             QStringLiteral("MUSIC_PLAYER_BGM"), &regError, id),
                  "delete: registerSong failed");
        };
        const auto deleteSong = [&](const QString &lab) {
            QString err;
            check(SongRegistry::unregisterSong(projectRoot, lab,
                                               SongRegistry::constantForLabel(lab), &err),
                  "delete: unregisterSong failed");
            check(SongRegistry::removeSongFlags(midiDir, lab, &err),
                  "delete: removeSongFlags failed");
            check(QFile::remove(midiDir + QStringLiteral("/%1.mid").arg(lab)),
                  "delete: remove .mid");
        };

        int idA = -1, idB = -1, idC = -1;
        createAndRegister(labelA, &idA);
        createAndRegister(labelB, &idB);
        check(idB == idA + 1, "delete: fresh registrations not sequential");

        // Mid-table delete: A leaves a free slot; B keeps its ID.
        deleteSong(labelA);
        check(dummyEntries() == dummies0 + 1, "mid-table delete left no free slot");
        check(!readAllBytes(songsHPath).contains("MUS_ONBOARDCHECK_DEL_A"),
              "deleted song's define still in songs.h");
        check(!readAllBytes(ldPath).contains("mus_onboardcheck_del_a.o"),
              "deleted song's object line still in ld_script.ld");
        check(!readAllBytes(charmapPath).contains("MUS_ONBOARDCHECK_DEL_A"),
              "deleted song's charmap entry still present");
        check(!readAllBytes(debugCPath).contains("MUS_ONBOARDCHECK_DEL_A"),
              "deleted song's debug menu entry still present");
        check(!readAllBytes(cfgPath).contains("mus_onboardcheck_del_a.mid"),
              "deleted song's midi.cfg line still present");
        RegistrationStatus after = SongRegistry::checkRegistration(
            projectRoot, labelB, SongRegistry::constantForLabel(labelB));
        check(after.complete(), "surviving song's registration broke on delete");
        // The free slot borrows entry 0's label without impersonating it:
        // the fallback song must still read as correctly registered.
        after = SongRegistry::checkRegistration(projectRoot, firstLabel,
                                                SongRegistry::constantForLabel(firstLabel));
        check(after.inSongTable && after.inSongsH,
              "free slot misattributed the fallback song's table entry");

        // Reuse: the next song is offered the freed ID, and its lines land
        // in ID order (songs.h sorted like the charmap insertion).
        const RegistrationPlan planC =
            SongRegistry::makePlan(projectRoot, labelC, SongRegistry::constantForLabel(labelC),
                                   QStringLiteral("MUSIC_PLAYER_BGM"));
        check(planC.songId == idA, "free slot not proposed for the next song");
        createAndRegister(labelC, &idC);
        check(idC == idA, "free slot not reused on registration");
        check(dummyEntries() == dummies0, "reused slot kept its dummy entry");
        {
            const QByteArray songsH = readAllBytes(songsHPath);
            const auto defineAt = [&songsH](const char *constant) {
                return songsH.indexOf(QByteArray("#define ") + constant);
            };
            check(defineAt("MUS_ONBOARDCHECK_DEL_C") >= 0 &&
                      defineAt("MUS_ONBOARDCHECK_DEL_C") < defineAt("MUS_ONBOARDCHECK_DEL_B"),
                  "reused ID's define not inserted in songs.h ID order");
        }
        if (plan.charmapApplicable) {
            const QByteArray charmap = readAllBytes(charmapPath);
            check(charmap.indexOf("MUS_ONBOARDCHECK_DEL_C") >= 0 &&
                      charmap.indexOf("MUS_ONBOARDCHECK_DEL_C") <
                          charmap.indexOf("MUS_ONBOARDCHECK_DEL_B"),
                  "reused ID's charmap entry not in ID order");
        }

        // Deleting an already-deleted song is a byte-level no-op success.
        {
            const QByteArray t = readAllBytes(tablePath);
            const QByteArray h = readAllBytes(songsHPath);
            QString err;
            check(SongRegistry::unregisterSong(projectRoot, labelA,
                                               SongRegistry::constantForLabel(labelA), &err),
                  "second unregister failed");
            check(readAllBytes(tablePath) == t && readAllBytes(songsHPath) == h,
                  "second unregister was not byte-identical");
        }

        // Wind back down: C leaves the slot again; B's last-entry delete then
        // collapses the trailing free slot. Everything must round-trip to the
        // pre-cycle bytes.
        deleteSong(labelC);
        check(dummyEntries() == dummies0 + 1, "re-deleted slot is not free again");
        deleteSong(labelB);
        check(readAllBytes(tablePath) == table0, "song_table.inc did not round-trip");
        check(readAllBytes(songsHPath) == songsH0, "songs.h did not round-trip");
        check(readAllBytes(ldPath) == ld0, "ld_script.ld did not round-trip");
        check(readAllBytes(charmapPath) == charmap0, "charmap.txt did not round-trip");
        check(readAllBytes(cfgPath) == cfg0, "midi.cfg did not round-trip");
        check(readAllBytes(debugCPath) == debug0, "src/debug.c did not round-trip");

        // Entry 0 is never deletable...
        {
            QString err;
            check(!SongRegistry::unregisterSong(projectRoot, firstLabel,
                                                SongRegistry::constantForLabel(firstLabel), &err) &&
                      !err.isEmpty(),
                  "unregisterSong deleted the fallback song");
            check(readAllBytes(tablePath) == table0, "refused delete still wrote");
        }
        // ...and never a free slot: entry 0 bears the dummy label like any
        // tombstone would, but the planner must not offer ID 0 — on a table
        // whose only dummy entry IS entry 0, it appends.
        {
            const RegistrationPlan probed = SongRegistry::makePlan(
                projectRoot, QStringLiteral("mus_onboardcheck_probe"),
                QStringLiteral("MUS_ONBOARDCHECK_PROBE"), QStringLiteral("MUSIC_PLAYER_BGM"));
            check(probed.songId != 0, "entry 0 was offered as a free slot");
            if (dummies0 == 1)
                check(probed.songId == tableEntries,
                      "planner did not append with no free slots open");
        }

        if (QFile::exists(midiDir + QStringLiteral("/%1.mid").arg(importLabel))) {
            // An unregistered stray (the imported song): no table entry at all,
            // so deletion is just the .mid and the cfg line.
            {
                QString err;
                check(SongRegistry::unregisterSong(projectRoot, importLabel,
                                                   SongRegistry::constantForLabel(importLabel),
                                                   &err),
                      "stray unregister failed");
                check(readAllBytes(tablePath) == table0, "stray unregister touched song_table.inc");
                check(SongRegistry::removeSongFlags(midiDir, importLabel, &err),
                      "stray removeSongFlags failed");
                check(!readAllBytes(cfgPath).contains(importLabel.toUtf8() + ".mid"),
                      "stray's midi.cfg line still present");
            }
        }
    }

    // ---- Delete voicegroup --------------------------------------------------
    // deletableVoicegroup gates the offer: sole song user, per-file layout,
    // no keysplit/drumkit reference, no C reference. deleteVoicegroup then
    // inverts createVoicegroup + appendIncludeLine byte-identically.
    {
        const QString hubPath = projectRoot + QStringLiteral("/sound/voice_groups.inc");
        const QByteArray hub0 = readAllBytes(hubPath);
        const QString vgName = QStringLiteral("onboardcheckvg");
        const bool created =
            VoicegroupSource::createVoicegroup(projectRoot, vgName, QString(), QString(), &error) &&
            VoicegroupSource::appendIncludeLine(projectRoot, vgName, &error);
        check(created, "vg delete: createVoicegroup/appendIncludeLine failed");
        if (created) {
            QVector<SongInfo> songs = project.songs();
            SongInfo user;
            user.label = QStringLiteral("mus_vg_user");
            user.cfg.voicegroupArg = QStringLiteral("_onboardcheckvg");
            songs.append(user);
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label) == vgName,
                  "sole-user voicegroup not deletable");

            SongInfo second = user;
            second.label = QStringLiteral("mus_vg_user2");
            songs.append(second);
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label).isEmpty(),
                  "shared voicegroup offered for deletion");
            songs.removeLast();

            // A keysplit reference from another voicegroup is load-bearing.
            const QString subName = QStringLiteral("onboardchecksub");
            check(VoicegroupSource::createVoicegroup(projectRoot, subName, QString(), QString(),
                                                     &error),
                  "vg delete: create sub voicegroup");
            {
                QFile host(projectRoot + QStringLiteral("/sound/voicegroups/onboardcheckvg.inc"));
                check(host.open(QIODevice::Append), "vg delete: append keysplit line");
                host.write("\tvoice_keysplit voicegroup_onboardchecksub, "
                           "KeySplitTable1\n");
            }
            SongInfo subUser = user;
            subUser.label = QStringLiteral("mus_vg_sub_user");
            subUser.cfg.voicegroupArg = QStringLiteral("_onboardchecksub");
            QVector<SongInfo> subSongs = songs;
            subSongs.append(subUser);
            check(SongRegistry::deletableVoicegroup(projectRoot, subSongs, subUser.label).isEmpty(),
                  "keysplit sub-voicegroup offered for deletion");
            check(VoicegroupSource::deleteVoicegroup(projectRoot, subName, &error),
                  "vg delete: remove sub voicegroup");

            // A C reference would break the link, not merely dangle.
            const QString refPath = projectRoot + QStringLiteral("/src/onboardcheck_ref.c");
            {
                QFile ref(refPath);
                check(ref.open(QIODevice::WriteOnly), "vg delete: write C ref");
                ref.write("extern int voicegroup_onboardcheckvg[];\n");
            }
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label).isEmpty(),
                  "C-referenced voicegroup offered for deletion");
            QFile::remove(refPath);
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label) == vgName,
                  "vg delete: dropped C reference not re-detected");

            check(VoicegroupSource::deleteVoicegroup(projectRoot, vgName, &error),
                  "deleteVoicegroup failed");
            check(!QFile::exists(projectRoot +
                                 QStringLiteral("/sound/voicegroups/onboardcheckvg.inc")),
                  "voicegroup file survived deletion");
            check(readAllBytes(hubPath) == hub0, "voice_groups.inc did not round-trip");
            check(VoicegroupSource::deleteVoicegroup(projectRoot, vgName, &error),
                  "second deleteVoicegroup failed");
        }
    }

    // ---- Delete action wiring ----------------------------------------------
    // The MainWindow path: deleting an open song closes its tab, drops it
    // from the model and browser, and moves the .mid to .porydaw/trash/.
    {
        const QString delLabel = QStringLiteral("mus_onboardcheck_del_ui");
        const SmfFile smf = SongRegistry::blankSong();
        check(smf.writeFile(midiDir + QStringLiteral("/%1.mid").arg(delLabel), &error),
              "action delete: write .mid");
        check(SongRegistry::writeSongFlags(midiDir, delLabel, cfg.rawFlags, &error),
              "action delete: write flags");
        int id = -1;
        check(SongRegistry::registerSong(projectRoot, delLabel,
                                         SongRegistry::constantForLabel(delLabel),
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError, &id),
              "action delete: registerSong failed");

        QTemporaryDir settingsDir;
        check(settingsDir.isValid(), "action delete: no temp dir for settings");
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
        MainWindow window;
        check(window.runDeleteActionCheck(projectRoot, delLabel),
              "delete-action check did not run");
    }
}

} // namespace OnboardCheck
