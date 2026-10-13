# Task 3 — PorydawProject: kit wrapper, usage scan, batch registrar, orphan delete

## Context

Third task of the Split Studio plan; the project layer's four kit
capabilities. Consumers: task 4's `DocumentSession.applyKitEdit` /
`ProjectService.applyKitEdit` call `ProjectStore.applyKitEdit`; task 9's
presenter calls `KitUsageScanner.usage` (through its `usageScan` closure)
for the "used by N" copy prompt; task 10's save pipeline validates slice
names through the R20 adapter over `SampleRegistrar.validate` +
`registerBatch`; task 12's orphan cleanup calls
`SampleRegistrar.deleteRegistration` for session-created samples the usage
scan proves unreferenced. Decisions: shared kits show usage with copy
default; orphan deletion removes the `.wav` and its
`DirectSoundWaveData_` registration; Save to Song registers all slices at
that moment (safe because the bank loader resolves a sibling `.wav` before
`.bin`, `BankBuilder.swift:73-86` — verified).

## Exact write set

- Create `src/swift/project/ProjectStore+Kit.swift`
- Create `src/swift/project/KitUsageScanner.swift`
- Edit `src/swift/project/SampleRegistrar.swift` (add `registerBatch` and
  `deleteRegistration`; do not modify existing declarations' behavior)
- Edit `src/checks/samplecheck/RegistrationChecks.swift` (batch + delete
  rows)
- Edit `src/checks/projectstore/KeysplitTablesChecks.swift` (usage-scan rows)

Controller-owned: the two new source lines in
`src/swift/project/CMakeLists.txt`.

## Prerequisites

Task 2 (interface only): `KitEditInput`, `VoicegroupStore.applyKitEdit`.

## Interface contract

`spec.md → PorydawProject (task 3)` — exact signatures for
`ProjectStore.applyKitEdit(lease:input:expectedParent:)`,
`KitUsageScanner.usage(projectRoot:subgroupSymbol:tableName:excludingSection:)`
(one signature everywhere, R13), `SampleRegistrar.registerBatch(projectRoot:
samples:)`, and `SampleRegistrar.deleteRegistration(projectRoot:name:)`.
Pinned behavior:

- `applyKitEdit` mirrors `applyVoicegroupEdit`
  (`ProjectStore+Edit.swift:16-22`): routes through the editing store,
  adopts the outcome, returns `ProjectBankEditOutcome`.
- `usage` scans the project's voicegroup sources for lines referencing
  `subgroupSymbol` as a keysplit-all or keysplit symbol argument and/or
  `tableName` as the keysplit table argument; returns the referencing
  **section labels** (deduplicated, sorted). The caller passes the kit's
  own parent section in `excludingSection` and the scanner filters it out
  (R13 — the exclusion lives in the scanner, not the callers).

- `registerBatch`: validate every name against
  `VoicegroupSource.directSoundSymbols(projectRoot)` plus the names
  registered earlier in the same call (one refusal message lists every
  offending name); then write every `.wav`; then append every registration
  block in ONE `writeAtomic` of `direct_sound_data.inc` (single indent
  scan, blocks in argument order). A failure at any stage stops before the
  next; already-written `.wav` files remain (orphan-cleanup territory) and
  the `.inc` is rewritten only on full success.
- `deleteRegistration`: removes `sound/direct_sound_samples/<name>.wav` and
  the sample's registration block — the trailing blank line (if the file
  lacked one before the block), the block's `.align 2` line, the
  `DirectSoundWaveData_<name>::` label and the `.incbin` line — from
  `direct_sound_data.inc` atomically. Unknown name (no label found) returns
  false without writing. A missing `.wav` is not an error (block still
  removed).

## Implementation steps

1. Write `ProjectStore+Kit.swift` per the contract (thin wrapper; no new
   conflict policy — task 2 owns it).
2. Write `KitUsageScanner.swift`: enumerate voicegroup files via
   `ProjectLayout(projectRoot:)` and call `.ensuringDeepScan()`
   unconditionally (deterministic, no conditional judgment), read each
   file, find `voice_keysplit_all <sym>` / `voice_keysplit <sym>, <tbl>`
   argument matches with `VoicegroupSource`'s macro parsing conventions
   (reuse `VoiceValues` spec prefixes; do not regex raw text). Map
   file+line to the enclosing section label using the same
   `declarations(in:)` scanner.
3. Extend `SampleRegistrar` with the two functions per the contract. Reuse
   the existing block-emission and indent-scan logic from `register`
   (`SampleRegistrar.swift:87-137`) — factor the shared block/indent code
   into a private helper rather than duplicating it.
4. Append check rows:
   - RegistrationChecks (`swiftcore/SampleRegistrarBatch::`): batch writes
     N wavs + one `.inc` containing N blocks in order; duplicate-in-batch
     refusal lists both names; pre-existing symbol refusal; partial-failure
     behavior (unwritable target dir) leaves `.inc` unchanged; delete
     removes exactly one block and the wav, leaving sibling blocks
     byte-identical; delete of unknown name is a no-op false; delete
     tolerates a missing wav.
   - KeysplitTablesChecks (`swiftcore/KitUsageScanner::`): against the
     decomp fixture — `fixture_drums_a` referenced by `fixture_rich`
     (excluding that section ⇒ empty); a scratch file adding a second
     referencing section ⇒ that section's label; keysplit table name
     matching (`keysplit_fixture` via `fixture_keys`); no false positives
     from comments or partial symbol matches (`fixture_drums_b` ≠
     `fixture_drums_a`).

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter samplecheck-storage`
  — `runSampleStorageChecks` with the batch/delete rows. Covers: batch
  atomicity/order/refusals, delete block surgery, no-op cases.
- `uv run --no-sync dev checks --filter projectstore-keysplits`
  — usage-scan rows. Covers: reference detection, exclusion, table-name
  matching, no partial-match hits.
- `uv run --no-sync dev checks --filter projectstore-editing`
  — regression: task 2's store rows plus the wrapper compiling and routing
  (the wrapper itself is exercised through task 4's session rows; here the
  lane must simply stay green).

Runtime prerequisites: none; offscreen. Added rows are budgeted at 0.15 s
(plan.md budget table).

## Task-specific constraints

- Do not modify `register`/`update`/`validate` behavior; the shared helper
  refactor must leave the existing registration rows byte-identical.
- `deleteRegistration` deletes ONLY the named sample's wav and block — never
  a directory, never siblings.
- `KitUsageScanner` performs no writes and holds no state (pure function of
  the project root).

## Controller verification

1. Add the two source lines to `src/swift/project/CMakeLists.txt`.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter samplecheck-storage`
3. `uv run --no-sync dev checks --filter projectstore-keysplits`
4. `uv run --no-sync dev checks --filter projectstore-editing`
5. `uv run --no-sync dev format --check` on changed lines.
