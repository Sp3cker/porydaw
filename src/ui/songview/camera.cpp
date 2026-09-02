#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/quick/timelinequickview.h"
#include <QScrollBar>
#include <QSizePolicy>
#include <QSpacerItem>

#include <algorithm>
#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;
using namespace songview;
using namespace songview::detail;

namespace {

// Normalized timeline wheel zoom: momentum contributes nothing, pixel wheels
// weigh 5 per pixel while rotary wheels weigh 1 per 1/8-degree unit, and the
// delivered deltas alone carry direction (inverted() is deliberately
// ignored). Only the y axis zooms.
double timelineWheelZoomDelta(Qt::ScrollPhase phase, const QPoint &pixelDelta,
                              const QPoint &angleDelta)
{
    if (phase == Qt::ScrollMomentum)
        return 0.0;
    const bool isPixel = !pixelDelta.isNull();
    return double((isPixel ? pixelDelta : angleDelta).y()) * (isPixel ? 5.0 : 1.0);
}

} // namespace
void SongView::setEditorHorizontalScroll(double px)
{
    setHScroll(px);
}
void SongView::setEditorTimeZoom(double pxPerBeatValue)
{
    if (!m_timeline)
        return;
    const double pxPerBeat =
        std::clamp(pxPerBeatValue, double(m_geometry.timelineMinimumPixelsPerBeat),
                   double(m_geometry.timelineMaximumPixelsPerBeat));
    if (pxPerBeat != m_pxPerBeat && m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_pxPerBeat = pxPerBeat;
    updateScrollbars();
    refreshTimelineViews(cPlotDirty);
    refreshDrawerPages();
}
qreal SongView::displayX(double tick, qreal origin, qreal dpr) const
{
    const qreal widgetX = origin + contentX(tick);
    return dpr > 0.0 ? std::round(widgetX * dpr) / dpr : widgetX;
}
void SongView::zoomTimelineAtWheel(const songview::TimelineWheelInput &wheel, qreal anchorContentX)
{
    const double zoomDelta =
        timelineWheelZoomDelta(wheel.phase, wheel.pixelDelta, wheel.angleDelta);
    if (zoomDelta != 0.0)
        zoomAroundContentX(std::pow(1.0015, zoomDelta), anchorContentX);
}
void SongView::zoomAroundContentX(double factor, qreal anchorContentX)
{
    if (!m_timeline)
        return;
    // Anchoring works in the canonical beat scale: the tick under the
    // cursor is beat-space scaled by the axis's derived quotient, so a
    // timebase change cannot alter what the zoom keeps pinned.
    const double oldPxPerBeat = m_pxPerBeat;
    const double pxPerBeat =
        std::clamp(oldPxPerBeat * factor, double(m_geometry.timelineMinimumPixelsPerBeat),
                   double(m_geometry.timelineMaximumPixelsPerBeat));
    if (pxPerBeat != oldPxPerBeat && m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_pxPerBeat = pxPerBeat;
    m_scrollX = std::clamp(
        cursorAnchoredScroll(double(anchorContentX), oldPxPerBeat, m_scrollX, m_pxPerBeat),
        minHScroll(), maxHScroll());
    updateScrollbars();
    refreshTimelineViews(cPlotDirty);
    refreshDrawerPages();
}
void SongView::zoomKeyHeight(const songview::TimelineWheelInput &input)
{
    if (!m_timeline)
        return;
    if (input.phase == Qt::ScrollMomentum)
        return;
    // Same momentum/pixel/angle weighting as wheelAngleUnits(), value form.
    const QPoint delta = input.pixelDelta.isNull() ? input.angleDelta : input.pixelDelta;
    const double zoomDelta = double(delta.y()) * (input.pixelDelta.isNull() ? 1.0 : 5.0);
    if (zoomDelta == 0.0)
        return;
    const double oldH = m_keyHeight;
    const double newH = std::clamp(oldH * std::exp2(zoomDelta / 1200.0),
                                   double(m_geometry.pianoRollMinimumKeyHeight),
                                   double(m_geometry.pianoRollMaximumKeyHeight));
    if (newH == m_keyHeight)
        return;
    // Pin the content row under the cursor before projecting to the scrollbar.
    const double anchorY = input.position.y();
    const double anchoredScroll = cursorAnchoredScroll(anchorY, oldH, m_scrollY, newH);
    m_keyHeight = newH;
    m_roll->refreshTextLayout();
    updateScrollbars();
    setVScroll(std::clamp(anchoredScroll, 0.0, maxRollScroll()));
    // The camera scale changed even when the cursor anchor keeps its scroll
    // offset numerically unchanged.
    m_roll->requestQuickUpdate(PianoRollQuickDirty::All);
    refreshDrawerPages();
}
void SongView::scrollByPx(double dx)
{
    setHScroll(m_scrollX + dx);
}
void SongView::scrollRollBy(double dy)
{
    setVScroll(m_scrollY + dy);
}
void SongView::setHScroll(double px)
{
    const double newX = std::clamp(px, minHScroll(), maxHScroll());
    const bool cameraChanged = newX != m_scrollX;
    m_scrollX = newX;
    const int scrollbarValue = scrollUnits(m_scrollX);
    if (m_hbar->value() != scrollbarValue) {
        m_hbar->blockSignals(true);
        m_hbar->setValue(scrollbarValue);
        m_hbar->blockSignals(false);
    }
    if (cameraChanged) {
        refreshTimelineViews(cPlotDirty);
        refreshDrawerPages();
    }
}
double SongView::minHScroll() const
{
    // The pre-roll floor applies in both axis states: the fallback camera
    // rests at this home until a song binds.
    return -leadPadPx();
}
double SongView::maxHScroll() const
{
    return m_timeAxis.isBound() ? double(m_timeAxis.lengthTicks()) * pxPerTick() : 0.0;
}
void SongView::setVScroll(double y)
{
    const double newY = std::clamp(y, 0.0, maxRollScroll());
    const bool cameraChanged = m_scrollY != newY;
    m_scrollY = newY;
    const int scrollbarValue = scrollUnits(m_scrollY);
    if (m_vbar->value() != scrollbarValue) {
        m_vbar->blockSignals(true);
        m_vbar->setValue(scrollbarValue);
        m_vbar->blockSignals(false);
    }
    if (cameraChanged)
        m_roll->requestQuickUpdate(PianoRollQuickDirty::All);
}
double SongView::maxRollScroll() const
{
    return std::max(0.0, m_projection.totalHeight(m_keyHeight) - rollViewportHeight());
}
void SongView::updateScrollbars()
{
    m_hbar->blockSignals(true);
    m_hbar->setRange(scrollUnits(minHScroll()), scrollUnits(maxHScroll()));
    m_hbar->setPageStep(scrollUnits(double(viewportWidth())));
    m_hbar->blockSignals(false);
    // The unbound axis's provisional camera tracks the newly resolved
    // pre-roll home; a bound camera stays where its user put it.
    setHScroll(m_timeAxis.isBound() ? m_scrollX : minHScroll());

    m_vbar->blockSignals(true);
    m_vbar->setRange(0, scrollUnits(maxRollScroll()));
    m_vbar->setPageStep(scrollUnits(double(rollViewportHeight())));
    m_vbar->blockSignals(false);
    setVScroll(m_scrollY);
}
int SongView::viewportWidth() const
{
    // The canonical roll rectangle already excludes the vertical scrollbar;
    // its timeline origin is the piano-keyboard column.
    const std::optional<songview::TimelineBandGeometry> &roll =
        m_timelineBandLayout.geometry(songview::TimelineBand::Roll);
    const int width = roll ? roll->rect.width() - roll->timelineOrigin : 0;
    return std::max(m_geometry.timelineViewportMinimumWidth, width);
}
int SongView::rollViewportHeight() const
{
    const int drawerHeight = m_editorDrawer ? m_editorDrawer->height() : 0;
    const std::optional<songview::TimelineBandGeometry> &roll =
        m_timelineBandLayout.geometry(songview::TimelineBand::Roll);
    const int height = roll ? roll->rect.height() : 0;
    return std::max(0, height - drawerHeight);
}
double SongView::leadPadPx() const
{
    // Whole DIPs: the pad is a camera resting position (fresh songs and
    // "go to start" home here), and an integral camera keeps note edges
    // on the same raster seams as the classic scroll-0 home.
    return std::clamp(std::round(double(viewportWidth()) * 0.10), 48.0, 256.0);
}
void SongView::ensureTickVisible(uint64_t tick)
{
    const qreal vw = viewportWidth();
    const qreal dpr = m_quickView ? m_quickView->quickDevicePixelRatio() : devicePixelRatioF();
    const qreal physicalPixel = logicalPhysicalPixel(dpr);
    const qreal displayedX = displayX(double(tick), lyt::space(Space::Zero), dpr);
    if (displayedX >= lyt::space(Space::Zero) && displayedX <= vw - physicalPixel)
        return;
    setHScroll(double(tick) * pxPerTick() - vw * m_geometry.timelineRevealViewportFraction);
}
void SongView::ensureRangeVisible(uint64_t startTick, uint64_t endTick, bool preferEnd)
{
    const qreal x0 = contentX(double(startTick));
    const qreal x1 = contentX(double(endTick));
    const qreal vw = viewportWidth();
    const qreal dpr = m_quickView ? m_quickView->quickDevicePixelRatio() : devicePixelRatioF();
    const qreal physicalPixel = logicalPhysicalPixel(dpr);
    const qreal displayedX0 = displayX(double(startTick), lyt::space(Space::Zero), dpr);
    const qreal displayedX1 = displayX(double(endTick), lyt::space(Space::Zero), dpr);
    const qreal rightEdge = vw - physicalPixel;
    qreal dx = 0.0;
    if (displayedX1 - displayedX0 > rightEdge)
        // Wider than the viewport: the leading edge wins.
        dx = preferEnd ? x1 - rightEdge : x0;
    else if (displayedX1 > rightEdge)
        dx = x1 - rightEdge;
    else if (displayedX0 < 0.0)
        dx = x0;
    if (dx != 0.0)
        setHScroll(m_scrollX + dx);
}
void SongView::ensureKeyVisible(int key)
{
    const int row = m_projection.rowForPitch(key);
    if (row == songview::PitchProjection::cHiddenRow)
        return;
    const double y0 = row * m_keyHeight - m_scrollY;
    const double y1 = y0 + m_keyHeight;
    const int vh = rollViewportHeight();
    if (y0 < 0)
        setVScroll(m_scrollY + y0);
    else if (y1 > vh)
        setVScroll(m_scrollY + y1 - vh);
}
