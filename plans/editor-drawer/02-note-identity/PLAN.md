# Task 02 — Use exact note identity in shared selection

**Blocked by:** Reviewed and integrated Task 01.

**Runtime worktree:** `02-note-identity`

**Branch:** `task/editor-drawer/02-note-identity`

**Target slice:** Specification implementation slice 2.

**Suggested subject:** `Use exact note identity in shared selection`

## Start rule

Fast-forward this clean worktree to the accepted Task 01 integration SHA and
record it as `START_SHA`.
Before editing, read the root plan, full specification, repository
instructions, and this plan in full.

## Contract

Own **CORE-02** and the duplicate-note identity foundation for **VEL-01**,
**VEL-02**, and **UX-05**.

## What to deliver

- An opaque note identity that distinguishes notes sharing track, start tick,
  and key.
- Exact identity through the document model, view projection, piano-roll hit
  and box selection, selection resolution, movement, deletion, clipboard
  operations, rebuilds, and Undo.
- Selection continuity for surviving notes.
- A hard duplicate-note selection, edit, and Undo regression.

The UI may display familiar note data, but it must not reconstruct identity
from `(tick, key)`.

## Non-goals

- No drawer or velocity page.
- No batch velocity mutation.
- No keyboard behavior or visual change.
- No broad rewrite of note storage when a smaller stable locator works.

## Method

1. Characterize every producer and consumer of current note selection.
2. Add the duplicate-note regression before changing identity.
3. Introduce the opaque identity beside the old representation if needed.
4. Migrate one complete selection/edit path at a time while checks stay green.
5. Contract the old ambiguous identity only after every consumer has moved.
6. Check that no fallback lookup silently picks the first duplicate.

## Verification

- **CORE-02** passes.
- Two notes at the same track, tick, and key can be selected independently.
- Editing one changes only that note.
- Undo restores exact values and selection.
- Existing roll selection, move, delete, copy, cut, paste, and track changes
  remain correct.
- No drawer, velocity UI, or unrelated source appears in the staged diff.

## Oracle review points

The oracle's `(start tick, key)` identity is a named defect. Match its user
flow but require stronger exact identity and selection continuity.

## Handoff and review

Stage but do not commit. Record `START_SHA`, staged tree ID, identity design,
all migrated selection paths, duplicate fixture details, commands and exits,
and known gaps.

The Review agent must search for ambiguous reconstruction paths, confirm the
duplicate regression is meaningful, verify Undo and clipboard behavior, and
reject a design that merely documents the defect. Approval gates the
coordinator's Task 02 commit.
