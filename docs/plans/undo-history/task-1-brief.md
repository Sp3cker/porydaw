# Context
Core history projection for the Undo History window. Read plan.md (Contract, Rulings,
Global Constraints) and spec.md §3–§4, §7 first. Paths are relative to the worktree root.

# Exact write set
- src/swift/core/SongHistory.swift
- src/swift/core/HistoryStepLabel.swift (new: the label builder; one concept)
- src/swift/core/SongDocument.swift (attach the labeler next to `attachApply`; nothing else)
- src/swift/core/CMakeLists.txt (only if Core lists sources explicitly)
- src/swift/document/ServiceBankHistory.swift (`historyLabel` on `ServiceBankAction`)
- src/checks/editcheck/NoteHistoryChecks.swift (`ProbeBankAction.historyLabel`)
- src/checks/workspace/bank_edits.swift (`MergingBoundaryAction.historyLabel` only)
- src/checks/workspace/bank_history_probes.swift (`historyLabel` on its two probe actions only)
- src/checks/editcheck/DocumentHistoryChecks.swift (new contracts, registered from
  `documentHistoryContracts`)

# Implementation steps
1. `HistoryStep` and the Contract members exactly as plan.md specifies.
2. Cap: `stepLimit = 512`. After each non-merge append (end of `record` and
   `recordConfirmedBankOwned`) evict from the front while `entries.count > stepLimit`,
   decrementing `index` by the number removed; set the base identity to the last evicted
   entry's `afterIdentity` (R4; make `baseIdentity` mutable and private) and mark
   `hasEvictedSteps`. Eviction never runs on undo/redo/merge.
3. `revision`: +1 once per mutation changing `entries`, `index`, labels or the saved marker:
   append (eviction folded into the same bump), merge replace, merge removal, undo, redo,
   stale removal, `discardRedo` folded into its record, `markSaved` (R5). Not on
   `sealMergeBoundary`/`sealBankMerge`/`beginBankTransition`/`endBankTransition`, nor on
   rejected (no-op/guarded) calls.
4. Labels (R12): store `label: String` on `DocumentEntry` (set at append; replaced on merge
   replace) and read `action.historyLabel` for bank entries at projection time (the
   action is immutable per entry except via merge replace). Add an internal
   `attachLabeler(_: @escaping (HistoryOperation, DocumentChangeSet) -> String)`; `record`
   calls it. Without a labeler attached, the label is the fixed phrase for the operation
   (no empty strings).
5. `HistoryStepLabel.swift`: internal builder taking `SongDocument` state, the operation and
   change set. Note ops (`addNotes, deleteNotes, moveNotes, moveNotesToPitches, nudgeNotes,
   nudgeNotePitches, resizeNotes, resizeNoteLengths, setVelocities`) → `Track <name> -
   edited <N> notes`; event ops (`insertRawEvent, modifyRawEvent, deleteRawEvents,
   moveRawEvent, writeLane, moveLanePoints, deleteLanePoints`) → `... events`. `N` = id
   payload count where the operation carries ids, else changed note-on events (notes) or
   changed events (events). Singular `note`/`event` when N == 1. `<name>` =
   `SongDocument.trackName(track)` at record time, else the 1-based engine-track position;
   map changed chunks to engine tracks via `engineTracks`. More than one track → `Edited <N>
   notes|events`. Fixed phrases: addTrack "Add track", duplicateTrack "Duplicate track",
   deleteTrack "Delete track", moveTrack "Move track", renameTrack "Rename track",
   setChunkEnd "Set song end", setConfig "Edit song config", editTempo and editRawAndTempo
   "Change tempo", setLoop "Set loop", setTimeSignature "Set time signature",
   moveTimeSignature "Move time signature", deleteTimeSignature "Delete time signature",
   applyRangeEdit "Range edit", moveRange "Move range", removeTime "Remove time",
   insertBlankTime "Insert time", duplicateTime "Duplicate time". The builder must not
   allocate per frame (it runs once per record).
6. `step(at:)`: projection only; never expose entries, changes or actions. `isSaved` per R2.
   `baseIsSaved`, `hasEvictedSteps`, `contains(_:)` per Contract.
7. `BankHistoryAction`: add `var historyLabel: String { get }` with no default
   implementation. `ServiceBankAction` captures `Edit voicegroup slot <slot>` at
   construction (merged actions report their own). Add explicit labels to the check probes.
8. Checks in `DocumentHistoryChecks.swift` (CheckReport style already used there):
   eviction at 513 appends preserves cursor/redo tail and `isDirty`, including undo-to-0
   after eviction staying dirty against an on-open save (R4); label contents (single-track
   note/event counts incl. singular, unnamed-track fallback, multi-track drop, capture-time
   name stable across later rename, merged gesture count refresh, a fixed phrase, bank
   label); `revision` strictly increases on each listed mutation and is unchanged by
   `sealMergeBoundary`; `markSaved` bumps; `isSaved`/`baseIsSaved` after save,
   save-then-undo, save at open, and after the saved step is evicted (no marker anywhere);
   bank steps never `isSaved`; `contains` for base, live and evicted identities.
9. Inspect final declarations locally; no build/test/lint/formatter mid-flight.

# Acceptance predicate
Contract members exist with exact names; labels and markers behave as above; all existing
history behavior unchanged. Controller runs `deno task build:checks`,
`deno task checks --filter swiftcore --verbose`.

# Task-specific constraints
SHARED_TREE. Do not edit DocumentSession files (task 2) or anything under src/swift/app or
src/ui. Do not change `record` call sites.
