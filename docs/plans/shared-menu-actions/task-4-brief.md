## 1. Context

The application menu still opens Settings on its Keyboard tab and the fixed catalogue must not retain an obsolete keyboard-settings command.

## 2. Exact write set

- `src/mainwindow.h`
- `src/mainwindow.cpp`
- `src/ui/keymap.cpp`

## 3. Prerequisites

- [Task 1](task-1-brief.md).
- [Task 2](task-2-brief.md).

## 4. Interface contract

Delete MainWindow::openKeyboardShortcuts and its menu connection, together with the `edit.keyboard_shortcuts` definition. Leave Preferences, Song Settings and Engine Settings entry points intact. Task 5 removes the remaining Settings tab itself.

## 5. Implementation steps

1. Remove the Keyboard Shortcuts QAction/menu creation, slot definition/declaration and dedicated connection.
2. Remove only `edit.keyboard_shortcuts` from the command definitions; preserve neighboring IDs/defaults and existing settings routes.
3. Exercise the visible menu and retained Settings entry points without introducing a read-only shortcut browser.

## 6. Acceptance predicate

The visible application has no Keyboard Shortcuts menu entry, while Preferences, Song Settings and Engine Settings still open their existing targets. Verify with `deno task build:app`, launch the built app, inspect/invoke those menu routes, and run `deno task verify --filter settings-dialog --filter mainwindow-routing --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not reorganize unrelated menus in this task. The still-present Settings Keyboard tab is removed by the dependent task, not replaced by an alias.
