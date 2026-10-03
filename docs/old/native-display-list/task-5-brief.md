# Task 5 brief — Ruler on display lists

## Context

Task 4 cut plot (list 0) and keyboard (list 1) to `DisplayList` while the
ruler (list 2) stayed on `TimelineRenderer` band 2 via
`contentRevision`/`drawingContent()` (`GridScene.swift:91-102`,
`EditorRulerBand.qml:38-49`). This task ports `ruler_scene.cpp` into
`RollDisplayLists.swift`, points the ruler band at list 2, and removes the
last `GridScene` blob path and the legacy roll packer. After this task
`GridScene` exposes only `displayRevision`/`displayList(list:)` (Checkpoint 3:
no legacy blob path). Consumes Task 4 `RollDisplayLists.swift`, the Task 1
writer, and Task 2 `face(id)` with the reserved loop-marker ids
(Contract §1: `PD_DL_ID_LOOP_START/LOOP_END`, exposed as item `loopStartId`/
`loopEndId`).

## Exact write set

- `src/swift/app/roll/RollDisplayLists.swift` — ruler list-2 builder (port
  of `src/render/ruler_scene.cpp`).
- `src/swift/app/roll/GridScene.swift` — remove `contentRevision`/
  `drawingContent()`/`drawingContentData`/`drawingContentKey` once
  unreferenced; keep `displayRevision`/`displayList(list:)`.
- `src/ui/songview/quick/swiftroll/EditorRulerBand.qml:38-49` —
  `TimelineRenderer` → `DisplayList` (`list: 2`, `objectName:
  timelineQuickRulerMarks` preserved; camera bindings
  `pixelsPerTick/keyHeight/scrollX/scrollY/devicePixelRatio` `:44-48`
  deleted).
- Ruler check helpers → `face(renderer.loopStartId)` etc.:
  `src/checks/editorqml/ShellGridMenuSupport.qml:235-245`
  (`loopMarkerAt`/`loopMarkerAbsent`), `tst_EditorDrawerChrome.qml:341-343`
  (`markerX`), `tst_ShellChromeVisuals.qml:221-226` (marker reads; the
  `band === 2` assertion at `:221` is re-expressed — `DisplayList` uses
  `list`, not `band`), `tst_ShellMenusLoop.qml:24-27,90-97` (`markerX`,
  `markerStart`/`markerEnd`).
- Legacy roll packer deletion: whatever of `RollDrawingContent` remains
  unreferenced after the port (the file was renamed in Task 4; delete the
  superseded sections, not the list builders).
- Affected `proof.*.txt` rows in the same commit(s).

## Prerequisites

- Task 4 `RollDisplayLists.swift` plot/keyboard builders and the
  `displayRevision` bump discipline (all lists rebuild together, one bump).
- Task 2 reserved ids: loop markers carry `PD_DL_ID_LOOP_START/LOOP_END`
  and are queryable as `face(renderer.loopStartId)` /
  `face(renderer.loopEndId)`; check helpers never spell the numbers.

## Interface contract

- List 2 contains, in order: chrome background + bottom separator
  (`ruler_scene.cpp:46-49`); pre-roll mask (`:85-86`, width
  `max(0, −soX)` where `soX` is the rounded scroll origin); subdivision
  ticks (`:87-93`, height `spaceHalf` at level 1 else 1.0, via
  `RollGrid.forEachSubdivision`); bar/beat ticks + labels (`:99-148`:
  `drawBeatTicks` gate `beatWidth >= detailMinPxPerBeat`, `showBeatLabels`
  gate `beatWidth >= rulerBeatLabelZoomFactor·(barCap + 2·labelGap +
  spaceTwo + beatAdvance)`, label-dedup via `lastLabelRight + labelGap`,
  max-bar reservation `maxBeatWidth`/`maxSignatureWidth` + margin
  `:72-84`); loop markers (`:150-169`, glyphs `[`/`]` in the bold font at
  `x + spaceHalf`, marker line rects); signature seams (`:171-191`,
  elision when `contentTickX(start) + 2·spaceHalf + labelWidth >
  contentTickX(next)`). All x positions via `EditorCamera.viewX`; all
  advances via `NativeFontMetrics.advance`; fitted sizes decided in Swift.
  Marker line rects carry the reserved ids and are what `face()` returns.
- `EditorRulerBand.qml` ruler item: `source: root.gridModel.scene`,
  `list: 2`, `revision: root.gridModel.scene.displayRevision`,
  `objectName: "timelineQuickRulerMarks"`; no `band`, `contentSource`,
  `contentRevision`, or camera bindings.
- `GridScene` after: no `contentRevision`, no `drawingContent()`; the only
  QtBridge-visible surface is `displayRevision` + `displayList(list:)` (+ the
  existing hover-chip state).

## Implementation steps

1. Port `RulerScene::append` (`ruler_scene.cpp:39-192`) section by section
   into the list-2 builder: background/separator, typography-availability
   early-out (`:50-53` — emit background-only list when fonts/axis
   missing), visible-range computation (`visibleTick`, `:25-30,67-84`),
   pre-roll mask, subdivision ticks, numbered-line pass with reservation
   gates and dedup, markers with reserved ids, signature seams with
   elision. Clip every record with `appendVisible` semantics.
2. Rebuild list 2 on the same triggers as lists 0/1 (content + camera
   paths); keep the single `displayRevision` bump.
3. Cut `EditorRulerBand.qml:38-49` to `DisplayList`; delete camera
   bindings; keep the objectName and layout.
4. Migrate the four ruler helpers to `face()` with the item's reserved-id
   properties: `noteFace(name)` → `face(renderer.loopStartId)` /
   `face(renderer.loopEndId)`; absence = empty map (`width === undefined`,
   same predicate as today). Re-express the `band === 2` assertion
   (`tst_ShellChromeVisuals.qml:221`) against the `DisplayList` list id.
5. Grep `contentRevision|drawingContent` under `src/swift` and `src/checks`:
   every remaining roll-reader must be gone or belong to a drawer page
   (Tasks 6-8 own those); then remove the `GridScene` blob path and the
   unreferenced packer sections. Grep `TimelineRenderer` under `src/ui`
   must show no roll-surface user.

## Acceptance predicate

- `deno task checks:shell --verbose` — covers loop-marker journeys
  (`ShellGridMenuSupport`, `tst_ShellMenusLoop`), chrome visuals, and ruler
  menu scopes through `face()`.
- `deno task checks:qml-roll --verbose` — covers ruler raster identity at
  dpr 1 and 2; the gate is byte-identity against current band-2 output.
- `deno task proof check --executed` — covers ledger health after anchor
  repair.
- Gaps: marker-absence polling timing (`width === undefined` immediately
  after undo) is timing-sensitive and not deterministic under load; the
  controller's native-desktop smoke (open song, set/clear loop, undo,
  watch markers at dpr 1 and 2) covers it.

## Task-specific constraints

- Do not change lists 0/1 record order or content except where the ruler
  shares helpers (reservation math); plot/keyboard rasters stay
  byte-identical through this task.
- Check helpers use `renderer.loopStartId`/`loopEndId` properties, never
  numeric literals for the reserved ids.
- `contentRevision`/`drawingContent` removal is gated on the grep in step
  5 being empty for roll readers; drawer blob paths are explicitly not
  this task's to remove.
