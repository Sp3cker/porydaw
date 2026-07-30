# Task 03 — Add revision-checked batch velocity editing

**Blocked by:** Reviewed and integrated Task 02.

**Runtime worktree:** `03-velocity-batch`

**Branch:** `task/editor-drawer/03-velocity-batch`

**Target slice:** Specification implementation slice 3.

**Suggested subject:** `Add revision-checked batch velocity editing`

## Start rule

Fast-forward this clean worktree to the accepted Task 02 integration SHA and
record it as `START_SHA`.
Before editing, read the root plan, full specification, repository
instructions, and this plan in full.

## Contract

Own the global document-revision rules, the velocity Preview/mutation/Undo
document seam, and **CORE-03**.

## What to deliver

- A monotonic `SongDocument` revision incremented exactly once for every
  successful mutation, load, Undo, and Redo before Task 01 remaps and general
  document-change notifications.
- No revision change for failures, no-ops, or view-only actions.
- One revision-checked `setNotesVelocities` batch seam that:

  - accepts exact note addresses from Task 02;
  - validates the expected revision and every address before mutation;
  - rejects the entire stale or invalid batch;
  - deduplicates by SMF track and note-on index with last edit winning;
  - clamps stored values to `1...127`;
  - filters no-ops;
  - stores exact old values;
  - creates one `paint note velocities` Undo command; and
  - emits normal document-change and playback-rebuild notifications.

- Selection continuity for surviving notes after apply and Undo.

## Non-goals

- No drawer or velocity page.
- No PSG canonicalization or axis model.
- No preview UI.
- No broad command-framework refactor.

## Method

1. Add focused revision tests around mutation, load, Undo, Redo, failure, and
   no-op paths.
2. Add failing batch tests for stale revision, stale address, duplicates,
   clamping, no-ops, exact Undo, signals, and selection continuity.
3. Introduce the smallest document-owned revision seam.
4. Implement whole-batch validation before any write.
5. Reuse existing command and rebuild paths rather than bypassing them.
6. Run the document harness after each step.

## Verification

- **CORE-03** passes in `editcheck`.
- A stale or partly invalid batch changes no bytes, selection, revision, or
  Undo depth.
- A valid batch increments revision once and creates exactly one command.
- Undo and Redo each increment revision once and restore exact values.
- A no-op batch creates no command and no revision change.
- Existing document edit checks remain green on fresh scratch fixtures.

## Oracle review points

Use the oracle to confirm intended batch outcomes, not its ambiguous note
identity. The final seam must be document-owned and atomic.

## Handoff and review

Stage but do not commit. Record `START_SHA`, staged tree ID, revision rules,
batch validation order, exact fixture edits, Undo-depth evidence, commands and
exits, and baseline comparisons.

The Review agent must probe partial-failure atomicity, notification order,
revision increments, exact Undo, no-op filtering, and ownership. Approval
gates the coordinator's Task 03 commit.
