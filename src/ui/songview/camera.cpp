#include "ui/editordrawer/editordrawer.h"
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
    const bool zoomChanged = m_camera.setTimeZoom(pxPerBeatValue);
    if (zoomChanged && m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    updateScrollbars();
    refreshTimelineViews(cPlotDirty);
    refreshDrawerPages();
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
    const auto r = m_camera.zoomAroundContentX(factor, anchorContentX);
    if (r.zoomChanged && m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
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
    if (!m_camera.zoomKeyHeight(std::exp2(zoomDelta / 1200.0), input.position.y()))
        return;
    m_roll->refreshTextLayout();
    updateScrollbars();
    // The camera scale changed even when the cursor anchor keeps its scroll
    // offset numerically unchanged.
    m_roll->requestQuickUpdate(PianoRollQuickDirty::All);
    refreshDrawerPages();
}
void SongView::scrollByPx(double dx)
{
    syncHorizontalCamera(m_camera.scrollByPx(dx));
}
void SongView::scrollRollBy(double dy)
{
    syncVerticalCamera(m_camera.scrollRollBy(dy));
}
void SongView::syncHorizontalCamera(bool cameraChanged)
{
    const int scrollbarValue = scrollUnits(m_camera.scrollX());
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
void SongView::setHScroll(double px)
{
    syncHorizontalCamera(m_camera.setHScroll(px));
}
void SongView::syncVerticalCamera(bool cameraChanged)
{
    const int scrollbarValue = scrollUnits(m_camera.scrollY());
    if (m_vbar->value() != scrollbarValue) {
        m_vbar->blockSignals(true);
        m_vbar->setValue(scrollbarValue);
        m_vbar->blockSignals(false);
    }
    if (cameraChanged)
        m_roll->requestQuickUpdate(PianoRollQuickDirty::All);
}
void SongView::setVScroll(double y)
{
    syncVerticalCamera(m_camera.setVScroll(y));
}
void SongView::updateScrollbars()
{
    m_camera.setViewport(double(viewportWidth()), double(rollViewportHeight()));
    m_hbar->blockSignals(true);
    m_hbar->setRange(scrollUnits(m_camera.minHScroll()), scrollUnits(m_camera.maxHScroll()));
    m_hbar->setPageStep(scrollUnits(double(viewportWidth())));
    m_hbar->blockSignals(false);
    // The unbound axis's provisional camera tracks the newly resolved
    // pre-roll home; a bound camera stays where its user put it.
    setHScroll(m_timeAxis.isBound() ? m_camera.scrollX() : m_camera.minHScroll());

    m_vbar->blockSignals(true);
    m_vbar->setRange(0, scrollUnits(m_camera.maxRollScroll()));
    m_vbar->setPageStep(scrollUnits(double(rollViewportHeight())));
    m_vbar->blockSignals(false);
    setVScroll(m_camera.scrollY());
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
    const int drawerHeight = m_editorDrawer ? m_editorDrawer->overlayHeight() : 0;
    const std::optional<songview::TimelineBandGeometry> &roll =
        m_timelineBandLayout.geometry(songview::TimelineBand::Roll);
    const int height = roll ? roll->rect.height() : 0;
    return std::max(0, height - drawerHeight);
}
void SongView::ensureTickVisible(uint64_t tick)
{
    const qreal dpr = m_quickView ? m_quickView->quickDevicePixelRatio() : devicePixelRatioF();
    syncHorizontalCamera(m_camera.ensureTickVisible(tick, dpr));
}
void SongView::ensureRangeVisible(uint64_t startTick, uint64_t endTick, bool preferEnd)
{
    const qreal dpr = m_quickView ? m_quickView->quickDevicePixelRatio() : devicePixelRatioF();
    syncHorizontalCamera(m_camera.ensureRangeVisible(startTick, endTick, preferEnd, dpr));
}
void SongView::ensureKeyVisible(int key)
{
    syncVerticalCamera(m_camera.ensureKeyVisible(key));
}
