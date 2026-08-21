#include "ui/editordrawer/automationprojection.h"

#include <algorithm>
#include <cmath>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"
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

int AutomationProjection::rowHeight(const AutomationRow &row) const
{
    if (!m_page)
        return m_geometry.rowDefaultHeight;
    return std::clamp(m_page->laneHeightFor(row.id), m_geometry.rowMinimumHeight,
                      m_geometry.rowMaximumHeight);
}

int AutomationProjection::rowTop(int index) const
{
    int top = m_topInset;
    for (int row = 0; row < index && row < int(m_rows.size()); ++row)
        top += rowHeight(m_rows[row]);
    return top;
}

std::pair<int, int> AutomationProjection::valuePlotBounds(int index) const
{
    const int top = rowTop(index);
    const int height = rowHeight(m_rows[index]);
    return {top + m_geometry.valuePlotPadding, top + height - m_geometry.valuePlotPadding};
}

int AutomationProjection::rowIndexAt(int y) const
{
    int bottom = m_topInset;
    for (int row = 0; row < int(m_rows.size()); ++row) {
        bottom += rowHeight(m_rows[row]);
        if (y < bottom)
            return row;
    }
    return -1;
}

int AutomationProjection::rowBoundaryAt(int y) const
{
    int bottom = m_topInset;
    for (int row = 0; row < int(m_rows.size()); ++row) {
        bottom += rowHeight(m_rows[row]);
        if (std::abs(y - bottom) <= layout::singlePixel())
            return row;
    }
    return -1;
}

int AutomationProjection::rowMinimum(const AutomationRow &row) const
{
    if (row.id.kind != EditorAutomationRowKind::ControlChange)
        return CoreTimeDefaults::kMinCcValue;
    return CoreTimeDefaults::laneValueMinimum(row.id.controller);
}

int AutomationProjection::rowMaximum(const AutomationRow &row) const
{
    if (row.id.kind != EditorAutomationRowKind::ControlChange)
        return CoreTimeDefaults::kMaxCcValue;
    if (row.id.controller == automation::kBendController ||
        !automation::rangeZoomable(row.id.controller))
        return CoreTimeDefaults::laneValueMaximum(row.id.controller);
    int dataMaximum = 0;
    if (const auto *lane = laneFor(row))
        for (const auto &point : lane->points)
            dataMaximum = std::max(dataMaximum, point.value);
    const auto it = m_page->m_viewState.laneRanges.find(row.id);
    const uint8_t mode = it == m_page->m_viewState.laneRanges.cend()
                             ? automation::defaultRange(row.id.controller)
                             : it->second;
    return mode == 0 ? automation::autoRange(dataMaximum) : std::max(int(mode), dataMaximum);
}

int AutomationProjection::valueAtY(int rowIndex, qreal y) const
{
    if (rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return 0;
    const auto [top, bottom] = valuePlotBounds(rowIndex);
    const int minimum = rowMinimum(m_rows[rowIndex]);
    const int maximum = rowMaximum(m_rows[rowIndex]);
    const qreal clamped = std::clamp(y, qreal(top), qreal(bottom));
    return minimum + int((qreal(bottom) - clamped) * qreal(maximum - minimum) /
                         qreal(std::max(1, bottom - top)));
}

qreal AutomationProjection::pointY(const AutomationRow &row, int rowIndex, int value) const
{
    const auto [top, bottom] = valuePlotBounds(rowIndex);
    return qreal(bottom) - qreal(value - rowMinimum(row)) * qreal(bottom - top) /
                               qreal(std::max(1, rowMaximum(row) - rowMinimum(row)));
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

const AutoLane *AutomationProjection::laneFor(const AutomationRow &row) const
{
    if (row.id.kind != EditorAutomationRowKind::ControlChange)
        return nullptr;
    return m_page->model().findLane(int(row.id.track), row.id.controller);
}

bool AutomationProjection::nodeMarkersVisible() const
{
    return m_page && m_page->pxPerBeat() >= m_geometry.pointDetailThreshold;
}

AutomationProjection::PointerMapping AutomationProjection::pointerMapping(int rowIndex, qreal x,
                                                                          qreal y) const
{
    PointerMapping mapped;
    if (!m_page || !m_page->timeline() || rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return mapped;
    const uint64_t length = m_page->timeline()->lengthTicks;
    mapped.rawTick = std::clamp(rawTickAt(x), 0.0, double(length));
    mapped.point.value = valueAtY(rowIndex, y);
    mapped.cell = snapCellAt(mapped.rawTick);
    mapped.point.tick = mapped.cell.tickBegin;
    return mapped;
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
