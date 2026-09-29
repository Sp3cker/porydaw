# Task 2 — `DisplayList` QQuickItem

## Context

Consumes Task 1's wire format: the item pulls a frame's bytes from its
QtBridge source, decodes with `pd_dl_decode`, and uploads scene-graph nodes.
It replaces the fetch/decode/upload residue of `TimelineRenderer`
(`src/render/timeline_renderer.cpp:247-281`,
`src/render/timeline_renderer_nodes.cpp:402-419`) with no projection,
culling, layout, or visibility logic. Drawers later instantiate several
items on several lists (cf. `AutomationPlot.qml` multi-item precedent cited
in Contract §1).

## Exact write set

- `src/render/display_list_item.h` (new)
- `src/render/display_list_item.cpp` (new)
- `CMakeLists.txt` (registration beside `timeline_renderer` entries)
- `src/checks/editorqml/DisplayListProbe.swift` (new; check-only source)
- `src/checks/editorqml/tst_DisplayListSameFrame.qml` (new)
- `src/checks/CMakeLists.txt` (probe source entry beside `:526-527`; QML
  lane entry for the new test)

## Prerequisites

- Task 1 interfaces: `display_list.h` structs/ids, `pd_dl_decode` semantics,
  8-byte alignment rule.

## Interface contract

- `class DisplayList : public QQuickItem` with `Q_OBJECT`,
  `QML_NAMED_ELEMENT(DisplayList)`, all members declared in the class body
  (QtBridge rule does not apply here; same discipline):
  `source` (`QObject*`), `list` (`int`), `revision` (`int`, wake-up only)
  properties with NOTIFY; `fetchedRevision` (`int`, read-only, NOTIFY) — the
  revision of the list the next sync uploads;
  `loopStartId`/`loopEndId` (`double`, CONSTANT) exposing the
  reserved ids so checks never spell the numbers.
- `Q_INVOKABLE QVariantMap face(double id)`: `{x, y, width, height, fill}`
  of the first rect with that id in the last decoded list; empty map if absent.
- Fetch — frame-time pull (plan Contract §2, normative): `revision` binds
  `source.displayRevision` and its setter only calls `update()`.
  `itemChange(ItemSceneChange)` connects/disconnects `pullFrame` to the
  window's `afterAnimating` (GUI thread, emitted before the window asks the
  render thread to sync). `pullFrame` reads the live `displayRevision`
  property directly; when it differs from `fetchedRevision` it calls
  `QMetaObject::invokeMethod(source, "displayList", Qt::DirectConnection,
  Q_RETURN_ARG(QByteArray, blob), Q_ARG(int, list))` (Swift `Int` registers
  as `QMetaType::Int`, so `int` matches), keeps the `QByteArray`, decodes
  into a `PdDlView`, sets `fetchedRevision`, calls `update()`. Decode failure
  is `qFatal` (current policy at `timeline_renderer.cpp:270-273`). No
  `updatePolish`.
- Threading: `pullFrame` (GUI thread) does fetch + decode; `updatePaintNode`
  reads only the decoded view and uploads nodes.
 - Nodes lifted from `src/render/timeline_renderer_nodes.cpp:45-374`:
  `RectGeometryNode` (batched geometry upload), `PainterRectNode`
  (software-graph `QSGRenderNode` fallback), `RectLayerNode` (geometry vs
  painter switch), `RectClipNode` (label clip rect, driven by
  `PD_DL_LABEL_CLIP`), `LayoutCache` (decoded `(text, family, weight,
  letterSpacing, pixelSize, alignment, w)` memo per `LayoutKey` at `:185-195`
  with per-frame purge), `LabelLayerNode` (slot pool, `QSGTextNode` with
  NativeRendering); `RollRootNode` (`:376-398`) is replaced by a fixed
  `under → labels → over` root with no band switch, fed by the
  `PD_DL_RECT_OVER` bit; `LabelSlot.background` (`:271`) goes — label
  backgrounds arrive as the last under-rects from Swift (plan.md:135-139,
  Contract §2 at plan.md:176-183). Software path and NativeRendering stay.
- Fonts: one `QFont` per `(PdDlFont, pixelSize)` built as
  `src/ui/songview/quick/swiftroll/native/font_metrics.cpp:18-24` does
  (family, pixelSize, weight, AbsoluteSpacing letterSpacing, PreferNoHinting,
  `tnum`), cached by key; layouts cached by `(text, font)`.
- Registration rides `qt_add_qml_module(porydaw_app …)` exactly like
  `TimelineRenderer`/`ItemCursor` (`CMakeLists.txt:180-201` sources,
  `CMakeLists.txt:221-293` module stanza).

## Implementation steps

1. Create the header with the Contract §2 class shape; `loopStartId` /
   `loopEndId` return the reserved ids as doubles.
2. Implement fetch + `face()` against the last decoded view; first-rect-wins
   on duplicate ids; empty map when absent (including `PD_DL_ID_NONE`
   queries with no match).
 3. Port the node classes: keep `drawable` (w,h > 0, nonzero alpha),
   `pixelCoverage` DPR snap, geometry/painter commits, slot reuse and
   clip attach/detach driven by `PD_DL_LABEL_CLIP`; retype inputs from
   `RollProjection::Rect` / `RollRender::Label` to `PdDlRect` /
   (`PdDlLabel` + resolved `PdDlFont` + text slice); key layouts by the
   decoded `(text, family, weight, letterSpacing, pixelSize, alignment, w)`
   with alignment from the `PD_DL_LABEL_ALIGN_*` bits; drop
   `LabelSlot.background` (backgrounds are under-rects); build the fixed
   `under → labels → over` root, partitioning rects by `PD_DL_RECT_OVER`.
4. Collapse today's `ensureScene`/`fetchContent`
   (`timeline_renderer.cpp:247-281`) into `pullFrame`; no scene rebuild step
   remains. `updatePaintNode` uploads only, following
   `timeline_renderer_nodes.cpp:402-419`: reuse root node unless the
   software/hardware branch flipped.
4b. `DisplayListProbe` (`@QtBridgeable`, `QmlInstantiableStatus`, precedent
   `GridInputClipProbe.swift`): `@QtTracked displayRevision`,
   `displayList(_:)` returning one rect at `x = step·10` via
   `DisplayListWriter`, a one-row `QListModel` carrier (`SceneRect`-shaped,
   `x = step·10`) and `advance()` that rebuilds the list, bumps the revision
   and syncs the row in one call. `tst_DisplayListSameFrame.qml`: a
   `DisplayList` on the probe and a `Repeater` delegate over the carrier row;
   in the window's `onAfterAnimating` (connected after the item's, so it runs
   later) record `(delegate.x, item.fetchedRevision, probe.displayRevision)`
   per frame; call `advance()` ten times with one `waitForRendering` each;
   assert every recorded frame has `fetchedRevision === displayRevision`
   and `face(id).x === delegate.x` — the grid never lags the row.
5. Register sources and QML module entries; `TimelineRenderer` stays
   untouched (one surface on exactly one item type; deletion is Task 9).

## Acceptance predicate

- `deno task build:checks` covers compilation of the new item and module
  registration.
- `deno task checks:bridge` covers the QtBridge surface guard for the new
  `displayRevision`/`displayList` source members the item fetches.
- `deno task checks:qml --filter DisplayListSameFrame --verbose` covers the
  plan Contract §2 invariant: every frame syncs the newest list, including
  frames triggered only by a synchronous row update; it also exercises the
  1-arg `invokeMethod` (plan Open risk 1, resolved by QtBridge's `Int` →
  `QMetaType::Int` registration). If it fails because `update()` from
  `afterAnimating` missed that frame's sync, STOP — the hook is a user
  decision, not a fallback.
- Throwaway QML smoke (not committed; controller-run, needs native
  desktop): the probe publishing one under-rect, one `PD_DL_LABEL_CLIP`
  label and one over-rect with known ids/colors must paint in that order
  and `face(id)` must return each rect's `{x, y, width, height, fill}`.
- Gap: no committed raster-identity check in this task (nothing uses the
  item yet); pixel identity is gated by the cutover tasks' raster suites.

## Task-specific constraints

- Qt ownership/threading review applies (seat `qt-cpp-reviewer`): no work
  in `updatePaintNode` beyond upload; node lifetime owned by the scene
  graph; `qFatal` on decode failure, never a silent fallback frame.
- Do not move projection/culling/layout code; Swift emits results as rects.
