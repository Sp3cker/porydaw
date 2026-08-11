#include <QElapsedTimer>
#include <QString>
#include <QTemporaryDir>
#include <cstdio>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "project/decompproject.h"

// --editcheck <projectRoot>: M2 undo-integrity check. For every song with a
// MIDI source, performs a scripted pass over every edit-operation type, then
// verifies that undoing everything restores the SMF byte-for-byte, that redo
// reproduces the edited state deterministically, and that event ticks stay
// sorted after each mutation. Complements --roundtrip (which proves the
// unedited writer) by proving the editing layer can always get back to that
// pristine state.

namespace {

bool tracksSorted(const SmfFile &smf)
{
    for (const SmfTrack &track : smf.tracks) {
        for (size_t i = 1; i < track.events.size(); i++) {
            if (track.events[i].tick < track.events[i - 1].tick)
                return false;
        }
    }
    return true;
}

} // namespace

int runEditCheck(const QString &projectRoot)
{
    DecompProject project;
    QString error;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "editcheck: %s\n", qUtf8Printable(error));
        return 1;
    }

    QElapsedTimer timer;
    timer.start();

    int checked = 0, failures = 0;
    for (const SongInfo &song : project.songs()) {
        if (!song.isPlayable())
            continue;

        SongDocument doc;
        if (!doc.load(song, &error)) {
            std::fprintf(stderr, "editcheck: FAIL %s: %s\n", qUtf8Printable(song.label),
                         qUtf8Printable(error));
            failures++;
            continue;
        }
        const QByteArray baseline = doc.smf().write();

        // Pick a track that has notes to edit on.
        int track = -1;
        for (int t = 0; t < doc.engineTrackCount(); t++) {
            if (!doc.notesForTrack(t).empty()) {
                track = t;
                break;
            }
        }

        auto fail = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL %s: %s\n", qUtf8Printable(song.label), what);
            failures++;
        };

        const uint32_t step = doc.ticksPerClock();
        // Edit far past the end of the song so scripted notes and lane points
        // can't collide with (or re-pair against) the song's real content.
        uint64_t base = 0;
        for (const SmfTrack &tr : doc.smf().tracks)
            base = std::max(base, tr.endTick);
        base += step * 100;
        bool ok = true;
        auto mutateAndCheck = [&](const char *what) {
            if (ok && !tracksSorted(doc.smf())) {
                fail(what);
                ok = false;
            }
        };

        if (track >= 0) {
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
                    if (!doc.findNote(track, base + step * 6, 63, &note) ||
                        note.duration != step * 8) {
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
                doc.addNotes(track, {{base + step * 20, 64, step * 2, 96},
                                     {base + step * 22, 67, step * 2, 96}});
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

            // Range edit: a multi-track/multi-lane batch of removals and
            // insertions must land as ONE undoable command.
            if (ok) {
                doc.addNotes(track, {{base + step * 30, 60, step * 2, 90},
                                     {base + step * 32, 62, step * 2, 90}});
                doc.addLanePoint(track, 7, base + step * 30, 80);
                doc.addLanePoint(track, DOC_CC_TEMPO, base + step * 31, 140);
                SongDocument::RangeEdit edit;
                for (const DocNote &n : doc.notesForTrack(track)) {
                    if (n.tick >= base + step * 30 && n.tick < base + step * 34)
                        edit.removeNotes.push_back(n);
                }
                for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
                    if (p.tick == base + step * 30)
                        edit.removePoints.push_back(p);
                }
                for (const DocLanePoint &p : doc.lanePoints(track, DOC_CC_TEMPO)) {
                    if (p.tick == base + step * 31)
                        edit.removePoints.push_back(p);
                }
                edit.addNotes.push_back({track, {{base + step * 40, 65, step * 2, 90}}});
                edit.addPoints.push_back({track, 7, {{base + step * 40, 70}}});
                edit.addPoints.push_back({-1, DOC_CC_TEMPO, {{base + step * 41, 155}}});
                doc.applyRangeEdit(QStringLiteral("range edit"), edit);
                mutateAndCheck("events unsorted after applyRangeEdit");
                DocNote n;
                DocLanePoint p;
                if (doc.findNote(track, base + step * 30, 60, &n) ||
                    doc.findNote(track, base + step * 32, 62, &n) ||
                    !doc.findNote(track, base + step * 40, 65, &n) ||
                    !doc.findLanePoint(track, 7, base + step * 40, &p) || p.value != 70 ||
                    !doc.findLanePoint(track, DOC_CC_TEMPO, base + step * 41, &p) ||
                    p.value != 155) {
                    fail("range edit produced wrong content");
                    ok = false;
                } else {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 30, 60, &n) ||
                        doc.findNote(track, base + step * 40, 65, &n)) {
                        fail("applyRangeEdit was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Range move (time-selection nudge): notes plus CC and tempo
            // points shift together by a tick delta as ONE undoable command,
            // with values intact (events move as raw bytes).
            if (ok) {
                doc.addNotes(track, {{base + step * 80, 60, step * 2, 90},
                                     {base + step * 82, 64, step * 2, 90}});
                doc.addLanePoint(track, 7, base + step * 80, 45);
                doc.addLanePoint(track, DOC_CC_TEMPO, base + step * 81, 140);
                std::vector<DocNote> moveNotes;
                for (const DocNote &n : doc.notesForTrack(track)) {
                    if (n.tick >= base + step * 80 && n.tick < base + step * 84)
                        moveNotes.push_back(n);
                }
                std::vector<DocLanePoint> movePoints;
                for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
                    if (p.tick == base + step * 80)
                        movePoints.push_back(p);
                }
                for (const DocLanePoint &p : doc.lanePoints(track, DOC_CC_TEMPO)) {
                    if (p.tick == base + step * 81)
                        movePoints.push_back(p);
                }
                doc.moveRange(moveNotes, movePoints, step * 3);
                mutateAndCheck("events unsorted after moveRange");
                DocNote n;
                DocLanePoint p;
                if (doc.findNote(track, base + step * 80, 60, &n) ||
                    !doc.findNote(track, base + step * 83, 60, &n) || n.duration != step * 2 ||
                    !doc.findNote(track, base + step * 85, 64, &n) ||
                    !doc.findLanePoint(track, 7, base + step * 83, &p) || p.value != 45 ||
                    !doc.findLanePoint(track, DOC_CC_TEMPO, base + step * 84, &p) ||
                    p.value != 140) {
                    fail("range move produced wrong content");
                    ok = false;
                }
                if (ok) {
                    doc.moveRange(moveNotes, movePoints, 0); // no-op guard
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 80, 60, &n) ||
                        doc.findNote(track, base + step * 83, 60, &n) ||
                        !doc.findLanePoint(track, 7, base + step * 80, &p)) {
                        fail("moveRange was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Same-key overlap resolution: a written note landing on another
            // note's span trims it (head or tail kept) or removes it when
            // fully covered, in the same undo command — the pairing rule
            // (first same-key end after the on) cannot represent an overlap,
            // which used to silently re-pair the stationary note's end onto
            // the edited note's.
            if (ok) {
                doc.addNote(track, base + step * 90, 71, step * 4, 100); // S 90..94
                doc.addNote(track, base + step * 88, 70, step * 4, 100); // M 88..92
                DocNote m, s;
                // Tail kept: M transposed up onto S's head.
                if (!doc.findNote(track, base + step * 88, 70, &m)) {
                    fail("overlap-scenario notes not found");
                    ok = false;
                } else {
                    doc.moveNotes({m}, 0, 1);
                    mutateAndCheck("events unsorted after overlap transpose");
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 4 ||
                        !doc.findNote(track, base + step * 92, 71, &s) || s.duration != step * 2) {
                        fail("transpose onto a note's head did not keep its tail");
                        ok = false;
                    }
                }
                // Fully covered: M resized right across all of S removes it.
                if (ok) {
                    doc.resizeNotes({m}, step * 4); // M 88..96 covers S 92..94
                    mutateAndCheck("events unsorted after overlap resize");
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 8 ||
                        doc.findNote(track, base + step * 92, 71, &s)) {
                        fail("resize across a covered note did not remove it");
                        ok = false;
                    }
                }
                // Head kept: a note drawn over M's tail trims M back, and one
                // undo reverts the trim together with the add.
                if (ok) {
                    doc.addNote(track, base + step * 94, 71, step * 4, 100);
                    mutateAndCheck("events unsorted after overlapping addNote");
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 6 ||
                        !doc.findNote(track, base + step * 94, 71, &s) || s.duration != step * 4) {
                        fail("overlapping add did not trim the covered tail");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 8 ||
                        doc.findNote(track, base + step * 94, 71, &s)) {
                        fail("overlap trim was not part of the edit's own undo");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Mergeable moves (keyboard transpose/nudge): consecutive
            // mergeable moveNotes of the same notes collapse into ONE undo
            // command that re-lands from the gesture's start — a neighbor
            // trimmed by a merely-passed-through overlap comes back — and
            // the merge stops at the stack's clean index (a save between
            // presses keeps its own command).
            if (ok) {
                doc.addNote(track, base + step * 100, 70, step * 4, 100); // S
                doc.addNote(track, base + step * 100, 69, step * 2, 100); // M
                const int countBefore = doc.undoStack()->count();
                DocNote m, s;
                if (!doc.findNote(track, base + step * 100, 69, &m)) {
                    fail("merge-scenario notes not found");
                    ok = false;
                }
                if (ok) {
                    doc.moveNotes({m}, 0, 1, true); // M onto S: S trimmed
                    if (!doc.findNote(track, base + step * 102, 70, &s) || s.duration != step * 2) {
                        fail("mergeable transpose did not trim the overlap");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.findNote(track, base + step * 100, 70, &m); // re-resolve
                    doc.moveNotes({m}, 0, 1, true);                 // past S: merged, +2 total
                    if (doc.undoStack()->count() != countBefore + 1) {
                        fail("consecutive mergeable moves did not merge");
                        ok = false;
                    } else if (!doc.findNote(track, base + step * 100, 71, &m) ||
                               m.duration != step * 2 ||
                               !doc.findNote(track, base + step * 100, 70, &s) ||
                               s.duration != step * 4) {
                        fail("merged transpose did not restore the trimmed note");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 100, 69, &m) ||
                        !doc.findNote(track, base + step * 100, 70, &s) || s.duration != step * 4) {
                        fail("merged move undo did not restore the gesture start");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
                if (ok) {
                    doc.findNote(track, base + step * 100, 71, &m);
                    doc.undoStack()->setClean();
                    doc.moveNotes({m}, 0, 1, true);
                    if (doc.undoStack()->count() != countBefore + 2) {
                        fail("mergeable move merged across the clean index");
                        ok = false;
                    }
                }
            }

            // Batch pitch moves (moveNotesToPitches): Wave 2's per-note
            // destination transposes. Two notes of different keys move by
            // different amounts in ONE undo command; identities survive at
            // the destinations (findNote resolves them, durations and
            // velocities intact), one undo restores the pre-gesture MIDI
            // bytes and one redo re-lands the destinations. Mergeable
            // nudges collapse exactly like moveNotes: repeated consecutive
            // presses stay one undo gesture (the count grows by exactly one
            // in total) and one undo returns to the gesture start; an
            // inverse press (up then down) nets to the gesture start with
            // no extra undo entry. A collision with an unselected note trims
            // it exactly like the moveNotes overlap scenarios above, with
            // the trim part of the move's own undo command. A rejected
            // resolver (destKey outside 0-127, or mismatched list sizes)
            // returns false without pushing: no command, unchanged SMF.
            if (ok) {
                const uint64_t tA = base + step * 110;
                doc.addNote(track, tA, 115, step * 4, 100);            // A 115 -> 118 (+3)
                doc.addNote(track, tA + step * 20, 117, step * 2, 90); // B 117 -> 114 (-3)
                mutateAndCheck("events unsorted after batch-pitch adds");
                const int countBefore = doc.undoStack()->count();
                const QByteArray preMove = doc.smf().write();
                DocNote a, b;
                if (!doc.findNote(track, tA, 115, &a) ||
                    !doc.findNote(track, tA + step * 20, 117, &b)) {
                    fail("batch-pitch scenario notes not found");
                    ok = false;
                }
                // One command moves different pitches by different amounts.
                if (ok) {
                    if (!doc.moveNotesToPitches({a, b}, {uint8_t(118), uint8_t(114)}, 0)) {
                        fail("moveNotesToPitches rejected a valid batch move");
                        ok = false;
                    }
                    mutateAndCheck("events unsorted after moveNotesToPitches");
                    if (ok && doc.undoStack()->count() != countBefore + 1) {
                        fail("moveNotesToPitches was not a single undo command");
                        ok = false;
                    }
                    if (ok &&
                        (!doc.findNote(track, tA, 118, &a) || a.duration != step * 4 ||
                         a.velocity != 100 || doc.findNote(track, tA, 115, &a) ||
                         !doc.findNote(track, tA + step * 20, 114, &b) ||
                         b.duration != step * 2 || b.velocity != 90 ||
                         doc.findNote(track, tA + step * 20, 117, &b))) {
                        fail("batch pitch move did not land both destinations");
                        ok = false;
                    }
                }
                // Undo restores the original bytes and identities; redo
                // reproduces the destinations. (QUndoStack::count never
                // shrinks on undo, so the restore is proven by bytes and
                // resolved note identities, not by a count comparison.)
                if (ok) {
                    const QByteArray moved = doc.smf().write();
                    doc.undoStack()->undo();
                    if (doc.smf().write() != preMove) {
                        fail("moveNotesToPitches undo did not restore the original bytes");
                        ok = false;
                    }
                    else if (!doc.findNote(track, tA, 115, &a) || a.duration != step * 4 ||
                             a.velocity != 100 || !doc.findNote(track, tA + step * 20, 117, &b) ||
                             b.duration != step * 2 || b.velocity != 90) {
                        fail("moveNotesToPitches undo did not restore bytes and identities");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                        if (ok && (doc.smf().write() != moved ||
                                   !doc.findNote(track, tA, 118, &a) || a.duration != step * 4 ||
                                   !doc.findNote(track, tA + step * 20, 114, &b) ||
                                   b.duration != step * 2)) {
                            fail("moveNotesToPitches redo did not reproduce the destinations");
                            ok = false;
                        }
                    }
                }
                // Repeated mergeable nudges stay ONE undo gesture: the count
                // grows by exactly one in total, and one undo returns the
                // notes to the gesture start.
                if (ok) {
                    const int countBefore = doc.undoStack()->count();
                    const QByteArray atStart = doc.smf().write();
                    if (!doc.findNote(track, tA, 118, &a) ||
                        !doc.findNote(track, tA + step * 20, 114, &b)) {
                        fail("merge-nudge notes not found");
                        ok = false;
                    }
                    if (ok) {
                        doc.moveNotesToPitches({a, b}, {uint8_t(119), uint8_t(115)}, 0, true);
                        if (!doc.findNote(track, tA, 119, &a) ||
                            !doc.findNote(track, tA + step * 20, 115, &b)) {
                            fail("first mergeable nudge did not land");
                            ok = false;
                        }
                    }
                    if (ok) {
                        doc.moveNotesToPitches({a, b}, {uint8_t(120), uint8_t(116)}, 0, true);
                        mutateAndCheck("events unsorted after merged pitch nudge");
                        if (doc.undoStack()->count() != countBefore + 1) {
                            fail("mergeable pitch nudges did not stay one undo gesture");
                            ok = false;
                        } else if (!doc.findNote(track, tA, 120, &a) ||
                                   !doc.findNote(track, tA + step * 20, 116, &b)) {
                            fail("merged pitch nudges did not reach the final pitch");
                            ok = false;
                        }
                    }
                    if (ok) {
                        doc.undoStack()->undo();
                        if (!doc.findNote(track, tA, 118, &a) ||
                            !doc.findNote(track, tA + step * 20, 114, &b) ||
                            doc.smf().write() != atStart) {
                            fail("one undo did not return to the nudge gesture start");
                            ok = false;
                        }
                    }
                }
                // Inverse merge: up then down collapses (no extra undo
                // entry) and one undo returns to the pre-gesture bytes. A
                // clean index marks the gesture boundary — without it Qt
                // merges the new press into the previous (undone) mergeable
                // command, exactly like MoveNotesCommand.
                if (ok) {
                    doc.undoStack()->setClean();
                    const QByteArray atStart = doc.smf().write();
                    if (!doc.findNote(track, tA, 118, &a) ||
                        !doc.findNote(track, tA + step * 20, 114, &b)) {
                        fail("inverse-nudge notes not found");
                        ok = false;
                    }
                    // Up nudge reuses the undone command's redo slot (its
                    // count is already counted); capture the post-push index
                    // as the gesture baseline.
                    if (ok) {
                        doc.moveNotesToPitches({a, b}, {uint8_t(119), uint8_t(115)}, 0, true);
                        if (!doc.findNote(track, tA, 119, &a) ||
                            !doc.findNote(track, tA + step * 20, 115, &b)) {
                            fail("up-nudge of the inverse gesture did not land");
                            ok = false;
                        }
                    }
                    // The down nudge must merge into the up nudge — it adds
                    // no command on top (the index is unchanged) — and net
                    // to the gesture start.
                    if (ok) {
                        const int afterUpIndex = doc.undoStack()->index();
                        doc.moveNotesToPitches({a, b}, {uint8_t(118), uint8_t(114)}, 0, true);
                        if (doc.undoStack()->index() != afterUpIndex) {
                            fail("inverse mergeable nudge did not collapse");
                            ok = false;
                        } else if (!doc.findNote(track, tA, 118, &a) ||
                                   !doc.findNote(track, tA + step * 20, 114, &b)) {
                            fail("collapsed inverse nudge did not net to the gesture start");
                            ok = false;
                        }
                    }
                    if (ok) {
                        doc.undoStack()->undo();
                        if (doc.smf().write() != atStart) {
                            fail("inverse-gesture undo did not return to the pre-gesture bytes");
                            ok = false;
                        }
                    }
                }
                // Collisions with unselected notes: a written note landing
                // on another note's span trims it (tail kept) or removes it
                // when fully covered, exactly like the moveNotes overlap
                // scenarios above, with the trim part of the move's own undo
                // command.
                if (ok) {
                    doc.addNote(track, base + step * 140, 119, step * 4, 100); // S 140..144
                    doc.addNote(track, base + step * 138, 118, step * 4, 100); // M 138..142
                    mutateAndCheck("events unsorted after collision adds");
                    DocNote m6, s6;
                    if (!doc.findNote(track, base + step * 138, 118, &m6) ||
                        !doc.findNote(track, base + step * 140, 119, &s6)) {
                        fail("collision-scenario notes not found");
                        ok = false;
                    }
                    // Tail kept: M pitch-moved up onto S's head.
                    if (ok) {
                        doc.moveNotesToPitches({m6}, {uint8_t(119)}, 0);
                        mutateAndCheck("events unsorted after pitch-move collision");
                        if (!doc.findNote(track, base + step * 138, 119, &m6) ||
                            m6.duration != step * 4 ||
                            !doc.findNote(track, base + step * 142, 119, &s6) ||
                            s6.duration != step * 2 ||
                            doc.findNote(track, base + step * 138, 118, &m6) ||
                            doc.findNote(track, base + step * 140, 119, &s6)) {
                            fail("pitch move onto a note's head did not keep its tail");
                            ok = false;
                        }
                    }
                    // One undo reverts the move together with its trim: both
                    // notes are back at their original keys and durations.
                    if (ok) {
                        doc.undoStack()->undo();
                        if (!doc.findNote(track, base + step * 138, 118, &m6) ||
                            m6.duration != step * 4 ||
                            !doc.findNote(track, base + step * 140, 119, &s6) ||
                            s6.duration != step * 4) {
                            fail("pitch-move trim was not part of the move's own undo");
                            ok = false;
                        } else {
                            doc.undoStack()->redo();
                        }
                    }
                    // Fully covered: M pitch-moved forward across all of S
                    // removes it.
                    if (ok) {
                        if (!doc.findNote(track, base + step * 138, 119, &m6)) {
                            fail("collision redo did not restore the moved note");
                            ok = false;
                        } else {
                            doc.moveNotesToPitches({m6}, {uint8_t(119)}, step * 2);
                            mutateAndCheck("events unsorted after pitch-move full cover");
                            if (!doc.findNote(track, base + step * 140, 119, &m6) ||
                                m6.duration != step * 4 ||
                                doc.findNote(track, base + step * 142, 119, &s6)) {
                                fail("pitch move across a covered note did not remove it");
                                ok = false;
                            }
                        }
                    }
                }
                // Rejected resolvers: a destKey outside 0-127 or mismatched
                // notes/dests sizes return false with no revision pushed and
                // no undo entry — the count is unchanged and the SMF stays
                // byte-identical.
                if (ok) {
                    const int countBefore = doc.undoStack()->count();
                    const QByteArray before = doc.smf().write();
                    DocNote x, y;
                    if (!doc.findNote(track, tA, 118, &x) ||
                        !doc.findNote(track, tA + step * 20, 114, &y)) {
                        fail("reject-scenario notes not found");
                        ok = false;
                    }
                    if (ok && doc.moveNotesToPitches({x}, {uint8_t(130)}, 0)) {
                        fail("moveNotesToPitches did not reject a dest above 127");
                        ok = false;
                    }
                    if (ok && doc.undoStack()->count() != countBefore) {
                        fail("rejected move above 127 pushed an undo command");
                        ok = false;
                    }
                    if (ok && doc.moveNotesToPitches({x}, {}, 0)) {
                        fail("moveNotesToPitches did not reject mismatched sizes");
                        ok = false;
                    }
                    if (ok && doc.moveNotesToPitches({}, {uint8_t(118)}, 0)) {
                        fail("moveNotesToPitches did not reject empty notes");
                        ok = false;
                    }
                    if (ok && doc.undoStack()->count() != countBefore) {
                        fail("rejected move pushed an undo command");
                        ok = false;
                    }
                    if (ok && (doc.smf().write() != before ||
                               !doc.findNote(track, tA, 118, &x) ||
                               !doc.findNote(track, tA + step * 20, 114, &y))) {
                        fail("rejected move changed the SMF");
                        ok = false;
                    }
                }
            }

            // Ripple remove (removeTimeRange): in-range content vanishes,
            // later events shift left by the span, and the last in-range
            // automation point survives at the seam. ONE undoable command.
            if (ok) {
                doc.addNotes(track, {{base + step * 50, 60, step, 90},
                                     {base + step * 52, 62, step, 90},
                                     {base + step * 56, 64, step, 90}});
                doc.addLanePoint(track, 7, base + step * 51, 30);
                doc.addLanePoint(track, 7, base + step * 52, 40);
                SongDocument::RippleScope scope;
                scope.tracks = {track};
                if (!doc.removeTimeRange(base + step * 51, base + step * 54, scope)) {
                    fail("removeTimeRange reported nothing to do");
                    ok = false;
                }
                mutateAndCheck("events unsorted after removeTimeRange");
                DocNote n;
                DocLanePoint p;
                if (ok && (!doc.findNote(track, base + step * 50, 60, &n) ||
                           doc.findNote(track, base + step * 52, 62, &n) ||
                           !doc.findNote(track, base + step * 53, 64, &n) ||
                           !doc.findLanePoint(track, 7, base + step * 51, &p) || p.value != 40)) {
                    fail("ripple remove produced wrong content");
                    ok = false;
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 56, 64, &n) ||
                        !doc.findLanePoint(track, 7, base + step * 52, &p) || p.value != 40) {
                        fail("removeTimeRange was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Whole-song ripple: the globals travel too — a time signature
            // and a tempo change inside the range survive at the seam, later
            // notes shift, loop markers before the range stay put, and the
            // end-of-track ticks close the gap so the song gets shorter.
            if (ok) {
                const auto maxEnd = [&doc] {
                    uint64_t end = 0;
                    for (const SmfTrack &tr : doc.smf().tracks)
                        end = std::max(end, tr.endTick);
                    return end;
                };
                doc.setTimeSig(base + step * 62, 3, 2);
                doc.addLanePoint(track, DOC_CC_TEMPO, base + step * 63, 150);
                doc.addNotes(track, {{base + step * 66, 65, step, 90}});
                const uint64_t endBefore = maxEnd();
                const uint64_t loopStartBefore = doc.loopTick(false);
                SongDocument::RippleScope scope;
                scope.wholeSong = true;
                if (!doc.removeTimeRange(base + step * 61, base + step * 65, scope)) {
                    fail("whole-song removeTimeRange reported nothing to do");
                    ok = false;
                }
                mutateAndCheck("events unsorted after whole-song removeTimeRange");
                DocNote n;
                DocLanePoint p;
                bool sigAtSeam = false;
                for (const DocTimeSig &sig : doc.timeSigs()) {
                    if (sig.tick == base + step * 61 && sig.numerator == 3)
                        sigAtSeam = true;
                }
                if (ok &&
                    (!sigAtSeam || !doc.findLanePoint(track, DOC_CC_TEMPO, base + step * 61, &p) ||
                     p.value != 150 || !doc.findNote(track, base + step * 62, 65, &n) ||
                     maxEnd() != endBefore - step * 4 || doc.loopTick(false) != loopStartBefore)) {
                    fail("whole-song ripple produced wrong content");
                    ok = false;
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 66, 65, &n) || maxEnd() != endBefore) {
                        fail("whole-song removeTimeRange was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Voice ops: add, value-only modify (must not reorder within the
            // tick), move to a new tick, delete.
            if (ok) {
                doc.addLanePoint(track, DOC_CC_VOICE, base + step, 5);
                mutateAndCheck("events unsorted after voice add");
                DocLanePoint vc;
                if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step, &vc) || vc.value != 5) {
                    fail("voice change not found after add");
                    ok = false;
                } else {
                    doc.moveLanePoint(track, DOC_CC_VOICE, vc, vc.tick, 9);
                    if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step, &vc) ||
                        vc.value != 9) {
                        fail("voice value edit not applied");
                        ok = false;
                    } else {
                        doc.moveLanePoint(track, DOC_CC_VOICE, vc, base + step * 6, 9);
                        mutateAndCheck("events unsorted after voice move");
                        if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step * 6, &vc)) {
                            fail("voice change not found after move");
                            ok = false;
                        } else {
                            doc.deleteLanePoints(track, DOC_CC_VOICE, {vc});
                        }
                    }
                }
            }

            // Automation ops on the volume lane, plus tempo and pitch bend.
            if (ok) {
                doc.addLanePoint(track, 7, base + step * 2, 100);
                doc.addLanePoint(track, DOC_CC_BEND, base + step * 3, -1024);
                doc.addLanePoint(track, DOC_CC_TEMPO, base + step * 4, 150);
                mutateAndCheck("events unsorted after addLanePoint");
                DocLanePoint pt;
                if (!doc.findLanePoint(track, 7, base + step * 2, &pt) || pt.value != 100) {
                    fail("lane point not found after add");
                    ok = false;
                } else {
                    doc.moveLanePoint(track, 7, pt, base + step * 5, 90);
                    mutateAndCheck("events unsorted after moveLanePoint");
                    if (!doc.findLanePoint(track, 7, base + step * 5, &pt) || pt.value != 90) {
                        fail("lane point not found after move");
                        ok = false;
                    } else {
                        std::vector<DocLanePoint> doomed{pt};
                        DocLanePoint bendPt, tempoPt;
                        if (doc.findLanePoint(track, DOC_CC_BEND, base + step * 3, &bendPt))
                            doc.deleteLanePoints(track, DOC_CC_BEND, {bendPt});
                        if (doc.findLanePoint(track, DOC_CC_TEMPO, base + step * 4, &tempoPt))
                            doc.deleteLanePoints(track, DOC_CC_TEMPO, {tempoPt});
                        // Re-resolve: the deletes above shifted indices.
                        if (doc.findLanePoint(track, 7, base + step * 5, &pt))
                            doc.deleteLanePoints(track, 7, {pt});
                    }
                }
            }
        }

        // Track ops: create a track (seeded with its voice), edit on it,
        // delete it again.
        if (ok && doc.canAddTrack()) {
            const int newTrack = doc.addTrack(7);
            if (newTrack < 0) {
                fail("addTrack returned no track with canAddTrack true");
                ok = false;
            } else {
                mutateAndCheck("events unsorted after addTrack");
                const auto seed = doc.lanePoints(newTrack, DOC_CC_VOICE);
                if (ok && (seed.empty() || seed.front().tick != 0 || seed.front().value != 7)) {
                    fail("new track missing its seed voice");
                    ok = false;
                }
                DocNote note;
                if (ok) {
                    doc.addNote(newTrack, base, 72, step * 4, 100);
                    if (!doc.findNote(newTrack, base, 72, &note)) {
                        fail("note on new track not found");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.deleteTrack(newTrack);
                    mutateAndCheck("events unsorted after deleteTrack");
                    if (doc.findNote(newTrack, base, 72, &note)) {
                        fail("deleted track still has its note");
                        ok = false;
                    }
                }
            }
        }

        // Duplicating a song track: the copy lands on a fresh engine slot
        // carrying the same notes as the source.
        if (ok && track >= 0 && doc.canAddTrack()) {
            const auto srcNotes = doc.notesForTrack(track);
            const int copy = doc.duplicateTrack(track);
            mutateAndCheck("events unsorted after duplicateTrack");
            if (copy < 0) {
                fail("duplicateTrack returned no track with canAddTrack true");
                ok = false;
            } else if (copy == track) {
                fail("duplicateTrack returned the source track");
                ok = false;
            } else if (ok) {
                const auto copyNotes = doc.notesForTrack(copy);
                bool same = copyNotes.size() == srcNotes.size();
                for (size_t i = 0; same && i < copyNotes.size(); i++) {
                    same = copyNotes[i].tick == srcNotes[i].tick &&
                           copyNotes[i].key == srcNotes[i].key &&
                           copyNotes[i].duration == srcNotes[i].duration &&
                           copyNotes[i].velocity == srcNotes[i].velocity;
                }
                if (!same) {
                    fail("duplicated track's notes differ from the source");
                    ok = false;
                } else {
                    doc.deleteTrack(copy);
                    mutateAndCheck("events unsorted after deleting the duplicate");
                }
            }
        }

        // Reordering tracks: the chunk moves with its events and channel
        // bytes untouched, and the seq globals — tempo, time signatures,
        // loop markers — stay with chunk 0 even when the move displaces it
        // (mid2agb and the tempo lane read them only there).
        if (ok && doc.engineTrackCount() >= 2 && track >= 0) {
            doc.addLanePoint(track, DOC_CC_TEMPO, base + step * 110, 145);
            doc.setTimeSig(base + step * 112, 5, 2);
            const uint64_t loopStartBefore = doc.loopTick(false);
            const uint64_t loopEndBefore = doc.loopTick(true);
            const auto srcNotes = doc.notesForTrack(0);
            const uint8_t srcChannel = doc.channelFor(0);
            const int last = doc.engineTrackCount() - 1;
            const int countBefore = doc.undoStack()->count();
            doc.moveTrack(0, 0); // no-op guard
            if (doc.undoStack()->count() != countBefore) {
                fail("moveTrack onto itself pushed a command");
                ok = false;
            }
            auto seqChunkHas = [&doc](uint8_t metaType, uint64_t tick) {
                for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                    if (ev.isMeta() && ev.metaType == metaType && ev.tick == tick)
                        return true;
                }
                return false;
            };
            auto notesMatch = [&doc](int engineTrack, const std::vector<DocNote> &want) {
                const auto got = doc.notesForTrack(engineTrack);
                if (got.size() != want.size())
                    return false;
                for (size_t i = 0; i < got.size(); i++) {
                    if (got[i].tick != want[i].tick || got[i].key != want[i].key ||
                        got[i].duration != want[i].duration || got[i].velocity != want[i].velocity)
                        return false;
                }
                return true;
            };
            if (ok) {
                doc.moveTrack(0, last);
                mutateAndCheck("events unsorted after moveTrack");
            }
            if (ok && doc.undoStack()->count() != countBefore + 1) {
                fail("moveTrack was not a single undo command");
                ok = false;
            }
            if (ok && (!notesMatch(last, srcNotes) || doc.channelFor(last) != srcChannel)) {
                fail("moved track's notes or channel changed");
                ok = false;
            }
            if (ok &&
                (!seqChunkHas(0x51, base + step * 110) || !seqChunkHas(0x58, base + step * 112))) {
                fail("seq globals did not stay with chunk 0 across the move");
                ok = false;
            }
            if (ok &&
                (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
                fail("moveTrack lost the loop markers");
                ok = false;
            }
            if (ok) {
                doc.undoStack()->undo();
                if (!notesMatch(0, srcNotes)) {
                    fail("moveTrack undo did not restore the track order");
                    ok = false;
                } else {
                    doc.undoStack()->redo();
                }
            }
            if (ok) {
                doc.moveTrack(last, 0); // and back again
                mutateAndCheck("events unsorted after moveTrack back");
                if (!notesMatch(0, srcNotes) || !seqChunkHas(0x51, base + step * 110) ||
                    !seqChunkHas(0x58, base + step * 112)) {
                    fail("moving the track back did not restore its slot");
                    ok = false;
                }
            }
        }

        // Reordering must not confuse chunk-0 metas that only LOOK like loop
        // markers: a first-0x03 name of "[" is the track's name and travels
        // with its chunk (findLoopMarkerEvent skips it; imported files can
        // carry such names even though renameTrack refuses them), while the
        // combined "][" marker mid2agb reads stays with chunk 0.
        if (ok && doc.engineTrackCount() >= 2 && doc.smfTrackFor(0) == 0) {
            const int last = doc.engineTrackCount() - 1;
            const int indexBefore = doc.undoStack()->index();
            const uint64_t loopStartBefore = doc.loopTick(false);
            const uint64_t loopEndBefore = doc.loopTick(true);
            doc.renameTrack(0, QString()); // the "[" below must be the first 0x03
            SmfEvent name;
            name.tick = 0;
            name.status = 0xFF;
            name.metaType = 0x03;
            name.blob = QByteArrayLiteral("[");
            doc.insertRawEvent(0, name);
            SmfEvent marker;
            marker.tick = base;
            marker.status = 0xFF;
            marker.metaType = 0x06;
            marker.blob = QByteArrayLiteral("][");
            doc.insertRawEvent(0, marker);
            doc.moveTrack(0, last);
            mutateAndCheck("events unsorted after marker-name moveTrack");
            if (ok && doc.trackName(last) != QStringLiteral("[")) {
                fail("a '['-named track lost its name in the move");
                ok = false;
            }
            if (ok &&
                (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
                fail("a '[' track name was misread as a loop marker");
                ok = false;
            }
            bool combinedStayed = false;
            for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                if (ev.isMeta() && ev.metaType == 0x06 && ev.blob == "][")
                    combinedStayed = true;
            }
            if (ok && !combinedStayed) {
                fail("the '][' marker left chunk 0 in the move");
                ok = false;
            }
            while (doc.undoStack()->index() > indexBefore)
                doc.undoStack()->undo();
            mutateAndCheck("events unsorted after marker-name undo");
        }

        // Deleting an original track must not lose the loop markers, even
        // when they live in the removed chunk (they get rescued into the seq
        // chunk). Undone right away so the loop/cfg script below still runs
        // against the full song.
        if (ok && track >= 0) {
            const uint64_t loopStartBefore = doc.loopTick(false);
            const uint64_t loopEndBefore = doc.loopTick(true);
            doc.deleteTrack(track);
            mutateAndCheck("events unsorted after deleteTrack of a song track");
            if (ok &&
                (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
                fail("deleteTrack lost the loop markers");
                ok = false;
            }
            doc.undoStack()->undo();
        }

        // Track rename: set, no-op guard (trimmed match pushes nothing),
        // clear, and undo back through the chunk's Track Name meta (0x03).
        if (ok && track >= 0) {
            doc.renameTrack(track, QStringLiteral("editcheck name"));
            mutateAndCheck("events unsorted after renameTrack");
            if (ok && doc.trackName(track) != QStringLiteral("editcheck name")) {
                fail("rename not applied");
                ok = false;
            }
            // The header paints from the playable projection, not the raw
            // SMF — the new meta must land where MidiTimeline's reader
            // (first 0x03 in the chunk) finds it.
            if (ok) {
                const auto timeline = doc.buildTimeline(48000.0);
                if (!timeline || timeline->tracks[track].name != QStringLiteral("editcheck name")) {
                    fail("renamed track not visible in the timeline projection");
                    ok = false;
                }
            }
            if (ok) {
                const int count = doc.undoStack()->count();
                doc.renameTrack(track, QStringLiteral("  editcheck name  "));
                if (doc.undoStack()->count() != count) {
                    fail("no-op rename pushed an undo command");
                    ok = false;
                }
            }
            if (ok) {
                // mid2agb reads any text meta whose whole text is a marker
                // as a loop/label command; those names must be refused.
                const int count = doc.undoStack()->count();
                doc.renameTrack(track, QStringLiteral("["));
                doc.renameTrack(track, QStringLiteral(" ][ "));
                if (doc.undoStack()->count() != count ||
                    doc.trackName(track) != QStringLiteral("editcheck name")) {
                    fail("loop-marker name was not refused");
                    ok = false;
                }
            }
            if (ok) {
                doc.renameTrack(track, QString());
                if (!doc.trackName(track).isEmpty()) {
                    fail("empty rename did not clear the name");
                    ok = false;
                }
            }
            if (ok) {
                doc.undoStack()->undo();
                if (doc.trackName(track) != QStringLiteral("editcheck name")) {
                    fail("rename undo did not restore the name");
                    ok = false;
                } else {
                    doc.undoStack()->redo();
                }
            }
        }

        // Time signatures: create, modify in place, move, delete.
        if (ok) {
            auto findSig = [&doc](uint64_t tick, DocTimeSig *out) {
                for (const DocTimeSig &sig : doc.timeSigs()) {
                    if (sig.tick == tick) {
                        *out = sig;
                        return true;
                    }
                }
                return false;
            };
            const size_t sigsBefore = doc.timeSigs().size();
            doc.setTimeSig(base, 3, 3); // 3/8
            mutateAndCheck("events unsorted after setTimeSig");
            DocTimeSig sig;
            if (ok && (!findSig(base, &sig) || sig.numerator != 3 || sig.denomPow2 != 3)) {
                fail("time signature not found after set");
                ok = false;
            }
            if (ok) {
                doc.setTimeSig(base, 7, 2); // 7/4, replacing in place
                if (!findSig(base, &sig) || sig.numerator != 7 || sig.denomPow2 != 2 ||
                    doc.timeSigs().size() != sigsBefore + 1) {
                    fail("time signature edit did not replace in place");
                    ok = false;
                }
            }
            if (ok) {
                doc.moveTimeSig(base, base + step * 4);
                mutateAndCheck("events unsorted after moveTimeSig");
                if (findSig(base, &sig) || !findSig(base + step * 4, &sig) || sig.numerator != 7) {
                    fail("time signature not moved");
                    ok = false;
                }
            }
            if (ok) {
                doc.deleteTimeSig(base + step * 4);
                if (findSig(base + step * 4, &sig)) {
                    fail("time signature not deleted");
                    ok = false;
                }
            }
        }

        // Loop markers: move an existing one / create where absent, and cfg.
        const uint64_t loopStart = doc.loopTick(false);
        doc.setLoopTick(false, loopStart == UINT64_MAX ? 0 : int64_t(loopStart + step));
        mutateAndCheck("events unsorted after setLoopTick");
        SongCfg cfg = doc.cfg();
        cfg.masterVolume = cfg.masterVolume == 80 ? 90 : 80;
        doc.setCfg(cfg);

        // Undo everything: the document must be byte-identical to the load.
        while (doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        if (doc.smf().write() != baseline)
            fail("undo-all did not restore the original bytes");
        else if (doc.cfg().masterVolume != song.cfg.masterVolume)
            fail("undo-all did not restore song settings");
        else {
            // Redo everything, then undo again: redo must be deterministic.
            while (doc.undoStack()->canRedo())
                doc.undoStack()->redo();
            const QByteArray redone = doc.smf().write();
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (doc.smf().write() != baseline)
                fail("undo after redo did not restore the original bytes");
            else if (redone == baseline && track >= 0)
                fail("redo-all produced no change (edits were lost)");
        }

        checked++;
    }

    // Format 0 is coerced to format 1 at load (convertToFormat1): the
    // single chunk splits into a conductor chunk 0 carrying every
    // non-channel meta, then one chunk per used channel in ascending
    // channel order — the order mid2agb emits agb tracks for a format-0
    // file, so the build output is unchanged (--roundtrip proves that end
    // to end). Channel-Prefix names (0x20 + 0x03) become ordinary chunk
    // names. Synthetic file — decomp projects are format 1 in practice.
    {
        auto fail0 = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL format0-convert: %s\n", what);
            failures++;
        };
        SmfFile smf;
        smf.format = 0;
        smf.division = 24;
        SmfTrack tr;
        auto chEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = status;
            ev.data0 = d0;
            ev.data1 = d1;
            return ev;
        };
        auto meta = [](uint64_t tick, uint8_t type, QByteArray blob) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = 0xFF;
            ev.metaType = type;
            ev.blob = std::move(blob);
            return ev;
        };
        // Global metas, a prefixed per-channel name, and notes on the
        // non-contiguous channels 1, 4, 7 (so slot order = channel order is
        // visible). The unprefixed 0x03 precedes the prefix — after a
        // channel prefix, names are scoped until the next channel event.
        // Three preservation cases ride along: a prefixed non-name text
        // meta (0x04 "Gtr" → travels to channel 4's chunk), a prefixed
        // MARKER-text 0x03 (":" → stays in the conductor chunk with a
        // prefix, where mid2agb reads markers), and a prefixed name on the
        // silent channel 9 ("Ambient" → a name-only chunk rather than
        // silent data loss).
        tr.events.push_back(meta(0, 0x51, QByteArray("\x07\xA1\x20", 3))); // 120 BPM
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Song")));
        tr.events.push_back(meta(0, 0x20, QByteArray(1, char(4))));
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Lead")));
        tr.events.push_back(meta(0, 0x04, QByteArrayLiteral("Gtr")));
        tr.events.push_back(chEvent(0x91, 0, 60, 100));
        tr.events.push_back(chEvent(0x94, 0, 64, 100));
        tr.events.push_back(chEvent(0x97, 0, 67, 100));
        tr.events.push_back(meta(12, 0x06, QByteArrayLiteral("[")));
        tr.events.push_back(meta(12, 0x20, QByteArray(1, char(7))));
        tr.events.push_back(meta(12, 0x03, QByteArrayLiteral(":")));
        tr.events.push_back(chEvent(0x81, 24, 60, 0));
        tr.events.push_back(chEvent(0x84, 24, 64, 0));
        tr.events.push_back(chEvent(0x87, 24, 67, 0));
        tr.events.push_back(meta(36, 0x06, QByteArrayLiteral("]")));
        tr.events.push_back(meta(36, 0x20, QByteArray(1, char(9))));
        tr.events.push_back(meta(36, 0x03, QByteArrayLiteral("Ambient")));
        tr.endTick = 48;
        smf.tracks.push_back(tr);
        const QByteArray originalBytes = smf.write();

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/format0.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("format0");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            fail0("could not write/load the synthetic format-0 file");
        if (ok && (doc.smf().format != 1 || !doc.smf().wasFormat0 || doc.smf().tracks.size() != 5 ||
                   doc.engineTrackCount() != 3)) {
            fail0("load did not split into conductor + one chunk per channel");
            ok = false;
        }
        if (ok && (doc.channelFor(0) != 1 || doc.channelFor(1) != 4 || doc.channelFor(2) != 7 ||
                   doc.smfTrackFor(0) != 1)) {
            fail0("converted chunks not in ascending channel order");
            ok = false;
        }
        if (ok) {
            const auto note = [&doc](int track) {
                const auto notes = doc.notesForTrack(track);
                return notes.size() == 1 && notes[0].duration == 24 ? int(notes[0].key) : -1;
            };
            if (note(0) != 60 || note(1) != 64 || note(2) != 67) {
                fail0("notes did not land on their channel's chunk");
                ok = false;
            }
        }
        if (ok && (doc.trackName(1) != QStringLiteral("Lead") || !doc.trackName(0).isEmpty() ||
                   !doc.trackName(2).isEmpty())) {
            fail0("the prefixed name did not become its channel chunk's name");
            ok = false;
        }
        if (ok) {
            auto hasMeta = [](const SmfTrack &track, uint8_t type, const char *text) {
                for (const SmfEvent &ev : track.events)
                    if (ev.isMeta() && ev.metaType == type && ev.blob == text)
                        return true;
                return false;
            };
            const auto &chunks = doc.smf().tracks;
            // Chunk layout: 0 conductor, 1..3 channels 1/4/7, 4 the
            // name-only channel-9 chunk.
            if (!hasMeta(chunks[2], 0x04, "Gtr")) {
                fail0("prefixed instrument-name meta did not travel to its channel chunk");
                ok = false;
            }
            if (ok && (!hasMeta(chunks[0], 0x03, ":") || hasMeta(chunks[3], 0x03, ":"))) {
                fail0("prefixed marker-text meta did not stay in the conductor chunk");
                ok = false;
            }
            if (ok) {
                // ...and it kept a prefix, so no reader mistakes it for the
                // conductor's name.
                bool prefixedMarker = false;
                const auto &evs = chunks[0].events;
                for (size_t i = 1; i < evs.size(); i++) {
                    if (evs[i].isMeta() && evs[i].metaType == 0x03 && evs[i].blob == ":" &&
                        evs[i - 1].isMeta() && evs[i - 1].metaType == 0x20)
                        prefixedMarker = true;
                }
                if (!prefixedMarker) {
                    fail0("the conductor's marker-text meta lost its prefix");
                    ok = false;
                }
            }
            if (ok && !hasMeta(chunks[4], 0x03, "Ambient")) {
                fail0("prefixed name on a silent channel was lost (no name-only chunk)");
                ok = false;
            }
            if (ok) {
                for (const SmfEvent &ev : chunks[4].events) {
                    if (ev.isChannel()) {
                        fail0("the name-only chunk grew channel events");
                        ok = false;
                    }
                }
            }
        }
        if (ok) {
            // Prefixes are rewritten into chunk structure everywhere except
            // the conductor's re-prefixed marker pair (the ":" case above).
            for (size_t t = 0; t < doc.smf().tracks.size(); t++) {
                const SmfTrack &track = doc.smf().tracks[t];
                for (const SmfEvent &ev : track.events) {
                    if (t > 0 && ev.isMeta() && ev.metaType == 0x20) {
                        fail0("a Channel Prefix meta survived in a channel chunk");
                        ok = false;
                    }
                }
                if (track.endTick != 48) {
                    fail0("a converted chunk lost the end-of-track tick");
                    ok = false;
                }
            }
            for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                if (ev.isChannel()) {
                    fail0("a channel event landed in the conductor chunk");
                    ok = false;
                }
            }
        }
        if (ok && (doc.loopTick(false) != 12 || doc.loopTick(true) != 36 ||
                   doc.lanePoints(0, DOC_CC_TEMPO).size() != 1)) {
            fail0("seq globals did not stay readable in chunk 0");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->usedTrackCount != 3 ||
                timeline->tracks[1].name != QStringLiteral("Lead") ||
                timeline->loopStartTick != 12) {
                fail0("conversion not reflected in the timeline projection");
                ok = false;
            }
        }
        if (ok && !tracksSorted(doc.smf())) {
            fail0("events unsorted after conversion");
            ok = false;
        }
        const QByteArray converted = ok ? doc.smf().write() : QByteArray();
        if (ok) {
            // SmfFile::read is the conversion choke point: re-reading the
            // original bytes yields the converted file directly, and doing
            // it twice proves determinism (an untouched file re-converts
            // identically next open). Converting the already-converted file
            // is a no-op (fixed point).
            SmfFile redo;
            QString rerror;
            if (!SmfFile::read(originalBytes, &redo, &rerror)) {
                fail0("could not re-read the original bytes");
                ok = false;
            } else {
                if (!redo.wasFormat0 || redo.write() != converted) {
                    fail0("read() did not coerce deterministically");
                    ok = false;
                }
                convertToFormat1(&redo);
                if (ok && redo.write() != converted) {
                    fail0("conversion of a converted file is not a no-op");
                    ok = false;
                }
            }
        }
        if (ok) {
            // The editing layer runs on the converted shape: undo-all
            // restores the converted baseline, not the format-0 bytes.
            doc.renameTrack(0, QStringLiteral("Bass"));
            doc.moveTrack(0, 2);
            if (doc.trackName(2) != QStringLiteral("Bass")) {
                fail0("edits after conversion did not behave as format 1");
                ok = false;
            }
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (ok && doc.smf().write() != converted)
                fail0("undo-all did not restore the converted baseline");
        }
    }

    // A PREFIXED 0x03 carrying marker text has no name position (a chunk's
    // name is its first unprefixed 0x03), so every classifier
    // (MidiTimeline::build, findLoopMarkerEvent, trackNameLoc) reads it as
    // a marker — mid2agb's rule: a foreign format-1 file whose chunk opens
    // with a prefixed 0x03 "[" has a loop the playback timeline, the loop
    // UI, and the compiled ROM all agree on, and renaming the track edits
    // the real name meta, never the marker.
    {
        auto failM = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL marker-vs-name: %s\n", what);
            failures++;
        };
        auto chEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = status;
            ev.data0 = d0;
            ev.data1 = d1;
            return ev;
        };
        auto meta = [](uint64_t tick, uint8_t type, QByteArray blob) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = 0xFF;
            ev.metaType = type;
            ev.blob = std::move(blob);
            return ev;
        };
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        SmfTrack tr;
        tr.events.push_back(meta(0, 0x20, QByteArray(1, char(0))));
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("[")));
        tr.events.push_back(chEvent(0x90, 0, 60, 100)); // clears the prefix
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Real")));
        tr.events.push_back(chEvent(0x80, 24, 60, 0));
        tr.endTick = 24;
        smf.tracks.push_back(tr);

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/marker.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("marker");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            failM("could not write/load the synthetic file");
        if (ok && doc.trackName(0) != QStringLiteral("Real")) {
            failM("marker-text 0x03 was mistaken for the track name");
            ok = false;
        }
        if (ok && doc.loopTick(false) != 0) {
            failM("the loop UI did not see the prefixed marker");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->loopStartTick != 0) {
                failM("playback did not see the prefixed marker (build/UI disagree)");
                ok = false;
            }
        }
        if (ok) {
            doc.renameTrack(0, QStringLiteral("Renamed"));
            if (doc.trackName(0) != QStringLiteral("Renamed") || doc.loopTick(false) != 0) {
                failM("rename clobbered the loop marker instead of the name");
            }
        }
    }

    // Same-tick duplicate setters (a foreign file's repeated channel-init
    // block): the loader preserves them — sanitizing is the import wizard's
    // job — but every editing surface resolves the run LAST-wins, matching
    // playback, and writing onto an occupied tick replaces what sits there
    // instead of stacking another duplicate. Undo restores the duplicates.
    {
        auto failD = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL same-tick-dup: %s\n", what);
            failures++;
        };
        auto chEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = status;
            ev.data0 = d0;
            ev.data1 = d1;
            return ev;
        };
        auto meta = [](uint64_t tick, uint8_t type, QByteArray blob) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = 0xFF;
            ev.metaType = type;
            ev.blob = std::move(blob);
            return ev;
        };
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        SmfTrack conductor;
        conductor.events.push_back(meta(0, 0x51, QByteArray("\x07\xA1\x20", 3))); // 120 BPM
        conductor.events.push_back(meta(0, 0x51, QByteArray("\x06\x1A\x80", 3))); // 150 BPM
        conductor.endTick = 96;
        smf.tracks.push_back(conductor);
        SmfTrack ch0;
        ch0.events.push_back(chEvent(0xC0, 0, 5, 0));
        ch0.events.push_back(chEvent(0xB0, 0, 7, 100));
        ch0.events.push_back(chEvent(0xC0, 0, 9, 0));
        ch0.events.push_back(chEvent(0xB0, 0, 7, 80));
        ch0.events.push_back(chEvent(0x90, 0, 60, 100));
        ch0.events.push_back(chEvent(0x80, 96, 60, 0));
        ch0.endTick = 96;
        smf.tracks.push_back(ch0);

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/dups.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("dups");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            failD("could not write/load the synthetic file");
        const QByteArray baseline = ok ? doc.smf().write() : QByteArray();
        const auto ccPointsAt = [&doc](uint8_t cc, uint64_t tick) {
            std::vector<DocLanePoint> at;
            for (const DocLanePoint &pt : doc.lanePoints(0, cc)) {
                if (pt.tick == tick)
                    at.push_back(pt);
            }
            return at;
        };
        if (ok && (doc.lanePoints(0, DOC_CC_VOICE).size() != 2 || ccPointsAt(7, 0).size() != 2)) {
            failD("the loader no longer preserves same-tick duplicates");
            ok = false;
        }
        DocLanePoint pt;
        if (ok && (!doc.findLanePoint(0, 7, 0, &pt) || pt.value != 80)) {
            failD("findLanePoint did not return the last CC at the tick");
            ok = false;
        }
        if (ok && (!doc.findLanePoint(0, DOC_CC_VOICE, 0, &pt) || pt.value != 9)) {
            failD("findLanePoint did not return the last program at the tick");
            ok = false;
        }
        if (ok && (!doc.findLanePoint(0, DOC_CC_TEMPO, 0, &pt) || pt.value != 150)) {
            failD("findLanePoint did not return the last tempo at the tick");
            ok = false;
        }
        if (ok) {
            // A value edit targets the winner AND heals the shadowed
            // duplicate under it, in one undoable edit.
            doc.findLanePoint(0, 7, 0, &pt);
            doc.moveLanePoint(0, 7, pt, 0, 60);
            const auto after = ccPointsAt(7, 0);
            if (after.size() != 1 || after[0].value != 60) {
                failD("a value edit left the shadowed duplicate behind");
                ok = false;
            }
            doc.undoStack()->undo();
            const auto restored = ccPointsAt(7, 0);
            if (ok &&
                (restored.size() != 2 || restored[0].value != 100 || restored[1].value != 80)) {
                failD("undo did not restore the shadowed duplicate");
                ok = false;
            }
        }
        if (ok) {
            // addLanePoint replaces the whole run on its tick.
            doc.addLanePoint(0, 7, 0, 70);
            if (ccPointsAt(7, 0).size() != 1) {
                failD("addLanePoint stacked another duplicate on the tick");
                ok = false;
            }
            doc.undoStack()->undo();
        }
        if (ok) {
            // A cross-tick move landing on an occupied tick replaces the
            // run there too.
            doc.addLanePoint(0, 7, 48, 55);
            doc.findLanePoint(0, 7, 48, &pt);
            doc.moveLanePoint(0, 7, pt, 0, 55);
            if (ccPointsAt(7, 0).size() != 1 || !ccPointsAt(7, 48).empty()) {
                failD("a cross-tick move did not replace the destination run");
                ok = false;
            }
        }
        if (ok) {
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (doc.smf().write() != baseline)
                failD("undo-all did not restore the duplicated file byte-for-byte");
        }
    }

    std::printf("editcheck: %d songs in %lld ms\n", checked, (long long)timer.elapsed());
    std::printf("editcheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
