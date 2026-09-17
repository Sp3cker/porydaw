#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <utility>
#include <variant>

#include <QCursor>
#include <QGuiApplication>
#include <QIcon>
#include <QPixmap>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/typography.h"

void AutomationCanvas::refreshGeometry()
{
    m_geometry = AutomationGeometry::resolve();
}

AutomationCanvas::AutomationCanvas(AutomationPage &page)
    : QObject(&page)
    , m_geometry(AutomationGeometry::resolve())
    , m_laneTitleFont(typography::bold(typography::caption(QGuiApplication::font())))
    , m_laneCaptionFont(typography::regular(typography::caption(QGuiApplication::font())))
    , m_page(page)
    , m_viewModel(buildAutomationViewModel(page.document(), page.timeline(),
                                           page.m_owner.selectionModel(), page.ready()))
    , m_tempoLane(page.document())
    , m_hoverState(QGuiApplication::font())
{
    refreshGeometry();
    // The tempo-scaled idle timer commits the current tap-tempo draft after the last tap.
    m_tapIdleCommit.setSingleShot(true);
    connect(&m_tapIdleCommit, &QTimer::timeout, this, &AutomationCanvas::commitTapTempo);
    // Menu adapters keep guarded targets until activation consumes them or shared-session cancellation clears them.
    ensureMenuAdapters();
}

void AutomationCanvas::attachInputHost(songview::TimelineInputHost &host)
{
    Q_ASSERT(!m_inputHost);
    m_inputHost = &host;
    m_inputHost->setAccessibilityDescription(tr("Automation lane"));
    hostAppearanceChanged();
}

void AutomationCanvas::detachInputHost(songview::TimelineInputHost &host)
{
    Q_ASSERT(m_inputHost == &host);
    if (m_inputHost != &host)
        return;
    inputCancelled(songview::TimelineInputCancelReason::Hidden);
    host.clearCursor();
    m_inputHost = nullptr;
}

void AutomationCanvas::hostAppearanceChanged()
{
    if (!m_inputHost)
        return;
    m_pencilCursorDpr = 0.0;
    // Rebuild lane geometry only after the input host publishes a changed size; always republish appearance.
    const QRect body = m_inputHost->bounds().toAlignedRect();
    if (m_nodeStack.empty() || m_nodeStack.front().body.size() != body.size())
        relayoutContent();
    emit parameterPresentationChanged();
    requestFullQuickUpdate();
}

void AutomationCanvas::viewportResized()
{
    relayoutContent();
}

void AutomationCanvas::relayoutContent()
{
    layoutLaneStack();
}

void AutomationCanvas::contentGeometryChanged()
{
    relayoutContent();
    m_page.synchronizeAutomationViewport(m_page.automationViewportSize());
    syncHoverValueLabel();
    syncPreviewValueLabel();
    requestFullQuickUpdate();
}

// Shared-plot content and viewport coordinates are identical because automation has no vertical plot scrolling.
QPointF AutomationCanvas::contentPosition(QPointF viewportPosition) const noexcept
{
    return viewportPosition;
}

QPointF AutomationCanvas::viewportPosition(QPointF contentPosition) const noexcept
{
    return contentPosition;
}

QPointF AutomationCanvas::contentPositionFromGlobal(QPointF globalPosition) const
{
    if (!m_inputHost)
        return {};
    return contentPosition(m_inputHost->mapFromGlobal(globalPosition));
}

QRect AutomationCanvas::viewportRect(QRect contentRect) const noexcept
{
    return contentRect;
}

QRect AutomationCanvas::contentBounds() const noexcept
{
    return m_inputHost ? m_inputHost->bounds().toAlignedRect() : QRect{};
}

AutomationProjection AutomationCanvas::projection() const
{
    return AutomationProjection(m_geometry, &m_page);
}

NodeLaneHoverTarget AutomationCanvas::hoverTarget() const
{
    NodeLaneHoverTarget target;
    target.widgetBounds = contentBounds();
    target.devicePixelRatio = m_inputHost ? m_inputHost->devicePixelRatio() : 1.0;
    target.documentRevision = m_page.document().revision();
    target.ready = m_page.ready();
    return target;
}
void AutomationCanvas::invalidateSelectedNodeMultiplicity() const noexcept
{
    m_selectedNodeMultiplicity.valid = false;
}

bool AutomationCanvas::hasMultipleSelectedNodes(
    const std::optional<std::pair<Tick, Tick>> &selectedTickRange) const
{
    if (!selectedTickRange)
        return false;
    const uint64_t documentRevision = m_page.document().revision();
    if (m_selectedNodeMultiplicity.valid &&
        m_selectedNodeMultiplicity.documentRevision == documentRevision) {
        return m_selectedNodeMultiplicity.multiple;
    }
    const auto [firstTick, lastTick] = *selectedTickRange;
    auto selectedCount = 0;
    for (std::size_t index = 0; index < m_nodeStack.size(); ++index) {
        const NodeLaneSlot &slot = m_nodeStack[index];
        const LaneHandle handle{int(index)};
        const AutomationViewModel::Row *const row = m_viewModel.find(slot.id);
        if (!slot.lane || ((!row || !row->coversNodes) && !bandPreviewContainsLane(handle)))
            continue;
        for (const NodePoint &point : slot.lane->points()) {
            if (point.tick < firstTick || point.tick >= lastTick)
                continue;
            if (++selectedCount > 1) {
                m_selectedNodeMultiplicity = {
                    .documentRevision = documentRevision, .valid = true, .multiple = true};
                return true;
            }
        }
    }
    m_selectedNodeMultiplicity = {
        .documentRevision = documentRevision, .valid = true, .multiple = false};
    return false;
}

void AutomationCanvas::requestQuickUpdate(songview::AutomationRefreshSet dirty) const
{
    if (dirty.testFlag(songview::AutomationRefresh::Hover)) {
        if (!m_hoverState.hover.lane.valid()) {
            m_page.m_owner.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
        } else {
            const Tick tick = CoreTimeDefaults::tickFromDouble(
                m_hoverState.insertionTick(projection(), m_pencilMode));
            m_page.m_owner.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation,
                                                     tick);
        }
    }
    m_page.requestQuickUpdate(dirty);
}

void AutomationCanvas::requestFullQuickUpdate() const
{
    // A full repaint invalidates the revision-keyed selected-node multiplicity cache.
    invalidateSelectedNodeMultiplicity();
    requestQuickUpdate(songview::AutomationRefresh::All);
}

void AutomationCanvas::requestSelectionQuickUpdate() const
{
    invalidateSelectedNodeMultiplicity();
    requestQuickUpdate(songview::AutomationRefresh::Content);
    // Selection refresh also republishes uncached parameter-inclusion state through the non-const signal.
    const_cast<AutomationCanvas *>(this)->parameterSelectionChanged();
}

void AutomationCanvas::requestHoverQuickUpdate() const
{
    requestQuickUpdate(songview::AutomationRefresh::Hover);
}

void AutomationCanvas::requestGestureBeginQuickUpdate(bool band) const
{
    if (band)
        invalidateSelectedNodeMultiplicity();
    requestQuickUpdate(songview::AutomationRefresh::Content |
                       songview::AutomationRefresh::Transient);
}

void AutomationCanvas::requestGestureMoveQuickUpdate() const
{
    if (m_band.active)
        invalidateSelectedNodeMultiplicity();
    requestQuickUpdate(songview::AutomationRefresh::Transient);
}

bool AutomationCanvas::bandPreviewContainsLane(LaneHandle handle) const noexcept
{
    return m_band.coversLane(handle);
}
void AutomationCanvas::setPencilMode(bool enabled)
{
    m_pencilMode = enabled;
    if (!m_activeGesture) {
        // Clear stationary hover before reclassifying it for the new tool without claiming foreign input ownership.
        m_hoverState.clearHover();
        refreshHoverAt(contentPositionFromGlobal(QCursor::pos()));
    }
    syncHoverValueLabel();
    syncPreviewValueLabel();
    updatePencilCursor();
    requestHoverQuickUpdate();
}

bool AutomationCanvas::isPanning() const noexcept
{
    return m_pan.active;
}

const QCursor &AutomationCanvas::pencilCursor()
{
    Q_ASSERT(m_inputHost);
    const qreal dpr = m_inputHost->devicePixelRatio();
    if (m_pencilCursorDpr != dpr) {
        constexpr int cursorExtent = 16;
        const QIcon icon(QStringLiteral(":/cursors/pencil.png"));
        const int physicalExtent = std::max(1, qRound(qreal(cursorExtent) * dpr));
        QPixmap pixmap = icon.pixmap(QSize(physicalExtent, physicalExtent));
        pixmap.setDevicePixelRatio(dpr);
        const int hotspotY = std::max(0, qRound(pixmap.height() / dpr) - 1);
        m_pencilCursor = QCursor(pixmap, 0, hotspotY);
        m_pencilCursorDpr = dpr;
    }
    return m_pencilCursor;
}

AutomationCanvas::TargetEpoch AutomationCanvas::targetEpoch() const
{
    return {m_page.document().revision(), m_rowGeneration};
}

void AutomationCanvas::rebuildRows()
{
    ++m_rowGeneration;
    cancelInteraction();
    // Structural rebuilds invalidate lane handles, so close only menus owned by this canvas before remapping.
    cancelLaneMenuWithoutFocus();
    cancelNodeMenuWithoutFocus();
    invalidateSelectedNodeMultiplicity();
    m_hoverState.invalidateCaches();
    m_hoverState.hoverValueLabel = {};
    m_hoverState.previewValueLabel = {};
    rebuildViewModel();
    contentGeometryChanged();
    // Document and track rebuilds republish remapped labels, appearance, and selection markers together.
    emit parameterPresentationChanged();
    emit parameterSelectionChanged();
}

void AutomationCanvas::rebuildViewModel()
{
    m_viewModel = buildAutomationViewModel(m_page.document(), m_page.timeline(),
                                           m_page.m_owner.selectionModel(), m_page.ready());
}

void AutomationCanvas::layoutLaneStack()
{
    rebuildNodeStack();
}

void AutomationCanvas::rebuildNodeStack()
{
    cancelNodeGestures();
    m_hoverState.hover.highlightLocked = false;
    m_hoverState.invalidateCaches();
    m_hoverState.clearHover();
    m_nodeStack.clear();
    m_ccAdapters.clear();
    // Every logical parameter uses the published plot body; only the active parameter renders and hit-tests.
    const QRect body(QPoint{}, m_page.automationViewportSize());
    const auto rows = m_viewModel.visibleRows();
    m_nodeStack.push_back({rows.front().id, &m_tempoLane, body});
    m_ccAdapters.reserve(rows.size() - 1);
    for (auto row = rows.begin() + 1; row != rows.end(); ++row)
        m_ccAdapters.emplace_back(m_page.document(), int(row->id.track), row->id.controller);
    for (std::size_t index = 1; index < rows.size(); ++index)
        m_nodeStack.push_back({rows[index].id, &m_ccAdapters[index - 1], body});
}

// A point inside the shared body resolves to the active parameter; all other points resolve to no lane.
LaneHandle AutomationCanvas::laneAt(int y) const noexcept
{
    const LaneHandle active = activeLane();
    const auto *slot = resolveSlot(active);
    if (!slot || y < slot->body.top() || y >= slot->body.top() + slot->body.height())
        return {};
    return active;
}
void AutomationCanvas::refreshHoverAt(const QPointF &position)
{
    // Resolve the active parameter directly because Tempo uses the same plot as every other parameter.
    const LaneHandle handle =
        contentBounds().contains(position.toPoint()) ? activeLane() : LaneHandle{};
    const auto *slot = resolveSlot(handle);
    if (!slot) {
        m_hoverState.clearHover();
    } else {
        m_hoverState.updateHover(hoverTarget(), m_geometry, *slot->lane, slot->body, handle,
                                 projection(), position.x(), position.toPoint().y(), m_pencilMode);
    }
    // Stationary refresh republishes hints only while the primary plot still owns their display.
    if (m_inputHost)
        m_inputHost->refreshMouseHint(mouseHintProfile());
}

ui::hint_profiles::Id AutomationCanvas::mouseHintProfile() const
{
    const auto &hover = m_hoverState.hover;
    if (!hover.lane.valid())
        return ui::hint_profiles::Id::Empty;
    if (hover.hasPoint)
        return hover.originPhantom ? ui::hint_profiles::Id::AutomationOriginPhantom
                                   : ui::hint_profiles::Id::AutomationNode;
    return m_pencilMode ? ui::hint_profiles::Id::AutomationPencil
                        : ui::hint_profiles::Id::AutomationSweep;
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
    m_hoverState.updateHoverValueLabel(hoverTarget(), m_geometry, resolved ? lane : nullptr, body,
                                       projection(), m_pencilMode);
}

void AutomationCanvas::syncPreviewValueLabel()
{
    const NodeLane *lane = nullptr;
    QRect body;
    LaneHandle handle;
    qreal x = 0;
    int value = 0;
    if (m_activeGesture && m_page.ready()) {
        handle = std::visit([](const auto &gesture) { return gesture.lane; }, *m_activeGesture);
        if (resolveLane(handle, &lane, &body)) {
            const qreal dpr = m_inputHost ? m_inputHost->devicePixelRatio() : 1.0;
            if (const auto *gesture = std::get_if<NodeDragGesture>(&*m_activeGesture)) {
                if (gesture->grabbedPoint < gesture->points.size()) {
                    const auto &point = gesture->points[gesture->grabbedPoint];
                    x = projection().displayX(point.current.tick, dpr);
                    value = point.current.value;
                } else {
                    lane = nullptr;
                }
            } else if (const auto *phantom = std::get_if<PhantomGesture>(&*m_activeGesture)) {
                value = phantom->point.current.value;
            } else if (const auto *sweep = std::get_if<SweepGesture>(&*m_activeGesture)) {
                x = projection().displayX(sweep->current.tick, dpr);
                value = sweep->current.value;
            } else if (const auto *pencil = std::get_if<PencilGesture>(&*m_activeGesture)) {
                const auto &sample = pencil->stroke.lastSample();
                x = sample.logicalX;
                value = int(std::lround(sample.continuousValue));
            }
        }
    }
    m_hoverState.updatePreviewValueLabel(hoverTarget(), m_geometry, lane, body, handle, x, value);
}

void AutomationCanvas::highlightHoveredPoint(LaneHandle handle, const QPointF &position,
                                             const NodePoint &point)
{
    const NodeLane *lane = nullptr;
    QRect body;
    if (!resolveLane(handle, &lane, &body))
        return;
    m_hoverState.setContextPointHighlight(hoverTarget(), m_geometry, *lane, body, handle,
                                          projection(), position, point, m_pencilMode);
    requestHoverQuickUpdate();
}

void AutomationCanvas::cancelInteraction()
{
    const bool wasActive = m_pan.active || m_band.pending || m_activeGesture.has_value();
    m_pan.active = false;
    m_activeGesture.reset();
    m_band.clear();
    if (m_pendingValuePrompt) {
        // Shared cancellation drops the value prompt without stealing focus.
        m_pendingValuePrompt.reset();
        emit valuePromptChanged();
    }
    // Cancelling canvas interaction also clears the tap-tempo draft and idle deadline.
    resetTapTempo();
    // Shared cancellation closes only this canvas's pending CC deletion session.
    cancelCcDeletePromptWithoutFocus();
    m_hoverState.previewValueLabel = {};
    m_hoverState.hover.highlightLocked = false;
    refreshHoverAt(contentPositionFromGlobal(QCursor::pos()));
    updateAxisLockCursor(AxisLock::None);
    if (m_inputHost)
        m_inputHost->releasePointerGrab();
    if (wasActive) {
        setGestureActive(false);
        requestFullQuickUpdate();
    } else {
        requestHoverQuickUpdate();
    }
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

bool AutomationCanvas::openValuePromptForNode(LaneHandle handle, const NodePoint &point)
{
    const NodeLaneSlot *slot = resolveSlot(handle);
    if (!slot || !slot->lane)
        return false;
    const TargetEpoch epoch = targetEpoch();
    m_pendingValuePrompt =
        PendingValuePrompt{handle, point, epoch, slot->lane->valuePrompt(point.value), true};
    QPointer<AutomationCanvas> self(this);
    emit valuePromptChanged();
    return self && targetEpoch() == epoch && m_pendingValuePrompt.has_value();
}

bool AutomationCanvas::openValuePromptForInsertion(LaneHandle handle, Tick tick, int storedValue)
{
    const NodeLaneSlot *slot = resolveSlot(handle);
    if (!slot || !slot->lane)
        return false;
    const TargetEpoch epoch = targetEpoch();
    m_pendingValuePrompt = PendingValuePrompt{
        handle, {tick, storedValue}, epoch, slot->lane->valuePrompt(storedValue), false};
    QPointer<AutomationCanvas> self(this);
    emit valuePromptChanged();
    return self && targetEpoch() == epoch && m_pendingValuePrompt.has_value();
}

void AutomationCanvas::acceptNodeValuePrompt(int displayedValue)
{
    const std::optional<PendingValuePrompt> pending =
        std::exchange(m_pendingValuePrompt, std::nullopt);
    if (!pending)
        return;
    QPointer<AutomationCanvas> self(this);
    emit valuePromptChanged();
    if (!self)
        return;
    if (targetEpoch() != pending->epoch) {
        if (m_inputHost)
            m_inputHost->requestFocus(Qt::PopupFocusReason);
        return;
    }
    const NodeLaneSlot *slot = resolveSlot(pending->lane);
    NodeLane *lane = slot ? slot->lane : nullptr;
    if (!lane)
        return;
    const int stored = std::clamp(displayedValue + pending->prompt.storedOffset,
                                  lane->minimumValue(), lane->maximumValue());
    if (pending->forExistingNode) {
        if (stored != pending->anchor.value) {
            const NodeDrag drag{pending->lane,
                                pending->anchor,
                                {pending->anchor.tick, stored},
                                lane->minimumValue(),
                                lane->maximumValue()};
            commitNodePointMoves(pending->epoch.documentRevision, {drag});
            if (!self)
                return;
            m_page.requestRefresh();
        }
    } else {
        const std::vector<NodePoint> existing = lane->points();
        const bool duplicate =
            std::any_of(existing.cbegin(), existing.cend(), [&](const NodePoint &point) {
                return point.tick == pending->anchor.tick && point.value == stored;
            });
        if (!duplicate) {
            lane->replaceSpan(pending->anchor.tick, pending->anchor.tick,
                              {{pending->anchor.tick, stored}});
            if (!self)
                return;
            m_page.requestRefresh();
        }
    }
    if (self && m_inputHost)
        m_inputHost->requestFocus(Qt::PopupFocusReason);
}

void AutomationCanvas::cancelNodeValuePrompt()
{
    if (!m_pendingValuePrompt)
        return;
    m_pendingValuePrompt.reset();
    emit valuePromptChanged();
    if (m_inputHost)
        m_inputHost->requestFocus(Qt::PopupFocusReason);
}

void AutomationCanvas::setGestureActive(bool active)
{
    m_page.setFollowScrollPaused(active);
}

void AutomationCanvas::updateAxisLockCursor(AxisLock lock)
{
    if (!m_inputHost)
        return;
    if (lock == AxisLock::Time)
        m_inputHost->setCursor(QCursor(Qt::SizeHorCursor));
    else if (lock == AxisLock::Value)
        m_inputHost->setCursor(QCursor(Qt::SizeVerCursor));
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
    const Tick tick = m_page.snapTick(proj.rawTickAt(pos.x()), fine);
    NodePoint out;
    updateValuePoint(proj, *lane, body, out, pos.y(), tick, snapValue, m_geometry.neutralSnapRadius,
                     lane->neutralValue());
    return out;
}

void AutomationCanvas::publishBandSelection(Tick first, Tick last, LaneHandle start,
                                            LaneHandle end) const
{
    if (first >= last || !start.valid() || !end.valid())
        return;
    const auto *startSlot = resolveSlot(start);
    const auto *endSlot = resolveSlot(end);
    if (!startSlot || !endSlot)
        return;
    const auto [tempo, lanes] = m_viewModel.laneSet(startSlot->id, endSlot->id);
    m_page.publishTimeSelection(first, last, lanes, tempo);
}
