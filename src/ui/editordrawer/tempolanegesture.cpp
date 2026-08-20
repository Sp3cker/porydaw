#include "ui/editordrawer/tempolane.h"

#include <algorithm>
#include <cmath>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationpage.h"
void TempoLane::updateActiveGesture(AutomationArea &area, const QPointF &position,
                                    Qt::KeyboardModifiers modifiers,
                                    const AutomationGeometry &geometry, bool activateSweep)
{
    if (!m_activeGesture || !m_page)
        return;
    const bool fine = modifiers & Qt::AltModifier;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    if (auto *gesture = std::get_if<NodeDragGesture>(&*m_activeGesture)) {
        const PointDragUpdate dragUpdate =
            gesture->drag.update(position, modifiers, geometry.nodeDragActivationDistance);
        if (dragUpdate.phase == PointDragUpdate::Phase::Pending)
            return;
        ValuePoint mapped;
        if (dragUpdate.phase == PointDragUpdate::Phase::Dragging)
            mapped = mappedPoint(dragUpdate.effectivePosition, projection, geometry, fine);
        area.updateAxisLockCursor(gesture->update(dragUpdate, mapped));
        return;
    }
    auto &gesture = std::get<SweepGesture>(*m_activeGesture);
    if (gesture.mode == SweepGesture::Mode::Ramp) {
        gesture.update(mappedPoint(position, projection, geometry, fine));
        return;
    }
    const auto effective =
        gesture.dragPosition(position, activateSweep, geometry.nodeDragActivationDistance);
    if (!effective)
        return;
    const ValuePoint mapped = mappedPoint(*effective, projection, geometry, fine);
    const double rawTick = projection.rawTickAt(effective->x());
    const uint64_t first = m_page->snapTick(std::min(gesture.previousRawTick, rawTick), fine);
    const uint64_t last = m_page->snapTick(std::max(gesture.previousRawTick, rawTick), fine);
    gesture.update(mapped, first, last, rawTick, fine,
                   [this](uint64_t tick, bool fineGrid, uint64_t limit) {
                       return m_page->nextGridTick(tick, fineGrid, limit);
                   });
}
std::optional<std::size_t> TempoLane::hitPoint(const QPointF &position,
                                               const AutomationProjection &projection,
                                               const AutomationGeometry &geometry,
                                               qreal devicePixelRatio) const
{
    if (!m_page || !m_page->document() || !containsBody(position))
        return std::nullopt;
    return nearestPointInRadius(
        m_page->document()->tempoPoints(), projection.rawTickAt(position.x()), position,
        geometry.pointHitRadius,
        [&projection, devicePixelRatio](const TempoPoint &point) {
            return projection.displayX(point.tick, devicePixelRatio);
        },
        [this, &geometry](const TempoPoint &point) {
            return AutomationProjection::valueY(
                m_body, geometry, CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm,
                CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote));
        });
}

int TempoLane::bpmAt(qreal y, const AutomationGeometry &geometry) const
{
    return std::clamp(
        qRound(AutomationProjection::valueAtY(m_body, geometry, CoreTimeDefaults::kMinTempoBpm,
                                              CoreTimeDefaults::kMaxTempoBpm, y)),
        CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm);
}

ValuePoint TempoLane::mappedPoint(const QPointF &position, const AutomationProjection &projection,
                                  const AutomationGeometry &geometry, bool fine) const
{
    return {projection.snapTickAt(position.x(), fine), bpmAt(position.y(), geometry)};
}

std::optional<TempoLane::NodeDragState>
TempoLane::nodeDragGestureAt(const QPointF &position, bool axisLockArmed,
                             const AutomationProjection &projection,
                             const AutomationGeometry &geometry, qreal devicePixelRatio) const
{
    const auto hit = hitPoint(position, projection, geometry, devicePixelRatio);
    if (!hit || !m_page || !m_page->document())
        return std::nullopt;
    const auto &tempoPoints = m_page->document()->tempoPoints();
    const auto makeNode = [](const TempoPoint &point) {
        const int bpm = qRound(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote));
        return NodeDrag{0,
                        {point.tick, bpm},
                        {point.tick, bpm},
                        CoreTimeDefaults::kMinTempoBpm,
                        CoreTimeDefaults::kMaxTempoBpm};
    };
    NodeDragState state;
    state.gesture.row = 0;
    const TempoPoint grabbed = tempoPoints[*hit];
    if (pointInTimeSelection(grabbed.tick)) {
        for (const TempoPoint &point : tempoPoints) {
            if (!pointInTimeSelection(point.tick))
                continue;
            state.gesture.points.push_back(makeNode(point));
            state.identities.push_back(point);
        }
        const auto grabbedPosition =
            std::find(state.identities.cbegin(), state.identities.cend(), grabbed);
        if (grabbedPosition != state.identities.cend()) {
            state.gesture.grabbedPoint = std::size_t(grabbedPosition - state.identities.cbegin());
            state.gesture.selectionDrag = true;
        }
    }
    if (state.gesture.points.empty()) {
        state.gesture.points.push_back(makeNode(grabbed));
        state.identities.push_back(grabbed);
    }
    state.gesture.drag.press(position, !axisLockArmed);
    std::vector<std::vector<ValuePoint>> lanePoints(1);
    lanePoints.front().reserve(tempoPoints.size());
    for (const TempoPoint &point : tempoPoints)
        lanePoints.front().push_back(
            {point.tick, qRound(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote))});
    state.gesture.preparePreview(1, lanePoints);
    return state;
}

void TempoLane::finishActiveGesture(bool fine, const AutomationGeometry &geometry)
{
    if (!m_activeGesture || !m_page || !m_page->document())
        return;
    if (const auto *gesture = std::get_if<NodeDragGesture>(&*m_activeGesture)) {
        if (m_activeNodeIdentities.size() != gesture->points.size())
            return;
        const NodeDragFinish finish = gesture->finish();
        if (finish.release == PointDragRelease::StationaryDelete) {
            const TempoPoint original = m_activeNodeIdentities[gesture->grabbedPoint];
            applyEdit({{original}, {}});
            m_deletedNodeClick.markDeleted();
            return;
        }
        if (finish.release != PointDragRelease::Move || !finish.changed)
            return;
        TempoEdit edit;
        edit.remove.reserve(gesture->points.size());
        edit.add.reserve(gesture->points.size());
        for (std::size_t index = 0; index < gesture->points.size(); ++index) {
            const NodeDrag &point = gesture->points[index];
            edit.remove.push_back(m_activeNodeIdentities[index]);
            edit.add.push_back(
                {point.current.tick,
                 CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.current.value)});
        }
        std::sort(
            edit.add.begin(), edit.add.end(),
            [](const TempoPoint &left, const TempoPoint &right) { return left.tick < right.tick; });
        applyEdit(edit);
        if (finish.dTick != 0 && finish.selectionDrag) {
            const auto &selection = m_page->m_owner.selectionModel().timeSelection();
            const uint64_t first =
                uint64_t(std::max<int64_t>(0, int64_t(selection.startTick) + finish.dTick));
            const uint64_t last =
                uint64_t(std::max<int64_t>(0, int64_t(selection.endTick) + finish.dTick));
            if (last > first)
                publishTimeSelection(first, last);
        }
        return;
    }
    const auto &gesture = std::get<SweepGesture>(*m_activeGesture);
    if (gesture.mode == SweepGesture::Mode::Drag && !gesture.slop.exceeded) {
        const AutomationProjection projection(geometry, {}, m_page, 0);
        m_page->commitEditCursor(
            m_page->snapTick(projection.rawTickAt(gesture.pressPosition.x()), false));
        return;
    }
    const std::vector<ValuePoint> result =
        gesture.finishedPoints(fine, [this](uint64_t tick, bool fineGrid, uint64_t limit) {
            return m_page->nextGridTick(tick, fineGrid, limit);
        });
    if (result.empty())
        return;
    TempoEdit edit;
    for (const TempoPoint &point : m_page->document()->tempoPoints())
        if (point.tick >= result.front().tick && point.tick <= result.back().tick)
            edit.remove.push_back(point);
    edit.add.reserve(result.size());
    for (const ValuePoint &point : result)
        edit.add.push_back(
            {point.tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
    applyEdit(edit);
}

bool TempoLane::pointInTimeSelection(uint64_t tick) const
{
    if (!hasTimeSelection())
        return false;
    const auto &selection = m_page->m_owner.selectionModel().timeSelection();
    return tick >= selection.startTick && tick < selection.endTick;
}

bool TempoLane::deleteTimeSelection()
{
    if (!hasTimeSelection() || !m_page || !m_page->document())
        return false;
    TempoEdit edit;
    for (const TempoPoint &point : m_page->document()->tempoPoints())
        if (pointInTimeSelection(point.tick))
            edit.remove.push_back(point);
    applyEdit(edit);
    clearHover();
    return true;
}
