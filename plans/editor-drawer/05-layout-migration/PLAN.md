# Task 05 — Move shared editor geometry into `layout`

**Blocked by:** Reviewed and integrated Task 04.

**Runtime worktree:** `05-layout-migration`

**Branch:** `task/editor-drawer/05-layout-migration`

**Target slice:** Specification implementation slice 5.

**Suggested subject:** `Move editor geometry into layout`

## Start rule

Fast-forward this clean worktree to the accepted Task 04 integration SHA and
record it as `START_SHA`.
Before editing, read the root plan, full specification, repository
instructions, and this plan in full.

## Contract

Close **LAY-01** and the geometry foundation for **DRW-01**, **AUT-02**,
**VEL-02**, and **UX-11**.

## What to deliver

- Semantically named shared `layout` accessors for every independent value in
  Task 04's inventory, including future drawer and velocity values.
- Numeric `layout::fontPx` factors only inside `layout.cpp`.
- `layout::singlePixel()` only for true one-unit hairlines.
- Existing automation geometry migrated with no raw static geometry left.
- Track-header and piano-keyboard widths owned by `layout`.
- Every consumer updated, plot origin derived from those widths, and no
  `SongView` alias that can drift.
- A fresh-process `--editor-layout-check --base-font-px` path.
- The standard-library-only
  `python3 tools/check_editor_layout_geometry.py` source gate.
- The source checker as the sole final source-location inventory; remove any
  temporary duplicate call-site allowlist from Task 04.

## Non-goals

- No visible drawer or velocity page.
- No automation behavior change.
- No unrelated layout cleanup elsewhere.
- No broad file, range, or numeric-pattern exemptions.

## Method

1. Add named accessors and resolver cases while old consumers still work.
2. Migrate one semantic value and all its consumers at a time.
3. Keep audited-scale geometry unchanged after each step.
4. Migrate shared origins before feature work can consume them.
5. Build the source gate from the accepted inventory.
6. Delete old aliases only after every consumer uses the shared value.
7. End with no local raw geometry in the current automation/shared-origin
   scope.

## Required verification

Run in fresh processes:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Also verify:

- audited default outcomes match Task 04;
- declared scale or hairline invariance matches at `16`;
- derived values resolve after their components;
- paint, hit-test, clamp, scroll, and persistence paths use the same values;
- current automation interaction remains unchanged;
- narrow widths clamp at the derived plot origin; and
- `git diff --cached --check` passes.

## Oracle review points

Require the oracle's intended default geometry while improving its ownership.
The oracle's local constants are evidence, never a structure to preserve.

## Handoff and review

Stage but do not commit. Record `START_SHA`, staged tree ID, old-to-new symbol
map, removed aliases, source-gate scope and exceptions, both resolver outputs,
default-geometry evidence, and all commands and exits.

The Review agent must search for hidden local geometry, direct numeric
`fontPx` calls, duplicated origins, weak exemptions, and changed default UX.
Approval gates the coordinator's Task 05 commit. Every later task inherits all
three geometry gates.
