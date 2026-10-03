#include "qml_engine_host.h"
#include "native_host.h"

#include <QtCore/qcoreapplication.h>
#include <QtCore/qthread.h>
#include <QtGui/qevent.h>
#include <QtGui/qfontdatabase.h>
#include <QtGui/qguiapplication.h>
#include <QtGui/qscreen.h>
#include <QtQml/qqmlapplicationengine.h>
#include <QtQuick/qquickwindow.h>
#include <cstdio>
#include <cinttypes>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <string>

#include <qappcpp.h>


#ifdef Q_OS_MACOS
#include <os/signpost.h>

namespace {
os_log_t startup_signpost_log()
{
    // Initialized before installing render-thread observers; immutable thereafter.
    static const os_log_t log = os_log_create("com.sp3cker.porydaw", "startup");
    return log;
}
} // namespace
#endif

namespace {

void report_screen_refresh(int64_t millihz)
{
#ifdef Q_OS_MACOS
    const auto log = startup_signpost_log();
    if (os_signpost_enabled(log))
        os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "screen-refresh-millihz",
                               "millihz=%lld", static_cast<long long>(millihz));
#endif
    if (std::getenv("PORYDAW_STARTUP_TRACE"))
        std::fprintf(stderr, "PORYDAW_STARTUP_TRACE screen-refresh-millihz=%" PRId64 "\n",
                     millihz);
}

void report_primary_screen_refresh(int64_t millihz, bool after)
{
#ifdef Q_OS_MACOS
    const auto log = startup_signpost_log();
    if (os_signpost_enabled(log)) {
        if (after)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE,
                                  "primary-screen-refresh-millihz-after",
                                  "millihz=%lld", static_cast<long long>(millihz));
        else
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE,
                                  "primary-screen-refresh-millihz",
                                  "millihz=%lld", static_cast<long long>(millihz));
    }
#endif
    if (std::getenv("PORYDAW_STARTUP_TRACE"))
        std::fprintf(stderr, "PORYDAW_STARTUP_TRACE %s=%" PRId64 "\n",
                     after ? "primary-screen-refresh-millihz-after"
                           : "primary-screen-refresh-millihz",
                     millihz);
}

} // namespace
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
#ifdef Q_OS_MACOS
    const auto log = startup_signpost_log();
    if (os_signpost_enabled(log)) {
        if (std::strcmp(stage, "app-init") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "app-init");
        else if (std::strcmp(stage, "presenter-begin") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "presenter-begin");
        else if (std::strcmp(stage, "presenter-end") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "presenter-end");
        else if (std::strcmp(stage, "chrome-restored") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "chrome-restored");
        else if (std::strcmp(stage, "root-created") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "root-created");
        else if (std::strcmp(stage, "content-ready") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "content-ready");
        else if (std::strcmp(stage, "workspace-ready") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "workspace-ready");
        else if (std::strcmp(stage, "first-frame") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "first-frame");
        else if (std::strcmp(stage, "chrome-frame") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "chrome-frame");
        else if (std::strcmp(stage, "workspace-frame") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "workspace-frame");
        else if (std::strcmp(stage, "editor-ready") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "editor-ready");
        else if (std::strcmp(stage, "editor-frame") == 0)
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "editor-frame");
        else
            os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "startup-adoption",
                                   "%{public}s", stage);
    }
#endif
    if (std::getenv("PORYDAW_STARTUP_TRACE")) {
        std::fprintf(stderr, "PORYDAW_STARTUP_TRACE %s\n", stage);
        std::fflush(stderr);
    }
}

bool pd_startup_trace_enabled()
{
    bool enabled = std::getenv("PORYDAW_STARTUP_TRACE") != nullptr;
#ifdef Q_OS_MACOS
    enabled = enabled || os_signpost_enabled(startup_signpost_log());
#endif
    return enabled;
}

// Observe submission on the render thread, not a delayed GUI-thread signal handler.
void pd_startup_trace_window()
{
    if (!pd_startup_trace_enabled())
        return;
    auto *engine = pd_qml_engine();
    if (!engine)
        return;
    if (auto *screen = QGuiApplication::primaryScreen())
        report_primary_screen_refresh(
            static_cast<int64_t>(std::llround(screen->refreshRate() * 1000)), false);
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
    if (!pd_startup_trace_enabled())
        return;
    auto *engine = pd_qml_engine();
    if (!engine)
        return;
    const auto roots = engine->rootObjects();
    for (auto *object : roots) {
        auto *window = qobject_cast<QQuickWindow *>(object);
        if (!window)
            continue;
        if (std::strcmp(stage, "chrome-frame") == 0) {
            if (auto *screen = window->screen())
                report_screen_refresh(static_cast<int64_t>(std::llround(screen->refreshRate() * 1000)));
            if (auto *screen = QGuiApplication::primaryScreen())
                report_primary_screen_refresh(
                    static_cast<int64_t>(std::llround(screen->refreshRate() * 1000)), true);
        }
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

void pd_startup_prewarm_fonts()
{
    auto *engine = pd_qml_engine();
    if (!engine)
        return;
    auto *worker = QThread::create([] {
        pd_startup_trace_mark("font-prewarm-begin");
        (void)QFontDatabase::families();
        pd_startup_trace_mark("font-prewarm-end");
    });
    // QThread::create's destructor joins; the engine dies before QGuiApplication.
    worker->setParent(engine);
    QObject::connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, worker,
                     [worker] { worker->wait(); });
    worker->start();
}
