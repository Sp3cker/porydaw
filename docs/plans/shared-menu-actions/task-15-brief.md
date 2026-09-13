## 1. Context

Task 8 separated semantic policy, Task 10 protected local delivery, and Tasks 11/13 bound every relevant root. This is the clean keyboard cutover.

## 2. Exact write set

- `src/ui/songview/editkeyrouting.cpp`
- `src/ui/songview.h`
- `src/mainwindow.cpp`

## 3. Prerequisites

- [Task 9](task-9-brief.md).
- [Task 14](task-14-brief.md).

## 4. Interface contract

handleEditKey recognizes only Editor-scope shared commands and implements the three terminal outcomes in spec.md#physical-activation-and-local-priority: decline, consume without activation, or trigger the enabled canonical action once and consume. Remove SharedShortcutOwner, its field/setter and all MainWindow calls. Qt alone matches Window Copy/Solo shortcuts; Quick fallback never executes them.

## 5. Implementation steps

1. Replace the local SharedBinding/kSharedBindings/resolveEditCommand machinery with EditActions::editorCommandForKey, shared with the native override stage. Apply the spec's early-return outcomes after existing origin/gesture/repeat arbitration: never trigger disabled actions, consume unavailable Duplicate Time/gesture-owned keys, preserve key-release audition.
2. Delete physical-owner switching and Window command fallback; leave Escape’s gesture-or-selection behavior local. No input synthesis or alternate unhosted path.
3. Ensure the action callback is the sole semantic execution route for each recognized Editor key, including Pencil and selected interval edits across drawer/chrome focus.

## 6. Acceptance predicate

Editor keys activate the same objects as menus exactly once while Window keys remain window-owned; local text, gestures and event-list controls retain priority. Named checks: `deno task verify --filter selectionkey --filter mainwindow-routing --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not treat action disablement as permission for Duplicate Time to fall into another local operation.
