# Unsafe-pointer vs Span A/B results (T11 Addendum)

Method: inside `projectstore-parity`, five alternating unsafe/safe rounds per
site on the pokeemerald-expansion corpus (274 voicegroups); medians of the
named operation window, milliseconds, Debug checks build. Rule: ship the safe
variant unless it is more than 25 % slower on that operation. Benchmarked
losers and the A/B scaffolding were deleted afterwards (`history://T11Finish`).

| site | operation | safe variant | unsafe ms | safe ms | shipped |
|---|---|---|---|---|---|
| Bank slab zeroing | sweep load | `MutableSpan<UInt8>.update(repeating:)` | 360.6 | 367.8 | safe |
| Bank keysplit table copy | sweep load | `Span`/`MutableSpan` scalar copy | 362.5 | 363.4 | safe |
| BankBuilder tone write | sweep load | `MutableSpan<ToneData>` assignment | 360.9 | 362.2 | safe |
| BankBuilder name copy | sweep load | source `Span`, destination `MutableSpan<CChar>` | 359.4 | 360.8 | safe |
| Bank/SubBank name accessor | load + all name reads | bounded `Span` scan + `UTF8Span` | 377.5 | 380.7 | safe |
| WaveCache path storage and scan | sweep load | `InlineArray<512, UInt8>`, `Span`/`MutableSpan` | 359.7 | 382.7 | safe (6 %) |
| Locator probe path storage | sweep load | `InlineArray<512, UInt8>`, `Span`/`MutableSpan` | 360.5 | 359.9 | safe |
| File reader storage | sweep load | initialized `Array.mutableSpan`; narrow POSIX `read` handoff | 360.9 | 360.9 | safe |
| Lease tone/child/table accessors | load + lease slot, `subvoiceMacros`, `drumPadNames` reads | bounded `Span` reads | 395.6 | 396.1 | safe |
| Picker sample payload snapshot | load + sample/prog-wave snapshots | `Span<Int8>` + `OutputSpan` append | 368.7 | 660.6 | **unsafe** (safe 79 % slower) |
| Picker sample header read | same | `Span<WaveData>` read | 368.7 | 367.6 | safe |
| Picker programmable-wave snapshot | same | `Span<UInt32>.bytes`, `OutputSpan` | 368.7 | 369.9 | safe |
| Synth parameter cursor | `SoundDataMap` init parse | BinaryParsing `ParserSpan`/`RawSpan` | 8.0 | 8.0 | safe (no `set_synth_` in corpus; init-only) |
| Minted synth header/payload writes | sweep load | `MutableSpan<WaveData>`/`MutableSpan<Int8>` | 363.2 | 362.6 | safe (zero corpus coverage) |

Boundary-exempt (documented in code, not benchmarked): `ToneData*` handed to
`m4a_engine_set_voicegroup`, `WaveData*`/`UInt32*` returned by
`vg_asset_decode_*`, their `free()`, and POSIX syscall arguments.
