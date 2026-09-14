# Context

Publish the Timeline inventory roll rows through the physical input-host presentation seam. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/songview/pianoroll_geometry.cpp`
- `src/ui/songview/pianoroll_interaction.cpp`
- `src/ui/songview/pianoroll.cpp`

# Prerequisites

Tasks 4 and 15 (accepted atomic host cutover), Task 17 (live view integration)

# Interface contract

PianoRoll::refreshHoverCursor and pointerMove reuse their current target classification. Preserve beginNotePress, armNoteDrag, applyNotePressSelection, wheel and all gesture algorithms; action descriptions do not change these authorities.

# Implementation steps

1. Publish body versus resize-edge descriptions where the existing note/edge hit is already resolved. Body includes the registered velocity-drag hold plus Control selection-click; an edge never advertises velocity drag.
2. Include Shift right-drag time selection, Control-at-release additive marquee and the plot wheel alternatives. Publish only the wheel alternatives over the piano-key gutter, using its existing surface branch.
3. Publish through the emitting host's setMouseHint, including the actual gutter host. Never use the band QObject as source or clear from band leave/cancel/detach. Preserve originating profiles during actual gestures; Task 4 owns physical release/outside/lifetime settlement.
4. Cache assembled profiles outside per-pixel motion and reuse existing hit results; do not add note searches, selection probes or held-modifier dimensions.

# Acceptance predicate

Roll body/edge/background/gutter transitions advertise only their real alternatives while velocity, resize, selection and wheel behavior are preserved. NAMED CHECKS: `deno task verify --filter rollcheck --filter timelinepancheck --filter selectionkey-gesture --verbose` (controller), plus the roll rows of Native acceptance.

# Task-specific constraints

Keep the press-time velocity chord and release-time marquee decision distinct. Do not edit pianoroll_gestures*.cpp merely to attach informational text.
