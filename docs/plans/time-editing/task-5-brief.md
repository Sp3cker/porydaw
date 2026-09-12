# Task 5: Unify guarded context menus

## Context

Redirect callers to the canonical command and hide the selection-only helper, preserving selected-range behavior. Tasks 2/3 supply command policy and registry naming; Task 6 consumes the resulting live/stale menu behavior.

## Exact write set

- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview/timeruler_interaction.cpp`
- `src/ui/songview.h`

## Prerequisites

Task 2: selection-aware `insertTime()`. Task 3: `edit.delete_time` registry ID.

## Interface contract

Both menus preserve `InsertBlank` and `RemoveContents` IDs and implement [placement and ownership](plan.md#placement-and-ownership). Reuse `contextShortcutText()` for registry-derived captions and the existing freshness checks in `handleTimeSelectionAction()` / `handleRulerMenuAction()`; SongView's `insertTime()` owns policy. `void SongView::insertBlankTime()` becomes private, with that unified command its sole caller.

## Implementation steps

1. Update the insertion/removal rows in `buildTimeSelectionItems` and `showRulerMenu` to the shared labels and `contextShortcutText` values from the registry IDs.
2. Retarget both InsertBlank dispatches to `insertTime()` only after existing document/revision/span/scope freshness checks. Preserve target consumption and focus-return behavior.
3. Use LSP references to confirm the selection-only helper has no external callers, then move its declaration to the existing private range-edit helpers. Keep ripple-removal dispatch unchanged.

## Acceptance predicate

Both live context menus operate on the selected range and stale targets remain inert, with no public selection-only insertion entry; native smoke meets the plan verification policy. Named checks: LSP helper references; `deno task verify --filter rollcheck --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: redirecting an expired selection to the unified entry could open its whole-song prompt. Existing stale-target guards must precede dispatch on both paths. Keep separators, unrelated rows and ordering; no shared menu registry or broad action-ID rename.
