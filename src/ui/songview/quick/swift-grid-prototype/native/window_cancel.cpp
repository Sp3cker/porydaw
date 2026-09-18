// Native window eventFilter for the Swift grid prototype.
//
// Production entry (timelinequickview_window.cpp TimelineQuickView::
// eventFilter): QEvent::Hide and QEvent::WindowDeactivate cancel every live
// Quick interaction exactly once. The prototype mirrors it: either event on
// the grid window forwards cancelPointer(3) to the grid model. The first
// delivery clears the live gesture, so a trailing Hide or WindowDeactivate
// for the same transition is a Swift-side no-op (guard let gesture).
//
// Only windows carrying the prototype's gridModel property are forwarded:
// popup-owned and foreign windows keep their own input (spec defers
// popup-session parity, so the grid's window path never tears them down).
// Window hide() additionally reaches QML onVisibleChanged (reason 2,
// Hidden); teardown is identical to reason 3 by design, so whichever entry
// runs first owns the cancel.

#include "window_cancel.h"

#include <QCoreApplication>
#include <QEvent>
#include <QMetaObject>
#include <QObject>
#include <QQuickWindow>
#include <QVariant>

namespace {

// QObject subclass without Q_OBJECT: the virtual eventFilter override needs
// no meta-object code, so no moc run is required for this TU.
class GridWindowCancelFilter final : public QObject
{
  public:
    using QObject::QObject;

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        const QEvent::Type type = event->type();
        if (type != QEvent::Hide && type != QEvent::WindowDeactivate)
            return false;
        const auto *window = qobject_cast<QQuickWindow *>(watched);
        if (!window)
            return false;
        QObject *model = window->property("gridModel").value<QObject *>();
        if (!model)
            return false;
        QMetaObject::invokeMethod(model, "cancelPointer", Q_ARG(int, 3));
        return false;
    }
};

void installNow()
{
    QCoreApplication *app = QCoreApplication::instance();
    if (!app)
        return;
    static GridWindowCancelFilter *installed = nullptr;
    if (installed)
        return;
    installed = new GridWindowCancelFilter(app);
    app->installEventFilter(installed);
}

} // namespace

extern "C" void sgw_installWindowCancelFilter(void)
{
    if (QCoreApplication::instance()) {
        installNow();
        return;
    }
    // App.init runs before QtBridge creates the application object; defer
    // to the pre-routine phase like the smoke driver does.
    qAddPreRoutine(installNow);
}
