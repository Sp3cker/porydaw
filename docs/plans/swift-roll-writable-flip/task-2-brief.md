# Task 2 — `sgs_` session seam + `sgd_` NoteId amendment

## Context

Delivers host-owned session state (selection, masks) to Swift and gives
every note its stable identity in the document feed. Consumer of
`EditorSelectionModel`'s observer; producer of the state Tasks 3–5 read.
Semantics FIXED in [spec.md §3](spec.md).

## Exact write set

- `src/ui/songview/quick/swiftgrid/session_feed.{h,cpp}` (new) — C ABI
  push: `SgsSessionState` (primary track, scope mask, note-selection
  token array, time selection, mute/solo masks, session revision) +
  `SwiftGridSessionFeed` QObject wiring `EditorSelectionModel::setObserver`
  and `SongView` mask signals.
- `src/ui/songview/quick/swiftgrid/document_feed.h` — the one sanctioned
  Wave-3 amendment: `SgdNote` gains `uint64_t noteId` (raw
  `NoteId::m_token`; document-scoped, never persisted to MIDI).
  `document_feed.cpp` populates it; nothing else in `sgd_` changes.
- `src/ui/songview/quick/swift-grid-prototype/SgdDocument.swift` (single
  writer, post-Wave-3) — mirror field + `SgsSession` structs.
- `src/checks/swiftdocfeed/` extension rows.

## Prerequisites

Wave 3 final gate green (this task edits the frozen `sgd_`; only after
the Wave 3 checkpoint commits).

## Interface contract

- Push source order: selection transitions (`SelectionTransition`),
  mask signals, both coalesce into one `SgsSessionState` shape; pushes
  are complete-state, not deltas.
- Reconciliation stays host-side: pushes after undo/redo/remap reflect
  `reconcileNoteSelection`/`applyRemap` results; vanished tokens simply
  absent from the next push.
- `SongView`-scoped lifetime: feed constructed with the view, destroyed
  before the document. No delivery after destruction.

## Implementation steps

1. ABI per spec §3; Swift mirrors with `Sendable` plain values.
2. Wire observer + signals into complete-state pushes on the GUI thread.
3. Amend `SgdNote` + populate from the document's note records.
4. Harness rows: transition payload correctness (set/clear/extend via
   the model's own API), mask round-trip, post-undo reconciliation
   (tokens that died), stale-token intent ⇒ `rejectedInvalid` once
   Task 1 lands (coordinate via the Task-1 checkpoint if ordering slips).

## Acceptance predicate

- `deno task verify --filter swiftdocfeed --verbose` green (extended).
- `deno task build:app` + canaries green.

## Task-specific constraints

- `EditorSelectionModel` and `SongView` are read-only consumers' sources;
  no edits to them — the feed observes.
- No Swift-side selection retention: state lives only inside an applied
  snapshot; the next push replaces it wholesale.
