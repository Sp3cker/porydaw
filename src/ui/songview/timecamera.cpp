#include "ui/songview/timecamera.h"

#include <algorithm>
#include <cmath>

namespace songview {
namespace {

// One physical pixel in DIPs at the given device pixel ratio; a non-positive
// DPR falls back to 1.0 (moved from songview::detail::logicalPhysicalPixel).
double logicalPhysicalPixel(double dpr)
{
    return dpr > 0.0 ? 1.0 / dpr : 1.0;
}

// The scroll offset that keeps the content point under the cursor anchored
// while the content scale moves from oldScale to newScale (moved from
// songview::detail::cursorAnchoredScroll).
double cursorAnchoredScroll(double anchor, double oldScale, double oldScroll, double newScale)
{
    const double content = (anchor + oldScroll) / oldScale;
    return content * newScale - anchor;
}

} // namespace

TimeCamera::TimeCamera(const TimeAxis &axis, const PitchProjection &projection)
    : m_axis(axis)
    , m_projection(projection)
{}

void TimeCamera::setLimits(const Limits &limits)
{
    m_limits = limits;
}

void TimeCamera::setViewport(double widthPx, double rollHeightPx)
{
    m_viewportWidth = widthPx;
    m_rollHeight = rollHeightPx;
}

double TimeCamera::pxPerTick() const noexcept
{
    return m_pxPerBeat / double(m_axis.ticksPerBeat());
}

double TimeCamera::pxPerBeat() const
{
    return m_pxPerBeat;
}

double TimeCamera::scrollX() const
{
    return m_scrollX;
}

double TimeCamera::scrollY() const
{
    return m_scrollY;
}

double TimeCamera::keyHeight() const
{
    return m_keyHeight;
}

double TimeCamera::contentX(double tick) const
{
    return tick * pxPerTick() - m_scrollX;
}

double TimeCamera::tickAtContentX(double x) const
{
    return (x + m_scrollX) / pxPerTick();
}

double TimeCamera::displayX(double tick, double origin, double dpr) const
{
    const double widgetX = origin + contentX(tick);
    return dpr > 0.0 ? std::round(widgetX * dpr) / dpr : widgetX;
}

double TimeCamera::leadPadPx() const
{
    // Whole DIPs: the pad is a camera resting position (fresh songs and
    // "go to start" home here), and an integral camera keeps note edges
    // on the same raster seams as the classic scroll-0 home.
    return std::clamp(std::round(m_viewportWidth * 0.10), 48.0, 256.0);
}

double TimeCamera::minHScroll() const
{
    // The pre-roll floor applies in both axis states: the fallback camera
    // rests at this home until a song binds.
    return -leadPadPx();
}

double TimeCamera::maxHScroll() const
{
    return m_axis.isBound() ? double(m_axis.lengthTicks()) * pxPerTick() : 0.0;
}

double TimeCamera::maxRollScroll() const
{
    return std::max(0.0, m_projection.totalHeight(m_keyHeight) - m_rollHeight);
}

bool TimeCamera::setHScroll(double px)
{
    const double newX = std::clamp(px, minHScroll(), maxHScroll());
    const bool cameraChanged = newX != m_scrollX;
    m_scrollX = newX;
    return cameraChanged;
}

bool TimeCamera::setVScroll(double y)
{
    const double newY = std::clamp(y, 0.0, maxRollScroll());
    const bool cameraChanged = m_scrollY != newY;
    m_scrollY = newY;
    return cameraChanged;
}

bool TimeCamera::scrollByPx(double dx)
{
    return setHScroll(m_scrollX + dx);
}

bool TimeCamera::scrollRollBy(double dy)
{
    return setVScroll(m_scrollY + dy);
}

bool TimeCamera::setTimeZoom(double pxPerBeat)
{
    const double newPxPerBeat =
        std::clamp(pxPerBeat, m_limits.minPixelsPerBeat, m_limits.maxPixelsPerBeat);
    const bool cameraChanged = newPxPerBeat != m_pxPerBeat;
    m_pxPerBeat = newPxPerBeat;
    return cameraChanged;
}

bool TimeCamera::setKeyHeight(double keyHeight)
{
    const double newKeyHeight = std::clamp(keyHeight, m_limits.minKeyHeight, m_limits.maxKeyHeight);
    const bool cameraChanged = newKeyHeight != m_keyHeight;
    m_keyHeight = newKeyHeight;
    return cameraChanged;
}

TimeCamera::ZoomResult TimeCamera::zoomAroundContentX(double factor, double anchorContentX)
{
    // Anchoring works in the canonical beat scale: the tick under the
    // cursor is beat-space scaled by the axis's derived quotient, so a
    // timebase change cannot alter what the zoom keeps pinned.
    const double oldPxPerBeat = m_pxPerBeat;
    const double oldScrollX = m_scrollX;
    m_pxPerBeat =
        std::clamp(oldPxPerBeat * factor, m_limits.minPixelsPerBeat, m_limits.maxPixelsPerBeat);
    m_scrollX =
        std::clamp(cursorAnchoredScroll(anchorContentX, oldPxPerBeat, m_scrollX, m_pxPerBeat),
                   minHScroll(), maxHScroll());
    ZoomResult result;
    result.zoomChanged = m_pxPerBeat != oldPxPerBeat;
    result.scrollChanged = m_scrollX != oldScrollX;
    return result;
}

bool TimeCamera::zoomKeyHeight(double factor, double anchorY)
{
    const double oldH = m_keyHeight;
    const double newH = std::clamp(oldH * factor, m_limits.minKeyHeight, m_limits.maxKeyHeight);
    if (newH == m_keyHeight)
        return false;
    // Pin the content row under the cursor before projecting to the scroll
    // offset. The camera scale changed even when the cursor anchor keeps its
    // scroll offset numerically unchanged.
    const double anchoredScroll = cursorAnchoredScroll(anchorY, oldH, m_scrollY, newH);
    m_keyHeight = newH;
    setVScroll(std::clamp(anchoredScroll, 0.0, maxRollScroll()));
    return true;
}

bool TimeCamera::ensureTickVisible(uint64_t tick, double dpr)
{
    const double vw = m_viewportWidth;
    const double physicalPixel = logicalPhysicalPixel(dpr);
    const double displayedX = displayX(double(tick), 0.0, dpr);
    if (displayedX >= 0.0 && displayedX <= vw - physicalPixel)
        return false;
    return setHScroll(double(tick) * pxPerTick() - vw * m_limits.revealViewportFraction);
}

bool TimeCamera::ensureRangeVisible(uint64_t startTick, uint64_t endTick, bool preferEnd,
                                    double dpr)
{
    const double x0 = contentX(double(startTick));
    const double x1 = contentX(double(endTick));
    const double vw = m_viewportWidth;
    const double physicalPixel = logicalPhysicalPixel(dpr);
    const double displayedX0 = displayX(double(startTick), 0.0, dpr);
    const double displayedX1 = displayX(double(endTick), 0.0, dpr);
    const double rightEdge = vw - physicalPixel;
    double dx = 0.0;
    if (displayedX1 - displayedX0 > rightEdge)
        // Wider than the viewport: the leading edge wins.
        dx = preferEnd ? x1 - rightEdge : x0;
    else if (displayedX1 > rightEdge)
        dx = x1 - rightEdge;
    else if (displayedX0 < 0.0)
        dx = x0;
    if (dx != 0.0)
        return setHScroll(m_scrollX + dx);
    return false;
}

bool TimeCamera::ensureKeyVisible(int key)
{
    const int row = m_projection.rowForPitch(key);
    if (row == PitchProjection::cHiddenRow)
        return false;
    const double y0 = row * m_keyHeight - m_scrollY;
    const double y1 = y0 + m_keyHeight;
    const double vh = m_rollHeight;
    if (y0 < 0)
        return setVScroll(m_scrollY + y0);
    if (y1 > vh)
        return setVScroll(m_scrollY + y1 - vh);
    return false;
}

} // namespace songview
