# Delete Time producer

## 1. Context

Implement [spec.md](spec.md)'s single collision rule for ripple deletion.
Inherit [Global Constraints](plan.md#global-constraints). Consume Task 2's
private `SongDocument::noteEditAdmissible` predicate. Fork-main
`TimeEditor::remove` shifts every paired note starting at or after the range
end left by the span while leaving earlier-starting notes untouched, so a
same-pitch straddle corrupts pairing: with A `[0,100)` and B `[110,120)`,
deleting `[20,50)` leaves A unchanged while B lands on `[80,90)` inside A —
A's release at 100 becomes shared/unmatched. This task refuses that edit
upfront; non-colliding ripples are unchanged.

## 2. Exact write set

- `src/core/songdocument_timeeditor.cpp`
- `src/checks/editcheck/tst_songdocument_timerange.cpp`

## 3. Prerequisites

Task 2: `noteEditAdmissible` exists (exempt-by-NoteId, identical spans
refuse). Task 1's oracle is used in this task's assertions.

## 4. Interface contract

`SongDocument::removeTimeRange` / `TimeEditor::remove` signatures, the
`TimeEditPlan`/`TimeEventRef` machinery, seam-keeper stream logic, XCMD
relocation records, `xcmdAssembleOps` assembly and ordering, tempo removal,
track-end closing and all no-op guards are unchanged. One gate is added:

- Before any removals/inserts are assembled, collect the ripple's note
  participants and their final spans. Every paired note in `plan.notes`
  with `note.tick >= s` is a participant and goes into `editNotes` (exempt
  by `NoteId`): notes starting inside `[s, e)` are deleted by the edit, and
  notes starting at or after `e` are shifted left by the span — both are
  moved-or-removed participants, never stationary. Only the shifted notes
  also contribute `written` spans: for each paired note with
  `note.tick >= e`, the half-open `[note.tick - span, endEventTick - span)`
  (plain subtraction — both endpoints are at or after `e`, so neither can
  underflow; `endEventTick` is the note's own end-event tick, matching what
  `appendTimeEditMove` re-emits). Only notes starting before `s` —
  including straddlers — are stationary and are only ever read. Call
  `noteEditAdmissible(written, editNotes)`; on refusal `remove()` returns
  false before building any ops, leaving bytes, revision, undo state and
  every note untouched. Omitting shifted notes from `editNotes` is a defect:
  a shifted note whose final span intersects its own old span (duration
  longer than the deleted span) would then refuse against itself.
- Unterminated participants and the raw orphan note-event pass keep their
  fork-main handling and contribute no span; pre-existing raw material is
  out of scope.

## 5. Implementation steps

1. Add the failing straddle row first (matrix below), capturing bytes,
   revision and undo state before the refused delete.
2. Insert the participant-span collection and the admission gate after
   `buildTimeEditPlan()` and before the first `appendTimeEdit*` call; reuse
   the plan's already-resolved notes rather than re-scanning.
3. Complete the matrix and run the named checks.

## 6. Acceptance predicate
Through unchanged `removeTimeRange`: the straddle `[0,100)` /
`[110,120)` delete `[20,50)` returns false with A, B, bytes, revision and
undo/redo state exactly unchanged; the same geometry with B far enough
right still ripples (B shifts left by the span, A untouched,
`songdocument_test::notePairsConsistent` true, one undo command restores
exact bytes); a shifted note longer than the deleted span — its final span
overlapping only its own old span — is accepted, proving shifted
participants are exempted by `NoteId`; lane-only scopes, whole-song
scopes, tempo and no-op refusals keep their existing contracts.

Matrix (existing synthetic slots, extended bodies — no new or renamed
slots):

| Slot | Added required cases |
| --- | --- |
| `timeRangeNoOps` / timerange | Straddle refusal (false return, zero state change, both notes intact); non-colliding same-pitch ripple success with oracle + byte-exact undo/redo, including a long-note accepted ripple where the shifted note's duration exceeds the deleted span so its final span overlaps only its own old span (and, where reachable, destinations intersecting another participant's old position) — proving shifted participants are exempted by `NoteId`. |
| `timeRangeWholeSong` / timerange | One whole-song-scoped straddle refusal row (scope covers all tracks; refusal still zero-state). |

NAMED CHECKS (controller under SHARED_TREE; implementer on its settled
tree):

```sh
deno task verify --filter editcheck --qt timeRangeNoOps timeRangeWholeSong
deno task verify --filter editcheck --verbose
```

`timeRangeRemove` (corpus, `tst_songdocument_songtime.cpp`) is outside this
write set and must stay green unchanged — its corpus geometry deletes
across different pitches, which remains admitted.

## 7. Task-specific constraints

- Do not edit `tst_songdocument.h` (Task 2 owns it): coverage goes into the
  two existing synthetic slots' bodies only.
- No trimming of earlier notes, ever: the fork-main corruption is fixed by
  refusal, not by shortening A. If users later want the trim variant it
  re-enters as its own plan.
- `insertBlankTime` and `duplicateTimeRange` (same file) are non-goals;
  their seam-split construction is untouched.
