# TimeCamera extraction plan

Branch: `feature/time-camera` from `fork-main` @ f45336c
("Phase C: flatten timeline dispatcher into per-band sync methods").
Validated GO-WITH-CHANGES by the Plan agent against this worktree
(2026-09-02). All signatures below are final — implementation agents do
not invent or alter them; deviations go back to review, not into the diff.

## Goal

Give the camera (tick↔pixel mapping + zoom/scroll state machine) a real
interface so agents — and checks — stop navigating `SongView`'s ~120-method
surface to do arithmetic. `SongView` keeps ownership; the interface moves.

Second, measured win: **declaration-site decoupling — not a mass include
flip.** `ui/songview.h` (787 lines) is included by 97 sites; the band
painters' most frequent calls are camera math (`timerulerquick.cpp` 12+
`displayX` sites; `velocityquick.cpp:150-153` re-derives `1/pxPerTick`
by hand because no camera type exists). Classification (2026-09-02):
every painter also uses `document()/timeline()/selectionModel()/grid`
or `SongView` statics, so an include is all-or-nothing and **no
production file drops `ui/songview.h` at Phase 2**. The real wins:
(a) Phase 2 flips the call sites, killing `m_owner.displayX` /
`m_sv->displayX` reach-through; (b) camera declarations move out of
`songview.h`, so camera changes stop recompiling the 97 dependants;
(c) new camera-only TUs include `ui/songview/timecamera.h` (~100
dependency-light lines) instead of `songview.h`.

## Hard rules

1. `TimeCamera` holds **no `SongView *`** and no back-pointer to any
   widget. (`AutomationProjection` is the failed pattern: new name, still
   `const SongView *m_songView` — automationprojection.h:95-97.)
2. The redraw bus stays host-side: scrollbar sync (`updateScrollbars`,
   songview.h:679), `refreshTimelineViews` fan-out (songview.cpp:948-954),
   `refreshDrawerPages`, drawer-interaction cancel, Quick dirty sets.
   Camera mutators *report* change; `SongView` reacts.
3. `viewState()/applyViewState()` (songview.h:147-150) stay on `SongView`;
   `ViewState` is the on-disk format. They read/write `m_camera` through
   the methods below.
4. Grid stays on `SongView` until step 3 (separate branch). Drawer-band
   re-derivation (velocityquick/automationpage/velocityarea) is out of
   scope.
5. Headers allowed in `timecamera.h`: `ui/songview/timeaxis.h`,
   `ui/pitchprojection.h`, `<cmath>`, `<cstdint>`. **No** Qt, no
   `miditimeline.h`, no `quick/timelineinput.h`, no `SongView`.
   (`pitchprojection.h` is Qt-free today; it must stay so.)

## The type — exact header

`src/ui/songview/timecamera.{h,cpp}`, namespace `songview`.

```cpp
#pragma once

#include <cstdint>

#include "ui/pitchprojection.h"
#include "ui/songview/timeaxis.h"

namespace songview {

// Zoom/scroll camera for one song tab: the tick<->pixel mapping shared by
// ruler, roll, strip, drawer, and quick scene. SongView owns it and pushes
// widget facts in (viewport, limits); the camera never pulls widgets and
// never notifies anyone — mutators report change, the host redraws.
class TimeCamera
{
  public:
    struct Limits {
        double minPixelsPerBeat = 16.0;
        double maxPixelsPerBeat = 1024.0;
        double minKeyHeight = 4.0;
        double maxKeyHeight = 64.0;
        double revealViewportFraction = 1.0 / 3.0; // ensureTickVisible anchor
    };
    struct ZoomResult {
        bool zoomChanged = false;
        bool scrollChanged = false;
    };

    // axis and projection are stable SongView members (songview.h:742-743);
    // the camera holds references and never rebinds. Axis rebind-to-timeline
    // (songview.cpp:342, 451) and projection rebuilds flow through in place.
    explicit TimeCamera(const TimeAxis &axis, const PitchProjection &projection);

    // host pushes; camera caches and uses these in clamps/pads
    void setLimits(const Limits &limits);
    void setViewport(double widthPx, double rollHeightPx);

    // map (pure)
    double pxPerTick() const noexcept;   // pxPerBeat() / axis.ticksPerBeat()
    double pxPerBeat() const;
    double scrollX() const;              // new getter: viewState().scrollPx,
                                         // drawercoordination.cpp:150,
                                         // scrollbar value sync
    double scrollY() const;
    double keyHeight() const;
    double contentX(double tick) const;          // tick * pxPerTick - scrollX
    double tickAtContentX(double x) const;        // (x + scrollX) / pxPerTick
    double displayX(double tick, double origin, double dpr) const;

    // bounds (derived from cached viewport/limits/axis/projection)
    double leadPadPx() const;  // round(viewportWidth * 0.10) clamped [48, 256]
    double minHScroll() const; // -leadPadPx()
    double maxHScroll() const; // axis.isBound() ? lengthTicks * pxPerTick : 0
    double maxRollScroll() const; // max(0, projection.totalHeight(keyHeight)
                                   // - rollHeightPx)

    // mutate — return camera-changed; host owns every redraw tail.
    // All clamp internally. Unanchored setters are the session-restore path.
    bool setHScroll(double px);
    bool setVScroll(double y);
    bool scrollByPx(double dx);   // horizontal
    bool scrollRollBy(double dy); // vertical
    bool setTimeZoom(double pxPerBeat);           // no anchor, scroll kept
    bool setKeyHeight(double keyHeight);          // no anchor
    ZoomResult zoomAroundContentX(double factor, double anchorContentX);
    bool zoomKeyHeight(double factor, double anchorY);
    bool ensureTickVisible(uint64_t tick, double dpr);
    bool ensureRangeVisible(uint64_t startTick, uint64_t endTick,
                            bool preferEnd, double dpr);
    bool ensureKeyVisible(int key); // uses ctor projection; cHiddenRow -> false

  private:
    const TimeAxis &m_axis;
    const PitchProjection &m_projection;
    Limits m_limits;
    double m_viewportWidth = 0.0;
    double m_rollHeight = 0.0;
    double m_pxPerBeat = 0.0;
    double m_scrollX = 0.0;
    double m_scrollY = 0.0;
    double m_keyHeight = 0.0;
};

} // namespace songview
```

Implementation notes (bodies move from `src/ui/songview/camera.cpp`, 253L;
do not rewrite math):
- `displayX` keeps the physical-pixel rounding:
  `origin + contentX`, `dpr > 0 ? round(x * dpr) / dpr : x`.
- `logicalPhysicalPixel(dpr)` moves to an anonymous-namespace helper in
  `timecamera.cpp` (used by ensure*Visible).
- Wheel-delta → factor conversion stays in the `SongView` wrappers
  (existing `songview::detail::wheelAngleUnits`), so the camera takes a
  plain `factor`: `pow(1.0015, units)` for time, `exp2(units / 1200)` for
  key height (camera.cpp:43-48, 77-78).
- Deletions from the validated sketch, with rationale: `bindTimeAxis`
  and `setRollContentHeight` (stable-member references make them
  un-desyncable; `m_projection` is never reassigned, songview.h:743);
  `ensureKeyVisible(key, projection)` per-call param (same reason);
  `wheelZoomDelta` static (keeps `timelineinput.h` out of the header).

## SongView wrappers — exact post-extraction bodies

Existing public/private API and names are unchanged in step 1; bodies
delegate. Keep every existing guard and unconditional tail; only the
listed parts change. Fields `m_pxPerBeat/m_scrollX/m_scrollY/m_keyHeight`
(songview.h:750-753) are deleted; state lives in `TimeCamera m_camera`
(declared after `m_timeAxis` and `m_projection`).

| Wrapper (file:line today) | New body shape |
|---|---|
| `setEditorHorizontalScroll(px)` camera.cpp:20 | `{ setHScroll(px); }` — **must keep host delegation**: direct `m_camera.setHScroll` would skip scrollbar sync and redraw fan-out owned by the private `setHScroll` wrapper |
| `setEditorTimeZoom(v)` camera.cpp:24 | keep `if (!m_timeline) return;` in wrapper; `const bool z = m_camera.setTimeZoom(v); if (z && m_editorDrawer) m_editorDrawer->cancelVisiblePageInteraction(); updateScrollbars(); refreshTimelineViews(cPlotDirty); refreshDrawerPages();` (tails stay unconditional, as today) |
| `zoomTimelineAtWheel(wheel, anchor)` camera.cpp:43 | `zoomAroundContentX(pow(1.0015, detail::wheelAngleUnits(wheel)), anchor)` |
| `zoomAroundContentX(f, a)` camera.cpp:49 | keep `if (!m_timeline) return;`; `const auto r = m_camera.zoomAroundContentX(f, a); if (r.zoomChanged && m_editorDrawer) m_editorDrawer->cancelVisiblePageInteraction(); updateScrollbars(); refreshTimelineViews(cPlotDirty); refreshDrawerPages();` (cancel keys on the zoom leg only — camera.cpp:60-61) |
| `zoomKeyHeight(input)` camera.cpp:70 | keep timeline/momentum/zero-delta guards; compute factor `exp2(units/1200)` and anchor from event Y; `if (!m_camera.zoomKeyHeight(factor, anchorY)) return;` then exactly `m_roll->refreshTextLayout(); updateScrollbars(); m_roll->requestQuickUpdate(PianoRollQuickDirty::All); refreshDrawerPages();` — anchor+clamp already happened atomically in the camera; **no second `setVScroll` or anchor calculation** |
| `scrollByPx/scrollRollBy` camera.cpp:95-102 | pass `m_camera.scrollByPx(dx)` / `scrollRollBy(dy)` result to the host sync helpers below |
| `setHScroll(px)` camera.cpp:103 | `syncHorizontalCamera(m_camera.setHScroll(px));` |
| `setVScroll(y)` camera.cpp:129 | `syncVerticalCamera(m_camera.setVScroll(y));` |
| private host sync helpers | add exact signatures `void syncHorizontalCamera(bool cameraChanged);` / `void syncVerticalCamera(bool cameraChanged);`; each **always** synchronizes its scrollbar value from `m_camera.scrollX()/scrollY()` (required after range/page-step changes), and only gates redraw/Quick tails on `cameraChanged` |
| `ensureTickVisible(t)` camera.cpp:180 | pass `m_camera.ensureTickVisible(t, effectiveDpr)` to `syncHorizontalCamera` |
| `ensureRangeVisible(s,e,preferEnd)` camera.cpp:190 | pass camera result to `syncHorizontalCamera`, wrapper passes effective dpr |
| `ensureKeyVisible(key)` camera.cpp:211 | pass camera result to `syncVerticalCamera` |
| `minHScroll/maxHScroll/maxRollScroll/leadPadPx/pxPerTick/pxPerBeat/scrollY/keyHeight/contentX/tickAtContentX/displayX` songview.h:213-226, 674-677 | inline `{ return m_camera.<same>(); }` |
| ctor songview.cpp:203-208 | init-list camera defaults move to `TimeCamera` member init; `m_scrollX = minHScroll()` at :309 becomes `m_camera.setHScroll(m_camera.minHScroll())` |
| `defaultVerticalScroll` songview.cpp:379 | unchanged (uses projection + viewport via SongView queries that now delegate) |
| `updateScrollbars` songview.cpp:147-162 equiv. | **first line:** `m_camera.setViewport(double(viewportWidth()), double(rollViewportHeight()));` then existing range/page-step logic reading camera getters |
| viewstate.cpp:150-176 | `m_scrollY` direct write + clamp becomes `m_camera.setVScroll(...)`; `maxRollScroll()` read delegates |

## Restore path (applyViewState, songview.cpp:658-689) — exact sequence

```cpp
// wrapper, replacing lines 667-684:
const double pxPerBeat = std::clamp(state.pxPerBeat, ...); // keep, or move
// the clamp into camera.setTimeZoom (it clamps anyway) and pass raw
const bool zoomChanged = m_camera.setTimeZoom(pxPerBeat);
const bool gridChanged = ...;                         // unchanged logic
if ((zoomChanged || gridChanged) && m_editorDrawer)
    m_editorDrawer->cancelVisiblePageInteraction();   // still before tails
(void)m_camera.setKeyHeight(state.keyHeight);        // clamps internally
m_roll->refreshTextLayout();
setGridMinDenom(...); setGridFeel(...); selectTrack(...); // unchanged
updateScrollbars();                                   // pushes viewport
setHScroll(state.scrollPx);   // camera clamps to range — comment at :683 stands
setVScroll(state.scrollY);
```
No unclamped adopt path exists or is needed: restore flows through the
same clamped mutators, so a restored state can never violate camera
invariants.

## Invariants (reviewer checks these)

1. **Viewport push rule:** every path that changes roll width, drawer
   height, or widget layout must push `setViewport` before camera math.
   Convergent sites: `updateScrollbars` (first line), resize/layout
   handling. This is the one semantic delta (live widget reads → cached
   push); `viewportWidth()/rollViewportHeight()` stay on `SongView` as
   the feeders (songview.h:670-671).
2. Zero behavior drift: `deno task verify` output identical; rollcheck
   camera harness (anchored zoom, clamps, DPR raster, key-height
   round-trips) and automationgesturecheck zoom sweeps are the contract.
3. No new public `SongView` camera methods beyond today's set.
4. `timecamera.h` include list exactly as in Hard rule 5.
5. `grid.cpp` compiles unchanged (reads `pxPerTick()/pxPerBeat()` via
   delegates).

## Phases — implementation + sign-off protocol

Every phase ends with a **sign-off gate by the same
`thermo-nuclear-reviewer` agent** (spawn once as `TimeCameraReview`).
The gate agent is NOT respawned per phase: after its first report it is
parked and revived by name (`hub send` to `TimeCameraReview`) so the
same reviewer that raised a finding is the one who confirms it is
resolved. A phase is done only when it signs off with zero unresolved
findings; its findings list carries into the next gate.

Gate protocol, identical each phase:
1. Implementer finishes the phase, runs `deno task verify` +
   `deno task format --check`, reports the diff summary.
2. Dispatch/revive `thermo-nuclear-reviewer` as `TimeCameraReview` with:
   the phase diff, the Invariants section above, and (phases 2+) the
   previous phase's findings list to re-check for resolution.
3. Findings are fixed on the same branch; the same agent re-reviews until
   it returns explicit sign-off.
4. No phase-2+ work starts before the previous phase's sign-off.

### Phase 1 — extract the type (implementer: `task`)
- Create `timecamera.{h,cpp}` per the exact header above; move bodies
  from `camera.cpp`; apply every wrapper shape in the table.
- Route direct state writers: viewstate.cpp:150-176, songview.cpp:309,
  646-649, 667-684 (assembly reads become `m_camera.*` getters).
- Delete the four members from `songview.h:750-753`.
- Zero child/check churn. Includes unchanged (phase 2 does includes).
- Implementer verify: `deno task verify` (full), `deno task format
  --check` on touched files.
- Gate 1 (`TimeCameraReview`): the five Invariants, header allow-list,
  wrapper-table fidelity — especially the `zoomKeyHeight` wrapper row vs
  current camera.cpp:70-94 (anchor+clamp moves inside the camera,
  tail order preserved).

### Phase 2 — call-surface cutover (implementer: `sonic`)
- Children (`PianoRoll`, `TimeRuler`, headers, strip) and quick-scene
  painters take `const TimeCamera &` (from a `SongView::camera()`
  accessor or existing owners) for mapping reads. Call sites flip:
  `m_owner.displayX / m_sv->displayX / owner.tickAtContentX` →
  `m_camera.*`. Files: `timelinequickscene.cpp`,
  `timelinequickview_pianoroll.cpp`, `timerulerquick.cpp`,
  `voicechangequick.cpp`, `otherstripquick.cpp`, drawer bands.
- **Includes do NOT flip wholesale** (classification 2026-09-02: every
  painter also uses `document()/timeline()/selectionModel()/grid/`
  statics, so `ui/songview.h` stays). A file drops the include only if
  camera was its sole `SongView` reference — expect none; measure,
  don't assume. If a file qualifies, flip it to
  `ui/songview/timecamera.h`; otherwise leave the include.
- `AutomationProjection`: mapping goes through `const TimeCamera &`;
  its `SongView *` survives for `timeline()`/grid delegates until
  Phase 3 removes the grid leg. The include stays until then.
- `velocityarea_interaction.cpp:351`, `voicechangearea.cpp:431`:
  `viewState().scrollPx` → `camera().scrollX()` (call-site fix only;
  both files keep `songview.h` for their other uses).
- Checks migrate (~35 files / ~150+ sites) one file per pass.
- After cutover: delegating `SongView` methods with zero remaining
  callers are deleted (grep-verify before each deletion; `viewState()`
  and serialization entries legitimately stay).
- Implementer verify (measured, not assumed): zero camera-method
  reach-through outside `SongView` itself —
  `grep '\(m_sv\|m_owner\|owner\)\.\(displayX\|tickAtContentX\|contentX\|pxPerTick\|pxPerBeat\|scrollY\|keyHeight\)'`
  under `src/ui` returns only `SongView`'s own TUs; include count
  recorded (expected: ~97, minus any camera-only qualifiers — likely 0);
  `deno task verify`; `deno task format --check`.
- Gate 2 (same `TimeCameraReview`): reach-through grep is clean, all
  Gate-1 findings confirmed resolved, deletions did not orphan callers,
  every surviving `ui/songview.h` include is justified by a non-camera
  use.

### Phase 3 — separate branch: Grid type (implementer: `task`)
- Only after Phase 2 sign-off. `Grid = f(TimeAxis, TimeCamera,
  feel/minDenom)`; `snapTick*`, `gridTicksAt`, `visibleGridCell*` from
  `grid.cpp`. Takes `TimeCamera &`, never `SongView*`.
- Gate 3 (same `TimeCameraReview`): Grid invariants — no `SongView*`,
  `grid.cpp` behavior byte-identical, checks pass.

## Explicitly rejected / out of scope

- **Raw wheel normalization inside `TimeCamera`.** `TimelineWheelInput`
  carries Qt input-adapter facts (`QPoint` pixel/angle deltas,
  `Qt::ScrollPhase`, modifiers, and device inversion). Moving that type or
  its momentum/device interpretation into the camera would either violate
  the Qt-free header rule or duplicate Qt event vocabulary behind a nominally
  pure interface. The timeline input/SongView adapter converts raw wheel
  input to a dimensionless zoom factor; `TimeCamera` owns applying that
  factor at an anchor, including zoom limits and scroll clamping. This keeps
  alternate inputs such as keyboard commands or future pinch gestures from
  pretending to be wheel events.
- Narrow `EditorSession` port; intent-emission for mutations; observer
  callbacks on the camera (children keep mutating through `SongView`
  wrappers — a scroll moves every band, so host mediation is the real
  dataflow, not reach-through).
- Naming campaign, synonym cleanup, `TimelineQuickView` dirty-bit
  lockstep, member moves, drawer-band camera dedup.
- One-commit clean cutover (~60 files) — staged; step 2 may land as its
  own commit series (children first, checks after).

## Evidence index

- Plan-agent validation report 2026-09-02 (TimeCameraPlanValidation),
  against this worktree: GO-WITH-CHANGES; Phase C per-band sync
  (timelinequickview.h:144-151) leaves uniform mutator tails.
- Include coupling: 97 `ui/songview.h` include sites under `src/`
  (grep 2026-09-02); painter usage enumerated in Goal.
- Restore path: songview.cpp:640-689 (viewState/applyViewState exact).
- Migration surface: production ~25 files/~90 sites; checks ~35
  files/~150+ sites.
