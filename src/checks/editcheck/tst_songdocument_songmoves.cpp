#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"

void EditCheckTest::noteMoveOverlapRefuses_data()
{
    addSongRows(SongCapability::EditableTrack);
}

// Uniform atomic refusal: a move that would land a note on a same-key
// stationary span refuses with absolutely no document change.
void EditCheckTest::noteMoveOverlapRefuses()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "noteMoveOverlapRefuses: corpus staged no song eligible for this required contract");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNote(track, base + step * 96, 70, step * 4, 100);
    document.addNote(track, base + step * 88, 70, step * 4, 100);
    DocNote moving;
    DocNote stationary;
    QVERIFY(document.findNote(track, base + step * 88, 70, &moving));
    QVERIFY(document.findNote(track, base + step * 96, 70, &stationary));
    const NoteId stationaryId = stationary.noteId;
    const NoteId movingId = moving.noteId;
    const QByteArray baseline = document.smf().write();
    const int commandsBefore = document.undoStack()->count();
    const int indexBefore = document.undoStack()->index();
    const uint64_t revisionBefore = document.revision();

    // A same-key move landing over the neighbor's span refuses.
    document.moveNotes({moving}, int64_t(step) * 6, 0);
    QVERIFY(!document.findNote(track, base + step * 94, 70, &moving));

    // A resize whose end would reach into the neighbor refuses equally
    // (never capped to the free space).
    document.resizeNotes({moving}, int64_t(step) * 8);
    QVERIFY(document.findNote(track, base + step * 88, 70, &moving));
    QCOMPARE(moving.duration, step * 4);

    // An addNote overlapping the stationary note refuses.
    document.addNote(track, base + step * 90, 70, step * 4, 100);
    QVERIFY(!document.findNote(track, base + step * 90, 70, &moving));

    QCOMPARE(document.smf().write(), baseline);
    QCOMPARE(document.undoStack()->count(), commandsBefore);
    QCOMPARE(document.undoStack()->index(), indexBefore);
    QCOMPARE(document.revision(), revisionBefore);
    QVERIFY(document.findNote(track, base + step * 88, 70, &moving));
    QCOMPARE(moving.noteId, movingId);
    QCOMPARE(moving.velocity, uint8_t(100));
    QVERIFY(document.findNote(track, base + step * 96, 70, &stationary));
    QCOMPARE(stationary.noteId, stationaryId);
    QCOMPARE(stationary.duration, step * 4);
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
}

void EditCheckTest::noteMoveMerge_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteMoveMerge()
{
    // Lower-bound tick, pitch, and per-pitch time clamps do not compose
    // with a reversing press. Each accepted landing must remain visible.
    for (int mode = 0; mode < 3; ++mode) {
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        smf.tracks.push_back(songdocument_test::conductor());
        smf.tracks.push_back({{
                                  songdocument_test::channel(0xC0, 0, 1, 0),
                                  songdocument_test::channel(0x90, 10, 3, 100),
                                  songdocument_test::channel(0x90, 20, 3, 0),
                              },
                              24});
        auto fixture =
            songdocument_test::makeDocument(std::move(smf), QStringLiteral("move-clamp-reversal"));
        QVERIFY(fixture);
        SongDocument &doc = fixture->document;
        DocNote note;
        QVERIFY(doc.findNote(0, 10, 3, &note));
        const NoteId id = note.noteId;
        const QByteArray start = doc.smf().write();
        const int commands = doc.undoStack()->count();
        if (mode == 2)
            QVERIFY(doc.moveNotesToPitches({note}, {3}, -20, true));
        else
            doc.moveNotes({note}, mode == 0 ? -20 : 0, mode == 1 ? -10 : 0, true);
        QVERIFY(doc.findNote(id, &note));
        QCOMPARE(note.tick, Tick(mode == 1 ? 10 : 0));
        QCOMPARE(note.key, uint8_t(mode == 1 ? 0 : 3));
        QCOMPARE(note.duration, uint32_t(10));
        const QByteArray clamped = doc.smf().write();
        if (mode == 2)
            QVERIFY(doc.moveNotesToPitches({note}, {3}, 5, true));
        else
            doc.moveNotes({note}, mode == 0 ? 5 : 0, mode == 1 ? 2 : 0, true);
        QCOMPARE(doc.undoStack()->count(), commands + 2);
        QVERIFY(doc.findNote(id, &note));
        QCOMPARE(note.tick, Tick(mode == 1 ? 10 : 5));
        QCOMPARE(note.key, uint8_t(mode == 1 ? 2 : 3));
        QCOMPARE(note.duration, uint32_t(10));
        const QByteArray final = doc.smf().write();
        QVERIFY(songdocument_test::notePairsConsistent(doc, 0));
        doc.undoStack()->undo();
        QCOMPARE(doc.smf().write(), clamped);
        QVERIFY(doc.findNote(id, &note));
        doc.undoStack()->undo();
        QCOMPARE(doc.smf().write(), start);
        QVERIFY(doc.findNote(id, &note));
        QCOMPARE(note.tick, Tick(10));
        QCOMPARE(note.key, uint8_t(3));
        doc.undoStack()->redo();
        QCOMPARE(doc.smf().write(), clamped);
        doc.undoStack()->redo();
        QCOMPARE(doc.smf().write(), final);
        QVERIFY(doc.findNote(id, &note));
        QCOMPARE(note.tick, Tick(mode == 1 ? 10 : 5));
        QCOMPARE(note.key, uint8_t(mode == 1 ? 2 : 3));
        QVERIFY(songdocument_test::notePairsConsistent(doc, 0));
    }

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
    DocNote moving;
    QVERIFY(document.findNote(track, base + step * 100, 69, &moving));
    // Routed through free pitches: every landing is admitted, so the
    // keyboard presses merge as one gesture instead of refusing.
    const int before = document.undoStack()->count();
    document.moveNotes({moving}, 0, 2, true);
    QVERIFY(document.findNote(track, base + step * 100, 71, &moving));
    document.moveNotes({moving}, 0, 2, true);
    QCOMPARE(document.undoStack()->count(), before + 1);
    QVERIFY(document.findNote(track, base + step * 100, 73, &moving));
    QCOMPARE(moving.duration, step * 2);
    QVERIFY(document.findNote(track, base + step * 100, 70, &moving));
    QCOMPARE(moving.duration, step * 4);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 100, 69, &moving));
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 100, 73, &moving));
    QCOMPARE(moving.duration, step * 2);
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
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
    // Per-pitch moves must not remint identities: the moved notes keep
    // their exact NoteIds through every landing.
    const NoteId firstId = first.noteId;
    const NoteId secondId = second.noteId;

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
    QCOMPARE(first.noteId, firstId);
    QCOMPARE(second.noteId, secondId);
    const QByteArray movedBytes = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), beforeBytes);
    QVERIFY(document.findNote(track, firstTick, 115, &first));
    QCOMPARE(first.noteId, firstId);
    QVERIFY(document.findNote(track, firstTick + step * 20, 117, &second));
    QCOMPARE(second.noteId, secondId);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), movedBytes);
    QVERIFY(document.findNote(track, firstTick, 118, &first));
    QCOMPARE(first.noteId, firstId);
    QVERIFY(document.findNote(track, firstTick + step * 20, 114, &second));
    QCOMPARE(second.noteId, secondId);

    const int nudgeBefore = document.undoStack()->count();
    const QByteArray nudgeStart = document.smf().write();
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(119), uint8_t(115)}, 0, true));
    QVERIFY(document.findNote(track, firstTick, 119, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 115, &second));
    // Reordered selection: destinations must follow NoteIds, not the
    // original vector positions retained by the merged command.
    QVERIFY(document.moveNotesToPitches({second, first}, {uint8_t(116), uint8_t(120)}, 0, true));
    QCOMPARE(document.undoStack()->count(), nudgeBefore + 1);
    QVERIFY(document.findNote(track, firstTick, 120, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 116, &second));
    QCOMPARE(first.noteId, firstId);
    QCOMPARE(second.noteId, secondId);
    const QByteArray nudgeFinal = document.smf().write();
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), nudgeStart);
    QVERIFY(document.findNote(track, firstTick, 118, &first));
    QCOMPARE(first.noteId, firstId);
    QVERIFY(document.findNote(track, firstTick + step * 20, 114, &second));
    QCOMPARE(second.noteId, secondId);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), nudgeFinal);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.key, uint8_t(120));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.key, uint8_t(116));
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), nudgeStart);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));

    document.undoStack()->setClean();
    const QByteArray inverseStart = document.smf().write();
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(119), uint8_t(115)}, 0, true));
    const int afterUp = document.undoStack()->index();
    QVERIFY(document.findNote(track, firstTick, 119, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 115, &second));
    int changeCount = 0;
    QObject::connect(&document, &SongDocument::documentChanged, [&changeCount] { ++changeCount; });
    // The inverse press makes the accumulated delta zero; the merged
    // command is obsoleted (handled as zero-delta/no-history), so the
    // stack's index drops by one and the bytes are already back at the
    // gesture start. No separate undo may follow — that would pop the
    // preceding clean-barrier command.
    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(118), uint8_t(114)}, 0, true));
    QCOMPARE(document.undoStack()->index(), afterUp - 1);
    QCOMPARE(document.smf().write(), inverseStart);
    QVERIFY(document.findNote(track, firstTick, 118, &first));
    QVERIFY(document.findNote(track, firstTick + step * 20, 114, &second));
    QCOMPARE(first.noteId, firstId);
    QCOMPARE(second.noteId, secondId);
    // The net-zero merge still publishes the restored state: the inverse
    // press's own redo emits once as it lands, and the merge's revert
    // emits one balanced closing notification.
    QCOMPARE(changeCount, 2);
}

void EditCheckTest::noteMoveCollision_data()
{
    addSongRows(SongCapability::EditableTrack);
}

// Per-pitch convergence refuses atomically: the stationary note keeps its
// exact identity, span and velocity, and nothing enters the undo stack.
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
    const NoteId stationaryId = stationary.noteId;
    const NoteId movingId = moving.noteId;
    const QByteArray collisionStart = document.smf().write();
    const int commandsBefore = document.undoStack()->count();
    const int indexBefore = document.undoStack()->index();
    const uint64_t revisionBefore = document.revision();

    // A pitch move onto the neighbor's head refuses.
    QVERIFY(!document.moveNotesToPitches({moving}, {uint8_t(119)}, 0));
    // A forward move that would fully cover the neighbor refuses equally.
    QVERIFY(!document.moveNotesToPitches({moving}, {uint8_t(119)}, int64_t(step) * 2));
    // A plain move that converges refuses too.
    document.moveNotes({moving}, int64_t(step) * 2, 1);

    // The three refusals above left everything untouched.
    QCOMPARE(document.smf().write(), collisionStart);
    QCOMPARE(document.undoStack()->count(), commandsBefore);
    QCOMPARE(document.undoStack()->index(), indexBefore);
    QCOMPARE(document.revision(), revisionBefore);
    QVERIFY(document.moveNotesToPitches({moving}, {uint8_t(117)}, 0));
    QVERIFY(document.findNote(track, base + step * 138, 117, &moving));
    QCOMPARE(moving.noteId, movingId);
    QCOMPARE(moving.duration, step * 4);
    QVERIFY(document.findNote(track, base + step * 140, 119, &stationary));
    QCOMPARE(stationary.noteId, stationaryId);
    QCOMPARE(stationary.duration, step * 4);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 138, 118, &moving));
    QCOMPARE(moving.noteId, movingId);
    QCOMPARE(stationary.noteId, stationaryId);
    QCOMPARE(document.smf().write(), collisionStart);
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
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

// Stable identity through scale-fold style per-pitch moves, including an
// unterminated participant: ids survive, bytes round-trip, convergent
// destinations refuse.
void EditCheckTest::noteIdentityStable()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(songdocument_test::conductor());
    SmfTrack notes;
    notes.events = {
        songdocument_test::channel(0xC0, 0, 1, 0),
        songdocument_test::channel(0x90, 0, 0, 100),
        songdocument_test::channel(0x90, 8, 0, 0),
        songdocument_test::channel(0x90, 12, 2, 90),
    };
    notes.endTick = 24;
    smf.tracks.push_back(notes);
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("identity-stable"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    DocNote terminated;
    DocNote unterminated;
    QVERIFY(document.findNote(0, 0, 0, &terminated));
    QVERIFY(document.findNote(0, 12, 2, &unterminated));
    QVERIFY(unterminated.unterminated());
    const NoteId terminatedId = terminated.noteId;
    const NoteId unterminatedId = unterminated.noteId;
    const int before = document.undoStack()->count();

    // Move both participants in one per-pitch batch onto free keys.
    QVERIFY(document.moveNotesToPitches({terminated, unterminated}, {uint8_t(4), uint8_t(6)}, 0));
    QVERIFY(document.findNote(terminatedId, &terminated));
    QCOMPARE(terminated.key, uint8_t(4));
    QCOMPARE(terminated.duration, uint32_t(8));
    QCOMPARE(terminated.velocity, uint8_t(100));
    QVERIFY(document.findNote(unterminatedId, &unterminated));
    QCOMPARE(unterminated.key, uint8_t(6));
    QVERIFY(unterminated.unterminated());
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findNote(terminatedId, &terminated));
    QCOMPARE(terminated.key, uint8_t(0));
    QVERIFY(document.findNote(unterminatedId, &unterminated));
    QCOMPARE(unterminated.key, uint8_t(2));
    document.undoStack()->redo();
    QVERIFY(document.findNote(terminatedId, &terminated));
    QCOMPARE(terminated.key, uint8_t(4));
    QVERIFY(document.findNote(unterminatedId, &unterminated));
    QCOMPARE(unterminated.key, uint8_t(6));
    // Convergent destinations refuse: two participants sent onto one key
    // collapse into identical duplicate spans — the batch refuses
    // atomically and leaves every note untouched.
    document.addNote(0, 20, 9, 4, 70);
    document.addNote(0, 20, 10, 4, 71);
    DocNote ninth;
    DocNote tenth;
    QVERIFY(document.findNote(0, 20, 9, &ninth));
    QVERIFY(document.findNote(0, 20, 10, &tenth));
    const NoteId ninthId = ninth.noteId;
    const NoteId tenthId = tenth.noteId;
    const QByteArray baseline = document.smf().write();
    const int commandsNow = document.undoStack()->count();
    const int indexNow = document.undoStack()->index();
    QVERIFY(!document.moveNotesToPitches({ninth, tenth}, {uint8_t(4), uint8_t(4)}, 0));
    QCOMPARE(document.undoStack()->count(), commandsNow);
    QCOMPARE(document.undoStack()->index(), indexNow);
    QCOMPARE(document.smf().write(), baseline);

    // An unchanged destination for a note's own pitch is still admissible
    // and produces no new command.
    QVERIFY(document.moveNotesToPitches({ninth}, {uint8_t(9)}, 0));
    QCOMPARE(document.undoStack()->count(), commandsNow);
    QCOMPARE(document.undoStack()->index(), indexNow);
    QCOMPARE(document.smf().write(), baseline);
    QVERIFY(document.findNote(ninthId, &ninth));
    QCOMPARE(ninth.noteId, ninthId);
    QVERIFY(document.findNote(tenthId, &tenth));
    QCOMPARE(tenth.noteId, tenthId);
    // notePairsConsistent is deliberately not asserted here: this fixture
    // intentionally contains an unterminated raw note-on, which the clean
    // fully-paired oracle excludes by contract.

    // The next press on a moved unterminated participant must still merge:
    // the builder moves its note-on (shifted tick, destination key), so a
    // repeat press matched at the moved position folds into one command —
    // not a separate second gesture.
    const int mergesBefore = document.undoStack()->count();
    const QByteArray gestureBytes = document.smf().write();
    QVERIFY(document.moveNotesToPitches({unterminated}, {uint8_t(7)}, 0, true));
    QCOMPARE(document.undoStack()->count(), mergesBefore + 1);
    QVERIFY(document.findNote(unterminatedId, &unterminated));
    QCOMPARE(unterminated.key, uint8_t(7));
    QCOMPARE(unterminated.tick, Tick(12));
    QVERIFY(document.moveNotesToPitches({unterminated}, {uint8_t(8)}, 0, true));
    QCOMPARE(document.undoStack()->count(), mergesBefore + 1);
    QVERIFY(document.findNote(unterminatedId, &unterminated));
    QCOMPARE(unterminated.key, uint8_t(8));
    QCOMPARE(unterminated.tick, Tick(12));
    document.undoStack()->undo();
    QVERIFY(document.findNote(unterminatedId, &unterminated));
    QCOMPARE(unterminated.key, uint8_t(6));
    QCOMPARE(document.smf().write(), gestureBytes);

    // A rewritten raw note-on has no end to validate, but its start
    // still must refuse positive overflow rather than cap at kMaxTick.
    const QByteArray overflowStart = document.smf().write();
    const int overflowCount = document.undoStack()->count();
    const int overflowIndex = document.undoStack()->index();
    const uint64_t overflowRevision = document.revision();
    QVERIFY(!document.moveNotesToPitches({unterminated}, {uint8_t(9)},
                                         int64_t(CoreTimeDefaults::kMaxTick), true));
    QCOMPARE(document.smf().write(), overflowStart);
    QCOMPARE(document.undoStack()->count(), overflowCount);
    QCOMPARE(document.undoStack()->index(), overflowIndex);
    QCOMPARE(document.revision(), overflowRevision);
    QVERIFY(document.findNote(unterminatedId, &unterminated));
    QCOMPARE(unterminated.tick, Tick(12));
    QCOMPARE(unterminated.key, uint8_t(6));
    QCOMPARE(unterminated.velocity, uint8_t(90));
    QVERIFY(unterminated.unterminated());
}

void EditCheckTest::noteMoveBatchTime_data()
{
    addSongRows(SongCapability::EditableTrack);
}

// Accepted two-note same-track time move: both notes change ticks in one
// command on the same SMF track — the case the interleaved remove/insert
// plan used to corrupt. Every NoteId's final tick/key/duration/velocity is
// asserted, plus tracksSorted, notePairsConsistent, exact bytes and
// undo/redo round-trip.
void EditCheckTest::noteMoveBatchTime()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(),
             "noteMoveBatchTime: corpus staged no song eligible for this required contract");

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
    const NoteId firstId = first.noteId;
    const NoteId secondId = second.noteId;
    const int commandsBefore = document.undoStack()->count();
    const QByteArray beforeBytes = document.smf().write();

    QVERIFY(document.moveNotesToPitches({first, second}, {uint8_t(115), uint8_t(117)},
                                        int64_t(step) * 8));
    QCOMPARE(document.undoStack()->count(), commandsBefore + 1);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.tick, Tick(firstTick + step * 8));
    QCOMPARE(first.key, uint8_t(115));
    QCOMPARE(first.duration, step * 4);
    QCOMPARE(first.velocity, uint8_t(100));
    QCOMPARE(first.engineTrack, track);
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.tick, Tick(firstTick + step * 20 + step * 8));
    QCOMPARE(second.key, uint8_t(117));
    QCOMPARE(second.duration, step * 2);
    QCOMPARE(second.velocity, uint8_t(90));
    QCOMPARE(second.engineTrack, track);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
    const QByteArray movedBytes = document.smf().write();

    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), beforeBytes);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.tick, Tick(firstTick));
    QCOMPARE(first.key, uint8_t(115));
    QCOMPARE(first.duration, step * 4);
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.tick, Tick(firstTick + step * 20));
    QCOMPARE(second.key, uint8_t(117));
    QCOMPARE(second.duration, step * 2);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), movedBytes);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.tick, Tick(firstTick + step * 8));
    QCOMPARE(first.duration, step * 4);
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.tick, Tick(firstTick + step * 28));
    QCOMPARE(second.duration, step * 2);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
}
