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
2. **One pending-source transaction.** Both the existing file-picker route and the new
   pane Load route stage bytes in a `PendingSource`; `sourcePath`/`sourceBytes`/
   `leftOnly`/`selectedZone` are committed only after decode (and, where applicable,
   stereo/zone acceptance). A rejected or corrupt load leaves the prior document,
   provenance inputs, name and undo history untouched.
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
3. **Stereo phase-cancellation through pane Load** — task 3 creates a real
  phase-cancelling PCM fixture and asserts both cancellation preserving the old
  edit and left-channel acceptance committing the replacement.
4. **Symlink-directory exclusion** — the unit check creates a real symlink when
  the host permits and asserts exclusion; on hosts where symlink creation is
  denied the row is skipped (named platform limitation).
5. **Native folder-picker dialog UX** — lane tests inject FolderDialog state; real
  dialog interaction is native smoke.
6. **Cancellation semantics** (contracts, not gaps): canceling a replacement
  (SF2 zone picker, stereo prompt) leaves the existing editor, document,
  provenance and undo history untouched; canceling the blank-studio chooser (menu
  route) leaves the browsable blank studio open. Source provenance commits only
  at the single `open(_:)` commit point.

## Verification gates (exact; controller-run)

- Swift suites: `uv run --no-sync dev checks --filter samplecheck-editor` (tasks
  1+2 checks live in `runSampleEditorChecks`) plus `samplecheck-storage` for the
  project sample/provenance storage regression sweep. `checks --filter swiftcore`
  is not a proven selector for these suites and is not used.
- Bridge: `uv run --no-sync dev checks:bridge` checks all new legal surface
  declarations. Observed zero baselined findings; retain the existing baseline.
- Shell: `uv run --no-sync dev checks:shell --filter shell-sample-studio-library`
  (new lane), the `shell-sample-studio` substring group (all five studio lanes),
  and the exact text-contrast gate
  `uv run --no-sync dev checks:shell --filter shell-text-contrast`, plus a
  populated-library row audit across theme roles (not just the empty pane).
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
