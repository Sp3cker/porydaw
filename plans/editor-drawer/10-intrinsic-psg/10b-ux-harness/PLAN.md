# Task 10B — Add intrinsic UX and the strict native harness

**Blocked by:** Approved Task 10A staged tree and its coordinator-created
reviewed transport commit.

**Runtime worktree:** `10b-intrinsic-ux`

**Branch:** `task/editor-drawer/10b-intrinsic-ux`

**Parent slice:** Task 10, intrinsic PSG velocity.

## Start rule

Fast-forward this clean worktree to the exact reviewed Task 10A transport
commit and record it as `START_SHA`. Also record the accepted combined Task 09
integration SHA as `TASK10_BASE_SHA`; the full combined Task 10 review uses
that fixed base.

Before editing, read the root plan, full specification, repository
instructions, the parent Task 10 plan, both Task 10A handoff and review
records, and this plan in full.

## Contract

Consume Task 10A's model and context without duplicating them. Own intrinsic
drawing, categorical gestures, exact-origin restoration, intrinsic
accessibility, categorical **LIFE-01**, **VEL-04**, **UX-07**, **UX-08**, and
the strict twelve-result native harness.

Recheck Task 09's continuous and mixed-context **VEL-03**, continuous
**A11Y-01**, and **PERF-01**.

## What to deliver

### Intrinsic drawing and labels

- Activate an intrinsic axis only for the compatible context returned by
  Task 10A; retain continuous placement for every incompatible note.
- Draw five graduations in one column and more than eight in two staggered
  columns, using only the accepted named `layout` values.
- Draw exact `Volume <one-based-level-number> (<exact-value>)` labels.
- Emphasize only the lowest and highest active levels when more than two are
  active.
- Substitute one selected exact value for its class; use the representative
  when selected notes conflict within a class.
- Draw no held-value ring and no separate silence cue. A mute class keeps the
  standard `Volume N (value)` label.
- Retain the selected-track watermark and add the quiet
  `<Voice> has N volume levels.` message.

### Categorical interaction and exact values

- Freeze the compatible axis, exact selection, document addresses and
  revision, voice context, and starting exact values for the full gesture.
- Apply one shared intrinsic-level delta.
- Preserve each note's exact starting value while it remains in or returns to
  its starting class.
- Use the destination representative after moving to another class.
- Submit one Task 03 batch and one Undo command on release; previews remain
  UI-only.
- Extend Task 09's stationary-stamp and gap-free crossed-node freehand path:
  a note compatible with the frozen intrinsic axis uses the requested level's
  representative; an incompatible PSG note maps pointer y continuously and
  canonicalizes through its own Task 09 context; DirectSound and unresolved
  notes keep the exact continuous value.
- Clicking an intrinsic graduation label sets all selected notes to that
  label's displayed exact value in one Undo command.
- Keep incompatible mixed notes on Task 09's continuous proposal and
  per-note-canonicalization path.
- Route page hide, drawer hide, track/song/document replacement, any document
  mutation, Undo, Redo, reload, mouse-grab loss, window deactivation, and
  Escape for both categorical drag and intrinsic freehand through the shared
  cancellation path, restoring the exact snapshot with no MIDI or Undo
  residue.
- Keep the piano roll's existing `Set velocity…` action as the sole exact-entry
  path. A typed value always remains exact and never snaps to a
  representative.

### Accessibility and native proof

- Use the exact intrinsic accessible description:

  ```text
  Velocity. <Voice> has N volume levels.
  ```

- Keep nodes and graduation labels out of the focus chain. Add no tooltip or
  live region.
- Add a strict native harness that reports exactly these twelve unique names:

  ```text
  track_header_updates_voice_type
  intrinsic_levels_ignore_mixer
  noise_has_sixteen_levels
  noise_edit_preserves_graduations
  square_selection_labels
  wave_selection_labels
  intrinsic_level_message
  exact_velocity_is_graduation
  exact_velocity_has_no_ring
  origin_level_restores_exact
  undo_restores_exact
  typed_velocity_stays_exact
  ```

- Return nonzero when any case is false, missing, duplicated, or when the
  total is not exactly twelve. Do not require `autoresearch.sh` or a temporary
  mixed harness to parse output.

## Non-goals

- No change to Task 10A's model ownership unless a failing case proves its
  reviewed API incomplete; such a change invalidates both reviews.
- No second selection, context, axis, or gesture system.
- No velocity page context menu, direct velocity keys, tooltip, live region,
  or extra focus target.
- No generated velocity-bar images, research output, theme/color benchmarks,
  application-style changes, Visual Studio changes, or unrelated roll fixes.
- No feature-local static geometry.

## Method

1. Add intrinsic drawing and label-layout checks against Task 10A's pure
   results.
2. Add categorical preview and exact-origin cases before connecting mutation.
3. Connect label and gesture commits through the existing batch and shared
   lifecycle seams.
4. Add exact accessibility and focus checks.
5. Add strict twelve-name accounting and negative cases for false, missing,
   duplicate, and wrong totals.
6. Rerun continuous, mixed-context, lifecycle, performance, and layout checks.

If a required static value is absent from Task 04's accepted inventory, stop
and route a separate reviewed characterization and `layout` preparatory change
before resuming this task.

## Required verification

Run the strict twelve-result harness, focused model, edit, roll, continuous
velocity, lifecycle, accessibility, and performance checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Prove:

- Square 1, Square 2, Noise, and Wave labels and layouts match the model;
- exact selected values replace only their compatible class label;
- conflicting exact values fall back to the representative;
- leave-and-return restores the exact origin and exact Undo restores it again;
- typed entry stays exact;
- label clicks use the displayed exact value and one command;
- intrinsic freehand remains gap-free, uses the frozen compatible
  representative, applies per-note canonicalization only to incompatible PSG
  notes, leaves DirectSound or unresolved values exact, and restores its
  snapshot on every cancellation route;
- mixer changes do not move or relabel graduations;
- every categorical cancellation trigger restores the snapshot and leaves no
  cursor, grab, preview, MIDI, or Undo residue;
- intrinsic accessibility and focus behavior are exact;
- all twelve unique names pass and each negative accounting case returns
  nonzero;
- Task 09 continuous/mixed behavior and **PERF-01** still pass; and
- both layout scales, the source gate, exclusions, and staged-diff checks pass.

## Handoff and two review gates

Stage the exact candidate without committing. Record `START_SHA`,
`TASK10_BASE_SHA`, staged tree ID, changed files, label and gesture matrices,
exact-origin and Undo evidence, cancellation matrix, accessibility results,
all twelve named results and negative accounting cases, mixer-independence and
PERF evidence, geometry gates, screenshots, and every command and exit.

The same staged tree requires two independent Review verdicts:

1. **Task 10B delta review** — compare `START_SHA` to the staged tree and
   review only 10B's intrinsic UX, lifecycle, accessibility, and harness delta.
2. **Combined Task 10 review** — compare `TASK10_BASE_SHA` to the staged tree
   and review the full 10A plus 10B result against the parent Task 10 plan,
   specification, oracle, exclusions, ownership boundaries, and focused
   checks.

Any remediation changes the staged tree and invalidates both tree bindings.
Reissue both verdicts for the new exact tree, reviewing the remediation delta,
prior findings, and combined boundary it affects rather than untouched
accepted portions. Only the coordinator may synthesize the
exact combined-approved tree. It first creates the clean B transport commit,
then uses its exact tree for the single Task 10 integration commit defined by
the root plan, with the required tree-identity and integration checks.
