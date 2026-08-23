#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <cmath>

#include <QKeyEvent>
#include <QMouseEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QWheelEvent>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"

bool AutomationCanvas::isEditablePencilHit(const QPointF &position) const noexcept
{
    if (position.x() < qreal(m_geometry.plotOrigin))
        return false;
    const PointerLaneHit pointer = pointerLaneAt(position.toPoint());
    if (pointer.tempoHeader)
        return false;
    const auto *slot = resolveSlot(pointer.lane);
    return slot && slot->lane != nullptr;
}

void AutomationCanvas::updatePencilCursor()
{
    if (!m_pencilMode) {
        setCursor(Qt::ArrowCursor);
        return;
    }
    setCursor(isEditablePencilHit(mapFromGlobal(QCursor::pos())) ? pencilCursor()
                                                                 : QCursor(Qt::ArrowCursor));
}

void AutomationCanvas::wheelEvent(QWheelEvent *event)
{
    if (!m_page || !m_page->ready())
        return;
    const QPoint pixelDelta = event->pixelDelta();
    const QPoint delta = pixelDelta.isNull() ? event->angleDelta() : pixelDelta;
    const int vertical = delta.y() != 0 ? delta.y() : delta.x();
    if (event->modifiers() & Qt::ControlModifier) {
        m_resize.wheelRemainder += vertical;
        const int steps = m_resize.wheelRemainder / 120;
        if (steps != 0) {
            m_resize.wheelRemainder -= steps * 120;
            const int shared = m_page->m_viewState.laneHeight > 0 ? m_page->m_viewState.laneHeight
                                                                  : m_geometry.rowDefaultHeight;
            const int height = std::clamp(shared + steps * m_geometry.rowWheelIncrement,
                                          m_geometry.rowMinimumHeight, m_geometry.rowMaximumHeight);
            if (height != shared) {
                const double factor = double(height) / double(shared);
                for (auto &[row, rowHeight] : m_page->m_viewState.laneHeights)
                    rowHeight =
                        std::clamp(int(std::lround(rowHeight * factor)),
                                   m_geometry.rowMinimumHeight, m_geometry.rowMaximumHeight);
                m_page->m_viewState.laneHeight = height;
                layoutLaneStack(m_voiceLane.engineTrack());
            }
        }
    } else if (event->modifiers() & Qt::ShiftModifier) {
        m_page->requestHorizontalScroll(m_page->liveState().horizontalScroll - vertical);
    } else if (delta.x() != 0 && delta.y() == 0) {
        m_page->requestHorizontalScroll(m_page->liveState().horizontalScroll - delta.x());
    } else if (event->position().x() < m_geometry.plotOrigin) {
        event->ignore();
        return;
    } else if (vertical != 0) {
        m_page->requestTimeZoom(event, event->position().x() - m_geometry.plotOrigin);
    }
    event->accept();
}

void AutomationCanvas::mousePressEvent(QMouseEvent *event)
{
    invalidateContent(m_hoverState.clearHover());
    m_deletedNodeClick.clear();
    if (!m_page || !m_page->document())
        return;
    if (event->button() == Qt::MiddleButton) {
        m_pan.active = true;
        m_pan.pos = event->position();
        m_pan.startHScroll = m_page->liveState().horizontalScroll;
        m_pan.startVScroll = m_scroll ? m_scroll->verticalScrollBar()->value() : 0;
        setCursor(Qt::ClosedHandCursor);
        setGestureActive(true);
        event->accept();
        return;
    }
    const AutomationProjection proj = projection();
    const PointerLaneHit pointer = pointerLaneAt(event->pos());
    const bool inTempoHeader = pointer.tempoHeader;
    const LaneHandle pointerLane = pointer.lane;
    const auto *pointerSlot = resolveSlot(pointerLane);
    const bool inTempo = pointerSlot && pointerSlot->isTempo();
    if (inTempo)
        m_voiceLane.clearHover(*this);
    if (!inTempo && m_voiceLane.contains(event->pos())) {
        setFocus();
        m_voiceLane.mousePress(*this, event, m_geometry);
        event->accept();
        return;
    }
    if ((event->button() == Qt::LeftButton || event->button() == Qt::RightButton)) {
        auto &model = m_page->m_owner.selectionModel();
        const auto activeTickRange =
            m_laneSelection ? m_laneSelection->activeTickRange() : std::nullopt;
        NodePoint selectedPoint;
        const bool selectedNode =
            pointerSlot && event->position().x() >= m_geometry.plotOrigin && m_laneSelection &&
            m_laneSelection->coversNodes(pointerSlot->id) && activeTickRange &&
            nodePointHit(pointerLane, event->position(), proj, &selectedPoint) &&
            selectedPoint.tick >= activeTickRange->first &&
            selectedPoint.tick < activeTickRange->second;
        const bool insideSelection =
            pointerSlot && event->position().x() >= m_geometry.plotOrigin && m_laneSelection &&
            (m_laneSelection->hitTest(pointerSlot->id, event->position().x(), proj,
                                      devicePixelRatioF()) ||
             selectedNode);
        if (!insideSelection && model.timeSelection().active()) {
            model.clearTimeSelection();
            invalidateContent();
        }
    }
    if (inTempoHeader) {
        if (event->button() == Qt::LeftButton) {
            m_tempoLane.toggleExpanded();
            updateTempoLayout();
        } else if (event->button() == Qt::RightButton) {
            m_band.press(event->pos(), m_page->snapTick(proj.rawTickAt(event->position().x()),
                                                        event->modifiers() & Qt::AltModifier));
            m_band.pressLane(pointerLane);
            setGestureActive(true);
        }
        setFocus();
        event->accept();
        return;
    }
    const int boundary =
        !inTempo && event->button() == Qt::LeftButton ? ccRowBoundaryAt(event->pos().y()) : -1;
    if (boundary >= 0) {
        m_resize.row = boundary;
        m_resize.startHeight = ccLaneHeight(m_rowData.rows()[std::size_t(boundary)]);
        m_resize.startY = event->pos().y();
        setGestureActive(true);
        return;
    }
    const QRect addRect(layout::space(layout::Space::Zero), addLaneStripTop(), width(),
                        m_geometry.addLaneStripHeight);
    if (!inTempo && (event->button() == Qt::LeftButton || event->button() == Qt::RightButton) &&
        addRect.contains(event->pos())) {
        showAddLaneMenu(event->globalPosition().toPoint());
        return;
    }
    const LaneHandle handle = pointerLane;
    const auto *laneSlot = resolveSlot(handle);
    if (!laneSlot)
        return;
    const NodeLane *lane = laneSlot->lane;
    const QRect body = laneSlot->body;
    setFocus();
    if (event->position().x() < m_geometry.plotOrigin) {
        if (event->button() == Qt::RightButton)
            showLaneMenuFor(handle, event->globalPosition().toPoint());
        return;
    }
    if (event->button() == Qt::RightButton) {
        m_band.press(event->pos(), m_page->snapTick(proj.rawTickAt(event->position().x()),
                                                    event->modifiers() & Qt::AltModifier));
        m_band.pressLane(handle);
        NodePoint point;
        if (nodePointHit(handle, event->position(), proj, &point))
            highlightHoveredPoint(handle, event->position(), point);
        setGestureActive(true);
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    const bool fine = event->modifiers() & Qt::AltModifier;
    if (m_pencilMode) {
        const auto *timeline = m_page->timeline();
        if (!timeline)
            return;
        const AutomationProjection::PointerMapping mapped =
            proj.pointerMapping(*lane, body, event->position().x(), event->position().y());
        if (auto nodeGesture =
                nodeDragGestureAt(handle, event->position(), event->modifiers() & Qt::ShiftModifier,
                                  proj, m_pencilMode)) {
            const auto grabbedPoint = nodeGesture->grabbedPoint;
            if (grabbedPoint < nodeGesture->points.size()) {
                const uint64_t hitTick = nodeGesture->points[grabbedPoint].original.tick;
                if (hitTick >= mapped.cell.tickBegin && hitTick < mapped.cell.tickEnd) {
                    m_activeGesture.emplace(std::move(*nodeGesture));
                    setGestureActive(true);
                    syncPreviewValueLabel();
                    invalidateContent();
                    return;
                }
            }
        }
        const AutomationPencilGesture::Target target{handle, m_page->document()->revision()};
        const AutomationPencilGesture::Sample sample{mapped.rawTick, event->position().x(),
                                                     mapped.point, double(mapped.point.value)};
        auto stroke = AutomationPencilGesture::start(
            target, lane->minimumValue(), lane->maximumValue(), timeline->lengthTicks,
            m_page->document()->ticksPerClock(), lane->points(), sample, mapped.cell);
        if (!stroke)
            return;
        PencilGesture pencil{handle, std::move(*stroke)};
        pencil.verticalSlop.origin = event->position();
        pencil.previousY = event->position().y();
        m_activeGesture.emplace(std::move(pencil));
        setGestureActive(true);
        syncPreviewValueLabel();
        invalidateContent();
        return;
    }
    const NodePoint mapped = mappedForLane(handle, event->position(), fine,
                                           event->modifiers() & Qt::ControlModifier, proj);
    setGestureActive(true);
    if (auto nodeGesture =
            nodeDragGestureAt(handle, event->position(), event->modifiers() & Qt::ShiftModifier,
                              proj, m_pencilMode)) {
        m_activeGesture.emplace(std::move(*nodeGesture));
    } else {
        SweepGesture sweep;
        sweep.lane = handle;
        sweep.mode = event->modifiers() & Qt::ShiftModifier ? SweepGesture::Mode::Ramp
                                                            : SweepGesture::Mode::Drag;
        sweep.anchor = mapped;
        sweep.current = mapped;
        sweep.previousRawTick = proj.rawTickAt(event->position().x());
        sweep.previousValue = mapped.value;
        sweep.pressPosition = event->position();
        sweep.slop.origin = event->position();
        if (sweep.mode == SweepGesture::Mode::Ramp)
            sweep.slop.markExceeded(event->position());
        m_activeGesture.emplace(std::move(sweep));
    }
    syncPreviewValueLabel();
    invalidateContent();
}

void AutomationCanvas::mouseMoveEvent(QMouseEvent *event)
{
    if (m_pan.active) {
        if (!(event->buttons() & Qt::MiddleButton)) {
            m_pan.active = false;
            unsetCursor();
            setGestureActive(false);
            return;
        }
        const QPointF delta = event->position() - m_pan.pos;
        m_page->requestHorizontalScroll(m_pan.startHScroll - delta.x());
        if (m_scroll)
            m_scroll->verticalScrollBar()->setValue(m_pan.startVScroll - int(delta.y()));
        event->accept();
        return;
    }
    const AutomationProjection proj = projection();
    if (m_resize.row >= 0 && m_resize.row < int(m_rowData.rows().size())) {
        const int height = std::clamp(m_resize.startHeight + event->pos().y() - m_resize.startY,
                                      m_geometry.rowMinimumHeight, m_geometry.rowMaximumHeight);
        if (height != ccLaneHeight(m_rowData.rows()[std::size_t(m_resize.row)])) {
            m_page->m_viewState.laneHeights[m_rowData.rows()[std::size_t(m_resize.row)].id] =
                height;
            m_page->publishViewState();
            layoutLaneStack(m_voiceLane.engineTrack());
            invalidateContent();
        }
        return;
    }
    if (m_band.pending) {
        if (m_band.move(event->pos(), m_page->snapTick(proj.rawTickAt(event->position().x()),
                                                       event->modifiers() & Qt::AltModifier))) {
            m_hoverState.hover.highlightLocked = false;
            invalidateContent(m_hoverState.clearHover());
        }
        if (m_band.active) {
            const int lastY = std::max(layout::space(layout::Space::Zero),
                                       addLaneStripTop() - layout::singlePixel());
            const int y = std::clamp(event->pos().y(), layout::space(layout::Space::Zero), lastY);
            const LaneHandle candidate = pointerLaneAt(QPoint(event->pos().x(), y)).lane;
            const auto *startSlot = resolveSlot(m_band.laneRange().first);
            const auto *candidateSlot = resolveSlot(candidate);
            const bool compatible =
                startSlot && candidateSlot && startSlot->id.kind == candidateSlot->id.kind;
            m_band.extendTo(candidate, compatible);
            invalidateContent();
        }
        return;
    }
    if (!m_activeGesture) {
        const PointerLaneHit pointer = pointerLaneAt(event->pos());
        if (pointer.tempoHeader) {
            m_voiceLane.clearHover(*this);
            invalidateContent(m_hoverState.clearHover());
            setCursor(Qt::ArrowCursor);
            return;
        }
        const LaneHandle pointerLane = pointer.lane;
        const auto *pointerSlot = resolveSlot(pointerLane);
        const bool inTempo = pointerSlot && pointerSlot->isTempo();
        if (!inTempo && m_voiceLane.contains(event->pos())) {
            invalidateContent(m_hoverState.clearHover());
            m_voiceLane.updateHover(*this, m_geometry, event->position().x(), event->pos().y());
            setCursor(Qt::ArrowCursor);
            return;
        }
        m_voiceLane.clearHover(*this);
        if (!inTempo && ccRowBoundaryAt(event->pos().y()) >= 0) {
            invalidateContent(m_hoverState.clearHover());
            setCursor(Qt::SplitVCursor);
            return;
        }
        const qreal x = event->position().x();
        const int y = event->pos().y();
        const LaneHandle handle = x >= m_geometry.plotOrigin ? pointerLane : LaneHandle{};
        const auto *slot = resolveSlot(handle);
        if (!m_page || !slot)
            invalidateContent(m_hoverState.clearHover());
        else
            invalidateContent(m_hoverState.updateHover(hoverTarget(), m_geometry, *slot->lane,
                                                       slot->body, handle, proj, x, y,
                                                       m_pencilMode));
        if (m_pencilMode && isEditablePencilHit(event->position()))
            setCursor(pencilCursor());
        else
            setCursor(Qt::ArrowCursor);
        return;
    }
    updateActiveGesture(event->position(), event->modifiers(), true);
    invalidateContent();
}

void AutomationCanvas::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_pan.active) {
        m_pan.active = false;
        unsetCursor();
        setGestureActive(false);
        event->accept();
        return;
    }
    if (event->button() == Qt::RightButton && m_band.pending) {
        const LaneHandle pointerLane = pointerLaneAt(event->pos()).lane;
        const auto *startSlot = resolveSlot(m_band.laneRange().first);
        const auto *candidateSlot = resolveSlot(pointerLane);
        const bool compatible =
            startSlot && candidateSlot && startSlot->id.kind == candidateSlot->id.kind;
        m_band.extendTo(pointerLane, compatible);
        const auto [laneFirst, laneLast] = m_band.laneRange();
        const LaneHandle contextLane = laneFirst;
        const auto selection = m_band.release();
        if (selection && selection->first < selection->second && laneFirst.valid() &&
            laneLast.valid()) {
            publishBandSelection(selection->first, selection->second, laneFirst, laneLast);
        } else if (selection) {
            auto &model = m_page->m_owner.selectionModel();
            if (model.timeSelection().active()) {
                model.clearTimeSelection();
                invalidateContent();
            }
        } else {
            m_hoverState.hover.highlightLocked = false;
            invalidateContent(m_hoverState.clearHover());
            if (!showPointMenuNear(contextLane, event->pos(), event->globalPosition().toPoint())) {
                const bool inPlot = event->position().x() >= m_geometry.plotOrigin;
                const auto *contextSlot = resolveSlot(contextLane);
                const bool selected =
                    contextSlot && inPlot && m_laneSelection &&
                    m_laneSelection->hitTest(contextSlot->id, event->position().x(), projection(),
                                             devicePixelRatioF());
                if (selected)
                    showTimeSelectionMenuFor(contextLane, event->globalPosition().toPoint());
                else if (contextLane.valid())
                    showLaneMenuFor(contextLane, event->globalPosition().toPoint());
            }
        }
        setGestureActive(false);
        invalidateContent();
        return;
    }
    if (event->button() == Qt::LeftButton && m_resize.row >= 0) {
        m_resize.row = -1;
        setGestureActive(false);
        return;
    }
    if (event->button() != Qt::LeftButton || !m_activeGesture)
        return;
    updateActiveGesture(event->position(), event->modifiers(), false);
    finishActiveGesture(event->modifiers() & Qt::AltModifier);
    m_activeGesture.reset();
    m_hoverState.previewValueLabel = {};
    setGestureActive(false);
    updateAxisLockCursor(AxisLock::None);
    invalidateContent();
}

void AutomationCanvas::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (!m_page || !m_page->document())
        return;
    const PointerLaneHit pointer = pointerLaneAt(event->pos());
    const bool inTempoHeader = pointer.tempoHeader;
    const LaneHandle handle = pointer.lane;
    const auto *slot = resolveSlot(handle);
    const bool inTempo = slot && slot->isTempo();
    if (inTempo)
        m_voiceLane.clearHover(*this);
    if (inTempoHeader) {
        invalidateContent(m_hoverState.clearHover());
        if (event->button() == Qt::LeftButton) {
            m_tempoLane.toggleExpanded();
            updateTempoLayout();
        }
        return;
    }
    if (!inTempo && m_voiceLane.contains(event->pos())) {
        m_voiceLane.mouseDoubleClick(*this, event, m_geometry);
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    if (!inTempo && event->position().x() < m_geometry.plotOrigin)
        return;
    const auto *laneSlot = resolveSlot(handle);
    if (!laneSlot)
        return;
    const NodeLane *lane = laneSlot->lane;
    if (m_deletedNodeClick.consume())
        return;
    NodePoint hit;
    if (nodePointHit(handle, event->position(), &hit))
        return;
    if (m_pencilMode) {
        m_activeGesture.reset();
        m_hoverState.previewValueLabel = {};
        setGestureActive(false);
        invalidateContent();
        return;
    }
    m_activeGesture.reset();
    m_hoverState.previewValueLabel = {};
    setGestureActive(false);
    const AutomationProjection proj = projection();
    const uint64_t tick = m_page->snapTick(proj.rawTickAt(event->position().x()),
                                           event->modifiers() & Qt::AltModifier);
    int value = mappedForLane(handle, event->position(), false, false, proj).value;
    bool accepted = lane->promptValue(this, value, &value);
    if (!accepted)
        return;
    NodeLane *target = laneSlot->lane;
    if (!target)
        return;
    const std::vector<NodePoint> existing = target->points();
    for (const NodePoint &point : existing) {
        if (point.tick == tick && point.value == value)
            return;
    }
    target->replaceSpan(tick, tick, {{tick, value}});
    m_page->requestRefresh();
}

void AutomationCanvas::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        if (m_band.pending || m_activeGesture) {
            cancelInteraction();
        } else {
            auto &model = m_page->m_owner.selectionModel();
            if (model.timeSelection().active()) {
                model.clearTimeSelection();
                invalidateContent();
            }
            invalidateContent(m_hoverState.clearHover());
        }
        event->accept();
        return;
    }
    if ((event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace)) {
        auto selected = collectSelectedNodeDrags();
        if (!selected.points.empty()) {
            commitNodePointDeletes(std::nullopt, selected.points);
            invalidateContent(m_hoverState.clearHover());
            m_page->requestRefresh();
            event->accept();
            return;
        }
        if (m_pencilMode && m_hoverState.hover.lane.valid()) {
            NodePoint point;
            if (nodePointHit(m_hoverState.hover.lane, m_hoverState.hover.pos, &point)) {
                if (const auto *slot = resolveSlot(m_hoverState.hover.lane); slot && slot->lane) {
                    NodeLane *lane = slot->lane;
                    const NodeDrag drag{m_hoverState.hover.lane, point, point, lane->minimumValue(),
                                        lane->maximumValue()};
                    commitNodePointDeletes(m_page->document()->revision(), {drag});
                    invalidateContent(m_hoverState.clearHover());
                    m_page->requestRefresh();
                }
            }
            event->accept();
            return;
        }
    }
    QWidget::keyPressEvent(event);
}

void AutomationCanvas::leaveEvent(QEvent *)
{
    m_voiceLane.clearHover(*this);
    invalidateContent(m_hoverState.clearHover());
}
