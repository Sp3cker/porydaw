# T3 — `ProjectLayout` and sound-data maps

## Context

Swift replaces the C loader's discovery (`native-loader-spec.md` §1) and the
global symbol maps (§2). Consumers: T7 (`BankBuildInputs.layout/soundMap/progMap`),
T6 (`VoicegroupLocator(layout:)`), T8 (store opens one layout per project).

## Exact write set

- `src/swift/voicegroup/ProjectLayout.swift` (new)
- `src/swift/voicegroup/SoundDataMap.swift` (new; `SoundDataEntry`, `SoundDataMap`, `ProgWaveMap`)
- `src/checks/projectstore/ProjectLayoutChecks.swift` (new; `runProjectLayoutSuite`)

## Prerequisites

T1 (module exists; `AsmLine`, `ProjectFileStore` are in `PorydawVoicegroup`).

## Interface contract

`spec.md` → "T3 — layout and sound maps", verbatim.

Additional behaviors fixed here:
- `ProjectLayout.init` performs the eager discovery of §1 (`discover_project`:
  standard data files, standard voicegroup dirs, standard monolithic file, config
  paths from `extraVoicegroupPaths` using the §1 `discover_config_*` rules).
  Paths are absolute, in the C probe order, and only existing files/dirs are kept
  exactly where C keeps only existing ones.
- `ensuringDeepScan()` returns a layout whose `keysplitTableFiles`,
  `sampleDirectories`, `voicegroupDirectories`, `monolithicFiles` include the §1
  deep-scan results (`discover_scan_tree` depth limit and directory heuristics);
  calling it on an already-scanned layout returns `self`.
- `SoundDataMap.parse` implements the §2 grammar for `direct_sound_data.inc`-style
  files: label forms, `.incbin` path derivation (quotes stripped, `cries`
  exclusion if §2 states one), inline `set_synth_*` descriptors to the exact
  6-byte layout, and the §2 duplicate rule (state it in a doc comment with the
  C line cited).
- `ProgWaveMap.parse` implements the §2 programmable-wave grammar with the same
  duplicate rule.
- Unreadable file → skipped, as C does (§2 `parse_all_*` return semantics);
  do not throw.

## Implementation steps

1. Read §1 and §2 in full and the cited C lines for each probe/grammar rule.
2. `ProjectLayout`: a final class holding immutable eager arrays plus a
   `deepScan` result computed once (`lazy` is fine; the class is `Sendable` via
   immutability — if `lazy var` breaks `Sendable`, store the scan behind a
   `Mutex` from `Synchronization`). Reuse `ProjectFileStore.exists/listRecursive`
   and `CatalogLines.files(_:recursive:)` where they match C's enumeration order;
   where C sorts or does not sort, match it.
3. `SoundDataMap`/`ProgWaveMap` over `AsmLine` (byte cursor), never `String`
   splitting per line.
4. Checks (`runProjectLayoutSuite`) against the decomp fixture root:
   standard file discovery finds `sound/direct_sound_data.inc`,
   `sound/programmable_wave_data.inc`, `sound/keysplit_tables.inc`, the
   `sound/voicegroups` dir and `sound/voice_groups.inc`; `SoundDataMap` yields
   the four fixture symbols with their `.bin` relative paths and no synths;
   a temp project (use `withTempProjectCopy` from `ProjectStoreCheckSupport.swift`)
   with an added `set_synth_pulse`-labelled entry parses to a `.synth` of the
   exact 6 bytes §2 specifies; duplicate symbol follows the §2 rule; a nested
   nonstandard layout (e.g. `sound/custom/keysplits/x.inc`) is found only after
   `ensuringDeepScan()`.

## Acceptance predicate

Controller registers the suite as `projectstore-layout` (argv `projectLayout`) and runs:

```
deno task build:checks
deno task checks --filter projectstore-layout
deno task checks --filter projectstore
```

The first covers every behavior above; the second guards that nothing already
using `CatalogLines` regressed.

## Task-specific constraints

- No use of `voicegroup_loader.h` APIs; this is Swift-only.
- Symbol tables keyed by `String` are acceptable (built once per project open).
