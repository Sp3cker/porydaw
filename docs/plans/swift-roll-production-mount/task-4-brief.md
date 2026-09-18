# Task 4 — Gated production mount + integration harness

## Context

Mount the real read-only grid using QtBridge's QML-owned nonvisual model and
existing visual canvas, not an invented Swift QQuickItem or proxy accessor.
Read [plan.md Global Constraints](plan.md) and [spec.md §4](spec.md).
Task 1 supplies the approved public registration API; Tasks 2/3 supply the
per-feed value handshake and read-only document rendering.

## Exact write set

- `src/ui/songview/quick/timelinequickview.h`, `timelinequickview.cpp`, and
  `timelinequickview_window.cpp`: mount and the actual `detachWindow()` /
  transferred-window lifecycle owner; no unrelated window/input rewrites.
- `src/ui/songview/quick/swiftgrid/grid_host.h` (new): sole registration ABI.
- `src/ui/songview/quick/swift-grid-prototype/SwiftGridHost.swift` (new):
  one-time `sg_register_grid_types` implementation.
- `src/ui/songview/quick/swift-grid-prototype/SwiftRollOverlay.qml` (new):
  nonvisual model creation plus visual roll renderer and viewing input.
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt`: only add the
  host Swift source to the explicit production list and qrc embedding of
  overlay plus its existing local QML renderer dependencies. Task 1 owns
  import/link/ABI compilation setup; do not duplicate it here.
- `src/checks/swiftrollgated/` (new harness directory),
  `src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`,
  `src/checks/fwd.hpp`: APPLE-only production integration registration.

## Prerequisites

Task 1's `swiftgrid` / `SwiftGrid` module, public
`QmlInstantiable.registerQmlElement()` patch, and production linkage;
Task 2's per-token routing ABI and observer; Task 3's QML completion binding
and read-only grid. No private/package QtBridge access remains necessary.

## Interface contract

Spec §4 fixes the sole `void sg_register_grid_types(void)` C entry point,
QML properties, full-width token string, component-completion binding,
ownership and ordered mount/teardown. `PianoGrid` remains a QObject model;
`SwiftRollOverlay.qml` is the visual item. QML/QtBridge owns model retention
and release; no `SgGridHandle`, custom retain/factory or proxy extraction.

Use the existing `m_quickView->engine()` / `m_view` QQuickView and ordinary
`QQmlComponent::createWithInitialProperties`; no `quickEngine()` API exists.
Overlay exposes read-only `noteCount` and a decimal-string applied revision
for harness observation without narrowing UInt64 through QML numbers.
Canonical roll-band geometry/visibility remains host-owned. Track changes
set the overlay's selected-track value; Swift re-filters the current accepted
snapshot. Flag off allocates/registers no Swift mount state.

## Implementation steps

1. Implement one-time type registration through the Task 1 public API. Add
   source/resource registration only in the existing target section; include
   the existing visual renderer components and their local dependencies so
   the production binary needs no source tree. The module name in both lanes
   is `SwiftGrid`; load `import SwiftGrid 1.0` after registration.
2. Implement spec §4's ordered mount. Feed endpoint exists before QML creation;
   component completion binds the model's receiver; host verifies a nonnull
   callback and explicitly calls `pushSnapshot()` after visual setup. If
   component creation/binding fails, report the error and unwind all partial
   state, never show demo data or silently substitute the old renderer.
3. Build an opaque, clipped roll overlay with ordinary QtObject `gridModel`
   and existing visual canvas. Host/QML handles pointer grabs and normalized
   viewing input: pan/zoom/hover remain live, mutation gestures are absorbed,
   nothing reaches the underlying editor, no focus acquisition or key
   listener/Shortcut is added. Keep window/engine/document objects out of Swift.
4. Integrate cleanup at the actual `detachWindow()` and externally destroyed
   transferred-window paths in `timelinequickview_window.cpp`: disconnect track
   forwarding and observer, clear/unregister/destroy feed before deleting QML.
   Handle partial mount and repeated teardown; QML-owned model destruction
   releases receiver/snapshot with no retained callback or closed document.
5. Register `swiftrollgated`: boot real `WorkspaceUi` with flag set before
   construction; assert initial selected-track rendering without edits,
   track-follow, edit/undo/redo refresh, non-24/signature geometry, no mutation
   or focus change on editing input, and real viewport/hover changes. Open two
   documents, interleave updates and track changes, close one and update the
   other; remount gets a fresh binding. Exercise transferred-window teardown
   and a flag-off row. Inspect the actual mounted renderer, not a duplicate
   Swift test grid.

## Acceptance predicate

- `deno task build:app` — production registration, resources and observer link.
- `deno task verify --filter swiftrollgated --verbose` — actual mounted surface,
  concurrent-document isolation, real input and ordered lifecycle.
- `deno task verify --filter selectionkey-core --filter rollcheck-static --verbose`
  — unchanged host arbitration and production geometry oracle.
- Final controller gate also runs
  `deno task verify --filter swiftdocfeed --verbose` and
  `deno task prototype:swift-grid --smoke` per plan verification policy.
  Native desktop is required for interactive/rendering checks.

## Task-specific constraints

Preserve the existing one-way `takeWindowForEmbedding()` ownership transfer
and canonical layout. No key routing, undo crossing or band-contract changes.
Do not delete/disable shipping C++ roll code: read-only mount does not satisfy
its charter retirement gate. No root CMake ownership duplication.
