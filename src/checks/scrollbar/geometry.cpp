#include "checks/scrollbar/tst_scrollbar.h"

#include <cmath>
#include <optional>

#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QSizeF>
#include <QtTest>

#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timecamera.h"
#include "ui/songview/timelinebandlayout.h"

namespace {

constexpr qreal kTolerance = 0.01;

bool near(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kTolerance;
}

QRectF windowRect(const QQuickWindow &window)
{
    return {QPointF{}, QSizeF(window.size())};
}

QRectF sceneRect(const QQuickItem &item)
{
    return item.mapRectToScene(item.boundingRect());
}

} // namespace

void ScrollbarTest::layoutFollowsCanonicalBands()
{
    SongView &songView = view();
    const songview::TimelineBandLayout &bands = songView.timelineBandLayout();
    const std::optional<songview::TimelineBandGeometry> &roll =
        bands.geometry(songview::TimelineBand::Roll);
    const std::optional<songview::TimelineBandGeometry> &otherEvents =
        bands.geometry(songview::TimelineBand::OtherEvents);
    QVERIFY(roll.has_value());
    QVERIFY(otherEvents.has_value());

    const QRectF horizontalRect(songView.horizontalScrollbarRect());
    const QRectF verticalRect(songView.verticalScrollbarRect());
    QVERIFY(!horizontalRect.isEmpty());
    QVERIFY(!verticalRect.isEmpty());
    QVERIFY(near(horizontalRect.left(), songView.timelineSplitX()));
    QVERIFY(near(horizontalRect.right(), window().width()));
    QVERIFY(near(horizontalRect.height(), layout::space(layout::Space::Two)));
    QVERIFY(near(horizontalRect.top(), otherEvents->rect.top() + otherEvents->rect.height()));

    QVERIFY(near(verticalRect.left(), roll->rect.left() + roll->rect.width()));
    QVERIFY(near(verticalRect.width(), layout::space(layout::Space::Two)));
    QVERIFY(near(verticalRect.top(), roll->rect.top()));
    QVERIFY(near(verticalRect.height(), roll->rect.height()));
    QVERIFY(roll->plotRect.right() < verticalRect.left() + kTolerance);

    QTRY_VERIFY(bar(Qt::Horizontal).isVisible() && thumb(Qt::Horizontal).isVisible());
    QTRY_VERIFY(bar(Qt::Vertical).isVisible() && thumb(Qt::Vertical).isVisible());
    const auto actualVerticalRect = [&] { return sceneRect(bar(Qt::Vertical)).toAlignedRect(); };
    QTRY_VERIFY(!actualVerticalRect().isEmpty());
    QTRY_COMPARE(actualVerticalRect().left(), roll->rect.right() + 1);
    QTRY_COMPARE(actualVerticalRect().right(), window().width() - 1);
    QVERIFY(actualVerticalRect().left() > roll->plotRect.right());
    QVERIFY(withinTrack(Qt::Horizontal));
    QVERIFY(withinTrack(Qt::Vertical));
}

void ScrollbarTest::scrollbarHostContainsBothTracks()
{
    QQuickWindow &quickWindow = window();
    QQuickItem &horizontalBar = bar(Qt::Horizontal);
    QQuickItem &verticalBar = bar(Qt::Vertical);

    QTRY_VERIFY(!horizontalBar.boundingRect().isEmpty());
    QTRY_VERIFY(!verticalBar.boundingRect().isEmpty());
    const QRectF host = windowRect(quickWindow);
    QTRY_VERIFY(host.contains(sceneRect(horizontalBar)));
    QTRY_VERIFY(host.contains(sceneRect(verticalBar)));
}

void ScrollbarTest::drawerResizeFollowsRollBand()
{
    SongView &songView = view();
    const int initialHeight = songView.drawerSectionHeight(EditorDrawerPage::Automations);
    const int initialViewportHeight = songView.rollViewportHeight();

    songView.setDrawerSectionHeight(EditorDrawerPage::Automations, initialHeight + 80);

    QTRY_VERIFY(songView.rollViewportHeight() != initialViewportHeight);
    const std::optional<songview::TimelineBandGeometry> &roll =
        songView.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(roll.has_value());
    const QRectF verticalRect(songView.verticalScrollbarRect());
    QVERIFY(!verticalRect.isEmpty());
    QVERIFY(near(verticalRect.top(), roll->rect.top()));
    QVERIFY(near(verticalRect.height(), roll->rect.height()));
    QVERIFY(near(verticalRect.left(), roll->rect.left() + roll->rect.width()));
    QTRY_VERIFY(withinTrack(Qt::Vertical));
}

void ScrollbarTest::eventListHidesOnlyRollScrollbar()
{
    SongView &songView = view();
    songView.setEventListVisible(true);

    QTRY_VERIFY(songView.verticalScrollbarRect().isEmpty());
    QTRY_VERIFY(!bar(Qt::Vertical).isVisible());
    QTRY_VERIFY(!songView.horizontalScrollbarRect().isEmpty());
    QTRY_VERIFY(bar(Qt::Horizontal).isVisible() && thumb(Qt::Horizontal).isVisible());

    const songview::TimeCamera &camera = songView.camera();
    const qreal horizontalTarget =
        camera.minHScroll() + (camera.maxHScroll() - camera.minHScroll()) / 3.0;
    songView.setHScroll(horizontalTarget);
    QTRY_VERIFY(near(songView.camera().scrollX(), horizontalTarget));
    QVERIFY(withinTrack(Qt::Horizontal));

    songView.setEventListVisible(false);
    QTRY_VERIFY(!songView.verticalScrollbarRect().isEmpty());
    QTRY_VERIFY(bar(Qt::Vertical).isVisible() && thumb(Qt::Vertical).isVisible());
    QVERIFY(withinTrack(Qt::Vertical));
}
