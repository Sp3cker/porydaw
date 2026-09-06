#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"

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
}
