#include "checks/nativegraphics/nativegraphics_fixture.h"

#include <QtTest>

#include "checks/voicepickerdriver.h"

#include <QGuiApplication>
#include <QImage>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>

#include <QScopeGuard>

#include <array>
#include <cmath>
#include <memory>
#include <optional>
#include <utility>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include "core/songdocument.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

namespace {

constexpr QSize kWindowSize{1280, 800};
constexpr qreal kGeometryTolerance = 0.5;

bool nearRect(const QRectF &actual, const QRectF &expected)
{
    return qAbs(actual.left() - expected.left()) <= kGeometryTolerance &&
           qAbs(actual.top() - expected.top()) <= kGeometryTolerance &&
           qAbs(actual.width() - expected.width()) <= kGeometryTolerance &&
           qAbs(actual.height() - expected.height()) <= kGeometryTolerance;
}

QColor averageColor(const QImage &image, const QPointF &logicalPoint)
{
    const QRect device = checks::support::devicePixelRect(
        image, QRect{qFloor(logicalPoint.x()), qFloor(logicalPoint.y()), 1, 1});
    if (device.isEmpty())
        return {};

    qint64 red = 0;
    qint64 green = 0;
    qint64 blue = 0;
    qint64 alpha = 0;
    for (int y = device.top(); y <= device.bottom(); ++y) {
        for (int x = device.left(); x <= device.right(); ++x) {
            const QColor pixel = image.pixelColor(x, y);
            red += pixel.red();
            green += pixel.green();
            blue += pixel.blue();
            alpha += pixel.alpha();
        }
    }
    const qint64 count = device.width() * device.height();
    return QColor{int(red / count), int(green / count), int(blue / count), int(alpha / count)};
}

bool nearColor(const QColor &actual, const QColor &expected, int tolerance = 14)
{
    return qAbs(actual.alpha() - expected.alpha()) <= tolerance &&
           qAbs(actual.red() - expected.red()) <= tolerance &&
           qAbs(actual.green() - expected.green()) <= tolerance &&
           qAbs(actual.blue() - expected.blue()) <= tolerance;
}

bool channelBetween(int value, int left, int right)
{
    return value >= (std::min)(left, right) && value <= (std::max)(left, right);
}

class NativeWindowingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(NativeWindowingTest)

  public:
    NativeWindowingTest(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void exposureAndChromeRouting();
    void headerSelectionAndVoicePicker();
    void geometryChunksShrinkClearAndReactivate();

  private:
    std::unique_ptr<checks::nativegraphics::Rig> freshRig() const
    {
        QString error;
        std::unique_ptr<checks::nativegraphics::Rig> rig =
            checks::nativegraphics::makeRig(m_projectRoot, m_songLabel, kWindowSize, error);
        if (!rig)
            QTest::qFail(qPrintable(error), __FILE__, __LINE__);
        return rig;
    }

    QString m_projectRoot;
    QString m_songLabel;
};

void NativeWindowingTest::exposureAndChromeRouting()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = freshRig();
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *quick = view.quickView();
    QVERIFY(quick && quick->quickWindow() && quick->rootObject());
    // Direct unhosted rig: exposure is the Quick window's own.
    QTRY_VERIFY(quick->quickWindow()->isExposed());

    auto *overlay =
        view.findChild<songview::PlayheadOverlay *>(QString{}, Qt::FindDirectChildrenOnly);
    QVERIFY(overlay);
#ifdef __APPLE__
    QVERIFY(!quick->playheadVisible());
#else
    QVERIFY(!quick->playheadVisible());
#endif

    auto *headers = view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"),
                                                                 Qt::FindDirectChildrenOnly);
    auto *headerBand =
        quick->rootObject()->findChild<QQuickItem *>(QStringLiteral("timelineQuickTrackHeaders"));
    auto *headerInput = quick->rootObject()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineTrackHeadersInput"));
    QObject *headerRows =
        quick->rootObject()->findChild<QObject *>(QStringLiteral("timelineTrackHeaderRows"));
    const std::optional<songview::TimelineBandGeometry> &geometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    QVERIFY(headers);
    QVERIFY(headerBand);
    QVERIFY(headerInput);
    QVERIFY(headerRows);
    QVERIFY(quick->quickWindow());
    QVERIFY(geometry);
    QVERIFY(headerBand->isVisible());
    QVERIFY(headerInput->isVisible());
    QCOMPARE(headerInput->interaction(), static_cast<songview::TimelineBandInteraction *>(headers));
    QVERIFY(
        nearRect(QRectF(headerBand->mapToItem(quick->rootObject(), QPointF()), headerBand->size()),
                 QRectF(geometry->rect)));
    QVERIFY(qAbs(headerInput->width() + headers->scrollbarWidth() - geometry->rect.width()) <=
            kGeometryTolerance);
    QVERIFY(qAbs(headerInput->height() - geometry->rect.height()) <= kGeometryTolerance);
    QCOMPARE(headerRows->property("count").toInt(), headers->rowCount());
    QVERIFY(quick->quickWindow()->mask().isEmpty());
}

void NativeWindowingTest::headerSelectionAndVoicePicker()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = freshRig();
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *quick = view.quickView();
    QVERIFY(quick && quick->rootObject() && quick->quickWindow());
    QTRY_VERIFY(quick->quickWindow()->isExposed());

    auto *headers = view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"),
                                                                 Qt::FindDirectChildrenOnly);
    auto *headerInput = quick->rootObject()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineTrackHeadersInput"));
    QVERIFY(headers);
    QVERIFY(headerInput);

    QVERIFY(view.focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason));
    QTRY_VERIFY(QGuiApplication::focusWindow() == quick->quickWindow() &&
                QGuiApplication::focusObject() == headerInput && headerInput->hasActiveFocus());

    const int selectedTrack = view.selectionModel().primaryTrack();
    int selectedRow = -1;
    int alternateRow = -1;
    int previousTrack = -1;
    int addRows = 0;
    for (int row = 0; row < headers->rowCount(); ++row) {
        const QModelIndex index = headers->index(row, 0);
        const bool isAdd =
            headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool();
        if (isAdd) {
            ++addRows;
            QCOMPARE(row, headers->rowCount() - 1);
            continue;
        }
        const int track = headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
        QVERIFY(track > previousTrack);
        QVERIFY(addRows == 0);
        previousTrack = track;
        if (track == selectedTrack)
            selectedRow = row;
        else if (alternateRow < 0)
            alternateRow = row;
    }
    QCOMPARE(addRows, rig->song->document().canAddTrack() ? 1 : 0);
    QVERIFY(selectedRow >= 0);

    const int targetRow = alternateRow >= 0 ? alternateRow : selectedRow;
    const QModelIndex target = headers->index(targetRow, 0);
    const int targetTrack = headers->data(target, songview::TrackHeaderModel::TrackRole).toInt();
    QVERIFY(targetTrack >= 0);
    headers->setScrollY(qreal(targetRow * headers->rowHeight()));
    checks::support::pumpQuick();
    const QRectF title = headers->data(target, songview::TrackHeaderModel::TitleRectRole).toRectF();
    const QPointF body =
        title.center() + QPointF(0.0, targetRow * headers->rowHeight() - headers->scrollY());
    const QPointF voice = headers->voiceLineRect().center() +
                          QPointF(0.0, targetRow * headers->rowHeight() - headers->scrollY());
    QVERIFY(!title.isEmpty());
    QVERIFY(headerInput->bounds().contains(body));
    QVERIFY(headerInput->bounds().contains(voice));

    const QPoint bodyInWindow = headerInput->mapToScene(body).toPoint();
    const QPoint voiceInWindow = headerInput->mapToScene(voice).toPoint();
    QVERIFY(checks::events::primeMouseMove(*quick->quickWindow(), *headerInput, bodyInWindow));
    QTest::mouseClick(quick->quickWindow(), Qt::LeftButton, Qt::NoModifier, bodyInWindow);
    QTRY_COMPARE(view.selectionModel().primaryTrack(), targetTrack);

    const int undoBefore = rig->song->document().undoStack()->index();
    QVERIFY(checks::events::primeMouseMove(*quick->quickWindow(), *headerInput, voiceInWindow));
    QTest::mouseDClick(quick->quickWindow(), Qt::LeftButton, Qt::NoModifier, voiceInWindow);
    QTRY_VERIFY(static_cast<bool>(checks::voicepicker::active(view)));
    const checks::voicepicker::Picker picker = checks::voicepicker::active(view);
    QVERIFY(picker.root->isVisible());
    QVERIFY(picker.list->isVisible());
    QTRY_VERIFY(picker.search->hasActiveFocus());

    checks::voicepicker::filter(picker, QStringLiteral("127"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 127) &&
                checks::voicepicker::row(picker, 127)->isVisible());

    checks::voicepicker::filter(picker, QStringLiteral("zz-no-such-voice"));
    QTRY_VERIFY(!picker.accept->property("enabled").toBool());

    checks::voicepicker::filter(picker, QString());
    QTRY_VERIFY(checks::voicepicker::row(picker, 0) &&
                checks::voicepicker::row(picker, 0)->isVisible());
    QTest::keyClick(picker.window, Qt::Key_Escape);
    QTRY_VERIFY(!quick_popup::popupSession(view)->isOpen());
    QCOMPARE(rig->song->document().undoStack()->index(), undoBefore);
    const auto *rename =
        quick->rootObject()->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderRename"));
    QVERIFY(!rename || !rename->isVisible());
}

void NativeWindowingTest::geometryChunksShrinkClearAndReactivate()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = freshRig();
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *quick = view.quickView();
    QVERIFY(quick && quick->rootObject());
    const std::optional<songview::TimelineBandGeometry> &roll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    const QRectF band =
        QRectF(roll->rect).intersected(QRectF(QPointF{}, quick->rootObject()->size()));
    QVERIFY(band.width() >= 160.0 && band.height() >= 120.0);

    auto *item = new songview::TimelineQuickItem(quick->rootObject());
    auto *scene = new songview::TimelineQuickScene(item);
    item->setWidth(quick->rootObject()->width());
    item->setHeight(quick->rootObject()->height());
    item->setZ(10'000.0);
    item->setSceneLayer(songview::TimelineQuickLayer::PianoDrawPreviewFill);
    item->setScene(scene);
    const auto cleanup = qScopeGuard([item] {
        item->setScene(nullptr);
        item->deleteLater();
        checks::support::pumpQuick();
    });

    const auto layer = songview::TimelineQuickLayer::PianoDrawPreviewFill;
    const qreal x = band.left() + 24.0;
    const qreal y = band.top() + 24.0;
    const QRectF filler{x + 120.0, y + 88.0, 1.0, 1.0};
    const QRectF oldSolid{x, y, 20.0, 20.0};
    const QRectF oldGradient{x + 32.0, y, 48.0, 20.0};
    const std::array<QPointF, 3> oldTriangle{QPointF{x + 96.0, y + 20.0},
                                             QPointF{x + 116.0, y + 20.0}, QPointF{x + 106.0, y}};
    const QRectF marker{x, y + 36.0, 20.0, 20.0};
    const QRectF newSolid{x, y + 64.0, 20.0, 20.0};
    const QRectF newGradient{x + 32.0, y + 64.0, 48.0, 20.0};
    const std::array<QPointF, 3> newTriangle{
        QPointF{x + 96.0, y + 84.0}, QPointF{x + 116.0, y + 84.0}, QPointF{x + 106.0, y + 64.0}};
    const QColor fillerColor{8, 12, 16};
    const QColor oldSolidColor{208, 24, 112};
    const QColor oldBase{20, 52, 192};
    const QColor oldLeft{232, 20, 88, 128};
    const QColor oldRight{24, 232, 72, 128};
    const QColor oldTriangleColor{232, 176, 24};
    const QColor markerColor{16, 200, 72};
    const QColor newSolidColor{40, 168, 232};
    const QColor newBase{168, 44, 24};
    const QColor newLeft{32, 224, 224, 128};
    const QColor newRight{240, 48, 224, 128};
    const QColor newTriangleColor{128, 48, 232};
    const QRectF clip = band;

    QString captureError;
    const auto capture = [&] {
        item->update();
        checks::support::pumpQuick();
        return checks::support::captureQuickBand(view, roll->rect, &captureError);
    };
    const auto inBand = [&band](const QPointF &point) { return point - band.topLeft(); };
    const auto point = [](const QRectF &rect) { return rect.center(); };
    const auto trianglePoint = [](const std::array<QPointF, 3> &triangle) {
        return (triangle[0] + triangle[1] + triangle[2]) / 3.0;
    };
    const auto addRectLoad = [&] {
        for (int index = 0; index < 256; ++index)
            songview::timeline_quick::addRect(scene->layer(layer), filler, fillerColor, clip);
    };
    const auto addTriangleLoad = [&](const std::array<QPointF, 3> &triangle, const QColor &color) {
        songview::timeline_quick::addClippedTriangle(scene->layer(layer), triangle[0], triangle[1],
                                                     triangle[2], color, clip);
        for (int index = 1; index < 506; ++index)
            songview::timeline_quick::addClippedTriangle(scene->layer(layer), filler.topLeft(),
                                                         filler.bottomRight(), filler.bottomLeft(),
                                                         fillerColor, clip);
    };

    const QImage baseline = capture();
    QVERIFY2(!baseline.isNull(), qPrintable(captureError));
    const auto matchesBaseline = [&](const QImage &image, const QPointF &rootPoint) {
        return nearColor(averageColor(image, inBand(rootPoint)),
                         averageColor(baseline, inBand(rootPoint)));
    };

    songview::timeline_quick::resetLayer(scene->layer(layer));
    addRectLoad();
    songview::timeline_quick::addRect(scene->layer(layer), marker, markerColor, clip);
    songview::timeline_quick::addRect(scene->layer(layer), oldSolid, oldSolidColor, clip);
    songview::timeline_quick::addRect(scene->layer(layer), oldGradient, oldBase, clip);
    songview::timeline_quick::addHorizontalGradient(scene->layer(layer), oldGradient, oldLeft,
                                                    oldRight, clip);
    addTriangleLoad(oldTriangle, oldTriangleColor);
    const QImage populated = capture();
    QVERIFY2(!populated.isNull(), qPrintable(captureError));
    QVERIFY(nearColor(averageColor(populated, inBand(point(oldSolid))), oldSolidColor));
    QVERIFY(
        nearColor(averageColor(populated, inBand(trianglePoint(oldTriangle))), oldTriangleColor));

    songview::timeline_quick::resetLayer(scene->layer(layer));
    addRectLoad();
    songview::timeline_quick::addRect(scene->layer(layer), marker, markerColor, clip);
    const QImage shrunken = capture();
    QVERIFY2(!shrunken.isNull(), qPrintable(captureError));
    QVERIFY(nearColor(averageColor(shrunken, inBand(point(marker))), markerColor));
    QVERIFY(matchesBaseline(shrunken, point(oldSolid)));
    QVERIFY(matchesBaseline(shrunken, point(oldGradient)));
    QVERIFY(matchesBaseline(shrunken, trianglePoint(oldTriangle)));

    songview::timeline_quick::resetLayer(scene->layer(layer));
    const QImage cleared = capture();
    QVERIFY2(!cleared.isNull(), qPrintable(captureError));
    QVERIFY(matchesBaseline(cleared, point(marker)));
    QVERIFY(matchesBaseline(cleared, point(oldSolid)));
    QVERIFY(matchesBaseline(cleared, trianglePoint(oldTriangle)));

    songview::timeline_quick::resetLayer(scene->layer(layer));
    addRectLoad();
    songview::timeline_quick::addClippedTriangle(scene->layer(layer), newTriangle[0],
                                                 newTriangle[1], newTriangle[2], newTriangleColor,
                                                 clip);
    const QImage partial = capture();
    QVERIFY2(!partial.isNull(), qPrintable(captureError));
    QVERIFY(nearColor(averageColor(partial, inBand(trianglePoint(newTriangle))), newTriangleColor));
    QVERIFY(matchesBaseline(partial, marker.topLeft() + QPointF{15.0, 15.0}));

    songview::timeline_quick::resetLayer(scene->layer(layer));
    addRectLoad();
    songview::timeline_quick::addRect(scene->layer(layer), marker, newSolidColor, clip);
    songview::timeline_quick::addRect(scene->layer(layer), newSolid, newSolidColor, clip);
    songview::timeline_quick::addRect(scene->layer(layer), newGradient, newBase, clip);
    songview::timeline_quick::addHorizontalGradient(scene->layer(layer), newGradient, newLeft,
                                                    newRight, clip);
    addTriangleLoad(newTriangle, newTriangleColor);
    const QImage reactivated = capture();
    QVERIFY2(!reactivated.isNull(), qPrintable(captureError));
    const QColor gradientLeft = averageColor(
        reactivated, inBand(QPointF{newGradient.left() + 2.0, newGradient.center().y()}));
    const QColor gradientMiddle = averageColor(reactivated, inBand(point(newGradient)));
    const QColor gradientRight = averageColor(
        reactivated, inBand(QPointF{newGradient.right() - 2.0, newGradient.center().y()}));
    QVERIFY(nearColor(averageColor(reactivated, inBand(point(newSolid))), newSolidColor));
    QVERIFY(
        nearColor(averageColor(reactivated, inBand(trianglePoint(newTriangle))), newTriangleColor));
    QVERIFY(!nearColor(gradientMiddle, averageColor(baseline, inBand(point(newGradient))), 5));
    QVERIFY(channelBetween(gradientMiddle.red(), gradientLeft.red(), gradientRight.red()));
    QVERIFY(channelBetween(gradientMiddle.green(), gradientLeft.green(), gradientRight.green()));
    QVERIFY(channelBetween(gradientMiddle.blue(), gradientLeft.blue(), gradientRight.blue()));
    QVERIFY(matchesBaseline(reactivated, point(oldSolid)));
    QVERIFY(matchesBaseline(reactivated, point(oldGradient)));
    QVERIFY(matchesBaseline(reactivated, trianglePoint(oldTriangle)));
}

} // namespace

int runRollWindowingCheck(const QString &projectRoot, const QString &songLabel,
                          const QStringList &qtArguments)
{
    NativeWindowingTest test{projectRoot, songLabel};
    QStringList arguments{QStringLiteral("rollwindowingcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_nativewindowing.moc"
