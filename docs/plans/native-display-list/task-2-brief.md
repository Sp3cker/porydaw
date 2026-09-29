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

## Prerequisites

- Task 1 interfaces: `display_list.h` structs/ids, `pd_dl_decode` semantics,
  8-byte alignment rule.

## Interface contract

- `class DisplayList : public QQuickItem` with `Q_OBJECT`,
  `QML_NAMED_ELEMENT(DisplayList)`, all members declared in the class body
  (QtBridge rule does not apply here; same discipline):
  `source` (`QObject*`), `list` (`int`), `revision` (`int`) properties with
  NOTIFY; `loopStartId`/`loopEndId` (`double`, CONSTANT) exposing the
  reserved ids so checks never spell the numbers.
- `Q_INVOKABLE QVariantMap face(double id)`: `{x, y, width, height, fill}`
  of the first rect with that id in the last decoded list; empty map if absent.
- Fetch: `revision` binds `source.displayRevision`; a change schedules
  polish; polish reads the live `displayRevision` and, when it differs from
  the fetched one, calls
  `QMetaObject::invokeMethod(source, "displayList", Qt::DirectConnection,
  Q_RETURN_ARG(QByteArray, blob), Q_ARG(int, list))`, keeps the `QByteArray`,
  decodes into a `PdDlView` over it. Decode failure is `qFatal` (current
  policy at `timeline_renderer.cpp:270-273`).
- Threading: polish (GUI thread) does fetch + decode; `updatePaintNode`
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
   (`timeline_renderer.cpp:247-281`) into `updatePolish` (fetch + decode on
   revision move); no scene rebuild step remains. `updatePaintNode` uploads
   only, following `timeline_renderer_nodes.cpp:402-419`: reuse root node
   unless the software/hardware branch flipped.
5. Register sources and QML module entries; `TimelineRenderer` stays
   untouched (one surface on exactly one item type; deletion is Task 9).

## Acceptance predicate

- `deno task build:checks` covers compilation of the new item and module
  registration.
- `deno task checks:bridge` covers the QtBridge surface guard for the new
  `displayRevision`/`displayList` source members the item fetches.
 - Throwaway QML smoke (not committed; controller-run, needs native
  desktop): instantiate `DisplayList` against a tiny Swift source publishing
  one list (one under-rect and one over-rect with known ids/colors, one
  `PD_DL_LABEL_CLIP` label); it must paint under-rect, then label, then
  over-rect, and `face(id)` must return each rect's
  `{x, y, width, height, fill}`. This smoke also proves the 1-arg
  `invokeMethod` with `Q_ARG(int, list)` (plan Open risk 1: only the 0-arg
  `drawingContent` form at `timeline_renderer.cpp:268-270` is proven);
  record pass/fail and, on failure, fall back per the risk note without
  changing the public shape.
- Gap: no committed raster-identity check in this task (nothing uses the
  item yet); pixel identity is gated by the cutover tasks' raster suites.

## Task-specific constraints

- Qt ownership/threading review applies (seat `qt-cpp-reviewer`): no work
  in `updatePaintNode` beyond upload; node lifetime owned by the scene
  graph; `qFatal` on decode failure, never a silent fallback frame.
- Do not move projection/culling/layout code; Swift emits results as rects.
