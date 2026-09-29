# Task 240 brief — Sample foundation: `PorydawSample` module, PCM decoder, `samplecheck` lane

# Context

P4 (ruling 10) ports the fork's Sample Studio. Nothing sample-processing exists in Swift today;
the fork's C++ owners were deleted at `5b8dcc9e` and survive only at the `fceecd88` oracle.
This task lays the pure-Swift domain module every later P4 task consumes, ports the fork's
single-stream front door for the uncompressed containers (WAV, AIFF), and registers the
`samplecheck` native lane that later P4 domain tasks extend. Compressed codecs are task 241;
SoundFont is 242; render/DSP are 243/244.

Surface: `SampleImport` — any supported source bytes/file → an immutable hi-res
`ImportedSample` or an actionable refusal (spec.md "Source and decode"; inventory SA02).
Ledger spec: `src/checks/samplecheck/proof.decoder.txt` A001–A056.
Verify lane: `samplecheck` (new; this task registers it).
Blocked rows left untouched: decoder A057–A079 (241), A072–A073 and A080–A093 (244); every
other samplecheck ledger.

Forward pointer: 241 extends `SampleImport`'s sniff with the compressed branches; 242, 244,
246, 247 consume `ImportedSample`, `SampleImportFailure` and `SampleNames.sanitize`.

Oracles (`git show fceecd88:<path>`): `src/audio/sampleimport.cpp` (`downmix`,
`appendDownmixWarnings`, `finishDiagnostics`, `rateFromAgbPitch`, `decodeWav` 113–274, `decodeAif`
276–437, `importAudioBytes` 558–596, `importAudioFile` 598), `src/audio/sampledata.h` 17–60
(`ImportedSample`, `kGbaDefaultRate`), `src/project/samplereg.cpp`
`SampleRegistrar::sanitizeSampleName`, `docs/old/sample-editor/FORMATS.md` §1–§3.
Check oracle: `git show fceecd88:src/checks/samplecheck/decoder.cpp` (decodeWidths,
decodeStereoPolicy incl. the f64 block 173–201 that `a7fcaa3` dropped — `fceecd88` is the
spec), `fixtures.{h,cpp}`, `project.cpp:39` `preparedSampleWav`.

# Exact write set

Production (new module):

- `src/swift/sample/CMakeLists.txt` — NEW: `add_library(PorydawSample STATIC …)` with the
  `PorydawProject` property/flag block shape (`Swift_MODULE_NAME PorydawSample`, module dir,
  language 6, `porydaw_enable_swift_batch_mode`, INTERFACE module-dir include). No Qt, no
  QtBridge, no link dependencies.
- `src/swift/sample/ImportedSample.swift` — NEW: `SampleSourceKind`, `ImportedSample`,
  `SampleImportFailure`.
- `src/swift/sample/SampleNames.swift` — NEW: `SampleNames.sanitize(_:)`.
- `src/swift/sample/SampleImport.swift` — NEW: front door, sniff, downmix, diagnostics.
- `src/swift/sample/SampleWavReader.swift` — NEW: RIFF/WAVE chunk walk + PCM/float conversion
  + `smpl`/`agbp`/`agbl` semantics.
- `src/swift/sample/SampleAiffReader.swift` — NEW: FORM/AIFF reader.
- `CMakeLists.txt` (root) — `add_subdirectory(src/swift/sample)` before `src/swift/project`.

Checks:

- `src/checks/samplecheck/SampleChecks.swift` — NEW: `runSampleChecks(_ report: CheckReport)`
  (the lane runner; one call per area, this task adds `runDecoderChecks`).
- `src/checks/samplecheck/SampleFixtures.swift` — NEW: ports of fork `fixtures.{h,cpp}`
  (`SampleFixtureSpec`, `fixtureWav`, `AiffFixtureSpec`, `fixtureAiff`, `putU16/putU32/getU32/
  putBe16/putBe32`, `genSine`, `genSineFast`, `rmsOf`, `toneAmp`, `median`, `genSaw`,
  `centsOff`) plus `preparedSampleWav()` (fork `project.cpp:39`).
- `src/checks/samplecheck/DecoderChecks.swift` — NEW: `runDecoderChecks`.
- `src/checks/support/corecheck/core_check.h` — `PDC_SUITE_SAMPLE = 35`.
- `src/checks/support/corecheck/tst_swiftcore.h`, `tst_swiftcore.cpp` — slot `sampleCheck()`
  calling `pdc_suite_run(PDC_SUITE_SAMPLE, …)` (the `displayList()` shape, 186–189).
- `src/checks/support/corecheck/CoreCheckSupport.swift` — `case 35:` `ReportBox` +
  `MainActor.assumeIsolated { runSampleChecks(…) }` (the case-32/33 shape).
- `src/checks/checkcatalog.cpp` — `swiftSuite("samplecheck", "sampleCheck");` after
  `swiftcore-displaylist` (130–131).
- `src/checks/CMakeLists.txt` — the three check files in `swift_core_check`'s source list;
  `PorydawSample` added to its `target_link_libraries`.

Ledger: `src/checks/samplecheck/proof.decoder.txt` (rows below + header).

Shared files (P4 registration order, see sprint-4 §P4): root `CMakeLists.txt`,
`src/checks/CMakeLists.txt`, `checkcatalog.cpp`, the corecheck registration trio.

# Prerequisites

None. Runs first in P4 (parallel with 255).

# Interface contract

- `public enum SampleSourceKind: Sendable { case wav, aif, mp3, flac, ogg, sf2 }`.
- `public struct ImportedSample: Sendable, Equatable` — the fork `ImportedSample` fields, Swift
  names: `buffer: [Float]` (mono, canonical scale value = s8/128), `sampleRate: Double`,
  `baseKey: Int` (60), `fracSemitone: Double` [0,1), `hasLoop`, `loopStart: Int` (inclusive),
  `loopEndInclusive: Int`, `playLength: Int`, `exactPitch: UInt32`, `hasPitchMetadata`,
  `suggestedName`, `sourcePath`, `sourceKind`, `sourceChannels: Int`, `sourceBits: Int`,
  `sourceFloat`, `gbaReady`, `phaseCancelStereo`, `warnings: [String]`; `var frameCount: Int`;
  `public static let gbaDefaultRate = 13379.0`. Public memberwise init (241/242 construct it).
- `public struct SampleImportFailure: Error, Equatable, Sendable { public let message: String }`
  — the message is the user-visible refusal text, verbatim from the fork.
- `public enum SampleNames { public static func sanitize(_ raw: String) -> String }` — fork
  `sanitizeSampleName` (lowercase; `[a-z0-9]` kept; any run of other characters becomes one
  `_` only between kept characters).
- `public enum SampleImport`:
  - `static func decode(_ bytes: Data, sourcePath: String, leftChannelOnly: Bool = false)
    throws(SampleImportFailure) -> ImportedSample`
  - `static func decodeFile(path: String, leftChannelOnly: Bool = false)
    throws(SampleImportFailure) -> ImportedSample` — unreadable → `"cannot read <path>."`.
  - Sniff order and refusals exactly as fork `importAudioBytes`: RIFF…WAVE → WAV; FORM…AIFF
    → AIFF; FORM…AIFC → the AIFF-C refusal; RIFF…sfbk → the "SoundFont files hold multiple
    samples…" refusal; everything else → the "not a supported audio file (WAV, AIFF, MP3,
    FLAC, and Ogg Vorbis sources are supported)." refusal (241 inserts its branches before
    this fallthrough). Suffixes are never consulted. `suggestedName =
    SampleNames.sanitize(<basename without extensions>)`, `sourcePath` as given.
  - Downmix/warnings/diagnostics = fork `downmix` (double accumulation, positive-zero start,
    L/R correlation < 0 ⇒ `phaseCancelStereo`), `appendDownmixWarnings` (exact strings,
    emitted at each decoder's original point), `finishDiagnostics` (> 0.1 % at |v| ≥ 0.9999).
- WAV: Swift parses RIFF itself (decision: the fork's own registrar/loader parse WAV
  in-house; `dr_wav` added nothing beyond container walking). Supported: PCM 8/16/24/32,
  IEEE float 32/64, `WAVE_FORMAT_EXTENSIBLE` translated to its sub-format tag; conversions
  u8 `(x−128)/128`, s16 `/32768`, s24 sign-extended `/8388608`, s32 `/2147483648`, float
  clamped to ±1 with the fork's clamp warning; a `data` chunk claiming more than the file
  holds is clamped to the bytes present (row A053); `smpl` (unity clamped ≤127, pitch
  fraction, first loop; non-forward loop dropped with the fork warning), top-level
  `agbp`/`agbl` u32 LE, and `decodeWav` 241–270 semantics for `playLength`, loop kept iff
  `loopStart < min(loopEndExcl, n) − 1`, `hasPitchMetadata`, agbp-derived exact rate via
  `rateFromAgbPitch`, `gbaReady = PCM && 8-bit && mono`. Refusals use the fork `decodeWav`
  strings (corrupt/truncated, unsupported format, missing fmt/data, no audio data).
- AIFF: fork `decodeAif` 276–437 verbatim semantics (COMM/MARK/INST/SSND, 80-bit extended
  rate, BE 8/16/24/32 via `ldexp(s, −(bits−1))`, INST base note/detune → `baseKey`/`frac`,
  marker loop end exclusive → inclusive, swap/invalid-loop warning).

# Implementation steps

1. Module + types + `SampleNames` + root `add_subdirectory`.
2. `SampleWavReader` / `SampleAiffReader` returning interleaved `Double` channel data plus
   container metadata; `SampleImport.decode` sniffs, calls them, downmixes, applies the
   metadata laws and diagnostics. No partial `ImportedSample` escapes a refusal.
3. `SampleFixtures.swift`: byte-exact ports of the fork fixture writers (they author the
   inputs, so independent literals stay in the checks).
4. `DecoderChecks.swift`: one predicate per fork assertion with a unique message literal,
   cppID `samplecheck/SampleProcessingTest::<method>` (decodeWidths, decodeStereoPolicy,
   decodeAiff, decodeRefusalBoundaries). Include one `decodeFile` leg through a WAV written to
   `CheckEnvironment`'s scratch root (the file ingress) and one unreadable-path refusal.
5. Lane registration (write set list) + runner call.
6. Ledger: A001–A029, A031–A056 → MATCHED (compact form, message-anchored S entries); A030
   (`QFAIL("unsupported PCM test width")` data-row dispatch guard) → RETIRED-REPRESENTATION,
   reason "harness data-row dispatch guard; Swift rows are explicit calls". Header:
   `Swift counterpart: src/checks/samplecheck/DecoderChecks.swift`, `Command: deno task checks
   --filter samplecheck --verbose`.

# Acceptance predicate

Synthesized u8/s16/s24/f32/f64/extensible WAV and AIFF sources decode to the fork's exact
buffers and metadata (agbp-exact rate, agbl play length, smpl/INST pitch, loops), stereo
sources obey the mean/left-only/phase-cancel policy with the fork warnings, and every refusal
boundary yields the fork message with no sample — observed on the new lane.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

Coverage: the lane runs every decoder predicate above. `proof check` confirms the anchors
executed; the decoder ledger stays open (241/244 rows). Gap: none for this row set.

# Task-specific constraints

`PorydawSample` stays Foundation-only (no Qt, no QtBridge, no `import PorydawCore`); types are
`Sendable` values; `Data`-based APIs never copy the whole source twice. Do not port
`dr_wav`. Do not add `SampleEditParams`/`ProcessedSample` here (244 owns them). Refusal
strings are copied from the fork, not reworded.
