## 1. Context

Quick menus currently carry value rows and dispatch integer IDs. This adapter serves real actions in Tasks 20 and 26–29 while preserving local grid/filter menus.

## 2. Exact write set

- `src/ui/songview/quick/quickmenumodel.h`
- `src/ui/songview/quick/quickmenuhost.cpp`
- `src/checks/host/tst_rulergridmenu.cpp`

## 3. Prerequisites

None beyond the plan entry conditions.

## 4. Interface contract

Implement QuickMenuItem::fromAction(QAction&, int id), an explicit action-backed tag, a guarded QAction pointer, and QuickMenuHost::actionActivated(QAction*) as specified. Scalar rows remain open-time projections. Observe actual QAction::changed/destroyed across the entire represented root item tree, including unopened submenu children, without materializing child models. Store the connections and an action-backed-root flag on the existing root Level; disconnect when that level pops or tears down. A submenu pop does not remove still-represented descendants. Reset of an action-backed root cancels it; value-only roots retain existing reset/stayOpen behavior.

## 5. Implementation steps

1. Implement fromAction as the spec's read-only projection; callers never attach shortcuts or choose scope. Project canonical metadata with no override, preserving escaped &&. Attach root-tree observations in one walk of items/children, preserving lazy submenu models. Action destruction cancels without dereference or value-row fallback.
2. Give activateRow one terminal action-backed branch with the spec's capture → synchronous close → guarded recheck → trigger sequence. A failed post-close guard returns immediately with no retry or actionActivated; successful activation never reaches value-row dispatch. Scope remains irrelevant to this branch.
3. Extend the existing shown Quick menu check with behavior-focused activation, close-before-form-open, destroyed-action and checked-action scenarios. Cover an action changing while its submenu is unopened or popped, root reset retirement, and value-only grid/stay-open behavior.

## 6. Acceptance predicate

Rendered action rows activate their actual QAction exactly once after closure, never double-toggle or execute destroyed/disabled actions, and leave value-row menus unchanged. Named checks: `deno task verify --filter ruler-grid-menu --filter host-seams --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No live metadata mirror model, generic QAction map, display-only fake shortcut suffix, or activation-time target snapshot.
