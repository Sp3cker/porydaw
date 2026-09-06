#include "checks/onboardcheck/onboardingtest.h"

#include <QCheckBox>
#include <QComboBox>
#include <QLabel>
#include <QLineEdit>

#include "checks/support/songfixture.h"
#include "core/midiimport.h"
#include "core/songdocument.h"
#include "ui/newsongwizard.h"
#include "ui/songsettingsdialog.h"

void OnboardingTest::importAnalysis_data()
{
    QTest::addColumn<int>("budget");
    QTest::newRow("default") << 16;
    QTest::newRow("tight") << 1;
    QTest::newRow("unknown") << -1;
}

void OnboardingTest::importAnalysis()
{
    QFETCH(int, budget);
    QString error;
    SmfFile external;
    QVERIFY2(midiFixture(QStringLiteral("external_import.mid"), external, error),
             qPrintable(error));
    const ImportAnalysis analysis =
        analyzeForImport(external, budget, QStringLiteral("MUSIC_PLAYER_BGM"));
    QCOMPARE(analysis.mappedTracks, 2);
    QCOMPARE(analysis.peakConcurrentNotes, 7);
    QCOMPARE(analysis.sampleNoteLimit, 5);
    bool divisionCategory = false;
    bool polyphonyCategory = false;
    bool budgetCategory = false;
    for (const QString &warning : analysis.warnings) {
        divisionCategory = divisionCategory || warning.contains(QStringLiteral("note timing"));
        polyphonyCategory = polyphonyCategory || warning.contains(QStringLiteral("same time"));
        budgetCategory = budgetCategory || (warning.contains(QStringLiteral("MUSIC_PLAYER_BGM")) &&
                                            warning.contains(QStringLiteral("will not play")));
    }
    QVERIFY(divisionCategory);
    QVERIFY(polyphonyCategory);
    QCOMPARE(analysis.silentTracks, budget == 1 ? 1 : 0);
    QCOMPARE(budgetCategory, budget == 1);
    QCOMPARE(analysis.tracks.size(), qsizetype{2});
    QCOMPARE(analysis.tracks[1].programs.size(), qsizetype{2});
    bool modAudible = false;
    bool reverbInert = false;
    for (const ImportCcUsage &usage : analysis.ccs) {
        modAudible = modAudible || (usage.cc == 1 && usage.audible);
        reverbInert = reverbInert || (usage.cc == 91 && !usage.audible);
    }
    QVERIFY(modAudible);
    QVERIFY(reverbInert);
}

void OnboardingTest::importRescale()
{
    QString error;
    SmfFile imported;
    QVERIFY2(midiFixture(QStringLiteral("external_import.mid"), imported, error),
             qPrintable(error));
    rescaleDivision(&imported, 24);
    QCOMPARE(imported.division, 24);
    QCOMPARE(imported.tracks[1].events[4].tick, uint64_t(28));
    QCOMPARE(imported.tracks[1].events[11].tick, uint64_t(57));
    QCOMPARE(imported.tracks[1].endTick, uint64_t(230));
    QCOMPARE(imported.tracks[2].events[0].tick, uint64_t(0));
    for (const SmfTrack &track : imported.tracks) {
        uint64_t previous = 0;
        for (const SmfEvent &event : track.events) {
            QVERIFY(event.tick >= previous);
            previous = event.tick;
        }
    }
}

void OnboardingTest::importDedup()
{
    QString error;
    SmfFile midi;
    QVERIFY2(midiFixture(QStringLiteral("duplicate_setters.mid"), midi, error), qPrintable(error));
    QCOMPARE(removeRedundantSetterEvents(&midi), 8);
    QCOMPARE(removeRedundantSetterEvents(&midi), 0);
    const SmfTrack &lead = midi.tracks[1];
    const auto count = [&lead](uint8_t type, int data0) {
        int total = 0;
        for (const SmfEvent &event : lead.events)
            total += event.isChannel() && event.typeNibble() == type &&
                     (data0 < 0 || event.data0 == data0);
        return total;
    };
    QCOMPARE(count(0xc, -1), 2);
    QCOMPARE(count(0xb, 7), 3);
    QCOMPARE(count(0xe, -1), 1);
    QCOMPARE(count(0xb, 101), 1);
    QCOMPARE(count(0xb, 0x0d), 2);
    QCOMPARE(count(0xb, 0x11), 2);
    QCOMPARE(count(0xa, 60), 1);
    QCOMPARE(count(0xa, 61), 1);
    QCOMPARE(count(0x9, -1), 2);
    QCOMPARE(count(0x8, -1), 2);
    int tempo = 0;
    int text = 0;
    for (const SmfEvent &event : midi.tracks[0].events) {
        if (event.isMeta() && event.metaType == 0x51) {
            ++tempo;
            QCOMPARE(event.blob, QByteArray("\x07\xA1\x20", 3));
        }
        text += event.isMeta() && event.metaType == 0x01;
    }
    QCOMPARE(tempo, 1);
    QCOMPARE(text, 2);
    int labelCount = 0;
    int previousLabel = 0;
    int programIndex = -1;
    int firstNote = -1;
    bool program = false;
    bool cc7 = false;
    bool bend = false;
    for (int i = 0; i < int(lead.events.size()) && lead.events[i].tick == 0; ++i) {
        const SmfEvent &event = lead.events[i];
        program =
            program || (event.typeNibble() == 0xc && event.data0 == 12 && (programIndex = i, true));
        cc7 = cc7 || (event.typeNibble() == 0xb && event.data0 == 7 && event.data1 == 80);
        bend = bend || (event.typeNibble() == 0xe && event.data1 == 0x40);
        if (event.typeNibble() == 0xb && event.data0 == 0x11) {
            QVERIFY(event.data1 > previousLabel);
            previousLabel = event.data1;
            ++labelCount;
        }
        if (event.typeNibble() == 0x9 && firstNote < 0)
            firstNote = i;
    }
    QVERIFY(program && cc7 && bend);
    QCOMPARE(labelCount, 2);
    QCOMPARE(previousLabel, 3);
    QVERIFY(programIndex >= 0 && firstNote > programIndex);
}

void OnboardingTest::importWizard()
{
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    DecompProject project;
    QVERIFY2(project.open(fixture->root(), &error), qPrintable(error));
    SmfFile external;
    QVERIFY2(midiFixture(QStringLiteral("external_import.mid"), external, error),
             qPrintable(error));
    const QStringList voicegroups = SongRegistry::voicegroupArgs(fixture->root());
    QVERIFY(!voicegroups.isEmpty());
    NewSongWizard wizard(&project, external, QStringLiteral("ext.mid"), voicegroups);
    QCheckBox *rescale = wizard.page(0)->findChild<QCheckBox *>();
    QVERIFY(rescale);
    QVERIFY(rescale->isChecked());
    QCOMPARE(wizard.songFile().division, 24);
    rescale->setChecked(false);
    QCOMPARE(wizard.songFile().division, 400);
    QLineEdit *name = nullptr;
    for (QLineEdit *edit : wizard.findChildren<QLineEdit *>())
        if (edit->placeholderText() == QStringLiteral("mus_my_song"))
            name = edit;
    QVERIFY(name);
    name->clear();
    name->insert(QStringLiteral("MUS_Loud_3"));
    QCOMPARE(name->text(), QStringLiteral("mus_loud_3"));
    name->clear();
    name->insert(QStringLiteral("mus 3!"));
    QVERIFY(name->text().isEmpty());
    QCOMPARE(wizard.cfg().reverb, SongCfg::kDefaultReverb);
    QVERIFY(wizard.cfg().rawFlags.contains(QStringLiteral("-R50")));
    SongCfg bare;
    SongSettingsWidget settings(bare, voicegroups);
    QCOMPARE(settings.cfg().reverb, bare.reverb);
    QComboBox *analysis = wizard.page(0)->findChild<QComboBox *>();
    QComboBox *identity = wizard.page(1)->findChild<QComboBox *>();
    QVERIFY(analysis && identity);
    for (int index = 0; index < analysis->count(); ++index) {
        analysis->setCurrentIndex(index);
        QCOMPARE(identity->currentData(), analysis->currentData());
    }
    const QVector<MusicPlayer> players = SongRegistry::musicPlayers(fixture->root());
    for (const MusicPlayer &player : players) {
        if (player.trackCount != 1)
            continue;
        analysis->setCurrentIndex(analysis->findData(player.name));
        bool muteWarning = false;
        for (const QLabel *notice : wizard.page(0)->findChildren<QLabel *>())
            muteWarning = muteWarning || notice->text().contains(QStringLiteral("mute track 2"));
        QVERIFY(muteWarning);
        QCOMPARE(wizard.player(), player.name);
        break;
    }
    SmfFile duplicateSetters;
    QVERIFY2(midiFixture(QStringLiteral("duplicate_setters.mid"), duplicateSetters, error),
             qPrintable(error));
    NewSongWizard dedupWizard(&project, duplicateSetters, QStringLiteral("dups.mid"), voicegroups);
    const SmfFile cleaned = dedupWizard.songFile();
    QCOMPARE(cleaned.tracks.size(), qsizetype{2});
    int cc7 = 0;
    int programs = 0;
    for (const SmfEvent &event : cleaned.tracks[1].events) {
        cc7 += event.isChannel() && event.typeNibble() == 0xb && event.data0 == 7;
        programs += event.isChannel() && event.typeNibble() == 0xc;
    }
    QCOMPARE(cc7, 3);
    QCOMPARE(programs, 2);
    identity->setCurrentIndex(0);
    QCOMPARE(analysis->currentIndex(), identity->currentIndex());
}

void OnboardingTest::importRoundtrip()
{
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    SmfFile imported;
    QVERIFY2(midiFixture(QStringLiteral("external_import.mid"), imported, error),
             qPrintable(error));
    rescaleDivision(&imported, 24);
    SongCfg cfg;
    QVERIFY2(defaultCfg(root, cfg, error), qPrintable(error));
    const QString label = QStringLiteral("mus_onboardcheck_import");
    const QString mid = midiDirectory(root) + QStringLiteral("/") + label + QStringLiteral(".mid");
    QVERIFY2(imported.writeFile(mid, &error), qPrintable(error));
    QVERIFY2(SongRegistry::writeMidiCfgLine(midiDirectory(root), label, cfg.rawFlags, &error),
             qPrintable(error));
    const QByteArray serialized = readFile(mid, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    SmfFile reread;
    QVERIFY2(SmfFile::readFile(mid, &reread, &error), qPrintable(error));
    const QString repeatPath =
        midiDirectory(root) + QStringLiteral("/") + label + QStringLiteral("_repeat.mid");
    QVERIFY2(reread.writeFile(repeatPath, &error), qPrintable(error));
    QCOMPARE(readFile(repeatPath, error), serialized);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(reread.division, 24);
    QCOMPARE(reread.tracks.size(), imported.tracks.size());
    DecompProject project;
    QVERIFY2(project.open(root, &error), qPrintable(error));
    const SongInfo *song = nullptr;
    for (const SongInfo &candidate : project.songs())
        if (candidate.label == label)
            song = &candidate;
    QVERIFY(song);
    QVERIFY(song->isPlayable() && !song->registered);
    SongDocument document;
    QVERIFY2(document.load(*song, &error), qPrintable(error));
    QCOMPARE(document.engineTrackCount(), 2);
}

void OnboardingTest::compilesThroughMid2agb_data()
{
    QTest::addColumn<QString>("kind");
    QTest::newRow("blank") << QStringLiteral("blank");
    QTest::newRow("imported") << QStringLiteral("imported");
}

void OnboardingTest::compilesThroughMid2agb()
{
    QFETCH(QString, kind);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    SongCfg cfg;
    QVERIFY2(defaultCfg(root, cfg, error), qPrintable(error));
    const QString label = QStringLiteral("mus_onboardcheck_compile_") + kind;
    SmfFile midi;
    if (kind == QStringLiteral("blank"))
        midi = SongRegistry::blankSong();
    else
        QVERIFY2(midiFixture(QStringLiteral("external_import.mid"), midi, error),
                 qPrintable(error));
    if (kind == QStringLiteral("imported"))
        rescaleDivision(&midi, 24);
    const QString mid = midiDirectory(root) + QStringLiteral("/") + label + QStringLiteral(".mid");
    QVERIFY2(midi.writeFile(mid, &error), qPrintable(error));
    QVERIFY2(compile(root, mid, cfg.rawFlags, error), qPrintable(error));
}
