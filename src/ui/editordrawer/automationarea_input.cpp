#include "ui/editordrawer/automationarea.h"

#include <algorithm>
#include <cmath>

#include <QInputDialog>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QWheelEvent>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"

void AutomationArea::wheelEvent(QWheelEvent *event)
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
                m_rowData.applyHeight(*this, m_geometry, m_tempoLane.totalHeight(m_geometry));
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

void AutomationArea::mousePressEvent(QMouseEvent *event)
{
    m_hoverState.clearHover(*this);
    m_deletedNodeClick.clear();
    m_activeNodeIdentities.clear();
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
    if (m_tempoLane.mousePress(*this, event, m_geometry)) {
        setFocus();
        setGestureActive(m_tempoLane.interactionActive());
        invalidateContent();
        return;
    }
    if ((event->button() == Qt::LeftButton || event->button() == Qt::RightButton) &&
        m_tempoLane.hasTimeSelection())
        m_page->m_owner.selectionModel().clearTimeSelection();
    const AutomationProjection proj = projection();
    const int boundary =
        event->button() == Qt::LeftButton ? proj.rowBoundaryAt(event->pos().y()) : -1;
    const int rowIndex = proj.rowIndexAt(event->pos().y());
    if ((event->button() == Qt::LeftButton || event->button() == Qt::RightButton) &&
        m_rowData.timeSelection().active()) {
        const bool insideSelection = boundary < 0 && rowIndex >= 0 &&
                                     event->position().x() >= m_geometry.plotOrigin &&
                                     m_rowData.selectionContains(rowIndex, event->position().x(),
                                                                 m_geometry, devicePixelRatioF());
        if (!insideSelection && m_rowData.clearTimeSelection())
            invalidateContent();
    }
    if (boundary >= 0) {
        m_resize.row = boundary;
        m_resize.startHeight = proj.rowHeight(m_rowData.rows()[boundary]);
        m_resize.startY = event->pos().y();
        setGestureActive(true);
        return;
    }
    const QRect addRect(layout::space(layout::Space::Zero),
                        proj.rowTop(int(m_rowData.rows().size())), width(),
                        m_geometry.addLaneStripHeight);
    if ((event->button() == Qt::LeftButton || event->button() == Qt::RightButton) &&
        addRect.contains(event->pos())) {
        showAddLaneMenu(event->globalPosition().toPoint());
        return;
    }
    if (rowIndex < 0)
        return;
    setFocus();
    const auto &row = m_rowData.rows()[rowIndex];
    if (event->position().x() < m_geometry.plotOrigin) {
        if (event->button() == Qt::RightButton &&
            row.id.kind == EditorAutomationRowKind::ControlChange)
            showLaneMenu(row, event->globalPosition().toPoint());
        return;
    }
    if (event->button() == Qt::RightButton) {
        m_band.press(event->pos(), m_page->snapTick(proj.rawTickAt(event->position().x()),
                                                    event->modifiers() & Qt::AltModifier));
        m_bandRightRow = rowIndex;
        m_bandEndRow = rowIndex;
        DocLanePoint point;
        if (pencilPointHit(row, rowIndex, event->position(), proj, &point))
            m_hoverState.setContextPointHighlight(*this, m_page, m_geometry, m_rowData, proj,
                                                  rowIndex, event->position(), point, m_pencilMode);
        setGestureActive(true);
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        showVoiceMenu(row, event->globalPosition().toPoint());
        return;
    }
    int track = -1;
    uint8_t controller = 0;
    if (!m_rowData.rowTarget(row, &track, &controller))
        return;
    const bool fine = event->modifiers() & Qt::AltModifier;
    if (m_pencilMode) {
        if (auto nodeGesture = m_rowData.nodeDragGestureAt(
                rowIndex, event->position(), event->modifiers() & Qt::ShiftModifier, proj,
                m_pencilMode, m_geometry, devicePixelRatioF())) {
            m_activeNodeIdentities = std::move(nodeGesture->identities);
            m_activeGesture.emplace(std::move(nodeGesture->gesture));
            setGestureActive(true);
            m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, m_rowData, proj,
                                                 m_activeGesture);
            invalidateContent();
            return;
        }
        const AutomationProjection::PointerMapping mapped =
            proj.pointerMapping(rowIndex, event->position().x(), event->position().y());
        const auto *timeline = m_page->timeline();
        if (!timeline)
            return;
        const auto existing = m_page->document()->lanePoints(track, controller);
        const AutomationPencilGesture::Target target{track, controller,
                                                     m_page->document()->revision()};
        const AutomationPencilGesture::Sample sample{mapped.rawTick, event->position().x(),
                                                     mapped.point, double(mapped.point.value)};
        auto stroke = AutomationPencilGesture::start(
            target, proj.rowMinimum(row), proj.rowMaximum(row), timeline->lengthTicks,
            m_page->document()->ticksPerClock(), laneEditPoints(existing), sample, mapped.cell);
        if (!stroke)
            return;
        PencilGesture pencil{rowIndex, std::move(*stroke)};
        pencil.verticalSlop.origin = event->position();
        pencil.previousY = event->position().y();
        m_activeGesture.emplace(std::move(pencil));
        setGestureActive(true);
        m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, m_rowData, proj,
                                             m_activeGesture);
        invalidateContent();
        return;
    }
    const ValuePoint mapped = mappedForRow(rowIndex, event->position(), fine,
                                           event->modifiers() & Qt::ControlModifier, proj);
    setGestureActive(true);
    if (auto nodeGesture = m_rowData.nodeDragGestureAt(
            rowIndex, event->position(), event->modifiers() & Qt::ShiftModifier, proj, m_pencilMode,
            m_geometry, devicePixelRatioF())) {
        m_activeNodeIdentities = std::move(nodeGesture->identities);
        m_activeGesture.emplace(std::move(nodeGesture->gesture));
    } else {
        SweepGesture sweep;
        sweep.row = rowIndex;
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
    m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                         m_activeGesture);
    invalidateContent();
}

void AutomationArea::mouseMoveEvent(QMouseEvent *event)
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
    if (m_tempoLane.mouseMove(*this, event, m_geometry)) {
        if (m_tempoLane.interactionActive())
            setGestureActive(true);
        invalidateContent();
        return;
    }

    const AutomationProjection proj = projection();
    if (m_resize.row >= 0 && m_resize.row < int(m_rowData.rows().size())) {
        const int height = std::clamp(m_resize.startHeight + event->pos().y() - m_resize.startY,
                                      m_geometry.rowMinimumHeight, m_geometry.rowMaximumHeight);
        if (height != proj.rowHeight(m_rowData.rows()[m_resize.row])) {
            m_page->m_viewState.laneHeights[m_rowData.rows()[m_resize.row].id] = height;
            m_page->publishViewState();
            m_rowData.applyHeight(*this, m_geometry, m_tempoLane.totalHeight(m_geometry));
            invalidateContent();
        }
        return;
    }
    if (m_band.pending) {
        if (m_band.move(event->pos(), m_page->snapTick(proj.rawTickAt(event->position().x()),
                                                       event->modifiers() & Qt::AltModifier))) {
            m_hoverState.hover.highlightLocked = false;
            m_hoverState.clearHover(*this);
        }
        if (m_band.active) {
            const int lastY =
                std::max(layout::space(layout::Space::Zero),
                         proj.rowTop(int(m_rowData.rows().size())) - layout::singlePixel());
            m_bandEndRow = proj.rowIndexAt(
                std::clamp(event->pos().y(), layout::space(layout::Space::Zero), lastY));
            invalidateContent();
        }
        return;
    }
    if (!m_activeGesture) {
        if (proj.rowBoundaryAt(event->pos().y()) >= 0) {
            m_hoverState.clearHover(*this);
            setCursor(Qt::SplitVCursor);
            return;
        }
        m_hoverState.updateHover(*this, *m_page, m_geometry, m_rowData, proj, event->position().x(),
                                 event->pos().y(), m_pencilMode);
        if (m_pencilMode)
            setCursor(pencilCursor());
        else
            setCursor(Qt::ArrowCursor);
        return;
    }
    updateActiveGesture(event->position(), event->modifiers(), true);
    invalidateContent();
}
void AutomationArea::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_pan.active) {
        m_pan.active = false;
        unsetCursor();
        setGestureActive(false);
        event->accept();
        return;
    }
    if (m_tempoLane.mouseRelease(*this, event, m_geometry)) {
        setGestureActive(false);
        invalidateContent();
        return;
    }

    if (event->button() == Qt::RightButton && m_band.pending) {
        const int rowIndex = m_bandRightRow;
        const auto selection = m_band.release();
        if (selection && selection->first < selection->second && rowIndex >= 0 &&
            m_bandEndRow >= 0) {
            auto &timeSelection = m_rowData.timeSelection();
            timeSelection.range = {selection->first, selection->second};
            timeSelection.scope = {};
            timeSelection.firstRow = std::min(rowIndex, m_bandEndRow);
            timeSelection.lastRow = std::max(rowIndex, m_bandEndRow);
            timeSelection.scope.lanes.reserve(
                std::size_t(timeSelection.lastRow - timeSelection.firstRow + 1));
            for (int row = timeSelection.firstRow;
                 row <= timeSelection.lastRow && row < int(m_rowData.rows().size()); ++row)
                timeSelection.scope.lanes.push_back(m_rowData.rowIdentity(m_rowData.rows()[row]));
            m_page->publishTimeSelection(selection->first, selection->second,
                                         timeSelection.scope.lanes);
            m_page->announce(
                tr("Automation range [%1, %2)").arg(selection->first).arg(selection->second));
        } else if (selection) {
            m_rowData.clearTimeSelection();
        } else {
            const bool handled = rowIndex >= 0 && rowIndex < int(m_rowData.rows().size()) &&
                                 showPointMenuNear(m_rowData.rows()[rowIndex], rowIndex,
                                                   event->pos(), event->globalPosition().toPoint());
            m_hoverState.hover.highlightLocked = false;
            m_hoverState.clearHover(*this);
            if (!handled && m_rowData.selectionContains(rowIndex, event->position().x(), m_geometry,
                                                        devicePixelRatioF()))
                showTimeSelectionMenu(event->globalPosition().toPoint());
            else if (!handled && rowIndex >= 0 && rowIndex < int(m_rowData.rows().size()) &&
                     m_rowData.rows()[rowIndex].id.kind != EditorAutomationRowKind::Voice)
                m_rowData.clearTimeSelection();
        }
        m_bandRightRow = -1;
        m_bandEndRow = -1;
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
    m_activeNodeIdentities.clear();
    m_hoverState.previewValueLabel = {};
    setGestureActive(false);
    updateAxisLockCursor(AxisLock::None);
    invalidateContent();
}

void AutomationArea::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (!m_page || !m_page->document())
        return;
    if (m_tempoLane.mouseDoubleClick(*this, event, m_geometry)) {
        invalidateContent();
        return;
    }
    if (event->button() != Qt::LeftButton || event->position().x() < m_geometry.plotOrigin)
        return;
    const AutomationProjection proj = projection();
    const int rowIndex = proj.rowIndexAt(event->pos().y());
    if (rowIndex < 0 || m_rowData.rows()[rowIndex].id.kind == EditorAutomationRowKind::Voice)
        return;
    int track = -1;
    uint8_t controller = 0;
    if (!m_rowData.rowTarget(m_rowData.rows()[rowIndex], &track, &controller))
        return;
    if (m_deletedNodeClick.consume())
        return;
    // Node delete is a plain single click (see NodeDragGesture finish). A
    // double-click on empty lane still opens exact value entry; on a node it
    // is a no-op because the first click already removed it.
    DocLanePoint hit;
    if (pencilPointHit(m_rowData.rows()[rowIndex], rowIndex, event->position(), &hit))
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
    const uint64_t tick = m_page->snapTick(proj.rawTickAt(event->position().x()),
                                           event->modifiers() & Qt::AltModifier);
    DocLanePoint existing;
    const bool hasExisting = m_page->document()->findLanePoint(track, controller, tick, &existing);
    int value = hasExisting ? existing.value : proj.valueAtY(rowIndex, event->pos().y());
    int minimum = 0;
    int maximum = 127;
    QString label = tr("Value:");
    if (controller == automation::kBendController) {
        minimum = -8192;
        maximum = 8191;
        label = tr("Bend (0 = none):");
    } else if (controller == 10 || controller == 24) {
        minimum = -64;
        maximum = 63;
        value -= 64;
        label = tr("c_v value (0 = center):");
    }
    bool accepted = false;
    const int entered = QInputDialog::getInt(this, m_rowData.titleFor(m_rowData.rows()[rowIndex]),
                                             label, value, minimum, maximum, 1, &accepted);
    if (!accepted)
        return;
    const int stored = (controller == 10 || controller == 24) ? entered + 64 : entered;
    if (hasExisting && existing.value == stored)
        return;
    m_page->document()->writeLanePoints(track, controller, tick, tick, {{tick, stored}});
    m_page->requestRefresh();
}

void AutomationArea::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        if (m_tempoLane.interactionActive() || m_band.pending || m_activeGesture) {
            cancelInteraction();
        } else {
            if (m_tempoLane.hasTimeSelection())
                m_page->m_owner.selectionModel().clearTimeSelection();
            else if (m_rowData.clearTimeSelection())
                invalidateContent();
            m_hoverState.clearHover(*this);
        }
        event->accept();
        return;
    }
    if ((event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) &&
        m_tempoLane.deleteTimeSelection()) {
        event->accept();
        invalidateContent();
        return;
    }
    if ((event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) &&
        m_rowData.timeSelection().active() && m_page && m_page->document()) {
        const auto selected = m_rowData.collectSelectedNodeDrags(projection());
        if (!selected.identities.empty()) {
            SongDocument::RangeEdit edit;
            edit.removePoints.reserve(selected.identities.size());
            for (const LaneNodeIdentity &identity : selected.identities)
                edit.removePoints.push_back(identity.documentPoint);
            m_page->document()->applyRangeEdit(tr("delete selected automation points"), edit);
            m_hoverState.clearHover(*this);
            m_page->requestRefresh();
        }
        event->accept();
        return;
    }
    if (m_pencilMode && (event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) &&
        m_hoverState.hover.row >= 0 && m_hoverState.hover.row < int(m_rowData.rows().size())) {
        const auto &row = m_rowData.rows()[m_hoverState.hover.row];
        DocLanePoint point;
        int track = -1;
        uint8_t controller = 0;
        if (row.id.kind != EditorAutomationRowKind::Voice &&
            pencilPointHit(row, m_hoverState.hover.row, m_hoverState.hover.pos, &point) &&
            m_rowData.rowTarget(row, &track, &controller)) {
            m_page->document()->deleteLanePoints(track, controller, {point});
            m_hoverState.clearHover(*this);
            m_page->requestRefresh();
        }
        event->accept();
        return;
    }
    QWidget::keyPressEvent(event);
}

void AutomationArea::leaveEvent(QEvent *)
{
    m_tempoLane.clearHover();
    m_hoverState.clearHover(*this);
}
