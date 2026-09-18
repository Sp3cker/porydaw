# Task 2 — `sgd_` document feed seam + revision guard

## Context

The seam that carries real `SongDocument` data into Swift as copied
values (charter S-2). Producer of the ABI that Task 3 consumes and Task 4
instantiates. ABI and delivery semantics are FIXED in
[spec.md §2](spec.md) — implement the contract, do not redesign it.

## Exact write set

- `src/ui/songview/quick/swiftgrid/document_feed.h` (new) — the C ABI of
  spec §2, verbatim.
- `src/ui/songview/quick/swiftgrid/document_feed.cpp` (new) —
  `SgdDeliveryFn` storage + `sgd_set_delivery`/`sgd_clear_delivery`.
- `src/ui/songview/quick/swiftgrid/swift_grid_document_feed.{h,cpp}`
  (new) — `SwiftGridDocumentFeed` QObject.
- `src/ui/songview/quick/swift-grid-prototype/SgdDocument.swift` (new) —
  Swift mirror structs + delivery registration + monotonic guard (Swift
  sources live only under the prototype dir; build-GLOB constraint).
- Harness: `src/checks/swiftdocfeed/` (new dir, sources per repo harness
  conventions) + the three registration points
  (`src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`,
  `src/checks/fwd.hpp`).

## Prerequisites

None (parallel with Task 1; disjoint files).

## Interface contract

- `SwiftGridDocumentFeed`: constructor takes `const SongDocument &`;
  connects `&SongDocument::documentChanged`; on emission builds the
  snapshot (all tracks' notes with `trackIndex`, all time signatures,
  header from `revision()` and the `documentState` identity value) and
  invokes the registered `SgdDeliveryFn` on the GUI thread. Destructor
  disconnects. No other public surface.
- `SgdDocument.swift` exposes: `struct SgdDocument` (header + notes +
  signatures, `Codable`-free plain values), a singleton `DocumentFeed`
  with `apply(header:notes:signatures:) -> Bool` implementing the §2
  monotonic guard, and a registration call mirroring the `sgw_` pattern
  (a Swift trampoline registered through `sgd_set_delivery`).
- Snapshot arrays are copied by Swift before the callback returns.

## Implementation steps

1. Write `document_feed.h` exactly per spec §2 (types, names, signature).
2. Implement delivery storage + the QObject feed. Notes iterate the
   document's tracks in track order; `trackIndex` is the document track
   index; `onTick`/`durationTicks` in document tick space; `key`/`
   velocity` from the note values the C++ roll reads today.
3. `SgdDocument.swift` with the guard; registration from Swift via a
   `@_cdecl("sgd_swift_register_feed")`-style trampoline is NOT used —
   Swift registers by calling `sgd_set_delivery` with a C function
   pointer over a context token (the `sgw_` pattern; no C++→Swift
   linkage).
4. Harness `swiftdocfeed`: build a `SongDocument` from a staged fixture
   `.mid` via the same import path core checks use; register a capture
   callback; assert spec §5 first block: initial snapshot contents
   (counts + sampled note fields + time signatures), then apply one
   mutation, one undo, one redo through the document's public edit API —
   each delivers exactly once with `revision` +1; deliver a fabricated
   stale header (same id, lower revision) — dropped; new `documentId` —
   applies.

## Acceptance predicate

- `deno task verify --filter swiftdocfeed --verbose` green (native
  desktop session required).
- `deno task build:app` green (new TUs compile; harness registration
  compiles into `porydaw_checks`).

## Task-specific constraints

- No edits to `SongDocument` or `src/core/**` — the feed is a pure
  observer.
- If `SongDocument` lacks a public accessor needed for identity or note
  iteration, escalate; do not widen `src/core` in this task.
- Harness fixtures: reuse the staging pattern from
  `src/checks/checkcatalog.cpp` selectionkey entries (`{scratch}` +
  fixture names); pick one existing fixture song (e.g. `mus_route101`).
