# registry

## Context
See plan.md Global Constraints and shell-contract.md. The production cutover covers all existing Swift-enabled targets (currently Apple); it does not add another platform/toolchain port.

## Exact write set
src/swift/app/commands/KeybindingRegistry.swift; src/swift/app/commands/QtKeybindings.modulemap.in

## Prerequisites
Registry and shell interface contracts are frozen; independent write sets run together.

## Interface contract
Registry: plan.md. Shell: shell-contract.md.

## Implementation steps
Port complete native keymap.cpp catalogue and matching semantics through Registry interface in plan.md. Use existing Qt header APIs via Swift C++ interop for StandardKey bindings/settings access; no new C++ source/header bodies. Do not hand-code platform alternate bindings. Public Swift value API must remain Qt-free. Own no CMake files; report required flags to integration owner.

## Acceptance predicate
Equivalent native observable behavior with exact old-check provenance. Controller runs deno task build:app; deno task verify --filter swiftcore --verbose; shell integration uses production QML smoke and proof-derived Qt Quick Test lane before acceptance.

## Task-specific constraints
No builds/tests/linters/formatters: SHARED_TREE, DEFERRED_TO_CONTROLLER. Read-only local structural inspection required. No commits. All tool timeouts <=300.
