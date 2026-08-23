#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/cclanes.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <variant>

#include <QCursor>
#include <QEvent>
#include <QIcon>
#include <QPixmap>
#include <QScrollArea>
#include <QScrollBar>

#include "core/songdocument.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/nodelane/batchcommit.h"
#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"

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
    // Lane layout is content: the surface cache must re-rasterize, a plain
    // update() would keep blitting the stale pre-layout pixels.
    invalidateContent();
    updateGeometry();
    update();
}

void AutomationCanvas::contentGeometryChanged()
{
    refreshGeometry();
    syncHoverValueLabel();
    syncPreviewValueLabel();
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
    rebuildFontCache();
    setMinimumHeight(m_tempoLane.totalHeight(m_geometry) + m_geometry.rowDefaultHeight);
    if (m_scroll && m_scroll->verticalScrollBar()) {
        const auto updatePinnedTempo = [this] {
            const QRegion dirty = syncPinnedTempoLayout();
            syncHoverValueLabel();
            songview::TimelineSurface::invalidateContent(dirty);
        };
        connect(m_scroll->verticalScrollBar(), &QScrollBar::valueChanged, this, updatePinnedTempo);
        connect(m_scroll->verticalScrollBar(), &QScrollBar::rangeChanged, this, updatePinnedTempo);
    }
}
AutomationProjection AutomationCanvas::projection() const
{
    return AutomationProjection(m_geometry, m_page);
}

NodeLaneHoverTarget AutomationCanvas::hoverTarget() const
{
    NodeLaneHoverTarget target;
    target.widgetBounds = rect();
    target.font = font();
    target.devicePixelRatio = devicePixelRatioF();
    target.documentRevision = m_page ? m_page->liveState().documentRevision : 0;
    target.ready = m_page && m_page->ready();
    return target;
}

void AutomationCanvas::invalidateContent()
{
    syncHoverValueLabel();
    songview::TimelineSurface::invalidateContent();
}
bool AutomationCanvas::bandPreviewContainsLane(LaneHandle handle) const noexcept
{
    return m_band.coversLane(handle);
}
void AutomationCanvas::setPencilMode(bool enabled)
{
    if (!m_activeGesture)
        invalidateContent(m_hoverState.clearHover());
    m_pencilMode = enabled;
    syncHoverValueLabel();
    syncPreviewValueLabel();
    updatePencilCursor();
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
        rebuildFontCache();
        m_hoverState.invalidateFontCache();
        m_voiceLane.invalidateFontCache();
        m_hoverState.hoverValueLabel = {};
        m_hoverState.previewValueLabel = {};
        invalidateContent();
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
    if (m_page)
        m_laneSelection.emplace(m_page->m_owner.selectionModel(), m_rowData.rows(),
                                m_page->usedTrackMask());
    layoutLaneStack(showVoice ? voiceTrack : -1);
    invalidateContent();
}

void AutomationCanvas::updateTempoLayout()
{
    refreshGeometry();
}
int AutomationCanvas::tempoTop() const
{
    return std::min(m_scroll->verticalScrollBar()->value() + m_scroll->viewport()->height(),
                    height()) -
           m_tempoLane.totalHeight(m_geometry);
}

QRegion AutomationCanvas::syncPinnedTempoLayout()
{
    QRegion dirty(pinnedTempoRect());
    m_tempoLane.updateLayout(width(), tempoTop(), m_geometry);
    for (NodeLaneSlot &slot : m_nodeStack) {
        if (slot.id.kind == EditorAutomationRowKind::Tempo) {
            slot.body = m_tempoLane.bodyRect();
            break;
        }
    }
    dirty += pinnedTempoRect();
    return dirty;
}

void AutomationCanvas::layoutLaneStack(int voiceTrack)
{
    cancelNodeGestures();
    m_voiceLane.rebuild(voiceTrack, width(), 0, m_geometry);
    const int scrollableHeight = m_rowData.minimumHeight(m_geometry, contentTopInset());
    setMinimumHeight(scrollableHeight + m_tempoLane.totalHeight(m_geometry));
    syncPinnedTempoLayout();
    rebuildNodeStack();
}

void AutomationCanvas::rebuildNodeStack()
{
    cancelNodeGestures();
    m_hoverState.hover.highlightLocked = false;
    m_hoverState.invalidateCaches();
    invalidateContent(m_hoverState.clearHover());
    m_nodeStack.clear();
    m_ccAdapters.clear();
    m_nodeStack.push_back(
        {{EditorAutomationRowKind::Tempo, 0, 0}, &m_tempoLane, m_tempoLane.bodyRect(), nullptr});
    if (!m_page || !m_page->document())
        return;
    const auto &rows = m_rowData.rows();
    auto &rowText = m_rowData.rowText();
    m_ccAdapters.reserve(rows.size());
    for (const auto &row : rows)
        m_ccAdapters.emplace_back(*m_page->document(), int(row.id.track), row.id.controller);
    int top = contentTopInset();
    for (int i = 0; i < int(rows.size()); ++i) {
        const int height = ccLaneHeight(rows[std::size_t(i)]);
        const QRect body(layout::space(layout::Space::Zero), top, width(), height);
        m_nodeStack.push_back({rows[std::size_t(i)].id, &m_ccAdapters[std::size_t(i)], body,
                               &rowText[std::size_t(i)]});
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
AutomationCanvas::PointerLaneHit
AutomationCanvas::pointerLaneAt(const QPoint &position) const noexcept
{
    LaneHandle tempoHandle;
    for (int index = 0; index < int(m_nodeStack.size()); ++index) {
        if (m_nodeStack[std::size_t(index)].id.kind == EditorAutomationRowKind::Tempo) {
            tempoHandle = LaneHandle{index};
            break;
        }
    }
    const bool tempoHeader = m_tempoLane.containsHeader(position);
    return {tempoHeader ? tempoHandle : laneAt(position.y()), tempoHeader};
}

const AutomationCanvas::NodeLaneSlot *
AutomationCanvas::resolveSlot(LaneHandle handle) const noexcept
{
    if (!handle.valid() || handle.index >= int(m_nodeStack.size()))
        return nullptr;
    const auto &slot = m_nodeStack[std::size_t(handle.index)];
    return slot.lane ? &slot : nullptr;
}

bool AutomationCanvas::resolveLane(LaneHandle handle, const NodeLane **lane,
                                   QRect *body) const noexcept
{
    const auto *slot = resolveSlot(handle);
    if (!slot)
        return false;
    if (lane)
        *lane = slot->lane;
    if (body)
        *body = slot->body;
    return true;
}

QRect AutomationCanvas::laneBody(LaneHandle handle) const
{
    QRect body;
    if (!resolveLane(handle, nullptr, &body))
        return {};
    return body;
}
QRect AutomationCanvas::pinnedTempoRect() const noexcept
{
    const QRect body = m_tempoLane.bodyRect();
    return body.isEmpty() ? m_tempoLane.headerRect() : body;
}

NodeLane *AutomationCanvas::mutableLane(LaneHandle handle) noexcept
{
    const auto *slot = resolveSlot(handle);
    return slot ? slot->lane : nullptr;
}

void AutomationCanvas::syncHoverValueLabel()
{
    const NodeLane *lane = nullptr;
    QRect body;
    const bool resolved = resolveLane(m_hoverState.hover.lane, &lane, &body);
    invalidateContent(m_hoverState.updateHoverValueLabel(
        hoverTarget(), m_geometry, resolved ? lane : nullptr, body, projection(), m_pencilMode));
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
    invalidateContent(m_hoverState.updatePreviewValueLabel(hoverTarget(), m_geometry, lane, body,
                                                           handle, x, value));
}

void AutomationCanvas::highlightHoveredPoint(LaneHandle handle, const QPointF &position,
                                             const NodePoint &point)
{
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body))
        return;
    invalidateContent(m_hoverState.setContextPointHighlight(hoverTarget(), m_geometry, *lane, body,
                                                            handle, projection(), position, point,
                                                            m_pencilMode));
}

int AutomationCanvas::ccRowIndexAt(int y) const noexcept
{
    const auto *slot = resolveSlot(laneAt(y));
    if (!slot)
        return -1;
    const auto &rows = m_rowData.rows();
    const auto found =
        std::find_if(rows.cbegin(), rows.cend(),
                     [id = slot->id](const AutomationRow &row) { return row.id == id; });
    return found == rows.cend() ? -1 : int(found - rows.cbegin());
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
    const auto &rows = m_rowData.rows();
    for (const NodeLaneSlot &slot : m_nodeStack) {
        const int bottom = slot.body.top() + slot.body.height();
        if (std::abs(y - bottom) > layout::singlePixel())
            continue;
        const auto found =
            std::find_if(rows.cbegin(), rows.cend(),
                         [&slot](const AutomationRow &row) { return row.id == slot.id; });
        if (found != rows.cend())
            return int(found - rows.cbegin());
    }
    return -1;
}

int AutomationCanvas::addLaneStripTop() const
{
    if (!m_nodeStack.empty() &&
        m_nodeStack.back().id.kind == EditorAutomationRowKind::ControlChange) {
        return m_nodeStack.back().body.top() + m_nodeStack.back().body.height();
    }
    return contentTopInset();
}

void AutomationCanvas::cancelInteraction()
{
    const bool wasActive =
        m_pan.active || m_resize.row >= 0 || m_band.pending || m_activeGesture.has_value();
    m_pan.active = false;
    m_resize.row = -1;
    m_activeGesture.reset();
    m_band.clear();
    m_tempoLane.cancel();
    m_voiceLane.cancel();
    m_hoverState.previewValueLabel = {};
    m_hoverState.hover.highlightLocked = false;
    invalidateContent(m_hoverState.clearHover());
    updateAxisLockCursor(AxisLock::None);
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
    m_hoverState.previewValueLabel = {};
    if (gestureActive)
        setGestureActive(false);
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
    if (!m_page || !m_page->document() || !mutableLane(target))
        return true;
    SongDocument *document = m_page->document();
    if (chosen == setValue) {
        int stored = targetPoint.value;
        const NodeLane *lane = mutableLane(target);
        bool accepted = lane->promptValue(this, stored, &stored);
        if (accepted && stored != targetPoint.value) {
            const NodeDrag drag{target,
                                targetPoint,
                                {targetPoint.tick, stored},
                                lane->minimumValue(),
                                lane->maximumValue()};
            commitNodePointMoves(document->revision(), {drag});
            m_page->requestRefresh();
        }
    } else if (chosen == deletePoint) {
        const NodeLane *lane = mutableLane(target);
        const NodeDrag drag{target, targetPoint, targetPoint, lane->minimumValue(),
                            lane->maximumValue()};
        commitNodePointDeletes(document->revision(), {drag});
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
    else
        updatePencilCursor();
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
                     lane->neutralValue());
    return out;
}

void AutomationCanvas::publishBandSelection(uint64_t first, uint64_t last, LaneHandle start,
                                            LaneHandle end) const
{
    if (!m_page || !m_laneSelection || first >= last || !start.valid() || !end.valid())
        return;
    const auto *startSlot = resolveSlot(start);
    const auto *endSlot = resolveSlot(end);
    if (!startSlot || !endSlot)
        return;
    const auto [tempo, lanes] = m_laneSelection->laneSet(startSlot->id, endSlot->id);
    m_page->publishTimeSelection(first, last, lanes, tempo);
    if (tempo && lanes.empty())
        m_page->announce(tr("Tempo range [%1, %2)").arg(first).arg(last));
    else
        m_page->announce(tr("Automation range [%1, %2)").arg(first).arg(last));
}
