# Task 4 — Edge resize, minimum clamping, abutting pairs

## Context

`proof.resize.txt` carries 28 addressable sites (A001–A002, A005–A019,
A021–A026, A029–A033; 20 GAP + 8 PARTIAL) auditing off-grid note edge
resizing, selection edge resize, minimum-duration clamping, and abutting
resize. The PARTIAL sites relate to
`EditorGridCameraChecks.checkEdgeResize`. Owners: `GridGesture` edge
grips and `NoteEditing.resizeNotes` (`src/swift/app/timeline/GridGeometry`
`edgeGripReach`/`snapTickDown/Up`). Consumes Tasks 1–2 coordinate
contracts.

## Exact write set

- `src/checks/rollcheck/resize.swift` (new)
- `src/checks/rollcheck/proof.resize.txt`
- `src/checks/CMakeLists.txt` (append stem, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (one suite call, original
  slot position)
- `src/checks/rollqml/tst_SwiftRoll.qml` (adapt; QML-observable resize
  feedback cases)

## Prerequisites

Task 1, Task 2 (interfaces only).

## Interface contract

- `@MainActor func runResizeChecks(_ report: CheckReport, session:
  DocumentSession)`; scenarios per original case; `cppID:
  "swiftcore/PianoRoll::<scenario>"` per proof header.
- Certified contract: edge hit regions, minimum duration clamp value,
  abutting-pair boundary, multi-selection resize semantics.

## Implementation steps

1. Read `deno task proof sites rollcheck/resize.cpp`; port fixtures
   verbatim (off-grid start ticks, clamp minimums, abutting pairs).
2. Write `resize.swift`; discharge the 8 PARTIAL conditions inside the
   new scenarios (cite `checkEdgeResize` where the original site already
   did, extending it only if the condition names it).
3. Register per spec.md §Registration.
4. Adapt `tst_SwiftRoll.qml` for viewport-observable resize cursors/
   feedback only if a site requires it.
5. Flip all 28 sites to MATCHED; 5 NATIVE sites stay; refresh evidence +
   Tally.

## Acceptance predicate

All 28 listed sites MATCHED; NATIVE unchanged (5); `deno task proof
check` passes. NAMED CHECKS — controller: `deno task verify --filter
swiftcore --verbose` and `deno task verify:qml-roll --verbose`;
implementer-local: `deno task proof check`.

## Task-specific constraints

- The historical leading-resize deviation is not license to weaken the
  destination transaction contract (charter S-3): one resize gesture =
  one undoable transaction, asserted.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose`;
`deno task lsp:swift`.
