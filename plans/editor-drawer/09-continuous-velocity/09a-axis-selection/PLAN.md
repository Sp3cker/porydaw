# Task 09A — Continuous axis, shared state, drawing, and selection

**Blocked by:** Reviewed and integrated Task 08.

**Runtime worktree:** `09a-axis-selection`

**Branch:** `task/editor-drawer/09a-axis-selection`

**Parent slice:** Task 09 continuous velocity.

## Start rule

Create or fast-forward this clean worktree to the accepted Task 08 integration
SHA and record it as `START_SHA`. Before editing, read the root plan, full
specification, repository instructions, the parent Task 09 plan, and this plan
in full.

Do not start from the oracle or the unused parent Task 09 branch. Do not commit.

## Contract

Own the non-mutating foundation of:

- **VEL-01**;
- selection, drawing, and axis portions of **VEL-02**;
- continuous fallback and pure per-note context portions of **VEL-03**; and
- shared-state portions of **UX-05** and **UX-06**.

Intrinsic ruler presentation remains disabled. Task 10 extends the pure voice
model without replacing the seam established here.

## What to deliver

### Pure axis and voice context

- A widget-independent continuous `VelocityAxis`.
- Exact continuous mapping from stored velocity `1...127`, with 127 at the top
  and 1 at the bottom.
- The specified five density bands, labels, tick sets, endpoint inclusion, and
  named `layout` thresholds.
- Continuous fallback for DirectSound, a missing voicegroup, an invalid
  program, nested key splits, a top-level key split without a note key, and
  incompatible selections.
- The sole PSG voice-context resolver and sole representative tables for this
  feature: the specified sixteen Square 1, Square 2, and Noise values and five
  Wave ranges, representatives, and audible flags.
- Selection compatibility based on the resolved voice type, graduation count,
  representatives, and audible flags, while still returning a continuous
  presentation in this task.
- The sole pure per-note canonicalizer needed by mixed **VEL-03** editing.
  Given a proposed continuous value, it leaves DirectSound and unresolved
  notes exact and maps each PSG note through its own resolved context.
- Pure checks for the proposal `65`: Wave resolves to `64`, Square and Noise
  resolve to `68`, and DirectSound remains `65`.
- Reuse of Task 07's `drawerContextTick`; no second tick conversion.

The resolver, tables, compatibility result, and canonicalizer are final owners,
not provisional Task 10 scaffolding. They must not depend on widget state, CC7,
song volume, pan, rhythm pan, modulation, or live mixer values. Task 10 may
consume their results to enumerate intrinsic labels and levels; it must not
reimplement them.

### Shared page state and drawing

- One Velocity page bound to Task 02's exact shared note selection.
- Shared selected track, notes, horizontal scroll, time zoom, cursor, playhead,
  grid, snap, track color, voice context, focus, and edit-command routes.
- Derived plot origin and the named `layout::Space::Three` vertical insets.
- Duration stems, start nodes, selected thicker stems and rings, track color,
  quiet track watermark, continuous ticks and labels, and no hover decoration.
- Selected-value extrema supplied as render data without creating a second
  selection or preview model.
- Plot width clamped to zero below the derived origin, with no painting through
  the gutter.
- Plain track-header clicks clear shared note selection, including clicks on
  the already-primary track.

### Hit testing, selection, and view-only input

- Exact node and duration-line hit testing through named `layout` values.
- Plain and Ctrl-left selection behavior before any future edit gesture.
- Pending right-band behavior, drag threshold, replace/add box selection,
  stationary plain/Ctrl clicks, blank-space behavior, and matching
  context-menu suppression.
- Middle-button horizontal pan and the specified horizontal-scroll and
  pointer-centered zoom wheel routing.
- No MIDI mutation, revision change, dirty state, or Undo entry from any action
  in this task.

## Non-goals

- No relative velocity drag, freehand paint, graduation mutation, preview
  commit, or document batch call.
- No structured note-status implementation or final accessibility wiring.
- No lifecycle or follow-scroll policy beyond exposing the state 09B must
  terminate.
- No content-cache, `TimelineSurface`, paint-update, or PERF-01 implementation.
- No visible intrinsic graduation, detent, level-count message, ring, or cue.
- No feature-local static geometry, second selection model, context menu,
  tooltip, live region, or velocity key command.

## Method

1. Add pure axis, fallback, compatibility, and canonicalizer checks.
2. Add the page against the existing shared selection and timeline state.
3. Add drawing and named-layout hit testing.
4. Add selection and view-only navigation behavior.
5. Prove all actions remain document-neutral.

## Required verification

Run focused axis, roll, selection, tab, and session checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Prove:

- duplicate notes remain independently selectable;
- every selection rule and shared-state update uses the piano-roll model;
- every continuous fallback is deterministic;
- the pure mixed-context `65` vector is exact;
- view-only input changes neither MIDI nor Undo;
- narrow and both-scale drawing aligns with hit testing;
- no intrinsic axis appears; and
- no 09B-owned mutation, status, lifecycle, rendering, or performance behavior
  has leaked into this slice.

## Oracle review points

Keep the oracle's intended continuous ruler, note drawing, and shared-selection
flow. Improve exact note identity, pure context resolution, mixed-note
canonicalization, narrow-width clamps, and `layout` ownership. Do not copy its
widget-owned axis state or ambiguous note lookup.

## Handoff and review

Stage the exact candidate without committing. Record `START_SHA`, staged tree
ID, pure-model inputs and outputs, fallback matrix, shared-state map, selection
matrix, view-only invariants, geometry-gate output, screenshots, and every
command and exit.

The Review agent reviews the complete Task 08-to-09A staged diff and binds
approval to its tree ID. It must inspect the pure/widget boundary, exact shared
selection, drawing and hit-test alignment, and the absence of mutation or
intrinsic display.

After approval, the coordinator may create a reviewed 09A transport commit so
09B can use this exact tree as its base. That commit is not permission to skip
the full combined Task 09 review.
