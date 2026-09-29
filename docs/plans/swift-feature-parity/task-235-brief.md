# Task 235 brief — the Standard MIDI File decoder parses spans with swift-binary-parsing

# Context

User direction (2026-09-29): the Import MIDI feature gets a very fast MIDI parser and may
use Apple's `swift-binary-parsing` library; implementers use modern Swift features (`Span`,
`RawSpan`, `InlineArray`, `OutputSpan`) where they fit.

Every SMF read in the app goes through `MidiFile.decode(_:)`
(`src/swift/core/MidiFile.swift:306`): song open (`DocumentSession.swift:303`), playback
(`PlaybackBridge.swift:114`) and, from task 230, Import MIDI analysis. Its reader
`MidiByteReader` (`MidiFile+Codec.swift:3-50`) copies the whole file into `[UInt8]`, indexes
it with manual bounds checks, and allocates an `Array` per payload read (`read(count:)`).

This task is a behavior-preserving refactor: the decoder's observable results, byte-exact
opaque payloads and error taxonomy stay identical; only the parsing machinery changes to
`BinaryParsing`'s `ParserSpan` over the input bytes. Consumers (230–234, song open,
playback) keep calling `MidiFile.decode` unchanged. Encoding (`encoded()`) is out of scope.

Surface: MIDI file loading (song open, playback, Import MIDI analysis).
Ledger spec: none (no open ledger row pins decoder internals); the existing codec
predicates are the oracle.
Verify lanes: `swiftcore-midicodec`, `swiftcore-midiimport`, `swiftcore-projectsession`,
`swiftcore-playback` (commands below).
Blocked rows left untouched: all.

# Exact write set

- `cmake/BinaryParsing.cmake` (new): `FetchContent` of
  `https://github.com/apple/swift-binary-parsing.git` pinned to the newest release tag's
  full commit SHA, following `cmake/QtBridge.cmake` (include guard, pinned `GIT_TAG`).
  The package ships no CMake build: define `add_library(BinaryParsing STATIC …)` from its
  `Sources/BinaryParsing` files, module name `BinaryParsing`, Swift 6, and exactly the
  `swiftSettings` its `Package.swift` declares for that target (experimental/upcoming
  features, e.g. `Lifetimes`), module directory published like `PorydawCore`'s. No other
  target of the package is built.
- Root `CMakeLists.txt`: `include(cmake/BinaryParsing.cmake)` beside the QtBridge include
  (**hot**, shared with 233 and P4 QML list edits; one line).
- `src/swift/core/CMakeLists.txt`: link `BinaryParsing` into `PorydawCore`.
- `src/swift/core/MidiFile+Codec.swift`: replace `MidiByteReader` and the reader-based
  `parseTrack` with `ParserSpan`-based parsing.
- `src/swift/core/MidiFile.swift`: `decode(_:)` body only (signature unchanged).

# Prerequisites

None. Runs in parallel with 230/231 (disjoint files except none; 230/231 edit
`src/swift/app/CMakeLists.txt` and `src/checks/CMakeLists.txt`, not the files above).

# Interface contract

- `public static func decode(_ bytes: [UInt8]) throws -> MidiFile` keeps its signature and
  throws only `MidiCodecError` with the exact same cases, associated values and precedence
  as today for every input (header checks in the current order: magic →
  `notStandardMIDIFile`, header length → `invalidHeaderLength`/`invalidHeader`, format,
  SMPTE, zero division, `missingTrack`, `truncatedTrack`, and every per-track
  `malformed(...)` reason string produced by `parseTrack`). BinaryParsing's own errors
  never escape: map each parse failure site to the error the current code throws there.
- Parse through `bytes.withParserSpan { … }` (or the library's equivalent span entry) with
  no intermediate copies of the input; track chunks are sliced as sub-spans bounded by the
  chunk length (replacing the `through end:` checks). Variable-length quantities keep the
  4-byte limit and the current error on overflow.
- Opaque payloads (sysex, meta, unknown chunks if retained today) are materialized once,
  byte-exact, into the stored event type; running status, tick accumulation (`UInt64`),
  EOT handling and `stableTickSort` behavior are unchanged.
- No `Foundation.Data` round-trips, no per-byte `Array` appends where a span read or
  `InlineArray` fits (e.g. fixed-size header fields).

# Implementation steps

1. Add the dependency (`cmake/BinaryParsing.cmake`, root include, core link). Read the
   package's `Package.swift` for the target's required Swift settings and platforms; if it
   requires a newer toolchain than the repo's Swift 6.4 or cannot build under CMake without
   SwiftPM-only features, stop and report BLOCKED with the exact reason.
2. Rewrite the header and track parsing on `ParserSpan`, keeping each failure site's thrown
   `MidiCodecError` identical (list every site you mapped in the result).
3. Delete `MidiByteReader` and `ReaderFailure` if no longer referenced (grep `src/swift`
   and `src/checks`; checks must not depend on them — if one does, report it).

# Acceptance predicate

Every existing codec, import, session-open and playback predicate passes unchanged
(including the malformed-SMF fixtures under `test_midis/smf/malformed/` and the opaque sysex
and running-status fixtures), proving identical results and errors on the full corpus.

```sh
deno task build:checks
deno task checks --filter swiftcore-midicodec --verbose     # decode/encode round-trip, every malformed fixture's exact error
deno task checks --filter swiftcore-midiimport --verbose    # import analysis over decoded files
deno task checks --filter swiftcore-projectsession          # song open through DocumentSession
deno task checks --filter swiftcore-playback                # PlaybackBridge decode path
deno task build:app --release                               # optimized build compiles the dependency
```

Coverage gap: speed is not asserted by a check; report a before/after decode timing of the
largest fixture in `test_midis/smf/stress/` from a throwaway script (not committed).

# Task-specific constraints

- Seat `sdd-implementer`. No check or fixture edits: the existing predicates are the oracle
  and must pass untouched. No change to `encoded()` or any public PorydawCore API.
- `BinaryParsing` is linked only into `PorydawCore`; later P4 parsers may link it too
  (their briefs say so), nothing else.
- Swift 6.4 strict concurrency; no `unsafe` escapes beyond what the library's span APIs
  require; comments ≤2 lines.
