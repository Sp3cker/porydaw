# Task 2b — Kit edits stage in memory until the song save (corrective)

## Context

User decision (Q12a, reaffirmed in Q23): Save to Song adds one song undo step
and leaves the song **dirty**. Voicegroup changes reach disk only through the
normal song save, exactly like scalar voice edits (`applyVoicegroupEdit` edits
`record.source` in memory; `saveVoicegroup(id:)` writes it). Only the slice
`.wav` files and their registrations are written at Save to Song (task 10).
Task 2's `VoicegroupStore.applyKitEdit` writes the parent, sub-group and table
files immediately. That deviates from the decision. This task makes kit edits
staged in memory and written by `saveVoicegroup(id:)`. Consumers:
task 3 (`ProjectStore.applyKitEdit` thin wrapper — unchanged signature),
task 4 (history replay; expects `bankDirty == true` after apply), task 10
(Save to Song), the song save pipeline (`ProjectStore.saveVoicegroup(lease:)`,
unchanged entry point).

## Exact write set

- Edit `src/swift/voicegroup/VoicegroupStore.swift`
- Edit `src/checks/projectstore/VoicegroupEditingChecks.swift` (rework the
  existing `editingStoreKit` rows to the staged semantics; add rows below)

No other file. `KitEditInput`, `KeysplitTableWriter`, `BankBuilder`,
`ProjectStore+*` keep their current source.

## Prerequisites

Task 2 (accepted, in tree). Rulings R-T2-1..5 and R-T4-2 in
`local://split-studio-exec-rulings.md`.

## Interface contract

Signatures do not change: `applyKitEdit(input:expectedParent:) throws ->
VoicegroupEditResult`; `saveVoicegroup(id:) throws -> LoadedBankView?`.
Behavior:

1. `applyKitEdit` performs **no disk writes**. It validates exactly as today
   (expected-parent conflict, editable slot, parent macro/symbol/children
   count, sub-group locate, table-name guard). Then it sets the parent slot in
   `record.source` in memory (as the scalar path does) and **stages** the
   edited sub-group source and the table in store-level overlays. A failed
   validation or bank build leaves the record, the overlays and the published
   view unchanged.
2. Overlays are keyed globally: staged sub-group sources by their
   `VoicegroupLocation`, and staged tables by name. Each record tracks the
   overlay keys its kit edits staged. A later kit edit to the same key replaces
   the staged value.
3. Every bank build for every record (`buildBank`, `bankBuildInputs`,
   `rebind`) sees staged content. Staged sub-group bytes are set into
   `textCache` at their location after the record's own bytes, using the
   mechanism `buildBank` already uses for the record source. Staged tables
   override the disk-parsed `keysplits` by name. Builds never read stale disk
   text for a staged key.
4. Publication: `published.dirty` is true when `record.source.dirty` OR the
   record has staged overlay keys. A kit apply therefore publishes dirty.
5. Parent-only apply (R-T4-2): an input with `subgroupSymbol.isEmpty &&
   children.isEmpty && table == nil` sets only the parent slot in memory (any
   voice kind), skips the kit guards and stages nothing. Expected-parent
   semantics are unchanged (nil = authoritative).
6. `saveVoicegroup(id:)` writes the parent source, then every staged
   sub-group source and every staged table (through
   `KeysplitTableWriter.replace`) that the record references. It is atomic:
   it reuses task 2's original-bytes restore on any failure, so either all
   files are written or none. On success it removes those keys from the
   overlays (for every record referencing them), refreshes `keysplits` from
   disk and republishes clean. On failure it throws as today, and the staged
   state is kept.
7. Lifetime: staged kit state lives exactly as long as the record's dirty
   source. Wherever the store discards or reloads a record's in-memory dirty
   source (e.g. `refreshIfStale`, reload/rebind paths), it applies the same
   rule to that record's staged keys. When no record references a key any
   longer, the key is dropped.

## Implementation steps

1. Read the full current `applyKitEdit`, `saveVoicegroup`, `buildBank`,
   `bankBuildInputs`, `rebind`, `refreshIfStale`, `publish`. Delete the
   immediate-write/rollback code from `applyKitEdit` and move the atomic
   multi-file write + restore into the save path (no copy).
2. Add the two overlays + per-record key tracking as private store state, in
   one small private type.
3. Wire overlays into every bank-build entry (step 3 of the contract).
4. Update `publish` dirty rule; implement parent-only path.
5. Rework checks (contract below).

## Acceptance predicate

Check rows in `editingStoreKit` (labels `swiftcore/VoicegroupStoreKitEdit::`):
- after apply: parent, sub-group and table files are byte-identical to
  before; published view is dirty; the published bank resolves the edited
  sub-group children and the new table (engine routing low/high keys);
- after `saveVoicegroup(id:)`: all three files contain the edit; the view is
  clean; reparse matches;
- a failing save (make the sub-group file unwritable or simulate via an
  existing hook) writes none of the files and leaves the view dirty;
- parent-only apply replaces a keysplit-all parent with a scalar voice in
  memory, stages nothing, and the save writes only the parent file;
- the existing conflict/missing-subgroup/undefined-parent atomicity rows still
  hold (now: nothing staged, nothing written).

NAMED CHECKS (controller-run):
`uv run --no-sync dev build:checks` then
`uv run --no-sync dev checks --filter projectstore-editing --filter projectstore-keysplits --filter projectstore-parity --verbose`.

## Task-specific constraints

- No new public API. No disk write anywhere in `applyKitEdit`.
- No second copy of the atomic-restore logic; it moves into the save path.
- Scalar edit behavior and its rows are unchanged.
