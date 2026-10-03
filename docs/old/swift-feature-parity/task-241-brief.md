# Task 241 brief — Compressed sources: MP3/FLAC/Ogg through one narrow C codec seam

# Context

Spec.md requires MP3, FLAC and Ogg Vorbis import with content sniffing and deterministic
refusals. These are real codecs; the fork decoded them with vendored single-header
libraries (`dr_mp3`, `dr_flac`, `stb_vorbis`) that `5b8dcc9e` deleted together with their
only consumer. `src/audio/` is inside the AGENTS.md native boundary ("C decoders behind a C
ABI"). Decision: restore exactly those three vendored decoders (not `dr_wav` — task 240
parses WAV in Swift) behind one C function; Swift keeps sniffing, conversion laws, downmix,
the size backstop's messages and the refusal taxonomy.

Surface: `SampleImport.decode` for MP3/FLAC/Ogg sources (spec.md "Source and decode").
Ledger spec: `proof.decoder.txt` A057–A071, A074–A079.
Verify lane: `samplecheck`.
Blocked rows left untouched: decoder A072–A073 (need the 244 render), A080–A093 (244).

Oracles: `git show fceecd88:src/audio/sampleimport.cpp` 1–35 (defines), 439–556
(`decodeMp3`/`decodeFlac`/`decodeOgg`), 558–596 (sniff order); `git show
5b8dcc9e^:CMakeLists.txt` (the removed `stb_vorbis_impl.c`, include dirs and
`PORYDAW_AUDIO_ALWAYS_OPTIMIZE_SRCS` entry); check oracle `git show
fceecd88:src/checks/samplecheck/decoder.cpp` compressedContainers/compressedRefusals and
`fceecd88:src/checks/samplecheck_fixtures.h` (`kFixtureMp3/Flac/Ogg/Opus`).

# Exact write set

Native (boundary):

- `external/dr_libs/dr_mp3.h`, `external/dr_libs/dr_flac.h`, `external/dr_libs/LICENSES.md`,
  `external/stb/stb_vorbis.c` — restored byte-for-byte from `5b8dcc9e^` (no edits).
- `src/audio/sample_codec.h` — NEW C header (contract below).
- `src/audio/sample_codec.c` — NEW: the three implementations (`DR_MP3_IMPLEMENTATION`,
  `DR_FLAC_IMPLEMENTATION`, `*_NO_STDIO`, `#include "stb_vorbis.c"` with `STB_VORBIS_NO_STDIO`)
  plus `pd_sample_decode`/`pd_sample_pcm_free`.
- `src/audio/sample_codec.modulemap` — NEW static map `module PorydawSampleCodec { header
  "sample_codec.h" export * }` (the `src/render/module.modulemap` precedent).
- `CMakeLists.txt` (root) — `src/audio/sample_codec.{h,c}` in `porydaw_app`'s source list next
  to `miniaudio_impl.c`; `external/dr_libs` and `external/stb` in
  `target_include_directories(porydaw_app SYSTEM PRIVATE …)`; `src/audio/sample_codec.c` in
  `PORYDAW_AUDIO_ALWAYS_OPTIMIZE_SRCS`.

Swift:

- `src/swift/sample/CMakeLists.txt` — `SampleCompressedDecode.swift` in the source list;
  PUBLIC `-Xcc -fmodule-map-file=${CMAKE_SOURCE_DIR}/src/audio/sample_codec.modulemap` and
  `-Xcc -I${CMAKE_SOURCE_DIR}/src/audio`.
- `src/swift/sample/SampleCompressedDecode.swift` — NEW: `import PorydawSampleCodec`; maps
  codec output/status to `ImportedSample`/`SampleImportFailure`.
- `src/swift/sample/SampleImport.swift` — three sniff branches inserted before the
  unsupported-file fallthrough (240's function; no other change).

Checks/fixtures:

- `src/checks/fixtures/decompproject/samplesources/tone.mp3`, `tone.flac`, `tone.ogg`,
  `tone.opus` — NEW binaries, byte-identical to the fork arrays `kFixtureMp3/Flac/Ogg/Opus`
  (extract with a throwaway script; never commit the script).
- `src/checks/checkcatalog.cpp` — replace 240's `swiftSuite("samplecheck", …)` line with an
  explicit entry of the same argv/handler whose `fixtureFiles` are `swiftCoreFixtures` plus the
  four `samplesources/` files.
- `src/checks/samplecheck/CompressedDecoderChecks.swift` — NEW `runCompressedDecoderChecks`.
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.

Ledger: `proof.decoder.txt` rows below.

# Prerequisites

240 (`SampleImport`, `ImportedSample`, `SampleImportFailure`, lane). Parallel with 242/243.

# Interface contract

C (`sample_codec.h`, C11, no Qt, `extern "C"` guards):

```c
typedef enum { PD_SAMPLE_CODEC_MP3 = 1, PD_SAMPLE_CODEC_FLAC = 2, PD_SAMPLE_CODEC_OGG = 3 } PdSampleCodec;
typedef enum { PD_SAMPLE_DECODE_OK = 0, PD_SAMPLE_DECODE_CORRUPT, PD_SAMPLE_DECODE_EMPTY,
               PD_SAMPLE_DECODE_TOO_LONG, PD_SAMPLE_DECODE_NO_MEMORY } PdSampleDecodeStatus;
typedef struct { uint32_t channels, sampleRate, bitsPerSample; uint64_t sampleCount;
                 float *f32; int32_t *s32; } PdSamplePcm;   /* interleaved; exactly one of f32/s32 */
PdSampleDecodeStatus pd_sample_decode(PdSampleCodec codec, const uint8_t *bytes, size_t length,
                                      uint64_t maxInterleavedSamples, PdSamplePcm *out);
void pd_sample_pcm_free(PdSamplePcm *pcm);
```

Semantics per codec mirror the fork loops exactly: MP3/Ogg decode in 4096-frame chunks to
`f32` (`drmp3_read_pcm_frames_f32`, `stb_vorbis_get_samples_float_interleaved`), check the
backstop after each chunk (`TOO_LONG`), zero decoded samples → `EMPTY`, open failure →
`CORRUPT`; FLAC fills `s32` via `drflac_read_pcm_frames_s32`, `channels < 1 || frames == 0`
→ `EMPTY`, `frames > max / channels` → `TOO_LONG`, short read → `CORRUPT`;
`bitsPerSample` = FLAC stream depth, 0 for MP3/Ogg; allocation failure → `NO_MEMORY`. On any
non-OK status `out` owns nothing. No clamping, scaling or downmixing in C.

Swift: `SampleImport.decode` sniffs `fLaC` (≥4 bytes) → FLAC, `OggS` → Ogg, `ID3` or
`0xFF, (b1 & 0xE0) == 0xE0` → MP3, in the fork order after the AIFF/SF2 checks; passes
`maxInterleavedSamples = 1 << 26`; converts MP3/Ogg samples with `clamp(±1)` (no warning)
and FLAC with `Double(s) / 2147483648`; reuses 240's downmix/warning/diagnostic path; sets
`sourceKind`, `sourceChannels`, `sourceBits` (FLAC only), `sampleRate`, `playLength =
frameCount`, no pitch/loop metadata. Status → message, verbatim fork strings: MP3 `CORRUPT`
"the MP3 file is corrupt or truncated.", FLAC `CORRUPT` "the FLAC file is corrupt or
truncated.", Ogg `CORRUPT` "cannot decode the Ogg file — only Ogg Vorbis is supported (Opus
and other codecs are not).", `EMPTY` "no audio data.", `TOO_LONG` and `NO_MEMORY` "the
<MP3|FLAC|Ogg> file is too long to import." (allocation failure is the backstop's failure
mode; decision recorded in sprint-4 §P4).

# Implementation steps

1. Restore the vendored files; add the C seam and CMake wiring; keep warnings suppressed only
   by the SYSTEM include (no pragma blankets in `sample_codec.c` beyond what the vendored
   headers need).
2. `SampleCompressedDecode.swift` + the three sniff branches.
3. Fixture binaries + catalog entry fixture list.
4. `CompressedDecoderChecks.swift`: fork compressedContainers (A057–A071: kind, channels,
   bits, rate, gapless 5512 frames, amplitudes, FLAC `maxDiff < 3e-7` vs `genSine` and the
   FNV golden `0x6c3d054141a6aae7`, Ogg left-only warning) and compressedRefusals (A074–A079:
   Opus, sync-less ID3 MP3, corrupt `fLaC`) — inputs read from the staged `samplesources/`
   files through `SampleImport.decodeFile` (file ingress) except the corrupted/truncated
   variants, which the check derives from those bytes in memory.
5. Ledger: A057–A071, A074–A079 → MATCHED.

# Acceptance predicate

The staged MP3/FLAC/Ogg fixtures import through content sniffing to the fork's exact frame
counts, rates, amplitudes and FLAC hash; Opus, sync-less MP3 and corrupt FLAC refuse with the
fork messages.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task build:app
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

`build:app` proves the app target links the codec; the lane covers every predicate. Gap:
Linux/Windows builds of the C seam (P9).

# Task-specific constraints

The C file is the only new native code; no Qt, no C++, no Swift-visible struct beyond the
header. Vendored files are never edited. The FNV golden and `maxDiff` bound are the fork's
numbers — a mismatch is a conversion bug, not a re-pin.
