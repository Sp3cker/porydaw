# Task 8 brief — Automation drawer on display lists

## Context

Automation cuts over from the C++ drawer raster to per-frame Swift
viewport-space `PdDlRect`s. It replaces `AutomationPage.drawingContent()` /
`contentRevision` with plan Contract §3 lists (0 axis, 1 statics, 2 preview)
and consumes the Task 6a `DrawerStaticsContent` builder API. Axis rules and
value lines (§11 with `pxSpace`/`viewportSticky` flags), curve runs (§11),
step edges and selection/preview nodes (§12 anchored), and layer breaks (§13)
map onto the three lists; nodes, bands, hover guides and labels stay QML.

## Exact write set

- `src/swift/app/drawer/automation/AutomationPage.swift`
- `src/swift/app/drawer/automation/AutomationDrawingContent.swift`
- `src/swift/app/drawer/automation/AutomationContentPublication.swift`
- `src/swift/app/drawer/automation/AutomationOverlayPublication.swift`
- `src/ui/songview/quick/drawer/AutomationPlot.qml`
- `src/checks/automation/AutomationDrawingContentChecks.swift`
- `src/checks/automation/automationcanvasediting.swift`
- `src/checks/automation/domain/gestureNodeDragPhantom.swift`
- `src/checks/automation/presentation/painting.swift`
- `src/checks/automation/presentation/painting_raster.swift`
- `src/checks/editorqml/tst_EditorDrawerAutomationCamera.qml`
- `src/checks/editorqml/tst_EditorDrawerAutomationCurves.qml`
- `src/checks/editorqml/tst_EditorDrawerAutomationPresentation.qml`
- `src/checks/editorqml/tst_EditorDrawerAutomationPreview.qml`
- `src/checks/editorqml/tst_ShellDrawerParityAutomation.qml`

- Task 1 interfaces (`DisplayListWriter`, wire format) and Task 2
  (`DisplayList` item fetch protocol).
- Task 6a's `DrawerStaticsContent` builder API; this task calls it
  and must not modify it. This task does not edit
  `DrawerStaticsContent.swift`; its legacy packer is deleted in Task 9.

## Interface contract

- `AutomationPage` (in its `@QtBridgeable` class body):
  `@QtTracked public var displayRevision = 0` and
  `public func displayList(list: Int) -> Data` with lists 0 (axis),
  1 (statics), 2 (preview), per plan Contract §3. All three rebuild together
  and bump `displayRevision` once. `drawingContent()` / `contentRevision`
  (`AutomationPage.swift:116-117`) / `drawingContentData` (`:244`) are
  removed; no shim remains.
- Per-frame Swift builder (rewriting `publishDrawingContent` at
  `AutomationDrawingContent.swift:6-125`): writes the three lists through
  `DisplayListWriter`, retaining buffers across frames:
  - list 0 (axis): grid via `buildGrid` (`forEachSubdivision`,
    `GridGeometry.swift:309-339`; `forEachGridLine`,
    `TimeAxis.swift:120-160`) plus the axis/frame rules and scale value
    lines assembled at `AutomationDrawingContent.swift:15-42` via
    `buildTickRects`, preserving their `flags: 3` (`pxSpace` +
    `viewportSticky`) semantics from `drawer_scene.cpp:116-119`;
  - list 1 (statics): ghost + curve runs via `buildTickRects` (from
    `appendDrawingCurve` at `:127-161`, 2px-high runs, step edges as
    anchored width-2 records with `flags: 1`) and selection fill/edges
    (`:62-80`) via `buildTickRects` / `buildAnchored`;
  - list 2 (preview): preview nodes via `buildAnchored` and preview runs
    via `buildTickRects` (`:81-112`, frozen-facts projection);
  - no dash pattern on this page (no `flags: 4` producer);
    `buildDashedFrame` is not called.
- Camera behavior: `AutomationContentPublication.refreshHorizontalProjection`
  (`AutomationContentPublication.swift:132-153`) and `refreshCameraImpl`
  (`AutomationLifecycle.swift:247-250`, via `AutomationPage.refreshCamera`
  at `AutomationPage.swift:292-294`) become display-list rebuild triggers
  (camera moves change bytes + revision); the `drawingCameraOnly` guard
  (`AutomationDrawingContent.swift:7`) is removed with the blob path.
  Overlay publications (`AutomationOverlayPublication.swift:22-35`
  band/hover x via `projection.x`) keep publishing scroll-stable QML models
  and are not folded into the lists.

## Implementation steps

1. Rewrite `publishDrawingContent` to emit the three lists via
   `DisplayListWriter` + Task 6a builders, preserving the assembly order in
   the `layers` array (`AutomationDrawingContent.swift:113-118`) as list
   assignment (axis → 0, ghost/curve/selection → 1, preview → 2).
2. Add `displayRevision` / `displayList(list:)`; remove `contentRevision`,
   `drawingContent()`, `drawingContentData`, `drawingCameraOnly`.
3. Flip `AutomationPlot.qml`: replace the three `TimelineRenderer` items
   (`automationAxis` at `:46-56`, `automationStatics` at `:85-95`,
   `automationPreviewRects` at `:234-244`) with
   `DisplayList { source: pageModel (existing contentSource); list: 0/1/2; revision: pageModel.displayRevision }`,
   objectNames preserved; delete `band` / `drawerLayer` / `pixelsPerTick` /
   `scrollX` / `devicePixelRatio` / `contentRevision` bindings on those
   items. Do not touch node repeaters, range band, hover guide/labels, value
   or ghost labels.
4. Migrate the checks in the write set from `drawingContent()` /
   `contentRevision` to `displayList(list:)` / `displayRevision`:
   `AutomationDrawingContentChecks.swift:190-230` (scroll/zoom stability,
   palette republish, selection), `presentation/painting.swift:334-379,433-437`
   and `painting_raster.swift:72-91,166-170`, `automationcanvasediting.swift:44-63,353-357`,
   `domain/gestureNodeDragPhantom.swift:250-266`, keeping the
   camera-stability assertions' intent inverted as in Task 6b (camera moves
   change bytes + revision). The QML files keep working through preserved
   objectNames (`automationAxis`, `automationStatics`,
   `automationPreviewRects`); edit them only where an assertion names
   `TimelineRenderer` properties or `contentRevision`
   (`tst_ShellDrawerParityAutomation.qml:60-67` does and must be rewritten to
   `displayRevision`).

## Acceptance predicate

- `deno task checks:qml --verbose` covers the automation QML suites and
  raster identity of axis + statics + preview at dpr 1/2.
- `deno task checks:shell --verbose` covers shell automation parity journeys.
- `deno task checks --filter swiftcore --verbose` covers the rewritten
  automation content/presentation/canvas suites.
- `deno task checks:bridge` covers the new `displayRevision`/`displayList`
  surface and removed members.
- `deno task proof check --executed` covers ledger health.
- Gap: no check gates per-frame cost.

## Task-specific constraints

- This task does not edit `DrawerStaticsContent.swift` (single writer:
  Task 6a; legacy packer deleted in Task 9); gaps in the builder API are reported, not worked around.
- All records use `PD_DL_ID_NONE`; paint order is record order per list;
  cross-list interleaving follows the existing QML item order.
