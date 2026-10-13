# Task 2 — PorydawVoicegroup: keysplit table writer + store kit edit

## Context

Second task of the Split Studio plan; gives the voicegroup layer the two kit
capabilities everything above it writes through. Consumers: task 3's
`ProjectStore.applyKitEdit` wraps `VoicegroupStore.applyKitEdit`; task 7
consumes the `public` blank-line constant; task 10's workflow creates new
kits at save time by combining the writer with the existing
`VoicegroupSource.createVoicegroup` + `appendIncludeLine`. Existing facts
this builds on: `KeysplitTables.parse` (`KeysplitTables.swift:44-106`) is
parse-only (the writer is its inverse for run-form tables);
`VoicegroupLocator.locateSubgroup(symbol:)` and `VoicegroupSource
.open(location:error:)` / `setVoice(slot:voice:)` / `save()`
(`VoicegroupSave.swift`) already cover sub-voicegroup line edits — this task
does NOT re-add that; the store-level kit application composes them.

## Exact write set

- Create `src/swift/voicegroup/KeysplitTableWriter.swift`
- Create `src/swift/voicegroup/KitEditInput.swift` (declares
  `public let kitBlankChildLine`)
- Edit `src/swift/voicegroup/VoicegroupSource+Create.swift` (use the
  constant at line 31 instead of the inline literal)
- Edit `src/swift/voicegroup/VoicegroupStore.swift` (add `applyKitEdit`)
- Edit `src/checks/projectstore/KeysplitTablesChecks.swift` (writer rows)
- Edit `src/checks/projectstore/VoicegroupEditingChecks.swift` (store
  kit-edit rows; append to `runVoicegroupEditingSuite`'s row list)

Controller-owned: the two source lines in
`src/swift/voicegroup/CMakeLists.txt`.

## Prerequisites

None. Task 3 consumes `KitEditInput` + `VoicegroupStore.applyKitEdit`;
task 7 consumes `kitBlankChildLine`; task 10 consumes
`KeysplitTableWriter.replace` (new-kit table creation at save).

## Interface contract

`spec.md → PorydawVoicegroup (task 2)` — exact signatures for
`KeysplitWriteError`, `KeysplitTableWriter.replace(table:inFile:)`,
`KitEditInput`, and `VoicegroupStore.applyKitEdit(input:expectedParent:)`.
Pinned behavior:

- Writer output format (matches the fixture's style,
  `src/checks/fixtures/decompproject/sound/keysplit_tables.inc`):
  a definition is `\t.align 2` + `keysplit <base>, <startingNote>` where
  `<base>` is `table.name` minus a leading `keysplit_`, followed by one
  `split <index>, <end>` line per maximal run of equal values starting at
  `startingNote` (run semantics identical to the parser's `split`
  handling: notes `lastNote..<end` get `index`). `.byte` form is never
  emitted. EOL convention and trailing-newline state come from
  `ProjectFileStore.splitLines` (`crlf`, `endsWithNewline`) — the same
  detection `SampleRegistrar.register` uses
  (`SampleRegistrar.swift:109-110`); indentation mirrors the replaced
  block's, or the file's other definitions' when appending. Replacing
  finds the existing `keysplit <base>`/`.set` definition block and swaps
  its lines in place (label and `.align` lines preserved); a table not
  present in the file appends after the last definition. Round-trip law:
  `KeysplitTables.parse(files: [path])!.table(named:).table` equals the
  written 128 bytes.
- Truncation rule (R14): runs are emitted through note 127 when
  `table.maxNote == 128` (Split Studio always writes full-range tables —
  `KitDraftCodec.table` in task 7). For tables with `maxNote < 128`, runs
  above `maxNote` are not emitted and the parser leaves those notes at
  the zero default; the round-trip law then holds for `0..<maxNote` only.
- `KitEditInput.children` nil entries write the blank template line via
  the module-`public` constant `kitBlankChildLine` declared in
  `KitEditInput.swift` (R3; the same line `createVoicegroup` writes for
  empty kits — refactor `VoicegroupSource+Create.swift:31` to use the
  constant instead of its inline literal: one definition, no copy).
- `applyKitEdit` order and atomicity: apply the parent slot edit through the
  existing scalar path (same conflict semantics as `applyVoicegroupEdit`,
  `expectedParent` = current parsed voice or nil-for-blank), open the
  sub-group via `locateSubgroup` + `open(location:)` (sub-group source NOT
  registered in `records`; it is opened, edited, saved, discarded), apply
  every child slot with `setVoice`, write the table with the writer when
  `table != nil`, save parent + sub-group, rebuild and republish ONLY the
  bound song's lease (R15 — the lease of the voicegroup whose
  `applyKitEdit` was called; same publication path as the scalar apply).
  Leases of other voicegroups referencing the same sub-group/table are NOT
  refreshed here; they refresh on their next load (stale-lease window
  recorded in spec.md §21). Any thrown conflict leaves every file
  untouched: validate all expected states and open all three sources
  before writing anything.
- Failure modes throw `VoicegroupStoreError.operationFailed` with a message
  naming the file; the sub-group symbol that cannot be located is a
  refusal, not a crash ("no sub-voicegroup <symbol> found in the project").

## Implementation steps

1. Write `KeysplitTableWriter.swift`: locate the definition by scanning the
   file's lines exactly the way `KeysplitTables.parse` does (reuse
   `AsmLine` helpers; do not invent a second line grammar). Compute the
   maximal-run `split` lines from the 128 bytes down to `maxNote` (trailing
   all-default runs above `maxNote` are not emitted; the parser leaves those
   notes at the table's zero default). Write through `ProjectFileStore
   .writeAtomic`.
2. Write `KitEditInput.swift` with the shared blank-line constant.
3. Add `applyKitEdit` to `VoicegroupStore`: gather the parent's current
   voice for expected-state comparison, apply the sequence per the contract,
   return the existing `VoicegroupEditResult` shape (materialization fields
   nil — kit edits never materialize blank slots; a kit edit onto an
   undefined parent slot is a refusal naming the slot).
4. Append check rows (existing fixtures; scratch copies under the suite's
   temp dir): writer round-trip on the decomp fixture table
   (`keysplit_fixture`); writer replace preserves sibling definitions
   byte-for-byte before/after the replaced block; writer append creates a
   new table parseable with the expected 128 bytes; CRLF file variant;
   store apply on a scratch project: drumkit edit writes parent line +
   children lines and republishes (`fixture_drums_a` slot 10 of
   `fixture_rich`), keysplit edit also rewrites the table, expected-parent
   mismatch throws with files unchanged, `children` nil entries produce the
   blank template line, sub-group symbol miss refuses.
   Row labels: `swiftcore/KeysplitTableWriter::` and
   `swiftcore/VoicegroupStoreKitEdit::`.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter projectstore-keysplits`
  — runs `runKeysplitTablesSuite` with the writer rows. Covers: round-trip
  law, replace/append, sibling preservation, EOL handling.
- `uv run --no-sync dev checks --filter projectstore-editing`
  — runs `runVoicegroupEditingSuite` with the store kit-edit rows. Covers:
  drumkit and keysplit application, republish, conflict atomicity, blank
  children, symbol-miss refusal. Existing scalar-editing rows keep passing.
- `uv run --no-sync dev checks --filter projectstore-parity`
  — regression: the bank loader parity sweep over every hub voicegroup
Runtime prerequisites: none; offscreen. Added rows are budgeted at 0.20 s
(plan.md budget table).


## Task-specific constraints

- Do not edit `KeysplitTables.swift` parse behavior, `VoicegroupSource`
  parsing, or the scalar edit/merge paths. `applyKitEdit` composes existing
  public/internal members; the only new file-writing primitive is the
  writer.
- The writer never rewrites files it was not given; it does not touch
  `voice_groups.inc` or any `.inc` other than `path`.
- No usage-count API here (task 3 owns scanning).

## Controller verification

1. Add the two source lines to `src/swift/voicegroup/CMakeLists.txt`.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter projectstore-keysplits`
3. `uv run --no-sync dev checks --filter projectstore-editing`
4. `uv run --no-sync dev checks --filter projectstore-parity`
5. `uv run --no-sync dev format --check` on changed lines.
