#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <vector>

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
    document.addNotes(track,
                      {{base + step * 20, 64, step * 2, 96}, {base + step * 22, 67, step * 2, 96}});
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

// Section 6.1 of docs/keyboard-note-resize-plan.md: the mergeable resize
// history contract, defended at the document seam without keyboard routing.
// The fixture is synthetic so SMF bytes, NoteIds, and publication counts are
// deterministic: first (key 70, tick 0, 8 ticks), second (key 69, tick 0,
// 4 ticks), and a later same-pitch neighbor (key 70, tick 20, 8 ticks) whose
// head sits inside first's extension range.
void EditCheckTest::resizeNotesMergeableHistory()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(
        {{songdocument_test::channel(0xC0, 0, 1, 0), songdocument_test::channel(0x90, 0, 70, 100),
          songdocument_test::channel(0x90, 0, 69, 100), songdocument_test::channel(0x80, 4, 69, 0),
          songdocument_test::channel(0x80, 8, 70, 0), songdocument_test::channel(0x90, 20, 70, 100),
          songdocument_test::channel(0x80, 28, 70, 0)},
         48});
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("resize-mergeable-history"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY(track >= 0);
    int changeCount = 0;
    std::vector<TrackRemap> remaps;
    QObject::connect(&document, &SongDocument::documentChanged, [&changeCount] { ++changeCount; });
    QObject::connect(&document, &SongDocument::tracksRemapped,
                     [&remaps](TrackRemap remap) { remaps.push_back(std::move(remap)); });
    DocNote first;
    DocNote second;
    DocNote neighbor;
    QVERIFY(document.findNote(track, 0, 70, &first));
    QVERIFY(document.findNote(track, 0, 69, &second));
    QVERIFY(document.findNote(track, 20, 70, &neighbor));
    const NoteId firstId = first.noteId;
    const NoteId secondId = second.noteId;
    const NoteId neighborId = neighbor.noteId;
    const QByteArray baseline = document.smf().write();
    const int before = document.undoStack()->count();
    const uint64_t initialRevision = document.revision();

    // Requirements 1 and 2: two compatible mergeable calls form one history
    // entry and land the same +8 final delta on both notes, leaving starts,
    // pitches, velocities, and identities untouched.
    document.resizeNotes({first, second}, 4, true);
    QCOMPARE(document.undoStack()->count(), before + 1);
    QCOMPARE(document.revision(), initialRevision + 1);
    QCOMPARE(changeCount, 1);
    QVERIFY(document.findNote(track, 0, 70, &first));
    QCOMPARE(first.noteId, firstId);
    QCOMPARE(first.duration, uint32_t(12));
    QCOMPARE(first.velocity, uint8_t(100));
    QVERIFY(document.findNote(track, 0, 69, &second));
    QCOMPARE(second.noteId, secondId);
    QCOMPARE(second.duration, uint32_t(8));
    document.resizeNotes({first, second}, 4, true);
    QCOMPARE(document.undoStack()->count(), before + 1);
    QCOMPARE(changeCount, 2);
    QVERIFY(document.findNote(track, 0, 70, &first));
    QCOMPARE(first.duration, uint32_t(16));
    QVERIFY(document.findNote(track, 0, 69, &second));
    QCOMPARE(second.duration, uint32_t(12));
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.tick, uint64_t(20));
    QCOMPARE(neighbor.duration, uint32_t(8));
    const QByteArray mergedBytes = document.smf().write();

    // Requirement 3: one undo restores exact original SMF bytes and the
    // original NoteId mapping.
    document.undoStack()->undo();
    QCOMPARE(changeCount, 3);
    QCOMPARE(document.revision(), initialRevision + 3);
    QCOMPARE(document.smf().write(), baseline);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.tick, uint64_t(0));
    QCOMPARE(first.key, uint8_t(70));
    QCOMPARE(first.duration, uint32_t(8));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.tick, uint64_t(0));
    QCOMPARE(second.key, uint8_t(69));
    QCOMPARE(second.duration, uint32_t(4));
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.duration, uint32_t(8));

    // Requirement 4: redo restores the merged bytes and identities.
    document.undoStack()->redo();
    QCOMPARE(changeCount, 4);
    QCOMPARE(document.smf().write(), mergedBytes);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(16));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(12));
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.tick, uint64_t(20));

    // Requirement 5: an equal positive/negative pair dissolves the command,
    // leaving the history count unchanged while still publishing once.
    document.resizeNotes({first, second}, -8, true);
    QCOMPARE(document.undoStack()->count(), before);
    QCOMPARE(changeCount, 5);
    QCOMPARE(document.revision(), initialRevision + 5);
    QCOMPARE(document.smf().write(), baseline);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(8));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(4));

    // Requirement 6: a call whose inputs do not match the preceding output
    // state starts a new gesture. The mismatching snapshot sits at the
    // current location but still carries the pre-press duration, so the
    // per-note duration comparison refuses the merge even though every
    // NoteId matches.
    document.resizeNotes({first, second}, 4, true);
    QCOMPARE(document.undoStack()->count(), before + 1);
    QCOMPARE(changeCount, 6);
    QVERIFY(document.findNote(track, 0, 70, &first));
    QCOMPARE(first.duration, uint32_t(12));
    QVERIFY(document.findNote(track, 0, 69, &second));
    QCOMPARE(second.duration, uint32_t(8));
    DocNote mismatched = first;
    mismatched.duration -= 4;
    document.resizeNotes({mismatched, second}, 4, true);
    QCOMPARE(document.undoStack()->count(), before + 2);
    QCOMPARE(changeCount, 7);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(12));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(12));
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.duration, uint32_t(8));

    // Requirement 7: a non-mergeable resize stays its own entry even with
    // perfectly matching inputs, and undoes independently — the
    // mouse-resize path must never collapse into a keyboard gesture.
    const QByteArray beforeSeparate = document.smf().write();
    document.resizeNotes({first, second}, 2);
    QCOMPARE(document.undoStack()->count(), before + 3);
    QCOMPARE(changeCount, 8);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(14));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(second.duration, uint32_t(14));
    const QByteArray afterSeparate = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(changeCount, 9);
    QCOMPARE(document.smf().write(), beforeSeparate);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(12));
    document.undoStack()->redo();
    QCOMPARE(changeCount, 10);
    QCOMPARE(document.smf().write(), afterSeparate);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(14));

    // Overlap replay boundary: extending first over the neighbor's head
    // trims the neighbor, the merged command rebuilds that trim from the
    // gesture's original state, and one undo of the whole gesture restores
    // the neighbor exactly. The trimmed neighbor is not part of the merge
    // predicate, so the follow-up press still merges.
    document.resizeNotes({first}, 10, true);
    QCOMPARE(document.undoStack()->count(), before + 4);
    QCOMPARE(changeCount, 11);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(24));
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.tick, uint64_t(24));
    QCOMPARE(neighbor.duration, uint32_t(4));
    document.resizeNotes({first}, 2, true);
    QCOMPARE(document.undoStack()->count(), before + 4);
    QCOMPARE(changeCount, 12);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(26));
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.tick, uint64_t(26));
    QCOMPARE(neighbor.duration, uint32_t(2));
    const QByteArray gestureEnd = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(changeCount, 13);
    QCOMPARE(document.smf().write(), afterSeparate);
    QVERIFY(document.findNote(firstId, &first));
    QCOMPARE(first.duration, uint32_t(14));
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.tick, uint64_t(20));
    QCOMPARE(neighbor.duration, uint32_t(8));
    document.undoStack()->redo();
    QCOMPARE(changeCount, 14);
    QCOMPARE(document.smf().write(), gestureEnd);
    QVERIFY(document.findNote(neighborId, &neighbor));
    QCOMPARE(neighbor.tick, uint64_t(26));
    QCOMPARE(neighbor.duration, uint32_t(2));
    QVERIFY(remaps.empty());
}
