#pragma once

// Shared view of the native application-modal Quick prompt host (songview
// modal plan): one TimelineQuickView-owned QuickModalHost realizes, replaces,
// and dismisses prompt windows, and every prompt family (velocity, time
// signature, insert time, voice picker) exposes object-named content through
// it. Checks observe the live surface through TimelineQuickView::modalHost()
// and the window's active focus instead of host internals. The scoped guard
// keeps the QInputDialog-era watchdog role: a step that fails before closing
// the prompt must not leave application modality silently swallowing every
// later delivery into the shell windows.

#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QtTest>

#include "ui/songview.h"
#include "ui/songview/quick/quickmodalhost.h"
#include "ui/songview/quick/timelinequickview.h"

namespace quick_modal {

// The tab Quick canvas' modal host, or null while the canvas is missing.
inline songview::QuickModalHost *modalHost(SongView &view)
{
    auto *const quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quick ? quick->modalHost() : nullptr;
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

// A named item inside the live prompt window (dialog root, text input,
// accept/cancel buttons).
inline QQuickItem *promptItem(QQuickWindow &window, QLatin1String objectName)
{
    return visualDescendant(window.contentItem(), objectName);
}

// The item's center in window coordinates, ready for QTest delivery.
inline QPoint itemCenter(QQuickItem &item)
{
    return item.mapToScene(QPointF(item.width() / 2, item.height() / 2)).toPoint();
}

// True while the named prompt text input owns the window's active focus.
inline bool inputHasActiveFocus(QQuickWindow &window, QLatin1String objectName)
{
    const QQuickItem *const focus = window.activeFocusItem();
    return focus && focus->objectName() == objectName;
}

// Clicks a named prompt button through the real modal window; false when the
// prompt is missing the item, so the caller attributes the failure.
inline bool clickPromptButton(QQuickWindow &window, QLatin1String objectName)
{
    QQuickItem *const button = promptItem(window, objectName);
    if (!button)
        return false;
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, itemCenter(*button));
    return true;
}

// Force-cancels a prompt still open when the scenario scope ends.
class PromptGuard final
{
  public:
    explicit PromptGuard(SongView &view) : m_host(modalHost(view)) {}

    ~PromptGuard()
    {
        if (m_host && m_host->isOpen())
            m_host->cancel();
    }

    PromptGuard(const PromptGuard &) = delete;
    PromptGuard &operator=(const PromptGuard &) = delete;

  private:
    songview::QuickModalHost *m_host;
};

} // namespace quick_modal
