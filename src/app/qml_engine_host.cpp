#include "qml_engine_host.h"
#include "native_host.h"

#include <QtCore/qcoreapplication.h>
#include <QtCore/qthread.h>
#include <QtGui/qevent.h>
#include <QtQml/qqmlapplicationengine.h>
#include <QtQuick/qquickwindow.h>
#include <cstdio>
#include <cstdlib>
#include <string>

#include <qappcpp.h>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <dwmapi.h>
#include <windows.h>

namespace {

// Qt's Windows backend consumes WM_ERASEBKGND without painting, so DWM would
// present the uninitialized native surface until the first scene-graph swap.
class CloakUntilFirstFrame : public QObject
{
public:
    using QObject::QObject;

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() != QEvent::PlatformSurface)
            return false;
        auto *window = qobject_cast<QQuickWindow *>(watched);
        if (!window
            || static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType()
                   != QPlatformSurfaceEvent::SurfaceCreated)
            return false;
        setCloaked(window, TRUE);
        QObject::connect(
            window, &QQuickWindow::frameSwapped, window,
            [window] {
                setCloaked(window, FALSE);
                DwmFlush();
            },
            static_cast<Qt::ConnectionType>(Qt::QueuedConnection | Qt::SingleShotConnection));
        return false;
    }

private:
    static void setCloaked(QWindow *window, BOOL cloaked)
    {
        constexpr DWORD kDwmwaCloak = 13;
        DwmSetWindowAttribute(reinterpret_cast<HWND>(window->winId()), kDwmwaCloak, &cloaked,
                              sizeof(cloaked));
    }
};

} // namespace
#endif

void pd_window_cloak_until_first_frame()
{
#ifdef Q_OS_WIN
    auto *app = QCoreApplication::instance();
    app->installEventFilter(new CloakUntilFirstFrame(app));
#endif
}

const char *pd_qml_module_prefix()
{
    return "qrc:/qt/qml/Porydaw/Ui/";
}

QQmlApplicationEngine *pd_qml_engine()
{
    QQmlApplicationEngine *engine = QAppCpp::engine();
    Q_ASSERT(!engine || QThread::currentThread() == engine->thread());
    return engine;
}

bool pd_qml_add_import_path(const char *path)
{
    QQmlApplicationEngine *engine = pd_qml_engine();
    if (!engine || !path)
        return false;
    engine->addImportPath(QString::fromUtf8(path));
    return true;
}

// The external launch probe owns the clock, including process creation and dyld.
void pd_startup_trace_mark(const char *stage)
{
    if (std::getenv("PORYDAW_STARTUP_TRACE"))
        std::fprintf(stderr, "PORYDAW_STARTUP_TRACE %s\n", stage);
}

// Observe submission on the render thread, not a delayed GUI-thread signal handler.
void pd_startup_trace_window()
{
    if (!std::getenv("PORYDAW_STARTUP_TRACE"))
        return;
    auto *engine = pd_qml_engine();
    QObject::connect(engine, &QQmlApplicationEngine::objectCreated, engine,
                     [](QObject *object, const QUrl &) {
                         auto *window = qobject_cast<QQuickWindow *>(object);
                         if (!window)
                             return;
                         pd_startup_trace_mark("root-created");
                         QObject::connect(
                             window, &QQuickWindow::frameSwapped, window,
                             [seen = false]() mutable {
                                 if (!seen) {
                                     seen = true;
                                     pd_startup_trace_mark("first-frame");
                                 }
                             },
                             Qt::DirectConnection);
                     });
}

// Called on the GUI thread at mount completion, before its next render.
void pd_startup_trace_next_frame(const char *stage)
{
    if (!std::getenv("PORYDAW_STARTUP_TRACE"))
        return;
    auto *engine = pd_qml_engine();
    if (!engine)
        return;
    const auto roots = engine->rootObjects();
    for (auto *object : roots) {
        auto *window = qobject_cast<QQuickWindow *>(object);
        if (!window)
            continue;
        // An in-flight swap can still contain the scene from before mounting.
        QObject::connect(
            window, &QQuickWindow::afterSynchronizing, window,
            [window, mark = std::string(stage)]() {
                QObject::connect(
                    window, &QQuickWindow::frameSwapped, window,
                    [mark]() { pd_startup_trace_mark(mark.c_str()); },
                    static_cast<Qt::ConnectionType>(Qt::DirectConnection |
                                                    Qt::SingleShotConnection));
            },
            static_cast<Qt::ConnectionType>(Qt::DirectConnection | Qt::SingleShotConnection));
        return;
    }
}
