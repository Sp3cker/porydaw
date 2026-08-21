#include "ui/editordrawer/automationprojection.h"

#include <algorithm>
#include <cmath>

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/songview.h"

AutomationGeometry AutomationGeometry::resolve()
{
    AutomationGeometry geometry;
    geometry.rowDefaultHeight = layout::fontPx(4.0);
    geometry.rowMinimumHeight = layout::fontPx(7.0 / 3.0);
    geometry.rowMaximumHeight = layout::fontPx(32.0 / 3.0);
    geometry.rowWheelIncrement = layout::fontPx(1.0 / 3.0);
    geometry.addLaneStripHeight = layout::fontPx(5.0 / 3.0);
    geometry.plotOrigin = layout::fontPx(17.5 + 13.0 / 3.0);
    geometry.pointHitRadius = layout::fontPx(7.0 / 12.0);
    geometry.neutralSnapRadius = layout::fontPx(2.0 / 3.0);
    geometry.deleteTimeRadius = layout::fontPx(3.0 / 4.0);
    geometry.pointDetailThreshold = layout::fontPx(2.0);
    geometry.hoverPaintPadding = layout::fontPx(1.0 / 6.0);
    geometry.nodeDragActivationDistance = layout::fontPx(5.0 / 12.0);
    geometry.gridMinimumCellWidth = layout::fontPx(4.0 / 3.0);
    geometry.nodePaintRadius = layout::fontPxF(3.0 / 16.0);
    geometry.selectedNodeRingRadius = layout::fontPxF(9.0 / 32.0);
    geometry.nodeOutlineDipWidth = layout::fontPxF(1.0 / 12.0);
    geometry.selectedNodeRingDipWidth = layout::fontPxF(1.0 / 5.0);
    // Plot endpoint centers at the painted outer edge, including marker stroke.
    const qreal nodeOuterRadius = geometry.nodePaintRadius + geometry.nodeOutlineDipWidth;
    const qreal selectedNodeOuterRadius =
        geometry.selectedNodeRingRadius + geometry.selectedNodeRingDipWidth * 0.5;
    geometry.valuePlotPadding = qRound(std::max(nodeOuterRadius, selectedNodeOuterRadius));
    return geometry;
}

const MidiTimeline *AutomationProjection::timeline() const
{
    if (m_page)
        return m_page->timeline();
    return m_songView ? m_songView->timeline() : nullptr;
}

uint64_t AutomationProjection::gridSnapTicks(uint64_t tick, bool fine) const
{
    if (m_page)
        return std::max<uint64_t>(1, m_page->gridState(tick, fine).snapTicks);
    if (m_songView)
        return std::max<uint64_t>(1, m_songView->gridState(tick, fine).snapTicks);
    return 1;
}

uint64_t AutomationProjection::snapTickDown(double tick, bool fine) const
{
    tick = std::max(0.0, tick);
    if (!fine) {
        if (m_page)
            return m_page->snapTickDown(tick, false);
        return m_songView ? m_songView->snapTickDown(tick) : 0;
    }
    const uint64_t spacing = gridSnapTicks(uint64_t(tick), true);
    return uint64_t(tick / double(spacing)) * spacing;
}

uint64_t AutomationProjection::nextGridTick(uint64_t tick, bool fine, uint64_t limit) const
{
    if (tick >= limit)
        return limit;
    const uint64_t spacing = gridSnapTicks(tick, fine);
    const uint64_t candidate = spacing >= limit - tick ? limit : tick + spacing;
    if (gridSnapTicks(candidate, fine) == spacing)
        return candidate;
    uint64_t first = tick + 1;
    uint64_t last = candidate;
    while (first < last) {
        const uint64_t probe = first + (last - first) / 2;
        if (gridSnapTicks(probe, fine) == spacing)
            first = probe + 1;
        else
            last = probe;
    }
    return first;
}

AutomationProjection::PointerMapping AutomationProjection::pointerMapping(const NodeLane &lane,
                                                                          const QRect &body,
                                                                          qreal x, qreal y) const
{
    PointerMapping mapped;
    const MidiTimeline *songTimeline = timeline();
    if (!songTimeline)
        return mapped;
    const uint64_t length = songTimeline->lengthTicks;
    mapped.rawTick = std::clamp(rawTickAt(x), 0.0, double(length));
    mapped.point.value =
        std::clamp(qRound(valueAtY(body, m_geometry, lane.minimumValue(), lane.maximumValue(), y)),
                   lane.minimumValue(), lane.maximumValue());
    mapped.cell = snapCellAt(mapped.rawTick);
    mapped.point.tick = mapped.cell.tickBegin;
    return mapped;
}

double AutomationProjection::rawTickAt(qreal x) const
{
    const qreal contentX = std::max(qreal(m_geometry.plotOrigin), x) - m_geometry.plotOrigin;
    if (m_page)
        return std::max(0.0, m_page->tickAtContentX(contentX));
    return m_songView ? std::max(0.0, m_songView->tickAtContentX(contentX)) : 0.0;
}

qreal AutomationProjection::displayX(uint64_t tick, qreal devicePixelRatio) const
{
    if (m_page)
        return m_page->displayX(tick, m_geometry.plotOrigin, devicePixelRatio);
    return m_songView ? m_songView->displayX(tick, m_geometry.plotOrigin, devicePixelRatio) : 0.0;
}

uint64_t AutomationProjection::snapTickAt(qreal x, bool fine) const
{
    const double tick = rawTickAt(x);
    if (m_page)
        return m_page->snapTick(tick, fine);
    return m_songView ? m_songView->snapTick(tick, fine) : 0;
}

qreal AutomationProjection::valueY(const QRect &bounds, const AutomationGeometry &geometry,
                                   double minimum, double maximum, double value)
{
    const qreal top = bounds.top() + geometry.valuePlotPadding;
    const qreal bottom = bounds.bottom() - geometry.valuePlotPadding;
    const double clamped = std::clamp(value, minimum, maximum);
    return bottom -
           qreal((clamped - minimum) * (bottom - top) / std::max<qreal>(1.0, maximum - minimum));
}

double AutomationProjection::valueAtY(const QRect &bounds, const AutomationGeometry &geometry,
                                      double minimum, double maximum, qreal y)
{
    const qreal top = bounds.top() + geometry.valuePlotPadding;
    const qreal bottom = bounds.bottom() - geometry.valuePlotPadding;
    const qreal clamped = std::clamp(y, top, bottom);
    return minimum +
           double(bottom - clamped) * (maximum - minimum) / std::max<qreal>(1.0, bottom - top);
}

uint64_t AutomationProjection::fineSnapTick(double rawTick) const
{
    if (m_page)
        return m_page->snapTick(rawTick, true);
    return m_songView ? m_songView->snapTick(rawTick, true) : 0;
}

bool AutomationProjection::nodeMarkersVisible() const
{
    if (m_page)
        return m_page->pxPerBeat() >= m_geometry.pointDetailThreshold;
    return m_songView && m_songView->pxPerBeat() >= m_geometry.pointDetailThreshold;
}

AutomationGridCell AutomationProjection::snapCellAt(double rawTick) const
{
    const MidiTimeline *songTimeline = timeline();
    if (!songTimeline || songTimeline->lengthTicks == 0)
        return {};
    const uint64_t length = songTimeline->lengthTicks;
    const double clamped = std::clamp(rawTick, 0.0, double(length));
    const uint64_t tick = clamped >= double(length) ? length - 1 : uint64_t(std::floor(clamped));
    const uint64_t start = snapTickDown(double(tick), false);
    return {start, nextGridTick(start, false, length)};
}

const std::vector<AutomationGridCell> &
AutomationProjection::snapCellsCrossed(std::vector<AutomationGridCell> &cells,
                                       double previousRawTick, double currentRawTick) const
{
    cells.clear();
    const MidiTimeline *songTimeline = timeline();
    if (!songTimeline || songTimeline->lengthTicks == 0)
        return cells;
    const uint64_t length = songTimeline->lengthTicks;
    const bool forward = currentRawTick >= previousRawTick;
    const auto target = snapCellAt(currentRawTick);
    auto cell = snapCellAt(previousRawTick);
    while (cell.tickBegin < cell.tickEnd && cell.tickEnd <= length) {
        cells.push_back(cell);
        if (cell.tickBegin == target.tickBegin)
            return cells;
        if (forward) {
            const uint64_t nextStart = nextGridTick(cell.tickBegin, false, length);
            if (nextStart >= length)
                break;
            const auto next = snapCellAt(double(nextStart));
            if (next.tickBegin <= cell.tickBegin)
                break;
            cell = next;
        } else {
            if (cell.tickBegin == 0)
                break;
            const auto previous = snapCellAt(double(cell.tickBegin - 1));
            if (previous.tickBegin >= cell.tickBegin)
                break;
            cell = previous;
        }
    }
    cells.clear();
    return cells;
}
