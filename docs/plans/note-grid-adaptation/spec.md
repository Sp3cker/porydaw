# Note grid adaptation — spec

Status: implemented (`PianoGrid+Gestures.swift`, `GridGesture.Move`). Supersedes the earlier
held-gesture re-anchoring design, which was built, reviewed and rejected: it only handled a
grid change *during* a drag and left the actual complaint untouched.

## 1. Problem

Move snapping was relative: `dTick = round((pointerTick − pressTick) / stride) × stride`. A
note placed on a finer grid (or recorded freely) kept its off-grid offset forever under a
coarser grid — it stepped in 1/8 increments but never landed on a 1/8 line. Resize was already
absolute (`snapTick(gripTick + pointerDelta)`), so only move misbehaved.

## 2. Behavior

- **Move is absolute.** The grabbed note's start follows the pointer and snaps to the lattice
  in force: `projected = snapTick(grabbedStart + (pointerTick − pressTick))`,
  `dTick = projected − grabbedStart`. For a note already on the lattice this is bit-identical
  to the old relative math.
- **A bare click never moves a note.** `dTick` stays 0 until the pointer has actually moved
  (`Move.moved`); the first motion event lands an off-grid note on its nearest line.
- **Multi-selection keeps spacing.** Other selected notes shift by the same `dTick`; only the
  grabbed note is snapped. Fine rhythms inside a selection survive.
- **Grid changes mid-drag** need no special path: `resnapHeldGesture()` re-runs `updated` at
  the held pointer, and the absolute projection re-snaps on its own.
- Committed notes never move because the grid changed; no document mutation or history entry
  outside the normal release commit.

## 3. Proof

`checkOffGridMoveSnapsToLattice` (`src/checks/rollcheck/EditorGridProjectionChecks.swift`,
`swiftcore-projectsession`): plants two notes a quarter-1/8 off the 1/8 lattice, asserts a
click leaves the first in place with no history entry, a 2 px drag lands it on a 1/8 line, and
the second note moves by the identical delta. Fails against the previous relative math.
No proof-ledger rows: this is new Swift-owned behavior with no C++ counterpart.
