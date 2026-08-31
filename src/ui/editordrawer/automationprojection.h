#pragma once

#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

#include <QRect>
#include <QtGlobal>

#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationPage;
class MidiTimeline;
class SongView;

// A half-open visible grid cell. Snapped callers provide crossed cells in
// pointer traversal order, including both endpoint cells.
struct AutomationGridCell {
    uint64_t tickBegin = 0;
    uint64_t tickEnd = 0;
};

// Automation drawer layout constants resolved from the UI scale. Shared by the
// projection (mapping math) and the canvas (paint and hit-test geometry).
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

// AutomationProjection owns the current geometry for pixel <-> tick mapping.
// It borrows only the page; construct one per event or paint pass. Value
// mapping is lane-keyed through pointerMapping and the static valueY helpers.
class AutomationProjection
{
  public:
    struct PointerMapping {
        NodePoint point;
        double rawTick = 0.0;
        AutomationGridCell cell;
    };

    AutomationProjection(const AutomationGeometry &geometry, const AutomationPage *page)
        : m_geometry(geometry)
        , m_page(page)
    {}
    AutomationProjection(const AutomationGeometry &geometry, const SongView *songView)
        : m_geometry(geometry)
        , m_songView(songView)
    {}

    const AutomationGeometry &geometry() const noexcept { return m_geometry; }
    double rawTickAt(qreal x) const;
    qreal displayX(uint64_t tick, qreal devicePixelRatio) const;
    // Display x of the song's end tick at the given device pixel ratio; nullopt
    // when the song is unbounded (null timeline or lengthTicks == 0).
    [[nodiscard]] std::optional<qreal> songEndX(qreal devicePixelRatio) const;
    uint64_t snapTickAt(qreal x, bool fine) const;
    static qreal valueY(const QRect &bounds, const AutomationGeometry &geometry, double minimum,
                        double maximum, double value);
    static double valueAtY(const QRect &bounds, const AutomationGeometry &geometry, double minimum,
                           double maximum, qreal y);
    uint64_t fineSnapTick(double rawTick) const;
    bool nodeMarkersVisible() const;
    PointerMapping pointerMapping(const NodeLane &lane, const QRect &body, qreal x, qreal y) const;
    AutomationGridCell snapCellAt(double rawTick) const;
    // Fills `cells` (reused scratch, no allocation) and returns it.
    const std::vector<AutomationGridCell> &snapCellsCrossed(std::vector<AutomationGridCell> &cells,
                                                            double previousRawTick,
                                                            double currentRawTick) const;

  private:
    const MidiTimeline *timeline() const;
    uint64_t gridSnapTicks(uint64_t tick, bool fine) const;
    uint64_t snapTickDown(double tick, bool fine) const;
    uint64_t nextGridTick(uint64_t tick, bool fine, uint64_t limit) const;

    AutomationGeometry m_geometry;
    const AutomationPage *m_page = nullptr;
    const SongView *m_songView = nullptr;
};
