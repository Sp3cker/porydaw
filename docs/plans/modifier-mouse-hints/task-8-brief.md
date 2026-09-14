# Context

Cover track body/voice scope actions, their no-hint controls and the rename text target. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/songview/trackheadermodel.h`
- `src/ui/songview/trackheadermodel.cpp`
- `src/ui/songview/quick/TrackHeaderBand.qml`

# Prerequisites

Tasks 4 and 15 (accepted atomic host cutover), Tasks 16 and 17 (Quick group and scope integration)

# Interface contract

TrackHeaderModel::rowAt/hitTarget/pointerMove remain the geometry authority; SongView::trackHeaderClicked remains the action authority. TrackHeaderBand TextInput owns rename hover.

# Implementation steps

1. Publish Control toggle-scope and Shift range-selection over body/voice targets, preserving Control precedence rather than inventing an additive Control+Shift range.
2. Replace body text with an empty profile over mute/solo/add-track targets. Use the existing target state; do not inspect current scope/solo/mute enablement.
3. Put one HoverHint on the actual rename editor group. Its passive hover claim excludes the underlying C++ input; use the existing editor geometry and text-selection behavior, not competing parent/child publishers. Verify stationary rename show/hide and first real re-entry.
4. The model publishes only through its physical host; no band-level leave/cancel/detach clears. Preserve reorder/reveal/meter behavior. A lower host's scope resync cannot bypass its lost hover membership.

# Acceptance predicate

Header target transitions distinguish scope selection from controls and rename text while preserving existing click/reorder behavior. NAMED CHECKS: `deno task verify --filter trackheader --filter selectionkey --verbose` (controller), plus header Native acceptance.

# Task-specific constraints

Do not change QAbstractItemModel row/data contracts or add a second row hit-test in QML.
