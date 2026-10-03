# Task 218 brief — a bank save refused by the synth-definition writer keeps the dirty record

# Context

**Released** under the user's 2026-09-28 ruling (2). The ruling covers the catalog outage
port "plus the voicegroupbank write-failure family" (sprint-3.md status header, lines
76–79). Task 215 owns the catalog outage. This task owns the write-failure family, which
has a disjoint write set and lane.

Fork contract (`tst_voicegroupbank.cpp:276-317` at the ledger pin `92f1a51f`,
`saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty`, tail):

1. The oracle saves the re-dirtied bank with the synth definition
   `DirectSoundSynth_check_missing`, `VgSynthDesc{}`.
2. The fixture defines no `set_synth_*` macros. `VoicegroupSource::writeSynthDefinitions`
   (`fceecd88:voicegroupsource.cpp:1543-1549`) therefore refuses with "this project doesn't
   define the set_synth_* macros". `DecompProject::saveVoicegroup` writes synth definitions
   before the source (`decompproject.cpp:218-227, 773-793`), so nothing is written.
3. The row asserts:
   - no refreshed bank (A089);
   - a nonempty error (A090);
   - the bank reloads with an empty error (A091);
   - the reload's bank pointer equals the dirty view's bank (A092);
   - the reload is still dirty (A093).

Swift has the same failing branch. `ProjectStore.saveVoicegroup` (`ProjectStore+Save.swift:9-18`)
calls `savePendingSynths` before the store save. `SynthDefinitions.write`
(`ProjectStore+Synth.swift:58-81`) throws
`VoicegroupStoreError.operationFailed("This project does not define the set_synth_* macros for <symbol>.")`
when no macro word exists for a pending referenced definition. The Swift seam never writes
an unreferenced, caller-supplied definition. `savePendingSynths` filters pending synths by
the bank's symbols, and `mintSynth` refuses without macros. The Swift route to the fork's
branch is therefore a synth minted while the macros exist, assigned to a slot, and then
saved after the macros disappeared.

Today the five rows are PARTIAL. They cite S046, the store write-failure row S04, which
fails under a different stimulus: the immutable flag on the source.

Surface: bank Save refusal at the project-store boundary. When the synth-definition writer
refuses, nothing is written, and the dirty bank record, its identity and its retry path
survive. (The session surfaces the thrown message through the existing Save-failure
route; unchanged here.)

Ledger spec: `src/checks/voicegroup/proof.tst_voicegroupbank.txt` A089–A093 (5 PARTIAL).
All five are behavior; none is representation.

Verify lane: `projectstore-savebank` (`runProjectStoreSaveSuite`).

Blocked rows left untouched:

- **A044 PARTIAL.** Unknown `VoicegroupId` construction needs a ghost-ID ingress, which
  is banned (sprint-3 §29).
- **The ledger's 38 strict-mapping-debt MATCHED rows** (A002–A013, A019, A021, A025, …).
  Rewriting their mappings would be a standalone reconciliation, which the workflow
  forbids.

The ledger therefore stays after this task.

No production code changes: the refusal behavior exists. This task adds the predicates
that exercise it through production store ingress.

# Exact write set

- `src/checks/projectstore/ProjectStoreSaveChecks.swift`:
  - a new file-private `saveSynthDefinitionFailureKeepsDirtyRecord(_ report: CheckReport)`;
  - one call as the last statement of `runProjectStoreSaveSuite`.

  Existing S01–S09 blocks are untouched.
- `src/checks/voicegroup/proof.tst_voicegroupbank.txt`:
  - A089–A093;
  - the two header lines naming A089–A093;
  - new S088–S092.

# Prerequisites

None. The write set is disjoint from task 215 and every other in-wave task. There are no
production interfaces consumed beyond the existing `ProjectStore` API: `open`,
`loadBank(voicegroupArg:)`, `mintSynth`, `applyVoicegroupEdit(lease:operation:)` and
`saveVoicegroup(lease:)`.

# Interface contract

The check drives only production store ingress on a `withTempProjectCopy(prefix: "projectstore-savebank")`
scratch copy, using cppID
`"vgbankcheck/VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty"`.

Setup (fail-closed; each failure reports through `report.fail` and returns):

- **Stage the macros.** Write `asm/macros/music_voice.inc` with the
  `set_synth_pulse a,b,c,d` / `set_synth_saw` / `set_synth_triangle` macros, exactly as the
  S07–S09 block stages them.
- **Open and load.** Open the store and `loadBank(voicegroupArg: "_fixture_rich")`.
- **Mint.** `mintSynth` a pulse descriptor (any fixed fields) and get the minted symbol.
- **Apply the edit.** Apply `.set` on slot 0 with `symbol = minted`, expecting the original
  voice, and get the `.applied(edited, _, _)` record. It must be dirty.
- **Remove the macros.** Overwrite `asm/macros/music_voice.inc` with content defining no
  `set_synth_` macro. Guard that
  `VoicegroupSource.directSoundCatalog(root).synths.macroWords` is now empty.

Then run `saveVoicegroup(lease: edited)`, followed by
`loadBank(voicegroupArg: "_fixture_rich")`.

Predicates (unique literals, one per fork clause):

| Row | Predicate |
|---|---|
| A089 | "a save whose synth macros vanished fails without a refreshed bank" — the save result is `.failure` |
| A090 | "the failed synth save names the missing set_synth macros" — the failure is `VoicegroupStoreError.operationFailed(message)` with `message == "This project does not define the set_synth_* macros for \(minted)."` |
| A091 | "the bank reloads after the failed synth save" — the reload is `.success` |
| A092 | "the reloaded bank keeps the edited bank token" — `current.bankToken == edited.bankToken` |
| A093 | "the reloaded bank stays dirty after the failed synth save" — `current.dirty` |

# Implementation steps

1. Add `saveSynthDefinitionFailureKeepsDirtyRecord` per the contract. Wrap the whole
   block in `do`/`catch`; a setup throw fails the row with its error. Call it at the end
   of `runProjectStoreSaveSuite`.
2. Run the lane. Confirm that the evidence file `build/debug/proof-evidence/projectstore-savebank.json`
   lists the five literals.
3. Update the ledger (the implementer owns it; single writer):
   - Append S088–S092 after S087 with the `edit` tool; `proof:edit` cannot add entry IDs.
     Each is `S0xx | saveSynthDefinitionFailureKeepsDirtyRecord | src/checks/projectstore/ProjectStoreSaveChecks.swift`
     plus one `Anchor: message "…"` line, in the table order above.
   - With `deno task proof:edit`, flip A089→S088, A090→S089, A091→S090, A092→S091,
     A093→S092 to compact MATCHED form: header + `Disposition: MATCHED` + one
     `Mapping: S0xx` line. Source context and Original expression lines are removed.
   - With `proof:edit … header`, rewrite the two header statements:
     - the "Additional Swift counterpart: …ProjectStoreSaveChecks.swift (write-failure row
       S04 only, for A089-A093)" line → "(synth-definition failure rows S088-S092, for
       A089-A093)";
     - the note sentence "A089-A093 stay PARTIAL (catalog-outage port)" → "A089-A093
       closed by task 218 on the synth-definition refusal".
   - S046 stays as is.
4. Run the acceptance commands.

# Acceptance predicate

Saving a bank whose minted synth lost its `set_synth_*` macros fails with the writer's
exact refusal message and writes nothing. The same dirty bank record (same token, still
dirty) reloads — the fork's failed-synth-save contract on the Swift store.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter projectstore-savebank --verbose
deno task proof check --executed --strict-mappings
deno task proof check --executed
```

Coverage:

- **`projectstore-savebank`** runs the five predicates and the untouched S01–S09
  regressions.
- **`--strict-mappings`** must list none of A089–A093; the pre-existing 38-row debt of
  this ledger and other ledgers' debt stays as is.
- **`--executed`** must classify S088–S092 as executed.

Gap: the session/UI consequence (Save Failed message, dock still dirty) is not a ledger
clause. It is not re-proved here.

# Task-specific constraints

- **One predicate per row.** Each A-id maps to exactly one new S entry. The literals are
  independent: the expected message is built from the minted symbol returned at setup, and
  the token is compared with the `edited` record, never re-read.
- **Scratch only.** The macro removal happens in the scratch copy.
- **Stimulus.** No immutable flag, no `chflags`, no test-only store API. Do not change
  `ProjectStore+Synth.swift` or `ProjectStore+Save.swift`.
- **Swift.** Swift 6.4; comments ≤2 lines.
- **Stop points.** Workarounds or architectural changes: stop and report.
