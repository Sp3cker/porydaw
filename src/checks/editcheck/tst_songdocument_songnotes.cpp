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
