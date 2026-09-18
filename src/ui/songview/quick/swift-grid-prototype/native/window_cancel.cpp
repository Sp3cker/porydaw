// Host-owned window cancel filter for the Swift piano-grid.
//
// Production analog: TimelineQuickView::eventFilter
// (timelinequickview_window.cpp). Hide and WindowDeactivate are distinct
// named deliveries (charter S-4). The filter is parented to the window it
// watches and calls the typed sink with TimelineInputCancelReason raw values.

#include "window_cancel.h"

#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QObject>
#include <QQuickWindow>
#include <QWindow>

namespace {

constexpr int kHidden = 2;
constexpr int kWindowDeactivated = 3;

class GridWindowCancelFilter final : public QObject
{
  public:
    GridWindowCancelFilter(QObject *window, SgwInputCancelledFn fn, void *context)
        : QObject(window)
        , m_fn(fn)
        , m_context(context)
    {
        window->installEventFilter(this);
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (watched != parent() || m_fn == nullptr)
            return false;
        switch (event->type()) {
        case QEvent::Hide:
            m_fn(kHidden, m_context);
            break;
        case QEvent::WindowDeactivate:
            m_fn(kWindowDeactivated, m_context);
            break;
        default:
            break;
        }
        return false;
    }

  private:
    SgwInputCancelledFn m_fn = nullptr;
    void *m_context = nullptr;
};

SgwInputCancelledFn g_fn = nullptr;
void *g_context = nullptr;
bool g_attached = false;

void attachToWindow(QQuickWindow *window)
{
    if (g_attached || window == nullptr || g_fn == nullptr)
        return;
    new GridWindowCancelFilter(window, g_fn, g_context);
    g_attached = true;
    g_fn = nullptr;
    g_context = nullptr;
}

class AttachOnShow final : public QObject
{
  public:
    using QObject::QObject;

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Show) {
            if (auto *window = qobject_cast<QQuickWindow *>(watched)) {
                attachToWindow(window);
                if (g_attached) {
                    qApp->removeEventFilter(this);
                    deleteLater();
                }
            }
        }
        return false;
    }
};

void installNow()
{
    QCoreApplication *app = QCoreApplication::instance();
    if (!app || g_fn == nullptr)
        return;
    for (QWindow *window : QGuiApplication::allWindows()) {
        attachToWindow(qobject_cast<QQuickWindow *>(window));
        if (g_attached)
            return;
    }
    app->installEventFilter(new AttachOnShow(app));
}

} // namespace

extern "C" void sgw_installWindowCancelHost(SgwInputCancelledFn fn, void *context)
{
    g_fn = fn;
    g_context = context;
    g_attached = false;
    if (QCoreApplication::instance()) {
        installNow();
        return;
    }
    qAddPreRoutine(installNow);
}
