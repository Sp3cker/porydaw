#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <QAbstractItemModel>
#include <QColor>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <optional>

#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
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

using checks::events::pointerInput;

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

void TrackHeadersTest::quickSurfacePublishesAndRendersHeaders()
{
    TrackHeadersFixture &fx = fixture();
    const QRect viewport(QPoint{}, fx.window().size());
    QVERIFY(viewport.contains(fx.isolatedBandRect()));
    // Band rects are published canonical viewport-local, so the QML-published
    // rect compares directly against the isolated band rect.
    const QRectF localRect(fx.isolatedBandRect());
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
    SongDocument &doc = fx.tab().document();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    // Selection is presentation too: flipping the primary track flips the
    // record's BaseColorRole and alters the retained header raster.
    view.selectTrack(fx.sourceTrack()); // guarantee the target starts unselected
    checks::support::pumpQuick();
    const QColor unselectedBase =
        rowData(headers, *selectionRow, songview::TrackHeaderModel::BaseColorRole).value<QColor>();
    QString error;
    const QImage beforeSelection = fx.captureBand(error);
    QVERIFY2(!beforeSelection.isNull(), qPrintable(error));

    headers.setScrollY(0.0);
    const std::optional<QPointF> selection = fx.titlePoint(*selectionRow);
    QVERIFY(selection);
    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *selection, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), *selection, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(view.selectionModel().primaryTrack(), fx.selectionTrack());
    const QColor selectedBase =
        rowData(headers, *selectionRow, songview::TrackHeaderModel::BaseColorRole).value<QColor>();
    const QImage afterSelection = fx.captureBand(error);
    QVERIFY2(selectedBase != unselectedBase,
             "selecting a header record did not flip its base color role");
    QVERIFY2(afterSelection.size() == beforeSelection.size() && afterSelection != beforeSelection,
             "track selection did not alter the retained Quick header rendering");

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
    checks::support::pumpQuick();

    // A title-line click selects its track without requesting a voice reveal.
    const std::optional<QPointF> voiceTitle = fx.titlePoint(*voiceRow);
    QVERIFY(voiceTitle);
    QVERIFY(headers.pointerPress(
        pointerInput(fx.input(), *voiceTitle, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(headers.pointerRelease(
        pointerInput(fx.input(), *voiceTitle, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(revealCount, 1);
    QCOMPARE(view.selectionModel().primaryTrack(), fx.voiceTrack());

    // A drag beginning on the voice line becomes an adjacent no-op reorder
    // and must not reveal a voice on release.
    const QPointF adjacentDrop{voice->x(), fx.rowHeight() * 1.2};
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *voice, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerMove(pointerInput(fx.input(), adjacentDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(headers.pointerRelease(
        pointerInput(fx.input(), adjacentDrop, Qt::RightButton, Qt::LeftButton)));
    headers.pointerRelease(pointerInput(fx.input(), adjacentDrop, Qt::LeftButton, Qt::NoButton));
    checks::support::pumpQuick();
    QCOMPARE(revealCount, 1);
    QVERIFY(!headers.reorderIndicatorVisible());
    QObject::disconnect(reveal);
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(doc.smf().write(), before);
}

void TrackHeadersTest::muteAndSoloHonorCancellationAndButtons()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    SongView &view = fx.view();
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    // Mask-only updates publish bounded dataChanged coverage for just the
    // toggled row; the retained record structure never resets.
    struct RowChange {
        int first = -1;
        int last = -1;
        QList<int> roles;
    };
    std::vector<RowChange> changes;
    int resets = 0;
    const QMetaObject::Connection observed = QObject::connect(
        &headers, &QAbstractItemModel::dataChanged, &headers,
        [&changes](const QModelIndex &first, const QModelIndex &last, const QList<int> &roles) {
            changes.push_back({first.row(), last.row(), roles});
        });
    const QMetaObject::Connection resetObserved = QObject::connect(
        &headers, &QAbstractItemModel::modelReset, &headers, [&resets] { ++resets; });
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
    changes.clear();
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *mute, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(headers.pointerRelease(pointerInput(fx.input(), *mute, Qt::LeftButton, Qt::NoButton)));
    QVERIFY(view.trackMuted(fx.sourceTrack()));
    QVERIFY(rowData(headers, *sourceRow, songview::TrackHeaderModel::MuteCheckedRole).toBool());
    QCOMPARE(view.selectionModel().primaryTrack(), fx.selectionTrack());
    const int mutedRow = *sourceRow;
    QVERIFY2(!changes.empty() && std::all_of(changes.cbegin(), changes.cend(),
                                             [mutedRow](const RowChange &change) {
                                                 return change.first == mutedRow &&
                                                        change.last == mutedRow;
                                             }),
             "the mute toggle churned records beyond the muted row");
    QVERIFY2(std::any_of(changes.cbegin(), changes.cend(),
                         [mutedRow](const RowChange &change) {
                             return change.roles.contains(
                                 songview::TrackHeaderModel::MuteCheckedRole);
                         }),
             "the mute toggle did not publish the checked role");
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
    // Document-driven masks follow the same bounded row contract.
    view.setTrackMute(fx.sourceTrack(), false);
    changes.clear();
    view.setTrackMute(fx.sourceTrack(), true);
    QVERIFY2(!changes.empty() &&
                 std::all_of(changes.cbegin(), changes.cend(),
                             [row = *sourceRow](const RowChange &change) {
                                 return change.first == row && change.last == row;
                             }) &&
                 std::any_of(changes.cbegin(), changes.cend(),
                             [](const RowChange &change) {
                                 return change.roles.contains(
                                     songview::TrackHeaderModel::MuteCheckedRole);
                             }),
             "the mask-only update was not bounded mute-role coverage");
    QCOMPARE(resets, 0);
    QObject::disconnect(observed);
    QObject::disconnect(resetObserved);
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

void TrackHeadersTest::hoveringHeadersDoesNotCreateTooltip()
{
    TrackHeadersFixture &fx = fixture();
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    const std::optional<QPointF> point = fx.titlePoint(*sourceRow);
    QVERIFY(point);
    QVERIFY(fx.headers().pointerMove(pointerInput(fx.input(), *point, Qt::NoButton, Qt::NoButton)));
    checks::support::pumpQuick();
    QVERIFY(!fx.root().findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderToolTip")));
}

void TrackHeadersTest::emptyTrackHeadersRejectInputWithoutMutation()
{
    MidiTimeline timeline;
    SongView emptyView;
    emptyView.setSong(&timeline, nullptr);
    // Direct SongView fixture: the canvas host is declared after the view so
    // it detaches and dies before the borrowed SongView.
    const checks::QuickSceneHost host(emptyView, QSize(320, 180));
    QVERIFY(checks::support::showQuickViewport(emptyView, QSize(320, 180)));
    auto *const quick = emptyView.quickView();
    auto *const model =
        emptyView.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
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
