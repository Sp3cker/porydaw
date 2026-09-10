#pragma once

// Shared view of the in-canvas Quick popup session. One
// TimelineQuickView-owned QuickPopupSession realizes, replaces, and dismisses
// prompt and menu content in the existing Quick canvas. Checks observe the
// content slot, the menu panel's typed rows, and the canvas' active focus
// rather than a separate native window.
// The scoped guard keeps a failed scenario from leaving a popup open to
// swallow later delivery into the shell canvas. Visual lookups reuse the
// canonical childItems traversal in checks::support.

#include "checks/support/quickframebuffer.h"
#include "checks/support/timelinequickcheck.h"
#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QVariant>
#include <QtTest>

#include "ui/songview.h"
#include "ui/songview/quick/quickmenumodel.h"
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

// A named item inside the current live popup content (dialog root, text input,
// accept/cancel buttons). The session's content slot distinguishes the current
// prompt from retired, deferred-deletion QML under the canvas root.
inline QQuickItem *promptItem(const songview::QuickPopupSession &session, QLatin1String objectName)
{
    return checks::support::visualDescendant(session.contentItem(), objectName);
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

// The visible root panel of the session's current menu level, or null while
// no menu level renders. The live overlay root excludes retired, deferred-
// deletion panels from a replaced session.
inline QQuickItem *menuPanel(const songview::QuickPopupSession &session)
{
    QQuickItem *const panel = checks::support::visualDescendant(
        session.overlayRoot(), QLatin1String("quickMenuPanelRoot"));
    return panel && panel->isVisible() ? panel : nullptr;
}

// The frame rectangle that absorbs presses around the current menu level.
inline QQuickItem *menuFrame(const songview::QuickPopupSession &session)
{
    return checks::support::visualDescendant(session.overlayRoot(),
                                             QLatin1String("quickMenuFrame"));
}

// The typed row model a menu panel renders, or null for foreign panels.
inline songview::QuickMenuModel *menuModel(QQuickItem &panel)
{
    return qobject_cast<songview::QuickMenuModel *>(panel.property("menuModel").value<QObject *>());
}

// Resolve through ListView.itemAtIndex in QML. Walking contentItem children
// includes retained pooling delegates after a model reset.
inline QQuickItem *menuRowItem(QQuickItem &panel, int row)
{
    QVariant result;
    if (!QMetaObject::invokeMethod(&panel, "rowItem", Q_RETURN_ARG(QVariant, result),
                                   Q_ARG(QVariant, row)))
        return nullptr;
    return result.value<QQuickItem *>();
}

// Scene-space center of the row's current delegate, waiting until the
// ListView realizes it and its layout stops moving. A fresh menu panel can
// publish the delegate's geometry before the list's first polish positions
// it, so the center is returned only after a pump leaves it unchanged; a
// null point means the row never rendered or its layout never settled.
inline QPointF menuRowSceneCenter(QQuickItem &panel, int row)
{
    QPointF center;
    bool seen = false;
    if (!QTest::qWaitFor([&panel, row, &center, &seen] {
            QQuickItem *const item = menuRowItem(panel, row);
            if (!item || !item->isVisible() || item->width() <= 0 || item->height() <= 0)
                return false;
            const QPointF resolved =
                item->mapToScene(QPointF(item->width() / 2.0, item->height() / 2.0));
            if (seen && resolved == center)
                return true;
            center = resolved;
            seen = true;
            checks::support::pumpQuick();
            return false;
        }))
        return {};
    return center;
}

// Real left click on a rendered menu row through the session window; false
// when the row never rendered, so the caller attributes the failure.
inline bool clickMenuRow(songview::QuickPopupSession &session, int row)
{
    QQuickWindow *const window = session.window();
    QQuickItem *const panel = menuPanel(session);
    if (!window || !panel)
        return false;
    const QPointF center = menuRowSceneCenter(*panel, row);
    if (center.isNull())
        return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center.toPoint());
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
