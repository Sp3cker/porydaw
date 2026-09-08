#include "ui/editordrawer/voicechangearea/voicechangearea.h"

#include <algorithm>
#include <optional>
#include <utility>
#include <vector>

#include <QQuickWindow>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/timecamera.h"

namespace {

songview::QuickMenuItem menuRow(int id, QString text)
{
    songview::QuickMenuItem item;
    item.id = id;
    item.text = std::move(text);
    return item;
}

using Action = VoiceChangeArea::VoiceMenuAction;

} // namespace

// The voice menu is VoiceChangeArea's slice of the shared canvas popup
// session: one persistent typed QuickMenuHost/QuickMenuModel pair serves the
// context menu, and the same captured-target seam feeds the double-click
// picker. This file owns that seam — guarded capture, guarded open, dispatch,
// and the picker handoff. Every command travels through the existing
// SongView/SongDocument primitives, re-resolved and revalidated at dispatch,
// so a stale target writes nothing.

void VoiceChangeArea::ensureMenuAdapters()
{
    if (m_menuHost)
        return;
    m_menuHost = new songview::QuickMenuHost(this);
    m_menuModel = new songview::QuickMenuModel(this);
    connect(m_menuModel, &songview::QuickMenuModel::activated, this,
            &VoiceChangeArea::handleMenuAction);
    // Any teardown of this menu's session ownership (outside press, Escape,
    // resize, foreign replacement, window deactivation) drops the pending
    // target.
    connect(m_menuHost, &songview::QuickMenuHost::cancelled, this,
            [this] { m_pendingMenu.reset(); });
}

void VoiceChangeArea::setPopupSession(songview::QuickPopupSession *session)
{
    if (m_menuSession == session)
        return;
    // Session replacement is a hard cancellation for any picker this band
    // handed off on the old session. Self and the serial advance before the
    // scoped cancel: the cascades can end this band, and a nested
    // replacement or hard cancel must win over this continuation.
    QPointer<VoiceChangeArea> self(this);
    ++m_pickerSerial;
    const uint64_t pickerSerial = m_pickerSerial;
    // Pinned before any callback; a caller-passed nullptr is intentional.
    const QPointer<songview::QuickPopupSession> target(session);
    m_owner.cancelVoicePickerFor(*this);
    if (!self || m_pickerSerial != pickerSerial)
        return;
    // A replaced session must not carry this band's pending menu: drop it
    // against the old session, ending only a form this band still owns.
    cancelMenuWithoutFocus();
    if (!self || m_pickerSerial != pickerSerial)
        return;
    ensureMenuAdapters();
    // A live incoming session that died in the cascades lost to a newer
    // operation and must not be bound.
    if (session && !target)
        return;
    // The host cancels its active menu on the displaced session first; the
    // stored pointer follows so a later open cannot target a dead session.
    m_menuHost->setPopupSession(session);
    if (!self || m_pickerSerial != pickerSerial || (session && !target))
        return;
    m_menuSession = session;
}

QPointF VoiceChangeArea::menuScenePosition(const QPointF &globalPosition) const
{
    songview::QuickPopupSession *const session = m_menuSession.data();
    QQuickWindow *const window = session ? session->window() : nullptr;
    return window ? window->mapFromGlobal(globalPosition) : QPointF();
}

void VoiceChangeArea::cancelMenuWithoutFocus()
{
    m_pendingMenu.reset();
    // Only end a session this band still owns: a foreign popup (the voice
    // picker, another band's menu) must survive band teardown.
    if (m_menuSession && m_menuSession->owns(m_menuHost))
        m_menuSession->cancel(/*restoreFocus=*/false);
}

std::optional<VoiceChangeArea::PendingVoiceMenu> VoiceChangeArea::captureTargetAt(qreal plotX) const
{
    SongDocument *const document = m_owner.document();
    if (!document || m_engineTrack < 0)
        return std::nullopt;
    PendingVoiceMenu target;
    target.document = document;
    target.revision = document->revision();
    target.track = m_engineTrack;
    DocLanePoint markerPoint;
    if (voiceMarkerAt(plotX, &markerPoint)) {
        target.marker = markerPoint;
        target.tick = markerPoint.tick;
        target.initialVoice = markerPoint.value;
    } else {
        // The logical snapped tick is the target: nothing re-hits the press
        // plot x, so a camera move after capture cannot drift it.
        const double rawTick = std::max(0.0, m_camera.tickAtContentX(std::max<qreal>(0.0, plotX)));
        target.tick = m_grid.snapTick(rawTick, false);
        target.initialVoice = voiceSlotAt(target.tick);
    }
    return target;
}

void VoiceChangeArea::showPicker(qreal plotX)
{
    // Direct entry: the double-click captures the same guarded target a menu
    // pick hands over, then delegates to the shared picker path.
    const std::optional<PendingVoiceMenu> target = captureTargetAt(plotX);
    if (target)
        openPickerForTarget(*target);
}

void VoiceChangeArea::showContextMenu(qreal plotX, const QPointF &globalPosition)
{
    songview::QuickPopupSession *const session = m_menuSession.data();
    if (!session || !session->window())
        return;
    // Capture first: the target is fixed from live state before any
    // signal-producing step, so a focus swap or open side effect can neither
    // recapture a different tick nor run on a torn-down band.
    std::optional<PendingVoiceMenu> captured = captureTargetAt(plotX);
    if (!captured)
        return;

    // Same rows, order, and labels as the former native menu.
    std::vector<songview::QuickMenuItem> rows;
    if (captured->marker) {
        rows.reserve(2);
        rows.push_back(menuRow(int(Action::ChangeVoice), tr("Change voice")));
        rows.push_back(menuRow(int(Action::DeleteMarker), tr("Delete")));
    } else {
        rows.push_back(menuRow(int(Action::InsertVoiceChange), tr("Insert voice change")));
    }

    // From here every step can re-enter this band synchronously, and any of
    // them can tear the band down — the document can outlive it — so a self
    // guard is checked at every callback boundary.
    QPointer<VoiceChangeArea> self(this);
    // Keyboard continuity: the band takes focus only after capture. The swap
    // is signal-producing (editing handlers can mutate the document or
    // track), so the captured target and the press's host are revalidated
    // before anything opens.
    if (m_inputHost)
        m_inputHost->requestFocus(Qt::MouseFocusReason);
    if (!self)
        return;
    SongDocument *const settled = m_owner.document();
    if (!settled || settled != captured->document || settled->revision() != captured->revision ||
        primaryTrack() != captured->track || !m_inputHost)
        return;
    m_menuModel->setItems(std::move(rows));
    if (!self)
        return;

    // End the press's implicit grab before the menu publishes: the panel
    // must receive the following clicks, and the synchronous PointerUngrabbed
    // cancellation lands before any pending target exists — the opening
    // press's paired release can neither pick a row nor leak into the band.
    if (m_inputHost)
        m_inputHost->releasePointerGrab();
    if (!self)
        return;
    // A synchronous callback above (focus swap, model reset, grab release)
    // may have let a foreign popup take the session: its newer publication
    // wins, and this open must not displace it.
    if (m_menuSession != session || (m_menuSession->isOpen() && !m_menuSession->owns(m_menuHost)))
        return;
    m_menuHost->open(m_menuModel, menuScenePosition(globalPosition));
    if (!self)
        return;
    if (!m_menuHost->isOpen())
        return;
    // Revalidate across the open's remaining synchronous callbacks: the
    // session must still be the one this menu opened on and still owned by
    // this band's host, so a displaced publication is never overwritten by
    // this continuation. Document identity, revision, the document-facing
    // track, and the attached host must all still hold before anything is
    // published. A stale open ends only a menu this band still owns, never
    // a foreign popup.
    if (!m_menuSession || m_menuSession != session || !m_menuSession->owns(m_menuHost))
        return;
    SongDocument *const live = m_owner.document();
    if (!live || live != captured->document || live->revision() != captured->revision ||
        primaryTrack() != captured->track || !m_inputHost) {
        cancelMenuWithoutFocus();
        return;
    }
    m_pendingMenu = std::move(*captured);
}

void VoiceChangeArea::openPickerForTarget(const PendingVoiceMenu &target)
{
    // Freshness fence for both callers (double-click and menu dispatch): the
    // captured target must still match the live document-facing state before
    // the picker's guarded open. SongView snapshots its pending after its
    // internal cancellations and returns focus to the origin band before its
    // acceptance guard, so the callback below re-judges the post-focus
    // document state.
    SongDocument *const live = m_owner.document();
    if (!live || live != target.document || primaryTrack() != target.track ||
        live->revision() != target.revision)
        return;
    // Serial snapshot taken before the signal-producing open: acceptance is
    // only live while nothing hard-cancelled this band's handed-off picker.
    const uint64_t pickerSerial = m_pickerSerial;
    QPointer<VoiceChangeArea> self(this);
    m_owner.requestVoicePicker(
        target.marker ? tr("Change voice") : tr("Insert voice change"),
        std::max(0, target.initialVoice), this,
        [this, self, target, pickerSerial](int selectedVoice) {
            // Self first: a late acceptance must not dereference this band
            // through the raw pointer before it is proven alive.
            if (!self)
                return;
            SongDocument *const document = m_owner.document();
            if (!document || document != target.document || primaryTrack() != target.track ||
                document->revision() != target.revision)
                return;
            // Irreversible surface fence: the serial advanced at every hard
            // cancellation boundary (hidden, window deactivated, detached,
            // session replaced). A hide→show or detach→reattach before
            // acceptance cannot resurrect the captured pick — a current-
            // state check alone would pass again after the band returns.
            if (m_pickerSerial != pickerSerial)
                return;
            DocLanePoint existing;
            if (document->findLanePoint(target.track, DOC_CC_VOICE, target.tick, &existing)) {
                if (existing.value == selectedVoice)
                    return;
                document->moveLanePoints(
                    {{target.track, DOC_CC_VOICE, existing, target.tick, selectedVoice}});
            } else {
                document->addLanePoint(target.track, DOC_CC_VOICE, target.tick, selectedVoice);
            }
            // The mutation's synchronous document fan-out can tear this band
            // down before the refresh runs.
            if (!self)
                return;
            m_owner.refreshAllDrawerPages();
        },
        songview::TimelineBand::VoiceChanges);
}

void VoiceChangeArea::handleMenuAction(int actionId)
{
    if (!m_pendingMenu)
        return;
    // Consume before any command: the dispatch may open the voice picker and
    // a target must never fire twice.
    const PendingVoiceMenu pending = std::move(*m_pendingMenu);
    m_pendingMenu.reset();
    // Keyboard continuity returns to the band before dispatch, but only when
    // no subsequent popup already owns the session. The focus return can
    // synchronously swap surfaces and run editing handlers, so it happens
    // BEFORE final validation: everything below judges the post-focus
    // document state.
    QPointer<VoiceChangeArea> self(this);
    if (!m_menuSession || !m_menuSession->isOpen()) {
        if (m_inputHost)
            m_inputHost->requestFocus(Qt::PopupFocusReason);
    }
    if (!self)
        return; // The focus swap tore this band down.
    SongDocument *const document = m_owner.document();
    if (!document || document != pending.document || primaryTrack() != pending.track ||
        document->revision() != pending.revision)
        return; // Stale target: no mutation, no picker.

    switch (static_cast<VoiceMenuAction>(actionId)) {
    case VoiceMenuAction::ChangeVoice:
    case VoiceMenuAction::InsertVoiceChange:
        // A late dispatch must not displace a popup a foreign owner opened
        // across the focus swap: the picker needs a free session, and a
        // taken one makes this pick stale.
        if (m_menuSession && m_menuSession->isOpen())
            return;
        // The captured target — tick, marker, initial voice — feeds the
        // picker directly; nothing re-hits the stored press position.
        openPickerForTarget(pending);
        return;
    case VoiceMenuAction::DeleteMarker: {
        // Deletion resolves through the document's canonical lookup at the
        // captured tick, so the removed occurrence is the one the document
        // holds now, never a stale copy.
        DocLanePoint currentMarker;
        if (!document->findLanePoint(pending.track, DOC_CC_VOICE, pending.tick, &currentMarker))
            return;
        document->deleteLanePoints(pending.track, DOC_CC_VOICE, {currentMarker});
        // Deletion's synchronous documentChanged fan-out can tear this band
        // down before the refresh runs.
        if (!self)
            return;
        m_owner.refreshAllDrawerPages();
        return;
    }
    }
}
