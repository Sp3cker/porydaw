#include "tst_swiftrollgated.h"

#include "nativefixture.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

#include <QColor>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QQuickItem>
#include <QQuickView>
#include <QRect>
#include <QVariant>
#include <QtTest/QTest>

#include <algorithm>
#include <array>
#include <optional>
#include <vector>

namespace {

constexpr int kBlackChannelMax = 16;
constexpr int kSelectAllCommand = 4;
constexpr double kSelectionRingFontFraction = 1.0 / 8.0;
constexpr double kSmallFontForScaledBorder = 4.0;
constexpr double kSmallFontForSinglePixelBorder = 7.0;

struct PublishedNote {
    quint64 id = 0;
    int track = 0;
    int velocity = 0;
    bool selected = false;
};

struct VisibleNote {
    PublishedNote note;
    QRect deviceRect;
};

std::optional<std::vector<PublishedNote>> publishedNotes(const QString &summary, QString *error)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(summary.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray()) {
        *error =
            QStringLiteral("noteSummary is not a JSON array: %1").arg(parseError.errorString());
        return std::nullopt;
    }

    std::vector<PublishedNote> result;
    result.reserve(std::size_t(document.array().size()));
    for (const QJsonValue value : document.array()) {
        if (!value.isObject()) {
            *error = QStringLiteral("noteSummary contains a non-object entry");
            return std::nullopt;
        }
        const QJsonObject object = value.toObject();
        const double id = object.value(QStringLiteral("id")).toDouble();
        if (id <= 0 || !object.value(QStringLiteral("track")).isDouble() ||
            !object.value(QStringLiteral("velocity")).isDouble()) {
            *error = QStringLiteral("noteSummary entry lacks a positive id, track, or velocity");
            return std::nullopt;
        }
        result.push_back({quint64(id), object.value(QStringLiteral("track")).toInt(),
                          object.value(QStringLiteral("velocity")).toInt(),
                          object.value(QStringLiteral("selected")).toBool()});
    }
    return result;
}

QRect deviceRectFor(QQuickItem *item, const QImage &image)
{
    const QRectF scene = item->mapRectToScene(item->boundingRect());
    const qreal dpr = image.devicePixelRatio();
    return QRect(qRound(scene.x() * dpr), qRound(scene.y() * dpr),
                 (std::max)(1, qRound(scene.width() * dpr)),
                 (std::max)(1, qRound(scene.height() * dpr)))
        .intersected(image.rect());
}

std::optional<VisibleNote> visibleNote(QQuickItem *fills, const QRectF &plotScene,
                                       const QImage &image, const std::vector<PublishedNote> &notes,
                                       std::optional<bool> selected)
{
    std::optional<VisibleNote> best;
    int bestArea = -1;
    for (const PublishedNote &note : notes) {
        if (selected && note.selected != *selected)
            continue;
        QQuickItem *const item =
            gridcheck::visualDescendant(fills, QStringLiteral("gridNote_%1").arg(note.id));
        if (!item || !item->isVisible())
            continue;
        const QRectF scene = item->mapRectToScene(item->boundingRect());
        if (!plotScene.adjusted(1.0, 1.0, -1.0, -1.0).contains(scene))
            continue;
        const QRect deviceRect = deviceRectFor(item, image);
        const int area = deviceRect.width() * deviceRect.height();
        if (deviceRect.width() >= 5 && deviceRect.height() >= 5 && area > bestArea) {
            best = VisibleNote{note, deviceRect};
            bestArea = area;
        }
    }
    return best;
}

bool publishedSelectionContains(QObject *grid, quint64 id)
{
    QString error;
    const auto notes = publishedNotes(grid->property("noteSummary").toString(), &error);
    if (!notes)
        return false;
    for (const PublishedNote &note : *notes)
        if (note.id == id)
            return note.selected;
    return false;
}

QColor originalNoteFace(int track, int velocity)
{
    const int count = int(themes::trackIdentityColorCount);
    const std::size_t index = std::size_t(((track % count) + count) % count);
    const auto identityHex = themes::track_identity_colors::fills[index];
    const QColor identity(QLatin1String(identityHex.data(), qsizetype(identityHex.size())));
    const QColor zero = themes::color(themes::Role::song_view_note_velocity_zero);
    const int clamped = std::clamp(velocity, 0, 127);
    if (clamped == 0)
        return zero;
    if (clamped == 127)
        return identity;
    const themes::Oklab from = themes::oklabFromColor(identity);
    const themes::Oklab to = themes::oklabFromColor(zero);
    const double amount = 1.0 - double(clamped) / 127.0;
    return themes::colorFromOklab({from.lightness + (to.lightness - from.lightness) * amount,
                                   from.a + (to.a - from.a) * amount,
                                   from.b + (to.b - from.b) * amount});
}

bool isPhysicalBlack(const QColor &color)
{
    return color.isValid() && color.red() <= kBlackChannelMax &&
           color.green() <= kBlackChannelMax && color.blue() <= kBlackChannelMax;
}

int fittedFrameThickness(const QRect &rect, int requestedPixels, int insetPixels)
{
    return std::clamp(((std::min)(rect.width(), rect.height()) - 1) / 2 - insetPixels, 0,
                      requestedPixels);
}

// Every segment of the shared playhead is a vertical line, and the tick-zero
// note begins exactly at the homed projection, so a note's left column is not a
// stable oracle: the frame probes sample the vertical edges, as the legacy
// production raster oracle does. The exact colour and black assertions, insets
// and thicknesses are unchanged.
QString frameColorFailure(const QImage &image, const QRect &rect, int inset, int thickness,
                          const QColor &expected, const QString &label)
{
    const int centerX = rect.center().x();
    for (int pixel = 0; pixel < thickness; ++pixel) {
        const int offset = inset + pixel;
        const std::array<QPoint, 2> probes = {
            QPoint(centerX, rect.top() + offset),
            QPoint(centerX, rect.bottom() - offset),
        };
        for (const QPoint &point : probes) {
            const QColor actual = image.rect().contains(point) ? image.pixelColor(point) : QColor{};
            if (!gridcheck::colorsNear(actual, expected)) {
                return QStringLiteral("%1 at device pixel (%2,%3): expected %4, actual %5")
                    .arg(label)
                    .arg(point.x())
                    .arg(point.y())
                    .arg(expected.name(QColor::HexArgb))
                    .arg(actual.name(QColor::HexArgb));
            }
        }
    }
    return {};
}

QString blackFrameFailure(const QImage &image, const QRect &rect, int inset, int thickness,
                          const QString &label)
{
    const int centerX = rect.center().x();
    for (int pixel = 0; pixel < thickness; ++pixel) {
        const int offset = inset + pixel;
        const std::array<QPoint, 2> probes = {
            QPoint(centerX, rect.top() + offset),
            QPoint(centerX, rect.bottom() - offset),
        };
        for (const QPoint &point : probes) {
            const QColor actual = image.rect().contains(point) ? image.pixelColor(point) : QColor{};
            if (!isPhysicalBlack(actual)) {
                return QStringLiteral("%1 at device pixel (%2,%3): expected physical black, "
                                      "actual %4")
                    .arg(label)
                    .arg(point.x())
                    .arg(point.y())
                    .arg(actual.name(QColor::HexArgb));
            }
        }
    }
    return {};
}

std::optional<VisibleNote> thinnedVisibleNote(QQuickItem *fills, const QRectF &plotScene,
                                              const QImage &image,
                                              const std::vector<PublishedNote> &notes,
                                              int ringRequest, int borderRequest)
{
    for (const PublishedNote &note : notes) {
        if (!note.selected)
            continue;
        QQuickItem *const item =
            gridcheck::visualDescendant(fills, QStringLiteral("gridNote_%1").arg(note.id));
        if (!item || !item->isVisible())
            continue;
        const QRectF scene = item->mapRectToScene(item->boundingRect());
        if (!plotScene.adjusted(1.0, 1.0, -1.0, -1.0).contains(scene))
            continue;
        const QRect rect = deviceRectFor(item, image);
        const int ring = fittedFrameThickness(rect, ringRequest, 0);
        const int border = fittedFrameThickness(rect, borderRequest, ring);
        if (ring > 0 && border > 0 && border < borderRequest)
            return VisibleNote{note, rect};
    }
    return std::nullopt;
}

} // namespace

void SwiftRollGatedTest::noteRasterParity()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("note raster parity belongs to the swiftrollgated surface");

    gridcheck::NativeScene scene;
    QString openError;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &openError), qPrintable(openError));
    QObject *const session = scene.session;
    QQuickView *const view = scene.view;
    QQuickItem *const root = scene.root;
    QObject *const grid = scene.grid;
    QTRY_VERIFY_WITH_TIMEOUT(grid->property("renderedNoteCount").toInt() > 0, 5'000);

    QQuickItem *const plot =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickRollPlot"));
    QQuickItem *const fills =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickPianoNoteFills"));
    QVERIFY(plot != nullptr);
    QVERIFY(fills != nullptr);
    const QRectF plotScene = plot->mapRectToScene(plot->boundingRect());
    QTRY_VERIFY_WITH_TIMEOUT(gridcheck::visiblePrimitiveCount(fills, plotScene) > 0, 5'000);

    QVERIFY(gridcheck::awaitFrame(view));
    const QImage unselectedImage = view->grabWindow();
    QVERIFY(!unselectedImage.isNull());
    QString summaryError;
    const auto initialNotes =
        publishedNotes(grid->property("noteSummary").toString(), &summaryError);
    QVERIFY2(initialNotes.has_value(), qPrintable(summaryError));
    const auto unselected = visibleNote(fills, plotScene, unselectedImage, *initialNotes, false);
    QVERIFY2(unselected.has_value(),
             "the retained fixture has no fully visible unselected note for a raster probe");

    const QColor expectedFace = originalNoteFace(unselected->note.track, unselected->note.velocity);
    const QColor unselectedFace = unselectedImage.pixelColor(unselected->deviceRect.center());
    const QString faceFailure =
        QStringLiteral("note %1 face violates the original track/velocity OKLab contract: "
                       "track %2 velocity %3 expected %4, actual %5")
            .arg(unselected->note.id)
            .arg(unselected->note.track)
            .arg(unselected->note.velocity)
            .arg(expectedFace.name(QColor::HexArgb))
            .arg(unselectedFace.name(QColor::HexArgb));
    QVERIFY2(gridcheck::colorsNear(unselectedFace, expectedFace), qPrintable(faceFailure));

    const qreal dpr = unselectedImage.devicePixelRatio();
    const int borderRequest = (std::max)(1, qRound(dpr));
    const int unselectedBorder = fittedFrameThickness(unselected->deviceRect, borderRequest, 0);
    QCOMPARE(unselectedBorder, borderRequest);
    const QString unselectedBorderFailure =
        blackFrameFailure(unselectedImage, unselected->deviceRect, 0, unselectedBorder,
                          QStringLiteral("unselected note %1 lost its display-scaled black border")
                              .arg(unselected->note.id));
    QVERIFY2(unselectedBorderFailure.isEmpty(), qPrintable(unselectedBorderFailure));

    QVERIFY(
        QMetaObject::invokeMethod(session, "performGridCommand", Q_ARG(int, kSelectAllCommand)));
    QTRY_VERIFY_WITH_TIMEOUT(publishedSelectionContains(grid, unselected->note.id), 5'000);

    QVERIFY(gridcheck::awaitFrame(view));
    const QImage selectedImage = view->grabWindow();
    QVERIFY(!selectedImage.isNull());
    // Model publication may replace delegates. Keep the note identity, not a
    // pointer into the previous frame's delegate tree.
    QQuickItem *const selectedItem =
        gridcheck::visualDescendant(fills, QStringLiteral("gridNote_%1").arg(unselected->note.id));
    QVERIFY(selectedItem && selectedItem->isVisible());
    const QRect selectedRect = deviceRectFor(selectedItem, selectedImage);
    const int ringRequest =
        (std::max)(1, qRound(grid->property("baseFontPx").toDouble() * kSelectionRingFontFraction *
                             selectedImage.devicePixelRatio()));
    const int ring = fittedFrameThickness(selectedRect, ringRequest, 0);
    QVERIFY2(ring > 0, "selected note is too small to retain a visible selection ring");
    const QColor expectedRing = themes::color(themes::Role::item_selected_background);
    const QString ringFailure =
        frameColorFailure(selectedImage, selectedRect, 0, ring, expectedRing,
                          QStringLiteral("selected note %1 outer ring must use "
                                         "themes::Role::item_selected_background")
                              .arg(unselected->note.id));
    QVERIFY2(ringFailure.isEmpty(), qPrintable(ringFailure));

    const int selectedBorder = fittedFrameThickness(selectedRect, borderRequest, ring);
    QVERIFY2(selectedBorder > 0, "selected note has no room for its inset black border");
    const QString selectedBorderFailure = blackFrameFailure(
        selectedImage, selectedRect, ring, selectedBorder,
        QStringLiteral("selected note %1 lost its inset black border").arg(unselected->note.id));
    QVERIFY2(selectedBorderFailure.isEmpty(), qPrintable(selectedBorderFailure));

    const QColor selectedFace = selectedImage.pixelColor(selectedRect.center());
    const QString selectedFaceFailure =
        QStringLiteral("selected note %1 frame changed its face: before %2, after %3, oracle %4")
            .arg(unselected->note.id)
            .arg(unselectedFace.name(QColor::HexArgb))
            .arg(selectedFace.name(QColor::HexArgb))
            .arg(expectedFace.name(QColor::HexArgb));
    QVERIFY2(gridcheck::colorsNear(selectedFace, unselectedFace) &&
                 gridcheck::colorsNear(selectedFace, expectedFace),
             qPrintable(selectedFaceFailure));

    const double smallFontPx =
        borderRequest > 1 ? kSmallFontForScaledBorder : kSmallFontForSinglePixelBorder;
    QVERIFY(QMetaObject::invokeMethod(grid, "configureViewport", Q_ARG(double, plot->width()),
                                      Q_ARG(double, plot->height()), Q_ARG(double, smallFontPx),
                                      Q_ARG(double, dpr)));
    QTRY_COMPARE_WITH_TIMEOUT(grid->property("baseFontPx").toDouble(), smallFontPx, 5'000);

    // Re-home through the production camera operation after the font/DPR push,
    // then prove its published vertical bound is the projected row height.
    QVERIFY(QMetaObject::invokeMethod(grid, "resetCameraScroll"));
    const double maxSmallScrollY =
        (std::max)(0.0, 128.0 * grid->property("rowHeight").toDouble() - plot->height());
    QTRY_VERIFY_WITH_TIMEOUT(
        qAbs(grid->property("cameraMaxVScroll").toDouble() - maxSmallScrollY) < 0.01, 5'000);
    const double smallScrollY = grid->property("cameraScrollY").toDouble();
    const QRectF smallPlotScene = plot->mapRectToScene(plot->boundingRect());
    QTRY_VERIFY_WITH_TIMEOUT(gridcheck::visiblePrimitiveCount(fills, smallPlotScene) > 0, 5'000);

    QVERIFY(gridcheck::awaitFrame(view));
    const QImage smallImage = view->grabWindow();
    QVERIFY(!smallImage.isNull());
    QString smallSummaryError;
    const auto smallNotes =
        publishedNotes(grid->property("noteSummary").toString(), &smallSummaryError);
    QVERIFY2(smallNotes.has_value(), qPrintable(smallSummaryError));
    const int smallRingRequest =
        (std::max)(1, qRound(grid->property("baseFontPx").toDouble() * kSelectionRingFontFraction *
                             smallImage.devicePixelRatio()));
    const int smallBorderRequest = (std::max)(1, qRound(smallImage.devicePixelRatio()));
    std::optional<VisibleNote> small;
    if (smallBorderRequest > 1) {
        small = thinnedVisibleNote(fills, smallPlotScene, smallImage, *smallNotes, smallRingRequest,
                                   smallBorderRequest);
        const QString smallSetupFailure =
            QStringLiteral("the public small-font viewport did not expose a selected note whose "
                           "physical black border should thin without vanishing: font=%1 dpr=%2 "
                           "rowHeight=%3 cameraScrollY=%4 targetY=%5 plot=(%6,%7 %8x%9) notes=%10")
                .arg(grid->property("baseFontPx").toDouble())
                .arg(smallImage.devicePixelRatio())
                .arg(grid->property("rowHeight").toDouble())
                .arg(grid->property("cameraScrollY").toDouble())
                .arg(smallScrollY)
                .arg(smallPlotScene.x())
                .arg(smallPlotScene.y())
                .arg(smallPlotScene.width())
                .arg(smallPlotScene.height())
                .arg(smallNotes->size());
        QVERIFY2(small.has_value(), qPrintable(smallSetupFailure));
    } else {
        small = visibleNote(fills, smallPlotScene, smallImage, *smallNotes, true);
        QVERIFY2(small.has_value(),
                 "the public small-font viewport has no fully visible selected note");
    }

    const int smallRing = fittedFrameThickness(small->deviceRect, smallRingRequest, 0);
    const int smallBorder = fittedFrameThickness(small->deviceRect, smallBorderRequest, smallRing);
    QVERIFY2(smallRing > 0 && smallBorder > 0,
             "small selected note geometry cannot preserve both ring and inset border");
    if (smallBorderRequest > 1)
        QVERIFY2(smallBorder < smallBorderRequest,
                 "small selected note did not exercise physical border thinning");
    const QString smallRingFailure =
        frameColorFailure(smallImage, small->deviceRect, 0, smallRing, expectedRing,
                          QStringLiteral("small selected note %1 lost its fitted selection ring")
                              .arg(small->note.id));
    QVERIFY2(smallRingFailure.isEmpty(), qPrintable(smallRingFailure));
    const QString smallBorderFailure = blackFrameFailure(
        smallImage, small->deviceRect, smallRing, smallBorder,
        QStringLiteral("small selected note %1 border vanished instead of thinning")
            .arg(small->note.id));
    QVERIFY2(smallBorderFailure.isEmpty(), qPrintable(smallBorderFailure));

    const QColor smallExpectedFace = originalNoteFace(small->note.track, small->note.velocity);
    const QColor smallFace = smallImage.pixelColor(small->deviceRect.center());
    const QString smallFaceFailure =
        QStringLiteral("small selected note %1 frame swallowed its face: expected %2, actual %3")
            .arg(small->note.id)
            .arg(smallExpectedFace.name(QColor::HexArgb))
            .arg(smallFace.name(QColor::HexArgb));
    QVERIFY2(gridcheck::colorsNear(smallFace, smallExpectedFace), qPrintable(smallFaceFailure));
}
