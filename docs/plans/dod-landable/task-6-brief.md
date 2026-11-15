# Task 6 — Visible-range rectangles in EffectOutput

## Context
`EffectOutputPage.refreshCamera` (src/swift/app/drawer/effectoutput/
EffectOutputPage.swift:359–383) recomputes viewport-space rectangles for
EVERY output note on every camera change, and `publishScene` then scans all
rectangles again clipping most away. Restrict both to the note index range
that can intersect the viewport.

## Exact write set
- `src/swift/app/drawer/effectoutput/EffectOutputPage.swift`

## Prerequisites
None.

## Interface contract
- Determine the ordering guarantee of `output.notes` from its producers
  (grep `EffectOutput(` constructions scoped to `src/swift/app/`). If notes
  are not tick-sorted by construction, report NEEDS_CONTEXT — do not sort
  them here (indices are published row ids / selection identity).
- Precompute `maximumDuration` once when `output` is assigned (find the
  existing assignment site that also sizes `rectangles`/`fills`).
- `refreshCamera` computes a visible tick window from camera
  (`scrollX`/`pixelsPerTick`/`plotWidth`, matching the rounding already
  used), binary-searches the first index with `tick >= windowStart −
  maximumDuration`, and the end index with `tick < windowEnd`; stores that
  range (e.g. `visibleRange: Range<Int>`). Rectangles outside the range are
  not recomputed.
- `publishScene` iterates only `visibleRange` for note rects (keep the
  existing per-rect clip guard). Range band, gesture box, selection colors,
  ids (`UInt64(index)` — absolute note index) unchanged.
- Every other reader of `rectangles` (grep the file: hit-testing, drag
  selection) must be audited: either it only runs on pointer positions
  inside the plot (then restricting to `visibleRange` is equivalent) or it
  must force/refresh the range it needs. State the audit outcome per reader
  in the result. If a reader needs arbitrary off-screen rects, keep that
  reader correct by computing the rect on demand with the same formula —
  do not silently serve stale coordinates.

## Implementation steps
1. Audit `output.notes` ordering + all `rectangles` readers.
2. Add `maximumDuration` at output assignment; `visibleRange` defaulting to
   full range until first camera refresh.
3. Range-restrict `refreshCamera` rect computation and `publishScene` loop.
4. When `output` is nil or notes empty: range empty, existing nil paths
   unchanged.

## Acceptance predicate
Identical scene bytes, selection, and pointer behavior in the EffectOutput
drawer/shell checks. Controller: `build:checks` + `checks:qml` +
`checks:shell` filter for effect output if available. SHARED_TREE:
DEFERRED_TO_CONTROLLER.

## Task-specific constraints
- Do not change rectangle formulas (rounding, gap, min width) — range
  selection only.
- Do not change `EffectOutput` type or its producers.
