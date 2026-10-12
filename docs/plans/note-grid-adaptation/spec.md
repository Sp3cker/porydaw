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
- **Bar-anchored lattices apply.** Because the projection snaps absolutely, a drag across a
  time-signature seam lands on that segment's drawn lines (e.g. 12 + 24k after a restated 4/4
  at tick 12), where the relative math could stop between two lines.
- **Same sensitivity as any note.** Under half a stride of pointer travel `dTick` is 0 (a click
  or a nudge never moves a note); past it the projection above applies, so an off-grid note
  lands on its nearest line at the same travel that steps an on-grid note.
- **Multi-selection keeps spacing.** Other selected notes shift by the same `dTick`; only the
  grabbed note is snapped. Fine rhythms inside a selection survive.
- **Grid changes mid-drag** need no special path: `resnapHeldGesture()` re-runs `updated` at
  the held pointer, and the absolute projection re-snaps on its own.
- Committed notes never move because the grid changed; no document mutation or history entry
  outside the normal release commit.

## 3. Proof

`checkOffGridMoveSnapsToLattice` (`src/checks/rollcheck/EditorGridProjectionChecks.swift`,
`swiftcore-projectsession`): plants a note a quarter-1/8 off the 1/8 lattice, asserts a 0.3-stride
drag leaves it in place with no history entry and a 0.6-stride drag lands it on a 1/8 line.
The landing assertion fails against the previous relative math.
No proof-ledger rows: this is new Swift-owned behavior with no C++ counterpart.
