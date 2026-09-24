# Task 10 — Scale folding & scale editing invariants

## Context

`proof.scale_fold.txt` (21 GAP: A002–A004, A006–A013, A014–A018, A019–A023)
audits scale-fold occupancy across the timeline, track scope, undo
lifecycle, root invariance; `proof.scale_editing.txt` (33 GAP: A001–A015,
A017–A018, A020–A035) audits diatonic/octave keyboard nudging, multi-note
mapping, exception-note editing and auditioning under fold. Owners:
`PianoGrid` fold state and `NoteProjection`-family projection
(`src/swift/core/`), building on Task 2's folded row invariants (cf.
`static/camera.swift` S018/S019). The 2 + 2 NATIVE sites (fold raster
highlight) stay.

## Exact write set

- `src/checks/rollcheck/scale_fold.swift` (new)
- `src/checks/rollcheck/scale_editing.swift` (new)
- `src/checks/rollcheck/proof.scale_fold.txt`
- `src/checks/rollcheck/proof.scale_editing.txt`
- `src/checks/CMakeLists.txt` (append two stems, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (two suite calls, original
  slot positions)
- `src/checks/rollqml/tst_SwiftRoll.qml` (adapt only if a site's fold
  observation is viewport-observable; justify in report)

## Prerequisites

Task 2 (folded-projection row contract).

## Interface contract

- `@MainActor func runScaleFoldChecks(_:, session:)` and
  `runScaleEditingChecks(_:, session:)`; `cppID:
  "swiftcore/PianoRoll::<scenario>"` per proof headers.
- Certified contracts: fold occupancy membership, track scoping, undo
  lifecycle of fold edits, root transposition invariance, diatonic nudge
  mapping incl. exception notes.

## Implementation steps

1. Read both proofs' sites; port each fold set, root, and nudge fixture
   verbatim; exception notes (outside the fold) get their own scenarios.
2. Write both stems; audition-under-fold scenarios use the existing
   audition surface idiom from the workspace checks, not a new hook.
3. Register per spec.md §Registration.
4. Flip all 54 sites to MATCHED; 2 + 2 NATIVE stay; refresh evidence +
   Tallies.

## Acceptance predicate

All 54 listed sites MATCHED; NATIVE unchanged (2 / 2); `deno task proof
check` passes. NAMED CHECKS — controller: `deno task verify --filter
swiftcore --verbose`; implementer-local: `deno task proof check`.

## Task-specific constraints

- swiftcore-only surface: fold *rasterization* sites are NATIVE and stay;
  do not substitute scene-model assertions for raster obligations.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task lsp:swift`.
