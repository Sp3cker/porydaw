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
    song.label = QStringLiteral("note-boundary");
    return document->adoptSmf(std::move(smf), song, error);
}

} // namespace

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

    // Synthetic boundary document: adoptSmf stages full-range ticks.
    SongDocument boundary;
    QVERIFY2(adoptBoundaryDocument(&boundary, &error), qPrintable(error));
    QCOMPARE(boundary.engineTrackCount(), 1);
    DocNote edge;
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    // noteEndTick reports the wide mathematical end even when that end is
    // not persistable.
    edge.tick = CoreTimeDefaults::kMaxTick - 20;
    edge.duration = 30;
    QCOMPARE(boundary.noteEndTick(edge), uint64_t(CoreTimeDefaults::kMaxTick) + 10);

    // A note ending exactly at kMaxTick is valid; a zero duration
    // normalizes to one tick before the end check.
    boundary.addNote(0, CoreTimeDefaults::kMaxTick - 24, 62, 24, 100);
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 24, 62, &edge));
    QCOMPARE(edge.duration, uint32_t(24));
    boundary.addNote(0, CoreTimeDefaults::kMaxTick - 20, 63, 0, 100);
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 20, 63, &edge));
    QCOMPARE(edge.duration, uint32_t(1));

    // Spec regressions: start 4294967293 + 2 must not write the reserved
    // 4294967295; start 4294967284 + 20 must not wrap to 8; a one-tick note
    // at kMaxTick is invalid. Rejection leaves the document, revision, and
    // undo stack untouched.
    const QByteArray baseline = boundary.smf().write();
    const uint64_t revision = boundary.revision();
    const int undoCount = boundary.undoStack()->count();
    boundary.addNote(0, CoreTimeDefaults::kMaxTick - 1, 65, 2, 100);
    boundary.addNote(0, CoreTimeDefaults::kMaxTick - 10, 66, 20, 100);
    boundary.addNote(0, CoreTimeDefaults::kMaxTick, 67, 1, 100);
    QCOMPARE(boundary.smf().write(), baseline);
    QCOMPARE(boundary.revision(), revision);
    QCOMPARE(boundary.undoStack()->count(), undoCount);

    // Right-resize: an end past kMaxTick rejects; the exact ceiling and an
    // extreme negative delta (floored at one tick) are admitted.
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    boundary.resizeNotes({edge}, int64_t(CoreTimeDefaults::kMaxTick) - 23);
    boundary.resizeNotes({edge}, INT64_MAX);
    QCOMPARE(boundary.smf().write(), baseline);
    QCOMPARE(boundary.undoStack()->count(), undoCount);
    boundary.resizeNotes({edge}, int64_t(CoreTimeDefaults::kMaxTick) - 24);
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    QCOMPARE(edge.duration, CoreTimeDefaults::kMaxTick);
    boundary.undoStack()->undo();
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    QCOMPARE(edge.duration, uint32_t(24));
    boundary.undoStack()->redo();
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    QCOMPARE(edge.duration, CoreTimeDefaults::kMaxTick);
    boundary.resizeNotes({edge}, INT64_MIN);
    QVERIFY(boundary.findNote(0, 0, 60, &edge));
    QCOMPARE(edge.duration, uint32_t(1));
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

    // Synthetic boundary document: one invalid end rejects the whole batch
    // before any note lands.
    SongDocument boundary;
    QVERIFY2(adoptBoundaryDocument(&boundary, &error), qPrintable(error));
    const QByteArray baseline = boundary.smf().write();
    const uint64_t revision = boundary.revision();
    const int undoCount = boundary.undoStack()->count();
    boundary.addNotes(0, {{CoreTimeDefaults::kMaxTick - 24, 62, 24, 96},
                          {CoreTimeDefaults::kMaxTick - 1, 65, 2, 96}});
    QCOMPARE(boundary.smf().write(), baseline);
    QCOMPARE(boundary.revision(), revision);
    QCOMPARE(boundary.undoStack()->count(), undoCount);
    QCOMPARE(boundary.notesForTrack(0).size(), size_t(2));
    boundary.addNotes(0, {{CoreTimeDefaults::kMaxTick - 24, 62, 24, 96},
                          {CoreTimeDefaults::kMaxTick - 48, 66, 24, 96}});
    QCOMPARE(boundary.undoStack()->count(), undoCount + 1);
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 24, 62, &first));
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 48, 66, &second));
    boundary.undoStack()->undo();
    QVERIFY(!boundary.findNote(0, CoreTimeDefaults::kMaxTick - 24, 62, &first));
    QVERIFY(!boundary.findNote(0, CoreTimeDefaults::kMaxTick - 48, 66, &second));
    boundary.undoStack()->redo();
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 24, 62, &first));
    QVERIFY(boundary.findNote(0, CoreTimeDefaults::kMaxTick - 48, 66, &second));
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
