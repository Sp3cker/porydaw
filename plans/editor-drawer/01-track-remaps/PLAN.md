# Task 01 — Publish complete track-identity remaps

**Blocked by:** Task 00 baseline and reviewed seed.

**Runtime worktree:** `01-track-remaps`

**Branch:** `task/editor-drawer/01-track-remaps`

**Target slice:** Specification implementation slice 1.

**Suggested subject:** `Publish complete track-identity remaps`

## Start rule

The coordinator must fast-forward this clean task branch to the reviewed seed
and record that exact SHA as `START_SHA`. Do not work from the oracle branch.
Before editing, read the root plan, full specification, repository
instructions, and this plan in full.

## Contract

Own the specification's Track-identity remapping section and **CORE-01**.
Provide the remap seam later consumed by automation state and **UX-04**.

## What to deliver

- One complete mutation event containing:

  - new SMF chunk index by old SMF chunk index; and
  - new engine slot by old engine slot.

- `-1` for deleted owners.
- Publication after track-map rebuild and before the general document-change
  notification.
- Coverage for move, insert, duplicate, delete, raw metadata-only to
  engine-track transitions, the reverse transition, Undo, and Redo.
- Suppression for no-op and identity remaps.
- Adapted existing selected-track, multi-track scope, mute/solo, and event-list
  consumers without changing their UX.

## Non-goals

- No drawer or velocity UI.
- No automation lane state yet.
- No unrelated event-list, mute/solo, follow-playhead, or formatting change.
- Do not add fallback notifications beside the complete remap.

## Method

1. Characterize current mutation notification order.
2. Add failing focused cases for every required apply/Undo/Redo transition.
3. Introduce the narrow remap value and one publication seam.
4. Adapt existing consumers one at a time.
5. Remove only compatibility code made obsolete by this task.
6. Build and run focused checks after each behavior-preserving step.

## Verification

- **CORE-01** passes for all named transitions, identity suppression, and
  signal order.
- Existing edit, event-list, session, tab, and roll seams touched by the remap
  still pass against fresh scratch fixtures.
- Apply, Undo, and Redo restore the same selected owner.
- MIDI and Undo state change only for the underlying requested mutation.
- `git diff --cached --check` passes and the staged file list is narrow.

## Oracle review points

Inspect the oracle only to understand downstream owner remapping. Improve it by
publishing one complete ordered event rather than task-specific partial
signals. Do not port unrelated consumer changes.

## Handoff and review

Stage the exact candidate without committing. Record `START_SHA`, staged tree
ID, `BASE_SHA`, specification SHA, plan SHA, oracle SHA, `hearth-test` HEAD,
fixture manifest hash, changed files, all commands and exits, each remap
scenario, signal-order evidence, and baseline-attributed failures.

The Review agent must confirm semantic owner identity, notification order,
complete Undo/Redo coverage, unchanged consumer UX, and no unrelated churn.
Approval is required before the coordinator commits this slice.

This is the first implementation commit. Its commit body must record
`BASE_SHA`, specification SHA, plan SHA, oracle SHA, `START_SHA`,
`hearth-test` HEAD, fixture manifest hash, approved tree ID, and focused
checks. The docs-seed `START_SHA` is not a substitute for the original fetched
base.
