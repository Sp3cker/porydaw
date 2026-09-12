// ------------------------------------------------ AutomationCanvas CC-lane delete confirmation

#include "ui/editordrawer/automationcanvas.h"

#include <limits>
#include <utility>

#include <QGuiApplication>
#include <QMetaObject>
#include <QUrl>
#include <QVariantMap>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/quick/promptappearance.h"
#include "ui/songview/quick/quickpopupsession.h"

// The lane menu's "Delete automation events" command on a parameter that
// still carries written events opens this confirmation on the shared canvas
// popup session instead of a native modal: one QML form (CcDeleteConfirm.qml)
// bound to this canvas as its bridge. The open path publishes the guarded
// snapshot before openForm, so the QML getters read a complete prompt during
// component creation, and never carries a lane pointer: acceptance
// revalidates document, revision, lane handle, and exact row id through the
// snapshot identity before running the same replaceSpan event deletion the
// legacy modal ran, so a stale prompt deletes nothing. The parameter label
// itself always survives; only its written events go.

QString AutomationCanvas::ccDeletePromptTitle() const
{
    return tr("Delete automation events");
}

QString AutomationCanvas::ccDeletePromptMessage() const
{
    if (!m_pendingCcDeletePrompt)
        return {};
    const PendingCcDeletePrompt &pending = *m_pendingCcDeletePrompt;
    return tr("Delete the %1 parameter's %2 written events? The %1 parameter remains.")
        .arg(pending.laneTitle)
        .arg(pending.eventCount);
}

QVariantMap AutomationCanvas::ccDeletePromptAppearance() const
{
    return songview::promptDialogAppearance(QGuiApplication::font());
}

bool AutomationCanvas::openCcDeletePrompt(LaneHandle handle, std::size_t writtenEventCount)
{
    SongDocument *const document = m_page.document();
    songview::QuickPopupSession *const session = m_menuSession.data();
    const auto *slot = resolveSlot(handle);
    if (!document || !session || !session->window() || !slot || !slot->lane)
        return false;
    // writtenEventCount comes from the caller's show-time document-written
    // query: adapter points() projects a synthetic tick-0 engine node for
    // Volume and Pan, which is neither deletable nor counted here. Revision
    // equality revalidated after the cancellation below keeps that captured
    // count truthful.
    if (writtenEventCount == 0)
        return false;

    // Capture the whole immutable guarded snapshot before any cancellation:
    // a displaced session's cleanup callbacks can re-enter document state,
    // so no raw document or slot pointer is held or dereferenced across it.
    PendingCcDeletePrompt pending;
    pending.document = document;
    pending.documentRevision = document->revision();
    pending.lane = handle;
    pending.rowId = slot->id;
    pending.laneTitle = slot->lane->title();
    pending.eventCount = writtenEventCount;

    // Replacement ends the active shared-popup session before this bridge
    // publishes a new guarded target: its cancellation callbacks cannot
    // observe or affect the new prompt.
    session->cancel(/*restoreFocus=*/false);
    cancelCcDeletePromptWithoutFocus();

    // That cancellation was a re-entry point: revalidate the snapshot against
    // live state before anything is published. Nothing was emitted yet, so a
    // stale target simply refuses to open.
    SongDocument *const current = m_page.document();
    const auto *settled = resolveSlot(handle);
    if (!current || current != pending.document ||
        current->revision() != pending.documentRevision || !settled || !settled->lane ||
        settled->id != pending.rowId)
        return false;

    m_pendingCcDeletePrompt = std::move(pending);
    // Publish before openForm: the QML form's property getters run while the
    // component is created, before the call returns.
    emit ccDeletePromptChanged();
    QObject::disconnect(m_ccDeletePromptCancellation);
    m_ccDeletePromptCancellation =
        connect(session, &songview::QuickPopupSession::cancelled, this,
                [this](bool restoreFocus) { clearCcDeletePrompt(restoreFocus); });
    if (!session->openForm(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/CcDeleteConfirm.qml")),
                           this)) {
        clearCcDeletePrompt(/*restoreFocus=*/true);
        return false;
    }
    return true;
}

void AutomationCanvas::acceptCcDeletePrompt()
{
    const std::optional<PendingCcDeletePrompt> pending =
        std::exchange(m_pendingCcDeletePrompt, std::nullopt);
    if (!pending)
        return;
    // Never expose a pending target while mutating the document.
    QObject::disconnect(m_ccDeletePromptCancellation);
    m_ccDeletePromptCancellation = {};
    emit ccDeletePromptChanged();
    // Close only the form this canvas still owns; a foreign popup survives.
    if (songview::QuickPopupSession *const session = m_menuSession.data();
        session && session->owns(this)) {
        session->close();
    }

    SongDocument *const document = m_page.document();
    const auto *slot = resolveSlot(pending->lane);
    if (!document || document != pending->document ||
        document->revision() != pending->documentRevision || !slot || !slot->lane ||
        slot->id != pending->rowId)
        return; // Stale request: document, lane, or row changed since open.

    // replaceSpan's documentChanged fan-out rebuilds m_nodeStack
    // synchronously, so nothing below may touch slot or lane state again —
    // the snapshot identity is the only surviving target description.
    slot->lane->replaceSpan(0, CoreTimeDefaults::kNoTick, {});
    m_page.requestRefresh();

    // Band focus returns only when no popup owns the session now: a popup
    // opened meanwhile keeps focus.
    if (!m_menuSession || !m_menuSession->isOpen()) {
        if (m_inputHost)
            m_inputHost->requestFocus(Qt::PopupFocusReason);
    }
}

void AutomationCanvas::cancelCcDeletePrompt()
{
    if (!m_pendingCcDeletePrompt)
        return;
    songview::QuickPopupSession *const session = m_menuSession.data();
    const bool ownsSession = session && session->owns(this);
    if (ownsSession)
        session->cancel();
    // A session this canvas no longer owns still drops its pending target,
    // but focus stays with whoever owns the session now.
    if (m_pendingCcDeletePrompt)
        clearCcDeletePrompt(ownsSession);
}

void AutomationCanvas::clearCcDeletePrompt(bool restoreFocus)
{
    m_pendingCcDeletePrompt.reset();
    QObject::disconnect(m_ccDeletePromptCancellation);
    m_ccDeletePromptCancellation = {};
    emit ccDeletePromptChanged();
    // Same restoration gate as the menu dispatch head: only when no popup
    // (ours already ended, or a foreign replacement) holds the session.
    if (restoreFocus && (!m_menuSession || !m_menuSession->isOpen())) {
        if (m_inputHost)
            m_inputHost->requestFocus(Qt::PopupFocusReason);
    }
}

void AutomationCanvas::cancelCcDeletePromptWithoutFocus()
{
    if (!m_pendingCcDeletePrompt)
        return;
    songview::QuickPopupSession *const session = m_menuSession.data();
    const bool ownsSession = session && session->owns(this);
    m_pendingCcDeletePrompt.reset();
    QObject::disconnect(m_ccDeletePromptCancellation);
    m_ccDeletePromptCancellation = {};
    emit ccDeletePromptChanged();
    if (ownsSession)
        session->cancel(/*restoreFocus=*/false);
}
