# Task 2: TimeMap + TimeAxis value type

## Context

Consumes Task 1's seam (`sgm_*` ABI, `MathSelftest.swift`, module map).
Ports `songview::TimeAxis` to a Swift value type over a copied `TimeMap`
(no `MidiTimeline*` borrow, no `isBound` — spec §1 D2, §2). Producer for
the TimeCamera epic (feed contract spec §8) and, transitively, Grid.
The C++ `timeaxis.cpp` stays untouched as the parity oracle.

## Exact write set

Created:
- `src/ui/songview/quick/swift-grid-prototype/TimeAxis.swift`

Edited (append-only to the seam):
- `src/checks/swiftgridprototype/math_smoke.h` — add `sgm_timeaxis_answer`, `sgm_timeaxis_grid_lines`
- `src/checks/swiftgridprototype/math_smoke.cpp` — implement both over production `songview::TimeAxis`
- `src/ui/songview/quick/swift-grid-prototype/MathSelftest.swift` — add the `math-timeaxis` group

## Prerequisites

1 (seam interfaces only).

## Interface contract

- `TimeAxis.swift` exactly as spec §3: `TimeSigPoint`, `TimeMap`,
  `GridSegment`, `ResolvedTimeSignature`, `TimeAxis` with
  `init(map: TimeMap = TimeMap())`, the five scalar properties,
  `hasImplicitOpeningSignature`, `signatureAt`, `segmentAt`,
  `forEachGridLine(from:to:_:)`. All §5 contract notes are normative:
  `max(1, tpb)` clamp; blank numerator → 4; last same-tick wins;
  `beatTicksFor = max(1, (UInt64(tpb) * 4) >> min(Int(denomPow2), 31))`;
  raw `denomPow2` preserved in `signatureAt`; unbound ≡ default map;
  half-open walk range with below-range beat skipping, `isBar`, and bar
  carry `bar += ceil(segTicks / barTicks)` including partial measures.
- `sgm_timeaxis_answer(map, tick, out)`: binds a stack-constructed
  `MidiTimeline` (public fields filled from `SGTimeMapFixture`) to a
  `songview::TimeAxis` and fills every `SGTimeAxisAnswer` field.
- `sgm_timeaxis_grid_lines(map, begin, end, out, capacity)`: walks
  `forEachGridLine`, writes at most `capacity` entries, returns the full
  needed count (spec §4 convention).
- `MathSelftest.swift` gains the `math-timeaxis` group: fixtures F0–F8 as
  literals (spec §6 T2) and the T4 time-axis parity sweep.

## Implementation steps

1. Write `TimeAxis.swift`. Port the walk's arithmetic in `UInt64` per spec
   §7; mirror `timeaxis.cpp`'s loop structure (prologue consumes tick-0
   duplicates; per-segment overwrite loops; the `beatTicks >= clampedEnd -
   tick` advance guard) rather than inventing a segment-list copy.
2. Extend `math_smoke.h`/`.cpp` with the two oracles; the fixture →
   `MidiTimeline` field copy stays in the C++ oracle (Swift never sees
   `MidiTimeline`).
3. Extend `MathSelftest.swift`: literal tables first (fail before parity
   so a port bug is attributed to Swift, not the ABI), then the parity
   sweep over the spec §6 T4 tick set and walks.
4. Run the acceptance check.

## Acceptance predicate

Every F0–F8 literal holds in Swift; Swift and the production C++ oracle
agree field-for-field on `sgm_timeaxis_answer` across all fixtures × ticks
and element-for-element on every T4 walk (counts included); tick group from
Task 1 still passes; grid/audio/interaction smokes unchanged. Named checks
(implementer runs):

- `deno task prototype:swift-grid --smoke`

Covers: all §5 TimeAxis contracts (fallback, zero-TPB clamp, implicit
opening, last-wins at tick 0 and mid-song, blank numerator, denominator
clamp with raw exponent preservation, 7/8 rescale, loop/length passthrough,
partial-measure bar carry, half-open/skip edges) plus live divergence
detection beyond the literals. Compile-only fallback:
`deno task prototype:swift-grid --build-only`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk named:
the bar-carry ceil and the same-tick overwrite loops are where a "cleaner"
rewrite diverges (bar renumbering at seams, first-wins) — F2/F3/F8 pin
exactly these; do not adjust literals. `MidiTimeline` fixtures must fill
viewer fields only (`ticksPerBeat`, `lengthTicks`, `loop*Tick`,
`timeSigs`); constructing events or tempo maps is out of scope. Do not add
caching, `isBound`, or mutation to the value type.
