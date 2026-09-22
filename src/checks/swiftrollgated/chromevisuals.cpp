#include "tst_swiftrollgated.h"

#include "nativefixture.h"
#include "ui/theme/themeruntime.h"

#include <QColor>
#include <QCoreApplication>
#include <QImage>
#include <QQuickItem>
#include <QQuickView>
#include <QRectF>
#include <QScopeGuard>
#include <QVariant>
#include <QWheelEvent>
#include <QtTest/QTest>

#include <algorithm>
#include <cmath>
#include <optional>

namespace {

constexpr int kBeatLineAlpha = 160;
constexpr int kFineBeatLineAlpha = 200;
constexpr int kNaturalPitch = 60;
constexpr int kAccidentalPitch = 61;

struct RowProbes {
    QPoint natural;
    QPoint accidental;
    int matchingColumns = 0;
    int sampledColumns = 0;
};

struct LineProbes {
    QPoint natural;
    QPoint accidental;
};

QColor withRelativeAlpha(themes::Role role, int alpha)
{
    auto color = themes::color(role);
    color.setAlpha((color.alpha() * alpha + 127) / 255);
    return color;
}

QColor sourceOver(const QColor &source, const QColor &destination)
{
    const int alpha = source.alpha();
    const auto channel = [alpha](int sourceValue, int destinationValue) {
        return (sourceValue * alpha + destinationValue * (255 - alpha) + 127) / 255;
    };
    return QColor::fromRgb(channel(source.red(), destination.red()),
                           channel(source.green(), destination.green()),
                           channel(source.blue(), destination.blue()));
}

qreal rowCenter(int pitch, qreal rowHeight)
{
    return (127.0 - pitch + 0.5) * rowHeight;
}

std::optional<RowProbes> findUncoveredRows(const QImage &image, QQuickItem &surface,
                                           qreal visibleLeft, qreal visibleRight, qreal naturalY,
                                           qreal accidentalY, const QColor &natural,
                                           const QColor &accidental)
{
    const int samples = (std::max)(1, qFloor(visibleRight - visibleLeft));
    std::optional<RowProbes> result;
    int matchingColumns = 0;
    for (int sample = 0; sample <= samples; ++sample) {
        const qreal x = visibleLeft + (visibleRight - visibleLeft) * sample / samples;
        const QPoint naturalPoint = surface.mapToScene(QPointF(x, naturalY)).toPoint();
        const QPoint accidentalPoint = surface.mapToScene(QPointF(x, accidentalY)).toPoint();
        if (!gridcheck::colorsNear(gridcheck::pixelAt(image, naturalPoint), natural) ||
            !gridcheck::colorsNear(gridcheck::pixelAt(image, accidentalPoint), accidental)) {
            continue;
        }
        ++matchingColumns;
        if (!result)
            result = RowProbes{naturalPoint, accidentalPoint};
    }
    if (result) {
        result->matchingColumns = matchingColumns;
        result->sampledColumns = samples + 1;
    }
    return result;
}

std::optional<LineProbes> findLine(const QImage &image, QQuickItem &surface, qreal visibleLeft,
                                   qreal visibleRight, qreal naturalY, qreal accidentalY,
                                   const QColor &natural, const QColor &accidental)
{
    const qreal dpr = image.devicePixelRatio();
    const QPointF naturalLeft = surface.mapToScene(QPointF(visibleLeft, naturalY));
    const QPointF naturalRight = surface.mapToScene(QPointF(visibleRight, naturalY));
    const QPointF accidentalScene = surface.mapToScene(QPointF(visibleLeft, accidentalY));
    const qreal left = (std::min)(naturalLeft.x(), naturalRight.x());
    const qreal right = (std::max)(naturalLeft.x(), naturalRight.x());
    const int firstColumn = qCeil(left * dpr - 0.5);
    const int finalColumn = qFloor(right * dpr - 0.5);
    const int naturalRow = qRound(naturalLeft.y() * dpr - 0.5);
    const int accidentalRow = qRound(accidentalScene.y() * dpr - 0.5);
    for (int column = firstColumn; column <= finalColumn; ++column) {
        const QPoint naturalPoint{column, naturalRow};
        const QPoint accidentalPoint{column, accidentalRow};
        if (image.rect().contains(naturalPoint) && image.rect().contains(accidentalPoint) &&
            gridcheck::colorsNear(image.pixelColor(naturalPoint), natural) &&
            gridcheck::colorsNear(image.pixelColor(accidentalPoint), accidental)) {
            return LineProbes{naturalPoint, accidentalPoint};
        }
    }
    return std::nullopt;
}

std::optional<int> separatorDeviceRow(const QImage &image, const QPointF &scenePoint,
                                      const QColor &separator)
{
    const qreal dpr = image.devicePixelRatio();
    const int deviceX = qFloor((scenePoint.x() + 0.5) * dpr);
    const int expectedRow = qFloor(scenePoint.y() * dpr);
    for (int offset = -2; offset <= 2; ++offset) {
        const int row = expectedRow + offset;
        if (image.rect().contains(deviceX, row) &&
            gridcheck::colorsNear(image.pixelColor(deviceX, row), separator)) {
            return row;
        }
    }
    return std::nullopt;
}

void sendVerticalWheel(QQuickView &view, QQuickItem &target, int angle)
{
    const QPointF scenePoint = target.mapToScene(target.boundingRect().center());
    QWheelEvent event(scenePoint, view.mapToGlobal(scenePoint.toPoint()), QPoint(),
                      QPoint(0, angle), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(&view, &event);
}

} // namespace

void SwiftRollGatedTest::chromeRasterParity()
{
    if (m_mode == QStringLiteral("swiftbandkeys"))
        QSKIP("chrome raster parity belongs to the swiftrollgated surface");
    if (m_mode == QStringLiteral("swiftqtml"))
        QSKIP("chrome raster parity belongs to the swiftrollgated surface");
    if (m_mode == QStringLiteral("selectionkey"))
        QSKIP("chrome raster parity belongs to the swiftrollgated surface");
    QCOMPARE(m_mode, QStringLiteral("swiftrollgated"));

    gridcheck::NativeScene scene;
    QString openError;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &openError), qPrintable(openError));
    QQuickView *const view = scene.view;
    QQuickItem *const root = scene.root;
    QObject *const grid = scene.grid;
    QTRY_VERIFY_WITH_TIMEOUT(grid->property("renderedNoteCount").toInt() > 0, 5'000);

    QQuickItem *const plot =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickRollPlot"));
    QQuickItem *const gutter =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickRollGutter"));
    QQuickItem *const surface =
        gridcheck::visualDescendant(root, QStringLiteral("pianoGridSurface"));
    QQuickItem *const rows =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickPianoGridRows"));
    QQuickItem *const time =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickPianoGridTime"));
    QQuickItem *const keys =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickPianoKeyboardKeys"));
    QQuickItem *const chip =
        gridcheck::visualDescendant(root, QStringLiteral("timelineQuickPianoHoverChip"));
    QVERIFY(plot != nullptr);
    QVERIFY(gutter != nullptr);
    QVERIFY(surface != nullptr);
    QVERIFY(rows != nullptr);
    QVERIFY(time != nullptr);
    QVERIFY(keys != nullptr);
    QVERIFY(chip != nullptr);

    const QRectF plotScene = plot->mapRectToScene(plot->boundingRect());
    const QRectF gutterScene = gutter->mapRectToScene(gutter->boundingRect());
    QTRY_VERIFY_WITH_TIMEOUT(gridcheck::visiblePrimitiveCount(rows, plotScene) > 0, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(gridcheck::visiblePrimitiveCount(time, plotScene) > 0, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(gridcheck::visiblePrimitiveCount(keys, gutterScene) > 0, 5'000);

    const qreal rowHeight = grid->property("rowHeight").toDouble();
    const qreal keyboardWidth = grid->property("keyboardWidth").toDouble();
    QVERIFY(rowHeight > 0.0);
    QVERIFY(keyboardWidth > 0.0);

    QVERIFY(gridcheck::awaitFrame(view));
    QImage image;
    QTRY_VERIFY_WITH_TIMEOUT(!(image = view->grabWindow()).isNull(), 5'000);
    QVERIFY(image.devicePixelRatio() > 0.0);

    const QColor natural = themes::color(themes::Role::song_view_piano_roll_background);
    const QColor accidental = themes::color(themes::Role::song_view_piano_roll_accidental_lane);
    const qreal cameraScrollX = grid->property("cameraScrollX").toDouble();
    const qreal cameraScrollY = grid->property("cameraScrollY").toDouble();
    QVERIFY(std::isfinite(cameraScrollX));
    QVERIFY(std::isfinite(cameraScrollY));
    const qreal naturalY = rowCenter(kNaturalPitch, rowHeight) - cameraScrollY;
    const qreal accidentalY = rowCenter(kAccidentalPitch, rowHeight) - cameraScrollY;
    const qreal visibleContentLeft = cameraScrollX + plot->width() * 0.10;
    const qreal visibleContentRight = cameraScrollX + plot->width() * 0.90;
    const qreal visibleLeft = visibleContentLeft - cameraScrollX;
    const qreal visibleRight = visibleContentRight - cameraScrollX;

    const auto rowProbes = findUncoveredRows(image, *surface, visibleLeft, visibleRight, naturalY,
                                             accidentalY, natural, accidental);
    QVERIFY2(rowProbes.has_value(),
             "the C4/C#4 row centers did not expose the production role colors");
    QVERIFY2(rowProbes->matchingColumns >= rowProbes->sampledColumns / 4,
             "less than one quarter of the C4/C#4 row-center region kept both role colors");

    const QPoint naturalKey = gutter->mapToScene(QPointF(keyboardWidth * 0.25, naturalY)).toPoint();
    const QPoint accidentalKey =
        gutter->mapToScene(QPointF(keyboardWidth * 0.25, accidentalY)).toPoint();
    const QColor expectedNaturalKey =
        themes::color(themes::Role::song_view_piano_keyboard_natural_key);
    const QColor expectedAccidentalKey =
        themes::color(themes::Role::song_view_piano_keyboard_black_key);
    QVERIFY(gridcheck::colorsNear(gridcheck::pixelAt(image, naturalKey), expectedNaturalKey));
    QVERIFY(gridcheck::colorsNear(gridcheck::pixelAt(image, accidentalKey), expectedAccidentalKey));

    const qreal cBoundary = (127.0 - kNaturalPitch + 1.0) * rowHeight - cameraScrollY;
    const QColor separator = themes::color(themes::Role::song_view_piano_keyboard_separator);
    const QPointF gutterBoundary = gutter->mapToScene(QPointF(keyboardWidth * 0.25, cBoundary));
    const QPointF rollBoundary(rowProbes->natural.x(),
                               surface->mapToScene(QPointF(0.0, cBoundary)).y());
    const auto gutterSeparatorRow = separatorDeviceRow(image, gutterBoundary, separator);
    const auto rollSeparatorRow = separatorDeviceRow(image, rollBoundary, separator);
    QVERIFY2(gutterSeparatorRow.has_value(), "the keyboard C4 separator is not role-colored");
    QVERIFY2(rollSeparatorRow.has_value(), "the roll C4 separator is not role-colored");
    QCOMPARE(*gutterSeparatorRow, *rollSeparatorRow);

    const QColor barInk = themes::color(themes::Role::song_view_grid);
    const int beatAlpha =
        grid->property("visibleGridTicks").toInt() == 1 ? kFineBeatLineAlpha : kBeatLineAlpha;
    const QColor beatInk = withRelativeAlpha(themes::Role::song_view_grid, beatAlpha);
    const QColor expectedBarNatural = sourceOver(barInk, natural);
    const QColor expectedBarAccidental = sourceOver(barInk, accidental);
    const QColor expectedBeatNatural = sourceOver(beatInk, natural);
    const QColor expectedBeatAccidental = sourceOver(beatInk, accidental);
    QVERIFY2(!gridcheck::colorsNear(expectedBarNatural, natural) &&
                 !gridcheck::colorsNear(expectedBarAccidental, accidental),
             "the active theme makes bar lines indistinguishable from both row roles");
    QVERIFY2(!gridcheck::colorsNear(expectedBeatNatural, natural) &&
                 !gridcheck::colorsNear(expectedBeatAccidental, accidental),
             "the active theme makes beat lines indistinguishable from both row roles");

    // TimeAxis restarts its beat/bar lattice at each signature event, including
    // an identical signature. Scan every visible device column instead of
    // assuming bars remain on leadPad + N * beatWidth after such a restart.
    const auto barProbes = findLine(image, *surface, visibleLeft, visibleRight, naturalY,
                                    accidentalY, expectedBarNatural, expectedBarAccidental);
    QVERIFY2(barProbes.has_value(),
             "no visible bar line composited the grid role over both row backgrounds");
    const auto beatProbes = findLine(image, *surface, visibleLeft, visibleRight, naturalY,
                                     accidentalY, expectedBeatNatural, expectedBeatAccidental);
    QVERIFY2(beatProbes.has_value(),
             "no visible beat line composited the relative-alpha grid role over both rows");

    const qreal initialScrollY = grid->property("cameraScrollY").toDouble();
    const qreal maximumScrollY = grid->property("cameraMaxVScroll").toDouble();
    const int wheelAngle = initialScrollY < maximumScrollY - 1.0 ? -120 : 120;
    sendVerticalWheel(*view, *gutter, wheelAngle);
    QTRY_VERIFY_WITH_TIMEOUT(
        std::abs(grid->property("cameraScrollY").toDouble() - initialScrollY) > 0.5, 5'000);

    const auto leavePointer =
        qScopeGuard([&] { QTest::mouseMove(view, plotScene.center().toPoint()); });
    const qreal scrolledY = grid->property("cameraScrollY").toDouble();
    const int hoverRow = std::clamp(qFloor((scrolledY + plot->height() * 0.5) / rowHeight), 0, 127);
    const int hoverPitch = 127 - hoverRow;
    const qreal hoverViewportY = (hoverRow + 0.5) * rowHeight - scrolledY;
    const QPointF hoverCenter = gutter->mapToScene(QPointF(keyboardWidth * 0.5, hoverViewportY));
    QTest::mouseMove(view, hoverCenter.toPoint());
    QTRY_VERIFY_WITH_TIMEOUT(grid->property("hoverKey").toInt() == hoverPitch && chip->isVisible(),
                             5'000);
    const qreal chipCenterY = chip->mapToScene(QPointF(0.0, chip->height() * 0.5)).y();
    const qreal oneDevicePixel = 1.0 / image.devicePixelRatio();
    QVERIFY2(std::abs(chipCenterY - hoverCenter.y()) <= oneDevicePixel,
             "the scrolled keyboard hover chip is not centered on the hovered pitch row");
}
