#include "checks/scrollbar/tst_scrollbar.h"

#include <cmath>

#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStyleHints>
#include <QtTest>

#include "ui/songview.h"
#include "ui/songview/timecamera.h"

namespace {

constexpr double kTolerance = 0.01;
constexpr double kWheelMargin = 80.0;

enum class WheelBehavior : int {
    PixelAccumulation,
    InvertedPixel,
    PixelPrecedesAngle,
    FullAngleNotch,
    FractionalAngleNotch,
    HorizontalPixel,
    HorizontalAngle,
    HorizontalDiagonal,
    Touchpad,
};

enum class KeyBehavior : int {
    SingleStep,
    Home,
    End,
};

} // namespace

void ScrollbarTest::trackPaging_data()
{
    QTest::addColumn<int>("orientationValue");
    QTest::addColumn<bool>("forward");

    QTest::newRow("horizontal-forward") << int(Qt::Horizontal) << true;
    QTest::newRow("horizontal-backward") << int(Qt::Horizontal) << false;
    QTest::newRow("vertical-forward") << int(Qt::Vertical) << true;
    QTest::newRow("vertical-backward") << int(Qt::Vertical) << false;
}

void ScrollbarTest::trackPaging()
{
    QFETCH(int, orientationValue);
    QFETCH(bool, forward);
    const Qt::Orientation orientation =
        orientationValue == int(Qt::Horizontal) ? Qt::Horizontal : Qt::Vertical;
    SongView &songView = view();
    QQuickItem &scrollbar = bar(orientation);
    if (orientation == Qt::Horizontal)
        songView.setEditorTimeZoom(songView.pxPerBeat() * 2.0);

    const songview::TimeCamera &camera = songView.camera();
    const double page =
        orientation == Qt::Horizontal ? songView.viewportWidth() : songView.rollViewportHeight();
    const double minimum = orientation == Qt::Horizontal ? camera.minHScroll() : 0.0;
    const double maximum =
        orientation == Qt::Horizontal ? camera.maxHScroll() : camera.maxRollScroll();
    const double span = maximum - minimum;

    QTRY_VERIFY(std::abs(scrollbar.property("minimum").toReal() - minimum) < kTolerance);
    QTRY_VERIFY(std::abs(scrollbar.property("maximum").toReal() - maximum) < kTolerance);
    QTRY_VERIFY(std::abs(scrollbar.property("pageStep").toReal() - page) < kTolerance);

    QVERIFY(span > page + kWheelMargin);
    const double pageStart = minimum + (span - page) / 2.0;
    const double initial = forward ? pageStart : pageStart + page;
    const double otherBefore = orientation == Qt::Horizontal ? camera.scrollY() : camera.scrollX();
    if (orientation == Qt::Horizontal)
        songView.setHScroll(initial);
    else
        songView.setVScroll(initial);

    if (orientation == Qt::Horizontal)
        QTRY_VERIFY(std::abs(camera.scrollX() - initial) < kTolerance);
    else
        QTRY_VERIFY(std::abs(camera.scrollY() - initial) < kTolerance);
    QTRY_VERIFY(std::abs(scrollbar.property("value").toReal() - initial) < kTolerance);

    QQuickItem &scrollThumb = thumb(orientation);
    const QPointF target =
        orientation == Qt::Horizontal
            ? QPointF(forward
                          ? scrollThumb.x() + scrollThumb.width() +
                                (scrollbar.width() - scrollThumb.x() - scrollThumb.width()) / 2.0
                          : scrollThumb.x() / 2.0,
                      scrollbar.height() / 2.0)
            : QPointF(scrollbar.width() / 2.0,
                      forward
                          ? scrollThumb.y() + scrollThumb.height() +
                                (scrollbar.height() - scrollThumb.y() - scrollThumb.height()) / 2.0
                          : scrollThumb.y() / 2.0);
    QVERIFY(scrollbar.boundingRect().contains(target));

    press(scrollbar.mapToScene(target));
    release();

    const double expected = forward ? pageStart + page : pageStart;
    if (orientation == Qt::Horizontal) {
        QTRY_VERIFY(std::abs(camera.scrollX() - expected) < kTolerance);
        QTRY_VERIFY(std::abs(camera.scrollY() - otherBefore) < kTolerance);
    } else {
        QTRY_VERIFY(std::abs(camera.scrollY() - expected) < kTolerance);
        QTRY_VERIFY(std::abs(camera.scrollX() - otherBefore) < kTolerance);
    }
}

void ScrollbarTest::wheelScrolling_data()
{
    QTest::addColumn<int>("orientationValue");
    QTest::addColumn<int>("behaviorValue");

    QTest::newRow("horizontal-pixel-accumulation")
        << int(Qt::Horizontal) << int(WheelBehavior::PixelAccumulation);
    QTest::newRow("vertical-pixel-accumulation")
        << int(Qt::Vertical) << int(WheelBehavior::PixelAccumulation);
    QTest::newRow("horizontal-inverted-natural-sign")
        << int(Qt::Horizontal) << int(WheelBehavior::InvertedPixel);
    QTest::newRow("vertical-inverted-natural-sign")
        << int(Qt::Vertical) << int(WheelBehavior::InvertedPixel);
    QTest::newRow("horizontal-pixel-precedes-angle")
        << int(Qt::Horizontal) << int(WheelBehavior::PixelPrecedesAngle);
    QTest::newRow("vertical-pixel-precedes-angle")
        << int(Qt::Vertical) << int(WheelBehavior::PixelPrecedesAngle);
    QTest::newRow("horizontal-full-angle-notch")
        << int(Qt::Horizontal) << int(WheelBehavior::FullAngleNotch);
    QTest::newRow("vertical-full-angle-notch")
        << int(Qt::Vertical) << int(WheelBehavior::FullAngleNotch);
    QTest::newRow("horizontal-fractional-angle-notch")
        << int(Qt::Horizontal) << int(WheelBehavior::FractionalAngleNotch);
    QTest::newRow("vertical-fractional-angle-notch")
        << int(Qt::Vertical) << int(WheelBehavior::FractionalAngleNotch);
    QTest::newRow("horizontal-only-pixel")
        << int(Qt::Horizontal) << int(WheelBehavior::HorizontalPixel);
    QTest::newRow("horizontal-only-angle")
        << int(Qt::Horizontal) << int(WheelBehavior::HorizontalAngle);
    QTest::newRow("horizontal-diagonal-precedence")
        << int(Qt::Horizontal) << int(WheelBehavior::HorizontalDiagonal);
    QTest::newRow("horizontal-touchpad") << int(Qt::Horizontal) << int(WheelBehavior::Touchpad);
    QTest::newRow("vertical-touchpad") << int(Qt::Vertical) << int(WheelBehavior::Touchpad);
}

void ScrollbarTest::wheelScrolling()
{
    QFETCH(int, orientationValue);
    QFETCH(int, behaviorValue);
    const Qt::Orientation orientation =
        orientationValue == int(Qt::Horizontal) ? Qt::Horizontal : Qt::Vertical;
    const WheelBehavior behavior = WheelBehavior(behaviorValue);
    const songview::TimeCamera &camera = view().camera();
    const double minimum = orientation == Qt::Horizontal ? camera.minHScroll() : 0.0;
    const double maximum =
        orientation == Qt::Horizontal ? camera.maxHScroll() : camera.maxRollScroll();
    const double midpoint = minimum + (maximum - minimum) / 2.0;
    const double otherBefore = orientation == Qt::Horizontal ? camera.scrollY() : camera.scrollX();
    const double notch = QGuiApplication::styleHints()->wheelScrollLines();

    QVERIFY(maximum - minimum > 2.0 * kWheelMargin);
    QVERIFY(notch > 0.0);
    if (orientation == Qt::Horizontal)
        view().setHScroll(midpoint);
    else
        view().setVScroll(midpoint);

    if (orientation == Qt::Horizontal)
        QTRY_VERIFY(std::abs(camera.scrollX() - midpoint) < kTolerance);
    else
        QTRY_VERIFY(std::abs(camera.scrollY() - midpoint) < kTolerance);

    double expected = midpoint;
    switch (behavior) {
    case WheelBehavior::PixelAccumulation:
        wheel(orientation, QPoint(0, -10), {});
        wheel(orientation, QPoint(0, -10), {});
        wheel(orientation, QPoint(0, -10), {});
        expected += 30.0;
        break;
    case WheelBehavior::InvertedPixel:
        wheel(orientation, QPoint(0, -10), {}, true);
        expected += 10.0;
        break;
    case WheelBehavior::PixelPrecedesAngle:
        wheel(orientation, QPoint(0, -10), QPoint(0, 120));
        expected += 10.0;
        break;
    case WheelBehavior::FullAngleNotch:
        wheel(orientation, {}, QPoint(0, 120));
        expected -= notch;
        break;
    case WheelBehavior::FractionalAngleNotch:
        wheel(orientation, {}, QPoint(0, 50));
        expected -= notch * 50.0 / 120.0;
        break;
    case WheelBehavior::HorizontalPixel:
        wheel(orientation, QPoint(10, 0), {});
        expected -= 10.0;
        break;
    case WheelBehavior::HorizontalAngle:
        wheel(orientation, {}, QPoint(120, 0));
        expected -= notch;
        break;
    case WheelBehavior::HorizontalDiagonal:
        wheel(orientation, QPoint(20, -10), {});
        expected -= 20.0;
        break;
    case WheelBehavior::Touchpad:
        if (orientation == Qt::Horizontal) {
            wheel(orientation, QPoint(8, 0), {}, false, true);
            expected -= 8.0;
        } else {
            wheel(orientation, QPoint(0, -6), {}, false, true);
            expected += 6.0;
        }
        break;
    }

    if (orientation == Qt::Horizontal) {
        QTRY_VERIFY(std::abs(camera.scrollX() - expected) < kTolerance);
        QTRY_VERIFY(std::abs(camera.scrollY() - otherBefore) < kTolerance);
    } else {
        QTRY_VERIFY(std::abs(camera.scrollY() - expected) < kTolerance);
        QTRY_VERIFY(std::abs(camera.scrollX() - otherBefore) < kTolerance);
    }
    endWheel(orientation, behavior == WheelBehavior::Touchpad);
}

void ScrollbarTest::keyboardNavigation_data()
{
    QTest::addColumn<int>("orientationValue");
    QTest::addColumn<int>("behaviorValue");

    QTest::newRow("horizontal-right-single-dip")
        << int(Qt::Horizontal) << int(KeyBehavior::SingleStep);
    QTest::newRow("vertical-down-single-dip") << int(Qt::Vertical) << int(KeyBehavior::SingleStep);
    QTest::newRow("horizontal-home-negative-preroll")
        << int(Qt::Horizontal) << int(KeyBehavior::Home);
    QTest::newRow("vertical-home-minimum") << int(Qt::Vertical) << int(KeyBehavior::Home);
    QTest::newRow("horizontal-end-maximum") << int(Qt::Horizontal) << int(KeyBehavior::End);
    QTest::newRow("vertical-end-maximum") << int(Qt::Vertical) << int(KeyBehavior::End);
}

void ScrollbarTest::keyboardNavigation()
{
    QFETCH(int, orientationValue);
    QFETCH(int, behaviorValue);
    const Qt::Orientation orientation =
        orientationValue == int(Qt::Horizontal) ? Qt::Horizontal : Qt::Vertical;
    const KeyBehavior behavior = KeyBehavior(behaviorValue);
    const songview::TimeCamera &camera = view().camera();
    const double minimum = orientation == Qt::Horizontal ? camera.minHScroll() : 0.0;
    const double maximum =
        orientation == Qt::Horizontal ? camera.maxHScroll() : camera.maxRollScroll();
    const double midpoint = minimum + (maximum - minimum) / 2.0;
    const double otherBefore = orientation == Qt::Horizontal ? camera.scrollY() : camera.scrollX();

    if (orientation == Qt::Horizontal)
        QVERIFY(minimum < 0.0);
    QVERIFY(maximum - minimum > 2.0);
    if (orientation == Qt::Horizontal)
        view().setHScroll(midpoint);
    else
        view().setVScroll(midpoint);

    if (orientation == Qt::Horizontal)
        QTRY_VERIFY(std::abs(camera.scrollX() - midpoint) < kTolerance);
    else
        QTRY_VERIFY(std::abs(camera.scrollY() - midpoint) < kTolerance);

    QQuickItem &scrollbar = bar(orientation);
    scrollbar.forceActiveFocus(Qt::TabFocusReason);
    QTRY_VERIFY(window().activeFocusItem() == &scrollbar && scrollbar.hasActiveFocus());

    Qt::Key key = Qt::Key_Right;
    double expected = midpoint;
    switch (behavior) {
    case KeyBehavior::SingleStep:
        key = orientation == Qt::Horizontal ? Qt::Key_Right : Qt::Key_Down;
        expected += 1.0;
        break;
    case KeyBehavior::Home:
        key = Qt::Key_Home;
        expected = minimum;
        break;
    case KeyBehavior::End:
        key = Qt::Key_End;
        expected = maximum;
        break;
    }

    QTest::keyClick(&window(), key);
    if (orientation == Qt::Horizontal) {
        QTRY_VERIFY(std::abs(camera.scrollX() - expected) < kTolerance);
        QTRY_VERIFY(std::abs(camera.scrollY() - otherBefore) < kTolerance);
    } else {
        QTRY_VERIFY(std::abs(camera.scrollY() - expected) < kTolerance);
        QTRY_VERIFY(std::abs(camera.scrollX() - otherBefore) < kTolerance);
    }

    if (behavior == KeyBehavior::Home) {
        if (orientation == Qt::Horizontal)
            QTRY_VERIFY(std::abs(thumb(orientation).x()) < kTolerance);
        else
            QTRY_VERIFY(std::abs(thumb(orientation).y()) < kTolerance);
        QVERIFY(withinTrack(orientation));
    }
    if (behavior == KeyBehavior::End) {
        if (orientation == Qt::Horizontal) {
            QTRY_VERIFY(std::abs(thumb(orientation).x() + thumb(orientation).width() -
                                 scrollbar.width()) < kTolerance);
        } else {
            QTRY_VERIFY(std::abs(thumb(orientation).y() + thumb(orientation).height() -
                                 scrollbar.height()) < kTolerance);
        }
        QVERIFY(withinTrack(orientation));
    }
}
