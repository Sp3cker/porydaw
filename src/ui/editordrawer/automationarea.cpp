#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationhover.h"
#include "ui/editordrawer/automationpaint.h"
#include "ui/editordrawer/automationrows.h"

#include <algorithm>
#include <cstring>
#include <limits>

#include <QApplication>
#include <QCursor>
#include <QEvent>
#include <QFontMetrics>
#include <QInputDialog>
#include <QKeyEvent>
#include <QMenu>
#include <QMessageBox>
#include <QMouseEvent>
#include <QPainter>
#include <QPixmap>
#include <QRegion>
#include <QScrollArea>
#include <QScrollBar>
#include <QWheelEvent>

#include "core/songdocument.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/linearramp.h"
#include "ui/layout.h"
#include "ui/m4asemantics.h"
#include "ui/selectionreticle.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
#include "ui/typography.h"

namespace {

template <class... Ts>
struct Visitor : Ts... {
    using Ts::operator()...;
};
template <class... Ts>
Visitor(Ts...) -> Visitor<Ts...>;

EditorAutomationRowId laneRow(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

QString laneLabel(uint8_t controller)
{
    if (controller == automation::kBendController)
        return QStringLiteral("Pitch bend (BEND)");
    const auto info = m4aClassifyCc(controller);
    return QStringLiteral("%1 (%2)").arg(QLatin1String(info.display), QLatin1String(info.name));
}

template <class T>
std::vector<AutomationLaneEdit::Point> toLaneEditPoints(const std::vector<T> &points)
{
    std::vector<AutomationLaneEdit::Point> result;
    result.reserve(points.size());
    for (const auto &point : points)
        result.push_back({point.tick, point.value});
    return result;
}

const QCursor &pencilCursor()
{
    static const QCursor cursor(QPixmap(QStringLiteral(":/cursors/pencil.png")), 0, 15);
    return cursor;
}
} // namespace

void AutomationArea::refreshGeometry()
{
    m_geometry = AutomationGeometry::resolve();
    const int leftScrollbarGutter =
        m_scroll && m_scroll->layoutDirection() == Qt::RightToLeft && m_page
            ? m_page->scrollGutter()
            : 0;
    m_geometry.plotOrigin =
        std::max(layout::space(layout::Space::Zero), m_geometry.plotOrigin - leftScrollbarGutter);
    const int gutterMargin = layout::space(layout::Space::One);
    m_labelGutter = QRect(
        gutterMargin, layout::space(layout::Space::Zero),
        std::max(layout::space(layout::Space::Zero), m_geometry.plotOrigin - 2 * gutterMargin),
        layout::space(layout::Space::Zero));
    m_rowData.applyHeight(*this, m_geometry);
    updateGeometry();
    update();
}

void AutomationArea::contentGeometryChanged()
{
    refreshGeometry();
    m_hoverState.updateHoverValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                       m_pencilMode);
    m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                         m_activeGesture);
}

QFont AutomationArea::captionLabelFont() const
{
    QFont caption = typography::caption(font());
    caption.setStyleName(QStringLiteral("Regular"));
    caption.setWeight(QFont::Normal);
    return caption;
}

AutomationArea::AutomationArea(AutomationPage *page, QScrollArea *scroll)
    : songview::TimelineSurface(nullptr)
    , m_geometry(AutomationGeometry::resolve())
    , m_page(page)
    , m_scroll(scroll)
    , m_rowData(page)
{
    setObjectName(QStringLiteral("automationArea"));
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    setMinimumHeight(m_geometry.rowDefaultHeight);
}

AutomationProjection AutomationArea::projection() const
{
    return AutomationProjection(m_geometry, m_rowData.rows(), m_page);
}

void AutomationArea::invalidateContent()
{
    m_rowData.syncTimeSelection();
    m_hoverState.updateHoverValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                       m_pencilMode);
    songview::TimelineSurface::invalidateContent();
}
bool AutomationArea::bandPreviewContains(int rowIndex, uint64_t tick) const noexcept
{
    if (!m_band.active)
        return false;
    const uint64_t first = std::min(m_band.startTick, m_band.endTick);
    const uint64_t last = std::max(m_band.startTick, m_band.endTick);
    if (first >= last || tick < first || tick >= last)
        return false;
    return bandPreviewContainsRow(rowIndex);
}
bool AutomationArea::bandPreviewContainsRow(int rowIndex) const noexcept
{
    if (!m_band.active)
        return false;
    const int firstRow = std::min(m_band.rightRow, m_band.endRow);
    const int lastRow = std::max(m_band.rightRow, m_band.endRow);
    return rowIndex >= firstRow && rowIndex <= lastRow;
}
void AutomationArea::setPencilMode(bool enabled)
{
    if (!m_activeGesture)
        m_hoverState.clearHover(*this);
    m_pencilMode = enabled;
    m_hoverState.updateHoverValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                       m_pencilMode);
    m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                         m_activeGesture);
    const QCursor cursor = enabled ? pencilCursor() : QCursor(Qt::ArrowCursor);
    setCursor(cursor);
    if (m_scroll && m_scroll->viewport())
        m_scroll->viewport()->setCursor(cursor);
    if (m_page)
        m_page->announce(enabled ? tr("Pencil mode on") : tr("Pencil mode off"));
}

bool AutomationArea::isPanning() const noexcept
{
    return m_pan.active;
}

bool AutomationArea::event(QEvent *event)
{
    if (event->type() == QEvent::FontChange) {
        m_hoverState.valueLabelFontValid = false;
        m_hoverState.hoverValueLabel = {};
        m_hoverState.previewValueLabel = {};
        refreshGeometry();
        m_hoverState.updateHoverValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                           m_pencilMode);
        m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, m_rowData, projection(),
                                             m_activeGesture);
    }
    if (event->type() == QEvent::Hide || event->type() == QEvent::WindowDeactivate ||
        event->type() == QEvent::UngrabMouse)
        cancelInteraction();
    return songview::TimelineSurface::event(event);
}
void AutomationArea::rebuildRows()
{
    cancelInteraction();
    m_hoverState.hoverText.clear();
    m_hoverState.hoverTextRow = -1;
    m_hoverState.hoverValueLabel = {};
    m_hoverState.previewValueLabel = {};
    m_rowData.rebuildRows();
    m_rowData.applyHeight(*this, m_geometry);
    invalidateContent();
}

void AutomationArea::cancelInteraction()
{
    const bool wasActive =
        m_pan.active || m_resize.row >= 0 || m_band.rightPending || m_activeGesture.has_value();
    m_pan.active = false;
    m_resize.row = -1;
    m_band.rightPending = false;
    m_band.active = false;
    m_band.rightRow = -1;
    m_band.endRow = -1;
    m_activeGesture.reset();
    m_hoverState.previewValueLabel = {};
    m_band.endTick = 0;
    m_band.rightStart = {};
    m_hoverState.hover.highlightLocked = false;
    m_hoverState.clearHover(*this);
    updateAxisLockCursor(AxisLock::None);
    if (m_pencilMode)
        setCursor(pencilCursor());
    if (mouseGrabber() == this)
        releaseMouse();
    if (wasActive)
        setGestureActive(false);
    invalidateContent();
}

bool AutomationArea::promptPointValue(const AutomationRow &row, uint8_t controller,
                                      int currentValue, int *storedValue)
{
    int value = currentValue;
    int minimum = 0;
    int maximum = 127;
    QString label = tr("Value:");
    if (row.id.kind == EditorAutomationRowKind::Tempo) {
        minimum = 1;
        maximum = 999;
        label = tr("BPM:");
    } else if (controller == automation::kBendController) {
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
    const int entered = QInputDialog::getInt(this, m_rowData.titleFor(row), label, value, minimum,
                                             maximum, 1, &accepted);
    if (!accepted)
        return false;
    *storedValue = (controller == 10 || controller == 24) ? entered + 64 : entered;
    return true;
}

bool AutomationArea::showPointMenuNear(const AutomationRow &row, int rowIndex,
                                       const QPoint &position, const QPoint &globalPosition)
{
    if (!m_page || !m_page->document() || row.id.kind == EditorAutomationRowKind::Voice)
        return false;
    int track = -1;
    uint8_t controller = 0;
    if (!m_rowData.rowTarget(row, &track, &controller))
        return false;
    DocLanePoint point;
    if (!pencilPointHit(row, rowIndex, position, &point))
        return false;
    int targetRowIndex = rowIndex;
    std::pair<int, uint8_t> targetLane{track, controller};
    DocLanePoint targetPoint = point;
    ui::ContextMenu menu(this);
    QAction *setValue = menu.addAction(tr("Set Value"));
    QAction *deletePoint = menu.addAction(tr("Delete"));
    menu.setOutsideRightClickHandler(
        [this, &menu, &targetRowIndex, &targetLane, &targetPoint](QPointF globalPos) {
            const QPoint localPosition = mapFromGlobal(globalPos.toPoint());
            const int candidateRowIndex = projection().rowIndexAt(localPosition.y());
            if (candidateRowIndex < 0 || candidateRowIndex >= int(m_rowData.rows().size()))
                return false;
            const auto &candidateRow = m_rowData.rows()[candidateRowIndex];
            if (candidateRow.id.kind == EditorAutomationRowKind::Voice)
                return false;
            int candidateTrack = -1;
            uint8_t candidateController = 0;
            if (!m_rowData.rowTarget(candidateRow, &candidateTrack, &candidateController))
                return false;
            DocLanePoint candidatePoint;
            if (!pencilPointHit(candidateRow, candidateRowIndex, localPosition, &candidatePoint))
                return false;
            targetRowIndex = candidateRowIndex;
            targetLane = {candidateTrack, candidateController};
            targetPoint = candidatePoint;
            m_hoverState.setContextPointHighlight(*this, m_page, m_geometry, m_rowData,
                                                  projection(), candidateRowIndex, localPosition,
                                                  candidatePoint, m_pencilMode);
            menu.popup(globalPos.toPoint());
            return true;
        });
    QAction *chosen = menu.exec(globalPosition);
    if (targetRowIndex < 0 || targetRowIndex >= int(m_rowData.rows().size()) || !m_page ||
        !m_page->document())
        return true;
    const auto &targetRow = m_rowData.rows()[targetRowIndex];
    if (chosen == setValue) {
        int stored = targetPoint.value;
        if (promptPointValue(targetRow, targetLane.second, targetPoint.value, &stored) &&
            targetPoint.value != stored) {
            m_page->document()->moveLanePoints(
                {{targetLane.first, targetLane.second, targetPoint, targetPoint.tick, stored}});
            m_page->requestRefresh();
        }
    } else if (chosen == deletePoint) {
        m_page->document()->deleteLanePoints(targetLane.first, targetLane.second, {targetPoint});
        m_page->requestRefresh();
    }
    return true;
}

void AutomationArea::setGestureActive(bool active)
{
    if (m_page) {
        if (active)
            m_page->automationGestureStarted();
        m_page->setFollowScrollPaused(active);
    }
}

void AutomationArea::updateAxisLockCursor(AxisLock lock)
{
    if (lock == AxisLock::Time)
        setCursor(Qt::SizeHorCursor);
    else if (lock == AxisLock::Value)
        setCursor(Qt::SizeVerCursor);
    else if (m_pencilMode)
        setCursor(pencilCursor());
    else
        setCursor(Qt::ArrowCursor);
}
ValuePoint AutomationArea::mappedForRow(int row, QPointF pos, bool fine, bool snapValue,
                                        const AutomationProjection &proj) const
{
    const uint64_t tick = m_page->snapTick(proj.rawTickAt(pos.x()), fine);
    ValuePoint out;
    updateValuePoint(proj, row, m_rowData.rows()[row], out, qRound(pos.y()), tick, snapValue,
                     m_geometry.neutralSnapRadius);
    return out;
}

void AutomationArea::showTimeSelectionMenu(const QPoint &globalPosition)
{
    if (m_rowData.timeSelection().active()) {
        DrawerPageTimeSelectionMenuRequest request;
        request.startTick = m_rowData.timeSelection().startTick;
        request.endTick = m_rowData.timeSelection().endTick;
        request.globalPosition = globalPosition;
        request.lanes = m_rowData.timeSelection().lanes;
        m_page->showTimeSelectionMenu(request);
        return;
    }
    QMenu menu;
    QAction *clear = menu.addAction(tr("Clear time selection"));
    if (menu.exec(globalPosition) == clear && m_rowData.clearTimeSelection())
        invalidateContent();
}

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
                m_page->publishViewState();
                m_rowData.applyHeight(*this, m_geometry);
                invalidateContent();
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
    m_hoverState.hover.nodeDeleted = false;
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
    const int boundary =
        event->button() == Qt::LeftButton ? proj.rowBoundaryAt(event->pos().y()) : -1;
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
    const int rowIndex = proj.rowIndexAt(event->pos().y());
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
        m_band.rightPending = true;
        m_band.active = false;
        m_band.rightStart = event->pos();
        m_band.rightRow = rowIndex;
        m_band.endRow = rowIndex;
        m_band.startTick = m_page->snapTick(proj.rawTickAt(event->position().x()),
                                            event->modifiers() & Qt::AltModifier);
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
            m_activeGesture.emplace(std::move(*nodeGesture));
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
            m_page->document()->ticksPerClock(), toLaneEditPoints(existing), sample, mapped.cell);
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
        m_activeGesture.emplace(std::move(*nodeGesture));
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
    const AutomationProjection proj = projection();
    if (m_resize.row >= 0 && m_resize.row < int(m_rowData.rows().size())) {
        const int height = std::clamp(m_resize.startHeight + event->pos().y() - m_resize.startY,
                                      m_geometry.rowMinimumHeight, m_geometry.rowMaximumHeight);
        if (height != proj.rowHeight(m_rowData.rows()[m_resize.row])) {
            m_page->m_viewState.laneHeights[m_rowData.rows()[m_resize.row].id] = height;
            m_page->publishViewState();
            m_rowData.applyHeight(*this, m_geometry);
            invalidateContent();
        }
        return;
    }
    if (m_band.rightPending) {
        if (!m_band.active && (event->pos() - m_band.rightStart).manhattanLength() >=
                                  QApplication::startDragDistance()) {
            m_band.active = true;
            m_hoverState.hover.highlightLocked = false;
            m_hoverState.clearHover(*this);
        }
        if (m_band.active) {
            m_band.endTick = m_page->snapTick(proj.rawTickAt(event->position().x()),
                                              event->modifiers() & Qt::AltModifier);
            const int lastY =
                std::max(layout::space(layout::Space::Zero),
                         proj.rowTop(int(m_rowData.rows().size())) - layout::singlePixel());
            m_band.endRow = proj.rowIndexAt(
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
    if (event->button() == Qt::RightButton && m_band.rightPending) {
        const int rowIndex = m_band.rightRow;
        m_band.rightPending = false;
        if (m_band.active) {
            m_band.active = false;
            const uint64_t first = std::min(m_band.startTick, m_band.endTick);
            const uint64_t last = std::max(m_band.startTick, m_band.endTick);
            if (first < last && rowIndex >= 0 && m_band.endRow >= 0) {
                auto &timeSelection = m_rowData.timeSelection();
                timeSelection = {first, last, std::min(rowIndex, m_band.endRow),
                                 std::max(rowIndex, m_band.endRow)};
                std::vector<std::pair<int, uint8_t>> lanes;
                for (int row = timeSelection.firstRow;
                     row <= timeSelection.lastRow && row < int(m_rowData.rows().size()); ++row)
                    lanes.push_back(m_rowData.rowIdentity(m_rowData.rows()[row]));
                timeSelection.lanes = lanes;
                m_page->publishTimeSelection(first, last, lanes);
                m_page->announce(tr("Automation range [%1, %2)").arg(first).arg(last));
            } else {
                m_rowData.clearTimeSelection();
            }
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
        m_band.rightRow = -1;
        m_band.endRow = -1;
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

void AutomationArea::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (!m_page || !m_page->document() || event->button() != Qt::LeftButton ||
        event->position().x() < m_geometry.plotOrigin)
        return;
    const AutomationProjection proj = projection();
    const int rowIndex = proj.rowIndexAt(event->pos().y());
    if (rowIndex < 0 || m_rowData.rows()[rowIndex].id.kind == EditorAutomationRowKind::Voice)
        return;
    int track = -1;
    uint8_t controller = 0;
    if (!m_rowData.rowTarget(m_rowData.rows()[rowIndex], &track, &controller))
        return;
    if (m_hoverState.hover.nodeDeleted) {
        m_hoverState.hover.nodeDeleted = false;
        return;
    }
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
    if (m_rowData.rows()[rowIndex].id.kind == EditorAutomationRowKind::Tempo) {
        minimum = 1;
        maximum = 999;
        label = tr("BPM:");
    } else if (controller == automation::kBendController) {
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
        if (m_band.rightPending || m_band.active || m_activeGesture) {
            cancelInteraction();
        } else {
            if (m_rowData.clearTimeSelection())
                invalidateContent();
            m_hoverState.clearHover(*this);
        }
        event->accept();
        return;
    }
    if ((event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) &&
        m_rowData.timeSelection().active() && m_page && m_page->document()) {
        const auto selected = m_rowData.collectSelectedNodeDrags();
        if (!selected.empty()) {
            SongDocument::RangeEdit edit;
            edit.removePoints.reserve(selected.size());
            for (const auto &point : selected)
                edit.removePoints.push_back(point.documentPoint);
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
    m_hoverState.clearHover(*this);
}

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
        Visitor{
            [](std::monostate) { return false; },
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
                if (move.dTick != 0 && move.selectionDrag && m_rowData.timeSelection().active()) {
                    SongView::TimeSelection moved = m_page->timeSelection();
                    moved.startTick =
                        uint64_t(std::max<int64_t>(0, int64_t(moved.startTick) + move.dTick));
                    moved.endTick =
                        uint64_t(std::max<int64_t>(0, int64_t(moved.endTick) + move.dTick));
                    if (moved.startTick < moved.endTick)
                        m_page->publishTimeSelection(moved.startTick, moved.endTick, moved.lanes);
                }
                return true;
            }},
        commit);
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::showAddLaneMenu(const QPoint &globalPosition)
{
    if (!m_page)
        return;
    const int track = m_page->selectedTrack();
    if (track < 0)
        return;
    static constexpr uint8_t candidates[] = {1, 7, 10, 20, 21, automation::kBendController};
    QMenu menu;
    std::vector<EditorAutomationRowId> hidden;
    for (const uint8_t controller : candidates) {
        const auto row = laneRow(track, controller);
        if (m_page->m_viewState.isLaneHidden(row) || projection().laneFor({row}) ||
            m_page->m_viewState.emptyLanes.find(row) != m_page->m_viewState.emptyLanes.cend())
            continue;
        auto *action = menu.addAction(laneLabel(controller));
        action->setData(int(controller));
    }
    for (const auto &row : m_page->m_viewState.hiddenLanes())
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == uint8_t(track))
            hidden.push_back(row);
    if (menu.isEmpty())
        menu.addAction(tr("All parameters already have lanes"))->setEnabled(false);
    if (!hidden.empty()) {
        menu.addSeparator();
        menu.addAction(tr("Hidden lanes"))->setEnabled(false);
        for (const auto &row : hidden) {
            auto *action = menu.addAction(tr("Show: %1 (hidden)").arg(laneLabel(row.controller)));
            action->setData(256 + int(row.controller));
        }
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen || !chosen->data().isValid())
        return;
    const int value = chosen->data().toInt();
    if (value >= 256) {
        const auto row = laneRow(track, uint8_t(value - 256));
        if (m_page->m_viewState.unhideLane(row)) {
            m_page->publishViewState();
            rebuildRows();
            m_page->announce(tr("Showed the %1 lane").arg(laneLabel(row.controller)));
        }
    } else {
        m_page->addEmptyLane(track, uint8_t(value));
        m_page->announce(tr("Added %1 lane").arg(laneLabel(uint8_t(value))));
    }
}

void AutomationArea::showLaneMenu(const AutomationRow &row, const QPoint &globalPosition)
{
    const bool empty = m_rowData.pointsFor(row, projection()).empty();
    QMenu menu;
    QAction *copy = menu.addAction(tr("Copy lane"));
    copy->setEnabled(!empty);
    QAction *paste = menu.addAction(tr("Paste lane (replace)"));
    paste->setEnabled(!m_clipboard.empty());
    menu.addSeparator();
    QAction *clear = menu.addAction(tr("Clear events"));
    clear->setEnabled(!empty);
    QAction *remove = menu.addAction(empty ? tr("Remove empty lane") : tr("Delete lane"));
    QAction *hide = menu.addAction(tr("Hide lane"));
    std::vector<std::pair<QAction *, uint8_t>> ranges;
    if (automation::rangeZoomable(row.id.controller)) {
        auto *rangeMenu = menu.addMenu(tr("Value range"));
        const auto range = m_page->m_viewState.laneRanges.find(row.id);
        const uint8_t current = range == m_page->m_viewState.laneRanges.cend()
                                    ? automation::defaultRange(row.id.controller)
                                    : range->second;
        for (const uint8_t value :
             {uint8_t(0), uint8_t(16), uint8_t(32), uint8_t(64), uint8_t(127)}) {
            const QString label = value == 0     ? tr("Auto (fit to data)")
                                  : value == 127 ? tr("0–127 (full)")
                                                 : QStringLiteral("0–%1").arg(value);
            auto *action = rangeMenu->addAction(label);
            action->setCheckable(true);
            action->setChecked(value == current);
            ranges.emplace_back(action, value);
        }
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen)
        return;
    for (const auto &[action, range] : ranges) {
        if (chosen == action) {
            m_page->setLaneRange(row.id, range);
            return;
        }
    }
    const int track = int(row.id.track);
    const uint8_t controller = row.id.controller;
    auto *document = m_page->document();
    const auto points = document->lanePoints(track, controller);
    bool changed = false;
    if (chosen == copy) {
        m_clipboard.clear();
        for (const auto &point : points)
            m_clipboard.push_back({point.tick, point.value});
        m_page->announce(tr("Copied the %1 lane (%n point(s))", nullptr, int(points.size()))
                             .arg(m_rowData.titleFor(row)));
    } else if (chosen == paste) {
        std::vector<SongDocument::LanePointValue> replacementPoints;
        replacementPoints.reserve(m_clipboard.size());
        const int minimum = controller == automation::kBendController ? -8192 : 0;
        const int maximum = controller == automation::kBendController ? 8191 : 127;
        for (const auto &point : m_clipboard)
            replacementPoints.push_back({point.tick, std::clamp(point.value, minimum, maximum)});
        auto completion =
            AutomationLaneEdit({track, controller, document->revision()}, toLaneEditPoints(points))
                .replacePointRange(0, std::numeric_limits<uint64_t>::max(),
                                   std::move(replacementPoints));
        if (!completion.unchanged) {
            SongDocument::RangeEdit edit;
            edit.removePoints = points;
            SongDocument::RangeEdit::LaneWrite replacement{track, controller,
                                                           std::move(completion.points)};
            edit.addPoints.push_back(std::move(replacement));
            document->applyRangeEdit(tr("paste lane"), edit);
            changed = true;
            m_page->announce(tr("Replaced the %1 lane").arg(m_rowData.titleFor(row)));
        }
    } else if (chosen == clear) {
        if (!points.empty()) {
            m_page->addEmptyLane(track, controller);
            document->deleteLanePoints(track, controller, points);
            changed = true;
        }
    } else if (chosen == remove) {
        if (!points.empty() && QMessageBox::question(this, tr("Delete lane"),
                                                     tr("Delete the %1 lane and its %2 events?")
                                                         .arg(m_rowData.titleFor(row))
                                                         .arg(points.size())) != QMessageBox::Yes)
            return;
        m_page->removeEmptyLane(track, controller);
        if (!points.empty()) {
            document->deleteLanePoints(track, controller, points);
            changed = true;
        }
    } else if (chosen == hide) {
        if (m_page->m_viewState.hideLane(row.id)) {
            m_page->publishViewState();
            rebuildRows();
            m_page->announce(tr("Hid the %1 lane").arg(m_rowData.titleFor(row)));
        }
    }
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::showVoiceMenu(const AutomationRow &row, const QPoint &globalPosition)
{
    Q_UNUSED(row);
    if (!m_page || !m_page->document())
        return;
    const int track = m_page->selectedTrack();
    if (track < 0)
        return;
    const qreal x = mapFromGlobal(globalPosition).x();
    const qreal dpr = devicePixelRatioF();
    const auto points = m_page->document()->lanePoints(track, DOC_CC_VOICE);
    const DocLanePoint *marker = nullptr;
    qreal distance = m_geometry.deleteTimeRadius + 1;
    for (const auto &point : points) {
        const qreal candidate =
            std::abs(m_page->displayX(point.tick, m_geometry.plotOrigin, dpr) - x);
        if (candidate <= m_geometry.deleteTimeRadius && (!marker || candidate <= distance)) {
            marker = &point;
            distance = candidate;
        }
    }
    const uint64_t tick =
        marker ? marker->tick : m_page->snapTick(projection().rawTickAt(x), false);
    int current = marker ? marker->value : 0;
    if (!marker)
        current = m_page->voiceContext(tick).voiceSlot;
    if (!marker) {
        for (const auto &point : points) {
            if (point.tick > tick)
                break;
            current = point.value;
        }
    }
    int selectedVoice = 0;
    if (!m_page->pickVoice(marker ? tr("Change voice") : tr("Insert voice change"),
                           std::max(0, current), &selectedVoice))
        return;
    DocLanePoint existing;
    bool changed = false;
    if (m_page->document()->findLanePoint(track, DOC_CC_VOICE, tick, &existing)) {
        if (existing.value != selectedVoice) {
            m_page->document()->moveLanePoints(
                {{track, DOC_CC_VOICE, existing, tick, selectedVoice}});
            changed = true;
        }
    } else {
        m_page->document()->addLanePoint(track, DOC_CC_VOICE, tick, selectedVoice);
        changed = true;
    }
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    int y = layout::space(layout::Space::Zero);
    const AutomationProjection proj = projection();
    const bool multipleSelectedNodes = m_rowData.selectionHasMultipleNodes();
    const QFont titleFont = typography::bold(typography::caption(font()));
    const QFont captionFont = captionLabelFont();
    const auto textLayout =
        layout::twoLineText(titleFont, titleFont, captionFont, layout::Space::Zero);
    const auto &rows = m_rowData.rows();
    for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
        const AutomationRow &row = rows[rowIndex];
        const int height = proj.rowHeight(row);
        const QRect bounds(layout::space(layout::Space::Zero), y, width(), height);
        const QRect plot(m_geometry.plotOrigin, bounds.top(),
                         std::max(0, width() - m_geometry.plotOrigin), bounds.height());
        const QRect textBounds(m_labelGutter.x(), bounds.top(), m_labelGutter.width(),
                               bounds.height());
        const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
        const auto &points = m_rowData.pointsFor(row, proj);
        const QColor color =
            row.id.kind == EditorAutomationRowKind::Tempo
                ? themes::color(themes::Role::song_view_automation_tempo_curve)
                : themes::trackIdentityColor(row.id.track % themes::trackIdentityColorCount);
        const automation::paint::RowPaintParams ctx{
            proj, row, rowIndex, plot, points, color, nullptr, nullptr, multipleSelectedNodes};
        automation::paint::paintRow(painter, ctx, bounds, titleFont, captionFont, textBoxes.primary,
                                    textBoxes.secondary, *this, *m_page, m_geometry, m_rowData,
                                    m_hoverState, m_activeGesture, m_pencilMode);
        y += height;
    }
    if (m_page->document()) {
        const QRect add(layout::space(layout::Space::Zero), y, width(),
                        m_geometry.addLaneStripHeight);
        painter.setPen(themes::color(themes::Role::song_view_add_automation_lane_action));
        painter.drawText(
            add.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                         -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
            Qt::AlignLeft | Qt::AlignVCenter, tr("+ Add lane"));
    }
    uint64_t first = 0;
    uint64_t last = 0;
    if (m_band.active) {
        first = std::min(m_band.startTick, m_band.endTick);
        last = std::max(m_band.startTick, m_band.endTick);
        const int firstRow = std::min(m_band.rightRow, m_band.endRow);
        const int lastRow = std::max(m_band.rightRow, m_band.endRow);
        if (first < last && firstRow >= 0 && lastRow >= firstRow) {
            const qreal dpr = painter.device()->devicePixelRatioF();
            const qreal x0 = m_page->displayX(first, m_geometry.plotOrigin, dpr);
            const qreal x1 = m_page->displayX(last, m_geometry.plotOrigin, dpr);
            const int top = proj.rowTop(firstRow);
            const int bottom = proj.rowTop(lastRow + 1);
            songview::paintSelectionReticle(
                painter, QRectF(std::min(x0, x1), top, std::abs(x1 - x0), bottom - top));
        }
    } else if (m_rowData.timeSelection().active()) {
        first = m_rowData.timeSelection().startTick;
        last = m_rowData.timeSelection().endTick;
        if (first < last) {
            const qreal dpr = painter.device()->devicePixelRatioF();
            const qreal x0 = m_page->displayX(first, m_geometry.plotOrigin, dpr);
            const qreal x1 = m_page->displayX(last, m_geometry.plotOrigin, dpr);
            for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
                if (std::find(m_rowData.timeSelection().lanes.cbegin(),
                              m_rowData.timeSelection().lanes.cend(),
                              m_rowData.rowIdentity(rows[rowIndex])) ==
                    m_rowData.timeSelection().lanes.cend())
                    continue;
                const int top = proj.rowTop(rowIndex);
                songview::paintSelectionReticle(painter,
                                                QRectF(std::min(x0, x1), top, std::abs(x1 - x0),
                                                       proj.rowHeight(rows[rowIndex])));
            }
        }
    }
}
