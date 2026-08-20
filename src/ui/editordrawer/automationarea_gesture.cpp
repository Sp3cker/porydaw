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
        Visitor{
            [this, position, fineGrid, snapValue, &proj, &axisCursor,
             modifiers](NodeDragGesture &gesture) {
                const QPointF effective = [&]() -> QPointF {
                    if (!gesture.dragSlop.exceeded)
                        return position;
                    return QPointF(
                        gesture.pressPosition.x() + (position.x() - gesture.dragSlop.origin.x()),
                        gesture.pressPosition.y() + (position.y() - gesture.dragSlop.origin.y()));
                }();
                const ValuePoint mappedGrab =
                    this->mappedForRow(gesture.row, effective, fineGrid, snapValue, proj);
                axisCursor =
                    gesture.update(position, mappedGrab, modifiers,
                                   m_geometry.nodeDragActivationDistance, m_rowData.rows(), proj);
            },
            [this, position, fineGrid, snapValue, activateSweep, &proj, &snappedRange,
             &nextGridTick](SweepGesture &gesture) {
                if (gesture.mode == SweepGesture::Mode::Ramp) {
                    const ValuePoint mapped =
                        this->mappedForRow(gesture.row, position, fineGrid, snapValue, proj);
                    gesture.update(mapped);
                    return;
                }
                if (!gesture.slop.exceeded) {
                    const QPointF delta = position - gesture.pressPosition;
                    const qreal travel = std::abs(delta.x()) + std::abs(delta.y());
                    const auto activationDistance = qreal(m_geometry.nodeDragActivationDistance);
                    if (!activateSweep || travel < activationDistance)
                        return;
                    gesture.slop.markExceeded(position);
                    return;
                }
                const QPointF effective = gesture.pressPosition + position - gesture.slop.origin;
                if (gesture.points.empty() && effective == gesture.pressPosition)
                    return;
                const ValuePoint mapped =
                    this->mappedForRow(gesture.row, effective, fineGrid, snapValue, proj);
                const double rawTick = proj.rawTickAt(effective.x());
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
    GestureCommit commit = std::visit(
        Visitor{[](const NodeDragGesture &gesture) -> GestureCommit { return gesture.finish(); },
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
                    auto completion =
                        gesture.finish(track, controller, document->revision(), existing, fineMode,
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
    const bool changed = std::visit(
        Visitor{[](std::monostate) { return false; },
                [this, rowIndex](const AutomationLaneEdit::Completion &completion) {
                    return commitLaneEdit(rowIndex, completion);
                },
                [this, document](const NodeDeleteCommit &del) {
                    document->deleteLanePoints(del.track, del.controller, {del.point});
                    m_hoverState.hover.nodeDeleted = true;
                    return true;
                },
                [this, document](const NodeMoveCommit &move) {
                    document->moveLanePoints(move.moves);
                    if (move.dTick != 0 && move.selectionDrag) {
                        const auto &selection = m_rowData.timeSelection();
                        if (selection.active()) {
                            auto moved = selection.range;
                            moved.startTick = uint64_t(
                                std::max<int64_t>(0, int64_t(moved.startTick) + move.dTick));
                            moved.endTick =
                                uint64_t(std::max<int64_t>(0, int64_t(moved.endTick) + move.dTick));
                            if (!moved.empty())
                                m_page->publishTimeSelection(moved.startTick, moved.endTick,
                                                             selection.scope.lanes);
                        }
                    }
                    return true;
                }},
        commit);
    if (changed)
        m_page->requestRefresh();
}
