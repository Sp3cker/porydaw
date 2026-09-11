## 1. Context

Task 7 catalogued A/V/P and polyphony. MainWindow still attaches them with direct key literals and separately formatted tooltip hints.

## 2. Exact write set

- `src/mainwindow.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`

## 3. Prerequisites

- [Task 7](task-7-brief.md).
- [Task 13](task-13-brief.md).

## 4. Interface contract

Attach view.automation_drawer, view.velocity_drawer, view.voice_changes_drawer and view.polyphony_debugger using Registry::attach and the existing actual QActions. Their scope remains Window; displayed shortcut text derives from those actions.

## 5. Implementation steps

1. Replace direct setShortcut literals and hardcoded shortcut annotations for these four commands with fixed catalogue attachment and QAction-derived presentation.
2. Preserve existing drawer visibility/event-list readiness and toggle behavior; do not move them into the Editor shortcut path.

## 6. Acceptance predicate

A/V/P still toggle their drawers from persistent Quick chrome and native View menus show fixed platform keys; polyphony retains its shipped binding. Named checks: `deno task verify --filter mainwindow-routing-input --filter selectionkey-window --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No new default keys, tooltip-hint framework or shortcut browser.
