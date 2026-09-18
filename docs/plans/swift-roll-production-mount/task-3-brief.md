# Task 3 — Swift grid consumes the document (read-only mode)

## Context

The grid becomes able to render a real document snapshot and to be
provably inert. Consumer of Task 2's `SgdDocument`/`DocumentFeed`
contract (spec §2); producer of the `readOnly` behavior Task 4's overlay
relies on (spec §3).

## Exact write set

- `src/ui/songview/quick/swift-grid-prototype/PianoGrid.swift` —
  `readOnly` property + entry-point guards + document load.
- `src/ui/songview/quick/swift-grid-prototype/SgdDocument.swift` —
  grid-facing loader bridging `DocumentFeed` results into `GridNote`s
  (file created by Task 2; this task extends it; single writer across
  both is enforced by the Task 2 checkpoint).
- `src/checks/swiftgridprototype/grid_smoke.cpp` (+ `grid_smoke.h` if a
  seam function is added) — new read-only rows.

## Prerequisites

Task 2 (`SgdDocument`, `DocumentFeed.apply` semantics).

## Interface contract

- `PianoGrid.readOnly: Bool = false` with the exact spec §3 behavior
  matrix: mutation entries inert (draw/move/resize commit paths,
  controller edits, pitch editor opening, menu actions); pan, zoom,
  hover, raster, rendering unchanged; `GridUndo` never records;
  `escapePressed` resolves but every teardown branch no-ops.
- `PianoGrid.loadDocument(_ document: SgdDocument, trackIndex: Int)`:
  replaces the note set with `document.notes` filtered by `trackIndex`,
  rebuilds the scene once, leaves zoom/scroll untouched, bumps an
  internal `loadedRevision` used by `DocumentFeed` auto-apply when a
  `loadDocument` has happened (the grid does not auto-subscribe before
  first load).
- Documented invariant in-code: `readOnly == true` ⇒ no code path mutates
  `notes`, `controllerEvents`, undo state, or selection-clearing side
  effects beyond rendering.

## Implementation steps

1. Add `readOnly` guards at the entry points listed in spec §3 — guards
   return early; they do not fake success or emit changes.
2. Implement `loadDocument` mapping `SgdNote` → `GridNote` fields
   (key/onTick/duration/velocity; track filtering; tick-space identity —
   no re-quantization).
3. Wire `DocumentFeed` delivery: after a `loadDocument`, later snapshots
   for the same `documentId` with higher `revision` re-load the filtered
   track automatically (the Task 4 refresh path).
4. Smoke rows (prototype lane): (a) `readonly-blocks-draw-and-move` —
   with `readOnly`, press/move/release and double-click produce zero note
   delta and zero undo entries; (b) `readonly-pan-zoom-alive` — wheel
   zoom and drag pan still change viewport metrics; (c)
   `document-load-filters-track` — C++ harness side pushes a synthetic
   `SgdDocument` (two tracks, distinct notes) through `sgd_` with Swift
   registered; `loadDocument(trackIndex: 1)` renders exactly track 1's
   notes; a higher-revision delivery for the same id updates counts.

## Acceptance predicate

- `deno task prototype:swift-grid --smoke` green with the new rows and
  every existing row outcome unchanged.
- `deno task verify --filter swiftdocfeed --verbose` still green (Task 2
  regression).

## Task-specific constraints

- No edits to `GridGeometry.swift` or Wave-1 math files.
- The prototype's fixture/demo loading path stays intact and default;
   `loadDocument` is additive.
- Do not gate UI affordances (cursor shapes etc.) on `readOnly` beyond
  what spec §3 names — inertness is the contract, not visual disablement.
