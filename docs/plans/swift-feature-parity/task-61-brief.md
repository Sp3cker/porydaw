# Context

Task 61 — VG01 voicegroup source catalog + loader defaults. Close the catalog and loader proof
families (209 open rows across five ledgers) against Swift production code that already exists,
then delete the three fully closable ledgers. Proof completion + ledger closure plus one small
store interface change, not a rebuild; names the resource contract that unblocks the loader
batching rows.

1. **Census (verified this freeze)**:
   - `proof.voicegroupsourcecatalog.txt` — 110 GAP (A001–A110). Header says `Swift counterpart:
     none identified`; **stale** — counterparts execute today in `SynthCatalogChecks.swift`,
     `VoicegroupValueChecks.swift`, `VoicegroupContextChecks.swift`,
     `ProjectStoreSaveChecks.swift` (the header itself says dispositions were never re-verified at
     the S6 cutover).
   - `proof.tst_voicegrouploader.txt` — 55 GAP (A001–A055; Reference revision is the fork
     oracle fceecd88; header command/result stale). `proof.voicegrouploadfixture.txt` — 14
     GAP (A001–A014).
   - `proof.tst_voicegroupbank.txt` — 93 rows: 72 MATCHED, 19 PARTIAL, 2 GAP (A087/A088).
     Counterparts `BankLeasesChecks.swift`, `ProjectStoreSaveChecks.swift`,
     `workspace/bank_sharing.swift`.
   - `proof.voicegroupsourceediting.txt` — 98 rows: 89 MATCHED, 2 PARTIAL (A001/A042), 7 GAP
     (A002, A086–A092); counterpart `VoicegroupEditingChecks.swift` (90 S rows).
   - `VoicegroupCatalogAbsentChecks.swift` (lane `projectstore-checks-catalog-absent`) pins
     task-18's retirement audit ("zero catalog rows ported / 90 editing / 1 save-core"). Porting
     catalog rows breaks its third expect; the audit ends when the catalog ledger is deleted, so
     the suite and its lane are deleted with it.
2. **Fork laws** (`git show fceecd88:src/checks/voicegroup/…`):
   - `voicegroupsourcecatalog.cpp:32-74` — synthetic scan over a check-written `adsrcheck.inc`:
     family modes Square1 `{1,2,10,3}`, Square2Alt `{1,2,4,3}` (tie → smaller packed code),
     DirectSoundNoResample `{255,0,255,165}`, Noise `{1,0,13,2}`; symbol mode `AdsrCheckA`
     retained, unusable symbols excluded (`AdsrCheckB` attack-zero, :48); `vgDefaultAdsr`
     symbol→family→fallback (ProgWave CGB `{0,0,15,3}`, empty-defaults DirectSound
     `{255,0,255,165}`). `:76-101` — staged-fixture scan: nonempty family/symbol defaults,
     `release > 0`, chip masks (CGB max 7/7/15/7 vs DirectSound 255, sustain 15 CGB), CGB `attack
     > 0`, symbol bounds ≤ 255. `:103-228` — synth catalog: defs in file order, `find`/`symbolFor`
     both directions, `macroWords`, creatable gate; write path appends defs, converts LF→CRLF
     (`allLfAreCrLf`), wires the `data/sound_data.s` include exactly once, an identical second
     write is a byte no-op, writing an existing symbol with a different descriptor is rejected
     without mutation, bare catalog (no `set_synth_*` macros) rejects writes, unwired root rejects
     with an error naming `direct_sound_synth_data.inc`. `:230-287` — single-colon labels scan as
     samples (synth labels do not) and load natively: `voices[0].wav` size 4 / `data[0] == 0x11`,
     `voices[1]` `0x22`, `voices[2].wavePointer` non-null. `:289-332` — append `set_synth_pulse
     0x21,0x43,0x65,0x87`, `setVoice` a DirectSound slot to it, save, `voicegroup_load`:
     `tone.type & ~0x18 == 0`, `wav->size == 0`, descriptor bytes `data[2..5] == 21 43 65 87`.
   - `tst_voicegrouploader.cpp` — `:54-114` one-shot `voicegroup_load` vs
     `voicegroup_project_load` bank parity (`sameBank`), warm reload keeps bank identity and
     requests **zero** adapter reads of `direct_sound_data.inc` / `programmable_wave_data.inc` /
     `keysplit_tables.inc`; sample-set parity `voicegroup_load_samples` vs
     `voicegroup_project_load_samples` (`sameSampleSet`, symbols
     loop/pulse/fixture_keys/keysplit_fixture). `:121-148` — `voice_group check_alias_kit, 60`
     declared inside a mismatched filename resolves through the host's `voice_keysplit_all`;
     subgroup slot names 59 "" / 60 `fixture_drum` / 61 `fixture_pluck`; top-level
     `check_alias_kit` load leaves 59/62 empty, 60/61 resolved. `:150-179` — serial (width 1) and
     four-wide adapters over the 16-asset batch: identical bank, `maxInFlight == width`
     (start-gate determinism, no wall clock), `populated == released`, each path requested once.
     `:181-205` — injected transport failure on `check_batch_07.bin`: load returns null,
     `populated ≥ 1` and `== released`, then the **same context heals** and loads the expected
     bank. `:230-253` — bench guards: project open, song locate + playable, first load, warm
     reload returns the same bank (timings printed, not asserted).
   - `voicegrouploadfixture.cpp` — `kBatchAssets = 16` (:20); staging writes 16 `check_batch_NN`
     sample copies + defs + group + include append (:217-261); alias staging adds two files
     without touching the include hub (:270-294); subgroup goldens (:304-344): program 8 KEYSPLIT
     slots 0 ""/1 `fixture_loop`/2 `fixture_pulse`; 10 KEYSPLIT_ALL 36 `fixture_drum`/37 ""/38
     `fixture_pluck`; 11 36 `fixture_pluck`/37 `fixture_saw`/38 `fixture_drum`; null contracts —
     `voicegroup_subgroup_names` nil bank, nil subgroup, unregistered subgroup → NULL;
     `voicegroup_subgroup_slot_name` nil args, unregistered subgroup, slots −1/128 → NULL; deep
     compares `sameBank`/`sameSampleSet` (:346-383).
3. **Swift current state — no catalog production gap identified at freeze**:
   `SynthCatalog.swift:254-324` `scanVoicegroups` (mode, tie→smaller code, exclusions, CGB
   masks), `VoiceValues.swift:362-367` `vgDefaultAdsr`, `:348` `vgSynthSymbolName`,
   `ProjectStore+Synth.swift` `mintSynth`/`savePendingSynths` + `SynthDefinitions.write`
   (append, CRLF, assembly wiring, collision suffix), `FileIo.swift:58-78` four-wide
   `FileIoOwner.readBatch`, `VoicegroupStore.swift:91-145` memoized warm loads. Checks already
   executing: `SynthCatalogChecks` S001–S015 (sound data/gates), S017–S029a (voicegroup scan),
   S031–S034 (staged symbols); `VoicegroupValueChecks:62-79` (vgDefaultAdsr), `:131-138`
   (symbol formatting); `ProjectStoreSaveChecks:200-263` (mint dedup, no file before save,
   save survives fresh load, include wired once); `VoicegroupContextChecks` F/C rows
   (store/native parity, memo identity, sample-removal soft miss, teardown ownership);
   `BankLeasesChecks` lease journeys over `mus_gym` (midi.cfg pins `-G_fixture_rich`).
4. **Resource contract named (unblocks the batching rows)**: the loader ABI `VoicegroupFileIo`
   (`voicegroup_loader.h:225-247`, exported to Swift via `PorydawProjectNative`) —
   `voicegroup_project_open(root, config, fileIo)` accepts a **caller-supplied**
   read-batch/release-batch adapter (:257-259); hard-failure semantics and context reuse are
   documented (:262-270). Checks already import this module and call `voicegroup_load`/
   `voicegroup_free` directly (`VoicegroupContextChecks.swift:10-28`), so a check-owned
   recording adapter (width, failure suffix, requested/populated/released/maxInFlight counters)
   reproduces the fork's `BatchAdapter` (`voicegrouploadfixture.cpp:28-140`) with no production
   seam change. The sprint's "batching internals Blocked unless a resource contract is named"
   clause is satisfied; **no row of the 209 fundamentally needs `src/project/` C++**. Fallback:
   if the pinned poryaaaa submodule at build time does not honor the documented adapter
   contract, stop and report those rows Blocked-by-project-store; never edit `external/` or
   `src/project/`.

# Exact write set

- `src/checks/projectstore/VoicegroupLoaderChecks.swift` — **new**: staging helpers (16-asset
  batch, alias pair), recording `VoicegroupFileIo` adapter, subgroup goldens + null contracts,
  parity/warm/no-re-read, sample-set parity, batch-width, transport-heal, bench guards.
- `src/checks/projectstore/VoicegroupContextChecks.swift` — one line:
  `runVoicegroupLoaderChecks(report)` in `runVoicegroupContextSuite`.
- `src/checks/CMakeLists.txt` — add the new file to the projectstore source list; remove the
  `VoicegroupCatalogAbsentChecks.swift` entry.
- `src/checks/projectstore/SynthCatalogChecks.swift` — staged-fixture ADSR audibility block;
  `symbolFor` reverse mappings; single-colon temp-root native-load block (sample binaries, wave
  sizes/data bytes, `wavePointer`).
- `src/checks/projectstore/SaveCoreChecks.swift` — synth write gates: LF→CRLF of the grown file,
  idempotent re-save byte-equality, existing-symbol different-descriptor rejection without
  mutation, bare-catalog and unwired-root rejection with the named-file error; failed-save
  re-dirty predicate (edit applies after a failed save, view stays dirty).
- `src/checks/projectstore/VoicegroupEditingChecks.swift` — config-resolved baseline
  (`songMeta("mus_gym").cfg.voicegroupArgument` → `loadBank`); synth-descriptor journey
  (append `set_synth_pulse`, `setVoice` slot, save, native load, byte asserts).
- `src/checks/projectstore/BankLeasesChecks.swift` — `.applied` pattern-match updates;
  `firstAddedSlot`/`addedLines` expects on the blank-materialization result; bench guards (open,
  `mus_gym` playable, first + warm `loadBank` → equal `bankToken`).
- `src/swift/project/ProjectStore+Edit.swift` — widen
  `ProjectBankEditOutcome.applied(lease:materialization:materializationToken:)`; thread
  `applied.materialization` through `adoptedEditOutcome`.
- `src/swift/app/ProjectService.swift` — mechanical: `bankEditResult` (:787-792) ignores the new
  associated value.
- `src/checks/projectstore/VoicegroupCatalogAbsentChecks.swift` — **delete** with its
  registration: `checkcatalog.cpp:214-221`, `CoreCheckSupport.swift` case 21, `tst_swiftcore.cpp`
  `catalogAbsent` slot (:126).
- Ledgers (controller-delegated ledger agent, this task's commit scope): flip then delete
  `proof.voicegroupsourcecatalog.txt`, `proof.tst_voicegrouploader.txt`,
  `proof.voicegrouploadfixture.txt`; row flips only in `proof.tst_voicegroupbank.txt` and
  `proof.voicegroupsourceediting.txt`.

No `src/project/` or `external/` changes, no production QML, no hot files (`ShellWindow.qml`,
`ShellPresenter.swift`, `ApplicationSession.swift`, `DocumentWorkspace.swift`,
`EditorSurface.qml`, `PianoGrid.swift`, `tst_EditorDrawer.qml`, `tst_ShellWindow.qml` untouched;
disjoint from in-flight 52/53/55 and queued 54). Task-62/63 own QML presentation and save journeys
— do not touch `VoicegroupPanel.qml`, `VoiceListController.swift`, `VoicegroupSave.swift` here.
Sizing exception: one proof family over 9 files (8 check-side; 2 carry one-line production edits)
with one verification-surface set — named for the dispatch table.

# Prerequisites

None. Free-parallel by the sprint plan (61 ∥ 62 → 63); no interface consumed from in-flight tasks.

# Interface contract

- `ProjectBankEditOutcome.applied(lease: ProjectBankLease, materialization:
  BlankSlotMaterialization?, materializationToken: UInt64?)` — the record the store already mints
  (`VoicegroupStore.swift:188-190`), now published through the ProjectStore boundary exactly as
  the fork's bank API returned `firstAddedSlot`/`addedLines`. `BlankSlotMaterialization` (public,
  `VoiceValues.swift:157-171`) is unchanged. Callers updated in the same commit:
  `BankLeasesChecks.swift:90,271,281`, `ProjectService.swift:789`. `AppliedBankEdit` (app side) is
  unchanged — the app does not consume the record yet.
- New check anchors (message-anchored, one per fork clause family; the `what:`/`message:` strings
  are the ledger anchors and stay verbatim once written), cppID prefix `voicegroup/` for the
  loader file:
  - `VoicegroupLoaderChecks::parityAndWarmReuse` — "one-shot and context banks load the same
    voices, names, waves and subgroups"; "a warm context reload reuses the parsed maps without
    re-reading sound data"; "context and one-shot sample sets resolve identical waves, prog waves
    and keysplit tables".
  - `::subgroupNames` — "keysplit and drumkit subgroups publish their per-slot display names";
    "registered but unnamed subgroup slots are empty, not missing"; "subgroup name lookups reject
    null banks, null subgroups, unregistered subgroups and out-of-range slots".
  - `::declaredNameResolution` — "a declared voice_group name resolves through a mismatched file
    name"; "the declared kit loads top-level with its starting-note window".
  - `::batchAdapters` — "serial and four-wide adapters preserve the bank"; "observed batch
    concurrency is exactly the adapter width"; "every populated blob is released and each path is
    requested once".
  - `::transportFailure` — "a failed batch releases its partial blobs"; "the context heals and
    loads after a failed batch".
  - `::benchGuards` — "the project opens and locates a playable song"; "a warm reload reuses the
    loaded bank identity".
  - `swiftproject/SynthCatalogChecks::fixtureAdsr` — "fixture family defaults are audible and
    chip-bounded"; "fixture symbol defaults are audible and bounded"; `::singleColonLoad` —
    "single-colon sample labels load with exact wave bytes"; "programmable wave voices resolve a
    wave pointer".
  - `source-save/…` gates — "written synth definitions are CRLF"; "re-saving the same definitions
    is a byte no-op"; "an existing symbol with a different descriptor is rejected without
    mutation"; "projects without defining macros cannot create synths"; "an unwired project
    rejects synth writes naming the synth data file"; "an edit after a failed save republishes a
    dirty view".
  - `voicegroupsourceediting/…` — "the song's configured voicegroup argument resolves and loads
    the baseline bank"; "a saved synth descriptor loads through the voicegroup with its packed
    parameters" (bytes 21/43/65/87 at data[2..5], `wav->size == 0`, type `& ~0x18 == 0`).
  - `vgbankcheck/…` — "a blank-slot edit publishes its first added slot and generated lines"
    (`firstAddedSlot == 13` — the fixture blank slot — and non-empty `addedLines`).
- Preservation contract: production behavior in `VoicegroupStore`, `VoicegroupSource`,
  `SynthCatalog`, `FileIo`, `MintedSynths`, `ProjectContext` is unchanged (contingent edits only
  if a new predicate exposes a real divergence — record RED→GREEN for that fix only); every
  existing check message in touched files stays verbatim.

# Implementation steps

1. Widen `.applied` and update the two consumers; extend the BankLeases blank-materialization
   predicate with the record expects and the bench-guard pair. Expected GREEN (the store already
   mints the record).
2. Add `VoicegroupLoaderChecks.swift`: staging into `withTempProjectCopy` roots (copy
   `fixture_pluck.bin` 16×, append defs/include exactly as the fork helper), the recording adapter
   (start-gate width determinism, `failureSuffix` substring match, counters), then the predicate
   blocks per the contract. Native pointer work follows the `contextTone` `withMemoryRebound`
   precedent; `subGroup` (`void*`) rebinds to `ToneData`.
3. `SynthCatalogChecks` additions: audibility block over the staged fixture root (read-only scan);
   `symbolFor` expects on the existing temp catalog; the single-colon temp root writes
   `sampleBinary('\x11'/'\x22')`-style fixtures and asserts native load bytes.
4. `SaveCoreChecks` gates over `withTempProjectCopy` + injected `asm/macros/music_voice.inc` /
   `data/sound_data.s` (the :200-209 pattern); the failed-save re-dirty rides the existing
   immutable-flag failure stimulus (S04) — apply a further edit after the failed save and assert
   the applied dirty view.
5. `VoicegroupEditingChecks` additions per the contract (config-resolved baseline; descriptor
   journey through a fresh `sound/direct_sound_synth_data.inc`).
6. Delete `VoicegroupCatalogAbsentChecks.swift` + its registration sites.
7. Run the lanes below; the per-lane evidence JSONs under `build/proof-evidence/` feed the ledger
   agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter projectstore-context --verbose` — new loader predicates + existing
  F/C regressions.
- `deno task verify --filter projectstore-synthcatalog --verbose` — scan, audibility, symbolFor,
  single-colon native load.
- `deno task verify --filter projectstore-savecore --verbose` and `--filter projectstore-savebank
  --verbose` — write gates, re-dirty, save regressions.
- `deno task verify --filter projectstore-editing --verbose` and `--filter projectstore-values
  --verbose` — config-resolved baseline, descriptor journey, vgDefaultAdsr/symbol-name
  regressions.
- `deno task verify --filter bankleases --verbose` and `--filter vgbankcheck --verbose` —
  materialization publication, bench guards, lease-journey regressions (the bank ledger's recorded
  command).
- Runtime prerequisite: macOS (projectstore lanes are `Platform::MacOS`); native audio not
  required (no playback in these suites).

# Task-specific constraints

- No new C++ outside the two existing check-harness files whose registration lines change
  (`checkcatalog.cpp`, `tst_swiftcore.cpp` — deletions only); never `src/project/` or `external/`.
- No code comments — delete stale ones inside edited regions.
- Check-owned adapter memory: blobs are `malloc`-equivalent
  (`UnsafeMutablePointer<UInt8>.allocate`) and freed only in `releaseBatch`, mirroring
  `FileIo.swift:173-188`; never free in `readBatch`.
- Deterministic concurrency: the width observation uses a start gate, never wall-clock timing
  (fork :166-172); the transport-failure stimulus targets one asset by name
  (`check_batch_07.bin`).
- Implementers never edit ledgers; the controller delegates them to the ledger agent. Ledger
  mapping (agent; re-verify each row against the evidence JSONs and the fork sources cited above):
  - voicegroupsourcecatalog: A001–A003 → synthetic-scan fixture-construction rows (function anchor
    of the S017 block); A004–A008 → S022/S023/S024/S027; A009–A012 → `VoicegroupValueChecks:64-79`
    anchors; A013–A024 → new fixtureAdsr anchors; A025–A033 → S003–S008 + S031–S034; A034–A059 →
    S003–S015, ProjectStoreSaveChecks S07–S09, new write-gate anchors; A060–A073 → new
    rejection/bare/unwired anchors (+ S013 gate); A074–A095 → S001/S002 + new singleColonLoad
    anchors; A096–A110 → new descriptor-journey anchors. Delete the file when all rows are
    MATCHED/RETIRED.
  - tst_voicegrouploader: A001–A003 → staging predicate setup rows; A004–A024 → parityAndWarmReuse
    + sample-set anchors; A025–A036 → declaredNameResolution + subgroupNames anchors (slots
    59–62); A037–A043 → batchAdapters anchors; A044–A050 → transportFailure anchors; A051–A055 →
    benchGuards anchors. Refresh the stale header command/result to the lanes above. Delete when
    closed.
  - voicegrouploadfixture: A001–A008 → subgroupNames golden anchors; A009–A014 → subgroupNames
    null-contract anchors. Delete when closed.
  - tst_voicegroupbank: A063/A064 → record-publication anchors (MATCHED); A077 → config-resolved
    baseline anchor (MATCHED); A086 → saved-lease square-slot + re-dirty anchors (MATCHED);
    A087/A088 → failed-save re-dirty anchors (MATCHED under the accepted alternate stimulus — the
    same substitution A089–A093 already record; the fork's unknown-synth-definition stimulus is
    unreachable because `mintSynth` gates definitions). The remaining 15 PARTIALs
    (A001/A003/A014/A015/A017/A022/A044/A048/A049/A050/A089–A093) keep their task-37 adjudicated
    mappings — no other row moves; ledger NOT deleted.
  - voicegroupsourceediting: A001/A042 → config-resolved baseline anchor (MATCHED); A002 →
    `RETIRED-REPRESENTATION` (pins the retired Qt session-pointer guard, subsumed by the A001
    baseline; verify at the ledger's Reference revision fbe1015a); A086–A092 stay GAP — the
    retired `createVoicegroup`/`appendIncludeLine` surface has no Swift ingress and no
    `src/project/` dependency; named deferral, ledger NOT deleted.
- If any loader predicate's runtime observation contradicts the documented `VoicegroupFileIo`
  contract (§4), stop and report those rows Blocked-by-project-store instead of adjusting the
  check to the divergence.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`, `deno task format
   --check`, `deno task proof check`, `deno task proof check --executed` (pre-deletion state shows
   the three ledgers fully closed with executing anchors), then `deno task proof sites --area
   voicegroup` confirms the three deletions and the surviving open rows (bank 15 PARTIAL,
   sourceediting 7 GAP).
2. Confirm `deno task verify --filter projectstore-checks-catalog-absent` reports an unknown check
   (lane removed with its suite).
3. Store-level smoke (headless, same lanes): the materialization record surfaces in `bankleases`
   verbose output; no lane regresses against the pre-task run.
