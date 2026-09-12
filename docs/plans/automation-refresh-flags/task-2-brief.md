# Task 2 — Fold gesture-end repaint into full repaint

Step 2 of the automation refresh-flags consolidation (planner verdicts in
`agent://FlagsConsolidationPlan`; read those verdicts first for the full
justification — values below are exact).

## Target

- `src/ui/editordrawer/automationcanvas.cpp` (~lines 207-210 `requestFullQuickUpdate`, ~248-252 `requestGestureEndQuickUpdate`, ~488 `cancelInteraction` wasActive branch)
- `src/ui/editordrawer/automationcanvas.h` (~line 218 `requestGestureEndQuickUpdate` declaration)
- `src/ui/editordrawer/automationcanvas_input.cpp` (lines 349, 361, 385, 469 — gesture release/cancel callsites)

Do not touch any other file. These files are clean in the working tree;
leave the dirty files (`AutomationTabs.qml`, `painting.cpp`, `cclanes.*`,
`CHANGELOG.md`) alone.

## Change

1. Move `invalidateSelectedNodeMultiplicity()` into `requestFullQuickUpdate()`
   with a one-line comment: full repaints re-render the selection layer, so
   the revision-keyed memo cannot survive them.
2. Delete `requestGestureEndQuickUpdate()` definition and declaration.
3. Re-point all 5 callsites to `requestFullQuickUpdate()`:
   `automationcanvas_input.cpp:349,361,385,469` and
   `automationcanvas.cpp:488`.

Ruling carried from the plan: the memo is keyed on documentRevision only
(`automationcanvas.cpp:160-163`), which selection changes don't bump, while
`All` repaints `AutomationSelection` whose pixels consume the memo via
`hasMultipleSelectedNodes` (`automationquick.cpp:154/219/235`). The
invalidation is therefore invariant to full repaints, not per-callsite.

## Acceptance

`grep pattern="requestGestureEndQuickUpdate" path="src"` finds nothing and
`deno task build:app` passes. Run `deno task format` on the touched files
first. Never invoke `cmake` directly. Verification is non-waivable: report
the build command and its output. Harness runs (`--filter=automation`)
stay controller-side; do not run them.
