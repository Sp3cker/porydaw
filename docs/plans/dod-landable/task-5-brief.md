# Task 5 — Block-max-end index for roll note culling

## Context
`RollPlotBuilder.build` culls notes by binary-searching tick-sorted
`records` from `lo − maxDuration` (RollPlotBuilder.swift:264–295). One long
note makes `maxDuration` huge, so every frame scans (and order-sorts) far
more candidates than are visible. Add a flat block index: fixed-size blocks
over the sorted records, each storing the block's maximum `end`; culling
skips whole blocks that cannot intersect the viewport.

## Exact write set
- `src/swift/app/roll/RollDisplayLists.swift` (build the index in `resolveNotes`)
- `src/swift/app/roll/RollPlotBuilder.swift` (consume it in the cull)
- `src/swift/app/roll/GridScene+Notes.swift` (retain + plumb it)

## Prerequisites
None (self-contained producer/consumer change).

## Interface contract
- Block size: 128 records. Index: `[Int]` of per-block max `end`, retained
  next to `noteRecords` (e.g. `noteRecordBlockEnds`), rebuilt exactly when
  records are rebuilt, capacity retained across builds like `noteRecords`.
- `resolveNotes` fills the index for the records it produces (records are
  tick-sorted on exit, as today). `noteRecordsMaxDuration` is removed if no
  other consumer exists — grep its uses first; if another consumer exists,
  keep returning it and say so in the result.
- `RollPlotBuilder.build` takes the block index instead of (or in addition
  to, per the grep) `maxDuration`. Painted output must be identical: same
  visible set, same order sort by `record.order`, same emitted rects/labels,
  same `count`.
- Camera-only path (`rebuildDisplayLists`) reuses the retained index; no
  recomputation per camera frame.

## Implementation steps
1. `resolveNotes`: after the sort, fill block max-ends in one pass.
2. Builder cull: iterate blocks; skip a block when its max end shows no
   record in it can satisfy `end >= lo` (same `lo` definition incl. slack
   and `noteMinWidth`), stop when the block's first record tick `>= hi`.
   Within a candidate block apply the current per-record tests unchanged.
   Keep the `ppt <= 0` fallback path behavior (all records, order-sorted).
3. Edge cases: zero records, single partial block, unterminated/huge `end`,
   records ending exactly at `lo` (current test is `>= lo` on end — match
   it), block boundary at `hi`.

## Acceptance predicate
Byte-identical display lists for the roll QML checks incl. long-note,
ghost, displaced, and folded cases. Controller: `build:checks` +
`checks:qml-roll`. SHARED_TREE: DEFERRED_TO_CONTROLLER.

## Task-specific constraints
- Do not change paint order rules, ghost pass order, or the order sort.
- `records` layout (`RollNote`) unchanged.
- Sovereign constants: block size is a single named constant, not scattered.
