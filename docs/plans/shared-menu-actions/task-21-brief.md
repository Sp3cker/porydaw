## 1. Context

Point menus consume Task 10 invalidation. A node-hit miss falls through the existing time-selection menu entry: Task 20 provides its inactive Clear row, and Task 26 provides active shared range rows. Node value and lane-delete forms remain separate transactions.

## 2. Exact write set

- `src/ui/editordrawer/automationcanvas_pointmenu.cpp`
- `src/checks/automation/automationpointmenus.cpp`

## 3. Prerequisites

- [Task 10](task-10-brief.md).
- [Task 11](task-11-brief.md).
- [Task 20](task-20-brief.md).

## 4. Interface contract

Cancel only the point menu owned by its host when selection/context changes. Keep node-value and lane-delete prompt state/guards and existing direct local point operations. Preserve the existing miss fallback; do not introduce a second Clear row producer or dispatch path.

## 5. Implementation steps

1. Attach owned-menu retirement at the existing point-menu adapter lifecycle. Keep local point action target checks that still protect actual document operations, but remove no form guard.
2. Exercise selection change dismissal and a value/lane form that remains governed by its own acceptance/cancellation rules.

## 6. Acceptance predicate

An obsolete point menu closes without document mutation while node-value and lane-delete drafts retain their independent guarded behavior. Named checks: `deno task verify --filter automation-editing --filter automation-domain --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No arbitrary node-ID selection feature or generic popup cancellation broadcast.
