# Task 4 — Grid editing: gestures → intents

## Context

The Swift roll edits the real document through the Task 1–3 seams,
behind `PORYDAW_SWIFT_ROLL`. Producer of the end-to-end acceptance rows.
Mapping rules FIXED in [spec.md §5](spec.md); eligibility comes from
`sgp_`, state from `sgs_`.

## Exact write set

- `src/ui/songview/quick/swift-grid-prototype/PianoGrid.swift` — editable
  gesture paths emit `sgc_` intents (draw/move/resize/delete); preview
  state during drag; commit-once at gesture end; selection interactions
  submit `SGC_SELECTION_*`.
- `src/ui/songview/quick/swift-grid-prototype/SgcCommands.swift` —
  gesture→intent helpers (single writer with Task 1 checkpoint).
- `src/checks/swiftgridprototype/grid_smoke.cpp` (+ `.h` seam if needed) —
  editable rows.
- `src/checks/swiftrollgated/` — end-to-end rows (flag on).

## Prerequisites

Tasks 1–3. Perf precondition accepted at the Wave 3 gate review
(plan.md).

## Interface contract

- Live drag renders a Swift-side preview; the document mutates exactly
  once, at gesture end, as one intent (or one batch) = one undo entry.
- Delete: marquee + key + menu paths all funnel to `SGC_NOTE_DELETE`
  batches (menu actions route through the same intents, not a parallel
  path).
- New-note flow: draw commits `SGC_NOTE_ADD`, outcome token selects the
  note (`SGC_SELECTION_SET_NOTES`) if production's roll selects on draw.
- Escape arbitration unchanged (Wave 2 arbiter); with a live gesture it
  cancels the preview with zero document effect.
- `readOnly` mode from Wave 3 remains and remains inert — flag on +
  `readOnly` off = editing; nothing may bypass the intents.

## Implementation steps

1. Wire each gesture's commit point to the matching intent; previews
   local to the gesture.
2. Selection gestures (click, shift-click, marquee) compute the desired
   set from `sgs_` state + modifiers and submit the complete set.
3. Smoke rows (prototype lane): `intent-commit-once` (drag emits one
   intent, undo depth +1), `preview-reverts-on-cancel`,
   `readonly-still-inert`, `selection-roundtrip`.
4. `swiftrollgated` rows: flag on, edit through the mounted band via the
   adapter, undo through the production undo stack (`QUndoStack` entry
   observed), `sgd_` re-render, redo, Escape mid-drag zero-effect.

## Acceptance predicate

- `deno task prototype:swift-grid --smoke` green, existing rows unchanged.
- `deno task verify --filter swiftrollgated --verbose` green (extended).
- `deno task build:app` + canaries green.

## Task-specific constraints

- No direct document access from Swift beyond `sgc_`; no preview state
  written back through any seam.
- Production roll behavior is the reference for gesture semantics
  (deadbands, thresholds — already parity-locked from Wave 1/2); do not
  re-derive them.
