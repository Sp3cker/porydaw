# Native C++ timeline renderer — implementation plan

Worktree: `.worktrees/swift-qml-grid` (Swift 6 + QML via QtBridge, Qt 6.11 Homebrew, macOS arm64).
All file:line citations verified against source on 2026-09-28.

## Summary

Today every roll/ruler rect and label is a Swift `GridScene` row (`QListModel<SceneRect/SceneText>`,
`src/swift/app/roll/GridScene.swift:88-126`) whose coordinates are camera-baked content px: a zoom or
scroll step runs `PianoGrid.refreshCamera()` → `rebuildStatic`/`rebuildNotes`, diffs thousands of rows
across the bridge, and QML translates containers fed by a one-row `cameraScroll` carrier
(`GridScene.swift:111-113`, `EditorSurface.qml:184-200`). We replace the draw side with one in-repo native
`QQuickItem` (`src/render/`, compiled into `porydaw_app` exactly like `src/app/item_cursor.{h,cpp}`,
`CMakeLists.txt:200-201`). Swift publishes model-space drawing content (notes as ticks+rows, row banding,
time-axis facts, label strings, palette, font specs) as ONE versioned binary blob, regenerated only on
document / selection / palette / hover / fold / typography changes. The item applies the camera
(`pixelsPerTick`, `keyHeight`, `scrollX`, `scrollY`, `devicePixelRatio`) itself in `updatePaintNode`:
projection, device-pixel snapping, minimum sizes, 1-physical-px borders and rings, culling, adaptive grid
subdivision, label placement and visibility. A zoom or scroll step changes only camera numbers: no Swift
scene rebuild, no bridge row traffic, no QML binding or JS. Output is pixel-identical; the existing raster
checks guard that. Semantics, editing, hit-testing and "what exists" stay in Swift. The vendored QtBridge
`QuickDisplayList` (injected by `cmake/patches/qtbridge/qtbridge-object-return.patch`) is replaced and
removed from the patch at the end.

## Contract

### Item API (`src/render/timeline_renderer.h`)

```cpp
class TimelineRenderer : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(TimelineRenderer)
    Q_PROPERTY(int band READ band WRITE setBand NOTIFY bandChanged)   // 0 plot, 1 keyboard, 2 ruler, 3 drawer
    Q_PROPERTY(QObject *contentSource READ contentSource WRITE setContentSource NOTIFY contentSourceChanged)
    Q_PROPERTY(int contentRevision READ contentRevision WRITE setContentRevision NOTIFY contentRevisionChanged)
    Q_PROPERTY(double pixelsPerTick ...)
    Q_PROPERTY(double keyHeight ...)
    Q_PROPERTY(double scrollX ...)
    Q_PROPERTY(double scrollY ...)
    Q_PROPERTY(double devicePixelRatio ...)
    Q_PROPERTY(bool bandSelectionActive ...)
    Q_PROPERTY(double bandSelectionX ...)
    Q_PROPERTY(double bandSelectionY ...)
    Q_PROPERTY(double bandSelectionWidth ...)
    Q_PROPERTY(double bandSelectionHeight ...)
    Q_PROPERTY(int hoverPitch ...)                                    // keyboard highlight + separator
public:
    Q_INVOKABLE QVariantMap noteFace(const QString &primitiveName);
protected:
    QSGNode *updatePaintNode(QSGNode *, UpdatePaintNodeData *) override;
};
```

- Registration rides `qt_add_qml_module(porydaw_app URI Porydaw.Ui VERSION 1.0 … NO_PLUGIN …)`
  (`CMakeLists.txt:221-243`); QML reaches it via `import Porydaw.Ui` (same as `ItemCursor`,
  `src/app/item_cursor.h:16-17`). The executable's `$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>`
  (`CMakeLists.txt:440-444`) keeps the static type registration alive.
- Camera numbers arrive as plain property bindings from PianoGrid tracked properties — no JS, no
  `Connections`, no functions:
  `pixelsPerTick: gridModel.pixelsPerTick`, `keyHeight: gridModel.rowHeight`,
  `scrollX: gridModel.cameraScrollX`, `scrollY: gridModel.cameraScrollY`,
  `devicePixelRatio: gridModel.devicePixelRatio` — `PianoGrid.swift:101-106` already publishes
  `devicePixelRatio`, `rowHeight`, `cameraScrollX/Y` (updated in `publishGeometry`,
  `PianoGrid+SceneSync.swift:143-164`); phase 0 adds `pixelsPerTick`. Item width/height are the viewport:
  `rollPlot`/`rollGutterSide`/the ruler band already size those items (`EditorRollBand.qml:53-76,100-115`;
  `EditorRulerBand.qml:8-27`). `EditorCamera.Change.geometry` therefore reduces to an item resize, which
  Quick handles natively.
- Content handoff (Decision 1): `contentSource` binds `gridModel.scene` (the QtBridge QObject proxy) and
  `contentRevision` binds a new `@QtTracked public var contentRevision = 0` on `GridScene`. In C++,
  a changed `contentSource`/`contentRevision` triggers, on the GUI thread before the next frame,
  `QMetaObject::invokeMethod(source, "drawingContent", Q_RETURN_ARG(QVariant, v))` — ONE bridge crossing
  per content revision. The slot is expressible because the vendored patch loosened
  `isSupportedReturnType` to accept identifier-typed returns (`Sources/QtBridgeMacros/Extensions.swift`
  hunk) and added `QVariant(value: Data)` → `QAbstractListModelCpp::variantFromBytes` →
  `QVariant(QByteArray)` (`Sources/QtBridge/QVariant.swift` hunk; `include/abstractlistmodel.h:56-58`).
  A `Data` *property* is not expressible in QtBridge today (supported property types are only
  Bool/Int/UInt/Double/Float/String/[String]/map/QListModel/QTableModel, `qtbridge-surface` rule), so
  slot + revision is the only no-JS shape. Synchronous fetch matches the vendored `QuickDisplayList`
  rationale (a queued rebuild paints one stale frame during camera moves).
- `noteFace(name)` answers `{x,y,width,height,fill}` for a note the item is currently drawing (e.g.
  `"gridNote_42"`), in the item's viewport space for the last painted frame. It reads only the renderer's
  own decoded blob — the rendered-output query that replaces the `exposeRows` mirror for checks
  (Decision 6), and the natural backing for any future roll accessibility interface. Unknown names →
  empty map; no rows are materialized.

### Versioned binary layout (`drawingContent() -> Data`, little-endian)

Header: `u32 magic 0x50544452 ("PTDR")`, `u16 version = 1`, `u16 sectionCount`; then per section
`u16 kind, u32 byteLength` + payload. Unknown kinds are skipped (`byteLength` makes the format
appendable). C++ decode structs: `src/render/roll_content.h`; Swift packer:
`src/swift/app/roll/RollDrawingContent.swift`. New code carries no comments (repo rule). All rounding
happens in C++; packers emit exact fields.

| # | kind | payload | Swift producer source |
|---|------|---------|----------------------|
| 1 | metrics | fixed-order f64: `baseFontPx, keyboardWidth, noteMinWidth, noteMinHeight, selectionRingDip, drawThreshold, detailMinPxPerBeat, autoGridMinCell, gridLineStrokeBase, spaceHalf, spaceTwo, dashLen, valueAllowance, rulerBeatLabelZoomFactor, keyLabelRightInset` | `GridGeometry.swift` — every value is a precomputed `fontPx` result so C++ never reimplements `fontPx`; `gridLineStroke = gridLineStrokeBase/dpr` per frame |
| 2 | fonts | `u8 count`; per font `u8 id, i32 pixelSize, i32 weight, f64 letterSpacing, u16 familyLen, utf8`. ids: 0 ruler, 1 beat, 2 bold, 3 sig, 4 chip, 5 keyLabelBase, 6 noteNameBase, 7 noteValueBase (5/6/7 are base specs; the item resolves fitted sizes per frame) | `GridTypography.swift:19-35` (`GridFontSpec`), `GridTypography.fonts` `:143-165` |
| 3 | palette | `u16 count` of `u32 ARGB` in the fixed enum order documented in `roll_content.h` (roll/keyboard/ruler/chrome/selection colors incl. `selectionRing` ink for glow math) | `src/swift/app/timeline/GridPalette.swift` |
| 4 | rows | `u16 rowCount` (the number of rows written); per row `u8 pitch, u8 flags` (bit0 accidentalLane bg, bit1 scaleHighlight) | `GridScene+Rebuild.swift:104-125` minus all camera math; rows ARE the fold projection (`ScaleProjection.projection`, `ScaleProjection.swift:30-41`) |
| 5 | notes | `u32 count`; per note `u64 id, u32 tick, u32 duration, u8 pitch, u8 track, u8 velocity, u8 flags` (bit0 ghost, bit1 selected, bit2 timeCovered) | `GridScene+Notes.swift:96-140` |
| 6 | keyboardNames | `u16 count`; per entry `u8 pitch, u16 len, utf8` (drum mode only; empty otherwise) | `GridSceneInput.keyboardNames`, consumed at `GridScene+Rebuild.swift:343-377` |
| 7 | timeAxis | `u8 feel, u32 clockTicks, u8 selectionMode, u32 musicalDenominator, u64 loopStartTick, u64 loopEndTick`; `u16 segmentCount` (per segment `u64 start, u64 next, u32 beatTicks, u32 beatsPerBar, u32 numerator, u8 denomPow2, u8 flags` bit0 implicit signature; segments tile `[0, kNoTick)`); `u32 ticksPerBeat` | segments from `TimeAxis.swift:41-121`; bar/beat lines are generated per frame in C++ from the segments over the visible tick range (never enumerated over the song: a note at `kMaxTick` would make a song-wide walk unbounded); `RollGrid` state from `GridGeometry.swift:59-75` |
| 8 | overlay | time selection: `u8 active, u64 startTick, u64 endTick, u32 selectedTrack, u32 usedTrackCount, u8 scopeTracks[32]` | `GridScene+Notes.swift:197-212` |
| 9 | drawPreview | `u8 active, u32 tick, u32 duration, u8 pitch, u8 lastVelocity` | `GridSceneInput.drawPreview`; `GridScene+Notes.swift:164-183` |
| 10 | modes | `u8 flags` (bit0 velocityColorMode, bit1 noteNameMode, bit2 showVelocityValues, bit3 typographyAvailable, bit4 drum keyboard — set iff drum pad names exist), `u8 selectedTrack` | `GridSceneInput` `:36-39`, `PianoGrid.swift:141-142` |
| 11 | drawerStatics | (phase 4) `u32 count`; per rect `u32 tickStart, u32 tickEnd, f32 y, f32 h, u32 argb, u8 flags` (bit0 pxSpace — ticks are pre-projected content px, bit1 viewportSticky, bit2 dashedFrame — draw a device-px dashed outline instead of a filled rect). Drawer publications send §1 with the roll's 15-f64 layout (slots 0 baseFontPx, 6 detailMinPxPerBeat, 7 autoGridMinCell, 8 gridLineStrokeBase, 9 spaceHalf, 10 spaceTwo, 11 dashLen; other metric slots zero), §3 with grid colors in roll palette slots 3–7 and 25 (other slots zero), and §7 timeAxis for frame-generated grid lines; §11 holds only PSG bands and transient fill/frame records, never enumerated grid lines. | drawer publications (Decision 7) |
| 12 | drawerAnchored | (phase 4 automation) `u32 count`; per rect `u32 tick, f32 dx, f32 width, f32 y, f32 h, u32 argb, u8 flags` (bit0 snapDevicePx). The renderer draws x = project(tick) + dx; width is logical px, independent of camera zoom. Fixed-width curve/selection edges and preview nodes use this section; velocity emits no §12 and retains its original bytes. | automation drawer publication |
| 13 | layerBreak | Empty payload. Drawer band 3 paints sections before the first break at `drawerLayer = 0`, and sections between successive breaks at increasing layers; the time grid paints only in layer 0. Automation layer 0 holds value-axis rules below QML value labels, layer 1 holds curves/selection below interactive nodes, and layer 2 holds preview above nodes/range; velocity transient geometry paints above handles in layer 1. | drawer publication |
| 14 | dashPattern | (phase 4 velocity) `f64 dashDevicePx, f64 gapDevicePx`; velocity writes `(4, 2)` physical pixels for its dashed transient frame. The renderer divides both by devicePixelRatio; a dashedFrame record requires this section. Automation and voice omit §14 because they emit no dashed frames. | velocity drawer publication |
Drawer sections paint in blob order and records in record order; §11 and §12 may repeat to interleave curve runs, curve edges, selection fill/edges, and preview.

Per-record colors are `u32 ARGB` packed with `PaletteMath` in Swift at pack time (ghost fill, velocity
hue, track fill — `GridScene+Notes.swift:117-130`), so C++ ports no palette math. Record order inside §5
preserves today's z-order: ghost pass first, then real notes (`GridScene+Notes.swift:96-98`).

### Projection formulas (C++ twin in `src/render/roll_projection.h`)

Swift `.rounded()` is round-half-away-from-zero → C++ `std::round`; `floor(x+0.5)` (half-up) is ported
literally.

| quantity | formula | Swift source |
|---|---|---|
| `pixel` | `1/dpr` | `GridGeometry.swift:395` |
| `scrollOriginX/Y` | `std::round(scroll*dpr)/dpr` | container translation `EditorRollBand.qml:64-70,97-105`; viewport bake `GridScene+Notes.swift:66-69` |
| `contentTickX(t)` | `std::round(t*ppt*dpr)/dpr` | `EditorCamera.swift:238-240` |
| `viewX(t)` | `contentTickX(t) − scrollOriginX` | `displayX` `EditorCamera.swift:233-236` |
| `contentRowTop(r)` | `std::round(r*keyHeight*dpr)/dpr` | `EditorCamera.swift:93-97` (`snappedEdge` with scrollY 0) |
| `rowBottom(r)` | `std::round((r+1)*keyHeight*dpr)/dpr` | `EditorCamera.swift:59-62` |
| `viewY(r)` | `contentRowTop(r) − scrollOriginY` | `rowTop` with scrollY, `EditorCamera.swift:54-57` |
| note fill box | `x = contentTickX(tick); y = rowTop + pixel; w = max(noteMinWidth, x1−x0); h = max(noteMinHeight*pixel, rowBottom−rowTop−pixel) − pixel` | `GridGeometry.swift:424-439` (`noteContentRect`/`noteContentBox`) |
| border/ring px | `noteBorderPixels = max(1, round(dpr))`; `selectionRingPixels = max(1, round(selectionRingDip*dpr))`; `fittedFrameThickness` port | `GridGeometry.swift:441-452` |
| frame decomposition | 4 rects — top/bottom `t` high, sides `max(0, fh−2t)` — only when `fw>0 && fh>0` | `GridScene+Primitives.swift:59-100` (`addFrame`) |
| border alpha fallback | fitted==0 → black, `alpha = clamp(min(w,h)/(3*pixel), 0.25…0.85)` | `GridScene+Primitives.swift:140-155` (`addNoteBorder`) |
| selection ring | ring thickness `selectionRingPixels`, inset `selectionRingDip` px, via `fittedFrameThickness` | `GridScene+Primitives.swift:157+` (`addSelectionRing`) |
| grid line | `x = contentTickX(t) − gridLineStroke/2`, `w = gridLineStroke`, full height; bar / beat / beatFine / sub1 / sub2 / sub3 colors | `GridScene+Rebuild.swift:128-149` |
| adaptive sub-grid | port `adaptiveTicks` (ladders `[32,16,8,4,2,1]` / `[48,24,12,6,3,1]`, `width/step >= autoGridMinCell`; the gcd snap path is not needed for drawing), `gridTicksAt(snap:false)`, `drawsSubGridIn`, `forEachSubdivision` level rules (`beat/(3 or 2)` → 1, `beat/(6 or 4)` → 2, else 3) | `GridGeometry.swift:60-61,174-195,211-219,309-340` |
| culling | per frame against the item rect; row bands and grid backgrounds span the full item width (replaces `ContentWindow` extents); pre-roll mask `x = extentLeft, w = −extentLeft` with `extentLeft = floor(minHScroll/1024)*1024`, `minHScroll = −clamp(round(viewportWidth*0.10),48,256)` | `GridScene.swift:136-171` (chunk 1024); `EditorCamera.swift:222-225` |
| loop glow | `glowWidth = min(2*baseFontPx, x1−x0)`, `bandWidth = max(1, spaceHalf)`, piecewise alpha (150→18 over first 0.2, then 18→0), clipped to viewport | `GridScene+Notes.swift:230-289` |
| selection band overlay | viewport band rect clipped to item rect: `selectionFill` fill + dashed frame (`dash = gap = dashLen`) | `GridScene+Notes.swift:184-196`; `GridScene+Primitives.swift:102-138` |
| label fit gates | `faceFits`; `nameFits` (`width >= spaceHalf + advance + spaceTwo`); `minKeyHeight = 12.0`; value-mode allowance = `valueAllowance` | `NoteNameLabels.swift:19-53` |
| ruler geometry | `markerHeight = boldHeight+1`; `tickBottom = rulerH−1`; `tickCenter = (markerHeight+tickBottom)/2`; `indicatorRise = barCap = spaceHalf`; `labelGap = 1.0`; `reserve = spaceTwo`; bar tick + horizontal cap; collision skip `labelX < lastLabelRight+labelGap`; `drawBeatTicks = beatWidth >= detailMinPxPerBeat`; `showBeatLabels = beatWidth >= 3.0*(barCap+2*labelGap+reserve+beatAdvance)`; loop markers 1px `h = markerHeight−1` + glyph label; signature drop rule `sigX+2*spaceHalf+w > contentTickX(next)` | `GridScene+Rebuild.swift:203-361` |
| keyboard geometry | white bg `keyboardWidth × totalHeight`; black-key rect per row; C/E/F separators `y = rowBottom − pixel/2, h = pixel` | `GridScene+Rebuild.swift:151-170` |
| sweep rings | per note: `selected || timeCovered || bandOverlap(box, viewportBand)` → ring, else border; ghosts ring only when timeCovered | `GridScene+Notes.swift:72-94` (`emitNoteSelection`) |

Rect rasterization replicates the vendored item exactly: `QSGGeometry(defaultAttributes_ColoredPoint2D)`
triangles, 6 vertices/rect, vertex RGB premultiplied `(c*a+127)/255`, `QSGVertexColorMaterial`,
reallocated only when the count changes (vendored `quickdisplaylistitem.cpp` `updatePaintNode`).

### Label text pipeline (Decision 4)

- Fonts: the item builds `QFont` per font-table entry exactly as `font_metrics.cpp:18-26` does
  (`setPixelSize`, `setWeight`, `setLetterSpacing(QFont::AbsoluteSpacing, …)`,
  `setHintingPreference(QFont::PreferNoHinting)`, `setFeature(QFont::Tag("tnum"), 1)`). Measurement goes
  through the same C API (`sgf_create/sgf_extents/sgf_advance/sgf_fit`, `font_metrics.h`) — the engine
  `GridTypography` already uses (`GridTypography.swift:113-141`), so advances, ascents and fitted sizes are
  identical by construction. `porydaw_app` already compiles `font_metrics.cpp` (`CMakeLists.txt:202-203`).
- Rasterization: `QSGTextNode` from `window()->createTextNode()` (public API, `qquickwindow.h:162`),
  `setRenderType(QSGTextNode::NativeRendering)` to match today's `Text { renderType: NativeRendering }`.
  One `QTextLayout` per distinct (text, font) is laid out once and cached; per frame only node positions
  change. Per-label clip (`contentWidth > width`) is decided per frame from `sgf_advance`, matching the
  QML `clip:` bindings (`PianoRollCanvas.qml:63,201,236`). No elision exists today (`ElideNone`
  everywhere) and none is added.
- Per-frame fitted faces: `.keyLabel` pixelSize = `sgf_fit(keyLabelBase, keyHeight)`;
  `.noteValue` = `max(1, sgf_fit(noteValueBase, floor(keyHeight−pixel)) − 1)`; `noteValueVisible` gate —
  all re-derived per frame from camera `keyHeight` (`GridTypography.swift:70-82`).
- Visibility (keyHeight gates, width fits, ruler collision, keyboard label widths) is decided per frame
  in C++ — these are camera-dependent today and must stop republishing.
- Loading text: `pianoLoadingTextModel` is only ever cleared to `[]` (`GridScene+Notes.swift:314`) — it
  renders nothing; it is dropped in phase 5 with no blob section.

## The nine decisions

### 1. Item API and content handoff

Decided in the Contract: `contentSource` + `contentRevision` plain property bindings and a C++-side
`invokeMethod("drawingContent")` returning one `QVariant(QByteArray)` per content revision; versioned
per-kind layout above. Rejected alternatives:
- `packedRows` role (the proven single-crossing route, vendored `quickdisplaylistitem.cpp:110-112`) —
  keeps the per-rect `QListModel` machinery that phase 5 deletes;
- a QML binding `content: { scene.contentRevision; … }` — works (content changes are allowed to touch
  bindings; only camera steps are not), but it is JS and the C++ fetch needs zero expressions;
- a `Data` property — unsupported by QtBridge property registration today.

### 2. Primitive kinds and projections

| today's layer | becomes | projection citation |
|---|---|---|
| `pianoGridRows` | §4 rows + §3 palette | `GridScene+Rebuild.swift:104-125` |
| `pianoGridTime` | §7 segments + ported bar/beat walk and sub-grid | `GridScene+Rebuild.swift:127-149`; `GridGeometry.swift:309-340` |
| `pianoNoteFills` (+ ghost, velocity mode) | §5 notes | `GridScene+Notes.swift:96-140` |
| `pianoDrawPreviewFill` | §9 | `GridScene+Notes.swift:164-183` |
| `pianoNoteBordersAndSelection` | per-frame from §5 flags + band props | `GridScene+Notes.swift:63-94`; `GridScene+Primitives.swift:59-175` |
| `pianoOverlay` (time-selection, loop glow/edges) | §7/§8 + per-frame glow | `GridScene+Notes.swift:197-289` |
| `pianoKeyboardKeys` | §4 | `GridScene+Rebuild.swift:151-170` |
| `pianoKeyboardHighlights` | per-frame from `hoverPitch` property | `GridScene.swift:212-247` (`rebuildHover`) |
| `cameraScroll` carrier | deleted once unconsumed | `GridScene.swift:111-113` |
| `pianoNoteTextModel` | per-frame labels from §5 + §10 | `NoteNameLabels.swift:55-94`; `GridScene+Notes.swift:291-313` |
| `pianoKeyboardTextModel` | per-frame labels from §4/§6 | `GridScene+Rebuild.swift:337-411` |
| `pianoLoadingTextModel` | dropped (always empty) | `GridScene+Notes.swift:314` |
| `rulerMarks` / `rulerTextModel` / `rulerChrome` / `rulerGutterChrome` | per-frame from §7 (phase 3) | `GridScene+Rebuild.swift:186-364` |
| hover chip properties | unchanged QML, Swift-computed | `GridScene.swift:249-311` |

### 3. Single source of truth for projection

Swift `GridGeometry` / `EditorCamera` / `ScaleProjection` remain the only *semantic* implementations:
hit-testing (`hitZone`/`hitNote` via `metrics.noteRect` + `displayX`, `PianoGrid+SceneSync.swift:219-260`)
and snapping stay entirely Swift. The C++ twin (`roll_projection.h`) is an exact port used only for
painting. Parity is proven three ways:
1. pixel-identical raster checks (category (a) below) — the primary gate;
2. behavioral: every shell journey that clicks a computed point and expects a hit pins
   Swift-hit-test ↔ painted-output agreement;
3. `swiftcore/PianoRoll::selectedNoteFrameRaster` keeps asserting the published box equals the camera
   projection (`note_rendering_economy.swift:107-118` precedent), re-expressed against the new economy
   seam: camera-only scroll/zoom/key-height must leave `contentRevision` and the blob bytes untouched;
   the workspace camera path (`refreshCameraPresentation`) skips content key work entirely.

`PianoGrid.projectedNoteBox` (`PianoGrid+Support.swift:92-99`) remains the canonical Swift box query for
swiftcore checks; it is a three-line composition of the same production functions hit-testing uses
(`displayX` + `noteBox`) — no second Swift formula exists. See Open risks §2 for its check-only tension.

### 4. Label text

Contract "Label text pipeline": Swift ships specs + strings; C++ measures via `sgf_*` (identical engine)
and rasterizes via `QSGTextNode` (NativeRendering); visibility per frame in C++.

### 5. What stays QML; how the scroll containers change

Stays QML: hover chip (`PianoRollCanvas.qml:172-186,238-262` — Swift keeps computing `hoverChipRect`
per camera change via `refreshHoverChip`; O(1) tracked-property math, not scene traffic); shared playhead
+ guides (`nativegraphics`, untouched); reticle and input overlays; menus, prompts, tooltips;
`MouseArea`/`WheelHandler` input (`EditorRollBand.qml:139-296`); `TimelineScrollbar`s; ruler controls
(`EditorRulerBand.qml:135+`); track headers; event list. Container change: `plotContent`,
`gutterContent`, `rulerContent` keep existing (checks locate them) but their translation bindings are
deleted — the renderer owns scroll. `EditorSurface.root.scrollX/scrollY` and the `cameraScroll` carrier
remain for residual consumers (velocity page until phase 4); the carrier is deleted in phase 5 once
`grep cameraScroll src/ui` is empty. Camera → QML flows only through tracked scalars
(`cameraScrollX/Y` for the scrollbar `value:` bindings, `EditorSurface.qml:224,253`).

### 6. Check strategy (per category; every coupled file)

- **(a) Raster — unchanged, the pixel-identical gate.** All grabImage suites:
  `rollqml`: `tst_SwiftRoll.qml`, `tst_SwiftRollPlayhead.qml`, `tst_SwiftRollPlots.qml:742-856`,
  `tst_SwiftRollSelection.qml:262`, `tst_SwiftRollTrackHeader{Input,Meter}.qml`, `tst_SwiftRollTrackHeaders.qml`,
  `tst_SwiftRollWindowing.qml`, `tst_TimelinePan.qml:235`, `tst_TimelinePanPublication.qml:27-49`.
  `editorqml`: `tst_ShellNoteVisuals{,Detail,Ruler}.qml`, `tst_ShellReticleVisuals.qml`,
  `tst_ShellChromeVisuals.qml`, `tst_EditorDrawerAutomation{Curves,Hover,Presentation,Preview,Tabs,Transactions}.qml`,
  `tst_EditorDrawerVelocityRaster.qml`, `tst_EditorDrawerHeaders.qml`, `tst_ShellDrawerParity*.qml`,
  `tst_ShellGridInput.qml:294-366`, plus JS helpers `EditorDrawerPixelSupport.js`,
  `ShellDrawerParityRasterSupport.js`, `ShellTabsRenderingSupport.js`, `EditorDrawerPageSupport.js`,
  `ShellDrawerParityVelocitySupport.js`.
- **(b) Existing production queries — unchanged.** `fetchNoteSummary` (47 files / 291 sites, all lanes);
  `renderedNoteCount` (23 files — PianoGrid keeps computing it during blob build, so it stays a real
  camera-windowed count, never a tautology); camera scalars (`beatWidth`, `rowHeight`, `cameraScrollX/Y`,
  `ticksPerBeat`, `snapTicks`, `drawThreshold`, `rulerMarkerRowHeight`, `visiblePitch` math);
  `grid.palette`; `projectedNoteBox` (5 swiftcore files).
- **Mirror decision — the `exposeRows` mirror is check-only production and is removed.** Production
  hit-testing is pure Swift (`PianoGrid+SceneSync.swift:241-260`); pointer input flows `MouseArea` →
  Swift slots; nothing in production or accessibility reads the mirrored sibling `QQuickItem`s. A
  production read that exists only for checks is banned, so the mirror cannot survive the cutover. Its
  consumers move to `TimelineRenderer.noteFace()` (renderer-owned rendered geometry — the item answers
  about what it itself paints, the moral equivalent of `mapToItem` on a delegate) or to raster.
- **(c) Files needing rewrite** (helper idiom → replacement):
  - QML per-note helpers → `noteFace` (objectName `timelineQuickPianoNoteFills` moves to the renderer
    item, so `findChild` keeps resolving):
    `src/checks/rollqml/tst_SwiftRollSelection.qml:159-171` (`noteItem`, `bandForNote`),
    `src/checks/editorqml/ShellNoteVisualsSupport.qml:142-165` (`noteItem`, `deviceRect`),
    `ShellClipboardSupport.qml:113-118` (`noteCenter`), `ShellGridInputSupport.qml:133-141` (`noteBand`),
    `ShellGridMenuSupport.qml:268-300` (`noteTargets`, `noteMenuMiss`),
    `ShellPitchBendSupport.qml:117-282` (`visibleNote`, `openViaG`),
    `ShellWindowSupport.qml:193-229` (`selectMountedNotePair`, `mountedNotePoint`),
    `ShellTabsSupport.qml` (`holdBandOn`), and their ~24 `tst_Shell*.qml` consumers:
    `tst_ShellClipboard.qml`, `tst_ShellClipboardRoundTrip.qml`,
    `tst_ShellEventListKeyboardSelection.qml`, `tst_ShellGridInput.qml`,
    `tst_ShellGridInputCancel.qml`, `tst_ShellGridInputDraw.qml` (per-note fill-color reads at
    `:215,224` → raster color sample at the face rect), `tst_ShellGridInputEditing.qml`,
    `tst_ShellGridInputKeyboard.qml`, `tst_ShellGridMenuInputZones.qml`,
    `tst_ShellPitchBendCancellation.qml`, `tst_ShellPitchBendKeys.qml`,
    `tst_ShellPitchBendPointer.qml`, `tst_ShellTabsReload.qml`, `tst_ShellTransportSession.qml`,
    `tst_ShellWindowEditorKeys.qml`, `tst_ShellWindowTimeEditing.qml`, `tst_Typography.qml`,
    `tst_ShellNoteVisuals.qml`, `tst_ShellNoteVisualsDetail.qml`, `tst_ShellNoteVisualsRuler.qml`,
    `tst_EditorDrawerVelocityHitTargets.qml`.
  - Scene-model reads (`grid.scene.*`) → raster or production scalars:
    `tst_SwiftRollSelection.qml:251,259` (ring count → raster ring quadrant),
    `ShellPitchBendSupport.qml:272-278` (painted range → raster), `tst_ShellGridInputDraw.qml:70`
    (preview presence → staged-face pixels already grabbed at `:73`),
    `tst_ShellTabsReload.qml:545-562` (band ring raster); `tst_TimelinePan.qml:78` and
    `tst_TimelinePanPublication.qml:102` are existence-only and stay.
  - Layer hosts: renderer items KEEP the objectNames (`timelineQuickPianoGridRows`, `…GridTime`,
    `…NoteFills`, `…DrawPreviewFill`, `…NoteBordersAndSelection`, `…Overlay`, `…KeyboardKeys`,
    `…KeyboardHighlights`, `timelineQuickRulerMarks/GutterChrome/Chrome`), so mounts-checks
    (`tst_ShellChromeVisuals.qml:118-123`, `tst_ShellReticleVisuals.qml:106-107`,
    `tst_SwiftRollPlots.qml:201-208`) pass unchanged.
  - Per-label child enumeration → raster ink (precedent `ShellNoteVisualsSupport.qml:440-470`
    `exactRulerColumns`) or production scalars: `TimelinePanSupport.qml:166-171` (`keyboardLabels`),
    `tst_TimelinePanPublication.qml:121-125`, `ShellDrawerParityVelocitySupport.js:176-193`,
    `ShellGridMenuSupport.qml:245-252` (`rulerLabelAt`).
  - swiftcore scene-representation readers → `projectedNoteBox` / camera math / raster:
    `rollcheck/EditorGridProjectionChecks.swift:86,140,177,207`, `rollcheck/EditorGridLatticeChecks.swift`
    (`pianoGridTime` → camera math), `rollcheck/interlock.swift:70,218-226`,
    `rollcheck/note_rendering_borders.swift:47-134`, `rollcheck/note_rendering_names.swift:41-169`,
    `rollcheck/note_rendering_velocity.swift:96-379`, `rollcheck/note_rendering_ghosts.swift:58`,
    `rollcheck/keyboard_drum_labels.swift:38` (row tops + names derivable from production projection +
    `keyName`), `rollcheck/keyboard_time_selection.swift:63`, `rollcheck/ruler_loop_menu_loop.swift:196`,
    `rollcheck/pencil.swift:325-480`, `rollcheck/resize.swift:70-79` (+ consumers
    `selection_editing.swift`, `selection_band.swift`), `rollcheck/selection.swift:21-35`,
    `rollcheck/note_commands.swift:620`, `rollcheck/note_commands_routing.swift:83`,
    `rollcheck/note_rendering_economy.swift:30` (rewritten to the revision seam),
    `velocity/VelocityRollCoreChecks.swift:16`.
- `deno task verify:bridge` stays green throughout (`TimelineQuickItem.qml`'s `QtBridge 1.0` import
  disappears only when the file dies in phase 5).

### 7. Drawer pages

They adopt the same item, `band = 3`, time-axis camera only (`pixelsPerTick`, `scrollX`,
`devicePixelRatio`; `keyHeight` unused). Moves native (phase 4): velocity grid lines
(`VelocityPage.qml:320-330`) generate per frame from §7 timeAxis over visible ticks, while its
`psgBands`/`transientRects` become §11 tick-space records. The other pages' static layers —
voice `gridLines`/`heldSpans` (`VoiceChangesPage.qml:280-290`), automation `gridLines`/
`valueLines`/`curveRuns`/`selectionRects`/`previewRects`
(`AutomationPlot.qml:46-56,84-94,228-232`) — move as §11 model-space records
(tick-space x; `pxSpace` for camera-free value-axis lines). Swift stops baking scroll into native
content: velocity retains legacy QListModel camera projections until its separate QML cutover.
The other `refreshHorizontalProjection` seams (`VoiceChangesPublication.swift:101-110`,
`AutomationContentPublication.swift:139-163`) become camera-property publications; full rebuilds
remain only where content genuinely depends on zoom
(automation curve segment quantization). Stays QML: every interactive handle (velocity handles
`VelocityPage.qml:336-415`, automation nodes `AutomationPlot.qml:152+`, voice markers, other-events
diamonds, tabs, menus, readouts) and all drawer text (`valueLabels`, `ghostNameLabels`, gutter texts,
axis labels — the axis is camera-free). Automation node x and other-events marker x become scroll-stable
content px inside a translated container (the velocity-handle pattern, `VelocityPage.qml:289-341`),
killing their per-scroll republish; containers translate from `gridModel.cameraScrollX` directly.
Velocity handles already publish scroll-stable x — only their carrier consumption changes. The
PitchBend popup is untouched (note-local geometry, no camera; `PitchBendScene.swift:53-68`).

### 8. Phase plan (parallel units, disjoint write sets)

`†` marks a true serial dependency. Units without `†` between them have disjoint write sets.

**Phase 0 — shared contract (serial, tiny).** Add `@QtTracked public var pixelsPerTick` to `PianoGrid`
(publish in `publishGeometry` beside `beatWidth`, `PianoGrid+SceneSync.swift:143-147`) and
`contentRevision` + `drawingContent() -> Data` stub on `GridScene`. Files: `src/swift/app/roll/PianoGrid.swift`,
`src/swift/app/roll/PianoGrid+SceneSync.swift`, `src/swift/app/roll/GridScene.swift`. This is the data-layout
contract every phase-2 unit consumes.

**Phase 2 — Roll plot + keyboard.**
- **U2a — C++ renderer item** (parallel with U2b). Writes: `src/render/timeline_renderer.h`,
  `src/render/timeline_renderer.cpp`, `src/render/roll_content.h`, `src/render/roll_projection.h`,
  `CMakeLists.txt` (add the four files to `qt_add_library(porydaw_app …)` beside `item_cursor`,
  `CMakeLists.txt:200-201`). Bands 0 (plot) + 1 (keyboard) implemented: rect pass, text pass
  (`QSGTextNode`), culling, snapping, minimums, borders/rings, sub-grid port, labels, glow, overlay.
  Edge cases: empty/short blob → paint nothing; non-finite camera values → `qFatal` (parity with the
  vendored item); dpr change mid-run (camera property, re-snaps); software scene graph (checks run real
  engines; must render under `GraphicsInfo.Software`); no per-frame allocations beyond reused vertex
  buffers and the cached `QTextLayout`s; `update()` scheduled from every property change; ItemHasContents.
  Acceptance: throwaway QML smoke (not committed) painting a synthetic blob; `deno task build:checks`
  compiles; `deno task verify:bridge` clean.
- **U2b — Swift roll content** (parallel with U2a; owns roll Swift). Writes:
  `src/swift/app/roll/RollDrawingContent.swift` (new packer, sections 1-10),
  `src/swift/app/roll/GridScene.swift` (slot body; revision bumps wherever content inputs change),
  `src/swift/app/roll/GridScene+Rebuild.swift` (rows/keys/grid-time/keyboard-names become model-space
  records; `rebuildRuler` stays camera-baked until phase 3; `StaticKey` shrinks accordingly),
  `src/swift/app/roll/GridScene+Notes.swift` (fills/borders/overlay/preview/labels become model-space
  records; `boxesProjected`/`fillWrites` count blob work), `src/swift/app/roll/GridScene+Primitives.swift`
  (frame/ring/dash decompositions move to C++; `timeCovers` stays and feeds §5 bit2),
  `src/swift/app/roll/PianoGrid+SceneSync.swift` (`refreshNotes` split: content rebuild only on
  document/selection/palette/hover/fold/typography/draw-preview/mode changes; `refreshCamera` publishes
  camera scalars + hover chip + `renderedNoteCount`, bumps nothing content-side),
  `src/swift/app/roll/PianoGrid.swift`. Edge cases: fold toggle re-rows everything; ghost/real z-order;
  drum-mode names and backgrounds; no-typography mode (metrics only, zero labels); `contentEndTick`
  recompute (`PianoGrid+SceneSync.swift:97-110`); selection band/preview staying live during gestures.
  Acceptance: `deno task verify --filter swiftcore --verbose` (with U2d), plus new revision-stability
  assertions in `note_rendering_economy.swift`.
- **U2c — roll QML cutover** (`†` after U2a+U2b). Writes: `src/ui/songview/quick/PianoRollCanvas.qml`
  (the 8 batched items + 2 text Repeaters → two renderer items carrying the preserved objectNames; z
  order becomes draw order per `PianoRollCanvas.qml:13-117`; hover chip untouched),
  `src/ui/songview/quick/swiftroll/EditorRollBand.qml` (pin `plotContent`/`gutterContent` translations to
  zero — delete the bindings), `src/ui/songview/quick/swiftroll/EditorSurface.qml` (carrier stays; audit
  residual `root.scrollX/scrollY` readers). Acceptance: `deno task verify:qml-roll --verbose` and
  `deno task verify:shell --verbose` green (with U2d), raster suites pixel-identical.
- **U2d — roll checks migration** (`†` after U2c). Writes: every file in Decision 6 (c) roll share:
  `src/checks/rollqml/{tst_SwiftRollPlots,tst_SwiftRollSelection,tst_TimelinePan,tst_TimelinePanPublication}.qml`,
  `src/checks/rollqml/TimelinePanSupport.qml`,
  `src/checks/editorqml/{ShellNoteVisualsSupport,ShellClipboardSupport,ShellGridInputSupport,ShellGridMenuSupport,ShellPitchBendSupport,ShellWindowSupport,ShellTabsSupport}.qml`
  + the ~24 `tst_Shell*.qml` consumers above,
  `src/checks/rollcheck/{EditorGridProjectionChecks,EditorGridLatticeChecks,interlock,note_rendering_borders,note_rendering_names,note_rendering_velocity,note_rendering_ghosts,note_rendering_economy,keyboard_drum_labels,keyboard_time_selection,ruler_loop_menu_loop,pencil,resize,selection,selection_band,selection_editing,note_commands,note_commands_routing}.swift`,
  `src/checks/velocity/VelocityRollCoreChecks.swift`. Keep every check report message byte-identical
  where the assertion class is unchanged (ledger anchors). Acceptance: `deno task verify --filter
  swiftcore --verbose`, `deno task verify:qml-roll --verbose`, `deno task verify:shell --verbose`,
  `deno task proof check --executed`.

**Phase 3 — Ruler** (`†` after phase 2; blob already carries §7).
- **U3a — ruler content**: `src/swift/app/roll/GridScene+Rebuild.swift` (retire camera-baked
  `rebuildRuler`; ruler band draws from the same blob), `src/swift/app/roll/GridScene.swift` (drop
  `rulerMarks`/`rulerTextModel`/chrome models when unconsumed), `src/swift/app/roll/PianoGrid+SceneSync.swift`
  (`StaticKey`/`invalidateStatic` collapse to typography-only).
- **U3b — ruler QML + checks** (`†` after U3a): `src/ui/songview/quick/swiftroll/EditorRulerBand.qml`
  (marks item + text Repeater → renderer item `band: 2` keeping `timelineQuickRulerMarks`;
  `rulerContent` translation pinned; chrome/gutter-chrome items → renderer),
  `src/checks/editorqml/ShellGridMenuSupport.qml`, `src/checks/editorqml/ShellNoteVisualsSupport.qml`,
  `src/checks/editorqml/tst_ShellNoteVisualsRuler.qml`, `tst_ShellChromeVisuals.qml`,
  `tst_ShellGridMenuRulerMarkers.qml`. Acceptance: `deno task verify:shell --verbose`,
  `deno task verify:qml-roll --verbose`, `deno task proof check --executed`.

**Phase 4 — Drawers** (U4a `†` after phase 2; the four page units are parallel with disjoint writes).
- **U4a — renderer drawer support**: `src/render/timeline_renderer.{h,cpp}`, `src/render/roll_content.h`
  (band 3 semantics + §11 records). No CMake change.
- **U4v — velocity**: `src/swift/app/drawer/velocity/{VelocityPage,VelocityPublication,VelocitySceneValues,VelocityProjection}.swift`,
  `src/ui/songview/quick/drawer/VelocityPage.qml` (axis column stays QML; three static layers →
  renderer; `handleContent` translation from `gridModel.cameraScrollX`). Checks:
  `tst_EditorDrawerVelocity*.qml`, `ShellDrawerParityVelocitySupport.js`, `velocity/*.swift` page checks.
- **U4c — voice changes**: `src/swift/app/drawer/voicechanges/{VoiceChangesPage,VoiceChangesPublication,VoiceChangesProjection,VoiceChangesScene}.swift`,
  `src/ui/songview/quick/drawer/VoiceChangesPage.qml` (grid/spans native; markers stabilized +
  translated container). Checks: `tst_ShellDrawerParity*` voice suites.
- **U4m — automation**: `src/swift/app/drawer/automation/{AutomationPage,AutomationLifecycle,AutomationContentPublication,AutomationOverlayPublication,AutomationProjection}.swift`,
  `src/ui/songview/quick/drawer/AutomationPlot.qml` (five rect layers native; nodes stabilized +
  translated container; labels stay QML). Checks: `tst_EditorDrawerAutomation*.qml`.
- **U4o — other events (stabilization only, no native)**: `src/swift/app/drawer/otherEvents/{OtherEventsBandPresenter,OtherEventsStrip}.swift`,
  `src/ui/songview/quick/drawer/OtherEventsBand.qml` (marker x → content px, container translated; drop
  per-scroll refresh, `DocumentWorkspace.swift:376` fan-out narrows).
- Acceptance per unit: `deno task verify:qml --verbose`, `deno task verify:shell --verbose`,
  `deno task verify --filter swiftcore --verbose`, `deno task proof check --executed`.

**Phase 5 — Cleanup** (single unit, `†` after all).
- QtBridge patch split (`cmake/patches/qtbridge/qtbridge-object-return.patch`), REMOVE:
  `quickdisplaylistitem.{h,cpp}` new-file hunks; `Sources/QtBridgeCpp/CMakeLists.txt` entries;
  `QtBridgeCpp.h` include; `qappcpp.{h,cpp}` registration + `engine()` accessor (after re-grep proves no
  consumer); `qtestappcpp.cpp` ctor; `QAbstractListModel.swift` + `QListModel.swift` `enablePackedRows`/
  `packedRows` role hunks. KEEP: `QVariant(value: Data)` + `variantFromBytes` (the blob slot needs
  them); `isSupportedReturnType` loosening; `beginMoveRows`/`endMoveRows` + `QListModel.move`
  (`SongTabsController.swift:386`); `QListModel.update` (drawer handle sync, `QListModelSync.swift:9`);
  `QObjectProxyImpl`/`QObjectProxy` CppOwnership pinning; `registerQmlElement` visibility; the CMake EP
  passthrough. Rebuild the vendored QtBridge; `deno task verify:bridge`.
- Delete: `src/ui/songview/quick/swiftroll/TimelineQuickItem.qml` + its `CMakeLists.txt:263` QML_FILES
  entry; `SceneRectPacking.swift`; `SceneRect` and the per-rect roll models (`SceneText` stays only if a
  drawer text model still uses it — verify, else it goes too); `cameraScroll` carrier (once
  `grep cameraScroll src/ui` is empty); `src/checks/quickdisplay/` + `checkcatalog.cpp:103-107` entry;
  `pianoLoadingTextModel`; `boxesProjected`/`fillWrites` if the rewritten economy check no longer needs
  them.
- Docs: mark this plan executed; release-notes entry.

### 9. Proof-ledger impact

Ledgers key rows to check *messages* (`Anchor: message "…"`), and closed rows cite the original C++
revision, so representation moves generally do not touch them — verified examples:
`src/checks/swiftrollgated/proof.clipboardchecks.txt:204,364,474` and
`src/checks/nativegraphics/proof.tst_nativewindowing.txt` quote the retired C++ source, never Swift scene
rows. Rules for this work: (i) keep every check message byte-identical when only its helper changes
(U2d default); (ii) when an assertion class genuinely changes (the economy check, scene-model reads),
repair that anchor in the same commit via `deno task proof:edit` — the workflow rule's "a code change
broke an anchor" clause; (iii) surfaces touched: `src/checks/rollcheck/proof.identity.txt`,
`proof.presentation.txt`, `proof.resize.txt`, `src/checks/visual/proof.chrome.txt`, and
`workspace/proof.*` only if camera-economy messages change. The removed `quickdisplay-decode` catalog
entry has no ledger row (confirm with `deno task proof sites`). Each phase closes with
`deno task proof check --executed`; no standalone reconciliation passes.

## Verification

Per phase, cumulative:
- `deno task build:checks` — compile (C++ + Swift + QML).
- `deno task verify --filter swiftcore --verbose` — roll semantics, rewritten scene-representation
  checks, new revision-stability checks (`contentRevision` + counters unchanged across in-window
  `scrollByPx` / `setTimeZoom` / `setKeyHeight`).
- `deno task verify:qml-roll --verbose` — roll QML + raster parity.
- `deno task verify:shell --verbose` — shell journeys (clicks via `noteFace`, raster, summaries).
- `deno task verify:qml --verbose` — drawer pages (phase 4).
- `deno task verify:bridge` — QtBridge surface guard.
- `deno task proof check --executed` — ledger health.
- `deno task format` — formatting.
- Implementation-time manual smoke (not committed): launch the app, zoom/scroll/pinch the roll; assert
  `contentRevision` static during camera moves and no visual difference vs. pre-cutover screenshots at
  dpr 1 and 2.

## Critical files (implementer reading list)

Swift: `src/swift/app/roll/GridScene.swift`, `GridScene+Rebuild.swift`, `GridScene+Notes.swift`,
`GridScene+Primitives.swift`, `SceneRectPacking.swift`, `NoteNameLabels.swift`,
`src/swift/app/roll/PianoGrid.swift`, `PianoGrid+SceneSync.swift`, `PianoGrid+Support.swift`,
`src/swift/app/timeline/EditorCamera.swift`, `GridGeometry.swift`, `ScaleProjection.swift`,
`GridTypography.swift`, `TimeAxis.swift`, `src/swift/app/DocumentWorkspace.swift:359-381`. QML:
`src/ui/songview/quick/PianoRollCanvas.qml`,
`src/ui/songview/quick/swiftroll/{EditorRollBand,EditorRulerBand,EditorSurface,TimelineQuickItem}.qml`,
`src/ui/songview/quick/drawer/{VelocityPage,VoiceChangesPage,AutomationPlot,OtherEventsBand}.qml`.
Native: `src/app/item_cursor.{h,cpp}` (registration precedent),
`src/ui/songview/quick/swiftroll/native/font_metrics.{h,cpp}`,
vendored `build/_deps/qtbridge-src/Sources/QtBridgeCpp/quickdisplaylistitem.cpp` (vertex math to
replicate), Qt 6.11 headers `qsgtextnode.h` and `qquickwindow.h:162` (`createTextNode`). Build/infra:
root `CMakeLists.txt:194-243,359-395,440-444`, `cmake/patches/qtbridge/qtbridge-object-return.patch`,
`deno.json`, `src/checks/checkcatalog.cpp:103-107`.
Prior-art C++ renderer (the pre-Swift app, main checkout on `fork-main`,
`/Users/sallegrezza/dev/cProjects/porydaw/src/ui/songview/quick/`): `timelinequickscene.{h,cpp}` and
`timelinequicklayer.h` (scene-graph node building), `timerulerquick.cpp` (ruler, phase 3),
`velocityquick.cpp`, `voicechangequick.cpp`, `automationquick.cpp`, `automationnodelanequick.cpp`,
`otherstripquick.cpp` (drawer pages, phase 4), `timelinequickchrome.cpp`, `playheadquick.cpp`. Consult
them for proven node structure, text rendering and per-frame projection before inventing an approach;
the Swift/HEAD formulas remain the pixel spec.

## Open risks

1. **`invokeMethod("drawingContent")` on a QtBridge proxy** — slot registration is patch-enabled but
   unproven when invoked from C++. Fallback (same write set): a `Q_INVOKABLE void reloadContent()` on the
   renderer plus a `Connections { function onContentRevisionChanged() { … } }` — still zero JS in
   property bindings. Resolve in U2a before U2b lands.
2. **`projectedNoteBox` is check-only today** (`PianoGrid+Support.swift:92-99`; callers are 5 check
   files). The plan leans on it because it composes the same production functions hit-testing uses, and
   the cutover adds no new check-only reads; if the rule is read strictly, those 5 files re-derive from
   camera scalars. Flag to the user before U2d.
3. **AGENTS.md C++ boundary** — "no new C++ outside `clipboard_host`, `font_metrics`, `src/project`" vs.
   the user-approved `src/render/`. AGENTS.md may only be edited with human permission; request it with
   phase 2.
4. **Raster identity at label edges** — `QQuickText` (NativeRendering) and a hand-built `QSGTextNode`
   (NativeRendering) should rasterize identically, but positioning/padding could differ by a subpixel;
   label raster suites (`tst_ShellNoteVisuals*`, `exactRulerColumns`) will catch it; budget a fix loop.
5. **Sub-grid port drift** (`adaptiveTicks` / `forEachSubdivision`) — the highest-formula-count port;
   guarded by Swift-side cadence/lattice checks (unchanged) and grid raster columns; a mismatch shows as
   a 1px column offset at specific zooms.
6. **Automation zoom rebuilds remain** — curve runs depend on pixelsPerTick beyond projection (segment
   quantization); phase 4 keeps the full rebuild on zoom (as today) and only scroll becomes camera-only.
7. **Blob size** on pathological songs (≈10⁵ notes ≈ 4 MB per fetch, content changes only): packer must
   reserve capacity; the item decodes into flat vectors with no per-record allocation beyond growth.
8. **`engine()` removal** in phase 5 depends on no new consumer; re-grep `QAppCpp::engine` before
   removing the hunk.
