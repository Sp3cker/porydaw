#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEvent>
#include <QGuiApplication>
#include <QImage>
#include <QObject>
#include <QPointF>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QStyleHints>
#include <QThread>
#include <QUrl>
#include <QWindow>
#include <QtTest/QTest>
#include <qqml.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <utility>

// Real-input SongView scenarios for the two timeline scrollbars; defined in
// scrollbarquickcheck_songview.cpp and run against this check's exposed view.
void runSongViewScrollbarChecks(SongView &view, int &failures);

namespace {

constexpr int kViewWidth = 1280;
constexpr int kViewHeight = 800;
constexpr int kExposurePollMilliseconds = 10;
constexpr int kExposureTimeoutMilliseconds = 1000;
constexpr qreal kGeometryTolerance = 0.01;

constexpr auto kStandaloneScrollbarQml = R"(
import QtQuick
import Porydaw.Ui
Item {
    id: root
    property real modelMinimum: -80
    property real modelMaximum: 80
    property real modelValue: -80
    property real modelPageStep: 20
    x: 40
    y: 40
    width: 240
    height: 20
    TimelineScrollbar {
        id: control
        objectName: "standaloneTimelineScrollbar"
        anchors.fill: parent
        orientation: Qt.Horizontal
        minimum: root.modelMinimum
        maximum: root.modelMaximum
        value: root.modelValue
        pageStep: root.modelPageStep
        singleStep: 5
        minimumThumbLength: 24
        handleColor: Qt.white
        handleHoverColor: Qt.white
        visibleWhenNotScrollable: true
        thumbObjectName: "standaloneTimelineScrollbarThumb"
        onValueRequested: (value) => root.modelValue = value
    }
}
)";

QQuickItem *createStandaloneScrollbar(QQuickItem &sceneRoot, QString &error)
{
    QQmlEngine *const engine = qmlEngine(&sceneRoot);
    if (!engine) {
        error = QStringLiteral("Quick scene has no QML engine");
        return nullptr;
    }
    QQmlComponent component(engine);
    component.setData(kStandaloneScrollbarQml,
                      QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/ScrollbarQuickCheck.qml")));
    if (component.status() != QQmlComponent::Ready) {
        error = component.errorString();
        return nullptr;
    }
    QObject *const object = component.create();
    auto *const item = qobject_cast<QQuickItem *>(object);
    if (!item) {
        delete object;
        error = QStringLiteral("standalone scrollbar component did not create a Quick item");
        return nullptr;
    }
    item->setParentItem(&sceneRoot);
    return item;
}

void processWindowEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

bool waitForNativeWindowExposure(SongView &view)
{
    QElapsedTimer elapsed;
    elapsed.start();
    do {
        processWindowEvents();
        QWindow *const window = view.windowHandle();
        if (view.isVisible() && window && window->isExposed())
            return true;
        QThread::msleep(kExposurePollMilliseconds);
    } while (elapsed.elapsed() < kExposureTimeoutMilliseconds);
    return false;
}

void check(int &failures, bool condition, const char *message)
{
    if (condition)
        return;
    std::fprintf(stderr, "scrollbarquickcheck: FAIL: %s\n", message);
    ++failures;
}
bool near(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kGeometryTolerance;
}

bool thumbIsWithinTrack(const QQuickItem &scrollbar, const QQuickItem &thumb,
                        Qt::Orientation orientation)
{
    if (orientation == Qt::Horizontal) {
        return thumb.x() >= -kGeometryTolerance &&
               thumb.x() + thumb.width() <= scrollbar.width() + kGeometryTolerance &&
               near(thumb.y(), 0.0) && near(thumb.height(), scrollbar.height());
    }
    return thumb.y() >= -kGeometryTolerance &&
           thumb.y() + thumb.height() <= scrollbar.height() + kGeometryTolerance &&
           near(thumb.x(), 0.0) && near(thumb.width(), scrollbar.width());
}

void sendWindowMouse(QQuickWindow &window, QEvent::Type type, QPointF windowPosition,
                     Qt::MouseButton button)
{
    const QPoint position = windowPosition.toPoint();
    switch (type) {
    case QEvent::MouseButtonPress:
        QTest::mousePress(&window, button, Qt::NoModifier, position);
        break;
    case QEvent::MouseMove:
        QTest::mouseMove(&window, position);
        break;
    case QEvent::MouseButtonRelease:
        QTest::mouseRelease(&window, button, Qt::NoModifier, position);
        break;
    default:
        Q_UNREACHABLE();
    }
    processWindowEvents();
}

void sendItemMouse(QQuickWindow &window, const QQuickItem &item, QEvent::Type type,
                   QPointF itemPosition, Qt::MouseButton button)
{
    sendWindowMouse(window, type, item.mapToScene(itemPosition), button);
}

qreal thumbPositionFor(qreal value, qreal minimum, qreal maximum, qreal thumbTravel)
{
    if (maximum <= minimum)
        return 0.0;
    return (value - minimum) / (maximum - minimum) * thumbTravel;
}

} // namespace

int runScrollbarQuickCheck(const QString &projectRoot, const QString &songLabel)
{
    QString error;
    auto loadedSong = checks::LoadedSong::load(projectRoot, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "scrollbarquickcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto rig = checks::SongViewRig::create(std::move(loadedSong), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "scrollbarquickcheck: %s\n", qUtf8Printable(error));
        return 1;
    }

    int failures = 0;
    SongView &view = rig->view();
    const auto finish = [&] {
        view.close();
        processWindowEvents();
        std::fprintf(stderr, "scrollbarquickcheck: %s\n", failures == 0 ? "PASS" : "FAIL");
        return failures == 0 ? 0 : 1;
    };

    view.resize(kViewWidth, kViewHeight);
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 180);
    view.show();
    if (!waitForNativeWindowExposure(view)) {
        check(failures, false, "SongView did not expose a native window");
        return finish();
    }
    checks::support::pumpQuick();

    EditorDrawer *const drawer = view.editorDrawer();
    auto *const quick = view.quickView();
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    auto *const scrollbar =
        root ? root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollBar")) : nullptr;
    auto *const thumb =
        root ? root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollThumb"))
             : nullptr;
    if (!drawer || !quick || !root || !window || !scrollbar || !thumb) {
        check(failures, false, "automation drawer did not expose its real QML scrollbar and thumb");
        return finish();
    }

    AutomationPage *const page = drawer->automationPage();
    DrawerChrome &chrome = drawer->chrome();
    check(failures, page && scrollbar->isVisible() && thumb->isVisible(),
          "automation drawer scrollbar was not visible in the real Quick window");
    if (!page || !scrollbar->isVisible() || !thumb->isVisible())
        return finish();

    QString framebufferError;
    const QImage initialFrame = checks::support::captureQuickBand(
        view, chrome.automationScrollbarRect().toAlignedRect(), &framebufferError);
    if (initialFrame.isNull()) {
        if (framebufferError.isEmpty())
            framebufferError = QStringLiteral("captureQuickBand returned a null image");
        std::fprintf(stderr, "scrollbarquickcheck: %s\n", qUtf8Printable(framebufferError));
    }
    check(failures, !initialFrame.isNull(), "automation scrollbar framebuffer capture failed");

    const int maximumScroll = chrome.automationMaximumScrollY();
    check(failures, maximumScroll > 0 && scrollbar->height() > thumb->height(),
          "Route 101 fixture did not create a scrollable automation drawer");
    if (maximumScroll <= 0 || scrollbar->height() <= thumb->height())
        return finish();
    const auto checkVertical = [&](bool condition, const char *message) {
        if (condition)
            return;
        std::fprintf(stderr, "scrollbarquickcheck: FAIL: %s\n", message);
        std::fprintf(stderr,
                     "scrollbarquickcheck: value=%d/%d track=(%.2f x %.2f) "
                     "thumb=(x=%.2f y=%.2f w=%.2f h=%.2f)\n",
                     page->verticalScroll(), maximumScroll, scrollbar->width(), scrollbar->height(),
                     thumb->x(), thumb->y(), thumb->width(), thumb->height());
        ++failures;
    };

    page->setVerticalScroll(0);
    checks::support::pumpQuick();
    const QPointF pageForwardPoint(scrollbar->width() / 2.0,
                                   thumb->y() + thumb->height() +
                                       (scrollbar->height() - thumb->y() - thumb->height()) / 2.0);
    const int expectedPageForward = std::min(
        maximumScroll, static_cast<int>(std::lround(scrollbar->property("pageStep").toReal())));
    sendItemMouse(*window, *scrollbar, QEvent::MouseButtonPress, pageForwardPoint, Qt::LeftButton);
    sendItemMouse(*window, *scrollbar, QEvent::MouseButtonRelease, pageForwardPoint,
                  Qt::LeftButton);
    checks::support::pumpQuick();
    check(failures, page->verticalScroll() == expectedPageForward,
          "clicking the automation track after the thumb did not request one forward page");

    // Deliver to QQuickWindow, not the item: this reaches DragHandler and preserves its live grab.
    // The threshold-crossing move activates DragHandler; the following local move establishes
    // translation before testing continuation beyond the scrollbar track.
    const qreal activationDistance =
        static_cast<qreal>(QGuiApplication::styleHints()->startDragDistance()) + 1.0;
    page->setVerticalScroll(0);
    checks::support::pumpQuick();
    const QPointF bottomPress = thumb->boundingRect().center();
    const QPointF bottomPressWindow = thumb->mapToScene(bottomPress);
    sendItemMouse(*window, *thumb, QEvent::MouseButtonPress, bottomPress, Qt::LeftButton);
    const QPointF bottomActivation = bottomPressWindow + QPointF(0.0, activationDistance);
    sendWindowMouse(*window, QEvent::MouseMove, bottomActivation, Qt::NoButton);
    const QPointF bottomDragPoint = bottomActivation + QPointF(0.0, 1.0);
    sendWindowMouse(*window, QEvent::MouseMove, bottomDragPoint, Qt::NoButton);
    checks::support::pumpQuick();
    checkVertical(page->verticalScroll() > 0 && page->verticalScroll() < maximumScroll,
                  "an in-window downward drag did not establish an in-range automation value");
    const QPointF farBelow(bottomPressWindow.x(), window->height() - 1.0);
    sendWindowMouse(*window, QEvent::MouseMove, farBelow, Qt::NoButton);
    checks::support::pumpQuick();
    checkVertical(
        page->verticalScroll() == maximumScroll,
        "dragging the automation thumb below its track did not request the content maximum");
    checkVertical(near(thumb->y() + thumb->height(), scrollbar->height()),
                  "automation thumb did not reach the held bottom endpoint");
    checkVertical(thumbIsWithinTrack(*scrollbar, *thumb, Qt::Vertical),
                  "automation thumb left the track bounds at the held bottom endpoint");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, farBelow, Qt::LeftButton);

    page->setVerticalScroll(maximumScroll);
    checks::support::pumpQuick();
    const QPointF pressPoint = thumb->boundingRect().center();
    const QPointF topPressWindow = thumb->mapToScene(pressPoint);
    sendItemMouse(*window, *thumb, QEvent::MouseButtonPress, pressPoint, Qt::LeftButton);
    const QPointF topActivation = topPressWindow - QPointF(0.0, activationDistance);
    sendWindowMouse(*window, QEvent::MouseMove, topActivation, Qt::NoButton);
    const QPointF topDragPoint = topActivation - QPointF(0.0, 1.0);
    sendWindowMouse(*window, QEvent::MouseMove, topDragPoint, Qt::NoButton);
    checks::support::pumpQuick();
    checkVertical(page->verticalScroll() > 0 && page->verticalScroll() < maximumScroll,
                  "an in-window upward drag did not establish an in-range automation value");
    const QPointF farAbove(topPressWindow.x(), 1.0);
    sendWindowMouse(*window, QEvent::MouseMove, farAbove, Qt::NoButton);
    checks::support::pumpQuick();
    checkVertical(
        page->verticalScroll() == 0,
        "dragging the automation thumb above its track did not request the content minimum");
    checkVertical(near(thumb->y(), 0.0), "automation thumb did not reach the held top endpoint");
    checkVertical(thumbIsWithinTrack(*scrollbar, *thumb, Qt::Vertical),
                  "automation thumb left the track bounds at the held top endpoint");

    const QPointF furtherAbove(topPressWindow.x(), 0.0);
    sendWindowMouse(*window, QEvent::MouseMove, furtherAbove, Qt::NoButton);
    checks::support::pumpQuick();
    checkVertical(page->verticalScroll() == 0,
                  "continued held drag above the track did not remain at the content minimum");
    checkVertical(thumbIsWithinTrack(*scrollbar, *thumb, Qt::Vertical),
                  "automation thumb left the track bounds during a held, clamped drag");

    const QPointF reversePoint =
        scrollbar->mapToScene(QPointF(scrollbar->width() / 2.0, scrollbar->height() / 2.0));
    sendWindowMouse(*window, QEvent::MouseMove, reversePoint, Qt::NoButton);
    checks::support::pumpQuick();
    const int reverseValue = page->verticalScroll();
    checkVertical(reverseValue > 0 && reverseValue < maximumScroll,
                  "reversing a held clamped drag did not resume an in-range automation value");
    checkVertical(thumbIsWithinTrack(*scrollbar, *thumb, Qt::Vertical),
                  "the resumed in-range automation thumb left the track bounds");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, reversePoint, Qt::LeftButton);
    page->setVerticalScroll(maximumScroll / 3);
    checks::support::pumpQuick();
    const qreal expectedVerticalY = thumbPositionFor(page->verticalScroll(), 0.0, maximumScroll,
                                                     scrollbar->height() - thumb->height());
    check(failures, near(thumb->y(), expectedVerticalY),
          "model-driven automation value did not reposition the thumb after reverse drag release");

    // Resize the actual drawer model to its fitting viewport; the still-visible control must render
    // a full thumb without any test-side mutation of its public QML inputs.
    const int scrollbarSectionHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int scrollbarSectionOverhead =
        std::max(0, scrollbarSectionHeight - chrome.automationViewportHeight());
    const int fittingSectionHeight =
        std::min(drawer->maximumSectionHeight(),
                 page->canvas()->minimumContentHeight() + scrollbarSectionOverhead);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, fittingSectionHeight);
    checks::support::pumpQuick();
    const bool fullThumb = chrome.automationMaximumScrollY() == 0 && thumb->isVisible() &&
                           near(thumb->height(), scrollbar->height()) &&
                           thumbIsWithinTrack(*scrollbar, *thumb, Qt::Vertical);
    check(failures, fullThumb,
          "non-scrollable automation scrollbar did not expose a full, in-track thumb");
    const QPointF zeroRangePress = thumb->boundingRect().center();
    sendItemMouse(*window, *thumb, QEvent::MouseButtonPress, zeroRangePress, Qt::LeftButton);
    const QPointF zeroRangeAbove =
        thumb->mapToScene(zeroRangePress) + QPointF(0.0, -2.0 * scrollbar->height());
    sendWindowMouse(*window, QEvent::MouseMove, zeroRangeAbove, Qt::NoButton);
    check(failures,
          page->verticalScroll() == 0 && near(thumb->height(), scrollbar->height()) &&
              thumbIsWithinTrack(*scrollbar, *thumb, Qt::Vertical),
          "held drag moved the non-scrollable full thumb or its content");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, zeroRangeAbove, Qt::LeftButton);
    check(failures,
          page->verticalScroll() == 0 && near(thumb->height(), scrollbar->height()) &&
              thumbIsWithinTrack(*scrollbar, *thumb, Qt::Vertical),
          "releasing a non-scrollable full-thumb drag changed its content or geometry");

    // This imports the shared QML type into the real production QQuickWindow, but has its
    // own bound authoritative model so no automation consumer can clamp the signed range.
    QString standaloneError;
    QQuickItem *const standaloneRoot = createStandaloneScrollbar(*root, standaloneError);
    auto *const standalone =
        standaloneRoot
            ? standaloneRoot->findChild<QQuickItem *>(QStringLiteral("standaloneTimelineScrollbar"))
            : nullptr;
    auto *const standaloneThumb = standaloneRoot
                                      ? standaloneRoot->findChild<QQuickItem *>(
                                            QStringLiteral("standaloneTimelineScrollbarThumb"))
                                      : nullptr;
    if (!standalone || !standaloneThumb) {
        if (standaloneError.isEmpty())
            standaloneError = QStringLiteral("standalone scrollbar or thumb object is unavailable");
        std::fprintf(stderr, "scrollbarquickcheck: %s\n", qUtf8Printable(standaloneError));
        check(failures, false,
              "standalone shared scrollbar did not load from the production QML module");
        return finish();
    }
    checks::support::pumpQuick();

    const qreal expectedInitialWidth = 20.0 / (80.0 - -80.0 + 20.0) * standalone->width();
    check(failures,
          near(standaloneThumb->width(), expectedInitialWidth) &&
              thumbIsWithinTrack(*standalone, *standaloneThumb, Qt::Horizontal),
          "signed horizontal range did not size its thumb from the actual track length");

    const QPointF horizontalPress = standaloneThumb->boundingRect().center();
    const QPointF horizontalPressWindow = standaloneThumb->mapToScene(horizontalPress);
    sendItemMouse(*window, *standaloneThumb, QEvent::MouseButtonPress, horizontalPress,
                  Qt::LeftButton);
    const QPointF horizontalActivation = horizontalPressWindow + QPointF(activationDistance, 0.0);
    sendWindowMouse(*window, QEvent::MouseMove, horizontalActivation, Qt::NoButton);
    const QPointF initialMove = horizontalPressWindow + QPointF(standalone->width() / 4.0, 0.0);
    sendWindowMouse(*window, QEvent::MouseMove, initialMove, Qt::NoButton);
    checks::support::pumpQuick();
    const qreal valueBeforeResize = standaloneRoot->property("modelValue").toReal();
    check(failures, valueBeforeResize > -80.0 && valueBeforeResize < 80.0,
          "initial held horizontal drag did not establish an in-range model value");

    standaloneRoot->setProperty("modelMaximum", 180.0);
    standaloneRoot->setProperty("modelPageStep", 60.0);
    checks::support::pumpQuick();
    const qreal valueAfterResize = standaloneRoot->property("modelValue").toReal();
    const qreal resizedTravel = standalone->property("thumbTravel").toReal();
    const qreal expectedResizedWidth = 60.0 / (180.0 - -80.0 + 60.0) * standalone->width();
    check(failures,
          near(valueAfterResize, valueBeforeResize) &&
              near(standaloneThumb->width(), expectedResizedWidth) &&
              thumbIsWithinTrack(*standalone, *standaloneThumb, Qt::Horizontal),
          "range and viewport change during held drag changed the model or escaped the track");
    check(failures, resizedTravel > 0.0,
          "range and viewport change removed all horizontal thumb travel");

    const QPointF tinyMove = initialMove + QPointF(1.0, 0.0);
    sendWindowMouse(*window, QEvent::MouseMove, tinyMove, Qt::NoButton);
    checks::support::pumpQuick();
    const qreal expectedTinyMove =
        valueAfterResize + (resizedTravel > 0.0 ? 260.0 / resizedTravel : 0.0);
    check(
        failures, near(standaloneRoot->property("modelValue").toReal(), expectedTinyMove),
        "range and viewport change replayed stale drag distance instead of applying local motion");

    const QPointF farRight =
        standaloneThumb->mapToScene(horizontalPress) + QPointF(2.0 * standalone->width(), 0.0);
    sendWindowMouse(*window, QEvent::MouseMove, farRight, Qt::NoButton);
    checks::support::pumpQuick();
    check(failures, near(standaloneRoot->property("modelValue").toReal(), 180.0),
          "held horizontal drag did not update the independent model for the new range");
    check(failures,
          near(standaloneThumb->x() + standaloneThumb->width(), standalone->width()) &&
              thumbIsWithinTrack(*standalone, *standaloneThumb, Qt::Horizontal),
          "horizontal thumb did not reach the updated maximum endpoint");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, farRight, Qt::LeftButton);
    standaloneRoot->setProperty("modelValue", 20.0);
    checks::support::pumpQuick();
    const qreal expectedHorizontalX =
        thumbPositionFor(20.0, -80.0, 180.0, standalone->width() - standaloneThumb->width());
    check(failures, near(standaloneThumb->x(), expectedHorizontalX),
          "external horizontal model value did not reposition the thumb after drag release");

    // Real-input SongView scenarios for the two timeline scrollbars that
    // replaced the QWidget bars: same exposed view, same failure counter.
    runSongViewScrollbarChecks(view, failures);

    return finish();
}
