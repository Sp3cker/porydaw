# Task 251 brief — Sample waveform: display-list scene, handles, zoom/pan/fit, seam overlay, sample theme roles

# Context

Spec.md: "Waveform interaction includes crop and loop handles, anchored zoom/pan/fit,
processed seam view, display gain, audition playhead and bounded marker relationships." Fork
owner: `WaveformView` (`src/ui/waveformview.{h,cpp}`) plus `SampleDsp::PeakPyramid`
(`sampledsp.cpp` 669–740) and the four sample theme roles (`presetcolors.h` 101–110, values
359–365/419–425/476–482). Swift renders through the existing display-list boundary: Swift
emits snapped rects into `DisplayList` bytes; native code only uploads (AGENTS.md "Native
boundary"). The model consumes 249's gesture API and 250's crossfade; 253 mounts it in QML
and drives the pointer journeys.

Surface: `SampleWaveformModel` (SA03 waveform).
Ledger spec and rows:
- `proof.editor.txt` editorCrossfade A078–A084 → MATCHED (A081 widget lookup retired as in
  249; NATIVE A083–A084 ported: toggling crossfade is one entry and changes the published
  seam windows).
- `src/checks/themelayout/proof.tst_themelayout_color.txt` A039 PARTIAL → MATCHED once the
  legibility predicate covers the five sample pairs across the three themes.
Verify lanes: `samplecheck`, `swiftcore-themecolor`.
Blocked rows left untouched: editorDrag A037–A046 (mounted pointer drag; 253).

# Exact write set

- `src/swift/sample/SamplePeakPyramid.swift` — NEW (fork `PeakPyramid`, block 16).
- `src/swift/sample/CMakeLists.txt` — add the file.
- `src/swift/app/samplestudio/SampleWaveformModel.swift` — NEW `@QtBridgeable` model.
- `src/swift/app/samplestudio/SampleWaveformScene.swift` — NEW display-list builder.
- `src/swift/app/CMakeLists.txt` — add the two files (hot).
- `src/swift/app/timeline/GridPalette.swift` — `sampleWaveformInk`, `sampleCropHandle`,
  `sampleLoopHandle`, `sampleSeamEndInk` fields.
- `src/swift/app/timeline/ThemeColorTables.swift`, `src/swift/app/shell/ShellAppearance.swift`
  — per-mode values from the fork presets (vanilla `#005B63/#92681F/#2A7292/#C54444`,
  dark-neutral-high `#9FCDD7/#E0A030/#4AB4E2/#F08D8D`, immaterial
  `#ABCAD2/#E0A030/#40B0E0/#EF8585`).
- `tools/qtbridge_surface_baseline.json` — via `deno task bridge:baseline`.
- `src/checks/themecolor/ThemeColorPresets.swift` — five legibility predicates
  (`themeLegibilityID`, ≥ 3.0): waveform ink / `menuBackground` (fork `item_background`),
  crop handle / `menuBackground`, loop handle / `menuBackground`, loop handle /
  `alternateBackground` (fork `item_alternate_background`), seam-end ink /
  `alternateBackground`.
- `src/checks/samplecheck/WaveformChecks.swift` — NEW `runWaveformChecks` (MainActor).
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledgers `proof.editor.txt` (rows above), `proof.tst_themelayout_color.txt` A039.

Shared: `GridPalette.swift`/`ShellAppearance.swift`/`ThemeColorTables.swift`/
`ThemeColorPresets.swift` are theme files other tracks may touch — flag before editing.

# Prerequisites

249 (presenter gestures, `processed`, observers), 250 (`setCrossfade`).

# Interface contract

`@QtBridgeable @MainActor public final class SampleWaveformModel`:

- `@QtIgnored init(presenter: SampleStudioPresenter, palette: GridPalette)`.
- Display-list source contract (as `VelocityPage`): `@QtTracked displayRevision`,
  `func displayList(list: Int) -> Data` — list 0 = main view (crop-outside dim, loop tint,
  pyramid min/max columns in `sampleWaveformInk` scaled by display gain, crop grips top band
  in `sampleCropHandle`, loop grips bottom band in `sampleLoopHandle`, playhead), list 1 = seam
  inset (end window in `sampleSeamEndInk` over start window in `sampleLoopHandle`, on
  `alternateBackground`). Background surfaces: main on `menuBackground`.
- QML-callable: `setViewport(width: Double, height: Double)`, `setSeamViewport(width:height:)`,
  `press(x: Double, y: Double) -> Bool` (fork `hitHandle`: crop handles own the top half, loop
  handles the bottom half; tolerance from the fork constant scaled by the base font px/12),
  `drag(x: Double)`, `release()`, `zoom(atX: Double, steps: Double)` (anchored at x),
  `pan(byPixels:)`, `fit()` (double-click), `handleAt(x:y:) -> Int` (for the resize cursor).
  Press/drag/release call `presenter.beginMarkerGesture/dragMarkers/endMarkerGesture`; marker
  clamps are fork `dragHandleTo` 165–189 (crop start < crop end ≤ n, crop end exclusive, loop
  inside the crop, loop start < loop end).
- Swift API: `xForSample(_:)`, `sampleForX(_:)` (fork 93–104), `seamEndWindow`,
  `seamStartWindow` (`[Float]`, fork `refreshOutputs` 687–696 windows ≤ 256),
  `setPlayhead(sourceFrame: Int?)` (252 drives it), `displayGain` (= `processed.normalizeGain`).
- Rendering is allocation-free in steady state: the pyramid is built once per source, scene
  records reuse capacity; colors come from the palette strings parsed once per palette change.

# Implementation steps

1. Pyramid port; theme roles/values; legibility predicates.
2. Model + scene builder; observer refresh on render change; view clamp (fork `clampView`).
3. `WaveformChecks.swift`: x↔sample round trips at several zooms; anchored zoom keeps the
   anchored sample under x; fit shows the whole buffer; handle hit bands with coincident
   markers; clamps; one drag = one presenter entry; crossfade toggle reshapes the seam
   windows (A078–A084); display list decodes (`pd_dl_decode` via `NativeDisplayList`) with
   the expected rect colors for handles/ink.
4. `deno task bridge:baseline`; ledger edits.

# Acceptance predicate

The waveform model maps samples to pixels like the fork, zooms anchored, fits, grabs
coincident handles by band, clamps markers, turns a drag into one undo entry, republishes the
processed seam windows after crossfade, and every sample ink meets 3:1 on its surface in all
three themes.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-themecolor --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

Gap: pixels on screen and pointer delivery are 253's mounted journeys.

# Task-specific constraints

No QML in this task. No native code change (the display-list wire format is reused as is).
Geometry derives from the base font px; no literal pixel constants beyond the fork ratios
expressed relative to it.
