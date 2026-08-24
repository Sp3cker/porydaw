#include "checks/editcheck/support.h"

namespace editcheck {
bool checkSongNoteEdits(SongEditScenario &scenario)
{
    SongDocument &doc = scenario.doc;
    const int track = scenario.track;
    const uint64_t base = scenario.base;
    const uint32_t step = scenario.step;
    bool ok = true;
    const auto fail = [&scenario](const char *what) { scenario.fail(what); };
    const auto mutateAndCheck = [&scenario, &ok](const char *what) {
        if (ok && !scenario.checkSorted(what))
            ok = false;
    };

    // Note ops: add, move, resize, re-velocity, delete.
    doc.addNote(track, base, 60, step * 4, 100);
    mutateAndCheck("events unsorted after addNote");
    DocNote note;
    if (ok && !doc.findNote(track, base, 60, &note)) {
        fail("added note not found");
        ok = false;
    }
    if (ok) {
        doc.moveNotes({note}, int64_t(step) * 8, 3);
        mutateAndCheck("events unsorted after moveNotes");
    }
    if (ok && !doc.findNote(track, base + step * 8, 63, &note)) {
        fail("moved note not found");
        ok = false;
    }
    if (ok) {
        doc.resizeNotes({note}, int64_t(step) * 2);
        mutateAndCheck("events unsorted after resizeNotes");
        if (!doc.findNote(track, base + step * 8, 63, &note) || note.duration != step * 6) {
            fail("resize produced wrong duration");
            ok = false;
        }
    }
    if (ok) {
        // Left resize: the note-on moves, the note-off stays pinned.
        doc.resizeNotesLeft({note}, -int64_t(step) * 2);
        mutateAndCheck("events unsorted after resizeNotesLeft");
        if (!doc.findNote(track, base + step * 6, 63, &note) || note.duration != step * 8) {
            fail("left resize produced wrong start/duration");
            ok = false;
        }
    }
    if (ok) {
        // Dragging the note-on past the note-off clamps to 1 tick left.
        doc.resizeNotesLeft({note}, int64_t(step) * 100);
        mutateAndCheck("events unsorted after clamped resizeNotesLeft");
        if (!doc.findNote(track, base + step * 14 - 1, 63, &note) || note.duration != 1) {
            fail("left resize not clamped at the note-off");
            ok = false;
        } else {
            doc.resizeNotesLeft({note}, -int64_t(step) * 8 + 1);
            if (!doc.findNote(track, base + step * 6, 63, &note) || note.duration != step * 8) {
                fail("left resize could not restore the note");
                ok = false;
            }
        }
    }
    if (ok) {
        doc.setNotesVelocity({note}, 88);
        if (!doc.findNote(track, base + step * 6, 63, &note) || note.velocity != 88) {
            fail("velocity edit not applied");
            ok = false;
        }
    }
    if (ok) {
        doc.nudgeNotesVelocity({note}, -30);
        if (!doc.findNote(track, base + step * 6, 63, &note) || note.velocity != 58) {
            fail("velocity nudge not applied");
            ok = false;
        }
    }
    if (ok) {
        doc.nudgeNotesVelocity({note}, 200); // must clamp to 127
        if (!doc.findNote(track, base + step * 6, 63, &note) || note.velocity != 127) {
            fail("velocity nudge not clamped");
            ok = false;
        }
    }
    if (ok)
        doc.deleteNotes({note});

    // Batch add (clipboard paste): both notes in one undoable command.
    if (ok) {
        doc.addNotes(track,
                     {{base + step * 20, 64, step * 2, 96}, {base + step * 22, 67, step * 2, 96}});
        mutateAndCheck("events unsorted after addNotes");
        DocNote a, b;
        if (!doc.findNote(track, base + step * 20, 64, &a) ||
            !doc.findNote(track, base + step * 22, 67, &b)) {
            fail("batch-added notes not found");
            ok = false;
        } else {
            doc.undoStack()->undo();
            if (doc.findNote(track, base + step * 20, 64, &a) ||
                doc.findNote(track, base + step * 22, 67, &b)) {
                fail("addNotes was not a single undo command");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
        }
    }

    // Abutting same-pitch notes, written right-to-left: the left
    // note's end lands at the right note's on tick, and must be
    // ordered before it — pairing (here and in mid2agb) gives every
    // note-on the first same-key end after it, so an end placed
    // after a same-tick note-on makes the left note swallow the
    // right one and orphans the real end when the pair is deleted.
    if (ok) {
        const uint64_t seam = base + step * 72;
        doc.addNote(track, seam, 60, step * 2, 100);
        doc.addNote(track, seam - step * 2, 60, step * 2, 100);
        mutateAndCheck("events unsorted after abutting addNote");
        DocNote leftNote, rightNote;
        if (!doc.findNote(track, seam - step * 2, 60, &leftNote) ||
            !doc.findNote(track, seam, 60, &rightNote) || leftNote.duration != step * 2 ||
            rightNote.duration != step * 2 || leftNote.endIndex == rightNote.endIndex) {
            fail("abutting notes mis-paired (note end after same-tick note-on)");
            ok = false;
        } else {
            doc.deleteNotes({leftNote, rightNote});
            bool leftover = false;
            for (const SmfEvent &ev : doc.smf().tracks[size_t(leftNote.smfTrack)].events) {
                leftover |= ev.tick >= seam - step * 2 && ev.isChannel() &&
                            (ev.isNoteOn() || ev.isNoteEnd());
            }
            if (leftover) {
                fail("deleting abutting notes left a note event behind");
                ok = false;
            }
        }
    }

    return ok;
}

} // namespace editcheck
