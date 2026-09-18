# Task 4: Edit-key policy dimensions (ported selectionkey matrix)

## Context

The frozen policy table (Task 3) is inert data until a routing layer
consumes it. Production's consumer is `SongView::handleEditKey`
(`editkeyrouting.cpp`): ordered gates — unbound decline, pointer-gesture
guard, origin rules, then the `keyRoute` switch with auto-repeat,
unavailable-ownership, and terminality decisions. This task ports those
policy branches as the Swift resolver (spec §3.4) and accepts it through
the six selectionkey scenario dimensions as a frozen matrix in the
prototype selftest ([spec](spec.md) §1 D5, §6.3) — the acceptance gate the wave
context demands, exercised where the Swift backend actually lives.
Consumes Task 3's `editCommandTable` and `sgp_*` seam.

## Exact write set

Created:
- `src/ui/songview/quick/swift-grid-prototype/EditKeyArbiter.swift`

Edited:
- `src/ui/songview/quick/swift-grid-prototype/PolicySelftest.swift` — append the `policy-dimensions` group

## Prerequisites

Task 3 (policy table, enums, seam, selftest harness).

## Interface contract

- `EditKeyArbiter.swift` exactly as spec §3.4: `EditKeyOrigin`,
  `EditKeyDecision` (`decline`/`consume`/`execute`), `EditSurfaceState`
  (six fields; `commandAvailable` is a host-answered input — availability
  predicates are deferred, spec §8), `decide(command:surface:)`, and
  `windowActionEnabled(command:textFocused:rowAvailable:)` (the
  `liveRowEnabled` analog for the Copy/Solo deferral dimension).
- Decision rules follow `handleEditKey` statement order verbatim (spec
  §3.4 steps 1–4): nil → decline; gesture guard before origin guard;
  origin guard before keyRoute; the three keyRoute arms with
  auto-repeat, ownership, and terminality exactly as written. Target
  resolution ports `resolveSelectionTarget` (time-range precedence, then
  notes-with-timeline-origin, else none).
- Pure functions over value inputs — no PianoGrid state, no Qt, no
  singletons; the prototype does not wire them into live key delivery
  (that is the keyboard cutover, spec §8).
- `PolicySelftest.swift` gains the `policy-dimensions` group asserting
  the spec §6.3 matrix (19 frozen rows) and printing
  `SWIFT_GRID_SMOKE policy-dimensions PASS` / `… FAIL: <row>` per the
  §4 convention.

## Implementation steps

1. Write `EditKeyArbiter.swift` per the frozen interface; each decision
   rule cites its `handleEditKey` source line in a trailing comment (one
   line per rule — provenance, not transcription).
2. Append the dimension matrix to `PolicySelftest.swift`; each row names
   its selectionkey provenance (suite + scenario family) in a comment.
3. Run the acceptance check.

## Acceptance predicate

`policy-dimensions` passes all frozen rows — autoRepeat consumption
(three routes), unavailable-ownership (ownsKey consumed no-op vs decline
vs terminal), gesture survival (guard vs `survivesPointerGesture`),
origin routing (event-list/timeline declines), prompt-text deferral
(Copy yes / Solo no through `windowActionEnabled`), unbound-key
neutrality (nil command declines on every surface variant); parity and
all prior groups unchanged; final `SWIFT_GRID_SMOKE PASS` unchanged.
Named checks (implementer runs):

- `deno task prototype:swift-grid --smoke`

Covers: the resolver's ordered decision table over the Task-3 table, and
the six dimensions as observable decisions. Coverage gap, named: the
matrix exercises the Swift policy layer with synthetic surface state —
production still routes real keys through C++ `handleEditKey`; the
`selectionkey-*` suites remain the gate for the production side (Task 3's
controller gates) and are not re-claimed here. Live availability
predicates and keymap binding lookup are deferred (spec §8).

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk:
the decision order is the contract — a resolver that computes the right
answer through different gate order is a defect (production comment:
keys judge live eligibility, and ordering is observable through the
gesture/origin interplay). Do not port `editCommandAvailable` or
`keymap::Registry` (spec §8); do not wire the resolver into Main.qml.
