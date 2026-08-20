#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationhover.h"
#include "ui/editordrawer/automationpaint.h"
#include "ui/editordrawer/automationrows.h"

#include <algorithm>
#include <optional>

#include <QCursor>
#include <QEvent>
#include <QIcon>
#include <QInputDialog>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QScrollArea>

#include "core/songdocument.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
#include "ui/typography.h"

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
    m_tempoLane.updateLayout(width(), m_geometry);
    m_rowData.applyHeight(*this, m_geometry, m_tempoLane.totalHeight(m_geometry));
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
    , m_tempoLane(page)
{
    setObjectName(QStringLiteral("automationArea"));
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    setMinimumHeight(m_tempoLane.totalHeight(m_geometry) + m_geometry.rowDefaultHeight);
}
AutomationProjection AutomationArea::projection() const
{
    return AutomationProjection(m_geometry, m_rowData.rows(), m_page,
                                m_tempoLane.totalHeight(m_geometry));
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
    const int firstRow = std::min(m_bandRightRow, m_bandEndRow);
    const int lastRow = std::max(m_bandRightRow, m_bandEndRow);
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

const QCursor &AutomationArea::pencilCursor()
{
    const qreal dpr = devicePixelRatioF();
    if (m_pencilCursorDpr != dpr) {
        constexpr int cursorExtent = 16;
        const QIcon icon(QStringLiteral(":/cursors/pencil.png"));
        const QPixmap pixmap = icon.pixmap(QSize(cursorExtent, cursorExtent), dpr);
        const qreal pixmapDpr = std::max<qreal>(1.0, pixmap.devicePixelRatio());
        const int hotspotY = std::max(0, qRound(pixmap.height() / pixmapDpr) - 1);
        m_pencilCursor = QCursor(pixmap, 0, hotspotY);
        m_pencilCursorDpr = dpr;
    }
    return m_pencilCursor;
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
    m_tempoLane.updateLayout(width(), m_geometry);
    m_rowData.applyHeight(*this, m_geometry, m_tempoLane.totalHeight(m_geometry));
    invalidateContent();
}

void AutomationArea::updateTempoLayout()
{
    refreshGeometry();
}

void AutomationArea::cancelInteraction()
{
    const bool wasActive =
        m_pan.active || m_resize.row >= 0 || m_band.pending || m_activeGesture.has_value();
    m_pan.active = false;
    m_resize.row = -1;
    m_activeGesture.reset();
    m_activeNodeIdentities.clear();
    m_band.clear();
    m_bandRightRow = -1;
    m_bandEndRow = -1;
    m_tempoLane.cancel();
    m_hoverState.previewValueLabel = {};
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
    const auto &selection = m_rowData.timeSelection();
    if (selection.active()) {
        DrawerPageTimeSelectionMenuRequest request;
        request.startTick = selection.range.startTick;
        request.endTick = selection.range.endTick;
        request.globalPosition = globalPosition;
        request.lanes = selection.scope.lanes;
        m_page->showTimeSelectionMenu(request);
        return;
    }
    QMenu menu;
    QAction *clear = menu.addAction(tr("Clear time selection"));
    if (menu.exec(globalPosition) == clear && m_rowData.clearTimeSelection())
        invalidateContent();
}

void AutomationArea::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    const AutomationProjection proj = projection();
    const bool multipleSelectedNodes = m_rowData.selectionHasMultipleNodes();
    const QFont titleFont = typography::bold(typography::caption(font()));
    const QFont captionFont = captionLabelFont();
    m_tempoLane.paint(painter, m_geometry, m_labelGutter, titleFont, captionFont);
    const auto textLayout =
        layout::twoLineText(titleFont, titleFont, captionFont, layout::Space::Zero);
    const auto &rows = m_rowData.rows();
    for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
        const AutomationRow &row = rows[rowIndex];
        const int height = proj.rowHeight(row);
        const QRect bounds(layout::space(layout::Space::Zero), proj.rowTop(rowIndex), width(),
                           height);
        const QRect plot(m_geometry.plotOrigin, bounds.top(),
                         std::max(0, width() - m_geometry.plotOrigin), bounds.height());
        const QRect textBounds(m_labelGutter.x(), bounds.top(), m_labelGutter.width(),
                               bounds.height());
        const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
        const auto &points = m_rowData.pointsFor(row, proj);
        const QColor color =
            themes::trackIdentityColor(row.id.track % themes::trackIdentityColorCount);
        const automation::paint::RowPaintParams ctx{
            proj, row, rowIndex, plot, points, color, nullptr, nullptr, multipleSelectedNodes};
        automation::paint::paintRow(painter, ctx, bounds, titleFont, captionFont, textBoxes.primary,
                                    textBoxes.secondary, *this, *m_page, m_geometry, m_rowData,
                                    m_hoverState, m_activeGesture, m_pencilMode);
    }
    if (m_page->document()) {
        const QRect add(layout::space(layout::Space::Zero), proj.rowTop(int(rows.size())), width(),
                        m_geometry.addLaneStripHeight);
        painter.setPen(themes::color(themes::Role::song_view_add_automation_lane_action));
        painter.drawText(
            add.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                         -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
            Qt::AlignLeft | Qt::AlignVCenter, tr("+ Add lane"));
    }
    const auto selectedRange = [&] {
        if (m_band.active)
            return automation::paint::TickRange::orderedNonEmpty(m_band.startTick, m_band.endTick);
        const auto &selection = m_rowData.timeSelection();
        if (!selection.active())
            return std::optional<automation::paint::TickRange>{};
        return automation::paint::TickRange::orderedNonEmpty(selection.range.startTick,
                                                             selection.range.endTick);
    }();
    if (m_band.active) {
        const int firstRow = std::min(m_bandRightRow, m_bandEndRow);
        const int lastRow = std::max(m_bandRightRow, m_bandEndRow);
        if (selectedRange && firstRow >= 0 && lastRow >= firstRow) {
            const int top = proj.rowTop(firstRow);
            const QRect bounds(m_geometry.plotOrigin, top,
                               std::max(0, width() - m_geometry.plotOrigin),
                               proj.rowTop(lastRow + 1) - top);
            automation::paint::paintSelectionReticle(painter, *selectedRange, proj, bounds,
                                                     painter.device()->devicePixelRatioF());
        }
    } else if (selectedRange) {
        const auto &selection = m_rowData.timeSelection();
        const qreal dpr = painter.device()->devicePixelRatioF();
        for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
            const auto lane = m_rowData.rowIdentity(rows[rowIndex]);
            if (!selection.scope.coversLane(lane.first, lane.second))
                continue;
            const QRect bounds(m_geometry.plotOrigin, proj.rowTop(rowIndex),
                               std::max(0, width() - m_geometry.plotOrigin),
                               proj.rowHeight(rows[rowIndex]));
            automation::paint::paintSelectionReticle(painter, *selectedRange, proj, bounds, dpr);
        }
    }
}
