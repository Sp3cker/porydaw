# Task 3: PitchProjection value type

## Context

Consumes Task 1's seam (does not consume Task 2's interfaces; it runs
after Task 2 only because both append to the same seam files). Ports
`songview::PitchProjection` to a Swift value type: the row↔pitch mapping,
fold builds, scale classification, nearest-visible anchoring, and
DPR-snapped row edges. The C++ `pitchprojection.cpp` stays untouched as
the parity oracle. Producer for the TimeCamera epic (vertical axis) and
the roll/paint surfaces at cutover.

## Exact write set

Created:
- `src/ui/songview/quick/swift-grid-prototype/PitchProjection.swift`

Edited (append-only to the seam):
- `src/checks/swiftgridprototype/math_smoke.h` — add the four `sgm_pitch_*` oracles
- `src/checks/swiftgridprototype/math_smoke.cpp` — implement them over production `songview::PitchProjection`
- `src/ui/songview/quick/swift-grid-prototype/MathSelftest.swift` — add the `math-pitch` group

## Prerequisites

1 (seam interfaces only; sequenced after 2 by file reuse, not interfaces).

## Interface contract

- `PitchProjection.swift` exactly as spec §3: `cMaxRows`, `cHiddenRow`,
  `init()` = chromatic, `buildChromatic()`, `buildFromPitches(_:)`
  (preconditions: strictly ascending, unique, ≤ 128, each < 128),
  `visibleRowCount`, `visiblePitch(at:)`, `row(forPitch:)`,
  `setScalePitchClassification(_:)` (indexed BY PITCH),
  `isScalePitch(row:)`, `nearestVisiblePitch(to:)` (tie → lower pitch),
  `totalHeight(keyHeight:)`, `rowTop`, `rowBottom`, `yToRow`, `yToPitch`.
  Storage is Swift-native (`[UInt8]` visible pitches high-to-low, a
  128-entry pitch→row table, per-row scale flags); no fixed-size C arrays
  unless the port is clearer with them — the C++ `cMaxRows` capacity
  ceiling and O(1) lookups are the contract, not the buffer shape.
- Deferred and forbidden here: `rowRect`, `buildRowEdges`, `revision()`
  (spec §8 — composites and cache hooks return at cutover; `Equatable`
  replaces `revision`).
- `sgm_pitch_row_for_pitch`, `sgm_pitch_nearest_visible`,
  `sgm_pitch_row_top`, `sgm_pitch_y_to_pitch` (spec §4): `pitches == NULL`
  → chromatic build, else `buildFromPitches`; thin forwarding to the C++
  type from `ui/pitchprojection.h` (already compiled into
  `swift_grid_curve`).
- `MathSelftest.swift` gains the `math-pitch` group: T3 literal tables and
  the T4 pitch parity sweep.

## Implementation steps

1. Write `PitchProjection.swift`. Mirror the C++ algorithms: descending
   visible-pitch array, binary search for `nearestVisiblePitch` with the
   `<=` tie toward the lower pitch, `snappedRowEdge` with
   `.toNearestOrAwayFromZero` (spec §5/§7), `yToRow` binary search over
   snapped edges with half-open rows.
2. Extend `math_smoke.h`/`.cpp` with the four oracles; each call
   constructs the C++ projection (chromatic or folded) and forwards.
3. Extend `MathSelftest.swift`: T3 literals (chromatic, folded [60,64,67],
   empty fold, DPR edge cases including the 2.5 → 3 rounding-mode probe),
   then the T4 parity sweep (full 0–127 and −2…129 sweeps, the three fold
   sets, the keyHeight × scrollY × dpr × row grid).
4. Run the acceptance check.

## Acceptance predicate

Every T3 literal holds in Swift; Swift and the production C++ oracle agree
on all T4 pitch queries (row mapping, nearest-visible including tie and
range clamp, DPR-snapped edges under every dpr in the grid, yToPitch
boundaries); tick and time-axis groups still pass; grid/audio/interaction
smokes unchanged. Named checks (implementer runs):

- `deno task prototype:swift-grid --smoke`

Covers: chromatic ctor defaults, fold preconditions and reversal,
cHiddenRow paths (out-of-domain pitch, hidden pitch, empty build, y
outside content), lower-pitch-wins ties, by-pitch scale classification
indexing, half-away-from-zero DPR edge rounding (the 1.25/2 case
distinguishes it from to-nearest-or-even), top-edge-inclusive/half-open
row hit tests. Compile-only fallback:
`deno task prototype:swift-grid --build-only`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk
named: Swift's default `rounded()` IS to-nearest-or-away-from-zero, but
`.toNearestOrEven` compiles just as happily — the 2.5 tie case is the only
guard; keep it first in the edge table. Precondition failures
(`buildFromPitches` with unsorted input) must crash in both debug and
release (`precondition`, not `assert`) — C++ release builds silently read
garbage; Swift fails loud, and that is the intended strictness delta.
Do not port `QRectF`-returning helpers or Qt types.
