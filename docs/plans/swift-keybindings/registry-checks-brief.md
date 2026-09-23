# registry-checks

## Context
See plan.md Global Constraints and shell-contract.md. The production cutover covers all existing Swift-enabled targets (currently Apple); it does not add another platform/toolchain port.

## Exact write set
src/checks/keyboard/KeybindingRegistryChecks.swift; src/checks/keyboard/proof.keymapregistry.txt

## Prerequisites
Registry and shell interface contracts are frozen; independent write sets run together.

## Interface contract
Registry: plan.md. Shell: shell-contract.md.

## Implementation steps
Copy original thirteen assertion sites and all sixteen defaultMatching rows, settings seeds and modifier sequences. Expose runKeybindingRegistryChecks(onAssertion: (Bool, String, String) -> Void): one required sink reports each condition with its native check ID and row/message. Compile this same source in the core and shell test hosts; keep CheckReport adaptation in SessionChecks and QML failure-string collection in ShellQmlBootstrap, so the shell does not link unrelated native test machinery. Use the production registry interface from plan.md, no mocks. Keep proof context and only mark candidates until controller runs. Own no CMake or SessionChecks.swift; report wiring required.

## Acceptance predicate
Equivalent native observable behavior with exact old-check provenance. Controller runs deno task build:app; deno task verify --filter swiftcore --verbose; deno task verify:shell --verbose, including the genuine QtCore.Settings seeded case, before acceptance.

## Task-specific constraints
No builds/tests/linters/formatters: SHARED_TREE, DEFERRED_TO_CONTROLLER. Read-only local structural inspection required. No commits. All tool timeouts <=300.
