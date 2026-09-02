#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <unordered_map>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/nodelane/batchcommit.h"

namespace {

template <class... Ts>
struct Visitor : Ts... {
    using Ts::operator()...;
};
template <class... Ts>
Visitor(Ts...) -> Visitor<Ts...>;

} // namespace

bool AutomationCanvas::nodePointHit(LaneHandle handle, const QPointF &position,
                                    NodePoint *point) const
{
    return nodePointHit(handle, position, projection(), point);
}

bool AutomationCanvas::nodePointHit(LaneHandle handle, const QPointF &position,
                                    const AutomationProjection &proj, NodePoint *point) const
{
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body) || !lane)
        return false;
    if (hitNodePoint(*lane, body, proj, m_geometry, position,
                     m_inputHost ? m_inputHost->devicePixelRatio() : 1.0, m_pencilMode, point))
        return true;
    const auto phantom = originPhantomAt(handle, position, proj);
    if (!phantom)
        return false;
    if (point)
        *point = phantom->point;
    return true;
}

std::optional<OriginPhantom>
AutomationCanvas::originPhantomAt(LaneHandle handle, const QPointF &position,
                                  const AutomationProjection &proj) const
{
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body) || !lane)
        return std::nullopt;
    const auto points = lane->points();
    const auto phantom = originPhantom(handle, proj, points);
    if (!phantom)
        return std::nullopt;
    const QPointF center(qreal(m_geometry.plotOrigin),
                         AutomationProjection::valueY(body, m_geometry, phantom->minimumValue,
                                                      phantom->maximumValue, phantom->point.value));
    if (pointDistanceSquared(position, center) >
        m_geometry.pointHitRadius * m_geometry.pointHitRadius)
        return std::nullopt;
    return phantom;
}

std::optional<OriginPhantom>
AutomationCanvas::originPhantom(LaneHandle handle, const AutomationProjection &proj,
                                std::span<const NodePoint> points) const
{
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body) || !lane)
        return std::nullopt;
    return ::originPhantomAt(points, handle, lane->minimumValue(), lane->maximumValue(),
                             double(m_geometry.plotOrigin), [this, &proj](uint64_t tick) {
                                 return proj.displayX(
                                     tick, m_inputHost ? m_inputHost->devicePixelRatio() : 1.0);
                             });
}

bool AutomationCanvas::commitResolvedNodeLaneChanges(std::optional<uint64_t> expectedRevision,
                                                     const std::vector<NodeLaneChange> &changes,
                                                     const QString &undoLabel)
{
    if (!m_page.document() || changes.empty())
        return false;
    auto *document = m_page.document();
    if (expectedRevision && document->revision() != *expectedRevision)
        return false;
    SongDocument::RangeEdit edit;
    std::vector<uint64_t> tempoDeletes;
    std::vector<nodelane::CcDeleteRequest> ccDeletes;
    for (const NodeLaneChange &change : changes) {
        const NodeLaneSlot *slot = change.slot;
        if (!slot || !slot->lane)
            return false;
        const bool resolved = slot->visit(
            [&]() -> bool {
                if (!change.moves.empty()) {
                    const auto moveResult = nodelane::resolveTempoMoves(*document, change.moves);
                    if (!moveResult)
                        return false;
                    nodelane::appendResolvedTempoMoves(edit, *moveResult);
                }
                tempoDeletes.insert(tempoDeletes.end(), change.deleteTicks.cbegin(),
                                    change.deleteTicks.cend());
                return true;
            },
            [&]() -> bool {
                if (!change.moves.empty()) {
                    const auto moveResult = nodelane::resolveCcMoves(
                        *document, int(slot->id.track), slot->id.controller, change.moves);
                    if (!moveResult)
                        return false;
                    nodelane::appendResolvedCcMoves(edit, *moveResult);
                }
                if (!change.deleteTicks.empty())
                    ccDeletes.push_back(
                        {int(slot->id.track), slot->id.controller, change.deleteTicks});
                return true;
            });
        if (!resolved)
            return false;
    }
    if (!tempoDeletes.empty() || !ccDeletes.empty()) {
        const auto resolved = nodelane::resolveBatchDeletes(*document, tempoDeletes, ccDeletes);
        if (!resolved)
            return false;
        edit.removeTempo.insert(edit.removeTempo.end(), resolved->removeTempo.cbegin(),
                                resolved->removeTempo.cend());
        edit.removePoints.insert(edit.removePoints.end(), resolved->removePoints.cbegin(),
                                 resolved->removePoints.cend());
    }
    if (edit.empty())
        return false;
    document->applyRangeEdit(undoLabel, edit);
    return true;
}

bool AutomationCanvas::commitLaneEdit(const NodeLaneEdit::Completion &completion)
{
    if (completion.unchanged || !m_page.document())
        return false;
    if (m_page.document()->revision() != completion.target.expectedRevision)
        return false;
    NodeLane *lane = mutableLane(completion.target.lane);
    if (!lane)
        return false;
    lane->replaceSpan(completion.tickBegin, completion.tickEnd, completion.points);
    return true;
}

bool AutomationCanvas::commitNodePointMoves(uint64_t expectedRevision,
                                            const std::vector<NodeDrag> &points)
{
    std::vector<NodeLaneChange> changes;
    std::unordered_map<const NodeLaneSlot *, std::size_t> changeIndex;
    changeIndex.reserve(points.size());
    for (const NodeDrag &point : points) {
        const NodeLaneSlot *slot = resolveSlot(point.lane);
        if (!slot)
            return false;
        const auto [entry, inserted] = changeIndex.try_emplace(slot, changes.size());
        if (inserted)
            changes.push_back(NodeLaneChange{slot});
        changes[entry->second].moves.push_back(
            {point.original.tick, {point.current.tick, point.current.value}});
    }
    return commitResolvedNodeLaneChanges(expectedRevision, changes, tr("edit automation points"));
}

bool AutomationCanvas::commitNodePointDeletes(std::optional<uint64_t> expectedRevision,
                                              const std::vector<NodeDrag> &points)
{
    std::vector<NodeLaneChange> changes;
    std::unordered_map<const NodeLaneSlot *, std::size_t> changeIndex;
    changeIndex.reserve(points.size());
    for (const NodeDrag &point : points) {
        const NodeLaneSlot *slot = resolveSlot(point.lane);
        if (!slot)
            return false;
        const auto [entry, inserted] = changeIndex.try_emplace(slot, changes.size());
        if (inserted)
            changes.push_back(NodeLaneChange{slot});
        changes[entry->second].deleteTicks.push_back(point.original.tick);
    }
    return commitResolvedNodeLaneChanges(expectedRevision, changes,
                                         tr("delete automation point(s)"));
}

void AutomationCanvas::updateActiveGesture(const QPointF &position, Qt::KeyboardModifiers modifiers,
                                           bool activateSweep)
{
    if (!m_activeGesture)
        return;
    const bool fineGrid = modifiers & Qt::AltModifier;
    const bool snapValue = modifiers & Qt::ControlModifier;
    const AutomationProjection proj = projection();
    AxisLock axisCursor = AxisLock::None;
    auto snappedRange = [&](double a, double b) -> std::pair<uint64_t, uint64_t> {
        return {m_page.snapTick(std::min(a, b), fineGrid),
                m_page.snapTick(std::max(a, b), fineGrid)};
    };
    auto nextGridTick = [this](uint64_t tick, bool useFineGrid, uint64_t limit) -> uint64_t {
        return m_page.nextGridTick(tick, useFineGrid, limit);
    };
    std::visit(
        Visitor{
            [this, position, fineGrid, snapValue, &proj, &axisCursor,
             modifiers](NodeDragGesture &gesture) {
                const PointDragUpdate dragUpdate =
                    gesture.drag.update(position, modifiers, m_geometry.nodeDragActivationDistance);
                NodePoint mappedGrab;
                if (dragUpdate.phase == PointDragUpdate::Phase::Dragging)
                    mappedGrab = this->mappedForLane(gesture.lane, dragUpdate.effectivePosition,
                                                     fineGrid, snapValue, proj);
                axisCursor = gesture.update(dragUpdate, mappedGrab);
            },
            [this, position, modifiers, snapValue, &proj, &axisCursor](PhantomGesture &gesture) {
                const PointDragUpdate dragUpdate =
                    gesture.drag.update(position, modifiers, m_geometry.nodeDragActivationDistance);
                const NodeLane *lane = nullptr;
                QRect body;
                if (!resolveLane(gesture.lane, &lane, &body) || !lane)
                    return;
                auto mappedValue = gesture.point.original.value;
                if (dragUpdate.phase == PointDragUpdate::Phase::Dragging) {
                    NodePoint mapped;
                    updateValuePoint(proj, *lane, body, mapped, dragUpdate.effectivePosition.y(),
                                     gesture.point.original.tick, snapValue,
                                     m_geometry.neutralSnapRadius, lane->neutralValue());
                    mappedValue = mapped.value;
                }
                axisCursor = gesture.update(dragUpdate, mappedValue);
            },
            [this, position, fineGrid, snapValue, activateSweep, &proj, &snappedRange,
             &nextGridTick](SweepGesture &gesture) {
                if (gesture.mode == SweepGesture::Mode::Ramp) {
                    const NodePoint mapped =
                        this->mappedForLane(gesture.lane, position, fineGrid, snapValue, proj);
                    gesture.update(mapped);
                    return;
                }
                const auto effective = gesture.dragPosition(position, activateSweep,
                                                            m_geometry.nodeDragActivationDistance);
                if (!effective)
                    return;
                const NodePoint mapped =
                    this->mappedForLane(gesture.lane, *effective, fineGrid, snapValue, proj);
                const double rawTick = proj.rawTickAt(effective->x());
                const auto [first, last] = snappedRange(gesture.previousRawTick, rawTick);
                gesture.update(mapped, first, last, rawTick, fineGrid, nextGridTick);
            },
            [this, position, modifiers, &proj](PencilGesture &gesture) {
                const NodeLane *lane = nullptr;
                QRect body;
                if (!resolveLane(gesture.lane, &lane, &body) || !lane)
                    return;
                const bool freehand = modifiers & Qt::ControlModifier;
                const AxisLock lock =
                    modifiers & Qt::ShiftModifier ? AxisLock::Value : AxisLock::None;
                gesture.update(position, freehand, lock, proj, *lane, body,
                               m_geometry.nodeDragActivationDistance);
            }},
        *m_activeGesture);
    if (std::holds_alternative<NodeDragGesture>(*m_activeGesture) ||
        std::holds_alternative<PhantomGesture>(*m_activeGesture))
        updateAxisLockCursor(axisCursor);
    syncPreviewValueLabel();
}

void AutomationCanvas::finishActiveGesture(bool fineMode)
{
    if (!m_activeGesture)
        return;
    auto *document = m_page.document();
    if (!document)
        return;
    const AutomationProjection proj = projection();
    const LaneHandle handle =
        std::visit([](const auto &gesture) { return gesture.lane; }, *m_activeGesture);
    NodeLane *lane = mutableLane(handle);
    bool changed = false;
    if (const auto *gesture = std::get_if<NodeDragGesture>(&*m_activeGesture)) {
        if (document->revision() != gesture->expectedRevision)
            return;
        const NodeDragFinish finish = gesture->finish();
        if (finish.release == PointDragRelease::StationaryDelete &&
            gesture->grabbedPoint < gesture->points.size()) {
            changed = commitNodePointDeletes(gesture->expectedRevision,
                                             {gesture->points[gesture->grabbedPoint]});
            if (changed)
                m_deletedNodeClick.markDeleted();
        } else if (finish.release == PointDragRelease::Move && finish.changed) {
            changed = commitNodePointMoves(gesture->expectedRevision, gesture->points);
            if (changed && finish.dTick != 0 && finish.selectionDrag) {
                const auto &selection = m_page.m_owner.selectionModel().timeSelection();
                if (selection.active()) {
                    const auto startTick =
                        uint64_t(std::max<int64_t>(0, int64_t(selection.startTick) + finish.dTick));
                    const auto endTick =
                        uint64_t(std::max<int64_t>(0, int64_t(selection.endTick) + finish.dTick));
                    if (endTick > startTick) {
                        auto movedSelection = selection;
                        movedSelection.startTick = startTick;
                        movedSelection.endTick = endTick;
                        m_page.m_owner.selectionModel().setTimeSelection(std::move(movedSelection));
                    }
                }
            }
        }
    } else if (const auto *gesture = std::get_if<PhantomGesture>(&*m_activeGesture)) {
        if (document->revision() != gesture->expectedRevision)
            return;
        if (const auto point = gesture->finish())
            changed = commitNodePointMoves(gesture->expectedRevision, {*point});
    } else if (const auto *gesture = std::get_if<SweepGesture>(&*m_activeGesture)) {
        if (gesture->mode == SweepGesture::Mode::Drag && !gesture->slop.exceeded) {
            m_page.commitEditCursor(
                m_page.snapTick(proj.rawTickAt(gesture->pressPosition.x()), false));
        } else if (lane) {
            auto completion =
                gesture->finish(handle, document->revision(), lane->points(), fineMode,
                                [this](uint64_t tick, bool fineGrid, uint64_t last) {
                                    return m_page.nextGridTick(tick, fineGrid, last);
                                });
            if (!completion.unchanged)
                changed = commitLaneEdit(completion);
        }
    } else if (auto *gesture = std::get_if<PencilGesture>(&*m_activeGesture)) {
        auto completion = std::move(*gesture).finish();
        if (!completion.unchanged)
            changed = commitLaneEdit(completion);
    }
    if (changed)
        m_page.requestRefresh();
}

NodeDragGesture AutomationCanvas::collectSelectedNodeDrags() const
{
    NodeDragGesture result;
    if (!m_page.document())
        return result;
    const auto activeTickRange = m_laneSelection.activeTickRange();
    for (std::size_t index = 0; index < m_nodeStack.size(); ++index) {
        const NodeLaneSlot &slot = m_nodeStack[index];
        const NodeLane *lane = slot.lane;
        if (!lane)
            continue;
        const LaneHandle handle{int(index)};
        if (!m_laneSelection.coversNodes(slot.id) || !activeTickRange)
            continue;
        for (const NodePoint &point : lane->points()) {
            if (point.tick < activeTickRange->first || point.tick >= activeTickRange->second)
                continue;
            result.points.push_back(
                {handle, point, point, lane->minimumValue(), lane->maximumValue()});
        }
    }
    return result;
}

std::optional<NodeDragGesture>
AutomationCanvas::nodeDragGestureAt(LaneHandle handle, const QPointF &position, bool axisLockArmed,
                                    const AutomationProjection &projection, bool pencilMode) const
{
    const NodeLaneSlot *slot = resolveSlot(handle);
    const NodeLane *lane = slot ? slot->lane : nullptr;
    if (!slot || !lane || !m_page.document() || (pencilMode && !projection.nodeMarkersVisible()))
        return std::nullopt;
    NodePoint hit;
    if (!hitNodePoint(*lane, slot->body, projection, m_geometry, position,
                      m_inputHost ? m_inputHost->devicePixelRatio() : 1.0, pencilMode, &hit))
        return std::nullopt;
    NodeDragGesture state;
    state.lane = handle;
    state.expectedRevision = m_page.document()->revision();
    const NodeDrag grabbed{handle, hit, hit, lane->minimumValue(), lane->maximumValue()};
    const auto activeTickRange = m_laneSelection.activeTickRange();
    const bool hitSelected = m_laneSelection.coversNodes(slot->id) && activeTickRange &&
                             hit.tick >= activeTickRange->first &&
                             hit.tick < activeTickRange->second;
    if (hitSelected) {
        auto selected = collectSelectedNodeDrags();
        const auto grabbedPosition = std::find_if(
            selected.points.cbegin(), selected.points.cend(), [&](const NodeDrag &point) {
                return point.lane == handle && point.original.tick == hit.tick;
            });
        if (grabbedPosition != selected.points.cend()) {
            selected.grabbedPoint = size_t(grabbedPosition - selected.points.cbegin());
            selected.selectionDrag = true;
            state = std::move(selected);
            state.lane = handle;
            state.expectedRevision = m_page.document()->revision();
        }
    }
    if (state.points.empty())
        state.points.push_back(grabbed);
    state.drag.press(position, !axisLockArmed);
    std::vector<std::vector<NodePoint>> lanePoints(m_nodeStack.size());
    for (int index = 0; index < int(m_nodeStack.size()); ++index) {
        const NodeLane *stackLane = m_nodeStack[std::size_t(index)].lane;
        if (!stackLane)
            continue;
        lanePoints[std::size_t(index)] = stackLane->points();
    }
    state.preparePreview(m_nodeStack.size(), lanePoints);
    return state;
}

std::optional<PhantomGesture> AutomationCanvas::phantomDragGestureAt(LaneHandle handle,
                                                                     const QPointF &position) const
{
    if (!m_page.document())
        return std::nullopt;
    const auto phantom = originPhantomAt(handle, position, projection());
    if (!phantom)
        return std::nullopt;
    PhantomGesture state;
    state.lane = handle;
    state.expectedRevision = m_page.document()->revision();
    state.point = {handle, phantom->point, phantom->point, phantom->minimumValue,
                   phantom->maximumValue};
    state.drag.press(position, false);
    return state;
}
