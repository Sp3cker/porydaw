#include "ui/editordrawer/nodelane/gesture.h"

#include <algorithm>
#include <cmath>

#include <QApplication>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/linearramp.h"

bool Slop::shouldSuppress(QPointF pos, int threshold, qreal aspect) const noexcept
{
    const qreal dx = std::abs(pos.x() - origin.x());
    const qreal dy = std::abs(pos.y() - origin.y());
    const qreal travel = dx + dy;
    return dy < qreal(threshold) && (travel < qreal(threshold) || dy == 0.0 || dx > dy * aspect);
}

void PointDragGesture::press(QPointF position, bool deleteStationary) noexcept
{
    pressPosition = position;
    dragSlop = {position, false};
    axisLock = AxisLock::None;
    deleteOnStationary = deleteStationary;
}

PointDragUpdate PointDragGesture::update(QPointF position, Qt::KeyboardModifiers modifiers,
                                         int activationDistance) noexcept
{
    if (!dragSlop.exceeded) {
        const QPointF delta = position - pressPosition;
        const qreal travel = std::abs(delta.x()) + std::abs(delta.y());
        if (travel < qreal(activationDistance))
            return {};
        dragSlop.markExceeded(position);
        return {PointDragUpdate::Phase::Reset, pressPosition, AxisLock::None};
    }
    axisLock = resolveAxisLock(axisLock, modifiers & Qt::ShiftModifier, pressPosition, position,
                               activationDistance);
    if (modifiers & Qt::ShiftModifier && axisLock == AxisLock::None)
        return {PointDragUpdate::Phase::Reset, pressPosition, AxisLock::None};
    return {PointDragUpdate::Phase::Dragging, pressPosition + position - dragSlop.origin, axisLock};
}

PointDragRelease PointDragGesture::release() const noexcept
{
    if (!dragSlop.exceeded)
        return deleteOnStationary ? PointDragRelease::StationaryDelete : PointDragRelease::NoOp;
    return PointDragRelease::Move;
}

void BandGesture::press(QPoint pos, uint64_t tick)
{
    pending = true;
    active = false;
    pressPos = pos;
    startTick = tick;
    endTick = tick;
}

bool BandGesture::move(QPoint pos, uint64_t tick)
{
    if (!pending)
        return false;
    if (!active && (pos - pressPos).manhattanLength() >= QApplication::startDragDistance()) {
        active = true;
        endTick = tick;
        return true;
    }
    if (active)
        endTick = tick;
    return false;
}

std::optional<std::pair<uint64_t, uint64_t>> BandGesture::release()
{
    if (!pending || !active) {
        clear();
        return std::nullopt;
    }
    const std::pair<uint64_t, uint64_t> result{std::min(startTick, endTick),
                                               std::max(startTick, endTick)};
    clear();
    return result;
}

void BandGesture::extendTo(LaneHandle candidate, bool compatible)
{
    if (!laneStart.valid() || !candidate.valid())
        return;
    if (!compatible)
        return;
    laneEnd = candidate;
}

bool BandGesture::coversLane(LaneHandle handle) const noexcept
{
    if (!active || !laneStart.valid() || !laneEnd.valid() || !handle.valid())
        return false;
    const int first = std::min(laneStart.index, laneEnd.index);
    const int last = std::max(laneStart.index, laneEnd.index);
    return handle.index >= first && handle.index <= last;
}

void NodeDragGesture::preparePreview(std::size_t laneCount,
                                     const std::vector<std::vector<NodePoint>> &lanePointsByLane)
{
    pointIndexesByLane.assign(laneCount, {});
    basePointsByLane.assign(laneCount, {});
    previewPoints.assign(laneCount, {});
    for (size_t index = 0; index < points.size(); ++index) {
        const int laneIndex = points[index].lane.index;
        if (laneIndex >= 0 && laneIndex < int(laneCount))
            pointIndexesByLane[std::size_t(laneIndex)].push_back(index);
    }
    for (int laneIndex = 0; laneIndex < int(laneCount); ++laneIndex) {
        auto &indexes = pointIndexesByLane[std::size_t(laneIndex)];
        if (indexes.empty())
            continue;
        std::stable_sort(indexes.begin(), indexes.end(), [this](size_t left, size_t right) {
            return points[left].original.tick < points[right].original.tick;
        });
        if (laneIndex >= int(lanePointsByLane.size()))
            continue;
        const auto &lanePoints = lanePointsByLane[std::size_t(laneIndex)];
        if (lanePoints.empty())
            continue;
        auto &base = basePointsByLane[std::size_t(laneIndex)];
        base.reserve(lanePoints.size());
        size_t selected = 0;
        for (const NodePoint &point : lanePoints) {
            while (selected < indexes.size() &&
                   points[indexes[selected]].original.tick < point.tick)
                ++selected;
            if (selected < indexes.size() &&
                points[indexes[selected]].original.tick == point.tick &&
                points[indexes[selected]].original.value == point.value) {
                ++selected;
                continue;
            }
            base.push_back(point);
        }
        previewPoints[std::size_t(laneIndex)].reserve(lanePoints.size());
    }
    updatePreview();
}

void NodeDragGesture::updatePreview()
{
    for (int laneIndex = 0; laneIndex < int(pointIndexesByLane.size()); ++laneIndex) {
        const auto &indexes = pointIndexesByLane[std::size_t(laneIndex)];
        if (indexes.empty())
            continue;
        const auto &base = basePointsByLane[std::size_t(laneIndex)];
        auto &preview = previewPoints[std::size_t(laneIndex)];
        preview.clear();
        size_t baseIndex = 0;
        size_t movedIndex = 0;
        const auto appendMoved = [&] {
            const auto &moved = points[indexes[movedIndex++]].current;
            if (!preview.empty() && preview.back().tick == moved.tick)
                preview.back() = moved;
            else
                preview.push_back(moved);
        };
        while (baseIndex < base.size() && movedIndex < indexes.size()) {
            const auto &moved = points[indexes[movedIndex]].current;
            if (base[baseIndex].tick < moved.tick) {
                preview.push_back(base[baseIndex++]);
            } else if (moved.tick < base[baseIndex].tick) {
                appendMoved();
            } else {
                const auto occupiedTick = base[baseIndex].tick;
                while (baseIndex < base.size() && base[baseIndex].tick == occupiedTick)
                    ++baseIndex;
                appendMoved();
            }
        }
        while (baseIndex < base.size())
            preview.push_back(base[baseIndex++]);
        while (movedIndex < indexes.size())
            appendMoved();
    }
}

void NodeDragGesture::applyDrag(const NodePoint &grabCurrent)
{
    if (points.empty() || grabbedPoint >= points.size())
        return;
    const NodePoint grabOriginal = points[grabbedPoint].original;
    const int64_t requestedTickDelta = int64_t(grabCurrent.tick) - int64_t(grabOriginal.tick);
    uint64_t earliestTick = points.front().original.tick;
    for (const NodeDrag &point : points)
        earliestTick = std::min(earliestTick, point.original.tick);
    const int64_t dTick = std::max(requestedTickDelta, -int64_t(earliestTick));
    const int dValue = grabCurrent.value - grabOriginal.value;
    for (NodeDrag &point : points) {
        point.current.tick = uint64_t(int64_t(point.original.tick) + dTick);
        point.current.value =
            std::clamp(point.original.value + dValue, point.minimumValue, point.maximumValue);
    }
}
AxisLock NodeDragGesture::update(const PointDragUpdate &dragUpdate,
                                 const NodePoint &mappedGrabBeforeLock)
{
    if (points.empty() || grabbedPoint >= points.size() ||
        dragUpdate.phase == PointDragUpdate::Phase::Pending)
        return AxisLock::None;
    NodeDrag &grabbed = points[grabbedPoint];
    if (dragUpdate.phase == PointDragUpdate::Phase::Reset) {
        grabbed.current = grabbed.original;
    } else {
        grabbed.current = mappedGrabBeforeLock;
        applyAxisLock(dragUpdate.axisLock, grabbed.original, grabbed.current);
    }
    applyDrag(grabbed.current);
    updatePreview();
    return dragUpdate.axisLock;
}
std::optional<QPointF> SweepGesture::dragPosition(QPointF position, bool activate,
                                                  int activationDistance)
{
    if (!slop.exceeded) {
        const QPointF delta = position - pressPosition;
        const qreal travel = std::abs(delta.x()) + std::abs(delta.y());
        if (!activate || travel < qreal(activationDistance))
            return std::nullopt;
        slop.markExceeded(position);
        return std::nullopt;
    }
    const QPointF effective = pressPosition + position - slop.origin;
    if (points.empty() && effective == pressPosition)
        return std::nullopt;
    return effective;
}

bool PencilGesture::update(const QPointF &position, bool freehand, AxisLock lock,
                           const AutomationProjection &proj, const NodeLane &nodeLane,
                           const QRect &body, int verticalSlopDistance)
{
    return updatePencilDrawPath(*this, position, freehand, lock, proj, nodeLane, body,
                                verticalSlopDistance);
}

void updateValuePoint(const AutomationProjection &proj, const NodeLane &lane, const QRect &body,
                      NodePoint &point, qreal y, uint64_t tick, bool snapValue,
                      int neutralSnapRadius, int snapNeutral)
{
    point.value =
        std::clamp(qRound(AutomationProjection::valueAtY(body, proj.geometry(), lane.minimumValue(),
                                                         lane.maximumValue(), y)),
                   lane.minimumValue(), lane.maximumValue());
    if (snapValue && snapNeutral >= 0) {
        const int span = lane.maximumValue() - lane.minimumValue();
        const int height = std::max(1, body.height());
        if (std::abs(point.value - snapNeutral) <= span * neutralSnapRadius / height)
            point.value = snapNeutral;
    }
    point.tick = tick;
}

bool hitNodePoint(const NodeLane &lane, const QRect &body, const AutomationProjection &proj,
                  const AutomationGeometry &geometry, QPointF position, qreal devicePixelRatio,
                  bool requireVisibleMarkers, NodePoint *point)
{
    if (requireVisibleMarkers && !proj.nodeMarkersVisible())
        return false;
    const std::vector<NodePoint> points = lane.points();
    const auto hit = nearestPointInRadius(
        points, proj.rawTickAt(position.x()), position, geometry.pointHitRadius,
        [&proj, devicePixelRatio](const NodePoint &candidate) {
            return proj.displayX(candidate.tick, devicePixelRatio);
        },
        [&lane, &body, &geometry](const NodePoint &candidate) {
            return AutomationProjection::valueY(body, geometry, lane.minimumValue(),
                                                lane.maximumValue(), candidate.value);
        });
    if (!hit)
        return false;
    if (point)
        *point = points[*hit];
    return true;
}

AxisLock resolveAxisLock(AxisLock current, bool shiftHeld, const QPointF &origin,
                         const QPointF &position, int activationDistance) noexcept
{
    if (!shiftHeld)
        return AxisLock::None;
    if (current != AxisLock::None)
        return current;
    const qreal dx = position.x() - origin.x();
    const qreal dy = position.y() - origin.y();
    const qreal threshold = qreal(activationDistance);
    if (std::abs(dx) + std::abs(dy) < threshold)
        return AxisLock::None;
    return std::abs(dx) >= std::abs(dy) ? AxisLock::Time : AxisLock::Value;
}

void applyAxisLock(AxisLock lock, const NodePoint &original, NodePoint &current) noexcept
{
    if (lock == AxisLock::None)
        return;
    if (lock == AxisLock::Time)
        current.value = original.value;
    else
        current.tick = original.tick;
}

bool updatePencilDrawPath(PencilGesture &gesture, const QPointF &position, bool freehand,
                          AxisLock lock, const AutomationProjection &proj, const NodeLane &lane,
                          const QRect &body, int verticalSlopDistance)
{
    const qreal top = body.top() + proj.geometry().valuePlotPadding;
    const qreal bottom = body.bottom() - proj.geometry().valuePlotPadding;
    const auto previous = gesture.stroke.lastSample();
    bool withinVerticalSlop = false;
    if (!freehand && lock != AxisLock::Value && !gesture.verticalSlop.exceeded) {
        if (gesture.verticalSlop.shouldSuppress(position, verticalSlopDistance,
                                                kPencilSlopAspect)) {
            withinVerticalSlop = true;
        } else {
            gesture.verticalSlop.markExceeded(position);
        }
    }
    const double continuousValue =
        lock == AxisLock::Value || withinVerticalSlop
            ? previous.continuousValue
            : std::clamp(previous.continuousValue +
                             double(gesture.previousY - position.y()) *
                                 double(lane.maximumValue() - lane.minimumValue()) /
                                 double(std::max<qreal>(1.0, bottom - top)),
                         double(lane.minimumValue()), double(lane.maximumValue()));
    const AutomationProjection::PointerMapping current =
        proj.pointerMapping(lane, body, position.x(), position.y());
    const AutomationPencilGesture::Sample sample{current.rawTick, position.x(), current.point,
                                                 continuousValue};
    const bool applied =
        freehand ? gesture.stroke.applyFreehandSegment(sample)
                 : gesture.stroke.applySnappedSegment(
                       sample, proj.snapCellsCrossed(gesture.crossedGridCells, previous.rawTick,
                                                     current.rawTick));
    if (applied && (freehand || lock == AxisLock::Value || gesture.verticalSlop.exceeded))
        gesture.previousY = position.y();
    if (applied && lock == AxisLock::Value && !gesture.verticalSlop.exceeded)
        gesture.verticalSlop.origin = position;
    return applied;
}

NodeDragFinish NodeDragGesture::finish() const
{
    if (points.empty() || grabbedPoint >= points.size())
        return {};
    const auto &grabbed = points[grabbedPoint];
    NodeDragFinish result;
    result.release = drag.release();
    result.dTick = int64_t(grabbed.current.tick) - int64_t(grabbed.original.tick);
    result.selectionDrag = selectionDrag;
    for (const NodeDrag &point : points)
        result.changed = result.changed || point.original.tick != point.current.tick ||
                         point.original.value != point.current.value;
    return result;
}

NodeLaneEdit::Completion PencilGesture::finish() &&
{
    return std::move(stroke).finish();
}
