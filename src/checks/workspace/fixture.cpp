#include "checks/workspace/fixture.h"

#include <QCoreApplication>
#include <QList>
#include <QPoint>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>
#include <QtMath>
#include <QtTest>

#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/workspacequick/workspacequickhost.h"
#include "ui/workspaceui.h"

namespace {

void settle()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

} // namespace

namespace workspace_test {

SongTab *waitReady(WorkspaceUi &workspace, const SongName &name, int timeoutMs)
{
    SongTab *tab = nullptr;
    const auto result = checks::async_wait::waitUntil(
        [&workspace, &name, &tab] {
            tab = workspace.songTabFor(name);
            return tab != nullptr;
        },
        [&workspace, &name, &tab] {
            tab = workspace.songTabFor(name);
            return tab && tab->isReady();
        },
        timeoutMs, 1);
    return result == checks::async_wait::Result::Ready ? tab : nullptr;
}

SongTab *openReady(WorkspaceUi &workspace, const SongName &name, bool newTab, int timeoutMs)
{
    workspace.requestSongOpen(name, newTab);
    return waitReady(workspace, name, timeoutMs);
}

WorkspaceQuickHost *quickHost(MainWindow &window)
{
    return window.findChild<WorkspaceQuickHost *>();
}

bool exposeWorkspaceHost(MainWindow &window, WorkspaceQuickHost &host, const QSize &size)
{
    QQuickWindow *const quickWindow = host.window();
    if (!quickWindow || !host.container())
        return false;

    window.resize(size);
    window.show();
    quickWindow->requestActivate();
    settle();
    if (!QTest::qWaitFor([quickWindow] { return quickWindow->isExposed(); }, 5000))
        return false;
    if (!QTest::qWaitFor([quickWindow] { return quickWindow->isActive(); }, 5000))
        return false;
    settle();
    return quickWindow->isExposed() && quickWindow->isActive();
}

// ListView delegates are visual children, so QObject lookup misses pooled rows.
QQuickItem *quickItem(QQuickWindow &window, const QString &objectName)
{
    QQuickItem *const root = window.contentItem();
    if (!root)
        return nullptr;

    QList<QQuickItem *> stack{root};
    while (!stack.isEmpty()) {
        QQuickItem *const item = stack.takeLast();
        if (item->objectName() == objectName)
            return item;
        for (QQuickItem *child : item->childItems())
            stack.append(child);
    }
    return nullptr;
}

void clickQuickItem(QQuickWindow &window, QQuickItem &item)
{
    const QPoint point = item.mapToScene(QPointF(item.width() / 2, item.height() / 2)).toPoint();
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, point);
    settle();
}

void dragQuickItemHorizontally(QQuickWindow &window, QQuickItem &item, double targetSceneX)
{
    const QPointF startScene = item.mapToScene(QPointF(item.width() * 0.25, item.height() / 2));
    const QPoint start = startScene.toPoint();
    QTest::mousePress(&window, Qt::LeftButton, Qt::NoModifier, start);
    constexpr int steps = 8;
    for (int step = 1; step <= steps; ++step) {
        const double x = startScene.x() + (targetSceneX - startScene.x()) * step / steps;
        QTest::mouseMove(&window, QPoint(qRound(x), start.y()));
    }
    QTest::mouseRelease(&window, Qt::LeftButton, Qt::NoModifier,
                        QPoint(qRound(targetSceneX), start.y()));
    settle();
}

bool itemInsideViewport(const QQuickItem &item, const QQuickItem &viewport)
{
    const QPointF topLeft = item.mapToItem(&viewport, QPointF());
    return topLeft.x() >= 0 && topLeft.y() >= 0 &&
           topLeft.x() + item.width() <= viewport.width() + 0.5 &&
           topLeft.y() + item.height() <= viewport.height() + 0.5;
}

} // namespace workspace_test
