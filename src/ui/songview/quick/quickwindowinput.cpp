#include "ui/songview/quick/quickwindowinput.h"

#include "ui/songview/quick/timelinequickview.h"

#include <QEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQuickWindow>

namespace songview {

QuickWindowInput &QuickWindowInput::forWindow(QQuickWindow &window)
{
    // Child lookup doubles as the idempotence guard: the arbiter is created
    // exactly once per window and lives until the window dies, so repeated
    // lookups — attach, reassociation, detach — always reach one instance.
    if (auto *const existing = window.findChild<QuickWindowInput *>())
        return *existing;
    return *new QuickWindowInput(window);
}

QuickWindowInput::QuickWindowInput(QQuickWindow &window) : QObject(&window), m_window(&window)
{
    m_window->installEventFilter(this);
    // Window deactivation drops armed releases: a cancelled grab must not
    // deliver its release as a click into whatever gains focus next. The
    // signal carries no argument, so the receiver queries live state.
    connect(m_window, &QWindow::activeChanged, this, [this] {
        if (!m_window->isActive())
            m_swallowedReleaseButtons = 0;
    });
}

TimelineQuickView *QuickWindowInput::selectedScene() const noexcept
{
    // Out of line so QPointer's static_cast to QObject* sees the complete
    // TimelineQuickView type; the header keeps only the forward declaration.
    return m_selectedScene.data();
}

void QuickWindowInput::setSelectedScene(TimelineQuickView *scene)
{
    // Hosts select explicitly; attaching another scene never broadcasts or
    // selects it. A scene's detach clears only its own association; a
    // sibling selected meanwhile keeps its selection.
    if (m_selectedScene.data() == scene)
        return;
    m_selectedScene = scene;
    // Swallowed-release state is window-owned and deliberately survives
    // selection changes and detach: a close-flow cancel arms the swallow,
    // then drops this scene's routing before the dismissal release arrives,
    // which the next page must receive cleanly.
}

void QuickWindowInput::swallowRelease(Qt::MouseButton button)
{
    // Qt::MouseButton values are already single-bit flags, so the stored
    // mask is the button bounded by the button mask.
    if (button == Qt::NoButton)
        return;
    m_swallowedReleaseButtons |= int(button) & Qt::MouseButtonMask;
}

bool QuickWindowInput::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != m_window)
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::MouseButtonPress:
        // A genuinely newer press supersedes any abandoned sequence: its own
        // release must be delivered normally, never eaten by a stale armed
        // swallow for the same button.
        m_swallowedReleaseButtons &= ~int(static_cast<QMouseEvent *>(event)->button());
        break;
    case QEvent::MouseButtonRelease: {
        // Consume an armed release exactly once, before any item or scene
        // observes it: a cancelled gesture's release must never land as a
        // click on a sibling page or a host strip control.
        const auto *const release = static_cast<QMouseEvent *>(event);
        const int buttonBit = int(release->button()) & Qt::MouseButtonMask;
        if (!(m_swallowedReleaseButtons & buttonBit))
            break;
        m_swallowedReleaseButtons &= ~buttonBit;
        return true;
    }
    case QEvent::KeyPress:
    case QEvent::KeyRelease:
        return dispatchWindowKey(static_cast<QKeyEvent &>(*event));
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

bool QuickWindowInput::dispatchWindowKey(QKeyEvent &event)
{
    // The moved no-activeFocusItem fallback: the selected scene's shared
    // song policy claims keys no Quick item holds active focus for. Scenes
    // without a selected owner keep Qt's default delivery, and every scene
    // handles its own focused keys through its items, so this runs at most
    // once per window event.
    if (m_window->activeFocusItem())
        return false;
    TimelineQuickView *const scene = m_selectedScene.data();
    if (!scene)
        return false;
    const TimelineKeyInput keyInput{
        .key = event.key(),
        .modifiers = event.modifiers(),
        .text = event.text(),
        .autoRepeat = event.isAutoRepeat(),
    };
    return event.type() == QEvent::KeyPress ? scene->dispatchSongKey(keyInput)
                                            : scene->dispatchSongKeyRelease(keyInput);
}

} // namespace songview
