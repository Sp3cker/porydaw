#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"

void EditCheckTest::rangeEdit_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeEdit()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for range editing");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNotes(track, {{Tick(base + step * 30), 60, step * 2, 90},
                              {Tick(base + step * 32), 62, step * 2, 90}});
    document.addLanePoint(track, 7, base + step * 30, 80);
    document.applyTempoEdit({{}, {songdocument_test::tempo(base + step * 31, 140)}});
    SongDocument::RangeEdit edit;
    for (const DocNote &note : document.notesForTrack(track)) {
        if (note.tick == base + step * 30 || note.tick == base + step * 32)
            edit.removeNotes.push_back(note);
    }
    for (const DocLanePoint &point : document.lanePoints(track, 7)) {
        if (point.tick == base + step * 30)
            edit.removePoints.push_back(point);
    }
    edit.removeTempo.push_back(songdocument_test::tempo(base + step * 31, 140));
    edit.addNotes.push_back({track, {{Tick(base + step * 40), 65, step * 2, 90}}});
    edit.addPoints.push_back({track, 7, {{Tick(base + step * 40), 70}}});
    edit.addTempo.push_back(songdocument_test::tempo(base + step * 41, 155));
    const int before = document.undoStack()->count();
    document.applyRangeEdit(QStringLiteral("range edit"), edit);
    DocNote note;
    DocLanePoint point;
    QVERIFY(!document.findNote(track, base + step * 30, 60, &note));
    QVERIFY(!document.findNote(track, base + step * 32, 62, &note));
    QVERIFY(document.findNote(track, base + step * 40, 65, &note));
    QVERIFY(document.findLanePoint(track, 7, base + step * 40, &point));
    QCOMPARE(point.value, 70);
    QVERIFY(songdocument_test::containsTempo(document,
                                             songdocument_test::tempo(base + step * 41, 155)));
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 30, 60, &note));
    QVERIFY(document.findNote(track, base + step * 32, 62, &note));
    QVERIFY(!document.findNote(track, base + step * 40, 65, &note));
    QVERIFY(!songdocument_test::containsTempo(document,
                                              songdocument_test::tempo(base + step * 41, 155)));
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 40, 65, &note));
}

void EditCheckTest::rangeMove_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeMove()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for range moving");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNotes(track, {{Tick(base + step * 80), 60, step * 2, 90},
                              {Tick(base + step * 82), 64, step * 2, 90}});
    document.addLanePoint(track, 7, base + step * 80, 45);
    document.applyTempoEdit({{}, {songdocument_test::tempo(base + step * 81, 140)}});
    DocNote first;
    DocNote second;
    DocLanePoint point;
    QVERIFY(document.findNote(track, base + step * 80, 60, &first));
    QVERIFY(document.findNote(track, base + step * 82, 64, &second));
    QVERIFY(document.findLanePoint(track, 7, base + step * 80, &point));
    const int before = document.undoStack()->count();
    document.moveRange({first, second}, {point}, int64_t(step) * 3,
                       {songdocument_test::tempo(base + step * 81, 140)});
    QVERIFY(document.findNote(track, base + step * 83, 60, &first));
    QCOMPARE(first.duration, step * 2);
    QVERIFY(document.findNote(track, base + step * 85, 64, &second));
    QCOMPARE(second.duration, step * 2);
    QVERIFY(document.findLanePoint(track, 7, base + step * 83, &point));
    QCOMPARE(point.value, 45);
    QVERIFY(songdocument_test::containsTempo(document,
                                             songdocument_test::tempo(base + step * 84, 140)));
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.moveRange({first}, {point}, 0, {});
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 80, 60, &first));
    QVERIFY(document.findNote(track, base + step * 82, 64, &second));
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 83, 60, &first));
}

void EditCheckTest::rangeLaneBulk_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeLaneBulk()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for bulk lane moves");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addLanePoint(track, 7, base + step * 90, 20);
    document.addLanePoint(track, 7, base + step * 91, 40);
    document.addLanePoint(track, 7, base + step * 92, 60);
    DocLanePoint first;
    DocLanePoint second;
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &first));
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &second));
    const int before = document.undoStack()->count();
    document.moveLanePoints({{track, 7, first, Tick(base + step * 93), 25},
                             {track, 7, second, Tick(base + step * 94), 45}});
    DocLanePoint point;
    QVERIFY(document.findLanePoint(track, 7, base + step * 93, &point));
    QCOMPARE(point.value, 25);
    QVERIFY(document.findLanePoint(track, 7, base + step * 94, &point));
    QCOMPARE(point.value, 45);
    QVERIFY(document.findLanePoint(track, 7, base + step * 92, &point));
    QCOMPARE(point.value, 60);
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &point));
    QCOMPARE(point.value, 20);
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &point));
    QCOMPARE(point.value, 40);
    QVERIFY(!document.findLanePoint(track, 7, base + step * 93, &point));
    document.undoStack()->redo();
    QVERIFY(document.findLanePoint(track, 7, base + step * 93, &point));
}

void EditCheckTest::rangeLaneConverge_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeLaneConverge()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for converging lane moves");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addLanePoint(track, 7, base + step * 90, 25);
    document.addLanePoint(track, 7, base + step * 91, 45);
    DocLanePoint first;
    DocLanePoint second;
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &first));
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &second));
    const int before = document.undoStack()->count();
    document.moveLanePoints({{track, 7, first, Tick(base + step * 97), 70},
                             {track, 7, second, Tick(base + step * 97), 72}});
    const auto atDestination = document.lanePoints(track, 7);
    int destinationCount = 0;
    for (const DocLanePoint &point : atDestination) {
        if (point.tick == base + step * 97) {
            ++destinationCount;
            QCOMPARE(point.value, 72);
        }
    }
    QCOMPARE(destinationCount, 1);
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    DocLanePoint point;
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &point));
    QCOMPARE(point.value, 25);
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &point));
    QCOMPARE(point.value, 45);
    QVERIFY(!document.findLanePoint(track, 7, base + step * 97, &point));
}
