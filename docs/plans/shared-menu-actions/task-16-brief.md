## 1. Context

Task 15 provides the sole Editor key activation route and Task 8 supplies the event controller's bool eligibility predicate. EventListController still intercepts Alt+Up/Down and directly edits; those branches yield to the shared route. Task 29 migrates equivalent row-menu entries.

## 2. Exact write set

- `src/ui/songview/quick/eventlistcontroller.cpp`
- `src/ui/songview/editactions.cpp`
- `src/checks/selectionkey/localinputtier_eventlist.cpp`

## 3. Prerequisites

- [Task 8](task-8-brief.md).
- [Task 15](task-15-brief.md).

## 4. Interface contract

Remove only eventlist.move_up/move_down execution from handleLocalKey. The shared route triggers the canonical action, which delegates eligibility to the existing canMoveCurrentRow(-1/+1) from Task 8 and execution to moveCurrentRow(-1/+1). Action code does not interpret moveDestForRow or consult timeline selection. Refresh from current-row, selected-row, chunk/filter/model, visibility and editing notifications.

## 5. Implementation steps

1. Leave plain/Shift Up/Down navigation, local Delete/Backspace and local Select All in the controller. Let Alt+Up/Down reach shared editor arbitration without a second matcher that edits.
2. Observe event-controller eligibility in the active action set without reproducing its predicate. Preserve same-tick legal-move rules and reorder undo; an unrelated note/time selection neither disables nor retargets the move.
3. Exercise row navigation, cell editing and one same-tick move while an unrelated timeline selection exists; only the event target moves.

## 6. Acceptance predicate

Event movement activates once through the shared command while local navigation/editing remains local and unrelated note/time selections are untouched. Named checks: `deno task verify --filter selectionkey --filter eventviews-edits --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not unify local event-row Delete with timeline Delete Selection or retarget by last focus.
