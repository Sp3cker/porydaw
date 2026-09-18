# Context
QtBridge QListModel supports insert/remove/reset but lacks moves. Remove+insert would destroy persistent QML pages. Add actual Qt model move support at the responsible bridge; no shadow registry. Read plan.md Global Constraints and Spec.

# Exact write set
- src/ui/songview/quick/swift-grid-prototype/qtbridge-object-return.patch

# Prerequisites
None. Source oracle is cached .worktrees/swift-qml-grid/build-swift-grid/_deps/qtbridge-src, read-only. Do not mutate other worktree/cache. Controller task consumes the new method.

# Interface contract
Public QListModel<Element>.move(from sourceIndex: Int, to destinationIndex: Int) where destination is final index, within existing indices. Same-index is no-op. Bracket backing storage remove/insert with genuine beginMoveRows/endMoveRows through QAbstractListModel Swift and QAbstractListModelCpp. For downward moves Qt destinationChild is destinationIndex + 1. Invalid indices do not mutate; document exact behavior. Do not emit reset or remove/insert notifications. Preserve existing patch hunks.
Single-row moves only. Native and Swift beginMoveRows wrappers return Bool; storage mutation and endMoveRows happen only if beginMoveRows succeeds. Qt rejects no-op moves; never pair a rejected begin with end. Same-index fast-path is allowed but does not replace handling the native Bool result.

# Implementation steps
1. Inspect QtBridge QListModel.swift, QAbstractListModel.swift, abstractlistmodel.cpp and include/abstractlistmodel.h; follow analogous existing abstractitemmodel or table move wrappers.
2. Extend existing checked-in patch with cohesive move method/wrappers in those upstream files. Construct correct unified diff against cached upstream originals, preserving existing object-return/build hunks. No patching live shared dependency cache; use scratch outside repo only if needed to generate a patch.
3. Keep API small and row bookkeeping correct; expose only needed native notifications. No own model class or custom item lifetime cache.

# Acceptance predicate
Fresh Main-run deno task prototype:swift-grid --smoke applies patch, compiles it and proves real pointer reorders preserve live page/model/camera. New tab smoke should observe rowsMoved and persistent index as applicable. Authors skip all builds/tests/linters/formatters; source-local inspection only.

# Task-specific constraints
This is a root-cause library capability addition, not a workaround. No changes to upstream pin or production target. Patch new-worktree dependency only through existing configure step. Shared controller contract fixed above.
