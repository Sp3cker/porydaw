# T8 — Cutover to `Bank`; delete the C project-load path

## Context

With `BankBuilder` (T7) producing banks, the store, lease, picker and
minted-synth graft switch to Swift-owned banks and the native project context
goes away. Consumers: none further; T9/T10 are refactor/docs.

## Exact write set

- `src/swift/voicegroup/VoicegroupStore.swift`
- `src/swift/voicegroup/ProjectBankLease.swift`
- `src/swift/voicegroup/VoicegroupSave.swift` (remove `previewShadowName`, `renderPreview`, `loadPreviewedSource`)
- `src/swift/voicegroup/MintedSynths.swift` (remove `MintedSynthStorage`, `graftMintedSynths`; keep `mintedSynthDesc`, `mintedCollisionSuffix`)
- `src/swift/voicegroup/module.modulemap.in` (header becomes `voicegroup_asset_batch.h`; it includes `voicegroup_loader.h` transitively — if so, additionally wrap so only decoder/types symbols are used; the goal is that no Swift file names `voicegroup_project_*`, `voicegroup_load`, `LoadedVoiceGroup`, `LoadedSampleSet`, `VoicegroupFileIo`)
- `src/swift/voicegroup/CMakeLists.txt` (remove deleted files)
- delete `src/swift/voicegroup/ProjectContext.swift`, `src/swift/voicegroup/FileIo.swift`
- `src/swift/project/ProjectStore.swift`, `ProjectStore+Open.swift`, `ProjectStore+Bank.swift`, `ProjectStore+Picker.swift`, `ProjectStore+Samples.swift`
- `src/checks/projectstore/VoicegroupContextChecks.swift` (delete `fileIoChecks` and `projectContextChecks`; the suite keeps `runVoicegroupLoaderChecks`)
- `src/checks/projectstore/VoicegroupParityChecks.swift` + `BankDigest.swift`: switch their `import PorydawVoicegroupNative` reference-loader use to a checks-local module `PorydawLoaderReference` (new `src/checks/projectstore/native/module.modulemap.in` with `header "@PORYAAAA_DIR@/plugin/voicegroup_loader.h"`), and add the `configure_file` + `-fmodule-map-file` flag for `swift_core_check_project` in `src/checks/CMakeLists.txt`.

Over the file cap by design: one cutover, one verification surface.

## Prerequisites

T5 (`Bank`, `WaveCache`), T7 interface (`BankBuildInputs`, `BankBuilder.build(_:at:)`),
T3/T4/T6 types. T7 may still be in flight: code against `spec.md` "T7 — builder".

## Interface contract

- `VoicegroupStore`:
  - `init(projectRoot:) throws` builds `ProjectLayout`, parses `SoundDataMap`,
    `ProgWaveMap`, `KeysplitTables` (parse failure → `operationFailed`), owns a
    `WaveCache`, a `VoicegroupLocator`, and a `[VoicegroupLocation: VoicegroupSource]`
    text cache used by `textProvider`. Delete `init(projectRoot:context:)`.
  - `rebind()` (no parameter) replaces `rebind(context:)`: `cache.removeAll()`,
    re-parse the three maps, rebuild every record's bank from its current
    source (dirty or clean alike — both are "descriptors → build" now).
  - `loadBank`, `applyVoicegroupEdit`, `revertBlankSlot`, `saveVoicegroup`,
    `currentPublication` keep signatures. `preview(id:)` returns `Bank?`.
  - `BankRecord.current: Bank`; `LoadedBankView.bank: Bank`.
  - Minted synths: a slot whose `VgVoice.symbol` is a minted synth
    (`mintedSynthDesc(symbol:)` non-nil) and absent from `SoundDataMap` is
    resolved by the store supplying a `SoundDataMap` overlay: before building,
    union the parsed map with `.synth(desc)` entries for every minted symbol in
    `VoicegroupSource.synthInstruments(projectRoot)` + the store's pending
    mints. Delete `MintedSynthStorage`/`graftMintedSynths`.
- `ProjectBankLease`: `let bank: Bank`; `voiceName(at:)` → `bank.name(at:)`;
  `drumPadNames(at:)` → `bank.subBank(for: tone)?.name(at:)`; `engineVoices` →
  `bank.voices`; `sharesBank(with:)` → `bank === other.bank`. Delete the
  `MemoryLayout<LoadedVoiceGroup>` offsets.
- `ProjectStore`: delete `projectContext`; `open` constructs `VoicegroupStore(projectRoot:)`;
  `ProjectStore+Samples` sample-commit path calls `voicegroupStore.rebind()`.
- Picker (`ProjectStore+Picker.swift`): `PickerSampleCache` holds
  `[String: WaveRef]` for direct symbols, `[String: ProgWaveRef]` for waves, and
  for keysplits a `[String: SubBank-plus-table]` built by `BankBuilder` over a
  synthetic single-voice `VoicegroupText`? No — simpler and equivalent: for
  keysplit kind, locate the sub-voicegroup via the locator, build it as a
  sub-bank through the same builder entry used for `voice_keysplit`, and read
  table[60] from `KeysplitTables`. Expose whatever `internal` builder entry
  T7 provides for a sub-bank (coordinate via the spec; if T7 exposes only
  `build(_:at:)`, build the sub-voicegroup as a top-level bank — its `voices`
  are the same `ToneData[128]`). `pickerSampleInfo()`/`pickerSound(symbol:kind:)`
  keep signatures and semantics (`freq/1024`, `status & 0x4000`).

## Implementation steps

1. Store + lease + picker over `Bank` as above; `rebind()`; delete the native
   context and its `ProjectStore` plumbing.
2. Remove preview staging and graft; `VoicegroupSave.save()` keeps its disk
   rebase/write contract.
3. Modulemap narrowing; checks-local reference modulemap for parity.
4. `VoicegroupContextChecks.swift`: delete the two native-context check
   functions; keep the loader suite wiring.
5. `lsp references` (if available) or scoped `grep` under `src/swift` and
   `src/checks` for `ProjectContext`, `BankHandle`, `SampleSetHandle`,
   `loadPreviewedSource`, `graftMintedSynths`, `PorydawVoicegroupNative`
   users of removed symbols — zero remaining outside the parity check's
   reference module.

## Acceptance predicate

Controller runs:

```
deno task build:app
deno task build:checks
deno task checks --filter projectstore
deno task checks --filter samplecheck
deno task checks --filter workspace
deno task checks:bridge
deno task checks --asan --filter projectstore
```

`projectstore-*` (loadbank/edit/savebank/banklogic/context/values/editing/
synthcatalog/parity) cover bank load, edit, save, rebase, minted synth,
picker info; `samplecheck` covers the sample-commit → `rebind()` path;
`workspace` covers session bank leases/engine pointer stability.

## Task-specific constraints

- `engineVoices` pointer stability contract is unchanged: a lease's `bank.voices`
  never moves for the lease's lifetime.
- No `Data`/array copies of PCM in the picker beyond the existing
  `PickerSound` detached copy (it already copies into `[Int8]` by design).
- If T7's builder is not yet on the tree when you need to compile-check,
  continue; the controller builds after both land.
