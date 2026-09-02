#pragma once

#include <cstdint>

#include "ui/pitchprojection.h"
#include "ui/songview/timeaxis.h"

namespace songview {

// Zoom/scroll camera for one song tab: the tick<->pixel mapping shared by
// ruler, roll, strip, drawer, and quick scene. SongView owns it and pushes
// widget facts in (viewport, limits); the camera never pulls widgets and
// never notifies anyone — mutators report change, the host redraws.
class TimeCamera
{
  public:
    struct Limits {
        double minPixelsPerBeat = 16.0;
        double maxPixelsPerBeat = 1024.0;
        double minKeyHeight = 4.0;
        double maxKeyHeight = 64.0;
        double revealViewportFraction = 1.0 / 3.0; // ensureTickVisible anchor
    };
    struct ZoomResult {
        bool zoomChanged = false;
        bool scrollChanged = false;
    };

    // axis and projection are stable SongView members (songview.h:742-743);
    // the camera holds references and never rebinds. Axis rebind-to-timeline
    // (songview.cpp:342, 451) and projection rebuilds flow through in place.
    explicit TimeCamera(const TimeAxis &axis, const PitchProjection &projection);

    // host pushes; camera caches and uses these in clamps/pads
    void setLimits(const Limits &limits);
    void setViewport(double widthPx, double rollHeightPx);

    // map (pure)
    double pxPerTick() const noexcept; // pxPerBeat() / axis.ticksPerBeat()
    double pxPerBeat() const;
    double scrollX() const; // new getter: viewState().scrollPx,
                            // drawercoordination.cpp:150,
                            // scrollbar value sync
    double scrollY() const;
    double keyHeight() const;
    double contentX(double tick) const;    // tick * pxPerTick - scrollX
    double tickAtContentX(double x) const; // (x + scrollX) / pxPerTick
    double displayX(double tick, double origin, double dpr) const;

    // bounds (derived from cached viewport/limits/axis/projection)
    double leadPadPx() const;     // round(viewportWidth * 0.10) clamped [48, 256]
    double minHScroll() const;    // -leadPadPx()
    double maxHScroll() const;    // axis.isBound() ? lengthTicks * pxPerTick : 0
    double maxRollScroll() const; // max(0, projection.totalHeight(keyHeight)
                                  // - rollHeightPx)

    // mutate — return camera-changed; host owns every redraw tail.
    // All clamp internally. Unanchored setters are the session-restore path.
    bool setHScroll(double px);
    bool setVScroll(double y);
    bool scrollByPx(double dx);          // horizontal
    bool scrollRollBy(double dy);        // vertical
    bool setTimeZoom(double pxPerBeat);  // no anchor, scroll kept
    bool setKeyHeight(double keyHeight); // no anchor
    ZoomResult zoomAroundContentX(double factor, double anchorContentX);
    bool zoomKeyHeight(double factor, double anchorY);
    bool ensureTickVisible(uint64_t tick, double dpr);
    bool ensureRangeVisible(uint64_t startTick, uint64_t endTick, bool preferEnd, double dpr);
    bool ensureKeyVisible(int key); // uses ctor projection; cHiddenRow -> false

  private:
    const TimeAxis &m_axis;
    const PitchProjection &m_projection;
    Limits m_limits;
    double m_viewportWidth = 0.0;
    double m_rollHeight = 0.0;
    double m_pxPerBeat = 0.0;
    double m_scrollX = 0.0;
    double m_scrollY = 0.0;
    double m_keyHeight = 0.0;
};

} // namespace songview
