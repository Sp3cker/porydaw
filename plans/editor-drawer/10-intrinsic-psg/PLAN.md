# Task 10 — Add intrinsic PSG velocity graduations

**Blocked by:** Reviewed and integrated Task 09.

**Task-agent worktrees:** `10a-psg-model`, then `10b-intrinsic-ux`.

**Task-agent plans:**

- [10A model and context](10a-model-context/PLAN.md)
- [10B UX and harness](10b-ux-harness/PLAN.md)

**Target slice:** Specification implementation slice 10.

**Suggested subject:** `Add intrinsic PSG velocity graduations`

## Start rule

Record the accepted Task 09 integration SHA as `LOGICAL_START_SHA`. Task 10A
starts there. After its staged tree passes Review, the coordinator creates a
task-local transport commit with that exact tree. Task 10B starts from that
transport commit. Neither task agent commits.

Before editing, each agent reads the root plan, full specification, repository
instructions, this parent plan, its child plan, and the Review plan in full.

## Contract

Own:

- **VEL-04**;
- intrinsic **A11Y-01**;
- categorical velocity cases in **LIFE-01**;
- **UX-07** and **UX-08**; and
- the strict twelve-result PSG native harness.

Recheck complete **VEL-03**, **PERF-01**, and all Task 09 behavior. Task 09's
mixed-context canonicalization is final, not provisional; this slice extends
the same pure model for intrinsic presentation without replacing that path.

## What to deliver

### Intrinsic level and axis projection

- Consume Task 09A's final resolver, representative tables, compatibility
  result, and per-note canonicalizer; do not add a second owner for any of
  them.
- Effective velocity:

  `E = min(ceil(s / 4) * 4, 127)`.

- Intrinsic level:

  `G = floor((E - 1) / 8)`.

- Enumerate intrinsic levels from Task 09A's exact Square 1, Square 2, Noise,
  and Wave tables without copying them.
- Stored exact MIDI velocity independent from displayed representative.
- Immutable selection-axis metadata for level count, representatives, audible
  flags, selected exact values, and conflicts.
- Task 09A's compatibility, voice/key-split resolution, continuous fallbacks,
  and mixed canonicalization remain unchanged.
- Independence from CC7, song volume, pan, rhythm pan, modulation, and live
  mixer state.
- Reuse of Task 09's per-note canonicalization and the shared
  `drawerContextTick` seam.

### Intrinsic UX

- One-column five-level and two-column larger label layouts.
- Exact `Volume N (value)` text.
- Lowest/highest emphasis rules.
- Exact selected value substitution and conflicting-value fallback.
- No held ring or extra silence cue.
- Compatible categorical drag with exact-origin restoration.
- Other-level moves use representatives.
- Intrinsic freehand keeps Task 09's stationary stamp and gap-free
  interpolation, uses the frozen axis representative for compatible notes,
  and retains per-note continuous canonicalization for incompatible notes.
- Incompatible notes remain at continuous positions.
- Label clicks batch all selected notes to the displayed exact value.
- Exact intrinsic accessible description and quiet level-count message.
- Typed piano-roll entry always stores the typed exact value.

### Native harness

Report exactly these twelve unique names and return nonzero for false,
missing, duplicate, or non-twelve totals:

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

## Non-goals

- No mixer-dependent graduations.
- No generated velocity-bar images, research scripts, temporary mixed harness,
  tooltips, separate focus targets, or velocity keyboard nudges.
- No theme, color-cache, application-style, Visual Studio, keymap, or
  unrelated roll changes.
- Do not copy oracle files wholesale.

## Method

1. Task 10A consumes the one Task 09 resolver and tables, then adds effective
   levels, exact-value class projection, selection-axis metadata, and proof
   that the projection remains mixer-independent.
2. Task 10B extends the existing axis and gesture system with intrinsic
   drawing, categorical interaction, exact restoration, accessibility, and
   the strict harness.
3. Review 10B's delta and then the full Task 10 tree against
   `LOGICAL_START_SHA`.
4. The coordinator synthesizes the exact combined approved tree as one Task 10
   integration commit.

## Required verification

Run the twelve-result velocity harness, focused roll/edit checks, and:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Prove:

- all exact representatives, ranges, labels, and level counts;
- Square 1, Square 2, and Noise are incompatible despite equal counts;
- mixed selection stays continuous and retains Task 09 semantics;
- leave-and-return restores exact origin;
- typed values never snap;
- mixer changes do not move graduations;
- categorical cancellation follows the shared lifecycle route;
- intrinsic accessibility is exact;
- the strict harness reports twelve unique passing names;
- **PERF-01** and continuous regressions still pass; and
- no excluded path or local geometry appears.

## Oracle review points

Retain the oracle's useful intrinsic-level experience while requiring exact
MIDI preservation, deterministic compatibility, key-aware resolution,
mixer independence, strict test status, and no research detritus.

## Handoff and review

Each child agent stages but does not commit and writes its own handoff. The
combined handoff records `LOGICAL_START_SHA`, 10A transport SHA and approved
tree, 10B staged tree, model tables, voice/key-split fixtures, all twelve named
results, exact-origin and Undo evidence, mixer-independence evidence,
accessibility text, PERF counters, geometry gates, screenshots, and all
commands and exits.

The Review agent must review each child and the full combined tree, compare
perceived intrinsic editing behavior with the oracle, and inspect the pure
model and exact-value boundaries. Only the coordinator may synthesize the tree
after both child verdicts and the combined verdict are `APPROVED`.
