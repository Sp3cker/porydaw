#include "checks/support/quickframebuffer.h"

#include <QEvent>
#include <QGuiApplication>
#include <QLayout>
#include <QPoint>
#include <QPointF>
#include <QPointingDevice>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QSize>
#include <QString>
#include <QStyleHints>
#include <QWheelEvent>
#include <QWindow>
#include <QtTest/QTest>

#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timecamera.h"
#include "ui/songview/timelinebandlayout.h"

#include <algorithm>
#include <cmath>
#include <optional>

// Real-input SongView scenarios for the two timeline scrollbars that replaced
// SongView's QWidget scroll bars: the horizontal timeline bar (bottom row) and
// the vertical piano-roll bar (right of the roll band). Both live in the
// existing TimelineCanvas Quick scene and are driven by the authoritative
// TimeCamera through view.quickView(). Every scenario drives the real
// QQuickWindow input path — QTest mouse, window-delivered wheel and key
// events — and asserts camera state plus rendered geometry, never setter
// echoes. The generic TimelineScrollbar control itself stays covered by
// scrollbarquickcheck.cpp.
namespace {

constexpr qreal kTolerance = 0.01;
constexpr const char *kHorizontalBar = "timelineHorizontalScrollBar";
constexpr const char *kHorizontalThumb = "timelineHorizontalScrollThumb";
constexpr const char *kVerticalBar = "timelineRollScrollBar";
constexpr const char *kVerticalThumb = "timelineRollScrollThumb";

void check(int &failures, bool condition, const char *message)
{
    if (condition)
        return;
    std::fprintf(stderr, "scrollbarquickcheck: FAIL: %s\n", message);
    ++failures;
}

bool near(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kTolerance;
}

void pump()
{
    checks::support::pumpQuick();
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
    pump();
}

void sendItemMouse(QQuickWindow &window, const QQuickItem &item, QEvent::Type type,
                   QPointF itemPosition, Qt::MouseButton button)
{
    sendWindowMouse(window, type, item.mapToScene(itemPosition), button);
}

// Non-mouse wheels reach the scene system-synthesized, the way real
// trackpads deliver; the primary pointer keeps the plain mouse source.
Qt::MouseEventSource wheelSourceFor(const QPointingDevice *device)
{
    return device == QPointingDevice::primaryPointingDevice() ? Qt::MouseEventNotSynthesized
                                                              : Qt::MouseEventSynthesizedBySystem;
}

// Window-delivered wheel event — the same path QQuickWindow gives real
// wheels, with the deltas, inversion flag, and device the scenario chooses.
void sendWindowWheel(QQuickWindow &window, QPointF scenePosition, QPoint pixelDelta,
                     QPoint angleDelta, bool inverted,
                     const QPointingDevice *device = QPointingDevice::primaryPointingDevice())
{
    QWheelEvent event(scenePosition, window.mapToGlobal(scenePosition.toPoint()), pixelDelta,
                      angleDelta, Qt::NoButton, Qt::NoModifier,
                      pixelDelta.isNull() ? Qt::NoScrollPhase : Qt::ScrollUpdate, inverted,
                      wheelSourceFor(device), device);
    QGuiApplication::sendEvent(&window, &event);
    pump();
}

// A phased pixel gesture leaves the QML WheelHandler active until an actual
// ScrollEnd arrives (a NoScrollPhase mouse stream only times out after the
// 100 ms activeTimeout), and an active handler skips the axis filter — so
// every wheel session below closes with a zero-delta ScrollEnd at the same
// position and device before an unrelated case can inherit the gesture.
void endWindowWheelGesture(QQuickWindow &window, QPointF scenePosition,
                           const QPointingDevice *device = QPointingDevice::primaryPointingDevice())
{
    QWheelEvent event(scenePosition, window.mapToGlobal(scenePosition.toPoint()), QPoint(),
                      QPoint(), Qt::NoButton, Qt::NoModifier, Qt::ScrollEnd, false,
                      wheelSourceFor(device), device);
    QGuiApplication::sendEvent(&window, &event);
    pump();
}

void sendWindowKey(QQuickWindow &window, Qt::Key key)
{
    QTest::keyClick(&window, key);
    pump();
}

QQuickItem *findItem(QQuickItem &root, const char *name)
{
    return root.findChild<QQuickItem *>(QString::fromLatin1(name));
}

// Published rects are Quick-root-local; SongView-local is the canonical space
// of the band-layout contract the rects must satisfy.
QRectF songViewRect(const SongView &view, const QRectF &rootRect)
{
    return rootRect.translated(view.quickView()->mapTo(&view, QPoint{}));
}

// The camera is the scroll oracle; thumb geometry below probes what the QML
// bindings made of the same state.
void expectScroll(int &failures, const SongView &view, Qt::Orientation orientation, qreal expected,
                  const char *message)
{
    const songview::TimeCamera &camera = view.camera();
    const qreal cameraValue = orientation == Qt::Horizontal ? camera.scrollX() : camera.scrollY();
    check(failures, near(cameraValue, expected), message);
    if (!near(cameraValue, expected))
        std::fprintf(stderr, "scrollbarquickcheck: actual=%.6f expected=%.6f range=[%.6f, %.6f]\n",
                     cameraValue, expected,
                     orientation == Qt::Horizontal ? camera.minHScroll() : 0.0,
                     orientation == Qt::Horizontal ? camera.maxHScroll() : camera.maxRollScroll());
}

bool thumbIsWithinTrack(const QQuickItem &scrollbar, const QQuickItem &thumb,
                        Qt::Orientation orientation)
{
    if (orientation == Qt::Horizontal) {
        return thumb.x() >= -kTolerance &&
               thumb.x() + thumb.width() <= scrollbar.width() + kTolerance &&
               near(thumb.y(), 0.0) && near(thumb.height(), scrollbar.height());
    }
    return thumb.y() >= -kTolerance &&
           thumb.y() + thumb.height() <= scrollbar.height() + kTolerance && near(thumb.x(), 0.0) &&
           near(thumb.width(), scrollbar.width());
}

// Establish a real drag after crossing the threshold; return its current
// window position so subsequent movements exclude the activation distance.
QPointF beginThumbDrag(QQuickWindow &window, const QQuickItem &thumb, Qt::Orientation orientation)
{
    const QPointF press = thumb.boundingRect().center();
    const QPointF pressWindow = thumb.mapToScene(press);
    sendItemMouse(window, thumb, QEvent::MouseButtonPress, press, Qt::LeftButton);
    const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
    const QPointF activationOffset =
        orientation == Qt::Horizontal ? QPointF(activation, 1.0) : QPointF(1.0, activation);
    sendWindowMouse(window, QEvent::MouseMove, pressWindow + activationOffset, Qt::NoButton);
    const QPointF dragPoint =
        pressWindow + activationOffset +
        (orientation == Qt::Horizontal ? QPointF(1.0, 0.0) : QPointF(0.0, 1.0));
    sendWindowMouse(window, QEvent::MouseMove, dragPoint, Qt::NoButton);
    return dragPoint;
}

} // namespace

void runSongViewScrollbarChecks(SongView &view, int &failures)
{
    // Every mutated view state is captured here and restored on every exit so
    // the pre-existing generic-control scenarios and the rest of the suite
    // stay isolated.
    const QSize initialSize = view.size();
    const int initialDrawerHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const bool initialEventList = view.eventListVisible();
    const bool initialFold = view.scaleFold();
    const double initialPxPerBeat = view.pxPerBeat();
    const double initialScrollX = view.camera().scrollX();
    const double initialScrollY = view.camera().scrollY();
    const auto restore = [&] {
        if (view.size() != initialSize)
            view.resize(initialSize);
        view.setDrawerSectionHeight(EditorDrawerPage::Automations, initialDrawerHeight);
        if (view.eventListVisible() != initialEventList)
            view.setEventListVisible(initialEventList);
        if (view.scaleFold() != initialFold)
            view.setScaleFold(initialFold);
        view.setEditorTimeZoom(initialPxPerBeat);
        view.setHScroll(initialScrollX);
        view.setVScroll(initialScrollY);
        pump();
    };

    // The preceding generic-control scenarios hand over whatever window,
    // zoom, and lane state they finished with, and the page-margin guard
    // below needs real range to page within: establish a standard editor
    // viewport at a moderate beat scale with the roll lane unfolded and the
    // event list off. All of it restores through `restore`.
    view.resize(1280, 800);
    pump();
    view.setEditorTimeZoom(64.0);
    // A deliberate tall automation section keeps the roll viewport small
    // enough for the page-margin guard at any font scale, and stays clear
    // of the +80 scenario below.
    view.setDrawerSectionHeight(EditorDrawerPage::Automations,
                                std::max(400, initialDrawerHeight + 160));
    view.setScaleFold(false);
    view.setEventListVisible(false);
    pump();

    songview::TimelineQuickView *const quick = view.quickView();
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const horizontalBar = root ? findItem(*root, kHorizontalBar) : nullptr;
    QQuickItem *const horizontalThumb = root ? findItem(*root, kHorizontalThumb) : nullptr;
    QQuickItem *const verticalBar = root ? findItem(*root, kVerticalBar) : nullptr;
    QQuickItem *const verticalThumb = root ? findItem(*root, kVerticalThumb) : nullptr;
    if (!quick || !root || !window || !horizontalBar || !horizontalThumb || !verticalBar ||
        !verticalThumb) {
        check(failures, false,
              "SongView Quick scene lacks the contracted timeline scrollbar objects");
        restore();
        return;
    }

    // Geometry contract: the horizontal row starts at the canonical split,
    // ends at the content right, and reserves the shared breadth below the
    // other-events spacer; the vertical bar sits directly right of the
    // drawer-clipped roll band, outside the plot surface.
    const songview::TimelineBandLayout &bands = view.timelineBandLayout();
    const std::optional<songview::TimelineBandGeometry> roll =
        bands.geometry(songview::TimelineBand::Roll);
    const std::optional<songview::TimelineBandGeometry> otherEvents =
        bands.geometry(songview::TimelineBand::OtherEvents);
    if (!roll || !otherEvents) {
        check(failures, false, "canonical band layout lacks roll and other-events geometry");
        restore();
        return;
    }
    const QRectF horizontalRect = songViewRect(view, quick->horizontalScrollbarRect());
    const QRectF verticalRect = songViewRect(view, quick->verticalScrollbarRect());
    check(failures, !horizontalRect.isEmpty(),
          "horizontal scrollbar geometry is absent in roll mode");
    check(failures, !verticalRect.isEmpty(), "vertical scrollbar geometry is absent in roll mode");
    check(failures,
          near(horizontalRect.left(), view.timelineSplitX()) &&
              near(horizontalRect.right(), view.width()) &&
              near(horizontalRect.height(), layout::space(layout::Space::Two)),
          "horizontal row does not run from the canonical split to the content right "
          "at the shared breadth");
    check(failures,
          near(horizontalRect.top(), otherEvents->rect.top() + otherEvents->rect.height()),
          "horizontal row is not directly below the other-events spacer row");
    check(failures,
          near(verticalRect.left(), roll->rect.left() + roll->rect.width()) &&
              near(verticalRect.width(), layout::space(layout::Space::Two)) &&
              near(verticalRect.top(), roll->rect.top()) &&
              near(verticalRect.height(), roll->rect.height()),
          "vertical scrollbar is not docked right of the drawer-clipped roll band");
    check(failures, roll->plotRect.right() <= verticalRect.left() + kTolerance,
          "roll plot surface extends into the vertical scrollbar gutter");
    check(failures,
          horizontalBar->isVisible() && horizontalThumb->isVisible() && verticalBar->isVisible() &&
              verticalThumb->isVisible(),
          "timeline scrollbar items are not visible in roll mode");
    check(failures,
          thumbIsWithinTrack(*horizontalBar, *horizontalThumb, Qt::Horizontal) &&
              thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "timeline thumbs render outside their tracks in roll mode");

    // The Quick host envelope must cover both bars or the crops fall outside
    // the framebuffer — the rendering-side form of the clipping regression.
    QString framebufferError;
    const QImage horizontalFrame =
        checks::support::captureQuickBand(view, horizontalRect.toAlignedRect(), &framebufferError);
    if (!framebufferError.isEmpty())
        std::fprintf(stderr, "scrollbarquickcheck: %s\n", qUtf8Printable(framebufferError));
    check(failures, !horizontalFrame.isNull(),
          "horizontal row did not render inside the Quick framebuffer");
    const QImage verticalFrame =
        checks::support::captureQuickBand(view, verticalRect.toAlignedRect(), &framebufferError);
    if (!framebufferError.isEmpty())
        std::fprintf(stderr, "scrollbarquickcheck: %s\n", qUtf8Printable(framebufferError));
    check(failures, !verticalFrame.isNull(),
          "vertical gutter did not render inside the Quick framebuffer");

    // Camera bounds and fixture range guards for the paged scenarios below.
    const songview::TimeCamera &camera = view.camera();
    const qreal hMinimum = camera.minHScroll();
    const qreal hMaximum = camera.maxHScroll();
    const qreal hPage = view.viewportWidth();
    const qreal vPage = view.rollViewportHeight();
    check(failures, hMinimum < 0.0, "fixture did not produce a negative horizontal pre-roll");
    const qreal hSpan = hMaximum - hMinimum;
    const qreal vSpan = camera.maxRollScroll();
    // The 80-DIP margin feeds the wheel and line-step sequences around the
    // anchored starts; the paged taps anchor at (span - page) / 2 so both
    // directions stay unclamped whenever the page fits the span at all.
    if (hSpan < hPage + 80.0 || vSpan < vPage + 80.0 || vSpan <= 0.0) {
        check(failures, false, "fixture lacks camera range for the paged scroll scenarios");
        restore();
        return;
    }
    const qreal hMid = hMinimum + (hSpan - hPage) / 2.0;
    const qreal hStart = hMinimum + std::max(0.0, (hSpan - hPage) / 2.0);

    // Horizontal track paging: a tap beyond the thumb pages one viewport.
    view.setHScroll(hStart);
    pump();
    {
        const QPointF afterThumb(
            horizontalThumb->x() + horizontalThumb->width() +
                (horizontalBar->width() - horizontalThumb->x() - horizontalThumb->width()) / 2.0,
            horizontalBar->height() / 2.0);
        sendItemMouse(*window, *horizontalBar, QEvent::MouseButtonPress, afterThumb,
                      Qt::LeftButton);
        sendItemMouse(*window, *horizontalBar, QEvent::MouseButtonRelease, afterThumb,
                      Qt::LeftButton);
        expectScroll(failures, view, Qt::Horizontal, hStart + hPage,
                     "tapping the horizontal track after the thumb did not page one viewport");
    }
    {
        const QPointF beforeThumb(horizontalThumb->x() / 2.0, horizontalBar->height() / 2.0);
        sendItemMouse(*window, *horizontalBar, QEvent::MouseButtonPress, beforeThumb,
                      Qt::LeftButton);
        sendItemMouse(*window, *horizontalBar, QEvent::MouseButtonRelease, beforeThumb,
                      Qt::LeftButton);
        expectScroll(
            failures, view, Qt::Horizontal, hStart,
            "tapping the horizontal track before the thumb did not page back one viewport");
    }

    // Explicit TouchPad wheel device: real trackpad wheels arrive
    // system-synthesized, which the control's default Mouse-only handler
    // rejects. Declared here so it outlives every gesture it delivers.
    const QPointingDevice touchpad(
        QStringLiteral("scrollbarquickcheck touchpad"), 0x2001, QInputDevice::DeviceType::TouchPad,
        QPointingDevice::PointerType::Finger,
        QInputDevice::Capability::Position | QInputDevice::Capability::Scroll, 5, 0);

    // Horizontal wheel: pixel deltas compose without truncation and never
    // move the roll camera; inverted deltas keep the delivered natural-scroll
    // sign (no double inversion); pixel wins over angle.
    const QPointF horizontalWheelPoint = horizontalBar->mapToScene(
        QPointF(horizontalBar->width() / 2.0, horizontalBar->height() / 2.0));
    view.setHScroll(hMid);
    pump();
    const qreal frozenScrollY = camera.scrollY();
    for (int i = 0; i < 3; ++i)
        sendWindowWheel(*window, horizontalWheelPoint, QPoint(0, -10), QPoint(), false);
    expectScroll(failures, view, Qt::Horizontal, hMid + 30.0,
                 "three -10px horizontal wheel events did not compose into 30 fractional DIPs");
    check(failures, near(camera.scrollY(), frozenScrollY),
          "wheeling the horizontal bar moved the roll camera (wrong axis)");
    const qreal invertedStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(0, -10), QPoint(), true);
    expectScroll(failures, view, Qt::Horizontal, invertedStart + 10.0,
                 "an inverted horizontal wheel flipped the natural-scroll sign (double inversion)");
    const qreal mixedStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(0, -10), QPoint(0, 120), false);
    expectScroll(failures, view, Qt::Horizontal, mixedStart + 10.0,
                 "a combined pixel and angle wheel consumed more than the pixel delta");
    endWindowWheelGesture(*window, horizontalWheelPoint);

    const qreal notch = QGuiApplication::styleHints()->wheelScrollLines();
    const qreal angleStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(), QPoint(0, 120), false);
    expectScroll(failures, view, Qt::Horizontal, angleStart - notch,
                 "a full wheel notch did not scroll one wheelScrollLines step toward the minimum");
    const qreal fractionalStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(), QPoint(0, 50), false);
    expectScroll(failures, view, Qt::Horizontal, fractionalStart - notch * 50.0 / 120.0,
                 "a fractional wheel notch did not compose fractionally onto the camera");
    endWindowWheelGesture(*window, horizontalWheelPoint);

    // Own-axis and device filtering: a horizontal-only pixel or angle wheel
    // scrolls the timeline while the roll camera freezes, a diagonal pixel
    // event applies its horizontal magnitude exactly once (two handlers must
    // not both relay the full delta), and a TouchPad gesture scrolls with
    // the delivered sign. Each case re-anchors so a failure cannot cascade.
    view.setHScroll(hMid);
    pump();
    const qreal horizontalOnlyPixelStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(10, 0), QPoint(), false);
    expectScroll(failures, view, Qt::Horizontal, horizontalOnlyPixelStart - 10.0,
                 "a horizontal-only pixel wheel did not scroll the timeline on its own axis");
    check(failures, near(camera.scrollY(), frozenScrollY),
          "a horizontal-only pixel wheel moved the roll camera (wrong axis)");
    endWindowWheelGesture(*window, horizontalWheelPoint);

    view.setHScroll(hMid);
    pump();
    const qreal horizontalOnlyAngleStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(), QPoint(120, 0), false);
    expectScroll(failures, view, Qt::Horizontal, horizontalOnlyAngleStart - notch,
                 "a horizontal-only wheel notch did not scroll the timeline one line step");
    check(failures, near(camera.scrollY(), frozenScrollY),
          "a horizontal-only wheel notch moved the roll camera (wrong axis)");
    endWindowWheelGesture(*window, horizontalWheelPoint);

    view.setHScroll(hMid);
    pump();
    const qreal diagonalStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(20, -10), QPoint(), false);
    expectScroll(failures, view, Qt::Horizontal, diagonalStart - 20.0,
                 "a diagonal pixel wheel did not apply its horizontal magnitude exactly once");
    check(failures, near(camera.scrollY(), frozenScrollY),
          "the diagonal wheel's vertical component moved the roll camera");
    endWindowWheelGesture(*window, horizontalWheelPoint);

    view.setHScroll(hMid);
    pump();
    const qreal touchpadHorizontalStart = camera.scrollX();
    sendWindowWheel(*window, horizontalWheelPoint, QPoint(8, 0), QPoint(), false, &touchpad);
    expectScroll(failures, view, Qt::Horizontal, touchpadHorizontalStart - 8.0,
                 "a TouchPad pixel wheel did not scroll the timeline");
    check(failures, near(camera.scrollY(), frozenScrollY),
          "a TouchPad timeline wheel moved the roll camera (wrong axis)");
    endWindowWheelGesture(*window, horizontalWheelPoint, &touchpad);

    // Horizontal keyboard: a one-DIP line step, End to the content maximum,
    // Home onto the negative pre-roll bound with the thumb docked left.
    QQuickItem *const priorFocus = window->activeFocusItem();
    view.activateWindow();
    quick->focusBand(songview::TimelineBand::Roll, Qt::OtherFocusReason);
    pump();
    horizontalBar->forceActiveFocus(Qt::TabFocusReason);
    pump();
    check(failures, horizontalBar->hasActiveFocus(),
          "horizontal scrollbar did not take active focus for key delivery");
    view.setHScroll(hMid);
    pump();
    sendWindowKey(*window, Qt::Key_Right);
    expectScroll(failures, view, Qt::Horizontal, hMid + 1.0,
                 "the right arrow did not step the camera one line");
    sendWindowKey(*window, Qt::Key_End);
    expectScroll(failures, view, Qt::Horizontal, hMaximum,
                 "End did not move the camera to the content maximum");
    check(failures, near(horizontalThumb->x() + horizontalThumb->width(), horizontalBar->width()),
          "End did not dock the horizontal thumb at the track end");
    sendWindowKey(*window, Qt::Key_Home);
    expectScroll(failures, view, Qt::Horizontal, hMinimum,
                 "Home did not move the camera onto the negative pre-roll bound");
    check(failures, near(horizontalThumb->x(), 0.0),
          "Home did not dock the horizontal thumb at the track start");
    if (priorFocus && priorFocus != horizontalBar)
        priorFocus->forceActiveFocus(Qt::OtherFocusReason);
    pump();

    // Horizontal drag: past the window to the positive maximum, held reverse
    // back into range, a mid-drag zoom rebasing onto the fresh scale, and an
    // external camera change repositioning the thumb after release.
    view.setHScroll(hMid);
    pump();
    const QPointF horizontalPress = beginThumbDrag(*window, *horizontalThumb, Qt::Horizontal);
    sendWindowMouse(*window, QEvent::MouseMove,
                    horizontalPress + QPointF(2.0 * horizontalBar->width(), 0.0), Qt::NoButton);
    expectScroll(failures, view, Qt::Horizontal, hMaximum,
                 "dragging the horizontal thumb past the window did not reach the content maximum");
    check(failures,
          near(horizontalThumb->x() + horizontalThumb->width(), horizontalBar->width()) &&
              thumbIsWithinTrack(*horizontalBar, *horizontalThumb, Qt::Horizontal),
          "the overdragged horizontal thumb left the track at the maximum");
    const QPointF horizontalReverse = horizontalBar->mapToScene(
        QPointF(horizontalBar->width() / 2.0, horizontalBar->height() / 2.0));
    sendWindowMouse(*window, QEvent::MouseMove, horizontalReverse, Qt::NoButton);
    const qreal reverseValue = camera.scrollX();
    check(failures, reverseValue > hMinimum + kTolerance && reverseValue < hMaximum - kTolerance,
          "reversing a held horizontal overdrag did not resume in-range travel");
    check(failures, thumbIsWithinTrack(*horizontalBar, *horizontalThumb, Qt::Horizontal),
          "the resumed horizontal thumb left the track");
    view.setEditorTimeZoom(initialPxPerBeat * 2.0);
    pump();
    check(failures, thumbIsWithinTrack(*horizontalBar, *horizontalThumb, Qt::Horizontal),
          "a mid-drag zoom pushed the held horizontal thumb out of the track");
    const qreal zoomedSpan = camera.maxHScroll() - camera.minHScroll();
    const qreal zoomedValue = camera.scrollX();
    const qreal zoomedTravel = horizontalBar->property("thumbTravel").toReal();
    sendWindowMouse(*window, QEvent::MouseMove, horizontalReverse + QPointF(1.0, 0.0),
                    Qt::NoButton);
    expectScroll(
        failures, view, Qt::Horizontal,
        zoomedValue + (zoomedTravel > 0.0 ? zoomedSpan / zoomedTravel : 0.0),
        "post-zoom horizontal drag replayed a stale gesture base instead of the fresh scale");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, horizontalReverse + QPointF(1.0, 0.0),
                    Qt::LeftButton);
    view.setHScroll(camera.minHScroll() + zoomedSpan / 4.0);
    pump();
    const qreal externalTravel = horizontalBar->property("thumbTravel").toReal();
    check(failures,
          near(horizontalThumb->x(),
               (camera.scrollX() - camera.minHScroll()) / zoomedSpan * externalTravel),
          "an external camera change did not reposition the released horizontal thumb");

    // Vertical track paging, mirroring the horizontal set; the frozen
    // horizontal camera proves the roll bar never drives the timeline.
    const qreal vMid = vSpan / 2.0;
    const qreal vStart = std::max(0.0, (vSpan - vPage) / 2.0);
    view.setVScroll(vStart);
    pump();
    {
        const QPointF afterThumb(
            verticalBar->width() / 2.0,
            verticalThumb->y() + verticalThumb->height() +
                (verticalBar->height() - verticalThumb->y() - verticalThumb->height()) / 2.0);
        sendItemMouse(*window, *verticalBar, QEvent::MouseButtonPress, afterThumb, Qt::LeftButton);
        sendItemMouse(*window, *verticalBar, QEvent::MouseButtonRelease, afterThumb,
                      Qt::LeftButton);
        expectScroll(failures, view, Qt::Vertical, vStart + vPage,
                     "tapping the roll track after the thumb did not page one viewport");
    }
    {
        const QPointF beforeThumb(verticalBar->width() / 2.0, verticalThumb->y() / 2.0);
        sendItemMouse(*window, *verticalBar, QEvent::MouseButtonPress, beforeThumb, Qt::LeftButton);
        sendItemMouse(*window, *verticalBar, QEvent::MouseButtonRelease, beforeThumb,
                      Qt::LeftButton);
        expectScroll(failures, view, Qt::Vertical, vStart,
                     "tapping the roll track before the thumb did not page back one viewport");
    }
    const QPointF verticalWheelPoint =
        verticalBar->mapToScene(QPointF(verticalBar->width() / 2.0, verticalBar->height() / 2.0));
    view.setVScroll(vMid);
    pump();
    const qreal frozenScrollX = camera.scrollX();
    for (int i = 0; i < 3; ++i)
        sendWindowWheel(*window, verticalWheelPoint, QPoint(0, -10), QPoint(), false);
    expectScroll(failures, view, Qt::Vertical, vMid + 30.0,
                 "three -10px roll wheel events did not compose into 30 fractional DIPs");
    check(failures, near(camera.scrollX(), frozenScrollX),
          "wheeling the roll bar moved the timeline camera (wrong axis)");
    const qreal invertedVerticalStart = camera.scrollY();
    sendWindowWheel(*window, verticalWheelPoint, QPoint(0, -10), QPoint(), true);
    expectScroll(failures, view, Qt::Vertical, invertedVerticalStart + 10.0,
                 "an inverted roll wheel flipped the natural-scroll sign (double inversion)");
    const qreal angleVerticalStart = camera.scrollY();
    sendWindowWheel(*window, verticalWheelPoint, QPoint(), QPoint(0, 120), false);
    expectScroll(
        failures, view, Qt::Vertical, angleVerticalStart - notch,
        "a full wheel notch did not scroll the roll one wheelScrollLines step toward zero");
    const qreal fractionalVerticalStart = camera.scrollY();
    sendWindowWheel(*window, verticalWheelPoint, QPoint(), QPoint(0, 50), false);
    expectScroll(failures, view, Qt::Vertical, fractionalVerticalStart - notch * 50.0 / 120.0,
                 "a fractional wheel notch did not compose fractionally onto the roll camera");
    endWindowWheelGesture(*window, verticalWheelPoint);

    // The roll bar accepts TouchPad gestures on its own axis too.
    view.setVScroll(vMid);
    pump();
    const qreal touchpadVerticalStart = camera.scrollY();
    sendWindowWheel(*window, verticalWheelPoint, QPoint(0, -6), QPoint(), false, &touchpad);
    expectScroll(failures, view, Qt::Vertical, touchpadVerticalStart + 6.0,
                 "a TouchPad pixel wheel did not scroll the roll");
    check(failures, near(camera.scrollX(), frozenScrollX),
          "a TouchPad roll wheel moved the timeline camera (wrong axis)");
    endWindowWheelGesture(*window, verticalWheelPoint, &touchpad);

    // Vertical keyboard: a one-DIP line step, End to the maximum, Home to the
    // zero minimum with the thumb docked at the track start.
    verticalBar->forceActiveFocus(Qt::TabFocusReason);
    pump();
    check(failures, verticalBar->hasActiveFocus(),
          "vertical scrollbar did not take active focus for key delivery");
    view.setVScroll(vMid);
    pump();
    sendWindowKey(*window, Qt::Key_Down);
    expectScroll(failures, view, Qt::Vertical, vMid + 1.0,
                 "the down arrow did not step the roll camera one line");
    sendWindowKey(*window, Qt::Key_End);
    expectScroll(failures, view, Qt::Vertical, vSpan,
                 "End did not move the roll camera to its maximum");
    check(failures, near(verticalThumb->y() + verticalThumb->height(), verticalBar->height()),
          "End did not dock the roll thumb at the track end");
    sendWindowKey(*window, Qt::Key_Home);
    expectScroll(failures, view, Qt::Vertical, 0.0,
                 "Home did not move the roll camera to its minimum");
    check(failures, near(verticalThumb->y(), 0.0),
          "Home did not dock the roll thumb at the track start");
    if (priorFocus && priorFocus != verticalBar)
        priorFocus->forceActiveFocus(Qt::OtherFocusReason);
    pump();

    // Vertical drag endpoints: past the window bottom to the maximum, held
    // reverse into range, then past the top to zero with a held clamp.
    view.setVScroll(vMid);
    pump();
    const QPointF verticalPress = beginThumbDrag(*window, *verticalThumb, Qt::Vertical);
    sendWindowMouse(*window, QEvent::MouseMove, QPointF(verticalPress.x(), window->height() - 1.0),
                    Qt::NoButton);
    expectScroll(failures, view, Qt::Vertical, vSpan,
                 "dragging the roll thumb past the window did not reach the vertical maximum");
    check(failures,
          near(verticalThumb->y() + verticalThumb->height(), verticalBar->height()) &&
              thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "the overdragged roll thumb left the track at the maximum");
    const QPointF verticalReverse =
        verticalBar->mapToScene(QPointF(verticalBar->width() / 2.0, verticalBar->height() / 2.0));
    sendWindowMouse(*window, QEvent::MouseMove, verticalReverse, Qt::NoButton);
    const qreal verticalReverseValue = camera.scrollY();
    check(failures, verticalReverseValue > kTolerance && verticalReverseValue < vSpan - kTolerance,
          "reversing a held roll overdrag did not resume in-range travel");
    check(failures, thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "the resumed roll thumb left the track");
    sendWindowMouse(*window, QEvent::MouseMove, QPointF(verticalReverse.x(), 1.0), Qt::NoButton);
    expectScroll(failures, view, Qt::Vertical, 0.0,
                 "dragging the roll thumb above its track did not reach the vertical minimum");
    sendWindowMouse(*window, QEvent::MouseMove, QPointF(verticalReverse.x(), 0.0), Qt::NoButton);
    expectScroll(failures, view, Qt::Vertical, 0.0,
                 "a continued held roll drag above the track did not stay clamped at zero");
    check(failures, thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "the clamped roll thumb left the track during the held overdrag");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, QPointF(verticalReverse.x(), 0.0),
                    Qt::LeftButton);

    // Folded pitch: collapsed content must collapse the vertical range to a
    // full, dead thumb — and re-expand into a working bar.
    view.setVScroll(vMid);
    pump();
    view.setScaleFold(true);
    pump();
    check(failures, camera.maxRollScroll() == 0.0,
          "folding the scale did not collapse the vertical camera range");
    expectScroll(failures, view, Qt::Vertical, 0.0,
                 "the roll camera did not follow the folded clamp to zero");
    check(failures,
          verticalBar->isVisible() && near(verticalThumb->height(), verticalBar->height()) &&
              thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "the folded zero-range vertical bar did not keep a full in-track thumb");
    const QPointF foldedPress = beginThumbDrag(*window, *verticalThumb, Qt::Vertical);
    sendWindowMouse(*window, QEvent::MouseMove,
                    QPointF(foldedPress.x(), foldedPress.y() - 2.0 * verticalBar->height()),
                    Qt::NoButton);
    check(failures,
          camera.scrollY() == 0.0 && near(verticalThumb->height(), verticalBar->height()) &&
              thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "a held drag moved the folded full vertical thumb or its content");
    sendWindowMouse(*window, QEvent::MouseButtonRelease,
                    QPointF(foldedPress.x(), foldedPress.y() - 2.0 * verticalBar->height()),
                    Qt::LeftButton);
    view.setScaleFold(false);
    pump();
    const qreal unfoldedSpan = camera.maxRollScroll();
    check(failures, unfoldedSpan > 0.0, "unfolding did not restore the vertical camera range");
    check(failures,
          verticalThumb->height() < verticalBar->height() &&
              thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "unfolding did not restore a partial in-track roll thumb");
    view.setVScroll(unfoldedSpan / 2.0);
    pump();
    const QPointF unfoldedPress = beginThumbDrag(*window, *verticalThumb, Qt::Vertical);
    const qreal unfoldedTravel = verticalBar->property("thumbTravel").toReal();
    const qreal unfoldedValue = camera.scrollY();
    sendWindowMouse(*window, QEvent::MouseMove, unfoldedPress + QPointF(0.0, 30.0), Qt::NoButton);
    expectScroll(failures, view, Qt::Vertical,
                 unfoldedValue +
                     (unfoldedTravel > 0.0 ? 30.0 * unfoldedSpan / unfoldedTravel : 0.0),
                 "a drag on the re-expanded roll bar did not scroll by the moved distance");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, unfoldedPress + QPointF(0.0, 30.0),
                    Qt::LeftButton);

    // Drawer height: the vertical bar follows the drawer-clipped roll band.
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, initialDrawerHeight + 80);
    pump();
    const std::optional<songview::TimelineBandGeometry> grownRoll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    const QRectF grownRect = songViewRect(view, quick->verticalScrollbarRect());
    check(failures,
          grownRoll && near(grownRect.height(), grownRoll->rect.height()) &&
              near(grownRect.top(), grownRoll->rect.top()),
          "a drawer height change did not resize the vertical bar with the clipped roll band");
    check(failures, view.rollViewportHeight() != vPage,
          "a drawer height change did not move the roll viewport (fixture guard)");
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, initialDrawerHeight);
    pump();

    // Resizing mid-drag rebases like zooming: the held gesture continues on
    // the fresh geometry instead of replaying a stale base.
    view.setVScroll(camera.maxRollScroll() / 2.0);
    pump();
    const QSize beforeResize = view.size();
    const qreal spanBeforeResize = camera.maxRollScroll();
    const QPointF resizePress = beginThumbDrag(*window, *verticalThumb, Qt::Vertical);
    view.resize(beforeResize.width(), beforeResize.height() - 160);
    pump();
    check(failures, thumbIsWithinTrack(*verticalBar, *verticalThumb, Qt::Vertical),
          "a mid-drag resize pushed the held vertical thumb out of the track");
    const qreal resizedSpan = camera.maxRollScroll();
    check(failures, resizedSpan != spanBeforeResize,
          "the held-drag resize did not change the vertical camera range");
    const qreal resizedValue = camera.scrollY();
    const qreal resizedTravel = verticalBar->property("thumbTravel").toReal();
    sendWindowMouse(*window, QEvent::MouseMove, resizePress + QPointF(0.0, 30.0), Qt::NoButton);
    expectScroll(failures, view, Qt::Vertical,
                 resizedValue + (resizedTravel > 0.0 ? 30.0 * resizedSpan / resizedTravel : 0.0),
                 "post-resize vertical drag replayed a stale gesture base");
    sendWindowMouse(*window, QEvent::MouseButtonRelease, resizePress + QPointF(0.0, 30.0),
                    Qt::LeftButton);
    view.resize(beforeResize);
    pump();

    // Event-list mode: the roll lane disappears with its vertical bar while
    // the horizontal row persists and keeps tracking the camera.
    view.setEventListVisible(true);
    pump();
    check(failures, quick->verticalScrollbarRect().isEmpty(),
          "vertical scrollbar geometry persisted into event list mode");
    check(failures, !verticalBar->isVisible(),
          "the vertical roll scrollbar stayed visible in event list mode");
    check(failures, !quick->horizontalScrollbarRect().isEmpty() && horizontalBar->isVisible(),
          "the horizontal row did not persist into event list mode");
    const qreal eventListTarget =
        camera.minHScroll() + (camera.maxHScroll() - camera.minHScroll()) / 3.0;
    view.setHScroll(eventListTarget);
    pump();
    expectScroll(failures, view, Qt::Horizontal, eventListTarget,
                 "the horizontal bar stopped tracking the camera in event list mode");
    view.setEventListVisible(initialEventList);
    pump();
    check(failures, !quick->verticalScrollbarRect().isEmpty() && verticalBar->isVisible(),
          "returning from event list mode did not restore the vertical bar");

    restore();
}
