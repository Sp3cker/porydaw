# Task 5 — Rewrite the floor- and fill-asserting checks

Runs after Task 4 (the C++ `minimumContentHeight` API is gone by then, so
any check referencing it fails to compile until rewritten here). This task
also covers the fill-semantics assertions broken by Task 1.

## Target (3 files)

- `src/checks/automation/automationcanvaslayout.cpp`
  (~lines 96-106, 313-317: floor-height resize tests)
- `src/checks/automation/presentation/painting.cpp`
  (~lines 139-144 viewport-minimum test; ~404-409 fill assertions pinning the
  OLD `currentFill`/`background` semantics; ~416-436 selection-pixel scan)
- `src/checks/drawerpresentation/drawer.cpp`
  (~lines 66-68 helper flooring on `minimumContentHeight`; ~352-355)

Ruling (controller, binding): tab-visibility/containment assertions conflict
with the new model and MUST be rewritten to it, not preserved. The drawer no
longer guarantees all tabs visible in the body viewport; the Flickable owns
visibility via scroll+clip. Rewrite such assertions as: first tab visible at
content top, overflow clipped at the gutter edge, scroll reaches the last
tab (or equivalent content-height assertions). "Byte-identical in intent"
below applies only to non-geometry assertions. If a harness has no
scroll-aware API to express this, shrink the assertion to what the new
behavior guarantees and report the gap rather than pinning the old floor.

## Change

1. Drop every `minimumContentHeight` reference; re-derive floor expectations
   from the uniform `minBody` floor (`minimumSectionHeight`). The drawer must
   now be shrinkable below the old cumulative tab height — assert that
   shrinkability explicitly (resize to the section minimum, expect the body
   to follow instead of clamping at the tab stack).
2. `painting.cpp:404-409`: active tab asserts `tabSelectedBackground`, idle
   tabs `tabBackground` (keys on the live `parameterAppearance` map — do NOT
   hard-code hex; read the map like the old assertions read `currentFill`).
   The 416-436 scan should still hit the underline's `selectionOutline`
   strip; adjust the rect only if the run proves otherwise.
3. Keep every other assertion in these files byte-identical in intent; if a
   helper (e.g. `drawer.cpp:67`) has no callers after the rewrite, delete it
   rather than leaving a stale floor enshrined.

## Acceptance

`grep pattern="minimumContentHeight" path="src/checks"` finds nothing;
`deno task format` on the three files; then
`deno task verify --filter=automation --verbose` and
`deno task verify --filter=drawer --verbose` both PASS — paste the raw
harness outputs (required). These are paint/layout harnesses, safe to run
headless. If a harness fails, run it once more unmodified; a twice-failing
assertion is a real finding, not flakiness — report it, do not work around it.
