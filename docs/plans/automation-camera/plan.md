# Automation camera

`AutomationPage` re-derives tick↔pixel math from the pushed `DrawerPageLiveState` snapshot while `VelocityArea`/`VoiceChangeArea` read the live `songview::TimeCamera`. Bind the page to `owner.camera()` and delegate, deleting the duplicated formula. No behavior change: snapping, row model, value mapping, Quick layers, `ready()` gating, and refresh routing are untouched.

## Behavior

- `AutomationPage::tickAtContentX`, `displayX`, and `pxPerBeat` return the camera's values for all bound timelines.
- Wheel/pan scroll-request bases in `AutomationCanvas` use the live camera instead of the last pushed snapshot; pan stays absolute-from-press.
- `AutomationPage::Geometry`, `m_geometry`, and the `fontPx(8/3)` fallback constant are gone; `AutomationProjection` (both ctors, both branches) is unchanged.
- Non-goals: no `TimeCamera` API change, no `Grid`/snap change, no Quick-layer change, no `refreshLiveState` routing change.

## Tasks

| Task | Requirement | Route | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Bind AutomationPage to TimeCamera](#task-1--bind-automationpage-to-timecamera-direct) | Direct | Mechanical, reversible, closed 3-file set, single predicate | None |

### Task 1 — Bind AutomationPage to TimeCamera (Direct)

**Target.** `src/ui/editordrawer/automationpage.h`, `src/ui/editordrawer/automationpage.cpp`, `src/ui/editordrawer/automationcanvas_input.cpp`. Closed list.

**Change.**
1. Header: forward-declare `songview::TimeCamera` (mirror `velocityarea.h`); add `const songview::TimeCamera &m_camera;` adjacent to `m_grid`; declare private `double scrollX() const noexcept` beside `pxPerBeat` (mirror the `SongView::scrollY` wrapper convention). `AutomationCanvas` is already a friend, so the wrapper needs no access change.
2. Ctor: initialize `m_camera(owner.camera())` after `m_grid(owner.grid())`; drop the `m_geometry` init.
3. Bodies, signatures unchanged: `tickAtContentX` delegates to `m_camera.tickAtContentX`; `displayX` to `m_camera.displayX`; `pxPerBeat` to `m_camera.pxPerBeat`. Delete `Geometry::resolve`, `struct Geometry`, `m_geometry`, and the now-unused `ui/layout.h` include (sole `layout::` use is the deleted fallback); include `ui/songview/timecamera.h` directly for the new dependency. Comment at `liveState()` that the snapshot serves row/model decisions and refresh routing while x-mapping reads the camera live.
4. Input: replace `m_page.liveState().horizontalScroll` with `m_page.scrollX()` at the two wheel request bases (`AutomationCanvas::wheel`) and the middle-button pan capture (`m_pan.startHScroll`). Pan move stays absolute-from-press; wheel branch structure, the `ready()` gate, and zoom anchoring unchanged.
5. Do not touch: `ready()`, `snapTick`/`snapTickDown`/`nextGridTick` (still `m_grid`), `sameLiveState`/`refreshLiveState`, `AutomationProjection`, any check or fixture.

**Acceptance.** Camera-derived automation geometry is unchanged end-to-end: `deno task verify --filter automation --filter host-adapter --filter host-integration --filter laneselectioncheck --verbose`.

## Global Constraints

- Every task inherits this section. Write sets are closed; preserve unrelated changes. Refresh source sections before editing. An unlisted production file the compiler names is a plan defect — escalate, do not expand.
- No second mapping convention: do not keep a snapshot fallback beside the camera, do not branch on push freshness, do not write back into `m_liveState` from input handlers.
- Use `deno task` for format/build/harness. Implementers reuse the Verification policy commands without repeating discovery; reassess only if the change alters scope or a command proves stale or unavailable, reporting the concrete mismatch.

## Verification policy

Controller (or implementer, single Direct task — run once after settling):

`deno task verify --filter automation --filter host-adapter --filter host-integration --filter laneselectioncheck --verbose`

- `--filter automation` (substring): `automation-editing` (pencil quantization, node drag commit/escape, cross-lane paste clamps), `automation-raster` (curve/node rendering, hover ghost, drag preview), `automation-presentation` (plot switching, scale labels via the `pxPerBeat`/`nodeMarkersVisible` path), `automation-hover` (grab/hover mapping), `automation-domain` (point resolution, snap). Check expectations are camera-derived (`view.camera().displayX(...)` round-tripped through the page projection), so they prove delegation preserves geometry.
- `--filter host-adapter`: automation pan routing — covers the wheel/pan request-base change.
- `--filter host-integration`: automation pan end-to-end.
- `--filter laneselectioncheck`: zoom/scroll hit tests over the untouched SongView-mode projection branch — regression only.

Coverage gaps (no harness, by design): unbound-timeline mapping values (fallback `1.0` → axis `24`) — unreachable through the preserved `ready()` gates with empty unbound rows; verified by gate preservation, not a check. Sub-ULP FP association differences pre-round — single formula post-cutover, nothing to assert against.

## Checkpoints

No commit is authorized by this plan. Single task, no cross-task file reuse: final handoff only, when the user authorizes persistence.

## Source anchors

| Owner | Current |
| --- | --- |
| `AutomationPage::tickAtContentX/displayX/pxPerBeat` (`src/ui/editordrawer/automationpage.cpp`) | snapshot formula over `m_liveState` + `timeline()->ticksPerBeat` + `m_geometry` fallback |
| `AutomationPage::m_grid` (`src/ui/editordrawer/automationpage.h`) | bound to `owner.grid()`; camera member absent |
| `AutomationProjection::rawTickAt/displayX` (`src/ui/editordrawer/automationprojection.cpp`) | page branch delegates to page; SongView branch reads camera pointers |
| `AutomationCanvas::wheel` / pan capture (`src/ui/editordrawer/automationcanvas_input.cpp`) | request bases from `m_page.liveState().horizontalScroll` |
| `SongView::drawerPageLiveState` (`src/ui/songview/drawercoordination.cpp`) | pushes `timeZoom ← pxPerBeat()`, `horizontalScroll ← scrollX()` — snapshot is a past camera |
| Reference shape (`velocityarea.cpp`, `voicechangearea.cpp`) | `m_camera(owner.camera())`; pan re-reads `m_camera.scrollX()` |
