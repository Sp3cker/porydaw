## 1. Context

The inactive automation time-selection fallback has its own Clear row; unlike the active selection path, it does not use SongView’s row producer. Task 19 supplies the adapter. This task migrates that equivalent command and gives this shared lane/fallback host a precise retirement gate.

## 2. Exact write set

- `src/ui/editordrawer/automationcanvas_menu.cpp`
- `src/checks/automation/automationmenus.cpp`

## 3. Prerequisites

- [Task 10](task-10-brief.md).
- [Task 11](task-11-brief.md).
- [Task 19](task-19-brief.md).

## 4. Interface contract

The inactive fallback ClearTimeSelection row uses QuickMenuItem::fromAction with the canonical ClearTimeSelection QAction and its existing typed CanvasMenuAction ID. Gate selection/cursor invalidation on session ownership and the root model containing that typed ClearTimeSelection row, not translated text; ordinary lane menus sharing the host/model keep their independent lifetime. Existing document/lane teardown protection remains. Track/controller identities and half-open time/tempo scope stay authoritative.

## 5. Implementation steps

1. Project the inactive fallback Clear row from the canonical action (disabled without an active time interval). Remove only the fallback’s PendingMenu population and its now-unreachable local ClearTimeSelection execution case; retain the lane menu’s real pending target and handlers.
2. Subscribe once to context invalidation and cancel only an owned fallback identified by its typed row. Preserve unrelated lane menus across selection-only changes and do not cancel foreign forms or value drafts.
3. Use existing automation menu scenarios to prove disabled fallback activation does nothing, selection changes dismiss it, and lane menu lifetime stays independent. Active selected-range Clear continues through SongView’s producer and is migrated by Task 26.

## 6. Acceptance predicate

The inactive fallback uses the exact shared Clear QAction, cannot act on a later selection, and does not over-dismiss the distinct lane menu or guarded drafts. Named checks: `deno task verify --filter automation-editing --filter selectionkey --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not introduce disconnected node selections or a second lane-selection model.
