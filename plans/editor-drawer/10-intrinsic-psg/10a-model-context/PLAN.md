# Task 10A — Add intrinsic level and axis metadata

**Blocked by:** Reviewed and integrated combined Task 09.

**Runtime worktree:** `10a-psg-model`

**Branch:** `task/editor-drawer/10a-psg-model`

**Parent slice:** Task 10, intrinsic PSG velocity.

## Start rule

Fast-forward this clean worktree to the accepted combined Task 09 integration
SHA. Record it as both `START_SHA` and `TASK10_BASE_SHA`.

Before editing, read the root plan, full specification, repository
instructions, the parent Task 10 plan, Task 09A's plan and handoff, and this
plan in full.

## Contract

Consume Task 09A's final PSG resolver, representative tables, compatibility
result, and per-note canonicalizer. Add the widget-independent intrinsic level
and selection-axis projection needed by Task 10B. Do not add a second voice
resolver, graduation table, context cache, compatibility path, or
canonicalizer.

Own the model and context foundation for **VEL-04**, while rechecking the
already complete mixed-context **VEL-03** path from Task 09. Task 10B owns all
intrinsic drawing, pointer interaction, accessibility, and the strict native
harness.

## What to deliver

### Effective levels and axis projection

- Derive effective velocity for stored `s` as
  `min(ceil(s / 4) * 4, 127)`.
- Derive the four-bit intrinsic level as
  `floor((E - 1) / 8)`.
- Enumerate intrinsic levels from Task 09A's exact Square/Noise and Wave
  tables without copying those tables.
- Keep stored exact MIDI velocity separate from effective velocity, intrinsic
  class, and representative.
- Project one compatible selection into immutable axis metadata: resolved voice
  name and type, level count, one-based level number, representative, audible
  flag, selected exact-value substitution, and conflicting-value fallback.
- Expose enough data for Task 10B to restore an exact origin after leaving and
  returning to a class. Do not put gesture state in the model.

### Context consumption

- Accept only Task 09A's resolved compatible or continuous result. Do not
  inspect voicegroup types, programs, key splits, or mixer state again.
- A compatible result produces intrinsic axis metadata. Task 09A's
  DirectSound, missing/invalid, nested-key-split, keyless, and incompatible
  results remain continuous unchanged.
- Reuse Task 09A's `drawerContextTick` route through its public result. Add no
  second rounding or lookup path.
- Preserve Task 09's mixed-context canonicalization unchanged.
- Prove the new projection adds no dependence on CC7, song volume, pan, rhythm
  pan, modulation, or live mixer values.

## Non-goals

- No intrinsic ruler, labels, drawing, hit testing, gestures, focus, status,
  accessibility, or widget behavior.
- No change to Task 09's visible continuous page.
- No strict twelve-result UI harness; Task 10B owns it.
- No parallel PSG model or temporary canonicalization table.
- No feature-local geometry or excluded oracle assets, scripts, theme work, or
  unrelated voice and playback fixes.

## Method

1. Characterize Task 09A's resolver, tables, compatibility result, and
   canonicalizer and add regression coverage before consuming them.
2. Add pure effective-value, level, class, representative, and audible-state
   cases.
3. Add the intrinsic axis projection and exact/conflicting selected-value
   metadata.
4. Prove every continuous fallback passes through unchanged.
5. Prove mixed-context canonicalization still uses one proposal and the Task
   09 path.
6. Probe mixer-state changes against identical projection inputs.

If this work needs static geometry absent from Task 04's accepted inventory,
stop. First route a separate reviewed characterization and `layout` preparatory
change through the coordinator. Do not add geometry to this model slice.

## Required verification

Run the focused pure-model, context, continuous-velocity, and edit checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Prove:

- every stored value `1...127` maps to the specified effective value and
  intrinsic class;
- Task 09A's Square/Noise and Wave representative, range, and audible tables
  remain exact and have no duplicate definition;
- velocity `95` belongs to Wave's representative-`96` class while remaining
  stored as `95`;
- Task 09A's equal-count incompatibility, key-split resolution, and every
  continuous fallback remain unchanged;
- mixed proposal `65` still yields Wave `64`, Square/Noise `68`, and
  DirectSound `65`;
- mixer-only changes do not alter graduation or compatibility results;
- Task 09 continuous behavior and **PERF-01** remain unchanged; and
- no UI, local geometry, duplicate table/resolver/compatibility path, or
  excluded path appears.

## Handoff and first review

Stage the exact candidate without committing. Record `START_SHA`,
`TASK10_BASE_SHA`, staged tree ID, the Task 09A APIs and tables consumed,
intrinsic projection outputs, voice and key-split fixtures,
mixer-independence evidence, all commands and exits, geometry gates, and
baseline-attributed failures.

An independent Review agent reviews the staged Task 10A delta against
`START_SHA`, the full Task 10 contract, the specification, and the oracle.
It must reject duplicate tables, context, compatibility, or canonicalization
logic, widget-owned model state, lost exact values, or changes to Task 09's
fallback rules.

After approval, the coordinator may create a reviewed transport commit from
this exact tree so Task 10B can start. That transport is not final Task 10
acceptance and must not bypass Task 10B's combined-tree review.
