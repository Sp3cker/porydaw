# Plan: voicegroup loading in Swift (`PorydawVoicegroup`)

Worktree `.worktrees/voicegroup-swift`, branch `feature/voicegroup-swift`, base `fork-main` @ `8556f510`.
Spec: `spec.md`. References: `native-loader-spec.md` (C behavior), `swift-surface.md` (current Swift).

## Global Constraints

Implementers read this section and `spec.md`; briefs carry deltas only.

1. Repo rules in `AGENTS.md` apply: Swift 6, one concept per file, `internal` by default,
   no new C outside the listed boundary, comments ≤ 2 lines, per-frame builders allocation-free.
   `.omp/rules/swift-standards.md` applies to every `.swift` file.
2. C behavior is the spec. Where `native-loader-spec.md` and existing Swift disagree, the
   C rule wins and the Swift is changed; the parity check (T2/T7) is the arbiter. Read the cited
   C lines before implementing a rule; do not implement from the spec's paraphrase alone.
3. Memory discipline for bank data: exactly one allocation per decoded sample (the C decoder's),
   one `calloc` per `ToneData[128]`, one `malloc` per 128-byte keysplit table, one per prog wave.
   No `[Int8]`/`Data` copies of PCM after decode; file bytes are read once into `Data` and handed
   to the decoder via `withUnsafeBytes`. No `String` allocation per slot on rebuild paths beyond
   the display-name copy into the fixed `names` buffer.
4. Verification ownership: implementers do read-only local inspection only (`lsp diagnostics`
   on owned files). They never run `deno task build:*`, `checks*`, `format`, or any formatter —
   the controller runs those once per phase over the settled tree. Tasks marked SHARED_TREE
   report `tests: DEFERRED_TO_CONTROLLER`.
5. Verification commands recorded in each brief are reused verbatim by the controller;
   implementers do not rediscover them. Report a stale command as a concrete mismatch.
6. Checks: new check files go in `src/checks/projectstore/`, one `run<Name>Suite(_ report: CheckReport)`
   per file, registered by the controller in `src/checks/CMakeLists.txt` (`swift_core_check_project`
   SOURCES) and `src/checks/checkcatalog.cpp` (`--swiftcore` manifest entry, `FixtureRootKind::DecompProject`,
   `fixtureFiles = project + editor`). Implementers write the check file and name the manifest
   entry in their result; they do not edit CMake/catalog.
7. No stubs, placeholders, `TODO`, or "follow-up" labels. A task is done when its acceptance
   predicate holds end to end.
8. Deletions are clean cutovers: migrate every caller, remove the obsolete declaration, no shims
   or re-exports. Run `lsp references` before removing or renaming an exported symbol.

## Tasks

| # | Task | Route | Seat | Write set (closed) | Depends on |
|---|---|---|---|---|---|
| T1 | Extract `PorydawVoicegroup` module (pure move + visibility) | SDD — multi-file, interface between modules, CMake | `sdd-implementer` | `src/swift/voicegroup/**` (new), `src/swift/project/CMakeLists.txt`, `src/swift/project/ProjectIdentity.swift`, `src/swift/project/ProjectStore+Bank.swift`, `CMakeLists.txt` (root add_subdirectory), `src/swift/document/CMakeLists.txt`, `src/swift/app/CMakeLists.txt`, `src/checks/CMakeLists.txt` (modulemap flag), every file adding `import PorydawVoicegroup` — over the file cap: one behavior-preserving move with one verification surface (build + `checks --filter projectstore`) | — |
| T2 | Parity digest + reference-loader harness (`projectstore-parity`) | SDD — new native binding, benchmark output | `sdd-implementer` | `src/checks/projectstore/VoicegroupParityChecks.swift`, `src/checks/projectstore/BankDigest.swift`, `src/checks/projectstore/native/module.modulemap.in`, `src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp` | — |
| T3 | `ProjectLayout` + `SoundDataMap`/`ProgWaveMap` | SDD — spec §1–2 port with fork heuristics | `sdd-implementer` | `src/swift/voicegroup/ProjectLayout.swift`, `src/swift/voicegroup/SoundDataMap.swift`, `src/checks/projectstore/ProjectLayoutChecks.swift` | T1 |
| T4 | `KeysplitTables` parser | Direct — single grammar, pure, one check file | `sdd-implementer` | `src/swift/voicegroup/KeysplitTables.swift`, `src/checks/projectstore/KeysplitTablesChecks.swift` | T1 |
| T5 | `Bank`/`SubBank`/`WaveRef`/`ProgWaveRef` + `WaveCache` over C decoders | SDD — ownership + unsafe memory | `sdd-implementer` | `src/swift/voicegroup/Bank.swift`, `src/swift/voicegroup/WaveCache.swift`, `src/checks/projectstore/BankOwnershipChecks.swift` | T1 |
| T6 | `VoicegroupLocator` + `VgVoiceDesc`/`descriptors()` | SDD — §4/§5 semantics, may change `parsedSource` | `sdd-implementer` | `src/swift/voicegroup/VoicegroupLocator.swift`, `src/swift/voicegroup/VoiceDescriptor.swift`, `src/swift/voicegroup/VoicegroupSource.swift`, `src/checks/projectstore/VoicegroupLocatorChecks.swift` | T1 |
| T7 | `BankBuilder` + parity equality | SDD — §6 resolution, recursion, cycle guard | `sdd-implementer` | `src/swift/voicegroup/BankBuilder.swift`, `src/checks/projectstore/VoicegroupParityChecks.swift`, `src/checks/projectstore/BankDigest.swift` | T2–T6 |
| T8 | Cutover: store/lease/picker on `Bank`; delete C project path | SDD — multi-file surgery, lifetime edges | `sdd-implementer` | `src/swift/voicegroup/VoicegroupStore.swift`, `ProjectBankLease.swift`, `VoicegroupSave.swift`, `MintedSynths.swift`, `module.modulemap.in`, `CMakeLists.txt` (voicegroup), `src/swift/project/ProjectStore.swift`, `ProjectStore+Open.swift`, `ProjectStore+Bank.swift`, `ProjectStore+Picker.swift`, `ProjectStore+Samples.swift`, delete `ProjectContext.swift`, `FileIo.swift`; `src/checks/projectstore/VoicegroupContextChecks.swift` — over cap: one cutover, one verification surface | T5, T7 interface |
| T9 | Fold `CatalogLines.scanVoicegroups` onto `VoicegroupSource.descriptors()` | Direct — refactor, existing `projectstore-synthcatalog` covers | `sdd-implementer` | `src/swift/voicegroup/SynthCatalog.swift` | T6 |
| T10 | Docs: `docs/BUILDING.md` floor before/after, module list in `AGENTS.md` project map | Direct — controller writes after measuring | controller | `docs/BUILDING.md`, `AGENTS.md` (project map line only, with user permission) | T8 |

Routes: T4/T9 Direct (mechanical, single predicate); the rest SDD (interface between steps, memory ownership, or parity-gated behavior).

## Phases and checkpoints

- **P1** T1 ∥ T2 (disjoint write sets). Checkpoint `voicegroup: extract module + parity harness`
  after `build:app`, `checks --filter projectstore`, `checks:bridge`, `format --check` green.
- **P2** T3 ∥ T4 ∥ T5 ∥ T6 (disjoint new files; T6 also owns `VoicegroupSource.swift`).
  Controller registers the four check files. Checkpoint `voicegroup: layout, keysplits, bank, locator`.
- **P3** T7 ∥ T8 (T8 codes against the T7 interface in spec.md; T8's parity run waits for T7).
  Checkpoint `voicegroup: Swift bank builder, C project loader removed` after parity green on
  fixture + `PORYDAW_PARITY_PROJECT_ROOT=~/dev/pokeemerald-expansion` sweep.
- **P4** T9, T10. Final whole-branch review, full `deno task checks`, push.

## Verification policy

Controller runs, per phase, from the worktree root:

```
deno task build:app
deno task build:checks
deno task checks --filter projectstore
deno task checks:bridge
deno task format --check
```

P3 adds `deno task checks --filter projectstore-parity` with and without
`PORYDAW_PARITY_PROJECT_ROOT=/Users/sallegrezza/dev/pokeemerald-expansion`, and the full
`deno task checks`. The before-number for T10 is already measured: semantic one-file edit in
`src/swift/project/VoicegroupSource.swift` on base = 18.2 s wall (Project → Document →
AppPresentation → App recompiles + 3 links).
