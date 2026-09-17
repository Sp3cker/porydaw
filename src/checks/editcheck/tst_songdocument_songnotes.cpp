#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <algorithm>

#include "checks/editcheck/tst_songdocument_support.h"

void EditCheckTest::noteResizeStopsAtNextSelectedStart()
{
    using namespace songdocument_test;
    for (bool reverse : {false, true}) {
        SmfFile smf;
        smf.tracks = {
            conductor(), {{channel(0xC0, 0, 0, 0)}, 200}, {{channel(0xC1, 0, 0, 0)}, 200}};
        auto fixture = makeDocument(smf);
        QVERIFY(fixture);
        auto &doc = fixture->document;
        doc.addNotes(0, {{0, 60, 10, 81}, {20, 60, 10, 92}});
        QVERIFY(notePairsConsistent(doc, 0));
        auto originals = doc.notesForTrack(0);
        auto durations = doc.resizeNotesDurations(originals, 20);
        QVERIFY(durations);
        QCOMPARE(*durations, (std::vector<uint32_t>{20, 30}));
        auto adjacent = originals;
        adjacent[0].duration = 20;
        adjacent[1].duration = 30;
        durations = doc.resizeNotesDurations(adjacent, 10);
        QVERIFY(durations);
        QCOMPARE(*durations, (std::vector<uint32_t>{20, 40}));
        auto zeroCap = originals;
        zeroCap[1].tick = zeroCap[0].tick;
        QVERIFY(!doc.resizeNotesDurations(zeroCap, 20));
        QVERIFY(!doc.resizeNotesDurations(originals, CoreTimeDefaults::kMaxTick));
        const auto before = doc.smf().write();
        doc.undoStack()->clear();
        auto selected = originals;
        if (reverse)
            std::reverse(selected.begin(), selected.end());
        doc.resizeNotes(selected, 20, true);
        auto notes = doc.notesForTrack(0);
        QCOMPARE(notes[0].duration, uint32_t(20));
        QCOMPARE(notes[1].duration, uint32_t(30));
        for (size_t i = 0; i < notes.size(); ++i) {
            QCOMPARE(notes[i].noteId, originals[i].noteId);
            QCOMPARE(notes[i].velocity, originals[i].velocity);
        }
        QVERIFY(notePairsConsistent(doc, 0));
        doc.resizeNotes(notes, 10, true);
        QVERIFY(notePairsConsistent(doc, 0));
        QCOMPARE(doc.undoStack()->count(), 1);
        notes = doc.notesForTrack(0);
        QCOMPARE(notes[0].duration, uint32_t(20));
        QCOMPARE(notes[1].duration, uint32_t(40));
        const auto extended = doc.smf().write();
        doc.resizeNotes(notes, -10, true);
        QVERIFY(notePairsConsistent(doc, 0));
        notes = doc.notesForTrack(0);
        QCOMPARE(notes[0].duration, uint32_t(10));
        QCOMPARE(notes[1].duration, uint32_t(30));
        QCOMPARE(doc.undoStack()->count(), 2); // capped extension is not additive on reversal
        const auto shortened = doc.smf().write();
        doc.undoStack()->undo();
        QCOMPARE(doc.smf().write(), extended);
        doc.undoStack()->undo();
        QCOMPARE(doc.smf().write(), before);
        doc.undoStack()->redo();
        QVERIFY(notePairsConsistent(doc, 0));
        doc.undoStack()->redo();
        QCOMPARE(doc.smf().write(), shortened);
        QVERIFY(notePairsConsistent(doc, 0));

        doc.undoStack()->clear();
        doc.resizeNotes(doc.notesForTrack(0), 1, true);
        QVERIFY(notePairsConsistent(doc, 0));
        doc.undoStack()->setClean();
        doc.resizeNotes(doc.notesForTrack(0), 1, true);
        QVERIFY(notePairsConsistent(doc, 0));
        QCOMPARE(doc.undoStack()->count(), 2);
        doc.undoStack()->undo();
        QVERIFY(doc.undoStack()->isClean());
    }

    SmfFile smf;
    smf.tracks = {conductor(), {{channel(0xC0, 0, 0, 0)}, 200}, {{channel(0xC1, 0, 0, 0)}, 200}};
    auto fixture = makeDocument(smf);
    QVERIFY(fixture);
    auto &doc = fixture->document;
    doc.addNotes(0, {{0, 60, 10, 81}, {20, 60, 10, 82}, {40, 60, 10, 83}, {0, 61, 10, 84}});
    doc.addNote(1, 0, 60, 10, 85);
    auto selected = doc.notesForTrack(0);
    selected.push_back(doc.notesForTrack(1).front());
    doc.resizeNotes(selected, 30);
    QVERIFY(notePairsConsistent(doc, 0));
    QVERIFY(notePairsConsistent(doc, 1));
    DocNote note;
    QVERIFY(doc.findNote(0, 0, 60, &note));
    QCOMPARE(note.duration, uint32_t(20));
    QVERIFY(doc.findNote(0, 20, 60, &note));
    QCOMPARE(note.duration, uint32_t(20));
    QVERIFY(doc.findNote(0, 40, 60, &note));
    QCOMPARE(note.duration, uint32_t(40));
    QVERIFY(doc.findNote(0, 0, 61, &note));
    QCOMPARE(note.duration, uint32_t(40));
    QVERIFY(doc.findNote(1, 0, 60, &note));
    QCOMPARE(note.duration, uint32_t(40));

    // A compatible inverse removes the gesture and restores its stationary victim.
    doc.addNote(1, 42, 60, 10, 93);
    QVERIFY(notePairsConsistent(doc, 1));
    doc.undoStack()->clear();
    const auto before = doc.smf().write();
    QVERIFY(doc.findNote(1, 0, 60, &note));
    doc.resizeNotes({note}, 5, true);
    QVERIFY(notePairsConsistent(doc, 1));
    QVERIFY(doc.findNote(note.noteId, &note));
    doc.resizeNotes({note}, -5, true);
    QCOMPARE(doc.smf().write(), before);
    QCOMPARE(doc.undoStack()->count(), 0);
    QVERIFY(notePairsConsistent(doc, 1));
    doc.resizeNotes(doc.notesForTrack(1), -100);
    QVERIFY(notePairsConsistent(doc, 1));
    const SavedDocState noOp = captureDocState(doc, 1);
    doc.resizeNotes(doc.notesForTrack(1), -1, true);
    QVERIFY2(docStateMismatch(doc, noOp, 1).isEmpty(), qPrintable(docStateMismatch(doc, noOp, 1)));
}

void EditCheckTest::noteBatchCollisionRejects()
{
    using namespace songdocument_test;
    SmfFile smf;
    smf.tracks = {conductor(), {{channel(0xC0, 0, 0, 0)}, 200}};
    auto fixture = makeDocument(smf);
    QVERIFY(fixture);
    auto &doc = fixture->document;
    doc.addNote(0, 0, 60, 100, 91);
    doc.addNote(0, 150, 62, 10, 72);
    doc.undoStack()->undo(); // refusal must not discard this redo branch
    const SavedDocState saved = captureDocState(doc);
    for (const std::vector<SongDocument::NewNote> &batch :
         {std::vector<SongDocument::NewNote>{{10, 60, 20, 80}, {20, 60, 20, 90}},
          std::vector<SongDocument::NewNote>{{10, 60, 20, 80}, {10, 60, 10, 90}},
          std::vector<SongDocument::NewNote>{{10, 60, 40, 80}, {20, 60, 10, 90}}}) {
        doc.addNotes(0, batch);
        QVERIFY2(docStateMismatch(doc, saved).isEmpty(), qPrintable(docStateMismatch(doc, saved)));
    }
    doc.addNotes(0, {{110, 60, 10, 81}, {120, 60, 10, 82}, {110, 61, 20, 83}});
    QVERIFY(notePairsConsistent(doc, 0));
    const auto after = doc.smf().write();
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), saved.bytes);
    doc.undoStack()->redo();
    QCOMPARE(doc.smf().write(), after);
    QVERIFY(notePairsConsistent(doc, 0));

    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), saved.bytes);
    doc.addNotes(0, {{110, 60, 10, 81}, {110, 60, 10, 81}});
    const auto duplicates = doc.notesForTrack(0);
    QCOMPARE(duplicates.size(), size_t(3));
    const DocNote &first = duplicates[1];
    const DocNote &second = duplicates[2];
    QVERIFY(first.noteId.isAssigned());
    QVERIFY(second.noteId.isAssigned());
    QVERIFY(first.noteId != second.noteId);
    for (const DocNote *note : {&first, &second}) {
        QCOMPARE(note->tick, Tick(110));
        QCOMPARE(note->duration, uint32_t(10));
        QCOMPARE(note->key, uint8_t(60));
        QCOMPARE(note->velocity, uint8_t(81));
    }
    const auto duplicateBytes = doc.smf().write();
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), saved.bytes);
    doc.undoStack()->redo();
    QCOMPARE(doc.smf().write(), duplicateBytes);
}

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
