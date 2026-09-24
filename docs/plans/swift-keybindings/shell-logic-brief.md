# shell-logic

## Context
See plan.md Global Constraints and shell-contract.md. The production cutover covers all existing Swift-enabled targets (currently Apple); it does not add another platform/toolchain port.

## Exact write set
src/swift/app/shell/ShellPresenter.swift; src/swift/app/shell/ShellAppearance.swift; src/swift/app/timeline/GridPalette.swift; src/swift/app/roll/GridScene.swift. ApplicationSession remains unchanged.

## Prerequisites
Registry and shell interface contracts are frozen; independent write sets run together.

## Interface contract
Registry: plan.md. Shell: shell-contract.md.

## Implementation steps
Implement full old RewriteWindow semantic shell responsibility in Swift under shared contract. Reuse session methods and EditKeyArbiter; complete routing, lifecycle, dialogs and palette behavior. New code must map old checks or explain Qt-access glue. Do not expand features absent old shell; preserve existing legacy surfaces as oracle, not runtime fallback.

## Acceptance predicate
Equivalent native observable behavior with exact old-check provenance. Controller runs deno task build:app; deno task verify --filter swiftcore --verbose; deno task verify:shell --verbose; and an offscreen launch of the actual production bundle before acceptance.

## Task-specific constraints
No builds/tests/linters/formatters: SHARED_TREE, DEFERRED_TO_CONTROLLER. Read-only local structural inspection required. No commits. All tool timeouts <=300.
