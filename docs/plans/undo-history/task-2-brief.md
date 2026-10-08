# Context
Session-level history jump for the Undo History window. Read plan.md (Contract, Rulings
R1, R11, Global Constraints) and spec.md §4.5, §7 first. Task 1 adds
`SongHistory.contains(_:)` concurrently; code against the Contract signature.

# Exact write set
- src/swift/document/DocumentSession.swift
- src/swift/document/DocumentSession+Selection.swift
- src/checks/workspace/history_jump.swift (new)
- the one registration site that runs workspace-lane checks (find it from an existing
  `src/checks/workspace/*.swift` entry such as `bank_switching.swift`), plus its CMake
  source list if checks list sources explicitly

# Implementation steps
1. `public func jump(toIndex target: Int) async throws -> Int` on `DocumentSession`:
   clamp `target` to `0...history.undoCount`; loop `stepHistory(.undo)` while
   `undoIndex > target`, `stepHistory(.redo)` while `undoIndex < target`; stop and return
   the current `undoIndex` when a step returns false; propagate thrown errors (the log is
   consistent per step). After a redo step where `undoCount` shrank and `undoIndex` did not
   advance, decrement `target`; re-clamp to `undoCount` every iteration (R1).
2. R11: when `highlightDuplicatedSelection`/the duplicate recording path inserts into
   `duplicatedSelections`, first drop keys for which `document.history.contains(key)` is
   false.
3. Checks in `history_jump.swift` using existing workspace fixtures (copy the fixture
   style of `bank_switching.swift` / `session_save.swift`): a multi-step jump back and
   forward lands on the exact index and document state; target clamping; a jump across a
   `-G` config change loads the matching bank (compare to stepping with `undo()`); early stop
   when a step refuses; a forward jump through a stale bank entry lands on the step the
   caller targeted (one fewer index) without applying an extra step; duplicate-time
   re-highlight after a jump that ends on a duplicate step; pruning removes evicted or
   discarded duplicate keys.
4. Inspect final declarations locally; no build/test/lint/formatter mid-flight.

# Acceptance predicate
`DocumentSession.jump(toIndex:)` matches repeated `undo()`/`redo()` results step for step,
including bank loading and selection restore. Controller runs `deno task build:checks`,
`deno task checks --filter swiftcore --verbose`.

# Task-specific constraints
SHARED_TREE. Do not edit SongHistory, src/swift/core, src/swift/app, src/ui, or the
existing workspace check files `bank_edits.swift` / `bank_history_probes.swift` (task 1).
