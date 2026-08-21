# Gesture deduplication plan — prerequisite for VoiceLane

## Goal

Delete the gesture-mechanics duplication between `TempoLane` and the generic
`AutomationArea` CC path before the voice-change lane is extracted. After this
plan, all lane types consume one set of gesture primitives; VoiceLane is written
once against them instead of becoming a third copy.

Scope approved by user 2026-08-20: Phases 1, 2, and 3 (option A — tempo lane
adopts the exact CC-lane gesture behavior, no tempo-specific drag policy).
Phase 4 (commit-shape alignment) is deferred.

Non-goals: no polymorphic `LaneType` interface, no `AutomationLaneKind` core
model, no commit-path unification (`applyTempoEdit` vs `writeLanePoints` stay
separate), no VoiceLane implementation in this plan, no `forGridTicks`
extraction (critique showed it recovers ~0 net lines — the three loops share
only a 6-line control shell).

This revision incorporates the Plan-agent critique (2026-08-20). Net sizing is
~60 lines deleted now, plus the avoided third implementation in VoiceLane.

## Where the shared code lives

`automationgesture.h` already declares itself the page-free domain layer:
"consumes plain values, produces commit values; the widget keeps Qt policy."
Extend it. Do not create a parallel primitives header.

## Phase 0 — Paint file discipline (behavior-neutral)

`automationpaint.cpp` is 746 lines, over the 600-line repo ceiling. Before
adding any paint helper, move the coherent preview-paint block —
`paintHover`, `paintNodeDragPreview`, `paintPencilPreview`
(automationpaint.cpp:299-552) — to `automationpaintpreview.cpp` (~250L).
Result: automationpaint.cpp under 500L. Own commit, no behavior change, so the
Phase 1 paint diff stays reviewable.

## Phase 1 — Earned primitives only

### 1A. `upsertByTick` (automationgesture.h)

```cpp
template <class Points, class Point>
void upsertByTick(Points &points, Point point);
```

Kills 3 copies: `extendSweepPoints` inline (automationgesture.h:149-160),
`TempoLane::appendDrawPoint` (tempolane.cpp:357-365),
`AutomationPencilGesture::upsertPoint` (automationpencilgesture.h:57).

Placement decision: `automationpencilgesture.cpp` will include the aggregate
`automationgesture.h` (implementation-only dependency; pragma-once handles the
reverse include). Accept and note it; do not create a utility micro-header.

### 1B. `nearestPointInRadius` (automationgesture.h)

```cpp
// Precondition: points sorted by .tick and xOf(point) monotonic in tick
// (early termination relies on it).
// Tie rule: exact equidistant candidates resolve to the LATER tick
// (matches current generic-path behavior at automationrows.cpp:349-357;
// tempo's exact-tie corner changes from earlier-tick — accepted, documented).
template <class Points, class XOf, class YOf>
std::optional<std::size_t> nearestPointInRadius(const Points &points,
                                                double centerRawTick,
                                                QPointF pos, qreal radius,
                                                XOf &&xOf, YOf &&yOf);
```

Kills 2 copies: `AutomationRows::cachedPointHit` (automationrows.cpp:306-361)
and `TempoLane::hitPoint` (tempolane.cpp:309-351). Both call sites verified to
adapt via short closures (generic maps y through valuePlotBounds/row min-max;
tempo through static `AutomationProjection::valueY` on m_body). Return index;
the generic caller dereferences to `DocLanePoint` itself.

### 1C. `paintPlainGridFallback` (automation::paint)

Only the common solid base-grid loop, called after `page.paintGrid(...)`
returns false. Kills 2 copies: CC base grid (automationpaint.cpp:157-167) and
tempo grid (tempolanepaint.cpp:112-124). The voice subdivision pass
(automationpaint.cpp:130-156) is a **different function** — distinct pen,
`gridState`/`ticksPerBeat`/`pxPerBeat` inputs, painted before the base grid.
It stays separate; do not add a row-kind flag.

`paintEditCursor`: add only for single ownership of theme/pen policy
(automationpaint.cpp:291-295, tempolanepaint.cpp:160-164). Line-neutral; not
counted in sizing.

### 1D. Tempo header/plot paint separation (user-reported bug, 2026-08-20)

Bug: with the tempo lane open, its header-right point-count caption paints at
`m_header.adjusted(geometry.plotOrigin, 0, …)` — the header's *plot* region —
and the tempo step curve is not clipped to the lane's own plot horizontally,
so both draw into the first track row's header/canvas (tempo paints first in
`AutomationArea::paintContent`, then row headers repaint — corrupt overlap).

Fix, taking inspiration from `paintRow`'s two-phase structure:

1. Split `TempoLane::paint` into header and body phases with header
   paint clipped to `m_header` (gutter + header rect only).
2. Clip the body/curve pass to the lane's own plot rect:
   `QRect(plotOrigin, m_body.top(), width − plotOrigin, m_body.height())` —
   mirror `paintRow`'s `painter.setClipRect(plot, Qt::IntersectClip)`
   (automationpaint.cpp:~128).
3. Move the point-count caption into the label gutter like `RowPaintParams`
   rows do (primary title + secondary caption boxes, automationpaint.cpp:95-125),
   instead of drawing it in the plot region.
4. Tempo header should repaint its own background before drawing (rows rely
   on the global fill + repaint order; tempo's selection reticle/clip needs
   the header region painted deliberately).

### NOT extracted: `forGridTicks`

The sweep/ramp/tempo-draw loops share only:

```cpp
for (uint64_t tick = first;;) {
    emit(tick);
    if (tick == last)
        break;
    tick = nextGridTick(tick, fine, last);
}
```

Lerp sources, clamping, state mutation all differ; tempo additionally guards
non-progress (`following <= tick`, tempolane.cpp:394-397). A template nets ~0
lines and hides the guard asymmetry. Leave the repeated shell; add one comment
noting the endpoint-inclusive contract.

## Phase 2 — BandGesture state machine

Add to `automationgesture.h`:

```cpp
struct BandGesture {
    bool pending = false;
    bool active = false;
    QPoint pressPos;
    uint64_t startTick = 0;
    uint64_t endTick = 0;

    void press(QPoint pos, uint64_t tick);
    // Owns QApplication::startDragDistance. Returns true only on the move
    // that first activates (callers clear locked hover on that transition).
    bool move(QPoint pos, uint64_t tick);
    // Clears pending/active. Returns:
    //   nullopt            — never activated (click)
    //   {t, t}             — activated drag, snapped width zero
    //   {first, last}      — activated drag, first < last
    std::optional<std::pair<uint64_t, uint64_t>> release();
    void clear() { *this = {}; }
};
```

The three release outcomes are load-bearing; the two callers differ on
`{t,t}`:

- TempoLane: only non-empty publishes a time selection; click AND zero-width
  both fall through to release-position menu routing (selection menu → lane
  menu → point menu, tempolane.cpp:214-240).
- AutomationArea: only non-empty publishes; zero-width clears the selection
  with no menu; click runs point/time-selection routing
  (automationarea_input.cpp:295-336).

Callers keep their own extra state: AutomationArea keeps `rightRow`/`endRow`;
TempoLane keeps its right-button-lost cancellation
(`!(event->buttons() & Qt::RightButton)` → clear, tempolane.cpp:162-165),
which `move(pos,tick)` does not own.

Convert ALL consumers, including the ones outside input dispatch:
`bandPreviewContains`/`bandPreviewContainsRow` (automationarea.cpp:89-106),
`cancelInteraction` (:181-193), band preview paint (:385-393). TempoLane's
double-arm in mousePress (identical fields at tempolane.cpp:118-127 and
:139-149) collapses to one `press()` call.

## Phase 3 — Tempo drag adopts the CC gesture exactly (option A)

Delete TempoLane's inline drag policy (tempolane.cpp:178-196): the unlatched
per-event axis decision and the no-Shift 1px vertical dead-zone. Replace with
the CC lifecycle, reproduced locally:

1. `DragState` gains `Slop dragSlop; AxisLock axisLock = AxisLock::None;`
   (tempolane.h:52-58).
2. On move: if slop not exceeded and travel < `nodeDragActivationDistance`,
   do nothing. First over-threshold move arms the slop and resets current to
   original — it commits no movement. Subsequent deltas are re-anchored as
   `pressPosition + (position - dragSlop.origin)`, matching the CC caller
   (automationarea_gesture.cpp:69-77 — the re-origin lives in the caller, not
   `NodeDragGesture::update`; tempo must reproduce it too).
3. `axisLock = resolveAxisLock(axisLock, shift, pressPosition, position,
   activationDistance)` every move — releasing Shift returns `None` and the
   assignment clears the latch.
4. `applyAxisLock(axisLock, original, current)` with an explicit
   `TempoPoint`↔`ValuePoint` adapter. The adapter works in stored
   microseconds-per-quarter-note, NOT rounded BPM — no precision loss through
   the lock.

Accepted behavior changes: axis decision now latches; the 1px dead-zone is
gone (phantom protection — committed values round to whole BPM through
`tempoBpmAt`); drags gain activation slop. No new single-node drag helper —
it would hide ~20 lines behind a second drag interface the generic path can't
use.

## Migration order

Note: Implemting/Orchestration agent MUST delegate to reviewer agent to run `thermo-nuclear-code-review` AFTER each numbered phase and address plan adherence findings.
1. Phase 0 paint split — own commit, checks green.
2. Phase 1A+1B primitives + caller conversions — one commit, zero behavior
   change except the documented exact-tie corner, checks green.
3. Phase 1C paint policy — one commit, zero behavior change, checks green.

4. Phase 2 BandGesture + all call sites — one commit, zero behavior change,
   checks green.
5. Phase 3 axis-lock adoption — one commit, intentional behavior change,
   checks green + manual tempo-node drag verification (Shift-horizontal locks
   value, Shift-vertical locks time, release restores two-axis, sub-threshold
   move commits nothing).

Phases 0–2 are prerequisites for VoiceLane (it needs band, hit-test, and grid
paint immediately). Phase 3 lands before VoiceLane so the new lane inherits
the unified policy.

## Verification

- `deno task checks build/porydaw_checks` after each commit —
  rollcheckautomation, automationgesturecheck, selectioncheck, editcheck,
  rollcheckdrawer cover the converted paths.
- New tempo interaction coverage in rollcheckautomation.cpp (near
  :1085-1113, beside existing generic band checks): header/body right click,
  point menu, time-selection menu, non-empty band, zero-width activated band.
  No TempoLane input coverage exists today.
- Phase 3 manual: drag a tempo node in the running app per step 5 above.

## Sizing (net physical LOC, helpers + adapters counted)

| Phase | Net |
|---|---:|
| 0 | 0 (move) |
| 1 | −45 to −55 |
| 2 | −10 to −15 (BandGesture itself costs ~35-45L) |
| 3 | 0 to +8 |
| **Total** | **~−60** |

The payoff is structural, not line count: VoiceLane gets written once against
primitives and the third duplication never exists.

## Out of scope

- Phase 4: `TempoEdit::replaceRange` commit-shape alignment (~10L, optional).
- VoiceLane itself, `DOC_CC_VOICE` sentinel death, core voice API.
- Clipboard unification (cross-kind paste is meaningless).
- Menu, hover-label, and step-curve dedup (small, low-value).
- Voice subdivision grid unification (different function, stays separate).
