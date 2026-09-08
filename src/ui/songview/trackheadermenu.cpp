#include "ui/songview/trackheadermodel.h"

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"

#include <QQuickWindow>

#include <utility>

namespace songview {

// The header context menu is TrackHeaderModel's slice of the shared canvas
// popup session: a persistent typed QuickMenuHost/QuickMenuModel pair opened
// from the band interaction's right-press route, which bridges the press to
// scene coordinates before this menu accepts it. Every row maps to one of the
// real header operations; this file owns only the menu lifecycle — the
// commands still travel through the existing SongView primitives
// (queueHeaderMutation for voice/duplicate/delete, direct reveal and rename).

void TrackHeaderModel::ensureHeaderMenuAdapters()
{
    if (m_headerMenuHost)
        return;
    m_headerMenuHost = new QuickMenuHost(this);
    m_headerMenuModel = new QuickMenuModel(this);
    connect(m_headerMenuModel, &QuickMenuModel::activated, this,
            &TrackHeaderModel::handleHeaderMenuAction);
    // Any teardown of our session ownership (outside press, Escape, resize,
    // foreign replacement, window deactivation) drops the pending target.
    connect(m_headerMenuHost, &QuickMenuHost::cancelled, this,
            [this] { m_pendingHeaderMenu.reset(); });
}

void TrackHeaderModel::setPopupSession(QuickPopupSession *session)
{
    if (m_headerMenuSession == session)
        return;
    // The host cancels its active menu on the displaced session first; the
    // stored pointer follows so a later open cannot target a dead session.
    m_headerMenuHost->setPopupSession(session);
    m_headerMenuSession = session;
}

std::vector<QuickMenuItem>
TrackHeaderModel::buildHeaderMenuItems(const SongDocument &document) const
{
    // Same rows, order, and labels as the former native menu; build-time
    // enablement only, because any structural change while the menu is open
    // cancels it through cancelTransientState before the rows could drift.
    const auto row = [](HeaderMenuAction action, QString text) {
        QuickMenuItem item;
        item.id = static_cast<int>(action);
        item.text = std::move(text);
        return item;
    };
    std::vector<QuickMenuItem> rows;
    rows.reserve(5);
    rows.push_back(row(HeaderMenuAction::ChangeVoice, SongView::tr("Change voice...")));
    rows.push_back(
        row(HeaderMenuAction::ShowVoiceInVoicegroup, SongView::tr("Show voice in voicegroup")));
    rows.push_back(row(HeaderMenuAction::RenameTrack, SongView::tr("Rename track...")));
    QuickMenuItem duplicate =
        row(HeaderMenuAction::DuplicateTrack, SongView::tr("Duplicate track"));
    duplicate.enabled = document.canAddTrack();
    rows.push_back(std::move(duplicate));
    rows.push_back(row(HeaderMenuAction::DeleteTrack, SongView::tr("Delete track")));
    return rows;
}

QPointF TrackHeaderModel::headerMenuScenePosition(const QPointF &globalPosition) const
{
    QuickPopupSession *const session = m_headerMenuSession.data();
    QQuickWindow *const window = session ? session->window() : nullptr;
    return window ? window->mapFromGlobal(globalPosition) : QPointF();
}

void TrackHeaderModel::showContextMenu(int track, const QPointF &scenePosition)
{
    SongDocument *const document = m_owner.document();
    QuickPopupSession *const session = m_headerMenuSession.data();
    if (!document || !session)
        return;

    ensureHeaderMenuAdapters();
    m_headerMenuModel->setItems(buildHeaderMenuItems(*document));

    // Snapshot the guarded open-time target first, but publish it only
    // after open()'s implicit cancellation of a displaced session has
    // completed: no callback can observe a half-published target, and an
    // open failure publishes nothing. The snapshot travels through the
    // session close until activation consumes it; cancellation clears it.
    PendingHeaderMenu target;
    target.document = document;
    target.documentRevision = document->revision();
    target.track = track;

    m_headerMenuHost->open(m_headerMenuModel, scenePosition);
    if (!m_headerMenuHost->isOpen())
        return;
    m_pendingHeaderMenu = std::move(target);
}

void TrackHeaderModel::handleHeaderMenuAction(int actionId)
{
    if (!m_pendingHeaderMenu)
        return;
    // Consume before any command: the dispatch may queue a header mutation
    // that rebuilds this model, and a target must never fire twice.
    const PendingHeaderMenu target = std::move(*m_pendingHeaderMenu);
    m_pendingHeaderMenu.reset();
    SongDocument *const document = m_owner.document();
    if (!document || document != target.document || document->revision() != target.documentRevision)
        return; // Stale raw index: no reveal, no queued mutation, no rename.

    // The activation close drops Quick focus without restoration, so hand
    // keyboard continuity back to the header band before dispatch: the
    // rename editor, the voice picker, and the revealed voicegroup dock then
    // intentionally take the final focus, while duplicate/delete keep the
    // header's editing keys. A popup opened from a cancellation callback
    // wins and must not be refocused over.
    if (!m_headerMenuSession || !m_headerMenuSession->isOpen())
        m_owner.focusTimelineBand(TimelineBand::TrackHeaders, Qt::OtherFocusReason);

    QPointer<SongView> owner(&m_owner);
    switch (static_cast<HeaderMenuAction>(actionId)) {
    case HeaderMenuAction::ChangeVoice:
        // The menu session is already closed; the queued mutation opens the
        // async voice picker on the next event-loop turn. The queued lambda
        // re-checks the captured document identity and revision so a remap
        // landing between pick and execution cannot reinterpret the raw index.
        m_owner.queueHeaderMutation([owner, snapshot = target] {
            if (!owner || owner->document() != snapshot.document || !snapshot.document ||
                snapshot.document->revision() != snapshot.documentRevision)
                return;
            owner->editTrackVoice(snapshot.track);
        });
        break;
    case HeaderMenuAction::ShowVoiceInVoicegroup:
        m_owner.revealTrackVoice(target.track);
        break;
    case HeaderMenuAction::RenameTrack:
        // Synchronous post-close: the in-band rename editor adopts focus
        // from the renamingTrack change through its visible flip.
        beginRename(target.track);
        break;
    case HeaderMenuAction::DuplicateTrack:
        m_owner.queueHeaderMutation([owner, snapshot = target] {
            if (!owner || owner->document() != snapshot.document || !snapshot.document ||
                snapshot.document->revision() != snapshot.documentRevision)
                return;
            owner->duplicateTrack(snapshot.track);
        });
        break;
    case HeaderMenuAction::DeleteTrack:
        m_owner.queueHeaderMutation([owner, snapshot = target] {
            if (!owner || owner->document() != snapshot.document || !snapshot.document ||
                snapshot.document->revision() != snapshot.documentRevision)
                return;
            owner->deleteTrack(snapshot.track);
        });
        break;
    }
}

void TrackHeaderModel::cancelHeaderMenuWithoutFocus()
{
    m_pendingHeaderMenu.reset();
    // Only end a session this menu still owns: a foreign popup (the voice
    // picker, a prompt) must survive a header-model rebuild.
    if (m_headerMenuSession && m_headerMenuSession->owns(m_headerMenuHost))
        m_headerMenuSession->cancel(/*restoreFocus=*/false);
}

} // namespace songview
