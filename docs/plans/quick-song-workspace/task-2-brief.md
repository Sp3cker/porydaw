# T02 — Make SongView layout follow its item viewport

## Context

`SongView::resolveViewportGeometry()` currently reads the per-song
`QQuickWindow` size. With task 1's borrowed scene, layout must follow the
attached viewport item so translated/clipped pages keep correct band geometry,
hit tests and cameras per [spec.md](spec.md) S7. Consumes task 1's
`viewportItem()`, `isInputEligible()`, `detachScene()` and `viewportChanged()`
contract; produces the association-bound `AutomationPage::setInputWindow` wiring
that task 8's eligibility gating relies on.

## Exact write set

- `src/ui/songview.h`
- `src/ui/songview.cpp`

## Prerequisites

Task 1 — consumes its
`attachScene`/`detachScene`/`viewportItem`/`viewportChanged` interface only, not
its implementation.

## Interface contract

- `SongView::~SongView()` calls `detachScene()` instead of the removed
  `detachWindow()`/owned-window teardown.
- `resolveViewportGeometry()` reads the attached `viewportItem()` dimensions;
  `TimelineBandLayout`, `TimeCamera`, selection and hit-test coordinates remain
  canvas-local. Local band math in `layoutViewport()`/`refreshViewportLayout()`
  is retained.
- The existing `viewportChanged` → `refreshViewportLayout` connection is
  preserved and now also fires on item geometry/association changes per task 1.
- `AutomationPage::setInputWindow` binds on scene association and unbinds on
  detach (S4); it is no longer a constructor-only call.
- `cancelTransientInput()` keeps its current semantics — it already cancels
  popups without forced focus restoration.
- All document, edit-action, selection, camera and public `SongView` methods are
  preserved unchanged.

## Implementation steps

1. Migrate the destructor and any `detachWindow` call sites inside the write set
   to `detachScene()`; remove references to the deleted owned-window API.
2. Change `resolveViewportGeometry()` to derive `ViewportGeometry` from
   `viewportItem()` size (null/detached yields the existing empty-geometry
   behavior); keep `m_geometry.timelineSplitX` and band math untouched.
3. Move the `setInputWindow` call out of the one-time setup into
   association/disassociation handling bound to task 1's attach/detach
   notifications.
4. Keep the `viewportChanged` → `refreshViewportLayout` choreography as the
   single layout entry; do not scatter tab-strip or page offsets into band code
   (S7).

## Acceptance predicate

Viewport-only resize and nonzero page placement keep hit tests and cameras
correct; named checks `host-seams` and `rollcheck` pass under the gate-A run
below. Local structural inspection is not a behavioral pass.

## Task-specific constraints

- No window-sized layout assumption may remain; do not add a second geometry
  source beside `viewportItem()`.
- Rotations/3D transforms are out of scope per S7.
- Band publication already lives in `timelinequickview.cpp` (task 1). Do not
  invent a `timelinequickview_layout.cpp` split for this migration.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
