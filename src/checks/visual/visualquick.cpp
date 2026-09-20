#include "checks/visual/visualquick.h"

#include "checks/quickpopupguard.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/timelinequickcheck.h"
#include "ui/songview/quick/quickpopupsession.h"

#include <QImage>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

namespace checks::visual {

QImage grabQuick(QQuickWindow &window, QString *error)
{
    if (!checks::support::waitForQuickFrame(window, error))
        return {};
    const QImage image = window.grabWindow();
    if (image.isNull() && error)
        *error = QStringLiteral("Quick framebuffer grab is empty");
    return image;
}

QRect quickItemBounds(QQuickItem *root, const QString &objectName)
{
    // Input items are transparent hit targets: bounds matter, opacity does
    // not, so visibility is not required — only a real mapped rectangle.
    QQuickItem *const item = checks::support::visualDescendant(root, objectName);
    if (!item || item->width() <= 0 || item->height() <= 0)
        return {};
    const QPointF topLeft = item->mapToScene(QPointF{});
    return {qRound(topLeft.x()), qRound(topLeft.y()), qRound(item->width()),
            qRound(item->height())};
}

Region quickItemRegion(const QString &name, QQuickItem *root, const QString &objectName)
{
    return {name, quickItemBounds(root, objectName)};
}

bool expectQuickBaseline(const QString &id, QQuickWindow &window, QQuickItem *root,
                         const QList<Region> &regions, QString *error)
{
    // The scenario's root belongs to the caller's region resolution; the grab
    // and the comparison are defined over the window image alone.
    Q_UNUSED(root);
    const QImage image = grabQuick(window, error);
    if (image.isNull())
        return false;
    for (const Region &region : regions) {
        if (region.bounds.isEmpty()) {
            if (error)
                *error = region.name + QStringLiteral(" has no visible bounds");
            return false;
        }
    }
    return compare(id, image, regions, error);
}

QQuickItem *awaitPopupForm(SongView &view)
{
    if (!QTest::qWaitFor([&view] {
            songview::QuickPopupSession *const session = quick_popup::popupSession(view);
            return session && session->isOpen() && session->contentItem() != nullptr;
        }))
        return nullptr;
    songview::QuickPopupSession *const session = quick_popup::popupSession(view);
    return session ? session->contentItem() : nullptr;
}

QQuickItem *awaitMenuPanel(SongView &view)
{
    if (!QTest::qWaitFor([&view] {
            songview::QuickPopupSession *const session = quick_popup::popupSession(view);
            return session && session->isOpen();
        }))
        return nullptr;
    songview::QuickPopupSession *const session = quick_popup::popupSession(view);
    QQuickItem *const overlay = session ? session->overlayRoot() : nullptr;
    if (!overlay)
        return nullptr;
    // Panels are item-children of the overlay but QObject-children of the menu
    // host, so findChild cannot reach them; scan the visual children.
    for (QQuickItem *child : overlay->childItems())
        if (child->objectName() == QStringLiteral("quickMenuPanelRoot"))
            return child;
    return nullptr;
}

void steadyPopupFocus(QQuickItem *form, const QString &objectName)
{
    QVERIFY2(form, "the popup form is unavailable for focus parking");
    if (objectName.isEmpty())
        return;
    QQuickItem *const steady = form->findChild<QQuickItem *>(objectName);
    QVERIFY2(
        steady,
        qPrintable(QStringLiteral("the popup form lacks the steady control '%1'").arg(objectName)));
    steady->setFocus(true);
}

} // namespace checks::visual
