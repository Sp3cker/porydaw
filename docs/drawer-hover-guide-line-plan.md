# Editor Drawer Hover Guide Line — Implementation Plan

## Goal

Draw a full-height vertical guide at the pointer x in `AutomationCanvas` and `VelocityArea`
so automation input can be aligned with notes.

Style (both surfaces):

```cpp
QPen(themes::color(themes::Role::song_view_secondary_text),
     layout::singlePixel(), Qt::DotLine)
```

The dotted secondary-text guide must remain visually distinct from the edit cursor, which
uses `Qt::DashLine` and `song_view_edit_cursor`.

`VoiceChangeArea` already paints its own dotted hover line (`voicechangearea_paint.cpp`
`m_hoverActive` block) with exactly this precedence and invalidation discipline. It is the
reference pattern; this plan changes nothing in it.

## Audit corrections applied

The audit matrix file (`audit-correction-matrix.json`) was delivered empty; the HGL
corrections below come from the audit's HGL risk entries and the review assignment. Each
correction maps to a concrete design decision in this plan:

A second correction pass folded in the NO_GO review findings
(`corrected-plan-reviews.json`, index 3): true no-op transitions, strip-coverage
accounting over the pinned-tempo gap, the full clear-path enumeration (double-click,
cancel, resize/geometry, document/song/focus), and executable Stage 5 budgets.

| Correction | Where it lands |
| --- | --- |
| Validated min/max paint bounds and clip | `AutomationCanvas::hoverGuidePlot()` (validated union of non-empty slot bodies, width guard) plus `Qt::IntersectClip` at every guide draw; VelocityArea validates x into `[origin, origin+plotWidth)` and draws inside the existing `contentClip` |
| One transition helper for all update/clear paths | `AutomationCanvas::hoverGuideTransition(region, guideX)` and `VelocityArea::updateHoverGuide(x)`; every hover update/clear call site in both canvases routes through them |
| `Interaction::None` invariant | Guides arm only from idle hover moves; every gesture/lifecycle boundary (press, double-click, release, keys, cancel, pencil toggle, stack rebuild, leave, window Hide/WindowDeactivate/UngrabMouse, document/song change, geometry change) clears them; VelocityArea paint double-gates on `m_interaction == Interaction::None` |
| Guide under cursor | Automation: the guide segment is drawn inside `paintLaneBody` *before* `paintEditCursor`. Velocity: drawn *before* the edit-cursor block. Both match VoiceChangeArea's paint order (hover line first, dashed cursor last) |
| Two DPR-safe `QRegion` strips | A real move invalidates two narrow strips (old x, new x), never one span strip; an identical-x transition is a true no-op (no strips, no invalidation); each strip is `QRectF(x - 1, ...).toAlignedRect()` over the validated plot (documented pinned-gap over-coverage, invariant 4) and `TimelineSurface::invalidateContent` snaps regions to the device-alignment grid |
| Includes / source ownership | No new includes anywhere; paint helpers live in `*_paint.cpp`, transition helpers in `*_input.cpp` / `*_interaction.cpp`, shared plot geometry in `automationcanvas.cpp`; no changes to `nodelane/`, `timelinesurface.*`, or `voicechangearea/` |
| Backing-store behavioral checks | Sweep-restore checks extended to both surfaces, hover repaint budgets re-derived for guide columns, fractional-scale and force-uncached runs, native-exposure windowing check (Stage 5 + Verification) |

Rejected plan fragments that the audit invalidated — do not resurrect them:

- `QRect(m_geometry.plotOrigin, m_nodeStack.front().body.top(), ...)` as the guide plot:
  `front()` is the tempo slot whose `bodyRect()` is **empty when collapsed**, CC bodies can
  extend past the visible height, and `width() - plotOrigin` can be negative. Use the
  validated min/max union (`hoverGuidePlot`) instead.
- "No new canvas hover state is required": false. `m_hoverState.hover` is mutated and
  cleared on eleven separate paths, some of it locked (`highlightLocked` survives gesture
  starts), so the previously painted guide x is unrecoverable after a clear. Explicit
  `m_hoverGuideX` / `m_hoverX` state is required.
- Single span strip `QRect(qFloor(min) - 1, 0, qAbs(dx) + 3, height())`: repaints the whole
  band between old and new x. Two strips instead.
- Drawing the VelocityArea guide "after painting the edit cursor": puts the transient
  hover line above the cursor. Draw it before.

## Invariants

1. **Guide state is the paint truth.** Automation paints a guide segment iff
   `m_hoverGuideX` holds a value; VelocityArea paints iff `m_hoverX` holds a value **and**
   `m_interaction == Interaction::None`. Hover-lane validity is never used as a paint gate —
   locked hover highlights outlive gestures and would resurrect a stale column.
2. **One transition helper per surface.** `hoverGuideTransition` /
   `updateHoverGuide` are the only code that mutates guide state or computes guide strips.
   All update/clear paths call them. A transition whose new optional equals the current
   state is a **true no-op**: the helper returns its input region untouched, adds no
   strips, and performs no invalidation — a same-x hover move or a redundant clear
   churns exactly nothing.
3. **Armed only by idle hover.** Guides arm from `mouseMoveEvent` hover handling only
   (AutomationCanvas: `updateHover` path; VelocityArea: `Interaction::None` branch). Every
   path that starts, runs, or cleans up a gesture passes `std::nullopt` through the helper.
4. **Strips cover what was painted — plus one documented exception.** A strip is the pen
   footprint (`layout::singlePixel()` is a logical hairline, so its logical coverage is
   `[x - singlePixel/2, x + singlePixel/2]` at any DPR) plus one logical pixel of
   rounding pad — the `QRectF(x - 1, ..., 2, ...)` rect — rounded outward by
   `toAlignedRect()`, with the vertical extent of the painted guide (node-stack span plot
   for AutomationCanvas, full widget height for VelocityArea). `TimelineSurface::invalidateContent`
   then snaps every region edge outward to the device-alignment grid
   (`deviceAlignmentGrid(dpr)`: 1 at integer scale, 2 at 150%, 4 at quarter scales), so
   no boundary device pixel is left stale at fractional scale factors. The exception:
   the Automation span plot unions non-empty lane bodies, so its height is the **span
   height, not the sum of lane heights** — the scroll-dependent gap between the last CC
   body and the bottom-pinned tempo body lies inside the strip but is never painted
   (per-lane clips paint lane bodies only). That gap over-coverage is intentional (a
   single span strip is cheaper than a per-lane region union), and the Stage 5 budgets
   are derived from the span height, so it stays inside budget.
5. **Guide under cursor.** Both surfaces paint the dashed edit cursor after (over) the guide.

## Layout primitives (preserve — do not invent geometry)

- `m_geometry.plotOrigin` / `nodelane::plotRect` semantics for the automation plot left
  edge and the `std::max<int>(0, width() - plotOrigin)` width guard.
- `VelocityArea::plotOrigin()` / `plotWidth()` for the velocity plot.
- `layout::singlePixel()` for pen width; `layout::space()` where padding is needed.
- Per-lane clips mirror `paintLaneBody`'s existing `plot` construction; no new layout
  constants, no magic numbers beyond the ±1 strip pad and pen footprint.

## Source & include ownership

| File | Concern | New includes |
| --- | --- | --- |
| `automationcanvas.h` | declarations: `paintHoverGuideLine`, `hoverGuidePlot`, `hoverGuideTransition`; member `std::optional<qreal> m_hoverGuideX` | none (`<optional>`, `QRegion` via `timelinesurface.h` already present) |
| `automationcanvas.cpp` | `hoverGuidePlot()` definition (geometry concern lives with layout code) | none |
| `automationcanvas_paint.cpp` | `paintHoverGuideLine` definition + per-lane draw site in `paintLaneBody` | none (`themes`, `layout` already included) |
| `automationcanvas_input.cpp` | `hoverGuideTransition` definition + all input call-site migrations | none (`<algorithm>` already present) |
| `velocityarea.h` | declaration `updateHoverGuide`; member `std::optional<double> m_hoverX` | none (`<optional>`, `<QRect>` already present) |
| `velocityarea.cpp` | lifecycle clears in `cancelInteraction` (before the `Interaction::None` early return) and `contentGeometryChanged` | none |
| `velocityarea_interaction.cpp` | `updateHoverGuide` definition + call-site migrations | none (`QRectF` via `<QRect>`, `<algorithm>` already present) |
| `velocityarea_paint.cpp` | guide draw inline in `paintContent` (single draw site, like the VoiceChangeArea reference) | none |

Not touched: `nodelane/hover.{h,cpp}` (guide state is canvas-owned, not node-lane hover
state), `timelinesurface.{h,cpp}` (strips ride the existing region invalidation + grid
snap), `voicechangearea/` (reference only), `automationprojection.h`.

Current sizes of the touched files: `automationcanvas.h` 235L, `automationcanvas.cpp`
516L, `automationcanvas_paint.cpp` 399L, `automationcanvas_input.cpp` 518L,
`velocityarea.h` 195L, `velocityarea.cpp` 546L, `velocityarea_interaction.cpp` 487L,
`velocityarea_paint.cpp` 161L. The roughly 12-20 added lines per file do not materially
move any of them against the ~600L review signal (keep-files-small): the seams above
keep each hover concept with its existing owner instead of spawning fragments.

## Stage 1 — AutomationCanvas paint

Files: `src/ui/editordrawer/automationcanvas.h`, `automationcanvas.cpp`,
`automationcanvas_paint.cpp`.

1. Declare in `automationcanvas.h` next to `paintEditCursor`:

   ```cpp
   static void paintHoverGuideLine(QPainter &painter, const QRect &plot, qreal x);
   ```

   Declare `QRect hoverGuidePlot() const noexcept;` near `pinnedTempoRect()`, and add
   `std::optional<qreal> m_hoverGuideX;` with a comment: "x of the painted hover guide,
   clamped into hoverGuidePlot(); empty when no guide is painted. Armed only by idle
   hover moves; cleared through hoverGuideTransition."

2. Define in `automationcanvas.cpp` (next to the layout helpers):

   ```cpp
   QRect AutomationCanvas::hoverGuidePlot() const noexcept
   {
       QRect span;
       for (const NodeLaneSlot &slot : m_nodeStack) {
           if (slot.lane && !slot.body.isEmpty())
               span = span.isEmpty() ? slot.body : span.united(slot.body);
       }
       const int plotWidth = span.isEmpty() ? 0 : std::max(0, width() - m_geometry.plotOrigin);
       if (plotWidth == 0)
           return {};
       return {m_geometry.plotOrigin, span.top(), plotWidth, span.height()};
   }
   ```

   Min/max over non-empty slot bodies: the collapsed tempo header (`headerRect`, not
   `body`) is excluded, empty tempo bodies cannot poison `top()`, and the width guard
   matches `nodelane::plotRect`.

3. Define in `automationcanvas_paint.cpp`:

   ```cpp
   void AutomationCanvas::paintHoverGuideLine(QPainter &painter, const QRect &plot, qreal x)
   {
       if (plot.isEmpty())
           return;
       painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text),
                           layout::singlePixel(), Qt::DotLine));
       painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
   }
   ```

   `x` arrives pre-clamped by the transition helper; the per-lane clip bounds it again.

4. Draw site — inside `paintLaneBody`, between the `nodelane::paintNodeLane(...)` call and
   the existing edit-cursor `save/clip/draw/restore` block:

   ```cpp
   if (m_hoverGuideX && plot.width() > 0) {
       painter.save();
       painter.setClipRect(plot, Qt::IntersectClip);
       paintHoverGuideLine(painter, plot, *m_hoverGuideX);
       painter.restore();
   }
   ```

   Per-lane segments tile into one full-height line over contiguous bodies, skip the gap
   between short CC stacks and the bottom-pinned tempo body, stay out of the collapsed
   tempo header and the add-lane strip, and sit **under** that lane's dashed edit cursor.
   A collapsed tempo slot returns before `paintLaneBody`, so it draws nothing — correct.

Acceptance: full repaint with an armed `m_hoverGuideX` shows one dotted column spanning
every non-empty lane body, crossing no header text, reticle, or drawer chrome, with the
edit cursor visibly on top where the columns meet.

## Stage 2 — AutomationCanvas transition helper

Files: `automationcanvas.h` (declaration), `automationcanvas_input.cpp` (definition +
input call-site migrations), `automationcanvas.cpp` (`cancelInteraction` fold at :399,
`contentGeometryChanged` clear at :43).

1. Declare in `automationcanvas.h` (private, input section):

   ```cpp
   QRegion hoverGuideTransition(QRegion dirty, std::optional<qreal> guideX);
   ```

2. Define in `automationcanvas_input.cpp`:

   ```cpp
   QRegion AutomationCanvas::hoverGuideTransition(QRegion dirty, std::optional<qreal> guideX)
   {
       const QRect plot = hoverGuidePlot();
       std::optional<qreal> next;
       if (guideX && !plot.isEmpty())
           next = qBound(qreal(plot.left()), *guideX, qreal(plot.right()));
       if (m_hoverGuideX == next)
           return dirty; // identical state: true no-op — no strips, no invalidation
       const auto strip = [&plot](qreal x) {
           return QRectF(x - 1.0, plot.top(), 2.0, plot.height()).toAlignedRect();
       };
       if (m_hoverGuideX)
           dirty += strip(*m_hoverGuideX);
       if (next)
           dirty += strip(*next);
       m_hoverGuideX = next;
       return dirty;
   }
   ```

   The equality guard runs before any strip math: when the new optional equals
   `m_hoverGuideX`, the input region is returned untouched — no strips, no invalidation.
   The `updateHover` unchanged-position early return re-reports the same x, so repeat
   hovers churn exactly nothing and `noRepeatChurn`
   (`automationgesturecheck/hover.cpp:291-295`) holds without loosening its budget.
   Clears with no guide armed (`m_hoverGuideX` empty, `guideX` empty) take the same
   early return, emitting exactly today's region. `toAlignedRect()` rounds outward;
   `TimelineSurface::invalidateContent` snaps the union to the device-alignment grid.
   Strips are emitted only when the guide actually moves or retires.

3. Migrate **every** hover invalidation site (clears pass `std::nullopt`, so their emitted
   region is identical to today's until a guide is armed):

   - `automationcanvas_input.cpp`
     - `mousePressEvent` entry (`clearHover` before dispatch — retires the guide for pan,
       band, resize, pencil, and drag gestures alike).
     - `mouseDoubleClickEvent` entry (:412-415, right after the document guard):
       `songview::TimelineSurface::invalidateContent(hoverGuideTransition({}, std::nullopt))`.
       Qt delivers the second click as `MouseButtonDblClick` — never as
       `mousePressEvent` — so the press-entry clear does not run for it, and a re-arming
       move between the two clicks would otherwise strand an armed column across the
       tempo-header collapse toggle (:421-427), the pencil branch's full invalidate
       (:442-447), or the CC `promptValue` dialog (:452-458). Empty in → empty out: a
       no-op unless a guide is armed.
     - `mouseMoveEvent`: the `m_band.pending` clear; tempo-header clear; CC-row-boundary
       clear; no-slot clear; and the `updateHover` path, which passes
       `m_hoverState.hover.lane.valid() ? std::optional<qreal>{x} : std::nullopt` as
       `guideX` after `updateHover` returns (the hover state stays valid on its
       unchanged-position early return, so repeat hovers emit nothing).
     - `mouseReleaseEvent` clears, `keyPressEvent` clears, `leaveEvent`.
   - `automationcanvas.cpp`
     - `setPencilMode` hover clear, `rebuildNodeStack` clear (runs before the stack is
       cleared, so the old plot is still valid for strips), `highlightHoveredPoint`'s
       `setContextPointHighlight` invalidation (`std::nullopt` — gesture start),
       `cancelInteraction` clear (its `m_hoverState.clearHover()` invalidation at :399
       becomes `invalidateContent(hoverGuideTransition(m_hoverState.clearHover(),
       std::nullopt))`).
     - `contentGeometryChanged` (:43-48): `hoverGuideTransition({}, std::nullopt)` with
       the returned region discarded — the final `TimelineSurface::resizeEvent`
       (timelinesurface.cpp:203-210) already reset the cache and invalidated the whole
       surface before the virtual call, so the clear is about state, not strips: without
       it a width change leaves `m_hoverGuideX` armed outside the new plot until the next
       move.
     - Window-level routes: `AutomationCanvas::event` (:142-144) sends `Hide`,
       `WindowDeactivate`, and `UngrabMouse` to `cancelInteraction`, and
       `AutomationPage::event` (`automationpage.cpp:144-146`) routes page-level
       `Hide`/`WindowDeactivate` the same way — covered by the `cancelInteraction` clear,
       no new call sites. (`AutomationCanvas` has no `focusOutEvent`;
       `automationcanvas.h:60-70` — window deactivation is the focus-loss path.)
     - Document/song lifecycle: `AutomationPage::songChanged` (`automationpage.cpp:226-231`)
       and `AutomationPage::documentChanged` (:253-258) both funnel through
       `AutomationPage::cancelInteraction` (:247-251) into
       `AutomationCanvas::cancelInteraction`; `rebuildRows` (:147-149) cancels too.
       Covered by the `cancelInteraction` clear.

Acceptance: every clear path enumerated above (press, double-click, move, release, keys,
leave, pencil toggle, stack rebuild, highlight gesture start, cancel, geometry change,
window Hide/WindowDeactivate/UngrabMouse, document/song change) and the single update
path compile down to the helper; no call site mutates `m_hoverGuideX` or builds strips
directly; same-x hovers and redundant clears perform zero invalidations; a hover →
gesture → release cycle leaves `m_hoverGuideX` empty without a paint of the column.

## Stage 3 — VelocityArea transition helper

Files: `src/ui/editordrawer/velocityarea/velocityarea.h`,
`velocityarea.cpp` (`cancelInteraction`, `contentGeometryChanged` lifecycle clears),
`velocityarea_interaction.cpp`.

1. Add the member with its invariant comment:

   ```cpp
   // x of the painted hover guide; armed only while m_interaction is None and
   // cleared at every gesture entry, leave, and cancel. Empty optional = no guide.
   std::optional<double> m_hoverX;
   ```

2. Declare `void updateHoverGuide(std::optional<double> x);` (private, next to
   `updateHoveredNote`) and define in `velocityarea_interaction.cpp`:

   ```cpp
   void VelocityArea::updateHoverGuide(const std::optional<double> x)
   {
       std::optional<double> next;
       if (x && *x >= plotOrigin() && *x <= plotOrigin() + plotWidth() - 1)
           next = x;
       if (m_hoverX == next)
           return; // identical state: true no-op — no strips, no invalidation
       const auto strip = [this](double x) {
           return QRectF(x - 1.0, 0.0, 2.0, qreal(height())).toAlignedRect();
       };
       QRegion dirty;
       if (m_hoverX)
           dirty += strip(*m_hoverX);
       if (next)
           dirty += strip(*next);
       m_hoverX = next;
       if (!dirty.isEmpty())
           songview::TimelineSurface::invalidateContent(dirty);
   }
   ```

   The equality guard runs before any strip math: same-x moves and redundant clears
   (`updateHoverGuide(std::nullopt)` with no guide armed) return without touching the
   dirty region, so every clear path added below is free when nothing is armed. The
   qualified call is required: `VelocityArea::invalidateContent(const QRect &)` hides
   the base overloads and takes no region. An out-of-plot x (post-resize, gutter) clears
   instead of clamping — the next in-plot move re-arms, matching `VoiceChangeArea`.

3. Call sites:
   - `mouseMoveEvent`, inside the `m_interaction == Interaction::None` branch, after
     `updateHoveredNote(position)`: `updateHoverGuide(position.x());`. Gesture moves never
     touch the guide.
   - `mousePressEvent`, after `setFocus` and before button dispatch:
     `updateHoverGuide(std::nullopt);` — Pan, PendingBand, Ramp, Paint, and Relative all
     retire the column at gesture entry, so partial gesture invalidations can never strand
     it. The ruler-press path (begin + finish inside one press) re-arms lazily on the next
     move, like the hovered-note state it sits beside.
   - `leaveEvent`: `updateHoverGuide(std::nullopt);` before
     `TimelineSurface::leaveEvent`.
   - `cancelInteraction` (`velocityarea.cpp:154-157`): `updateHoverGuide(std::nullopt);`
     as the **first statement, before the `m_interaction == Interaction::None` early
     return** — focus loss while idle-armed must clear even though no gesture is active.
     This one site covers every lifecycle route that funnels here: `UngrabMouse` via
     `event()` (:85-95), Escape via `keyPressEvent` (:467-470), `focusOutEvent`
     (:475-479), `setUseDetents` (:191-198), the stale-gesture cancel in
     `refreshLiveState` (:145-148), `songChanged` (:110-118), and `documentChanged`
     (:178-185) with `tracksRemapped` (:187-190), plus the external `DrawerSections`
     (drawersections.cpp:459-465) and `editordrawer.cpp:323-331` cancels — the
     document/song/focus discipline `VoiceChangeArea` follows for its hover state.
   - `contentGeometryChanged` (`velocityarea.cpp:250-253`):
     `updateHoverGuide(std::nullopt);` after `rebuildAxis()`. The final
     `TimelineSurface::resizeEvent` (timelinesurface.cpp:203-210) has already
     full-invalidated before the virtual call, so this is a state clear, not a strip
     invalidate.
   - No `mouseDoubleClickEvent` exists (`velocityarea.h:62-74`), so the press-entry clear
     covers every click sequence; there is no double-click stranding case to enumerate.

Acceptance: `finishGesture`/`cancelInteraction` return to `Interaction::None` with
`m_hoverX` empty; document swap, song change, focus loss, Escape, detent toggle, and
resize each leave the guide disarmed; the paint gate in Stage 4 makes the
`Interaction::None` invariant observable; `updateHoverGuide(std::nullopt)` on an empty
guide performs no invalidation; no other method references `m_hoverX`.

## Stage 4 — VelocityArea paint

File: `velocityarea_paint.cpp`, inside `paintContent`'s existing
`save / setClipRect(axisStyle.contentClip, IntersectClip) / restore`.

Insert after the band-reticle block's `setRenderHint(QPainter::Antialiasing, false)` and
**before** the edit-cursor block:

```cpp
// Hover guide sits under the edit cursor: the dashed cursor must win where the
// two columns cross (VoiceChangeArea paint order is the reference).
if (m_interaction == Interaction::None && m_hoverX && *m_hoverX >= origin &&
    *m_hoverX <= origin + width - 1) {
    painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text),
                        layout::singlePixel(), Qt::DotLine));
    painter.drawLine(QPointF(*m_hoverX, 0), QPointF(*m_hoverX, height()));
}
```

Full widget height is inside `contentClip` (`QRect(origin, 0, width, height())`), so the
line cannot leak into the axis ruler. The bounds re-validation is belt-and-braces
behind the Stage 3 `contentGeometryChanged` clear: any transient stale x (e.g. a
font-change geometry re-resolve, which does not route through `cancelInteraction`)
draws nothing, and the next in-plot move re-arms.

Acceptance: guide and cursor overlap shows the dashed cursor unbroken over the dotted
guide; the guide never appears left of the plot separator.

## Stage 5 — Check budgets and backing-store coverage

The existing checks encode today's hover contract (a small readout neighborhood), which a
full-height column breaks. Update them in the same change, with budgets computed from the
same primitives the widget code uses — exact formulas, no `~` approximations:

1. `src/checks/rollcheckhover.cpp` owns only the real-surface cache, pixel, and velocity
   hover oracle: its exposed-backing-store captures, narrow repaint budgets, velocity
   lifecycle clears, and serpentine restoration sweep. It exports `checkHoverCacheUpdates`
   for the playhead check and `hoverGuideCheckFailures` through the existing
   `rollcheckplayhead.h` seam. In `PORYDAW_HOVER_GUIDE_ONLY=1` mode, `runRollCheck`
   composes that oracle with
   `runAutomationGestureCheck(projectRoot, songLabel, QStringLiteral("hover"))`, aggregates
   their results, and invokes the automation domain even if the real-surface oracle reports
   failures. The automation hover domain remains the single owner of its six-interaction,
   eleven-clear-path `AutomationCanvas` lifecycle matrix; `rollcheckhover.cpp` must not
   duplicate it. The focused seam finds the two drawer surfaces from
   `SongView::timelineBands()`, exposes them, warms their content, runs the real-surface
   oracle, and restores their visibility. Playhead-specific overlay probes stay in
   `rollcheckplayhead.cpp`.
   - `checkAutomationHoverCacheUpdate` keeps the probe assertions and the existing readout
     constants — `maxReadoutWidth = min(192, max(64, width/3))` and
     `maxReadoutPaintPixels` — then derives its guide budget through
     `rollcheck::rendering::hoverGuideBudget`:

     ```
     dpr = lanes.devicePixelRatioF()
     g   = songview::deviceAlignmentGrid(dpr)      // 1 integer, 2 at 150%, 4 quarter scales
     alignUp(n, g) = ((n + g - 1) / g) * g
     stripW = alignUp(qCeil(3 * dpr), g) + g       // device px per strip, horizontal
     stripH = qCeil(spanPlotHeight * dpr) + 2 * g  // device rows per strip, vertical
     guidePaintBudget = maxReadoutPaintPixels + 2 * stripW * stripH
     guideWidthBudget = maxReadoutWidth + qCeil(stripW / dpr)  // logical px
     ```

     `3` is the worst-case `toAlignedRect` strip width (`ceil(x+1) - floor(x-1)`: 2 when x
     is integral, else 3); the `+ g` terms cover the one-grid outward snap
     `expandRegionToDeviceGrid` applies per edge. `spanPlotHeight` is the `hoverGuidePlot`
     span height — non-empty lane bodies plus the pinned-tempo gap, **not** the sum of
     lane heights (invariant 4). Assertions keep the visible contract: hover arms a narrow
     column, a move restores the old column and arms the new one, leave restores the
     baseline, and the full-surface guard remains `hoverPaintPixels * 4 < wholeSurfacePixels`.
2. `src/checks/rollcheckrendering.{h,cpp}` is the shared rendering seam: it centralizes the
   strip-budget formula plus cursor-precedence and guide-column restoration comparisons.
   `src/checks/automationgesturecheck/hover.cpp` reuses those comparisons while retaining its
   automation-specific stack topology and repeat-hover assertion. No duplicate device-column
   scan or budget formula is permitted.

## Critical files

- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_paint.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea.h`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_paint.cpp`
- `src/checks/rollcheckplayhead.cpp`
- `src/checks/rollcheckplayhead.h`
- `src/checks/rollcheckhover.cpp`
- `src/checks/rollcheckrendering.h`
- `src/checks/rollcheckrendering.cpp`
- `src/checks/automationgesturecheck/hover.cpp`

## Verification

Gates and harnesses (run once at the end; stages are validated by their acceptance
criteria plus the checks above):

- `deno task build:checks`, then run the affected check binaries through
  `deno task checks` (rollcheck, automationgesturecheck, renderingplayheadcheck).
- Fractional-scale backing-store gates:
  `QT_SCALE_FACTOR=1.25 PORYDAW_HOVER_GUIDE_ONLY=1 deno task checks build/porydaw_checks --filter=rollcheck`
  and
  `QT_SCALE_FACTOR=1.5 PORYDAW_HOVER_GUIDE_ONLY=1 deno task checks build/porydaw_checks --filter=rollcheck`.
  These exercise the device-grid strip snapping that `grab()`-based comparisons cannot
  (the backing-store flush region is exactly the trail class the
  `TimelineSurface::invalidateContent` comment warns about). The generic full rollcheck is
  not the fractional-scale gate: it has two unrelated, pre-existing scale-sensitive
  note/nudge assertions that fail identically in the trailing-hold baseline worktree.
- `PORYDAW_FORCE_UNCACHED_TIMELINE=1 PORYDAW_HOVER_GUIDE_ONLY=1 deno task checks
  build/porydaw_checks --filter=rollcheck`: the uncached escape hatch must paint the guide
  identically, isolating any cache-only assumption.
- Native-exposure windowing check (rollcheckwindowing) still passes: the guide strips ride
  the existing dirty-region flush path.

Manual pass on the real surfaces:

- Hover every automation node lane and the velocity area: one dotted full-height line
  follows the pointer x, clipped to the plot (no gutter, header, add-lane, or ruler ink).
- Move the pointer quickly across both surfaces: the old column erases without trails and
  the new column paints immediately (two narrow strips — visible as bounded repaint, not a
  sweeping band).
- Leave each surface: the guide disappears.
- Start each gesture kind (drag, pencil, band, pan, ramp, paint, relative) and each
  lifecycle edge (double-click tempo toggle, CC double-click insert prompt, Escape,
  focus loss, document/song swap, window resize): the guide retires at the boundary and
  never bleeds into gesture or post-lifecycle rendering; it re-arms on the next idle
  move after release.
- Guide and edit cursor overlap: the dashed cursor reads on top; the dotted guide is
  visually distinct from it and from `VoiceChangeArea`'s existing line.
- `VoiceChangeArea` behaves exactly as before, with no code changes.
