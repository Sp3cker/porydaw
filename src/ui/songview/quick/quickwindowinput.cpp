#include "ui/songview/quick/quickwindowinput.h"

#include <QEvent>
#include <QMouseEvent>
#include <QQuickWindow>

namespace songview {

QuickWindowInput &QuickWindowInput::forWindow(QQuickWindow &window)
{
    // Child lookup doubles as the idempotence guard: the arbiter is created
    // exactly once per window and lives until the window dies, so repeated
    // lookups always reach one instance.
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
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

} // namespace songview
