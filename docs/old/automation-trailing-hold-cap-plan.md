# Cap Automation Trailing Hold at Song End — Implementation Plan

## Goal

Stop the flat segment after the last automation node—and equivalent preview or phantom trailing segments—at:

```cpp
min(plot.right(), displayX(songEndTick))
```

The curve must not continue across visible empty space beyond the song's end tick.

## Audit corrections applied

| ID | Correction | Supersedes |
|----|------------|------------|
| TH-1 | Semantic song-end query on `AutomationProjection`; `timeline()` stays `private`, `MidiTimeline` never leaks into painters | Public `timeline()` + painter-side `lengthTicks` poking |
| TH-2 | Five terminal sites (pencil preview has two distinct ones) | Four sites |
| TH-3 | Drag preview: no post-end hold, no reversed segment | Unaddressed |
| TH-4 | Explicit plot clipping rules (below), binding for implementation and tests | One prose sentence |
| TH-5 | Pixel-oracle checks for before / inside / after / zero-length end | Manual zoom-and-look verification steps |

## Stage 1 — Semantic song-end query in AutomationProjection

**Target:** `src/ui/editordrawer/automationprojection.{h,cpp}` only.

**Change:**

- Do **not** make `timeline()` public. It remains a private resolver over `m_page` / `m_songView`.
- Add one public semantic query, matching the `nodeMarkersVisible()` precedent of exposing meaning instead of raw state:

  ```cpp
  // In AutomationProjection (public). Display x of the song's end tick at the
  // given device pixel ratio; nullopt when the song is unbounded (null
  // timeline or lengthTicks == 0).
  std::optional<qreal> songEndX(qreal devicePixelRatio) const;
  ```

  Implementation in `automationprojection.cpp` resolves `timeline()` privately and maps through the existing `displayX`:

  ```cpp
  std::optional<qreal> AutomationProjection::songEndX(qreal devicePixelRatio) const
  {
      const MidiTimeline *timeline = this->timeline();
      if (!timeline || timeline->lengthTicks == 0)
          return std::nullopt;
      return displayX(timeline->lengthTicks, devicePixelRatio);
  }
  ```

- Add `#include <optional>` to the header. No new includes in the `.cpp`; painters must not include `core/miditimeline.h`.

**Acceptance:** query returns the end x for a bounded timeline and `nullopt` for null / zero-length; `timeline()` is still private; no painter files touched.

**Review focus:** the raw timeline pointer stays encapsulated; the only new public surface is the semantic query.

## Stage 2 — Bound the five terminal sites

**Target:** `src/ui/editordrawer/nodelane/paint.cpp` (anonymous namespace + the five sites). Depends on Stage 1.

**Change:** add the plot-side bound helper, then replace exactly these five terminal fallbacks:

```cpp
// Right edge where a held segment terminates: the song end when it falls
// inside the plot, otherwise the plot edge itself.
qreal heldEndX(const AutomationProjection &projection, const QRect &plot, qreal dpr)
{
    const std::optional<qreal> endX = projection.songEndX(dpr);
    return endX ? std::min<qreal>(plot.right(), *endX) : qreal(plot.right());
}
```

1. **`paintStepCurve`** — terminal hold of the committed curve (also serves prepared drag-preview curves via `gesture.previewPoints`): when `index + 1 == points.size()`, `x1 = heldEndX(...)` instead of `plot.right()`; if `x0 >= x1` skip the hold (a last node at or past the end draws no hold).
2. **`paintPhantomCurvePreview`** — when `next == points.end()`, `nextX = heldEndX(...)` instead of `plot.right()`. No reversal guard needed: the segment starts at `plot.left()`, so a bound left of the viewport is discarded by the plot clip (see clipping rules).
3. **`paintDragPreview`** — single-point drag path: when there is no `next`, the terminal hold runs to `heldEndX(...)` and only when `x < endX`. Stage 3 adds the surrounding guards.
4. **`paintPencilPreview`** (committed tail) — a point beyond the stroke range with no successor draws to `heldEndX(...)` instead of `plot.right()`; skip when `tickX(point.tick) >= endX`.
5. **`paintPencilPreview`** (preview tail) — the `previewValue && !nextAfterRange` tail draws `preview.tickEnd → heldEndX(...)` instead of `→ plot.right()`; skip when `tickX(preview.tickEnd) >= endX`.

**Acceptance:** the only remaining `plot.right()` uses in `paint.cpp` are viewport culling, `plotRect`, and clip construction; intermediate segments (a point with a successor still holds through the successor's x) are untouched; `paintSweepPreview` and `paintHover` are untouched (they have no terminal hold).

**Review focus:** each site bounded exactly once; no clip or culling logic changed.

## Stage 3 — Drag preview: no post-end, no reversed segment

**Target:** `paintDragPreview` single-point path in `src/ui/editordrawer/nodelane/paint.cpp`. Depends on Stage 1; serialize after Stage 2 (same file — assign both stages to one owner or run sequentially).

**Change:** with `x = tickX(grabbed.current.tick)` and `endX = heldEndX(...)`:

- The `previous` hold and its vertical drop clamp their right end to `min(x, endX)` and draw only when that is strictly right of `tickX(previous->tick)`. A drag past the song end steps down at the last drawable x, never beyond it.
- The terminal hold draws only when `x < endX` (Stage 2's site 3). This kills both defect shapes: a post-end hold when the dragged node sits past the song end, and a reversed line painting back into the viewport when the node is scrolled off right (`x > plot.right()`).
- The dragged node marker and preview label keep current behavior (pointer feedback under the overflow clip); only held segments are bounded.

**Acceptance:** dragging a last node past the song end paints no segment beyond `endX` in either scroll position; multi-node / prepared-preview drags inherit the bound through `paintStepCurve`.

**Review focus:** marker feedback preserved; guards cannot produce zero- or negative-length lines.

## Stage 4 — Pixel-oracle checks

**Target:** extend `src/checks/rollcheckautomation_paint.cpp` with `checkAutomationTerminalHold(view, page, document, live, failures)`, declared and invoked from `rollcheckautomation.cpp` next to `checkAutomationNodePaint` (same `automation` catalog entry — no new check file, `src/` top level untouched). Depends on Stages 1–3.

**Harness:** follow the file's existing idiom — offscreen `QImage` renders of `paintNodeLane` with a directly constructed `NodeLanePaint` for the committed and phantom sites (deterministic, no events), and the canvas-event helpers (`sendActivatedDrag`, pencil-mode action) for drag and pencil previews. Sample device pixels through the widget's DPR with the existing `deviceRect` / color-tolerance helpers (tolerance precedent: `persistedCurvePixelNear`, ±40 per channel).

**Cases** — one lane, its held lead-in plus a trailing node, four end positions:

- **inside:** song end strictly inside the plot → curve-colored pixels end within one device pixel of `round(endX · dpr)` (the 2×`singlePixel` pen fringe); columns `endX + clearance … plot.right()` at the held row match the backdrop.
- **before:** song end left of the plot → no held-segment pixels anywhere in the plot row (clipping discards the bound).
- **after:** song end right of the plot → hold reaches the last plot column; the raster equals the zero-length raster for identical nodes (both bound at `plot.right()`).
- **zero-length:** timeline null or `lengthTicks == 0` (empty-song fixture, or a projection over a null timeline) → full-width hold to `plot.right()`, preserving today's fallback.

**Preview coverage:** at minimum the inside case for each preview site (phantom, drag, both pencil tails) plus the Stage 3 guard cases — drag past the end in-viewport (nothing beyond `endX`) and off-viewport right (no reversed segment). Committed-curve cases double as regression cover for prepared-preview drags, which render through `paintStepCurve`.

**Acceptance:** `deno task build:checks` and `deno task verify --filter automation --verbose` pass with the new oracle failing on a reverted painter.

## Plot clipping rules (binding)

1. The song end participates **only** as a right-edge bound: `min(plot.right(), songEndX)`. Never clamp to `plot.left()`, `top()`, or `bottom()`.
2. A song end left of the viewport is not a clamp target. Left-clamping would truncate holds that start off-screen but remain inside the song; the installed painter clips discard those pixels instead — `plot` for committed and phantom curves, `nodeOverflowClip(plot, geometry)` for drag, sweep, and pencil previews. No new clip rects.
3. `displayX` coordinates may lie far outside the viewport before clipping; do not pre-clamp inputs — only the terminal bound takes `min()`.
4. Node markers are not bounded by song end (a dragged node may sit past it); held segments are.
5. Degenerate plots (`plot.right() < plot.left()`) simply cull, as today.

## Non-goals

- Intermediate segments: a point with a successor still holds through the successor's x, even if that successor sits past the song end — node placement beyond the end tick is a data-model question, not a paint defect.
- `paintSweepPreview` (ramp diagonal and inter-point holds only) and `paintHover` chrome (dotted insertion line).
- Gesture commit/clamping semantics; this plan bounds rendering only.

## Verification

- `deno task build:checks`
- `deno task verify --filter automation --verbose` — includes the Stage 4 oracle.
- `deno task verify --filter editor-drawer --verbose`
- Manual spot-check remains meaningful but is no longer the proof: scroll past the song end and confirm the committed, drag, pencil, and phantom holds all stop at the end tick, and that a dragged node past the end leaves the region beyond it untouched.
