# shell-proof

## Context
See plan.md Global Constraints and shell-contract.md. Prove the production QML shell with checks derived from original C++ fixtures, sequences and observable assertions, not a new invented scenario inventory.

## Exact write set
src/checks/editorqml/ShellQmlTests.swift; src/checks/editorqml/tst_ShellWindow.qml; src/checks/editorqml/proof.shellwindow.txt; deno.json; tools/cli.ts.

## Interface and preservation contract
Use the production ShellWindow and existing song-tab/editor controls. The Swift bootstrap exposes only necessary Qt test access, fixture staging, native settings preservation, main-actor event pumping and original enum/clipboard observations. No production test hooks or new C++ code. Reuse runKeybindingRegistryChecks(onAssertion:) with its required single assertion sink; collect failed labels only at the QML boundary. Keep tools/run_checks.ts unchanged and follow the existing verify:qml standalone manifest/task pattern for verify:shell.

## Native sources
- keyboard/keymapregistry.cpp: all four exact real Settings seeds and all 28 registry predicates.
- themelayout/tst_themelayout_color.cpp::settingsRepair: exact custom/primary/accent/contrast values and repaired state/persistence predicates; disclose genuine native-store snapshot/restore versus original scratch INI glue.
- mainwindowrouting/mainwindowroutingfixture.h::openSession and tst_mainwindowrouting_native.cpp::nativeMenuAndWindowShortcutRouting: original two-song fixture, menu observation, selected-note Copy, exact activation counts and decoded clipboard track/note/key observations, local text without musical selection, non-text and roll Solo delivery, then local text rejection. Qt Quick SignalSpy and input probes replace equivalent QWidget test machinery, not assertions.
- Existing selectionkey local-input proof context supplies numeric-field Copy/Paste, ordinary-key ownership and window-priority Space observations.

## Evidence rules
Preserve original source references, hashes, assertion IDs/context and exact coverage limits. Do not mark unported native assertions as matched. A new dirty-window-close sequence with no exact C++ test origin is a throwaway lifecycle smoke only: retain observed output and its immutable controller artifact, remove the permanent invented scenario. The same applies to the independent Qt Find enum smoke. Neither enlarges the native assertion count.

## Acceptance
Controller runs `deno task verify:shell --verbose` for all retained native-derived cases and `deno task verify --filter swiftcore --verbose` for the shared assertion sink. Record actual commands/results and current source hashes after passing. Existing editor visuals remain covered by `deno task verify:qml --verbose`, without rebaselining. Offscreen evidence never claims physical Cocoa menu-bar integration.

## Inspection and constraints
SHARED_TREE, DEFERRED_TO_CONTROLLER for builds/tests/formatters/linters. Inspect source declarations, fixture lifetime, settings restoration, exact assertion crosswalk and standalone task resolution. No commits. Every tool timeout is at most 300 seconds.
