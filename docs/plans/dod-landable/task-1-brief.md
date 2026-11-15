# Task 1 — Bulk-merge `MidiChunk.apply` insertion phase

## Context
`MidiChunk.apply` (src/swift/core/MidiFile.swift, `extension MidiChunk`)
already slides survivors over removals in one pass, but then inserts each
new event with `events.insert(event, at: target)` — one tail shift per
insertion, O(insertions × events) for grouped note moves/pastes/time edits.
Replace the insertion phase with a single build of the final array that
produces byte-identical order and identical `ApplyResult` offsets.

## Exact write set
- `src/swift/core/MidiFile.swift` (body of `apply(removing:inserting:)` only)

## Prerequisites
None.

## Interface contract
- Signature, `ApplyResult`, `insert(_:)`, and all doc-comment semantics
  preserved verbatim, including: removals ignored when out-of-range/repeated;
  insertions processed in (tick, caller-order); each insertion lands in its
  tick run per the pin rule (channel type ≥ 0xB after last not-note-class,
  note ends after last not-note-on, others at run end); `inserted` result
  list stays in processing order with INSERTION-TIME offsets in evolving-array
  coordinates (corrected ruling: `DocumentChangeSet.applyEvents` replays
  insertions in recorded/reverse order, so offsets must match the array state
  at each insertion moment, not final positions); `endTick` update
  unchanged.
- The existing doc comment's cost paragraph ("One algorithm, no strategy
  bound…") must be updated to describe the new algorithm truthfully (≤2 lines
  more than current).

## Implementation steps
1. Keep the removal slide exactly as is.
2. Insertion phase: group the sorted insertions by tick. For each tick group,
   take the survivor tick run as a small local array and replay the CURRENT
   incremental pin logic within that local run (same target computation,
   including how inserted events update `lastNotNoteClass`/`lastNotNoteOn`,
   but in run-local coordinates). Insertion targets never leave the run, so
   run-local replay is equivalent to the current global inserts.
3. Assemble the final `events` in one pass: survivors before the run, merged
   run, survivors between runs, … with one `reserveCapacity`. Record each
   inserted event's offset at replay time as runStart + (insertions from
   earlier tick groups) + local target; return `inserted` in the same
   processing order as today.
4. No `events.insert` in the insertion phase. Local run arrays may use
   `insert` (bounded by run+group size).
5. Preserve behavior when insertions is empty, when a tick has no survivor
   run, and when insertions precede/follow all survivors.

## Acceptance predicate
Behavior identical to current implementation for all inputs (resulting
`events`, `endTick`, `ApplyResult.removals`, `ApplyResult.insertions`).
Controller: `build:checks` + `checks --filter swiftcore` (note/history/time
edit suites exercise apply through every grouped edit). SHARED_TREE:
implementer reports DEFERRED_TO_CONTROLLER.

## Task-specific constraints
- Equal-tick pin order is NOT a sort key (0xA is unordered against both note
  classes; see comment at `precedesAtSameTick`). Do not replace pin logic
  with a comparator sort.
- `DocumentChangeSet` offset replay is out of scope; do not touch it.
