# MIDI Drag Import Integration Plan

## Status

Ready for implementation against `fork-main`. Source behavior is reconstructed from `feature/midi-drag-import` commit `059527ee`; the commit is not a merge or cherry-pick candidate because it is 606 commits behind and conflicts with the current ownership model. Thermo-nuclear plan audit: APPROVED after blocker resolution.

## Tasks

| Task | Route | Seat | Work |
|---|---|---|---|
| 1 | SDD-track | `sdd-implementer` | Add pure selected-track MIDI projection and focused import regressions. See [task-1-brief.md](task-1-brief.md). Judgment is required around SMF global-event ownership and stable ordering. |
| 2 | SDD-track | `qt-cpp-reviewer` | Add atomic imported-track append to `SongDocument`. See [task-2-brief.md](task-2-brief.md). This changes Qt model/history contracts, remapping, and publication. |
| 3 | Direct | Controller | Move the current MIDI/new-song workspace flow into its canonical translation unit. This is a reversible Move Function refactor with no behavior change. Inline contract below. |
| 4 | SDD-track | `qt-cpp-reviewer` | Extend `SongTab`'s existing input gate to publish URL drops from native and Quick content, with a focused producer regression. See [task-4-brief.md](task-4-brief.md). This touches Qt event ownership across a widget and embedded `QQuickWindow`. |
| 5 | SDD-track | `qt-cpp-reviewer` | Add workspace drop policy, chooser, and append/new-song orchestration. See [task-5-brief.md](task-5-brief.md). This joins UI lifetime, document mutation, and current tab state. |
| 6 | SDD-track | `qt-cpp-reviewer` | Add scenario-cohesive real drag/drop and modal onboarding regressions. See [task-6-brief.md](task-6-brief.md). This is a Qt input/lifetime harness, not a source-text test. |
| 7 | Direct | Controller | Replace the TODO-only MIDI import manual page after Tasks 5–6 pass. Inline contract below. |

### Task 3 — Direct contract

- **Target:** `src/ui/workspaceui_samples.cpp`; new `src/ui/workspaceui_midi.cpp`; root `CMakeLists.txt`.
- **Change:** Move the complete definitions of `WorkspaceUi::runNewSongWizard`, `WorkspaceUi::runMidiImport`, and `WorkspaceUi::submitCreateSong` without changing declarations, behavior, includes beyond ownership needs, or call sites. Register `workspaceui_midi.cpp` in the existing UI source list. Do not leave forwarding wrappers.
- **Acceptance:** `deno task build:app` compiles the moved definitions once and preserves the existing File-menu new-song and MIDI-import flows. Controller performs one existing File-menu MIDI-import smoke before Task 5 edits this file.

### Task 7 — Direct contract

- **Target:** `docsrc/manual/midi-import.md` only.
- **Change:** Replace the TODO text with the shipped behavior from [spec.md](spec.md): File-menu import, content-area drag acceptance, chooser modes/default, hardware-capacity selection bound, append timing conversion, current player-budget warning behavior, source-file immutability, and failure/no-mutation behavior. Do not document rejected source-branch architecture or implementation details.
- **Acceptance:** `git diff --check -- docsrc/manual/midi-import.md` passes; review confirms every statement matches [spec.md](spec.md), the settled behavior-to-proof matrix, and final File-menu/drop smoke.

## Global Constraints

- Reimplement against current `fork-main`; never merge or cherry-pick `059527ee`.
- Keep `MainWindow` unchanged. `WorkspaceUi` owns project/tab/dialog policy; `SongTab::InputGate` owns native/Quick input capture; `midiimport` owns pure SMF selection; `SongDocument` owns mutation/history/publication.
- Reuse `mapSmfEngineTracks` for projected/destination SMFs, `isTempoMeta` as one input to the stricter global-event classifier, `smfMetaIsMarker`, `SmfChannelPrefix`, checked `rescaleDivision`, `removeRedundantSetterEvents`, `EditOp::InsertTrack`, `SongEditCommand`, `TrackRemap`, stable note-ID minting, and current document publication. Source-chunk enumeration intentionally scans every chunk independently of the destination mapper's hardware cap. Do not add parallel history, event forwarding, focus, or capacity systems.
- Capacity means `track_limits::kHardwareCapacity - engineTrackCount()`. Do not gate editing by the player budget and do not add the old `NewSongWizard` minimum-track overload. Preserve current player-budget warnings.
- Use `layout::` font metrics for any chooser geometry, padding, hit targets, and strokes. No hard-coded widget pixels.
- Keep the chooser private to `workspaceui_midi.cpp`; no `Q_OBJECT`, public dialog type, QML `DropArea`, or feature-specific `MainWindow` surface.
- No new top-level `src/*check.cpp`. Harness additions belong under `src/checks/`.
- Tests assert observable projection, atomic document behavior, and real Qt input/modal behavior—not source text, signal wiring, or copied fields.
- Implementers reuse the exact commands recorded below and in their brief. Reassess only when scope changes or a command is stale/unavailable; report the mismatch and replacement instead of narrowing verification silently.
- Parallel implementers may inspect locally but must not run shared builds, formatters, or harnesses. The controller runs settled-tree commands and native smoke checks.
- Every build, check, or harness tool invocation has a maximum timeout of 180 seconds. Split verification more narrowly rather than raising it.

## Execution and Checkpoints

1. Run Tasks 1 and 3 in parallel; their write sets are disjoint.
2. Accept Task 1 and the Task 3 File-menu smoke, then checkpoint them together. This protects `import.cpp` before Task 4 and `workspaceui_midi.cpp` before Task 5 reuse.
3. Run Tasks 2 and 4 in parallel. Task 2 consumes Task 1's interface; Task 4 is source-independent but starts after the checkpoint because it re-edits `import.cpp`.
4. Accept and checkpoint Tasks 2 and 4 after their recorded harnesses pass.
5. Run Task 5 and its real app smoke, then Task 6 against the settled UI path.
6. Accept and checkpoint Tasks 5–6 together before Task 7 records shipped behavior.
7. Final checkpoint contains all remaining accepted work after the settled verification gate.

## Settled Verification Gate

Run from the integration worktree after all writers and reviewers settle. Cap each build/check invocation at 180 seconds:

- `deno task build:app` — compiles the production ownership cutover and new Qt drop path.
- `deno task verify --filter onboardcheck --verbose` — covers pure import projection, raw native/Quick URL delivery, chooser policy, commit paths, and rejection/interlock behavior.
- `deno task verify --filter editcheck --verbose` — covers atomic append, undo/redo, track remapping, checked rescale, and stable note identity.
- `deno task format --check src/core/midiimport.h src/core/midiimport.cpp src/core/songdocument.h src/core/songdocument.cpp src/ui/songtab.h src/ui/songtab.cpp src/ui/workspaceui.h src/ui/workspaceui.cpp src/ui/workspaceui_samples.cpp src/ui/workspaceui_midi.cpp src/checks/onboardcheck/import.cpp src/checks/onboardcheck/drop.cpp src/checks/onboardcheck/onboardingtest.h src/checks/editcheck/tst_songdocument_songtracks.cpp` — checks every planned C++ write target.
- `git diff --check -- CMakeLists.txt src/checks/CMakeLists.txt docsrc/manual/midi-import.md` — checks the non-formatter build/document targets for whitespace errors.

### Behavior-to-proof matrix

| Behavior | Permanent proof | Runtime proof |
|---|---|---|
| Every source note chunk is selectable beyond mapper capacity; channels and projection/global ordering are exact | `OnboardingTest::importAnalysis`, `OnboardingTest::importDedup` | Chooser shows a capacity-bounded prefix for a 17-track fixture |
| Append is preflighted and atomic across rescale, remap, note identity, publication, Undo, and Redo | `EditCheckTest::trackCreateDelete` | Valid mismatched-division Append; one Undo/Redo |
| Native and Quick content deliver one raw URL drop; tab bar does not | `OnboardingTest::importWizard`, `OnboardingTest::midiDropOwnership` | Quick-content chooser appears once; tab-bar chooser stays absent |
| Append uses the captured target, scales timing, and reveals the first imported note | `OnboardingTest::midiDropAppend` observes active tab, selected track/note/tick, history index, revision, and publication | Valid Quick-content Append |
| New Song keeps current wizard/player-budget policy | `OnboardingTest::midiDropNewSong` observes project/song state and warning presentation | Drop with no viable append target |
| Invalid inputs and entry/pre-commit interlock changes are no-ops with correct error/chooser behavior | `OnboardingTest::midiDropRejections` observes chooser presence/absence, project/document/history/revision/publication state, and source bytes | Tab-bar and stale-target spot checks |
| Existing File-menu MIDI import is unchanged by the Move Function refactor | Existing onboard import coverage plus controller smoke | Import a MIDI file from the File menu after all Task 5 edits |

Launch the actual app with a project open. First import a MIDI file from the File menu. Then drop one valid multi-track, mismatched-division MIDI file on Quick song content, choose Append, confirm one Undo removes the whole import, Redo restores it at the scaled tick, and the first imported note is visible. Drop on the tab bar and confirm no chooser opens. Repeat with no viable active song and confirm New Song is the only/default destination. These observations are the runtime proof for the final UI composition.

Any assertion or harness failure blocks handoff and must be resolved.

## Source Anchors

- Source behavior: commit `059527ee` (`Add MIDI drag-and-drop import`).
- Pure import owner: `src/core/midiimport.h`, `src/core/midiimport.cpp`.
- Document mutation owner: `src/core/songdocument.h`, `src/core/songdocument.cpp`.
- Quick/native input owner: `src/ui/songtab.h`, `src/ui/songtab.cpp`, especially `SongTab::InputGate`.
- Workspace composition and tab wiring: `src/ui/workspaceui.cpp`, `WorkspaceUi::wireTab`.
- Current MIDI/new-song flow: `src/ui/workspaceui_samples.cpp` before Task 3.
- Import regressions: `src/checks/onboardcheck/import.cpp` and the `onboardcheck` catalogue entry.
- Track-history regressions: `src/checks/editcheck/tst_songdocument_songtracks.cpp` and the `editcheck` catalogue entry.
