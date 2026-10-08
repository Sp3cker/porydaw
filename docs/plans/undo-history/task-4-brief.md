# Context
Shell dock QML for the Undo History window and its shell-lane test. Read plan.md
(Contract, Rulings R3, R6, Global Constraints) and spec.md §6 first. Task 3 adds the
bridged presenter concurrently; code against the Contract names.

# Exact write set
- src/ui/shell/UndoHistoryPanel.qml (new)
- src/ui/shell/ShellBody.qml (dock instantiation next to the Polyphony dock)
- the QML module source list that registers `src/ui/shell/*.qml` (CMake)
- src/checks/editorqml/tst_ShellUndoHistory.qml (new)
- the shell QML test registration (`ShellQmlEntries.swift` and/or the CMake list that
  lists `tst_Shell*.qml`)

# Implementation steps
1. Dock in `ShellBody.qml` modeled on the Polyphony dock (`ShellBody.qml` ~91-139):
   visible from `body.shell.undoHistoryVisible`, presenter
   `body.shell.session.undoHistory`, close button activating `view.undo_history`.
2. `UndoHistoryPanel.qml`: `ListView` over `rows` (newest top, base row last). Row text is
   exactly `label` (compose nothing). Undone rows (`!applied`) use the GridPalette
   disabled-text role over the dock surface, others the normal text role; the current row
   shows a position marker and the saved row a saved marker (both may coexist). Pointer
   click activates (`presenter.activate(index)`); Up/Down move the highlight, Enter/Return
   activate, Esc toggles the dock closed. Never handle `Space`. The highlight follows
   `currentRow` on external changes unless the user moved it, then clamps into range.
   Geometry from the resolved base font via existing shell layout policies; follow
   `PolyphonyPanel.qml` for metrics, palette access and contrast pairs.
3. `tst_ShellUndoHistory.qml` using `ShellMenusSupport.openShell()` and the
   `tst_ShellPolyphony.qml` patterns: the action toggles the dock; with a fixture song
   making three edits the list shows 3 steps + base row newest first; clicking the base row
   rewinds to `undoIndex 0`; Enter on a highlighted undone row redoes to it; undone rows
   render dimmed (assert the palette role); Esc closes the dock; Cmd+Z with dock focus
   still undoes; `Space` with dock focus still reaches the window transport command.
4. Inspect final files locally; no build/test/lint/formatter mid-flight.

# Acceptance predicate
The dock renders and drives the presenter; the new shell test passes. Controller runs
`deno task build:checks`, `deno task checks:shell`, `deno task qml-aot:baseline` +
`deno task checks:qml-aot`.

# Task-specific constraints
SHARED_TREE. Do not edit src/swift (except the shell QML test registration file), and do
not touch other tst_Shell* tests.
