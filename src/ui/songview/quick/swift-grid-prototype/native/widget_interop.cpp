// Native widget interop for the Swift/QML song-tab prototype.
//
// The prototype keeps the real QML ApplicationWindow as its top-level window
// and opens real production widgets over it: the production NewSongWizard
// (populated from a detached in-memory catalog, so it never reads a project
// root) and a plain QMenu. Both launches return as soon as the widget is up;
// the single outcome arrives later through the caller's callback.
//
// Ownership: one widget at a time, tracked with QPointer and deleted with
// QWidget::deleteLater. The QWidget parent is deliberately null — the platform
// QWindow's transient parent is the Quick window, which is what keeps the
// widget above the Quick window on Cocoa without pretending the Quick window
// is a QWidget.
//
// Lifecycle: the host installs from the QML bootstrap — the root
// ApplicationWindow's Component.onCompleted — which is the first moment a fully
// constructed QApplication exists. That same call installs the production
// layout (src/ui/layout.cpp) once, before any widget exists, exactly as
// applicationstartup.cpp does for the real application.

#include "widget_interop.h"

#include <QAbstractButton>
#include <QAction>
#include <QApplication>
#include <QByteArray>
#include <QCoreApplication>
#include <QDialog>
#include <QFontInfo>
#include <QGuiApplication>
#include <QMenu>
#include <QMessageBox>
#include <QMetaObject>
#include <QPoint>
#include <QPointer>
#include <QProgressDialog>
#include <QQuickWindow>
#include <QScreen>
#include <QSize>
#include <QThread>
#include <QTimer>
#include <QWidget>
#include <QWindow>

#include <cstdio>
#include <functional>

#include "ui/layout.h"
#include "widget_window_fixtures.h"

// Defined in widget_interop_smoke.cpp (internal to this library pair).
void sgw_installWidgetInteropSmokeImpl();

namespace {

// ---- Host state -------------------------------------------------------------

struct HostState {
    // Set once the host has been installed; repeated installs are no-ops.
    bool installed = false;
    bool layoutReady = false;
    bool readyLogged = false;
    QPointer<QQuickWindow> window;
    // At most one bridge-owned top-level widget is open at a time. The QPointer
    // releases the slot as soon as the widget is deleted, so a later launch can
    // never reuse a stale pointer.
    QPointer<QWidget> activeWidget;
};

HostState &host()
{
    static HostState state;
    return state;
}

// ---- Production layout ------------------------------------------------------

// Installs the one application-wide production layout. layout::initialize()
// sets the application-wide style sheet through QApplication and installs its
// process-wide popup filter, so it is only legal under a fully constructed
// QApplication. A false return leaves the layout uninstalled and the host
// uninstalled with it: the caller must not carry on with only part of the host
// in place.
bool ensureProductionLayout(QApplication &app)
{
    HostState &state = host();
    if (state.layoutReady)
        return true;
    // applicationstartup.cpp resolves the base font pixel size from the
    // platform font and installs the one application-wide layout before any
    // widget exists. This lane deliberately leaves the application font alone:
    // the Quick UI derives its own base font from Qt.application.font, and the
    // bundled body face would rescale the whole grid.
    const int baseFontPx = QFontInfo(QApplication::font()).pixelSize();
    if (baseFontPx <= 0 || !layout::initialize(app, baseFontPx))
        return false;
    state.layoutReady = true;
    return true;
}

// ---- Quick window adoption --------------------------------------------------

void markWindowExposed()
{
    HostState &state = host();
    if (state.readyLogged || !state.window || !state.window->isExposed())
        return;
    state.readyLogged = true;
    // The exact host-readiness line the lane's tooling waits for: printed once,
    // and only once the Quick window is really on screen.
    std::puts("SWIFT_GRID_QUICK_HOST READY");
    std::fflush(stdout);
}

class QuickWindowExposureWatch final : public QObject
{
  public:
    explicit QuickWindowExposureWatch(QQuickWindow *window) : QObject(window)
    {
        window->installEventFilter(this);
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Expose || event->type() == QEvent::Show)
            markWindowExposed();
        return QObject::eventFilter(watched, event);
    }
};

void adoptQuickWindow(QQuickWindow *window)
{
    HostState &state = host();
    if (!window || !window->isTopLevel() || state.window)
        return;
    state.window = window;
    new QuickWindowExposureWatch(window);
    markWindowExposed();
}

// The applications's top-level Quick window may not exist yet when the host
// installs, so the first one to be shown is adopted (one adoption per
// process; the host is a singleton).
class QuickWindowAttachFilter final : public QObject
{
  public:
    using QObject::QObject;

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Show) {
            adoptQuickWindow(qobject_cast<QQuickWindow *>(watched));
            if (host().window) {
                if (auto *app = QCoreApplication::instance())
                    app->removeEventFilter(this);
                deleteLater();
            }
        }
        return QObject::eventFilter(watched, event);
    }
};

// The host's lifecycle entry point, reached once through
// sgw_installWidgetInteropHost(). Its caller contract is the QML bootstrap: the
// root ApplicationWindow's Component.onCompleted, which QML emits only after
// QApplication has been fully constructed. Installing any earlier would drive
// layout::initialize() and its application style sheet through a half-built
// QApplication, so a call without a fully constructed one is a contract
// violation that stops the process instead of quietly installing a partial
// host.
void installHost()
{
    HostState &state = host();
    if (state.installed)
        return;
    auto *app = qobject_cast<QApplication *>(QCoreApplication::instance());
    if (!app || QCoreApplication::startingUp() || QCoreApplication::closingDown()) {
        qFatal("SWIFT_GRID_QUICK_HOST ERROR: sgw_installWidgetInteropHost requires a fully "
               "constructed QApplication; call it from the root ApplicationWindow's "
               "Component.onCompleted");
    }
    if (!ensureProductionLayout(*app))
        qFatal("SWIFT_GRID_QUICK_HOST ERROR: production layout initialization failed");
    // The Quick window may already exist at Component.onCompleted, in which
    // case it is adopted here, or it arrives with its first Show event, which
    // is what the attach filter waits for. Either way one window is adopted.
    for (QWindow *candidate : QGuiApplication::allWindows())
        adoptQuickWindow(qobject_cast<QQuickWindow *>(candidate));
    if (!state.window)
        app->installEventFilter(new QuickWindowAttachFilter(app));
    state.installed = true;
}

// ---- Exactly-once outcome delivery ------------------------------------------

class WidgetOutcome
{
  public:
    WidgetOutcome(SgwWidgetResultFn fn, void *context) : m_fn(fn), m_context(context) {}

    void deliver(int kind, const QString &detail)
    {
        if (m_delivered)
            return;
        m_delivered = true;
        if (!m_fn)
            return;
        const QByteArray utf8 = detail.toUtf8();
        m_fn(kind, utf8.constData(), m_context);
    }

  private:
    SgwWidgetResultFn m_fn = nullptr;
    void *m_context = nullptr;
    bool m_delivered = false;
};

// Carries a launch's outcome on the launched widget itself, so the connection
// that reports it dies with the widget.
class OutcomeHolder final : public QObject
{
  public:
    OutcomeHolder(QObject *parent, SgwWidgetResultFn fn, void *context)
        : QObject(parent)
        , m_outcome(fn, context)
    {}

    WidgetOutcome &outcome() { return m_outcome; }

  private:
    WidgetOutcome m_outcome;
};

// ---- Window reactivation ----------------------------------------------------

// Hands activation back to the Quick window once a bridge-owned modal widget
// has dismissed. A modal QWidget owns activation while it is open; after it is
// gone, the normal product behavior is that the Quick window is the active
// window again. This is deliberately window-scoped: which item holds keyboard
// focus inside the window is the window's own business, so the bridge neither
// observes nor imposes one. The platform reports activation asynchronously and
// may ignore the request if the user has moved on, so nothing downstream waits
// on it.
void reactivateQuickWindow()
{
    QQuickWindow *window = host().window;
    if (!window || window->isActive())
        return;
    window->requestActivate();
}

// The dialog/menu has no QWidget parent on purpose: the platform QWindow's
// transient parent is the Quick window, so the platform keeps the widget above
// the Quick window without pretending the Quick window is a QWidget.
void adoptTransientParent(QWidget *widget)
{
    QQuickWindow *window = host().window;
    if (!widget || !window)
        return;
    if (QWindow *handle = widget->windowHandle())
        handle->setTransientParent(window);
}

// ---- Launch plumbing --------------------------------------------------------

// The ABI is a GUI-thread interface. A launch from another thread is dispatched
// onto the GUI thread and the call still reports whether the widget actually
// started: the caller sends the request and waits for the launch decision.
bool runOnGuiThread(const std::function<int()> &body)
{
    auto *app = QCoreApplication::instance();
    if (!app)
        return false;
    if (QThread::currentThread() == app->thread())
        return body() != 0;
    int started = 0;
    QMetaObject::invokeMethod(
        app, [&body, &started] { started = body(); }, Qt::BlockingQueuedConnection);
    return started != 0;
}

// A launch needs the installed host: the production layout is in place (the
// installer stops the process otherwise) and the adopted window is on screen.
bool canLaunch()
{
    HostState &state = host();
    auto *app = qobject_cast<QApplication *>(QCoreApplication::instance());
    return app && state.window && state.window->isExposed() && !state.activeWidget &&
           ensureProductionLayout(*app);
}

// ---- Menu -------------------------------------------------------------------

class WidgetMenu final : public QMenu
{
  public:
    WidgetMenu(SgwWidgetResultFn fn, void *context) : m_outcome(fn, context) {}

    // Retires the menu one event-loop turn after the popup hides. aboutToHide
    // is emitted from the hide itself, before an activated action has been
    // triggered and before the platform hands activation back, so the dismissal
    // is reported from the following turn: an action has always delivered by
    // then (the exactly-once guard then keeps the action as the outcome), and
    // window reactivation happens after the popup has relinquished activation.
    // Ownership stays here, so the deletion happens exactly once.
    void finish()
    {
        if (m_retired)
            return;
        m_retired = true;
        QTimer::singleShot(0, this, [this] {
            m_outcome.deliver(SgwWidgetResultMenuDismissed, QString());
            reactivateQuickWindow();
            deleteLater();
        });
    }

    WidgetOutcome &outcome() { return m_outcome; }

  private:
    WidgetOutcome m_outcome;
    bool m_retired = false;
};

// QQuickWindow-local logical pixels -> global logical pixels, clamped so the
// whole popup stays inside the available geometry of the screen under it.
// QWindow::mapToGlobal already works in device-independent coordinates: a
// device pixel ratio never enters this mapping (scaling by DPR would land the
// popup off screen on a Retina display).
QPoint clampedAnchor(const QQuickWindow *window, const QPoint &local, const QSize &popupSize)
{
    const QPoint global = window->mapToGlobal(local);
    const QScreen *screen = QGuiApplication::screenAt(global);
    if (!screen)
        screen = window->screen();
    if (!screen)
        return global;
    const QRect available = screen->availableGeometry();
    const int maxX = qMax(available.left(), available.right() - popupSize.width() + 1);
    const int maxY = qMax(available.top(), available.bottom() - popupSize.height() + 1);
    return {qBound(available.left(), global.x(), maxX), qBound(available.top(), global.y(), maxY)};
}

int startWidgetMenu(double windowX, double windowY, SgwWidgetResultFn fn, void *context)
{
    if (!canLaunch())
        return 0;

    auto *menu = new WidgetMenu(fn, context);
    QAction *inspect = menu->addAction(QStringLiteral("Inspect Current Tab"));
    // The reported detail is the action's own label, so it cannot drift from
    // what the menu rendered.
    QObject::connect(inspect, &QAction::triggered, menu, [menu, inspect] {
        menu->outcome().deliver(SgwWidgetResultMenuAction, inspect->text());
    });
    QObject::connect(menu, &QMenu::aboutToHide, menu, [menu] { menu->finish(); });

    menu->ensurePolished();
    const QPoint local(qRound(windowX), qRound(windowY));
    const QPoint anchor = clampedAnchor(host().window, local, menu->sizeHint());
    host().activeWidget = menu;
    // Same ordering as the wizard: the popup's platform window exists with its
    // transient parent before the platform shows it.
    menu->setAttribute(Qt::WA_NativeWindow);
    menu->winId();
    adoptTransientParent(menu);
    menu->popup(anchor);
    if (!menu->isVisible()) {
        // The platform refused the popup; retiring it releases the slot and no
        // outcome is reported, exactly like a launch that never started.
        delete menu;
        return 0;
    }
    return 1;
}

// ---- Standalone window fixtures ---------------------------------------------

bool isDialogAccepted(QDialog *dialog, int result)
{
    if (result == QDialog::Rejected)
        return false;

    if (auto *box = qobject_cast<QMessageBox *>(dialog)) {
        if (QAbstractButton *clicked = box->clickedButton()) {
            const QMessageBox::ButtonRole role = box->buttonRole(clicked);
            if (role == QMessageBox::AcceptRole || role == QMessageBox::YesRole ||
                role == QMessageBox::ApplyRole) {
                return true;
            }
            if (role == QMessageBox::RejectRole || role == QMessageBox::NoRole ||
                role == QMessageBox::DestructiveRole) {
                return false;
            }
        }
        switch (result) {
        case QMessageBox::Ok:
        case QMessageBox::Yes:
        case QMessageBox::Save:
        case QMessageBox::Open:
            return true;
        default:
            return false;
        }
    }
    return result == QDialog::Accepted;
}

int startWindowFixture(int kind, SgwWidgetResultFn fn, void *context)
{
    if (!canLaunch())
        return 0;

    QDialog *dialog = sgw_createWindowFixture(kind);
    if (!dialog)
        return 0;

    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->setWindowModality(Qt::WindowModal);
    host().activeWidget = dialog;

    const QString title = dialog->windowTitle();
    auto *holder = new OutcomeHolder(dialog, fn, context);
    const QPointer<QDialog> guarded = dialog;

    const auto deliverOutcome = [holder, guarded, title](int result) {
        if (host().activeWidget == guarded)
            host().activeWidget = nullptr;
        const bool accepted =
            guarded ? isDialogAccepted(guarded.data(), result) : (result == QDialog::Accepted);
        const QString resolvedTitle =
            (guarded && !guarded->windowTitle().isEmpty()) ? guarded->windowTitle() : title;
        holder->outcome().deliver(accepted ? SgwWidgetResultAccepted : SgwWidgetResultCancelled,
                                  resolvedTitle);
        if (guarded)
            guarded->deleteLater();
        reactivateQuickWindow();
    };

    QObject::connect(dialog, &QDialog::finished, holder,
                     [deliverOutcome](int result) { deliverOutcome(result); });

    // Special handling for QProgressDialog which might emit canceled() instead
    // of or prior to finished().
    if (auto *progress = qobject_cast<QProgressDialog *>(dialog)) {
        QObject::connect(progress, &QProgressDialog::canceled, holder,
                         [deliverOutcome] { deliverOutcome(QDialog::Rejected); });
    }

    dialog->setAttribute(Qt::WA_NativeWindow);
    dialog->winId();
    adoptTransientParent(dialog);
    dialog->open();
    return 1;
}

} // namespace

// Internal to this translation-unit pair: the smoke observes the host's
// readiness and adopted window instead of re-deriving them from Qt state.
extern "C" int sgw_widgetInteropHostReady(void)
{
    return host().readyLogged ? 1 : 0;
}

extern "C" void *sgw_widgetInteropHostWindow(void)
{
    return host().window.data();
}

extern "C" void *sgw_widgetInteropActiveWidget(void)
{
    return host().activeWidget.data();
}

extern "C" void sgw_installWidgetInteropHost(void)
{
    // Executed at the caller's lifecycle boundary — the root ApplicationWindow's
    // Component.onCompleted — never deferred to a pre-routine or an earlier
    // point of application startup.
    installHost();
}

extern "C" int sgw_openWidgetMenu(double windowX, double windowY, SgwWidgetResultFn fn,
                                  void *context)
{
    return runOnGuiThread([=] { return startWidgetMenu(windowX, windowY, fn, context); });
}

extern "C" int sgw_openWindowFixture(int kind, SgwWidgetResultFn fn, void *context)
{
    return runOnGuiThread([=] { return startWindowFixture(kind, fn, context); });
}

extern "C" void sgw_installWidgetInteropSmoke(void)
{
    // Defined in widget_interop_smoke.cpp; keeping the gate there leaves the
    // host free of verification-only code paths.
    sgw_installWidgetInteropSmokeImpl();
}
