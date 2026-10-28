# Task 2 — Studio lifecycle: presenter replacement, audition arbitration, workflow transaction

## Context

Second task of the sample-library port. Makes the Sample Studio safely replaceable
while open (stable presenter via `replaceSource`), opens it blank, introduces
owner-gated audition arbitration for the shared sample lane, and wires the pane
model produced by task 1 into `SampleStudioWorkflow` (preview, transactional load,
open-file). Consumer: task 3 mounts the QML pane and drives these workflow slots;
its shell lane tests exercise the wiring end-to-end. The interface contracts this
task consumes are `spec.md → SampleLibraryModel` (task 1, frozen) and produces
`spec.md → SampleAuditionArbiter / SampleStudioAudition / SampleStudioPresenter /
SampleStudioWorkflow`.

## Exact write set — bounded parallel sub-units (≤5 explicit paths each)

- **Task 2a — arbitration + audition** (4 paths):
  - Create `src/swift/app/samplestudio/SampleAuditionArbiter.swift`
  - Edit `src/swift/app/samplestudio/SampleStudioAudition.swift`
  - Edit `src/checks/samplecheck/AuditionStripChecks.swift` (migrate the
    `SampleStudioAudition` init callers at lines 28, 44, 101 to the lane
    signature; no compatibility shim)
  - Create `src/checks/samplecheck/StudioLifecycleChecks.swift` (arbiter +
    real-PCM predicates only, via the existing synchronous real
    `AudioRenderEngine` harness: audible peak/RMS PCM, owner isolation,
    displaced-owner silence)
- **Task 2b — replacement + invalidation** (4 paths):
  - Edit `src/swift/app/samplestudio/SampleStudioPresenter.swift`
    (`replaceSource`/`hasSource`/`sourceRevision`)
  - Edit `src/swift/app/samplestudio/SampleWaveformModel.swift`
    (revision-gated pyramid rebuild + fit/drag/playhead/seam reset)
  - Edit `src/swift/app/samplestudio/SampleLoopTools.swift`
    (revision-gated pitch/candidates/status clear + reanalyze)
  - Create `src/checks/samplecheck/SourceReplacementChecks.swift`
    (source geometry, reset state, fresh pitch/loop suggestions, blank commit gate).
- **Task 2c — workflow only** (1 path):
  - Edit `src/swift/app/samplestudio/SampleStudioWorkflow.swift`
    (consumes the frozen task-1 and task-2a/2b interfaces; its transaction,
    no-source-open, SF2/stereo cancellation, provenance and locked-edit behavior
    is covered by task 3's production shell lanes)

Controller-owned mechanical additions (NOT in any sub-unit): the
`src/swift/app/CMakeLists.txt` source lines, the `src/checks/CMakeLists.txt`
lane lines, the `SampleChecks.swift` runner calls, and all baseline files.
`sourceRevision` is a Swift-only internal `private(set)` property — never a QML
baseline addition.

## Prerequisites

Task 1's interface only (`SampleLibraryModel` declarations; no implementation
detail). The lane builds only when both tasks' CMake lines exist — expected; the
controller's verification run happens after both.

## Interface contract

Exact declarations: `spec.md → SampleAuditionArbiter`, `SampleStudioAudition`,
`SampleStudioPresenter`, `SampleStudioWorkflow`, plus behavioral contract §20–§28.
Declarations preserved verbatim (existing callers/QML depend on them): every
existing public member of the touched Swift files keeps its name, signature and
observable behavior except where spec.md names a change: `SampleStudioAudition.init`
signature (task 2a migrates all construction sites, including the three in
`AuditionStripChecks` — no shim), `SampleStudioAudition.stop()` no longer
unconditionally clears the global lane (that is the designed fix, not a
regression), `SampleStudioPresenter` gains `hasSource`/`sourceRevision`/
`replaceSource` plus the two observer-file edits, and
`SampleStudioWorkflow.chooseSource/answerStereoPrompt/acceptZone/close` gain the
pending-transaction staging internally while their QML-facing behavior is
unchanged. `editorRevision`, `pickerRequested`, `pickerFolder`, alert/stereo/zone
published state, `editor()/loopTools()/waveform()/audition()/zonePicker()/
editorReleased()/zonePickerReleased()` slots: unchanged names and semantics.
`sourceRevision` is internal `private(set)` (Swift-only, task 2b) — never a QML
baseline addition.

Pinned behaviors:

- **Blank open** (`requestImport` post-probe, when `!editorOpen`): construct the
  presenter with `ImportedSample()` (empty defaults), `hasSource == false`
  (`canCommit == false` — never true for a zero-frame source), same validator
  closure; wave/tools/player/lane as a normal open; pane `setLoadedPath("")`;
  then the existing `pickerFolder`/`pickerRequested` lines run unchanged so the
  picker still appears over the blank studio (existing lane tests' observable
  sequence is preserved).
- **Source transaction** (task 2c): picker/pane requests carry a `SourceRecord`
  and error destination together in `SourceRequest`. Only stereo/zone acceptance
  retains a pending request. Stereo answers update the record's `leftOnly` before
  re-decode; `acceptZone` sets its zone after extraction succeeds.
  `applySource(sample, source:)` installs the complete committed record, calls
  `presenter.replaceSource`, keeps wave/tools/player instances, and bumps
  `editorRevision`; destination ADSR stays bound to the studio session.
  Initial blank/reopened studios use `createEditor`, with a `nil`/resolved record
  respectively. Neither constructor nor replacement consumes ambient pending state.
- **Async session guard** (task 2c): async source/probe continuations validate
  task identity (session/generation) at each await; results racing `close()` are
  dropped and never reopen the studio.
- **Source observer checks are consumer behavior** (task 2b): assert rendered
  waveform geometry, zoom reset, new pitch and newly valid loop bounds after
  same-length different-content replacement. Inspect single-rebuild behavior
  structurally; do not add implementation counters solely for tests.
- **Load failure surface**: errors from a pane-initiated load go to
  `library.showMessage(...)` (strings per spec §20); picker-initiated decode
  failures keep today's `showAlert` route. Implementation shape: thread an error
  surface (e.g. a private enum) through the decode path rather than duplicating it.
- **Preview** per spec §28 exactly: `player?.stop()` first; availability message
  `Audio is unavailable.`; read failure `Cannot read <path>.`; decode failure
  `"<lastPathComponent>": <error.message>` (today's alert format); empty render
  `"<fileName>" renders no audio.`; publish `owner: self` (the workflow), key from
  `player.auditionKey`, `toneKey = UInt8(clamping: rendered.unityNote)`, default
  `AudioADSR()`, `loopStart 0`, `looped false`; success →
  `library.setPreviewingPath(path)`; `false` → `The audition engine is busy.`.
  No stereo prompt on preview (default leftChannelOnly: false decode).
- **Arbiter**: `publish` clears+releases the active owner (weak identity) and calls
  `output.auditionSampleOff()` before publishing; on `output.auditionSample(...) ==
  false` the lane stays released with no owner and `publish` returns `false`;
  `stop(owner:)` compares identity and no-ops otherwise. The lane is created lazily
  with `session.audio` and kept for the workflow's lifetime; `SampleStudioAudition`
  receives it in `init` and never touches `NativeAudio` directly.
- **Close**: `close()` additionally `stopLibraryPreview()` (owner-gated) and resets
  pane ephemeral state (`showMessage("")`, `setLoadedPath("")`,
  `setPreviewingPath("")`, `clearFileSelection()`); bookmark list untouched.
- **Mutual exclusion**: `player.onStarted` (wired at player creation in `open`)
  calls `library.setPreviewingPath("")`; `previewLibrarySample` calls
  `player?.stop()` first (which resets the editor play state/label). Editor render
  Busy-retry semantics (`republishPending` tick) are unchanged.
- `loadLibrarySample` guards: `committing`, `stereoPromptOpen`, `zonePickerOpen`
  (no-ops otherwise), matching `requestImport`'s guard set. Pane interactions are
  additionally modality-blocked in QML (task 3) — the guards are the contract.

## Implementation steps

1. (2a) `SampleAuditionArbiter` first (no dependencies); one concept, Swift-only,
   `@MainActor final class`, weak `activeOwner`.
2. (2a) `SampleStudioAudition`: swap `output` for `lane`, route `start/stop/close`
   through the arbiter with `owner: self`, add `onStarted`. Keep every published
   property and the tick/advance/playhead logic untouched. Migrate all
   construction sites (workflow + `AuditionStripChecks` lines 28, 44, 101).
3. (2b) `SampleStudioPresenter`: extract the readout construction shared by `init`
   into a private reset helper; add `hasSource` (published,
   `source.frameCount > 0`) and gate `refreshName()`'s `canCommit` on it; add
   `replaceSource` per spec (history reset via fresh `SampleStudioHistory()`,
   `gestureBase = nil`, `sourceCents` recomputed, locked-name retention,
   `restoredParams` application after the document swap,
   `sourceRevision` bump before render-observer notification).
   `applyParamsExternal`/`commitParams`/undo/redo untouched.
4. (2b) `SampleWaveformModel`: `pyramid` becomes `var`; refresh detects
   `sourceRevision` and rebuilds the pyramid / resets fit, drag, playhead and
   seam state once. Parameter edits keep the `renderRevision` scene path and
   never rebuild the pyramid. `SampleLoopTools`: detect `sourceRevision`, clear
   pitch/candidates/status, then reanalyze.
5. (2c) `SampleStudioWorkflow`: introduce `SourceRecord`, `SourceRequest`,
   `pendingSource`, `committedSource`, `libraryPane`, `auditionLane`; migrate
   picker/pane loading and stereo/zone acceptance onto explicit requests.
   `requestEdit` passes its resolved record directly to `createEditor`;
   `requestImport` creates a blank editor; `applySource` owns replacement.
   Centralize source-staging eligibility in `canStageSource`; add
   `library()/requestOpenFile()/loadLibrarySample()/previewLibrarySample()/
   stopLibraryPreview()` and the `close()` additions; wire the four pane
   callbacks and `player.onStarted` at pane/player creation.
6. (2a) `StudioLifecycleChecks.swift` (`runStudioLifecycleChecks(_ report:)`,
   `cppID` labels `swiftcore/SampleAuditionArbiter::*`), `@testable`-free where
   public APIs suffice; arbiter checks use a private spy `SampleAuditionOutput`
   (records `auditionSample` arguments + `auditionSampleOff` calls;
   `auditionSample` programmable to return `false` for Busy) plus the existing
   synchronous real `AudioRenderEngine` harness (`AuditionStripChecks` idiom —
   `runSampleEditorChecks` is synchronous, so no `await NativeAudio.make()`).
   Assert at least:
   - Arbiter (spy output, direct construction): publish then publish-by-second-owner
     records `off` before the second publish; displaced `stop` is a no-op (no extra
     `off`); active `stop` offs once; Busy publish leaves no owner (a following
     displaced `stop` no-ops). Do not test argument forwarding.
   - Real PCM (synchronous `AudioRenderEngine` harness): sounding audition renders
     audible PCM (peak/RMS thresholds per the existing strip checks); a displaced
     owner's stop leaves the newer owner's audio sounding (owner isolation is a
     deterministic rendered observation, not a native-only gap).
7. (2b) `SourceReplacementChecks.swift` (`runSourceReplacementChecks(_ report:)`,
   `cppID` labels `swiftcore/SampleStudioPresenter::replaceSource*`,
   `swiftcore/SampleWaveformModel::sourceRevision*`,
   `swiftcore/SampleLoopTools::sourceRevision*`): `replaceSource` keeps a locked
   `setEditTarget` name and read-only state, resets undo (`canUndo == false`),
   refreshes `sourceFrameCount`/`sourceLine`/rate choices; unlocked name prefills
   from the new `suggestedName`; blank presenter has `hasSource == false`,
   `canCommit == false`, and a real `replaceSource` flips `hasSource` and enables
   commit for a valid name; zero-frame decode keeps `canCommit == false`;
   `restoredParams` survive the swap; a second `replaceSource` clears history
   again; different sources yield correct fresh waveform geometry and fit,
   pitch and loop suggestions; parameter edits preserve zoom. Workflow
   transactions, no-source-open, SF2/stereo cancellation, provenance and locked
   edits are covered by task 3's production shell lanes (including new checks
   where needed) — no phantom async invocation or unreachable source fields here.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded). Baseline: exact
`samplecheck-editor` passes (1/58 selected). No broad `swiftcore` regex is used
as fake coverage.

- `uv run --no-sync dev checks --filter samplecheck-editor`
  — runs `runSampleEditorChecks` (all three new check files wired by the
  controller). Covers: arbiter ownership matrix (§24), audible PCM + owner
  isolation via the real engine harness, presenter replacement + `sourceRevision`
  invalidation (§21–§23, R1), blank-studio gating (§23), plus no regression in
  existing samplecheck suites (`EditorPresenterChecks`, `AuditionStripChecks`,
  etc. depend on the edited files).
- `uv run --no-sync dev checks:bridge`
  — no new bridged types in this task (task 1 owns the pane types); new members on
  existing types must stay legal: `hasSource` is a supported-type tracked member,
  `sourceRevision` is internal and Swift-only, `onStarted` is `@QtIgnored`, and
  the `SampleStudioAudition` init change does not register. Guard must pass;
  update the baseline only for reviewed, intentional findings. The settled
  Task 1+2 gate passed against the unchanged baseline with zero findings.

Permanent checks assert consumer-visible behavior (rendered PCM, ownership
transitions, replacement outcomes); no duplicate exact-string implementation
tests. Runtime prerequisites: none beyond the worktree's existing sync state;
offscreen.

## Task-specific constraints

- Deltas on top of plan.md Global Constraints:
  - Do not add guards around `SampleStudioAudition.stop()` callers — the arbiter is
    the fix; every existing call site (`accept`, `close`, `toggle`) keeps calling
    `stop()`/`close()` and the owner gate makes displaced stops harmless.
  - Do not introduce a second dispatcher, timer, or notification chain for the
    preview label; the explicit `player.stop()` / `onStarted` calls are the whole
    mechanism (historical parity).
  - `voiceList` picker audition (`ApplicationSession+Audio.swift`) stays untouched;
    the studio dialog's `Qt.ApplicationModal` modality keeps it from interleaving
    (stated in spec.md §24 context — if a check reveals an interleaving path,
    report; do not widen the arbiter's scope).
  - No QML edits (task 3), no `SampleLibraryModel` edits (task 1); a needed fix in
    either is a report, not an edit.
  - `SampleStudioHistory` needs no edit: a fresh instance is the reset.
- Concurrency hazard owned here: `applySource` must not recreate the
  `SampleWaveformModel`/`SampleLoopTools` (QML holds them; they observe
  `sourceRevision` and invalidate once per revision).
- Keep the audition key shared: pane preview reads `player.auditionKey` (live field,
  not a copy at studio open).

## Controller verification

After the writer settles (controller-owned, in order):

1. Wire the controller-owned registration: `src/swift/app/CMakeLists.txt` source
   lines, `src/checks/CMakeLists.txt` lane lines, `SampleChecks.swift` runner calls.
2. `uv run --no-sync dev checks --filter samplecheck-editor` (covers tasks 1+2 together)
3. `uv run --no-sync dev checks:bridge`
4. `uv run --no-sync dev checks:shell --filter shell-sample-studio-voice` — the
   untouched voice lane proves the workflow's QML-facing behavior (picker, zone
   picker, edit reopen, commit) survived the internal refactor; QML pane lanes
   arrive in task 3.
5. `uv run --no-sync dev format --check --base 834642b5`
