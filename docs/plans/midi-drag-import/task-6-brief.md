# Task 6 — Drag/Modal Onboarding Regression

## Context

The permanent regressions exercise the actual Qt drag/drop and modal path through the shown `MainWindow` central widget. They protect Task 5's target identity, chooser policy, interlock handling, timing conversion, atomic commit, and failure behavior. Read [plan.md](plan.md) Global Constraints and [spec.md](spec.md).

## Exact write set

- New `src/checks/onboardcheck/drop.cpp`
- `src/checks/onboardcheck/onboardingtest.h`
- `src/checks/CMakeLists.txt`

## Prerequisites

Task 5.

## Interface contract

- Add `OnboardingTest::midiDropOwnership`, `midiDropAppend`, `midiDropNewSong`, and `midiDropRejections` slots in `onboardingtest.h`, implement them in `drop.cpp`, and register that source in the existing `onboardcheck` target.
- Drive public Qt input and visible modal controls only. Stable chooser `objectName`s from Task 5 are the permitted test seam. The existing onboardcheck catalogue description remains accurate because these are onboarding import scenarios.

## Implementation steps

1. Reuse declared checked-in fixtures for existing project/import scenarios. Construct the 17-note-track, 16-channel-only-before-note, and mismatched-division MIDI inputs deterministically with `SmfFile::writeFile` inside the harness-provided private scratch path; do not add undeclared fixture files or repository-path copying.
2. In `midiDropOwnership`, show the real `MainWindow`, deliver actual drag phases to native/empty and Quick song content, and observe one chooser; deliver to the tab bar and observe no chooser or mutation.
3. In `midiDropAppend`, prove capacity-bounded defaults, captured-target identity across an active-tab change, source order, one-command Undo/Redo, scaled earliest-note tick, active tab, selected imported track/note, reveal state, history index, revision, and publication.
4. In `midiDropNewSong`, prove New Song when no append target is viable, including balanced `m_dialogOps`/`updateOpenGate()` release before the wizard, and observe the existing player-budget warning plus resulting project/song state.
5. In `midiDropRejections`, distinguish pre-chooser rejection from modal pre-commit rejection. Cover multi-URL, non-local/non-MIDI, invalid/no-note, stale target, changed capacity, unexpected dialog depth, changed project-operation/load-save gate, and changed bank/history gate; observe error presentation, restored `m_dialogOps == 0`/open gate, unchanged project/document/history/revision/publication state, and unchanged source bytes.

## Acceptance predicate

`deno task verify --filter onboardcheck --verbose` passes while exercising the shown native/Quick window. The named slots fail on duplicate delivery, tab-bar ownership, wrong-target commit, incorrect rescaled tick/reveal, split history, missing player warning, incorrect chooser/error presentation, or any mutation on a rejected path.

## Task-specific constraints

- Declare every required fixture through the existing test-only registry/manifest mechanism; no ad-hoc repository path copying.
- Keep the test deterministic and bounded; no repeated GUI stress loops.
- Test observable behavior, not private chooser classes or event-filter implementation details.
