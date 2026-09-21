# Task 1 — Integrate the session camera into the real grid

## Context

Follow [Global Constraints](plan.md#global-constraints) and [spec.md](spec.md). The
running piano grid must render, hit-test and navigate through ONE
document-session-owned `EditorCamera` instead of its own Flickable content offsets
and `horizontalZoom`/`verticalZoom` fields. This task is independently useful: it
adds no drawer, no velocity/voice/automation page, no menu or shortcut, no new C++
and no new check suite or catalog name.

Consume the landed camera preparation
(`src/swift/app/EditorCamera.swift`, `src/checks/swiftcore/EditorCameraChecks.swift`,
checkpoint `d3e49a3a`, dispatched by `runProjectSessionSuite`,
`SessionChecks.swift:293`). Its value/projection layer, `Snapshot`, `Limits`, bounds,
anchored zoom, `restore`, and `ensureTickVisible`/`ensureRangeVisible`/`ensureKeyVisible`
are the camera: do not re-port, rename, weaken, duplicate or extend them, and do not
present the prep's own cases as this task's integration proof. Those cases keep their
independent headless acceptance. File existence or a checkpoint is not acceptance:
the prep's own review is a predecessor gate, and this task must prove the grid really
uses it. If the reviewed prep is reworked before dispatch, consume the landed API
rather than an older spelling.

Boundary: Swift owns session/camera/presenter behavior; QML renders and delivers raw
input; the native host keeps the window, the `appSession` context property, key
routing, palette transfer and scene lifetime. No new handwritten C++ is authorized:
the only native edits are mechanical assertion maintenance in three retained windowed
check files whose reads of the retired Flickable must be re-pointed at the camera, plus
one QML resource line.

Forward pointer: task 2 composes the drawer inside this task's production
`EditorSurface.qml` below the roll band and pushes the reduced roll height through the
same `configureViewport` path. Nothing here presupposes a page: the grid must work
alone.

## Exact write set

Create:
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — the production root/input
  composition moved out of `SwiftRollOverlay.qml`, behind
  `required property QtObject applicationSession`.
- `src/checks/swiftcore/EditorGridCameraChecks.swift` — the four integration cases
  below, called from `runProjectSessionSuite`.

Modify (Swift app):
- `src/swift/app/DocumentSession.swift`: camera ownership/publication, edit-cursor
  value, private time-domain reconciliation on document change.
- `src/swift/app/ApplicationSession.swift`: the single camera subscription that
  refreshes the grid presenter.
- `src/swift/app/NoteCommands.swift`: mechanical `session.camera.tick` →
  `session.editCursor` migration only (paste semantics unchanged).

Modify (Swift grid / QML):
- `src/ui/songview/quick/swiftroll/PianoGrid.swift`: camera push, wheel policy, camera
  setters/home, camera-derived published values, scene rebuild from the camera.
- `src/ui/songview/quick/swiftroll/GridGeometry.swift`: `GridCameraPolicy`
  (font-relative production limits/defaults) and `GridMetrics` without camera-derived
  fields.
- `src/ui/songview/quick/swiftroll/GridGesture.swift`: gesture updates take the camera
  for tick/pitch mapping.
- `src/ui/songview/quick/swiftroll/GridScene.swift`: scene input carries the camera;
  primitives become viewport-relative; culling uses the camera window.
- `src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml`: thin host adapter.

Modify (checks and build wiring):
- `src/checks/swiftcore/SessionChecks.swift`: the `SessionCamera` assignment at
  `SessionChecks.swift:499`, and the call site for the new check function immediately
  before the `// 8. Close lifecycle.` block.
- `src/checks/swiftrollgated/{chromevisuals.cpp,gesturechecks.cpp,notevisuals.cpp}`:
  mechanical Flickable/viewport reads → camera observations (details in the steps).
- `src/checks/CMakeLists.txt`: add `swiftcore/EditorGridCameraChecks.swift` to the
  existing `swift_core_check` source list. Source-list entry only.
- `CMakeLists.txt`: add `src/ui/songview/quick/swiftroll/EditorSurface.qml` to the
  existing `swift_roll_qml` `FILES` list (`CMakeLists.txt:238-245`). One addition.

Not in the write set: `src/swift/app/EditorCamera.swift` and
`src/checks/swiftcore/EditorCameraChecks.swift` (consumed as landed; no integration
gap requires changing them), the native host sources, the check catalog, the coverage
ledger (no historical row is promoted, reclassified or retired here), and every other
grid Swift/QML file.

## Prerequisites

- Accepted T7 (`97dc7fea`) and the bounded T8 closure; the camera preparation's own
  review/acceptance recorded as a predecessor gate (its presence in the tree does not
  satisfy it). An unresolved predecessor gate blocks dispatch.
- Existing and reused unchanged: `DocumentSession`/`ProjectService`, `TimeAxis` and
  its snap/segment semantics, `GridTypography` measurement and font maps,
  `GridPalette`, `QtBridge` (`@QtBridgeable`, `@QtTracked`), the retained-object bridge
  used by `gridPresenter()`, the four windowed check names
  (`swiftrollgated`, `swiftbandkeys`, `swiftqtml`, `selectionkey`), the `swiftcore`
  suite and its `projectSession` slot.
- The camera prep's public surface as inspected at `d3e49a3a`: `Snapshot`
  (`pixelsPerBeat`, `pixelsPerTick`, `scrollX`, `keyHeight`, `scrollY`, `minHScroll`,
  `maxHScroll`, `maxVScroll`, `viewportWidth`, `rollHeight`), `Limits`, `PitchProjection`,
  `contentX`, `tickAtContentX`, `displayX`, `updateLimits`, `updateViewport`,
  `updateTimeDomain`, `setHScroll`, `setVScroll`, `setTimeZoom`, `setKeyHeight`,
  `scrollByPx`, `scrollRollBy`, `zoomAroundContentX`, `zoomKeyHeight`, `restore`,
  `ensureTickVisible`, `ensureRangeVisible`, `ensureKeyVisible`.

## Interface contract

### Session ownership and publication (`DocumentSession`)

- Delete `public struct SessionCamera` entirely. It conflates edit-cursor values with
  pan/zoom and has no surviving caller.
- `public var editCursor: Tick = 0` — the edit cursor (formerly
  `SessionCamera.tick`). Callers migrate without semantic change: `NoteCommands.paste`
  keeps its speculative pre-paste write and restore, `PianoGrid` reads/writes it in
  `init`, `refreshFromSession`, `setEditCursorTick` and `performCommand`. Writes stay
  bounded by `TimeDefaults.tick(from:)`. `selectedTrack: Int?` continues to own track
  scope and is unchanged; the duplicate `session.camera.track` write in
  `PianoGrid.setTrack` disappears with `SessionCamera`.
- `public private(set) var camera: EditorCamera` — created in `init` with the
  document's `ticksPerBeat`, the timeline's `lengthTicks`, zero viewport, and an
  internal neutral seed
  (`GridCameraPolicy.limits(baseFontPx: GridCameraPolicy.seedBaseFontPx)` plus the
  matching default scale); the first `configureViewport` push installs the pushed
  font's limits and effective scale. After creation it is mutated only through
  `mutateCamera` or the private document-path reconciliation.
- `public var onCameraChange: ((EditorCamera.Snapshot) -> Void)?` — the single camera
  publication. `ApplicationSession` is its only subscriber. A change that alters only
  the projection publishes with the unchanged snapshot; consumers re-read
  `session.camera.projection`.
- `@discardableResult public func mutateCamera(_ body: (inout EditorCamera) -> Void) -> Bool`
  — applies one mutation, compares snapshot and projection before/after, publishes
  exactly once when either changed, and returns whether it published. Camera mutation
  never dirties the document, touches history, rebuilds or publishes playback, or
  changes the edit cursor.
- `handleDocumentChange` reconciles the camera's time-domain extent **privately**,
  after the canonical selection/track updates and the timeline rebuild and before
  `onPlayback`/`onChange`: the session applies
  `updateTimeDomain(ticksPerBeat:lengthTicks:)` to its own camera value and reclamps
  its bounds without calling `mutateCamera` and without emitting `onCameraChange`.
  That path must yield exactly one coherent document refresh — one `onPlayback`, one
  `onChange`, no nested camera callback and no second presenter rebuild — because
  `PianoGrid` still holds the previous notes and time axis while a camera callback
  would run. Presentation-only external mutations (wheel, camera setters, reveal) use
  `mutateCamera`/`onCameraChange` and never publish document state.
- No scoped selection/cursor setter or `SessionChangeScopes` is added: selection,
  track and cursor keep today's direct-value semantics, and this task adds no second
  publication path.

### Camera integration (`PianoGrid`, grid files, QML)

- `PianoGrid.configureViewport(width:height:fontPx:dpr:)` keeps its exact signature
  (the retained suite invokes it to prove font/DPR response) and performs ONE
  `mutateCamera` that: re-resolves `GridCameraPolicy.limits(baseFontPx: fontPx)`; on a
  font change scales the current zoom by the font-relative ratio
  (`defaultPixelsPerBeat(new)/defaultPixelsPerBeat(old)`,
  `defaultKeyHeight(new)/defaultKeyHeight(old)`) before the new limits clamp it; pushes
  `updateViewport(width:rollHeight:)`; and pushes the current
  `updateTimeDomain(ticksPerBeat:lengthTicks:)`. The presenter's own layout metrics
  (chrome, typography, `dpr`, time axis) are updated in the same entry point.
  `GridCameraPolicy` states the production `SongView::Geometry::resolve()` values once,
  font-relative: `defaultPixelsPerBeat = fontPx(b, 8/3)`, minimum `fontPx(b, 1/3)`,
  maximum `fontPx(b, 160/3)`, `defaultKeyHeight = fontPx(b, 1)`, minimum
  `fontPx(b, 1/3)`, maximum `fontPx(b, 8/3)`, reveal `1/3`, minimum plot width
  `fontPx(b, 25/6)`. `GridCameraPolicy.seedBaseFontPx` (the grid's existing `13`
  default) is an internal neutral seed for the camera between session open and the
  first viewport push; it is not a host-font claim, and the font actually pushed
  through `configureViewport` determines the rendered limits and scale from the first
  push onward (that pushed value comes from the existing presentation path — QML's
  `Screen.devicePixelRatio` plus the surface's base font — so no second font source or
  fixture constant is added). The rewrite's `0.5...4.0` zoom multipliers and the raw
  TimeCamera class defaults are not limits.
- Vertical home: `resetCameraScroll()` is the production `resetScrollPosition` port —
  `setHScroll(minHScroll)` plus `setVScroll(defaultVerticalScroll())`, where the home
  is `max(0, centerRow * keyHeight - max(fontPx(baseFontPx, 50/3), rollHeight) / 2)`
  for the projection row of the nearest visible pitch to the note-set mid key (60 when
  empty). The first non-degenerate `configureViewport` (positive roll height) applies it
  once per presenter; later pushes and font changes never re-home a user's scroll. QML
  no longer owns a centering flag or an initial offset.
- Camera setters: `setCameraHScroll(_:)` and `setCameraVScroll(_:)` are the unanchored
  restoration/scrollbar operations (finite-only, clamped by the camera).
- Wheel policy: `public func handleWheel(angleDeltaX: Double, angleDeltaY: Double,
  pixelDeltaX: Double, pixelDeltaY: Double, modifiers: Int, phase: Int,
  overGutter: Bool, anchorX: Double, anchorY: Double)` implements production
  `PianoRoll::wheel` exactly, with all policy in Swift and only raw event facts from
  QML: pick `pixelDelta` when non-zero else `angleDelta`; `d = dy != 0 ? dy : dx`;
  Ctrl → pitch zoom `exp2(weightedDy / 1200)` at `anchorY`; Shift → `scrollByPx(-d)`;
  horizontal-only delta → `scrollByPx(-dx)`; `overGutter` → `scrollRollBy(-dy / 2)`;
  otherwise time zoom `pow(1.0015, weightedDy)` at `anchorX`, where
  `weightedDy = dy * (isPixel ? 5 : 1)`. `phase` is the raw
  `Qt::ScrollPhase` value; `QtScrollPhase.momentum` (a named Swift constant carrying
  the pinned Qt's values — `qnamespace.h:1719-1725` `NoScrollPhase = 0 … ScrollMomentum = 4`,
  registered for QML by `Q_ENUM_NS(ScrollPhase)` at `qnamespace.h:1854` and exposed as
  `Qt.ScrollMomentum`) suppresses both zoom branches and never suppresses pan/scroll.
  A phase value outside the enumerated range is a contract failure to report, never a
  silent behavior change. Anchors are
  viewport-relative: `anchorX` is plot-local x, `anchorY` is gutter/band-local y. Each
  branch is one `mutateCamera`; a no-op or clamped-out zoom publishes nothing.
- Mapping and rendering use the camera, never a second copy: scene x is
  `camera.displayX(tick:origin:0,dpr:)`, row edges are
  `camera.projection.rowTop/rowBottom(row, keyHeight:scrollY:dpr:)`, pointers are
  `camera.tickAtContentX(x)` and `camera.projection.pitch(atY:keyHeight:scrollY:dpr:)`.
  The plot-local `MouseArea` sits on an untranslated clipped surface, so its
  coordinates ARE the camera's viewport coordinates (no translation item, no reciprocal
  binding), and the note rectangle keeps its existing chrome (`noteMinWidth`, grip reach, pixel
  insets) around those camera edges. `GridMetrics` loses `beatWidth`, `rowHeight`,
  `leadPadWidth`, `documentTicksPerBeat`, `pxPerTick`, `gridHeight`, `viewportWidth`,
  `viewportHeight`, and `contentX`/`tickAtContentX`/`displayX`/`rowEdge`/`yToPitch`/
  `contentEndTick`/`maxRulerBar`; it keeps font/chrome/snap/time-axis metrics and gains
  `noteRect(camera:x0:x1:pitch:)`. `GridGesture.updated` takes the camera so `move`,
  `resize`, `draw` and band selection keep their exact snapping while the projection
  moves.
- Scene culling: `GridSceneInput` carries the camera and the presenter's
  `contentEndTick` (max of timeline length, the existing minimum scene length, note
  ends and any draw preview). The generated window is
  `[max(0, scrollX - viewportWidth), min(contentEndTick * pixelsPerTick + viewportWidth,
  scrollX + 2 * viewportWidth)]` in content pixels, so one viewport of overscan is
  retained at both edges and no marks are generated for the rest of a long document.
- Published Qt surface: keep `beatWidth` (= snapshot `pixelsPerBeat`), `rowHeight`
  (= snapshot `keyHeight`), `ticksPerBeat`, `snapTicks`, `visibleGridTicks`,
  `keyboardWidth`, `baseFontPx`, `devicePixelRatio`, `editCursorTick`, `hoverKey`,
  `cursorKind`, `statusText`, `noteSummary`, `renderedNoteCount`, `appliedRevisionText`,
  `lastCancelReason`, `trackIndex`, `pencilMode`, `tripletGrid`, `lastVelocity`,
  `scene`, `palette`; add `cameraScrollX`, `cameraScrollY`, `cameraMaxVScroll`. Retire
  `gridWidth`, `gridHeight`, `leadPadWidth`, `initialScrollY`, `beatCount`, the
  `setViewportScroll(x:y:)` and `zoomBy(delta:vertical:)` entry points, and the
  `viewportScrollX`/`viewportScrollY`/`horizontalZoom`/`verticalZoom` fields. No
  aliases and no compatibility wrappers.
- Presenter refresh: `@QtIgnored func refreshCamera()` re-reads `session.camera`,
  updates the published camera values, typography and time axis, then rebuilds
  static+notes and publishes outputs. Wheel/scroll/setter entry points never rebuild
  directly; the single session publication drives `refreshCamera()` (wired by
  `ApplicationSession`). `configureViewport` additionally calls it directly after its
  own push, because an identical push publishes nothing while the layout metrics may
  still have changed.

### Production composition (`EditorSurface.qml`)

- `EditorSurface.qml` carries the whole existing `SwiftRollOverlay.qml` body —
  background, gutter side, plot side, `PianoRollCanvas`, both `MouseArea`s, hover and
  focus handling, `configureViewport()` — moved, not copied, with `appSession.…`
  rewritten as `applicationSession.…` and `readonly property var gridModel:
  applicationSession.gridPresenter()` kept (the host reads it for palette transfer).
  Its only new interface is `required property QtObject applicationSession`.
- `SwiftRollOverlay.qml` becomes `EditorSurface { applicationSession: appSession }` and
  remains the context-property adapter the host loads
  (`RewriteWindow::attachGridScene`), so no native change is needed.
- Retired in the move: the `Flickable`, its `contentX`/`contentY` integration and
  bounds behavior, the `swiftRollViewport` item, the one-shot `centeredOnNotes`
  contentY write, and the fixture `handleWheel`/`scrollBy` modifier mapping
  (Alt-wheel pitch zoom, plain-wheel vertical scroll). Both `MouseArea`s are
  unchanged in behavior; the plot gains the same `WheelHandler` device filter it has
  today, and the gutter gains a `WheelHandler` routing through `handleWheel` with
  `overGutter: true`. Handlers pass `event.angleDelta`, `event.pixelDelta`,
  `event.modifiers`, `phase: event.phase` (`phase` is a `Q_PROPERTY` of the pinned Qt
  6.11 `QQuickWheelEvent`, `qquickevents_p_p.h:191`, and its `Qt::ScrollPhase` value is
  the QML-visible `Qt.ScrollMomentum` for momentum), `anchorX: event.x`,
  `anchorY: event.y`, and accept the event. No handler is copied, no inert side item
  and no synthetic event.
- `objectName` values required by the host and the retained suite stay exactly:
  `swiftRollOverlay` (root), `swiftRollBackground`, `timelineQuickRollGutter`,
  `timelineQuickRollPlot`, `pianoGridSurface`, `swiftRollInput`, plus every scene
  primitive name produced by `GridScene`/`PianoRollCanvas`.

### Integration checks

`runEditorGridCameraChecks(_ report: CheckReport, session: DocumentSession)` in the
new file, called from `runProjectSessionSuite` immediately before the close-lifecycle
block, so its committed edits follow all save/reload evidence. It builds a
`PianoGrid(session:)`, wires check-owned `onCameraChange`/`onPlayback` counters, and
restores the suite's callbacks when it returns. Case IDs and their outcomes:

- `swiftcore/EditorGridCamera::viewportPushAndBounds` — one `configureViewport(width:
  height:fontPx:dpr:)` moves the session camera, not a presenter copy: viewport width and
  roll height are pushed; `minHScroll = -clamp(round(width*0.10),48,256)`;
  `maxHScroll = lengthTicks * pixelsPerTick`; `maxVScroll =
  max(0, visibleRowCount * keyHeight - rollHeight)`; the published `beatWidth`/`rowHeight`
  equal the snapshot; the first push leaves the note-centred vertical home in
  `[0, maxVScroll]`; an identical push publishes nothing and preserves fractional
  offsets; a roll-height increase and a document shrink reclamp; a push at
  `fontPx * 2` scales both axes by the font ratio and a push back restores the exact
  earlier scale; the pushed font, not the seed, defines the rendered limits (after a
  push at `f`, time zoom clamps to `[fontPx(f,1/3), fontPx(f,160/3)]` and key height to
  `[fontPx(f,1/3), fontPx(f,8/3)]`).
- `swiftcore/EditorGridCamera::wheelPolicy` — through `handleWheel` only:
  Shift+angle pans by `-d` and clamps at `minHScroll`/`maxHScroll`; a horizontal-only
  delta pans; a plain vertical wheel over the plot changes `pixelsPerBeat` by
  `pow(1.0015, dy)` and keeps the tick at `anchorX` fixed when unclamped; pixel deltas
  weigh five times the angle deltas (asserted ppb values differ by that weighting);
  Ctrl+wheel changes `keyHeight` by `exp2(dy/1200)` and keeps the row at `anchorY`
  fixed when unclamped; a gutter wheel moves `scrollY` by `-dy/2` within its bounds;
  a momentum phase (`QtScrollPhase.momentum`) suppresses both zoom branches and still
  pans/scrolls, while `noScroll`/`begin`/`update`/`end` phases zoom normally; the same
  commands after a prior scroll still anchor at the pointer, not at the plot origin;
  clamped and no-op cases publish nothing (check-owned counter) while every effective
  command publishes exactly once.
- `swiftcore/EditorGridCamera::projectionAndHitTesting` — after a scroll and a zoom, a
  known note's `pianoNoteFills` rect equals the camera projection
  (`x = displayX(tick)`, row edges from the projection and `keyHeight`/`scrollY`), the
  pre-roll mask is present exactly when `displayX(0) > 0`, generated time marks stay
  inside the culling window and cover it, and `noteSummary` is unchanged by camera
  movement (rendering is not document state). Hit testing uses the same projection:
  `beginPointer` at a note's on-screen position selects that note; a drag by one snap
  cell publishes the snapped preview and `endPointer` commits exactly one document
  revision with the expected snapped tick/pitch; a draw drag on empty rows adds one
  note at the snapped tick/pitch; a right-press band over the visible window selects
  exactly the intersecting notes; `inputCancelled`/`handleEscape` leave the document
  unchanged; a press outside the pitch rows is rejected.
- `swiftcore/EditorGridCamera::navigationIsolationAndReveal` — with check-owned
  counters, a sequence of wheel, setter, `resetCameraScroll` and reveal operations
  produces zero `onChange` publications, zero `onPlayback` publications, no revision
  change, no dirty change and no undo/redo change, while `onCameraChange` fires once
  per effective change. `ensureTickVisible`, `ensureRangeVisible(preferEnd: true/false)`
  and `ensureKeyVisible` through `mutateCamera` move the same camera the presenter
  publishes (`cameraScrollX`/`cameraScrollY` track `session.camera.snapshot`), keep the
  reveal fraction/edge behavior the prep cases assert, are no-ops for hidden pitches and
  already-visible targets, and non-finite or no-op setter input publishes nothing.
  Setting `editCursor` does not move the camera, and navigation does not change the
  published `editCursorTick`. A committed document edit on the same wiring produces
  exactly one `onChange` and one `onPlayback` with zero `onCameraChange` publications,
  and when `onChange` runs the camera already reflects the edited extent (reconciled
  length/ticks-per-beat bounds and reclamped scroll) — no nested camera callback and no
  second presenter rebuild on the document path.

## Implementation steps

1. **Session ownership and publication.** Delete `SessionCamera`; add `editCursor`,
   the owned `EditorCamera`, `onCameraChange`, and `mutateCamera`; reconcile the
   camera's time-domain extent privately inside `handleDocumentChange` (no
   `onCameraChange` on that path) so the single `onPlayback`/`onChange` pair stays one
   coherent refresh. Migrate `NoteCommands.paste` mechanically. Wire
   `ApplicationSession`'s single subscription to the presenter's `refreshCamera()`.
2. **Camera push, home and input policy.** Add `GridCameraPolicy`; make
   `configureViewport` perform its single `mutateCamera` push with the font-ratio
   rescale; implement `resetCameraScroll`/`setCameraHScroll`/`setCameraVScroll` and
   `handleWheel`; migrate `PianoGrid`'s published camera values and refresh path; delete
   the retired fields, entry points and the `GridMetrics` copies. Keep note draw,
   move, resize, band selection, audition, hover and command/selection semantics exactly
   as they are; only their coordinate derivation changes.
3. **Projection cutover in scene/gesture/hit-testing.** Feed the camera into
   `GridGesture.updated`, `GridSceneInput` and note-rect geometry; make primitives
   viewport-relative; replace `visibleTicks`/ruler range bounds with the camera window
   and the presenter's `contentEndTick`; keep every palette, typography, dash, frame and
   label computation unchanged.
4. **Production surface extraction and input wiring.** Move the overlay body into
   `EditorSurface.qml` behind `required property QtObject applicationSession`; reduce
   `SwiftRollOverlay.qml` to the adapter; drop the Flickable, `swiftRollViewport`, the
   one-shot centering and the fixture wheel mapping; add the gutter `WheelHandler` and
   re-point the plot handler at `handleWheel`; add the `EditorSurface.qml` resource line.
   Compile/load from the same relative directory as `PianoRollCanvas.qml`; do not add a
   second composition, a test copy or a `Porydaw.Ui` registration.
5. **Checks.** Add `EditorGridCameraChecks.swift` and the `swift_core_check` source
   entry; call it from `runProjectSessionSuite` before the close-lifecycle block;
   migrate `SessionChecks.swift:499` to `editCursor` plus a camera mutation so the
   "session-only state never dirties" assertion keeps its meaning. Then migrate the
   three retained files: `gesturechecks.cpp` computes scene points and the visible
   window from `cameraScrollX`/`cameraScrollY` and the published `beatWidth`/`rowHeight`
   (`leadPadWidth` and Flickable offsets disappear), `chromevisuals.cpp` reads
   `cameraScrollX` for its probe bounds, sends its wheel over `timelineQuickRollGutter`
   and asserts `cameraScrollY` moves (the scroll-visibility observation production
   preserves) before re-checking the hover chip against `cameraScrollY`, and
   `notevisuals.cpp` replaces the Flickable placement with `resetCameraScroll()` plus an
   assertion that the published bounds equal the projected row height
   (`cameraMaxVScroll == max(0, 128 * rowHeight - plot height)`). Change no other
   assertion, add no case and no registration, and do not weaken any expectation: the
   observed production behavior (input moves the viewport; geometry follows font/DPR)
   must remain proven.

## Acceptance predicate

The four `swiftcore/EditorGridCamera::*` cases above are the headless integration gate
for grid rendering, hit testing, pan, anchored zoom, bounds and reveal on the
session-owned camera; the prep's `swiftcore/EditorCamera::*` cases keep their own
independent acceptance and are not re-run as proof of this work. The retained windowed
suite proves the same projection through the real window: pointer draw/move/resize,
band selection, escape/ungrab cancellation, clipboard round-trip on the real window,
font/DPR raster response, wheel scroll and hover alignment after the mechanical
migration, with no assertion removed before its replacement executes. The same run
doubles as the native-window harness smoke below and completes the input evidence that
only a real wheel and desktop can produce.

Controller verification — controller-run after writers settle, from the worktree root.
The `deno task` commands are existing tasks and the windowed filter names are existing
catalog entries; the new case IDs and `EditorSurface.qml` are prospective until step 4
lands. Windowed runs need a free desktop and run serially.

```sh
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession
deno task verify --filter swiftrollgated --filter swiftbandkeys --filter swiftqtml --filter selectionkey --verbose
```

The first builds the app and the migrated QML resource. The second runs the prep cases
plus the four integration cases headlessly (and builds `mid2agb`, which that suite
needs). The third is the retained native regression protection and the real-window
proof; it is not a mandate to restore more C++ GUI cases.

Native-window harness smoke (the third command). Every windowed harness constructs the
production `RewriteWindow` and opens it against a runner-staged scratch copy of the
fixture, so its input and raster are real while the checked-in fixture tree is never
mutated. While the runner's scratch is alive, capture that window and record: the real
wheel event reaching the migrated routing (`chromeRasterParity`'s gutter wheel scrolls
the view and its hover chip stays on the hovered row), the migrated pointer cases
landing draw/move/resize and band selection on the intended ticks and pitches after a
scroll, and `noteRasterParity` re-rendering at the pushed font/DPR with the published
camera bounds matching the projected row height. Do not launch a standalone bundle
against the checked-in fixture tree, add a staging runner or add a C++ scenario or
driver; if a required behavior is not observable through these runs, record it as
missing acceptance evidence instead of narrowing the requirement or substituting
offscreen/model-only evidence.

## Task-specific constraints

- No drawer, velocity, voice-change, automation, prompt or menu work; no new
  shortcut, action, native menu row or palette row; no velocity preview, voice query
  or selection-model change. Existing selection/track/cursor semantics are preserved,
  only their `SessionCamera` storage moves.
- No new C++ API, helper, controller, bootstrap, check name, catalog entry or suite
  value. The only native edits are the three mechanical assertion migrations listed
  in step 5; anything beyond them is a user decision, not an implementer extension.
- No new test infrastructure in this task: no Qt Quick Test lane, no test executable,
  no test-only production hook, no fixture scene. Task 2 owns any such lane; the
  integration checks live in the existing `runProjectSessionSuite`.
- Do not modify `EditorCamera.swift` or `EditorCameraChecks.swift`; if a genuine
  integration gap appears, report it rather than editing around it. No aliases,
  deprecated shims or compatibility wrappers for retired fields; no second camera, no
  reciprocal scroll binding, no presenter-owned viewport authority.
- Middle-button drag pan is absent from the current composition
  (`SwiftRollOverlay.qml:125` accepts only `Qt.LeftButton | Qt.RightButton` on the
  roll and `SwiftRollOverlay.qml:55` only `Qt.LeftButton` on the gutter) and is not
  added; nothing that exists may be dropped. Scrollbars, folding and page controls are
  likewise not part of this task: the production wheel policy, the existing pointer
  gestures and the camera setters are the pan/zoom surface. Do not restore absent
  chrome to satisfy a camera contract.
- Do not preserve fixture behaviors that contradict production input (plain-wheel
  scroll, Alt-wheel pitch zoom, Flickable bounds). The momentum contract is the pinned
  Qt's `WheelEvent.phase` (the `Qt.ScrollMomentum` value, source-cited above); if that
  value cannot be delivered or read on this Qt, report the unsupported contract as a
  blocker instead of adding C++, a second input path or a silent fallback.
- Keep the QML composition and the Swift presenter single-instance: no page, drawer or
  second surface may be created to host these checks, and no assertion may be weakened
  to make a migrated case pass.
