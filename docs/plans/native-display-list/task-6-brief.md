# Task 6 brief — Velocity drawer on display lists

## Context

Velocity is the first drawer surface to cut over from the C++ drawer raster
(`src/render/drawer_scene.cpp`, `src/render/drawer_content.h`) to per-frame
Swift viewport-space `PdDlRect`s. It replaces `VelocityPage.drawingContent()`
/ `contentRevision` with plan Contract §3 lists (0 grid, 1 transient) and
rewrites `DrawerStaticsContent.swift` from a tick-space blob packer into the
display-list builder API that Tasks 7 and 8 consume. Forward pointer: Tasks 7
(voice) and 8 (automation) cite this brief's Interface contract as a
prerequisite and must not re-decide it.

## Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift`
- `src/swift/app/drawer/velocity/VelocityPublication.swift`
- `src/swift/app/drawer/DrawerStaticsContent.swift`
- `src/ui/songview/quick/drawer/VelocityPage.qml`
- `src/checks/velocity/VelocityContentProbe.swift` (sole Swift reader of `drawingContent()`/`contentRevision` on this page; owned here — Task 7 consumes the rewritten probe for voice decoding, it does not co-edit it)
- `src/checks/editorqml/tst_EditorDrawerVelocityEditing.qml`
- `src/checks/editorqml/tst_EditorDrawerVelocityHitTargets.qml`
- `src/checks/editorqml/tst_EditorDrawerVelocityPrompt.qml`
- `src/checks/editorqml/tst_EditorDrawerVelocityRaster.qml`
- `src/checks/editorqml/tst_ShellDrawerParityVoiceVelocity.qml` (shared with Task 7; Tasks 6 and 7 coordinate — Task 6 owns the velocity-half edits, Task 7 the voice-half edits)

## Prerequisites

- Task 1 interfaces (`DisplayListWriter`, `display_list.h` wire format,
  swiftcore round-trip check) and Task 2 (`DisplayList` item fetch protocol).
- Task 6 defines the rewritten `DrawerStaticsContent` builder API consumed by
  Tasks 7 and 8.

## Interface contract

- `static func buildGrid(into writer: inout DisplayListWriter, axis: TimeAxis, grid: RollGrid, camera: EditorCamera, viewport: CGSize, paletteColors: [Int: String])` — emits grid lines over the visible tick range using `RollGrid.forEachSubdivision` (`src/swift/app/timeline/GridGeometry.swift:309-339`) and `TimeAxis.forEachGridLine` (`src/swift/app/timeline/TimeAxis.swift:120-160`) projected with the unified `viewX`/`displayX`, snapped and culled exactly as `drawer_scene.cpp:31-65` does today (visible-tick range from scroll origin, stroke margin, `w,h > 0` cull, alpha gate). The grid reads only slots 3, 4, 5, 6, 7, 25 (`GridBar`, `GridBeat`, `GridSub1-3`, `GridBeatFine`) — the same dict every caller already builds (`DrawerStaticsContent.swift:42-46` from `VelocityScenePalette`, `VoiceChangesPublication.swift:121-125`, `AutomationDrawingContent.swift:10-14`); the velocity caller keeps building that dict from its `VelocityScenePalette` (`VelocityScene.swift:93-100`) at the call site.
- `VelocityPage` (in its `@QtBridgeable` class body):
  `@QtTracked public var displayRevision = 0` and
  `public func displayList(_ list: Int) -> Data` with lists 0 (grid) and 1
  (transient), per plan Contract §3. Both lists rebuild together and bump
  `displayRevision` once. `drawingContent()` / `contentRevision` /
  `drawingContentData` are removed; no shim remains.
- `static func buildTickRects(into writer: inout DisplayListWriter, rects: [DrawerStaticRect], camera: EditorCamera, viewport: CGSize)` — §11 tick-space rects: `x0 = displayX(tickStart)`, `x1 = displayX(tickEnd)`, honoring the `pxSpace` (bit 0), `viewportSticky`/origin-zero (bit 1), and `dashedFrame` (bit 2) flag semantics decoded in `drawer_content.h:74-88` and painted in `drawer_scene.cpp:114-128`.
- `static func buildAnchored(into writer: inout DisplayListWriter, rects: [DrawerAnchoredRect], camera: EditorCamera, viewport: CGSize)` — §12 anchored rects: `x = viewX(tick) + dx`, with bit-0 snap (`drawer_scene.cpp:130-135`).
- `static func buildDashedFrame(into writer: inout DisplayListWriter, box: CGRect, argb: UInt32, dashDevicePx: Double, gapDevicePx: Double, camera: EditorCamera, viewport: CGSize)` — §14 dash pattern decomposed into viewport rects, porting the period-walk in `drawer_scene.cpp:67-97` using the pre-renderer Swift decomposition `addDashedFrame` (`git show 63f492d8:src/swift/app/roll/GridScene+Primitives.swift`, horizontal/vertical period walk with `dash = fontPx(baseFontPx, 0.25)`, `gap = dash`) adapted to drawer stroke/palette inputs.
- Layer breaks (§13, `drawer_scene.cpp:106-113`) are expressed as list boundaries: velocity bands go to list 0, the band/transient fill+frame go to list 1. The builder takes no `DrawerLayer` array; callers choose the list.
- Per-frame Swift builder on `VelocityPage`: `publishDisplayLists()` (name may
  follow the file's existing `publishDrawingContent` convention) writes list 0
  (grid via `buildGrid` + `modelBands` via `buildTickRects`) and list 1
  (transient fill via `buildTickRects`, transient frame via
  `buildDashedFrame` with the `(4, 2)` pattern in
  `DrawerStaticsContent.swift:46`), through `DisplayListWriter`, retaining
  buffers across frames.

## Implementation steps

1. Rewrite `DrawerStaticsContent.swift` to the builder API above; delete the
   three `pack` overloads, `DrawerLayer`, and the §11/§12/§13/§14 record
   machinery. Preserve `DrawerStaticRect` / `DrawerAnchoredRect` as the
   caller-side inputs (bands from `VelocityScene.modelBands`, transient from
   `drawingTransientRects()` at `VelocityPublication.swift:237-256`) until
   Tasks 7/8 migrate their callers.
2. Add `displayRevision` / `displayList(_:)` to `VelocityPage`
   (`VelocityPage.swift:211-212` today); remove `contentRevision`,
   `drawingContent()`, `drawingContentData`. Rebuild trigger: existing
   content path (`publishDrawingContent` at
   `VelocityPublication.swift:223-235`) and camera path
   (`VelocityPage.refreshCamera` at `VelocityPage.swift:398-405`, which today
   republishes handles but not drawing content — extend it to rebuild both
   lists, since camera moves must change bytes + revision).
3. Emit grid lines in Swift over the visible tick range with
   `forEachSubdivision` / `forEachGridLine`; project node/band/transient
   geometry with the unified `viewX` (Contract §4). Cull to the viewport and
   snap exactly as `drawer_scene.cpp:15-29` (`clipped`) does.
4. Flip `VelocityPage.qml`: replace the two `TimelineRenderer` items
   (`velocityGridLines` at `:359-369`, `velocityTransient` at `:450-460`)
   with `DisplayList { source: pageModel (existing contentSource); list: 0/1; revision: pageModel.displayRevision }`, objectNames preserved; delete
   `band` / `drawerLayer` / `pixelsPerTick` / `scrollX` /
   `devicePixelRatio` / `contentRevision` bindings on those items. Do not
   touch handle delegates, scroll carrier, or ramp.
5. Migrate the checks in the write set from `drawingContent()` /
   `contentRevision` to `displayList(_:)` / `displayRevision`:
   `VelocityContentProbe.swift:176-284` (decode the new wire format instead of
   the §11/§14 blob; invert the camera-stability assertions per the Contract
   §3 economy re-expression — camera moves MUST change `displayRevision` and
   bytes; document/selection-tier inputs must not). The QML files keep working
   through preserved objectNames; edit them only where an assertion names
   `TimelineRenderer` properties (`band`, `drawerLayer`, camera bindings) or
   `contentRevision`. `drawerpresentation/velocity.swift` and
   `VelocityPageChecks.swift` do not read `drawingContent()`/`contentRevision`
   (verified by grep) and stay untouched.

## Acceptance predicate

- `deno task checks:qml --verbose` covers the velocity QML suites and raster
  identity of grid + transient against `TimelineRenderer` output at dpr 1/2.
- `deno task checks:shell --verbose` covers shell drawer-parity journeys via
  the new lists.
- `deno task checks --filter swiftcore --verbose` covers the rewritten
  velocity content probes and economy re-expression.
- `deno task checks:bridge` covers the new `displayRevision`/`displayList`
  QtBridge surface and the removed `drawingContent`/`contentRevision`.
- `deno task proof check --executed` covers ledger health.
- Gap: no automated check asserts per-frame Swift pack cost; controller
  manual smoke (plan Verification) compares screenshots and Instruments time
  against the Task 0 budget.

## Task-specific constraints

- Dash segments are emitted as plain rects; no dash metadata crosses the
  wire (Contract §1 rules).
- Records use `PD_DL_ID_NONE`; paint order is record order per list.
- Do not add labels or fonts on this surface; velocity has no drawer text in
  the native path.
