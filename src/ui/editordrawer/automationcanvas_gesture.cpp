#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <utility>
#include <variant>
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

bool ccLaneIdentity(const CCLanes &rowData, LaneHandle handle, int *engineTrack,
                    uint8_t *controller)
{
    if (handle.index <= 0)
        return false;
    const auto &rows = rowData.rows();
    const int rowIndex = handle.index - 1;
    if (rowIndex >= int(rows.size()))
        return false;
    const auto identity = rowData.rowIdentity(rows[std::size_t(rowIndex)]);
    if (engineTrack)
        *engineTrack = identity.first;
    if (controller)
        *controller = identity.second;
    return true;
}
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
    if (!resolveLane(handle, &lane, &body) || !lane || !m_page)
        return false;
    return hitNodePoint(*lane, body, proj, m_geometry, position, devicePixelRatioF(), m_pencilMode,
                        point);
}

bool AutomationCanvas::commitLaneEdit(const NodeLaneEdit::Completion &completion)
{
    if (completion.unchanged || !m_page || !m_page->document())
        return false;
    if (m_page->document()->revision() != completion.target.expectedRevision)
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
    if (!m_page || !m_page->document() || points.empty())
        return false;
    auto *document = m_page->document();
    if (document->revision() != expectedRevision)
        return false;
    std::vector<std::vector<NodePointMove>> movesByLane(m_nodeStack.size());
    for (const NodeDrag &point : points) {
        if (!point.lane.valid() || point.lane.index >= int(movesByLane.size()) ||
            !mutableLane(point.lane))
            return false;
        if (point.lane.index > 0) {
            int track = 0;
            uint8_t controller = 0;
            if (!ccLaneIdentity(m_rowData, point.lane, &track, &controller))
                return false;
        }
        movesByLane[std::size_t(point.lane.index)].push_back(
            {point.original.tick, {point.current.tick, point.current.value}});
    }
    int occupied = 0;
    int occupiedIndex = -1;
    for (int index = 0; index < int(movesByLane.size()); ++index) {
        if (movesByLane[std::size_t(index)].empty())
            continue;
        ++occupied;
        occupiedIndex = index;
    }
    if (occupied == 0)
        return false;
    if (occupied == 1) {
        NodeLane *lane = mutableLane(LaneHandle{occupiedIndex});
        if (!lane)
            return false;
        lane->movePoints(movesByLane[std::size_t(occupiedIndex)]);
        return true;
    }
    SongDocument::RangeEdit edit;
    if (!movesByLane.empty() && !movesByLane.front().empty()) {
        const auto tempoEdit = nodelane::resolveTempoMoves(*document, movesByLane.front());
        if (!tempoEdit)
            return false;
        nodelane::appendResolvedTempoMoves(edit, *tempoEdit);
    }
    for (int index = 1; index < int(movesByLane.size()); ++index) {
        if (movesByLane[std::size_t(index)].empty())
            continue;
        int track = 0;
        uint8_t controller = 0;
        if (!ccLaneIdentity(m_rowData, LaneHandle{index}, &track, &controller))
            return false;
        const auto resolved =
            nodelane::resolveCcMoves(*document, track, controller, movesByLane[std::size_t(index)]);
        if (!resolved)
            return false;
        nodelane::appendResolvedCcMoves(edit, *resolved);
    }
    if (edit.empty())
        return false;
    document->applyRangeEdit(tr("edit automation points"), edit);
    return true;
}

bool AutomationCanvas::commitNodePointDeletes(std::optional<uint64_t> expectedRevision,
                                              const std::vector<NodeDrag> &points)
{
    if (!m_page || !m_page->document() || points.empty())
        return false;
    auto *document = m_page->document();
    if (expectedRevision && document->revision() != *expectedRevision)
        return false;
    std::vector<std::vector<uint64_t>> ticksByLane(m_nodeStack.size());
    for (const NodeDrag &point : points) {
        if (!point.lane.valid() || point.lane.index >= int(ticksByLane.size()) ||
            !mutableLane(point.lane))
            return false;
        if (point.lane.index > 0) {
            int track = 0;
            uint8_t controller = 0;
            if (!ccLaneIdentity(m_rowData, point.lane, &track, &controller))
                return false;
        }
        ticksByLane[std::size_t(point.lane.index)].push_back(point.original.tick);
    }
    int occupied = 0;
    int occupiedIndex = -1;
    for (int index = 0; index < int(ticksByLane.size()); ++index) {
        if (ticksByLane[std::size_t(index)].empty())
            continue;
        ++occupied;
        occupiedIndex = index;
    }
    if (occupied == 0)
        return false;
    if (occupied == 1) {
        NodeLane *lane = mutableLane(LaneHandle{occupiedIndex});
        if (!lane)
            return false;
        lane->deletePoints(ticksByLane[std::size_t(occupiedIndex)]);
        return true;
    }
    std::vector<uint64_t> tempoTicks;
    if (!ticksByLane.empty())
        tempoTicks = ticksByLane.front();
    std::vector<nodelane::CcDeleteRequest> ccDeletes;
    for (int index = 1; index < int(ticksByLane.size()); ++index) {
        if (ticksByLane[std::size_t(index)].empty())
            continue;
        int track = 0;
        uint8_t controller = 0;
        if (!ccLaneIdentity(m_rowData, LaneHandle{index}, &track, &controller))
            return false;
        ccDeletes.push_back({track, controller, ticksByLane[std::size_t(index)]});
    }
    const auto edit = nodelane::resolveBatchDeletes(*document, tempoTicks, ccDeletes);
    if (!edit || edit->empty())
        return false;
    document->applyRangeEdit(tr("delete automation point(s)"), *edit);
    return true;
}

void AutomationCanvas::updateActiveGesture(const QPointF &position, Qt::KeyboardModifiers modifiers,
                                           bool activateSweep)
{
    if (!m_activeGesture || !m_page)
        return;
    const bool fineGrid = modifiers & Qt::AltModifier;
    const bool snapValue = modifiers & Qt::ControlModifier;
    const AutomationProjection proj = projection();
    AxisLock axisCursor = AxisLock::None;
    auto snappedRange = [&](double a, double b) -> std::pair<uint64_t, uint64_t> {
        return {m_page->snapTick(std::min(a, b), fineGrid),
                m_page->snapTick(std::max(a, b), fineGrid)};
    };
    auto nextGridTick = [this](uint64_t tick, bool useFineGrid, uint64_t limit) -> uint64_t {
        return m_page->nextGridTick(tick, useFineGrid, limit);
    };
    std::visit(
        Visitor{[this, position, fineGrid, snapValue, &proj, &axisCursor,
                 modifiers](NodeDragGesture &gesture) {
                    const PointDragUpdate dragUpdate = gesture.drag.update(
                        position, modifiers, m_geometry.nodeDragActivationDistance);
                    if (dragUpdate.phase == PointDragUpdate::Phase::Pending)
                        return;
                    NodePoint mappedGrab;
                    if (dragUpdate.phase == PointDragUpdate::Phase::Dragging)
                        mappedGrab = this->mappedForLane(gesture.lane, dragUpdate.effectivePosition,
                                                         fineGrid, snapValue, proj);
                    axisCursor = gesture.update(dragUpdate, mappedGrab);
                },
                [this, position, fineGrid, snapValue, activateSweep, &proj, &snappedRange,
                 &nextGridTick](SweepGesture &gesture) {
                    if (gesture.mode == SweepGesture::Mode::Ramp) {
                        const NodePoint mapped =
                            this->mappedForLane(gesture.lane, position, fineGrid, snapValue, proj);
                        gesture.update(mapped);
                        return;
                    }
                    const auto effective = gesture.dragPosition(
                        position, activateSweep, m_geometry.nodeDragActivationDistance);
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
    if (std::holds_alternative<NodeDragGesture>(*m_activeGesture))
        updateAxisLockCursor(axisCursor);
    syncPreviewValueLabel();
}

void AutomationCanvas::finishActiveGesture(bool fineMode)
{
    if (!m_page || !m_activeGesture)
        return;
    auto *document = m_page->document();
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
                const auto &selection = m_page->m_owner.selectionModel().timeSelection();
                if (selection.active()) {
                    const auto startTick =
                        uint64_t(std::max<int64_t>(0, int64_t(selection.startTick) + finish.dTick));
                    const auto endTick =
                        uint64_t(std::max<int64_t>(0, int64_t(selection.endTick) + finish.dTick));
                    if (endTick > startTick)
                        m_page->publishTimeSelection(startTick, endTick, selection.lanes,
                                                     selection.tempo);
                }
            }
        }
    } else {
        GestureCommit commit = std::visit(
            Visitor{[](const NodeDragGesture &) -> GestureCommit { return std::monostate{}; },
                    [this, &proj, document, lane, handle,
                     fineMode](const SweepGesture &gesture) -> GestureCommit {
                        if (gesture.mode == SweepGesture::Mode::Drag && !gesture.slop.exceeded) {
                            m_page->commitEditCursor(
                                m_page->snapTick(proj.rawTickAt(gesture.pressPosition.x()), false));
                            return std::monostate{};
                        }
                        if (!lane)
                            return std::monostate{};
                        auto completion =
                            gesture.finish(handle, document->revision(), lane->points(), fineMode,
                                           [this](uint64_t tick, bool fineGrid, uint64_t last) {
                                               return m_page->nextGridTick(tick, fineGrid, last);
                                           });
                        if (completion.unchanged)
                            return std::monostate{};
                        return GestureCommit{std::move(completion)};
                    },
                    [](PencilGesture &gesture) -> GestureCommit {
                        auto completion = std::move(gesture).finish();
                        if (completion.unchanged)
                            return std::monostate{};
                        return GestureCommit{std::move(completion)};
                    }},
            *m_activeGesture);
        changed = std::visit(Visitor{[](std::monostate) { return false; },
                                     [this](const NodeLaneEdit::Completion &completion) {
                                         return commitLaneEdit(completion);
                                     }},
                             commit);
    }
    if (changed)
        m_page->requestRefresh();
}

NodeDragGesture AutomationCanvas::collectSelectedNodeDrags() const
{
    NodeDragGesture result;
    if (!m_page || !m_page->document())
        return result;
    for (int index = 0; index < int(m_nodeStack.size()); ++index) {
        const NodeLane *lane = m_nodeStack[std::size_t(index)].lane;
        if (!lane)
            continue;
        const LaneHandle handle{index};
        for (const NodePoint &point : lane->points()) {
            if (!lane->pointSelected(point.tick))
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
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body) || !lane || !m_page || !m_page->document() ||
        (pencilMode && !projection.nodeMarkersVisible()))
        return std::nullopt;
    NodePoint hit;
    if (!nodePointHit(handle, position, projection, &hit))
        return std::nullopt;
    NodeDragGesture state;
    state.lane = handle;
    state.expectedRevision = m_page->document()->revision();
    const NodeDrag grabbed{handle, hit, hit, lane->minimumValue(), lane->maximumValue()};
    if (lane->pointSelected(hit.tick)) {
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
            state.expectedRevision = m_page->document()->revision();
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
