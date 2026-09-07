#pragma once

// Shared view of the in-canvas Quick prompt session. One
// TimelineQuickView-owned QuickPopupSession realizes, replaces, and dismisses
// prompt content in the existing Quick canvas. Checks observe the content
// slot and the canvas' active focus rather than a separate native window.
// The scoped guard keeps a failed scenario from leaving a popup open to
// swallow later delivery into the shell canvas.

#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QtTest>

#include "ui/songview.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"

namespace quick_popup {

// The tab Quick canvas' popup session, or null while the canvas is missing.
inline songview::QuickPopupSession *popupSession(SongView &view)
{
    auto *const quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quick ? quick->popupSession() : nullptr;
}

// Named prompt controls belong to the live visual tree. Pooled QML content can
// be visually reparented without matching QObject parentage, so QObject
// findChild() is not a reliable lookup seam.
inline QQuickItem *visualDescendant(QQuickItem *root, QLatin1String objectName)
{
    if (!root)
        return nullptr;
    if (root->objectName() == objectName)
        return root;
    for (QQuickItem *const child : root->childItems())
        if (QQuickItem *const found = visualDescendant(child, objectName))
            return found;
    return nullptr;
}

// A named item inside the current live popup content (dialog root, text input,
// accept/cancel buttons). The session's content slot distinguishes the current
// prompt from retired, deferred-deletion QML under the canvas root.
inline QQuickItem *promptItem(const songview::QuickPopupSession &session, QLatin1String objectName)
{
    return visualDescendant(session.contentItem(), objectName);
}

// The item's center in window coordinates, ready for QTest delivery.
inline QPoint itemCenter(QQuickItem &item)
{
    return item.mapToScene(QPointF(item.width() / 2, item.height() / 2)).toPoint();
}

// True while the named prompt text input owns the canvas' active focus.
inline bool inputHasActiveFocus(QQuickWindow &window, QLatin1String objectName)
{
    const QQuickItem *const focus = window.activeFocusItem();
    return focus && focus->objectName() == objectName;
}

// Clicks a named prompt button through the real canvas window; false when the
// session has no current prompt item, so the caller attributes the failure.
inline bool clickPromptButton(songview::QuickPopupSession &session, QLatin1String objectName)
{
    QQuickWindow *const window = session.window();
    QQuickItem *const button = promptItem(session, objectName);
    if (!window || !button)
        return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, itemCenter(*button));
    return true;
}

// Force-cancels a popup still open when the scenario scope ends.
class PromptGuard final
{
  public:
    explicit PromptGuard(SongView &view) : m_session(popupSession(view)) {}

    ~PromptGuard()
    {
        if (m_session && m_session->isOpen())
            m_session->cancel();
    }

    PromptGuard(const PromptGuard &) = delete;
    PromptGuard &operator=(const PromptGuard &) = delete;

  private:
    songview::QuickPopupSession *m_session;
};

} // namespace quick_popup
