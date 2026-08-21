#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <variant>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"

namespace {

template <class... Ts>
struct Visitor : Ts... {
    using Ts::operator()...;
};
template <class... Ts>
Visitor(Ts...) -> Visitor<Ts...>;

} // namespace

bool AutomationCanvas::pencilPointHit(const AutomationRow &row, int rowIndex,
                                      const QPointF &position, DocLanePoint *point) const
{
    return pencilPointHit(row, rowIndex, position, projection(), point);
}
bool AutomationCanvas::pencilPointHit(const AutomationRow &row, int rowIndex,
                                      const QPointF &position, const AutomationProjection &proj,
                                      DocLanePoint *point) const
{
    if (!m_page || !m_page->document() || (m_pencilMode && !proj.nodeMarkersVisible()))
        return false;
    DocLanePoint hit;
    if (!m_rowData.cachedPointHit(row, rowIndex, position, proj, m_geometry, devicePixelRatioF(),
                                  &hit))
        return false;
    if (point)
        *point = hit;
    return true;
}

bool AutomationCanvas::commitLaneEdit(int rowIndex, const NodeLaneEdit::Completion &completion)
{
    if (completion.unchanged || !m_page || !m_page->document() || rowIndex < 0 ||
        rowIndex >= int(m_rowData.rows().size()))
        return false;
    int track = -1;
    uint8_t controller = 0;
    if (!m_rowData.rowTarget(m_rowData.rows()[rowIndex], &track, &controller) ||
        track != completion.target.engineTrack || controller != completion.target.controller ||
        m_page->document()->revision() != completion.target.expectedRevision)
        return false;
    std::vector<SongDocument::LanePointValue> lanePoints;
    lanePoints.reserve(completion.points.size());
    for (const auto &point : completion.points)
        lanePoints.push_back({point.tick, point.value});
    m_page->document()->writeLanePoints(track, controller, completion.tickBegin, completion.tickEnd,
                                        lanePoints);
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
                    ValuePoint mappedGrab;
                    if (dragUpdate.phase == PointDragUpdate::Phase::Dragging)
                        mappedGrab = this->mappedForRow(gesture.row, dragUpdate.effectivePosition,
                                                        fineGrid, snapValue, proj);
                    axisCursor = gesture.update(dragUpdate, mappedGrab);
                },
                [this, position, fineGrid, snapValue, activateSweep, &proj, &snappedRange,
                 &nextGridTick](SweepGesture &gesture) {
                    if (gesture.mode == SweepGesture::Mode::Ramp) {
                        const ValuePoint mapped =
                            this->mappedForRow(gesture.row, position, fineGrid, snapValue, proj);
                        gesture.update(mapped);
                        return;
                    }
                    const auto effective = gesture.dragPosition(
                        position, activateSweep, m_geometry.nodeDragActivationDistance);
                    if (!effective)
                        return;
                    const ValuePoint mapped =
                        this->mappedForRow(gesture.row, *effective, fineGrid, snapValue, proj);
                    const double rawTick = proj.rawTickAt(effective->x());
                    const auto [first, last] = snappedRange(gesture.previousRawTick, rawTick);
                    gesture.update(mapped, first, last, rawTick, fineGrid, nextGridTick);
                },
                [this, position, modifiers, &proj](PencilGesture &gesture) {
                    const bool freehand = modifiers & Qt::ControlModifier;
                    const AxisLock lock =
                        modifiers & Qt::ShiftModifier ? AxisLock::Value : AxisLock::None;
                    gesture.update(position, freehand, lock, proj, m_rowData.rows()[gesture.row],
                                   m_geometry.nodeDragActivationDistance);
                }},
        *m_activeGesture);
    if (std::holds_alternative<NodeDragGesture>(*m_activeGesture))
        updateAxisLockCursor(axisCursor);
    m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, m_rowData, proj,
                                         m_activeGesture);
}

void AutomationCanvas::finishActiveGesture(bool fineMode)
{
    if (!m_page || !m_activeGesture)
        return;
    auto *document = m_page->document();
    const AutomationProjection proj = projection();
    const int rowIndex =
        std::visit([](const auto &gesture) { return gesture.row; }, *m_activeGesture);
    int track = -1;
    uint8_t controller = 0;
    const bool hasTarget = document && rowIndex >= 0 && rowIndex < int(m_rowData.rows().size()) &&
                           m_rowData.rowTarget(m_rowData.rows()[rowIndex], &track, &controller);
    bool changed = false;
    if (const auto *gesture = std::get_if<NodeDragGesture>(&*m_activeGesture)) {
        if (!document || m_activeNodeIdentities.size() != gesture->points.size())
            return;
        const NodeDragFinish finish = gesture->finish();
        if (finish.release == PointDragRelease::StationaryDelete &&
            gesture->grabbedPoint < m_activeNodeIdentities.size()) {
            const auto &identity = m_activeNodeIdentities[gesture->grabbedPoint];
            document->deleteLanePoints(identity.engineTrack, identity.controller,
                                       {identity.documentPoint});
            m_deletedNodeClick.markDeleted();
            changed = true;
        } else if (finish.release == PointDragRelease::Move && finish.changed) {
            std::vector<SongDocument::LanePointMove> moves;
            moves.reserve(gesture->points.size());
            for (std::size_t index = 0; index < gesture->points.size(); ++index) {
                const NodeDrag &point = gesture->points[index];
                const LaneNodeIdentity &identity = m_activeNodeIdentities[index];
                moves.push_back({identity.engineTrack, identity.controller, identity.documentPoint,
                                 point.current.tick, point.current.value});
            }
            document->moveLanePoints(moves);
            if (finish.dTick != 0 && finish.selectionDrag) {
                const auto &selection = m_rowData.timeSelection();
                if (selection.active()) {
                    const auto startTick =
                        uint64_t(std::max<int64_t>(0, int64_t(selection.startTick) + finish.dTick));
                    const auto endTick =
                        uint64_t(std::max<int64_t>(0, int64_t(selection.endTick) + finish.dTick));
                    if (endTick > startTick)
                        m_page->publishTimeSelection(startTick, endTick, selection.lanes);
                }
            }
            changed = true;
        }
    } else {
        GestureCommit commit = std::visit(
            Visitor{[](const NodeDragGesture &) -> GestureCommit { return std::monostate{}; },
                    [this, &proj, document, hasTarget, track, controller,
                     fineMode](const SweepGesture &gesture) -> GestureCommit {
                        if (gesture.mode == SweepGesture::Mode::Drag && !gesture.slop.exceeded) {
                            m_page->commitEditCursor(
                                m_page->snapTick(proj.rawTickAt(gesture.pressPosition.x()), false));
                            return std::monostate{};
                        }
                        if (!hasTarget)
                            return std::monostate{};
                        const auto existing = document->lanePoints(track, controller);
                        auto completion = gesture.finish(
                            track, controller, document->revision(), existing, fineMode,
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
                                     [this, rowIndex](const NodeLaneEdit::Completion &completion) {
                                         return commitLaneEdit(rowIndex, completion);
                                     }},
                             commit);
    }
    if (changed)
        m_page->requestRefresh();
}

LaneNodeDragState
AutomationCanvas::collectSelectedNodeDrags(const AutomationProjection &projection) const
{
    LaneNodeDragState result;
    if (!m_rowData.timeSelection().active() || !m_page || !m_page->document())
        return result;
    const auto &rows = m_rowData.rows();
    for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
        const auto lane = m_rowData.rowIdentity(rows[rowIndex]);
        if (!m_rowData.timeSelection().coversLane(lane.first, lane.second))
            continue;
        int track = -1;
        uint8_t controller = 0;
        if (!m_rowData.rowTarget(rows[rowIndex], &track, &controller))
            continue;
        const auto docPoints = m_page->document()->lanePoints(track, controller);
        for (const auto &point : docPoints) {
            if (!m_rowData.timeSelection().contains(point.tick))
                continue;
            const DocLanePoint documentPoint{point.smfTrack, point.index, point.tick, point.value};
            result.gesture.points.push_back({rowIndex,
                                             {documentPoint.tick, documentPoint.value},
                                             {documentPoint.tick, documentPoint.value},
                                             projection.rowMinimum(rows[rowIndex]),
                                             projection.rowMaximum(rows[rowIndex])});
            result.identities.push_back({track, controller, documentPoint});
        }
    }
    return result;
}

std::optional<LaneNodeDragState>
AutomationCanvas::nodeDragGestureAt(int rowIndex, const QPointF &position, bool axisLockArmed,
                                    const AutomationProjection &projection, bool pencilMode) const
{
    const auto &rows = m_rowData.rows();
    if (rowIndex < 0 || rowIndex >= int(rows.size()) || !m_page || !m_page->document() ||
        (pencilMode && !projection.nodeMarkersVisible()))
        return std::nullopt;
    DocLanePoint hit;
    if (!m_rowData.cachedPointHit(rows[rowIndex], rowIndex, position, projection, m_geometry,
                                  devicePixelRatioF(), &hit))
        return std::nullopt;
    int track = -1;
    uint8_t controller = 0;
    if (!m_rowData.rowTarget(rows[rowIndex], &track, &controller))
        return std::nullopt;
    LaneNodeDragState state;
    state.gesture.row = rowIndex;
    const NodeDrag grabbed{rowIndex,
                           {hit.tick, hit.value},
                           {hit.tick, hit.value},
                           projection.rowMinimum(rows[rowIndex]),
                           projection.rowMaximum(rows[rowIndex])};
    const LaneNodeIdentity grabbedIdentity{track, controller, hit};
    if (m_rowData.pointInTimeSelection(rowIndex, hit.tick)) {
        auto selected = collectSelectedNodeDrags(projection);
        const auto grabbedPosition =
            std::find_if(selected.identities.cbegin(), selected.identities.cend(),
                         [&hit](const LaneNodeIdentity &identity) {
                             return identity.documentPoint.smfTrack == hit.smfTrack &&
                                    identity.documentPoint.index == hit.index;
                         });
        if (grabbedPosition != selected.identities.cend()) {
            selected.gesture.grabbedPoint = size_t(grabbedPosition - selected.identities.cbegin());
            selected.gesture.selectionDrag = true;
            state = std::move(selected);
            state.gesture.row = rowIndex;
        }
    }
    if (state.gesture.points.empty()) {
        state.gesture.points.push_back(grabbed);
        state.identities.push_back(grabbedIdentity);
    }
    state.gesture.drag.press(position, !axisLockArmed);
    std::vector<std::vector<ValuePoint>> lanePointsByRow(rows.size());
    for (size_t i = 0; i < rows.size(); ++i)
        for (const LanePoint &point : m_rowData.pointsFor(rows[i], projection))
            lanePointsByRow[i].push_back({point.tick, point.value});
    state.gesture.preparePreview(rows.size(), lanePointsByRow);
    return state;
}
