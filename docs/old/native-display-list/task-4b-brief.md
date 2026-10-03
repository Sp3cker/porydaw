# Task 4b brief — Roll keyboard (list 1) on display lists; keyboard check migration

## Context

Task 4a cut the plot (list 0) to `DisplayList` while the keyboard (list 1)
stayed on `TimelineRenderer` band 1 via `contentRevision`/
`drawingContent()`. This task ports `RollScene::appendKeys` and
`appendKeyLabels` into `RollDisplayLists.swift`, points the keyboard item
at list 1, removes the legacy packer's keyboard section, and migrates the
keyboard-byte checks. The ruler (list 2) stays on band 2 until Task 5.
Consumes Task 4a `RollDisplayLists.swift`, the Task 1 writer, Task 2
`face(id)`, and Task 3 projection. After this task the only legacy blob
reader on `GridScene` is the ruler. This task owns the `hoverPitch` move:
the `hoverPitch` item property dies here and the hover highlight becomes
Swift-emitted keyboard-list rects; the plot-side hover chip stays QML (see
contract).

## Exact write set

- `src/swift/app/roll/RollDisplayLists.swift` — keyboard list-1 builder
  (port of `RollScene::appendKeys` and `appendKeyLabels`; Task 4a owns the
  plot builder in the same file — sequential, 4b edits after 4a lands).
- `src/swift/app/roll/GridScene.swift` — remove the legacy packer's
  keyboard section once unreferenced; keep `contentRevision`/
  `drawingContent()` as the band-2 ruler feed; keep
  `displayRevision`/`displayList(list:)`.
- `src/ui/songview/quick/PianoRollCanvas.qml` — keyboard item only
  (`:38-50`): `TimelineRenderer` → `DisplayList` (`list: 1`,
  `objectName: "timelineRendererKeyboard"` preserved); camera bindings
  (`:44-49`) and `hoverPitch` (`:49`) deleted. Plot item and hover chip
  (`:53-85`) untouched.
- Keyboard checks in `src/checks/rollcheck/` and `src/checks/rollqml/`
  that read keyboard bytes or `hoverPitch`: `keyboard_drum_labels.swift`
  (`keyboardNames`/`drumKeyboard` probe readers, `GridScene.keyName`
  fallback), `roll_content_probe.swift` (keyboard-names/drum-flag
  section), `EditorGridCameraChecks.swift` (hover-chip/hoverKey
  assertions), `static/camera_wheel.swift` (gutter-hover `hoverKey`
  assertions), `note_rendering_economy.swift` (hover-only refresh
  assertions, if still legacy-shaped after 4a), `tst_TimelinePan.qml`
  (`keyboardRenderer()` helper `:163-167`, `band === 1` assertion
  `:180-182`, `hoverKey`/chip reads), `tst_TimelinePanPublication.qml`
  (drum-label `padLabel`/`hoverKey` reads), `tst_ShellChromeVisuals.qml`
  (`timelineRendererKeyboard` lookup `:120`, `band === 1` assertion
  `:128`), `tst_TextContrast.qml` (`timelineRendererKeyboard` lookup),
  and any further keyboard-byte or `hoverPitch` reader found by scoped
  grep under `src/checks/rollcheck` and `src/checks/rollqml` — each
  rewritten per step 4.
- Affected `proof.*.txt` rows in the same commit(s).

## Prerequisites

- Task 4a `RollDisplayLists.swift` plot builder, the `displayRevision`
  bump discipline (all lists rebuild together, one bump), and `face(id)`.
- Task 2 `DisplayList` item (list selection, not band).
- Task 3b `viewX` and the unified `rowTop`/`rowBottom`.

## Interface contract

- List 1 contains, in order: keyboard background
  (`roll_scene.cpp:409-411`, `KeyboardWhite` over the grid height);
  accidental lanes (`:416-420`, `KeyboardBlack`); C/F separators
  (`:421-425`, non-drum rows where `pitch % 12 == 0 || pitch % 12 == 5`,
  `KeyboardSeparator`); hover highlight (`:428-442`, `KeyboardHighlight`
  at `rowForPitch(hoverPitch)` gated on typography availability, plus the
  C/F separator re-emit `:437-441`); right-edge separator (`:443-444`,
  `Separator`). All row geometry via `rowTop`/`rowBottom`; all widths from
  `metrics.keyboardWidth`. Per Contract §1 the keyboard's C++ under/over
  split flattens to all-under: records the C++ code pushes to `m_over`
  (`timeline_renderer.cpp:453` call site; `roll_scene.cpp:433-444` hover
  and edge separators) emit as ordinary under-rects, painted below the
  key labels.
- Key labels (`timeline_renderer.cpp:458-497 appendKeyLabels`): fitted size
  via the Swift-side per-frame fit; white-keys/octave-C-F filter (`:472`,
  skipped when drum mode); drum-width rule (`:480-484`,
  `max(keyboardWidth - inset, advance + inset)`); right-aligned
  `KeyboardLabel` ink; drum-mode label backgrounds
  (`:490-495`, background rect = label rect, `KeyboardBlack` on black keys
  else `KeyboardWhite`). Advances via `NativeFontMetrics.advance`; fitted
  sizes decided in Swift.
- `hoverPitch` moves here: the `TimelineRenderer.hoverPitch` item property
  and the `PianoRollCanvas.qml:49` binding are deleted; `PianoGrid.hoverKey`
  (`PianoGrid.swift:143`) becomes a list-1 input — the hover highlight is
  emitted records, and camera-only hover changes rebuild the lists and
  bump `displayRevision`. The plot-side hover chip is not list content:
  `GridScene` hover-chip state (`GridScene.swift:119-148`) and the QML
  chip items (`PianoRollCanvas.qml:53-85`) stay exactly as Task 4a left
  them.
- `PianoRollCanvas.qml` keyboard item: `source:
  root.gridModel.scene`, `list: 1`, `revision:
  root.gridModel.scene.displayRevision`; no `band`, `contentSource`,
  `contentRevision`, camera bindings, or `hoverPitch`.
- Checks: keyboard-byte assertions (`keyboardNames`, `drumKeyboard`,
  label-overflow geometry) read list-1 labels via raster/`face()` or the
  Swift-published names the list builder consumed; `hoverKey` journey
  assertions keep driving `grid.updateHover`/`clearKeyboardHover` and read
  the highlight from the painted list; the `band === 1` assertions
  (`tst_TimelinePan.qml:181`, `tst_ShellChromeVisuals.qml:128`) are
  re-expressed against the `DisplayList` list id.

## Implementation steps

1. Port `RollScene::appendKeys` (`roll_scene.cpp:396-445`) section by
   section into the list-1 builder: background, accidental lanes, C/F
   separators, typography-gated hover highlight + separator re-emit,
   right-edge separator. Flatten the C++ under/over split to all-under.
   Clip every record with `appendVisible` semantics.
2. Port `appendKeyLabels` (`timeline_renderer.cpp:458-497`): fitted-size
   gate, visible-row cull, white-keys/octave-C-F filter, drum-width rule,
   right alignment, drum backgrounds as rects.
3. Rebuild list 1 on the same triggers as list 0 (content + camera paths,
   including hover-only changes); keep the single `displayRevision` bump.
4. Cut the keyboard item in `PianoRollCanvas.qml:38-50` to `DisplayList`;
   delete its camera bindings and `hoverPitch`; keep the objectName, the
   clip wrapper, and layout.
5. Grep `contentRevision|drawingContent` under `src/swift` and
   `src/checks`: every remaining keyboard-reader must be gone; then remove
   the legacy packer's keyboard section (ruler section stays for Task 5).
   Grep `hoverPitch` under `src/ui`/`src/checks` must show no renderer-item
   user.
6. Migrate each keyboard check per the contract; keep report messages
   byte-identical where the assertion class is unchanged.

## Acceptance predicate

- `deno task checks --filter swiftcore --verbose` — covers keyboard
  label semantics, gutter-hover journeys, and the hover-refresh economy
  assertions (camera/hover moves change `displayRevision` and list bytes).
- `deno task checks:qml-roll --verbose` — covers keyboard raster identity
  at dpr 1 and 2; the gate is byte-identity against current band-1 output.
- `deno task checks:shell --verbose` — covers shell journeys that hover
  or read the keyboard gutter.
- `deno task checks:bridge` — covers the unchanged `displayRevision`/
  `displayList` surface (no new members; property removal only).
- `deno task proof check --executed` — covers ledger health after anchor
  repair.
- Rasters byte-identical to checkpoint 1b; hit points unchanged from 1b —
  a raster diff is a port bug, a hit-test diff is not this task's.
- Gap: ruler raster is not this task's gate (band 2 still paints from
  C++); Task 5 gates it. Marker-absence polling timing, if touched, stays
  controller-smoked as in Task 5.

## Task-specific constraints

- Do not change list-0 record order or content except where the keyboard
  shares helpers; plot rasters stay byte-identical through this task.
- The keyboard list has no over-rects: everything emits under the key
  labels (Contract §1 flattening of the band-1 `m_over` pushes).
- The legacy packer's ruler section and `EditorRulerBand.qml:38-49`
  bindings are untouched; `contentRevision`/`drawingContent()` stay until
  Task 5 removes them.
