# Undo History — plan

Implements [spec.md](spec.md) §1–§9 with the §10 review notes resolved by the rulings below.
The rulings override the spec text where they conflict.

## Tasks
1. Core history projection (SDD-track): `SongHistory` cap/eviction, labels, `HistoryStep`,
   `revision`, saved/base markers, identity lookup; `BankHistoryAction.historyLabel` and
   every conformer. Brief: [task-1-brief.md](task-1-brief.md).
2. Session jump (SDD-track): `DocumentSession.jump(toIndex:)` and duplicated-selection
   pruning. Brief: [task-2-brief.md](task-2-brief.md).
3. App presenter and command (SDD-track): `UndoHistoryPanel`, jump request gating, the
   `view.undo_history` command. Brief: [task-3-brief.md](task-3-brief.md).
4. Shell dock QML and shell lane (SDD-track). Brief: [task-4-brief.md](task-4-brief.md).

Tasks run in parallel with disjoint write sets against the Contract below. The controller
owns baselines (`bridge:baseline`, `qml-aot:baseline`), formatting, and all gates.

## Contract (shared interfaces; exact names)

PorydawCore (`src/swift/core/SongHistory.swift`):
```swift
public struct HistoryStep: Equatable, Sendable {
    public let label: String
    public let applied: Bool    // offset < undoIndex
    public let isCurrent: Bool  // offset == undoIndex - 1
    public let isSaved: Bool    // document entry whose afterIdentity == savedIdentity
}
extension SongHistory {
    public static let stepLimit: Int            // 512
    public private(set) var revision: Int       // bumps once per projection-visible mutation
    public func step(at offset: Int) -> HistoryStep?   // offset 0 = oldest
    public var baseIsSaved: Bool                // savedIdentity == current base identity
    public var hasEvictedSteps: Bool            // any entry was evicted by the cap
    public func contains(_ identity: DocumentIdentity) -> Bool  // base or any entry's afterIdentity
}
public protocol BankHistoryAction { var historyLabel: String { get } }  // new requirement
```

PorydawDocument (`src/swift/document/DocumentSession.swift`):
```swift
@discardableResult
public func jump(toIndex target: Int) async throws -> Int   // returns the reached undoIndex
```

PorydawApp (QtBridge surface; QML consumes these names):
- `@QtBridgeable public final class UndoHistoryRow` roles: `label: String`, `applied: Bool`,
  `isCurrent: Bool`, `isSaved: Bool`, `isBase: Bool`.
- `@QtBridgeable public final class UndoHistoryPanel`: `rows: QListModel<UndoHistoryRow>`
  (newest step first, base row last; always ≥1 row while a song is open, else empty),
  `@QtTracked currentRow: Int` (model row of the current position; base row when
  `undoIndex == 0`, `-1` when empty), `@QtTracked canJump: Bool`,
  `func activate(row: Int)` (no-op unless `canJump`, row in range and not current).
- `ApplicationSession.undoHistory: UndoHistoryPanel` (owned, `public let`).
- `ShellPresenter`: `@QtTracked public var undoHistoryVisible = false`; action id
  `view.undo_history` toggles it.

## Rulings
- R1 Jump lives on `DocumentSession` and loops its private `stepHistory`, so `-G` bank
  preloading, inbox draining, publication and duplicate re-highlighting run per step. No
  `SongHistory.jump`. A forward step that drops a stale bank entry without advancing
  decrements `target` (the clicked step shifted down one place); re-clamp to `undoCount`.
- R2 No `savedStepIndex`. `HistoryStep.isSaved` is true only for document entries; bank
  entries share their predecessor's identity and never carry the saved marker.
  `baseIsSaved` marks the base row.
- R3 The panel shows a base row below the oldest step; activating it jumps to `0`. Label
  `Opened` when `!hasEvictedSteps`, else `Oldest kept state`.
- R4 Eviction sets the base identity to the last evicted entry's `afterIdentity`; spec
  §4.1's "isDirty needs no bookkeeping" is wrong without this (undo-to-0 after eviction
  would report clean against an on-open save).
- R5 `markSaved` bumps `revision` (the saved marker moves). `sealMergeBoundary` and
  `sealBankMerge` do not.
- R6 Host as an in-window dock in `ShellBody.qml` following the Polyphony Debugger
  precedent: visibility on `ShellPresenter.undoHistoryVisible` (not
  `ApplicationSession.undoHistoryOpen`), checkable action, no persisted visibility, no
  default key binding. In-window hosting keeps window-scope Cmd+Z/Cmd+Shift+Z working.
- R7 No gesture/prompt gating beyond what menu undo has; same exposure as menu undo.
- R8 `ApplicationSession` tracks one app-wide history jump in flight; while set,
  `refreshDocumentState` publishes `canUndo`/`canRedo` false and the panel's `canJump`
  false. The jump stays bound to the `DocumentSession` it started on.
- R9 The panel updates rows incrementally (mutate row objects for flag changes;
  `replaceSubrange` for structural changes), only while visible; it rebuilds on show and
  tab switch. Skips work when `revision` and the history instance are unchanged.
- R10 No redo-tail-discard notice (not agreed behavior).
- R11 `DocumentSession.duplicatedSelections` is pruned to identities that
  `history.contains` when a new duplicate is recorded.
- R12 Labels come from a labeler `SongDocument` attaches to its history (like
  `attachApply`), so `record` callers stay unchanged. Singular `note`/`event` when N == 1.

## Global Constraints
- Work only in `/Users/spencer/dev/cProjects/porydaw/.worktrees/undo-history`; use absolute
  paths there for every read/edit. Never touch the main checkout.
- Swift 6 + QML only; no new C++. One concept per file; comments ≤2 lines; no force unwraps;
  `internal` by default, `public` only for cross-module callers. Never grep without a path.
- SHARED_TREE: implementers skip builds, tests, lint and formatters; perform read-only local
  structural inspection and report unavailable LSP honestly. The controller runs named gates
  on the settled union and formats once.
- No proof-ledger edits (spec §9). No workarounds, fallbacks or default protocol
  implementations that hide missing behavior.
- Existing undo/redo, merge, dirty, bank-transition and save semantics stay intact except
  where a ruling changes them.
- QML: geometry from the resolved base font through existing layout policies; GridPalette
  text pairs; never handle bare `Space`.
- Return the full result contract in the task result; write no report/scratch files; commit
  nothing.
