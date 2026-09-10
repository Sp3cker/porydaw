#include "ui/editordrawer/automationcanvas.h"

#include <QQuickWindow>
#include <algorithm>
#include <limits>
#include <optional>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"

namespace {

EditorAutomationRowId laneRow(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

songview::QuickMenuItem menuRow(int id, QString text)
{
    songview::QuickMenuItem item;
    item.id = id;
    item.text = std::move(text);
    return item;
}

songview::QuickMenuItem disabledRow(QString text)
{
    songview::QuickMenuItem item = menuRow(0, std::move(text));
    item.enabled = false;
    return item;
}

using Action = AutomationCanvas::CanvasMenuAction;

// Per-kind presentation for the unified lane menu, keyed by the lane kind so
// the menu body carries no tempo/CC branching. Labels feed the open-time
// rows, messages feed the dispatch-time announcements; both rebuild from live
// state, so nothing presentation-shaped crosses the popup.
struct LaneMenuKind {
    QString copyLabel;
    QString pasteLabel;
    QString clearLabel;
    QString copiedMessage;
    QString pastedMessage;
    std::optional<QString> clearedMessage;
    bool hasLaneActions = false;
};

LaneMenuKind laneMenuKind(bool tempo, const QString &laneTitle, std::size_t pointCount = 0)
{
    if (tempo) {
        return LaneMenuKind{AutomationCanvas::tr("Copy"),
                            AutomationCanvas::tr("Paste"),
                            AutomationCanvas::tr("Clear Tempo"),
                            AutomationCanvas::tr("Copied Tempo"),
                            AutomationCanvas::tr("Pasted Tempo"),
                            AutomationCanvas::tr("Cleared Tempo"),
                            false};
    }
    return LaneMenuKind{
        AutomationCanvas::tr("Copy CC lane"),
        AutomationCanvas::tr("Paste CC lane (replace)"),
        AutomationCanvas::tr("Clear events"),
        AutomationCanvas::tr("Copied the %1 CC lane (%n point(s))", nullptr, int(pointCount))
            .arg(laneTitle),
        AutomationCanvas::tr("Replaced the %1 CC lane").arg(laneTitle),
        std::nullopt,
        true};
}

} // namespace

// The automation menus are AutomationCanvas's slice of the shared canvas popup
// session: one persistent typed QuickMenuHost/QuickMenuModel pair serves the
// lane menu, the add-lane strip menu, and the inactive time-selection menu,
// and a second pair in automationcanvas_pointmenu.cpp serves the node point
// menu. This file owns only the menu lifecycle — every command travels through
// the existing AutomationPage/SongView primitives, re-resolved and revalidated
// at dispatch, so a stale target writes nothing.

void AutomationCanvas::ensureMenuAdapters()
{
    if (m_menuHost)
        return;
    m_menuHost = new songview::QuickMenuHost(this);
    m_menuModel = new songview::QuickMenuModel(this);
    connect(m_menuModel, &songview::QuickMenuModel::activated, this,
            &AutomationCanvas::handleMenuAction);
    // Any teardown of our session ownership (outside press, Escape, resize,
    // foreign replacement, window deactivation) drops the pending target.
    connect(m_menuHost, &songview::QuickMenuHost::cancelled, this,
            [this] { m_pendingMenu.reset(); });
}

void AutomationCanvas::setPopupSession(songview::QuickPopupSession *session)
{
    if (m_menuSession == session)
        return;
    // A replaced session must not carry this canvas's pending delete
    // confirmation: drop it against the old session, ending only a form this
    // canvas still owns, before the stored pointer follows.
    cancelCcDeletePromptWithoutFocus();
    ensureMenuAdapters();
    ensureNodeMenuAdapters();
    // The host cancels its active menu on the displaced session first; the
    // stored pointer follows so a later open cannot target a dead session.
    m_menuHost->setPopupSession(session);
    m_nodeMenuHost->setPopupSession(session);
    m_menuSession = session;
}

QPointF AutomationCanvas::menuScenePosition(const QPointF &globalPosition) const
{
    songview::QuickPopupSession *const session = m_menuSession.data();
    QQuickWindow *const window = session ? session->window() : nullptr;
    return window ? window->mapFromGlobal(globalPosition) : QPointF();
}

void AutomationCanvas::cancelLaneMenuWithoutFocus()
{
    m_pendingMenu.reset();
    // Only end a session this canvas still owns: a foreign popup (the value
    // prompt, another band's menu) must survive canvas teardown.
    if (m_menuSession && m_menuSession->owns(m_menuHost))
        m_menuSession->cancel(/*restoreFocus=*/false);
}

void AutomationCanvas::showTimeSelectionMenuFor(LaneHandle contextLane,
                                                const QPointF &scenePosition)
{
    const auto *slot = resolveSlot(contextLane);
    if (!slot)
        return;
    auto &model = m_page.m_owner.selectionModel();
    const auto &selection = model.timeSelection();
    if (selection.active()) {
        DrawerPageTimeSelectionMenuRequest request{.startTick = selection.startTick,
                                                   .endTick = selection.endTick,
                                                   .tempo = slot->isTempo(),
                                                   .scenePosition = scenePosition};
        if (!request.tempo)
            request.lanes = m_laneSelection.visibleLanes();
        // Focus return lives in the owner's terminal menu paths.
        m_page.showTimeSelectionMenu(request);
        return;
    }
    SongDocument *const document = m_page.document();
    songview::QuickPopupSession *const session = m_menuSession.data();
    if (!document || !session || !session->window())
        return;
    // Inactive fallback: the same single clear row the native menu carried.
    // Dispatch rechecks activation, exactly as the post-exec path did.
    std::vector<songview::QuickMenuItem> rows;
    rows.push_back(menuRow(int(Action::ClearTimeSelection), tr("Clear time selection")));
    m_menuModel->setItems(std::move(rows));

    PendingMenu target;
    target.document = document;
    target.documentRevision = document->revision();
    target.lane = contextLane;
    target.rowId = slot->id;

    m_menuHost->open(m_menuModel, scenePosition);
    if (!m_menuHost->isOpen())
        return;
    m_pendingMenu = std::move(target);
}

void AutomationCanvas::showLaneMenuFor(LaneHandle handle, const QPointF &scenePosition)
{
    SongDocument *const document = m_page.document();
    songview::QuickPopupSession *const session = m_menuSession.data();
    if (!document || !session || !session->window())
        return;
    const auto *slot = resolveSlot(handle);
    if (!slot || !slot->lane)
        return;
    const QString laneTitle = slot->lane->title();
    // Enablement needs live data, not a snapshot: read emptiness now and let
    // every command re-read what it mutates at dispatch.
    const bool hasPoints = !slot->lane->points().empty();
    const LaneMenuKind kind = laneMenuKind(slot->isTempo(), laneTitle);

    std::vector<songview::QuickMenuItem> rows;
    rows.reserve(kind.hasLaneActions ? 7u : 4u);
    songview::QuickMenuItem copy = menuRow(int(Action::Copy), kind.copyLabel);
    copy.enabled = hasPoints;
    rows.push_back(std::move(copy));
    songview::QuickMenuItem paste = menuRow(int(Action::Paste), kind.pasteLabel);
    paste.enabled = !m_clipboard.empty();
    rows.push_back(std::move(paste));
    rows.push_back(songview::QuickMenuItem::makeSeparator());
    songview::QuickMenuItem clear = menuRow(int(Action::Clear), kind.clearLabel);
    clear.enabled = hasPoints;
    rows.push_back(std::move(clear));
    if (kind.hasLaneActions) {
        const uint8_t controller = slot->id.controller;
        // The delete/remove split classifies on document-written events: the
        // adapter projects a synthetic tick-0 engine node for Volume and Pan,
        // so adapter emptiness cannot tell a written lane from a
        // never-touched default row. Copy stays explicit about what remains.
        QString removeLabel;
        if (document->lanePoints(int(slot->id.track), controller).empty())
            removeLabel = tr("Remove empty CC lane");
        else if (CoreTimeDefaults::isDefaultVisibleController(controller))
            removeLabel = tr("Delete CC events (default row remains)");
        else
            removeLabel = tr("Delete CC lane");
        rows.push_back(menuRow(int(Action::RemoveLane), std::move(removeLabel)));
        rows.push_back(menuRow(int(Action::HideLane), tr("Hide CC lane")));
        if (CCLanes::rangeZoomable(controller)) {
            const auto range = m_page.m_viewState.laneRanges.find(slot->id);
            const uint8_t current = range == m_page.m_viewState.laneRanges.cend()
                                        ? CCLanes::defaultRange(controller)
                                        : range->second;
            songview::QuickMenuItem ranges = menuRow(int(Action::ValueRange), tr("Value range"));
            ranges.children.reserve(5);
            for (const uint8_t value :
                 {uint8_t(0), uint8_t(16), uint8_t(32), uint8_t(64), uint8_t(127)}) {
                const Action action = value == 0    ? Action::RangeAuto
                                      : value == 16 ? Action::Range16
                                      : value == 32 ? Action::Range32
                                      : value == 64 ? Action::Range64
                                                    : Action::Range127;
                const QString label = value == 0     ? tr("Auto (fit to data)")
                                      : value == 127 ? tr("0–127 (full)")
                                                     : QStringLiteral("0–%1").arg(value);
                songview::QuickMenuItem choice = menuRow(int(action), label);
                choice.checkable = true;
                choice.checked = value == current;
                ranges.children.push_back(std::move(choice));
            }
            rows.push_back(std::move(ranges));
        }
    }
    m_menuModel->setItems(std::move(rows));
    // Submenu rows activate through the lazily created child model, not the
    // root: bind this open's child before the panel can traverse into it.
    // setItems() destroyed the previous child models, so the connection is
    // re-established per open; rowForId misses on menus without the range
    // submenu (tempo lanes, non-zoomable controllers).
    if (const int rangeRow = m_menuModel->rowForId(int(Action::ValueRange)); rangeRow >= 0) {
        if (songview::QuickMenuModel *const rangesModel = m_menuModel->submenuForRow(rangeRow))
            connect(rangesModel, &songview::QuickMenuModel::activated, this,
                    &AutomationCanvas::handleMenuAction);
    }

    // Snapshot the guarded open-time target first, but publish it only after
    // open()'s implicit cancellation of a displaced session has completed: no
    // callback can observe a half-published target, and an open failure
    // publishes nothing. Cancellation clears it.
    PendingMenu target;
    target.document = document;
    target.documentRevision = document->revision();
    target.lane = handle;
    target.rowId = slot->id;
    target.laneTitle = laneTitle;

    // End the press's implicit grab before the menu publishes: the panel must
    // receive the following clicks, and the synchronous PointerUngrabbed
    // cancellation lands while no pending target exists yet.
    if (m_inputHost)
        m_inputHost->releasePointerGrab();
    m_menuHost->open(m_menuModel, scenePosition);
    if (!m_menuHost->isOpen())
        return;
    m_pendingMenu = std::move(target);
}

void AutomationCanvas::showAddLaneMenu(const QPointF &scenePosition)
{
    SongDocument *const document = m_page.document();
    songview::QuickPopupSession *const session = m_menuSession.data();
    if (!document || !session || !session->window())
        return;
    const int track = m_page.m_owner.selectionModel().primaryTrack();
    if (track < 0)
        return;
    const auto candidates = CCLanes::supportedControllers();
    std::vector<songview::QuickMenuItem> rows;
    std::vector<EditorAutomationRowId> hidden;
    for (const uint8_t controller : candidates) {
        const auto row = laneRow(track, controller);
        if (m_page.m_viewState.isLaneHidden(row) || m_page.model().findLane(track, controller) ||
            m_page.m_viewState.emptyLanes.find(row) != m_page.m_viewState.emptyLanes.cend())
            continue;
        rows.push_back(
            menuRow(int(Action::AddLaneBase) + controller, CCLanes::laneLabel(controller)));
    }
    for (const auto &row : m_page.m_viewState.hiddenLanes())
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == uint8_t(track))
            hidden.push_back(row);
    if (rows.empty())
        rows.push_back(disabledRow(tr("All parameters already have CC lanes")));
    if (!hidden.empty()) {
        rows.push_back(songview::QuickMenuItem::makeSeparator());
        rows.push_back(disabledRow(tr("Hidden CC lanes")));
        for (const auto &row : hidden)
            rows.push_back(
                menuRow(int(Action::ShowLaneBase) + row.controller,
                        tr("Show: %1 (hidden)").arg(CCLanes::laneLabel(row.controller))));
    }
    m_menuModel->setItems(std::move(rows));

    PendingMenu target;
    target.document = document;
    target.documentRevision = document->revision();
    target.track = track;

    // Same grab/focus handoff contract as the lane menu above.
    if (m_inputHost)
        m_inputHost->releasePointerGrab();
    m_menuHost->open(m_menuModel, scenePosition);
    if (!m_menuHost->isOpen())
        return;
    m_pendingMenu = std::move(target);
}

void AutomationCanvas::handleMenuAction(int actionId)
{
    if (!m_pendingMenu)
        return;
    // Consume before any command: the dispatch may rebuild rows (hide,
    // remove, add) and a target must never fire twice.
    const PendingMenu pending = std::move(*m_pendingMenu);
    m_pendingMenu.reset();
    // Keyboard continuity returns to the band before dispatch, but only when
    // no subsequent popup already owns the session. The focus return can
    // synchronously swap surfaces and run editing handlers, so it happens
    // BEFORE final validation: everything below judges the post-focus
    // document state.
    QPointer<AutomationCanvas> self(this);
    if (!m_menuSession || !m_menuSession->isOpen()) {
        if (m_inputHost)
            m_inputHost->requestFocus(Qt::PopupFocusReason);
    }
    if (!self)
        return; // The focus swap tore this canvas down.
    SongDocument *const document = m_page.document();
    if (!document || document != pending.document ||
        document->revision() != pending.documentRevision)
        return; // Stale document: no mutation, no announcement.

    if (actionId == int(Action::ClearTimeSelection)) {
        auto &model = m_page.m_owner.selectionModel();
        if (model.timeSelection().active()) {
            model.clearTimeSelection();
            requestSelectionQuickUpdate();
        }
        return;
    }
    if (actionId >= int(Action::ShowLaneBase)) {
        const uint8_t controller = uint8_t(actionId - int(Action::ShowLaneBase));
        const auto row = laneRow(pending.track, controller);
        if (pending.track >= 0 && m_page.m_viewState.unhideLane(row)) {
            m_page.publishViewState();
            rebuildRows();
            m_page.announce(tr("Showed the %1 CC lane").arg(CCLanes::laneLabel(controller)));
        }
        return;
    }
    if (actionId >= int(Action::AddLaneBase)) {
        const uint8_t controller = uint8_t(actionId - int(Action::AddLaneBase));
        if (pending.track >= 0) {
            m_page.addEmptyLane(pending.track, controller);
            m_page.announce(tr("Added %1 CC lane").arg(CCLanes::laneLabel(controller)));
        }
        return;
    }
    // Lane-menu commands re-resolve the captured handle and require the same
    // row: a remap landing between open and dispatch cannot mutate a
    // different lane.
    const auto *slot = resolveSlot(pending.lane);
    if (!slot || !slot->lane || slot->id != pending.rowId)
        return;
    NodeLane *lane = slot->lane;
    const auto maxTick = std::numeric_limits<uint64_t>::max();
    if (actionId == int(Action::Copy)) {
        m_clipboard = lane->points();
        m_page.announce(
            laneMenuKind(slot->isTempo(), pending.laneTitle, m_clipboard.size()).copiedMessage);
    } else if (actionId == int(Action::Paste)) {
        std::vector<NodePoint> replacement;
        replacement.reserve(m_clipboard.size());
        const int minimum = lane->minimumValue();
        const int maximum = lane->maximumValue();
        for (const auto &point : m_clipboard)
            replacement.push_back({point.tick, std::clamp(point.value, minimum, maximum)});
        lane->replaceSpan(0, maxTick, replacement);
        m_page.requestRefresh();
        m_page.announce(
            laneMenuKind(pending.rowId.kind == EditorAutomationRowKind::Tempo, pending.laneTitle)
                .pastedMessage);
    } else if (actionId == int(Action::Clear)) {
        lane->replaceSpan(0, maxTick, {});
        // Read the snapshot row from here on: replaceSpan's documentChanged
        // fan-out rebuilds m_nodeStack, invalidating slot pointers.
        if (pending.rowId.kind == EditorAutomationRowKind::ControlChange)
            m_page.addEmptyLane(int(pending.rowId.track), pending.rowId.controller);
        m_page.requestRefresh();
        if (const LaneMenuKind kind = laneMenuKind(
                pending.rowId.kind == EditorAutomationRowKind::Tempo, pending.laneTitle);
            kind.clearedMessage)
            m_page.announce(*kind.clearedMessage);
    } else if (actionId == int(Action::RemoveLane)) {
        const int track = int(slot->id.track);
        const uint8_t controller = slot->id.controller;
        const std::size_t writtenEventCount = document->lanePoints(track, controller).size();
        // A synthetic-only default row (engine-default node, no writes) takes
        // the plain remove body below: a Delete confirmation there would
        // count the projected node and then write nothing.
        if (writtenEventCount != 0) {
            // The QML confirmation opens on the shared canvas popup session;
            // activateRow has already closed the menu before this dispatch,
            // and openCcDeletePrompt pre-cancels any displaced session before
            // it publishes its guarded open-time snapshot (document,
            // revision, lane handle, exact row id, displayed title and event
            // count). Acceptance revalidates the whole guard through
            // immutable identity, so a rebuild landing meanwhile deletes
            // nothing.
            openCcDeletePrompt(pending.lane, writtenEventCount);
            return;
        }
        m_page.removeEmptyLane(track, controller);
        if (CoreTimeDefaults::isDefaultVisibleController(controller) &&
            m_page.m_viewState.hideLane(laneRow(track, controller))) {
            m_page.publishViewState();
            rebuildRows();
        }
        m_page.requestRefresh();
    } else if (actionId == int(Action::HideLane)) {
        if (m_page.m_viewState.hideLane(slot->id)) {
            m_page.publishViewState();
            rebuildRows();
            m_page.announce(tr("Hid the %1 CC lane").arg(pending.laneTitle));
        }
    } else if (actionId == int(Action::RangeAuto)) {
        m_page.setLaneRange(slot->id, 0);
    } else if (actionId == int(Action::Range16)) {
        m_page.setLaneRange(slot->id, 16);
    } else if (actionId == int(Action::Range32)) {
        m_page.setLaneRange(slot->id, 32);
    } else if (actionId == int(Action::Range64)) {
        m_page.setLaneRange(slot->id, 64);
    } else if (actionId == int(Action::Range127)) {
        m_page.setLaneRange(slot->id, 127);
    }
}
