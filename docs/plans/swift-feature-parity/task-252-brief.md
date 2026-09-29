# Task 252 brief — Sample Studio audition strip on the engine-true audition owner

# Context

Spec.md: reuse the existing sample-audition owner; preserve key choice, destination-voice
ADSR, live parameter/handle updates, one-shot repeat and dialog-local Space audition of the
rendered sample; one play/stop control (no A/B); on cancel/close/project change stop and
release buffers only after the callback no longer consumes them. The owner already exists:
`AudioAudition` (`src/swift/app/audio/AudioAudition.swift`) with its four-slot
publish/acknowledge `AudioSampleAudition`, reached in the app through
`NativeAudio.auditionSample(...)`/`auditionSampleOff()`. Fork behavior:
`SampleEditorDialog` strip 400–438, `toggleAudition` 982, `startAudition` 990–1022,
`stopAudition` 1024–1037, `republishAudition` 1039–1043, `auditionTick` 1045–1078 (33 ms).
The QML strip and Space routing mount in 253; this task delivers the Swift owner and its
engine-true PCM proof.

Surface: `SampleStudioAudition` (SA04).
Ledger spec and rows:
- `proof.editor.txt` editorAuditionStrip A085–A088 (setup rows per the P4 scaffolding rule;
  NATIVE A088 ported: no audio → Play disabled); spaceAudition A116 (hi-res decode), A117
  (engine initializes — same predicate shape as analysis A022), A121–A125 (idle silence,
  started PCM peak ≥ 0.01 and RMS ≥ 0.001, Play text changes, stop → ≤ 1e-7 after release,
  text restored) → MATCHED through `toggle()`; A118 (`nullBackendForced`) and A119
  (`AudioEngineTestAccess::parkDevice`) → RETIRED-REPRESENTATION ("C++ engine test-access
  harness; the Swift predicate renders an offline `AudioRenderEngine`").
- `proof.analysis.txt` A022–A035 (already MATCHED): add message-anchored S mappings (convert
  the S001 function anchor by adding an `expect` for "audition engine initializes" in
  `checkSampleAuditionSlots`), clear their strict-mapping debt, then delete the ledger (every
  row closed after 244/245).
Verify lanes: `samplecheck`, `swiftcore-playback` (AudioAuditionChecks).
Blocked rows left untouched: spaceAudition A120, A126–A130 (focus/Space routing on the
mounted dialog; 253 edits them citing this task's PCM S entries).

# Exact write set

- `src/swift/app/samplestudio/SampleStudioAudition.swift` — NEW `@QtBridgeable` owner +
  `SampleAuditionOutput` protocol + `extension NativeAudio: SampleAuditionOutput {}`.
- `src/swift/app/CMakeLists.txt` — add the file (hot).
- `tools/qtbridge_surface_baseline.json` — via `deno task bridge:baseline`.
- `src/checks/samplecheck/AuditionStripChecks.swift` — NEW `runAuditionStripChecks`
  (MainActor) with `extension AudioRenderEngine: SampleAuditionOutput` forwarding to
  `audition.publishSample`/`sampleOff`.
- `src/checks/audio/AudioAuditionChecks.swift` — one added `expect` (engine initializes)
  inside `checkSampleAuditionSlots`; nothing else moves.
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledgers `proof.editor.txt` (rows above; this task's proof edit runs only after 251's
  editor-ledger commit — single writer per ledger), `proof.analysis.txt` (repair + delete).

# Prerequisites

249 (presenter `processed`, observers, `source`, marker gesture API), 245 (analysis ledger
rows closed). Code runs in parallel with 250/251; only the editor-ledger edit waits for 251.

# Interface contract

- `public protocol SampleAuditionOutput: AnyObject { func auditionSample(samples: [Int8],
  frequency: UInt32, loopStart: UInt32, looped: Bool, key: UInt8, adsr: AudioADSR, toneKey:
  UInt8) -> Bool; func auditionSampleOff() }`.
- `@QtBridgeable @MainActor public final class SampleStudioAudition`:
  - `@QtIgnored init(presenter: SampleStudioPresenter, output: SampleAuditionOutput?,
    destinationAdsr: VoiceListAdsr?)`; `@QtIgnored var onPlayhead: ((Int?) -> Void)?` (253
    wires it to `SampleWaveformModel.setPlayhead(sourceFrame:)`).
  - Tracked: `available` (output != nil), `playing`, `playText` ("Play"/"Stop"),
    `playToolTip` (fork text, or "Audio is unavailable." when unavailable), `auditionKey`
    (60), `auditionKeyText` ("C4 (60)" form), `hasDestinationAdsr`, `useDestinationAdsr`
    (initially `hasDestinationAdsr`).
  - QML-callable: `toggle()` (fork `toggleAudition`; no-op when unavailable or the render is
    empty), `stop()`, `setAuditionKeyText(_:)` (fork `parseMidiKey`; restarts a sounding
    audition), `setUseDestinationAdsr(_:)` (restarts a sounding audition), `tick()` (33 ms
    driver from QML: measures elapsed time with `ContinuousClock`, calls `advance`).
  - `@QtIgnored func advance(bySeconds: Double)` — fork `auditionTick`: retry a failed publish;
    one-shot end → 0.5 s gap then republish; looped playhead wraps inside the loop; playhead
    mapped back to source frames and reported through `onPlayhead`; nil when stopped.
  - Publication: `processed.s8`, `freq`, `loopStart`, looped only when the render loops,
    `key = auditionKey`, `adsr` = destination ADSR when used else `AudioADSR()` (fork
    `AuditionSlots::Adsr{}` = 255/0/255/165), `toneKey` 60. A looped audition republishes on
    every render change (live handle/param updates); a one-shot keeps its current bytes until
    it repeats.
  - `@QtIgnored func close()` — stops (`auditionSampleOff`) and detaches; called by 253 on
    accept, cancel, window close and project change. Buffer release stays with
    `AudioSampleAudition`'s acknowledged-slot retirement (no new lifetime code).

# Implementation steps

1. Owner + protocol + `NativeAudio` conformance.
2. `AuditionStripChecks.swift`: presenter + an `AudioRenderEngine`
   (`AudioControllerCheckFixture` construction pattern) as output; unavailable → disabled +
   tooltip; toggle → rendered PCM bounds; stop → silence after 2 s release; key/ADSR change
   restarts; loop-marker drag republishes (bytes differ); one-shot repeats after the gap via
   `advance`; playhead inside the loop; `close()` silences.
3. `AudioAuditionChecks.swift` expect; `deno task bridge:baseline`; ledger edits; delete
   `proof.analysis.txt`.

# Acceptance predicate

The strip auditions the exact rendered bytes through the real audition slots, obeys key and
destination ADSR, keeps a looped audition current with edits, repeats one-shots, moves the
playhead, and stops to digital silence on stop/close; the audition-primitive rows carry
message-anchored evidence.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-playback --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

Gap: physical device output is excluded (null backend); Space/focus routing is 253.

# Task-specific constraints

No second audition owner, no A/B selector, no new threading: publication goes through the
existing slot protocol. `AudioAuditionChecks.swift` gains one assertion only (its other
anchors must stay byte-stable).
