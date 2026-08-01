#include "ui/automationarea.h"
#include "ui/automationpage.h"
#include "ui/editordrawer.h"
#include "ui/songview.h"
#include "ui/velocityarea.h"

#include <QApplication>

#include <QAction>
#include <QFocusEvent>
#include <QCoreApplication>
#include <QMouseEvent>
#include <QStackedWidget>
#include <QTabBar>
#include <QVBoxLayout>

#include <algorithm>
#include <cstdio>
#include <utility>
#include <vector>

#include "ui/layout.h"

namespace {

void sendMouse(QWidget *widget, QEvent::Type type, const QPoint &position, Qt::MouseButton button,
               Qt::MouseButtons buttons)
{
    QMouseEvent event(type, QPointF(position), QPointF(widget->mapToGlobal(position)), button, buttons,
                      Qt::NoModifier);
    QCoreApplication::sendEvent(widget, &event);
}

class WidgetObserver final : public QObject {
  public:
    explicit WidgetObserver(QWidget *widget) : m_widget(widget) {}

    int hideEvents = 0;
    int focusInEvents = 0;

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (watched == m_widget) {
            if (event->type() == QEvent::Hide)
                ++hideEvents;
            else if (event->type() == QEvent::FocusIn)
                ++focusInEvents;
        }
        return QObject::eventFilter(watched, event);
    }

  private:
    QWidget *m_widget = nullptr;
};

} // namespace

int runEditorDrawerCheck(const QString &screenshotPath)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "drawer: FAIL: %s\n", message);
            ++failures;
        }
    };

    SongView view;
    view.setObjectName(QStringLiteral("drawerCheckHost"));
    view.resize(std::max(layout::editorGeometry().plotOrigin * 2, 640), 480);
    view.show();
    QCoreApplication::processEvents();

    auto *drawer = view.editorDrawer();
    auto *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    auto *automationPage = drawer ? drawer->automationPage() : nullptr;
    auto *automationCanvas = automationPage ? automationPage->area() : nullptr;
    auto *velocityCanvas = drawer ? drawer->velocityArea() : nullptr;
    check(drawer && roll && automationPage && automationCanvas && velocityCanvas,
          "concrete SongView did not expose its drawer pages");
    if (!drawer || !roll || !automationPage || !automationCanvas || !velocityCanvas)
        return 1;

    std::vector<QString> statuses;
    std::vector<EditorViewState> publishedStates;
    QObject::connect(&view, &SongView::statusMessage, [&statuses](const QString &status) {
        statuses.push_back(status);
    });
    const auto observeState = [&publishedStates, &view] {
        publishedStates.push_back(view.editorViewState());
    };

    WidgetObserver automationEvents(automationPage);
    WidgetObserver velocityEvents(velocityCanvas);
    WidgetObserver rollEvents(roll);
    automationPage->installEventFilter(&automationEvents);
    velocityCanvas->installEventFilter(&velocityEvents);
    roll->installEventFilter(&rollEvents);

    const QRect rollBefore = roll->geometry();
    auto *tabs = drawer->findChild<QTabBar *>(QStringLiteral("editorDrawerTabs"));
    auto *handle = drawer->findChild<QWidget *>(QStringLiteral("editorDrawerResizeHandle"));
    auto *stack = drawer->findChild<QStackedWidget *>(QStringLiteral("editorDrawerPages"));
    check(tabs && handle && stack, "drawer controls were not created");
    if (tabs && handle && stack) {
        check(tabs->count() == 2 && tabs->tabText(0) == QStringLiteral("Automations")
                  && tabs->tabText(1) == QStringLiteral("Velocity"),
              "drawer tab labels differ from the contract");
        check(tabs->tabToolTip(0) == QStringLiteral("Show or hide automation lanes (A)")
                  && tabs->tabToolTip(1) == QStringLiteral("Show or hide note velocities (V)"),
              "drawer tab tooltips differ from the contract");
        check(tabs->focusPolicy() == Qt::NoFocus && stack->focusPolicy() == Qt::NoFocus,
              "drawer chrome joined the focus chain");
        check(tabs->x() == 0 && tabs->y() == 0
                  && tabs->width() == layout::editorGeometry().trackHeaderWidth
                  && tabs->tabRect(0).right() + 1 == tabs->tabRect(1).left()
                  && tabs->tabRect(1).right() + 1 == tabs->width()
                  && handle->y() == tabs->geometry().bottom() + 1
                  && handle->geometry().bottom() + 1 == stack->y(),
              "drawer resize handle does not sit below its tabs");
        const QPoint velocityTabCenter = tabs->tabRect(1).center();
        sendMouse(tabs, QEvent::MouseButtonPress, velocityTabCenter, Qt::LeftButton, Qt::LeftButton);
        sendMouse(tabs, QEvent::MouseButtonRelease, velocityTabCenter, Qt::LeftButton, Qt::NoButton);
        QCoreApplication::processEvents();
        observeState();
        check(view.drawerVisible() && view.drawerPage() == EditorDrawerPage::Velocity,
              "clicking the Velocity tab did not open its drawer page");
        view.setDrawerPage(EditorDrawerPage::Automations);
        observeState();
        check(drawer->parentWidget()
                  && drawer->geometry().bottom() == drawer->parentWidget()->rect().bottom()
                  && roll->geometry() == rollBefore,
              "drawer overlay changed the roll geometry");
        check(drawer->plotOrigin() == layout::editorGeometry().plotOrigin && drawer->plotWidth() > 0,
              "drawer did not derive a usable plot geometry");
        check(handle->x() == 0 && handle->width() == drawer->width(),
              "resize handle does not span the drawer beneath its tabs");
        check(drawer->automationAction()->shortcuts().isEmpty()
                  && drawer->velocityAction()->shortcuts().isEmpty(),
              "drawer actions compete with the window A/V shortcuts");

        const int heightBeforeRightDrag = drawer->drawerHeight();
        const QPoint handleCenter = handle->rect().center();
        sendMouse(handle, QEvent::MouseButtonPress, handleCenter, Qt::RightButton, Qt::RightButton);
        sendMouse(handle, QEvent::MouseMove, handleCenter - QPoint(0, 40), Qt::NoButton,
                  Qt::RightButton);
        sendMouse(handle, QEvent::MouseButtonRelease, handleCenter - QPoint(0, 40), Qt::RightButton,
                  Qt::NoButton);
        check(drawer->drawerHeight() == heightBeforeRightDrag, "right drag resized the drawer");

        sendMouse(handle, QEvent::MouseButtonPress, handleCenter, Qt::LeftButton, Qt::LeftButton);
        sendMouse(handle, QEvent::MouseMove, handleCenter - QPoint(0, 40), Qt::NoButton,
                  Qt::LeftButton);
        sendMouse(handle, QEvent::MouseButtonRelease, handleCenter - QPoint(0, 40), Qt::LeftButton,
                  Qt::NoButton);
        check(drawer->drawerHeight() > heightBeforeRightDrag
                  && drawer->drawerHeight() <= drawer->maximumDrawerHeight()
                  && QWidget::mouseGrabber() == nullptr,
              "left resize did not clamp or resume follow scrolling");
        view.setDrawerHeight(-1);
        check(view.drawerHeight() == drawer->minimumDrawerHeight(),
              "drawer minimum height was not enforced");
        view.setDrawerHeight(view.height() * 2);
        check(view.drawerHeight() == drawer->maximumDrawerHeight(),
              "drawer maximum height was not enforced");

        const int automationHidesBeforeSwitch = automationEvents.hideEvents;
        drawer->velocityAction()->trigger();
        QCoreApplication::processEvents();
        observeState();
        check(view.drawerVisible() && view.drawerPage() == EditorDrawerPage::Velocity
                  && !publishedStates.empty() && publishedStates.back().drawerVisible
                  && publishedStates.back().drawerPage == EditorDrawerPage::Velocity
                  && !statuses.empty() && statuses.back() == QStringLiteral("Velocity lane shown")
                  && automationEvents.hideEvents > automationHidesBeforeSwitch
                  && QApplication::focusWidget() == velocityCanvas,
              "velocity action did not switch, cancel, focus, and announce");
        QFocusEvent drawerCanvasFocus(QEvent::FocusIn, Qt::OtherFocusReason);
        QCoreApplication::sendEvent(velocityCanvas, &drawerCanvasFocus);

        const int velocityHidesBeforeClose = velocityEvents.hideEvents;
        const int mainFocusBeforeClose = rollEvents.focusInEvents;
        drawer->velocityAction()->trigger();
        QCoreApplication::processEvents();
        observeState();
        check(!view.drawerVisible() && view.drawerPage() == EditorDrawerPage::Velocity
                  && !publishedStates.empty() && !publishedStates.back().drawerVisible
                  && publishedStates.back().drawerPage == EditorDrawerPage::Velocity
                  && !statuses.empty() && statuses.back() == QStringLiteral("Velocity lane hidden")
                  && velocityEvents.hideEvents > velocityHidesBeforeClose
                  && rollEvents.focusInEvents > mainFocusBeforeClose,
              "visible velocity action did not close, cancel, and return focus");
        drawer->automationAction()->trigger();
        QCoreApplication::processEvents();
        observeState();
        check(view.drawerVisible() && view.drawerPage() == EditorDrawerPage::Automations
                  && !publishedStates.empty() && publishedStates.back().drawerVisible
                  && publishedStates.back().drawerPage == EditorDrawerPage::Automations
                  && !statuses.empty() && statuses.back() == QStringLiteral("Automation lanes shown"),
              "automation action did not open and announce");
        const int automationHidesBeforeClose = automationEvents.hideEvents;
        drawer->automationAction()->trigger();
        QCoreApplication::processEvents();
        observeState();
        check(!view.drawerVisible() && view.drawerPage() == EditorDrawerPage::Automations
                  && !publishedStates.empty() && !publishedStates.back().drawerVisible
                  && publishedStates.back().drawerPage == EditorDrawerPage::Automations
                  && !statuses.empty() && statuses.back() == QStringLiteral("Automation lanes hidden")
                  && automationEvents.hideEvents > automationHidesBeforeClose,
              "automation action did not close and announce");
        view.setDrawerVisible(true);
        observeState();
        QFocusEvent restoredCanvasFocus(QEvent::FocusIn, Qt::OtherFocusReason);
        QCoreApplication::sendEvent(automationCanvas, &restoredCanvasFocus);
        const int mainFocusBeforeStateClose = rollEvents.focusInEvents;
        EditorViewState restoredClose = view.editorViewState();
        restoredClose.drawerVisible = false;
        view.applyEditorViewState(restoredClose);
        observeState();
        check(rollEvents.focusInEvents > mainFocusBeforeStateClose,
              "restored drawer close did not return canvas focus to the host");

        view.setDrawerPage(EditorDrawerPage::Automations);
        automationCanvas->hide();
        view.setDrawerVisible(false);
        const QWidget *focusBeforeHiddenAutomation = QApplication::focusWidget();
        view.setDrawerPage(EditorDrawerPage::Automations);
        observeState();
        check(QApplication::focusWidget() == focusBeforeHiddenAutomation,
              "a hidden canvas received a focus request");
        automationCanvas->show();

        const QRect parentBounds = drawer->parentWidget()->rect();
        const int narrowWidth = std::max(0, drawer->plotOrigin() - layout::singlePixel());
        const QRect narrowBounds(parentBounds.left(), parentBounds.top(), narrowWidth,
                                 parentBounds.height());
        const QRect rollBeforeNarrow = roll->geometry();
        drawer->setHostBounds(narrowBounds);
        QCoreApplication::processEvents();
        check(drawer->plotWidth() == 0 && !stack->isVisible()
                  && roll->geometry().top() == rollBeforeNarrow.top()
                  && roll->geometry().height() == rollBeforeNarrow.height(),
              "narrow drawer left page content visible through the gutter");
        drawer->useParentBounds();
        QCoreApplication::processEvents();
    }

    if (!screenshotPath.isEmpty()) {
        view.setDrawerVisible(true);
        view.setDrawerPage(EditorDrawerPage::Automations);
        QCoreApplication::processEvents();
        view.grab().save(screenshotPath);
    }
    std::printf("drawer: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0 ? 0 : 1;
}
