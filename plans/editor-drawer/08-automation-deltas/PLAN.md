# Task 08 — Complete the automation drawer behavior

**Blocked by:** Reviewed and integrated Task 07.

**Task-agent worktrees:** `08a-state-menus`, then `08b-gestures`.

**Task-agent plans:**

- [08A state and menus](08a-state-menus/PLAN.md)
- [08B gestures](08b-gestures/PLAN.md)

**Target slice:** Specification implementation slice 8.

**Suggested subject:** `Complete automation drawer behavior`

## Start rule

Record the accepted Task 07 integration SHA as `LOGICAL_START_SHA`. Task 08A
starts there. After its staged tree passes Review, the coordinator creates a
task-local transport commit with that exact tree. Task 08B starts from that
transport commit. Neither task agent commits.

Before editing, each agent reads the root plan, full specification, repository
instructions, this parent plan, its child plan, and the Review plan in full.

## Contract

Own all Automations page sections and:

- **AUT-01**, **AUT-02**, and **AUT-03**;
- typed lane-state portions of **DRW-04** and **DRW-05**;
- automation gestures in **LIFE-01**;
- Task 01 remap consumers; and
- **UX-03**, **UX-04**, and the lane-state part of **UX-10**.

## What to deliver

### Rows and persistence

- Tempo, conditional Voice, then sorted visible controller rows.
- Pitch bend last through pseudo-controller `255`.
- Primary-track row context with specified multi-track edit scope.
- Empty and hidden lane state.
- Shared and per-row heights and eligible value ranges.
- Typed canonical row keys and lane-object shape.
- Rejection of controller identities `128...254`.
- Per-entry malformed-state tolerance.
- Repeated restore replaces both lane lists.
- Heights and ranges retained across hide, remove, delete, reorder, and
  recreation.
- Valid non-menu range `91` survives load, remap, and save.
- Complete track-owner remapping from Task 01.

### Menus and announcements

- Exact add-lane ordering, disabled all-present item, hidden-lane section, and
  left/right click behavior.
- Exact lane actions, enablement, confirmation, value-range submenu, clamping,
  copy/paste semantics, and announcement strings.
- View-only lane actions create no MIDI change or Undo entry.

### Gestures and drawing

- Middle pan, wheel routing, shared row-height scaling, and row-divider resize.
- Point move/no-op, complete freehand interpolation, Shift ramp, Alt grid,
  normal snap, and Ctrl magnetization.
- Half-open time selection and nearby deletion rules.
- Atomic exact-entry double-click with no first-click side effect.
- Correct Escape semantics.
- Modal existing/new voice picker behavior and insertion preview.
- Held-step drawing, dot threshold, hover values, colors, center line, and
  rounded current-voice context.
- One `SongEditCommand` for each completed edit and none for no-ops.
- Full safe termination for every automation gesture.

## Non-goals

- No lane reordering or per-row collapse.
- No velocity page.
- No extra menus, shortcuts, tooltips, or status strings.
- No unrelated roll, event-list, voice, or playback fixes.

## Method

Use the two required child plans in order:

1. Task 08A implements typed lane state, menus, persistence, and remapping.
2. Task 08B implements gestures, drawing, cancellation, and Undo deltas on the
   exact reviewed 08A transport tree.
3. Review 08B's delta and then the full Task 08 tree against
   `LOGICAL_START_SHA`.
4. The coordinator synthesizes the exact combined approved tree as one Task 08
   integration commit.

Add a focused failing case before each behavior change. Preserve Task 06 parity
where the specification does not name a delta.

## Required verification

Run focused automation, edit, roll, session, and remap checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Prove:

- **AUT-01...AUT-03**, automation **LIFE-01**, and current DRW state portions;
- exact menu text, order, enablement, and messages;
- apply/Undo/Redo remapping across track mutations;
- hidden lane participation in track-scoped range edits;
- one command per completed edit, zero for no-op or view-only action;
- atomic cancel and double-click behavior;
- lost capture leaves no cursor, grab, hover, preview, MIDI, or Undo residue;
- sidecar round-trip changes no MIDI; and
- no new local geometry or excluded hunk appears.

## Oracle review points

Compare the complete interaction flow with the oracle but require the spec's
improvements: one complete remap, typed validation, replace-not-append restore,
atomic double-click, unknown-key preservation, and safe cancellation.

## Handoff and review

Each child agent stages but does not commit and writes its own handoff. The
final combined handoff records `LOGICAL_START_SHA`, 08A transport SHA and
approved tree, 08B staged tree, row-state fixtures, menu transcripts,
gesture/Undo matrix, remap evidence, sidecar and MIDI diffs, geometry gates,
screenshots, and all commands and exits.

The Review agent must review each child and the complete combined tree, exercise
real pointer/menu flows, and verify view/document ownership. Only the
coordinator may synthesize the tree after both child verdicts and the combined
verdict are `APPROVED`.
