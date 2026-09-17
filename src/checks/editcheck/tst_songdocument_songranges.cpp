#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"

void EditCheckTest::rangeEditCollisionRejects()
{
    using namespace songdocument_test;
    for (bool empty : {false, true}) {
        SmfFile smf;
        if (!empty)
            smf.tracks = {conductor(), {{channel(0xC0, 0, 0, 0)}, 200}};
        auto fixture = makeDocument(smf);
        QVERIFY(fixture);
        auto &doc = fixture->document;
        if (!empty) {
            doc.addNote(0, 0, 60, 100, 91);
            doc.addLanePoint(0, 7, 20, 80);
            doc.addNote(0, 150, 61, 10, 92);
            doc.undoStack()->undo();
        }
        const SavedDocState saved = captureDocState(doc);
        const auto notes = empty ? std::vector<DocNote>{} : saved.notes;
        SongDocument::RangeEdit edit;
        edit.minimumEngineTrackCount = 2;
        edit.removeNotes = notes;
        edit.addNotes = {{1, {{10, 60, 20, 80}}}, {1, {{20, 60, 20, 90}}}};
        edit.addPoints = {{1, 7, {{10, 90}}}};
        edit.addTempo = {tempo(10, 150)};
        doc.applyRangeEdit(QStringLiteral("colliding range"), edit);
        QVERIFY2(docStateMismatch(doc, saved).isEmpty(), qPrintable(docStateMismatch(doc, saved)));
    }
    SmfFile smf;
    smf.tracks = {conductor(), {{channel(0xC0, 0, 0, 0)}, 200}};
    auto fixture = makeDocument(smf);
    QVERIFY(fixture);
    auto &doc = fixture->document;
    doc.addNotes(0, {{20, 60, 10, 81}, {30, 60, 70, 92}});
    doc.addLanePoint(0, 7, 10, 80);
    doc.applyTempoEdit({{}, {tempo(10, 150)}});
    auto notes = doc.notesForTrack(0);
    const SavedDocState before = captureDocState(doc);
    doc.moveRange({notes.front()}, doc.lanePoints(0, 7), -30, doc.tempoPoints());
    QVERIFY2(docStateMismatch(doc, before).isEmpty(), qPrintable(docStateMismatch(doc, before)));
    // [30,60) shifts to [0,20), not [0,30): the stationary [20,30) survives.
    doc.addNote(0, 60, 60, 20, 73);
    DocNote moving;
    QVERIFY(doc.findNote(0, 30, 60, &moving));
    const auto partialBefore = doc.smf().write();
    doc.moveRange({moving}, {}, -40);
    QVERIFY(notePairsConsistent(doc, 0));
    DocNote tail;
    QVERIFY(doc.findNote(0, 60, 60, &tail));
    QCOMPARE(tail.duration, uint32_t(20));
    QVERIFY(doc.findNote(0, 20, 60, &tail));
    QCOMPARE(tail.duration, uint32_t(10));
    QVERIFY(doc.findNote(0, 0, 60, &moving));
    QCOMPARE(moving.duration, uint32_t(20));
    const auto after = doc.smf().write();
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), partialBefore);
    doc.undoStack()->redo();
    QCOMPARE(doc.smf().write(), after);
    QVERIFY(notePairsConsistent(doc, 0));
}

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
