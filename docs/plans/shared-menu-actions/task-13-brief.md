## 1. Context

The action set from Task 9 and binding from Task 10 replace MainWindow’s separate song-command objects. Task 25 extends the menu with the remaining operations and existing transport actions.

## 2. Exact write set

- `src/mainwindow.h`
- `src/mainwindow.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp`

## 3. Prerequisites

- [Task 10](task-10-brief.md).
- [Task 12](task-12-brief.md).

## 4. Interface contract

Own one EditActions for MainWindow’s lifetime. The existing m_copyAction/m_soloAction/m_insertTimeAction/m_deleteTimeAction may remain borrowed presentation pointers to its actual objects, never owning duplicates or separate handlers. Rebind at selected-tab/readiness changes; a null/unready target is disabled. Project all currently implemented song commands into the Edit groups from the spec.

## 5. Implementation steps

1. Construct the action set before menu entries and call installWindowShortcuts(*this) once; delete the old four allocations/mutation lambdas and MainWindow's per-song-action registration logic. Compose native QMenus from borrowed pointers. The action set owns Window registration; no editor widget receives a QAction shortcut association.
2. Call only EditActions::rebind at selected-tab/readiness changes and refresh for other state updates. The action set performs both pointer updates and old-menu retirement internally; MainWindow does not clear view pointers or separately orchestrate cancellation. Preserve action identity across tabs and null-target handling.
3. Add the current core command groups without moving unrelated File/View/Help entries. Keep current keyboard-owner flags until Task 15; do not introduce a new owner mode.

## 6. Acceptance predicate

Native Edit activation and Window Copy/Solo/Insert/Delete Time operate once on the current ready tab, survive tab switches with stable action objects, and protect text input. Named checks: `deno task verify --filter mainwindow-routing --filter selectionkey-window --filter selectionkey-local-input --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not create per-tab production action sets, placeholder clones, or new activation callbacks in menu construction.
