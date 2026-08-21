#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/cclanes.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <variant>

#include <QCursor>
#include <QEvent>
#include <QIcon>
#include <QInputDialog>
#include <QMenu>
#include <QPixmap>
#include <QScrollArea>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"
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
    return AutomationProjection(m_geometry, m_page);
}

void AutomationCanvas::invalidateContent()
{
    m_rowData.syncTimeSelection();
    syncHoverValueLabel();
    songview::TimelineSurface::invalidateContent();
}
bool AutomationCanvas::bandPreviewContains(LaneHandle handle, uint64_t tick) const noexcept
{
    if (!m_band.active)
        return false;
    const uint64_t first = std::min(m_band.startTick, m_band.endTick);
    const uint64_t last = std::max(m_band.startTick, m_band.endTick);
    if (first >= last || tick < first || tick >= last)
        return false;
    return bandPreviewContainsLane(handle);
}
bool AutomationCanvas::bandPreviewContainsLane(LaneHandle handle) const noexcept
{
    if (!m_band.active || !handle.valid() || !m_bandStart.valid() || !m_bandEnd.valid())
        return false;
    const int first = std::min(m_bandStart.index, m_bandEnd.index);
    const int last = std::max(m_bandStart.index, m_bandEnd.index);
    return handle.index >= first && handle.index <= last;
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
    cancelNodeGestures();
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
    int top = contentTopInset();
    for (int i = 0; i < int(rows.size()); ++i) {
        const int height = ccLaneHeight(rows[std::size_t(i)]);
        const QRect body(layout::space(layout::Space::Zero), top, width(), height);
        m_nodeStack.push_back({&m_ccAdapters[std::size_t(i)], body});
        top += height;
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

QRect AutomationCanvas::laneBody(LaneHandle handle) const
{
    QRect body;
    if (!resolveLane(handle, nullptr, &body))
        return {};
    return body;
}

NodeLane *AutomationCanvas::mutableLane(LaneHandle handle) noexcept
{
    if (!handle.valid() || handle.index >= int(m_nodeStack.size()))
        return nullptr;
    return m_nodeStack[std::size_t(handle.index)].lane;
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
        handle = std::visit([](const auto &gesture) { return gesture.lane; }, *m_activeGesture);
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
    m_hoverState.updatePreviewValueLabel(*this, m_page, m_geometry, lane, body, handle, x, value);
}

void AutomationCanvas::highlightHoveredPoint(LaneHandle handle, const QPointF &position,
                                             const NodePoint &point)
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

int AutomationCanvas::ccLaneHeight(const AutomationRow &row) const
{
    if (!m_page)
        return m_geometry.rowDefaultHeight;
    return std::clamp(m_page->laneHeightFor(row.id), m_geometry.rowMinimumHeight,
                      m_geometry.rowMaximumHeight);
}

int AutomationCanvas::ccRowBoundaryAt(int y) const
{
    for (int i = 1; i < int(m_nodeStack.size()); ++i) {
        const QRect &body = m_nodeStack[std::size_t(i)].body;
        const int bottom = body.top() + body.height();
        if (std::abs(y - bottom) <= layout::singlePixel())
            return i - 1;
    }
    return -1;
}

int AutomationCanvas::addLaneStripTop() const
{
    if (m_nodeStack.size() > 1)
        return m_nodeStack.back().body.top() + m_nodeStack.back().body.height();
    return contentTopInset();
}

int AutomationCanvas::snapNeutralFor(LaneHandle handle) const
{
    if (!handle.valid() || handle.index <= 0 || handle.index - 1 >= int(m_rowData.rows().size()))
        return -1;
    const uint8_t controller = m_rowData.rows()[std::size_t(handle.index - 1)].id.controller;
    if (controller == CCLanes::bendController())
        return 0;
    if (controller == 10 || controller == 24)
        return 64;
    return -1;
}

void AutomationCanvas::cancelInteraction()
{
    const bool wasActive =
        m_pan.active || m_resize.row >= 0 || m_band.pending || m_activeGesture.has_value();
    m_pan.active = false;
    m_resize.row = -1;
    m_activeGesture.reset();
    m_band.clear();
    m_bandStart = {};
    m_bandEnd = {};
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
    m_band.clear();
    m_bandStart = {};
    m_bandEnd = {};
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
    if (controller == CCLanes::bendController()) {
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

bool AutomationCanvas::showPointMenuNear(LaneHandle handle, const QPoint &position,
                                         const QPoint &globalPosition)
{
    if (!m_page || !m_page->document())
        return false;
    NodePoint point;
    if (!nodePointHit(handle, position, &point))
        return false;
    LaneHandle target = handle;
    NodePoint targetPoint = point;
    ui::ContextMenu menu(this);
    QAction *setValue = menu.addAction(tr("Set Value"));
    QAction *deletePoint = menu.addAction(tr("Delete"));
    menu.setOutsideRightClickHandler([this, &menu, &target, &targetPoint](QPointF globalPos) {
        const QPoint localPosition = mapFromGlobal(globalPos.toPoint());
        const LaneHandle candidate = laneAt(localPosition.y());
        NodePoint candidatePoint;
        if (!nodePointHit(candidate, localPosition, &candidatePoint))
            return false;
        target = candidate;
        targetPoint = candidatePoint;
        highlightHoveredPoint(candidate, localPosition, candidatePoint);
        menu.popup(globalPos.toPoint());
        return true;
    });
    QAction *chosen = menu.exec(globalPosition);
    NodeLane *lane = mutableLane(target);
    if (!lane || !m_page || !m_page->document())
        return true;
    if (chosen == setValue) {
        int stored = targetPoint.value;
        bool accepted = false;
        if (target.index == 0)
            accepted = m_tempoLane.promptBpm(*this, stored, &stored);
        else if (target.index > 0 && target.index - 1 < int(m_rowData.rows().size())) {
            const auto &row = m_rowData.rows()[std::size_t(target.index - 1)];
            accepted = promptPointValue(row, row.id.controller, stored, &stored);
        }
        if (accepted && stored != targetPoint.value) {
            lane->movePoints({{targetPoint.tick, {targetPoint.tick, stored}}});
            m_page->requestRefresh();
        }
    } else if (chosen == deletePoint) {
        lane->deletePoints({targetPoint.tick});
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

NodePoint AutomationCanvas::mappedForLane(LaneHandle handle, QPointF pos, bool fine, bool snapValue,
                                          const AutomationProjection &proj) const
{
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body) || !lane)
        return {};
    const uint64_t tick = m_page->snapTick(proj.rawTickAt(pos.x()), fine);
    NodePoint out;
    updateValuePoint(proj, *lane, body, out, pos.y(), tick, snapValue, m_geometry.neutralSnapRadius,
                     snapNeutralFor(handle));
    return out;
}

void AutomationCanvas::publishBandSelection(uint64_t first, uint64_t last, LaneHandle start,
                                            LaneHandle end) const
{
    if (!m_page || first >= last || !start.valid() || !end.valid())
        return;
    const int firstIndex = std::min(start.index, end.index);
    const int lastIndex = std::max(start.index, end.index);
    std::vector<std::pair<int, uint8_t>> lanes;
    bool tempo = false;
    for (int index = firstIndex; index <= lastIndex && index < int(m_nodeStack.size()); ++index) {
        if (index == 0) {
            tempo = true;
            continue;
        }
        const int rowIndex = index - 1;
        if (rowIndex >= 0 && rowIndex < int(m_rowData.rows().size()))
            lanes.push_back(m_rowData.rowIdentity(m_rowData.rows()[std::size_t(rowIndex)]));
    }
    m_page->publishTimeSelection(first, last, lanes, tempo);
    if (tempo && lanes.empty())
        m_page->announce(tr("Tempo range [%1, %2)").arg(first).arg(last));
    else
        m_page->announce(tr("Automation range [%1, %2)").arg(first).arg(last));
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
