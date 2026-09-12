#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <algorithm>

#include "checks/editcheck/tst_songdocument_support.h"

void EditCheckTest::timeRangeRemove_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::timeRangeRemove()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "timeRangeRemove: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNotes(track, {{base + step * 50, 60, step, 90},
                              {base + step * 52, 62, step, 90},
                              {base + step * 56, 64, step, 90}});
    document.addLanePoint(track, 7, base + step * 51, 30);
    document.addLanePoint(track, 7, base + step * 52, 40);
    SongDocument::TimeScope scope;
    scope.tracks = {track};
    const int before = document.undoStack()->count();
    QVERIFY(document.removeTimeRange({base + step * 51, base + step * 54}, scope));
    DocNote note;
    DocLanePoint point;
    QVERIFY(document.findNote(track, base + step * 50, 60, &note));
    QVERIFY(!document.findNote(track, base + step * 52, 62, &note));
    QVERIFY(document.findNote(track, base + step * 53, 64, &note));
    QVERIFY(document.findLanePoint(track, 7, base + step * 51, &point));
    QCOMPARE(point.value, 40);
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 52, 62, &note));
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 53, 64, &note));
}

void EditCheckTest::songWholeSongRemove_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::songWholeSongRemove()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "songWholeSongRemove: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    // Globals travel too: a signature and a tempo inside the range
    // survive at the seam, later notes shift, loop markers stay put,
    // and every chunk's end-of-track closes the gap so the song is
    // exactly 4 steps shorter.
    const auto maxEnd = [&document] {
        uint64_t end = 0;
        for (const SmfTrack &chunk : document.smf().tracks)
            end = std::max(end, uint64_t(chunk.endTick));
        return end;
    };
    const TempoPoint originalTempo = songdocument_test::tempo(base + step * 63, 150);
    document.setTimeSig(base + step * 62, 3, 2);
    document.applyTempoEdit({{}, {originalTempo}});
    document.addNote(track, base + step * 66, 65, step, 90);
    const QByteArray bytesBefore = document.smf().write();
    const uint64_t endBefore = maxEnd();
    const uint64_t loopStart = document.loopTick(false);
    const uint64_t loopEnd = document.loopTick(true);
    SongDocument::TimeScope scope;
    scope.wholeSong = true;
    const int before = document.undoStack()->count();
    QVERIFY(document.removeTimeRange({base + step * 61, base + step * 65}, scope));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    DocTimeSig signature;
    DocNote shifted;
    QVERIFY(songdocument_test::findsTimeSig(document, base + step * 61, &signature));
    QCOMPARE(signature.numerator, uint8_t(3));
    QVERIFY(songdocument_test::containsTempo(document,
                                             songdocument_test::tempo(base + step * 61, 150)));
    QVERIFY(document.findNote(track, base + step * 62, 65, &shifted));
    QCOMPARE(document.loopTick(false), loopStart);
    QCOMPARE(document.loopTick(true), loopEnd);
    QCOMPARE(maxEnd(), endBefore - step * 4);
    QCOMPARE(document.undoStack()->count(), before + 1);

    document.undoStack()->undo();
    DocNote restored;
    QCOMPARE(document.smf().write(), bytesBefore);
    QVERIFY(songdocument_test::containsTempo(document, originalTempo));
    QVERIFY(document.findNote(track, base + step * 66, 65, &restored));
    QCOMPARE(document.loopTick(false), loopStart);
    QCOMPARE(maxEnd(), endBefore);
    QCOMPARE(document.loopTick(true), loopEnd);
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 62, 65, &shifted));
}

void EditCheckTest::voiceLanePoint_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::voiceLanePoint()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "voiceLanePoint: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addLanePoint(track, DOC_CC_VOICE, base + step, 5);
    DocLanePoint point;
    QVERIFY(document.findLanePoint(track, DOC_CC_VOICE, base + step, &point));
    document.moveLanePoints({{track, DOC_CC_VOICE, point, point.tick, 9}});
    QVERIFY(document.findLanePoint(track, DOC_CC_VOICE, base + step, &point));
    QCOMPARE(point.value, 9);
    document.moveLanePoints({{track, DOC_CC_VOICE, point, base + step * 6, 9}});
    QVERIFY(document.findLanePoint(track, DOC_CC_VOICE, base + step * 6, &point));
    document.deleteLanePoints(track, DOC_CC_VOICE, {point});
    QVERIFY(!document.findLanePoint(track, DOC_CC_VOICE, base + step * 6, &point));
}

void EditCheckTest::automationLanePoints_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::automationLanePoints()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "automationLanePoints: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const QByteArray originalBytes = document.smf().write();
    const auto originalTempos = document.tempoPoints();
    const int originalUndoIndex = document.undoStack()->index();
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addLanePoint(track, 7, base + step * 2, 100);
    document.addLanePoint(track, DOC_CC_BEND, base + step * 3, -1024);
    const TempoPoint tempo = songdocument_test::tempo(base + step * 4, 150);
    document.applyTempoEdit({{}, {tempo}});
    DocLanePoint cc;
    DocLanePoint bend;
    QVERIFY(document.findLanePoint(track, 7, base + step * 2, &cc));
    QVERIFY(document.findLanePoint(track, DOC_CC_BEND, base + step * 3, &bend));
    document.moveLanePoints({{track, 7, cc, base + step * 5, 90}});
    QVERIFY(document.findLanePoint(track, 7, base + step * 5, &cc));
    QCOMPARE(cc.value, 90);
    QVERIFY(document.findLanePoint(track, DOC_CC_BEND, base + step * 3, &bend));
    document.deleteLanePoints(track, DOC_CC_BEND, {bend});
    QVERIFY(!document.findLanePoint(track, DOC_CC_BEND, base + step * 3, &bend));
    document.applyTempoEdit({{tempo}, {}});
    QVERIFY(!songdocument_test::containsTempo(document, tempo));
    QVERIFY(document.findLanePoint(track, 7, base + step * 5, &cc));
    document.deleteLanePoints(track, 7, {cc});
    QVERIFY(!document.findLanePoint(track, 7, base + step * 5, &cc));
    const QByteArray editedBytes = document.smf().write();
    const auto editedTempos = document.tempoPoints();
    const int editedUndoIndex = document.undoStack()->index();
    while (document.undoStack()->index() > originalUndoIndex)
        document.undoStack()->undo();
    QCOMPARE(document.smf().write(), originalBytes);
    QVERIFY(document.tempoPoints() == originalTempos);
    while (document.undoStack()->index() < editedUndoIndex)
        document.undoStack()->redo();
    QCOMPARE(document.smf().write(), editedBytes);
    QVERIFY(document.tempoPoints() == editedTempos);
}
