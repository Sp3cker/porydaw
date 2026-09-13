## 1. Context

Task 13 moves ownership under a concrete action set; QObject parent layout is not behavior. Task 15 removes unhosted Window-key fallback.

## 2. Exact write set

- `src/checks/selectionkey/coreediting.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_native.cpp`

## 3. Prerequisites

- [Task 11](task-11-brief.md).

## 4. Interface contract

Remove QObject-parent, menu-membership wiring, raw shortcut-context and copied-binding assertions for the migrated actions; do not repin Insert Time from Window to Editor metadata. In the isolated core clipboard scenario, invoke only Window Copy through the rig’s real canonical QAction; keep Paste as the existing Editor keyboard input. Preserve clipboard contents/targets, undo, text protection and exactly-once observations.

## 5. Implementation steps

1. Delete ownership/wiring/metadata pins rather than replacing them with new implementation assertions. In particular, the native harness currently pins Insert Time to WindowShortcut and echoes Registry bindings; those checks must disappear before Task 13. Keep enabled behavior and actual activation observations.
2. Change the standalone Copy stimulus to the bound production action, with no test callback or new Window dispatcher. Keep the complete clipboard target scenario and real-MainWindow Window-key tests.

## 6. Acceptance predicate

The existing checks continue proving content and activation while no longer depending on QObject parent layout or standalone Window fallback. Named checks: `deno task verify --filter selectionkey --filter mainwindow-routing --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not switch Paste to direct invocation or weaken text/gesture/undo assertions.
