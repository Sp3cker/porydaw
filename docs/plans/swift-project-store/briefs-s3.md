## Task 10: FileIo adapter

### Context
Bridges poryaaaa `VoicegroupProject` file callbacks (`readBatch` / `releaseBatch`) into Swift-owned I/O. `readBatch` runs on the store's dedicated executor thread, never the cooperative pool; parsing, decoding, and assembly stay on the ProjectIo worker and only independent file reads fan out. The C++ trampoline lives in S1's `banklease.{h,cpp}` — there is exactly one trampoline, owned by S1; this task consumes the plan.md contract and does not create a second one.

### Exact write set
- `src/swift/project/FileIo.swift` (new: `ProjectFileReader` struct, `readBatch`/`releaseBatch` closures, blob lifetime handling)
- `src/swift/project/module.modulemap.in` (new: umbrella exposing `voicegroup_loader.h` to Swift; required for S3's import)
- `src/swift/project/CMakeLists.txt` (new: `PorydawProject` Swift target wiring the modulemap)

### Prerequisites
- S1's `banklease.{h,cpp}` trampoline contract in plan.md (single-trampoline signatures, blob/error out-params, user-pointer lifetime).
- `external/poryaaaa/plugin/voicegroup_loader.h` `VoicegroupFileBlob` / `VoicegroupProject` ABI.

### Interface contract
- `ProjectFileReader.readBatch(paths:) -> [FileBlob]` fills one `VoicegroupFileBlob` per path in order; missing/unreadable files produce zero-length blobs, never throw across the C boundary.
- `releaseBatch(_:)` frees exactly the blobs `readBatch` produced; no retain after return.
- Errors use the caller-sized `error`/`errorCapacity` buffer with NUL termination; never overflow.
- Swift closures never block the cooperative pool; all blocking I/O is confined to the store's dedicated executor thread.

### Implementation steps
- Define `FileBlob` as `(bytes: [UInt8], path: String)` value; copy file bytes synchronously inside the closure.
- Implement `readBatch` as ordered loop over `paths` with `Data(contentsOf:)`-equivalent blocking read; on failure emit empty blob.
- Implement `releaseBatch` as drop of the retained buffers; no manual free of C memory.
- Expose both as `@convention(c)`-compatible closures matching S1's trampoline typedefs via the plan.md contract names.
- Wire `PorydawProject` target in `CMakeLists.txt` with the `module.modulemap.in` umbrella importing `voicegroup_loader.h`.

### Acceptance predicate
- Missing file yields empty blob and ordered output preserved; error buffer NUL-terminated and bounded.
- NAMED CHECKS: `deno task verify --filter projectstore-fileio --verbose` covers ordered batch reads, missing-file empty blobs, and release-drop symmetry.

### Task-specific constraints
- R9 (executor confinement + single trampoline): blocking reads only on the store's dedicated executor thread, never the cooperative pool; coordinate with S1 via plan.md contract, do not duplicate the trampoline.
- R8 (Windows first-party): MSVC-clean C++ at the boundary; no `Dispatch`, no `NSString` path helpers; ban `FileManager.replaceItem`, `CryptoKit` anywhere near this seam.
- See plan.md Global Constraints.

## Task 11: Project context owner

### Context
Swift-owned replacement for `VoicegroupProjectContext`: worker-confined owner of poryaaaa's project-scoped discovery state (`VoicegroupProject*`), fronting `load(target)` and `loadSamples(...)` for the store.

### Exact write set
- `src/swift/project/ProjectContext.swift` (new: `ProjectContext` final class, `open(projectRoot:)`, `load`, `loadSamples`, deinit teardown)

### Prerequisites
- Task 10 `ProjectFileReader` and the S1 trampoline contract.
- `VoicegroupProjectContext::open/load/loadSamples` semantics (worker confinement, dedicated pool only for independent reads).

### Interface contract
- `ProjectContext.open(projectRoot:) -> ProjectContext?` returns nil (no throw) when discovery state cannot be built.
- `load(target:) -> BankHandle?` borrows no memory past the call; returned handle owns its bank.
- `loadSamples(direct:wave:keysplit:tables:) -> SampleSetHandle?` passes symbol arrays as borrowed pointer/count pairs for the duration of the call.
- Deinit drains outstanding work then joins the worker; non-copyable, non-Sendable except via the store executor.

### Implementation steps
- Store `projectRoot` plus a dedicated serial executor; keep the raw `VoicegroupProject*` worker-confined.
- Implement `open` to construct discovery state synchronously on the executor; nil on failure.
- Implement `load`/`loadSamples` as synchronous worker-confined calls marshalled through the dedicated executor, returning owning handles.
- Tear down by draining then destroying discovery state in deinit; never touch the bank after teardown.

### Acceptance predicate
- Open of fixture project succeeds; unknown root returns nil; load/loadSamples round-trip matches C++ loader output.
- NAMED CHECKS: `deno task verify --filter projectstore-context --verbose` covers open-failure nil, load identity, and teardown without use-after-free.

### Task-specific constraints
- R9 (worker confinement): all `VoicegroupProject*` touches stay on the dedicated executor; parsing/decoding/assembly never hop to the cooperative pool.
- R8 (Windows first-party): no `Dispatch`, no `FileManager.replaceItem`, no `CryptoKit`; MSVC-clean bridging types only.
- See plan.md Global Constraints.

## Task 12: Value vocabulary

### Context
Ports the worker-side bank value vocabulary from `voicegroupsource.h` (worker bank values section): `VgMacro`, `VgVoice`, `VgVoiceDraft`, `VgAdsr`, `VgSynthDesc`, `VoicegroupSlotView`, `LoadedBankView`, `SetVoicegroupSlot` / `RevertBlankSlot` / `VoicegroupEditInput`, result variants, `SaveVoicegroupInput` (minus dead fields per resolved decisions).

### Exact write set
- `src/swift/project/VoiceValues.swift` (new: all value types, `vgMacroName/DisplayName/VoiceType/HasSymbol/IsCgb`, `vgAdsrFamily`, `vgDefaultAdsr`, `vgVoiceStructuralChange`, `vgSynthWaveformName/SymbolName`)

### Prerequisites
- Task 11 context handle types (`BankHandle` identity shape).
- `VgMacro` ordinal order and `VOICEGROUP_SIZE` slot count from `voicegroup_loader.h`.

### Interface contract
- `VgMacro` is `Int32`-backed with ordinals matching the C++ enum order (DirectSound … KeysplitAll); `PdVoiceValue.macro` round-trips losslessly.
- `VgVoice` is `Equatable` value semantics mirroring the C++ struct field-for-field (macro/key/pan/symbol/keysplitTable/sweep/duty/period/attack/decay/sustain/release).
- `vgVoiceStructuralChange(_:_:)` returns true iff macro or sample/wave symbol changed (scalar-only changes return false).
- `vgAdsrFamily` collapses `_alt`/`no_resample` onto base, returns -1 for keysplit/drumkit; `SaveVoicegroupInput` carries voicegroup id only (no synth-definition payload).

### Implementation steps
- Port `VgMacro` plus the five query functions with identical tables (macro word, display label, `VOICE_*` constant, symbol/CGB flags).
- Port `VgVoice`/`VgVoiceDraft`/`VgAdsr`/`VgSynthDesc` (with pulse-only equality) as `Equatable` structs.
- Port `vgAdsrFamily`, `vgSynthWaveformName`, `vgSynthSymbolName`, `vgDefaultAdsr` (symbol → family → full-sustain-with-short-release fallback), `vgVoiceStructuralChange`.
- Port `VoicegroupSlotView`/`LoadedBankView`/`SetVoicegroupSlot`/`RevertBlankSlot`/`VoicegroupEditInput`/`VoicegroupEditResult`/`VoicegroupEditAppliedResult`/`VoicegroupEditConflictResult` as value types; define `SaveVoicegroupInput` with voicegroup id only.

### Acceptance predicate
- Macro tables, ADSR family collapse, synth-desc equality, and structural-change taxonomy match C++ fixtures field-for-field.
- NAMED CHECKS: `deno task verify --filter projectstore-values --verbose` covers macro ordinals/names, ADSR family mapping, structural-change true/false matrix, and synth symbol naming.

### Task-specific constraints
- R4 (structural-vs-scalar taxonomy): only macro or sample/wave symbol flips are structural; envelope/pan/key/sweep/duty/period-only edits stay scalar.
- R5 (synthDefinitions never cross the seam): `SaveVoicegroupInput` has no synth payload; `writeSynthDefinitions`/`ensureSynthDataIncluded` do not port.
- R6 (registrationGaps never cross the seam): no gaps field anywhere in this vocabulary; `checkRegistrations`/`applyRegistrationGaps` do not port.
- See plan.md Global Constraints.

## Task 13: Line model, parser, and open

### Context
Ports `VoicegroupSource` line model plus `open`/`reload`/`parse`: per-file vs monolithic section location, `VgLineKind` classification, slot accounting, byte-conservative line storage (raw/indent/macroText/argPieces/tail, `\r` kept, `\n` stripped), pristine-bytes tracking.

### Exact write set
- `src/swift/project/VoicegroupSource.swift` (new: `VgLineKind`, `SourceLine`, `VoicegroupSource` with `open/reload`, path/loadName/section accessors, `kindAt/isEditable/voiceAt/voiceDraft`)

### Prerequisites
- Task 12 value vocabulary (`VgMacro`, `VgVoice`, `VgLineKind` ordinals).
- C loader slot-accounting rules and `voice_group NAME[, startingNote]` header convention.

### Interface contract
- `open(projectRoot:voicegroupArg:) -> Bool` resolves `""` to `_dummy`, locates file or monolithic section, parses; `error: String?` out-param on failure.
- `reload() -> Bool` re-reads the located file from disk, dropping unsaved edits and resetting pristine bytes.
- `filePath/loadName/isMonolithic/sectionLabel` match C++ accessors; `loadName` is the exact name `voicegroup_load()` resolves (also the preview shadow basename).
- `kindAt(slot:)` covers all 128 slots (`None` past last voice); `voiceAt` non-nil only for `Editable`; `voiceDraft(slot:blank:)` nil for invalid/read-only/broken slots.

### Implementation steps
- Implement locator: per-file `sound/voicegroups/<arg>.inc` first, else monolithic scan for `voicegroup<arg>` section; record `filePath`, `sectionLabel`, `loadName`, section begin/end.
- Implement parser storing raw bytes per line plus indent/macro/arg-piece/tail splits; classify `Other/Header/Editable/ReadOnlyVoice/Broken/None`; build `slotToLine` table.
- Implement `reload` as re-read plus full re-parse, clearing dirty and resetting pristine bytes.
- Implement `completeBaseName` as LAST-suffix strip (`deletingPathExtension().lastPathComponent` equivalent without `NSString` helpers).

### Acceptance predicate
- Fixture per-file and monolithic opens reproduce C++ `kindAt`/`voiceAt` for every slot; reload drops edits; loadName matches loader resolution.
- NAMED CHECKS: `deno task verify --filter projectstore-open --verbose` covers per-file open, monolithic section open, `_dummy` fallback, slot table, and reload-drop semantics.

### Task-specific constraints
- R7 (completeBaseName): LAST-suffix strip only; no `NSString` path helpers.
- R1 (byte conservation starts here): parser preserves raw/indent/arg-piece/tail and line endings exactly; pristine bytes captured at open/reload.
- R8 (Windows first-party): no `FileManager.replaceItem`, `CryptoKit`, `Dispatch`, or `NSString` path helpers; pure-Swift path math.
- See plan.md Global Constraints.

## Task 14: Voice edits

### Context
Ports the in-memory edit core: `setVoice`, `materializeBlankSlot` / `revertBlankSlotMaterialization`, `sourceBytes` / `restoreSourceBytes`, `didSave` staleness guard, `applyScalarsToToneData` scalar path.

### Exact write set
- `src/swift/project/VoiceEdits.swift` (new: `setVoice`, `materializeBlankSlot`, `revertBlankSlotMaterialization`, `sourceBytes/restoreSourceBytes`, `didSave`, `applyScalarsToToneData`, `silentPaddingVoice`, header rewrite)

### Prerequisites
- Task 13 line model, parser, and slot table.
- `voice_group` starting-note convention and silent square-wave padding rule.

### Interface contract
- `setVoice(slot:voice:) -> Bool` rewrites an existing editable line or materializes an undefined slot; false for read-only/broken/invalid slots.
- `materializeBlankSlot(slot:voice:) -> BlankSlotMaterialization?` applies only while the slot is still undefined; returns the narrow delta (firstAddedSlot/addedLines/header rewrite before/after).
- `revertBlankSlotMaterialization(_:) -> Bool` removes only a previously materialized slot when all generated bytes and rewritten header still match; conflict leaves bytes untouched.
- `didSave(savedBytes:) -> Bool` adopts a detached worker save only when no newer edit replaced the captured bytes.

### Implementation steps
- Implement `setVoice` via re-render of the single edited line from stored formatting; route blank slots through the insertion builder.
- Implement blank-slot insertion: compute insertion index, header index, starting-slot rewrite, silent-square padding lines so existing slots stay fixed; apply atomically.
- Implement narrow-delta revert: byte-compare generated lines plus header before/after; remove only on exact match, else return false without touching bytes.
- Implement `applyScalarsToToneData` via the C loader's packing; return false on type mismatch (caller must reload structurally).

### Acceptance predicate
- Edit/materialize/revert sequences reproduce C++ source bytes exactly; stale revert and stale `didSave` both refuse; scalar path agrees with loader packing.
- NAMED CHECKS: `deno task verify --filter projectstore-edits --verbose` covers rewrite-in-place, sparse materialization slot stability, narrow-delta revert accept/refuse, `didSave` staleness, and scalar-vs-structural routing.

### Task-specific constraints
- R2 (slot stability): new sparse entries use starting-note convention plus silent square padding; existing voice slots never shift.
- R3 (narrow delta): revert compares generated bytes and header before/after exactly; never restores a whole stale buffer.
- R4 (taxonomy enforcement): `applyScalarsToToneData` false on structural change forces the reload path.
- See plan.md Global Constraints.

## Task 15: Save and preview shadow-load

### Context
Ports `save`, `renderPreview`, and the pre-save audition shadow-load. RESOLVED: `synthDefinitions` never cross the seam — `swift_project_service.cpp:425` always passes `{}` — so `writeSynthDefinitions` / `ensureSynthDataIncluded` / `reopenedVoicegroupContext` / `pruneStaleBanks` do not port and the mapsChanged save path does not port; save is `source.save` only.

### Exact write set
- `src/swift/project/VoicegroupSave.swift` (new: `save()`, `renderPreview()`, `previewShadowName`, atomic write helper)

### Prerequisites
- Tasks 13–14 source model and dirty/pristine tracking.
- Loader shadow convention: preview file basename must equal `loadName`.

### Interface contract
- `save() -> Bool` writes the whole file back with only edited voice lines differing from open/reload bytes; updates pristine bytes and clears dirty on success.
- `renderPreview() -> [UInt8]` returns the whole buffer for per-file layouts, the section slice for monolithic layouts; always standalone-parseable.
- Preview shadow file uses `loadName` as basename so the loader resolves it over the real file during audition.
- No synth-definition I/O, no context reopen, no stale-bank pruning in this path.

### Implementation steps
- Implement `save` as atomic whole-file write preserving sibling line endings and trailing-newline state; refresh pristine bytes and dirty flag only on success.
- Implement `renderPreview` as whole-buffer vs section-slice branch on `isMonolithic`.
- Implement the shadow-load helper naming the temp preview file exactly `loadName` and loading through the Task 11 context.
- Delete (do not port) `writeSynthDefinitions`, `ensureSynthDataIncluded`, `reopenedVoicegroupContext`, `pruneStaleBanks`, and the `mapsChanged` branch.

### Acceptance predicate
- Saved files differ from pristine only on edited lines; previews parse standalone; shadow-load resolves the preview bank.
- NAMED CHECKS: `deno task verify --filter projectstore-save --verbose` covers byte-conservative save, dirty/pristine transitions, per-file vs section preview slicing, and shadow basename resolution.

### Task-specific constraints
- R1 (byte conservation): only edited voice lines differ; header style and line endings preserved.
- R5 (resolved dead code): synth-definition write/ensure, context reopen, stale-bank prune, and mapsChanged paths are dead — absence is required, not optional.
- R8 (Windows first-party): atomic write without `FileManager.replaceItem`; no `CryptoKit`/`Dispatch`.
- See plan.md Global Constraints.

## Task 16: Minted synths and subvoice facts

### Context
Ports the project-wide read-only fact scans that feed the browser picker: synth catalog, direct-sound/prog-wave symbols, keysplit/drumkit instruments, typical ADSR, and the single-pass `catalogScan` / `directSoundCatalog` combinators. Write paths stay dead per Task 15.

### Exact write set
- `src/swift/project/SynthCatalog.swift` (new: `VgSynthCatalog`, `VgAdsrDefaults`, `VgCatalogScan`, `VgDirectSoundScan`, `directSoundSymbols`, `progWaveSymbols`, `synthInstruments`, `keysplitInstruments`, `drumkitInstruments`, `typicalAdsr`, `catalogScan`, `directSoundCatalog`)

### Prerequisites
- Task 12 `VgSynthDesc` / `VgAdsr` / `vgDefaultAdsr` semantics.
- Sound-data file layout (`sound/direct_sound_synth_data.inc`, `set_synth_*` macros, cry/phoneme exclusion rules).

### Interface contract
- `directSoundSymbols` excludes cries and synth definitions, sorts phonemes last; `progWaveSymbols` lists wave symbols.
- `synthInstruments` returns defs in file order plus defining macro words; `available()` = defs or macros non-empty, `creatable()` = macros non-empty.
- `typicalAdsr` skips clicking/silent envelopes (release-0, DirectSound attack-0) including release-0 filler squares.
- `catalogScan` is value-identical to running each single-dataset accessor separately; `directSoundCatalog` fuses the two sound-data scans into one read.

### Implementation steps
- Port the four single-dataset scans (direct-sound symbols, synth catalog, keysplit pairs, drumkit list) with identical exclusion/sort/file-order rules.
- Port `typicalAdsr` counting with the click/silence skip exactly as specified.
- Implement `catalogScan` as one read of each voicegroup file fanning out to the four datasets; implement `directSoundCatalog` as one read of the sound-data files.
- Leave `writeSynthDefinitions` unported (dead per R5).

### Acceptance predicate
- Catalog outputs match C++ fixtures in order, exclusion, sort, and ADSR counts; fused scans equal separate scans.
- NAMED CHECKS: `deno task verify --filter projectstore-catalog --verbose` covers symbol exclusion/sort, synth file order and macro availability, keysplit/drumkit extraction, typical-Adsr skips, and fused-vs-separate scan equality.

### Task-specific constraints
- R5 (write path dead): `writeSynthDefinitions` absent; unsaved pending definitions live in memory only.
- Regression ranking note (applies here): catalog drift ranks below save/slot/conflict regressions — keep this scan read-only and order-stable.
- See plan.md Global Constraints.

## Task 17: VoicegroupStore bank logic

### Context
Ports the worker-side `DecompProject` bank core: bank records (canonical entry vs immutable publication copy), arg memo plus mtime fencing, `applyVoicegroupEdit` conflict taxonomy, materialization-token registry, and `saveVoicegroup` as write-plus-reload only with no context swap.

### Exact write set
- `src/swift/project/VoicegroupStore.swift` (new: `BankRecord`, `BankMemo`, `TokenRegistry`, `applyVoicegroupEdit`, `revertBlankSlot`, `saveVoicegroup`, `dirty` propagation)

### Prerequisites
- Tasks 11–15 (context, values, source model, edits, save).
- `VoicegroupId` identity and `LoadedBankEntry` vs `LoadedBankView` split.

### Interface contract
- `applyVoicegroupEdit(input:) -> VoicegroupEditResult`: `.applied(view + optional materialization)` on success, `.conflict(voicegroup)` as the confirmed not-applied outcome for expected-mismatch and validation no-ops; never throws for conflicts.
- Arg memo plus file-mtime fencing: stale memo or newer on-disk mtime forces reload before edit/save; silent success on unchanged memo.
- Token registry maps `materializationToken` to `BlankSlotMaterialization` for undo; unknown/expired tokens are conflicts, not crashes.
- `saveVoicegroup(id:) -> LoadedBankView?` performs write plus reload only; no source-holder context swap, no synth payload, no mapsChanged branch.

### Implementation steps
- Implement `BankRecord` holding the canonical mutable entry plus its last-published immutable view; publications copy, never alias, the canonical entry.
- Implement arg memo (voicegroup arg → file path/section) with mtime check on every edit/save entry; fence stale state to reload.
- Implement `applyVoicegroupEdit` handling `SetVoicegroupSlot` (expected nil = must-still-be-blank) and `RevertBlankSlot` ops, returning applied vs conflict per the taxonomy.
- Implement the token registry (mint on materialize, consume on revert/undo expiry) and `saveVoicegroup` as source-save then context reload republishing the view.

### Acceptance predicate
- Edit conflict matrix, memo/mtime fencing, token mint/consume, and save write-plus-reload match C++ worker behavior with no context swap.
- NAMED CHECKS: `deno task verify --filter projectstore-banklogic --verbose` covers applied-vs-conflict taxonomy, memo/mtime fencing, token registry lifecycle, dirty propagation, and save write-plus-reload republication.

### Task-specific constraints
- Regression ranking (most → least likely): 1) save byte-diff/dirty-flag drift, 2) slot shift on materialize, 3) applied-vs-conflict misclassification, 4) preview shadow basename mismatch, 5) memo/mtime fence skip causing stale edit, 6) token reuse/leak, 7) catalog/ADSR drift, 8) executor hop off the dedicated thread.
- R3/R4 (conflict taxonomy): expected-mismatch and validation no-ops are conflicts, never failures; scalar-vs-structural routing from R4 decides reload vs poke.
- R5/R6 (dead paths): no synth payload, no gaps logic, no `pruneStaleBanks`/`reopenedVoicegroupContext`/`mapsChanged` port; `saveVoicegroup` never swaps context.
- R9 (threading): all bank mutation on the store executor; no cooperative-pool hops.
- See plan.md Global Constraints.

## Task 18: Swift checks

### Context
Adds the new Swift checks for the seam in `src/checks/projectstore/` (not `src/checks/project/`, which dies at the flip). Ports the `proof.voicegroupsourceediting.txt` (98 rows) and `proof.savecore.txt` (81 rows) ledgers row-for-row; the catalog proof is retired-dead and is not ported.

### Exact write set
- `src/checks/projectstore/VoicegroupStoreChecks.swift` (new: editing ledger checks + save-core ledger checks)
- `src/checks/projectstore/CMakeLists.txt` (new: checks target wiring; no edits under `src/checks/project/`)

### Prerequisites
- Tasks 10–17 implementations under `src/swift/project/`.
- Source ledgers `src/checks/voicegroup/proof.voicegroupsourceediting.txt` (98 rows) and `src/checks/voicegroupsave/proof.savecore.txt` (81 rows).

### Interface contract
- Each ledger row becomes one named check with the same stimulus, oracle, and row id; 98 + 81 = 179 checks total, no merges or splits.
- Check names encode the ledger (`voicegroupsourceediting/<row-id>`, `savecore/<row-id>`) for traceability.
- No catalog-proof checks land in this target; retired rows stay absent.

### Implementation steps
- Port all 98 `proof.voicegroupsourceediting.txt` rows (line-model, edit, materialize/revert, scalar-vs-structural cases) into `VoicegroupStoreChecks.swift` against the Task 13–14 APIs.
- Port all 81 `proof.savecore.txt` rows (byte-conservative save, dirty/pristine, preview slice, shadow-load cases) against the Task 15/17 APIs.
- Retire the catalog proof: port zero catalog-proof rows and record the retirement in a code comment citing this task.
- Wire the `projectstore` checks target without touching `src/checks/project/`.

### Acceptance predicate
- 179 checks pass with row-id traceability; zero catalog-proof checks present; `src/checks/project/` untouched.
- NAMED CHECKS: `deno task verify --filter projectstore-checks --verbose` covers the full 98-row editing ledger plus the 81-row save-core ledger; `deno task verify --filter projectstore-checks-catalog-absent --verbose` covers catalog-proof retirement (zero catalog rows ported).

### Task-specific constraints
- R1–R4 (ledger oracles are binding): byte conservation, slot stability, narrow-delta revert, and structural-vs-scalar routing must match the ledger exactly — fix the implementation, never re-pin the row.
- R7 (paths): `loadName`/basename expectations use LAST-suffix strip.
- R8 (Windows first-party): checks run on Windows without `FileManager.replaceItem`/`CryptoKit`/`Dispatch`/`NSString` helpers.
- See plan.md Global Constraints.
