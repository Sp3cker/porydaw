# Task 5: Grid snapping and bounded iteration

## Context

Consume Task 1's floating conversion. Fix both the conversion ceiling and the integer arithmetic that remains unsafe even for valid input. The prior plan's exclusion of coarse `lo + g` overflow is removed. The complete result policy is in [Grid boundary behavior](spec.md#grid-boundary-behavior).

## Exact write set

- `src/ui/songview/detail.h`
- `src/ui/songview/grid.cpp`
- `src/checks/rollcheck/static/camera.cpp`

## Prerequisites

1: `CoreTimeDefaults::tickFromDouble`.

## Interface contract

Keep `forEachSubGridLine`'s template signature and visitor contract, and all three `Grid::snapTick*` signatures. Ordinary lattice positions, fractional ties, and signature-boundary snapping remain unchanged. No snapped result is reserved or wrapped; the final upper candidate saturates at the specified terminal position.

## Implementation steps

1. In `forEachSubGridLine`, validate the first ceiling-aligned candidate before narrowing or adding it to the segment start. If no candidate belongs to the half-open segment intersection, skip its inner walk. Preserve the existing segment traversal and visibility threshold.
2. Make every inner advancement use the TimeAxis break-before-increment pattern. Restructure beat-line omission so it skips only the callback; no `continue` may bypass advancement or its guard. Keep the running position Tick rather than a wide stride with narrowing at every callback.
3. Give `snapTick`, `snapTickDown`, and `snapTickUp` the fraction-preserving entry clamp from the spec. Use `tickFromDouble` for the fine branch's rounded result, not for raw nearest-snap input.
4. Bound the coarse upper-candidate addition itself in nearest/up snapping using headroom before addition. Cap against the real segment end and valid terminal position. Preserve the coarse lower calculation and fractional tie comparison where already safe; do not retain `std::min(lo + g, seg.next)` with a wrapping addition.
5. Extend `PianoRollStaticTest::tickRangeWalksFractionalLattice` with near-ceiling iterator/snap scenarios using the existing fixture. Cover a non-dividing grid, a first aligned candidate already outside the range, a beat-line first candidate, the last advancement, fractional points on both sides of a nearest tie, a signature seam, coarse up/nearest at the ceiling, and fine rounding beyond it. Exercise NaN/infinities as snap inputs. Compare exact in-range callback sequences with independently bounded expectations, not just a nonempty result. Bound failure handling so the old wrap path does not accumulate billions of callbacks; a callback can abort the test walk on an out-of-range tick while the existing harness timeout bounds a missing-advancement hang.

## Acceptance predicate

The iterator terminates without out-of-range callbacks, including first-candidate and beat-skip paths; all snap variants follow the bounded candidate policy and preserve ordinary fractional ties. The new boundary cases exercise the real grid implementation. Named checks:

```sh
deno task verify --filter rollcheck --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not use `detail::tickRange` as a scalar conversion helper or edit `detail.cpp`. Do not truncate the raw fractional snap input, preserve a wrapped candidate as “pre-existing behavior,” or build a second grid traversal abstraction. Necessary one-time wide candidate arithmetic is not cast scaffolding.
