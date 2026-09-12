#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"

namespace {

// In-memory document with one channel track whose notes sit far below the
// tick ceiling: adoptSmf accepts the full Tick range a VLQ round-trip
// through makeDocument cannot stage.
bool adoptBoundaryDocument(SongDocument *document, QString *error)
{
    SmfFile smf;
    smf.tracks.push_back(songdocument_test::conductor());
    SmfTrack track;
    track.events.push_back(songdocument_test::channel(0x90, 0, 60, 100));
    track.events.push_back(songdocument_test::channel(0x90, 24, 60, 0));
    track.events.push_back(songdocument_test::channel(0x90, 48, 64, 100));
    track.events.push_back(songdocument_test::channel(0x90, 72, 64, 0));
    track.endTick = 96;
    smf.tracks.push_back(track);
    SongInfo song;
    song.label = QStringLiteral("note-move-boundary");
    return document->adoptSmf(std::move(smf), song, error);
}

} // namespace

void EditCheckTest::noteMoveOverlap_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteMoveOverlap()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "noteMoveOverlap: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNote(track, base + step * 90, 71, step * 4, 100);
    document.addNote(track, base + step * 88, 70, step * 4, 100);
    DocNote moving;
    DocNote stationary;
    QVERIFY(document.findNote(track, base + step * 88, 70, &moving));
    document.moveNotes({moving}, 0, 1);
    QVERIFY(document.findNote(track, base + step * 88, 71, &moving));
    QCOMPARE(moving.duration, step * 4);
    QVERIFY(document.findNote(track, base + step * 92, 71, &stationary));
    QCOMPARE(stationary.duration, step * 2);
    document.resizeNotes({moving}, step * 4);
    QVERIFY(document.findNote(track, base + step * 88, 71, &moving));
    QCOMPARE(moving.duration, step * 8);
    QVERIFY(!document.findNote(track, base + step * 92, 71, &stationary));
    document.addNote(track, base + step * 94, 71, step * 4, 100);
    QVERIFY(document.findNote(track, base + step * 88, 71, &moving));
    QCOMPARE(moving.duration, step * 6);
    QVERIFY(document.findNote(track, base + step * 94, 71, &stationary));
    QCOMPARE(stationary.duration, step * 4);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 88, 71, &moving));
    QCOMPARE(moving.duration, step * 8);
    QVERIFY(!document.findNote(track, base + step * 94, 71, &stationary));
    document.undoStack()->redo();
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
}

void EditCheckTest::noteMoveMerge_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteMoveMerge()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "noteMoveMerge: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNote(track, base + step * 100, 70, step * 4, 100);
    document.addNote(track, base + step * 100, 69, step * 2, 100);
    const int before = document.undoStack()->count();
    DocNote moving;
    DocNote stationary;
    QVERIFY(document.findNote(track, base + step * 100, 69, &moving));
    document.moveNotes({moving}, 0, 1, true);
    QVERIFY(document.findNote(track, base + step * 102, 70, &stationary));
    QCOMPARE(stationary.duration, step * 2);
    QVERIFY(document.findNote(track, base + step * 100, 70, &moving));
    document.moveNotes({moving}, 0, 1, true);
    QCOMPARE(document.undoStack()->count(), before + 1);
    QVERIFY(document.findNote(track, base + step * 100, 71, &moving));
    QCOMPARE(moving.duration, step * 2);
    QVERIFY(document.findNote(track, base + step * 100, 70, &stationary));
    QCOMPARE(stationary.duration, step * 4);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 100, 69, &moving));
    QVERIFY(document.findNote(track, base + step * 100, 70, &stationary));
    QCOMPARE(stationary.duration, step * 4);
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 100, 71, &moving));
    document.didSave(document.captureSaveSnapshot(), true);
    document.moveNotes({moving}, 0, 1, true);
    QCOMPARE(document.undoStack()->count(), before + 2);
    // An accumulated tick delta that no longer fits int64_t declines the
    // merge: both applied commands stay separate and undo individually.
    SongDocument boundary;
    QVERIFY2(adoptBoundaryDocument(&boundary, &error), qPrintable(error));
    DocNote edge;
    QVERIFY(boundary.findNote(0, 48, 64, &edge));
    const int mergeCount = boundary.undoStack()->count();
    boundary.moveNotes({edge}, INT64_MIN, 0, true);
    QVERIFY(boundary.findNote(0, 0, 64, &edge));
    boundary.moveNotes({edge}, -5, 1, true);
    QCOMPARE(boundary.undoStack()->count(), mergeCount + 2);
    QVERIFY(boundary.findNote(0, 0, 65, &edge));
    boundary.undoStack()->undo();
    QVERIFY(boundary.findNote(0, 0, 64, &edge));
    boundary.undoStack()->undo();
    QVERIFY(boundary.findNote(0, 48, 64, &edge));
    boundary.undoStack()->redo();
    boundary.undoStack()->redo();
    QVERIFY(boundary.findNote(0, 0, 65, &edge));

    // Same declined merge for the pitched-move command, driven by the
    // other fixture note (the first is still at its merged position).
    DocNote lowEdge;
    QVERIFY(boundary.findNote(0, 0, 60, &lowEdge));
    QVERIFY(boundary.moveNotesToPitches({lowEdge}, {uint8_t(61)}, INT64_MIN, true));
    QVERIFY(boundary.findNote(0, 0, 61, &lowEdge));
    QVERIFY(boundary.moveNotesToPitches({lowEdge}, {uint8_t(62)}, -5, true));
    QCOMPARE(boundary.undoStack()->count(), mergeCount + 4);
    QVERIFY(boundary.findNote(0, 0, 62, &lowEdge));
    boundary.undoStack()->undo();
    QVERIFY(boundary.findNote(0, 0, 61, &lowEdge));
    boundary.undoStack()->undo();
    QVERIFY(boundary.findNote(0, 0, 60, &lowEdge));
}

void EditCheckTest::noteMoveBatch_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteMoveBatch()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "noteMoveBatch: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();
    const uint64_t firstTick = base + step * 110;
    document.addNote(track, firstTick, 115, step * 4, 100);
    document.addNote(track, firstTick + step * 20, 117, step * 2, 90);
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(track, firstTick, 115, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 117, &second));

    const int before = document.undoStack()->count();
    const QByteArray beforeBytes = document.smf().write();
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(118), uint8_t(114)}, 0));
    QCOMPARE(document.undoStack()->count(), before + 1);
    QVERIFY(document.findNote(track, firstTick, 118, &first));
    QCOMPARE(first.duration, step * 4);
    QCOMPARE(first.velocity, uint8_t(100));
    QVERIFY(!document.findNote(track, firstTick, 115, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 114, &second));
    QCOMPARE(second.duration, step * 2);
    QCOMPARE(second.velocity, uint8_t(90));
    QVERIFY(!document.findNote(track, firstTick + step * 20, 117, &second));
    const QByteArray movedBytes = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), beforeBytes);
    QVERIFY(document.findNote(track, firstTick, 115, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 117, &second));
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), movedBytes);
    QVERIFY(document.findNote(track, firstTick, 118, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 114, &second));

    const int nudgeBefore = document.undoStack()->count();
    const QByteArray nudgeStart = document.smf().write();
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(119), uint8_t(115)}, 0, true));
    QVERIFY(document.findNote(track, firstTick, 119, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 115, &second));
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(120), uint8_t(116)}, 0, true));
    QCOMPARE(document.undoStack()->count(), nudgeBefore + 1);
    QVERIFY(document.findNote(track, firstTick, 120, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 116, &second));
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), nudgeStart);
    QVERIFY(document.findNote(track, firstTick, 118, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 114, &second));

    document.undoStack()->setClean();
    const QByteArray inverseStart = document.smf().write();
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(119), uint8_t(115)}, 0, true));
    const int afterUp = document.undoStack()->index();
    QVERIFY(document.findNote(track, firstTick, 119, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 115, &second));
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(118), uint8_t(114)}, 0, true));
    QCOMPARE(document.undoStack()->index(), afterUp);
    QVERIFY(document.findNote(track, firstTick, 118, &first));
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), inverseStart);
}

void EditCheckTest::noteMoveCollision_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteMoveCollision()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "noteMoveCollision: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNote(track, base + step * 140, 119, step * 4, 100);
    document.addNote(track, base + step * 138, 118, step * 4, 100);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    DocNote moving;
    DocNote stationary;
    QVERIFY(document.findNote(track, base + step * 138, 118, &moving));
    QVERIFY(document.findNote(track, base + step * 140, 119, &stationary));
    // Batch pitch moves rewrite the selected note-on and may mint its
    // identity. The trimmed, unselected neighbor must retain its identity.
    const NoteId stationaryId = stationary.noteId;
    const QByteArray collisionStart = document.smf().write();
    const int collisionStartIndex = document.undoStack()->index();

    // Tail kept: a pitch move onto another note's head trims the
    // covered note instead of swallowing it.
    QVERIFY(document.moveNotesToPitches({moving}, {uint8_t(119)}, 0));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(document.findNote(track, base + step * 138, 119, &moving));
    QCOMPARE(moving.duration, step * 4);
    QVERIFY(document.findNote(track, base + step * 142, 119, &stationary));
    QCOMPARE(stationary.noteId, stationaryId);
    QCOMPARE(stationary.duration, step * 2);
    QVERIFY(!document.findNote(track, base + step * 138, 118, &moving));
    QVERIFY(!document.findNote(track, base + step * 140, 119, &stationary));

    // The trim is part of the move's own undo command: one undo
    // puts both notes back at their original keys and durations.
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 138, 118, &moving));
    QCOMPARE(moving.duration, step * 4);
    QVERIFY(document.findNote(track, base + step * 140, 119, &stationary));
    QCOMPARE(stationary.noteId, stationaryId);
    QCOMPARE(stationary.duration, step * 4);
    document.undoStack()->redo();

    // Fully covered: moving forward across all of the trimmed
    // note removes it.
    QVERIFY(document.findNote(track, base + step * 138, 119, &moving));
    QVERIFY(document.moveNotesToPitches({moving}, {uint8_t(119)}, int64_t(step) * 2));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(document.findNote(track, base + step * 140, 119, &moving));
    QCOMPARE(moving.duration, step * 4);
    const QByteArray collisionEnd = document.smf().write();
    const int collisionEndIndex = document.undoStack()->index();
    while (document.undoStack()->index() > collisionStartIndex)
        document.undoStack()->undo();
    QCOMPARE(document.smf().write(), collisionStart);
    QVERIFY(document.findNote(track, base + step * 140, 119, &stationary));
    QCOMPARE(stationary.noteId, stationaryId);
    while (document.undoStack()->index() < collisionEndIndex)
        document.undoStack()->redo();
    QCOMPARE(document.smf().write(), collisionEnd);
    QVERIFY(!document.findNote(track, base + step * 142, 119, &stationary));
}

void EditCheckTest::noteMoveRejects_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteMoveRejects()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "noteMoveRejects: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();
    const uint64_t firstTick = base + step * 110;
    document.addNote(track, firstTick, 115, step * 4, 100);
    document.addNote(track, firstTick + step * 20, 117, step * 2, 90);
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(track, firstTick, 115, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 117, &second));

    const QByteArray baseline = document.smf().write();
    const int before = document.undoStack()->count();
    QVERIFY(!document.moveNotesToPitches({first}, {uint8_t(130)}, 0));
    QVERIFY(!document.moveNotesToPitches({first}, {}, 0));
    QVERIFY(!document.moveNotesToPitches({}, {uint8_t(118)}, 0));
    QCOMPARE(document.undoStack()->count(), before);
    QCOMPARE(document.smf().write(), baseline);
    QVERIFY(document.findNote(track, firstTick, 115, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 117, &second));
    // Synthetic boundary document: adoptSmf stages full-range ticks.
    SongDocument boundary;
    QVERIFY2(adoptBoundaryDocument(&boundary, &error), qPrintable(error));
    DocNote edge;
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    const QByteArray boundaryBaseline = boundary.smf().write();
    const uint64_t boundaryRevision = boundary.revision();
    const int boundaryUndoCount = boundary.undoStack()->count();

    // A requested upper start shift or a terminated end past kMaxTick
    // rejects the whole move without touching the document.
    boundary.moveNotes({edge}, INT64_MAX, 0);
    boundary.moveNotes({edge}, int64_t(CoreTimeDefaults::kMaxTick) - 23, 0);
    QCOMPARE(boundary.smf().write(), boundaryBaseline);
    QCOMPARE(boundary.revision(), boundaryRevision);
    QCOMPARE(boundary.undoStack()->count(), boundaryUndoCount);

    // The pitched move reports the same rejections on its return value.
    QVERIFY(!boundary.moveNotesToPitches({edge}, {uint8_t(62)}, INT64_MAX));
    QVERIFY(!boundary.moveNotesToPitches({edge}, {uint8_t(62)},
                                         int64_t(CoreTimeDefaults::kMaxTick) - 23));
    QCOMPARE(boundary.smf().write(), boundaryBaseline);
    QCOMPARE(boundary.undoStack()->count(), boundaryUndoCount);

    // One invalid destination rejects every member of the batch.
    DocNote secondEdge;
    QVERIFY(boundary.findNote(0, 48, 64, &secondEdge));
    boundary.moveNotes({edge, secondEdge}, int64_t(CoreTimeDefaults::kMaxTick) - 47, 0);
    QCOMPARE(boundary.smf().write(), boundaryBaseline);
    QCOMPARE(boundary.undoStack()->count(), boundaryUndoCount);

    // An end landing exactly at kMaxTick is admitted and survives undo/redo.
    boundary.moveNotes({edge}, int64_t(CoreTimeDefaults::kMaxTick) - 24, 0);
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 24, 60, &edge));
    QCOMPARE(edge.duration, uint32_t(24));
    boundary.undoStack()->undo();
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    boundary.undoStack()->redo();
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 24, 60, &edge));

    // An extreme negative delta still clamps the start at zero.
    boundary.moveNotes({edge}, INT64_MIN, 0);
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    QCOMPARE(edge.duration, uint32_t(24));
}
