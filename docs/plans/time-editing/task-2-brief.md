# Task 2: Make insertion selection-first

## Context

Task 1 supplies the command name. This is a new selection-first policy, not a behavior-preserving refactoring; it composes existing selection insertion and prompting without a new editing layer. Tasks 3 and 5 consume that policy; Task 4 exercises it through the window action.

## Exact write set

- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview.h`
- `src/checks/rollcheck/keyboard.cpp`

## Prerequisites

Task 1: public `void SongView::insertTime()`.

## Interface contract

`insertTime()` implements [selection-first insertion](plan.md#insert-time). Reuse SongView's `insertBlankTime()`, `resolveTimeSelectionScope()` and `openInsertTimePrompt()` in `rangeedit.cpp`; SongDocument remains the mutation/undo owner. The selection-only helper stays public until Task 5 completes its caller cutover.

## Implementation steps

1. Distinguish selection activity from scope validity before choosing insertion versus prompting. A rejected active scope terminates the command rather than falling through to whole-song prompting.
2. Update the public method contract without changing prompt arithmetic, stale-target rejection or document mutation algorithms.
3. Retarget `timelineInsertBlankTimeTracks` and `timelineInsertBlankTimeLanes` to the unified command; retain scope, cursor, selection and undo assertions and use an edit cursor different from the range start.
4. Add the invalid-active-scope case inside the existing track check: find a timeline-unused track U, select it through `view.selectTrack(U)`, then set a positive Tracks time span through the public selection model. Assert primary U, stored singleton scope, unused track and active span before invocation; prove no popup and unchanged bytes, revision, undo, cursor and selection. Restore fixture state between scenarios.

## Acceptance predicate

The unified entry preserves track/lane isolation and undo, rejects the constructible invalid active scope without a prompt, and retains existing no-selection prompt behavior. Named checks: `deno task verify --filter rollcheck --filter mainwindow-routing-input --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risks: activity is not scope validity, and the playhead must not override a selected anchor. Do not use an empty Lanes selection (it normalizes inactive), set only an unused mask while retaining a used primary track, or expose/call the private scope resolver from a check. Keep the policy stateless; do not extract a policy class or mirror selection state.
