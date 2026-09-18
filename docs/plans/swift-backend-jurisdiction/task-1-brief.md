# Task 1: Undoable PianoGrid gesture commits

## Context

First task of the jurisdiction wave ([plan](plan.md), [spec](spec.md)).
`PianoGrid.endPointer` (~L352) mutates `notes` in place and
`deleteSelection`/`doublePointer`/`commitPitchCurves` do the same — every
edit is permanent. Production edits are undoable song mutations
(`SongDocument`: one undoable command per gesture commit, monotonic
`revision`, exact restore). This task introduces the Swift undo
representation ([spec](spec.md) §1 D2, §3.1) so a later cutover to `SongDocument`
deletes the stack and keeps the contract. Producer for Task 2 (its cancel
rows assert `revision` invariance through cancellation) and Task 5.

## Exact write set

Created:
- `src/ui/songview/quick/swift-grid-prototype/GridUndo.swift`
- `src/checks/swiftgridprototype/jurisdiction_smoke.cpp`

Edited:
- `src/ui/songview/quick/swift-grid-prototype/PianoGrid.swift`
- `src/checks/swiftgridprototype/grid_smoke.h` — declare `verifyGridUndo(QQuickWindow *, QObject *)`
- `src/checks/swiftgridprototype/grid_smoke.cpp` — call it from `exercise()` after `verifyGridInteractions`
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` — add `jurisdiction_smoke.cpp` to `swift_grid_smoke` sources

## Prerequisites

None (first task).

## Interface contract

- `GridUndo.swift` exactly as spec §3.1: `GridNoteSnapshot`,
  `GridEditCommand` (`.notes` / `.controllerEvents` snapshot pairs),
  `GridUndoStack` with `push`/`undo`/`redo`/`removeAll`,
  `undoCount`/`redoCount`. `push` of a before == after pair is a no-op.
- `PianoGrid` gains QtBridge-visible `canUndo`, `canRedo`, `revision`
  (`public private(set) var`, kept true at every mutation boundary) and
  `public func undo()` / `public func redo()`.
- Command sites and granularity exactly per spec §5.1 — one command per
  gesture commit, pushed only when state actually changed; view state
  (cursor, selection) never becomes a command.
- `undo()`/`redo()` apply the stored snapshot, refresh
  `canUndo`/`canRedo`, mark `noteSummaryDirty`, and run the same
  refresh/publish/audio-sync sequence the direct mutation paths use.
- `resetDemo()` clears history and sets `revision = 0`.
- Smoke: `verifyGridUndo(window, model)` implements the eight spec §6.1
  rows with the existing QTest style (`resetDemo` invoke, `noteSummary`
  equality as exact-restore oracle) and prints one
  `SWIFT_GRID_SMOKE <row> PASS` per row.

## Implementation steps

1. Write `GridUndo.swift` per the frozen interface. Snapshot pairs, not
   deltas — exactness by construction; do not add merge/coalescing
   (production merge is keyboard-only, out of scope).
2. Add the stack and `revision` to `PianoGrid`; route every §5.1 mutation
   site through `push` at the moment the mutation lands. Keep
   `beginPointer`'s selection capture and all gesture math untouched.
3. Implement `undo()`/`redo()` including the empty-stack inert case and
   the audio resync after every applied command.
4. Write `verifyGridUndo` with the spec §6.1 rows; register the file in
   CMake and the call in `exercise()`. Drive edits through real mouse
   events where the existing interaction smoke already does (draw, move,
   resize, menu delete, double-click); the pitch-curve row follows the
   interaction smoke's existing popup reopen pattern.
5. Run the acceptance check.

## Acceptance predicate

Every §6.1 row passes with exact `noteSummary` restoration and the
`revision`/`canUndo`/`canRedo` transitions stated there; the Wave-1 math
groups, grid/audio/interaction smokes, and the final
`SWIFT_GRID_SMOKE PASS` (exit 0) are unchanged. Named checks (implementer
runs):

- `deno task prototype:swift-grid --smoke`

Covers: undo granularity per gesture (draw/move/resize/delete/
double-click/pitch commit), exact restore, revision monotonicity and
no-op invariance, view-state exclusion (cursor/selection rows), reset
semantics, and full prototype regression. Compile-only fallback:
`deno task prototype:swift-grid --build-only`. Coverage gap, named:
production `QUndoStack` merge behavior for keyboard chords is SongDocument
territory and deliberately unported — spec §8 defers it; no production
check claims it here.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk:
`PianoGrid.swift` is ~680L and this task adds ~60L — keep the undo
plumbing in `GridUndo.swift`; `PianoGrid` gains only the API and push
calls (file-size discipline: cohesion over line count, no fragment
files). Do not add a QML undo button or menu (spec §8 defers undo UI).
The `sgm_*`/`sgp_*` oracle is not a gate for this task (spec §1 D6).
