# T7 — `BankBuilder` and parity equality

## Context

Turns `VoicegroupText` descriptors into a `Bank` with the C loader's
resolution semantics (`native-loader-spec.md` §6 parts 1 and 2), then proves
byte-equality against the reference C loader for every fixture voicegroup and
the optional real-project sweep. Consumer: T8 (`VoicegroupStore` builds via
`BankBuilder`; picker uses the same inputs).

## Exact write set

- `src/swift/voicegroup/BankBuilder.swift` (new; `BankBuildInputs`, `BankBuildError`, `BankBuilder`)
- `src/swift/voicegroup/CMakeLists.txt` (add the file)
- `src/checks/projectstore/VoicegroupParityChecks.swift` (edit: add the Swift path and equality assertions)
- `src/checks/projectstore/BankDigest.swift` (edit only if the Swift overload needs a `Bank` convenience; keep both overloads)

## Prerequisites

T2 (`BankDigest`, `parityTargets`, `referenceDigest`), T3 (`ProjectLayout`,
`SoundDataMap`, `ProgWaveMap`), T4 (`KeysplitTables`), T5 (`Bank`, `SubBank`,
`WaveRef`, `ProgWaveRef`, `WaveCache`), T6 (`VoicegroupLocator`,
`VgVoiceDesc`, `VoicegroupText`, `VoicegroupSource.descriptors()`). All are on
the tree; read their declarations, not the briefs.

## Interface contract

`spec.md` → "T7 — builder", verbatim. Semantics per §6:

- Directsound family (`type` with `VOICE_DIRECTSOUND`, `_NO_RESAMPLE`, `_ALT`):
  (1) `soundMap[symbol]` is `.synth(desc)` → `cache.synth(symbol:descriptor:)`;
  nil result is a hard failure; (2) `.sample(rel)` → candidates per
  `build_wave_abs_paths`: `.wav`/`.aif` variants only when `rel` ends in
  `.bin`, `.bin` path always; try in the session round order WAV → AIF → BIN
  (`cache.wave(absolutePath:format:)`), first non-nil wins, all nil → `wav`
  stays NULL (soft); (3) symbol absent from the map → serial fallback
  `search_sample_directories`: for each `layout.sampleDirectories` (after
  `ensuringDeepScan()`), `<dir>/<symbol>.wav` then `<dir>/<symbol>.aif`, first
  hit wins, else NULL. `WaveDecodeError` anywhere → `BankBuildError.hardFailure`.
- Programmable wave: `progMap[symbol]` absent → `wavePointer` NULL; present →
  `cache.prog(absolutePath:)`, nil → NULL (soft), register on the bank.
- Square/noise: `wavePointer` = `UnsafeMutablePointer(bitPattern: Int(desc.wavePointerBits))`.
- Cry (`VOICE_CRY`, `VOICE_CRY_REVERSE`): `soundMap` lookup, BIN-only candidate.
- `voice_keysplit`: `keysplits.table(named: desc.tableSymbol)` → `bank.registerTable`
  (copied per voice, as `copy_keysplit_table` does); missing table → per §6
  (NULL table or hard failure — follow the cited line). Sub-bank: locate via
  `locator.locateKeysplitTarget(symbol)` (or drumset for `_all`), fetch text
  through `inputs.textProvider`, build into a new `SubBank` with the same
  resolution rules (sub-voicegroups never recurse into further sub-voicegroups
  — `noSubRecurse` — so a nested keysplit line in a sub-bank leaves `subGroup`
  NULL); register on the bank; `tone.subGroup = subBank.voices`. Cycle guard:
  a location already on the active stack → `BankBuildError.cycle`.
- Names: `desc.displayName` copied into `bank.names`/`subBank.names` at the slot
  (NUL-terminated, truncated at `VG_VOICE_NAME_LEN - 1`).
- Continuation (`continuesIntoIncludedFile`): follow
  `locator.nextIncludedFile(after:)` and keep filling from the current slot per
  §5 continuation rules until the 128 cap or no next file.
- Slots never written stay zeroed (calloc), matching C.

## Implementation steps

1. Read §6 fully and the cited C for each branch above; implement `build` as a
   single pass over the 128 descriptors with helper functions per voice family.
   No per-slot heap allocation beyond what the spec names (tables, sub-banks,
   decoder output).
2. Parity: in `VoicegroupParityChecks.swift`, for each target build the Swift
   bank: `ProjectLayout(projectRoot:)`, maps parsed from the layout's files,
   `KeysplitTables.parse`, one `WaveCache` per root, `VoicegroupLocator`,
   `textProvider` = `VoicegroupSource` open at the location → `descriptors()`;
   `BankDigest.of(voices:names:subBankNames:)` on the result; assert
   `swiftDigest == referenceDigest` per target with a message naming the first
   differing slot and field. Print `name  C: <ms>  Swift: <ms>  <mallocs>/<mallocs>`.
   Sweep mode asserts equality too (not skip) for targets the C loader loads.
3. Timing/malloc for the Swift path measured the same way as the C path.

## Acceptance predicate

Controller runs:

```
deno task build:checks
deno task checks --filter projectstore-parity --verbose
PORYDAW_PARITY_PROJECT_ROOT=/Users/sallegrezza/dev/pokeemerald-expansion deno task checks --filter projectstore-parity --verbose
deno task checks --asan --filter projectstore-parity
```

All fixture targets equal; all 274 sweep targets equal; ASAN clean.

## Task-specific constraints

- Do not modify `VoicegroupStore`, `ProjectStore*`, or `ProjectBankLease` —
  T8 owns the cutover concurrently.
- Do not touch `VoicegroupSource.parsedSource`; if parity reveals a tokenizer
  deviation, report it with the slot/field and stop (`DONE_WITH_CONCERNS`), do
  not patch around it in the builder.
