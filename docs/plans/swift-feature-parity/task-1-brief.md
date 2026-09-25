# Existing shell command parity

Route: SDD-track, shared tree. Base `1096534c7d3e97c17a785625a93a215459c39d6e`.

## Surface and spec

Current production shell menus and editor shortcuts. The `mainwindowrouting` proofs and pinned C++ action/keyboard checks are the acceptance oracle. Restore only supported missing routes for existing semantic behavior (pitch bend G, Set Velocity, loop commands, event moves, register song). Investigate before editing: commands already integrated at the base are preserved, not reimplemented. Absent import/export/sample/theme surfaces and their GAP rows are blocked/deferred and untouched. No UI beyond the proofs. Existing QML is adapted, not redesigned.

## Write set

- src/swift/app/shell/ShellPresenter.swift
- src/ui/shell/ShellWindow.qml
- src/checks/editorqml/tst_ShellMenus.qml
- src/checks/editorqml/tst_ShellPitchBend.qml

A cohesive routing surface needs all four. Other files require controller approval. Proof files are exclusively owned by the later ledger agent.

## Contract

Preserve KeybindingRegistry as the single shortcut registry, existing EditCommand semantics and enablement, popup/text arbitration, bare-Space window priority, newly integrated menus/display settings, document/history ownership and existing bridge APIs. Add missing action catalog/menu entries and input dispatch only when the original checks require them. Do not introduce fallback dispatchers, new QML files, new production C++ or comments.

Add behavior checks exercising actual production keyboard/menu input and state effects. Do not assert copied action counts or source text. Return exact proof A sites and executing predicate identities; keep unproved/native remainder explicit.

## Acceptance and inspection

Controller: `deno task verify:shell --filter shell-menus --verbose`; `deno task verify:shell --filter shell-pitch-bend --verbose`; settled-batch `deno task verify --filter swiftcore --verbose`. Desktop: select an actual note and press G; inspect existing pitch-bend popup and cancel without document mutation. Baseline native click + G left the selected note without a popup.

Shared builds/tests/formatters are deferred to controller. Implementer performs the local inspection section of `rule://sdd-execution-loop`: baseline/final file symbols and diagnostics where supported, complete affected constructs, references before exported-signature changes, scope preservation comparison. Unavailable/stale tools are not passing evidence. Return full result contract, no commits or scratch reports. Proof handoff follows successful execution on frozen sources, then task-scoped review of code, checks and ledger edits.
