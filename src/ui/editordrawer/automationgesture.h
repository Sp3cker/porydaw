#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include <QPointF>
#include <QRect>

#include "ui/editordrawer/automationlaneedit.h"
#include "ui/editordrawer/automationpencilgesture.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/linearramp.h"
#include "ui/songviewmodel.h"

// Automation gestures — page-free domain for the automation drawer.
// Each gesture is a small stateful object (cf. AutomationPencilGesture exemplar)
// that consumes plain values (PointerMapping, ticks, points) and produces a
// GestureCommit value; the widget keeps Qt policy and performs effects.

namespace automation {
enum class AxisLock : uint8_t { None, Time, Value };
} // namespace automation

using automation::AxisLock;
using automation::ValuePoint;

struct Slop {
    QPointF origin;
    bool exceeded = false;

    bool shouldSuppress(QPointF pos, int threshold, qreal aspect = 0.0) const noexcept;
    void markExceeded(QPointF pos)
    {
        origin = pos;
        exceeded = true;
    }
};

inline constexpr qreal kPencilSlopAspect = 4.0;

struct NodeDrag {
    int row = -1;
    int engineTrack = -1;
    uint8_t controller = 0;
    DocLanePoint documentPoint;
    ValuePoint original;
    ValuePoint current;
};

struct NodeDeleteCommit {
    DocLanePoint point;
    int track = -1;
    uint8_t controller = 0;
};
struct NodeMoveCommit {
    std::vector<SongDocument::LanePointMove> moves;
    int64_t dTick = 0;
    bool selectionDrag = false;
};
using GestureCommit =
    std::variant<std::monostate, AutomationLaneEdit::Completion, NodeDeleteCommit, NodeMoveCommit>;

struct NodeDragGesture {
    int row = -1;
    std::vector<NodeDrag> points;
    std::size_t grabbedPoint = 0;
    QPointF pressPosition;
    // Set when travel first exceeds automationNodeDragActivationDistance.
    // Subsequent drag deltas are measured from here so the slop is not
    // applied as intentional node movement.
    Slop dragSlop;
    AxisLock axisLock = AxisLock::None;
    bool axisLockArmed = false;
    bool selectionDrag = false;
    std::vector<std::vector<std::size_t>> pointIndexesByRow;
    std::vector<std::vector<LanePoint>> basePointsByRow;
    std::vector<std::vector<LanePoint>> previewPoints;

    AxisLock update(const QPointF &position, const ValuePoint &mappedGrabBeforeLock,
                    Qt::KeyboardModifiers mods, int activationDistance,
                    const std::vector<AutomationRow> &rows, const AutomationProjection &proj);
    GestureCommit finish() const;
    void applyDrag(const ValuePoint &grabCurrent, const std::vector<AutomationRow> &rows,
                   const AutomationProjection &proj);
    void preparePreview(const std::vector<AutomationRow> &rows,
                        const std::vector<std::vector<LanePoint>> &lanePointsByRow);
    void updatePreview();
};

struct SweepGesture {
    enum class Mode : uint8_t { Drag, Ramp };

    int row = -1;
    Mode mode = Mode::Drag;
    ValuePoint anchor;
    ValuePoint current;
    std::vector<ValuePoint> points;
    double previousRawTick = 0.0;
    int previousValue = 0;
    QPointF pressPosition;
    // A drag sweep remains pending while this is false.
    Slop slop;

    template <typename NextGridTick>
    void update(const ValuePoint &mapped, uint64_t first, uint64_t last, double rawTick,
                bool fineGrid, NextGridTick &&nextGridTick);
    void update(const ValuePoint &mapped) { current = mapped; }
    template <typename NextGridTick>
    AutomationLaneEdit::Completion finish(int track, uint8_t controller, uint64_t revision,
                                          const std::vector<DocLanePoint> &existing, bool fineGrid,
                                          NextGridTick &&nextGridTick) const;
};

struct PencilGesture {
    int row = -1;
    AutomationPencilGesture stroke;
    std::vector<AutomationGridCell> crossedGridCells;
    Slop verticalSlop;
    qreal previousY = 0.0;

    bool update(const QPointF &position, bool freehand, AxisLock lock,
                const AutomationProjection &proj, const AutomationRow &row,
                int verticalSlopDistance);
    AutomationLaneEdit::Completion finish() &&;
};

using ActiveGesture = std::variant<NodeDragGesture, SweepGesture, PencilGesture>;

// Shared helpers — moved from AutomationArea (Feature Envy).
AxisLock resolveAxisLock(AxisLock current, bool shiftHeld, const QPointF &origin,
                         const QPointF &position, int activationDistance) noexcept;
void applyAxisLock(AxisLock lock, const ValuePoint &original, ValuePoint &current) noexcept;

// Mapping helpers — page-free versions that take plain values.
void updateValuePoint(const AutomationProjection &proj, int rowIndex, const AutomationRow &row,
                      ValuePoint &point, int y, uint64_t tick, bool snapValue,
                      int neutralSnapRadius);

template <typename NextGridTick>
void extendSweepPoints(SweepGesture &gesture, uint64_t first, uint64_t last, double rawTick,
                       bool fineGrid, NextGridTick &&nextGridTick);

bool updatePencilDrawPath(PencilGesture &gesture, const QPointF &position, bool freehand,
                          AxisLock lock, const AutomationProjection &proj, const AutomationRow &row,
                          int verticalSlopDistance);

// ---- template definitions ----

template <typename NextGridTick>
void extendSweepPoints(SweepGesture &gesture, uint64_t first, uint64_t last, double rawTick,
                       bool fineGrid, NextGridTick &&nextGridTick)
{
    const double from = gesture.previousRawTick;
    for (uint64_t tick = first;;) {
        int value = gesture.current.value;
        if (rawTick != from) {
            const double fraction = std::clamp((double(tick) - from) / (rawTick - from), 0.0, 1.0);
            value = gesture.previousValue +
                    int(std::llround(fraction * (gesture.current.value - gesture.previousValue)));
        }
        const auto position =
            std::lower_bound(gesture.points.begin(), gesture.points.end(), tick,
                             [](const ValuePoint &point, uint64_t v) { return point.tick < v; });
        if (position != gesture.points.end() && position->tick == tick)
            position->value = value;
        else
            gesture.points.insert(position, {tick, value});
        if (tick == last)
            break;
        tick = nextGridTick(tick, fineGrid, last);
    }
    gesture.previousRawTick = rawTick;
    gesture.previousValue = gesture.current.value;
}

template <typename NextGridTick>
void SweepGesture::update(const ValuePoint &mapped, uint64_t first, uint64_t last, double rawTick,
                          bool fineGrid, NextGridTick &&nextGridTick)
{
    current = mapped;
    extendSweepPoints(*this, first, last, rawTick, fineGrid,
                      std::forward<NextGridTick>(nextGridTick));
}

template <typename NextGridTick>
AutomationLaneEdit::Completion
SweepGesture::finish(int track, uint8_t controller, uint64_t revision,
                     const std::vector<DocLanePoint> &existing, bool fineGrid,
                     NextGridTick &&nextGridTick) const
{
    const auto laneEditPoints = [](const std::vector<ValuePoint> &valuePoints) {
        std::vector<AutomationLaneEdit::Point> lanePoints;
        lanePoints.reserve(valuePoints.size());
        for (const ValuePoint &point : valuePoints)
            lanePoints.push_back({point.tick, point.value});
        return lanePoints;
    };
    const auto replace = [track, controller, revision,
                          &existing](uint64_t first, uint64_t last,
                                     std::vector<AutomationLaneEdit::Point> lanePoints) {
        std::vector<AutomationLaneEdit::Point> existingEdit;
        existingEdit.reserve(existing.size());
        for (const DocLanePoint &point : existing)
            existingEdit.push_back({point.tick, point.value});
        const AutomationLaneEdit laneEdit({track, controller, revision}, std::move(existingEdit));
        return laneEdit.replacePointRange(first, last, std::move(lanePoints));
    };
    if (mode == Mode::Ramp) {
        uint64_t first = anchor.tick;
        uint64_t last = current.tick;
        int firstValue = anchor.value;
        int lastValue = current.value;
        if (first > last) {
            std::swap(first, last);
            std::swap(firstValue, lastValue);
        }
        std::vector<AutomationLaneEdit::Point> rampPoints;
        for (uint64_t tick = first;;) {
            const int value = int(std::llround(ui::linearRampValue(
                double(tick), double(first), double(firstValue), double(last), double(lastValue))));
            rampPoints.push_back({tick, value});
            if (tick == last)
                break;
            tick = nextGridTick(tick, fineGrid, last);
        }
        return replace(first, last, std::move(rampPoints));
    }
    if (points.empty())
        return {};
    return replace(points.front().tick, points.back().tick, laneEditPoints(points));
}
