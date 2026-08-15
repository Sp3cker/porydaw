# Peel 09 — Meter-aware grid stepping + radius-based value detent in the lanes

Read `docs/peels/GROUND-RULES.md` first. Small peel. Target: main's
`AutomationArea` sweep/line generation (`extendSweep`, the Line commit loop in
`mouseReleaseEvent`) in `src/ui/songview.cpp`. Source: branch
`automationpage.cpp:301-334` (`nextGridTick`, `snapTickDown`),
`automationgesture.h:154-236` (templated point generation),
`automationgesture.cpp:170-189` (`updateValuePoint` neutral snap); harness
`src/rollcheckautomation.cpp:294-382`.

## Fix 1 — sweeps and ramps across a meter change

Main's generators step a fixed grid: `for (t = a; t < b; t += g)` with
`g = gridTicksAt(a)` — when the time-signature (and thus grid spacing) changes
inside the swept range, points land off the new meter's grid. The branch's
`nextGridTick` binary-searches the grid so each successive point lands on the
first tick of the CURRENT grid cell after the boundary. Port that stepping into
both main's `extendSweep` cell walk and the Line-ramp commit loop (and the ramp
still emits its final endpoint exactly at b). Pure lane-local change; the roll's
note snapping is out of scope.

## Fix 2 — Ctrl neutral detent gets a radius

Main's Ctrl detent (`updateDrag`) magnetizes to the lane's neutral within a
hard-coded ~8px window. The branch computes the window from geometry:
`span * neutralSnapRadius / rowHeight` value-units, with neutral 0 for bend and
64 for CC 10/24 (branch `automationgesture.cpp:170-189`). Port the
geometry-derived radius (DPI/font-scaled via `layout::`) so tall lanes don't get
a proportionally huge magnet and short lanes an unusable one. Behavior parity
with main at default lane height should be approximately preserved — check and
state the before/after windows.

## Explicitly exclude

- `AutomationGridCell` / `snapCellsCrossed` machinery — pencil-stroke plumbing on
  the branch; main's pencil (already ported) uses main's sweep and doesn't need it.
- Any `AutomationProjection`/`AutomationPage` structure.

## Tests

- rollcheck: author a mid-song time-signature change in the scratch song (or via
  the document API), sweep across the boundary → every committed point sits on
  its side's grid (assert tick % expected grid per side); Shift-line ramp across
  the boundary → same, endpoint exact at release tick; Ctrl detent: press near
  neutral within the computed radius → snapped, just outside → not (probe both
  sides of the boundary, at two lane heights).
- Adapt branch harness :294-382. Negative-test each probe (restore `t += g` →
  meter probe fails; drop radius → detent probe fails). SF 1/1.5/2; ASAN sweep +
  ctest; CHANGELOG.
