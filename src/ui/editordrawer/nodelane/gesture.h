#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include <QPoint>
#include <QPointF>
#include <QRect>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/linearramp.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/nodelane/pencilgesture.h"

// Node-lane gestures. Each gesture is a small stateful object (cf.
// AutomationPencilGesture) that consumes pointer mappings; the canvas keeps Qt
// policy and performs effects.

namespace automation {
enum class AxisLock : uint8_t { None, Time, Value };
} // namespace automation

using automation::AxisLock;

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

enum class PointDragRelease : uint8_t { NoOp, StationaryDelete, Move };

struct PointDragUpdate {
    enum class Phase : uint8_t { Pending, Reset, Dragging };

    Phase phase = Phase::Pending;
    QPointF effectivePosition;
    AxisLock axisLock = AxisLock::None;
};

// Page-free pointer mechanics for a single point. The caller retains domain
// points: Reset restores its original; Dragging maps effectivePosition and
// applies axisLock to its own original/current values.
struct PointDragGesture {
    QPointF pressPosition;
    Slop dragSlop;
    AxisLock axisLock = AxisLock::None;
    bool deleteOnStationary = true;

    void press(QPointF position, bool deleteStationary) noexcept;
    PointDragUpdate update(QPointF position, Qt::KeyboardModifiers modifiers,
                           int activationDistance) noexcept;
    PointDragRelease release() const noexcept;
};
struct NodeDrag {
    LaneHandle lane;
    NodePoint original;
    NodePoint current;
    int minimumValue = 0;
    int maximumValue = 127;
};

struct NodeDragFinish {
    PointDragRelease release = PointDragRelease::NoOp;
    bool changed = false;
    int64_t dTick = 0;
    bool selectionDrag = false;
};

struct NodeDoubleClickGuard {
    bool pending = false;

    void clear() noexcept { pending = false; }
    void markDeleted() noexcept { pending = true; }
    bool consume() noexcept { return std::exchange(pending, false); }
};

struct NodeDragGesture {
    LaneHandle lane;
    uint64_t expectedRevision = 0;
    std::vector<NodeDrag> points;
    std::size_t grabbedPoint = 0;
    PointDragGesture drag;
    bool selectionDrag = false;
    std::vector<std::vector<std::size_t>> pointIndexesByLane;
    std::vector<std::vector<NodePoint>> basePointsByLane;
    std::vector<std::vector<NodePoint>> previewPoints;
    AxisLock update(const PointDragUpdate &dragUpdate, const NodePoint &mappedGrabBeforeLock);
    NodeDragFinish finish() const;
    void applyDrag(const NodePoint &grabCurrent);
    void preparePreview(std::size_t laneCount,
                        const std::vector<std::vector<NodePoint>> &lanePointsByLane);
    void updatePreview();
};

struct PhantomGesture {
    LaneHandle lane;
    uint64_t expectedRevision = 0;
    NodeDrag point;
    PointDragGesture drag;

    AxisLock update(const PointDragUpdate &dragUpdate, int mappedValue) noexcept;
    std::optional<NodeDrag> finish() const noexcept;
};

struct SweepGesture {
    enum class Mode : uint8_t { Drag, Ramp };

    LaneHandle lane;
    Mode mode = Mode::Drag;
    NodePoint anchor;
    NodePoint current;
    std::vector<NodePoint> points;
    double previousRawTick = 0.0;
    int previousValue = 0;
    QPointF pressPosition;
    // A drag sweep remains pending while this is false.
    Slop slop;

    template <typename NextGridTick>
    void update(const NodePoint &mapped, uint64_t first, uint64_t last, double rawTick,
                bool fineGrid, NextGridTick &&nextGridTick);
    void update(const NodePoint &mapped) { current = mapped; }
    std::optional<QPointF> dragPosition(QPointF position, bool activate, int activationDistance);
    template <typename NextGridTick>
    std::vector<NodePoint> finishedPoints(bool fineGrid, NextGridTick &&nextGridTick) const;
    template <typename NextGridTick>
    NodeLaneEdit::Completion finish(LaneHandle handle, uint64_t revision,
                                    const std::vector<NodePoint> &existing, bool fineGrid,
                                    NextGridTick &&nextGridTick) const;
};

struct PencilGesture {
    LaneHandle lane;
    AutomationPencilGesture stroke;
    std::vector<AutomationGridCell> crossedGridCells;
    Slop verticalSlop;
    qreal previousY = 0.0;

    bool update(const QPointF &position, bool freehand, AxisLock lock,
                const AutomationProjection &proj, const NodeLane &nodeLane, const QRect &body,
                int verticalSlopDistance);
    NodeLaneEdit::Completion finish() &&;
};

struct BandGesture {
    bool pending = false;
    bool active = false;
    QPoint pressPos;
    uint64_t startTick = 0;
    uint64_t endTick = 0;
    LaneHandle laneStart;
    LaneHandle laneEnd;

    void press(QPoint pos, uint64_t tick);
    void pressLane(LaneHandle handle) { laneStart = laneEnd = handle; }
    void extendTo(LaneHandle candidate, bool compatible);
    std::pair<LaneHandle, LaneHandle> laneRange() const noexcept { return {laneStart, laneEnd}; }
    bool coversLane(LaneHandle handle) const noexcept;
    // Owns QApplication::startDragDistance. Returns true only on the move
    // that first activates (callers clear locked hover on that transition).
    bool move(QPoint pos, uint64_t tick);
    // Clears pending/active. Returns:
    //   nullopt            — never activated (click)
    //   {t, t}             — activated drag, snapped width zero
    //   {first, last}      — activated drag, first < last
    std::optional<std::pair<uint64_t, uint64_t>> release();
    void clear() noexcept
    {
        pending = false;
        active = false;
        pressPos = {};
        startTick = 0;
        endTick = 0;
        laneStart = {};
        laneEnd = {};
    }
};

using ActiveGesture = std::variant<NodeDragGesture, PhantomGesture, SweepGesture, PencilGesture>;

// Shared helpers — moved from AutomationCanvas (Feature Envy).
AxisLock resolveAxisLock(AxisLock current, bool shiftHeld, const QPointF &origin,
                         const QPointF &position, int activationDistance) noexcept;
void applyAxisLock(AxisLock lock, const NodePoint &original, NodePoint &current) noexcept;
inline qreal pointDistanceSquared(QPointF lhs, QPointF rhs) noexcept
{
    const qreal dx = lhs.x() - rhs.x();
    const qreal dy = lhs.y() - rhs.y();
    return dx * dx + dy * dy;
}

// Insert or replace the point at its tick. Precondition: points sorted by tick.
template <class Points, class Point>
void upsertByTick(Points &points, Point point);

// Nearest point to pos within radius px, measured via xOf/yOf pixel mapping.
// Preconditions: points sorted by .tick; xOf(point) monotonic in tick
// (early termination relies on it).
// Tie rule: exact equidistant candidates resolve to the LATER tick.
template <class Points, class XOf, class YOf>
std::optional<std::size_t> nearestPointInRadius(const Points &points, double centerRawTick,
                                                QPointF pos, qreal radius, XOf &&xOf, YOf &&yOf);

void updateValuePoint(const AutomationProjection &proj, const NodeLane &lane, const QRect &body,
                      NodePoint &point, qreal y, uint64_t tick, bool snapValue,
                      int neutralSnapRadius, int snapNeutral);
bool hitNodePoint(const NodeLane &lane, const QRect &body, const AutomationProjection &proj,
                  const AutomationGeometry &geometry, QPointF position, qreal devicePixelRatio,
                  bool requireVisibleMarkers, NodePoint *point);

template <typename NextGridTick>
void extendSweepPoints(SweepGesture &gesture, uint64_t first, uint64_t last, double rawTick,
                       bool fineGrid, NextGridTick &&nextGridTick);

bool updatePencilDrawPath(PencilGesture &gesture, const QPointF &position, bool freehand,
                          AxisLock lock, const AutomationProjection &proj, const NodeLane &lane,
                          const QRect &body, int verticalSlopDistance);

// ---- template definitions ----

template <class Points, class Point>
void upsertByTick(Points &points, Point point)
{
    auto it = std::lower_bound(points.begin(), points.end(), point.tick,
                               [](const auto &p, uint64_t tick) { return p.tick < tick; });
    if (it != points.end() && it->tick == point.tick)
        *it = point;
    else
        points.insert(it, std::move(point));
}

template <class Points, class XOf, class YOf>
std::optional<std::size_t> nearestPointInRadius(const Points &points, double centerRawTick,
                                                QPointF pos, qreal radius, XOf &&xOf, YOf &&yOf)
{
    const auto center =
        std::lower_bound(points.cbegin(), points.cend(), centerRawTick,
                         [](const auto &point, double tick) { return double(point.tick) < tick; });
    auto first = center;
    while (first != points.cbegin()) {
        const auto candidate = first - 1;
        if (std::abs(xOf(*candidate) - pos.x()) > radius)
            break;
        first = candidate;
    }
    auto last = center;
    while (last != points.cend()) {
        if (std::abs(xOf(*last) - pos.x()) > radius)
            break;
        ++last;
    }

    const qreal radiusSquared = radius * radius;
    std::optional<std::size_t> nearest;
    qreal nearestDistance = radiusSquared;
    for (auto candidate = first; candidate != last; ++candidate) {
        const qreal distance = pointDistanceSquared(QPointF(xOf(*candidate), yOf(*candidate)), pos);
        if (distance <= radiusSquared && distance <= nearestDistance) {
            nearestDistance = distance;
            nearest = std::size_t(candidate - points.cbegin());
        }
    }
    return nearest;
}

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
        upsertByTick(gesture.points, NodePoint{tick, value});
        if (tick == last)
            break;
        tick = nextGridTick(tick, fineGrid, last);
    }
    gesture.previousRawTick = rawTick;
    gesture.previousValue = gesture.current.value;
}

template <typename NextGridTick>
void SweepGesture::update(const NodePoint &mapped, uint64_t first, uint64_t last, double rawTick,
                          bool fineGrid, NextGridTick &&nextGridTick)
{
    current = mapped;
    extendSweepPoints(*this, first, last, rawTick, fineGrid,
                      std::forward<NextGridTick>(nextGridTick));
}

template <typename NextGridTick>
std::vector<NodePoint> SweepGesture::finishedPoints(bool fineGrid,
                                                    NextGridTick &&nextGridTick) const
{
    if (mode != Mode::Ramp)
        return points;
    uint64_t first = anchor.tick;
    uint64_t last = current.tick;
    int firstValue = anchor.value;
    int lastValue = current.value;
    if (first > last) {
        std::swap(first, last);
        std::swap(firstValue, lastValue);
    }
    std::vector<NodePoint> result;
    for (uint64_t tick = first;;) {
        const int value = int(std::llround(ui::linearRampValue(
            double(tick), double(first), double(firstValue), double(last), double(lastValue))));
        result.push_back({tick, value});
        if (tick == last)
            break;
        tick = nextGridTick(tick, fineGrid, last);
    }
    return result;
}

template <typename NextGridTick>
NodeLaneEdit::Completion SweepGesture::finish(LaneHandle handle, uint64_t revision,
                                              const std::vector<NodePoint> &existing, bool fineGrid,
                                              NextGridTick &&nextGridTick) const
{
    std::vector<NodePoint> result =
        finishedPoints(fineGrid, std::forward<NextGridTick>(nextGridTick));
    if (result.empty())
        return {};
    const uint64_t tickBegin = result.front().tick;
    const uint64_t tickEnd = result.back().tick;
    const NodeLaneEdit laneEdit({handle, revision}, existing);
    return laneEdit.replacePointRange(tickBegin, tickEnd, std::move(result));
}
