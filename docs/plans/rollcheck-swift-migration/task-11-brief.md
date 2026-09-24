# Task 11 — Note rendering geometry, insets, border bounds

## Context

`proof.note_rendering.txt` carries 39 addressable sites (A001–A016,
A018–A030, A034, A035, A037, A046–A050, A053–A054; 28 GAP + 11 PARTIAL)
auditing note borders, selection rings, ghost notes, velocity colors, note
names, and velocity text rendering geometry. The 15 NATIVE sites are
framebuffer-pixel obligations (e.g. A017, A031–A033, A036) and stay.
Owners: `GridScene` (`src/swift/app/roll/GridScene.swift`) publishing
`SceneRect`/`SceneText` primitives, `GridPalette`, `GridTypography`
(`src/swift/app/timeline/`). QML observation rides the existing
`tst_SwiftRollPlots.qml`.

## Exact write set

- `src/checks/rollcheck/note_rendering.swift` (new)
- `src/checks/rollcheck/proof.note_rendering.txt`
- `src/checks/CMakeLists.txt` (append stem, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (one suite call, original
  slot position)
- `src/checks/rollqml/tst_SwiftRollPlots.qml` (adapt; scene-published
  geometry observation cases)

## Prerequisites

Task 1 (camera/projection contract for geometry values).

## Interface contract

- `@MainActor func runNoteRenderingChecks(_ report: CheckReport, session:
  DocumentSession)`; scenarios assert published scene primitives
  (rects/text: position, size, insets, border bounds, colors via
  `GridPalette`) — the model-level rendering contract, not pixels;
  `cppID: "swiftcore/PianoRoll::<scenario>"` per proof header.
- Helper reuse: the `firstRect(named:in:)` idiom from
  `EditorGridCameraChecks.swift:1091`.

## Implementation steps

1. Read `deno task proof sites rollcheck/note_rendering.cpp`; port each
   fixture's note geometry, velocity color buckets, and typography
   literals verbatim.
2. Write `note_rendering.swift`; discharge the 11 PARTIAL conditions by
   completing what their Mapping/reason lines name.
3. Register per spec.md §Registration.
4. Adapt `tst_SwiftRollPlots.qml` so QML-observable geometry (published
   primitives reaching the delegate) is observed once per scenario.
5. Flip the 39 listed sites to MATCHED; 15 NATIVE stay untouched;
   refresh evidence + Tally.

## Acceptance predicate

All 39 listed sites MATCHED; NATIVE unchanged (15); `deno task proof
check` passes. NAMED CHECKS — controller: `deno task verify --filter
swiftcore --verbose` and `deno task verify:qml-roll --verbose`;
implementer-local: `deno task proof check`.

## Task-specific constraints

- Scene-model geometry is the addressable surface; framebuffer-pixel
  equality stays NATIVE — never claim a scene assertion proves pixels.
- Typography values come from `GridTypography` measurements; port the
  original expected literals, do not re-measure to fit.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose`;
`deno task lsp:swift`.
