# Context

Expose the existing pure-C++ sample source-processing pipeline through one owned Swift value API and port the matching SwiftCore predicates. This is the processing half of the sample editor: source decoding, SF2 zone extraction, analysis, deterministic DSP/render, and export. Task 10's QML workflow consumes this API; task 12 adds project/editor lifecycle behavior. Do not change the C++ algorithms to make tests easier.

Historical source oracles are `src/checks/samplecheck/{analysis,decoder,dsp,soundfont}.cpp` and their four `proof.*.txt` ledgers: 229 assertion sites in 30 named test methods. Their implementation methods already live in `src/audio/sampleimport.{h,cpp}`, `sf2reader.{h,cpp}`, `sampledsp.{h,cpp}`, `sampledoc.{h,cpp}`, `samplewav.{h,cpp}`, and `auditionslots.{h,cpp}`.

# Exact write set

- `src/audio/swift_sample_processing.h` and `.cpp` — new narrow C ABI over the existing sample source, SF2, document, DSP, and WAV-export types; add the bridge and currently unlinked implementation units `src/audio/sampleimport.cpp`, `src/audio/sf2reader.cpp`, `src/audio/sampledsp.cpp`, `src/audio/sampledoc.cpp`, and `src/audio/samplewav.cpp` to `porydaw_app` in root `CMakeLists.txt`, with their existing headers as target sources where required. Compile and call these implementations; do not copy their algorithms.
- `src/swift/app/samples/SampleProcessingBackend.swift` — new typed Swift owner/facade over the C ABI; import the explicit `PorydawSampleProcessing` module added in `src/swift/app/module.modulemap.in`; add the Swift source to `src/swift/app/CMakeLists.txt`.
- `src/checks/workspace/sample_processing.swift` and `src/checks/workspace/sample_processing_fixtures.swift` — new SwiftCore predicates and retained check fixtures. The fixture file owns deterministic generated WAV recipes and copies the compressed byte corpus needed by the checks from the soon-retired native fixture header; do not call native `samplecheck` fixture helpers at runtime.
- `src/swift/app/module.modulemap.in` — add module `PorydawSampleProcessing` with header `@CMAKE_SOURCE_DIR@/src/audio/swift_sample_processing.h`; `src/checks/workspace/SessionChecks.swift` and `src/checks/CMakeLists.txt` — register `runSampleProcessingChecks` for 29 new predicates and compile the retained fixture/check sources; `src/checks/audio/AudioAuditionChecks.swift` — extend the existing `auditionSlotLifecycle` predicate in place, without another check registration or duplicate `cppID`.

Read-only inputs: the checked-in `src/checks/fixtures/decompproject/**`, fixture recipes and source oracles in `src/checks/samplecheck/{fixtures.h,fixtures.cpp,project.cpp}` plus `src/checks/samplecheck_fixtures.h`, and the four samplecheck proof ledgers. Do not edit the C++ source/header or proof ledgers; task 14 owns samplecheck proof reconciliation and task 17 later retires native checks. Use `PORYDAW_SAMPLE_CORPUS` only when present; absent optional corpus cases are skipped rather than becoming required. Task 10 consumes the facade after this task lands.

# Prerequisites

Tasks 5, 8, and 9 for the existing app/check module conventions, voice/sample vocabulary, and compiled service-worker boundary. This task has no task 10 dependency; it adds the required processing units to the shared root target before task 10 consumes the facade. No QML or project mutation work is required here.

# Interface contract

- C ABI types are opaque, owning handles for `ImportedSample`, `Sf2File`, and `SampleDocument`. They never expose Qt/C++ containers or `SampleEditorDialog` to Swift. Import inputs are borrowed only for the call; results crossing into Swift are copied value data, and every handle has one explicit release function. Do not retain callback-borrowed buffers or pass C++ object pointers across the Clang importer.
- `SampleProcessingBackend` is the sole Swift facade used by the app and checks:
  - `importAudio(bytes:sourcePath:leftChannelOnly:) throws -> SampleSource` calls `importAudioBytes`; dispatch is by magic bytes, not extension. `SampleSource` exposes the consumer-visible decoded frame count/rate, base key/fraction, loop and playable-length metadata, exact pitch, source kind/channel/bit/float facts, GBA-ready state, phase-cancel warning, and refusal/warning strings.
  - `readSoundFont(bytes:sourcePath:) throws -> SoundFontSource` calls `readSf2Bytes` and returns the presentable zone/instrument/preset records. `extractZone(_:index:) throws -> SampleSource` calls `extractSf2Zone` and preserves stereo-pair warning and SF2 index metadata.
  - `makeDocument(source:params:) -> SampleDocumentHandle`, `setParameters(_:on:)`, `render(_:) -> SampleRender`, and `writeWav(_:) -> Data` own the `SampleDocument`/render lifetime and reuse `SampleDocument::defaultParams`, `setParams`, `processed`, and `writeSampleWav`. `SampleRender` exposes final PCM8 bytes, GBA header values, exact/output/effective rates, normalization gain, seam metrics, and warnings.
  - Internal check operations wrap, rather than reimplement, `SampleDsp::resampleSinc`, `quantizeBuffer`, `nearestZeroCrossing`, `mapMarker`, `normalizeGain`, `detectPitchYin`, `suggestLoop`, `refineLoop`, `seamMetricsAt`, and `PeakPyramid`. Keep them internal to the Swift app/check modules; do not add a second DSP implementation in Swift.
  - Source/import refusal is a typed error carrying the canonical importer message. A phase-cancelling stereo source is returned with its warning; callers may explicitly request left-channel-only re-import.
- Preserve the existing algorithms exactly: magic-byte dispatch; WAV widths and metadata; AIFF and supported compressed formats; arithmetic stereo downmix plus phase-cancel warning; normalized source scale; windowed-sinc/Kaiser resampling and loop-wrap behavior; bit-matched floor/clamp quantization and fixed-seed dither; marker mapping; guarded normalization; YIN pitch detection as prefill-only; best-first loop candidates, refine, and seam metrics; and deterministic unsigned-8 mono WAV export.
- SwiftCore check method names mirror the original `SampleProcessingTest` method identity. Every check emits the exact `cppID` `samplecheck/SampleProcessingTest::<method>`; it must assert values the app/editor consumer receives, not source text, C ABI field forwarding, or direct echoes.

# Implementation steps

1. Add the C ABI with opaque source/SF2/document handles, bounded callback/copy ownership, and release functions. Implement each operation as a direct call to the existing audio backend; leave its files and DSP constants unchanged.
2. Add the Swift `SampleProcessingBackend` value types/facade, import `PorydawSampleProcessing` from the explicit module in `src/swift/app/module.modulemap.in`, and register the new Swift source in `src/swift/app/CMakeLists.txt`.
3. Add the retained Swift check fixture in `src/checks/workspace/sample_processing_fixtures.swift`: reproduce deterministic WAV inputs from `src/checks/samplecheck/{fixtures.h,fixtures.cpp,project.cpp}` and copy the required compressed-container byte arrays from `src/checks/samplecheck_fixtures.h` so they survive task 17 retirement. Do not call uncompiled native helpers such as `samplecheck::preparedSampleWav()` at runtime. Use the checked-in decompproject fixtures; skip only cases whose optional `PORYDAW_SAMPLE_CORPUS` is absent. Add or extend one runnable SwiftCore predicate for each source method below, asserting the consumer-visible values from the fixture/source assertions:

   | Proof source | Swift predicates (one per named source method) |
   |---|---|
   | `proof.analysis.txt` | `pitchMatrix`, `pitchNegativeCases`, `loopAndCrossfade`, `auditionSlotLifecycle` |
   | `proof.decoder.txt` | `decodeWidths`, `decodeStereoPolicy`, `decodeAiff`, `decodeRefusalBoundaries`, `compressedContainers`, `compressedRefusals`, `optionalCorpus` |
   | `proof.dsp.txt` | `dspDeterminism`, `markerMapping`, `normalization`, `parityCases`, `parityLoopGeometry`, `parityRiffPadding`, `quantizationDither`, `quantizationU8Roundtrip`, `quantizationVectors`, `resampleAliasRejection`, `resampleDcGain`, `resampleFrequencyAccuracy`, `resampleIdentity`, `resampleImpulseSymmetry`, `resamplePassband`, `retuneVectors` |
   | `proof.soundfont.txt` | `soundFontExtraction`, `soundFontPicker`, `soundFontRefusals` |

- `auditionSlotLifecycle` already emits its `samplecheck/SampleProcessingTest::auditionSlotLifecycle` cppID from `src/checks/audio/AudioAuditionChecks.swift` and is already called by the SwiftCore audio suite. Extend that exact `checkSampleAuditionSlots` predicate to cover `analysis.cpp:301-307` engine destroy, cold reinitialization at 32768 Hz, pool reset, and one-channel post-reset playback; do not add a duplicate `cppID` or register a second lifecycle check.
4. Register `runSampleProcessingChecks(report:fixtureRoot:)` in the existing `swiftcore` session suite for the 29 new sample-processing predicates only. Keep each source method's real boundaries/refusals and compare exact output or consumer-visible metadata; do not turn an unavailable optional corpus into an unconditional required file. The existing audio suite continues to run the extended `auditionSlotLifecycle` predicate.

# Acceptance predicate

- `deno task build:app` and `deno task build:checks` succeed.
- `deno task verify --filter swiftcore --verbose` executes all 30 named Swift predicates against retained fixtures and reports exact `samplecheck/SampleProcessingTest::<method>` IDs: 29 new predicates from `runSampleProcessingChecks` and the extended, already-registered `auditionSlotLifecycle` predicate.
- Results prove byte/data behavior at the actual Swift facade boundary: decoded width/channel/metadata/refusal outcomes; supported/refused compressed inputs; SF2 catalog/extraction facts; deterministic DSP/output invariants and tolerances; document defaults and rendered/exported GBA values; and audition slot lifecycle through engine destroy, cold reinitialization at 32768 Hz, pool reset, and successful post-reset playback.
- No `SampleProcessingTest` C++ executable is treated as this task's Swift parity evidence. Task 14 reconciles the samplecheck proof ledgers only after these predicates pass; task 17 retires native sources only after proof gates are green.

# Task-specific constraints

- Keep source processing as the existing pure C++ backend. No copied DSP algorithms, fallback decoder, wrapper QWidget, or format-specific guessed behavior.
- Preserve original assertion semantics and tolerances from the proof/source fixtures; do not weaken vector, frequency, seam, refusal, or metadata boundaries.
- The facade is a product-consumer seam for task 10 and task 12, not a test-only substitute API. Task 12 may extend its contract only for lifecycle operations and must not fork the processing model.
