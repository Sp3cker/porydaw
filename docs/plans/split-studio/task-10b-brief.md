# Task 10b — Producer seams for Split Studio's workflow (corrective)

## Context

Task 10's workflow needs (1) a staged-aware read of the bound slot's
current kit, both to supply `expected` (R-T4-1: whole replaced state; "Keep
mine" re-reads) and to load the window, and (2) kit creation in a genuinely
UNDEFINED voice slot ("New kit in empty slot N…") with exact undo back to
undefined. Today `VoicegroupStore.applyKitEdit` refuses undefined slots
(VoicegroupStore.swift ~:271) and there is no reader. Consumer: task 10
(`KitStudioWorkflow`). Rulings R-T10-2 and R-T10-3 in
`local://split-studio-exec-rulings.md`.

## Exact write set

- `src/swift/voicegroup/KitEditInput.swift`
- `src/swift/voicegroup/VoicegroupStore.swift`
- `src/swift/voicegroup/VoiceEdits.swift` (only if the revert API needs an
  `authoritative` parameter; default preserves today's behavior)
- `src/swift/project/ProjectStore+Kit.swift`
- `src/swift/document/service/ProjectService.swift`
- `src/swift/document/ServiceBankHistory.swift`
- `src/swift/document/DocumentSession.swift` (only if required by the
  Optional parent)
- `src/checks/projectstore/VoicegroupEditingChecks.swift`
- `src/checks/workspace/SessionChecks.swift`

## Prerequisites

Tasks 2, 2b, 3, 4 (accepted, committed).

## Interface contract

1. `KitEditValue.parent: BankVoice?` and `KitEditInput.parent: VgVoice?`
   (nil = genuinely undefined slot). `KitEditInput` gains
   `materialization: BlankSlotMaterialization? = nil` (last field, default
   nil, memberwise order preserved otherwise).
2. `VoicegroupStore.applyKitEdit`: when the current slot is undefined and the
   target parent is non-nil, materialize it on the detached parent source
   with the existing `materializeBlankSlot`, then set the parent and stage
   the kit as today. Return the materialization in the existing
   `VoicegroupEditApplied` (same field the scalar path uses). When the target
   parent is nil (parent-only undo back to undefined), revert using
   `input.materialization` through the existing
   `revertBlankSlotMaterialization`; add an `authoritative` parameter
   (default false) to that API only if an authoritative replay can otherwise
   be refused by a later sibling edit. Staged in memory; publishes dirty;
   atomic.
3. `ServiceKitEditAction` stores the materialization returned by the forward
   apply and passes it on an undo whose before-parent is nil; redo
   re-materializes and records the new materialization.
4. Reader: `VoicegroupStore.kitSnapshot(id:slot:) throws -> KitSnapshot?`
   reading parent, sub-group symbol, 128 sub-group children (`[VgVoice?]`,
   nil = undefined) and `KeysplitTable?` through the SAME overlay-aware
   inputs bank builds use (staged sub-group text, staged tables), so it never
   returns stale disk content after Save to Song. nil parent ⇒ undefined slot.
   `ProjectStore.kitSnapshot(lease:slot:)` thin wrapper;
   `ProjectService.readKit(lease:slot:) -> KitEditValue` using the existing
   `bankVoice` converter; a non-kit or undefined slot yields the parent-only
   form (`subgroupSymbol ""`, `children []`, `tableName/table nil`, parent
   possibly nil).

## Implementation steps

1. Optional parent through KitEditInput/KitEditValue and converters.
2. Store materialize/revert in applyKitEdit (reuse existing APIs only).
3. History action carries/replays the materialization.
4. Reader chain.
5. Rows (below).

## Acceptance predicate

Rows:
- `swiftcore/VoicegroupStoreKitEdit::undefined-slot`: apply a drumkit to an
  undefined slot materializes it in memory (file unchanged until save), view
  dirty; a parent-only nil apply with the returned materialization restores
  undefined; save after re-apply writes the materialized line.
- `swiftcore/VoicegroupStoreKitEdit::kitSnapshot-staged`: after applyKitEdit
  (before save) `kitSnapshot` returns the staged children/table.
- `swiftcore/KitHistory::undefined-slot-undo`: session applyKitEdit on an
  undefined slot → undo restores undefined → redo re-materializes.
- `swiftcore/KitHistory::readKit`: `readKit` round-trips what applyKitEdit
  wrote, staged.

NAMED CHECKS (controller): `uv run --no-sync dev build:checks`;
`uv run --no-sync dev checks --filter projectstore-editing --filter projectstore-keysplits --filter swiftcore-bankhistory --filter swiftcore-projectsession --verbose`.

## Task-specific constraints

- No new materialization mechanism; no fake blank DirectSound voice.
- Scalar paths and their rows unchanged.
- No disk writes in apply (R-T4-3).
