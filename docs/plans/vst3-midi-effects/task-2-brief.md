# Context

A track can host one whole-track plugin effect as document state. Config edits and finished plugin edits are undoable history entries; each finished plugin edit is one "edit plugin settings" step. Track remaps move effects inside the same mutation. There are no ranges, no output or derived state, no basis, no bypass and no arpeggiator kind. Consumers: task 3 (sidecar codec and restore, via the types and the history cases) and task 7 (the capture reads `config`). Read plan.md Global Constraints and spec.md "Core" (Model, Document operations) first.

# Exact write set

- src/swift/core/TrackEffect.swift (new): every model type in spec "Model", plus `PluginStateBlob { component: [UInt8], controller: [UInt8] }`
- src/swift/core/TrackEffectEditing.swift (new): `effects`, `effect(onTrack:)`, `addEffect`, `removeEffect`, `updateEffect`, `recordPluginState`, `TrackEffectError`
- src/swift/core/SongDocument.swift:
  - `SongState.effects` (init default `[]`, included in `differs`);
  - `DocumentMutation` effect helpers;
  - `DocumentChange.effectsOnly: Bool` (true when every delta is an effect delta);
  - `nextEffectID` beside `nextNoteID` (`src/swift/core/SongDocument.swift:321`), outside undoable state;
  - `isDirty` is `history.isDirty`, with no special case.
- src/swift/core/DocumentChangeSet.swift: `insertEffect`, `removeEffect`, `effectConfig` and `pluginState(EffectID, before, after)` deltas, applied in both directions, and included in `isEmpty`
- src/swift/core/SongHistory.swift: `.addEffect`, `.removeEffect`, `.updateEffect(EffectID)` (gesture-coalescable within one group) and `.editPluginState(EffectID)`, in every exhaustive switch
- src/swift/core/HistoryStepLabel.swift: "add MIDI effect", "remove MIDI effect", "edit MIDI effect", and "edit plugin settings"
- src/swift/core/EventEditing.swift: remap effects inside the track add, duplicate, delete and move mutations through `TrackRemap.engineTrackMap` (`src/swift/core/SongDocument.swift:73-77`)
- src/checks/editcheck/TrackEffectModelChecks.swift (new; `@MainActor public func runTrackEffectModelChecks(_ report: CheckReport)`)

Registration (controller): Core sources. The check file goes into `swift_core_check_logic`, called from the `PDC_SUITE_NOTE_EDITS` dispatch case after `runArpeggiatorChecks`.

# Prerequisites

None. Task 1 is a parallel lane, not a dependency: there is no range validation to reuse.

# Interface contract

Exactly spec.md "Model" and "Document operations", with these details:

- **Errors.** `addEffect` throws `.trackHasEffect` unless `replacing` names that track's effect; with `replacing`, the removal and the insertion are one entry. `config.track` must map to an engine track.
- **Effect IDs.** The counter (`nextEffectID`, stored beside `nextNoteID`) never rolls back on undo or redo, so an ID is never reused within a session. `init(effects:)` starts it past the restored maximum.
- **Undoable deltas.** `DocumentChangeSet` gains `insertEffect(TrackEffect)`, `removeEffect(TrackEffect)`, `effectConfig(EffectID, before, after)` and `pluginState(EffectID, before, after)`. A config delta replays onto the current effect's config and leaves its `pluginState` untouched, so undo never rolls back plugin state. Insert and remove deltas restore the whole effect, plugin state included.
- **History operations.** `HistoryOperation` gains `.addEffect`, `.removeEffect`, `.updateEffect(EffectID)` (gesture-coalescable within one `HistoryGroup`) and `.editPluginState(EffectID)`. `HistoryStepLabel` phrases: "add MIDI effect", "remove MIDI effect", "edit MIDI effect", and "edit plugin settings".
- **Remap.** Every structural track mutation in `EventEditing.swift` (add, duplicate, delete, move) maps `config.track` through its `TrackRemap.engineTrackMap` inside the same mutation. A nil destination removes the effect in that mutation, and undo restores it.
- **Record.** `recordPluginState` commits one history entry through the normal `commit` path with a `pluginState` delta. It is a no-op when `after == before`.
- **Dirty.** `SongDocument.isDirty = history.isDirty`, with no special case.
- **Patch sites, before → after:**
  - `differs`: compares effects too.
  - `commit`: unchanged guard; effect deltas make the change set non-empty.
  - `publish`: an all-effect-delta change publishes with `effectsOnly` (no timeline rebuild, no selection reconciliation).

# Implementation steps

1. Add the types.
2. Extend `SongState`, `DocumentMutation` and `DocumentChangeSet`. A config delta's undo writes the `before` config onto the current effect and leaves `pluginState` alone.
3. Add the document operations, history cases, labels and effect-ID minting, all through the single `commit` path (`src/swift/core/SongDocument.swift:488`). The ID counter never rewinds on undo or redo.
4. Remap: in each structural track mutation, map `config.track` through `TrackRemap.engineTrackMap` before `commit`; a nil target records a `removeEffect` delta in the same mutation.
5. Dirty state per spec "Dirty".
6. Checks:
   - add, remove and update each undo and redo exactly;
   - `addEffect` on a track that already has one throws, while `replacing` makes one entry;
   - invalid tracks throw with no mutation;
   - updates in one `HistoryGroup` coalesce into one undo step, and undoing them keeps the current `pluginState`;
   - `recordPluginState` adds exactly one undo step; undo/redo restore the before/after blobs; equal state is a no-op;
   - a config edit leaves `pluginState` alone;
   - `isDirty` follows history;
   - deleting the effect's track drops the effect, and undo restores it with `pluginState`;
   - moving a track remaps `config.track`;
   - effect IDs are not reused after undoing an add;
   - every label text.

# Acceptance predicate

NAMED CHECKS (controller):

- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-noteedits`: the new model checks and arpeggiator parity.
- `uv run --no-sync dev checks --filter swiftcore-documenthistory`: history regression.
- `uv run --no-sync dev checks --filter swiftcore-eventedits`: track-structure regression after the remap changes.

# Task-specific constraints

- No flattening, bake, persistence or app code (tasks 3, 7, 9).
- `Arpeggiator.swift` is not edited.
- No new mutation path: every undoable operation goes through `DocumentMutation` and `commit`.
