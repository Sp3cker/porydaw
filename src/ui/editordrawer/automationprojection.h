#pragma once

#include <cstdint>
#include <utility>
#include <vector>

#include <QRect>
#include <QtGlobal>

#include "ui/editorviewstate.h"
#include "ui/songviewmodel.h"

class AutomationPage;

namespace automation {
struct ValuePoint {
    uint64_t tick = 0;
    int value = 0;
};

inline constexpr uint8_t kBendController = LANE_CC_BEND;

inline bool rangeZoomable(uint8_t controller)
{
    return controller != kBendController && controller != 10 && controller != 24;
}

inline uint8_t defaultRange(uint8_t controller)
{
    return controller == 1 ? 0 : 127;
}

inline int autoRange(int maximum)
{
    if (maximum <= 16)
        return 16;
    if (maximum <= 32)
        return 32;
    if (maximum <= 64)
        return 64;
    return 127;
}

} // namespace automation

struct AutomationRow {
    EditorAutomationRowId id;
};

// A half-open visible grid cell. Snapped callers provide crossed cells in
// pointer traversal order, including both endpoint cells.
struct AutomationGridCell {
    uint64_t tickBegin = 0;
    uint64_t tickEnd = 0;
};

// Automation drawer layout constants resolved from the UI scale. Shared by the
// projection (mapping math) and the area (paint and hit-test geometry).
struct AutomationGeometry {
    int rowDefaultHeight = 0;
    int rowMinimumHeight = 0;
    int rowMaximumHeight = 0;
    int rowWheelIncrement = 0;
    int addLaneStripHeight = 0;
    int plotOrigin = 0;
    int pointHitRadius = 0;
    int neutralSnapRadius = 0;
    int deleteTimeRadius = 0;
    int pointDetailThreshold = 0;
    int hoverPaintPadding = 0;
    int nodeDragActivationDistance = 0;
    int gridMinimumCellWidth = 0;
    qreal nodePaintRadius = 0.0;
    qreal selectedNodeRingRadius = 0.0;
    qreal nodeOutlineDipWidth = 0.0;
    qreal selectedNodeRingDipWidth = 0.0;
    int valuePlotPadding = 0; // Aligns endpoint marker edges with row gutters.

    static AutomationGeometry resolve();
};

// AutomationProjection owns the current geometry and row snapshot for pixel
// <-> tick <-> value mapping. It borrows only the page and widget DPR;
// construct one per event or paint pass.
class AutomationProjection
{
  public:
    struct PointerMapping {
        automation::ValuePoint point;
        double rawTick = 0.0;
        AutomationGridCell cell;
    };

    AutomationProjection(const AutomationGeometry &geometry, const std::vector<AutomationRow> &rows,
                         const AutomationPage *page, int topInset)
        : m_geometry(geometry)
        , m_rows(rows)
        , m_page(page)
        , m_topInset(topInset)
    {}

    int rowHeight(const AutomationRow &row) const;
    int rowTop(int index) const;
    std::pair<int, int> valuePlotBounds(int index) const;
    int rowIndexAt(int y) const;
    int rowBoundaryAt(int y) const;
    int rowMinimum(const AutomationRow &row) const;
    int rowMaximum(const AutomationRow &row) const;
    int valueAtY(int rowIndex, qreal y) const;
    qreal pointY(const AutomationRow &row, int rowIndex, int value) const;
    double rawTickAt(qreal x) const;
    qreal displayX(uint64_t tick, qreal devicePixelRatio) const;
    uint64_t snapTickAt(qreal x, bool fine) const;
    static qreal valueY(const QRect &bounds, const AutomationGeometry &geometry, double minimum,
                        double maximum, double value);
    static double valueAtY(const QRect &bounds, const AutomationGeometry &geometry, double minimum,
                           double maximum, qreal y);
    uint64_t fineSnapTick(double rawTick) const;
    const AutoLane *laneFor(const AutomationRow &row) const;
    bool nodeMarkersVisible() const;
    PointerMapping pointerMapping(int rowIndex, qreal x, qreal y) const;
    AutomationGridCell snapCellAt(double rawTick) const;
    // Fills `cells` (reused scratch, no allocation) and returns it.
    const std::vector<AutomationGridCell> &snapCellsCrossed(std::vector<AutomationGridCell> &cells,
                                                            double previousRawTick,
                                                            double currentRawTick) const;

  private:
    AutomationGeometry m_geometry;
    std::vector<AutomationRow> m_rows;
    const AutomationPage *m_page;
    int m_topInset = 0;
};
