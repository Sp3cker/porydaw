#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"

void EditCheckTest::noteEditingBasic_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteEditingBasic()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for basic note editing");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNote(track, base, 60, step * 4, 100);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    DocNote note;
    QVERIFY(document.findNote(track, base, 60, &note));
    document.moveNotes({note}, int64_t(step) * 8, 3);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(document.findNote(track, base + step * 8, 63, &note));
    document.resizeNotes({note}, int64_t(step) * 2);
    QVERIFY(document.findNote(track, base + step * 8, 63, &note));
    QCOMPARE(note.duration, step * 6);
    document.resizeNotesLeft({note}, -int64_t(step) * 2);
    QVERIFY(document.findNote(track, base + step * 6, 63, &note));
    QCOMPARE(note.duration, step * 8);
    document.resizeNotesLeft({note}, int64_t(step) * 100);
    QVERIFY(document.findNote(track, base + step * 14 - 1, 63, &note));
    QCOMPARE(note.duration, uint32_t(1));
    document.resizeNotesLeft({note}, -int64_t(step) * 8 + 1);
    QVERIFY(document.findNote(track, base + step * 6, 63, &note));
    QCOMPARE(note.duration, step * 8);
    document.setNotesVelocity({note}, 88);
    QVERIFY(document.findNote(track, base + step * 6, 63, &note));
    QCOMPARE(note.velocity, uint8_t(88));
    document.nudgeNotesVelocity({note}, -30);
    QVERIFY(document.findNote(track, base + step * 6, 63, &note));
    QCOMPARE(note.velocity, uint8_t(58));
    document.nudgeNotesVelocity({note}, 200);
    QVERIFY(document.findNote(track, base + step * 6, 63, &note));
    QCOMPARE(note.velocity, uint8_t(127));
    document.deleteNotes({note});
    QVERIFY(!document.findNote(track, base + step * 6, 63, &note));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
}

void EditCheckTest::noteEditingBatch_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteEditingBatch()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for batch note editing");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    const int before = document.undoStack()->count();
    document.addNotes(track, {{Tick(base + step * 20), 64, step * 2, 96},
                              {Tick(base + step * 22), 67, step * 2, 96}});
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(track, base + step * 20, 64, &first));
    QVERIFY(document.findNote(track, base + step * 22, 67, &second));
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(!document.findNote(track, base + step * 20, 64, &first));
    QVERIFY(!document.findNote(track, base + step * 22, 67, &second));
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 20, 64, &first));
    QVERIFY(document.findNote(track, base + step * 22, 67, &second));
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
    // Identical twin spans in one batch refuse atomically.
    const int twinsBefore = document.undoStack()->count();
    const uint64_t twinsRevision = document.revision();
    document.addNotes(track, {{Tick(base + step * 40), 70, step * 2, 90},
                              {Tick(base + step * 40), 70, step * 2, 90}});
    QVERIFY(!document.findNote(track, base + step * 40, 70, &first));
    QCOMPARE(document.undoStack()->count(), twinsBefore);
    QCOMPARE(document.revision(), twinsRevision);
    QVERIFY(songdocument_test::notePairsConsistent(document, track));
}

void EditCheckTest::noteEditingAbutting_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::noteEditingAbutting()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for abutting notes");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    // The seam sits at base+30step (old suite used 2step inside a shared
    // document); every offset this slot touches is disjoint within its
    // own fresh document, so no pairing boundary contract is lost.
    const uint64_t seam = base + step * 30;
    document.addNote(track, seam, 60, step * 2, 100);
    document.addNote(track, seam - step * 2, 60, step * 2, 100);
    DocNote left;
    DocNote right;
    QVERIFY(document.findNote(track, seam - step * 2, 60, &left));
    QVERIFY(document.findNote(track, seam, 60, &right));
    QCOMPARE(left.duration, step * 2);
    QCOMPARE(right.duration, step * 2);
    QVERIFY(left.endIndex != right.endIndex);
    document.deleteNotes({left, right});
    for (const SmfEvent &event :
         document.smf().tracks[size_t(document.smfTrackFor(track))].events) {
        QVERIFY(!(event.isChannel() && event.tick >= seam - step * 2 &&
                  (event.isNoteOn() || event.isNoteEnd())));
    }
}

// Grouped admission: overlapping same-key spans inside one batch refuse
// atomically — including identical twin spans — while disjoint and
// adjacent batches accept.
void EditCheckTest::noteBatchCollisionRejects()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(songdocument_test::conductor());
    smf.tracks.push_back({{songdocument_test::channel(0xC0, 0, 1, 0)}, 8});
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("batch-collision"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const int before = document.undoStack()->count();
    const uint64_t revisionBefore = document.revision();

    // Overlapping same-key spans within one batch refuse.
    document.addNotes(0, {{Tick(10), 60, 8, 100}, {Tick(14), 60, 8, 100}});
    DocNote probe;
    QVERIFY(!document.findNote(0, 10, 60, &probe));
    QCOMPARE(document.undoStack()->count(), before);
    QCOMPARE(document.revision(), revisionBefore);

    // Identical twin spans refuse — the former duplicate carve-out is
    // gone everywhere, including addNotes.
    document.addNotes(0, {{Tick(10), 60, 8, 100}, {Tick(10), 60, 8, 100}});
    QVERIFY(!document.findNote(0, 10, 60, &probe));

    // A member colliding with an already-admitted stationary note refuses
    // the whole batch before anything is inserted.
    document.addNote(0, 100, 62, 4, 100);
    const int withSeed = document.undoStack()->count();
    document.addNotes(0, {{Tick(20), 65, 8, 100}, {Tick(98), 62, 8, 100}});
    QVERIFY(!document.findNote(0, 20, 65, &probe));
    QCOMPARE(document.undoStack()->count(), withSeed);

    // Disjoint and adjacent batches accept.
    document.addNotes(0, {{Tick(20), 65, 8, 100}, {Tick(28), 65, 8, 100}});
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(0, 20, 65, &first));
    QVERIFY(document.findNote(0, 28, 65, &second));
    QCOMPARE(first.duration, uint32_t(8));
    QCOMPARE(second.duration, uint32_t(8));
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));
}

// Grouped right-edge resize accepted in free space: both ends move in one
// command with exact per-note outcomes, tracksSorted, notePairsConsistent,
// exact bytes and undo/redo round-trip.
void EditCheckTest::noteGroupedResizeAccepts()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(songdocument_test::conductor());
    SmfTrack notes;
    notes.events = {
        songdocument_test::channel(0xC0, 0, 1, 0),  songdocument_test::channel(0x90, 0, 0, 100),
        songdocument_test::channel(0x90, 10, 0, 0), songdocument_test::channel(0x90, 20, 5, 90),
        songdocument_test::channel(0x90, 30, 5, 0),
    };
    notes.endTick = 40;
    smf.tracks.push_back(notes);
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("grouped-resize-accept"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(0, 0, 0, &first));
    QVERIFY(document.findNote(0, 20, 5, &second));
    const NoteId firstId = first.noteId;
    const NoteId secondId = second.noteId;
    const int commandsBefore = document.undoStack()->count();
    const uint64_t revisionBefore = document.revision();
    const QByteArray beforeBytes = document.smf().write();

    document.resizeNotes({first, second}, 10);
    QCOMPARE(document.undoStack()->count(), commandsBefore + 1);
    QCOMPARE(document.revision(), revisionBefore + 1);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.tick, Tick(0));
    QCOMPARE(first.key, uint8_t(0));
    QCOMPARE(first.duration, uint32_t(20));
    QCOMPARE(first.velocity, uint8_t(100));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.tick, Tick(20));
    QCOMPARE(second.key, uint8_t(5));
    QCOMPARE(second.duration, uint32_t(20));
    QCOMPARE(second.velocity, uint8_t(90));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));
    const QByteArray resizedBytes = document.smf().write();

    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), beforeBytes);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(10));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(10));
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), resizedBytes);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(20));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(20));
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));

    // Minimum-duration clamping followed by lengthening must preserve the
    // sequential result, not reapply a non-composing accumulated delta.
    const int clampCommands = document.undoStack()->count();
    const QByteArray clampStart = document.smf().write();
    document.resizeNotes({first, second}, -40, true);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.duration, uint32_t(1));
    QCOMPARE(second.duration, uint32_t(1));
    const QByteArray minimumBytes = document.smf().write();
    document.resizeNotes({first, second}, 5, true);
    QCOMPARE(document.undoStack()->count(), clampCommands + 2);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.duration, uint32_t(6));
    QCOMPARE(second.duration, uint32_t(6));
    QCOMPARE(first.tick, Tick(0));
    QCOMPARE(second.tick, Tick(20));
    const QByteArray reversedBytes = document.smf().write();
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), minimumBytes);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), clampStart);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.duration, uint32_t(20));
    QCOMPARE(second.duration, uint32_t(20));
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), minimumBytes);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), reversedBytes);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.duration, uint32_t(6));
    QCOMPARE(second.duration, uint32_t(6));
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));
}

// Grouped left-edge resize (resizeNotesLeft) on a two-note batch: both
// note-ons drift left in one command, ids and velocities intact.
void EditCheckTest::noteGroupedLeftResizeAccepts()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(songdocument_test::conductor());
    SmfTrack notes;
    notes.events = {
        songdocument_test::channel(0xC0, 0, 1, 0),  songdocument_test::channel(0x90, 10, 3, 100),
        songdocument_test::channel(0x90, 20, 3, 0), songdocument_test::channel(0x90, 30, 6, 90),
        songdocument_test::channel(0x90, 40, 6, 0),
    };
    notes.endTick = 48;
    smf.tracks.push_back(notes);
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("grouped-left-resize"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(0, 10, 3, &first));
    QVERIFY(document.findNote(0, 30, 6, &second));
    const NoteId firstId = first.noteId;
    const NoteId secondId = second.noteId;
    const int commandsBefore = document.undoStack()->count();
    const QByteArray beforeBytes = document.smf().write();

    document.resizeNotesLeft({first, second}, -5);
    QCOMPARE(document.undoStack()->count(), commandsBefore + 1);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.tick, Tick(5));
    QCOMPARE(first.key, uint8_t(3));
    QCOMPARE(first.duration, uint32_t(15));
    QCOMPARE(first.velocity, uint8_t(100));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.tick, Tick(25));
    QCOMPARE(second.key, uint8_t(6));
    QCOMPARE(second.duration, uint32_t(15));
    QCOMPARE(second.velocity, uint8_t(90));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));
    const QByteArray resizedBytes = document.smf().write();

    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), beforeBytes);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.tick, Tick(10));
    QCOMPARE(first.duration, uint32_t(10));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.tick, Tick(30));
    QCOMPARE(second.duration, uint32_t(10));
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), resizedBytes);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));
}

void EditCheckTest::noteResizeCollisionRejects()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(songdocument_test::conductor());
    SmfTrack notes;
    notes.events = {
        songdocument_test::channel(0xC0, 0, 1, 0),  songdocument_test::channel(0x90, 0, 0, 100),
        songdocument_test::channel(0x90, 10, 0, 0), songdocument_test::channel(0x90, 20, 0, 100),
        songdocument_test::channel(0x90, 30, 0, 0), songdocument_test::channel(0x90, 40, 0, 100),
        songdocument_test::channel(0x90, 50, 0, 0),
    };
    notes.endTick = 60;
    smf.tracks.push_back(notes);
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("resize-collision"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(0, 0, 0, &first));
    QVERIFY(document.findNote(0, 20, 0, &second));
    const NoteId firstId = first.noteId;
    const NoteId secondId = second.noteId;
    const int commandsBefore = document.undoStack()->count();
    const int indexBefore = document.undoStack()->index();
    const uint64_t revisionBefore = document.revision();
    const QByteArray baseline = document.smf().write();

    // Grouped right resize +20 would emit [0,30) and [20,50): both starts
    // would claim release 30. Refuses; never capped.
    document.resizeNotes({first, second}, 20);
    // Grouped left resize into the sibling refuses.
    document.resizeNotesLeft({second}, -15);
    // A single-note resize reaching a stationary note refuses equally.
    document.resizeNotes({second}, 15);

    QCOMPARE(document.smf().write(), baseline);
    QCOMPARE(document.undoStack()->count(), commandsBefore);
    QCOMPARE(document.undoStack()->index(), indexBefore);
    QCOMPARE(document.revision(), revisionBefore);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(10));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(10));
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));

    // Free-space single-note resize still admits, and undo restores bytes.
    document.resizeNotes({second}, 5);
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(15));
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), baseline);
    QVERIFY(songdocument_test::notePairsConsistent(document, 0));
}
