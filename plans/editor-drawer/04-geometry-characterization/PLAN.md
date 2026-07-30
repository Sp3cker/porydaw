# Task 04 — Characterize editor static geometry

**Blocked by:** Reviewed and integrated Task 03.

**Runtime worktree:** `04-geometry-characterization`

**Branch:** `task/editor-drawer/04-geometry-characterization`

**Target slice:** Specification implementation slice 4.

**Suggested subject:** `Characterize editor static geometry`

## Start rule

Fast-forward this clean worktree to the accepted Task 03 integration SHA and
record it as `START_SHA`.
Before editing, read the root plan, full specification, repository
instructions, and this plan in full.

## Contract

Own the characterization half of the Static geometry contract and **LAY-01**.
Do not migrate production geometry in this task.

## What to deliver

Focused characterization cases containing a complete inventory of:

- current automation geometry;
- shared track-header and piano-keyboard geometry;
- every consumer of the derived plot origin;
- reference drawer geometry;
- reference continuous and intrinsic velocity geometry;
- paint extents, text bounds, strokes, cull and hover slop;
- hit radii, pointer tolerances, density thresholds, and clamps; and
- derived sums, partitions, minimums, and maximums.

For every call site, record:

- semantic role;
- audited default outcome;
- current owner and consumers;
- intended named `layout` accessor or derivation;
- scaling or intentional one-unit invariance;
- the `12` and `16` base-font inputs;
- rounding and resolution order; and
- a symbol-specific reason for any non-geometry exemption.

The cases must be checked in and runnable. They are the source record Task 05
uses to build the final gate.

## Non-goals

- No production geometry change.
- No drawer or velocity UI.
- No feature-local replacement constants.
- No broad suppression or generic “number is data” exception.
- No visual redesign.

## Method

1. Characterize current integration behavior first.
2. Inspect the oracle read-only for drawer and velocity call sites not present
   on the base.
3. Classify domain numbers, indices, ratios, live metrics, and actual geometry.
4. Add tests for audited outcomes and derivations.
5. Prove the inventory covers constructors, setters, painter calls,
   comparisons, constants, aliases, hit tests, and clips.
6. Leave production source behavior unchanged.

## Verification

- The inventory has no unexplained geometry site.
- Header width plus keyboard width derives plot origin.
- Tab widths partition the header, with remainder assigned as specified.
- Minimum drawer height derives from row plus add-strip heights.
- Audit input `12`, alternate input `16`, `qRound` order, zero, and true
  one-unit hairline behavior are explicit.
- Existing builds and behavior checks remain unchanged.
- The production-source diff is empty apart from test-only exposure strictly
  required for characterization.

## Oracle review points

Compare every visual and interaction measurement needed by the spec, not only
the old pixel values listed in its table. Do not inventory excluded assets,
research scripts, theme experiments, or unrelated editor sizing changes.

## Handoff and review

Stage but do not commit. Record `START_SHA`, staged tree ID, inventory count by
component and category, uncovered-site search results, test commands and exits,
and confirmation that production geometry did not change.

The Review agent must independently inspect current and oracle call sites,
sample every category, reject weak exceptions, and confirm this task
characterizes before Task 05 refactors. Approval gates the coordinator's Task
04 commit.
