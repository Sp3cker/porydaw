#include <QCheckBox>
#include <QComboBox>
#include <QLabel>
#include <QLineEdit>

#include "core/midiimport.h"
#include "core/songdocument.h"
#include "pipeline.h"
#include "ui/newsongwizard.h"
#include "ui/songsettingsdialog.h"

namespace OnboardCheck {

void runImportChecks(const QString &projectRoot, const QString &midiDir, const QString &mid2agb,
                     bool haveMid2agb, const QStringList &voicegroupArgs, DecompProject &project,
                     const SongCfg &cfg, const SmfFile &externalImport,
                     const SmfFile &duplicateSetters, CheckReporter &reporter)
{
    const auto check = [&](bool ok, const char *what) { reporter.check(ok, what); };
    const QStringList &vgArgs = voicegroupArgs;
    const SmfFile &external = externalImport;
    QString error;
    SmfFile imported;
    ImportAnalysis analysis = analyzeForImport(external);
    check(analysis.mappedTracks == 2, "import: mapped track count");
    check(analysis.peakConcurrentNotes == 7, "import: peak polyphony");
    check(analysis.sampleNoteLimit == 5, "import: sample note limit");
    bool sawDivisionWarning = false, sawPolyWarning = false;
    for (const QString &w : analysis.warnings) {
        if (w.contains(QStringLiteral("note timing")))
            sawDivisionWarning = true;
        if (w.contains(QStringLiteral("same time")))
            sawPolyWarning = true;
    }
    check(sawDivisionWarning, "import: no division warning for 480 ppqn");
    check(sawPolyWarning, "import: no polyphony warning for 7-note chord");
    bool sawMod = false, sawInert = false;
    for (const ImportCcUsage &cc : analysis.ccs) {
        if (cc.cc == 1)
            sawMod = cc.audible;
        if (cc.cc == 91)
            sawInert = !cc.audible;
    }
    check(sawMod, "import: CC1 not classified audible");
    check(sawInert, "import: CC91 not classified inert");
    check(analysis.tracks.size() == 2 && analysis.tracks[1].programs.size() == 2,
          "import: per-track program usage");
    check(analysis.silentTracks == 0, "import: no budget warning at default 16");

    // Track-budget warning: with a 1-track player, the second mapped track is
    // silent in-game and the warning names the player and its allocation.
    {
        const ImportAnalysis tight =
            analyzeForImport(external, 1, QStringLiteral("MUSIC_PLAYER_BGM"));
        check(tight.silentTracks == 1, "import: silent track counted");
        bool sawBudgetWarning = false;
        for (const QString &w : tight.warnings) {
            if (w.contains(QStringLiteral("MUSIC_PLAYER_BGM")) &&
                w.contains(QStringLiteral("will not play")))
                sawBudgetWarning = true;
        }
        check(sawBudgetWarning, "import: budget warning names the player");
        check(analyzeForImport(external, -1).silentTracks == 0,
              "import: unknown budget warns about nothing");
    }

    imported = external;

    // Division rescale onto the 24-clock grid (the wizard's default for a
    // non-multiple-of-24 file). Floor arithmetic matches mid2agb, so the
    // chord's onset lands where an as-is import would have played it:
    // 480 * 24 / 400 = 28.8 -> 28, offs 960 -> 57, EOT 3840 -> 230.
    rescaleDivision(&imported, 24);
    check(imported.division == 24, "rescale: division not rewritten");
    check(imported.tracks[1].events[4].tick == 28, "rescale: note-on tick");
    check(imported.tracks[1].events[11].tick == 57, "rescale: note-off tick");
    check(imported.tracks[1].endTick == 230, "rescale: end-of-track tick");
    check(imported.tracks[2].events[0].tick == 0, "rescale: tick-0 event moved");
    for (const SmfTrack &track : imported.tracks) {
        uint64_t prev = 0;
        for (const SmfEvent &ev : track.events) {
            check(ev.tick >= prev, "rescale: tick order regressed");
            prev = ev.tick;
        }
    }

    // The wizard end of the same option: the analysis page offers the rescale
    // (default on) and songFile() applies it with the Sound page's clock base.
    {
        NewSongWizard wizard(&project, external, QStringLiteral("ext.mid"), vgArgs);
        auto *rescale = wizard.page(0)->findChild<QCheckBox *>();
        check(rescale && rescale->isChecked(),
              "wizard: rescale checkbox missing or off for division 400");
        check(wizard.songFile().division == 24, "wizard: songFile() not rescaled by default");
        if (rescale) {
            rescale->setChecked(false);
            check(wizard.songFile().division == 400,
                  "wizard: opting out of the rescale still rescaled");
        }

        // The name validator folds typed capitals (Shift, Caps Lock) into the
        // lowercase convention instead of swallowing the keystroke; characters
        // outside the label grammar are still rejected outright.
        QLineEdit *nameEdit = nullptr;
        for (QLineEdit *edit : wizard.findChildren<QLineEdit *>()) {
            if (edit->placeholderText() == QStringLiteral("mus_my_song"))
                nameEdit = edit;
        }
        check(nameEdit, "wizard: name field not found");
        if (nameEdit) {
            nameEdit->clear();
            nameEdit->insert(QStringLiteral("MUS_Loud_3"));
            check(nameEdit->text() == QStringLiteral("mus_loud_3"),
                  "wizard: typed capitals not folded to lowercase");
            nameEdit->clear();
            nameEdit->insert(QStringLiteral("mus 3!"));
            check(nameEdit->text().isEmpty(),
                  "wizard: characters outside the label grammar accepted");
        }

        // Reverb is a plain value, not an optional override: the wizard emits
        // an explicit -R at the vanilla STD_REVERB default.
        check(wizard.cfg().reverb == SongCfg::kDefaultReverb,
              "wizard: reverb does not default to 50");
        check(wizard.cfg().rawFlags.contains(QStringLiteral("-R50")),
              "wizard: default reverb not written as an explicit -R flag");

        // Opening Song Settings without editing must preserve a missing -R;
        // otherwise accepting another settings tab dirties the song by
        // silently replacing the inherited default with an explicit flag.
        SongCfg bare;
        SongSettingsWidget widget(bare, vgArgs);
        check(widget.cfg().reverb == bare.reverb,
              "song settings: absent -R changed without a user edit");

        // Role-aware analysis: the analysis page's player choice and the
        // identity page's are one selection, kept in sync from either side,
        // and the analysis text tracks the chosen player's track budget.
        auto *analysisCombo = wizard.page(0)->findChild<QComboBox *>();
        auto *identityCombo = wizard.page(1)->findChild<QComboBox *>();
        check(analysisCombo && identityCombo, "wizard: player combos not found");
        if (analysisCombo && identityCombo) {
            bool synced = analysisCombo->currentData() == identityCombo->currentData();
            for (int i = analysisCombo->count() - 1; i >= 0; i--) {
                analysisCombo->setCurrentIndex(i);
                synced = synced && identityCombo->currentData() == analysisCombo->currentData();
            }
            check(synced, "wizard: identity player does not follow the analysis page");
            identityCombo->setCurrentIndex(identityCombo->count() - 1);
            check(analysisCombo->currentIndex() == identityCombo->currentIndex(),
                  "wizard: analysis player does not follow the identity page");
            identityCombo->setCurrentIndex(0);

            // A 1-track player mutes the external file's second track, and
            // the page says so in the singular. The selection also decides
            // what player() hands the song registration.
            const QVector<MusicPlayer> players = SongRegistry::musicPlayers(projectRoot);
            int tight = -1;
            for (int i = 0; i < players.size(); i++)
                if (players[i].trackCount == 1)
                    tight = i;
            if (tight >= 0) {
                analysisCombo->setCurrentIndex(analysisCombo->findData(players[tight].name));
                bool sawMute = false;
                for (const QLabel *label : wizard.page(0)->findChildren<QLabel *>())
                    if (label->text().contains(QStringLiteral("mute track 2")))
                        sawMute = true;
                check(sawMute, "wizard: 1-track player does not warn about muting track 2");
                check(wizard.player() == players[tight].name,
                      "wizard: player() does not return the engine symbol");
                analysisCombo->setCurrentIndex(0);
            }
        }
    }

    // Same-tick duplicate setters: the import silently keeps only the last of
    // each same-slot run (exporters love repeating the channel-init block),
    // while events whose every occurrence acts — notes, text metas, MEMACC
    // plumbing, the loop Label — survive untouched and in order.
    {
        // duplicateSetters
        SmfFile direct = duplicateSetters;
        // A tempo, 2 programs, CC7, bend, CC101, and polyAT(60) at tick 0,
        // plus the CC7 at 96.
        check(removeRedundantSetterEvents(&direct) == 8, "dedup: wrong removal count");
        check(removeRedundantSetterEvents(&direct) == 0, "dedup: not idempotent");
        const auto countEvents = [](const SmfTrack &track, uint8_t nibble, int cc) {
            int n = 0;
            for (const SmfEvent &ev : track.events) {
                if (ev.isChannel() && ev.typeNibble() == nibble && (cc < 0 || ev.data0 == cc))
                    n++;
            }
            return n;
        };
        int tempoCount = 0, textCount = 0;
        for (const SmfEvent &ev : direct.tracks[0].events) {
            if (!ev.isMeta())
                continue;
            if (ev.metaType == 0x51) {
                tempoCount++;
                check(ev.blob == QByteArray("\x07\xA1\x20", 3), "dedup: kept the wrong tempo");
            }
            textCount += ev.metaType == 0x01 ? 1 : 0;
        }
        check(tempoCount == 1, "dedup: same-tick tempo metas not collapsed");
        check(textCount == 2, "dedup: text metas were touched");
        const SmfTrack &lead = direct.tracks[1];
        check(countEvents(lead, 0xC, -1) == 2, "dedup: program-change count");
        check(countEvents(lead, 0xB, 7) == 3, "dedup: CC7 count");
        check(countEvents(lead, 0xE, -1) == 1, "dedup: bend count");
        check(countEvents(lead, 0xB, 101) == 1, "dedup: inert-CC count");
        check(countEvents(lead, 0xB, 0x0D) == 2, "dedup: MEMACC CCs were touched");
        check(countEvents(lead, 0xB, 0x11) == 2, "dedup: Label CCs were touched");
        check(countEvents(lead, 0xA, 60) == 1 && countEvents(lead, 0xA, 61) == 1,
              "dedup: poly-aftertouch not keyed per note");
        check(countEvents(lead, 0x9, -1) == 2 && countEvents(lead, 0x8, -1) == 2,
              "dedup: notes were touched");
        // The kept run preserves values, positions, and relative order: the
        // winners are the LAST of each run, still ahead of the tick's notes,
        // and the Label pair keeps its 2-then-3 file order.
        bool progOk = false, ccOk = false, bendOk = false, orderOk = true;
        int lastLabel = 0, firstNoteIdx = -1, progIdx = -1;
        for (size_t i = 0; i < lead.events.size(); i++) {
            const SmfEvent &ev = lead.events[i];
            if (ev.tick != 0)
                break;
            if (ev.typeNibble() == 0xC) {
                progOk = ev.data0 == 12;
                progIdx = int(i);
            }
            if (ev.typeNibble() == 0xB && ev.data0 == 7)
                ccOk = ev.data1 == 80;
            if (ev.typeNibble() == 0xE)
                bendOk = ev.data1 == 0x40;
            if (ev.typeNibble() == 0xB && ev.data0 == 0x11) {
                orderOk = orderOk && ev.data1 > lastLabel;
                lastLabel = ev.data1;
            }
            if (ev.typeNibble() == 0x9 && firstNoteIdx < 0)
                firstNoteIdx = int(i);
        }
        check(progOk && ccOk && bendOk, "dedup: a run's survivor is not its last value");
        check(orderOk && lastLabel == 3, "dedup: kept events lost their relative order");
        check(progIdx >= 0 && firstNoteIdx > progIdx,
              "dedup: setter drifted past the tick's notes");
        for (const SmfTrack &track : direct.tracks) {
            uint64_t prev = 0;
            for (const SmfEvent &ev : track.events) {
                check(ev.tick >= prev, "dedup: tick order regressed");
                prev = ev.tick;
            }
        }

        // The wizard end: songFile() applies the dedup silently on import.
        NewSongWizard wizard(&project, duplicateSetters, QStringLiteral("dups.mid"), vgArgs);
        const SmfFile cleaned = wizard.songFile();
        check(cleaned.tracks.size() == 2 && countEvents(cleaned.tracks[1], 0xB, 7) == 3 &&
                  countEvents(cleaned.tracks[1], 0xC, -1) == 2,
              "wizard: songFile() did not dedup same-tick setters");
    }

    const QString importLabel = QStringLiteral("mus_onboardcheck_import");
    const QString importMid = midiDir + QStringLiteral("/%1.mid").arg(importLabel);
    check(imported.writeFile(importMid, &error), "write imported .mid");
    check(SongRegistry::writeMidiCfgLine(midiDir, importLabel, cfg.rawFlags, &error),
          "write imported midi.cfg line");

    SmfFile reread;
    check(SmfFile::readFile(importMid, &reread, &error) &&
              reread.tracks.size() == imported.tracks.size() && reread.division == 24,
          "imported .mid does not re-read cleanly");

    check(project.reload(&error), "project reload after import");
    const SongInfo *importedSong = nullptr;
    for (const SongInfo &s : project.songs()) {
        if (s.label == importLabel)
            importedSong = &s;
    }
    check(importedSong && importedSong->isPlayable() && !importedSong->registered,
          "imported song not discovered");
    if (importedSong) {
        SongDocument doc;
        check(doc.load(*importedSong, &error), "imported song fails to open");
        check(doc.engineTrackCount() == 2, "imported song engine track count");
    }

    if (haveMid2agb)
        check(compilesThroughMid2agb(mid2agb, importMid, cfg.rawFlags),
              "imported song does not compile through mid2agb");
}

} // namespace OnboardCheck
