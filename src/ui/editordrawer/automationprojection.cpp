#include "ui/editordrawer/automationprojection.h"

#include <algorithm>
#include <cmath>

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"

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

AutomationProjection::PointerMapping AutomationProjection::pointerMapping(const NodeLane &lane,
                                                                          const QRect &body,
                                                                          qreal x, qreal y) const
{
    PointerMapping mapped;
    if (!m_page || !m_page->timeline())
        return mapped;
    const uint64_t length = m_page->timeline()->lengthTicks;
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
    return std::max(0.0, m_page->tickAtContentX(std::max(qreal(m_geometry.plotOrigin), x) -
                                                m_geometry.plotOrigin));
}

qreal AutomationProjection::displayX(uint64_t tick, qreal devicePixelRatio) const
{
    return m_page->displayX(tick, m_geometry.plotOrigin, devicePixelRatio);
}

uint64_t AutomationProjection::snapTickAt(qreal x, bool fine) const
{
    return m_page->snapTick(rawTickAt(x), fine);
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
    return m_page->snapTick(rawTick, true);
}

bool AutomationProjection::nodeMarkersVisible() const
{
    return m_page && m_page->pxPerBeat() >= m_geometry.pointDetailThreshold;
}

AutomationGridCell AutomationProjection::snapCellAt(double rawTick) const
{
    if (!m_page || !m_page->timeline() || m_page->timeline()->lengthTicks == 0)
        return {};
    const uint64_t length = m_page->timeline()->lengthTicks;
    const double clamped = std::clamp(rawTick, 0.0, double(length));
    const uint64_t tick = clamped >= double(length) ? length - 1 : uint64_t(std::floor(clamped));
    const uint64_t start = m_page->snapTickDown(double(tick), false);
    return {start, m_page->nextGridTick(start, false, length)};
}

const std::vector<AutomationGridCell> &
AutomationProjection::snapCellsCrossed(std::vector<AutomationGridCell> &cells,
                                       double previousRawTick, double currentRawTick) const
{
    cells.clear();
    if (!m_page || !m_page->timeline() || m_page->timeline()->lengthTicks == 0)
        return cells;
    const uint64_t length = m_page->timeline()->lengthTicks;
    const bool forward = currentRawTick >= previousRawTick;
    const auto target = snapCellAt(currentRawTick);
    auto cell = snapCellAt(previousRawTick);
    while (cell.tickBegin < cell.tickEnd && cell.tickEnd <= length) {
        cells.push_back(cell);
        if (cell.tickBegin == target.tickBegin)
            return cells;
        if (forward) {
            const uint64_t nextStart = m_page->nextGridTick(cell.tickBegin, false, length);
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
