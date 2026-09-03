#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>

#include <QCursor>

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
    if (!m_inputHost)
        return;
    if (!m_pencilMode) {
        m_inputHost->clearCursor();
        return;
    }
    const QPointF position = contentPositionFromGlobal(QCursor::pos());
    if (isEditablePencilHit(position))
        m_inputHost->setCursor(pencilCursor());
    else
        m_inputHost->clearCursor();
}

bool AutomationCanvas::wheel(const songview::TimelineWheelInput &input)
{
    if (!m_page.ready())
        return false;
    const QPoint delta = input.pixelDelta.isNull() ? input.angleDelta : input.pixelDelta;
    const int vertical = delta.y() != 0 ? delta.y() : delta.x();
    const QPointF position = contentPosition(input.position);
    if (input.modifiers & Qt::ControlModifier) {
        m_resize.wheelRemainder += vertical;
        const int steps = m_resize.wheelRemainder / 120;
        if (steps != 0) {
            m_resize.wheelRemainder -= steps * 120;
            if (m_page.scaleSharedHeight(steps, m_geometry))
                contentGeometryChanged();
        }
    } else if (input.modifiers & Qt::ShiftModifier) {
        m_page.requestHorizontalScroll(m_page.liveState().horizontalScroll - vertical);
    } else if (delta.x() != 0 && delta.y() == 0) {
        m_page.requestHorizontalScroll(m_page.liveState().horizontalScroll - delta.x());
    } else if (position.x() < m_geometry.plotOrigin) {
        return m_page.scrollVertically(input);
    } else if (vertical != 0) {
        m_page.requestTimeZoom(input, position.x() - m_geometry.plotOrigin);
    }
    return true;
}

void AutomationCanvas::clearTimeSelectionIfOutsidePress(QPointF position,
                                                        const AutomationProjection &projection,
                                                        LaneHandle lane, const NodeLaneSlot *slot)
{
    auto &model = m_page.m_owner.selectionModel();
    const auto activeTickRange = m_laneSelection.activeTickRange();
    Q_ASSERT(activeTickRange);
    const auto [firstTick, lastTick] = *activeTickRange;
    auto laneSelectionHit = false;
    auto selectedNode = false;
    if (slot) {
        laneSelectionHit = m_laneSelection.hitTest(slot->id, position.x(), projection,
                                                   m_inputHost->devicePixelRatio());
        if (m_laneSelection.coversNodes(slot->id)) {
            NodePoint selectedPoint;
            if (nodePointHit(lane, position, projection, &selectedPoint)) {
                selectedNode =
                    std::clamp(selectedPoint.tick, firstTick, lastTick - 1) == selectedPoint.tick;
            }
        }
    }
    if (laneSelectionHit || selectedNode)
        return;
    model.clearTimeSelection();
    requestSelectionQuickUpdate();
}

bool AutomationCanvas::beginPencilPress(QPointF position, Qt::KeyboardModifiers modifiers,
                                        LaneHandle handle, const NodeLane &lane, const QRect &body,
                                        const AutomationProjection &projection)
{
    const auto *timeline = m_page.timeline();
    if (!timeline)
        return false;
    const AutomationProjection::PointerMapping mapped =
        projection.pointerMapping(lane, body, position.x(), position.y());
    if (auto nodeGesture = nodeDragGestureAt(handle, position, modifiers & Qt::ShiftModifier,
                                             projection, m_pencilMode)) {
        const auto grabbedPoint = nodeGesture->grabbedPoint;
        if (grabbedPoint < nodeGesture->points.size()) {
            const uint64_t hitTick = nodeGesture->points[grabbedPoint].original.tick;
            if (std::clamp(hitTick, mapped.cell.tickBegin, mapped.cell.tickEnd - 1) == hitTick) {
                m_activeGesture.emplace(std::move(*nodeGesture));
                setGestureActive(true);
                syncPreviewValueLabel();
                requestGestureBeginQuickUpdate(false);
                return true;
            }
        }
    }
    const AutomationPencilGesture::Target target{handle, m_page.document()->revision()};
    const AutomationPencilGesture::Sample sample{mapped.rawTick, position.x(), mapped.point,
                                                 double(mapped.point.value)};
    auto stroke = AutomationPencilGesture::start(
        target, lane.minimumValue(), lane.maximumValue(), timeline->lengthTicks,
        m_page.document()->ticksPerClock(), lane.points(), lane.leadIn(), sample, mapped.cell);
    if (!stroke)
        return false;
    PencilGesture pencil{handle, std::move(*stroke)};
    pencil.verticalSlop.origin = position;
    pencil.previousY = position.y();
    m_activeGesture.emplace(std::move(pencil));
    setGestureActive(true);
    syncPreviewValueLabel();
    requestGestureBeginQuickUpdate(false);
    return true;
}

bool AutomationCanvas::beginDragOrSweep(QPointF position, Qt::KeyboardModifiers modifiers,
                                        LaneHandle handle, const AutomationProjection &projection)
{
    const bool fine = modifiers & Qt::AltModifier;
    const NodePoint mapped =
        mappedForLane(handle, position, fine, modifiers & Qt::ControlModifier, projection);
    setGestureActive(true);
    if (auto nodeGesture = nodeDragGestureAt(handle, position, modifiers & Qt::ShiftModifier,
                                             projection, m_pencilMode)) {
        m_activeGesture.emplace(std::move(*nodeGesture));
    } else if (auto phantomGesture = phantomDragGestureAt(handle, position)) {
        m_activeGesture.emplace(std::move(*phantomGesture));
    } else {
        SweepGesture sweep;
        sweep.lane = handle;
        sweep.mode =
            modifiers & Qt::ShiftModifier ? SweepGesture::Mode::Ramp : SweepGesture::Mode::Drag;
        sweep.anchor = mapped;
        sweep.current = mapped;
        sweep.previousRawTick = projection.rawTickAt(position.x());
        sweep.previousValue = mapped.value;
        sweep.pressPosition = position;
        sweep.slop.origin = position;
        if (sweep.mode == SweepGesture::Mode::Ramp)
            sweep.slop.markExceeded(position);
        m_activeGesture.emplace(std::move(sweep));
    }
    syncPreviewValueLabel();
    requestGestureBeginQuickUpdate(false);
    return true;
}

bool AutomationCanvas::pointerPress(const songview::TimelinePointerInput &input)
{
    m_hoverState.clearHover();
    requestHoverQuickUpdate();
    m_deletedNodeClick.clear();
    if (!m_page.document())
        return false;
    const QPointF position = contentPosition(input.position);
    if (input.button == Qt::MiddleButton) {
        m_pan.active = true;
        m_pan.pos = position;
        m_pan.startHScroll = m_page.liveState().horizontalScroll;
        m_pan.startVScroll = m_page.verticalScroll();
        m_inputHost->setCursor(QCursor(Qt::ClosedHandCursor));
        m_inputHost->requestFocus(Qt::MouseFocusReason);
        setGestureActive(true);
        return true;
    }
    const AutomationProjection proj = projection();
    const PointerLaneHit pointer = pointerLaneAt(position.toPoint());
    const bool inTempoHeader = pointer.tempoHeader;
    const LaneHandle pointerLane = pointer.lane;
    const auto *pointerSlot = resolveSlot(pointerLane);
    const bool inTempo = pointerSlot && pointerSlot->isTempo();
    if (input.button == Qt::LeftButton || input.button == Qt::RightButton) {
        if (m_laneSelection.active()) {
            const NodeLaneSlot *selectionSlot = pointerSlot;
            if (position.x() < m_geometry.plotOrigin)
                selectionSlot = nullptr;
            clearTimeSelectionIfOutsidePress(position, proj, pointerLane, selectionSlot);
        }
    }
    if (inTempoHeader) {
        if (input.button == Qt::LeftButton) {
            m_tempoLane.toggleExpanded();
            updateTempoLayout();
        } else if (input.button == Qt::RightButton) {
            m_band.press(position.toPoint(), m_page.snapTick(proj.rawTickAt(position.x()),
                                                             input.modifiers & Qt::AltModifier));
            m_band.pressLane(pointerLane);
            setGestureActive(true);
            requestGestureBeginQuickUpdate(true);
        } else {
            return false;
        }
        m_inputHost->requestFocus(Qt::MouseFocusReason);
        return true;
    }
    const int boundary =
        !inTempo && input.button == Qt::LeftButton ? ccRowBoundaryAt(position.toPoint().y()) : -1;
    if (boundary >= 0) {
        m_resize.row = boundary;
        m_resize.startHeight = ccLaneHeight(m_rowData.rows()[std::size_t(boundary)]);
        m_resize.startY = position.toPoint().y();
        m_inputHost->requestFocus(Qt::MouseFocusReason);
        setGestureActive(true);
        return true;
    }
    const QRect addRect(layout::space(layout::Space::Zero), addLaneStripTop(),
                        m_page.automationViewportSize().width(), m_geometry.addLaneStripHeight);
    if (!inTempo && (input.button == Qt::LeftButton || input.button == Qt::RightButton) &&
        addRect.contains(position.toPoint())) {
        showAddLaneMenu(input.globalPosition.toPoint());
        return true;
    }
    const auto *laneSlot = resolveSlot(pointerLane);
    if (!laneSlot)
        return false;
    const NodeLane *lane = laneSlot->lane;
    const QRect body = laneSlot->body;
    m_inputHost->requestFocus(Qt::MouseFocusReason);
    if (position.x() < m_geometry.plotOrigin) {
        if (input.button == Qt::RightButton)
            showLaneMenuFor(pointerLane, input.globalPosition.toPoint());
        return input.button == Qt::RightButton;
    }
    if (input.button == Qt::RightButton) {
        m_band.press(position.toPoint(), m_page.snapTick(proj.rawTickAt(position.x()),
                                                         input.modifiers & Qt::AltModifier));
        m_band.pressLane(pointerLane);
        NodePoint point;
        if (nodePointHit(pointerLane, position, proj, &point))
            highlightHoveredPoint(pointerLane, position, point);
        setGestureActive(true);
        requestGestureBeginQuickUpdate(true);
        return true;
    }
    if (input.button != Qt::LeftButton)
        return false;
    if (m_pencilMode)
        return beginPencilPress(position, input.modifiers, pointerLane, *lane, body, proj);
    return beginDragOrSweep(position, input.modifiers, pointerLane, proj);
}

bool AutomationCanvas::pointerMove(const songview::TimelinePointerInput &input)
{
    const QPointF position = contentPosition(input.position);
    if (m_pan.active) {
        if (!(input.buttons & Qt::MiddleButton)) {
            m_pan.active = false;
            m_inputHost->clearCursor();
            setGestureActive(false);
            return true;
        }
        const QPointF delta = position - m_pan.pos;
        m_page.requestHorizontalScroll(m_pan.startHScroll - delta.x());
        m_page.setVerticalScroll(m_pan.startVScroll - qRound(delta.y()));
        return true;
    }
    const AutomationProjection proj = projection();
    if (m_resize.row >= 0 && m_resize.row < int(m_rowData.rows().size())) {
        const int height =
            std::clamp(m_resize.startHeight + position.toPoint().y() - m_resize.startY,
                       m_geometry.rowMinimumHeight, m_geometry.rowMaximumHeight);
        if (height != ccLaneHeight(m_rowData.rows()[std::size_t(m_resize.row)])) {
            m_page.m_viewState.laneHeights[m_rowData.rows()[std::size_t(m_resize.row)].id] = height;
            m_page.publishViewState();
            contentGeometryChanged();
        }
        return true;
    }
    if (m_band.pending) {
        if (m_band.move(position.toPoint(), m_page.snapTick(proj.rawTickAt(position.x()),
                                                            input.modifiers & Qt::AltModifier))) {
            m_hoverState.hover.highlightLocked = false;
            m_hoverState.clearHover();
        }
        if (m_band.active) {
            const int lastY = std::max(layout::space(layout::Space::Zero),
                                       addLaneStripTop() - layout::singlePixel());
            const int y =
                std::clamp(position.toPoint().y(), layout::space(layout::Space::Zero), lastY);
            const LaneHandle candidate = pointerLaneAt(QPoint(position.toPoint().x(), y)).lane;
            const auto *startSlot = resolveSlot(m_band.laneRange().first);
            const auto *candidateSlot = resolveSlot(candidate);
            const bool compatible =
                startSlot && candidateSlot && startSlot->id.kind == candidateSlot->id.kind;
            m_band.extendTo(candidate, compatible);
            requestGestureMoveQuickUpdate();
        }
        return true;
    }
    if (!m_activeGesture) {
        const PointerLaneHit pointer = pointerLaneAt(position.toPoint());
        if (pointer.tempoHeader) {
            const bool hoverWasActive = m_hoverState.hover.lane.valid();
            m_hoverState.clearHover();
            if (hoverWasActive && !m_hoverState.hover.lane.valid())
                requestHoverQuickUpdate();
            m_inputHost->clearCursor();
            return true;
        }
        const auto *pointerSlot = resolveSlot(pointer.lane);
        const bool inTempo = pointerSlot && pointerSlot->isTempo();
        if (!inTempo && ccRowBoundaryAt(position.toPoint().y()) >= 0) {
            const bool hoverWasActive = m_hoverState.hover.lane.valid();
            m_hoverState.clearHover();
            if (hoverWasActive && !m_hoverState.hover.lane.valid())
                requestHoverQuickUpdate();
            m_inputHost->setCursor(QCursor(Qt::SplitVCursor));
            return true;
        }
        const qreal x = position.x();
        const int y = position.toPoint().y();
        const LaneHandle handle =
            x >= m_geometry.plotOrigin - m_geometry.pointHitRadius ? pointer.lane : LaneHandle{};
        const auto *slot = resolveSlot(handle);
        const LaneHandle previousHoverLane = m_hoverState.hover.lane;
        const QPointF previousHoverPosition = m_hoverState.hover.pos;
        if (slot) {
            m_hoverState.updateHover(hoverTarget(), m_geometry, *slot->lane, slot->body, handle,
                                     proj, x, y, m_pencilMode);
        } else {
            m_hoverState.clearHover();
        }
        const bool hoverPublicationChanged = !(previousHoverLane == m_hoverState.hover.lane) ||
                                             previousHoverPosition != m_hoverState.hover.pos;
        if (hoverPublicationChanged)
            requestHoverQuickUpdate();
        if (m_hoverState.hover.originPhantom)
            m_inputHost->clearCursor();
        else if (m_pencilMode && isEditablePencilHit(position))
            m_inputHost->setCursor(pencilCursor());
        else
            m_inputHost->clearCursor();
        return true;
    }
    updateActiveGesture(position, input.modifiers, true);
    requestGestureMoveQuickUpdate();
    return true;
}

bool AutomationCanvas::pointerRelease(const songview::TimelinePointerInput &input)
{
    const QPointF position = contentPosition(input.position);
    if (input.button == Qt::MiddleButton && m_pan.active) {
        m_pan.active = false;
        m_inputHost->clearCursor();
        setGestureActive(false);
        return true;
    }
    if (input.button == Qt::RightButton && m_band.pending) {
        const LaneHandle pointerLane = pointerLaneAt(position.toPoint()).lane;
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
            auto &model = m_page.m_owner.selectionModel();
            if (model.timeSelection().active()) {
                model.clearTimeSelection();
                requestSelectionQuickUpdate();
            }
        } else {
            m_hoverState.hover.highlightLocked = false;
            m_hoverState.clearHover();
            if (!showPointMenuNear(contextLane, position.toPoint(),
                                   input.globalPosition.toPoint())) {
                const bool inPlot = position.x() >= m_geometry.plotOrigin;
                const auto *contextSlot = resolveSlot(contextLane);
                const bool selected =
                    contextSlot && inPlot &&
                    m_laneSelection.hitTest(contextSlot->id, position.x(), projection(),
                                            m_inputHost->devicePixelRatio());
                if (selected)
                    showTimeSelectionMenuFor(contextLane, input.globalPosition.toPoint());
                else if (contextLane.valid())
                    showLaneMenuFor(contextLane, input.globalPosition.toPoint());
            }
        }
        if (!m_hoverState.hover.highlightLocked)
            refreshHoverAt(position);
        setGestureActive(false);
        requestGestureEndQuickUpdate();
        return true;
    }
    if (input.button == Qt::LeftButton && m_resize.row >= 0) {
        m_resize.row = -1;
        setGestureActive(false);
        return true;
    }
    if (input.button != Qt::LeftButton || !m_activeGesture)
        return false;
    updateActiveGesture(position, input.modifiers, false);
    finishActiveGesture(input.modifiers & Qt::AltModifier);
    m_activeGesture.reset();
    m_hoverState.previewValueLabel = {};
    refreshHoverAt(position);
    setGestureActive(false);
    updateAxisLockCursor(AxisLock::None);
    requestGestureEndQuickUpdate();
    return true;
}

bool AutomationCanvas::pointerDoubleClick(const songview::TimelinePointerInput &input)
{
    if (!m_page.document())
        return false;
    const QPointF position = contentPosition(input.position);
    const PointerLaneHit pointer = pointerLaneAt(position.toPoint());
    const auto *slot = resolveSlot(pointer.lane);
    const bool inTempo = slot && slot->isTempo();
    if (pointer.tempoHeader) {
        m_hoverState.clearHover();
        requestHoverQuickUpdate();
        if (input.button != Qt::LeftButton)
            return false;
        m_tempoLane.toggleExpanded();
        updateTempoLayout();
        return true;
    }
    if (input.button != Qt::LeftButton || (!inTempo && position.x() < m_geometry.plotOrigin))
        return false;
    const auto *laneSlot = resolveSlot(pointer.lane);
    if (!laneSlot || m_deletedNodeClick.consume())
        return false;
    const NodeLane *lane = laneSlot->lane;
    NodePoint hit;
    if (nodePointHit(pointer.lane, position, &hit))
        return true;
    if (m_pencilMode) {
        m_activeGesture.reset();
        m_hoverState.previewValueLabel = {};
        refreshHoverAt(position);
        setGestureActive(false);
        requestGestureEndQuickUpdate();
        return true;
    }
    m_activeGesture.reset();
    m_hoverState.previewValueLabel = {};
    setGestureActive(false);
    const AutomationProjection proj = projection();
    const uint64_t tick =
        m_page.snapTick(proj.rawTickAt(position.x()), input.modifiers & Qt::AltModifier);
    int value = mappedForLane(pointer.lane, position, false, false, proj).value;
    const bool accepted = lane->promptValue(&m_page.m_owner, value, &value);
    if (m_inputHost)
        m_inputHost->requestFocus(Qt::PopupFocusReason);
    if (!accepted)
        return true;
    NodeLane *target = laneSlot->lane;
    if (!target)
        return true;
    const std::vector<NodePoint> existing = target->points();
    for (const NodePoint &point : existing) {
        if (point.tick == tick && point.value == value)
            return true;
    }
    target->replaceSpan(tick, tick, {{tick, value}});
    m_page.requestRefresh();
    return true;
}

bool AutomationCanvas::keyPress(const songview::TimelineKeyInput &input)
{
    if (input.key == Qt::Key_Escape) {
        if (m_band.pending || m_activeGesture) {
            cancelInteraction();
        } else {
            auto &model = m_page.m_owner.selectionModel();
            if (model.timeSelection().active()) {
                model.clearTimeSelection();
                requestSelectionQuickUpdate();
            }
            m_hoverState.clearHover();
            requestHoverQuickUpdate();
        }
        return true;
    }
    if (input.key == Qt::Key_Delete || input.key == Qt::Key_Backspace) {
        auto selected = collectSelectedNodeDrags();
        if (!selected.points.empty()) {
            commitNodePointDeletes(std::nullopt, selected.points);
            m_hoverState.clearHover();
            requestHoverQuickUpdate();
            m_page.requestRefresh();
            return true;
        }
        if (m_pencilMode && m_hoverState.hover.lane.valid()) {
            NodePoint point;
            if (nodePointHit(m_hoverState.hover.lane, m_hoverState.hover.pos, &point)) {
                if (const auto *slot = resolveSlot(m_hoverState.hover.lane); slot && slot->lane) {
                    NodeLane *lane = slot->lane;
                    const NodeDrag drag{m_hoverState.hover.lane, point, point, lane->minimumValue(),
                                        lane->maximumValue()};
                    commitNodePointDeletes(m_page.document()->revision(), {drag});
                    m_hoverState.clearHover();
                    requestHoverQuickUpdate();
                    m_page.requestRefresh();
                }
            }
            return true;
        }
    }
    return false;
}

void AutomationCanvas::pointerLeave()
{
    const bool hoverWasActive = m_hoverState.hover.lane.valid();
    m_hoverState.clearHover();
    if (m_inputHost)
        m_inputHost->clearCursor();
    if (hoverWasActive && !m_hoverState.hover.lane.valid())
        requestHoverQuickUpdate();
}

void AutomationCanvas::inputCancelled(songview::TimelineInputCancelReason reason)
{
    if (reason == songview::TimelineInputCancelReason::FocusLost)
        return;
    cancelInteraction();
    m_hoverState.clearHover();
    m_hoverState.previewValueLabel = {};
    m_inputHost->clearCursor();
    requestGestureEndQuickUpdate();
}
