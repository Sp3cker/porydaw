# Task 4a brief — Roll plot (list 0) on display lists; plot check migration

## Context

Task 3b unified projection in Swift (`viewX`; `rowTop`/`rowBottom` keep
their names with the unified `snappedEdge` body). This task moves the roll
plot (list 0) off `TimelineRenderer` onto `DisplayList`, with Swift
emitting every viewport rect and label the C++ plot builder used to
compute. The keyboard (list 1) stays on `TimelineRenderer` band 1 via the
legacy `contentRevision`/`drawingContent()` pair until Task 4b; the ruler
(list 2) stays on band 2 until Task 5. Consumes the Task 1 writer
(`DisplayListWriter`), the Task 2 item (`DisplayList` + `face(id)`), and
Task 3 projection. Produces the plot builder, the `GridScene`
`displayRevision`/`displayList(_:)` surface, and the `face()` migration
that Task 4b's keyboard cutover rides on. Rebuild triggers and the
economy-check inversion are stated once in plan Contract §3
(`plan.md:207-216`, per-page camera seams named there); this brief cites
that paragraph instead of restating it. Check migration funnel:
`src/checks/editorqml/RollNoteFaces.js:6` is the only live `gridNote_`
caller (verified by grep), so all QML journeys migrate through one line.

## Exact write set

Swift:

- `src/swift/app/roll/RollDisplayLists.swift` — created by renaming
  `RollDrawingContent.swift` (git mv; keeps history) and rewriting its
  body to per-frame viewport-list building, plot builder only (list 0;
  lists 1 and 2 return empty lists). Do not create a second file beside
  the old one.
- `src/swift/app/roll/GridScene.swift` — gains `displayRevision`/
  `displayList(_:)`; keeps `contentRevision`/`drawingContent()` (`:91-103`)
  as the band-1/band-2 feed while the keyboard and ruler need them.
- `src/swift/app/roll/GridScene+Notes.swift`,
  `src/swift/app/roll/GridScene+Rebuild.swift`,
  `src/swift/app/roll/PianoGrid.swift`,
  `src/swift/app/roll/PianoGrid+SceneSync.swift` — rebuild triggers, list
  inputs, counts.

QML:

- `src/ui/songview/quick/PianoRollCanvas.qml` — plot item only
  (`:11-29`): `TimelineRenderer` → `DisplayList` (`list: 0`,
  `objectName: "timelineRendererPlot"` preserved). The keyboard item
  (`:38-50`) and its camera bindings including `hoverPitch` (`:49`) are
  untouched; the hover chip (`:53-85`) is untouched (still QML
  Rectangle/Text).

Checks:

- `src/checks/editorqml/RollNoteFaces.js` (`:6`: `renderer.noteFace(
  "gridNote_" + id)` → `renderer.face(id)`; `rect`/`center`/`point`/
  `grab` unchanged) plus its consumers (no signature change; they keep
  calling `rect`/`center`/`point`/`face`).
- `src/checks/rollcheck/note_rendering_economy.swift` (also gains
  `checkRollPlotCullBound`, wired into `runNoteRenderingChecks`
  (`note_rendering.swift:7-15`); no new suite file and no
  `src/checks/CMakeLists.txt` touch — the file is already listed at
  `:150` in `swift_core_check`), `note_rendering_support.swift`,
  `note_rendering_borders.swift`,
  `note_rendering_ghosts.swift`, `note_rendering_names.swift`,
  `note_rendering_velocity.swift`, `note_name_labels.swift` (delete
  `faceFits`/`nameFits`, `:34-52`; re-express `labels`/`valueLabels`
  callers against `face()`/raster), `selection.swift`
  (`projectedNoteBox`, `:9-19`), `EditorGridProjectionChecks.swift`,
  `scale_editing.swift`, `selection_audition.swift`,
  `keyboard_time_selection.swift`, `roll_content_probe.swift`,
  `EditorGridCameraChecks.swift`, `EditorGridLatticeChecks.swift`, and any
  further plot-side `grid.scene.contentRevision`/`drawingContent` reader
  found by grep under `src/checks/rollcheck` — each rewritten per step 6.
  Keyboard-byte readers (`keyboardNames`, `drumKeyboard`, `hoverPitch`/
  `hoverKey` assertions) and `src/checks/rollqml/` keyboard journeys are
  out of scope until Task 4b. Drawer-page blob readers
  (`AutomationDrawingContentChecks.swift`, `VoiceChangesPageChecks.swift`,
  automation/hover, drawerpresentation) are out of scope until Tasks 6-8.
- Affected `proof.*.txt` rows in the same commit(s).

## Prerequisites

- Task 1 `DisplayListWriter` (`rect`/`label`/`font`/`finish`, capacity kept
  across frames) and Task 2 `DisplayList` with working `face(id)`.
- Task 3b `viewX` and the unified `rowTop`/`rowBottom` (band-1/band-2 C++
  keeps its own copy until Tasks 4b/5; no C++ change here).
- Task 0 per-frame pack budget recorded in plan.md Status.

## Interface contract

- `GridScene` (in its `@QtBridgeable` class body):
  `@QtTracked public var displayRevision = 0`;
  `public func displayList(_ list: Int) -> Data` returning a retained
  buffer. All three lists rebuild together and bump `displayRevision` once
  per rebuild. `displayList(1)` and `displayList(2)` return empty lists
  (valid header, zero records) until Tasks 4b/5 port them.
- `RollDisplayLists.swift` builds list 0, per frame, from `GridSceneInput`
  (`GridScene+Rebuild.swift:6-31`) + camera snapshot
  (`EditorCamera.swift:126-137`; viewport size arrives via
  `snapshot.viewportWidth`/`rollHeight`, fed by
  `PianoGrid.configureViewport` ← `configureViewportImpl`
  (`PianoGrid+Camera.swift:8-56`) ← `EditorSurface.qml:355-359`
  `configureViewport()` on width/height change) + `GridMetrics` +
  `GridTypography` + item width/height. C++→Swift port map (Swift function
  replaces C++ function; row functions are `rowTop`/`rowBottom` per the
  Contract §4 naming decision):
  rows/separators `roll_scene.cpp:124-150 appendRows` → list builder
  section using `rowTop`/`rowBottom`; pre-roll mask `:152-159` →
  `viewX(0)`-gated mask rect; time grid `:161-208` (`forEachSubdivision` +
  `forEachGridLine` walks) → `RollGrid.forEachSubdivision`
  (`GridGeometry.swift:309-345`) + `TimeAxis.forEachGridLine`
  (`TimeAxis.swift:101-155`) emitting `viewX` line rects; note fills +
  `notesByTick` cull `:210-254` → culled plot-list notes via
  `EditorCamera.viewX` + `GridMetrics.noteBox`; preview `:256-269` →
  preview rect from `GridSceneInput.drawPreview`; frames/rings/sweep
  `:271-291` (`addNoteBorder`, `addSelectionRing`, `addFrame`,
  `fittedFrameThickness`) → `GridMetrics.noteBorderPixels/
  selectionRingPixels/fittedFrameThickness` (`GridGeometry.swift:442-450`)
  with frame/ring/dash decomposition copied from the pre-renderer
  `git show 63f492d8:src/swift/app/roll/GridScene+Primitives.swift`
  (`addFrame`, `addDashedFrame`); band selection `:293-314` and time
  selection `:316-334` → rects from the `selectionBand`/`timeSelection`
  inputs; loop edge/glow `:336-394` → edge rects + alpha-ramp bands from
  the time-axis loop ticks; note-name faces
  `timeline_renderer.cpp:424-448 appendNoteLabels` (gate `:430-432`, width
  fit `:439`) → `GridTypography` fits + `NativeFontMetrics.advance` with
  Swift-decided `pixelSize`; fitted-size memo `:310-319` → Swift-side
  per-frame fit (no memo needed — inputs are already per-frame).
- Frame-tier skip (plan Contract §3, `plan.md:237-242`): the content tier
  keeps `RollNotesSectionKey`/`displacesNotes` keying
  (`RollDrawingContent.swift:42-50`, `GridScene+Rebuild.swift:16-20`) for
  the per-note fills, spans and selection it resolves once per content key
  into a tick-sorted record array; the frame tier culls and projects that
  array — O(visible) per frame, never O(notes). `notesSectionCache`
  (`GridScene.swift:101`) is deleted, replaced by that record array, not
  kept as packed bytes.
- Rebuild triggers and the economy inversion: exactly plan Contract §3
  (`plan.md:207-216`) — content path plus the named per-page camera seams;
  camera moves change `displayRevision` and the list bytes while the
  content-tier keys stay untouched.
- Band selection (`bandSelection*`, `PianoGrid.swift:109-113`,
  `publishOutputs`, `PianoGrid+SceneSync.swift:315-324`) becomes a list
  input: band rects are emitted records, not item properties.
  `hoverKey` (`PianoGrid.swift:143`, `PianoGrid+SceneSync.swift:54`) stays
  a legacy-pack/hover-chip input only — no keyboard highlight records in
  this task; the plot-side hover chip (`GridScene.swift:119-148`
  `hoverChipRect`/`hoverChipVisible`/`hoverChipText`, QML chip
  `PianoRollCanvas.qml:53-85`) is untouched and stays QML-driven.
- `renderedNoteCount` (`PianoGrid.swift:99`,
  `PianoGrid+SceneSync.swift:312-314`) keeps its meaning, computed from the
  culled plot list (`noteRecordCount` analogue on the new path).
- QML: plot item `source: root.gridModel.scene, list: 0, revision:
  root.gridModel.scene.displayRevision`; all camera bindings on the plot
  item (`pixelsPerTick/keyHeight/scrollX/scrollY/devicePixelRatio/
  bandSelection*`, `PianoRollCanvas.qml:18-27`) deleted. Keyboard item
  keeps `band: 1`, `contentSource`/`contentRevision`, all camera bindings
  and `hoverPitch`.
- Checks: `renderer.face(id)` takes the numeric note id and returns
  `{x,y,width,height,fill}` of the first matching rect or an empty map;
  every `noteFace("gridNote_` consumer migrates through `RollNoteFaces.js`.

## Implementation steps

1. `git mv RollDrawingContent.swift RollDisplayLists.swift`; rewrite the
   body to per-frame building, plot builder only. Keep every palette slot
   the plot needs; keyboard-only and ruler-only slots stay for Tasks
   4b/5.
2. Port the plot pass (rows, grid, fills+cull, preview, frames/rings/sweep,
   band/time selection, loop, note-name faces) per the port map;
   viewport-clip every record to the item size (`emitClipped`/
   `appendVisible` semantics). Lists 1 and 2 build empty lists.
3. Replace the content tier per the contract: `RollNotesSectionKey`/
   `displacesNotes` keying resolves into the tick-sorted record array;
   delete `notesSectionCache`; the frame tier culls/projects per frame.
4. Wire rebuild triggers per plan Contract §3 (`plan.md:207-216`): content
   path and the named camera seams rebuild all lists and bump
   `displayRevision` once.
5. QML cutover of the plot item in `PianoRollCanvas.qml` only; delete its
   camera bindings; keep `objectName: "timelineRendererPlot"` and layout.
6. Migrate `RollNoteFaces.js:6` to `face(id)`; leave all downstream helpers
   and journeys unchanged.
7. Rewrite each plot-side roll check reader: `projectedNoteBox`/
   `contentNoteBox`/`noteBox` helpers → `face()` lookups or raster probes;
   `contentRevision`/`drawingContent` assertions → `displayRevision`/
   `displayList(_:)` byte comparisons; economy check per Contract §3
   (`plan.md:211-214`); delete check-only `faceFits`/`nameFits` and
   re-express those assertions against `face()` geometry or raster.
8. Grep `TimelineRenderer` under `src/ui`/`src/checks` and
   `DrawingContentBinary` under `src/swift` to confirm band 0 is fully off
   the old path (band 1 keyboard and band 2 ruler references must remain).
9. Add `checkRollPlotCullBound` in `note_rendering_economy.swift` per the
   Acceptance bullet; wire it into `runNoteRenderingChecks`.

## Acceptance predicate

- `deno task checks --filter swiftcore --verbose` — covers projection,
  economy (re-expressed), roll semantics, and migrated label assertions.
- Same command — covers the roll-plot cull bound
  (`checkRollPlotCullBound`): fixture song with a known visible note set
  plus thousands of notes far outside the viewport (off-screen notes via
  `document.addNotes`, `note_rendering_economy.swift:181-183`; visible
  set via a `renderingSeed`-style free-cell insert,
  `note_rendering_support.swift:39-83`); decode
  `grid.scene.displayList(0)` with the Task 1 reader and assert the
  note-fill rect count equals the count projected from only the visible
  notes (`EditorCamera.viewX`, `EditorCamera.swift:233-236`;
  `GridMetrics.noteBox`, `GridGeometry.swift:413-416`) plus grid lines,
  and that doubling the off-screen notes leaves the count unchanged.
- `deno task checks:qml-roll --verbose` — covers roll raster identity at
  dpr 1 and 2; the gate is byte-identity against current
  `TimelineRenderer` output.
- `deno task checks:shell --verbose` — covers hit-test journeys now routed
  through `face()`.
- `deno task checks:bridge` — covers the new `displayRevision`/
  `displayList` QtBridge surface.
- `deno task proof check --executed` — covers ledger health (no rows
  currently anchor `EditorGridProjectionChecks.swift` messages).
- Rasters byte-identical to the Task 3 checkpoint (1b): Swift paints with
  the formula C++ painted with, so any diff is a port bug, not tolerance.
- Gap: keyboard and ruler rasters are not this task's gate (their bands
  still paint from C++); Task 4b/5 gate them.

## Task-specific constraints

- Plot paint order is under-rects → labels → over-rects (Contract §1):
  the plot rects that today go to `m_over`
  (`timeline_renderer.cpp:374-378`: note frames/rings, band selection, time
  selection, loop edge/glow) carry `PD_DL_RECT_OVER`; label backgrounds
  emit as the last under-rects. Dashed frames/rings decompose to rects
  exactly as the pre-renderer primitives did — no new decomposition
  scheme.
- Keyboard band 1 and ruler band 2 keep working through
  `contentRevision`/`drawingContent()`; `displayList(1)` and
  `displayList(2)` stay empty; do not delete the legacy packer's keyboard
  or ruler sections, and do not touch the keyboard item's QML bindings
  (`PianoRollCanvas.qml:38-50`) or `EditorRulerBand.qml:38-49`.
- No dual formats: band 0 decodes only `display_list.h`; `TimelineRenderer`
  keeps serving bands 1/2.
