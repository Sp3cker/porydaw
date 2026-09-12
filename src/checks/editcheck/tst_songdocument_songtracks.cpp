#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"
#include "core/miditimeline.h"

namespace {

SmfFile markerNameFile()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack first;
    first.events = {songdocument_test::channel(0xC0, 0, 1, 0),
                    songdocument_test::channel(0x90, 12, 60, 100),
                    songdocument_test::channel(0x80, 24, 60, 0)};
    first.endTick = 48;
    smf.tracks.push_back(first);
    smf.tracks.push_back({{songdocument_test::channel(0xC1, 0, 2, 0)}, 48});
    return smf;
}

} // namespace

void EditCheckTest::trackCreateDelete_data()
{
    addSongRows(SongCapability::AddTrack);
}

void EditCheckTest::trackCreateDelete()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "trackCreateDelete: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    QVERIFY(document.canAddTrack());
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    const int added = document.addTrack(7);
    QVERIFY(added >= 0);
    const auto voices = document.lanePoints(added, DOC_CC_VOICE);
    QVERIFY(!voices.empty());
    QCOMPARE(voices.front().tick, uint64_t(0));
    QCOMPARE(voices.front().value, 7);
    document.addNote(added, base, 72, step * 4, 100);
    DocNote note;
    QVERIFY(document.findNote(added, base, 72, &note));
    document.deleteTrack(added);
    QVERIFY(!document.findNote(added, base, 72, &note));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
}

void EditCheckTest::trackDuplicate_data()
{
    addSongRows(SongCapability::DuplicateTrack);
}

void EditCheckTest::trackDuplicate()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "trackDuplicate: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    QVERIFY(document.canAddTrack());

    const auto source = document.notesForTrack(track);
    const int copy = document.duplicateTrack(track);
    QVERIFY(copy >= 0);
    QVERIFY(copy != track);
    const auto copied = document.notesForTrack(copy);
    QVERIFY(songdocument_test::sameNotes(source, copied));
    document.deleteTrack(copy);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
}

void EditCheckTest::trackMove_data()
{
    addSongRows(SongCapability::ReorderableTrack);
}

void EditCheckTest::trackMove()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "trackMove: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    QVERIFY(document.engineTrackCount() >= 2);
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.applyTempoEdit({{}, {songdocument_test::tempo(base + step * 110, 145)}});
    document.setTimeSig(base + step * 112, 5, 2);
    const uint64_t loopStart = document.loopTick(false);
    const uint64_t loopEnd = document.loopTick(true);
    const auto source = document.notesForTrack(0);
    const uint8_t sourceChannel = document.channelFor(0);
    const int last = document.engineTrackCount() - 1;
    const int before = document.undoStack()->count();
    QVERIFY(!document.moveTrack(0, 0));
    QCOMPARE(document.undoStack()->count(), before);
    QVERIFY(document.moveTrack(0, last));
    QCOMPARE(document.undoStack()->count(), before + 1);
    QVERIFY(songdocument_test::sameNotes(document.notesForTrack(last), source));
    QCOMPARE(document.channelFor(last), sourceChannel);
    QVERIFY(songdocument_test::containsTempo(document,
                                             songdocument_test::tempo(base + step * 110, 145)));
    DocTimeSig signature;
    QVERIFY(songdocument_test::findsTimeSig(document, base + step * 112, &signature));
    QCOMPARE(document.loopTick(false), loopStart);
    QCOMPARE(document.loopTick(true), loopEnd);
    document.undoStack()->undo();
    QVERIFY(songdocument_test::sameNotes(document.notesForTrack(0), source));
    document.undoStack()->redo();
    QVERIFY(document.moveTrack(last, 0));
    QVERIFY(songdocument_test::sameNotes(document.notesForTrack(0), source));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
}

void EditCheckTest::trackMarkerName()
{
    auto fixture = songdocument_test::makeDocument(markerNameFile(), QStringLiteral("marker-name"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    QVERIFY(document.engineTrackCount() >= 2);
    QCOMPARE(document.smfTrackFor(0), 0);
    const uint64_t base = songdocument_test::distantBase(document);
    QUndoStack *const undo = document.undoStack();
    const int indexBefore = undo->index();
    const QByteArray bytesBefore = document.smf().write();
    const QString nameBefore = document.trackName(0);
    const int last = document.engineTrackCount() - 1;
    const uint64_t loopStart = document.loopTick(false);
    const uint64_t loopEnd = document.loopTick(true);

    document.renameTrack(0, {});
    document.insertRawEvent(0, songdocument_test::meta(0x03, 0, QByteArrayLiteral("[")));
    document.insertRawEvent(0, songdocument_test::meta(0x06, base, QByteArrayLiteral("][")));
    QVERIFY(document.moveTrack(0, last));
    QCOMPARE(document.trackName(last), QStringLiteral("["));
    QCOMPARE(document.loopTick(false), loopStart);
    QCOMPARE(document.loopTick(true), loopEnd);
    bool markerStayed = false;
    for (const SmfEvent &event : document.smf().tracks.front().events) {
        markerStayed |=
            event.isMeta() && event.metaType == 0x06 && event.blob == QByteArrayLiteral("][");
    }
    QVERIFY(markerStayed);

    // The rename, both inserts and the move revert together; the
    // song is sorted again at the entry index.
    while (undo->index() > indexBefore)
        undo->undo();
    QCOMPARE(document.smf().write(), bytesBefore);
    QCOMPARE(document.trackName(0), nameBefore);
    QCOMPARE(document.loopTick(false), loopStart);
    QCOMPARE(document.loopTick(true), loopEnd);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
}

void EditCheckTest::trackDeleteRescue_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::trackDeleteRescue()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "trackDeleteRescue: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");

    const uint64_t loopStart = document.loopTick(false);
    const uint64_t loopEnd = document.loopTick(true);
    document.deleteTrack(track);
    QCOMPARE(document.loopTick(false), loopStart);
    QCOMPARE(document.loopTick(true), loopEnd);
    document.undoStack()->undo();
    QCOMPARE(document.loopTick(false), loopStart);
    QCOMPARE(document.loopTick(true), loopEnd);
}

void EditCheckTest::trackRename_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::trackRename()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "trackRename: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");

    const auto rawNameCount = [&document, track] {
        const int smfTrack = document.smfTrackFor(track);
        int count = 0;
        SmfChannelPrefix prefix;
        for (const SmfEvent &event : document.smf().tracks[size_t(smfTrack)].events) {
            prefix.observe(event);
            if (event.isMeta() && event.metaType == 0x03 && prefix.channel < 0)
                ++count;
        }
        return count;
    };
    document.renameTrack(track, QStringLiteral("editcheck name"));
    QCOMPARE(document.trackName(track), QStringLiteral("editcheck name"));
    QCOMPARE(rawNameCount(), 1);
    const auto timeline = document.buildTimeline(48000.0);
    QVERIFY(timeline);
    QCOMPARE(timeline->tracks[size_t(track)].name, QStringLiteral("editcheck name"));
    const int before = document.undoStack()->count();
    document.renameTrack(track, QStringLiteral("  editcheck name  "));
    QCOMPARE(document.undoStack()->count(), before);
    document.renameTrack(track, QStringLiteral("["));
    document.renameTrack(track, QStringLiteral(" ][ "));
    QCOMPARE(document.undoStack()->count(), before);
    QCOMPARE(document.trackName(track), QStringLiteral("editcheck name"));
    document.renameTrack(track, {});
    QVERIFY(document.trackName(track).isEmpty());
    QCOMPARE(rawNameCount(), 0);
    document.undoStack()->undo();
    QCOMPARE(document.trackName(track), QStringLiteral("editcheck name"));
    document.undoStack()->redo();
    QVERIFY(document.trackName(track).isEmpty());
}

void EditCheckTest::songTimeSignature_data()
{
    addSongRows(SongCapability::Playable);
}

void EditCheckTest::songTimeSignature()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "songTimeSignature: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    const size_t before = document.timeSigs().size();
    document.setTimeSig(base, 3, 3);
    DocTimeSig signature;
    QVERIFY(songdocument_test::findsTimeSig(document, base, &signature));
    QCOMPARE(signature.numerator, uint8_t(3));
    QCOMPARE(signature.denomPow2, uint8_t(3));
    document.setTimeSig(base, 7, 2);
    QVERIFY(songdocument_test::findsTimeSig(document, base, &signature));
    QCOMPARE(signature.numerator, uint8_t(7));
    QCOMPARE(signature.denomPow2, uint8_t(2));
    QCOMPARE(document.timeSigs().size(), before + 1);
    document.moveTimeSig(base, base + step * 4);
    QVERIFY(!songdocument_test::findsTimeSig(document, base, &signature));
    QVERIFY(songdocument_test::findsTimeSig(document, base + step * 4, &signature));
    QCOMPARE(signature.numerator, uint8_t(7));
    document.deleteTimeSig(base + step * 4);
    QVERIFY(!songdocument_test::findsTimeSig(document, base + step * 4, &signature));
}

void EditCheckTest::loopCfgUndoRedo_data()
{
    addSongRows(SongCapability::Playable);
}

void EditCheckTest::loopCfgUndoRedo()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const QByteArray baseline = document.smf().write();
    const uint32_t step = document.ticksPerClock();
    const Tick loopStart = document.loopTick(false);
    document.setLoopTick(false,
                         loopStart == CoreTimeDefaults::kNoTick ? 0 : int64_t(loopStart) + step);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    SongCfg cfg = document.cfg();
    cfg.masterVolume = cfg.masterVolume == 80 ? 90 : 80;
    document.setCfg(cfg);
    while (document.undoStack()->canUndo())
        document.undoStack()->undo();
    QCOMPARE(document.smf().write(), baseline);
    QCOMPARE(document.cfg().masterVolume, song.cfg.masterVolume);
    while (document.undoStack()->canRedo())
        document.undoStack()->redo();
    const QByteArray redone = document.smf().write();
    QVERIFY(redone != baseline || songdocument_test::firstEditableTrack(document) < 0);
    while (document.undoStack()->canUndo())
        document.undoStack()->undo();
    QCOMPARE(document.smf().write(), baseline);
}
