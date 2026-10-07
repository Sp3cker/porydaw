# T11 — Hot path: Swift bank load must be ≤ C in time and allocations

## Context

Acceptance rule from the user (binding): the Swift bank path is rejected if it
is slower or allocates more than the comparable C code. The comparable C work
is `voicegroup_project_load`: read + tokenize the voicegroup file(s) and
sub-voicegroup files, resolve symbols, decode assets, assemble
`LoadedVoiceGroup`. Measured on `pokeemerald-expansion` (274 voicegroups):

| | C | Swift (parity run at `55cca385`) |
|---|---|---|
| total wall | 351 ms | 335 ms parse + 4,525 ms build |
| total mallocs | 14,531 | 170,470 parse + 222,804 build |
| worst (`voicegroup229`) | 96 ms / 496 | 1,497 ms / 26,297 |

Correctness is already proven (parity 274/274 + fixture 7/7); this task must
keep it. Consumer: the parity check gates it; nothing else consumes new API.

## Exact write set

- `src/swift/voicegroup/VoiceDescriptor.swift`
- `src/swift/voicegroup/BankBuilder.swift`
- `src/swift/voicegroup/WaveCache.swift`, `src/swift/voicegroup/Bank.swift`
- `src/swift/voicegroup/VoicegroupLocator.swift`
- `src/swift/voicegroup/SoundDataMap.swift`, `src/swift/voicegroup/KeysplitTables.swift`
- `src/swift/voicegroup/VoicegroupSource.swift` (only what the descriptor fold shares)
- `src/swift/voicegroup/VoicegroupStore.swift`, `src/swift/project/ProjectStore+Picker.swift`, `src/swift/voicegroup/ProjectBankLease.swift` (callers of changed types only)
- `src/checks/projectstore/VoicegroupParityChecks.swift` (gate assertions)
- `src/checks/projectstore/*.swift` that name changed types (`WaveRef`, `VgVoiceDesc.symbol` as `String`, etc.) — migrate, keep assertions

Over the file cap by design: one behavior (the gate), one verification surface.

## Prerequisites

Everything landed through `55cca385`. Read the actual files; `spec.md` T5–T7
sections are now descriptive, update them to the final shapes.

## Interface contract (decisions, not options)

1. **No `String` on the load path.** `VgVoiceDesc.symbol`, `tableSymbol`,
   `displayName` become `ArraySlice<UInt8>` into the retained source buffer
   (`VoicegroupText` holds the `[UInt8]` buffer so slices stay valid).
   `SoundDataMap`, `ProgWaveMap`, `KeysplitTables` lookups take
   `ArraySlice<UInt8>` (store keys as `ArraySlice<UInt8>` over their own
   retained file buffers; `Dictionary<ArraySlice<UInt8>, _>` is Hashable and
   lookup allocates nothing). Display names are copied directly into the
   `names` buffer. Public String-taking conveniences may remain only where an
   existing caller outside the load path needs them (picker, catalog).
2. **Descriptor fold straight from bytes.** `VoicegroupText.parse(bytes:
   sectionLabel: contiguousFill: noSubRecurse:) throws` folds the C §5 line
   loop over the byte buffer with no `SourceLine` materialization. It shares
   the grammar with the editor tokenizer — `VoiceMacroSpec`, `AsmLine` int
   parsing, `contentBounds`, section-boundary helpers — by calling the same
   static helpers; it does not duplicate the macro table or the integer
   grammar. `VoicegroupSource.descriptors()` stays as a thin wrapper that
   calls `VoicegroupText.parse` on `sourceBytes()` (editor path, not hot).
   Allocation budget of `parse`: the output `[VgVoiceDesc?]` (128) plus the
   retained buffer. Nothing per line.
3. **Load path never builds the editor model.** `VoicegroupStore.loadBank`
   reads the file bytes once, calls `VoicegroupText.parse`, builds the bank,
   and only then constructs the `VoicegroupSource` editor model from the same
   bytes for the record (editor needs it for slot views/edits). The parity
   check's `textProvider` mirrors the load path exactly (read bytes →
   `VoicegroupText.parse`). Sub-voicegroup text is cached per
   `VoicegroupLocation` for the store's lifetime (invalidated on `rebind()`),
   as the store already does; the parity provider uses the same cache class.
4. **No per-sample wrapper objects.** Delete `WaveRef`/`ProgWaveRef`.
   `WaveCache` owns decoder allocations for the project lifetime in
   `[ArraySlice<UInt8>-or-String path: Entry]` with `Entry { raw, refs }`;
   `Bank` stores raw `UnsafeMutablePointer<WaveData>`/`UnsafeMutablePointer<UInt32>`
   in two arrays and holds the cache; `Bank.deinit` calls `cache.release`
   for each; `WaveCache.removeAll()` marks entries evicted, freeing on last
   release. Prog waves stay uncached (owned by the bank, freed by it) as C does.
   Picker reads raw pointers under `withExtendedLifetime(bank)`.
5. **Locator probes without Foundation.** `FileManager.fileExists` /
   `URL` building per probe → `access(2)`/`stat(2)` on a stack `[CChar]`
   path assembled once per probe; results of `locateSubgroup` are memoized
   per symbol for the store lifetime (C memoizes nothing, so this is allowed
   headroom, not required).
6. **File reads**: one `Data(contentsOf:)`-equivalent per file per load (C
   does the same via its adapter); no second copy. `[UInt8](data)` counts as
   a copy — read straight into a `[UInt8]` with `FileHandle`/`read(2)`.
7. **Gate in the parity check** (both roots): per target assert
   `swift.mallocs <= c.mallocs` where `swift` = read + parse + build with a
   fresh sub-voicegroup text cache per root (so the first load of a drumkit
   is counted, like C), and per root assert `sum(swift.seconds) <= sum(c.seconds)`.
   Print both as today. A failing gate is a check failure.

## Implementation steps

1. Measure first: with `malloc_zone_statistics` deltas already in the check,
   bisect the 26k mallocs of `voicegroup229` by instrumenting locally (temporary
   prints are fine; remove before handoff). Expect: `SourceLine` arrays in
   sub-voicegroup parses, `String` symbol/name creation, `FileManager` probes,
   dictionary growth, `Data`→`[UInt8]` copies.
2. Apply decisions 1–6 in that order; keep each step parity-green in your
   head by not touching resolution semantics (same branches, same order).
3. Update the gate (7). Update `spec.md` T5–T7 to the final shapes.
4. Delete anything the hot path no longer needs (`WaveRef`, String-keyed map
   APIs with no caller, `VoicegroupText.endIndex` if unused, …). No shims.

## Acceptance predicate

Controller runs:

```
deno task build:checks
deno run --allow-read --allow-write --allow-run --allow-env=ASAN_OPTIONS,DISPLAY,PORYDAW_SAMPLE_CORPUS,PORYDAW_CHECK_HOST tools/run_checks.ts build/debug/porydaw_checks --filter projectstore --filter samplecheck --filter workspace
PORYDAW_PARITY_PROJECT_ROOT=/Users/sallegrezza/dev/pokeemerald-expansion deno run ... --filter projectstore-parity --verbose
deno task checks --asan --filter projectstore
deno task build:app
```

Parity still 274/274 equal; the new gate assertions pass on fixture and sweep;
ASAN clean; all other suites unchanged.

## Task-specific constraints

- Do not add caching layers beyond: the sub-voicegroup text cache (exists),
  `WaveCache` (exists), and the locator memo (5). No protocols, no generic
  "resolver" abstractions, no option structs. If a helper exists only to be
  reused by a hypothetical consumer, delete it.
- Do not change C-visible behavior: the parity equality is the arbiter.
- `@inline(__always)`/`@_transparent` sprinkling is not a strategy; remove
  allocations and Foundation calls instead.

## Addendum (user directive, binding): unsafe pointers must earn their place

For every `Unsafe*Pointer`/`UnsafeRawPointer`/`withUnsafe*` use in
`src/swift/voicegroup/` after this task (tokenizer, descriptor fold, builder
writes into `ToneData`, name copies, keysplit table copies, file reads, locator
path probes, `ProjectBankLease` slot accessors, picker reads):

1. Write the memory-safe equivalent using Swift 6.2+ `Span`, `MutableSpan`,
   `RawSpan`, `OutputSpan`, or `InlineArray` (the toolchain is 6.4; `Lifetimes`
   is enabled where needed — see `src/swift/document/CMakeLists.txt`).
2. Benchmark both on the real-project sweep (`PORYDAW_PARITY_PROJECT_ROOT`)
   inside the parity check, same window as the time gate, alternating A/B at
   least 5 rounds, reporting median per variant.
3. Keep the unsafe version only where the safe one is more than 25 % slower
   on that path; otherwise ship the safe one and delete the unsafe code.
4. The C boundary handoffs are exempt and documented as such in ≤ 1 comment
   line each: the `ToneData*` given to `m4a_engine_set_voicegroup`, the
   `WaveData*`/`UInt32*` returned by `vg_asset_decode_*`, and the final
   `free()`. Swift-side reads/writes of that memory are NOT exempt — they go
   through spans unless the benchmark says otherwise.
5. Report a table in your result: site, safe variant, unsafe ms, safe ms,
   decision. The controller copies it into `docs/BUILDING.md`.
