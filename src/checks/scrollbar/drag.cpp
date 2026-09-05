#include "checks/scrollbar/tst_scrollbar.h"

#include <cmath>

#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>
#include <QVariant>
#include <QtTest>

#include "ui/songview.h"
#include "ui/songview/timecamera.h"

namespace {

constexpr qreal kTolerance = 0.01;

bool near(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kTolerance;
}

qreal minimum(const SongView &songView, Qt::Orientation orientation)
{
    return orientation == Qt::Horizontal ? songView.camera().minHScroll() : 0.0;
}

qreal maximum(const SongView &songView, Qt::Orientation orientation)
{
    return orientation == Qt::Horizontal ? songView.camera().maxHScroll()
                                         : songView.camera().maxRollScroll();
}

qreal value(const SongView &songView, Qt::Orientation orientation)
{
    return orientation == Qt::Horizontal ? songView.camera().scrollX()
                                         : songView.camera().scrollY();
}

void setValue(SongView &songView, Qt::Orientation orientation, qreal scrollValue)
{
    if (orientation == Qt::Horizontal)
        songView.setHScroll(scrollValue);
    else
        songView.setVScroll(scrollValue);
}

qreal travel(const QQuickItem &bar)
{
    return bar.property("thumbTravel").toReal();
}

qreal thumbPosition(const QQuickItem &thumb, Qt::Orientation orientation)
{
    return orientation == Qt::Horizontal ? thumb.x() : thumb.y();
}

QPointF offset(Qt::Orientation orientation, qreal distance)
{
    return orientation == Qt::Horizontal ? QPointF(distance, 0.0) : QPointF(0.0, distance);
}

qreal trackLength(const QQuickItem &bar, Qt::Orientation orientation)
{
    return orientation == Qt::Horizontal ? bar.width() : bar.height();
}

} // namespace

void ScrollbarTest::dragClampsAndReverses_data()
{
    QTest::addColumn<int>("orientation");
    QTest::newRow("horizontal") << int(Qt::Horizontal);
    QTest::newRow("vertical") << int(Qt::Vertical);
}

void ScrollbarTest::dragClampsAndReverses()
{
    QFETCH(int, orientation);
    const Qt::Orientation axis = static_cast<Qt::Orientation>(orientation);
    SongView &songView = view();
    QQuickItem &track = bar(axis);

    const qreal minimumValue = minimum(songView, axis);
    const qreal maximumValue = maximum(songView, axis);
    const qreal span = maximumValue - minimumValue;
    QVERIFY(span > 0.0);
    setValue(songView, axis, minimumValue + span / 2.0);
    QTRY_VERIFY(near(value(songView, axis), minimumValue + span / 2.0));

    const QPointF dragPosition = beginDrag(axis);
    const QPointF pastMaximum = dragPosition + offset(axis, 2.0 * trackLength(track, axis));
    move(pastMaximum);
    QTRY_VERIFY(near(value(songView, axis), maximumValue));
    QTRY_VERIFY(withinTrack(axis));

    const QPointF reverse = track.mapToScene(track.boundingRect().center());
    move(reverse);
    QTRY_VERIFY(value(songView, axis) > minimumValue + kTolerance &&
                value(songView, axis) < maximumValue - kTolerance);
    QTRY_VERIFY(withinTrack(axis));

    const QPointF pastMinimum = reverse - offset(axis, 2.0 * trackLength(track, axis));
    move(pastMinimum);
    QTRY_VERIFY(near(value(songView, axis), minimumValue));
    QTRY_VERIFY(withinTrack(axis));

    move(pastMinimum - offset(axis, 1.0));
    QTRY_VERIFY(near(value(songView, axis), minimumValue));
    QTRY_VERIFY(withinTrack(axis));
    release();
}

void ScrollbarTest::dragRebasesAfterZoom()
{
    constexpr qreal kOnePixel = 1.0;
    SongView &songView = view();
    QQuickItem &track = bar(Qt::Horizontal);
    const qreal initialMinimum = songView.camera().minHScroll();
    const qreal initialMaximum = songView.camera().maxHScroll();
    const qreal initialSpan = initialMaximum - initialMinimum;
    QVERIFY(initialSpan > 0.0);
    songView.setHScroll(initialMinimum + initialSpan / 2.0);
    QTRY_VERIFY(near(songView.camera().scrollX(), initialMinimum + initialSpan / 2.0));

    const QPointF dragPosition = beginDrag(Qt::Horizontal);
    songView.setEditorTimeZoom(songView.pxPerBeat() * 2.0);
    QTRY_VERIFY(
        !near(songView.camera().maxHScroll() - songView.camera().minHScroll(), initialSpan));
    QTRY_VERIFY(withinTrack(Qt::Horizontal));

    const qreal freshSpan = songView.camera().maxHScroll() - songView.camera().minHScroll();
    const qreal freshValue = songView.camera().scrollX();
    const qreal freshTravel = travel(track);
    QVERIFY(freshTravel > 0.0);
    const qreal expected = freshValue + kOnePixel * freshSpan / freshTravel;
    QVERIFY(expected < songView.camera().maxHScroll());

    move(dragPosition + offset(Qt::Horizontal, kOnePixel));
    QTRY_VERIFY(near(songView.camera().scrollX(), expected));
    release();
}

void ScrollbarTest::dragRebasesAfterResize()
{
    constexpr qreal kDragDistance = 30.0;
    SongView &songView = view();
    QQuickItem &track = bar(Qt::Vertical);
    const qreal initialSpan = songView.camera().maxRollScroll();
    QVERIFY(initialSpan > 0.0);
    songView.setVScroll(initialSpan / 2.0);
    QTRY_VERIFY(near(songView.camera().scrollY(), initialSpan / 2.0));

    const QPointF dragPosition = beginDrag(Qt::Vertical);
    const QSize beforeResize = songView.size();
    songView.resize(beforeResize.width(), beforeResize.height() - 160);
    QTRY_VERIFY(!near(songView.camera().maxRollScroll(), initialSpan));
    QTRY_VERIFY(withinTrack(Qt::Vertical));

    const qreal freshSpan = songView.camera().maxRollScroll();
    const qreal freshValue = songView.camera().scrollY();
    const qreal freshTravel = travel(track);
    QVERIFY(freshTravel > 0.0);
    const qreal expected = freshValue + kDragDistance * freshSpan / freshTravel;
    QVERIFY(expected < freshSpan);

    move(dragPosition + offset(Qt::Vertical, kDragDistance));
    QTRY_VERIFY(near(songView.camera().scrollY(), expected));
    release();
}

void ScrollbarTest::foldingDisablesAndRestoresRollDrag()
{
    constexpr qreal kDragDistance = 30.0;
    SongView &songView = view();
    QQuickItem &track = bar(Qt::Vertical);
    QQuickItem &rollThumb = thumb(Qt::Vertical);
    const qreal initialSpan = songView.camera().maxRollScroll();
    QVERIFY(initialSpan > 0.0);
    songView.setVScroll(initialSpan / 2.0);
    QTRY_VERIFY(near(songView.camera().scrollY(), initialSpan / 2.0));

    songView.setScaleFold(true);
    QTRY_COMPARE(songView.camera().maxRollScroll(), 0.0);
    QTRY_COMPARE(songView.camera().scrollY(), 0.0);
    QTRY_VERIFY(near(rollThumb.height(), track.height()));
    QTRY_VERIFY(withinTrack(Qt::Vertical));

    const QPointF foldedDrag = beginDrag(Qt::Vertical);
    move(foldedDrag - offset(Qt::Vertical, 2.0 * track.height()));
    QTRY_COMPARE(songView.camera().scrollY(), 0.0);
    QTRY_VERIFY(near(rollThumb.height(), track.height()));
    QTRY_VERIFY(withinTrack(Qt::Vertical));
    release();

    songView.setScaleFold(false);
    QTRY_VERIFY(songView.camera().maxRollScroll() > 0.0);
    QTRY_VERIFY(rollThumb.height() < track.height());
    QTRY_VERIFY(withinTrack(Qt::Vertical));

    const qreal restoredSpan = songView.camera().maxRollScroll();
    songView.setVScroll(restoredSpan / 2.0);
    QTRY_VERIFY(near(songView.camera().scrollY(), restoredSpan / 2.0));
    const QPointF restoredDrag = beginDrag(Qt::Vertical);
    const qreal restoredValue = songView.camera().scrollY();
    const qreal restoredTravel = travel(track);
    QVERIFY(restoredTravel > 0.0);
    const qreal expected = restoredValue + kDragDistance * restoredSpan / restoredTravel;
    QVERIFY(expected < restoredSpan);

    move(restoredDrag + offset(Qt::Vertical, kDragDistance));
    QTRY_VERIFY(near(songView.camera().scrollY(), expected));
    release();
}

void ScrollbarTest::externalCameraMovesReleasedThumb_data()
{
    QTest::addColumn<int>("orientation");
    QTest::newRow("horizontal") << int(Qt::Horizontal);
    QTest::newRow("vertical") << int(Qt::Vertical);
}

void ScrollbarTest::externalCameraMovesReleasedThumb()
{
    QFETCH(int, orientation);
    const Qt::Orientation axis = static_cast<Qt::Orientation>(orientation);
    SongView &songView = view();
    QQuickItem &track = bar(axis);
    QQuickItem &handle = thumb(axis);

    const qreal minimumValue = minimum(songView, axis);
    const qreal maximumValue = maximum(songView, axis);
    const qreal span = maximumValue - minimumValue;
    QVERIFY(span > 0.0);
    setValue(songView, axis, minimumValue + span / 2.0);
    QTRY_VERIFY(near(value(songView, axis), minimumValue + span / 2.0));

    beginDrag(axis);
    release();
    QTRY_VERIFY(!window().mouseGrabberItem());

    const qreal externalValue = minimumValue + span / 4.0;
    setValue(songView, axis, externalValue);
    QTRY_VERIFY(near(value(songView, axis), externalValue));
    const qreal freshTravel = travel(track);
    QVERIFY(freshTravel > 0.0);
    const qreal expectedPosition = (externalValue - minimumValue) / span * freshTravel;
    QTRY_VERIFY(near(thumbPosition(handle, axis), expectedPosition));
    QVERIFY(withinTrack(axis));
}
