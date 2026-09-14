# Context

Cover every Drawer velocity row using the current hovered note and active interaction. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/editordrawer/velocityarea/velocityarea.h`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp`

# Prerequisites

Tasks 4 and 15 (accepted atomic host cutover), Task 17 (live view integration)

# Interface contract

VelocityArea::pointerPress/pointerMove/pointerRelease, notesAt and hovered-note state remain authoritative. Descriptions resolve velocity.detent_unlock through the registry without changing detentsUnlocked.

# Implementation steps

1. Publish note/head selection-click and preserving-selection drag alternatives, Shift ramp, registered detent-unlock drag/paint, and Control right-click/right-marquee operations with their actual buttons.
2. Publish the gutter's exact-chord click-to-set behavior separately; do not inherit the plot's Shift carve-out or Shift-wheel description.
3. Keep press-captured detent and additive-selection decisions unchanged. Reuse existing hover results instead of repeating notesAt queries for hints.
4. Publish through the emitting physical host's setMouseHint, including the separate gutter item. No band-level leave/cancel/detach clears or parallel lifetime state: Task 4 owns release/outside/hide settlement.

# Acceptance predicate

Velocity note/background/gutter transitions expose the correct distinct alternatives and retain selection/detent/editing semantics. NAMED CHECKS: `deno task verify --filter velocity --filter editor-drawer --filter selectionkey-gesture --verbose` (controller), plus velocity Native acceptance.

# Task-specific constraints

Do not copy the roll's release-time Control decision into velocity hints; velocity captures that decision at press.
