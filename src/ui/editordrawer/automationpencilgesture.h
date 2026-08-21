#pragma once

#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/nodelane.h"

// One deferred automation Pencil stroke. The caller maps pointer events and
// visible grid cells; this gesture owns stroke sampling and traversal.
class AutomationPencilGesture
{
  public:
    using Target = NodeLaneEdit::Target;
    using Completion = NodeLaneEdit::Completion;

    struct Sample {
        double rawTick = 0.0;
        double logicalX = 0.0;
        automation::ValuePoint point;
        double continuousValue = 0.0;
    };

    // Edit snap cells are produced by AutomationProjection.
    static std::optional<AutomationPencilGesture>
    start(Target target, int minimumValue, int maximumValue, uint64_t songEndTick,
          uint64_t documentClockTicks, std::vector<NodeLaneEdit::Point> originalPoints,
          Sample firstSample, AutomationGridCell firstCell);

    bool applySnappedSegment(Sample sample, const std::vector<AutomationGridCell> &cells);
    bool applyFreehandSegment(Sample sample);

    Completion finish() && { return std::move(m_cachedPreview); }
    const Completion &preview() const noexcept { return m_cachedPreview; }
    const Sample &lastSample() const noexcept { return m_previous; }

  private:
    AutomationPencilGesture(Target target, int minimumValue, int maximumValue, uint64_t songEndTick,
                            uint64_t documentClockTicks,
                            std::vector<NodeLaneEdit::Point> originalPoints, Sample firstSample,
                            AutomationGridCell firstCell);

    static bool lessPointTick(const automation::ValuePoint &left, uint64_t tick) noexcept;
    static bool validCell(const AutomationGridCell &cell, uint64_t songEndTick) noexcept;

    void rebuildPreview();
    void eraseStrokePointsIn(uint64_t tickBegin, uint64_t tickEnd);
    int roundedValue(double continuousValue) const noexcept;

    int m_minimumValue = 0;
    int m_maximumValue = 0;
    uint64_t m_songEndTick = 0;
    uint64_t m_documentClockTicks = 0;
    Sample m_previous;
    NodeLaneEdit m_laneEdit;
    std::vector<automation::ValuePoint> m_strokePoints;
    AutomationGridCell m_initialCell;
    automation::ValuePoint m_initialPoint{};
    bool m_initialCellExited = false;
    // A non-integral freehand endpoint remains provisional until the next
    // event proves it collinear and forward with both adjacent segments.
    std::optional<automation::ValuePoint> m_provisionalFreehandEndpoint;
    std::optional<Sample> m_freehandSegmentStart;
    std::optional<Sample> m_snappedSegmentStart;
    uint64_t m_tickBegin = 0;
    uint64_t m_tickEnd = 0;
    Completion m_cachedPreview;
};
