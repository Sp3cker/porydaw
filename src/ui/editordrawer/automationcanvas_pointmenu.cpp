#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <utility>
#include <vector>

#include <QQuickWindow>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/retirehostmenu.h"

namespace {

songview::QuickMenuItem menuRow(int id, QString text)
{
    songview::QuickMenuItem item;
    item.id = id;
    item.text = std::move(text);
    return item;
}

using Action = AutomationCanvas::NodeMenuAction;

} // namespace

// The node point menu is AutomationCanvas's second slice of the shared canvas
// popup session: a typed QuickMenuHost/QuickMenuModel pair of its own, so the
// lane menu keeps a single model and no menu-kind flag. This file owns that
// menu's lifecycle — open, outside-right retarget, guarded dispatch. Every
// command travels through the existing commit primitives, re-resolved and
// revalidated at dispatch, so a stale target writes nothing.

void AutomationCanvas::ensureNodeMenuAdapters()
{
    if (m_nodeMenuHost)
        return;
    m_nodeMenuHost = new songview::QuickMenuHost(this);
    m_nodeMenuModel = new songview::QuickMenuModel(this);
    connect(m_nodeMenuModel, &songview::QuickMenuModel::activated, this,
            &AutomationCanvas::handleNodeMenuAction);
    // Any teardown of the node menu's session ownership (Escape, outside
    // press, foreign replacement, window resize or deactivation) drops the
    // pending target.
    connect(m_nodeMenuHost, &songview::QuickMenuHost::cancelled, this,
            [this] { m_pendingNodeMenu.reset(); });
    // Selection and context changes retire only the active point menu. Its
    // dedicated root identity leaves value prompts and CC-lane-delete forms
    // with their own Escape/Cancel paths.
    connect(&m_page.m_owner, &SongView::contextMenusInvalidated, this, [this](bool restoreFocus) {
        songview::retireHostMenu(m_menuSession.data(), m_nodeMenuHost, m_nodeMenuModel,
                                 restoreFocus);
    });
    // Outside-right retarget: the session dismissed this host's menu and the
    // paired release is swallowed; the press may move the menu onto another
    // node or leave it dismissed on a miss.
    connect(m_nodeMenuHost, &songview::QuickMenuHost::outsideRightPressed, this,
            [this](QPointF scenePosition) { retargetNodeMenu(scenePosition); });
}

void AutomationCanvas::cancelNodeMenuWithoutFocus()
{
    m_pendingNodeMenu.reset();
    // Only end a session this canvas still owns: a foreign popup (the lane
    // menu, a prompt, another band's menu) must survive canvas teardown.
    if (m_menuSession && m_menuSession->owns(m_nodeMenuHost))
        m_menuSession->cancel(/*restoreFocus=*/false);
}

bool AutomationCanvas::showNodeMenuNear(LaneHandle handle, const QPointF &position,
                                        const QPointF &globalPosition)
{
    // The return is node-hit consumption, not "a menu stayed open": false is
    // only a genuine miss, which keeps the caller's fallback alive; a hit
    // whose open aborts — teardown, refused publish, displaced by a newer
    // popup, stale snapshot — returns true and never opens a second menu.
    SongDocument &document = m_page.document();
    songview::QuickPopupSession *const session = m_menuSession.data();
    // No menu surface: nothing consumed; the miss fallback proceeds.
    if (!session || !session->window())
        return false;
    const auto *slot = resolveSlot(handle);
    NodePoint point;
    // The same hit the press path used: an empty plot misses and the caller
    // keeps its time-selection fallback. Phantom and synthetic-default
    // projections hit exactly as they did under the former native menu.
    if (!slot || !slot->lane || !nodePointHit(handle, position, &point))
        return false;

    // Capture the whole guarded open-time target BEFORE any signal-producing
    // step: setItems' model reset, the grab release, and open()'s implicit
    // cancellation of a displaced session can all re-enter this canvas
    // synchronously, so nothing below trusts state re-read after them.
    PendingNodeMenu target;
    target.epoch = targetEpoch();
    target.lane = handle;
    target.rowId = slot->id;
    target.point = point;

    // Delete only ever writes what the document holds: a projected hit (the
    // engine-default tick-0 node on Volume/Pan, or an origin phantom anchored
    // on one) has no written event at its tick, so its Delete row is disabled
    // — activating it would be a silent no-op. SetValue stays enabled and
    // keeps its promotion of a projected node into a written event. The
    // query is the document's canonical written-point lookup, never adapter
    // state or lead-in subtraction.
    const bool writtenAtTick =
        slot->isTempo()
            ? std::any_of(document.tempoPoints().cbegin(), document.tempoPoints().cend(),
                          [tick = point.tick](const TempoPoint &tempoPoint) {
                              return tempoPoint.tick == tick;
                          })
            : document.findLanePoint(int(slot->id.track), slot->id.controller, point.tick, nullptr);

    std::vector<songview::QuickMenuItem> rows;
    rows.reserve(2);
    rows.push_back(menuRow(int(Action::SetValue), tr("Set Value")));
    songview::QuickMenuItem del = menuRow(int(Action::DeleteNode), tr("Delete"));
    del.enabled = writtenAtTick;
    rows.push_back(std::move(del));
    // The model reset, grab release, and open each run synchronous canvas
    // callbacks: they can tear this canvas down — the document can outlive
    // it — and rebind the canvas to another session or detach/replace its
    // input host. Pin the press's surface; after every boundary, a failed
    // self guard or a changed identity aborts the open as consumed.
    QPointer<AutomationCanvas> self(this);
    const QPointer<songview::QuickPopupSession> boundSession = session;
    songview::TimelineInputHost *const boundHost = m_inputHost;
    m_nodeMenuModel->setItems(std::move(rows));
    if (!self)
        return true;
    if (!boundSession || boundSession != m_menuSession || boundHost != m_inputHost)
        return true;

    // End the press's implicit grab before the menu publishes: the panel must
    // receive the following clicks, and the synchronous PointerUngrabbed
    // cancellation lands before any pending target exists.
    if (boundHost)
        boundHost->releasePointerGrab();
    if (!self)
        return true;
    if (!boundSession || boundSession != m_menuSession || boundHost != m_inputHost)
        return true;
    // A callback above may have published a newer popup on the shared
    // session; it wins — never displace it, never fall back over the hit.
    if (m_menuSession && m_menuSession->isOpen() && !m_menuSession->owns(m_nodeMenuHost))
        return true;
    m_nodeMenuHost->open(m_nodeMenuModel, menuScenePosition(globalPosition));
    if (!self)
        return true;
    if (!m_nodeMenuHost->isOpen())
        return true;
    if (targetEpoch() != target.epoch) {
        cancelNodeMenuWithoutFocus();
        return true;
    }
    m_pendingNodeMenu = std::move(target);
    return true;
}

void AutomationCanvas::retargetNodeMenu(const QPointF &scenePosition)
{
    // The host forward already proved the canvas stayed idle. Map the press
    // through global coordinates so the shared hit-test helpers stay
    // unchanged.
    songview::QuickPopupSession *const session = m_menuSession.data();
    QQuickWindow *const window = session ? session->window() : nullptr;
    if (!window || !m_inputHost)
        return;
    const QPointF globalPosition = window->mapToGlobal(scenePosition);
    const QPointF position = contentPositionFromGlobal(globalPosition);
    const LaneHandle candidate = laneAt(position.toPoint().y());
    NodePoint candidatePoint;
    if (!nodePointHit(candidate, position, &candidatePoint))
        return; // Miss: the menu stays dismissed.
    highlightHoveredPoint(candidate, position, candidatePoint);
    showNodeMenuNear(candidate, position, globalPosition);
}

void AutomationCanvas::handleNodeMenuAction(int actionId)
{
    if (!m_pendingNodeMenu)
        return;
    // Consume before any command: SetValue opens the inline value prompt and
    // a target must never fire twice.
    const PendingNodeMenu pending = std::move(*m_pendingNodeMenu);
    m_pendingNodeMenu.reset();
    // Keyboard continuity returns to the band before dispatch, but only when
    // no subsequent popup already owns the session — never stealing focus
    // from a foreign owner. The focus return can synchronously swap active
    // surfaces and run editing handlers, so it happens BEFORE final
    // validation: everything below judges the post-focus document state.
    QPointer<AutomationCanvas> self(this);
    if (!m_menuSession || !m_menuSession->isOpen()) {
        if (m_inputHost)
            m_inputHost->requestFocus(Qt::PopupFocusReason);
    }
    if (!self)
        return; // The focus swap tore this canvas down.
    if (targetEpoch() != pending.epoch)
        return;
    const auto *slot = resolveSlot(pending.lane);
    if (!slot || !slot->lane)
        return;
    NodeLane *lane = slot->lane;
    const std::vector<NodePoint> points = lane->points();
    const bool present =
        std::any_of(points.cbegin(), points.cend(), [&pending](const NodePoint &point) {
            return point.tick == pending.point.tick && point.value == pending.point.value;
        });
    if (!present)
        return;
    if (actionId == int(Action::SetValue)) {
        // The existing DrawerChrome inline Quick value prompt: opening
        // snapshots the revision and never writes; acceptance revalidates.
        openValuePromptForNode(pending.lane, pending.point);
    } else if (actionId == int(Action::DeleteNode)) {
        // Deletion resolves by tick group, so duplicate-tick written points
        // at the target tick are removed together. Projected targets can
        // never reach this branch: their row opened disabled and the revision
        // guard above proves the document has not changed since.
        const NodeDrag drag{pending.lane, pending.point, pending.point, lane->minimumValue(),
                            lane->maximumValue()};
        commitNodePointDeletes(pending.epoch.documentRevision, {drag});
        if (!self)
            return;
        m_page.requestRefresh();
    }
}
