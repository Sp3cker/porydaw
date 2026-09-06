#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <QDialog>
#include <QQuickItem>
#include <QTimer>

#include <algorithm>
#include <optional>

#include "checks/support/quickframebuffer.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/trackheadermodel.h"

namespace {

constexpr qreal kGeometryTolerance = 0.01;
constexpr qreal kProbeExtent = 2.0;
constexpr auto kRenamedTitle = "HdrSrc";

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

bool near(qreal actual, qreal expected)
{
    return qAbs(actual - expected) <= kGeometryTolerance;
}

std::vector<int> modelTracks(const songview::TrackHeaderModel &model)
{
    std::vector<int> tracks;
    for (int row = 0; row < model.rowCount(); ++row) {
        if (!rowData(model, row, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            tracks.push_back(rowData(model, row, songview::TrackHeaderModel::TrackRole).toInt());
    }
    return tracks;
}

void commitRename(TrackHeadersFixture &fixture, int track)
{
    songview::TrackHeaderModel &headers = fixture.headers();
    headers.beginRename(track);
    headers.setRenameDraft(QString::fromLatin1(kRenamedTitle));
    headers.finishRename(true, false);
}

} // namespace

void TrackHeadersTest::renameCommitsAndRebuildsHeader()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    const std::optional<QPointF> sourceTitle = fx.titlePoint(*sourceRow);
    QVERIFY(sourceTitle);
    const QString original = fx.tab().document().trackName(fx.sourceTrack());

    QVERIFY(headers.pointerDoubleClick(
        pointerInput(fx.input(), *sourceTitle, Qt::LeftButton, Qt::LeftButton)));
    QCOMPARE(headers.renamingTrack(), fx.sourceTrack());
    checks::support::pumpQuick();
    QVERIFY(fx.rename().isVisible());
    QQuickItem *const editor = fx.rename().parentItem();
    QVERIFY(editor);
    QVERIFY(near(editor->x(), headers.renameEditorRect().x()));
    QVERIFY(near(editor->y(), *sourceRow * headers.rowHeight() - headers.scrollY() +
                                  headers.renameEditorRect().y()));
    headers.finishRename(false, false);
    checks::support::pumpQuick();
    QCOMPARE(headers.renamingTrack(), -1);
    QCOMPARE(fx.tab().document().trackName(fx.sourceTrack()), original);
    QVERIFY(!fx.rename().isVisible());

    headers.beginRename(fx.sourceTrack());
    headers.setRenameDraft(QStringLiteral("Discard direct cancellation"));
    headers.cancelRename();
    QCOMPARE(headers.renamingTrack(), -1);
    QCOMPARE(fx.tab().document().trackName(fx.sourceTrack()), original);
    headers.beginRename(fx.sourceTrack());
    headers.setRenameDraft(QStringLiteral("Discard transient cancellation"));
    headers.cancelTransientState();
    checks::support::pumpQuick();
    QCOMPARE(headers.renamingTrack(), -1);
    QCOMPARE(fx.tab().document().trackName(fx.sourceTrack()), original);
    QVERIFY(!fx.rename().isVisible());

    commitRename(fx, fx.sourceTrack());
    QTRY_COMPARE(headers.renamingTrack(), -1);
    QCOMPARE(fx.tab().document().trackName(fx.sourceTrack()), QString::fromLatin1(kRenamedTitle));
    QString error;
    QVERIFY2(fx.rebuild(error), qPrintable(error));
    const std::optional<int> renamedRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(renamedRow);
    QVERIFY(rowData(headers, *renamedRow, songview::TrackHeaderModel::TitleRole)
                .toString()
                .contains(QString::fromLatin1(kRenamedTitle)));
}

void TrackHeadersTest::reorderCommitsAndRebuildsHeader()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    commitRename(fx, fx.sourceTrack());
    QTRY_COMPARE(fx.tab().document().trackName(fx.sourceTrack()),
                 QString::fromLatin1(kRenamedTitle));
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    const std::optional<QPointF> start = fx.titlePoint(*sourceRow);
    QVERIFY(start);

    const QPointF noOpDrop{start->x(), 0.0};
    const uint64_t noOpRevision = fx.tab().document().revision();
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(headers.pointerMove(pointerInput(fx.input(), noOpDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(headers.reorderIndicatorVisible());
    QVERIFY(near(headers.reorderIndicatorY(), 0.0));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), noOpDrop, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(fx.tab().document().revision(), noOpRevision);

    const int trackRows = int(modelTracks(headers).size());
    const QPointF bottomDrop{start->x(), qreal(trackRows * headers.rowHeight())};
    const uint64_t cancelRevision = fx.tab().document().revision();
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerMove(pointerInput(fx.input(), bottomDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(headers.reorderIndicatorVisible());
    QVERIFY(near(headers.reorderIndicatorY(), trackRows * headers.rowHeight()));
    checks::support::pumpQuick();
    QVERIFY(fx.marker().isVisible());
    QVERIFY(fx.marker().y() >= 0.0);
    QVERIFY(fx.marker().y() + fx.marker().height() <= fx.input().height() + kGeometryTolerance);
    headers.inputCancelled(songview::TimelineInputCancelReason::PointerUngrabbed);
    QVERIFY(!headers.reorderIndicatorVisible());
    QVERIFY(!headers.pointerRelease(
        pointerInput(fx.input(), bottomDrop, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(fx.tab().document().revision(), cancelRevision);

    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerMove(pointerInput(fx.input(), bottomDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(headers.pointerRelease(
        pointerInput(fx.input(), bottomDrop, Qt::RightButton, Qt::LeftButton)));
    QVERIFY(!headers.reorderIndicatorVisible());
    QCOMPARE(fx.tab().document().revision(), cancelRevision);

    const uint64_t commitRevision = fx.tab().document().revision();
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerMove(pointerInput(fx.input(), bottomDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), bottomDrop, Qt::LeftButton, Qt::NoButton)));
    QTRY_VERIFY(fx.tab().document().revision() > commitRevision);
    QCOMPARE(fx.tab().document().trackName(fx.reorderTargetTrack()),
             QString::fromLatin1(kRenamedTitle));
    QString error;
    QVERIFY2(fx.rebuild(error), qPrintable(error));
    const std::optional<int> movedRow = fx.rowForTrack(fx.reorderTargetTrack());
    QVERIFY(movedRow);
    QVERIFY(rowData(headers, *movedRow, songview::TrackHeaderModel::TitleRole)
                .toString()
                .contains(QString::fromLatin1(kRenamedTitle)));
}

void TrackHeadersTest::addTrackOpensPickerAndRebuildsHeader()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    headers.setScrollY(headers.maximumScrollY());
    const std::optional<int> row = fx.addTrackRow();
    QVERIFY(row);
    const qreal halfProbe = kProbeExtent / 2.0;
    const std::optional<QPointF> addPoint = fx.pointForRow(
        *row, QRectF{fx.input().width() / 2.0 - halfProbe, headers.rowHeight() / 2.0 - halfProbe,
                     kProbeExtent, kProbeExtent});
    QVERIFY(addPoint);
    const uint64_t revision = fx.tab().document().revision();
    const int rowCount = headers.rowCount();
    const std::vector<int> before = modelTracks(headers);
    const int selected = fx.view().selectionModel().primaryTrack();

    QVERIFY(headers.pointerMove(pointerInput(fx.input(), *addPoint, Qt::NoButton, Qt::NoButton)));
    QVERIFY(rowData(headers, *row, songview::TrackHeaderModel::AddHoveredRole).toBool());
    headers.pointerLeave();
    QVERIFY(!rowData(headers, *row, songview::TrackHeaderModel::AddHoveredRole).toBool());
    QVERIFY(headers.pointerPress(
        pointerInput(fx.input(), *addPoint, Qt::RightButton, Qt::RightButton)));
    QCOMPARE(fx.view().selectionModel().primaryTrack(), selected);
    QCOMPARE(fx.tab().document().revision(), revision);

    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(rowData(headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool());
    headers.inputCancelled(songview::TimelineInputCancelReason::FocusLost);
    QVERIFY(!rowData(headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool());
    QCOMPARE(fx.tab().document().revision(), revision);
    QVERIFY(
        !headers.pointerRelease(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::NoButton)));

    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::LeftButton)));
    const QPointF outsideRow = *addPoint - QPointF{0.0, qreal(headers.rowHeight())};
    QVERIFY(fx.input().bounds().contains(outsideRow));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), outsideRow, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(fx.tab().document().revision(), revision);
    QVERIFY(!rowData(headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool());

    bool pickerSeen = false;
    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::LeftButton)));
    QTimer::singleShot(0, &fx.view(), [&fx, &pickerSeen] {
        if (QDialog *const dialog = fx.view().findChild<QDialog *>()) {
            pickerSeen = true;
            dialog->accept();
        }
    });
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::NoButton)));
    QTRY_VERIFY(pickerSeen);
    QTRY_VERIFY(fx.tab().document().revision() > revision);
    QString error;
    QVERIFY2(fx.rebuild(error), qPrintable(error));
    const std::vector<int> after = modelTracks(headers);
    const std::optional<int> afterRow = fx.addTrackRow();
    QCOMPARE(headers.rowCount(), rowCount + 1);
    QCOMPARE(after.size(), before.size() + 1);
    QVERIFY(std::is_sorted(after.cbegin(), after.cend()));
    QVERIFY(std::includes(after.cbegin(), after.cend(), before.cbegin(), before.cend()));
    QVERIFY(std::adjacent_find(after.cbegin(), after.cend()) == after.cend());
    QVERIFY(afterRow && *afterRow == headers.rowCount() - 1);
}
