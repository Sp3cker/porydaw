# UI consumers and manual

## 1. Context

Implement [spec.md](spec.md)'s user-visible refusal contract. Inherit
[Global Constraints](plan.md#global-constraints). Consume Task 2's public
rejection contract (refused void mutations leave the revision unchanged;
`addNotes` refuses overlapping/identical paste notes; `moveNotes` refuses
colliding transposes). Fork-main consumers of those mutations still perform
success-only effects unconditionally: `pasteRangeAtEditCursor` clears the
time selection, advances the edit cursor and announces success;
`pasteFromClipboard` re-selects from `insertedNoteIds` (empty after a
refusal, silently clearing the selection), advances the cursor and
announces; `transposeTimeSelection` scrolls and announces; `nudgeTimeSelection`
moves the selection band; and `PianoRoll::transposeSelection` reveals and
auditions the requested destination key even when `moveNotes` refused —
every one of them must tell the truth. This task also deletes the rollcheck
duplicate-identity coverage that pinned twin-note admission and documents
the single rule in the manual.

## 2. Exact write set

- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview/pianoroll_commands.cpp`
- `src/checks/rollcheck/timemenu.cpp`
- `src/checks/rollcheck/tst_pianoroll.h`
- `src/checks/rollcheck/identity.cpp`
- `docsrc/manual/piano-roll.md`

## 3. Prerequisites

Task 2: `addNotes`/`moveNotes` refusals are live with zero state change,
and identical duplicate inserts refuse. (Tasks 3-4 wire `applyRangeEdit` /
`moveRange` / `removeTimeRange` refusals; this task's gates over those
mutations are written here but their live-fire scenarios are the
controller's settled-tree run — see Acceptance.)

## 4. Interface contract

Public `SongView` signatures stay unchanged. Edit bodies only:

- `pasteRangeAtEditCursor`, `pasteFromClipboard`, `transposeTimeSelection`,
  `nudgeTimeSelection`: capture `m_document.revision()` immediately before
  the mutation and gate every success-only effect on the revision having
  changed. A refused paste retains note/time selection, edit cursor and
  camera and emits no success announcement; a refused transpose does not
  scroll or announce; a refused nonempty nudge keeps its selection band.
  Accepted edits keep their existing tiling, selection, cursor and
  announcement behavior exactly.
- `nudgeTimeSelection` keeps the intentional empty-band exception: when the
  gathered edit is genuinely empty (no notes, points or tempo), the band
  still moves. Revision alone cannot distinguish that case from refused
  content — keep the existing emptiness check, do not replace scope rules
  with revision checks.
- `foldTransposeSelection` (already boolean-gated) stays unchanged.
  `PianoRoll::transposeSelection` is not yet gated and must be migrated:
  capture the document revision immediately before `moveNotes` and return
  early on an unchanged revision — before `ensureKeyVisible`, `auditionKey`,
  `m_auditioned` and
  the success-only update — so a refused ordinary selected-note transpose
  neither reveals nor auditions the refused destination. Accepted
  transposes keep the existing reveal/audition/update behavior exactly.
  `removeTimeSelectionContents` keeps its announce-and-early-return shape
  on a false `removeTimeRange`, but that false return now covers both a
  genuine no-op and a collision refusal, so its message must be one
  neutral sentence true of either cause (e.g. that Delete Time made no
  change because the shift would overlap another note or there is nothing
  to remove) — never a bare claim that the selection was empty. No new
  result type, status channel or dialog distinguishes the two causes.
- No rejection dialog, status channel, synthetic key routing, public result
  type, or generic UI mutation wrapper.

Rollcheck: add slot `rejectedNotePastePreservesViewState` (declaration in
`tst_pianoroll.h`, body in `timemenu.cpp`, reusing that file's shown
fixture, `clipcheck_support::ClipboardStateGuard`, typed clip writer and
menu/key routing). Rewrite `duplicateNoteIdentity` as
`noteIdentityEditDiscipline` (rename across both files): seed two
same-tick different-key notes instead of the refused twin insert, and keep
the salvageable contract — distinct stable IDs, a one-ID edit changing only
that note, selection surviving the edit, undo restoring both notes, plain
and cross-track header clicks clearing note selection. The twin-admission
assertions are deleted; nothing re-pins duplicate acceptance.

Manual (`docsrc/manual/piano-roll.md`): state the single rule in the note
editing sections — an edit that would make two notes overlap on the same
track and pitch (drawing over a note, moving or transposing onto one,
pasting overlapping or identical copies, grouped resizing into a sibling)
is refused and nothing changes; adjacent back-to-back notes are legal;
resize preview may show attempted geometry during a drag and snaps back
when the commit is refused. Amend the Delete Time and Paste-at-edit-cursor
prose with the corresponding refusal sentences (a straddling delete that
would push a note onto an earlier same-pitch note is refused; a conflicting
paste changes nothing — no selection loss, no cursor movement). Remove any
cap/trim wording if present; do not describe cleanup or import repair as
shipped.

## 5. Implementation steps

1. Apply the revision gates to the two paste paths, then transpose and
   nudge with the explicit empty-band exception, and gate
   `PianoRoll::transposeSelection`'s reveal/audition/update effects on the
   accepted revision as specified above; each check stays adjacent to its
   mutation.
2. Add `rejectedNotePastePreservesViewState`: drive the real Paste command
   with a plain-note clip whose same-pitch spans conflict at the cursor;
   observe unchanged document/undo/revision, retained selection and cursor,
   and no success announcement (public signals/state, not message-text
   matching); a subsequent valid paste selects/advances/undoes normally;
   clipboard state restored on all exits. Extend with a refused transpose
   (selection-driven) where reachable without inventing private access,
   followed by an accepted transpose as positive control — assert the
   success feedback and revision change prove the stroke was not
   swallowed, and that undo/redo preserves the accepted move's redo
   branch. Cover the ordinary selected-note transpose path specifically:
   a selected note whose `moveNotes` transpose collides with a stationary
   note must produce no reveal toward and no audition of the refused
   destination, followed by an accepted ordinary transpose as positive
   control.
3. Rewrite and rename `duplicateNoteIdentity` per the contract.
4. Update the manual sections.

## 6. Acceptance predicate

Task 2's refusal reaches users without fake cursor movement, selection
changes, reveals, auditions or success messages; accepted commands keep
their existing behavior; a false `removeTimeRange` reports that Delete
Time made no change in one neutral sentence true of both the no-op and
the refused shift, without asserting the selection was empty; the manual
matches the shipped surface; rollcheck no longer pins duplicate-note
admission.

NAMED CHECKS (controller under SHARED_TREE; implementer on its settled
tree):

```sh
deno task verify --filter rollcheck --exclude rollcheck-static --qt rejectedNotePastePreservesViewState noteIdentityEditDiscipline
deno task verify --filter rollcheck --verbose
```

`rollcheck` requires an available native desktop; a skipped native scenario
is not proof. Implementer-runnable scenarios use only Task-2-backed
refusals (plain-note paste, transpose); the range-paste and nudge refusal
paths added to `rangeedit.cpp` are exercised by the controller's
settled-tree full run once Tasks 3-4 land, and must not be asserted here.

## 7. Task-specific constraints

- No preview redesign and no preview plumbing: a provisional drag shows
  attempted geometry and the committed view shows the accepted result or
  unchanged geometry on refusal; `pianoroll_commands.cpp` is touched only
  for the `transposeSelection` revision gate — no other `pianoroll*.cpp`
  file is touched and no document preview API is added.
- A document no-op must never be reported as a successful insertion; do not
  keep false-success behavior for symmetry with older overflow refusals.
- Preserve the intentional empty time-selection band movement.
- Do not edit `tst_songdocument.h` or any editcheck file (Tasks 2-4 own
  them).
