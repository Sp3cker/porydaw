## 1. Context

Task 16 routes event move keys through canonical actions; Task 19 supplies the action-backed row adapter. The current row menu already opens for m_currentRow.

## 2. Exact write set

- `src/ui/songview/quick/eventlistcontroller.cpp`
- `src/checks/eventviews/edits.cpp`
- `src/checks/eventviews/chrome.cpp`

## 3. Prerequisites

- [Task 16](task-16-brief.md).
- [Task 19](task-19-brief.md).

## 4. Interface contract

Project row-menu Move Up/Down from the actual MoveEventUp/MoveEventDown QActions and delete their legacy ID mutation cases. Current row/chunk/filter/selection/document changes dismiss the owned row menu; type/filter/chunk menus retain their distinct local behavior. Retain m_menuRow only where still required by local type/insert/voice operations.

## 5. Implementation steps

1. Replace just the equivalent Move rows with fromAction, preserving current-row target establishment before open. No extra clicked-row target is needed for those actions.
2. Retire the owned row menu when its target context changes, without closing a stay-open filter or another form. Keep Insert/Delete/type/voice operations local where their semantics differ from shared timeline commands.
3. Prove same-tick movement once through row menu and key, unchanged unrelated events and undo, plus row-menu dismissal on row/chunk context changes.

## 6. Acceptance predicate

Event row-menu Move and keyboard Move invoke the same action once on the current legal event, with preserved local menu behavior and undo. Named checks: `deno task verify --filter eventviews-edits --filter eventviews-chrome --filter selectionkey-local-input --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not delete m_menuRow or local value-row handlers that still serve non-equivalent commands.
