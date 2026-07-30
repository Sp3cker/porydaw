# Task 06 — Characterize and expose the automation page

**Blocked by:** Reviewed and integrated Task 05.

**Runtime worktree:** `06-automation-extraction`

**Branch:** `task/editor-drawer/06-automation-extraction`

**Target slice:** Specification implementation slice 6.

**Suggested subject:** `Expose the automation editor as a hostable page`

## Start rule

Fast-forward this clean worktree to the accepted Task 05 integration SHA and
record it as `START_SHA`.
Before editing, read the root plan, full specification, repository
instructions, and this plan in full.

## Contract

Establish the behavior baseline later closed by **AUT-02** and **AUT-03**.
Make the existing automation editor hostable by an overlay without changing
its visible behavior.

## What to deliver

- Focused characterization for existing:

  - point move and no-op;
  - freehand sweep;
  - Shift ramp;
  - row-divider resize;
  - wheel and pan routing;
  - value ranges;
  - lane menus;
  - time selection;
  - exact entry;
  - Undo depth; and
  - current cancellation behavior.

- The smallest structural seam that exposes one automation page to a future
  drawer host.
- Click-focus support for the automation canvas.
- Preserved shared time scroll, zoom, selection, playhead, and edit cursor.
- No visible drawer yet.

If the existing editor can be hosted without a new module, do not extract it
for aesthetics alone.

## Non-goals

- No lane hiding, empty-lane persistence, new menu actions, or specified
  gesture deltas.
- No drawer tabs, shortcuts, or sidecar fields.
- No velocity work.
- No broad `SongView` breakup.

## Method

1. Add characterization checks before moving any structure.
2. Name the minimal owner boundary required by the future overlay.
3. Move code in behavior-preserving steps.
4. Run parity checks after each move.
5. Keep existing names and local style unless the host interface requires a
   clearer name.

## Required verification

Run the focused automation checks plus:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Confirm:

- before/after automation outputs and Undo counts match;
- the extracted page has no independent time or selection model;
- the application still presents the same editor;
- no new static geometry appears; and
- no unrelated source or formatting changed.

## Oracle review points

Use the base implementation as the parity source and the oracle only to judge
whether the resulting host seam can support the specified overlay. Do not
introduce oracle-only UX in this task.

## Handoff and review

Stage but do not commit. Record `START_SHA`, staged tree ID, every
characterized behavior, before/after results, structural ownership change,
geometry-gate outputs, commands and exits, and screenshots if geometry moved.

The Review agent must distinguish structural parity from feature work, check
that the page remains one shared editor surface, and reject broad refactoring.
Approval gates the coordinator's Task 06 commit.
