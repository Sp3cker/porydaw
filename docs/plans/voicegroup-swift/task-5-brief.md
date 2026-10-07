# T5 — `Bank` ownership and `WaveCache` over the C decoders

## Context

The engine consumes `ToneData*`; everything it points at must outlive the
pointer and be freed exactly once. This task owns that memory in Swift and
binds the C byte-span decoders. Consumers: T7 (`BankBuilder` fills a `Bank`),
T8 (`ProjectBankLease` wraps `Bank`; picker reads `WaveRef`).

## Exact write set

- `src/swift/voicegroup/Bank.swift` (new; `Bank`, `SubBank`, `WaveRef`, `ProgWaveRef`)
- `src/swift/voicegroup/WaveCache.swift` (new; `WaveCache`, `WaveFormat`, `WaveDecodeError`)
- `src/checks/projectstore/BankOwnershipChecks.swift` (new; `runBankOwnershipSuite`)

## Prerequisites

T1. Decoder signatures: `native-loader-spec.md` §7; ownership/free order §8;
synth layout §6 `build_synth_wavedata`.

## Interface contract

`spec.md` → "T5 — bank ownership and decoders", verbatim, with these
`internal` builder hooks on `Bank`:

```swift
func register(wave: WaveRef)                      // retains; idempotent per object identity
func register(prog: ProgWaveRef)
func registerTable(_ bytes: UnsafePointer<UInt8>) -> UnsafeMutablePointer<UInt8>  // malloc(128), memcpy, owned
func register(subBank: SubBank)
```

and `SubBank.init()` (calloc both buffers). `Bank.subBank(for:)` matches by
pointer identity of `tone.subGroup`. `name(at:)` decodes up to NUL within
`VG_VOICE_NAME_LEN`, untrimmed (same as `ProjectBankLease.voiceName(at:)` today).

`WaveCache`:
- `wave(absolutePath:format:)`: cache hit by exact path string → same `WaveRef`
  object; miss → `ProjectFileStore.read` (missing file → `nil`, no throw),
  `withUnsafeBytes` → `vg_asset_decode_<format>`; decoder returning NULL with
  `hardFailure == false` → `nil` (not cached); `hardFailure == true` →
  `throw WaveDecodeError(path:)`; success → new `WaveRef` cached under the path.
- `synth(symbol:descriptor:)`: key `"synth-macro:<symbol>"`; builds the 17-byte
  `WaveData` exactly as §6 (`calloc(sizeof(WaveData)+17)`, `type 0`,
  `status 0x4000`, `freq 0x01058920`, `loopStart 0`, `size 0`, `data` past the
  header, 6 descriptor bytes copied); cached.
- `prog(absolutePath:)`: same shape over `vg_asset_decode_prog`; **not cached**
  (§6: prog bindings have no cache) — return a fresh `ProgWaveRef` each call.
- `removeAll()` drops cache entries; live `Bank`s keep their refs alive.

## Implementation steps

1. `WaveRef`/`ProgWaveRef`: `deinit { free(raw) }`; `SubBank`/`Bank`: calloc in
   init, free in deinit in the §8 order (tables, sub-banks' buffers, names,
   voices; waves/progs by ARC). No `[Int8]` PCM anywhere.
2. `WaveCache` as above; file read once into `Data`, decoder called inside
   `withUnsafeBytes`.
3. Checks (`runBankOwnershipSuite`), using the fixture `.bin` samples in
   `src/checks/fixtures/decompproject/sound/direct_sound_samples/`:
   decoding `fixture_loop.bin` via `.bin` yields a `WaveRef` whose header
   fields equal those from the reference `vg_asset_decode_bin` called directly
   in the check on the same bytes (type/status/freq/loopStart/size) and whose
   PCM bytes are identical; second `wave(...)` call returns the identical
   object; a missing path → nil; a 3-byte garbage file → nil without throw
   (unless §7 says hardFailure; follow §7); `synth` payload bytes equal §6
   constants; `registerTable` copies and the bank owns a distinct pointer;
   dropping the last `Bank` referencing a `WaveRef` after `removeAll()`
   deallocates it (observe via a `deinit` counter in a test subclass is
   impossible — instead assert `isKnownUniquelyReferenced` transitions, or
   use a weak reference that becomes nil).

## Acceptance predicate

Controller registers `projectstore-bank` (argv `bankOwnership`) and runs:

```
deno task build:checks
deno task checks --filter projectstore-bank
deno task checks --asan --filter projectstore-bank
```

ASAN run proves no double free / leak on the ownership paths.

## Task-specific constraints

- Only `voicegroup_asset_batch.h` decoders and `voicegroup_types.h` symbols
  from the native module; no `voicegroup_project_*`, no `LoadedVoiceGroup`.
- Classes are `@unchecked Sendable` only where the spec says; document the
  invariant (immutable after build) in ≤ 2 comment lines.
