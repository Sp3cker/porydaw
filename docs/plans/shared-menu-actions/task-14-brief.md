## 1. Context

The canonical action exists in Task 9 and is exposed in Task 13. This task removes AutomationPage’s second object/matcher before the final key-only cutover.

## 2. Exact write set

- `src/ui/editordrawer/automationpage.h`
- `src/ui/editordrawer/automationpage.cpp`
- `src/ui/songview/editactions.cpp`

## 3. Prerequisites

- [Task 13](task-13-brief.md).

## 4. Interface contract

AutomationPage::pencilModeAction() returns the bound canonical Pencil action, not a page-owned QAction. Delete m_pencilModeAction allocation/field, matchesPencilShortcut and its modifier helper, and the ShortcutOverride/KeyPress filter branches. Preserve the WindowDeactivate pending-value-form cancellation and its input-window ownership test.

## 5. Implementation steps

1. Replace the action accessor with a borrow from the owner’s bound EditActions and remove the page's old toggled-to-setPencilMode connection. The real checked state comes from AutomationCanvas::pencilMode; only the bound target may synchronize it on rebind and page-state changes, without firing edits. An unbound/background page never writes the canonical action's state.
2. Remove the page’s manual Pencil keyboard matching and triggering. B continues through the shared eligibility route introduced in Task 8, including non-repeat, drawer visibility and local text/prompt priority.
3. Retain the deactivation-only filter lifecycle and cancellation of a pending value draft without focus restoration.

## 6. Acceptance predicate

Pencil toggles once from its visible action and editor key path, preserves per-tab state and text/prompt behavior, and window deactivation still cancels a pending value draft. Named checks: `deno task verify --filter selectionkey --filter automation --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not delete the remaining page event filter or move value-form cancellation into a generic action dispatcher.
