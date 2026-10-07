# Voicegroup loading in Swift — spec

Binding references: `native-loader-spec.md` (C behavior to match, source-cited)
and `swift-surface.md` (current Swift surface, source-cited). This file holds
the agreed vocabulary and the forward-facing interfaces that tasks produce and
consume. Anything not stated here is decided by the cited reference, never by
the implementer.

## Goal

`PorydawVoicegroup` (`src/swift/voicegroup/`) is a leaf Swift module that turns
`.inc` text into a playable bank. C keeps exactly three things: the byte-span
decoders in `voicegroup_asset_batch.h` (`vg_asset_decode_wav/aiff/bin/prog`),
the layouts in `voicegroup/voicegroup_types.h` (`ToneData`, `WaveData`, `VOICE_*`),
and the engine (`m4a_engine_set_voicegroup(ToneData*)`). Porydaw stops using
`voicegroup_project_open/load/load_samples`, `voicegroup_load`, `VoicegroupFileIo`
and `LoadedVoiceGroup`; the reference C loader remains linked only into the
parity check.

Non-goals: no behavior change visible to the editor, picker, or engine; no new
C; no editing features (keysplit/drumset assignment, ADSR) — those are enabled
by this shape but not built here.

## Vocabulary

- **Bank**: 128 `ToneData` plus everything they point at, owned as one unit.
  Replaces `BankHandle`/`LoadedVoiceGroup`.
- **Descriptor** (`VgVoiceDesc`): one parsed voice line, no resolution.
- **Resolution**: symbol → asset bytes → `WaveData*`/prog words/keysplit table/sub-bank.
- **Sub-bank**: the `ToneData[128]` a `voice_keysplit`/`voice_keysplit_all` points at.
- **Layout** (`ProjectLayout`): discovered project paths (spec §1).
- **Sound map** (`SoundDataMap`): symbol → sample relative path or inline synth bytes (spec §2).
- **Prog map** (`ProgWaveMap`): symbol → programmable-wave relative path (spec §2).
- **Keysplit tables** (`KeysplitTables`): name → 128-byte table (spec §3).
- **Locator**: voicegroup argument → (file path, section label) (spec §4).

## Module layout (final state)

```
src/swift/voicegroup/
  CMakeLists.txt                 PorydawVoicegroup, links PorydawVoicegroupNative only
  module.modulemap.in            PorydawVoicegroupNative: voicegroup_asset_batch.h (+ types)
  ProjectFileStore.swift         moved down from project/
  VoicegroupId.swift             VoicegroupId moved down from ProjectIdentity.swift
  AsmLine.swift                  moved
  VoiceValues.swift              moved
  VoicegroupSource.swift         moved; + descriptors()
  VoicegroupSource+Create.swift  moved
  VoiceEdits.swift               moved
  VoicegroupSave.swift           moved; preview staging removed in T8
  SynthCatalog.swift             moved; scanVoicegroups folded onto VoicegroupSource in T9
  MintedSynths.swift             moved; graft removed in T8
  VoicegroupStore.swift          moved; builds via BankBuilder after T8
  ProjectBankLease.swift         moved from ProjectStore+Bank.swift; wraps Bank after T8
  ProjectLayout.swift            T3
  SoundDataMap.swift             T3 (SoundDataMap + ProgWaveMap)
  KeysplitTables.swift           T4
  Bank.swift                     T5 (Bank, SubBank, WaveRef, ProgWaveRef)
  WaveCache.swift                T5
  VoicegroupLocator.swift        T6
  VoiceDescriptor.swift          T6 (VgVoiceDesc + VoicegroupSource.descriptors())
  BankBuilder.swift              T7
```

`ProjectContext.swift` and `FileIo.swift` are deleted in T8.

## Interfaces

All types `public` unless noted; module `PorydawVoicegroup`.

### T3 — layout and sound maps

```swift
public final class ProjectLayout: Sendable {
    public let projectRoot: String
    public let soundDataFiles: [String]        // absolute; spec §1 order
    public let programmableWaveFiles: [String]
    public let keysplitTableFiles: [String]    // eager set; deep-scan additions appended lazily
    public let voicegroupDirectories: [String]
    public let monolithicFiles: [String]
    public let sampleDirectories: [String]     // wavSampleDirs
    public init(projectRoot: String, extraVoicegroupPaths: [String] = [])
    /// Runs the one-time deep scan (spec §1 `discovery_ensure_deep_scan`) and
    /// returns the layout with scan results merged. Idempotent.
    public func ensuringDeepScan() -> ProjectLayout
}

public enum SoundDataEntry: Equatable, Sendable {
    case sample(relativePath: String)
    case synth([UInt8])                        // exactly 6 bytes, spec §2 layout
}
public struct SoundDataMap: Sendable {
    public var entries: [String: SoundDataEntry]
    public static func parse(files: [String]) throws -> SoundDataMap   // spec §2 grammar + duplicate rule
    public subscript(symbol: String) -> SoundDataEntry? { get }
}
public struct ProgWaveMap: Sendable {
    public var entries: [String: String]       // symbol → relative path
    public static func parse(files: [String]) throws -> ProgWaveMap
    public subscript(symbol: String) -> String? { get }
}
```

### T4 — keysplit tables

```swift
public struct KeysplitTable: Equatable, Sendable {
    public let name: String                    // stored form (spec §3: "keysplit_" prefix for macro form)
    public let startingNote: Int
    public let maxNote: Int
    public let table: [UInt8]                  // count 128
}
public struct KeysplitTables: Sendable {
    public let tables: [KeysplitTable]         // file order, no dedupe
    /// First-wins lookup (spec §3 `keysplit_map_find`).
    public func table(named: String) -> KeysplitTable?
    /// Throws KeysplitParseError(file:line:reason:) on INVALID; unreadable file throws too.
    public static func parse(files: [String]) throws -> KeysplitTables
}
```

### T5 — bank ownership and decoders

```swift
/// Owns one decoder allocation; `deinit` calls `free`. Never copied.
public final class WaveRef: @unchecked Sendable {
    public let raw: UnsafeMutablePointer<WaveData>
    public let path: String                    // cache key: absolute path or "synth-macro:<symbol>"
}
public final class ProgWaveRef: @unchecked Sendable {
    public let raw: UnsafeMutablePointer<UInt32>   // 16 packed bytes; free() in deinit
    public let path: String
}
public final class SubBank {                   // one voice_keysplit/_all target
    public let voices: UnsafeMutablePointer<ToneData>     // 128, calloc'd, free() in deinit
    public let names: UnsafeMutablePointer<CChar>         // 128 * VG_VOICE_NAME_LEN, calloc'd
    public func name(at slot: Int) -> String
}
public final class Bank: @unchecked Sendable {
    public let voices: UnsafeMutablePointer<ToneData>     // 128, calloc'd, free() in deinit
    public let names: UnsafeMutablePointer<CChar>         // 128 * VG_VOICE_NAME_LEN
    public private(set) var subBanks: [SubBank]
    public private(set) var tables: [UnsafeMutablePointer<UInt8>]   // 128 bytes each, malloc'd
    public private(set) var waves: [WaveRef]              // retained for lifetime
    public private(set) var progWaves: [ProgWaveRef]
    public init()
    public func name(at slot: Int) -> String
    /// Sub-bank whose `voices` pointer equals `tone.subGroup`, or nil.
    public func subBank(for tone: ToneData) -> SubBank?
    // Builder-only mutation (internal): register(wave:), register(prog:), register(table:) -> UnsafeMutablePointer<UInt8>, register(subBank:)
}
/// Project-scoped decode cache. Keyed by WaveRef.path. Not thread-safe; owned by VoicegroupStore.
public final class WaveCache {
    public init()
    /// Reads and decodes; nil on soft miss (missing/undecodable), throws WaveDecodeError on hardFailure.
    public func wave(absolutePath: String, format: WaveFormat) throws -> WaveRef?
    public func synth(symbol: String, descriptor: [UInt8]) -> WaveRef?      // spec §6 build_synth_wavedata layout
    public func prog(absolutePath: String) throws -> ProgWaveRef?
    public func removeAll()
}
public enum WaveFormat { case wav, aiff, bin }
```

Free order on `Bank.deinit` mirrors spec §8: waves are released by ARC when the
last `Bank` referencing a `WaveRef` dies; `tables`, `subBanks`, `voices`,
`names` are freed by the bank.

### T6 — locator and descriptors

```swift
public struct VoicegroupLocation: Equatable, Sendable {
    public let filePath: String                // absolute
    public let sectionLabel: String            // "" for a per-file voicegroup
}
public struct VoicegroupLocator {
    public init(layout: ProjectLayout)
    /// spec §4 find_voicegroup probe order. nil when not found.
    public func locate(voicegroupArg: String) -> VoicegroupLocation?
    public func locateKeysplitTarget(symbol: String) -> VoicegroupLocation?   // §4 find_keysplit_voicegroup
    public func locateDrumsetTarget(symbol: String) -> VoicegroupLocation?    // §4 find_drumset_voicegroup
    /// spec §4 next_included_voicegroup continuation; nil when none.
    public func nextIncludedFile(after filePath: String) -> String?
}

public struct VgVoiceDesc: Equatable, Sendable {
    public var type: UInt8                     // VOICE_* constant, already including ALT/REV bits
    public var key: UInt8
    public var panSweep: UInt8                 // spec §5 formula applied
    public var attack, decay, sustain, release: UInt8   // spec §5 masks applied
    public var wavePointerBits: UInt8          // square/noise duty bits (§5), else 0
    public var symbol: String                  // sample / wave / sub-voicegroup symbol, "" if none
    public var tableSymbol: String             // voice_keysplit table symbol, "" if none
    public var displayName: String             // spec §5 set_voice_display_name result
}
public struct VoicegroupText: Sendable {
    public let voices: [VgVoiceDesc?]          // 128; nil = slot never written
    public let continuesIntoIncludedFile: Bool // spec §5 contiguousFill continuation needed
}
public enum VoicegroupTextError: Error, Equatable, Sendable {
    case hardFailure(line: Int, reason: String) // one-based source line
}
extension VoicegroupSource {
    /// Opens an exact location while retaining the editor's non-contiguous section bounds.
    public func open(location: VoicegroupLocation, error: inout String?) -> Bool
    /// C :3483 defaults; sub-banks (:2360) use contiguousFill; successors (:2328) use noSubRecurse.
    public func descriptors(contiguousFill: Bool = false, noSubRecurse: Bool = false) throws -> VoicegroupText
}
```

### T7 — builder

```swift
public struct BankBuildInputs {
    public var layout: ProjectLayout
    public var soundMap: SoundDataMap
    public var progMap: ProgWaveMap
    public var keysplits: KeysplitTables
    public var cache: WaveCache
    public var locator: VoicegroupLocator
    /// Supplies parsed text for sub-voicegroups; the store backs it with its VoicegroupSource cache.
    public var textProvider: (VoicegroupLocation) throws -> VoicegroupText
}
public enum BankBuildError: Error { case hardFailure(String), cycle(VoicegroupLocation), unreadable(String) }
public struct BankBuilder {
    public init(_ inputs: BankBuildInputs)
    /// spec §6 resolution; sub-voicegroups via textProvider with cycle guard.
    public func build(_ text: VoicegroupText, at location: VoicegroupLocation) throws -> Bank
}
```

### T8 — cutover contract

- `ProjectBankLease` keeps its public API (`subscript(slot:)`, `voiceName(at:)`,
  `subvoiceMacros(at:)`, `drumPadNames(at:)`, `engineVoices`, `sharesBank(with:)`)
  over `Bank` instead of `BankHandle`.
- `VoicegroupStore.loadBank/applyVoicegroupEdit/saveVoicegroup/preview/rebind`
  keep their signatures; `rebind` takes no `ProjectContext` (it clears the
  `WaveCache` and rebuilds).
- Picker: `ProjectStore.pickerSampleInfo()`/`pickerSound(symbol:kind:)` keep
  their signatures; backed by `WaveCache` + `KeysplitTables` + `BankBuilder`
  for keysplit kinds.

## Parity contract (T2, T7)

`BankDigest` is a canonical value computed from any bank (C `LoadedVoiceGroup*`
or Swift `Bank`):

- per slot 0..<128: `type,key,length,panSweep,attack,decay,sustain,release`,
  `waveKey` (SHA-256 of the pointed `WaveData` header fields + PCM bytes, or
  `"nil"`), `progKey` (16 bytes hex or `"nil"`), `tableKey` (128 bytes hex or
  `"nil"`), `subBankDigest` (recursive, or `"nil"`), `name`.
- Square/noise `wavePointer` is compared as its low 2 bits.

Two banks are equal iff digests are equal. The parity check loads every
voicegroup named in the fixture hub (`src/checks/fixtures/decompproject/sound/voice_groups.inc`)
through both paths and asserts equality; with `PORYDAW_PARITY_PROJECT_ROOT`
set it also sweeps every `voicegroup*` declared in that project. It reports
wall time per path and `malloc` count per build (via `malloc_zone_statistics`
delta or `mstats`) as check output, not assertions.
