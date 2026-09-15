# T23 — Verify native clipping and surface lifecycle on real pages

## Context

Gate C verification task: with the single shared window live (gate B accepted
and task22's old-host deletion landed), the native-graphics checks must prove
playhead geometry, clipping, and surface lifecycle on real translated/clipped
pages. Consumes task7 (native playhead window mapping), task16 (page selection),
task20 (popup suppression behavior), and task22 (final fixture cutover). Task 11
already migrated existing nativegraphics scenarios at accepted gate A; this task
adds new scenarios, retaining the mac/non-mac split.

## Exact write set

- `src/checks/nativegraphics/tst_renderingplayhead.h`
- `src/checks/nativegraphics/tst_playhead_plots.cpp`
- `src/checks/nativegraphics/tst_playhead_native_mac.mm`

## Prerequisites

Interfaces from tasks 7 (PlayheadOverlay mapping/visibility policy), 16
(WorkspaceUi selection), 20 (popup/focus behavior), 22 (QuickSceneHost
fixtures). Gate C runs after accepted gate B; this task consumes the frozen spec
S7/S8 contract, not peer implementation detail.

## Interface contract

Produces check scenarios per spec S7/S8; no production interface. Requirements:

- Keep the current platform test split: `tst_playhead_native_mac.mm` covers the
  macOS CALayer renderer; the existing non-mac Quick renderer checks stay in the
  shared sources.
- New coverage: page at nonzero origin and smaller than the window — notes,
  scrollbars, menu anchors and CALayer align after a viewport-only resize;
  effective page/ancestor clipping and window-bounds intersection; hidden page
  playhead absent; open page popup hides that page's native playhead entirely
  and dismissal restores it when otherwise eligible; DPR/screen change and
  actual native surface loss/recreation remain correct.
- Assert actual rendering/native attachment, not only forwarded state; reuse the
  current native graphics capture/support.
- Preserve existing guide math and the non-mac Quick playhead checks.

## Implementation steps

1. In tst_renderingplayhead.h: extend declarations for the new
   geometry/clipping/popup/surface scenarios on the existing fixture shape.
2. In tst_playhead_plots.cpp: add translated/smaller-than-window viewport cases,
   viewport-only resize alignment, effective clipping, hidden-page absence, and
   popup suppression/restoration assertions through real page state.
3. In tst_playhead_native_mac.mm: add the CALayer-specific assertions for the
   same scenarios plus native surface loss/recreation; never force native
   surface creation merely to query geometry (spec S7).
4. Remove assertions pinning per-song window geometry rather than repinning
   them; keep existing guide-math and non-mac coverage intact.

## Acceptance predicate

Real/native page geometry and popup occlusion are correct. NAMED CHECKS:
`deno task verify --filter rendering-playhead --filter rollwindowingcheck` plus
the final native walkthrough (controller-run at gate C/final).

## Task-specific constraints

- Platform coverage stays in exactly the three listed files; no new harness or
  standalone executable.
- No partial native-popup occlusion implementation and no renderer substitution
  — the checks verify the spec policy, they do not extend it.

## Controller verification

[Gate C/final](plan.md#verification-and-checkpoint-semantics).
