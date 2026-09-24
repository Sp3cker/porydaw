# Task 1 — Camera transform, zoom, panning

## Context

`static/proof.camera.txt` holds 101 PARTIAL sites: presenter-level Swift
predicates exist (`runEditorCameraChecks` S001–S041 in
`src/checks/rollcheck/static/camera.swift`, `checkViewport`/`checkProjection`
in `EditorGridCameraChecks.swift`) but each site's Mapping/reason names an
unproved condition — the original observed the values through the live
viewport/parity substrate, not an executing Swift observation. Three
`static/proof.geometry.txt` GAP sites (A002, A003, A049) cover the same
camera math. This task discharges those conditions with executing
assertions, extending the existing files only (no new stem). Consumer:
Tasks 3/4/6/7/11/12 build gesture/keyboard/rendering assertions on the
camera coordinate contract this task certifies.

## Exact write set

- `src/checks/rollcheck/static/camera.swift` (extend)
- `src/checks/rollcheck/EditorGridCameraChecks.swift` (extend, only where a
  site's unproved condition names a `check*` function there)
- `src/checks/rollcheck/static/proof.camera.txt`
- `src/checks/rollcheck/static/proof.geometry.txt`
- `src/checks/rollqml/tst_TimelinePan.qml` (adapt; and
  `src/checks/rollqml/RollQmlTests.swift` only if a new case needs runner
  wiring)

## Prerequisites

None (foundation task).

## Interface contract

- No new files. Existing entry points keep their names and suite positions:
  `runEditorCameraChecks(_ report:)`, `runEditorGridCameraChecks(_:session:)`.
- New/extended private `check*` scenarios cite existing
  `cppID` ids (`swiftcore/EditorGridCamera::*`,
  `swiftcore/EditorCamera::*` family already used in these files) — one id
  per original scenario, stable across tasks.
- Camera coordinate contract certified for consumers: content/tick
  round-trip, anchored zoom, clamped scrolling, DPR-snapped projection
  (`EditorCamera`, `PitchProjection` in
  `src/swift/app/timeline/EditorCamera.swift`).

## Implementation steps

1. Enumerate the authoritative site list once:
   `deno task proof sites rollcheck/static/camera.cpp --status PARTIAL`
   (all 101 PARTIAL sites, A001–A109 minus the 8 NATIVE). Read each site's
   Mapping/reason and group by the unproved condition it names
   (swiftcore-executable vs QML-viewport-observable). The first family is
   the `tickRange` edge guards (nan/infinity/negative/empty/`0x1p64`
   overflow, sites A001–A010…): those are pure camera math and belong in
   `camera.swift`.
2. For swiftcore-executable conditions: extend `camera.swift` /
   `EditorGridCameraChecks.swift` scenarios so each condition is asserted by
   an executing `report.expect` with the original fixture values from the
   site's recorded context.
3. For viewport-observable conditions: adapt `tst_TimelinePan.qml` cases to
   observe the same values on the production Swift roll surface
   (`swiftroll/TimelineQuickItem.qml` mount) without creating new QML files.
4. Flip each covered site PARTIAL→MATCHED / the three geometry GAPs→MATCHED
   via `deno task proof:edit` (Mapping line cites the `S###` predicate;
   discharge wording names the executing observation). Update the camera
   file's header verification evidence and the Tally.
5. Leave camera's 8 NATIVE sites and geometry's NATIVE sites untouched.

Edge cases: fractional scroll offsets (10.25/20.25), DPR-2 snapping, pre-roll
clamp at −48, unbound-timeline home — port the exact literals from site
context; do not re-round.

## Acceptance predicate

Every one of the 101 camera PARTIAL sites (authoritative enumeration:
`deno task proof sites rollcheck/static/camera.cpp --status PARTIAL`) and
geometry A002/A003/A049 reads MATCHED;
NATIVE counts unchanged (camera 8, geometry 28); `deno task proof check`
passes. NAMED CHECKS — controller: `deno task verify --filter swiftcore
--verbose` and `deno task verify:qml-roll --verbose`; implementer-local:
`deno task proof check`, `deno task proof sites` reads.

## Task-specific constraints

- Do not add a new camera API to production Swift; a failing expectation is
  a Swift defect to fix in `src/swift/app/timeline/EditorCamera.swift`
  following the C++ behavior (Global Constraints).
- QML adaptation is limited to what the unproved conditions require; report
  each adapted case.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow form
`--qt projectSession` while iterating) — covers the extended swiftcore
scenarios; `deno task verify:qml-roll --verbose` — covers the adapted
`tst_TimelinePan.qml` viewport observations.
