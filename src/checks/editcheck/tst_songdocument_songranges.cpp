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

    // Two same-destination groups write overlapping same-pitch spans; the
    // combined eligible set refuses atomically — no removals, lane writes,
    // tempo change, history entry or revision change.
    const QByteArray baseline = document.smf().write();
    const int trackCountBefore = document.engineTrackCount();
    {
        SongDocument::RangeEdit collision = edit;
        collision.minimumEngineTrackCount = track + 2;
        collision.addNotes.push_back({track, {{Tick(base + step * 40), 65, step * 2, 90}}});
        const int refusalUndo = document.undoStack()->count();
        const int refusalUndoIndex = document.undoStack()->index();
        const uint64_t refusalRevision = document.revision();
        document.applyRangeEdit(QStringLiteral("overlapping groups"), collision);
        QCOMPARE(document.smf().write(), baseline);
        QCOMPARE(document.engineTrackCount(), trackCountBefore);
        QCOMPARE(document.undoStack()->count(), refusalUndo);
        QCOMPARE(document.undoStack()->index(), refusalUndoIndex);
        QCOMPARE(document.revision(), refusalRevision);
        QVERIFY(songdocument_test::notePairsConsistent(document, track));
    }

    // Identical-twin paste notes in one group refuse identically.
    {
        SongDocument::RangeEdit twins = edit;
        twins.addNotes.push_back({track,
                                  {{Tick(base + step * 44), 66, step * 2, 90},
                                   {Tick(base + step * 44), 66, step * 2, 90}}});
        const int twinsUndo = document.undoStack()->count();
        const uint64_t twinsRevision = document.revision();
        document.applyRangeEdit(QStringLiteral("identical twins"), twins);
        QCOMPARE(document.smf().write(), baseline);
        QCOMPARE(document.engineTrackCount(), trackCountBefore);
        QCOMPARE(document.undoStack()->count(), twinsUndo);
        QCOMPARE(document.revision(), twinsRevision);
        QVERIFY(songdocument_test::notePairsConsistent(document, track));
    }

    // Disjoint groups onto a freshly expanded track accept, land, and undo
    // byte-exactly. Built fresh — the first paste is still applied after
    // redo, so copying `edit` would re-write its same destination.
    {
        SongDocument::RangeEdit expansion;
        // The destination is always the next new engine track after the
        // pre-edit count, so every corpus row expands by exactly one track.
        const int expansionTrack = trackCountBefore;
        expansion.minimumEngineTrackCount = expansionTrack + 1;
        expansion.addNotes.push_back(
            {expansionTrack, {{Tick(base + step * 40), 67, step * 2, 90}}});
        document.applyRangeEdit(QStringLiteral("expansion paste"), expansion);
        QCOMPARE(document.engineTrackCount(), trackCountBefore + 1);
        DocNote landed;
        QVERIFY(document.findNote(expansionTrack, base + step * 40, 67, &landed));
        QCOMPARE(document.undoStack()->count(), before + 2);
        document.undoStack()->undo();
        QCOMPARE(document.smf().write(), baseline);
        QCOMPARE(document.engineTrackCount(), trackCountBefore);
        document.undoStack()->redo();
        QVERIFY(document.findNote(expansionTrack, base + step * 40, 67, &landed));
    }
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
    // Stable note identity survives the accepted move; the stream stays
    // invariant-clean and the geometry matches the emitted endpoints.
    DocNote movedFirst;
    QVERIFY(document.findNote(track, base + step * 83, 60, &movedFirst));
    QCOMPARE(movedFirst.noteId, first.noteId);
    QVERIFY(songdocument_test::notePairsConsistent(document, track));

    // A left shift that would clamp both notes to tick zero collapses both
    // positive spans to zero length (their first note-on reaches tick 0
    // only when the shift is at least base + step * 85); the mixed move
    // refuses with notes, lane points and tempo untouched.
    const QByteArray moveBaseline = document.smf().write();
    const int refusedUndo = document.undoStack()->count();
    const int refusedUndoIndex = document.undoStack()->index();
    const uint64_t refusedRevision = document.revision();
    document.moveRange({first, second}, {point}, -int64_t(base + step * 85),
                       {songdocument_test::tempo(base + step * 84, 140)});
    QCOMPARE(document.smf().write(), moveBaseline);
    QCOMPARE(document.revision(), refusedRevision);
    QCOMPARE(document.undoStack()->count(), refusedUndo);
    QCOMPARE(document.undoStack()->index(), refusedUndoIndex);
    QVERIFY(document.findLanePoint(track, 7, base + step * 83, &point));
    QCOMPARE(point.value, 45);
    QVERIFY(songdocument_test::containsTempo(document,
                                             songdocument_test::tempo(base + step * 84, 140)));
    QVERIFY(songdocument_test::notePairsConsistent(document, track));

    // A left shift that collides one surviving span with a stationary
    // same-pitch note refuses as well. first sits at step*83 on key 60 up
    // to step*85; a stationary note under it refuses a right shift of the
    // pair.
    document.addNote(track, Tick(base + step * 90), 60, step * 2, 90);
    QCOMPARE(document.undoStack()->count(), refusedUndo + 1);
    DocNote survivor;
    QVERIFY(document.findNote(track, base + step * 90, 60, &survivor));
    const QByteArray stationaryBaseline = document.smf().write();
    const int stationaryUndo = document.undoStack()->count();
    document.moveRange({first}, {point}, int64_t(step) * 6, {});
    QCOMPARE(document.smf().write(), stationaryBaseline);
    QCOMPARE(document.undoStack()->count(), stationaryUndo);
    QVERIFY(document.findNote(track, base + step * 83, 60, &first));
    QCOMPARE(first.duration, step * 2);
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
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
