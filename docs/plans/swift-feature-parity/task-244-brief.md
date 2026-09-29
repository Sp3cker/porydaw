# Task 244 brief — Render pipeline: `SampleDocument`, loop crossfade, 8-bit WAV writer, corpus agreement

# Context

Spec.md: crop, DC policy, resampling, normalization, loop crossfade, micro-fades,
quantization/dither and metadata "in the existing render order"; retune changes pitch
metadata only; immutable hi-res source with non-destructive parameters; final audition PCM,
WAV metadata and the ROM asset agree (RIFF padding, `smpl`/`agbp`/`agbl` laws). This task
ports the fork's deterministic render (`SampleDocument`), its parameter/result types and the
unsigned-8-bit sample WAV writer, and restores the fork's optional real-project corpus
comparison (default render vs the `.bin` a real wav2agb build produced).

Surface: `SampleDocument` render + `SampleWavWriter` (SA03/SA06 byte laws).
Ledger spec and rows (→ MATCHED unless noted):
- `proof.dsp.txt` A026–A034 (dspDeterminism), A052–A056 (parityLoopGeometry), A057–A065
  (parityRiffPadding), A066–A067 (retuneVectors).
- `proof.analysis.txt` A016–A021 (loopAndCrossfade: crossfade bake).
- `proof.decoder.txt` A072–A073 (FLAC through the render); A080 (`QSKIP` when no corpus) →
  RETIRED-REPRESENTATION ("harness skip guard; the Swift predicate is gated by the optional
  corpus argument"); A081–A093 (optionalCorpus) → MATCHED only when the controller run
  supplied `PORYDAW_SAMPLE_CORPUS` and the evidence carries them; otherwise untouched.
- `proof.soundfont.txt` A018 (zone 0 renders looped through the pipeline).
Verify lane: `samplecheck` (+ optional corpus run).
Blocked rows left untouched: dsp A035–A051 (246); analysis A001–A015 (245); decoder A081–A093
when no corpus run happened (blocker: external built project corpus).

Oracles: `git show fceecd88:src/audio/sampledata.h` 60–122 (`kGbaDefaultRate`,
`SampleEditParams`, `ProcessedSample`), `src/audio/sampledoc.{h,cpp}` (`defaultParams` 20–49,
`setParams` 51, `processed` 59, `render` 68–252 stages [1] crop, [2] DC, [3] resample +
loop-ratio nudge, [6] normalize, [7] crossfade bake, [8] micro-fades, [9] quantize + header
fields), `src/audio/samplewav.cpp` (`writeSampleWav`), `docs/old/sample-editor/DSP.md` §1,
§7, §8 and `FORMATS.md` §1–§4. Check oracle: `git show
fceecd88:src/checks/samplecheck/dsp.cpp` 26–91 (`ParityProfile`, `importHiRes`,
`parityParams`), 318–361, 437–506; `analysis.cpp` 199–235; `decoder.cpp` 380–392 and
420–468 (corpus); `soundfont.cpp` A018 block.

# Exact write set

Production:

- `src/swift/sample/SampleEditParams.swift` — NEW: `SampleEditParams`, `ProcessedSample`.
- `src/swift/sample/SampleDocument.swift` — NEW: defaults + cached render.
- `src/swift/sample/SampleRender.swift` — NEW: the nine-stage render (incl. crossfade bake and
  micro-fades) as a pure function.
- `src/swift/sample/SampleWavWriter.swift` — NEW: `SampleWavWriter.bytes(for:)`.
- `src/swift/sample/CMakeLists.txt` — add the four files.

Checks and corpus plumbing:

- `src/checks/samplecheck/RenderPipelineChecks.swift` — NEW `runRenderPipelineChecks`
  (incl. the check-local RIFF chunk reader used by the padding rows and 246).
- `src/checks/samplecheck/SampleFixtures.swift` — add `ParityProfile` + `parityParams`.
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- `src/checks/support/corecheck/native_check.{h,cpp}` — `pdc_check_set_sample_corpus(const
  char *)` / `pdc_check_sample_corpus(void)` beside the mid2agb pair.
- `src/checks/support/corecheck/tst_swiftcore.cpp` — parse `--pdc-sample-corpus=<path>` the
  way `--pdc-mid2agb=` is parsed (197–203).
- `src/checks/support/corecheck/CoreCheckSupport.swift` — `CheckEnvironment.sampleCorpus:
  String?`.
- `src/checks/checkcatalog.cpp` — the `samplecheck` entry gets its own handler `swiftSample`
  (argv `--swiftcore {scratch} {mid2agb} sampleCheck {sample-corpus?}`,
  `optionalArgumentEnvironment {"{sample-corpus?}": "PORYDAW_SAMPLE_CORPUS"}`) that forwards
  `--pdc-sample-corpus=` only when the optional argument is present; fixture list unchanged.

Ledgers: `proof.dsp.txt`, `proof.analysis.txt`, `proof.decoder.txt`, `proof.soundfont.txt`
(rows above only).

# Prerequisites

243 (kernel), 241 (FLAC for A072–A073), 242 (fixture + zone extraction for soundfont A018;
also serializes the soundfont ledger writer).

# Interface contract

- `public struct SampleEditParams: Sendable, Equatable` — fork fields, Swift names:
  `cropStart` (incl.), `cropEnd` (excl.), `loopOn`, `loopStart`, `loopEnd` (incl., source
  coords), `baseKey` (60), `fineTuneCents` [0,100), `targetRate: Double`,
  `normalizeMode: NormalizeMode { auto, looped, oneShot, off }` (raw values 0–3, fork order),
  `dcRemove: Toggle { auto, on, off }` (0–2), `fadeIn` (true), `fadeOut` (true),
  `crossfadeOn` (false), `ditherOn` (false), `exactPitchOverride: UInt32` (0).
- `public struct ProcessedSample: Sendable, Equatable` — `s8: [Int8]`, `freq`, `loopStart`,
  `size`, `looped`, `declaredRate`, `unityNote`, `pitchFraction`, `outputRate`,
  `effectiveRate`, `normalizeGain`, `seam: SeamMetrics`, `warnings: [String]`,
  `preview: [Float]`.
- `public struct SampleDocument: Sendable` — `init(source: ImportedSample)`, `let source`,
  `static func defaultParams(for: ImportedSample) -> SampleEditParams` (fork 20–49: gbaReady
  keeps source rate, normalize/DC/fades off and `exactPitchOverride = source.exactPitch`;
  otherwise `min(sourceRate, 13379)`), `var params` (initially the defaults),
  `mutating func setParams(_:)` (no-op when equal), `var processed: ProcessedSample` (cached;
  recomputed only after a params change). Rendering is deterministic: equal
  source + params ⇒ byte-equal output.
- `public enum SampleWavWriter { static func bytes(for: ProcessedSample) -> Data }` — fork
  `writeSampleWav`: RIFF/WAVE, `fmt ` 16 (PCM, mono, `declaredRate`, byteRate = rate, align 1,
  8-bit), `data` unsigned (s8 + 128) with a pad byte when odd, `smpl` (36 + 24·loops;
  `unityNote`, `pitchFraction`, one forward loop `loopStart..size−1` when looped), `agbp` =
  `freq`, `agbl` = `size`, in that chunk order.

# Implementation steps

1. Types and `SampleDocument.defaultParams`.
2. `SampleRender.render(source:params:) -> ProcessedSample` in the fork stage order; crossfade
   bake and its warning for an impossible bake (fork [7]); micro-fades [8]; quantize once with
   `SampleDsp.quantizeBuffer`; header fields, `seam = SampleDsp.seamMetrics` on the quantized
   loop; retune only changes `freq`/`unityNote`/`pitchFraction`.
3. `SampleWavWriter`.
4. Corpus plumbing (C setter/getter, arg parse, `CheckEnvironment.sampleCorpus`, catalog
   handler) and the checks: dspDeterminism (A026–A034), parityLoopGeometry (A052–A056,
   profile A), parityRiffPadding (A057–A065, profile F, chunk offsets read by the check-local
   reader), retuneVectors (A066–A067 golden table), loopAndCrossfade bake (analysis
   A016–A021), FLAC render (decoder A072–A073), soundfont zone 0 render (A018) and
   optionalCorpus (decoder A081–A093: for each `sc88pro_*.wav` under the corpus, decode +
   default render equals the built `.bin` header/bytes, then the fork's median-peak and
   loop-RMS windows; with no corpus the predicate records nothing).
5. Ledger edits. When the corpus run executed and every decoder row is closed, delete
   `proof.decoder.txt` in this commit; otherwise it stays with A081–A093 open.

# Acceptance predicate

Default params follow the fork (gba-ready no-op path, 13379 Hz cap, 8000 Hz source kept),
identical inputs render identically, loop geometry/RIFF padding/chunk order/retune goldens
match the fork, the crossfade bake fixes only the fade window and refuses impossible loops,
and FLAC/SoundFont sources render through the same pipeline.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

Controller verification (optional corpus; closes decoder A081–A093 only when run): with a
built pret project whose `sound/direct_sound_samples/` holds `sc88pro_*.wav` and their built
`.bin` files,

```sh
PORYDAW_SAMPLE_CORPUS=<project root> /usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
```

Gap: without that run the real-wav2agb agreement stays unproven (rows untouched).

# Task-specific constraints

Pure value types; the render allocates its output buffers once per render. The fork's golden
numbers are the expected values. `SampleEditParams` raw values match the fork enums (sidecar
compatibility in 247).
