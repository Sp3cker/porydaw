# Task 4 brief — Roll plot + keyboard on display lists; roll check migration

## Context

Task 3 unified projection in Swift (`viewX`; `rowTop`/`rowBottom` keep their
names with the unified `snappedEdge` body). This task moves the roll plot
(list 0) and keyboard (list 1) off `TimelineRenderer` onto `DisplayList`,
with Swift emitting every viewport rect and label the C++ scene builders
used to compute. Consumes the Task 1 writer (`DisplayListWriter`) and Task
2 item (`DisplayList` + `face(id)`), and Task 3 projection. Decided (plan
Contract §3, `plan.md:200-216`): between Tasks 4 and 5 `displayList(2)`
returns an empty list (valid header, zero records — the item paints nothing
for it, `plan.md:176`) while the ruler stays on `TimelineRenderer` band 2
via the legacy `drawingContent()`/`contentRevision` pair. Rebuild triggers
and the economy-check inversion are stated once in plan Contract §3
(`plan.md:207-216`, per-page camera seams named there); this brief cites
that paragraph instead of restating it. Check migration funnel:
`src/checks/editorqml/RollNoteFaces.js:6` is the only live `gridNote_`
caller (verified by grep; other hits are quoted provenance in
`proof.clipboardchecks.txt`), so all QML journeys migrate through one line.

## Exact write set

Swift:

- `src/swift/app/roll/RollDisplayLists.swift` — created by renaming
  `RollDrawingContent.swift` (git mv; keeps history) and rewriting its body
  to per-frame viewport-list building. Do not create a second file beside
  the old one.
- `src/swift/app/roll/GridScene.swift` — gains `displayRevision`/
  `displayList(_:)`; keeps `contentRevision`/`drawingContent()` (`:91-102`)
  as the band-2 feed while the ruler needs them.
- `src/swift/app/roll/GridScene+Notes.swift`, `GridScene+Rebuild.swift`,
  `src/swift/app/roll/PianoGrid.swift`, `src/swift/app/roll/
  PianoGrid+SceneSync.swift` — rebuild triggers, list inputs, counts.

QML:

- `src/ui/songview/quick/PianoRollCanvas.qml:11-50` — two `DisplayList`
  items replace the two `TimelineRenderer` items; `objectName`s
  `timelineRendererPlot`/`timelineRendererKeyboard` preserved (both are
  looked up by checks: grep `timelineRendererPlot` hits
  `ShellClipboardSupport.qml:115`, `ShellGridInputSupport.qml:135`,
  `ShellGridMenuSupport.qml:278,302`, `ShellPitchBendSupport.qml:116,234`,
  `ShellWindowSupport.qml:193,213,246`,
  `tst_EditorDrawerVelocityHitTargets.qml:67`,
  `tst_ShellEventListKeyboardSelection.qml:31`; `timelineRendererKeyboard`
  hit in `tst_ShellChromeVisuals.qml:120`).

Checks:

- `src/checks/editorqml/RollNoteFaces.js` (`:6`: `renderer.noteFace(
  "gridNote_" + id)` → `renderer.face(id)`; `rect`/`center`/`point` unchanged).
- `src/checks/rollcheck/note_rendering_economy.swift`,
  `note_rendering_support.swift`, `note_rendering_borders.swift`,
  `note_rendering_ghosts.swift`, `note_rendering_names.swift`,
  `note_rendering_velocity.swift`, `note_name_labels.swift` (delete
  `faceFits`/`nameFits`, `:34-52`; re-express `labels`/`valueLabels`
  callers against `face()`/raster), `selection.swift`
  (`projectedNoteBox`, `:8-19`), `EditorGridProjectionChecks.swift`,
  `keyboard_parity.swift:119-123`, `scale_editing.swift:332-336,424-428`,
  `selection_audition.swift:216-224`, `keyboard_time_selection.swift`,
  `roll_content_probe.swift`, `EditorGridCameraChecks.swift`,
  `EditorGridLatticeChecks.swift`, and any further `grid.scene.
  contentRevision`/`drawingContent` reader found by grep under
  `src/checks/rollcheck` — each rewritten per step 6. Drawer-page blob
  readers (`AutomationDrawingContentChecks.swift`,
  `VoiceChangesPageChecks.swift`, automation/hover, drawerpresentation)
  are out of scope until Tasks 6-8.
- Affected `proof.*.txt` rows in the same commit(s).

## Prerequisites

- Task 1 `DisplayListWriter` (`rect`/`label`/`font`/`finish`, capacity kept
  across frames) and Task 2 `DisplayList` with working `face(id)`.
- Task 3 `viewX` and the unified `rowTop`/`rowBottom` (band-2 C++ keeps its
  own copy until Task 5; no C++ change here).
- Task 0 per-frame pack budget recorded in plan.md Status.

## Interface contract

- `GridScene` (in its `@QtBridgeable` class body):
  `@QtTracked public var displayRevision = 0`;
  `public func displayList(_ list: Int) -> Data` returning a retained
  buffer. All three lists rebuild together and bump `displayRevision` once
  per rebuild. `displayList(2)` returns an empty list (valid header, zero
  records) until Task 5 ports the ruler.
- `RollDisplayLists.swift` builds, per frame, from `GridSceneInput`
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
  the time-axis loop ticks; keys/separators/hover `:396-445 appendKeys` →
  keyboard list via `rowTop`/`rowBottom`; note-name faces
  `timeline_renderer.cpp:424-448 appendNoteLabels` (gate `:430-432`, width
  fit `:439`) → `GridTypography` fits + `NativeFontMetrics.advance` with
  Swift-decided `pixelSize`; key labels `:458-497 appendKeyLabels`
  (white-keys/octave-C-F filter `:472`, drum-width rule `:480-484`) →
  same filter in Swift; fitted-size memo `:310-319` → Swift-side per-frame
  fit (no memo needed — inputs are already per-frame).
- Rebuild triggers and the economy inversion: exactly plan Contract §3
  (`plan.md:207-216`) — content path plus the named per-page camera seams;
  camera moves change `displayRevision` and the list bytes while the
  content-tier keys stay untouched.
- `hoverKey` (`PianoGrid.swift:143`, `PianoGrid+SceneSync.swift:54`) and
  band selection (`bandSelection*`, `PianoGrid.swift:109-113`,
  `publishOutputs`, `PianoGrid+SceneSync.swift:315-324`) become list inputs:
  hover highlight and band rects are emitted records, not item properties.
- `renderedNoteCount` (`PianoGrid.swift:99`,
  `PianoGrid+SceneSync.swift:312-314`) keeps its meaning, computed from the
  culled plot list (`noteRecordCount` analogue on the new path).
- QML: plot item `source: root.gridModel.scene, list: 0, revision:
  root.gridModel.scene.displayRevision`; keyboard item `list: 1`; all camera
  bindings (`pixelsPerTick/keyHeight/scrollX/scrollY/devicePixelRatio/
  bandSelection*/hoverPitch`, `PianoRollCanvas.qml:18-27,44-49`) deleted.
  Hover chip (`:53-64`) is untouched (still a QML Rectangle).
- Checks: `renderer.face(id)` takes the numeric note id and returns
  `{x,y,width,height,fill}` of the first matching rect or an empty map;
  every `noteFace("gridNote_` consumer migrates through `RollNoteFaces.js`.

## Implementation steps

1. `git mv RollDrawingContent.swift RollDisplayLists.swift`; rewrite the
   body to per-frame building. Keep every palette slot the plot/keyboard
   need; ruler-only slots stay for Task 5.
2. Port the plot pass (rows, grid, fills+cull, preview, frames/rings/sweep,
   band/time selection, loop) then the keyboard pass (keys, separators,
   hover, labels) per the port map; viewport-clip every record to the item
   size (`emitClipped`/`appendVisible` semantics). List 2 builds an empty
   list.
3. Wire rebuild triggers per plan Contract §3 (`plan.md:207-216`): content
   path and the named camera seams rebuild all lists and bump
   `displayRevision` once.
4. QML cutover in `PianoRollCanvas.qml`; delete camera bindings on both
   items; keep objectNames.
5. Migrate `RollNoteFaces.js:6` to `face(id)`; leave all downstream helpers
   and journeys unchanged.
6. Rewrite each roll check reader: `projectedNoteBox`/`contentNoteBox`/
   `noteBox` helpers → `face()` lookups or raster probes;
   `contentRevision`/`drawingContent` assertions → `displayRevision`/
   `displayList(_:)` byte comparisons; economy check per Contract §3
   (`plan.md:211-214`); delete check-only `faceFits`/`nameFits` and
   re-express those assertions against `face()` geometry or raster.
7. Grep `TimelineRenderer` under `src/ui`/`src/checks` and
   `DrawingContentBinary` under `src/swift` to confirm bands 0/1 are fully
   off the old path (band 2 ruler references must remain).

## Acceptance predicate

- `deno task checks --filter swiftcore --verbose` — covers projection,
  economy (re-expressed), roll semantics, and migrated label assertions.
- `deno task checks:qml-roll --verbose` — covers roll raster identity at
  dpr 1 and 2; the gate is byte-identity against current
  `TimelineRenderer` output.
- `deno task checks:shell --verbose` — covers hit-test journeys now routed
  through `face()`.
- `deno task checks:bridge` — covers the new `displayRevision`/
  `displayList` QtBridge surface.
- `deno task proof check --executed` — covers ledger health after anchor
  repair (known anchors: `proof.clipboardchecks.txt` S026-S035 for
  `EditorGridProjectionChecks.swift` messages).
- Rasters byte-identical to the Task 3 checkpoint (1b): Swift paints with
  the formula C++ painted with, so any diff is a port bug, not tolerance.
- Bench (plan Verification, Task 0b): roll pan and roll zoom scenarios,
  three runs, min-of-3 not above the 1b baseline; a regression stops the
  plan.

## Task-specific constraints

- Ruler band 2 keeps working through `contentRevision`/`drawingContent()`
  for one more task; `displayList(2)` stays empty; do not delete the legacy
  packer or its QML bindings in `EditorRulerBand.qml:38-49`.
- Paint order inside each list is under-rects → labels → over-rects
  (Contract §1): the plot rects that today go to `m_over`
  (`timeline_renderer.cpp:374-378`: note frames/rings, band selection, time
  selection, loop edge/glow) carry `PD_DL_RECT_OVER`; the keyboard list has
  no over-rects (`RollRootNode` paints band 1 rects below labels);
  dashed frames/rings decompose to rects exactly as the pre-renderer
  primitives did — no new decomposition scheme.
- No dual formats: bands 0/1 decode only `display_list.h`; `TimelineRenderer`
  keeps serving band 2.
