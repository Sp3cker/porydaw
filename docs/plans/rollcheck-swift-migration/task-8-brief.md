# Task 8 — Track remap, header presentation, reconciliation

## Context

`proof.remap.txt` (67 sites: A001–A067; 29 GAP + 38 PARTIAL) audits track
move/insert/duplicate/delete remapping, signal-ordering invariants, and
engine promotion; `proof.presentation.txt` (40 GAP: A001–A040) audits
header follow-scroll during pan, inline track rename, reveal-note, and
mute/solo shortcuts; `proof.header_reconciliation.txt` (11 addressable of
13: A001, A003–A005, A007–A013; 6 GAP + 5 PARTIAL) audits header-model
reconciliation against the roll. **A002 and A006 are blockers** (retired
native `SongView` viewport; source deleted in `91cab247`) — never touch
them. Owners: `TrackHeaders` (`src/swift/app/headers/`), `DocumentSession`
track operations; related existing coverage:
`EditorGridCameraChecks.checkTrackOwnerRemap`. `src/checks/trackheaders/`
fixtures/helpers are read-only reuse.

## Exact write set

- `src/checks/rollcheck/remap.swift` (new)
- `src/checks/rollcheck/presentation.swift` (new)
- `src/checks/rollcheck/proof.remap.txt`
- `src/checks/rollcheck/proof.presentation.txt`
- `src/checks/rollcheck/proof.header_reconciliation.txt`
- `src/checks/CMakeLists.txt` (append two stems, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (two suite calls, original
  slot positions)
- `src/checks/rollqml/tst_SwiftRollWindowing.qml` (adapt; header/roll
  coupled-scroll observation cases)

## Prerequisites

Task 5 (command-transaction idiom for destructive track operations).

## Interface contract

- `@MainActor func runRemapChecks(_:, session:)` and
  `runPresentationChecks(_:, session:)`; `cppID:
  "swiftcore/PianoRoll::<scenario>"` per proof headers.
- Certified contracts: note `track` remap after each track operation,
  signal ordering, engine promotion, header follow-scroll coupling,
  rename round-trip, reveal-note scroll, mute/solo state.

## Implementation steps

1. Read the three proofs' sites; for each PARTIAL site discharge exactly
   the condition its Mapping/reason names.
2. Write both stems; destructive operations assert one-transaction undo
   (charter S-3) and note-owner remap (cf. `checkTrackOwnerRemap`).
3. Register per spec.md §Registration. The `header_reconciliation` proof
   header currently names `src/checks/trackheaders/trackheadermutations.swift`
   as its Swift counterpart; its new `S###` predicates live in
   `rollcheck/presentation.swift`, so update that header's Swift reference
   with `deno task proof:edit rollcheck/header_reconciliation.cpp header
   …` in the same edit. The trackheaders file itself stays read-only.
4. Adapt `tst_SwiftRollWindowing.qml` for coupled header/roll scroll.
5. Flip the 118 listed sites to MATCHED — **except A002/A006, which stay
   in their current disposition untouched**; NATIVE counts unchanged
   (2 in header_reconciliation); refresh evidence + Tallies.

## Acceptance predicate

All 118 listed sites MATCHED; A002/A006 untouched; NATIVE unchanged;
`deno task proof check` passes. NAMED CHECKS — controller:
`deno task verify --filter swiftcore --verbose` and
`deno task verify:qml-roll --verbose`; implementer-local:
`deno task proof check`.

## Task-specific constraints

- No `trackheaders` filter exists on this branch and none may be invented;
  the QML lane covers the header surface via `verify:qml-roll`.
- `src/checks/trackheaders/**` is read-only; a needed helper change there
  is a brief defect — report it, do not edit.
- Over-cap exception named in plan.md.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose`;
`deno task lsp:swift`.
