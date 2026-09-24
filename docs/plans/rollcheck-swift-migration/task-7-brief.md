# Task 7 — Selection mechanics, duplicate identity, gesture interlock

## Context

Three proofs, one selection-behavior family: `proof.selection.txt`
(48 GAP sites: A003, A007, A010, A011, A013, A018, A021, A022, A026,
A029–A032, A034, A036–A042, A044–A045, A047–A050, A052–A060, A063–A074)
audits marquee band sweep, provisional rings, press audition, pending-draw
readout, modifier velocity; `proof.identity.txt` (11 GAP: A003, A005–A014)
audits note identity, duplicate distinction, timeline projection,
ViewState round-trip; `proof.interlock.txt` (20 GAP: A001–A020) audits
gesture interlock and concurrent button conflicts. Owners:
`DocumentSession.selectedNotes/selectedNoteOrder`,
`PianoGrid.applyBandSelection/applyPressSelection/pendingControlToggle`,
`GridGesture` state machine; identity via `NoteID` stability across
revisions (`src/swift/core/MusicTypes.swift`). Existing related coverage:
`EditorGridCameraChecks.checkOrderedSelection`.

## Exact write set

- `src/checks/rollcheck/selection.swift` (new)
- `src/checks/rollcheck/identity.swift` (new)
- `src/checks/rollcheck/interlock.swift` (new)
- `src/checks/rollcheck/proof.selection.txt`
- `src/checks/rollcheck/proof.identity.txt`
- `src/checks/rollcheck/proof.interlock.txt`
- `src/checks/CMakeLists.txt` (append three stems, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (three suite calls, original
  slot positions)
- `src/checks/rollqml/tst_SwiftRoll.qml` (adapt; band-sweep and ring
  observation cases)

## Prerequisites

Task 3 (gesture sequencing interface).

## Interface contract

- `@MainActor func runSelectionChecks(_:, session:)`,
  `runIdentityChecks(_:, session:)`, `runInterlockChecks(_:, session:)`;
  `cppID: "swiftcore/PianoRoll::<scenario>"` per proof headers.
- Certified contracts: Shift extend / Ctrl deferred toggle semantics,
  marquee accumulation order (`selectedNoteOrder`), NoteID stability
  across move/duplicate/undo, ViewState round-trip, mutual exclusion of
  concurrent gestures (draw vs right-drag vs pan).

## Implementation steps

1. Read the three proofs' sites; reproduce each original sequence,
   including the deferred Ctrl mouse-up toggle and concurrent-button
   conflict orders.
2. Write the three stems per spec.md §"Check function shape".
3. Register all three per spec.md §Registration.
4. Adapt `tst_SwiftRoll.qml` for viewport-observable ring/band feedback.
5. Flip all 79 sites to MATCHED; 26 + 3 NATIVE sites stay; refresh
   evidence + Tallies.

## Acceptance predicate

All 79 listed sites MATCHED; NATIVE unchanged (selection 26, identity 3);
`deno task proof check` passes. NAMED CHECKS — controller:
`deno task verify --filter swiftcore --verbose` and
`deno task verify:qml-roll --verbose`; implementer-local:
`deno task proof check`.

## Task-specific constraints

- Interlock scenarios must assert the *conflict* outcome (which gesture
  wins, what cancels), not merely that no crash occurs.
- Over-cap exception named in plan.md: three stems are one selection
  family with one verification pair; splitting them would multiply
  registration churn on the shared integration files.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose`;
`deno task lsp:swift`.
