# Task 7: Scalar conversion sweep

## Context

Consume Task 1's conversion interfaces. This is the remaining mechanical batch, not another overflow-policy design task. Apply the spec's existing per-caller rounding rules and scalar saturation contracts. The missed velocity context sibling is included explicitly. No subsequent task writes these files.

## Exact write set

- `src/ui/pitchbendgraph.cpp`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_gesture.cpp`
- `src/ui/editordrawer/automationprojection.cpp`
- `src/ui/editordrawer/nodelane/pencilgesture.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/songview/pianoroll_gestures_active.cpp`
- `src/ui/songview/quick/automationnodelanequick.cpp`
- `src/ui/songview/quick/velocityquick.cpp`
- `src/ui/songview/quick/voicechangequick.cpp`
- `src/ui/songview/clipmime.cpp`
- `src/checks/automation/automationcanvasediting.cpp`
- `src/checks/automation/automationstroke.cpp`
- `src/checks/rollcheck/presentation.cpp`

## Prerequisites

1: `CoreTimeDefaults::tickFromDouble` and `shiftTickClamped`.

## Interface contract

No signatures or gesture algorithms change. Each listed scalar conversion uses the appropriate helper, preserving its caller's rounding and surrounding domain bounds. `rescaleClip` loses only the identity outer cast around the span calculation; its rescaling and duration limits remain unchanged.

## Implementation steps

1. Replace rounded context conversions in `PitchBendGraph::tickAtFraction` (retain its range clamp), the two playhead-slot operands in voicechangearea, and the context slot in voicechangequick. Include `drawerContextTick` in velocityarea: preserve its `floor(... + 0.5)` nearest behavior rather than replacing it with a new global rounding policy.
2. Replace floor/ceil conversions in automationprojection and nodelane pencilgesture, preserving their boundary ternaries; replace velocityquick's lower floor and upper ceil conversions while retaining its coverage `std::max`. Only drop inner zero clamps whose sole purpose was conversion safety.
3. Replace truncating hover conversions in automationcanvas and automationnodelanequick, and both `m_pressTick` conversions passed to `snapTicksAt` in pianoroll_gestures_active. In `AutomationCanvas::finishActiveGesture`, replace only the two scalar time-selection endpoint shifts with `shiftTickClamped`, retaining the successful-commit, active-selection, and nonempty-range guards.
4. Apply the same caller-owned rounding to the existing probes: `view.playheadTick() + 0.5` in automationcanvasediting, floored `sample.mapping.rawTick` in automationstroke, and the camera far-tick conversion in presentation. Do not rewrite assertions to pin implementation or cast spelling.
5. Remove the identity outer `Tick(...)` in `rescaleClip`'s `result.span = std::max<Tick>(...)` expression. Preserve `scaleTick`, its wide intermediates and maximum argument, and all note/lane duration clamps.

## Acceptance predicate

All listed conversions have defined scalar boundary behavior with unchanged ordinary rounding, surrounding selection/coverage guards, and clip semantics. No identified sibling remains in the closed write set merely because an old site count was satisfied. Named checks:

```sh
deno task verify --filter rollcheck --filter automation-editing --filter automation-domain --filter automation-presentation --filter automation-hover --filter automation-raster --filter velocity-page --filter velocity-editing --filter pitch-bend-editing --filter clipmimecheck --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. This is the sole mechanical file-cap exception. Preserve width-floor probes in `note_rendering.cpp`, double-to-double arguments in `automationvoice.cpp`, `velocityquick.cpp`'s integer `firstTick + 1` coverage expression, variable-bound resize-left clamps, and computed note-end widths. No blanket cast deletion or rounding consolidation. The final full verification gate waits for all tasks, not just this batch.
