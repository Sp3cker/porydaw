# T2 — Parity digest and reference-loader harness

## Context

Before any Swift loader exists, pin the C loader's output as a canonical
digest so T7 can prove byte-equality and T10 can report build-time numbers.
Consumer: T7 adds the Swift side to the same check and asserts equality.

## Exact write set

- `src/checks/projectstore/BankDigest.swift` (new)
- `src/checks/projectstore/VoicegroupParityChecks.swift` (new)

Nothing else. The controller registers the suite in `src/checks/CMakeLists.txt`
and `src/checks/checkcatalog.cpp` under manifest name `projectstore-parity`,
argv suite `voicegroupParity`.

## Prerequisites

None. Import `PorydawProjectNative` (the loader header module as it exists on
the tree now; the controller renames the import after T1 lands).

## Interface contract

```swift
struct BankDigest: Equatable, Codable {
    struct Slot: Equatable, Codable {
        var type, key, length, panSweep, attack, decay, sustain, release: UInt8
        var waveKey: String       // "nil" or hex SHA-256 over: type,status,freq,loopStart,size (little-endian) + PCM bytes
        var progKey: String       // "nil" or 32 hex chars of the 16 packed bytes
        var wavePointerBits: UInt8 // low 2 bits of wavePointer for square/noise, else 0
        var tableKey: String      // "nil" or 256 hex chars
        var subBank: BankDigest?  // for keysplit types
        var name: String
    }
    var slots: [Slot]             // 128
    static func of(_ bank: UnsafePointer<LoadedVoiceGroup>) -> BankDigest
    static func of(voices: UnsafePointer<ToneData>, names: UnsafePointer<CChar>, subBankNames: (UnsafeRawPointer) -> UnsafePointer<CChar>?) -> BankDigest
}
```

The second `of` is the shape T7 will call with a Swift `Bank`; implement it now
and have the `LoadedVoiceGroup` overload delegate to it (names via
`voicegroup_subgroup_names`). Slot `waveKey` for a directsound voice whose `wav`
is NULL is `"nil"`; for a synth wave it hashes the 17-byte payload like any other.

```swift
public func runVoicegroupParitySuite(_ report: CheckReport)
struct ParityTarget { let voicegroupArg: String; let location: VoicegroupTarget-equivalent (filePath, sectionLabel) }
func parityTargets(projectRoot: String) -> [ParityTarget]   // hub-declared voicegroups (see steps)
func referenceDigest(projectRoot: String, target: ParityTarget) -> (BankDigest, seconds: Double, mallocs: Int)?
```

## Implementation steps

1. `BankDigest.of` walks 128 `ToneData`; for `VOICE_KEYSPLIT`/`VOICE_KEYSPLIT_ALL`
   recurse into `subGroup` (as `ToneData[128]`) with that sub-bank's names table;
   `keySplitTable` → `tableKey`; directsound family → hash `WaveData` header + `size`
   PCM bytes; programmable wave → 16 bytes at `wavePointer`; square/noise → low 2 bits.
   Use `CryptoKit.SHA256` (Apple) — the checks target already links Foundation; if
   `CryptoKit` is unavailable on the Linux lane, gate with `#if canImport(CryptoKit)`
   and fall back to a FNV-1a 64-bit hex (both sides of parity use the same function).
2. `parityTargets`: parse the hub `sound/voice_groups.inc` for `.include "sound/voicegroups/<file>.inc"`
   lines and per-file `voicegroup_<name>::` labels (reuse `VoicegroupSource.declarations`
   via `VoicegroupSource.open(projectRoot:voicegroupArg:error:)` per name is acceptable);
   for a monolithic hub the targets are its labels. Each target resolves to the
   `(filePath, sectionLabel)` that `VoicegroupSource.open` reports.
3. `referenceDigest`: `voicegroup_project_open(root, nil, nil)` once per suite run (stdio
   adapter), `voicegroup_project_load(project, &VoicegroupTarget)` per target, digest, free.
   Time with `ContinuousClock`; count mallocs as the delta of `malloc_zone_statistics`
   `.blocks_in_use` on the default zone around the load (Apple), 0 elsewhere.
4. Suite: for the fixture root (`report.scratch` as the other projectstore suites use it)
   assert every hub target loads (non-nil) and that loading twice yields equal digests
   (determinism). Emit one `report.note`/log line per target: `name  C: <ms> ms  <mallocs> mallocs`.
   If env `PORYDAW_PARITY_PROJECT_ROOT` is set, repeat for that root (targets from its hub),
   skipping targets that fail to load with a note rather than a failure.
5. Write a JSON snapshot of the fixture digests to `report.scratch/parity/<name>.json`
   (not committed; useful for diffing when T7 disagrees).

## Acceptance predicate

Controller runs after registering:

```
deno task build:checks
deno task checks --filter projectstore-parity
PORYDAW_PARITY_PROJECT_ROOT=/Users/sallegrezza/dev/pokeemerald-expansion deno task checks --filter projectstore-parity --verbose
```

Fixture run: all 7 hub voicegroups (`dummy`, `fixture_rich`, `fixture_alt`,
`fixture_keys`, `fixture_bass`, `fixture_drums_a`, `fixture_drums_b`) load and are
deterministic; `fixture_rich` digest shows two keysplit sub-banks with non-nil
`tableKey` and two keysplit_all sub-banks. Sweep run: ≥ 270 targets load, per-target
timing printed.

## Task-specific constraints

- Follow `VoicegroupContextChecks.swift` for how the suite reaches the scratch
  root and the native header module.
- No assertions on timing or malloc counts; those are output only.
- SHARED_TREE: report `tests: DEFERRED_TO_CONTROLLER`.
