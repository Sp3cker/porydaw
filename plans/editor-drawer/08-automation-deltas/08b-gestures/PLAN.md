# Task 08B — Automation gestures, drawing, lifecycle, and Undo

**Blocked by:** Reviewed Task 08A materialized as a coordinator-created
transport commit on top of the accepted Task 07 integration tree.

**Runtime worktree:** `08b-gestures`

**Branch:** `task/editor-drawer/08b-gestures`

**Target slice:** Gesture-and-drawing sub-slice of specification implementation
slice 8.

## Start rule

The coordinator creates or fast-forwards this clean worktree to a transport
whose tree is exactly the approved Task 08A `git write-tree` result. Record:

- accepted Task 07 integration commit as `TASK07_SHA`;
- the coordinator-created Task 08A transport commit as `STATE_BASE_SHA`; and
- its tree as `STATE_BASE_TREE`.

Before editing, prove `HEAD^{tree}` equals `STATE_BASE_TREE`. Stop if it does
not. Read the root `PLAN.md`, full editor drawer specification, parent Task 08
plan, Task 08A plan and approved handoff/review, the shared Review plan,
repository instructions, and this plan in full. Inspect oracle commit
`52fd478f27594ffe410472fb8d4a62e792378f16` read-only.

## Contract

Own:

- automation pointer, wheel, pan, resize, exact-entry, selection, and
  voice-row behavior in **AUT-02**;
- one-command and no-op rules in **AUT-03**;
- every automation gesture case in **LIFE-01**;
- automation drawing and hover deltas; and
- the gesture portions of **UX-03** and **UX-04**.

Consume Task 08A's row identity and state interfaces without creating a second
codec, lane list, remap path, or menu model.

## What to deliver

### Pointer and wheel behavior

- Middle drag pans horizontal time and vertical lane scroll.
- Ctrl-wheel changes shared row height by the resolved increment, clamps to
  layout bounds, scales overrides, and pins the row under the pointer.
- Shift/horizontal wheel scrolls time; plain plot wheel zooms about the
  pointer; plain gutter wheel remains for outer vertical scroll.
- Only left drag resizes a row divider; other buttons do nothing there.

### Editing gestures

- Point hit testing uses the shared resolved radius in both axes.
- Point move, unchanged press/release no-op, gap-free freehand replacement,
  Shift ramp priority, Alt clock grid, normal endpoint snap, and Ctrl neutral
  magnetization.
- Half-open multi-row right-drag time selection, in-selection menu routing,
  time-axis-only nearby deletion, and the specified empty-row clearing rules.
- Atomic double-click exact entry with no first-click write, correct value
  domains, cancel/no-op behavior, and at most one point and one Undo command.
- Existing/new voice picker initialization, commit/no-op/delete rules, and
  empty-space preview behavior.
- Escape restores the gesture-start selection or edit snapshot as specified.

### Drawing and lifecycle

- Held-step curves, point-detail threshold, tempo/track colors, dashed bend
  center, raw-pointer hover value, and no value before the first point.
- Rounded current voice through the one shared `drawerContextTick` path.
- Full termination for point, sweep, ramp, and band gestures on page hide,
  drawer hide, track/song/document replacement, any document mutation, Undo,
  Redo, reload, mouse-grab loss, window deactivation, and Escape.
- Staged edits and provisional selections restore their snapshots without MIDI
  or Undo changes.
- Pan and resize end capture while keeping already-applied view state.
- Every active automation gesture pauses follow-scroll and commit or cancel
  resumes it without changing the frozen gesture coordinates.
- No cursor, grab, hover, preview, or follow-scroll pause remains after
  termination.
- Exactly one `SongEditCommand` per completed document-edit gesture and none
  for no-op or view-only gestures.

## Non-goals

- Do not redesign Task 08A row keys, sidecar codecs, remap storage, lane lists,
  or menu contents.
- Do not add velocity behavior, lane reordering, row collapse, tooltips, or
  extra shortcuts.
- Do not introduce feature-local static geometry.
- Do not repair unrelated roll, event-list, voice, or playback behavior.

If a real integration defect requires changing an 08A-owned seam, stop and
record it for the coordinator. Such a change requires renewed 08A coverage and
review of the combined boundary affected by that delta.

## Method

1. Characterize the Task 08A transport and add a failing focused case before
   each gesture delta.
2. Introduce one gesture snapshot and termination route, then migrate one
   gesture family at a time.
3. Separate UI preview state from document mutation.
4. Finish each family with its Undo/no-op and lost-lifecycle matrix.
5. Add drawing changes only after size, paint, and hit paths share Task 05
   layout values.
6. Re-run Task 08A checks after every change that consumes row state.

## Required verification

Use one-at-a-time ephemeral scratch reflinks for mutating checks, deleting each
immediately after recording its result. Reuse the active candidate build and
run focused automation, edit, roll, session, drawer-lifecycle, and remap checks
that prove:

- every pointer and wheel route above;
- gap-free fast sweep and ramp behavior;
- point, neutral-snap, nearby-delete, divider, and detail thresholds use the
  same resolved geometry as painting;
- exact-entry domains, atomic cancel, unchanged no-op, and one-command accept;
- time-selection scope and Escape restoration;
- voice insert/change/delete and hover preview behavior;
- all automation **LIFE-01** termination events restore the correct snapshot;
- pan and resize retain applied view state;
- follow-scroll pause/resume retains the frozen gesture frame;
- one command per completed edit and zero for no-op, canceled, or view-only
  gestures; and
- Task 08A row, sidecar, remap, menu, MIDI, revision, and Undo checks still
  pass.

Run all three geometry gates:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Run `git diff --cached --check` and attribute any full-roll failure against
Task 00's same-fixture baseline.

## Staged-tree handoff

Stage only the 08B candidate delta and do not commit. Leave no unstaged tracked
changes or untracked source files.

Record in `_coordination/08b-gestures/HANDOFF.md`:

- `TASK07_SHA`, `STATE_BASE_SHA`, `STATE_BASE_TREE`, and final
  `git write-tree` ID;
- the 08B-only changed files and diffstat;
- the full Task 08 combined changed files and diffstat from `TASK07_SHA`;
- gesture/Undo and lifecycle matrices;
- drawing, hover, focus, cursor/grab, MIDI, revision, and snapshot evidence;
- Task 08A regression results;
- exact commands, exits, ephemeral fixture identifiers and deletion
  confirmations, baseline attribution, screenshots, and geometry outputs; and
- confirmation that the worktree is staged and uncommitted.

## Review gates

The Review agent performs two reviews against the same final staged tree:

1. **08B delta review:** compare `STATE_BASE_SHA` with the staged tree and
   verify every gesture, drawing, lifecycle, Undo, non-goal, and oracle point
   owned here.
2. **Combined Task 08 review:** compare `TASK07_SHA` with the staged tree,
   reread both 08A and 08B plans, rerun both focused suites, and verify
   **AUT-01...AUT-03**, typed **DRW-04/DRW-05**, automation **LIFE-01**,
   remapping, sidecar/MIDI invariants, menu-to-gesture interaction, exclusions,
   layout ownership, and spiritual correctness as one candidate.

The review record must name both base trees and the final staged tree.
Approval of 08B alone is insufficient. Any change after either review
invalidates both tree bindings. Reissue both verdicts for the new exact tree,
reviewing the remediation delta, prior findings, and combined boundary it
affects rather than untouched accepted portions.

The task agent never commits. Only after both reviews return `APPROVED` may the
coordinator create the clean B transport commit, then synthesize its exact tree
as the single Task 08 integration commit defined by the root plan.
