# Task 3 — Hover-sync consolidation in activateParameter

Step 3 of the automation refresh-flags consolidation (planner verdicts in
`agent://FlagsConsolidationPlan`; read the `activateParameter_narrowing_ruling`
and `single_flag_ruling` first — they explain what NOT to do).

Depends on Task 2 (same files). Dispatch only after Task 2 lands clean.

## Target

- `src/ui/editordrawer/automationcanvas_tabs.cpp` (`activateParameter`,
  ~lines 106-123)
- `src/ui/editordrawer/automationcanvas.cpp` (`requestQuickUpdate` ~189-194,
  `syncTimelineQuickHover` ~196-205)
- `src/ui/editordrawer/automationcanvas.h` (~line 212
  `syncTimelineQuickHover` declaration)

Do not touch any other file, especially not `AutomationTabs.qml` (dirty,
in-flight work elsewhere).

## Change

1. Delete the direct `syncTimelineQuickHover()` call in `activateParameter`
   (~line 120). Keep the surrounding lines unchanged, including
   `emit activeParameterChanged()` and `requestFullQuickUpdate()`.
2. Add a brief comment at the `requestFullQuickUpdate()` call: the Hover bit
   inside All is what re-syncs the cross-band hover owner after `clearHover`.
3. Inline the `syncTimelineQuickHover` body into `requestQuickUpdate`'s Hover
   branch and drop the declaration in the header.

Rulings carried from the plan, do not relitigate: line 120 is the provable
redundancy (nothing between it and the request mutates hover; the request
re-runs the sync with identical inputs AND publishes the cross-band owner).
Do NOT narrow the request to `Content|Transient` — two concrete failure
modes: stale `AutomationHover` pixels on keyboard activation while the
pointer idles, and stale owner publish because `cancelInteraction`'s Hover
request runs pre-`clearHover`. Flags and rebuild branches are untouched.

## Acceptance

`grep pattern="syncTimelineQuickHover" path="src"` finds nothing and
`deno task build:app` passes. Run `deno task format` on the touched files
first. Never invoke `cmake` directly. Verification is non-waivable: report
the build command and its output. Harness runs (`--filter=automationhover`,
`--filter=playhead`, `--filter=selectionkey`) stay controller-side.
