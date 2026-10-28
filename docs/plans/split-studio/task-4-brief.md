# Task 4 — PorydawDocument: `applyKitEdit` + one `ServiceKitEditAction`

## Context

Fourth task of the Split Studio plan; makes Save to Song one undoable song
step. Consumer: task 10's `KitStudioWorkflow.saveToSong` calls
`DocumentSession.applyKitEdit` exactly once per save. Producers consumed:
task 3's `ProjectStore.applyKitEdit`
(store application). The existing scalar path is the pattern to mirror:
`DocumentSession.applyBankEdit(slot:value:expected:)`
(`DocumentSession.swift:376-415` — the guard/transition/record structure)
guards `bankPersistenceInFlight`, seals
bank merges, opens a history transition, applies through the service, and
records `ServiceBankAction` (`ServiceBankHistory.swift:28-126`) with a
`BankResultInbox`. Engine-level justification for registering samples at
save time: the bank loader resolves a sibling `.wav` before `.bin`
(`BankBuilder.swift:73-86`), so batch registration can precede the built
sample binaries.

## Exact write set

- Edit `src/swift/document/service/ProjectService.swift` (add
  `applyKitEdit(lease:input:expected:)`; `KitEditValue` lives here beside
  `BankVoice`)
- Edit `src/swift/document/service/ProjectService+Bank.swift` (BankVoice →
  VgVoice conversion reuse for kit rows — one new internal converter
  function if the existing one is scalar-only)
- Edit `src/swift/document/DocumentSession.swift` (add `applyKitEdit`)
- Edit `src/swift/document/ServiceBankHistory.swift` (add
  `ServiceKitEditAction` beside `ServiceBankAction`)
- Edit `src/checks/workspace/SessionChecks.swift` (rows in
  `runBankHistorySuite`)

Controller-owned: none (all files already registered).

## Prerequisites

Task 3 (interface only): `ProjectStore.applyKitEdit`, `KitEditInput`.

## Interface contract

`spec.md → PorydawDocument (task 4)` — exact signatures for `KitEditValue`,
`DocumentSession.applyKitEdit(_:expected:)`, `ProjectService.applyKitEdit`,
and the `ServiceKitEditAction` contract. Pinned behavior:

- `KitEditValue` is the document-value mirror of `KitEditInput` with
  `BankVoice` rows, the raw 128-byte table, and the `voicegroup` identity
  field (the -G arg, R11); `tableName` nil ⇔ Drumkit mode. `Equatable`
  field-wise.
- `DocumentSession.applyKitEdit` follows `applyBankEdit`'s exact guard and
  publication structure — `requireOpen`, in-flight refusal with the same
  message, `sealBankMerge` + `beginBankTransition`, service apply with
  `publishResult: false`, `finishBankTransition` recording the kit action,
  `adoptBank`, publish `[.bank, .dirty, .history]`
  (`DocumentSession.swift:376-415` is the mirrored structure). Conflicts
  throw and record nothing.
- `ServiceKitEditAction: BankHistoryAction`:
  - `historyLabel`: `"Kit <subgroupSymbol>"`.
  - `apply(direction:)` replays the **whole** kit edit in both directions:
    undo re-applies the captured `before` value (parent + children + table
    or absence), redo re-applies `after`, both through
    `service.applyKitEdit` with `expected: nil`. Replay is authoritative
    (R12): history is last-writer-wins over any song-side change, exactly
    like the scalar path; the window reconciles through the decided
    conflict behavior (spec §21 — clean → silent reload, dirty →
    `Changed in the song` bar), so undo can never be blocked by a conflict
    and a dirty window is never silently overwritten. The result is
    delivered through the shared `BankResultInbox`.
  - `isRedundant` is `before == after`.
  - `merged(with:)` returns nil against every other action kind and against
    `ServiceBankAction` (a kit edit never merges with scalar edits or other
    kit edits); `rebaseCurrent(with:)` adopts the newer `current` only when
    the newer action is a kit edit whose `voicegroup` AND `slot` equal this
    action's (R11 — the identity fields exist on the captured values);
    otherwise it no-ops.
  - `markSaved` sealing follows the existing protocol.
- `ProjectService.applyKitEdit` converts `KitEditValue` rows to
  `KitEditInput` (BankVoice→VgVoice via the same field mapping
  `bankApply` uses) and routes to the store; project failures map through
  the existing `projectFailure` wrapping.

## Implementation steps

1. Add `KitEditValue` to `ProjectService.swift` beside `BankVoice`.
2. Add the service method (and the row-converter extension if needed) per
   the contract; no publication changes — the session owns publishing.
3. Add `DocumentSession.applyKitEdit` mirroring the scalar structure
   exactly; do not invent a second transition kind.
4. Add `ServiceKitEditAction` in `ServiceBankHistory.swift` beside
   `ServiceBankAction`; share `BankResultInbox`; keep it `final` and
   `@MainActor` like its sibling.
5. Append rows to `runBankHistorySuite` (labels
   `swiftcore/KitHistory::`): apply on a scratch project flips
   `bankDirty`, records exactly one history entry with the kit label; one
   undo restores the prior parent voice AND the prior children/table (disk
   and lease views); redo re-applies; a second kit save replaces the redo
   target without merging (two entries); scalar edit after kit edit does
   not merge into the kit entry; save seals (post-save undo is not a
   merge); conflict (`expected` mismatch) throws with history unchanged;
   replay is authoritative — a song-side scalar edit between save and undo
   is overwritten by the undo replay (last writer wins, R12);
   `rebaseCurrent` adopts a newer kit action's `current` only for the same
   `voicegroup` + `slot` (R11) and no-ops otherwise.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter swiftcore-bankhistory`
  — `runBankHistorySuite` with the kit rows. Covers: one-step undoability
  in both directions, no-merge policy, sealing, conflict atomicity,
  inbox-driven bank adoption.
- `uv run --no-sync dev checks --filter swiftcore-projectsession`
  — regression: session save/domain publication interplay unchanged.
- `uv run --no-sync dev checks --filter projectstore-editing`
  — regression: store-level rows green through the new routing.

Runtime prerequisites: none; offscreen. Added rows are budgeted at 0.10 s
(plan.md budget table).

## Task-specific constraints

- Do not touch `ServiceBankAction`'s behavior or the scalar merge policy.
- The kit action never materializes blank slots — its materialization
  fields are absent by design; do not reuse the token machinery.
- `KitEditValue` carries `BankVoice` rows, not `VgVoice` (document layer
  must not import voicegroup parsing beyond what the service already does).
- No changes to `save(forceOverwrite:)` or `checkMidiConflict`.

## Controller verification

1. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter swiftcore-bankhistory`
2. `uv run --no-sync dev checks --filter swiftcore-projectsession`
3. `uv run --no-sync dev checks --filter projectstore-editing`
4. `uv run --no-sync dev format --check` on changed lines.
