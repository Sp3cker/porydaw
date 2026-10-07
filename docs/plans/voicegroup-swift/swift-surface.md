# Swift surface: voicegroup vs project split

Scope: `src/swift/project/`, `src/swift/document/service/ProjectService*.swift`,
`src/swift/document/DocumentSession.swift`, `src/swift/app/NativeAudio.swift`,
`src/swift/app/audio/AudioRenderEngine.swift`,
`src/swift/app/voicelist/VoiceListController.swift`,
`src/swift/app/samplestudio/SampleStudioWorkflow.swift`,
`src/swift/project/CMakeLists.txt`, `src/swift/document/CMakeLists.txt`,
`src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`,
`src/checks/projectstore/*.swift`, `src/checks/fixtures/decompproject/sound/`.

## 1. File classification

| File | Class | Imports | Purpose |
|---|---|---|---|
| `src/swift/project/AsmLine.swift:1` | VOICEGROUP | `Foundation` (`AsmLine.swift:1`) | Byte-level asm line cursor: `struct AsmLine` (`AsmLine.swift:4`), `word()`, `skipSpaces()`, `consume()`, `until()`, `lines(path:)`, `text()`, `content()`, `contains()`, `equals()`, `hasPrefix()` |
| `src/swift/project/VoiceValues.swift:1-2` | VOICEGROUP | `Foundation`, `PorydawProjectNative` | `VgMacro` enum (`VoiceValues.swift:5`), `VgVoice`/`VgVoiceDraft`/`VgAdsr`/`VgAdsrDefaults`/`VgSynthDesc` (`VoiceValues.swift:22,58,69,84,95`), `VgLineKind` (`VoiceValues.swift:122`), `VoicegroupSlotView` (`VoiceValues.swift:132`), `LoadedBankView` (`VoiceValues.swift:143`), edit/save input structs (`VoiceValues.swift:163,183,196,205,211,222,238,247,253`), `VoiceMacroSpec` grammar (`VoiceValues.swift:262`), `vgMacro*`/`vgSynth*`/`vgDefaultAdsr`/`vgVoiceStructuralChange` helpers (`VoiceValues.swift:303,308,327,346,351,357,362,371,386,395`) |
| `src/swift/project/VoicegroupSource.swift:1-2` | VOICEGROUP | `Foundation` | `SourceLine` (`VoicegroupSource.swift:4`), `VoicegroupSourceConflict` (`VoicegroupSource.swift:20`), `VoicegroupSource` source model: `filePath`/`loadName`/`sectionLabel`/`projectRoot`/`voicegroupArg` (`VoicegroupSource.swift:28-33`), `lines`/`slotToLine`/`sectionBegin`/`sectionEnd`/`endsWithNewline`/`pristineSource`/`dirty` (`VoicegroupSource.swift:34-40`), `open(projectRoot:voicegroupArg:error:)` (`VoicegroupSource.swift:50`), `reload(error:)` (`VoicegroupSource.swift:98`), `kindAt` (`VoicegroupSource.swift:113`), `isEditable` (`VoicegroupSource.swift:121`), `voiceAt` (`VoicegroupSource.swift:126`), `voiceDraft` (`VoicegroupSource.swift:136`), `parse` (`VoicegroupSource.swift:220`), `rebasePreservingEdits(from:)` (`VoicegroupSource.swift:239`), catalog helpers `directSoundSymbols`/`progWaveSymbols`/`synthInstruments`/`keysplitInstruments`/`drumkitInstruments`/`typicalAdsr`/`catalogScan`/`directSoundCatalog` (declared as `VoicegroupSource` extension in `SynthCatalog.swift:325-372`) |
| `src/swift/project/VoicegroupSource+Create.swift:1-2` | VOICEGROUP | `Foundation` | `VoicegroupCreateError` (`VoicegroupSource+Create.swift:4`), `VoicegroupSource.createVoicegroup(projectRoot:name:copyFromFile:copySectionLabel:)` (`VoicegroupSource+Create.swift:13`), `appendIncludeLine(projectRoot:name:)` (`VoicegroupSource+Create.swift:67`), file-local `siblingHeaderStyle(dir:)` (`VoicegroupSource+Create.swift:105`), `copiedVoicegroupLines(_:copySectionLabel:)` (`VoicegroupSource+Create.swift:131`), `leadingWhitespace(_:)` (`VoicegroupSource+Create.swift:162`) |
| `src/swift/project/VoiceEdits.swift:3,10,117` | VOICEGROUP | `Foundation` (no import line; extension-only file) | `BlankSlotInsertion` (`VoiceEdits.swift:3`), `VoicegroupSource.setVoice(slot:voice:)` (`VoiceEdits.swift:16`), `materializeBlankSlot(slot:voice:)` (`VoiceEdits.swift:38`), `revertBlankSlotMaterialization(_:)` (`VoiceEdits.swift:57`), `sourceBytes()` (`VoiceEdits.swift:83`), plus private rebase/restore/parse helpers (`VoiceEdits.swift:117` extension) |
| `src/swift/project/VoicegroupSave.swift:1-3` | VOICEGROUP | `Foundation` | `VoicegroupSource.previewShadowName` (`VoicegroupSave.swift:5`), `save()` (`VoicegroupSave.swift:12`), `renderPreview()` (`VoicegroupSave.swift:23`), `loadPreviewedSource(using:)` (`VoicegroupSave.swift:44`) |
| `src/swift/project/SynthCatalog.swift:1` | VOICEGROUP | `Foundation` | `VgSynthCatalog` (`SynthCatalog.swift:4`), `VgCatalogScan` (`SynthCatalog.swift:22`), `VgDirectSoundScan` (`SynthCatalog.swift:32`), `CatalogLines` (`SynthCatalog.swift:39`) scanner, `VoicegroupSource` catalog extension (`SynthCatalog.swift:325`) |
| `src/swift/project/MintedSynths.swift:1-2` | VOICEGROUP | `Foundation`, `PorydawProjectNative` | `MintedSynthStorage` (`MintedSynths.swift:6`), `mintedSynthDesc(symbol:)` (`MintedSynths.swift:43`), `mintedCollisionSuffix(_:)` (`MintedSynths.swift:65`), `BankHandle.graftMintedSynths(source:)` (`MintedSynths.swift:75`) |
| `src/swift/project/VoicegroupStore.swift:1-2` | VOICEGROUP | `Foundation` | `VoicegroupStoreError` (`VoicegroupStore.swift:4`), `BankRecord` (`VoicegroupStore.swift:15`), `BankMemo` (`VoicegroupStore.swift:23`), `TokenRegistry` (`VoicegroupStore.swift:30`), `VoicegroupStore` (`VoicegroupStore.swift:54`) with `init(projectRoot:)` (`VoicegroupStore.swift:64`), `init(projectRoot:context:)` (`VoicegroupStore.swift:75`), `rebind(context:)` (`VoicegroupStore.swift:83`), `loadBank(voicegroupArg:)` (`VoicegroupStore.swift:114`), `applyVoicegroupEdit(input:)` (`VoicegroupStore.swift:178`), `revertBlankSlot(id:materializationToken:)` (`VoicegroupStore.swift:229`), `saveVoicegroup(id:)` (`VoicegroupStore.swift:241`), `preview(id:)` (`VoicegroupStore.swift:282`), `currentPublication(id:)` (`VoicegroupStore.swift:289`), `refreshIfStale(id:)` (`VoicegroupStore.swift:293`), `publish(id:source:bank:)` (`VoicegroupStore.swift:310`) |
| `src/swift/project/ProjectContext.swift:1-2` | VOICEGROUP | `Foundation`, `PorydawProjectNative` | `ProjectContext` (`ProjectContext.swift:7`), `BankHandle` (`ProjectContext.swift:59`), `SampleSetHandle` (`ProjectContext.swift:76`), `ContextWorker` (`ProjectContext.swift:90`), `WorkerResult` (`ProjectContext.swift:193`), `withSymbolPointers(_:_:)` (`ProjectContext.swift:220`) |
| `src/swift/project/FileIo.swift:1-3` | VOICEGROUP | `Foundation`, `PorydawProjectNative`, `Synchronization` | `FileBlob` (`FileIo.swift:6`), `ProjectFileReader` (`FileIo.swift:14`), `FileIoOwner` (`FileIo.swift:40`), `FileReadBatch` (`FileIo.swift:71`), `readBatchCallback` (`FileIo.swift:135`), `releaseBatchCallback` (`FileIo.swift:174`), `writeFileIoError(_:into:capacity:)` (`FileIo.swift:180`) |
| `src/swift/project/MidiCfg.swift:1-2` | PROJECT | `Foundation`, `PorydawCore` | `MidiCfg.parse` / song-flag rewrite |
| `src/swift/project/ProjectFileStore.swift:1` | PROJECT | `Foundation` | `ProjectFileStoreError`, `ProjectFileStore.exists/read/write/writeAtomic/listRecursive` |
| `src/swift/project/ProjectIdentity.swift:1` | PROJECT | (no imports) | `SongName`, `VoicegroupId`, workspace identities |
| `src/swift/project/ProjectStore.swift` | PROJECT | `Foundation` | `ProjectStore` actor, `projectContext`, `voicegroupStore`, `pickerSamples`, `publicationOwner/Revision` |
| `src/swift/project/ProjectStore+Bank.swift:1-2` | PROJECT | `Foundation`, `PorydawProjectNative` | `ProjectBankLease` (`ProjectStore+Bank.swift:7`), `ToneData.isMintedSynthDescriptor` (`ProjectStore+Bank.swift:147`), `ProjectStore.loadBank(voicegroupArg:)` (`ProjectStore+Bank.swift:157`), `adoptBankLease(view:)` (`ProjectStore+Bank.swift:167`) |
| `src/swift/project/ProjectStore+Edit.swift` | PROJECT | — | `ProjectBankEditOutcome`, `ProjectStore.applyVoicegroupEdit`/`revertBlankSlot` entrypoints |
| `src/swift/project/ProjectStore+Open.swift:1-2` | PROJECT | `Foundation`, `PorydawCore` | `ProjectSnapshot`, open/catalog/loader wiring |
| `src/swift/project/ProjectStore+Picker.swift:1-2` | PROJECT | `Foundation`, `PorydawProjectNative` | `PickerSound` (`ProjectStore+Picker.swift:5`), `PickerSampleInfo` (`ProjectStore+Picker.swift:13`), `PickerSampleCache` (`ProjectStore+Picker.swift:25`), `pickerSampleInfo()` (`ProjectStore+Picker.swift:35`), `pickerSound(symbol:kind:)` (`ProjectStore+Picker.swift:58`), `loadPickerSamples()` (`ProjectStore+Picker.swift:98`) |
| `src/swift/project/ProjectStore+Reads.swift:1` | PROJECT | `Foundation` | `BankDescriptor`, snapshot/catalog reads |
| `src/swift/project/ProjectStore+Samples.swift:1` | PROJECT | `Foundation` | `SampleCommitRequest`, sample commit + bank refresh |
| `src/swift/project/ProjectStore+Save.swift:1-2` | PROJECT | `Foundation`, `PorydawCore` | `ProjectStore.saveVoicegroup(lease:)` persisted-save path |
| `src/swift/project/ProjectStore+Synth.swift:1` | PROJECT | `Foundation` | `ProjectStore.mintSynth(_:)`/`savePendingSynths`/`write` |
| `src/swift/project/SampleRegistrar.swift`, `SampleRegistrar+Committed.swift` | PROJECT | `Foundation` | sample registration probe/perform + committed WAV replace/read |
| `src/swift/project/SongCatalog.swift`, `SongModel.swift` | PROJECT | `Foundation` | song table / player data |
| `src/swift/project/SongRegistration*.swift` (5 files), `SongsMk.swift` | PROJECT | `Foundation` | registration/removal/store/writes/debug + songs.mk |
| `src/swift/project/CMakeLists.txt`, `module.modulemap.in` | BUILD | — | module sources list |

PROJECT → VOICEGROUP references (symbol, ref):

- `VoicegroupSource` used by `ProjectStore+Picker.swift:101-103` (`directSoundSymbols`, `progWaveSymbols`, `keysplitInstruments`), `VoicegroupStore.swift:124,141,148,165-166` (open/rebase/graft/publish), `ProjectStore+Synth.swift` (resolve/mint path), `ProjectStore+Open.swift` (catalog/store open).
- `VoicegroupStore` / `LoadedBankView` used by `ProjectStore+Bank.swift:157-172` (`store.loadBank`, `adoptBankLease(view:)`).
- `VgSynthDesc` / `mintedSynthDesc` / `vgSynthSymbolName` used by `ProjectStore+Synth.swift:3-9` and `ProjectStore+Bank.swift:147` (`isMintedSynthDescriptor`).
- `VgVoice` / `VgMacro` / `VoicegroupSlotView` / `VgLineKind` used by `ProjectStore+Edit.swift:7-15`, `ProjectStore+Bank.swift:13`, `VoiceListController` (`src/swift/app/voicelist/VoiceListController.swift:74` bank-view comment; `VoiceListController+Bank.swift:37` slots).
- `ProjectContext.load/loadSamples` used by `VoicegroupStore.swift:93,162,208,258,283` and `ProjectStore+Picker.swift:105`.
- `BankHandle.graftMintedSynths` used by `VoicegroupStore.swift:97,165,265` and `VoicegroupSave.swift:62`.
- `VoicegroupSource.save/renderPreview/loadPreviewedSource/setVoice/materializeBlankSlot/revertBlankSlotMaterialization/sourceBytes` used by `VoicegroupStore.swift:208,248,283`, `ProjectStore+Save.swift:4-9`, `ProjectStore+Edit.swift:7-15`.
- `VoicegroupSource.createVoicegroup/appendIncludeLine` used by workspace voicegroup-creation probes (`workspace/voicegroup_creation` checks) via `ProjectStore`/`ProjectService` creation path.
- `VgCatalogScan` / `VgDirectSoundScan` / `VgSynthCatalog` / `VgAdsrDefaults` consumed by `ProjectService+Bank.swift:22-60` (`voicegroupCatalog()` mapping to `VoicegroupCatalog`).

VOICEGROUP → PROJECT references (what moves down must shed or take along):

- `ProjectFileStore.exists/read/write/writeAtomic/listRecursive` used by `VoicegroupSource.swift:66-67,76-82,99` (`open`, `reload`), `VoicegroupSave.swift:17,55` (`save`, `loadPreviewedSource`), `VoicegroupSource+Create.swift:19,25,35,59,68` and `SynthCatalog.swift:150-166` (`files(directory:recursive:)`, `voicegroupFiles`).
- `VoicegroupId` (declared in `ProjectIdentity.swift:49-53`) used by `VoicegroupStore.swift:16,24,32,54-58,114,229,241,282,289,293,310` (`BankRecord.id`, `BankMemo.id`, `TokenRegistry.Entry.id`, all public method signatures).
- `PorydawProjectNative` C symbols (`LoadedVoiceGroup`, `LoadedSampleSet`, `ToneData`, `WaveData`, `voicegroup_free`, `voicegroup_free_samples`, `VOICE_*`, `VG_VOICE_NAME_LEN`, `VOICEGROUP_SIZE`, `voicegroup_subgroup_slot_name`) stay in C; both sides import them (`ProjectContext.swift:2`, `MintedSynths.swift:2`, `ProjectStore+Bank.swift:2`, `ProjectStore+Picker.swift:2`, `VoiceValues.swift:2`).
- No other PROJECT types are referenced from VOICEGROUP files; `ProjectStore`, `ProjectSnapshot`, song/registration/MIDI symbols do not appear in VOICEGROUP files.

Outside `src/swift/project/` consumers:

- `ProjectService.loadBank(voicegroupArg:)` (`src/swift/document/service/ProjectService+Bank.swift:9`) calls `store.loadBank` (`ProjectService+Bank.swift:12`) and publishes `AppliedBankEdit` (`ProjectService+Bank.swift:13-14`); also `ProjectService+Bank.swift:148,164` (history reload path builds `midiBytes/bank/bankSlots`).
- `ProjectService.voicegroupCatalog()` (`ProjectService+Bank.swift:22`) reads `store.voicegroupCatalog()` (`ProjectService+Bank.swift:33`) and maps `groups.typicalAdsr` / `groups.keysplits` / `direct.synths.defs` (`ProjectService+Bank.swift:38,46,54,56,59`).
- `DocumentSession.bankLease/bankSlots/bankDirty/bankLoadName` (`src/swift/document/DocumentSession.swift:94-97`) project to `sharedBank.value` (`DocumentSession.swift:95`); `service.loadBank` awaited at `DocumentSession.swift:378,408`.
- `VoiceListController+Bank.swift:37` refreshes from `session.bankSlots`; `VoiceListController.swift:74` documents bank-view reading.
- `SampleStudioWorkflow.swift` consumes `ProjectService+Picker.swift` / `ProjectService+Samples.swift` picker/commit APIs (picker sound + sample commit), not the store directly.

## 2. Visibility list (non-`public` decls in VOICEGROUP files used outside `src/swift/project/` or from PROJECT files)

Access levels as declared; each entry lists declaration then every external reference found by per-symbol `grep` scoped to `src/swift`.

- `AsmLine` — `internal struct` (`AsmLine.swift:4`).
  Refs: `SynthCatalog.swift` label/incbin/word scanners (same module, VOICEGROUP-internal); check suites `SynthCatalogChecks.swift`, `VoicegroupValueChecks.swift`, `VoicegroupLoaderChecks.swift` construct/parse via public wrappers only — no direct outside-module use (struct is internal to `PorydawProject` module; split requires `public`).
- `VoiceMacroSpec` — `internal struct` (`VoiceValues.swift:262`); members `macro/word/category/symbolField/argumentCount/adsrFamily/prefix` (`VoiceValues.swift:263-269`), `all` (`VoiceValues.swift:282`), `forMacro(_:)` (`VoiceValues.swift:299`).
  Refs: `SynthCatalog.swift` voice-macro dispatch (`voiceMacro(_:text:)`, `voiceFields`) — VOICEGROUP-internal. Public wrappers `vgMacroName/vgMacroHasSymbol/vgAdsrFamily/vgMacroIsCgb` (`VoiceValues.swift:303,346,351,357`) are the PROJECT-visible surface. Split: keep internal if `SynthCatalog.swift` moves too (it does); otherwise make `public`.
- `VoicegroupSourceConflict` — `internal struct` (`VoicegroupSource.swift:20`).
  Refs: `VoicegroupStore.swift:249` (`catch let conflict as VoicegroupSourceConflict` in `saveVoicegroup(id:)`); `VoicegroupSource.swift:13-15,249-252` (throw sites). Split: must become `public` (or map to `VoicegroupStoreError` at seam).
- `VoicegroupCreateError` — `internal struct` (`VoicegroupSource+Create.swift:4`).
  Refs: `ProjectStore`/`ProjectService` creation path surfaces its `localizedDescription` only. Split: `public` if thrown across seam.
- `ProjectContext` — `internal final class` (`ProjectContext.swift:7`); `Target` (`ProjectContext.swift:8`), `projectRoot` (`ProjectContext.swift:18`), `open(projectRoot:)` (`ProjectContext.swift:26`), `load(target:)` (`ProjectContext.swift:40`), `loadSamples(direct:wave:keysplit:tables:)` (`ProjectContext.swift:44`).
  Refs: `VoicegroupStore.swift:56,64-75,83-91,162,208,258` (owns/calls context); `ProjectStore+Picker.swift:99,105` (`projectContext.loadSamples`); `VoicegroupSave.swift:44,59` (`loadPreviewedSource(using:)`). `ProjectContext` is `internal` but used by PROJECT file `ProjectStore+Picker.swift:99,105` — split edit: `public`.
- `BankHandle.raw` — `internal let` (`ProjectContext.swift:60`); `mintedStorage` — `internal var` (`ProjectContext.swift:63`); `init(raw:)` — `fileprivate` (`ProjectContext.swift:65`).
  Refs `.raw`: `ProjectStore+Bank.swift:42,100,117` (voice names/subgroup/voices pointer math); `ProjectStore+Picker.swift:37,64-65,70-71,76-78` (sample-set reads are `SampleSetHandle.raw`; bank `.raw` not read in picker); `MintedSynths.swift:80` (`raw.pointee.voices` graft); checks construct via `context.load` only. `mintedStorage` refs: `MintedSynths.swift:92-93` (lazy graft storage). Split: `raw`/`mintedStorage`/`graftMintedSynths` must be at least `internal` in the leaf module with `@usableFromInline` or `public` accessors for the PROJECT lease readers.
- `SampleSetHandle.raw` — `internal let` (`ProjectContext.swift:77`); `init(raw:)` — `fileprivate` (`ProjectContext.swift:79`).
  Refs: `ProjectStore+Picker.swift:37,64,70,76,78` (every picker metadata/sound read dereferences `set.raw.pointee.{count,waves,progWaveCount,progWaves,keysplitCount,keysplits}`). Split: `public` (or move picker cache down).
- `ContextWorker` — `private final class` (`ProjectContext.swift:90`); `WorkerResult` — `private` (`ProjectContext.swift:193`); `withSymbolPointers` — `private func` (`ProjectContext.swift:220`).
  Refs: none outside `ProjectContext.swift`. No split edit.
- `FileBlob` — `internal struct` (`FileIo.swift:6`); `ProjectFileReader` — `internal struct` (`FileIo.swift:14`).
  Refs: `ProjectContext.swift` worker owns `ProjectFileReader` (VOICEGROUP-internal). PROJECT files do not name them. Split: stay internal.
- `MintedSynthStorage` — `internal final class` (`MintedSynths.swift:6`); `graft(slot:descriptor:)` — `internal func` (`MintedSynths.swift:24`).
  Refs: `ProjectContext.swift:63` (`mintedStorage` field type); `MintedSynths.swift:92-94` (graft). PROJECT files never name the type. Split: stay internal.
- `BankHandle.graftMintedSynths(source:)` — `internal func` (`MintedSynths.swift:75`).
  Refs: `VoicegroupStore.swift:97,165,265` (`rebind`/`loadBank`/`saveVoicegroup` graft after every `context.load`); `VoicegroupSave.swift:62` (preview graft). All callers are VOICEGROUP files. Split: stay internal.
- `VoicegroupSource.loadPreviewedSource(using:)` — `internal func` (`VoicegroupSave.swift:44`).
  Refs: `VoicegroupStore.swift:91` (`rebind` dirty branch), `VoicegroupStore.swift:208` (`applyVoicegroupEdit`), `VoicegroupStore.swift:283` (`preview(id:)`). All VOICEGROUP-internal callers. Split: `public` only if PROJECT calls preview directly (today it goes through the store).
- `VoicegroupStore.rebind(context:)` (`VoicegroupStore.swift:83`), `currentPublication(id:)` (`VoicegroupStore.swift:289`), `refreshIfStale(id:)` (`VoicegroupStore.swift:293`), `modificationTime(_:)` (`VoicegroupStore.swift:306`), `publish(id:source:bank:)` (`VoicegroupStore.swift:310`), `context` (`VoicegroupStore.swift:56`), `init(projectRoot:context:)` (`VoicegroupStore.swift:75`) — all `internal`/`private`.
  Refs: `ProjectStore+Bank.swift:167` (`adoptBankLease`), `ProjectStore+Open.swift` (`rebind` on sample commit), `ProjectStore+Save.swift`/`ProjectStore+Edit.swift` (via public `loadBank/applyVoicegroupEdit/saveVoicegroup`). Split: `rebind`/`currentPublication` become seam API if PROJECT keeps driving refresh; today only `ProjectStore` (PROJECT) calls them.
- `PickerSampleCache` — `internal struct` (`ProjectStore+Picker.swift:25`) in a PROJECT file; `loadPickerSamples()` — `private` (`ProjectStore+Picker.swift:98`).
  Refs: `ProjectStore+Picker.swift:36,59` (self-file only). `ProjectService+Picker.swift` reaches it only through public `pickerSampleInfo()/pickerSound(symbol:kind:)`. No split edit unless picker moves down.
- `CatalogLines` — `private enum` (`SynthCatalog.swift:39`); helpers `files(directory:recursive:)` / `voicegroupFiles(_:)` (`SynthCatalog.swift:149-166` per grep), `scanSoundData`/`scanVoicegroups` internals.
  Refs: VOICEGROUP-internal (`VoicegroupSource.directSoundSymbols/progWaveSymbols/...` wrappers at `SynthCatalog.swift:326-372`). PROJECT reaches catalogs only via those public wrappers + `ProjectService+Bank.swift:33-59`. Split: stay `private`/`internal`.
- `siblingHeaderStyle` (`VoicegroupSource+Create.swift:105`), `copiedVoicegroupLines` (`VoicegroupSource+Create.swift:131`), `leadingWhitespace` (`VoicegroupSource+Create.swift:162`), `mintedCollisionSuffix` (`MintedSynths.swift:65`) — `fileprivate`/`private`; no external refs. No split edit.
- `BlankSlotInsertion` (`VoiceEdits.swift:3`) — `private`; `VoicegroupSource` private extension (`VoiceEdits.swift:117`) — no external refs. No split edit.
- `readBatchCallback` (`FileIo.swift:135`), `releaseBatchCallback` (`FileIo.swift:174`), `writeFileIoError` (`FileIo.swift:180`) — `private`; used only by `ProjectFileReader`/`FileIoOwner`. No split edit.
- `FileIoOwner` (`FileIo.swift:40`), `FileReadBatch` (`FileIo.swift:71`) — `private`; no external refs. No split edit.
- `BankRecord` (`VoicegroupStore.swift:15`), `BankMemo` (`VoicegroupStore.swift:23`), `TokenRegistry` (`VoicegroupStore.swift:30`) — `private`; no external refs. No split edit.

Visibility count: 17 non-`public` declarations needing a split edit if the seam is drawn at the file list in §1
(`AsmLine`, `VoiceMacroSpec`, `VoicegroupSourceConflict`, `VoicegroupCreateError`, `ProjectContext` + 4 members,
`BankHandle.raw`, `BankHandle.mintedStorage`, `SampleSetHandle.raw`, `graftMintedSynths`,
`loadPreviewedSource`, `VoicegroupStore.rebind`, `VoicegroupStore.currentPublication`).

## 3. Native handles

- `ProjectContext` — `internal final class` (`ProjectContext.swift:7`).
  - `struct Target: Sendable` (`ProjectContext.swift:8`): `let filePath: String` (`ProjectContext.swift:9`), `let sectionLabel: String` (`ProjectContext.swift:10`), `init(filePath:sectionLabel: = "")` (`ProjectContext.swift:12`).
  - `let projectRoot: String` (`ProjectContext.swift:18`); `private let worker: ContextWorker` (`ProjectContext.swift:19`); `private init(projectRoot:worker:)` (`ProjectContext.swift:21`).
  - `static func open(projectRoot:) -> ProjectContext?` (`ProjectContext.swift:26`): nil unless existing directory (`ProjectContext.swift:28-30`); builds `ContextWorker` + `open()` (`ProjectContext.swift:32-33`), `shutdown()` on failure (`ProjectContext.swift:34`).
  - `func load(target: Target) -> BankHandle?` (`ProjectContext.swift:40-42`): forwards to worker.
  - `func loadSamples(direct:wave:keysplit:tables:) -> SampleSetHandle?` (`ProjectContext.swift:44-50`): nil unless `keysplit.count == tables.count` (`ProjectContext.swift:45`) and counts fit `Int32` (`ProjectContext.swift:46-47`).
  - `deinit` (`ProjectContext.swift:52-54`): `worker.shutdown()`.
- `BankHandle` — `public final class: @unchecked Sendable` (`ProjectContext.swift:59`).
  - `internal let raw: UnsafeMutablePointer<LoadedVoiceGroup>` (`ProjectContext.swift:60`).
  - `internal var mintedStorage: MintedSynthStorage?` (`ProjectContext.swift:63`).
  - `fileprivate init(raw:)` (`ProjectContext.swift:65`).
  - `deinit` (`ProjectContext.swift:69-71`): `voicegroup_free(raw)`.
- `SampleSetHandle` — `public final class: @unchecked Sendable` (`ProjectContext.swift:76`).
  - `internal let raw: UnsafeMutablePointer<LoadedSampleSet>` (`ProjectContext.swift:77`).
  - `fileprivate init(raw:)` (`ProjectContext.swift:79`).
  - `deinit` (`ProjectContext.swift:83-85`): `voicegroup_free_samples(raw)`.
- `ContextWorker` — `private final class: @unchecked Sendable` (`ProjectContext.swift:90`): owns `projectRoot`, `ProjectFileReader`, `NSCondition` mailbox, `jobs`, `stopping/exited`, native `project: OpaquePointer?`; `init(projectRoot:)` starts thread; `open/load/loadSamples/shutdown/execute/run` (all `ProjectContext.swift:90-191`).

External uses (outside declaring file):

- `.raw` (bank): `ProjectStore+Bank.swift:42` (voice-names pointer math in `voiceName(at:)`); `ProjectStore+Bank.swift:100` (`voicegroup_subgroup_slot_name(UnsafePointer(bank.raw), subgroup, key)` in `drumPadNames(at:)`); `ProjectStore+Bank.swift:117` (voices base pointer in `voices`); `MintedSynths.swift:80` (`raw.pointee.voices` graft). (`SourceLine.raw` hits in `VoiceEdits.swift:42-126,219-277` and `RulerMenuPresenter.swift:122-124` are unrelated byte buffers, not handles.)
- `.raw` (sample set): `ProjectStore+Picker.swift:37` (`cache.set.raw.pointee` copied to `set` for metadata loop); `ProjectStore+Picker.swift:64-65` (count + `waves[index]` for `sample` kind); `ProjectStore+Picker.swift:70-71` (`progWaveCount` + `progWaves[index]` for `wave` kind); `ProjectStore+Picker.swift:76-78` (`keysplitCount` + `keysplits[index]` for `keysplit` kind).
- `context.load(`: `VoicegroupStore.swift:93` (`rebind` clean branch loads `filePath`/`sectionLabel`); `VoicegroupStore.swift:162` (`loadBank` fresh load by absolute `path`); `VoicegroupStore.swift:258` (`saveVoicegroup` reload from `record.source.filePath`); `VoicegroupSave.swift:59` (preview staging load by temp path + `sectionLabel`).
- `loadSamples(`: `ProjectStore+Picker.swift:105` (`projectContext.loadSamples(direct:wave:keysplit:tables:)`; on success wraps in `PickerSampleCache` at `ProjectStore+Picker.swift:109-111` and memoizes to `pickerSamples` at `ProjectStore+Picker.swift:112`).
- `loadPreviewedSource(`: `VoicegroupStore.swift:91` (`rebind` dirty-source branch); `VoicegroupStore.swift:208` (`applyVoicegroupEdit` builds edited bank, restores `before` bytes on nil at `VoicegroupStore.swift:209-211`); `VoicegroupStore.swift:283` (`preview(id:)` returns staged self-contained bank).
- `graftMintedSynths(`: `VoicegroupStore.swift:97` (`rebind` clean branch); `VoicegroupStore.swift:165` (`loadBank` fresh bank); `VoicegroupStore.swift:265` (`saveVoicegroup` reloaded bank); `VoicegroupSave.swift:62` (preview handle before return).
- `renderPreview(`: `VoicegroupSave.swift:55` (staged bytes written to temp `previewShadowName.inc`); preview rendering itself at `VoicegroupSave.swift:23-33` (monolithic → section slice with LF; else full `sourceBytes()`).
- `mintedStorage`: only `MintedSynths.swift:92-93` (lazily created per grafted bank, pinned by `BankHandle` until `voicegroup_free`); no PROJECT reader.

`ProjectBankLease.engineVoices` + `bankSlots` chain:

- `ProjectBankLease` (`ProjectStore+Bank.swift:7`): `let bank: BankHandle` (`ProjectStore+Bank.swift:8`); `public id/loadName/sectionLabel/dirty/slotViews/publicationOwner/publicationRevision` (`ProjectStore+Bank.swift:9-15`); `init(bank:view:publicationOwner:publicationRevision:)` (`ProjectStore+Bank.swift:17`); `sharesBank(with:)` (`ProjectStore+Bank.swift:29`); `subscript(slot:)` value copy (`ProjectStore+Bank.swift:34`); `voiceName(at:)` (`ProjectStore+Bank.swift:39`); `subvoiceMacros(at:)` (`ProjectStore+Bank.swift:56`); `drumPadNames(at:)` (`ProjectStore+Bank.swift:93`); `@unsafe public var engineVoices` (`ProjectStore+Bank.swift:114`) returning `voices` (`ProjectStore+Bank.swift:116-118`: `bank.raw + voicesOffset` rebound to `ToneData`); `voicesOffset`/`voiceNamesOffset` from `MemoryLayout<LoadedVoiceGroup>.offset(of:)` (`ProjectStore+Bank.swift:129-141`); `ToneData.isMintedSynthDescriptor` (`ProjectStore+Bank.swift:147`).
- `ProjectStore.loadBank(voicegroupArg:)` (`ProjectStore+Bank.swift:157-161`) → `store.loadBank` → `adoptBankLease(view:)` (`ProjectStore+Bank.swift:167-173`, bumps `publicationRevision`).
- `ProjectService.loadBank` (`ProjectService+Bank.swift:9-19`) → `appliedBank(bank, token:)` + `publish` (`ProjectService+Bank.swift:13-14`).
- `DocumentSession.bankLease` (`DocumentSession.swift:94`) / `bankSlots` (`DocumentSession.swift:95`: `sharedBank.value.slots`) / `bankDirty` (`DocumentSession.swift:96`) / `bankLoadName` (`DocumentSession.swift:97`); bank adopted at `DocumentSession.swift:381` (`adoptBank(bank)` after `service.loadBank` at `DocumentSession.swift:378`); history path at `DocumentSession.swift:408`.
- `DocumentWorkspace` bank domain: `audio.updateVoicegroup(session.bankLease)` (`src/swift/app/DocumentWorkspace.swift:490`).
- `NativeAudio.updateVoicegroup(_ bank: ProjectBankLease)` (`src/swift/app/NativeAudio.swift:120-125`): `device.renderer.updateVoicegroup(bank.engineVoices)` (`NativeAudio.swift:122`), retains `bankLease = bank` (`NativeAudio.swift:123`); `bind(timeline:bank:settings:)` reads `bank.engineVoices` the same way (`NativeAudio.swift:90`, retains at `NativeAudio.swift:91`); export capture reads `capture.lease.engineVoices` (`src/swift/app/export/WavExportJob.swift:43`).
- `AudioRenderEngine.updateVoicegroup(_ voicegroup: UnsafeMutablePointer<ToneData>?)` (`src/swift/app/audio/AudioRenderEngine.swift:169-180`): `m4a_engine_all_sound_off` (`AudioRenderEngine.swift:171`), stores `self.voicegroup` (`AudioRenderEngine.swift:173`), `m4a_engine_set_voicegroup(main, voicegroup)` (`AudioRenderEngine.swift:174`), chase/prime + `resetPreview()` (`AudioRenderEngine.swift:176-179`).
- `bankSlots` UI fan-out (all read `DocumentSession.bankSlots` / `session.bankSlots`): `SongTabsController.swift:163,170`, `VelocitySceneValues.swift:29`, `VoiceChangesPublication.swift:26`, `VoiceChangesPage.swift:168,235,318`, `PianoGrid+SceneSync.swift:45-46`, `VoiceListController+Bank.swift:37`, `PolyphonyPanelPresenter.swift:125`, `TrackHeadersGeometry.swift:288-294`, `HeaderVoicePicker.swift:41,63`, `EventListPresenter.swift:624`.

## 4. VoicegroupStore

Public + internal API (all `VoicegroupStore.swift` unless noted):

- `init(projectRoot:) throws` (`VoicegroupStore.swift:64`): opens `ProjectContext`; throws `operationFailed` when loader cannot open.
- `init(projectRoot:context:)` (`VoicegroupStore.swift:75`, internal): shares store-owned loader.
- `rebind(context:) -> [LoadedBankView]` (`VoicegroupStore.swift:83`, internal): swaps loader; per record reloads — dirty sources via `loadPreviewedSource` (`VoicegroupStore.swift:91`), clean via `context.load` + `graftMintedSynths` (`VoicegroupStore.swift:93-97`); republishes (`VoicegroupStore.swift:101-103`).
- `loadBank(voicegroupArg:) throws -> LoadedBankView` (`VoicegroupStore.swift:114`, public): memo fast path when `sourceFileTime` matches (`VoicegroupStore.swift:116-122`); else `VoicegroupSource.open` (`VoicegroupStore.swift:126`), `VoicegroupId` from relative path + section (`VoicegroupStore.swift:131-134`), `modificationTime` (`VoicegroupStore.swift:138`); record hit with unchanged mtime returns publication (`VoicegroupStore.swift:141-145`); changed mtime tries `rebasePreservingEdits` (`VoicegroupStore.swift:148`) and returns rebased publication (`VoicegroupStore.swift:152-160`); otherwise `context.load` (`VoicegroupStore.swift:162`), `graftMintedSynths` (`VoicegroupStore.swift:165`), `publish` + record/memo (`VoicegroupStore.swift:166-171`).
- `applyVoicegroupEdit(input:) throws -> VoicegroupEditResult` (`VoicegroupStore.swift:178`, public): `refreshIfStale` first (`VoicegroupStore.swift:179`); `.set` with `expected` requires `voiceAt == expected` + `setVoice` (`VoicegroupStore.swift:188-193`); `.set` without expected requires empty slot + `materializeBlankSlot` (`VoicegroupStore.swift:195-201`, mints token at `VoicegroupStore.swift:216`); `.revert` requires `revertBlankSlotMaterialization` (`VoicegroupStore.swift:202-205`); rebuilds via `loadPreviewedSource` (`VoicegroupStore.swift:208`); restores `before` bytes on load failure (`VoicegroupStore.swift:209-211`).
- `revertBlankSlot(id:materializationToken:) throws -> VoicegroupEditResult` (`VoicegroupStore.swift:229`, public): consumes single-use token (`VoicegroupStore.swift:230`), dispatches `.revert` through `applyVoicegroupEdit` (`VoicegroupStore.swift:233-234`).
- `saveVoicegroup(id:) throws -> LoadedBankView?` (`VoicegroupStore.swift:241`, public): tolerates stale-reload failure (`VoicegroupStore.swift:243`); `source.save()` (`VoicegroupStore.swift:248`), mapping `VoicegroupSourceConflict` to `operationFailed` (`VoicegroupStore.swift:249-250`); nil on supersede race (`VoicegroupStore.swift:254-256`); reloads via `context.load` (`VoicegroupStore.swift:257-261`), grafts (`VoicegroupStore.swift:265`), refreshes mtime + memos (`VoicegroupStore.swift:266-275`).
- `preview(id:) -> BankHandle?` (`VoicegroupStore.swift:282`, public): `loadPreviewedSource` on the record's source.
- `currentPublication(id:) -> LoadedBankView?` (`VoicegroupStore.swift:289`, internal): memo-free read.
- `refreshIfStale(id:) throws -> Bool` (`VoicegroupStore.swift:293`, private): compares mtime + memo (`VoicegroupStore.swift:300`); reloads through `loadBank(voicegroupArg:)` (`VoicegroupStore.swift:302`); false when identity changed.
- `publish(id:source:bank:) -> LoadedBankView` (`VoicegroupStore.swift:310`, private): 128 `VoicegroupSlotView(kind:voice:)` from `kindAt`/`voiceAt` (`VoicegroupStore.swift:313-315`).

Records:

- `BankRecord` (`VoicegroupStore.swift:15-21`): `id: VoicegroupId` (`:16`), `source: VoicegroupSource` (`:17`), `current: BankHandle` (`:18`), `sourceFileTime: Date` (`:19`), `published: LoadedBankView` (`:20`).
- `BankMemo` (`VoicegroupStore.swift:23-27`): `id` (`:24`), `filePath` (`:25`), `sourceFileTime` (`:26`); keyed by `-G` arg (`VoicegroupStore.swift:58,116,143,158,170,273-274,299`).
- `TokenRegistry` (`VoicegroupStore.swift:30-50`): `entries: [UInt64: Entry]` (`:36`), `next` (`:37`); `mint(id:materialization:)` (`:39`), `consume(_:)` (`:47`); `Entry(id:materialization:)` (`:31-34`).

`context.load` vs `loadPreviewedSource` flows: `context.load` serves clean on-disk bytes (`rebind` clean at `:93`, `loadBank` fresh at `:162`, `saveVoicegroup` reload at `:258`); `loadPreviewedSource` serves in-memory edited bytes via temp staging (`rebind` dirty at `:91`, `applyVoicegroupEdit` at `:208`, `preview` at `:283`). Every `context.load` result is grafted (`:97,:165,:265`); `loadPreviewedSource` grafts internally (`VoicegroupSave.swift:62`).

`LoadedBankView` (`VoiceValues.swift:143`): `id`, `bank: BankHandle`, `loadName`, `dirty`, `slotViews: [VoicegroupSlotView]`.

## 5. VoiceMacroSpec table

`VoiceMacroSpec` (`VoiceValues.swift:262-300`): fields `macro: VgMacro` (`:263`), `word: String` (`:264`), `category: VgMacro` (`:265`), `symbolField: Int?` (`:266`), `argumentCount: Int` (`:267`), `adsrFamily: Int` (`:268`), `prefix: [UInt8]` (`:269`). `adsrFamily = category == .keysplit || category == .keysplitAll ? -1 : Int(category.rawValue)` (`VoiceValues.swift:277`); `prefix = word + (category == .progWave ? "" : " ")` (`VoiceValues.swift:278`); dispatch order keeps `no_resample`/`alt` before base words and prog-wave prefixes separator-free (`VoiceValues.swift:281`).

`VoiceMacroSpec.all` (`VoiceValues.swift:282-296`) — (word, macro, category/field-order base, symbolField, argumentCount, adsrFamily, tableField):

| word (`VoiceValues.swift:283-295`) | `VgMacro` | envelope category | symbolField | args | adsrFamily | field order / notes |
|---|---|---|---|---|---|---|
| `voice_directsound_no_resample` (`:283`) | `.directSoundNoResample` | `.directSound` | `2` | 7 | `0` | key, pan, symbol, attack, decay, sustain, release |
| `voice_directsound_alt` (`:284`) | `.directSoundAlt` | `.directSound` | `2` | 7 | `0` | same order |
| `voice_directsound` (`:285`) | `.directSound` | `.directSound` | `2` | 7 | `0` | same order |
| `voice_square_1_alt` (`:286`) | `.square1Alt` | `.square1` | nil | 8 | `3` | key, pan, sweep, duty, period, attack, decay, sustain+release packed per CGB scale |
| `voice_square_1` (`:287`) | `.square1` | `.square1` | nil | 8 | `3` | same order |
| `voice_square_2_alt` (`:288`) | `.square2Alt` | `.square2` | nil | 7 | `5` | key, pan, duty, period, attack, decay, sustain/release |
| `voice_square_2` (`:289`) | `.square2` | `.square2` | nil | 7 | `5` | same order |
| `voice_programmable_wave_alt` (`:290`) | `.progWaveAlt` | `.progWave` | `2` | 7 | `7` | key, pan, symbol, attack, decay, sustain, release; prefix has no trailing space (`:278`) |
| `voice_programmable_wave` (`:291`) | `.progWave` | `.progWave` | `2` | 7 | `7` | same order |
| `voice_noise_alt` (`:292`) | `.noiseAlt` | `.noise` | nil | 7 | `9` | key, pan, period, attack, decay, sustain, release |
| `voice_noise` (`:293`) | `.noise` | `.noise` | nil | 7 | `9` | same order |
| `voice_keysplit_all` (`:294`) | `.keysplitAll` | `.keysplitAll` | `0` | 1 | `-1` | symbol only (drumkit; sub-voicegroup symbol) |
| `voice_keysplit` (`:295`) | `.keysplit` | `.keysplit` | `0` | 2 | `-1` | symbol, table |

`VgMacro` ordinals (`VoiceValues.swift:5-19`): `directSound=0`, `directSoundNoResample`, `directSoundAlt`, `square1`, `square1Alt`, `square2`, `square2Alt`, `progWave`, `progWaveAlt`, `noise`, `noiseAlt`, `keysplit`, `keysplitAll`.

`VgVoice` fields (`VoiceValues.swift:22-54`): `macro` (`:23`), `key` (`:24`), `pan` (`:25`), `symbol` (`:26`), `keysplitTable` (`:27`), `sweep` (`:28`), `duty` (`:29`), `period` (`:30`), `attack` (`:31`), `decay` (`:32`), `sustain` (`:33`), `release` (`:34`); defaults (`:36-41`).

`SourceLine` fields (`VoicegroupSource.swift:4-12`): `raw` (`:5`), `kind: VgLineKind` (`:6`), `slot` (`:7`), `voice: VgVoice` (`:8`), `indent` (`:9`), `macroText` (`:10`), `argPieces` (`:11`), `tail` (`:12`).

`parsedSource` fill (`VoicegroupSource.swift:156-163` struct; parser at `:220-238`): keysplit lines fill `voice.macro=.keysplit`, `voice.symbol` (field 0), `voice.keysplitTable` (field 1); keysplit-all lines fill `voice.macro=.keysplitAll`, `voice.symbol`, empty table; `cry ` lines are read-only voices (`VgLineKind.readOnlyVoice`), `cry_reverse ` likewise (prefixes at `VoicegroupSource.swift:166-167`); other voice macros fill `key/pan/symbol?/sweep/duty/period/attack/decay/sustain/release` per spec order.

Accessors: `kindAt(slot:)` (`VoicegroupSource.swift:113-116`, `.none` outside `0..<128` or unmapped); `isEditable(slot:)` (`VoicegroupSource.swift:121`); `voiceAt(slot:)` (`VoicegroupSource.swift:126-...`, voice iff `.editable`); `voiceDraft(slot:blank:)` (`VoicegroupSource.swift:136`).

`headerStartingSlot`: the `voice_group <name>[, start]` header's optional second argument (parsed where `headerPrefix = "voice_group "` at `VoicegroupSource.swift:165` is matched); per-file `fixture_drums_a, 36` / `fixture_drums_b, 36` examples in fixtures (see §10).

`contentBounds`: byte range of a line's significant content used by `VoiceEdits.swift:219-226` (`bounds = contentBounds(line.raw)` at `:219`, replace at `:226`, restore at `:277`).

Section boundary rules for monolithic files: `sectionLabel` nonempty ⇒ `isMonolithic` (`VoicegroupSource.swift:30`); `sectionBegin/sectionEnd` delimit the selected `voice_group`/`label::` section (`VoicegroupSource.swift:36-37`); `select(path:declarations:symbol:)` picks the matching declaration (`VoicegroupSource.swift:183-199`); `declarations(in:)` matches `^\s*voice_group\s+(\w+)` and `^\s*(voicegroup\w+)::` (`VoicegroupSource.swift:170-177,201-218`); `renderPreview` slices `lines[sectionBegin..<sectionEnd]` for monolithic (`VoicegroupSave.swift:24-32`).

## 6. CatalogLines / SynthCatalog

Structs:

- `VgSynthCatalog: Sendable` (`SynthCatalog.swift:4`): `defs: [(symbol: String, descriptor: VgSynthDesc)]`, `macroWords: [String]`; `available()` (`SynthCatalog.swift:13`: defs or macroWords nonempty); `creatable()` (`SynthCatalog.swift:14`: macroWords nonempty); `find(_:)` (`SynthCatalog.swift:15`); `symbolFor(_:)` (`SynthCatalog.swift:16-17`).
- `VgCatalogScan: Sendable` (`SynthCatalog.swift:22`): `groupArgs: [String]`, `keysplits: [(symbol: String, table: String)]`, `drumkits: [String]`, `typicalAdsr: VgAdsrDefaults`.
- `VgDirectSoundScan: Sendable` (`SynthCatalog.swift:32`): `directSound: [String]`, `synths: VgSynthCatalog`.
- `VgSynthDesc` (`VoiceValues.swift:95-119`): `waveform/baseDuty/dutyStep/modDepth/phase` (`:96-100`); `==` ignores pulse params for non-pulse (`:113-118`).
- `CatalogLines` — `private enum` (`SynthCatalog.swift:39`): `incbinDirective`/`macroDirective`/`synthMacroPrefix`/`voiceGroup`/`voicegroupPrefix`/`keysplit`/`drumkit`/`doubleColon`/`cries`/`voiceMacroPrefix...` constants (`SynthCatalog.swift:40-49`); `label(_:)`/`incbin(_:)`/`synthMacroWord`/`decimal`/`voiceMacro`/`voiceFields` parsers; `scanSoundData(_:)` / `scanVoicegroups(_:)`; `files(directory:recursive:)` (lists `.inc` via `ProjectFileStore.listRecursive`), `voicegroupFiles(_ root:)` (hub indices + recursive `sound/voicegroups`).

`VoicegroupSource` extension (`SynthCatalog.swift:325-372`): `directSoundSymbols(_:)` (`:326`), `progWaveSymbols(_:)` (`:330`), `synthInstruments(_:)` (`:349`), `keysplitInstruments(_:)` (`:353`), `drumkitInstruments(_:)` (`:357`), `typicalAdsr(_:)` (`:361`), `catalogScan(_:)` (`:365`), `directSoundCatalog(_:)` (`:369`).

Field consumers outside the file:

- `catalog.groups: VgCatalogScan` + `catalog.direct: VgDirectSoundScan` via `store.voicegroupCatalog()` at `ProjectService+Bank.swift:33-35`; `groups.typicalAdsr.bySymbol/byFamily` mapped to `VoiceListAdsr` at `ProjectService+Bank.swift:38,46`; `groups.keysplits` mapped at `ProjectService+Bank.swift:55`; `direct.synths.defs` mapped to symbols + `synthDefinitions` at `ProjectService+Bank.swift:56,59`.
- `VoicegroupSource.directSoundSymbols/progWaveSymbols/keysplitInstruments` consumed by picker cache build at `ProjectStore+Picker.swift:101-103`.
- `VoicegroupSource.synthInstruments(projectRoot).defs` consumed by graft definition map at `MintedSynths.swift:77`.
- `voicegroupFiles` / `files(_:recursive:)`: used by `VoicegroupSource.open` candidate scan (`VoicegroupSource.swift:76-82`) and `CatalogLines.scanVoicegroups/scanSoundData`; no direct PROJECT caller.

## 7. MintedSynths

- A minted synth is a memory-only Golden Sun waveform with no on-disk bytes: canonical symbol `DirectSoundSynth_GoldenSun_*` decoded by `mintedSynthDesc(symbol:)` (`MintedSynths.swift:43-63`): `Saw`/`Triangle` (+`_<digits>` collision suffix per `mintedCollisionSuffix` at `MintedSynths.swift:65-70`) ⇒ waveform 1/2; else 8-hex-digit pulse params ⇒ baseDuty/dutyStep/modDepth/phase (`MintedSynths.swift:53-62`); non-matching ⇒ nil.
- Bytes live in `MintedSynthStorage` (`MintedSynths.swift:6-38`): `waves` (128 `WaveData`) + `bytes` (128×17) (`:7-8`), allocated/initialized in `init` (`:10-15`), freed in `deinit` (`:17-22`); `graft(slot:descriptor:)` (`:24-37`) writes `status=0x4000`, `freq=0x01058920`, 17-byte payload (`0x80, waveform, baseDuty, dutyStep, modDepth, phase`, `:30-35`).
- Reaching the bank: `BankHandle.graftMintedSynths(source:)` (`MintedSynths.swift:75-98`) builds on-disk definition map from `VoicegroupSource.synthInstruments(source.projectRoot).defs` (`:76-79`); for each slot `0..<128` (`:82`) with parsed `voiceAt` (`:83`) and nil `tones[slot].wav`, direct-sound-family only (`:84-87`), resolves `definitions[voice.symbol] ?? mintedSynthDesc(symbol:)` (`:88-91`), lazily creates `mintedStorage` (`:92-93`), assigns `tones[slot].wav` (`:94`). Called after every `context.load` (`VoicegroupStore.swift:97,165,265`) and inside `loadPreviewedSource` (`VoicegroupSave.swift:62`).
- `ProjectStore+Synth.swift`: `mintSynth(_ descriptor: VgSynthDesc) throws -> String` (resolves reusable symbol via `VgSynthCatalog.symbolFor`/`find` without writing files); `savePendingSynths` / `write` persist pending `set_synth_*` definitions to the sound-data file (pending-definition write path; exact lines per `ProjectStore+Synth.swift`).
- `ToneData.isMintedSynthDescriptor` (`ProjectStore+Bank.swift:147-149`): DirectSound type mask, zero-size non-null `wav` — the loader-confirmed minted marker read by UI/export code.

## 8. Picker

`ProjectStore+Picker.swift` (PROJECT file, kept here because the seam question is whether `loadSamples` moves down):

- `loadSamples` is the picker's bulk sample fetch: `projectContext.loadSamples(direct:wave:keysplit:tables:)` at `ProjectStore+Picker.swift:105-107` with `direct`/`waves`/`keysplits.symbol`/`keysplits.table`; memoized into `pickerSamples` (`ProjectStore+Picker.swift:110-112`); invalidated on sample commit / rebind.
- `PickerSampleCache` (`ProjectStore+Picker.swift:25-30`): `set: SampleSetHandle` (`:26`), `direct: [String]` (`:27`), `waves: [String]` (`:28`), `keysplit: [(symbol:table:)]` (`:29`).
- `SampleSetHandle.raw` reads: metadata loop copies `raw.pointee` (`:37`), checks `waves[index]` data/size (`:41-43`), derives `rateHz = freq/1024` (`:44`), `looped = status & 0x4000` (`:47`); `pickerSound` indexes `raw.pointee.count/waves` (`:64-65`), `progWaveCount/progWaves` (`:70-71`), `keysplitCount/keysplits` (`:76-78`), reads `split.table/group` (`:79`), `table[60]` sub-index (`:80`), `group[subIndex]` tone (`:82`), envelope bytes (`:84-85`), `wav` vs `wavePointer` branches (`:86-91`); `sampleSound`/`waveSound` copy detached bytes (`:116-138`).
- Consumers: `ProjectService+Picker.swift` exposes `pickerSampleInfo/pickerSound` to UI; `SampleStudioWorkflow.swift` drives audition/commit off those APIs (audition via `AudioSampleAudition.swift`, workflow in `src/swift/app/samplestudio/SampleStudioWorkflow.swift`).

## 9. Checks

Lane: `add_porydaw_check_lane(swift_core_check_project ...)` at `src/checks/CMakeLists.txt:398-424`; sources listed per-file (`projectstore/<Name>.swift` at `:403-424`); support lane `swift_core_check_support` holds `projectstore/ProjectStoreCheckSupport.swift` (`:125-137`); link/default pattern per `add_porydaw_check_lane(name)` (`:33-69`: `cmake_parse_arguments(... "SOURCES;SWIFT_SOURCES;...")` at `:74`, `add_library(${name} STATIC ${CHECK_SOURCES})` + Swift module props at `:34-53`, batch mode + include/map flags at `:54-65`, link libs at `:66,68`).
Adding a check: append `projectstore/<New>.swift` to the `swift_core_check_project` `SOURCES` list (pattern at `:398-424`, one path per line) and add a `{name, argv:[--swiftcore,{scratch},{mid2agb},<filter>], fixture...}` entry in `src/checks/checkcatalog.cpp` (pattern at `:164-316`).

Manifest names (`checkcatalog.cpp:164-316`) vs suite functions (`src/checks/projectstore/*.swift`):

| File | Suite func | Manifest (`--filter`) | Fixtures declared | Asserts (from bodies) |
|---|---|---|---|---|
| `BankLeasesChecks.swift:151` | `runBankLeasesSuite` | (workspace lane; bank-lease manifest) | decomp project + editor | lease identity/sharing, slot views, publication revision, engine pointer stability |
| `ExportChecks.swift:126` | `runExportChecks` | (workspace/export lane) | decomp + MIDI | export job voices capture, settings, failure paths |
| `ExportCaptureChecks.swift:164` | `runExportCaptureChecks` (internal) | (workspace/export lane) | decomp + MIDI | capture lease pinning, completed-bytes contract |
| `MidiCfgChecks.swift:4` | `runMidiCfgSuite` | `projectstore-midicfg` (`checkcatalog.cpp:178`), argv `midiCfg` | decomp project (`FixtureRootKind::DecompProject`) | midi.cfg parse (last-wins), flag rewrite byte-preservation, missing-file behavior |
| `ProjectIdentityChecks.swift:14` | `runProjectIdentitySuite` | `projectIdentity` (argv at `:168`) | swiftCoreFixtures | label registration incl. mixed-case (`:114-118`: "mixed-case existing MIDI label must register", "mixed-case label is registered in every applicable build file"), `registerSong` paths (`:96,114-115,117`) |
| `ProjectStoreActorChecks.swift:35` | `runProjectStoreActorSuite` | `projectStoreActor` (`:267`) | project + editor | actor serialization, concurrent open/load ordering |
| `ProjectStoreCheckSupport.swift:11,18,27,50,56,77` | helpers `update/wait/awaitValue/withTempProjectCopy` | — (support) | — | temp-copy isolation; missing-fixture errors stay in-suite |
| `ProjectStoreEditChecks.swift:27` | `runProjectStoreEditSuite` | `projectStoreEdit` (`:296`) | project + editor | expected-value apply, blank materialize + token undo, conflict on stale expected |
| `ProjectStoreLoadBankChecks.swift:12` | `runProjectStoreLoadBankSuite` | `projectStoreLoadBank` (`:285`) | project (+editor) | `-G` resolution, `_dummy` empty-arg, memo reuse, load failure errors |
| `ProjectStoreOpenChecks.swift:4` | `runProjectStoreOpenSuite` | `projectStoreOpen` (`:231`) | project + editor | snapshot songs/players, route registration (`:96,103`: `MUS_ROUTE101`/`MUSIC_PLAYER_BGM`, `SE_USE_ITEM`/`SE_...`), unregistered MIDI playable flags, missing-MIDI path nil (`:284,286`) |
| `ProjectStoreReadChecks.swift:4` | `runProjectStoreReadSuite` | `projectStoreReads` (`:274`) | project | `BankDescriptor` addressability without load, catalog reads |
| `ProjectStoreSaveChecks.swift:19` | `runProjectStoreSaveSuite` | `projectStoreSave` (`:307`) | project + editor | save→reload clean lease, supersede nil, write-failure throw |
| `SaveCoreChecks.swift:6` | `runSaveCoreSuite` | `projectstore-savecore` (`:215`), argv `saveCore` | project | atomic write, trailing-newline/CRLF preservation, conflict refusal |
| `SongCatalogChecks.swift:5` | `runSongCatalogSuite` | `projectstore-catalog` (`:192`), argv `songCatalog` (`:193`) | project | comments/non-ASCII skipped, unregistered sort (`:62`), constant derivation (`:74`), registered MIDI flags/paths/playable (`:76-77,82,84,86,91,94`), lookup follows links/case rules (`:222-223,226,236`) |
| `SongModelChecks.swift:4` | `runSongModelSuite` | `projectstore-songmodel` (`:171`), argv `songModel` | mid2agb scratch | model parse/round-trip |
| `SongsMkChecks.swift:5` | `runSongsMkSuite` | `projectstore-songsmk` (`:185`), argv `songsMk` | project | songs.mk parse/emit; mk-only setup cannot open registry (`:181`) |
| `SynthCatalogChecks.swift:5` | `runSynthCatalogSuite` | `projectstore-synthcatalog` (`:200`), argv `synthCatalog` | project + rich voicegroups | `set_synth_*` defs, macro words, direct-sound exclusion of synth names |
| `VoicegroupValueChecks.swift` | `runVoicegroupValuesSuite` (argv `voicegroupValues`, `:208`) | `projectstore-values` | project + rich | macro grammar, ADSR families/scales, `vgSynthSymbolName`, structural-change predicate |
| `VoicegroupEditingChecks.swift` | `runVoicegroupEditingSuite` (argv `voicegroupEditing`, `:223`) | `projectstore-editing` | project + editor | `setVoice`/materialize/revert byte-exactness, header shift, token undo |
| `VoicegroupLoaderChecks.swift` | `runVoicegroupLoaderSuite` (argv `voicegroupContext`/`projectStoreChecks` family, `:242,250`) | `projectstore-checks`, `projectstore-context` | project + rich + editor | loader discovery order, section selection, sample resolution |
| `VoicegroupContextChecks.swift` | `runVoicegroupContextSuite` (argv `voicegroupContext`, `:250`) | `projectstore-context` | project | context open/failure, worker confinement |
| `VoicegroupBankLogicChecks.swift` | `runVoicegroupBankLogicSuite` (argv `voicegroupBankLogic`, `:258`) | `projectstore-banklogic` | project + editor | memo/rebase/retain logic, `headerStartingSlot`, monolithic sections |
| `WriteFailureFixture.swift:1-27` | fixture helper (no suite) | — | — | read-only-dir write-failure injection for save checks |

Fixture argv pattern: `--swiftcore {scratch} {mid2agb} <filter>` (e.g. `:171-172,178-179,185-186,192-193,200-201,208-209,215-216`); later suites use `{scratch} {mid2agb} <suite>` with `FixtureRootKind::DecompProject` + `fixtureFiles = project [+ editor]` (`:219-316`, e.g. editor files at `:74`, voicegroup editor files, `mus_route101.mid` + `sound/songs/midi/mus_route102.mid` rich sets at `:73-78`, `sound/songs/midi/mus_gym.mid`/`mus_oldale.mid` project sets, `include/constants/songs.h` + `sound/music_player_table.inc` at `:238`, `decompMidiFiles()` at `:239`).

## 10. Fixture

All files under `src/checks/fixtures/decompproject/sound/` (line counts via `wc -l`):

- `direct_sound_data.inc` — 15
- `keysplit_tables.inc` — 10
- `music_player_table.inc` — 13
- `programmable_wave_data.inc` — 11
- `song_table.inc` — 22
- `voice_groups.inc` — 7
- `voicegroups/dummy.inc` — 3
- `voicegroups/fixture_alt.inc` — 8
- `voicegroups/fixture_bass.inc` — 6
- `voicegroups/fixture_drums_a.inc` — 6
- `voicegroups/fixture_drums_b.inc` — 6
- `voicegroups/fixture_keys.inc` — 6
- `voicegroups/fixture_rich.inc` — 15
- `direct_sound_samples/fixture_bass.bin`, `fixture_drum.bin`, `fixture_loop.bin`, `fixture_pluck.bin` (binary)
- `programmable_wave_samples/fixture_pulse.pcm`, `fixture_saw.pcm` (binary)
- `songs/midi/midi.cfg` — 14; `mus_caught.mid`, `mus_dummy.mid`, `mus_gsc_route38.mid`, `mus_gym.mid`, `mus_littleroot_test.mid`, `mus_oldale.mid`, `mus_petalburg.mid`, `mus_route101.mid`, `mus_route102.mid`, `mus_surf.mid`, `mus_victory_wild.mid`, `se_fanfare_1trk.mid`, `se_pc_login.mid`, `se_use_item.mid` (binary)

Per-`voicegroups/*.inc` macros (from verbatim reads above):

- `dummy.inc` (3 lines): `voicegroup_dummy::` label-style, 1× `voice_square_1`. No keysplit/drumkit refs. Non-monolithic (own file, no section label).
- `fixture_alt.inc` (8 lines): `voice_group fixture_alt` header (no start arg → slot 0); 2× `voice_directsound`, 1× `voice_square_1_alt`, 1× `voice_square_2_alt`, 1× `voice_programmable_wave_alt`, 1× `voice_noise_alt`. No keysplit refs. Non-monolithic.
- `fixture_bass.inc` (6 lines): `fixture_bass::` + `voice_group fixture_bass` dual declaration; 1× `voice_directsound`, 1× `voice_square_1`, 1× `voice_noise`. No keysplit refs. Non-monolithic file (label + macro forms both present).
- `fixture_drums_a.inc` (6 lines): `fixture_drums_a::` + `voice_group fixture_drums_a, 36` (headerStartingSlot=36); 2× `voice_directsound`, 1× `voice_noise`. No keysplit refs (it *is* a drumkit target). Non-monolithic.
- `fixture_drums_b.inc` (6 lines): `fixture_drums_b::` + `voice_group fixture_drums_b, 36`; 2× `voice_directsound`, 1× `voice_programmable_wave` (symbol `ProgrammableWaveData_fixture_named_pad_long_label_123`). Non-monolithic.
- `fixture_keys.inc` (6 lines): `fixture_keys::` + `voice_group fixture_keys`; 1× `voice_square_2`, 1× `voice_directsound`, 1× `voice_programmable_wave` (`ProgrammableWaveData_fixture_pulse`). Non-monolithic.
- `fixture_rich.inc` (15 lines): `voice_group fixture_rich` monolithic-style section inside hub-included file; 2× `voice_directsound`, 1× `voice_directsound_no_resample`, 1× `voice_directsound_alt`, 1× `voice_square_1`, 1× `voice_square_2`, 1× `voice_programmable_wave`, 1× `voice_noise`, 2× `voice_keysplit` (`fixture_keys→keysplit_fixture`, `fixture_bass→keysplit_fixture_bass`), 2× `voice_keysplit_all` (`fixture_drums_a`, `fixture_drums_b`), 1× `cry` (`DirectSoundWaveData_fixture_loop`). Monolithic-capable section (relies on `sectionLabel` when hub holds several groups; here single-section file exercising all parsers).

`keysplit_tables.inc` (10 lines): two `keysplit` tables — `keysplit fixture, 0` with `split 0,48 / split 1,96 / split 2,128`; `keysplit fixture_bass, 0` with `split 0,64 / split 1,128`; each preceded by `.align 2`. No drumkit/`set_synth_*` lines.

`direct_sound_data.inc` (15 lines): four `.align 2` + label + `.incbin` groups: `DirectSoundWaveData_fixture_loop → sound/direct_sound_samples/fixture_loop.bin`; `..._pluck → .../fixture_pluck.bin`; `..._bass → .../fixture_bass.bin`; `..._drum → .../fixture_drum.bin`. No `set_synth_*` lines (synth defs live in `direct_sound_synth_data.inc`-style scans in real projects; fixture synths are minted by symbol).

`programmable_wave_data.inc` (11 lines): `ProgrammableWaveData_fixture_pulse → fixture_pulse.pcm`; `..._saw → fixture_saw.pcm`; `..._named_pad_long_label_123 → fixture_saw.pcm` (alias target).

`voice_groups.inc` (7 lines): hub `.include`s for all seven voicegroup files in order dummy, rich, alt, keys, bass, drums_a, drums_b.
