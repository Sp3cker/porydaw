# Task 2 — Fallback grid & tick ceiling bounds

## Context

`static/proof.geometry.txt` carries 23 GAP sites (A004, A009–A019, A032,
A035, A037, A039, A042, A044–A048, A050) asserting the fallback grid and
tick-ceiling math of `static/geometry.cpp`; `proof.scale_projection.txt`
carries 17 GAP sites (A001–A008, A010–A016, A031–A032) asserting
chromatic-vs-folded row-count invariants. No Swift assertion exists for
either. Owners: `GridGeometry` (`GridCameraPolicy`, `GridMetrics`) and
`PitchProjection` in `src/swift/app/timeline/`. Consumer: Tasks 3/4/10 build
snap/hit-test/fold assertions on the tick and row contracts certified here.

## Exact write set

- `src/checks/rollcheck/static/geometry.swift` (new)
- `src/checks/rollcheck/static/proof.geometry.txt`
- `src/checks/rollcheck/proof.scale_projection.txt`
- `src/checks/CMakeLists.txt` (append `rollcheck/static/geometry.swift` to
  `swift_core_check` sources only)
- `src/checks/workspace/SessionChecks.swift` (one suite call, original
  slot position)
- `src/checks/rollqml/tst_SwiftRoll.qml` (adapt only if a site's condition
  is viewport-observable; justify in report)

## Prerequisites

None (foundation task; runs parallel to Task 1).

## Interface contract

- `@MainActor func runGeometryChecks(_ report: CheckReport)` (pure-math
  scenarios may take no `session`); private `check*` scenarios per original
  scenario; `cppID: "swiftcore/EditorGridGeometry::<scenario>"` or the
  original class name from the proof header if it differs.
- Certified contracts: fallback subdivision/zoom bounds, snap tick
  down/up, note rect math, tick ceiling; chromatic 128-row and folded
  subset row invariants (`visibleRowCount`, `row(forPitch:)`,
  `visiblePitch(at:)`, `PitchProjection.hiddenRow`).

## Implementation steps

1. Read the sites: `deno task proof sites rollcheck/static/geometry.cpp`
   and `deno task proof sites rollcheck/scale_projection.cpp`; port each
   assertion's fixture values and boundary literals verbatim.
2. Write `geometry.swift` per spec.md §"Check function shape"; cover all 40
   sites; edge cases: maximum tick ceiling overflow, zero/minimum zoom,
   folded subset with hidden rows, root invariance.
3. Register per spec.md §Registration (suite position from the audited
   `tst_pianorollstatic.h` slot order).
4. Flip all 23 + 17 sites GAP→MATCHED via `proof:edit` with Mapping lines
   citing the new `S###` predicates; refresh header evidence and Tally.
5. Leave geometry's 28 NATIVE and scale_projection's 15 NATIVE
   (raster/framebuffer) sites untouched.

## Acceptance predicate

All 40 listed sites read MATCHED; NATIVE counts unchanged (28 / 15);
`deno task proof check` passes. NAMED CHECKS — controller:
`deno task verify --filter swiftcore --verbose`; implementer-local:
`deno task proof check`, `deno task proof sites`.

## Task-specific constraints

- Pure-math scenarios construct `EditorCamera.Limits` /
  `PitchProjection` values directly (existing `static/camera.swift` idiom);
  no production API additions.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession` while iterating) — executes the new suite-10
scenarios. `deno task lsp:swift` after the CMake/Swift edits.
