#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"

#include <QScrollBar>
#include <QSizePolicy>
#include <QSpacerItem>
#include <QWheelEvent>

#include <algorithm>
#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;
using namespace songview;
using namespace songview::detail;

void SongView::setEditorHorizontalScroll(double px)
{
    setHScroll(px);
}
void SongView::setEditorTimeZoom(double pxPerBeatValue)
{
    if (!m_timeline)
        return;
    const double pxPerTick =
        std::clamp(pxPerBeatValue, double(m_geometry.timelineMinimumPixelsPerBeat),
                   double(m_geometry.timelineMaximumPixelsPerBeat)) /
        double(m_timeline->ticksPerBeat);
    if (pxPerTick != m_pxPerTick && m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_pxPerTick = pxPerTick;
    updateScrollbars();
    refreshTimelineViews();
    refreshDrawerPages();
}
qreal SongView::displayX(double tick, qreal origin, qreal dpr) const
{
    const qreal widgetX = origin + contentX(tick);
    return dpr > 0.0 ? std::round(widgetX * dpr) / dpr : widgetX;
}
double SongView::pxPerBeat() const
{
    return m_timeline ? m_pxPerTick * m_timeline->ticksPerBeat : m_pxPerTick * 24.0;
}
void SongView::zoomTimelineAtWheel(const QWheelEvent *event, qreal anchorContentX)
{
    const double zoomDelta = wheelAngleUnits(event);
    if (zoomDelta != 0.0)
        zoomAroundContentX(std::pow(1.0015, zoomDelta), anchorContentX);
}
void SongView::zoomAroundContentX(double factor, qreal anchorContentX)
{
    if (!m_timeline)
        return;
    const double tpb = double(m_timeline->ticksPerBeat);
    const double oldPxPerTick = m_pxPerTick;
    const double pxPerTick =
        std::clamp(oldPxPerTick * factor, double(m_geometry.timelineMinimumPixelsPerBeat) / tpb,
                   double(m_geometry.timelineMaximumPixelsPerBeat) / tpb);
    if (pxPerTick != oldPxPerTick && m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_pxPerTick = pxPerTick;
    m_scrollX = std::clamp(
        cursorAnchoredScroll(double(anchorContentX), oldPxPerTick, m_scrollX, m_pxPerTick),
        minHScroll(), maxHScroll());
    updateScrollbars();
    refreshTimelineViews();
    refreshDrawerPages();
}
void SongView::zoomKeyHeight(const QWheelEvent *event)
{
    if (!m_timeline)
        return;
    const double zoomDelta = wheelAngleUnits(event);
    if (zoomDelta == 0.0)
        return;
    const double oldH = m_keyHeight;
    const double newH = std::clamp(oldH * std::exp2(zoomDelta / 1200.0),
                                   double(m_geometry.pianoRollMinimumKeyHeight),
                                   double(m_geometry.pianoRollMaximumKeyHeight));
    if (newH == m_keyHeight)
        return;
    // Pin the content row under the cursor before projecting to the scrollbar.
    const double anchorY = event->position().y();
    const double anchoredScroll = cursorAnchoredScroll(anchorY, oldH, m_scrollY, newH);
    m_keyHeight = newH;
    m_roll->refreshTextLayout();
    updateScrollbars();
    setVScroll(std::clamp(anchoredScroll, 0.0, maxRollScroll()));
    // The camera scale changed even when the cursor anchor keeps its scroll
    // offset numerically unchanged.
    m_roll->invalidateContent();
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
        refreshTimelineViews();
        refreshDrawerPages();
    }
}
double SongView::minHScroll() const
{
    return m_timeline ? -leadPadPx() : 0.0;
}
double SongView::maxHScroll() const
{
    return m_timeline ? double(m_timeline->lengthTicks) * m_pxPerTick : 0.0;
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
        m_roll->invalidateContent();
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
    setHScroll(m_scrollX);

    m_vbar->blockSignals(true);
    m_vbar->setRange(0, scrollUnits(maxRollScroll()));
    m_vbar->setPageStep(scrollUnits(double(rollViewportHeight())));
    m_vbar->blockSignals(false);
    setVScroll(m_scrollY);
}
int SongView::viewportWidth() const
{
    return std::max(m_geometry.timelineViewportMinimumWidth,
                    m_roll->width() - m_geometry.pianoKeyboardWidth);
}
int SongView::rollViewportHeight() const
{
    const int drawerHeight = m_editorDrawer ? m_editorDrawer->height() : 0;
    return std::max(0, m_roll->height() - drawerHeight);
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
    const qreal dpr = m_roll->devicePixelRatioF();
    const qreal physicalPixel = logicalPhysicalPixel(dpr);
    const qreal displayedX = displayX(double(tick), lyt::space(Space::Zero), dpr);
    if (displayedX >= lyt::space(Space::Zero) && displayedX <= vw - physicalPixel)
        return;
    setHScroll(double(tick) * m_pxPerTick - vw * m_geometry.timelineRevealViewportFraction);
}
void SongView::ensureRangeVisible(uint64_t startTick, uint64_t endTick, bool preferEnd)
{
    const qreal x0 = contentX(double(startTick));
    const qreal x1 = contentX(double(endTick));
    const qreal vw = viewportWidth();
    const qreal dpr = m_roll->devicePixelRatioF();
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
