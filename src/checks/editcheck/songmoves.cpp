#include "checks/editcheck/support.h"

namespace editcheck {
bool checkSongNoteMoveContracts(SongEditScenario &scenario)
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
    // the merge stops at the saved document state (a save between
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
            } else if (!doc.findNote(track, base + step * 100, 71, &m) || m.duration != step * 2 ||
                       !doc.findNote(track, base + step * 100, 70, &s) || s.duration != step * 4) {
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
            doc.didSave(doc.captureSaveSnapshot(), true);
            doc.moveNotes({m}, 0, 1, true);
            if (doc.undoStack()->count() != countBefore + 2) {
                fail("mergeable move merged across the saved document state");
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
        if (!doc.findNote(track, tA, 115, &a) || !doc.findNote(track, tA + step * 20, 117, &b)) {
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
            if (ok && (!doc.findNote(track, tA, 118, &a) || a.duration != step * 4 ||
                       a.velocity != 100 || doc.findNote(track, tA, 115, &a) ||
                       !doc.findNote(track, tA + step * 20, 114, &b) || b.duration != step * 2 ||
                       b.velocity != 90 || doc.findNote(track, tA + step * 20, 117, &b))) {
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
            } else if (!doc.findNote(track, tA, 115, &a) || a.duration != step * 4 ||
                       a.velocity != 100 || !doc.findNote(track, tA + step * 20, 117, &b) ||
                       b.duration != step * 2 || b.velocity != 90) {
                fail("moveNotesToPitches undo did not restore bytes and identities");
                ok = false;
            } else {
                doc.undoStack()->redo();
                if (ok &&
                    (doc.smf().write() != moved || !doc.findNote(track, tA, 118, &a) ||
                     a.duration != step * 4 || !doc.findNote(track, tA + step * 20, 114, &b) ||
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
                    !doc.findNote(track, tA + step * 20, 114, &b) || doc.smf().write() != atStart) {
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
                if (!doc.findNote(track, base + step * 138, 119, &m6) || m6.duration != step * 4 ||
                    !doc.findNote(track, base + step * 142, 119, &s6) || s6.duration != step * 2 ||
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
                if (!doc.findNote(track, base + step * 138, 118, &m6) || m6.duration != step * 4 ||
                    !doc.findNote(track, base + step * 140, 119, &s6) || s6.duration != step * 4) {
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
            if (ok && (doc.smf().write() != before || !doc.findNote(track, tA, 118, &x) ||
                       !doc.findNote(track, tA + step * 20, 114, &y))) {
                fail("rejected move changed the SMF");
                ok = false;
            }
        }
    }

    return ok;
}

} // namespace editcheck
