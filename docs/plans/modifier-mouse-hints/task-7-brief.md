# Context

Publish the Timeline inventory ruler rows without changing time-selection or marker semantics. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/songview/timeruler.h`
- `src/ui/songview/timeruler.cpp`
- `src/ui/songview/timeruler_interaction.cpp`

# Prerequisites

Tasks 4 and 15 (accepted atomic host cutover), Task 17 (live view integration)

# Interface contract

TimeRuler::pointerMove reuses hitMarker, hitTimeSigChip and hitSelEdge with pointerPress precedence. Private presentation state/helpers may be added only to TimeRuler; public gesture APIs remain unchanged.

# Implementation steps

1. Publish Control multi-track sweep only over the background that actually begins a sweep, retaining the primary-track-plus-intersecting-notes meaning.
2. Publish Shift wheel horizontal scrolling on the ruler, including handles; do not invent Control-wheel or modifier variants for consumed marker/signature/selection-edge drags.
3. Publish through the physical host's setMouseHint using existing classification and cached phrases. Bands never clear ownership; Task 4 owns leave/ungrab/hide/detach. Do not re-run selection discovery.

# Acceptance predicate

Ruler background and handle transitions produce the appropriate distinct hint profiles without changing time-selection scope or marker/signature editing. NAMED CHECKS: `deno task verify --filter rollcheck --filter timelinepancheck --filter selectionkey-gesture --verbose` (controller), plus ruler Native acceptance.

# Task-specific constraints

The hint must not enumerate tracks or inspect whether a multi-track sweep would currently change selection.
