# Task 6 — Marker-list waveform + Sample Studio migration onto it

## Context

Sixth task of the Split Studio plan; generalizes the hard-coded 4-handle
waveform into the shared marker-list model both studios use, and migrates
Sample Studio onto it (explicitly allowed: the user has not used the current
waveform editor and it needs improving). Consumers: task 8's source session
and task 10's slicing view drive `MarkerWaveformModel` with
`kind: "slice"` markers; task 9's presenter stores it; task 10 mounts it
in the Split Studio window. Producers consumed: task 5's
`PorydawSampleUI` module and task 1's `SampleRatePolicy` (R16 — the
presenter's rate computation rewires onto it here). Today's coupling being
removed: `SampleWaveformModel`'s hard-coded
handle ids 1–4 and presenter dependency (`SampleWaveformModel.swift:79-137`,
`SampleWaveformScene.swift:41-103`).

## Exact write set

- Create `src/swift/sampleui/MarkerWaveformModel.swift` (model + row type)
- Create `src/swift/sampleui/MarkerWaveformScene.swift` (display-list
  scene; mirror of the moved `SampleWaveformScene`, extended with marker
  tabs — separate file like the pair it replaces)
- Delete `src/swift/app/samplestudio/SampleWaveformModel.swift` and
  `src/swift/app/samplestudio/SampleWaveformScene.swift` (logic moves)
- Edit `src/swift/app/samplestudio/SampleStudioWorkflow.swift` (waveform
  construction: build the marker model, wire presenter observers)
- Edit `src/swift/app/samplestudio/SampleLoopTools.swift` (loop-handle
  interaction moves to marker ids; analysis behavior unchanged)
- Edit `src/ui/shell/samplestudio/SampleWaveform.qml` (mounts the shared
  model; objectNames and input semantics preserved)
- Edit `src/ui/shell/samplestudio/SampleStudioDialog.qml` (crop/loop handles
  become markers; layout may be redesigned freely within the existing
  objectName contract)
- Edit `src/ui/shell/samplestudio/SampleStudioHost.qml` (rename the type
  reference at line 32)
- Edit `src/swift/app/samplestudio/SampleStudioPresenter.swift` (rate
  computation calls `SampleRatePolicy`; no other presenter change)
- Edit `src/checks/samplecheck/WaveformChecks.swift` (rows target the new
  model; same behaviors)

Precomputed type-rename survey (R24): `SampleWaveformModel` appears in
exactly three QML files — `SampleWaveform.qml:9`,
`SampleStudioDialog.qml:18`, `SampleStudioHost.qml:32` (all in this write
 set) — and in NO check QML (verified: no hit in `src/checks/editorqml`).
`tst_ShellSampleStudio.qml` needs no edit.

Controller-owned: source-list/CMake moves, `checks:bridge` /
`qml-aot` baselines, format.

## Prerequisites

Task 5 (interface only): the `PorydawSampleUI` module exists and compiles.
Task 1 (interface only): `SampleRatePolicy` for the presenter rewire (R16).
Task 1's `SampleZeroCrossing` is NOT consumed here (Sample Studio has no
snap toggle; only Split Studio snaps — do not add one).

## Interface contract

`spec.md → PorydawSampleUI (tasks 5–6)` — the exact
`WaveformMarkerRow` / `MarkerWaveformModel` surface. Pinned behavior:

- Markers are the only handles: grab threshold, cursor feedback and drag
  semantics follow the existing waveform interaction (`SampleWaveform.qml`
  MouseArea contract: press grabs a handle, drag moves it, wheel zooms at
  cursor, middle-drag pans, double-click fits). Marker ids are stable
  across a `setMarkers` call that only moves frames; ids may change only
  when the marker set changes structurally.
- Scene rendering: waveform from the peak pyramid, marker tabs above the
  wave, seam strip (list 1) and playhead unchanged from the current scene
  logic (`SampleWaveformScene.buildMain/buildSeam`) — moved, not redrawn
  from scratch; marker tab visuals may be redesigned (tab shows `label`).
- Viewport/zoom/scroll/fit math is the existing math (ppm/spp clamping,
  `clampView`, user-zoom stickiness) moved into the model; `fit()` restores
  the full-sample view.
- Sample Studio mapping: crop start/end = two `"crop"` markers, loop
  start/end = two `"loop"` markers (loop markers hidden/disabled while
  `loopOn` is false, matching today's loop-handle gating). Presenter
  parameter edits publish through the existing revision pattern
  (`renderRevision` / `sourceRevision` semantics preserved);
  `SampleLoopTools` seam analysis continues to receive the same windows.
- `setSamples` rebuilds the peak pyramid once per source revision;
  parameter-only edits never rebuild it (existing invariant).

## Implementation steps

1. Write the marker model + scene in `src/swift/sampleui/`, moving the
   viewport, pyramid, grab, zoom and scene code from
   `SampleWaveformModel`/`SampleWaveformScene` and replacing the four
   hard-coded handle ids with the marker list.
2. Rewire `SampleStudioWorkflow`: construct `MarkerWaveformModel`, install
   crop/loop markers from presenter state, forward the model to QML via the
   existing `waveform()` accessor (return type changes to the new model;
   the three QML type references and checks follow).
3. Update `SampleLoopTools` to address loop points via the model's marker
   ids; no analysis changes.
4. Migrate `SampleWaveform.qml` + the dialog's waveform section onto the
   model; keep objectNames `sampleWaveformDisplay`, `sampleSeamDisplay`,
   `sampleBrowserSplitter`, and the dialog's Space handling exactly as is.
   Rename the type reference in `SampleStudioHost.qml` (line 32).
5. Rewire `SampleStudioPresenter`'s rate computation to call
   `SampleRatePolicy.targetRate` (R16): the choices/labels stay as they
   are; only the target-rate decision routes through the shared policy.
6. Update `WaveformChecks` rows to construct the new model directly
   (markers replace handle ids); assert: marker grab/drag/release, two
   markers of the same kind do not cross (drag clamps at the neighbor —
   same rule crop/loop pairs have today), zoom/pan/fit math invariants,
   pyramid rebuild only on `setSamples`, marker list publication shape for
   QML delegates.
7. Run nothing (controller owns gates); self-review against the contract.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter samplecheck-editor`
  — waveform + loop-tools rows against the new model; the rest of the
  studio suites prove the workflow rewiring. Covers: marker interaction
  semantics, no-cross rules, pyramid/revision invariants.
- `uv run --no-sync dev checks:shell --filter shell-sample-studio`
  — `ShellSampleStudio::test_dragZoomScrollSplitterAndSpace` proves the
  production QML interaction contract survived the redesign.
- `uv run --no-sync dev checks:shell --filter shell-sample-studio-commit`
  — dialog layout regression around the editor chrome.
- `uv run --no-sync dev checks:bridge` + `uv run --no-sync dev checks:qml-aot`
  — the new bridged model registers cleanly; AOT rejections, if any, are
  justified through a controller-reviewed baseline update.

Runtime prerequisites: none; row count stays ~flat (budget-neutral).

## Task-specific constraints

- The redesign license is for the waveform editor's internals and visual
  layout only; objectNames named above, keyboard/Special-key behavior, and
  the lane-visible interaction order are contract.
- No presenter moves: `SampleStudioPresenter` stays in `PorydawApp`; the
  marker model is presenter-free (values in via `setSamples`/`setMarkers`).
- Do not add slice semantics here: no `"slice"` marker handling beyond the
  kind string passing through; slicing behavior is task 8.
- `SampleStudioAudition` is untouched (task 5 settled it).

## Controller verification

1. Move the deleted sources' CMake lines; add the new ones to
   `src/swift/sampleui/CMakeLists.txt`.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter samplecheck-editor`
3. `uv run --no-sync dev checks:shell --filter shell-sample-studio`
4. `uv run --no-sync dev checks:shell --filter shell-sample-studio-commit`
5. `uv run --no-sync dev checks:bridge`; `uv run --no-sync dev checks:qml-aot`
   (baseline rewrite only for justified intended deltas)
6. `uv run --no-sync dev format --check` on changed lines.
