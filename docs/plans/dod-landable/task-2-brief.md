# Task 2 — Occupied-bitset held storage in `LiveInsert`

## Context
`LiveInsert` (src/swift/pluginhost/LiveInsert.swift) keeps `held` and
`outputHeld` as `InlineArray<4096, …>` and linearly scans all 4096 slots in
`remember`, `forget`, `flush`, `chase` emission, and `outputID` (both
branches) — per live note, in the audio callback path. Add occupied bitsets
so allocation is first-clear-bit and iteration touches only occupied slots,
with bit-identical observable behavior.

## Exact write set
- `src/swift/pluginhost/LiveInsert.swift`

## Prerequisites
None.

## Interface contract
- No signature changes outside the file. All private helpers keep names and
  semantics: `remember` first-fit lowest free slot; `forget(id:pitch:)`
  clears the lowest-index matching slot; `flush` emits note-offs in
  ascending slot order then clears all output held; `chase` emits held
  note-ons in ascending slot order; `outputID` on-branch first-fit, off-branch
  returns the OLDEST (minimum `order`) matching held output (explicit-ID
  match when `event.note_id > 0`, pitch match otherwise), pitch write-back
  unchanged; overflow accounting (`inputOverflow`, nil return) unchanged.
- Storage stays fixed-capacity inline; no heap allocation, no locks added.

## Implementation steps
1. Add two occupied bitsets (`InlineArray<64, UInt64>` each: held, output)
   with small private helpers: first-clear-slot, set, clear, and ascending
   iteration over set slots (word scan + `trailingZeroBitCount`).
2. `remember`/`outputID` on-branch: allocate via first-clear-bit (identical
   slot choice to current first-fit scan). Full → same failure results.
3. `forget`/`outputID` off-branch: scan occupied slots only, same winner
   (lowest index for `forget`; minimum `order` for `outputID`).
4. `flush` and `chase` emission: iterate occupied slots ascending (same
   emission order); clears update bitsets; the `outputHeld` full reset in
   `flush` clears only occupied slots and zeroes the bitset.
5. Every existing write to `held[i]`/`outputHeld[i]` that changes occupancy
   must go through set/clear so bitsets can never diverge. Grep the file for
   all such writes (including `processRender`/chase failure paths that clear
   a slot after failed emit).

## Acceptance predicate
Identical wire event sequences and overflow counts for all paths.
Controller: `build:checks` + `checks --filter swiftcore` (LiveInsertChecks)
plus pluginhost suites if separately filtered. SHARED_TREE: DEFERRED_TO_CONTROLLER.

## Task-specific constraints
- Explicit plugin IDs are arbitrary Int32; do not index storage by ID.
- Duplicate (id,pitch) held inputs remain possible; `forget` removes exactly
  the same (lowest-index) entry as today.
- `chase`'s timeline prefix scan is out of scope (Task 3 territory).
