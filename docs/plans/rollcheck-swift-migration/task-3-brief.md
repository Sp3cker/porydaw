# Task 3 — Pointer draw, velocity latch, double-press delete

## Context

`proof.pencil.txt` (21 sites: A001–A015, A017–A022; 17 GAP + 4 PARTIAL)
audits double-click pencil creation, fractional placement, abutting notes,
gutter selection. `proof.pencil_velocity.txt` (51 GAP sites: A001–A035,
A037–A051, A053) audits velocity click-latching, menu retargeting/stale
activation, drag commit, double-press delete. The 4 PARTIAL pencil sites
name `EditorGridCameraChecks.checkDrawLatchAndCancel` as related coverage
with unproved conditions. Owners: `PianoGrid.beginPointer/updatePointer/
endPointer/doublePointer` and `GridGesture` in `src/swift/app/roll/`,
`NoteEditing` in `src/swift/core/`. Consumes Task 1's camera coordinates
and Task 2's snap/tick contracts; producer for Tasks 5–7 (they assert
commands/keyboard over selections created here).

## Exact write set

- `src/checks/rollcheck/pencil.swift` (new)
- `src/checks/rollcheck/proof.pencil.txt`
- `src/checks/rollcheck/proof.pencil_velocity.txt`
- `src/checks/CMakeLists.txt` (append stem, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (one suite call, original
  slot position)
- `src/checks/rollqml/tst_SwiftRoll.qml` (adapt; cases for QML-observable
  draw/latch behavior)

## Prerequisites

Task 1 (camera coordinate contract), Task 2 (snap/tick contract) —
interfaces only.

## Interface contract

- `@MainActor func runPencilChecks(_ report: CheckReport, session:
  DocumentSession)` covering both stems' scenarios
  (`checkPencilCreation`, `checkVelocityLatch`, … — one per original
  scenario); `cppID: "swiftcore/PianoRoll::<scenario>"` per the proof
  headers' original class.
- Gesture sequencing uses `PianoGrid` public pointer methods only; no
  synthetic QWheel/QMouse events, no test-only production hooks.

## Implementation steps

1. Read both proofs' sites and the recorded original sequences; reproduce
   each scenario's press/move/release cadence and fixture notes exactly
   (including the double-press delete timing and fractional-tick
   placements).
2. Write `pencil.swift`; the 4 PARTIAL pencil sites are discharged by
   completing the named unproved conditions (extend the related scenarios
   rather than duplicating them).
3. Register per spec.md §Registration (slot order from `tst_pianoroll.h`).
4. Adapt `tst_SwiftRoll.qml` for the QML-observable subset (draw feedback,
   latch state) — no new QML files.
5. Flip all 72 sites (21 + 51) to MATCHED; Mapping lines cite `S###`
   predicates; refresh evidence + Tally. The 1 + 2 NATIVE sites stay.

## Acceptance predicate

All 72 listed sites MATCHED; NATIVE unchanged (pencil 1, pencil_velocity
2); `deno task proof check` passes. NAMED CHECKS — controller:
`deno task verify --filter swiftcore --verbose` and
`deno task verify:qml-roll --verbose`; implementer-local:
`deno task proof check`.

## Task-specific constraints

- Distinguish latch-retarget from stale-activation exactly as the original
  does; do not merge the scenarios into one generalized "menu" case.
- Over-cap exception: two proofs + stem + registration + QML is one
  gesture-painting behavior with one verification pair; named in plan.md.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose` for the
adapted `tst_SwiftRoll.qml` cases; `deno task lsp:swift`.
