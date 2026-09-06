#include "ui/songview/quick/timelinequickview.h"

#include "ui/songview.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/quick/timelineinputitem.h"

#include <algorithm>

namespace songview {

// Quick keyboard-routing bridge: the seam between normalized Quick key input
// and the shared song command policy. TimelineInputItem runs the attached
// interaction's restricted local handling first and consults the callback
// installed here only for keys it declines, so a consumed key executes
// exactly once and never reaches the scene-root fallback. Key events arrive
// as TimelineKeyInput values; semantic targeting lives in SongView's
// shared policy, never here.

bool TimelineQuickView::dispatchSongKey(const TimelineKeyInput &input)
{
    // QPointer guard: a destroyed SongView turns every key into a terminal
    // decline instead of a dangling call.
    return m_songView && m_songView->handleEditKey(input);
}

bool TimelineQuickView::dispatchSongKeyRelease(const TimelineKeyInput &input)
{
    return m_songView && m_songView->handleEditKeyRelease(input);
}

void TimelineQuickView::installKeyPolicyHandlers()
{
    // Each attached input receives one fresh guarded policy. Local handling
    // remains first; the policy routes only a declined normalized event.
    const TimelineKeyPolicy policy{
        [this](const TimelineKeyInput &input) { return dispatchSongKey(input); },
        [this](const TimelineKeyInput &input) { return dispatchSongKeyRelease(input); },
    };
    for (TimelineInputItem *item : m_inputItems) {
        if (item)
            item->setKeyPolicy(policy);
    }
    for (TimelineInputItem *item : m_gutterInputItems) {
        if (item)
            item->setKeyPolicy(policy);
    }
    for (TimelineInputItem *item : m_drawerChromeInputs) {
        if (item)
            item->setKeyPolicy(policy);
    }
}

void TimelineQuickView::clearKeyPolicyHandlers()
{
    for (TimelineInputItem *item : m_inputItems) {
        if (item)
            item->clearKeyPolicy();
    }
    for (TimelineInputItem *item : m_gutterInputItems) {
        if (item)
            item->clearKeyPolicy();
    }
    for (TimelineInputItem *item : m_drawerChromeInputs) {
        if (item)
            item->clearKeyPolicy();
    }
}

bool TimelineQuickView::gestureActive() const
{
    // Live reads only: primary inputs and drawer chrome each represent one
    // interaction; typed scrollbar roots publish their actual accepted press.
    const auto active = [](const TimelineInputItem *item) {
        const TimelineBandInteraction *const interaction = item ? item->interaction() : nullptr;
        return interaction && interaction->gestureActive();
    };
    const auto scrollbarActive = [](const QPointer<TimelineGestureScrollbar> &scrollbar) {
        return scrollbar && scrollbar->gestureActive();
    };
    return std::any_of(m_inputItems.cbegin(), m_inputItems.cend(), active) ||
           std::any_of(m_drawerChromeInputs.cbegin(), m_drawerChromeInputs.cend(), active) ||
           std::any_of(m_gestureScrollbars.cbegin(), m_gestureScrollbars.cend(), scrollbarActive);
}

void TimelineQuickView::discoverGestureScrollbars(QObject &root)
{
    for (TimelineGestureScrollbar *scrollbar : root.findChildren<TimelineGestureScrollbar *>()) {
        if (scrollbar)
            registerGestureScrollbar(*scrollbar);
    }
}

void TimelineQuickView::registerGestureScrollbar(TimelineGestureScrollbar &scrollbar)
{
    TimelineGestureScrollbar *const rawScrollbar = &scrollbar;
    const auto alreadyRegistered =
        [rawScrollbar](const QPointer<TimelineGestureScrollbar> &existing) {
            return existing.data() == rawScrollbar;
        };
    if (std::any_of(m_gestureScrollbars.cbegin(), m_gestureScrollbars.cend(), alreadyRegistered))
        return;

    m_gestureScrollbars.emplace_back(rawScrollbar);
    connect(rawScrollbar, &QObject::destroyed, this,
            [this, rawScrollbar] { forgetGestureScrollbar(rawScrollbar); });
}

void TimelineQuickView::forgetGestureScrollbar(TimelineGestureScrollbar *scrollbar)
{
    std::erase_if(m_gestureScrollbars,
                  [scrollbar](const QPointer<TimelineGestureScrollbar> &existing) {
                      return existing.isNull() || existing.data() == scrollbar;
                  });
}

void TimelineQuickView::cancelActiveGestures()
{
    // Each attached interaction receives exactly one semantic pointer
    // cancellation; PianoRoll deliberately leaves popup policy to its owner.
    for (TimelineInputItem *item : m_inputItems) {
        if (item && item->interaction())
            item->interaction()->cancelInteraction();
    }
    for (TimelineInputItem *item : m_drawerChromeInputs) {
        if (item && item->interaction())
            item->interaction()->cancelInteraction();
    }
    if (QQuickWindow *const window = quickWindow()) {
        if (QQuickItem *const mouseGrabber = window->mouseGrabberItem())
            mouseGrabber->ungrabMouse();
    }
}

bool TimelineQuickView::forwardUnhandledKey(int key, int modifiers, const QString &text,
                                            bool autoRepeat)
{
    // Scene-root fallback (TimelineCanvas Keys.onPressed) for keys unclaimed
    // by band, gutter, chrome and local-control items. Only unaccepted events
    // arrive here, so a command consumed on the band path can never run
    // twice; a declined policy key stays an ignored no-op.
    return dispatchSongKey(
        TimelineKeyInput{key, static_cast<Qt::KeyboardModifiers>(modifiers), text, autoRepeat});
}

bool TimelineQuickView::forwardUnhandledKeyRelease(int key, int modifiers, const QString &text,
                                                   bool autoRepeat)
{
    return dispatchSongKeyRelease(
        TimelineKeyInput{key, static_cast<Qt::KeyboardModifiers>(modifiers), text, autoRepeat});
}

} // namespace songview
