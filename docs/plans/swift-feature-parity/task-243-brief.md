# Task 243 brief — DSP kernel: resampler, quantization, marker mapping, normalization, seam metrics

# Context

Spec.md: "Use the old DSP implementation/tests as the numerical oracle: loop-aware
resampling and loop-ratio correction, alias/passband and gain limits, silent-input handling,
deterministic signed-8 floor/clamp quantization and fixed-seed dither." This task ports the
stateless kernel of fork `SampleDsp` that the render pipeline (244), analysis (245) and the
editor consume. Pitch detection and loop search are 245; the peak pyramid is 251.

Surface: `SampleDsp` kernel functions (SA03 numerics).
Ledger spec: `src/checks/samplecheck/proof.dsp.txt` A001–A025.
Verify lane: `samplecheck`.
Rows: A001–A024 → MATCHED; A025 (`QFAIL` data-row guard in normalization) →
RETIRED-REPRESENTATION ("harness data-row dispatch guard; Swift rows are explicit calls").
Blocked rows left untouched: A026–A034, A052–A067 (244), A035–A051 (246).

Oracles: `git show fceecd88:src/audio/sampledsp.h` (constants, signatures, inline
`quantizeToAgb8`/`mapMarker`, `SeamMetrics` in `sampledata.h` 91–100), `sampledsp.cpp`
17–213 (`besselI0`, `kaiserFromArg`, `resampleSinc` 54–118, `quantizeBuffer` 120–142,
`nearestZeroCrossing` 144–162, `normalizeGain` 164–213) and 630–667 (`seamMetricsAt`);
`docs/old/sample-editor/DSP.md` §2, §3, §5, §6 (seam metrics). Check oracle: `git show
fceecd88:src/checks/samplecheck/dsp.cpp` 100–312 (resample*, quantization*, markerMapping,
normalization).

# Exact write set

- `src/swift/sample/SampleDsp.swift` — NEW: constants, quantization, markers, normalize.
- `src/swift/sample/SampleResampler.swift` — NEW: Kaiser-windowed sinc resampler.
- `src/swift/sample/SampleSeam.swift` — NEW: `SeamMetrics` + `SampleDsp.seamMetrics`.
- `src/swift/sample/CMakeLists.txt` — add the three files.
- `src/checks/samplecheck/SampleFixtures.swift` — add `hiResSampleWav()` (fork
  `project.cpp:54`: 16-bit mono 44100 Hz, 12000 frames, 220.5 Hz sine amp 0.5·32000, smpl
  loop 2000..9999).
- `src/checks/samplecheck/DspKernelChecks.swift` — NEW `runDspKernelChecks`.
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledger `proof.dsp.txt` rows above + header (`Swift counterpart`, `Command`).

# Prerequisites

240 (module, lane, fixtures file). Parallel with 241/242.

# Interface contract

`public enum SampleDsp` (all pure, `Sendable` inputs):

- `static let targetLoopRms = 45.5 / 128.0`, `peakCeiling = 125.0 / 128.0`,
  `maxAutoGain = 15.848931924611133`.
- `static func resampleSinc(_ x: [Float], ratio: Double, outCount: Int, loopWrapStart: Int = 0,
  loopWrapExclusive: Int = 0) -> [Float]` — fork algorithm (Kaiser window from `besselI0`,
  tap count, cutoff and loop-wrap reads exactly as `resampleSinc` 54–118); ratio 1.0 is a
  bit-exact identity.
- `static func quantizeToAgb8(_ x: Double) -> Int8` — `floor(x·128)` clamped to [−128, 127].
- `static func quantizeBuffer(_ x: [Float], dither: Bool) -> [Int8]` — fork TPDF dither with
  the LCG seed `0x50525944`, multiplier `1664525`, increment `1013904223`, two uniforms per
  sample; byte-identical to the fork for identical input.
- `static func nearestZeroCrossing(_ x: [Float], _ index: Int) -> Int` — fork 144–162.
- `static func mapMarker(_ sourcePosition: Int, cropStart: Int, ratio: Double) -> Int` —
  `llround((pos − cropStart)·ratio)`.
- `static func normalizeGain(_ x: [Float], loopedMode: Bool, loopStart: Int) ->
  (gain: Double, warning: String?)` — fork 164–213 incl. the near-silent warning text and gain
  1.0.
- `public struct SeamMetrics: Sendable, Equatable { valid, ampLsb, derivLsb, ncc, nccValid }`;
  `static func seamMetrics(_ s8: [Int8], loopStart: Int, loopEnd: Int) -> SeamMetrics` — fork
  `seamMetricsAt` 630–667 (NCC invalid without pre-loop context).

# Implementation steps

1. Port the kernel in the three files with `Double` intermediates exactly where the fork uses
   `double`; hot loops use `withUnsafeBufferPointer`, no per-sample allocation.
2. `DspKernelChecks.swift`: fork resamplePassband (A001, ±0.1 dB over 100 Hz–6 kHz),
   resampleAliasRejection (A002), resampleDcGain (A003), resampleImpulseSymmetry (A004–A005),
   resampleFrequencyAccuracy (A006), resampleIdentity (A007–A008), quantizationVectors (A009
   golden table), quantizationU8Roundtrip (A010), quantizationDither (A011–A012),
   markerMapping (A013–A017), normalization (A018–A024) — the fork thresholds and golden
   values as literals; one predicate per assertion; cppID
   `samplecheck/SampleProcessingTest::<method>`.
3. Ledger edits.

# Acceptance predicate

The kernel meets the fork's passband/alias/DC/impulse/frequency bounds, is identity at ratio
1, reproduces the quantization golden table, u8 round trip and deterministic dither, maps
markers to the fork values and normalizes looped/one-shot/near-silent input to the fork
targets and warnings.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

Gap: seam metrics execute here only through their own unit predicate; their fork rows
(dsp A029–A034, analysis) close in 244/245.

# Task-specific constraints

Numeric thresholds and goldens are copied from the fork check, never derived from the Swift
output. If a bound fails, the port is wrong — do not widen it. The lane runs under the
175-second alarm: keep synthesized signals at the fork lengths (use `genSineFast` where the
fork did).
