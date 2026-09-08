// Window lifecycle for the Quick timeline coordinator: sole ownership of the
// unhosted QQuickView, exactly-once embedding transfer, idempotent teardown,
// and the window event ports (resize/DPR/screen publication, focus
// bridging, hide/deactivate cancellation, focus-less key routing). Scene
// publication and syncing live in timelinequickview.cpp; the key-policy
// bridge in timelinequickview_keyrouting.cpp; the roll scene builders in
// timelinequickview_pianoroll.cpp.

#include "ui/songview/quick/timelinequickview.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/trackheadermodel.h"

#include <QKeyEvent>
#include <QQuickView>
#include <QUrl>
#include <algorithm>

namespace songview {

TimelineQuickView::~TimelineQuickView()
{
    detachWindow();
}

std::unique_ptr<QQuickWindow> TimelineQuickView::takeWindowForEmbedding()
{
    // Exactly-once one-way transfer: the external container sole-owns the
    // window from here on. The QPointer borrow keeps publishing into the
    // same scene, and detachWindow() later unbinds its content without
    // deleting it. This never emits windowAboutToDetach(): the window stays
    // valid throughout.
    return std::move(m_quickView);
}

void TimelineQuickView::detachWindow()
{
    // Final, once per lifetime: SongView's destructor detaches first and this
    // destructor repeats safely; also a no-op once an external container has
    // destroyed a transferred window. A windowAboutToDetach listener may
    // re-enter while the borrow is still live — the nested call returns here
    // without re-emitting or re-running teardown.
    if (m_detachStarted)
        return;
    m_detachStarted = true;
    if (!m_view && !m_popupSession)
        return;

    m_layoutTimer.stop();
    m_flushTimer.stop();

    if (m_popupSession)
        m_popupSession->cancel(false);
    // Transient Quick-scene state cancels while every input item still
    // exists; the wiring then detaches exactly once per item.
    cancelActiveGestures();
    clearKeyPolicyHandlers();
    m_gestureScrollbars.clear();
    for (TimelineInputItem *item : m_drawerChromeInputs) {
        if (item)
            item->setInteraction(nullptr);
    }
    for (TimelineInputItem *item : m_gutterInputItems) {
        if (item)
            item->setInteraction(nullptr);
    }
    for (TimelineInputItem *item : m_inputItems) {
        if (item)
            item->setInteraction(nullptr);
    }
    if (m_eventListInput) {
        m_eventListInput->clearKeyPolicy();
        m_eventListInput->setInteraction(nullptr);
    }
    m_eventListInteraction.reset();

    // Session bindings release while the domain models are alive; the
    // session itself dies synchronously so popupSession() turns null here.
    if (m_eventList)
        m_eventList->setPopupSession(nullptr);
    if (m_roll)
        m_roll->setPopupSession(nullptr);
    if (m_trackHeaders)
        m_trackHeaders->setPopupSession(nullptr);
    if (m_automation && m_automation->canvas())
        m_automation->canvas()->setPopupSession(nullptr);
    if (m_voiceChanges)
        m_voiceChanges->setPopupSession(nullptr);
    delete m_popupSession;
    m_popupSession = nullptr;

    // Raw QML borrows clear before the unload, then the QML tree unloads
    // while the context properties still point at live models.
    m_items.fill(nullptr);
    m_chromeItems.fill(nullptr);
    m_inputItems.fill(nullptr);
    m_gutterInputItems.fill(nullptr);
    m_drawerChromeInputs.fill(nullptr);
    m_eventListInput.clear();
    m_root.clear();
    if (m_view)
        m_view->setSource(QUrl{});

    // Native attachments clear while the window is still valid — never
    // during takeWindowForEmbedding().
    if (m_view)
        emit windowAboutToDetach();

    // Detach event surveillance before the window tears down: the QWindow
    // destructor hides/destroys through setVisible(), which would otherwise
    // re-enter eventFilter() against a partially destroyed QQuickWindow
    // (cancelActiveGestures -> mouseGrabberItem -> mousePointData). Removal
    // also covers the hosted path, where the transferred window outlives
    // this coordinator and must not call back into it at container teardown.
    QQuickView *window = m_quickView ? m_quickView.get() : m_view.data();
    if (window) {
        window->removeEventFilter(this);
        disconnect(window, nullptr, this, nullptr);
    }
    if (m_quickView)
        m_quickView.reset(); // unhosted: synchronous window destruction
    m_view.clear();          // hosted: unbind; the embedding container deletes it
}

QQuickItem *TimelineQuickView::rootObject() const
{
    return m_root.data();
}

QQuickWindow *TimelineQuickView::quickWindow() const
{
    return m_view.data();
}

QuickPopupSession *TimelineQuickView::popupSession() const noexcept
{
    return m_popupSession;
}

qreal TimelineQuickView::quickDevicePixelRatio() const
{
    return m_view ? m_view->effectiveDevicePixelRatio() : 1.0;
}

bool TimelineQuickView::eventFilter(QObject *watched, QEvent *event)
{
    QQuickWindow *const window = m_view.data();
    if (watched != window)
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::Resize:
        // The window is the canonical viewport: surface resizes reframe the
        // camera and the band layout, so SongView reruns its former resize
        // choreography while this view republishes its stored layout.
        emit viewportChanged();
        scheduleTimelineBandLayoutPublication();
        break;
    case QEvent::DevicePixelRatioChange:
        // Fractional scale changes move quickDevicePixelRatio(); the same
        // publication keeps physical-pixel math converged. Screen moves
        // arrive through the screenChanged connection.
        emit viewportChanged();
        scheduleTimelineBandLayoutPublication();
        break;
    // No FocusIn handling by design: Qt clears the scene's activeFocusItem
    // while the window is inactive, so any retarget here fires with a null
    // focus item and steals from scoped editors (rename, value prompts) that
    // Qt restores itself on activation. Explicit focusBand() and
    // focusActiveSurface() callers remain the only focus drivers.
    case QEvent::Hide:
    case QEvent::WindowDeactivate:
        // Ported SongView widget semantics: a hidden or deactivated surface
        // cancels every live Quick interaction exactly once. Per-item
        // mouseUngrabEvent() already covers window ungrabs.
        cancelActiveGestures();
        break;
    case QEvent::KeyPress:
    case QEvent::KeyRelease: {
        // Ported SongView widget-key semantics: with no Quick item holding
        // active focus, the shared song policy claims the key. Focused
        // delivery travels item → policy → scene-root fallback instead, so
        // either way a key is handled exactly once.
        if (window->activeFocusItem())
            break;
        const auto *keyEvent = static_cast<QKeyEvent *>(event);
        const TimelineKeyInput keyInput{
            .key = keyEvent->key(),
            .modifiers = keyEvent->modifiers(),
            .text = keyEvent->text(),
            .autoRepeat = keyEvent->isAutoRepeat(),
        };
        return event->type() == QEvent::KeyPress ? dispatchSongKey(keyInput)
                                                 : dispatchSongKeyRelease(keyInput);
    }
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

} // namespace songview
