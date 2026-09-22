#pragma once

#include "tst_swiftrollgated.h"

#include "app/native_host.h"
#include "ui/layout.h"

#include <QImage>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QTemporaryDir>
#include <QUrl>
#include <QtTest/QTest>

#include <memory>

namespace gridcheck {

// Real Swift session and production composition, without the temporary QWidget
// embedding host. Private drawer preferences keep native raster/input checks isolated.
class NativeScene final
{
  public:
    bool open(const QString &project, const QString &song, QString *error)
    {
        pd_app_register_types();
        QQmlComponent component(&engine);
        component.setData("import PorydawApp\nApplicationSession {}\n", QUrl());
        sessionOwner.reset(component.create());
        session = sessionOwner.get();
        if (!session) {
            *error = component.errorString();
            return false;
        }
        QQmlEngine::setObjectOwnership(session, QQmlEngine::CppOwnership);
        if (!QMetaObject::invokeMethod(session, "openProjectAndSong", Q_ARG(QString, project),
                                       Q_ARG(QString, song)) ||
            !QTest::qWaitFor([&] { return session->property("songOpen").toBool(); }, 15'000)) {
            *error = QStringLiteral("the production Swift session did not open the fixture song");
            return false;
        }
        view->setResizeMode(QQuickView::SizeRootObjectToView);
        view->resize(layout::fontPx(76), layout::fontPx(54));
        view->rootContext()->setContextProperty(QStringLiteral("appSession"), session);
        view->setSource(QUrl(QStringLiteral("qrc:/porydaw/swiftroll/SwiftRollOverlay.qml")));
        root = view->rootObject();
        if (!root || view->status() == QQuickView::Error) {
            *error = QStringLiteral("the production Swift Quick composition did not load");
            return false;
        }
        grid = root->property("gridModel").value<QObject *>();
        drawer = item("editorDrawer");
        auto *surface = drawer ? drawer->parentItem() : nullptr;
        if (!grid || !surface || !preferences.isValid()) {
            *error =
                QStringLiteral("the production drawer scene or private preferences are missing");
            return false;
        }
        if (!surface->setProperty("drawerPreferenceLocation",
                                  QUrl::fromLocalFile(preferences.filePath("drawer.ini")))) {
            *error = QStringLiteral("the mounted EditorSurface has no preference location");
            return false;
        }
        presenter = drawer->property("presenter").value<QObject *>();
        if (!presenter ||
            !QMetaObject::invokeMethod(presenter, "restoreStoredPreferences", Q_ARG(int, 0),
                                       Q_ARG(int, 160), Q_ARG(int, 1), Q_ARG(int, 240),
                                       Q_ARG(int, 1), Q_ARG(int, 90), Q_ARG(int, 0))) {
            *error = QStringLiteral("the production drawer rejected its initial layout");
            return false;
        }
        view->show();
        view->raise();
        view->requestActivate();
        if (!QTest::qWaitForWindowExposed(view) || !QTest::qWaitForWindowActive(view)) {
            *error = QStringLiteral("the native Quick window did not become active");
            return false;
        }
        if (!QTest::qWaitFor(
                [&] {
                    return item("automationPlotInput") && item("voicePlotInput") &&
                           item("automationPlotInput")->isVisible() &&
                           item("voicePlotInput")->isVisible();
                },
                5'000) ||
            capture(root).isNull()) {
            *error = QStringLiteral("the native drawer did not finish its first visible frame");
            return false;
        }
        return true;
    }

    QQuickItem *item(const char *name) const
    {
        return gridcheck::visualDescendant(root, QString::fromLatin1(name));
    }

    QObject *model(const char *page) const
    {
        auto *component = item(page);
        return component ? component->property("pageModel").value<QObject *>() : nullptr;
    }

    QString revision() const { return grid->property("appliedRevisionText").toString(); }

    void move(QQuickItem *target, QPointF position) const
    {
        QTest::mouseMove(view, target->mapToScene(position).toPoint());
    }

    // Crop the actual window framebuffer, not grabToImage's offscreen subtree.
    // Keep physical pixels and DPR so a blank/hidden scene cannot pass a diff.
    QImage capture(const QRectF &bounds) const
    {
        if (!gridcheck::awaitFrame(view))
            return {};
        const QImage image = view->grabWindow();
        const qreal dpr = image.devicePixelRatio();
        if (image.isNull() || bounds.isEmpty())
            return {};
        const QRect pixels = QRectF(bounds.topLeft() * dpr, bounds.size() * dpr).toAlignedRect();
        if (!image.rect().contains(pixels))
            return {};
        QImage result = image.copy(pixels);
        result.setDevicePixelRatio(dpr);
        return result;
    }

    QImage capture(QQuickItem *target) const
    {
        return capture(target->mapRectToScene(target->boundingRect()));
    }

    QList<QQuickItem *> descendants(QQuickItem *parent, const char *name) const
    {
        QList<QQuickItem *> result;
        for (auto *child : parent->childItems()) {
            if (child->objectName() == QString::fromLatin1(name))
                result.append(child);
            result.append(descendants(child, name));
        }
        return result;
    }

  private:
    QTemporaryDir preferences;
    QQmlEngine engine;
    std::unique_ptr<QObject> sessionOwner;
    QQuickView quickWindow{&engine, nullptr};

  public:
    QQuickView *view = &quickWindow;
    QQuickItem *root = nullptr;
    QQuickItem *drawer = nullptr;
    QObject *session = nullptr;
    QObject *grid = nullptr;
    QObject *presenter = nullptr;
};

} // namespace gridcheck
