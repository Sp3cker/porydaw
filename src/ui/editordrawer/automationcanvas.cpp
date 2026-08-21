#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpaint.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/paint.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <variant>

#include <QCursor>
#include <QEvent>
#include <QIcon>
#include <QInputDialog>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QScrollArea>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
#include "ui/typography.h"

void AutomationCanvas::refreshGeometry()
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
    layoutLaneStack(m_voiceLane.engineTrack());
    updateGeometry();
    update();
}

void AutomationCanvas::contentGeometryChanged()
{
    refreshGeometry();
    syncHoverValueLabel();
    syncPreviewValueLabel();
}

QFont AutomationCanvas::captionLabelFont() const
{
    QFont caption = typography::caption(font());
    caption.setStyleName(QStringLiteral("Regular"));
    caption.setWeight(QFont::Normal);
    return caption;
}

AutomationCanvas::AutomationCanvas(AutomationPage *page, QScrollArea *scroll)
    : songview::TimelineSurface(nullptr)
    , m_geometry(AutomationGeometry::resolve())
    , m_page(page)
    , m_scroll(scroll)
    , m_rowData(page)
    , m_tempoLane(page)
    , m_voiceLane(page)
{
    setObjectName(QStringLiteral("automationCanvas"));
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    setMinimumHeight(m_tempoLane.totalHeight(m_geometry) + m_geometry.rowDefaultHeight);
}
AutomationProjection AutomationCanvas::projection() const
{
    return AutomationProjection(m_geometry, m_rowData.rows(), m_page, contentTopInset());
}

void AutomationCanvas::invalidateContent()
{
    m_rowData.syncTimeSelection();
    syncHoverValueLabel();
    songview::TimelineSurface::invalidateContent();
}
bool AutomationCanvas::bandPreviewContains(int rowIndex, uint64_t tick) const noexcept
{
    if (!m_band.active)
        return false;
    const uint64_t first = std::min(m_band.startTick, m_band.endTick);
    const uint64_t last = std::max(m_band.startTick, m_band.endTick);
    if (first >= last || tick < first || tick >= last)
        return false;
    return bandPreviewContainsRow(rowIndex);
}
bool AutomationCanvas::bandPreviewContainsRow(int rowIndex) const noexcept
{
    if (!m_band.active)
        return false;
    const int firstRow = std::min(m_bandRightRow, m_bandEndRow);
    const int lastRow = std::max(m_bandRightRow, m_bandEndRow);
    return rowIndex >= firstRow && rowIndex <= lastRow;
}
void AutomationCanvas::setPencilMode(bool enabled)
{
    if (!m_activeGesture)
        m_hoverState.clearHover(*this);
    m_pencilMode = enabled;
    syncHoverValueLabel();
    syncPreviewValueLabel();
    const QCursor cursor = enabled ? pencilCursor() : QCursor(Qt::ArrowCursor);
    setCursor(cursor);
    if (m_scroll && m_scroll->viewport())
        m_scroll->viewport()->setCursor(cursor);
    if (m_page)
        m_page->announce(enabled ? tr("Pencil mode on") : tr("Pencil mode off"));
}

bool AutomationCanvas::isPanning() const noexcept
{
    return m_pan.active;
}

const QCursor &AutomationCanvas::pencilCursor()
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

bool AutomationCanvas::event(QEvent *event)
{
    if (event->type() == QEvent::FontChange) {
        m_hoverState.valueLabelFontValid = false;
        m_hoverState.hoverValueLabel = {};
        m_hoverState.previewValueLabel = {};
        refreshGeometry();
        syncHoverValueLabel();
        syncPreviewValueLabel();
    }
    if (event->type() == QEvent::Hide || event->type() == QEvent::WindowDeactivate ||
        event->type() == QEvent::UngrabMouse)
        cancelInteraction();
    return songview::TimelineSurface::event(event);
}
void AutomationCanvas::rebuildRows()
{
    cancelInteraction();
    m_hoverState.invalidateCaches();
    m_hoverState.hoverValueLabel = {};
    m_hoverState.previewValueLabel = {};
    int voiceTrack = -1;
    bool showVoice = false;
    if (m_page && m_page->ready() && m_page->timeline()) {
        voiceTrack = m_page->m_owner.selectionModel().primaryTrack();
        if (voiceTrack >= 0) {
            showVoice = m_page->document() != nullptr;
            if (!showVoice) {
                for (const auto &change : m_page->model().voices) {
                    if (change.track == voiceTrack) {
                        showVoice = true;
                        break;
                    }
                }
            }
        }
    }
    m_rowData.rebuildRows();
    layoutLaneStack(showVoice ? voiceTrack : -1);
    invalidateContent();
}

void AutomationCanvas::updateTempoLayout()
{
    refreshGeometry();
}

void AutomationCanvas::layoutLaneStack(int voiceTrack)
{
    cancelNodeGestures();
    m_tempoLane.updateLayout(width(), m_geometry);
    const int shared = m_page && m_page->m_viewState.laneHeight > 0 ? m_page->m_viewState.laneHeight
                                                                    : m_geometry.rowDefaultHeight;
    const int voiceHeight = voiceTrack >= 0 ? std::clamp(shared, m_geometry.rowMinimumHeight,
                                                         m_geometry.rowMaximumHeight)
                                            : 0;
    m_voiceLane.rebuild(voiceTrack, width(), m_tempoLane.totalHeight(m_geometry), voiceHeight);
    rebuildNodeStack();
    setMinimumHeight(m_rowData.minimumHeight(m_geometry, contentTopInset()));
}

void AutomationCanvas::rebuildNodeStack()
{
    m_hoverState.hover.highlightLocked = false;
    m_hoverState.invalidateCaches();
    m_hoverState.clearHover(*this);
    m_nodeStack.clear();
    m_ccAdapters.clear();
    m_nodeStack.push_back({&m_tempoLane, m_tempoLane.bodyRect()});
    if (!m_page || !m_page->document())
        return;
    const auto &rows = m_rowData.rows();
    m_ccAdapters.reserve(rows.size());
    const auto &selection = m_page->m_owner.selectionModel();
    const uint32_t mask = m_page->usedTrackMask();
    for (const auto &row : rows)
        m_ccAdapters.emplace_back(*m_page->document(), selection, mask, int(row.id.track),
                                  row.id.controller);
    const AutomationProjection proj = projection();
    for (int i = 0; i < int(rows.size()); ++i) {
        const QRect body(layout::space(layout::Space::Zero), proj.rowTop(i), width(),
                         proj.rowHeight(rows[std::size_t(i)]));
        m_nodeStack.push_back({&m_ccAdapters[std::size_t(i)], body});
    }
}

LaneHandle AutomationCanvas::laneAt(int y) const noexcept
{
    for (int i = 0; i < int(m_nodeStack.size()); ++i) {
        const QRect &body = m_nodeStack[std::size_t(i)].body;
        if (y >= body.top() && y < body.top() + body.height())
            return LaneHandle{i};
    }
    return {};
}

bool AutomationCanvas::resolveLane(LaneHandle handle, const NodeLane **lane,
                                   QRect *body) const noexcept
{
    if (!handle.valid() || handle.index >= int(m_nodeStack.size()))
        return false;
    const NodeLaneSlot &slot = m_nodeStack[std::size_t(handle.index)];
    if (!slot.lane)
        return false;
    if (lane)
        *lane = slot.lane;
    if (body)
        *body = slot.body;
    return true;
}

void AutomationCanvas::syncHoverValueLabel()
{
    const NodeLane *lane = nullptr;
    QRect body;
    const bool resolved = resolveLane(m_hoverState.hover.lane, &lane, &body);
    m_hoverState.updateHoverValueLabel(*this, m_page, m_geometry, resolved ? lane : nullptr, body,
                                       projection(), m_pencilMode);
}

void AutomationCanvas::syncPreviewValueLabel()
{
    const NodeLane *lane = nullptr;
    QRect body;
    LaneHandle handle;
    qreal x = 0;
    int value = 0;
    if (m_activeGesture && m_page && m_page->ready()) {
        const auto rowIndex =
            std::visit([](const auto &gesture) { return gesture.row; }, *m_activeGesture);
        if (rowIndex >= 0 && rowIndex < int(m_rowData.rows().size())) {
            handle = LaneHandle{rowIndex + 1};
            if (resolveLane(handle, &lane, &body)) {
                if (const auto *gesture = std::get_if<NodeDragGesture>(&*m_activeGesture)) {
                    if (gesture->grabbedPoint < gesture->points.size()) {
                        const auto &point = gesture->points[gesture->grabbedPoint];
                        x = m_page->displayX(point.current.tick, m_geometry.plotOrigin,
                                             devicePixelRatioF());
                        value = point.current.value;
                    } else {
                        lane = nullptr;
                    }
                } else if (const auto *gesture = std::get_if<SweepGesture>(&*m_activeGesture)) {
                    x = m_page->displayX(gesture->current.tick, m_geometry.plotOrigin,
                                         devicePixelRatioF());
                    value = gesture->current.value;
                } else if (const auto *gesture = std::get_if<PencilGesture>(&*m_activeGesture)) {
                    const auto &sample = gesture->stroke.lastSample();
                    x = sample.logicalX;
                    value = int(std::lround(sample.continuousValue));
                }
            }
        }
    }
    m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, lane, body, handle, x, value);
}

void AutomationCanvas::highlightHoveredPoint(LaneHandle handle, const QPointF &position,
                                             const ValuePoint &point)
{
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body))
        return;
    m_hoverState.setContextPointHighlight(*this, m_page, m_geometry, *lane, body, handle,
                                          projection(), position, point, m_pencilMode);
}

int AutomationCanvas::ccRowIndexAt(int y) const noexcept
{
    const LaneHandle handle = laneAt(y);
    if (!handle.valid() || handle.index == 0)
        return -1;
    return handle.index - 1;
}

void AutomationCanvas::cancelInteraction()
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
    m_voiceLane.cancel();
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

void AutomationCanvas::cancelNodeGestures()
{
    const bool gestureActive = m_band.pending || m_activeGesture.has_value();
    m_activeGesture.reset();
    m_activeNodeIdentities.clear();
    m_band.clear();
    m_bandRightRow = -1;
    m_bandEndRow = -1;
    m_hoverState.previewValueLabel = {};
    if (gestureActive)
        setGestureActive(false);
}

bool AutomationCanvas::promptPointValue(const AutomationRow &row, uint8_t controller,
                                        int currentValue, int *storedValue)
{
    int value = currentValue;
    int minimum = CoreTimeDefaults::laneValueMinimum(controller);
    int maximum = CoreTimeDefaults::laneValueMaximum(controller);
    QString label = tr("Value:");
    if (controller == automation::kBendController) {
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

bool AutomationCanvas::showPointMenuNear(const AutomationRow &row, int rowIndex,
                                         const QPoint &position, const QPoint &globalPosition)
{
    if (!m_page || !m_page->document())
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
            const int candidateRowIndex = ccRowIndexAt(localPosition.y());
            if (candidateRowIndex < 0 || candidateRowIndex >= int(m_rowData.rows().size()))
                return false;
            const auto &candidateRow = m_rowData.rows()[candidateRowIndex];
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
            highlightHoveredPoint(LaneHandle{candidateRowIndex + 1}, localPosition,
                                  {candidatePoint.tick, candidatePoint.value});
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

void AutomationCanvas::setGestureActive(bool active)
{
    if (m_page) {
        if (active)
            m_page->automationGestureStarted();
        m_page->setFollowScrollPaused(active);
    }
}

void AutomationCanvas::updateAxisLockCursor(AxisLock lock)
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
ValuePoint AutomationCanvas::mappedForRow(int row, QPointF pos, bool fine, bool snapValue,
                                          const AutomationProjection &proj) const
{
    const uint64_t tick = m_page->snapTick(proj.rawTickAt(pos.x()), fine);
    ValuePoint out;
    updateValuePoint(proj, row, m_rowData.rows()[row], out, qRound(pos.y()), tick, snapValue,
                     m_geometry.neutralSnapRadius);
    return out;
}

void AutomationCanvas::showTimeSelectionMenu(const QPoint &globalPosition)
{
    const auto &selection = m_rowData.timeSelection();
    if (selection.active()) {
        DrawerPageTimeSelectionMenuRequest request;
        request.startTick = selection.startTick;
        request.endTick = selection.endTick;
        request.globalPosition = globalPosition;
        request.lanes = selection.lanes;
        m_page->showTimeSelectionMenu(request);
        return;
    }
    QMenu menu;
    QAction *clear = menu.addAction(tr("Clear time selection"));
    if (menu.exec(globalPosition) == clear && m_rowData.clearTimeSelection())
        invalidateContent();
}

void AutomationCanvas::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    const AutomationProjection proj = projection();
    const bool multipleSelectedNodes = m_rowData.selectionHasMultipleNodes();
    const QFont titleFont = typography::bold(typography::caption(font()));
    const QFont captionFont = captionLabelFont();
    m_tempoLane.paint(painter, m_geometry, m_labelGutter, titleFont, captionFont);
    m_voiceLane.paint(painter, *this, m_geometry, m_labelGutter, titleFont, captionFont);
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
    const NodeLane *hoveredLane = nullptr;
    QRect hoveredBody;
    if (resolveLane(m_hoverState.hover.lane, &hoveredLane, &hoveredBody)) {
        nodelane::paintHover(painter, *hoveredLane, hoveredBody, m_geometry, proj, m_hoverState,
                             m_pencilMode);
        const QRect plot = nodelane::plotRect(hoveredBody, m_geometry);
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        automation::paint::paintEditCursor(painter, plot,
                                           proj.displayX(m_page->liveState().editCursorTick,
                                                         painter.device()->devicePixelRatioF()));
        painter.restore();
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
        return automation::paint::TickRange::orderedNonEmpty(selection.startTick,
                                                             selection.endTick);
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
            if (!selection.coversLane(lane.first, lane.second))
                continue;
            const QRect bounds(m_geometry.plotOrigin, proj.rowTop(rowIndex),
                               std::max(0, width() - m_geometry.plotOrigin),
                               proj.rowHeight(rows[rowIndex]));
            automation::paint::paintSelectionReticle(painter, *selectedRange, proj, bounds, dpr);
        }
    }
}
