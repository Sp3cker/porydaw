# Phase 4 — Drawer pages on the native renderer

Plan: `docs/old/native-timeline-renderer/plan.md` (blob table rows 1, 3, 7, 11; Decision 7; §8 phase 4).
Precedent (done, committed 0142cbba): velocity page Swift content — brief
`docs/old/native-timeline-renderer/task-4v1-brief.md`, writer
`src/swift/app/drawer/DrawerStaticsContent.swift`, shared framing
`src/swift/app/timeline/DrawingContentBinary.swift`, decoder check
`src/checks/velocity/VelocityContentProbe.swift`, `VelocityPage.contentRevision` + `drawingContent()`.
Prior art: pre-Swift C++ drawers in `/Users/sallegrezza/dev/cProjects/porydaw/src/ui/songview/quick/`
(`velocityquick.cpp`, `voicechangequick.cpp`, `automationquick.cpp`, `automationnodelanequick.cpp`).

## Rulings (carried from 4v1)

- D1 Grid lines never ship as §11 rects: the page blob carries §7 timeAxis and the renderer generates
  lines per frame over the visible range. Never enumerate over the song span.
- D2 §11 records are tick-space (`tickStart`/`tickEnd`), plot-local y/h; count bounded by document
  data, never by tick span. `pxSpace` (bit0) only for camera-free value-axis lines. `dashedFrame`
  (bit2) = renderer draws a device-px dashed outline; fill and frame are separate records.
- D3 `contentRevision` is equality-gated (bumps only when blob bytes change); scroll and zoom never
  enter records or the revision. Where content truly depends on zoom (automation curve segment
  quantization), keep it and state it with evidence.
- D4 Dual publication until the QML cutover: keep the existing QListModels and the page QML untouched
  in the Swift task.
- D5 Interactive items stay QML (velocity handles, automation nodes, voice markers, other-events
  diamonds, all drawer text).

## Task 4c — Voice changes Swift content (sdd-implementer)

Write set: `src/swift/app/drawer/voicechanges/*`, `src/swift/app/drawer/DrawerStaticsContent.swift`
(generalize its packer only if needed, keeping velocity bytes identical), `src/checks/voicechanges/`
or the existing voice-change check file (decoder reuse: extend `VelocityContentProbe` into a shared
drawer probe only if it stays one file). Layers: `gridLines` → §7, `heldSpans`
(`VoiceChangesPage.swift:174`) → §11. `VoiceChangesPage` gains `contentRevision` + `drawingContent()`.
Checks: scroll/zoom leave bytes+revision unchanged; a voice-change edit bumps once and the decoded spans
match the fixture.

## Task 4m — Automation Swift content (sdd-implementer)

Write set: `src/swift/app/drawer/automation/*`, automation checks under `src/checks/automation/`.
Layers (`AutomationPage.swift:117-127`): `gridLines` → §7; `valueLines` → §11 `pxSpace` rows;
`curveRuns`, `selectionRects`, preview rects → §11 tick-space horizontal runs and §12
`drawerAnchored` for fixed-width tick-anchored vertical edges and preview nodes.
`drawerAnchored`: `u32 count`; per record `u32 tick, f32 dx, f32 width, f32 y, f32 h,
u32 argb, u8 flags` (bit0 snapDevicePx). x = project(tick) + dx, width is logical px.
Sections paint in blob order, records in record order; §11 and §12 may repeat.
Emit axis, curves, selection, preview in that z-order.
Curve segments derive from lane point ticks (`AutomationProjection.swift:269-286`), not zoom or scroll; viewport clipping
and device snapping happen in the renderer. Zoom and scroll do not change blob bytes
or revision. `AutomationPage` gains `contentRevision` + `drawingContent()`. Same check shape as 4c.

## Task 4a — Renderer band 3 (sdd-implementer, after phase 3 C++)

Write set: `src/render/*`. `band: 3` draws a drawer blob: §3 palette slots, §7 grid (reuse the roll
grid builder), §11 records (fill, `pxSpace`, `dashedFrame` using §1 stroke/dash/gap), camera =
`pixelsPerTick`, `scrollX`, dpr only.

## Tasks 4v2/4c2/4m2 — QML cutovers (sdd-implementer, after 4a + the page's Swift task)

One page per task: `VelocityPage.qml`, `VoiceChangesPage.qml`, `AutomationPlot.qml`. Replace the
static rect layers with `TimelineRenderer { band: 3; contentSource: <page> }`; delete the page's
legacy static QListModels and their Swift publication; interactive layers unchanged.

## Tasks 4x — Drawer checks migration (qt-check-fixer, per page)

Migrate readers of the deleted models; keep message literals; report changes.

## Verification (controller)

`deno task build:checks`; `deno task checks --filter swiftcore --verbose`; `deno task checks:qml --verbose`;
`deno task checks:shell --verbose`; `deno task proof check --executed`.

## Global constraints

Swift 6, QML, C++ only in `src/render/`. No code comments. Geometry from base font px. No workarounds;
report instead. Scoped searches. No commits. Do not run `deno task` commands unless told you may.
New Swift files: register in `src/swift/app/CMakeLists.txt` / `src/checks/CMakeLists.txt` and say so.
