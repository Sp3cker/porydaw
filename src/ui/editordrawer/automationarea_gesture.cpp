#include "ui/editordrawer/automationarea.h"

#include <algorithm>
#include <cmath>
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

bool AutomationArea::pencilPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                                    DocLanePoint *point) const
{
    return pencilPointHit(row, rowIndex, position, projection(), point);
}
bool AutomationArea::pencilPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                                    const AutomationProjection &proj, DocLanePoint *point) const
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

bool AutomationArea::commitLaneEdit(int rowIndex, const AutomationLaneEdit::Completion &completion)
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
    m_page->document()->writeLanePoints(track, controller, completion.tickBegin, completion.tickEnd,
                                        completion.points);
    return true;
}

void AutomationArea::updateActiveGesture(const QPointF &position, Qt::KeyboardModifiers modifiers,
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

void AutomationArea::finishActiveGesture(bool fineMode)
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
                    auto moved = selection.range;
                    moved.startTick =
                        uint64_t(std::max<int64_t>(0, int64_t(moved.startTick) + finish.dTick));
                    moved.endTick =
                        uint64_t(std::max<int64_t>(0, int64_t(moved.endTick) + finish.dTick));
                    if (!moved.empty())
                        m_page->publishTimeSelection(moved.startTick, moved.endTick,
                                                     selection.scope.lanes);
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
        changed =
            std::visit(Visitor{[](std::monostate) { return false; },
                               [this, rowIndex](const AutomationLaneEdit::Completion &completion) {
                                   return commitLaneEdit(rowIndex, completion);
                               }},
                       commit);
    }
    if (changed)
        m_page->requestRefresh();
}
