# Task 220 brief — one Swift production owner renders and writes the export WAV

# Context

P3 (user ruling 9, 2026-09-28; `repairs/p3-wav-export-draft.md`) ports File → Export
WAV. This task merges draft P3-T1 (totals + RIFF writer) and P3-T2 (streamed
renderer) and takes the ledger half of P3-T5: all three are proven by one run of the
two `exportcheck` entries, so the sizing rule makes them one task. The ledger
re-map goes here, not in a later task, because `proof-ledger-workflow` puts row
edits in the commit whose code and checks prove them.

Oracle, at `fceecd88`: `src/audio/wavexport.h` (options, totals, contract) and
`src/audio/wavexport.cpp`:
- `wavExportTotals` (`:42-54`): the duration law.
- `exportWav`: refusals (`:60-71`), open/truncate (`:73-78`), 44-byte header
  (`:80-93`), private engine and settings (`:97-105`), 4096-frame buffers
  (`:107-117`), `progress(0)` (`:123-124`), suppression pre-roll and zero flush
  (`:126-149`), chunk loop, fade and PCM (`:151-184`), cleanup (`:185-209`).

Duration preview and success text: `src/mainwindow.cpp:1247-1263`, `:1320-1327`.
Original check: `git show 97dc7fea:src/checks/midi/tst_midiexport.cpp`.

Anti-oracle to replace: `src/checks/projectstore/ExportChecks.swift`. It has a
private `renderExport`/`wavHeader` pair with fixed 1 s fade/tail math. It also goes
through `AudioRenderEngine.render`, which applies live output gain, stops 3 s after
the song ends and never pre-rolls the suppressor. The C ABI needs no new entry.
Swift already reaches the engine through `PorydawPlaybackNative`
(`m4a_engine_create`/`m4a_engine_free`, `AudioRenderEngine.swift:46-69`). The
sequencer is `Sequencer.render(engine:timeline:left:right:looping:muteMask:)`
(`src/swift/playback/Sequencer.swift:60-73`). The suppressor is the Swift port
`ResonanceSuppression` (`src/swift/app/audio/ResonanceSuppression.swift`,
`latency = 2047`).

Forward pointer: task 221 wraps `WavExport.render` in the async job and live-session
capture. Task 222 uses `WavExportTotals.previewSeconds`/`clockText` for the dialog.

- Surface: the export render/write engine that File → Export WAV runs. The menu is
  mounted in 222.
- Spec ledger: `src/checks/midi/proof.tst_midiexport.txt`.
- Verify lanes: `exportcheck-loop` (`mus_route101`) and `exportcheck-tail`
  (`mus_route102`). They are registered at `src/checks/checkcatalog.cpp:311-314` →
  `CoreCheckSupport.swift:231` → `runExportChecks`.

# Exact write set

Production:
- `src/swift/app/audio/WavExport.swift` (new, module `PorydawAppAudio`, one cohesive
  file): options, totals, preview, header, errors and the streamed renderer.
- `src/swift/app/audio/AudioRenderEngine.swift`: make `AudioSettings` `Sendable`.
  Turn the private instance `applySettings(_:)` into
  `public static func applySettings(_ settings: AudioSettings, to engine: UnsafeMutablePointer<M4AEngine>)`.
  Instance call sites pass `self.settings`. No behavior change.
- `src/swift/app/CMakeLists.txt`: add `audio/WavExport.swift` to `PorydawAppAudio`
  (**shared**: 221 and 222 also add sources).

Checks:
- `src/checks/projectstore/ExportChecks.swift`: rewrite over the production owner
  (**shared**: 221 appends one call).

Ledger:
- `src/checks/midi/proof.tst_midiexport.txt`: rows and S entries listed below, plus
  header `Command:`/`Result:` lines (they still cite `deno task verify`).

# Prerequisites

None. Read `plan.md` Global constraints and `spec.md` "WAV export — one production
implementation".

# Interface contract

All in `PorydawAppAudio`:

- `public struct WavExportOptions: Equatable, Sendable`
  - `static let sampleRates = [32_000, 44_100, 48_000]`
  - Fields: `sampleRate = 48_000`, `loopCount = 2`, `fadeoutSeconds = 5.0`,
    `tailSeconds = 3.0`, `resonanceSuppression = false`.
  - Memberwise public init with those defaults (`wavexport.h:20-26`).
- `public struct WavExportTotals: Equatable, Sendable`
  - Fields: `totalFrames: UInt64`, `fadeStartFrame: UInt64`.
    `static let noFade = UInt64.max`. Public memberwise init.
  - `init(timeline: borrowing PlaybackTimeline, options:)`: the `:42-54` law.
    - Looping (`timeline.hasLoop`): `fadeStart = loopStart + loopCount × (loopEnd − loopStart)`
      and `total = fadeStart + UInt64(fadeoutSeconds × rate + 0.5)`.
    - Otherwise: `total = lengthSamples + UInt64(tailSeconds × rate + 0.5)` and
      `fadeStart = noFade`.
  - `func gain(atFrame:) -> Float`: 1 before `fadeStartFrame`. From there on,
    `1 − Float(frame − fadeStart) / Float(total − fadeStart)` (`:163-167`). So the last
    frame is `1/fadeLength`, not 0. A zero fade never reaches the fade branch.
  - `static func previewSeconds(timeline:options:) -> Int`: the dialog preview
    (`mainwindow.cpp:1247-1260`).
    1. Scale `lengthSamples` by `options.sampleRate / timeline.sampleRate`, truncating.
       Scale the loop positions the same way only when looping.
    2. Compute the totals of the scaled positions.
    3. Return `Int(Double(total) / rate + 0.5)`.
  - `static func clockText(seconds:) -> String`: `m:ss` with two-digit zero-padded
    seconds (`:1261-1262`).
- `public enum WavExportError: Error, Equatable, Sendable`, with
  `var message: String` holding the fork texts:
  - `.nothingToRender`: `Nothing to render.`
  - `.exceedsRiffLimit`: `The rendered file would exceed the 4 GB WAV limit — reduce the loop count.`
  - `.cannotWrite(path:reason:)`: `Cannot write <path>: <reason>`.
- `public enum WavExportResult: Equatable, Sendable { case completed, cancelled }`.
- `public enum WavExport`:
  - `static let chunkFrames = 4096`
  - `static func header(totals:sampleRate:) throws(WavExportError) -> [UInt8]`
    - Checks, in order: `totalFrames == 0` → `.nothingToRender`;
      `totalFrames × 4 + 36 > UInt32.max` → `.exceedsRiffLimit` (`:60-71`).
    - Otherwise returns the `:80-93` 44 bytes: PCM, 2 channels, rate, `rate × 4`,
      block align 4, 16 bits, little-endian.
  - `static func render(to path: String, timeline: borrowing PlaybackTimeline, voices: UnsafeMutablePointer<ToneData>?, settings: AudioSettings, options: WavExportOptions, progress: (Double) -> Bool) throws(WavExportError) -> WavExportResult`
    - Synchronous and caller-thread; it never touches shared state. The caller keeps
      the voices' bank alive for the call (`wavexport.h:38-42`).
    - Precondition: `timeline.sampleRate == Double(options.sampleRate)`.
    - `progress` returns false to cancel.
    - Cancel returns `.cancelled`; a partial file never survives.

# Implementation steps

1. `WavExport.swift`, value types: implement options, totals, gain, preview, clock
   text, errors and header as specified. Header refusals run before any file is
   touched.
2. `WavExport.render`, in the order of `wavexport.cpp:56-209`:
   1. Compute totals and the header. Refusals throw with no file created.
   2. Create or truncate `path`. On failure throw `.cannotWrite` with the Foundation
      error description (or `strerror(errno)`) as the reason.
   3. Write the header.
   4. Create a private engine with `m4a_engine_create(Float(rate))` and free it with
      `defer`. Bind voices with the existing `AudioRenderEngine.bindEngineVoicegroup`.
      Then call `AudioRenderEngine.applySettings(settings, to:)` and
      `m4a_engine_set_pcm_mix_rate`, as `bind` does (`AudioRenderEngine.swift:122-124`).
      Do not chase, prime, mute or apply output gain; the fork does none of these.
   5. Allocate once, before the loop, and free with `defer`: L/R float buffers of
      `chunkFrames`, the interleaved suppression buffer, and one reusable 16 KiB
      byte buffer. Nothing allocates per chunk.
   6. Create `var player = Sequencer()`.
   7. Call `progress(0)` first; false means cancel before any PCM is written.
   8. Suppression on: create `ResonanceSuppression(sampleRate:)` with
      `setEnabled(true)`.
      - Pre-roll `ResonanceSuppression.latency` frames, in chunks, through the
        `:126-141` helper. The helper renders source frames only while
        `sourcePos < totalFrames` and zero-fills the rest.
      - The main loop feeds the same helper, so the last `latency` output frames are
        the zero flush. The frame count does not change.
   9. Chunk loop:
      - `n = min(chunkFrames, remaining)`.
      - Render with `looping: timeline.hasLoop, muteMask: 0`.
      - Apply `totals.gain(atFrame:)` per frame.
      - PCM16: clamp `sample × 32767` in `Float` to −32768…32767, truncate toward
        zero, and map NaN to 0. The fork's `int32_t` cast is not reproducible as a
        trapping Swift `Int32(_:)`.
      - Write the chunk, then call `progress(Double(pos) / Double(total))`. The last
        call is exactly 1.0.
   10. Cleanup:
       - Write failure: close the file, remove it, throw `.cannotWrite`.
       - Cancel: close the file, remove it, return `.cancelled`.
       - Close failure: remove the file, throw `.cannotWrite`.
       - The engine is freed on every path.
3. `ExportChecks.swift` rewrite.
   - Keep `withExportFixture(label:_:)`: the same two guards with the same messages
     (S001/S002), its name and `runExportChecks(_:)`. Change it to open
     `CheckEnvironment.fixtureRoot` directly (the runner's private staged root)
     rather than a `withTempProjectCopy` copy.
   - Delete `ExportFixture.fadeStart`/`totalFrames`, `appendU16`, `appendU32`,
     `wavHeader`, `pcm16`, `renderExport` and `exportChunk`.
   - Keep `le16`/`le32` as the independent decoder.
   - Replace the fixture totals with a check-local `expectedTotalFrames`, mirroring
     the original `expectedTotalSamples` (`tst_midiexport.cpp:176-183` at `97dc7fea`).
   - Every render goes through `song.bank.withVoices { WavExport.render(...) }`. Use
     the original options: 44 100 Hz, loop count 1, fade 1.0 s, tail 1.0 s.
     Settings: `songVolume = masterVolume`, `reverb = reverb > 0 ? reverb : 0`
     (original `:141-146`).
   - Outputs go to a per-case directory under `FileManager.default.temporaryDirectory`.
   - Each clause is a message-anchored `report.expect`, so failures carry the error
     string.
4. Ledger predicates. Keep the S IDs; `proof:edit` each S to a message anchor for
   the predicate below:

   | S | Predicate | Rows |
   |---|---|---|
   | S003 | fixture opens the staged song and builds its timeline | A003, A005, A024, A032 |
   | S004 | production totals equal `expectedTotalFrames` | A004 |
   | S005 | exported WAV reads back | A009 |
   | S006 | per-case scratch directory created | A006, A025, A033 |
   | S007 | export completes | A007 |
   | S008 | progress strictly monotonic ending at 1.0 | A008 |
   | S009 | cancelled export reports no error: `.cancelled`, not a throw | A035 |
   | S010 | byte count = 44 + 4 × frames | A010 |
   | S011 | the ten `:242-251` header fields | A011–A020 |
   | S012 | peak ≥ 256 | A021 |
   | S013 | loop total ≥ 16 | A022 |
   | S014 | last 16 frames' peak ≤ peak/16 | A023 |
   | S015 | baseline completes | A026 |
   | S016 | suppressed completes | A028 |
   | S017 | baseline reads back | A027 |
   | S018 | suppressed reads back | A029 |
   | S019 | suppressed frame count equals baseline | A030 |
   | S020 | suppressed PCM differs | A031 |
   | S021 | cancel at `progress(0)` returns `.cancelled` | A034 |
   | S022 | no partial file | A036 |

   - Row outcome: 34 MATCHED. A001 and A002 stay PARTIAL, untouched, still citing
     S001/S002.
   - Update each row's Mapping line to its S IDs. Drop A004's S006 citation.
5. Non-ledger production predicates (cppID `exportcheck/WavExport::<case>`):
   - Zero fade → `total == fadeStart`; zero tail → `total == lengthSamples`.
   - Loop count 3 minus 2 equals the loop length.
   - Rounding: 0.1 s at 44 100 → 4 410 frames; 1.25 s at 32 000 → 40 000.
   - Gain: 1 at `fadeStart − 1` and at `fadeStart`; `1/fadeLength` at `total − 1`;
     no-loop gain is 1 everywhere.
   - Header boundary: 1 073 741 814 frames accepted; 1 073 741 815 frames refused
     with `.exceedsRiffLimit` and the fork text. 0 frames refused with
     `.nothingToRender` and its text.
   - An empty `MidiFile()` timeline with tail 0 renders as `.nothingToRender` and
     leaves no file.
   - A path inside a nonexistent directory throws `.cannotWrite`. Its message starts
     with `Cannot write <path>: ` and no file is left.
   - Suppression is aligned. The normalized cross-correlation of the suppressed and
     baseline PCM at lag 0 is ≥ 0.9 and greater than at lag 2047: no initial delay
     is added.
   - `previewSeconds` at the timeline's own rate equals
     `Int(Double(total) / rate + 0.5)`. `clockText(125) == "2:05"` and
     `clockText(59) == "0:59"`.

# Acceptance predicate

Both staged songs go through the production `WavExport` (no check-local renderer or
header) and produce:
- the fork's duration law, RIFF header, fade, suppression pre-roll/flush and refusals;
- cancel and failure cleanup.

The midiexport ledger cites executed message-anchored predicates of that owner.

Implementer runs, under the build lock:
```sh
deno task build:checks
deno task checks --filter exportcheck-loop --verbose
deno task checks --filter exportcheck-tail --verbose
deno task proof check --executed
deno task proof check --strict-mappings
deno task proof sites src/checks/midi/proof.tst_midiexport.txt --status PARTIAL
```

Coverage:
- The two entries cover a loop song and a tail song: the law, the header, PCM,
  suppression, cancel, refusals and open failure.
- `--executed`/`--strict-mappings` prove every MATCHED row cites an executed message
  anchor.
- The `sites` query must list only A001/A002.

Gaps:
- A mid-write I/O failure and a close failure cannot be synthesized; the code path
  is reviewed, not executed.
- Physical audio output is excluded.

# Task-specific constraints

- One owner. `ExportChecks.swift` keeps no RIFF writer, gain law or PCM conversion.
- The render never uses `AudioRenderEngine` instances, `NativeAudio` or the live
  device.
- No new C/C++ and no C ABI entry.
- `wavexport.{h,cpp}` stay until task 223.
- Do not touch retained `proof.tst_nativeboundaries.txt` A015/A016. They stay under
  the standing native-boundary exclusion.
- The typed throws follow `swift-typed-throws`. No force unwraps, no `try?` on the
  write path.
