#include "ui/editordrawer/automationgesture.h"
#include "core/songdocument.h"

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

void NodeDragGesture::preparePreview(std::size_t rowCount,
                                     const std::vector<std::vector<ValuePoint>> &lanePointsByRow)
{
    pointIndexesByRow.assign(rowCount, {});
    basePointsByRow.assign(rowCount, {});
    previewPoints.assign(rowCount, {});
    for (size_t index = 0; index < points.size(); ++index) {
        const int rowIndex = points[index].row;
        if (rowIndex >= 0 && rowIndex < int(rowCount))
            pointIndexesByRow[rowIndex].push_back(index);
    }
    for (int rowIndex = 0; rowIndex < int(rowCount); ++rowIndex) {
        auto &indexes = pointIndexesByRow[rowIndex];
        if (indexes.empty())
            continue;
        std::stable_sort(indexes.begin(), indexes.end(), [this](size_t left, size_t right) {
            return points[left].original.tick < points[right].original.tick;
        });
        if (rowIndex >= int(lanePointsByRow.size()))
            continue;
        const auto &lanePoints = lanePointsByRow[rowIndex];
        if (lanePoints.empty())
            continue;
        auto &base = basePointsByRow[rowIndex];
        base.reserve(lanePoints.size());
        size_t selected = 0;
        for (const ValuePoint &point : lanePoints) {
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
        previewPoints[rowIndex].reserve(lanePoints.size());
    }
    updatePreview();
}

void NodeDragGesture::updatePreview()
{
    for (int rowIndex = 0; rowIndex < int(pointIndexesByRow.size()); ++rowIndex) {
        const auto &indexes = pointIndexesByRow[rowIndex];
        if (indexes.empty())
            continue;
        const auto &base = basePointsByRow[rowIndex];
        auto &preview = previewPoints[rowIndex];
        preview.clear();
        size_t baseIndex = 0;
        size_t movedIndex = 0;
        const auto appendMoved = [&] {
            const auto &point = points[indexes[movedIndex++]].current;
            const ValuePoint moved{point.tick, point.value};
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

void NodeDragGesture::applyDrag(const ValuePoint &grabCurrent)
{
    if (points.empty() || grabbedPoint >= points.size())
        return;
    const ValuePoint grabOriginal = points[grabbedPoint].original;
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
                                 const ValuePoint &mappedGrabBeforeLock)
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
                           const AutomationProjection &proj, const AutomationRow &row,
                           int verticalSlopDistance)
{
    return updatePencilDrawPath(*this, position, freehand, lock, proj, row, verticalSlopDistance);
}

void updateValuePoint(const AutomationProjection &proj, int rowIndex, const AutomationRow &row,
                      ValuePoint &point, int y, uint64_t tick, bool snapValue,
                      int neutralSnapRadius)
{
    point.value = proj.valueAtY(rowIndex, y);
    if (snapValue && row.id.kind == EditorAutomationRowKind::ControlChange) {
        const int neutral = row.id.controller == 0xFF
                                ? 0
                                : (row.id.controller == 10 || row.id.controller == 24 ? 64 : -1);
        if (neutral >= 0) {
            const int span = proj.rowMaximum(row) - proj.rowMinimum(row);
            if (std::abs(point.value - neutral) <=
                span * neutralSnapRadius / std::max(1, proj.rowHeight(row)))
                point.value = neutral;
        }
    }
    point.tick = tick;
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

void applyAxisLock(AxisLock lock, const ValuePoint &original, ValuePoint &current) noexcept
{
    if (lock == AxisLock::None)
        return;
    if (lock == AxisLock::Time)
        current.value = original.value;
    else
        current.tick = original.tick;
}

bool updatePencilDrawPath(PencilGesture &gesture, const QPointF &position, bool freehand,
                          AxisLock lock, const AutomationProjection &proj, const AutomationRow &row,
                          int verticalSlopDistance)
{
    const auto [top, bottom] = proj.valuePlotBounds(gesture.row);
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
                                 double(proj.rowMaximum(row) - proj.rowMinimum(row)) /
                                 double(std::max(1, bottom - top)),
                         double(proj.rowMinimum(row)), double(proj.rowMaximum(row)));
    const AutomationProjection::PointerMapping current =
        proj.pointerMapping(gesture.row, position.x(), position.y());
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
