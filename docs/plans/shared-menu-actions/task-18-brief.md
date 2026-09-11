## 1. Context

The ruler consumes Task 10 invalidation and committed-cursor notifications. Task 28 later changes its target establishment and action rows.

## 2. Exact write set

- `src/ui/songview/timeruler.cpp`
- `src/checks/rollcheck/ruler_loop_menu.cpp`
- `src/checks/host/tst_rulergridmenu.cpp`

## 3. Prerequisites

- [Task 10](task-10-brief.md).
- [Task 11](task-11-brief.md).

## 4. Interface contract

Ruler context-menu retirement requires both session ownership by m_menuHost and m_menuHost->rootModel() == m_rulerMenuModel. Subscribe to contextMenusInvalidated and committed editCursorMoved; selection/cursor changes must not dismiss division/feel grid menus sharing that host. Retain existing document/teardown cancellation. Numeric signature forms keep their separate guarded lifetime.

## 5. Implementation steps

1. Cancel only an owned ruler context menu on relevant selection/document/cursor changes, using normal-versus-teardown focus policy. Do not route through broad closePopups when that would cancel a form.
2. Replace selection/document stale-activation checks with dismissal plus no-write assertions; keep Escape, outside-click and two-step loop undo coverage. Extend the existing ruler-grid-menu suite with a division/feel menu across a selection/cursor change and confirm it stays open.

## 6. Acceptance predicate

Ruler menu invalidation closes the menu, leaves the document unchanged and preserves independent signature-form guards. Named checks: `deno task verify --filter rollcheck --filter ruler-grid-menu --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Raw setEditCursorTick during a drag is not a committed cursor notification; do not add seek behavior here.
