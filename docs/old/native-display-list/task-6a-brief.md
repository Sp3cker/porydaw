# Task 6a brief — `DrawerStaticsContent` builder API + parity check against the legacy packer

## Context

Velocity is the first drawer surface to cut over from the C++ drawer raster
(`src/render/drawer_scene.cpp`, `src/render/drawer_content.h`) to per-frame
Swift viewport-space `PdDlRect`s. This task definitionally produces the
builder API that Tasks 6b, 7 and 8 consume without re-deciding: it adds the
display-list builders to `DrawerStaticsContent.swift` beside the untouched
legacy §11–§14 packer, and proves them equal to that packer with a new
swiftcore parity suite. Nothing in production calls the builders yet; no QML
changes. Forward pointer: Tasks 6b, 7 (voice) and 8 (automation) cite this
brief's Interface contract as a prerequisite and must not re-decide it.

## Exact write set

- `src/swift/app/drawer/DrawerStaticsContent.swift` (additive only: new
  builder functions beside the legacy `pack` overloads, `DrawerLayer`, and
  §11/§12/§13/§14 record machinery, which stay untouched until Task 9)
- `src/checks/drawerpresentation/DrawerStaticsParityChecks.swift` (new)
- `src/checks/checkcatalog.cpp` (one `swiftSuite("drawerstatics-parity", ...)`
  registration beside the existing entries at `:107-127`)
- Swiftcore suite dispatch for the new suite, per the `themeColor` precedent
  in `src/checks/support/corecheck/` (`CoreCheckSupport.swift:122-125`
  `pdcSuiteRun` cdecl dispatch, `tst_swiftcore.cpp:181-184`
  `SwiftCoreTest::themeColor` slot, `tst_swiftcore.h:47`)

## Prerequisites

- Task 1 interfaces (`DisplayListWriter`, `display_list.h` wire format with
  `pd_dl_decode`, swiftcore round-trip check) and Task 2 (`DisplayList` item
  fetch protocol).
- Task 6a defines the `DrawerStaticsContent` builder API consumed by Tasks
  6b, 7 and 8.
- Task 3b (`viewX` with its final body): the builders project with it, and
  the parity check's re-expression of `drawer_scene.cpp` snapping must match
  it by Contract §4, not by coincidence.

## Interface contract

- `static func buildGrid(into writer: inout DisplayListWriter, axis: TimeAxis, grid: RollGrid, camera: EditorCamera, viewport: CGSize, paletteColors: [Int: String])` — emits grid lines over the visible tick range using `RollGrid.forEachSubdivision` (`src/swift/app/timeline/GridGeometry.swift:309-339`) and `TimeAxis.forEachGridLine` (`src/swift/app/timeline/TimeAxis.swift:120-160`) projected with `viewX` (Task 3b's unified formula; 6a depends on 3b), snapped and culled exactly as `drawer_scene.cpp:31-65` does today (visible-tick range from scroll origin, stroke margin, `w,h > 0` cull, alpha gate). The grid reads only slots 3, 4, 5, 6, 7, 25 (`GridBar`, `GridBeat`, `GridSub1-3`, `GridBeatFine`) — the same dict every caller already builds (`DrawerStaticsContent.swift:42-46` from `VelocityScenePalette`).
- `static func buildTickRects(into writer: inout DisplayListWriter, rects: [DrawerStaticRect], camera: EditorCamera, viewport: CGSize)` — §11 tick-space rects: `x0 = viewX(tickStart)`, `x1 = viewX(tickEnd)`, honoring the `pxSpace` (bit 0), `viewportSticky`/origin-zero (bit 1), and `dashedFrame` (bit 2) flag semantics painted in `drawer_scene.cpp:114-128` (record layout decoded in `drawer_content.h:74-88`).
- `static func buildAnchored(into writer: inout DisplayListWriter, rects: [DrawerAnchoredRect], camera: EditorCamera, viewport: CGSize)` — §12 anchored rects: `x = viewX(tick) + dx`, with bit-0 snap (`drawer_scene.cpp:130-135`).
- `static func buildDashedFrame(into writer: inout DisplayListWriter, box: CGRect, argb: UInt32, dashDevicePx: Double, gapDevicePx: Double, camera: EditorCamera, viewport: CGSize)` — §14 dash pattern decomposed into viewport rects, porting the period-walk in `drawer_scene.cpp:67-97` using the pre-renderer Swift decomposition `addDashedFrame` (`git show 63f492d8:src/swift/app/roll/GridScene+Primitives.swift`, horizontal/vertical period walk with `dash = fontPx(baseFontPx, 0.25)`, `gap = dash`) adapted to drawer stroke/palette inputs.
- Layer breaks (§13, `drawer_scene.cpp:106-113`) are expressed as list boundaries: velocity bands go to list 0, the band/transient fill+frame go to list 1. The builders take no `DrawerLayer` array; callers choose the list.
- The three legacy `pack` overloads, `DrawerLayer`, and the §11/§12/§13/§14 record machinery in `DrawerStaticsContent.swift:49-129` stay byte-identical; `DrawerStaticRect` / `DrawerAnchoredRect` (`:4-21`) keep their shape as the caller-side inputs shared with the builders.

## Implementation steps

1. Add the four builders to `DrawerStaticsContent.swift` emitting through
   `DisplayListWriter`; do not touch the legacy `pack` overloads,
   `DrawerLayer`, or the record machinery. Colors are resolved per palette
   slot from the `paletteColors` dict, never per record.
2. Add `src/checks/drawerpresentation/DrawerStaticsParityChecks.swift` as a
   swiftcore suite registered `swiftSuite("drawerstatics-parity", ...)` in
   `src/checks/checkcatalog.cpp:107-127`, with suite dispatch per the
   `themeColor` precedent in `src/checks/support/corecheck/`.
3. For a fixed set of inputs — grid over a tick range at two zooms and two
   dprs, anchored records, dashed frames — decode each builder's output with
   `pd_dl_decode` (module `NativeDisplayList`) and assert rect
   geometry/colors equal the legacy packer's records for the same inputs,
   after applying the legacy item's own snapping
   (`src/render/drawer_scene.cpp:15-29` `clipped`) in the check.
4. Keep the fixed input set small and deterministic: one tick range, two
   zoom levels, dprs 1 and 2, one anchored-record set, one dashed frame.
   Cover slots 3, 4, 5, 6, 7, 25 in the grid inputs.

## Acceptance predicate

- `deno task build:checks` compiles the new suite and its dispatch.
- `deno task checks --filter drawerstatics-parity --verbose` is green: the
  builders reproduce the legacy packer's geometry/colors for the fixed
  inputs at two zooms and two dprs.
- `deno task proof check --executed` covers ledger health.
- Nothing in production calls the builders yet; no QML file changes in this
  task.
- Gap: no check gates per-frame cost.

## Task-specific constraints

- Dash segments are emitted as plain rects; no dash metadata crosses the
  wire (Contract §1 rules).
- Records use `PD_DL_ID_NONE`; paint order is record order per list.
- Do not add labels or fonts on this surface; velocity has no drawer text in
  the native path.
- Additive only: any diff to the legacy `pack` path fails review.
- The parity check is transitional: it references the legacy `pack` path and
  re-expresses C++ snapping, so Task 9 deletes it with the packer. Say so in
  a one-line comment at the top of the suite.
