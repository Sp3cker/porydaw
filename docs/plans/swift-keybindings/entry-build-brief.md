# entry-build

## Context
See plan.md Global Constraints and shell-contract.md. Replace the production host on every existing Swift-enabled target (currently Apple); do not introduce another toolchain port.

## Exact write set
CMakeLists.txt; src/swift/app/CMakeLists.txt; src/checks/CMakeLists.txt; src/swift/app/shell/PorydawShellApp.swift.

## Interface and preservation contract
The Swift QApp entry registers ShellPresenter and ApplicationSession after GUI creation and loads the bundled ShellWindow plus existing resources/fonts. Preserve application identity/version and native startup options. Non-Swift production targets retain their original entry. The Swift executable must not instantiate RewriteWindow or route through the native key registry. Existing native clipboard/resource helpers and native check oracles may remain linked; they are not a routing fallback.

## Implementation
Wire production sources, resources and the existing-header QtKeybindings module map. Compile the same KeybindingRegistryChecks.swift assertion source into swiftcore and the standalone shell_qml_lane without importing the whole native-check module. The shell test executable follows the existing Qt Quick Test target/manifest pattern. Remove task-created prototype targets, flags, resources and sources after successful smoke evidence. No new C++ source or code.

## Acceptance
Controller runs `deno task build:app` (real Swift bundle and retained resources), `deno task verify --filter swiftcore --verbose` (shared registry assertions), `deno task verify:shell --verbose` (actual production shell through the standalone test host), and offscreen production startup plus `--help`/`--version`. Existing `deno task verify:qml --verbose` remains the editor/reference gate, with no baseline changes.

## Inspection and constraints
SHARED_TREE, DEFERRED_TO_CONTROLLER for builds/tests/formatters/linters. Inspect target ownership, source membership, inherited module-map flags, platform conditions and prototype removal. Existing oversized build manifests receive only target-local wiring; no unrelated restructuring. No commits. Every tool timeout is at most 300 seconds.

## Observed final evidence

All prescribed gates passed. The final clean `build:app` completed in 21.10 s. The real executable prints its help and `porydaw 1.0.3`. With only `QT_QPA_PLATFORM=offscreen`, `QT_QUICK_BACKEND=software`, and `QSG_INFO=1`, the rebuilt application reached scene-graph startup in 521 ms with no QML load errors; no framework/plugin/QML path overrides were needed. The supervised process was stopped after inspection. This is startup evidence, not physical Cocoa-menu coverage.

The first headless attempts exposed stale generated deployment contents in the build bundle, not a source fallback requirement. That entire old bundle was preserved outside the worktree and the app rebuilt from the current target. No deployment-path workaround was added to production code. The necessary identity bootstrap and native settings isolation are specified in settings-isolation-brief.md.
