# T07 — Map native playheads into the shared window

## Context

`PlayheadOverlay::synchronizeGeometry` assumes the page fills its window. Under
shared-window pages it must map the canvas-local timeline-column rect into
window scene coordinates, clip to effective page bounds, and hide while a page
popup is open, per [spec.md](spec.md) S7. Consumes task 1's
`viewportItem`/`isInputEligible`/`windowAboutToDetach` and task 4's popup
open-state contract; task 23 adds the focused platform acceptance coverage.

## Exact write set

- `src/ui/playheadoverlay.h`
- `src/ui/playheadoverlay.cpp`
- `src/ui/playheadrenderer_macos.mm`

## Prerequisites

Tasks 1 and 4 — consume their interfaces only (viewport item/eligibility/detach
notification; popup session open state).

## Interface contract

Per spec S7:

- `synchronizeGeometry()` maps the canvas-local timeline-column rect into window
  scene coordinates with `QQuickItem` mapping, intersects it with effective
  page/ancestor clipping and window bounds, and applies pixel rounding only at
  the existing native seam.
- Effective visibility includes attached/selected-ready effective page
  visibility and input eligibility — not just `QWindow::isVisible`. For an open
  page popup, that page's native playhead hides entirely and restores after
  dismissal if otherwise eligible; the same popup visibility policy applies to
  the Quick playhead.
- The macOS CALayer renderer (`playheadrenderer_macos.mm`) and the existing
  non-mac Quick renderer are both kept; no renderer substitution and no partial
  native-popup occlusion.
- `windowAboutToDetach` and PlatformSurface destruction remove the native
  attachment before losing the NSView; never create a native surface merely to
  query geometry; no per-frame scene reconstruction.
- Track association, item geometry and platform surface loss/recreation.

## Implementation steps

1. Rework `synchronizeGeometry` to derive native origin/clip/effective
   visibility from the attached item, ancestor/window bounds and popup state.
2. Wire association, item-geometry and surface-loss tracking so recreation
   happens on real surface loss only. Bind existing isOpenChanged and sample
   isOpen at association per S7; disconnect on detach, not after a future frame.
3. Apply the popup suppression/restoration policy identically in both renderers.

## Acceptance predicate

Translated, hidden and popup-covered page playhead geometry and native surface
recreation are correct; named checks `rendering-playhead` and
`rollwindowingcheck` pass under the gate-A run below. Local structural
inspection is not a behavioral pass.

## Task-specific constraints

- Keep all existing rendering algorithms and the platform split unchanged.
- Rotations/3D transforms out of scope; axis-aligned translated/resized/clipped
  pages only.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
