# Task 6b brief — Velocity drawer on display lists

## Context

Velocity is the first drawer surface to cut over from the C++ drawer raster
(`src/render/drawer_scene.cpp`, `src/render/drawer_content.h`) to per-frame
Swift viewport-space `PdDlRect`s. It replaces `VelocityPage.drawingContent()`
/ `contentRevision` with plan Contract §3 lists (0 grid, 1 transient), calling
the `DrawerStaticsContent` builder API defined by Task 6a without modifying
it. Forward pointer: Task 7 (voice) consumes the rewritten
`VelocityContentProbe` for voice decoding — it does not co-edit it.

## Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift`
- `src/swift/app/drawer/velocity/VelocityPublication.swift`
- `src/ui/songview/quick/drawer/VelocityPage.qml`
- `src/checks/velocity/VelocityContentProbe.swift` (sole Swift reader of
  `drawingContent()`/`contentRevision` on this page; owned here — Task 7
  consumes the rewritten probe for voice decoding, it does not co-edit it)
- `src/checks/editorqml/tst_EditorDrawerVelocityEditing.qml`
- `src/checks/editorqml/tst_EditorDrawerVelocityHitTargets.qml`
- `src/checks/editorqml/tst_EditorDrawerVelocityPrompt.qml`
- `src/checks/editorqml/tst_EditorDrawerVelocityRaster.qml`
- `src/checks/editorqml/tst_ShellDrawerParityVoiceVelocity.qml` (shared with
  Task 7; Task 6b owns the velocity-half edits, Task 7 the voice-half edits)
- `src/checks/editorqml/tst_EditorDrawerVelocitySameFrame.qml` (new)

## Prerequisites

- Task 1 interfaces (`DisplayListWriter`, `display_list.h` wire format,
  swiftcore round-trip check) and Task 2 (`DisplayList` item fetch protocol).
- Task 6a's `DrawerStaticsContent` builder API (`buildGrid`,
  `buildTickRects`, `buildAnchored`, `buildDashedFrame`); this task calls it
  and must not modify `DrawerStaticsContent.swift` — mismatches are
  reported, not worked around.

## Interface contract

- `VelocityPage` (in its `@QtBridgeable` class body):
  `@QtTracked public var displayRevision = 0` and
  `public func displayList(_ list: Int) -> Data` with lists 0 (grid) and 1
  (transient), per plan Contract §3. Both lists rebuild together and bump
  `displayRevision` once. `drawingContent()` / `contentRevision` /
  `drawingContentData` are removed; no shim remains.
- Per-frame Swift builder on `VelocityPage`: `publishDisplayLists()` (name may
  follow the file's existing `publishDrawingContent` convention) writes list 0
  (grid via Task 6a `buildGrid` + `modelBands` via `buildTickRects`) and list
  1 (transient fill via `buildTickRects`, transient frame via
  `buildDashedFrame` with the `(4, 2)` pattern in
  `DrawerStaticsContent.swift:46`), through `DisplayListWriter`, retaining
  buffers across frames.
- Layer breaks (§13, `drawer_scene.cpp:106-113`) are expressed as list
  boundaries: velocity bands go to list 0, the band/transient fill+frame go
  to list 1.

## Implementation steps

1. Add `displayRevision` / `displayList(_:)` to `VelocityPage`
   (`VelocityPage.swift:211-212` today); remove `contentRevision`,
   `drawingContent()`, `drawingContentData`. Rebuild trigger: existing
   content path (`publishDrawingContent` at
   `VelocityPublication.swift:238-250`) and camera path
   (`VelocityPage.refreshCamera` at `VelocityPublication.swift:85-96`: it
   moves each tick-space handle's `x`/`endX` in place, then
   `publishTransient(updateDrawing: false)` — keep the in-place handle
   update, and end with a rebuild of both lists + one `displayRevision`
   bump, since camera moves must change bytes + revision; plan Contract §7).
   Handles stay tick-space QML delegates; `contentScrollX` /
   `contentPixelsPerTick` bindings in `VelocityPage.qml` are not yours.
2. Emit grid lines in Swift over the visible tick range with
   `forEachSubdivision` / `forEachGridLine` (via Task 6a `buildGrid`);
   project node/band/transient geometry with the unified `viewX` (Contract
   §4). Cull to the viewport and snap exactly as `drawer_scene.cpp:15-29`
   (`clipped`) does.
3. Flip `VelocityPage.qml`: replace the two `TimelineRenderer` items
   (`velocityGridLines` at `:362-372`, `velocityTransient` at `:458-468`)
   with `DisplayList { source: pageModel (existing contentSource); list: 0/1; revision: pageModel.displayRevision }`, objectNames preserved; delete
   `band` / `drawerLayer` / `pixelsPerTick` / `scrollX` /
   `devicePixelRatio` / `contentRevision` bindings on those items. Do not
   touch handle delegates, scroll carrier, or ramp.
4. Migrate the checks in the write set from `drawingContent()` /
   `contentRevision` to `displayList(_:)` / `displayRevision`:
   `VelocityContentProbe.swift:171-286` (decode the new wire format instead of
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
- `deno task checks:qml --filter EditorDrawerVelocitySameFrame --verbose`
  covers the production half of the plan Contract §2 invariant: after each
  of ten wheel-scroll steps on the velocity page, in the window's
  `onAfterAnimating` record a handle stem's x (tick-space delegate placed
  from the synchronous carrier row) and the grid line list's `face()` for
  the same tick's grid rect; assert they agree in every frame — handles
  never lead the drawn grid by a frame. Pattern: Task 2's
  `tst_DisplayListSameFrame.qml`.
- Gap: no check gates per-frame cost.

## Task-specific constraints

- This task does not edit `DrawerStaticsContent.swift` (single writer: Task
  6a). If the Task 6a API cannot express the velocity bands or transient,
  stop and report the gap instead of adding a local pack path.
- All records use `PD_DL_ID_NONE`; paint order is record order per list.
