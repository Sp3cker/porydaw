#include <QCoreApplication>
#include <QMetaObject>
#include <QThread>

extern "C" void porydaw_drain_qt_main_executor();

extern "C" bool porydaw_schedule_qt_main_executor_drain()
{
    auto *app = QCoreApplication::instance();
    if (!app)
        return false;
    return QMetaObject::invokeMethod(
        app, [] { porydaw_drain_qt_main_executor(); }, Qt::QueuedConnection);
}

extern "C" bool porydaw_is_qt_main_thread()
{
    auto *app = QCoreApplication::instance();
    return app ? app->thread() == QThread::currentThread() : QThread::isMainThread();
}

static void startQtMainExecutor()
{
    porydaw_schedule_qt_main_executor_drain();
}

Q_COREAPP_STARTUP_FUNCTION(startQtMainExecutor)
