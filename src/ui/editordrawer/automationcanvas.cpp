#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/cclanes.h"

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
#include "ui/layout.h"
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
    , m_rowData(&page)
    , m_tempoLane(&page)
    , m_laneSelection(page.m_owner.selectionModel(), m_rowData.rows(), page.usedTrackMask())
    , m_hoverState(QGuiApplication::font())
{
    refreshGeometry();
    // The lane menus are typed adapters over the shared canvas popup session;
    // the session itself is assigned later by the Quick host view. The host
    // closes the session before emitting activated(), so the guarded open-
    // time target survives until handleMenuAction consumes it — only a
    // cancellation (Escape, outside press, foreign replacement, window
    // resize or deactivation) clears it.
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
    // TimelineInputItem::geometryChange publishes after the actual QML bounds
    // update, so the compared body is never a stale pre-publication band
    // width. Rebuild geometry only on a size change; appearance notifications
    // carry the parameter-presentation refresh for font and theme churn.
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

// The shared plot fills the viewport, so content and viewport space coincide;
// the vertical automation scroll transform is identity by design.
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
    target.documentRevision = m_page.liveState().documentRevision;
    target.ready = m_page.ready();
    return target;
}
void AutomationCanvas::invalidateSelectedNodeMultiplicity() const noexcept
{
    m_selectedNodeMultiplicity.valid = false;
}

bool AutomationCanvas::hasMultipleSelectedNodes(
    const std::optional<std::pair<uint64_t, uint64_t>> &selectedTickRange) const
{
    if (!selectedTickRange)
        return false;
    const uint64_t documentRevision = m_page.liveState().documentRevision;
    if (m_selectedNodeMultiplicity.valid &&
        m_selectedNodeMultiplicity.documentRevision == documentRevision) {
        return m_selectedNodeMultiplicity.multiple;
    }
    const auto [firstTick, lastTick] = *selectedTickRange;
    auto selectedCount = 0;
    for (std::size_t index = 0; index < m_nodeStack.size(); ++index) {
        const NodeLaneSlot &slot = m_nodeStack[index];
        const LaneHandle handle{int(index)};
        if (!slot.lane ||
            (!m_laneSelection.coversNodes(slot.id) && !bandPreviewContainsLane(handle))) {
            continue;
        }
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
            const uint64_t tick =
                uint64_t(std::max(0.0, m_hoverState.insertionTick(projection(), m_pencilMode)));
            m_page.m_owner.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation,
                                                     tick);
        }
    }
    m_page.requestQuickUpdate(dirty);
}

void AutomationCanvas::requestFullQuickUpdate() const
{
    // Full repaints re-render the selection layer, so the revision-keyed
    // memo cannot survive them.
    invalidateSelectedNodeMultiplicity();
    requestQuickUpdate(songview::AutomationRefresh::All);
}

void AutomationCanvas::requestSelectionQuickUpdate() const
{
    invalidateSelectedNodeMultiplicity();
    requestQuickUpdate(songview::AutomationRefresh::Content);
    // The existing selection refresh doubles as the selector's
    // shared-selection indicator notification; no membership is cached. The
    // signal is non-const, so emission crosses this refresh's const surface
    // explicitly; activating it does not mutate the canvas.
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
    if (!m_activeGesture)
        m_hoverState.clearHover();
    m_pencilMode = enabled;
    syncHoverValueLabel();
    syncPreviewValueLabel();
    updatePencilCursor();
    requestHoverQuickUpdate();
    m_page.announce(enabled ? tr("Pencil mode on") : tr("Pencil mode off"));
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

void AutomationCanvas::rebuildRows()
{
    cancelInteraction();
    // A structural rebuild remaps every LaneHandle in m_nodeStack, so a menu
    // opened earlier would mutate a different lane: end it synchronously,
    // without stealing focus. Only an owned session ends here; a foreign
    // popup (a prompt, another band's menu) survives.
    cancelLaneMenuWithoutFocus();
    cancelNodeMenuWithoutFocus();
    invalidateSelectedNodeMultiplicity();
    m_hoverState.invalidateCaches();
    m_hoverState.hoverValueLabel = {};
    m_hoverState.previewValueLabel = {};
    m_rowData.rebuildRows();
    m_laneSelection.setUsedTrackMask(m_page.usedTrackMask());
    contentGeometryChanged();
    // Document and track rebuilds rebind every adapter and remap the
    // selector's row identities: labels, appearance and selection markers
    // are republished together.
    emit parameterPresentationChanged();
    emit parameterSelectionChanged();
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
    // Use the synchronously published plot viewport: after showing the drawer,
    // the Quick input host can still have its hidden bounds until QML settles.
    // Every logical slot shares this body so selected multi-lane edits keep
    // valid value geometry; only activeLane() decides what renders and hit-tests.
    const QRect body(QPoint{}, m_page.automationViewportSize());
    m_nodeStack.push_back({{EditorAutomationRowKind::Tempo, 0, 0}, &m_tempoLane, body, nullptr});
    if (!m_page.document())
        return;
    const auto &rows = m_rowData.rows();
    auto &rowText = m_rowData.rowText();
    m_ccAdapters.reserve(rows.size());
    for (const auto &row : rows)
        m_ccAdapters.emplace_back(*m_page.document(), int(row.id.track), row.id.controller);
    for (int i = 0; i < int(rows.size()); ++i)
        m_nodeStack.push_back({rows[std::size_t(i)].id, &m_ccAdapters[std::size_t(i)], body,
                               &rowText[std::size_t(i)]});
}

// Only the active parameter occupies the shared plot: a y inside the common
// body resolves the active lane, anywhere else is no lane.
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
    if (!contentBounds().contains(position.toPoint())) {
        m_hoverState.clearHover();
        return;
    }
    // Resolve the active slot directly — Tempo is ordinary plot content, not
    // gutter or header.
    const LaneHandle handle = activeLane();
    const auto *slot = resolveSlot(handle);
    if (!slot) {
        m_hoverState.clearHover();
        return;
    }
    m_hoverState.updateHover(hoverTarget(), m_geometry, *slot->lane, slot->body, handle,
                             projection(), position.x(), position.toPoint().y(), m_pencilMode);
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
            } else if (const auto *gesture = std::get_if<PhantomGesture>(&*m_activeGesture)) {
                value = gesture->point.current.value;
            } else if (const auto *gesture = std::get_if<SweepGesture>(&*m_activeGesture)) {
                x = projection().displayX(gesture->current.tick, dpr);
                value = gesture->current.value;
            } else if (const auto *gesture = std::get_if<PencilGesture>(&*m_activeGesture)) {
                const auto &sample = gesture->stroke.lastSample();
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
        // Shared cancellation policy (detach, hide, deactivation, document
        // change) drops the prompt without stealing focus from whoever has it.
        m_pendingValuePrompt.reset();
        emit valuePromptChanged();
    }
    // Same shared policy for the CC-lane delete confirmation: rebuilds,
    // hides, detaches, and document changes drop its pending target and end
    // only a session this canvas still owns, without stealing focus.
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
    SongDocument *document = m_page.document();
    const NodeLaneSlot *slot = resolveSlot(handle);
    if (!document || !slot || !slot->lane)
        return false;
    m_pendingValuePrompt = PendingValuePrompt{handle, point, document->revision(),
                                              slot->lane->valuePrompt(point.value), true};
    emit valuePromptChanged();
    return true;
}

bool AutomationCanvas::openValuePromptForInsertion(LaneHandle handle, uint64_t tick,
                                                   int storedValue)
{
    SongDocument *document = m_page.document();
    const NodeLaneSlot *slot = resolveSlot(handle);
    if (!document || !slot || !slot->lane)
        return false;
    m_pendingValuePrompt = PendingValuePrompt{handle,
                                              {tick, storedValue},
                                              document->revision(),
                                              slot->lane->valuePrompt(storedValue),
                                              false};
    emit valuePromptChanged();
    return true;
}

void AutomationCanvas::acceptNodeValuePrompt(int displayedValue)
{
    const std::optional<PendingValuePrompt> pending =
        std::exchange(m_pendingValuePrompt, std::nullopt);
    if (!pending)
        return;
    emit valuePromptChanged();
    SongDocument *document = m_page.document();
    const NodeLaneSlot *slot = resolveSlot(pending->lane);
    NodeLane *lane = slot ? slot->lane : nullptr;
    if (!document || !lane || document->revision() != pending->expectedRevision) {
        // Stale prompt — replacement, lane removal, or a document change
        // since it opened. No edit, no undo entry, only the focus return.
        if (m_inputHost)
            m_inputHost->requestFocus(Qt::PopupFocusReason);
        return;
    }
    const int stored = std::clamp(displayedValue + pending->prompt.storedOffset,
                                  lane->minimumValue(), lane->maximumValue());
    if (pending->forExistingNode) {
        if (stored != pending->anchor.value) {
            const NodeDrag drag{pending->lane,
                                pending->anchor,
                                {pending->anchor.tick, stored},
                                lane->minimumValue(),
                                lane->maximumValue()};
            commitNodePointMoves(pending->expectedRevision, {drag});
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
            m_page.requestRefresh();
        }
    }
    if (m_inputHost)
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
    const uint64_t tick = m_page.snapTick(proj.rawTickAt(pos.x()), fine);
    NodePoint out;
    updateValuePoint(proj, *lane, body, out, pos.y(), tick, snapValue, m_geometry.neutralSnapRadius,
                     lane->neutralValue());
    return out;
}

void AutomationCanvas::publishBandSelection(uint64_t first, uint64_t last, LaneHandle start,
                                            LaneHandle end) const
{
    if (first >= last || !start.valid() || !end.valid())
        return;
    const auto *startSlot = resolveSlot(start);
    const auto *endSlot = resolveSlot(end);
    if (!startSlot || !endSlot)
        return;
    const auto [tempo, lanes] = m_laneSelection.laneSet(startSlot->id, endSlot->id);
    m_page.publishTimeSelection(first, last, lanes, tempo);
    if (tempo && lanes.empty())
        m_page.announce(tr("Tempo range [%1, %2)").arg(first).arg(last));
    else
        m_page.announce(tr("Automation range [%1, %2)").arg(first).arg(last));
}
