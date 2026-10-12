# Plan: Port the Sample Library pane into the Swift/QML Sample Studio

Worktree: `.worktrees/swift-sample-library` (branch `feature/swift-sample-library`, base
`834642b5`). The historical C++ `SampleLibraryPanel` (read via `git show
897afc77:src/ui/soundbrowser/samplelibrarypanel.cpp`, its wiring in
`src/ui/sampleeditordialog.cpp`, and its contract in
`src/checks/samplecheck/library.cpp`) is the authoritative behavioral spec; `spec.md`
restates it and names every deliberate delta.

## What lands

A Swift-owned library pane (bookmark folders → subdirectory tree → flat audio-file
list) docked left of the existing Sample Studio editor, with single-click/Enter/Space
source preview, double-click/Load transactional document replacement that never
corrupts a failed prior document, remove-bookmark that never deletes files, and
owner-gated audition arbitration shared by the pane preview and the editor render.
The studio becomes openable blank ("empty editor can browse before loading").
No new module, no native code, no broad audio refactor; preferences, decoder, render
and audio-output machinery are reused as-is.

## Design decisions (settled here, not by implementers)

1. **Presenter stability over QML rebinding.** Library load replaces the source inside
   the *existing* `SampleStudioPresenter` (`replaceSource`) instead of swapping
   presenter/wave/player objects behind the once-mounted dialog. `editorRevision`
   stays as an observation hook; no proxy chains, no Loader recreation. A Swift-only
   `sourceRevision` (public `@QtIgnored`) is bumped before render-observer
   notification: `SampleWaveformModel` refresh detects the revision and rebuilds its
   peak pyramid / resets fit, drag, playhead and seam state once; `SampleLoopTools`
   detects the revision and clears pitch/candidates/status, then reanalyzes. Parameter
   edits keep the existing `renderRevision` path and never rebuild the pyramid.
2. **One source record, explicit transactions.** The picker and pane Load routes
   carry a `SourceRequest` containing the `SourceRecord` and its error destination.
   Only stereo/zone questions retain a pending request; successful decode passes
   the record explicitly to `applySource`. Initial construction uses `createEditor`.
   A rejected or corrupt load leaves the document, committed source record, name
   and undo history untouched.
3. **Audition arbitration, not guards.** A small `SampleAuditionArbiter`
   (historical `SoundBrowser` single-active-owner semantics: publish displaces,
   `stop(owner:)` no-ops for a displaced owner, failed publish leaves the lane
   released with no owner) is injected into `SampleStudioAudition` and used by the
   workflow for pane preview. `SampleStudioAudition.stop()` stops being an
   unconditional global off — the displaced-owner-close hazard is designed out.
4. **Preview render semantics pinned to history.** Pane preview = fresh
   `SampleDocument` with `defaultParams` and `loopOn = false` (the historical
   `SoundBrowser::auditionExternalFile` pipeline: default GBA-rate/normalization
   render of the raw source, `loopStart 0`, not looped, default ADSR, `toneKey` =
   clamped `unityNote`, key = the editor's audition key). It is **not** the editor's
   current edited render.
5. **Pane Load shares the picker's decode pipeline**, including the existing stereo
   phase-cancellation prompt (current-app convention; historical library load mixed
   silently — delta named in spec.md). SF2 never appears in the pane list; the
   "Open File…" button keeps the existing picker + SF2 zone + stereo flows verbatim.
6. **Menu import opens the studio blank, then the picker** (`requestImport` probe
   gate unchanged). Existing lane tests keep their observable sequence (picker
   visible after the menu click); a blank browsable studio is new surface, not a
   rewrite of the menu route.
7. **Preferences list API widened, not duplicated**: `PreferencesStore.strings(_:)` /
   `setStrings(_:_:)` become `public` for `sampleLibraryFolders`. No JSON-string
   encoding, no second store.
8. **Synchronous directory listing** (FileManager on the main actor). The historical
   "Listing audio files…" state was a `QFileSystemModel` async-fetch artifact;
   dropped (delta named). Symlinked directories stay excluded; listing stays flat
   files-only, hidden entries excluded, case-insensitive 6-extension filter.

## Task table

| # | Task | Route / seat | Justification (triage signals) |
|---|------|--------------|--------------------------------|
| 1 | Swift library pane model + preferences widening + `PorydawQmlTypes` registration + `LibraryModelChecks` | SDD-track · `sdd-implementer` | New bridged model with a state machine and persistence contract; judgment work, several edge cases |
| 2 | Studio lifecycle: presenter `replaceSource`/`hasSource`/`sourceRevision`, waveform + loop-tools invalidation, audition arbiter, workflow transaction + preview wiring + unit checks | SDD-track · `sdd-implementer` | Ownership/lifecycle surgery across six Swift files; correctness-critical arbitration; not mechanical |
| 3 | QML pane + dialog layout + `SampleStudioHost` parenting (only if required) + shell probe/entries/new lane + user docs | SDD-track · `sdd-implementer` | New QML surface with pointer/keyboard contracts, new lane entry, fixture probes; judgment work |
| 4 | Bounded background preview/load preparation, cancellation, prepared-document installation and constructor migration | SDD-track · `sdd-implementer` | One source transaction across DSP/document/workflow/presenter; over-cap write set is cohesive, check migrations mechanical |
| 5 | Background pitch lifecycle, reusable Double YIN windows and deterministic existing-check waits | SDD-track · `sdd-implementer` | Independent analysis owner, numerical invariants and cancellation/source-revision races |

Disjoint ownership: task 1 owns the model, preferences widening, `PorydawQmlTypes`
registration and `LibraryModelChecks`; task 2 owns the six lifecycle Swift files and
`StudioLifecycleChecks`; task 3 owns QML, dialog, Host (if parenting proves
required), shell probe/entries, the new lane and the manual. Controller owns all
mechanical registration: `src/swift/app/CMakeLists.txt`,
`src/checks/CMakeLists.txt`, root `CMakeLists.txt`, `SampleChecks.swift` runner
additions and baseline files. Frozen spec interfaces let all three start
concurrently; gates run against the settled union.

## Global Constraints (read once; briefs carry deltas only)

- **Scope**: all edits inside this worktree only. No commits by implementers (the
  execution loop owns staging/checkpoints). No source changes outside a brief's Exact
  write set. Main checkout stays untouched.
- **Gates**: implementers run **no** build/test/lint/format/baseline commands. The
  controller owns every command recorded in this plan. Read-only inspection (reads,
  greps, `git show`) is always allowed.
- **Verification reuse**: implementers reuse the commands recorded in each brief's
  Acceptance predicate / Controller verification without re-discovering. If scope
  changes or a command proves stale, report the mismatch and the revised verification;
  never silently narrow.
- **Language/framework**: Swift 6 strict concurrency, `rule://swift-standards`
  (access control, `final`, `guard let`, domain errors, no test sleeps). QML follows
  the repo conventions: versionless imports, `required property` delegates,
  `model.X` only inside `QListModel`-backed delegates, `Connections` function syntax.
- **QtBridge**: follow `rule://qtbridge-surface` and
  `docs/old/qtbridge-surface/spec.md`. Bridged declarations live in class bodies (not
  extensions); QML-facing state public; unsupported stored types need `@QtTracked`;
  `@QtSignal` params only settable primitives/string lists. The bridge guard
  (`uv run --no-sync dev checks:bridge`) and any baseline rewrite
  (`bridge:baseline`) are controller-run.
- **Audio**: no new C/C++, no audio-thread changes, no second dispatcher. All pane
  audio goes through the existing `NativeAudio` output and the arbiter introduced in
  task 2. Nothing decodes or publishes from an audio callback.
- **UI**: geometry derives from `applicationSession.baseFontPx` (`dialog.unit`);
  no hard-coded pixel constants. Text colors come from the `GridPalette`
  (`dialog.colors`) pairs per `rule://text-contrast`. Space/Enter handling honors the
  AGENTS keyboard priority: the pane file list is an explicit audition surface (it
  consumes plain Space/Enter itself, before the dialog-wide Space toggle, matching
  the historical `sampleLibraryFiles` event-filter exemption).
- **Files**: one concept per file under `src/swift/app/samplestudio/`; no new module;
  `internal` by default, `public` only for cross-module or QML-facing needs.
- **Proof ledgers are retired** (verified: no `src/checks/**/proof.*.txt` exists and
  there is no automated proof command). Do not create ledger files, do not cite a
  proof command; `cppID` scoping strings in check reports are labels only.
- **Preserved flows**: existing SF2 zone import, stereo prompt, commit/collision,
  provenance reopen/fallback, undo/redo, voice-slot destination ADSR, and current
  studio behavior assertions keep passing. Migrate only incidental picker
  mechanics where required by correct native dialog parenting.
- **Docs**: user-facing surface change updates `docsrc/manual/sample-studio.md`
  (owned by task 3).

## Concurrency and checkpoints

- The three implementation units are disjoint (see Task table); no shared writes
  among implementers. The controller owns every append-only CMake edit, every
  `SampleChecks.swift` runner addition and every baseline file.
- Task 3 consumes task 1's model contract and task 2's workflow contract; it starts
  after both interfaces land (implementations may still be in review).
- Checkpoint milestones: (M1) after tasks 1–2 are accepted; (M2) final handoff
  after task 3 review, any justified baseline changes and native smoke.
  No per-task commit requirements.

## Coverage gaps (named; no silent narrowing)

1. **Audible preview output** — the existing real `AudioRenderEngine` PCM harness
  makes audible PCM and owner isolation deterministic unit checks (task 2 pins
  peak/RMS audibility and displaced-owner silence there); final audibility is
  additionally covered by controller native smoke with live audio.
2. **Engine slot exhaustion (Busy) for pane preview** — unit checks cover arbiter
  Busy semantics with a spy output; real 4-slot exhaustion/retry timing is not
  reachable in the null-backend lane. Native smoke only. Busy retry stays editor
  only; the pane surfaces the message with no retry.
3. **Pane transaction and cancellation UI** — the dedicated pane journey was
  removed at the user's request to keep added test execution below three seconds.
  Retained Swift checks do not prove QML prompt routing; use targeted smoke.
4. **Symlink-directory exclusion** — the unit check creates a real symlink when
  the host permits and asserts exclusion; on hosts where symlink creation is
  denied the row is skipped (named platform limitation).
5. **Native folder-picker dialog UX** — lane tests inject FolderDialog state; real
  dialog interaction is native smoke.
6. **Cancellation semantics** (contracts, not gaps): canceling a replacement
  (SF2 zone picker, stereo prompt) leaves the existing editor, document,
  provenance and undo history untouched; canceling the blank-studio chooser (menu
  route) leaves the browsable blank studio open. Replacement provenance commits
  only when `applySource` installs the complete source record.

## Verification gates (exact; controller-run)

- Swift suites: `uv run --no-sync dev checks --filter samplecheck-editor` (tasks
  1+2 checks live in `runSampleEditorChecks`) plus `samplecheck-storage` for the
  project sample/provenance storage regression sweep. `checks --filter swiftcore`
  is not a proven selector for these suites and is not used.
- Bridge: `uv run --no-sync dev checks:bridge` checks all new legal surface
  declarations. Observed zero baselined findings; retain the existing baseline.
- Shell: `uv run --no-sync dev checks:shell --filter shell-sample-studio` runs
  the four existing studio lanes. The populated-library row audit across theme
  roles remains in `uv run --no-sync dev checks:shell --filter shell-text-contrast`.
- Added-check runtime budget: below three seconds, excluding compilation. The
  three retained Swift runners measured 1.44 seconds total in the debug build on
  the development Mac. The dedicated library UI lane and its exclusive fixture
  helpers are retired; do not recreate them as required checks.
- Native smoke is controller-run against the real app with live audio and
  screenshot capture where available — mandatory, not optional. Honest blockers
  are reported; no keyboard observation is claimed without tooling.

## Historical-parity audit trail

Behavioral parity was audited against `git show 897afc77:` of
`src/ui/soundbrowser/samplelibrarypanel.{h,cpp}`,
`src/ui/sampleeditordialog.cpp` (`installLibraryPanel`, `loadLibrarySample`,
`previewLibrarySample`, `startAudition`/`stopAudition`, `done`), and
`src/checks/samplecheck/library.cpp` (`libraryFolders`, `librarySourceLoad`,
`libraryPreviewIsolation`, `librarySaveAsNew` — the last is adjacent and excluded,
see spec.md Non-goals). Spec.md carries the full contract.

## Allocation and numeric-loop repair

`SampleImport` scans clipping through a borrowed `Span<Float>`. `SampleRender`
uses borrowed spans for DC mean and mutable spans for full-buffer DC and gain
updates. These retain the original iteration, conversion, threshold and
arithmetic order. The sinc resampler hoists identical-order phase constants and
uses `Double.magnitude` rather than generic `abs` in its tap loop.

The whole Debug sample-editor harness's millionth intercepted allocation was
`malloc(40)` from the generic Array collection read witness through
`IndexingIterator.next` into `SampleRender.render`. Main-thread allocator-call
counts for the same harness, including initialization and existing assertions:

| Measurement | Before span scans | After span scans |
|---|---:|---:|
| Successful intercepted allocation calls | 5,570,154 | 3,816,395 |
| Requested bytes | 304,633,220 | 266,047,984 |

The remaining millionth call belongs to an existing audition-check
`allSatisfy` assertion, not the production sample scan. Counts are requested
allocations, not rounded heap sizes, and are not per-click measurements.

CLI `xctrace` Time Profiler captures of the same Debug harness observed 4,517 ms
weighted CPU before and 4,129 ms after all three source changes; the sinc
resampler's inclusive weight was 2,726 ms and 2,454 ms respectively. These are
single-run sampled observations, not a latency guarantee or Release comparison.

`samplecheck-processing`, `samplecheck-render`, and `samplecheck-editor` passed
together after the changes. No checks were added. The scoped
`thermo-nuclear-reviewer` audit passed with no blockers; it verified unchanged
arithmetic ordering, Float clipping thresholds and borrow scopes.

A native AX-observed editor load of a local 8.32-second mono WAV (366,932 frames,
44.1 kHz) installed the source in the rebuilt Debug app. Its CLI Time Profiler
capture recorded 2,988 ms weighted main-thread CPU, including 1,531 ms in YIN
pitch detection and 1,321 ms in sinc resampling. The allocator binary accounted
for 2 ms. The remaining delay in this run is numeric-loop cost, not allocation
time; Debug bounds checks and conversions are prominent in the stacks.

## Asynchronous preparation milestone

Tasks 4–5 execute from checkpoint `0aff945ace0cdb659dd8379095c78cd9b3d29535`.
Their write sets are disjoint and their shared presenter/cancel interfaces are
frozen in the briefs. Controller owns temporary CPU/race instrumentation,
registration if a new owned Swift file needs enrollment, documentation, shared
verification, and review packages. Commit the accepted union after both tasks
and the final thermo-nuclear audit pass.

The approved latency contract supplements the existing spec: UI selection
returns without waiting for render or pitch DSP; at most one preparation worker
and one pitch worker run, each with only its newest pending request. Superseded
work cooperatively stops. Stop, close and source/session replacement invalidate
late results. Source/provenance/history install atomically after successful
current preparation; failed or stale jobs leave the prior editor intact.
Pitch suggestions arrive asynchronously and never automatically change the key.
Pitch-dependent explicit actions defer against the same source/parameter state.
Prepared source installation retains its render cache. Preview remains the
historical default GBA render with looping disabled; reuse requires matching
immutable source identity and exact parameters, never path alone.

Numerical coverage, thresholds, arithmetic order and filter quality stay
unchanged. All QObject/QML/audio publication stays on the main actor; worker
inputs/results are immutable Sendable values. No new permanent integration
suite. The original three added local checks must remain below three seconds
combined. The controller repeats the temporary real-input CPU harness, exercises
latest-request-wins/stop/close behavior, then removes the harness before handoff.

### Measured outcome

Temporary production-slice harness: the same local mono WAV, 366,932 frames at
44.1 kHz. CPU figures below are medians of three stage calls; replacement
measures main-actor installation plus live waveform/loop-tools observers, not
the separately scheduled worker DSP. Source preparation still costs real CPU.

| CPU stage | Checkpoint Debug ms | Current Debug ms | Checkpoint Release ms | Current Release ms |
|---|---:|---:|---:|---:|
| Render preparation | 1365.871 | 1325.601 | 108.235 | 109.108 |
| YIN detection | 1548.480 | 1413.497 | 131.549 | 103.234 |
| Source installation and observers | 2931.694 | 6.708 | 239.917 | 0.258 |

The actual workflow's first load dispatch returned in 0.043 ms Debug /
0.025 ms Release. The main actor processed a turn before the source installed.
These are dispatch timings, not whole-click completion times. Render quality,
windows and pitch arithmetic are unchanged; exact checkpoint comparisons passed
on the real input, eight rate/frequency tone cases and five noise/boundary lengths.

The temporary real-session/native-audio smoke passed latest-only load/preview,
failed-load preservation, Stop during preparation and Close without late
mutation. Pitch smoke passed immediate old-hint invalidation, no automatic key
adoption, explicit deferred adoption against latest C, and terminal cancellation.
The original three added local checks totaled 1.365 s Debug / 0.177 s Release.
No permanent integration checks were added.

Time Profiler capture `/tmp/porydaw-sample-async-release.trace` observed YIN
and sinc resampling on worker threads (639 ms / 113 ms inclusive across the
whole harness). Deliberate direct DSP benchmark calls also run on its main
thread; those samples are not production UI blocking.

Thermo review prompted a completion-reentrancy repro: A's callback submits B
then C, and stale B must not clear C's task ownership. The temporary repro
failed before and passed after requiring an idle worker in `startPending`.
Canonical reopen policy remains in `SampleReopen`; returned source bytes avoid
duplicating policy or rereading provenance data. The temporary harness,
dispatcher hook, fixture enrollment, trace wrapper and copied binary were removed.

Final clean-tree gates after removing instrumentation and its observation-only
hooks: Task 4 spec/standards PASS, Task 5 spec/standards PASS, final independent
thermo-nuclear PASS. Debug covering lanes (processing, storage, render, editor,
analysis): 5/5 passed in 8.52 s. Release adds the six original pitch rows:
11/11 passed in 3.06 s. `checks:bridge`: zero baselined findings.
`format --check`: passed; refreshed Swift index: 23/23 targets.
The first cleanup index refresh referenced the deleted temporary source through
stale CMake metadata; the normal Debug build regenerated it before the successful
refresh. No temporary source or benchmark branch remains.
