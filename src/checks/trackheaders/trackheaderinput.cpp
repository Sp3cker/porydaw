#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <QAbstractItemModel>
#include <QQuickItem>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <optional>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "ui/activity/trackactivity.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

namespace {

constexpr qreal kGeometryTolerance = 0.01;
constexpr int kWheelNotch = 120;

QVariant rowData(const songview::TrackHeaderModel &model, int row, int role)
{
    return model.data(model.index(row, 0), role);
}

songview::TimelinePointerInput pointerInput(const songview::TimelineInputItem &input,
                                            QPointF position, Qt::MouseButton button,
                                            Qt::MouseButtons buttons)
{
    return {position, input.mapToGlobal(position), button, buttons, Qt::NoModifier};
}

songview::TimelineWheelInput wheelInput(const songview::TimelineInputItem &input, QPointF position,
                                        QPoint pixelDelta, QPoint angleDelta)
{
    return {position,       input.mapToGlobal(position), pixelDelta, angleDelta,
            Qt::NoModifier, Qt::NoScrollPhase,           false};
}

bool near(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kGeometryTolerance;
}

bool sameRect(const QRectF &actual, const QRectF &expected)
{
    return near(actual.x(), expected.x()) && near(actual.y(), expected.y()) &&
           near(actual.width(), expected.width()) && near(actual.height(), expected.height());
}

bool hasDistinctPixels(const QImage &image)
{
    if (image.isNull() || image.size().isEmpty() || image.depth() <= 0 || image.depth() % 8 != 0)
        return false;
    const int stride = image.depth() / 8;
    if (image.bytesPerLine() < image.width() * stride)
        return false;
    const uchar *const first = image.constScanLine(0);
    for (int y = 0; y < image.height(); ++y) {
        const uchar *const scanline = image.constScanLine(y);
        for (int offset = 0; offset < image.width() * stride; offset += stride) {
            if (std::memcmp(scanline + offset, first, stride) != 0)
                return true;
        }
    }
    return false;
}

} // namespace

void TrackHeadersTest::unattachedModelPublishesSafeZeroGeometry()
{
    TrackActivity activity;
    songview::TrackHeaderModel model(fixture().view());
    model.rebuild(activity, false);

    QCOMPARE(model.viewportHeight(), 0.0);
    QCOMPARE(model.maximumScrollY(), 0.0);
    QCOMPARE(model.rowCount(),
             int(fixture().tracks().size()) + int(fixture().tab().document().canAddTrack()));
    for (int row = 0; row < model.rowCount(); ++row) {
        if (rowData(model, row, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            continue;
        QCOMPARE(rowData(model, row, songview::TrackHeaderModel::ActivityLeftHeightRole).toReal(),
                 0.0);
        QCOMPARE(rowData(model, row, songview::TrackHeaderModel::ActivityRightHeightRole).toReal(),
                 0.0);
    }
}

void TrackHeadersTest::quickSurfacePublishesAndRendersHeaders()
{
    TrackHeadersFixture &fx = fixture();
    const QRect hostRect = fx.quick().geometry();
    const QRectF localRect(fx.isolatedBandRect().translated(-hostRect.topLeft()));

    QVERIFY(hostRect.contains(fx.isolatedBandRect()));
    QVERIFY(fx.root().property("trackHeadersBandVisible").toBool());
    QVERIFY(sameRect(fx.root().property("trackHeadersBandRect").toRectF(), localRect));
    QVERIFY(fx.band().isVisible());
    QVERIFY(near(fx.band().x(), localRect.x()));
    QVERIFY(near(fx.band().y(), localRect.y()));
    QVERIFY(near(fx.band().width(), localRect.width()));
    QVERIFY(near(fx.band().height(), localRect.height()));
    QVERIFY(fx.input().isVisible());
    QVERIFY(
        near(fx.input().width(), fx.isolatedBandRect().width() - fx.headers().scrollbarWidth()));
    QVERIFY(near(fx.input().height(), fx.isolatedBandRect().height()));
    QVERIFY(near(fx.scrollbar().x(), fx.input().width()));
    QVERIFY(near(fx.scrollbar().width(), fx.headers().scrollbarWidth()));
    QCOMPARE(fx.headers().viewportHeight(), qreal(fx.isolatedBandRect().height()));
    QCOMPARE(fx.headers().contentHeight(), fx.headers().rowCount() * fx.rowHeight());
    QVERIFY(!fx.headers().appearance().isEmpty());
    QCOMPARE(fx.rows().property("count").toInt(), fx.headers().rowCount());

    QString error;
    const QImage frame = fx.captureBand(error);
    QVERIFY2(!frame.isNull(), qPrintable(error));
    QVERIFY(hasDistinctPixels(frame));
}

void TrackHeadersTest::selectionAndVoiceRouteThroughHeaders()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    SongView &view = fx.view();
    const std::optional<int> selectionRow = fx.rowForTrack(fx.selectionTrack());
    const std::optional<int> voiceRow = fx.rowForTrack(fx.voiceTrack());
    QVERIFY(selectionRow && voiceRow);

    headers.setScrollY(0.0);
    const std::optional<QPointF> selection = fx.titlePoint(*selectionRow);
    QVERIFY(selection);
    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *selection, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), *selection, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(view.selectionModel().primaryTrack(), fx.selectionTrack());

    headers.setScrollY(qreal(*voiceRow * fx.rowHeight()));
    const std::optional<QPointF> voice = fx.voicePoint(*voiceRow);
    QVERIFY(voice);
    int revealCount = 0;
    int revealedProgram = -1;
    const QMetaObject::Connection reveal =
        QObject::connect(&view, &SongView::revealVoiceRequested, &view,
                         [&revealCount, &revealedProgram](int program) {
                             ++revealCount;
                             revealedProgram = program;
                         });
    QVERIFY(headers.pointerMove(pointerInput(fx.input(), *voice, Qt::NoButton, Qt::NoButton)));
    QVERIFY(rowData(headers, *voiceRow, songview::TrackHeaderModel::VoiceHoveredRole).toBool());
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *voice, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(rowData(headers, *voiceRow, songview::TrackHeaderModel::VoicePressedRole).toBool());
    QCOMPARE(view.selectionModel().primaryTrack(), fx.voiceTrack());
    QVERIFY(headers.pointerRelease(pointerInput(fx.input(), *voice, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(revealCount, 1);
    QCOMPARE(revealedProgram, view.currentProgram(fx.voiceTrack()));
    QVERIFY(!rowData(headers, *voiceRow, songview::TrackHeaderModel::VoicePressedRole).toBool());
    QObject::disconnect(reveal);
}

void TrackHeadersTest::muteAndSoloHonorCancellationAndButtons()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    SongView &view = fx.view();
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    headers.setScrollY(0.0);
    view.selectTrack(fx.selectionTrack());
    view.setTrackMute(fx.sourceTrack(), false);
    const std::optional<QPointF> mute = fx.mutePoint(*sourceRow);
    const std::optional<QPointF> solo = fx.soloPoint(*sourceRow);
    const std::optional<QPointF> title = fx.titlePoint(*sourceRow);
    QVERIFY(mute && solo && title);
    QVERIFY(headers.pointerMove(pointerInput(fx.input(), *mute, Qt::NoButton, Qt::NoButton)));
    QVERIFY(rowData(headers, *sourceRow, songview::TrackHeaderModel::MuteHoveredRole).toBool());
    headers.pointerLeave();
    QVERIFY(!rowData(headers, *sourceRow, songview::TrackHeaderModel::MuteHoveredRole).toBool());
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *mute, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(rowData(headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool());
    QVERIFY(headers.pointerPress(
        pointerInput(fx.input(), *title, Qt::RightButton, Qt::LeftButton | Qt::RightButton)));
    QVERIFY(rowData(headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool());
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), *title, Qt::RightButton, Qt::LeftButton)));
    QVERIFY(!view.trackMuted(fx.sourceTrack()));
    QVERIFY(!rowData(headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool());
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *mute, Qt::LeftButton, Qt::LeftButton)));
    headers.inputCancelled(songview::TimelineInputCancelReason::FocusLost);
    QVERIFY(!rowData(headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool());
    QVERIFY(!view.trackMuted(fx.sourceTrack()));
    QVERIFY(!headers.pointerRelease(pointerInput(fx.input(), *mute, Qt::LeftButton, Qt::NoButton)));
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *mute, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(headers.pointerRelease(pointerInput(fx.input(), *mute, Qt::LeftButton, Qt::NoButton)));
    QVERIFY(view.trackMuted(fx.sourceTrack()));
    QVERIFY(rowData(headers, *sourceRow, songview::TrackHeaderModel::MuteCheckedRole).toBool());
    QCOMPARE(view.selectionModel().primaryTrack(), fx.selectionTrack());
    headers.activateMute(fx.sourceTrack());
    QVERIFY(!view.trackMuted(fx.sourceTrack()));

    view.setTrackSolo(fx.sourceTrack(), false);
    QVERIFY(headers.pointerMove(pointerInput(fx.input(), *solo, Qt::NoButton, Qt::NoButton)));
    QVERIFY(rowData(headers, *sourceRow, songview::TrackHeaderModel::SoloHoveredRole).toBool());
    headers.pointerLeave();
    QVERIFY(!rowData(headers, *sourceRow, songview::TrackHeaderModel::SoloHoveredRole).toBool());
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *solo, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(headers.pointerRelease(pointerInput(fx.input(), *solo, Qt::LeftButton, Qt::NoButton)));
    QVERIFY(view.trackSoloed(fx.sourceTrack()));
    QVERIFY(rowData(headers, *sourceRow, songview::TrackHeaderModel::SoloCheckedRole).toBool());
    headers.activateSolo(fx.sourceTrack());
    QVERIFY(!view.trackSoloed(fx.sourceTrack()));
}

void TrackHeadersTest::scrollClampsAndRoutesKeyboardAndWheelInput()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    const qreal maximumScroll = headers.maximumScrollY();
    QVERIFY(maximumScroll > 0.0);
    headers.setScrollY(maximumScroll + fx.rowHeight());
    QVERIFY(near(headers.scrollY(), maximumScroll));
    QVERIFY(fx.scrollbar().isVisible() && fx.thumb().isVisible());
    QVERIFY(fx.thumb().height() > 0.0 && fx.thumb().y() >= 0.0);
    QVERIFY(fx.thumb().y() + fx.thumb().height() <= fx.scrollbar().height() + kGeometryTolerance);
    headers.setScrollY(0.0);
    fx.scrollbar().forceActiveFocus(Qt::TabFocusReason);
    checks::events::sendKey(fx.scrollbar(), QEvent::KeyPress, Qt::Key_Down, Qt::NoModifier, {},
                            false, 1);
    checks::events::sendKey(fx.scrollbar(), QEvent::KeyRelease, Qt::Key_Down, Qt::NoModifier, {},
                            false, 1);
    checks::support::pumpQuick();
    QVERIFY(near(headers.scrollY(), std::min<qreal>(fx.rowHeight(), maximumScroll)));
    const qreal afterKey = headers.scrollY();
    QVERIFY(!headers.wheel(wheelInput(fx.input(), {1.0, 1.0}, {}, {kWheelNotch, 0})));
    QVERIFY(near(headers.scrollY(), afterKey));
    headers.setScrollY(0.0);
    QVERIFY(headers.wheel(wheelInput(fx.input(), {1.0, 1.0}, {}, {0, -kWheelNotch})));
    QVERIFY(headers.scrollY() > 0.0);
}

void TrackHeadersTest::tooltipClearsOnScroll()
{
    TrackHeadersFixture &fx = fixture();
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    const std::optional<QPointF> point = fx.titlePoint(*sourceRow);
    QVERIFY(point);
    QVERIFY(fx.headers().pointerMove(pointerInput(fx.input(), *point, Qt::NoButton, Qt::NoButton)));
    QVERIFY(fx.headers().toolTipVisible());
    QVERIFY(!fx.headers().toolTipText().isEmpty());
    QCOMPARE(fx.headers().toolTipPosition(), *point);
    checks::support::pumpQuick();
    QVERIFY(fx.toolTip().isVisible());
    QVERIFY(fx.toolTip().x() >= 0.0 && fx.toolTip().y() >= 0.0);
    QVERIFY(fx.toolTip().x() + fx.toolTip().width() <= fx.root().width() + kGeometryTolerance);
    QVERIFY(fx.toolTip().y() + fx.toolTip().height() <= fx.root().height() + kGeometryTolerance);
    QVERIFY(fx.headers().wheel(wheelInput(fx.input(), *point, {}, {0, -kWheelNotch})));
    checks::support::pumpQuick();
    QVERIFY(!fx.headers().toolTipVisible());
    QVERIFY(!fx.toolTip().isVisible());
}

void TrackHeadersTest::emptyTrackHeadersRejectInputWithoutMutation()
{
    MidiTimeline timeline;
    SongView emptyView;
    emptyView.resize(320, 180);
    emptyView.setSong(&timeline, nullptr);
    emptyView.show();
    checks::support::pumpQuick();
    auto *const model =
        emptyView.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
    auto *const quick = emptyView.quickView();
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    auto *const input = root ? root->findChild<songview::TimelineInputItem *>(
                                   QStringLiteral("timelineTrackHeadersInput"))
                             : nullptr;
    QVERIFY(model && quick && root && input);
    QTRY_COMPARE(model->rowCount(), 0);
    QVERIFY(!model->pointerPress(pointerInput(*input, {1.0, 1.0}, Qt::LeftButton, Qt::LeftButton)));

    const uint64_t revision = fixture().tab().document().revision();
    QVERIFY(!fixture().headers().pointerPress(
        pointerInput(fixture().input(), {-1.0, -1.0}, Qt::LeftButton, Qt::LeftButton)));
    QCOMPARE(fixture().tab().document().revision(), revision);
}
