# Task 4 — Gated production mount + integration harness

## Context

The wave's deliverable: with `PORYDAW_SWIFT_ROLL=1`, the production
`TimelineQuickView` window hosts the Swift roll overlay rendering the
real document (spec §4). Consumer of Task 1's `swiftgrid` target and
Task 3's read-only grid. Qt-heavy: item parenting inside the embedded
production window, engine type registration, lifecycle under
`takeWindowForEmbedding()`/`detachWindow()` — reviewed by qt-cpp-reviewer.

## Exact write set

- `src/ui/songview/quick/timelinequickview.h` / `timelinequickview.cpp`
  — mount point (flag read, overlay load, feed construction, teardown).
- `src/ui/songview/quick/swift-grid-prototype/SwiftRollOverlay.qml`
  (new) — overlay component.
- Root `CMakeLists.txt` or the Task 1 target section — qrc embedding of
  `SwiftRollOverlay.qml` into `swiftgrid`.
- `src/checks/swiftrollgated/` (new dir) + the three registration points
  (`src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`,
  `src/checks/fwd.hpp`).

## Prerequisites

Task 1 (`swiftgrid` target linked into `porydaw`), Task 3 (`readOnly`
grid + `loadDocument` + feed auto-apply).

## Interface contract

- Mount: in `TimelineQuickView`'s window-setup path, when
  `qEnvironmentVariableIsSet("PORYDAW_SWIFT_ROLL")` and `APPLE`: load
  `SwiftRollOverlay.qml` through the window's existing `QQmlEngine`
  (`quickEngine()`), parent to `contentItem`, position/size bound to the
  roll band geometry the scene already computes, above the C++ roll
  painting, opaque background.
- Overlay properties: `noteCount` (int, read-only, exposed for the
  harness), tracks the `SongView::selectedTrack` via
  `selectedTrackChanged(int)` and re-filters (calls `loadDocument` with
  the new track index from the applied snapshot).
- Feed: construct `SwiftGridDocumentFeed` on the `SongDocument` the view
  renders at mount; destroy at teardown; ordering with
  `detachWindow()` idempotent — no delivery after destruction.
- Input: overlay `focusPolicy: Qt.NoFocus`, pointer events accepted and
  discarded; nothing forwards into the C++ scene beneath (the C++ roll
  band's input item is NOT covered by the overlay's event handling —
  the overlay sits above and consumes; no key events are listened to).
- Flag off: no component load, no feed construction, no measurable
  startup cost beyond the linked library.

## Implementation steps

1. Add the mount point in the window-setup path; keep it a single
   coherent block (flag check → engine load → geometry bind → feed
   construct → initial `loadDocument`), no scattering into band code.
2. `SwiftRollOverlay.qml`: minimal — a container instantiating the grid
   component from the linked Swift types with `readOnly: true`, sized by
   its parent, `SwiftGridDocumentFeed` wiring done from C++ via
   context properties or the registered types (follow the existing
   production QML context conventions; do not invent a second context
   object).
3. qrc-embed the overlay in the `swiftgrid` target so the production
   binary is source-tree-independent.
4. Harness `swiftrollgated` (spec §5 last block): boot `WorkspaceUi` with
   `qputenv("PORYDAW_SWIFT_ROLL", "1")` before window construction, open
   the staged fixture song, assert overlay present, `noteCount` equals
   the fixture's selected-track note count, `selectedTrackChanged`
   re-filters (count changes to the other track's count), a C++-side
   document mutation bumps the overlay revision, pointer press on the
   overlay leaves document revision and focus unchanged. One negative
   row: without the flag, no overlay exists and behavior matches
   production canaries.

## Acceptance predicate

- `deno task verify --filter swiftrollgated --verbose` green (native
  desktop session required).
- `deno task verify --filter selectionkey-core --filter rollcheck-static
  --verbose` green (production regression).
- `deno task build:app` green.
- Controller final gate (whole plan): the two above plus
  `deno task verify --filter swiftdocfeed --verbose` and
  `deno task prototype:swift-grid --smoke`.

## Task-specific constraints

- `timelinequickview` edits are additive around the existing setup path;
  do not reorder existing window/scene setup. If the mount cannot be
  expressed additively, escalate — the embed path is
  `takeWindowForEmbedding()`-transferred ownership; wrong parenting is
  the exact failure class this seat exists to catch.
- No key routing, no ShortcutOverride interaction, no band-contract
  changes (read-only scope lock, plan Global Constraints).
- Do not delete or disable any C++ roll code — the C++ roll remains the
  shipping surface; the overlay is additive.
