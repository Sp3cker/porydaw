# TempoStrip migration plan

Extract the tempo lane from the automation drawer into `songview::TempoStrip`, a
fixed-height timeline-aligned strip between `TimeRuler` and `rollPane`.
Design: workflowz 2026-08-21 (3 designs, 3-judge panel; C skeleton + A seams,
B coordinator rejected 3-0).

## Decisions

1. **Always visible, fixed height** (`AutomationGeometry::rowDefaultHeight`). No
   expand/collapse, no visibility toggle, no new sidecar key. Replaces
   `TempoLane::m_expanded` and `EditorAutomationRowId{Tempo}` height/range
   persistence; legacy `"tempo"` sidecar keys are discarded on load, never written.
2. **Cross-lane tempo+CC multi-node drag and cross-surface band selection are
   removed intentionally.** They were artifacts of tempo living at node-stack slot 0
   (`automationcanvas_gesture.cpp:79-133`). Strip band publishes
   `{scope=Lanes, tempo=true, lanes={}}`. `EditorSelectionModel` keeps its tempo
   flag untouched (`selectioncheck.cpp` stays green).
3. **Shared seams, two real users each:**
   - `NodeLaneHoverState` decoupled: `NodeLaneHoverTarget` value
     (bounds/font/dpr/revision/ready) in, dirty `QRegion` out. No callbacks.
   - `AutomationProjection` gains an additive `const SongView *` constructor so
     `nodelane::paintNodeLane` runs on the strip. Existing page ctor unchanged.
4. **File layout:** `src/ui/songview/tempostrip.{h,cpp,_input.cpp,_paint.cpp}`
     beside `OtherStrip`. Private `TempoLane` NodeLane adapter inside the strip
     module. Delete `src/ui/editordrawer/tempolane.{h,cpp}` and
     `src/ui/editordrawer/nodelane/tempoadapter.cpp`.

## Component contract

```cpp
// src/ui/songview/tempostrip.h
namespace songview {
class TempoStrip final : public TimelineSurface {
public:
    explicit TempoStrip(SongView &view);
    int plotOrigin() const noexcept;
    void cancelInteraction();
    bool gestureActive() const noexcept;
protected:                       // TimelineSurface + Qt events
    void paintContent(QPainter &) override;
    void contentGeometryChanged() override;
    // mousePressEvent/mouseMoveEvent/mouseReleaseEvent/
    // mouseDoubleClickEvent/keyPressEvent/leaveEvent/event
private:
    class TempoLane final : public NodeLane { ... };  // SongView-bound adapter
    SongView &m_view;
    QRect m_body;
    std::vector<TempoPoint> m_clipboard;
    std::optional<NodeDragGesture> m_drag;   // or SweepGesture variant
    BandGesture m_band;
    NodeLaneHoverState m_hover;
    NodeDoubleClickGuard m_deletedNodeClick;
};
}
```

Gesture UX preserved 1:1 from the drawer lane: drag (+Shift axis lock),
double-click BPM prompt add, stationary-click delete (+double-click guard),
right-drag band select, hover value pill, Copy/Paste/Clear menu, one undo per
gesture via `resolveTempoMoves` -> `SongDocument::applyTempoEdit`. Pencil mode
stays CC-only (drawer-owned action).

## SongView wiring

- Construct after `m_ruler` (songview.cpp:121-124), `vbox->addWidget(m_tempoStrip)`.
- `timelineBands()` (songview.cpp:100-108): unconditional `{*m_tempoStrip, plotOrigin}`.
- Add to `refreshTimelineViews()` (songview.cpp:565-571), `setDocument`
  documentChanged cancel+invalidate (songview.cpp:306-325), camera scroll/zoom
  paths (camera.cpp:24-119), `cancelActiveInteractions()`, `userGestureActive()`.
- Gutter `[0, plotOrigin)` paints "Tempo (BPM)" title; body paints grid +
  `nodelane::paintNodeLane` + reticles with `song_view_automation_tempo_curve`.

## AutomationCanvas cutover (CC-only)

Remove `m_tempoLane`, `contentTopInset` tempo term, header hit test, expanded
gating, `index == 0` branches, front-slot commit merge, tempo menus/prompts.
CC `LaneHandle` becomes 0-based matching `rows()`. VoiceChangeLane keeps its
slot; inset = voice height only.

## Waves

1. **Seams:** `NodeLaneHoverTarget`/QRegion hover decoupling + `AutomationProjection`
   SongView ctor; migrate canvas call sites; zero behavior change. Run
   automation-gestures + automation checks.
2. **Strip:** implement tempostrip files + private adapter; CMake sources.
   New `src/checks/tempostripcheck.cpp` (mount/DPR alignment, fixed height,
   Shift lock, stationary delete, double-click add, band publishes tempo=true
   lanes={}, copy/paste/clear, one undo per gesture).
3. **Wiring + cutover:** SongView mount/bands/refresh/cancel; remove canvas tempo;
   reindex CC handles; delete old tempo files. Run rollcheck family.
4. **State + harnesses:** retire Tempo row identity in editorviewstate/viewsidecar;
   update automationgesturecheck rig (CC-only, strip helpers), crosslane
   (independent tempo-only + CC-only cases), rollcheckautomation_paint (strip
   paint), mainwindowroutingcheck/rollcheck sidecar expectations. Full suite.

## Explicitly not abstracted

No LaneStrip base (one consumer). No gesture coordinator. VoiceChangeLane stays
independent (non-node surface). Pencil mode not carried to the strip.
