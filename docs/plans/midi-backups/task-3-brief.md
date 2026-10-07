# Context
Make backups accessible through the real File menu without a project. Read plan.md Global Constraints and spec.md.
# Exact write set
- src/swift/app/shell/ShellPresenter.swift
- src/swift/app/shell/ShellActionCatalog.swift
- src/ui/shell/ShellWindow.qml
- src/checks/editorqml/tst_ShellMenus.qml
# Prerequisites
Consume task 1 MidiBackupStore.shared.directory() interface from spec.md.
# Interface contract
Action file.open_backups with Open Backups... label and no shortcut; existing File grouping. ShellPresenter backupsFolderRequested(url: String) signal consumed in ShellWindow via Qt.openUrlExternally; report false result through an explicit presenter method using existing failure surface.
# Implementation steps
1. Register action and label without a fake keybinding or special dispatcher; default enable policy already permits it without project.
2. Add retained asynchronous directory creation/request task and error reporting; cancel on teardown. Import existing lower project module.
3. Connect signal positionally in production ShellWindow; surface OS-open rejection.
4. Adapt menu checks for behavioral no-project availability. Delete the existing exact File row-order/count assertion rather than repinning this incidental topology test. Preserve all other tests; do not add wiring/source-text tests.
# Acceptance predicate
Real File > Open Backups... launches matching root in OS explorer even with no project, creates absent directory, and reports failure: controller runs deno task checks:shell --filter shell-menus --verbose, deno task checks:bridge, deno task checks:qml-aot and native menu smoke.
# Task-specific constraints
Do not edit store or service. No new C/C++ and no hardcoded URL paths. No baseline ratchet rewrites without reporting exact need to controller.
