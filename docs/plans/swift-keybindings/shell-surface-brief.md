# shell-surface

## Context
See plan.md Global Constraints and shell-contract.md. The production cutover covers all existing Swift-enabled targets (currently Apple); it does not add another platform/toolchain port.

## Exact write set
src/ui/shell/ShellWindow.qml; src/ui/songview/quick/swiftroll/EditorSurface.qml; src/ui/songview/quick/swiftroll/SongTabs.qml; src/ui/songview/quick/swiftroll/SongTab.qml; src/ui/songview/quick/swiftroll/MouseHintStatus.qml; src/ui/songview/quick/drawer/VoiceChangeMenu.qml. Six-file exception: one end-to-end font and input propagation responsibility, preserving the existing visual composition.

## Prerequisites
Registry and shell interface contracts are frozen; independent write sets run together.

## Interface contract
Registry: plan.md. Shell: shell-contract.md.

## Implementation steps
Build QML ApplicationWindow consuming shared contract. Reuse SongTabs/EditorSurface visual composition; replace QWidget shell with menu/shortcut/dialog QML. All action meaning in Swift. Deliver window shortcuts via Qt Shortcut and raw editor keys to Swift without duplicate dispatch. Preserve text/modal ownership, window Space priority, input cancellation and scene-detach lifecycle. Thread shell routing through tabs without new C++ code. Existing native fixtures retain their existing path but production has exactly one Swift owner.

## Acceptance predicate
Equivalent native observable behavior with exact old-check provenance. Controller runs deno task build:app; deno task verify:shell --verbose for actual shell input and lifecycle; deno task verify:qml --verbose for unchanged editor behavior and DPI/font reference profiles. No visual rebaselining.

## Task-specific constraints
No builds/tests/linters/formatters: SHARED_TREE, DEFERRED_TO_CONTROLLER. Read-only local structural inspection required. No commits. All tool timeouts <=300.
