# Task 08A — Automation state, persistence, remapping, and menus

**Blocked by:** Reviewed and integrated Task 07.

**Runtime worktree:** `08a-state-menus`

**Branch:** `task/editor-drawer/08a-state-menus`

**Target slice:** State-and-menu sub-slice of specification implementation
slice 8.

## Start rule

The coordinator creates or fast-forwards this clean worktree to the accepted
Task 07 integration SHA. Record that exact commit as both `TASK07_SHA` and
`START_SHA`.

Before editing, read the root `PLAN.md`, the full editor drawer specification,
the parent Task 08 plan, the Review plan, repository instructions, and this
plan in full. Inspect oracle commit
`52fd478f27594ffe410472fb8d4a62e792378f16` read-only; never copy its files or
commits.

## Contract

Own:

- row ordering and typed automation-row identity in **AUT-01**;
- empty and hidden lane state;
- automation portions of **DRW-04** and **DRW-05**;
- Task 01 remap consumers for saved lane ownership;
- all add-lane and lane-menu behavior; and
- the state/menu portions of **UX-03**, **UX-04**, and **UX-10**.

Task 08B owns pointer editing, drawing, gesture cancellation, and gesture Undo.

## What to deliver

### Rows and stored state

- Tempo first, conditional Voice second, then visible controller rows sorted by
  track and controller, with pitch bend pseudo-controller `255` last.
- Primary selected track as the row context without adding rows for secondary
  header selections.
- Empty and hidden lane lists with stable stored order.
- Shared and per-row heights plus eligible fixed or Auto display ranges.
- Canonical keys `tempo`, `voice:<track>`, and `cc:<track>:<controller>`.
- Track validation in `0...15`; controller validation in `0...127` or `255`;
  explicit rejection of `128...254`, malformed, and non-canonical keys.
- Per-entry sidecar tolerance so one bad row or lane does not discard valid
  siblings.
- Repeated restore that replaces, rather than appends, both lane lists.
- Preservation of unknown root and `view` keys through the Task 07 merge path.
- Valid non-menu ranges such as `91` preserved across load, remap, and save.
- Height and range retention across hide, remove, delete, reorder, and
  recreation.
- Complete apply/Undo/Redo remapping through Task 01's single remap event,
  dropping only state owned by a deleted track.

### Menus and document boundaries

- Exact add-lane order, omission rules, disabled all-present item, separator,
  hidden-lane section, and left/right-click opening behavior.
- Exact lane actions and enablement for copy, replace-paste, hide, clear,
  remove-empty, and confirmed delete.
- Exact eligible value-range submenu and Auto/default behavior.
- Whole-lane clipboard semantics, destination clamping, and one Undo command
  for replace-paste.
- Exact success announcements from the specification.
- Add, hide, show, remove-empty, height, and range changes remain view-only:
  no MIDI diff, dirty state, revision change, or Undo entry.
- Clear, delete, and replace-paste remain document edits with the specified
  Undo behavior.

## Non-goals

- Do not change point, sweep, ramp, exact-entry, time-selection, wheel, pan,
  divider, voice-picker, hover, or drawing behavior.
- Do not add gesture cancellation code; Task 08B owns it.
- Do not add velocity behavior, lane reordering, row collapse, or extra menu
  items.
- Do not introduce static geometry or edit excluded reference paths.
- Do not refactor unrelated `SongView`, event-list, voice, or playback code.

## Method

1. Add focused failing cases for typed decoding, per-entry tolerance, repeated
   restore, and complete remapping.
2. Introduce one canonical row/lane identity codec and migrate each stored
   state consumer to it.
3. Add hidden-lane state and remap it beside existing empty-lane and row-state
   data.
4. Add menu cases before implementing each menu delta.
5. Keep view-only and document-edit paths separate and assert their state
   effects.
6. Run focused checks after each small transformation.

## Required verification

Use one-at-a-time ephemeral scratch reflinks for mutating commands and delete
each immediately after recording its result. Reuse the active candidate build
and run the focused automation, edit, session, roll, and remap checks needed to
prove:

- row order, primary-track context, empty lanes, hidden lanes, heights, and
  ranges;
- canonical-key acceptance and every malformed or out-of-range rejection;
- two disjoint restores replace both lane lists;
- unknown sidecar fields and valid range `91` survive round-trip;
- Task 07's splitter, unknown-page, silent-I/O, and one-fifth fallback cases
  still pass;
- move, insert, duplicate, delete, raw engine-track transitions, Undo, and
  Redo remap all surviving row state once;
- deleted owners alone lose state;
- exact menu text, order, enablement, confirmation, and announcements;
- hidden lanes still participate in track-scoped range edits;
- view-only actions change no MIDI, dirty state, revision, or Undo depth;
- document menu actions create the required single command; and
- the sidecar round-trip changes no MIDI bytes.

Run all three geometry gates:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Run `git diff --cached --check` and compare any full-roll failure with Task
00's same-fixture baseline.

## Staged-tree handoff

Stage only this sub-slice's candidate files. Leave no unstaged tracked changes
or untracked source files. Do not commit.

Record in `_coordination/08a-state-menus/HANDOFF.md`:

- `TASK07_SHA`, `START_SHA`, and `git write-tree` ID;
- changed files and diffstat;
- identity codec and validation table;
- row-order, sidecar, remap, menu, MIDI, revision, and Undo evidence;
- exact commands, exits, ephemeral fixture identifiers and deletion
  confirmations, baseline-attributed failures, and geometry outputs; and
- confirmation that gesture and drawing behavior did not change.

## Review gate

The Review agent reviews the staged delta from `TASK07_SHA`, follows the shared
Review plan, and compares the relevant oracle state/menu flows while requiring
the specification's stronger validation, replacement, remapping, and
view/document ownership.

`APPROVED` requires all owned checks to pass, no Task 08B behavior change, and
an unchanged staged tree ID. The task agent must resolve every requested change
and obtain the focused exact-tree remediation review defined by the shared
Review plan.

The task agent never commits. After approval, only the coordinator may
materialize the exact reviewed tree as the transport commit/base supplied to Task
08B. Any change to that tree invalidates approval.
