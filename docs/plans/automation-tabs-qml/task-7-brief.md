# Task 7 — De-duplicate the scroll-test helpers

The three check binaries each carry a near-identical
`automationTabsScroller` + `scrollTabIntoView` + `rectInside` trio
(`automationcanvaslayout.cpp:39-72`, `painting.cpp:70-91`,
`drawer.cpp:57-80`). One home, three callers.

## Target

- The trio in all three files above, plus exactly one shared home under
  `src/checks/support/` (new file only if no existing support file fits —
  check how other shared helpers are wired first).

## Change

1. Find the precedent for sharing code across check binaries (CMake sources,
   manifest registry, `tools/run_checks.ts` staging) and follow it — the
   helper must compile into all three harnesses.
2. Move the trio to the shared home with one canonical epsilon
   (`layout::singlePixel()`, per the epsilon fix) and one clamp policy.
   Keep the `QVERIFY2` failure messages.
3. Re-point all three callsites; delete the local copies. No behavior
   change: identical scroll/clip assertions, identical thresholds.

## Acceptance

`grep pattern="scrollTabIntoView|rectInside|automationTabsScroller" path="src/checks"` shows one definition plus callsites;
`deno task format` on touched files; then
`deno task verify --filter=automation --verbose` and
`deno task verify --filter=drawer --verbose` both PASS — paste raw outputs.
