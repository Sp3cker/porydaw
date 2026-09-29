# Native display-list boundary — implementation plan

Worktree: `.worktrees/swift-qml-grid` (Swift 6.4 `swift-6.4-RELEASE`, arm64; Qt 6.11; QML via
QtBridge). Supersedes the ownership split in `docs/plans/native-timeline-renderer/plan.md` (executed,
`b774dd32`). All file:line citations verified against source on 2026-09-28.

## Status: planned; Task 0 measured (go)

Task 0 (2026-09-28, `swiftc -O`, arm64): a writer shaped like Contract §3 packing the per-frame
worst case — 3 000 visible notes × (fill + 4 border rects) + 400 grid lines + 500 labels = 15 400
rects + 500 labels, 768 KB — costs **≈185 µs per frame (12 ns per record)** including the snapped
projection arithmetic. Budget was 0.5 ms → proceed. Synthetic (no `GridSceneInput` walk).

## The problem this plan removes

The executed renderer plan made C++ an "exact port" of Swift projection (`native-timeline-renderer/plan.md:137-164`).
The port is a second copy of ~20 formulas (`roll_projection.h`, `roll_scene.cpp`, `ruler_scene.cpp`,
`drawer_scene.cpp`, `timeline_renderer.cpp:430-500`) and it has already drifted from the Swift copy that
production hit-testing uses:

- Swift `EditorCamera.displayX` rounds `(tick·ppt − scrollX)·dpr` as one value (`src/swift/app/timeline/EditorCamera.swift:233-236`);
  `PitchProjection.snappedEdge` rounds `(row·keyHeight − scrollY)·dpr` (`:93-97`).
- C++ `Camera::viewX` rounds `tick·ppt·dpr` and `scrollX·dpr` separately and subtracts
  (`src/render/roll_projection.h:34-40`).
- `EditorCamera.setHScroll` keeps fractional scroll (`EditorCamera.swift:270-272`; pinned by
  `src/checks/rollcheck/static/camera.swift:37-38`), so the two orders differ by one physical pixel whenever
  the fractional parts straddle `.5`. Hit-testing (`PianoGrid+SceneSync.swift:243-261`) and the painted
  note therefore disagree at those scrolls. Raster checks pass because they only see the C++ side.

Full duplicate inventory (both-side rows, single-side rows, every Swift production projection site, every
parity check): `agent://FormulaDupInventory` transcript, reproduced in `inventory.md` beside this plan.

## Decision

**Swift owns every formula. Native code owns nothing but pixels.**

Concretely:

1. Swift computes, per frame, the viewport-space geometry each surface paints (rects and labels, already
   snapped, already culled, already fitted) and packs it into one binary **display list**.
2. The wire format is defined **once**, in a C header (`src/render/display_list.h`) that Swift imports
   through a module map and C++ includes. Record types are C structs; Swift appends their bytes verbatim;
   the decoder is C (`src/render/display_list.c`) and is called by both the Qt item and a swiftcore
   round-trip check. Nothing about the format exists in two places.
3. The C++ that survives is exactly the Qt-bound residue: one `QQuickItem` (`DisplayList`) that pulls the
   list from its QtBridge source, decodes it with the C decoder, and turns records into scene-graph
   nodes; plus the existing `font_metrics.cpp`. No projection, culling, layout, label-fit, contrast, or
   time-axis code remains native.
4. Every C++ scene file is deleted: `roll_scene.{h,cpp}`, `ruler_scene.{h,cpp}`, `drawer_scene.{h,cpp}`,
   `roll_projection.h`, `roll_content.h`, `drawer_content.h`, `roll_labels.h`, `timeline_renderer.{h,cpp}`,
   `timeline_renderer_nodes.cpp` (its node classes move into the new item file). ~2 900 lines of C++
   become ~600 lines of C++ plus ~150 lines of C.

### Rejected alternatives

- **Shared C projection kernel** (C `static inline` formulas imported by Swift for hit-testing and called
  by C++ scene builders). Keeps all C++ scene code; puts semantic geometry (what snaps, where a tick is)
  in C; needs C-layout mirrors of Swift `TimeAxis`/`GridSegment`/`GridMetrics`, i.e. a second copy of the
  *types* instead of the formulas.
- **Swift kernel exported with `@_cdecl`, called per record per frame from C++ scene builders.** Keeps all
  C++ scene code, adds ~20 C entry points, and needs the same C-layout mirrors for time-axis inputs.
- **Reverse C++ interop (`-emit-clang-header`)**. New compiler mode on a Qt-linked module; nothing in the
  repo uses it; agents would trip on it.

### Why per-frame Swift work is acceptable

The pre-renderer cost was never projection arithmetic. The profile that motivated the renderer plan was
dominated by `PaletteMath.hex`/`channels` string formatting per row (removed in `6d5cca20`) and by
`QListModel` row diffing across the bridge (removed in `0142cbba`). Evidence that binary per-frame packing
is cheap: `RollDrawingContent.pack` already packs the *entire song* allocation-free on every content
change (`src/swift/app/roll/RollDrawingContent.swift:112-158`), and automation already re-packs on every
zoom step (`native-timeline-renderer/plan.md:537-538`). A display list is bounded by the viewport, not
the song. Task 0 measures this before any cutover and records the number below.

### Stale frames

The old design had two channels (camera scalars via queued QtBridge NOTIFY, content via revision) and
therefore could paint a frame with a new camera and old content. A display list is one channel: the
Swift rebuild writes the bytes and bumps `displayRevision` in the same call; the item reads the live
`displayRevision` property at polish (today's `ensureScene`, `src/render/timeline_renderer.cpp:247-257`)
and fetches synchronously. There is no second input to be stale against.

## Contract

### 1. Wire format — `src/render/display_list.h` (C, no Qt; the only definition)

```c
#define PD_DL_MAGIC   0x314C4450u        /* "PDL1" little-endian */
#define PD_DL_VERSION 1u

typedef struct {
    uint32_t magic, version;
    uint32_t fontCount, rectCount, labelCount, textBytes;
} PdDlHeader;                            /* 24 B; followed by fonts, rects, labels, text — each array
                                            starts on an 8-byte boundary (writer pads, decoder checks) */

typedef struct {                         /* 24 B */
    uint32_t id;                         /* PD_DL_FONT_* slot the labels reference */
    int32_t  weight;
    double   letterSpacing;
    uint32_t familyOffset, familyLength; /* UTF-8 in the text block */
} PdDlFont;

typedef struct {                         /* 48 B; viewport logical px, already snapped; w,h > 0 */
    double   x, y, w, h;
    uint64_t id;                         /* PD_DL_ID_NONE, a note id, or a PD_DL_ID_* reserved id */
    uint32_t argb;
    uint32_t flags;                      /* PD_DL_RECT_OVER: paint above this list's labels */
} PdDlRect;

typedef struct {                         /* 64 B; viewport logical px; text laid out in (w,h) */
    double   x, y, w, h;
    uint64_t id;
    uint32_t textOffset, textLength;     /* UTF-8 in the text block */
    uint32_t argb, flags;                /* PD_DL_LABEL_CLIP | PD_DL_LABEL_ALIGN_{LEFT,RIGHT,CENTER} */
    uint32_t fontId, pixelSize;          /* pixelSize is the fitted size Swift decided */
} PdDlLabel;

enum { PD_DL_RECT_OVER = 1u };
enum { PD_DL_LABEL_CLIP = 1u, PD_DL_LABEL_ALIGN_LEFT = 0u, PD_DL_LABEL_ALIGN_RIGHT = 2u,
       PD_DL_LABEL_ALIGN_CENTER = 4u, PD_DL_LABEL_ALIGN_MASK = 6u };

enum { PD_DL_ID_NONE = 0, PD_DL_ID_LOOP_START = 0xFFFFFFFF00000001ull,
       PD_DL_ID_LOOP_END = 0xFFFFFFFF00000002ull };

typedef struct {
    const PdDlHeader *header; const PdDlFont *fonts; const PdDlRect *rects;
    const PdDlLabel *labels; const char *text;
} PdDlView;

bool pd_dl_decode(const void *bytes, size_t length, PdDlView *out);  /* false on any inconsistency */
```

Rules: paint order is under-rects (record order) → labels (record order) → over-rects (record order),
where a rect is "over" iff `PD_DL_RECT_OVER` is set; this reproduces today's `RollRootNode` layering
(`timeline_renderer_nodes.cpp:376-398`: plot `under → labels → over`, keyboard `under → over →
labels` becomes all-under). Label backgrounds (`RollRender::Label.background`, `roll_labels.h:15-16`)
are emitted by Swift as the last under-rects. Dashed outlines, frames and rings are emitted as rects by
Swift, exactly as the pre-renderer
Swift primitives did (`git show 63f492d8:src/swift/app/roll/GridScene+Primitives.swift`). Layer
interleaving with QML items is expressed by using several `DisplayList` items on several lists, as the
drawer already does with several `TimelineRenderer` items (`AutomationPlot.qml:46,85,234`). The format
is in-process and never persisted: layout is the C ABI of the running build (same compiler, same arch),
which is why the round-trip check exists.

Record ids: note faces use the note's id; the two loop markers use the reserved ids; every other rect
uses `PD_DL_ID_NONE`. Reserved ids are exported to QML as `CONSTANT` properties of the item
(`loopStartId`, `loopEndId`) so check helpers never spell the numbers.

### 2. Item — `src/render/display_list_item.{h,cpp}` (C++, Qt-bound)

```cpp
class DisplayList : public QQuickItem {
    Q_OBJECT
    QML_NAMED_ELEMENT(DisplayList)
    Q_PROPERTY(QObject *source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(int list READ list WRITE setList NOTIFY listChanged)
    Q_PROPERTY(int revision READ revision WRITE setRevision NOTIFY revisionChanged)   // wake-up only
    Q_PROPERTY(int fetchedRevision READ fetchedRevision NOTIFY fetchedRevisionChanged) // check probe
    Q_PROPERTY(double loopStartId READ loopStartId CONSTANT)
    Q_PROPERTY(double loopEndId READ loopEndId CONSTANT)
public:
    Q_INVOKABLE QVariantMap face(double id);   // {x,y,width,height,fill} of the first rect with that id
                                               // in the last decoded list; empty map if absent
protected:
    void itemChange(ItemChange, const ItemChangeData &) override;  // (dis)connect window afterAnimating
    QSGNode *updatePaintNode(QSGNode *, UpdatePaintNodeData *) override;  // upload only
private:
    void pullFrame();                          // GUI thread, once per frame before sync: fetch if moved
};
```

Fetch protocol — **frame-time pull, not NOTIFY-driven**. `revision` binds `source.displayRevision` and
its setter only calls `update()`: it exists so a list-only change (no other item moved) still produces
a frame. Freshness comes from `pullFrame`, connected to `QQuickWindow::afterAnimating` — emitted on the
GUI thread before the window asks the render thread to synchronize (Qt 6.11 docs). `pullFrame` reads the
live `displayRevision` property (direct metacall into the Swift getter, no signal), and when it differs
from `fetchedRevision` calls `QMetaObject::invokeMethod(source, "displayList", Qt::DirectConnection,
Q_RETURN_ARG(QByteArray, blob), Q_ARG(int, list))` (QtBridge registers Swift `Int` as `QMetaType::Int`,
`QVariant.swift:224-228`, `QMetaObjectBuilder.swift:332-335`), keeps the `QByteArray`, decodes into a
`PdDlView`, updates `fetchedRevision` and calls `update()`. Invariant: **every frame, whatever triggered
it, syncs the newest list** — including a frame triggered by the synchronous `cameraScroll` row that
moves velocity handles, the playhead and the drawer containers in the same turn. Today's item lags that
row by one queued NOTIFY (`TimelineRenderer.scrollX`), so handles and grid can disagree for a frame; the
pull closes it. [INFERENCE: `QQuickItem::update()` issued inside `afterAnimating` is collected by that
frame's sync — Task 2's same-frame check is the proof; if it is not, stop and ask before choosing a
different GUI-thread hook.] `updatePolish` is not used. A decode failure is `qFatal` (today's policy,
`timeline_renderer.cpp:270-273`). An empty list (valid header, zero records) and a null source both
paint nothing.
Node building: `RectGeometryNode`/`PainterRectNode`/`RectLayerNode`/`RectClipNode`/`LayoutCache`/
`LabelLayerNode` from `timeline_renderer_nodes.cpp:45-374` move into the item file; `RollRootNode`
(`:376-398`) is replaced by a fixed `under → labels → over` root with no band switch; `LayoutKey`
(`:185-195`) is keyed by the decoded `(text, family, weight, letterSpacing, pixelSize, alignment, w)`;
`LabelSlot.background` (`:271`) goes — backgrounds arrive as rects. The software-scene-graph painter
path and `QSGTextNode` NativeRendering stay. Fonts: `QFont` per `(PdDlFont, pixelSize)` built as
`font_metrics.cpp:18-26` does, cached by key. Today's `ensureScene`/`fetchContent`
(`timeline_renderer.cpp:247-281`) collapse into `pullFrame`; no scene rebuild step remains.

Registration rides `qt_add_qml_module(porydaw_app …)` exactly like `TimelineRenderer` and `ItemCursor`.

### 3. Sources — Swift

Every source that owns a `DisplayList` item exposes, in its `@QtBridgeable` class body:

```swift
@QtTracked public var displayRevision = 0
public func displayList(_ list: Int) -> Data
```

`displayList` returns a buffer the source retains; the item copies it into a `QByteArray` at fetch.
All lists of one source rebuild together and bump `displayRevision` once. Sources and their lists:

| source | lists | replaces |
|---|---|---|
| `GridScene` | 0 plot, 1 keyboard, 2 ruler | `drawingContent()` + `contentRevision` (`GridScene.swift:91-102`); item camera props `pixelsPerTick/keyHeight/scrollX/scrollY/devicePixelRatio/bandSelection*/hoverPitch` (`PianoRollCanvas.qml:18-27,44-49`, `EditorRulerBand.qml:38-44`). Keyboard stays on the legacy pair through 4a, ruler through 4b; `displayList` returns an empty list for a band not yet cut over |
| `VelocityPage` | 0 grid, 1 transient | `drawingContent()` (`VelocityPage.swift:211-212`), `DrawerStaticsContent` §11/§14 |
| `VoiceChangesPage` | 0 grid | `drawingContent()` (`VoiceChangesPage.swift:174-175`) |
| `AutomationPage` | 0 axis, 1 statics, 2 preview | `drawingContent()` (`AutomationPage.swift:116-117`), `AutomationDrawingContent` §11/§12/§13 |

Rebuild triggers: the source's existing content-change path **and** its camera-change path
(`PianoGrid.refreshCameraPresentation`, `PianoGrid+SceneSync.swift:99-122`; `VelocityPage.refreshCamera`
`VelocityPublication.swift:85-98`; `VoiceChangesPage.refreshCamera` `VoiceChangesPage.swift:377-381`;
`AutomationContentPublication.refreshHorizontalProjection` `:131-153`). Lists are viewport-space, so
**every** camera change (scroll-only included) rebuilds the visible source's lists:
`DocumentWorkspace.applyCamera` (`DocumentWorkspace.swift:383-391`) loses its `(.voiceChanges, false):
break` arm, and `refreshCamera` on each page ends with the list rebuild instead of
`publishTransient(updateDrawing: false)`. The hidden-section deferral (`deferredCameraZoom`, `:376-399`)
stays: a hidden page's lists may be stale; showing or re-attaching it flushes one rebuild. Every
camera-stability assertion inverts deliberately — this is a behavior change to pinned checks, not a rename:
`note_rendering_economy.swift`, `VelocityContentProbe.swift:241-257`, `VoiceChangesPageChecks.swift`,
`AutomationDrawingContentChecks.swift:190-230` now assert that camera moves change `displayRevision`
and the list bytes while the content-tier inputs (`GridSceneInput` key, page content keys) stay
untouched. Automation list numbering follows today's `drawerLayer` values in `AutomationPlot.qml`
(axis 0, statics 1, preview 2).

Frame-tier skip: a source rebuilds only when `(content key, camera snapshot, viewport size, dpr)` moved;
the content tier keeps `RollNotesSectionKey`/`displacesNotes` keying (`RollDrawingContent.swift:42-50`,
`GridScene+Rebuild.swift:16-20`) for the per-note fills, spans and selection it resolves once per content
key into a tick-sorted record array; the frame tier culls and projects that array — O(visible) per frame,
never O(notes). `notesSectionCache` (`GridScene.swift:101`) is replaced by that record array, not kept as
packed bytes.

Writer: `src/swift/app/timeline/DisplayListWriter.swift` — `struct DisplayListWriter` with
`rect(_ r: PdDlRect)`, `label(_ l: PdDlLabel, text: String)`, `font(_ f: PdDlFont, family: String)`
(the writer fills the text offsets/lengths), `finish() -> Data`. Storage is four typed arrays of the
imported C structs — `[PdDlFont]`, `[PdDlRect]`, `[PdDlLabel]`, `[UInt8]` text — so appends are plain
value appends with no pointer code; `finish()` writes `PdDlHeader` then each array's `span.bytes` into
the retained `Data`, padding to 8 bytes. The only unsafe calls are the `RawSpan.withUnsafeBytes`
hand-offs into `Data.append` inside `finish()` (proven on Swift 6.4: `Array.span.bytes`,
`RawSpan.withUnsafeBytes`, `Data.bytes: RawSpan`, `Array(capacity:initializingWith: OutputSpan)`
all compile; `Data.append(contentsOf: RawSpan)` does not exist). Arrays keep capacity across frames
(`removeAll(keepingCapacity:)`). Readers in Swift (the round-trip check) walk `data.bytes` with
`unsafeLoadUnaligned(fromByteOffset:as:)` — never a stored `RawSpan` (it cannot escape its scope).
Replaces `DrawingContentBinary.swift`.

Builders (per-frame, Swift): `RollDisplayLists.swift` (rewrite of `RollDrawingContent.swift`; ports
`roll_scene.cpp`, `ruler_scene.cpp` and the label passes of `timeline_renderer.cpp:300-338,430-500`
back into Swift using the production functions hit-testing already uses: `EditorCamera.viewX`,
`PitchProjection.rowTop/rowBottom`, `GridMetrics.noteBox/noteBorderPixels/selectionRingPixels/
fittedFrameThickness`, `RollGrid.forEachSubdivision`, `TimeAxis.forEachGridLine`, `GridTypography`
fits and `NativeFontMetrics.advance`), `DrawerStaticsContent.swift` and `AutomationDrawingContent.swift`
(rewritten to emit viewport rects through the same writer).

### 4. One projection

`EditorCamera.displayX` and `PitchProjection.snappedEdge` adopt the raster-proven order
(`round(content·dpr)/dpr − round(scroll·dpr)/dpr`). `displayX(tick:origin:dpr:)` becomes
`viewX(tick:dpr:)` — the `origin` parameter dies with it (its only non-zero caller is
`camera.swift:39`). `PitchProjection.rowTop/rowBottom` keep their names and signatures; only
`snappedEdge`'s body changes, so their ~20 check callers need no edit. `contentTickX`/`contentRowTop`
stay as the content-space halves. Reveal math (`EditorCamera.swift:336-356`) tests visibility with
`viewX` and keeps its unrounded `contentX` scroll replacement (`setHScroll` preserves fractions by
design). Hit-testing, band selection, hover chip,
pitch-bend anchors and the drawer projections call these and nothing else. This is the only behavior
change in the plan: hit zones move by ≤ 1 physical pixel at the scrolls where paint and hit disagreed.
`src/checks/rollcheck/static/camera.swift:39-40,231-240` are re-pinned to the unified formula in the
same task (message text changes → `deno task proof:edit` in that commit).

### 5. What leaves the repo

C++ (all of `src/render/` except the new item and the C pair) and the `porydaw_app` source entries at
`CMakeLists.txt:180-201`. Swift: `DrawingContentBinary.swift`; the §11/§12/§13/§14 drawer record
machinery in `DrawerStaticsContent.swift`; `GridScene.contentRevision`/`drawingContent`;
`PianoGrid.pixelsPerTick` if the item was its only consumer (verify with references); check-only formula
copies `src/checks/rollcheck/note_name_labels.swift:21-59` (`faceFits`/`nameFits`) — the checks that used
them read `face()` or raster instead. QML: every camera binding on renderer items.

### 6. Native boundary statement — landed in AGENTS.md ("Native boundary" section)

AGENTS.md now names `src/app/`, `src/audio/`, `src/project/`, `font_metrics.cpp` and the display-list
pair in `src/render/` as the only native code, states that native code never projects, culls, lays out
or decides visibility, and carries one transitional sentence about the `TimelineRenderer` scene code.
Task 9 deletes that sentence with the code.

### 7. Reconciliation with `feature/grid-cpu` (`ccb68ab5..ed6e9d26`, now on this branch)

The plan was written at `5ac7c63c`; four perf commits landed on top. They optimize the QML-delegate
and bridge-wakeup paths, not the painted batch, so the design stands — with these normative deltas:

| grid-cpu change | effect on this plan |
|---|---|
| QtBridge same-thread NOTIFY coalescing (`cmake/patches/qtbridge/qtbridge-object-return.patch`, `flushEmissions`): emissions queue and flush once per event-loop turn, FIFO | Neutral for the item: freshness is the frame-time pull (Contract §2), which reads `displayRevision` directly and never waits for the NOTIFY. The NOTIFY only guarantees a frame for list-only changes. What is **not** solved by the list alone: items driven by the synchronous `cameraScroll` row (velocity handles, playhead, drawer containers — `VelocityPage.qml:122-130` exists precisely so the container never lags a queued NOTIFY) render in the same turn; without the pull the grid would follow one flush later, as `TimelineRenderer.scrollX` does today. Task 2 adds the same-frame check that proves handles and grid agree in the first frame after a scroll |
| Hidden drawer sections defer camera work (`DocumentWorkspace.deferredCameraZoom`, `:376-399`, flushed on show/attach; document rebuilds clear it) | Kept. Deferral now covers scroll-only too (all lists are viewport-space); `applyCamera` calls each visible page's `refreshCamera` for both scroll and zoom (Contract §3). Invariant: a hidden page's lists may be stale; a visible page's lists are never stale |
| Velocity handles are tick-space QML delegates placed from the camera carrier's `pixelsPerTick` (`VelocityPage.qml:122-130,396-404`; carrier `GridScene+Rebuild.swift:38-46` publishes `scrollX/scrollY/pixelsPerTick`); `VelocityPage.refreshCamera` updates handle `x/endX` in place (`VelocityPublication.swift:85-98`) | Untouched by Tasks 4a–8: handles, ramp, hover guides and the `cameraScroll` carrier are interactive delegates, not painted lists. Task 6b adds the list rebuild to `refreshCamera` after the in-place handle update and leaves `contentScrollX`/`contentPixelsPerTick` bindings alone. `VelocityProjection.stableXForTick` keeps calling `contentTickX` (survives Contract §4) |
| Notes section cached across draw-preview-only rebuilds (`notesSectionCache`, `RollNotesSectionKey`, `displacesNotes`; `1c690352`) | Content-tier keying survives as a tick-sorted record array (Contract §3 “Frame-tier skip”); the packed-bytes cache is deleted with `RollDrawingContent`. `displacesNotes` stays a `GridSceneInput` field |
| `syncModel` prefix/suffix diff (`QListModelSync.swift`) | Unrelated to lists; not in any write set |

Cost model after cutover, per scroll frame: today = C++ `buildRoll` O(visible) + node upload; after =
Swift build O(visible) (Task 0: 12 ns/record) + one `QByteArray` copy + `pd_dl_decode` + the same node
upload. The delta is the copy and decode, tens of µs at the worst-case list size. What grid-cpu removed
(per-row model rewrites, per-NOTIFY wakeups) stays removed because lists ride one NOTIFY per turn.

## Global Constraints (read once; briefs carry deltas only)

- Rules in force: `.omp/rules/proof-ledger-workflow.md`, `qtbridge-surface`, `swift-standards`,
  `swift-typecheck-complexity`, `text-contrast`, AGENTS.md conventions (no hard-coded pixels, ≤2-line
  comments, `deno task` only, never `grep` without `path`).
- Pixel identity is the gate for every cutover task: the raster suites listed under Verification must
  stay byte-identical against the current `TimelineRenderer` output at dpr 1 and 2. A cutover task that
  cannot reach identity stops and reports the differing pixels; it does not loosen a check.
- No dual formats: `DisplayList` decodes only `display_list.h`; `TimelineRenderer` keeps serving the
  surfaces not yet cut over until Task 9 deletes it. A surface is on exactly one item type.
- One writer per file per wave. Check-only production reads are banned; `face()` is the only
  renderer-state query and it answers about the decoded list the item paints.
- Implementers reuse the verification commands recorded in each brief; reassess only if scope changes
  or a command proves stale, and report the mismatch instead of narrowing.
- Keep check report messages byte-identical where the assertion class is unchanged (ledger anchors).
  Where a class genuinely changes, repair the anchor with `deno task proof:edit` in the same commit.
- Swift LSP: run `deno task lsp:swift` after the CMake reconfigure in Task 1 and before any rename.
- Per-frame builders are allocation-free in steady state and do no per-record string work: record
  colors are `UInt32` ARGB resolved from the theme tables (`ThemeColorTables.swift`) or note fills
  computed at content time; parsing a palette slot string (`SceneRectPacking.argb`) is allowed only
  per palette slot, never per record. `PaletteMath` never runs on the frame path.
- Swift 6.4 buffer vocabulary (verified on this toolchain): `Array.span` / `.span.bytes` (`RawSpan`),
  `Data.bytes` (`RawSpan`) with `unsafeLoad[Unaligned]`, `Array(capacity:initializingWith:)` over
  `OutputSpan`, `InlineArray<N, T>` for fixed slot tables (the six palette slots). `RawSpan` values are
  non-escaping: use them inline or as borrowed parameters, never stored. Unsafe pointers appear only in
  `DisplayListWriter.finish()` and where a C decoder/metrics function takes a pointer. Not in scope:
  `~Copyable` writer types, `-strict-memory-safety`, `@lifetime` annotations.
- QML checks: after any Swift mutation, let one frame render (`waitForRendering(item)`) before reading
  `face()` or a raster; `fetchedRevision` is the probe for "what this frame drew". The same-frame
  invariant (Contract §2) is proven once by Task 2's check; other checks do not re-prove it.

## Tasks

| # | Task | Route | Seat | Write set (closed) |
|---|---|---|---|---|
| 0 | Measure per-frame pack cost (throwaway, Release build) | Direct | controller | none committed; number recorded in this file |
| 1 | Wire format, C decoder, Swift writer, round-trip check | SDD | sdd-implementer | `src/render/display_list.{h,c}`, `src/render/module.modulemap`, `src/swift/app/timeline/DisplayListWriter.swift`, `src/swift/app/CMakeLists.txt`, root `CMakeLists.txt`, `src/checks/CMakeLists.txt`, `src/checks/displaylist/DisplayListChecks.swift`, `src/checks/checkcatalog.cpp`, swiftcore suite dispatch |
| 2 | `DisplayList` QQuickItem + same-frame check | SDD | qt-cpp-reviewer (Qt ownership/threading) | `src/render/display_list_item.{h,cpp}`, root `CMakeLists.txt`, `src/checks/editorqml/{DisplayListProbe.swift,tst_DisplayListSameFrame.qml}`, `src/checks/CMakeLists.txt` |
| 3a | Projection rename (no behavior change) | SDD | sdd-implementer | `src/swift/app/timeline/EditorCamera.swift`, `src/swift/app/timeline/GridGeometry.swift`, callers named in `inventory.md` §3, every check file calling `displayX`/`noteContentRect`/`noteContentBox` (rename only; assertions unchanged), affected `proof.*.txt` rows (path/line anchors only) |
| 3b | One projection formula (the plan's only behavior change) | SDD | sdd-implementer | `EditorCamera.swift` (`viewX`, `PitchProjection.snappedEdge` bodies), `src/checks/rollcheck/static/camera.swift`, its `proof.*.txt` rows via `proof:edit` |
| 4a | Roll plot (list 0) on display lists; plot check migration | SDD | sdd-implementer `:high` | `src/swift/app/roll/{RollDisplayLists,GridScene,GridScene+Notes,GridScene+Rebuild,PianoGrid,PianoGrid+SceneSync}.swift`, `src/ui/songview/quick/PianoRollCanvas.qml` (plot item only), `src/checks/editorqml/RollNoteFaces.js` + roll consumers, `src/checks/rollcheck/note_rendering_*.swift` (incl. the cull-bound predicate in `note_rendering_economy.swift`, no new file), `note_name_labels.swift`, `proof.*` rows |
| 4b | Roll keyboard (list 1) on display lists; keyboard check migration | SDD | sdd-implementer | `RollDisplayLists.swift`, `GridScene.swift`, `PianoRollCanvas.qml` (keyboard item), keyboard checks in `src/checks/rollcheck/` and `src/checks/rollqml/`, `proof.*` rows |
| 5 | Ruler on display lists | SDD | sdd-implementer | `RollDisplayLists.swift`, `src/ui/songview/quick/swiftroll/EditorRulerBand.qml`, ruler check helpers (`ShellGridMenuSupport.qml`, `tst_EditorDrawerChrome.qml`, `tst_ShellChromeVisuals.qml`, `tst_ShellMenusLoop.qml`) |
| 6a | `DrawerStaticsContent` builder API + parity check against the legacy packer | SDD | sdd-implementer `:high` | `src/swift/app/drawer/DrawerStaticsContent.swift` (additive: builders beside the legacy packer, which Task 9 deletes), `src/checks/drawerpresentation/DrawerStaticsParityChecks.swift`, `src/checks/checkcatalog.cpp`, swiftcore suite dispatch |
| 6b | Velocity drawer on display lists | SDD | sdd-implementer | `src/swift/app/drawer/velocity/{VelocityPage,VelocityPublication}.swift`, `src/ui/songview/quick/drawer/VelocityPage.qml`, velocity checks (task-6b brief) |
| 7 | Voice-changes drawer on display lists | SDD | sdd-implementer | `src/swift/app/drawer/voicechanges/{VoiceChangesPage,VoiceChangesPublication}.swift`, `src/ui/songview/quick/drawer/VoiceChangesPage.qml` |
| 8 | Automation drawer on display lists | SDD | sdd-implementer | `src/swift/app/drawer/automation/{AutomationPage,AutomationDrawingContent,AutomationContentPublication,AutomationOverlayPublication}.swift`, `src/ui/songview/quick/drawer/AutomationPlot.qml` |
| 9 | Delete `TimelineRenderer`, the C++ scene code and the legacy Swift packers; docs | Direct | controller | `src/render/` deletions, root `CMakeLists.txt`, `src/swift/app/timeline/DrawingContentBinary.swift`, legacy packer in `src/swift/app/drawer/DrawerStaticsContent.swift` and its transitional `drawerstatics-parity` suite, `docs/plans/native-timeline-renderer/plan.md` status note, AGENTS.md transitional sentence, release notes |

Serial dependencies: 1 → 2; 3a → 3b; 1, 3b → 4a → 4b → 5; 1, 2, 3b → 6a → 6b ∥ 7 ∥ 8 (disjoint writes;
none of the three touches `DrawerStaticsContent.swift` — the legacy packer goes in Task 9 with
`DrawingContentBinary.swift`); 5, 6b, 7, 8 → 9.
The legacy `contentRevision`/`drawingContent()` pair on `GridScene` serves whichever bands are not yet
on lists (keyboard through 4a, ruler through 4b) and dies in Task 5.

### Task 0 (Direct) — inline

Target: no committed files. Change: a throwaway `swiftc -O` benchmark of a Contract-§3-shaped
writer (imported-struct byte appends, 8-byte padding, string table) fed by the snapped projection
formulas of Contract §4, packing the per-frame worst case (3 000 visible notes with 4-rect borders,
400 grid lines, 500 labels) over 2 000 frames. Acceptance: ≤ 0.5 ms per frame → proceed; otherwise
stop and re-plan with the shared-C-kernel alternative. Executed; figure recorded under Status.

### Task 9 (Direct) — inline

Target: `src/render/` (keep only `display_list.{h,c}`, `display_list_item.{h,cpp}`, `module.modulemap`),
root `CMakeLists.txt:180-201` source list, `DrawingContentBinary.swift`, docs. Change: delete every
file named in Contract §5 once `grep TimelineRenderer src/ui src/checks` and
`grep DrawingContentBinary src/swift` are empty; mark the renderer plan superseded; add a release-notes
entry; delete the transitional `TimelineRenderer` sentence from AGENTS.md "Native boundary" (the only
AGENTS.md edit this plan makes after the user's review). Acceptance: `deno task build:checks`,
the full Verification list green, `deno task checks:bridge` clean.

## Checkpoints

1. After Tasks 1 + 2 (new boundary exists and is round-trip checked; nothing uses it yet).
1a. After Task 3a (pure rename): every lane green, nothing moved.
1b. After Task 3b alone, every lane green on its own commit: rasters byte-identical (C++ still paints),
    only hit-test points moved ≤1 px; the diff is the plan's only behavior change.
2. After Task 4a (plot on list 0): rasters still byte-identical, hit points unchanged from 1b — a
    raster diff is a port bug, a hit-test diff is not this task's.
2b. After Task 4b (keyboard on list 1): same gates.
3. After Task 5 (roll surface complete; `GridScene` has no legacy blob path).
3b. After Task 6a (builder API + parity check green; nothing in production uses it yet).
4. After Tasks 6b, 7, 8 (drawers; `TimelineRenderer` unreferenced).
5. Final: Task 9.

## Verification (cumulative; exact commands)

- `deno task build:checks` — compiles C, C++, Swift, QML.
- `deno task checks --filter displaylist --verbose` — Task 1 round-trip contract (new suite).
- `deno task checks --filter swiftcore --verbose` — camera/projection, economy, roll semantics, 4a roll-plot cull bound.
- `deno task checks:qml-roll --verbose` — roll QML + raster identity (plot, keyboard, ruler).
- `deno task checks:shell --verbose` — shell journeys via `face()`, chrome/ruler rasters.
- `deno task checks:qml --verbose` — drawer pages (Tasks 6a–8).
- `deno task checks:bridge` — QtBridge surface guard (new `displayRevision`/`displayList` members).
- `deno task proof check --executed` — ledger health after each checkpoint.
- `deno task format --check`.

## Open risks

1. ~~`invokeMethod` with `Q_ARG(int, list)` type mismatch~~ resolved by reading QtBridge: Swift `Int`
   registers as `QMetaType::Int` (`QVariant.swift:224-228`, `QMetaObjectBuilder.swift:332-335`), so
   `int` matches. Task 2's smoke still exercises the call once; if it returns false for any other
   reason, stop and ask (fallback with the same public shape: one slot per list).
2. Label raster identity: Swift now decides fitted pixel sizes and clip widths; C++ only positions. The
   fit functions are the same `sgf_fit`/`sgf_advance` calls (`GridTypography.swift:150-175`), so the
   numbers are identical by construction; subpixel placement is unchanged because the same node code
   positions the same `QTextLayout`s.
3. Hit-test behavior change (Contract §4) is deliberate and ≤ 1 physical pixel; any shell check that
   clicked a computed point inside that pixel will surface it — fix the check's point, not the formula.
4. Per-frame Swift cost on pathological songs is bounded by culling, not by note count; the cull itself
   walks `notesByTick`-ordered records (today's C++ does the same, `roll_scene.cpp:210-254`), guarded
   for the roll plot by Task 4a's `checkRollPlotCullBound` cull-bound check (drawers remain ungated).
5. ~~AGENTS.md boundary text needs human permission~~ landed with the user's AGENTS.md review.

## Orchestrator brief (for whoever runs this plan)

Run `.omp/rules/sdd-execution-loop.md` as written; this section is only the plan-specific delta. The
orchestrator never implements Tasks 1–8 inline and never edits a proof ledger.

### Waves and seats

| wave | tasks | seat | gate before the next wave |
|---|---|---|---|
| A | 1 | `sdd-implementer` | `deno task checks --filter displaylist --verbose` green; `checks:bridge` clean; `lsp:swift` re-run |
| B | 2 ∥ 3a → 3b | 2: `qt-cpp-reviewer`; 3a/3b: `sdd-implementer` | Task 2: same-frame check green (Contract §2 invariant), 1-arg `invokeMethod` exercised. 3a: every lane green, no raster or hit-point change (checkpoint 1a). 3b lands **alone**, every lane green, rasters byte-identical, `camera.swift` re-pin via `proof:edit` in the same commit (checkpoint 1b). Task 4a is not dispatched before Task 2 and 1b |
| C | 4a → 4b → 5 | `sdd-implementer` (4a at `:high`, then default) | after each: `checks:qml-roll`, `checks:shell`, `checks --filter swiftcore` (4a incl. the cull-bound predicate), rasters byte-identical to 1b; after 5: `GridScene` has no `drawingContent`. Checkpoints 2, 2b, 3 |
| D | 6a → 6b ∥ 7 ∥ 8 | `sdd-implementer` (6a at `:high`, then default ×3) | 6a: `checks --filter drawerstatics-parity` green (builders reproduce the legacy packer's geometry for the same inputs) — checkpoint 3b; then 6b, 7, 8 in parallel, disjoint write sets, none touching `DrawerStaticsContent.swift`. `checks:qml`, `checks:shell`. Checkpoint 4 |
| E | 9 | orchestrator, Direct | full Verification list; `grep TimelineRenderer src/ui src/checks` empty; AGENTS.md: remove the transitional sentence only |

Reasoning levels: overrides are per agent name (`cfg://task/agentModelOverrides`), so flip
`sdd-implementer` to `:high` before dispatching 4a and 6a and back to default after each lands;
`qt-cpp-reviewer` stays `:xhigh` for Task 2; `sdd-task-reviewer` runs `:high` for 2, 4a, 6a and
default elsewhere. Do not raise 1, 3a, 3b — their risk is caught by lanes, not by thinking longer.

Each brief is self-contained: dispatch with `task-N-brief.md` + this file's Contract and Global
Constraints; do not paraphrase either. Review every task with `sdd-task-reviewer` against the brief's
acceptance predicate before marking it done; bounded fix loop of 2, then escalate to the user.

### Reject on sight (agents will try these)

- Any geometry, culling, clipping or font-fit decision in `display_list.c` or `display_list_item.cpp`.
  Native code positions what Swift emitted; nothing else. A "small helper" that rounds or snaps is the
  drifted twin this plan removes.
- Camera properties on `DisplayList` (`scrollX`, `pixelsPerTick`, `devicePixelRatio`, `keyHeight`…).
  The item has `source`, `list`, `revision` and the two constant ids — Contract §2, closed.
- A JS or QML path that decodes the blob, or per-list slots added "for now" without the Task 2 smoke
  failing first (open risk 1 names the only sanctioned fallback).
- Keeping `TimelineRenderer`, `RollDrawingContent`, `DrawingContentBinary` or a §11–§14 record kind
  alive past the task that replaces it, or re-adding `contentRevision`/`drawingContent()` on a source.
- Re-pinning a camera-stability check to "bytes unchanged" instead of inverting it (Contract §3).
- Fixing a hit-test point disagreement by changing `viewX`/`snappedEdge` instead of the check's point
  (open risk 3).
- Per-record string work on the frame path: hex parsing, `String(format:)`, `PaletteMath`; label text
  is the only string a record carries.
- Stored `RawSpan`/`Span` properties, `UnsafeMutableRawPointer` bookkeeping in the writer, or
  `withUnsafeBytes` anywhere but `finish()` and the C hand-offs.
- Proof-ledger edits outside the commit whose checks prove them, "GAP → covered" flips without a new
  Swift predicate, or an agent editing a ledger it was not assigned (`proof-ledger-workflow`).
- `cmake`/`ninja` invoked directly; a root-scoped `grep`; comments over two lines; pixel literals.
- Scope creep dressed as prerequisite: "while here" refactors of `EditorCamera`, drawer publication
  rewrites beyond the write set, new QtBridge patches.

### Stop and ask the user

- Task 2's same-frame check fails (an `update()` from `afterAnimating` missed that frame's sync) or
  the 1-arg `invokeMethod` returns false — choose the hook or the slot shape with the user.
- A `pd_dl_decode` failure reaches `qFatal` in a check — the writer or the header changed shape;
  the format is versioned, so a bump is a user decision.
- Any raster check differs at all after Tasks 3a, 3b, 4a or 4b (all byte-identical); after Tasks 5–8
  only the deliberate-inversion list may change.
- Any failing check not on the deliberate-inversion list, or a pre-existing failure an implementer
  reports. Never hand off red.
- Any AGENTS.md edit beyond removing the transitional `TimelineRenderer` sentence in Task 9.

### Ledger hand-off

Each task's implementer freezes its Swift check sources and reports affected ledger paths, site
identities and final predicate locations; the orchestrator then dispatches `ledger-agent` for those
proof files only, serially per file, and verifies `A###`→`S###` links, hashes, tallies and
`deno task proof check --executed` before accepting the task. Unresolved `GAP`/`PARTIAL` rows stay
as they are.

### Done means

`src/render/` contains exactly `display_list.{h,c}`, `display_list_item.{h,cpp}`, `module.modulemap`;
every Verification command is green on the final commit; the commit is pushed; the superseded plan
`docs/plans/native-timeline-renderer/plan.md` carries a status note pointing here.
