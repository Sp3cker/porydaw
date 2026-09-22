#include "tst_swiftrollgated.h"

#include "app/RewriteWindow.h"
#include "nativefixture.h"

#include "ui/theme/themeruntime.h"

#include <QApplication>
#include <QColor>
#include <QFile>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QRegularExpression>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QStatusBar>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QWidget>
#include <QtTest/QTest>

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>
#include <utility>

namespace {

constexpr int kSelectionFillAlpha = 30;
constexpr int kChannelTolerance = 2;

struct PixelProbe {
    QPoint point;
    QColor baseline;
};

} // namespace

namespace gridcheck {

QColor pixelAt(const QImage &image, const QPoint &logicalPoint)
{
    const qreal dpr = image.devicePixelRatio();
    const QPoint devicePoint(qFloor((logicalPoint.x() + 0.5) * dpr),
                             qFloor((logicalPoint.y() + 0.5) * dpr));
    return image.rect().contains(devicePoint) ? image.pixelColor(devicePoint) : QColor{};
}

bool colorsNear(const QColor &actual, const QColor &expected)
{
    return actual.isValid() && expected.isValid() &&
           std::abs(actual.red() - expected.red()) <= kChannelTolerance &&
           std::abs(actual.green() - expected.green()) <= kChannelTolerance &&
           std::abs(actual.blue() - expected.blue()) <= kChannelTolerance;
}

bool activateWindow(QQuickWindow *window)
{
    QWindow *host = window;
    while (host->parent())
        host = host->parent();
    host->raise();
    host->requestActivate();
    if (!QTest::qWaitForWindowActive(host, 5'000))
        return false;
    window->requestActivate();
    return QTest::qWaitFor([window] { return QGuiApplication::focusWindow() == window; }, 5'000);
}

bool awaitFrame(QQuickWindow *window)
{
    // Published model state may precede queued delegate updates and a render.
    QSignalSpy swapped(window, &QQuickWindow::frameSwapped);
    window->update();
    return QTest::qWaitFor([&swapped] { return !swapped.isEmpty(); }, 5'000);
}

} // namespace gridcheck

namespace {

using gridcheck::colorsNear;
using gridcheck::pixelAt;

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

bool hasFlatNeighborhood(const QImage &image, const QPoint &point, QColor *color)
{
    const QColor center = pixelAt(image, point);
    if (!center.isValid())
        return false;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (pixelAt(image, point + QPoint(x, y)).rgb() != center.rgb())
                return false;
        }
    }
    *color = center;
    return true;
}

std::optional<std::array<PixelProbe, 2>> distinctInteriorProbes(const QImage &image,
                                                                const QRect &reticle)
{
    const QRect interior = reticle.adjusted(12, 12, -12, -12);
    std::optional<PixelProbe> first = std::nullopt;
    for (int y = interior.top(); y <= interior.bottom(); y += 2) {
        for (int x = interior.left(); x <= interior.right(); x += 2) {
            QColor color;
            const QPoint point{x, y};
            if (!hasFlatNeighborhood(image, point, &color))
                continue;
            if (!first) {
                first = PixelProbe{point, color};
                continue;
            }
            const int difference = (std::max)({std::abs(color.red() - first->baseline.red()),
                                               std::abs(color.green() - first->baseline.green()),
                                               std::abs(color.blue() - first->baseline.blue())});
            if (difference >= 8)
                return std::array{*first, PixelProbe{point, color}};
        }
    }
    return std::nullopt;
}

} // namespace

namespace gridcheck {
QQuickItem *visualDescendant(QQuickItem *root, const QString &name)
{
    if (!root)
        return nullptr;
    if (root->objectName() == name)
        return root;
    for (QQuickItem *const child : root->childItems())
        if (QQuickItem *const found = visualDescendant(child, name))
            return found;
    return nullptr;
}

int visiblePrimitiveCount(QQuickItem *root, const QRectF &sceneClip)
{
    if (!root)
        return 0;
    int count = 0;
    for (QQuickItem *const child : root->childItems()) {
        if (child->isVisible() && child->property("fillColor").isValid() &&
            sceneClip.intersects(child->mapRectToScene(child->boundingRect()))) {
            ++count;
        }
        count += visiblePrimitiveCount(child, sceneClip);
    }
    return count;
}

} // namespace gridcheck

namespace {

using gridcheck::colorsNear;
using gridcheck::pixelAt;

std::optional<PixelProbe> noteFaceProbe(QQuickItem *root, const QImage &image, const QRect &reticle)
{
    if (!root)
        return std::nullopt;
    for (QQuickItem *const child : root->childItems()) {
        const QVariant fillProperty = child->property("fillColor");
        if (child->isVisible() && fillProperty.isValid()) {
            const QColor fill(fillProperty.toString());
            const QRect sceneRect =
                child->mapRectToScene(child->boundingRect()).toAlignedRect().intersected(reticle);
            const QRect interior = sceneRect.adjusted(3, 3, -3, -3);
            for (int y = interior.top(); y <= interior.bottom(); ++y) {
                for (int x = interior.left(); x <= interior.right(); ++x) {
                    QColor baseline;
                    const QPoint point{x, y};
                    if (hasFlatNeighborhood(image, point, &baseline) &&
                        colorsNear(baseline, fill)) {
                        return PixelProbe{point, baseline};
                    }
                }
            }
        }
        if (const auto probe = noteFaceProbe(child, image, reticle))
            return probe;
    }
    return std::nullopt;
}

bool nearVisibleNote(QQuickItem *root, const QPoint &scenePoint)
{
    if (!root)
        return false;
    for (QQuickItem *const child : root->childItems()) {
        if (child->isVisible() && child->property("fillColor").isValid() &&
            child->mapRectToScene(child->boundingRect())
                .adjusted(-3.0, -3.0, 3.0, 3.0)
                .contains(scenePoint)) {
            return true;
        }
        if (nearVisibleNote(child, scenePoint))
            return true;
    }
    return false;
}

std::optional<std::array<PixelProbe, 3>> outsideReticleProbes(const QImage &image,
                                                              const QRectF &plotScene,
                                                              const QRect &reticle,
                                                              QQuickItem *notes)
{
    const QRect search = plotScene.toAlignedRect().adjusted(5, 5, -5, -5);
    const QRect guardedReticle = reticle.adjusted(-6, -6, 6, 6);
    std::array<PixelProbe, 3> result;
    int count = 0;
    for (int y = search.top(); y <= search.bottom(); y += 2) {
        for (int x = search.left(); x <= search.right(); x += 2) {
            const QPoint point{x, y};
            if (guardedReticle.contains(point) || nearVisibleNote(notes, point))
                continue;
            bool separated = true;
            for (int index = 0; index < count; ++index)
                separated =
                    separated && (point - result[std::size_t(index)].point).manhattanLength() >= 40;
            QColor color;
            if (!separated || !hasFlatNeighborhood(image, point, &color))
                continue;
            result[std::size_t(count++)] = PixelProbe{point, color};
            if (count == int(result.size()))
                return result;
        }
    }
    return std::nullopt;
}

struct HorizontalEdgeScan {
    int matches = 0;
    int span = 0;
};

HorizontalEdgeScan scanHorizontalEdge(const QImage &image, const QRect &reticle, const QColor &edge)
{
    const qreal dpr = image.devicePixelRatio();
    const int left = qFloor(reticle.left() * dpr);
    const int right = qCeil(reticle.right() * dpr);
    const int top = qFloor((reticle.top() - 2.0) * dpr);
    const int bottom = qCeil((reticle.top() + 2.0) * dpr);
    HorizontalEdgeScan result;
    result.span = right - left + 1;
    for (int y = top; y <= bottom; ++y) {
        int matches = 0;
        for (int x = left; x <= right; ++x) {
            if (image.rect().contains(x, y) && colorsNear(image.pixelColor(x, y), edge))
                ++matches;
        }
        result.matches = (std::max)(result.matches, matches);
    }
    return result;
}

int matchingPixelCount(const QImage &image, const QRectF &logicalRect, const QColor &expected)
{
    const qreal dpr = image.devicePixelRatio();
    const QRect deviceRect = QRectF(logicalRect.topLeft() * dpr, logicalRect.size() * dpr)
                                 .toAlignedRect()
                                 .intersected(image.rect());
    int count = 0;
    for (int y = deviceRect.top(); y <= deviceRect.bottom(); ++y)
        for (int x = deviceRect.left(); x <= deviceRect.right(); ++x)
            count += colorsNear(image.pixelColor(x, y), expected);
    return count;
}

} // namespace

SwiftRollGatedTest::SwiftRollGatedTest(QString mode, QString projectRoot, QString songLabel)
    : m_mode(std::move(mode))
    , m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}
void SwiftRollGatedTest::init()
{
    QTest::failOnWarning(QRegularExpression(QStringLiteral("TypeError|ReferenceError")));
}

void SwiftRollGatedTest::failedReopenLeavesEmptyStripAndSurfacesError()
{
    if (m_mode != QStringLiteral("swiftqtml"))
        QSKIP("failed open error surface belongs to swiftqtml");

    RewriteWindow window;
    window.show();
    window.openStartup(m_projectRoot, m_songLabel);

    QObject *const session = window.sessionObject();
    QVERIFY(session != nullptr);
    QTRY_VERIFY_WITH_TIMEOUT(session->property("projectOpen").toBool() &&
                                 session->property("songOpen").toBool(),
                             15'000);
    QTRY_VERIFY_WITH_TIMEOUT(window.gridView() != nullptr && window.gridView()->isExposed() &&
                                 window.gridView()->rootObject() != nullptr,
                             5'000);

    QObject *const controller = session->property("songTabs").value<QObject *>();
    QVERIFY(controller != nullptr);
    QQuickView *const view = window.gridView();
    QQuickItem *const root = qobject_cast<QQuickItem *>(view->rootObject());
    QVERIFY(root != nullptr);
    QObject *const grid = root->property("gridModel").value<QObject *>();
    QVERIFY(grid != nullptr);
    const QString baselineSummary = grid->property("noteSummary").toString();
    QVERIFY(!baselineSummary.isEmpty());
    QVERIFY(window.centralWidget() != nullptr);
    const int tabId = controller->property("selectedId").toInt();
    QVERIFY(tabId >= 0);

    // Model a user-reachable filesystem failure: the previously valid song file
    // is externally removed after a successful open, then the user reopens the
    // same known song through the existing public openSong operation.
    const QString songPath =
        m_projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(m_songLabel);
    const QString backupPath = songPath + QStringLiteral(".testbak");
    QFile::remove(backupPath);
    QVERIFY2(QFile::exists(songPath), qPrintable(songPath));
    QVERIFY2(QFile::rename(songPath, backupPath), qPrintable(songPath));
    auto restoreGuard = qScopeGuard([&] {
        if (QFile::exists(backupPath) && !QFile::exists(songPath))
            QFile::rename(backupPath, songPath);
        else
            QFile::remove(backupPath);
    });

    QSignalSpy openFailedSpy(session, SIGNAL(openFailed(QString)));
    QVERIFY(openFailedSpy.isValid());

    int errorDialogCount = 0;
    auto *const dismissTimer = new QTimer(&window);
    dismissTimer->setInterval(10);
    connect(dismissTimer, &QTimer::timeout, &window, [&errorDialogCount] {
        QWidget *const modal = QApplication::activeModalWidget();
        if (modal && modal->inherits("QMessageBox")) {
            ++errorDialogCount;
            modal->close();
        }
    });
    dismissTimer->start();

    QVERIFY(QMetaObject::invokeMethod(session, "openSong", Q_ARG(QString, m_songLabel)));

    QTRY_COMPARE_WITH_TIMEOUT(openFailedSpy.size(), 1, 5'000);
    QTRY_COMPARE_WITH_TIMEOUT(errorDialogCount, 1, 5'000);

    dismissTimer->stop();
    QVERIFY2(QFile::rename(backupPath, songPath), qPrintable(backupPath));
    QCoreApplication::processEvents();

    // Tab semantics own the reopen: re-opening the selected song is the in-place
    // reload path, so the tab closed first — cleanly, with no gate — and the
    // failed load then installed nothing. The strip is empty, the mounted view
    // survives its empty strip, and the failure reached the session and the
    // window rather than leaving a half-open tab behind.
    QTRY_COMPARE_WITH_TIMEOUT(controller->property("tabCount").toInt(), 0, 5'000);
    QCOMPARE(controller->property("pendingCloseId").toInt(), -1);
    QCOMPARE(controller->property("selectedId").toInt(), -1);
    QVERIFY(!session->property("songOpen").toBool());
    QVERIFY(!session->property("lastSaveError").toString().isEmpty());
    QVERIFY(view == window.gridView());
    QVERIFY(view->isExposed());
    QVERIFY(view->rootObject() != nullptr);
    QVERIFY(window.centralWidget() != nullptr);
    QVERIFY(root->property("gridModel").value<QObject *>() == nullptr);
    QVERIFY(gridcheck::visualDescendant(root, QStringLiteral("songTab_%1").arg(tabId)) == nullptr);

    // The failed load left no broken state behind: the restored song opens again
    // in the same view with its original content.
    QVERIFY(QMetaObject::invokeMethod(session, "openSong", Q_ARG(QString, m_songLabel)));
    QTRY_COMPARE_WITH_TIMEOUT(controller->property("tabCount").toInt(), 1, 15'000);
    QVERIFY(session->property("songOpen").toBool());
    QQuickItem *const reopenedRoot = qobject_cast<QQuickItem *>(view->rootObject());
    QVERIFY(reopenedRoot != nullptr);
    QObject *const reopenedGrid = reopenedRoot->property("gridModel").value<QObject *>();
    QVERIFY(reopenedGrid != nullptr);
    QTRY_VERIFY_WITH_TIMEOUT(reopenedGrid->property("renderedNoteCount").toInt() > 0, 5'000);
    QCOMPARE(reopenedGrid->property("noteSummary").toString(), baselineSummary);
}

void SwiftRollGatedTest::selectionReticleRasterTranslucency()
{
    using gridcheck::visiblePrimitiveCount;
    using gridcheck::visualDescendant;

    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("selection reticle raster belongs to the swiftrollgated surface");

    gridcheck::NativeScene scene;
    QString openError;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &openError), qPrintable(openError));
    QQuickView *const view = scene.view;
    QQuickItem *const root = scene.root;
    QObject *const grid = scene.grid;
    QTRY_VERIFY_WITH_TIMEOUT(grid->property("renderedNoteCount").toInt() > 0, 5'000);
    QVERIFY(gridcheck::awaitFrame(view));

    QQuickItem *const plot = visualDescendant(root, QStringLiteral("timelineQuickRollPlot"));
    QQuickItem *const input = visualDescendant(root, QStringLiteral("swiftRollInput"));
    QQuickItem *const notes = visualDescendant(root, QStringLiteral("timelineQuickPianoNoteFills"));
    QQuickItem *const overlay = visualDescendant(root, QStringLiteral("timelineQuickPianoOverlay"));
    QVERIFY(plot != nullptr);
    QVERIFY(input != nullptr);
    QVERIFY(notes != nullptr);
    QVERIFY(overlay != nullptr);

    const QRectF plotScene = plot->mapRectToScene(plot->boundingRect());
    QTRY_VERIFY_WITH_TIMEOUT(visiblePrimitiveCount(notes, plotScene) > 0, 5'000);

    const QPoint start =
        plot->mapToScene(QPointF(plot->width() * 0.15, plot->height() * 0.20)).toPoint();
    const QPoint finish =
        plot->mapToScene(QPointF(plot->width() * 0.85, plot->height() * 0.80)).toPoint();
    const QRect reticle = QRect(start, finish).normalized();
    QVERIFY(reticle.width() > 80);
    QVERIFY(reticle.height() > 80);
    QVERIFY(input->mapRectToScene(input->boundingRect()).contains(reticle));

    QVERIFY(gridcheck::awaitFrame(view));
    const QImage baseline = view->grabWindow();
    QVERIFY(!baseline.isNull());
    const auto probes = distinctInteriorProbes(baseline, reticle);
    QVERIFY2(probes.has_value(),
             "the visible roll did not provide two distinct flat pixels under the reticle");
    const auto noteProbe = noteFaceProbe(notes, baseline, reticle);
    QVERIFY2(noteProbe.has_value(), "no visible note face was covered by the reticle");
    const auto outsideProbes = outsideReticleProbes(baseline, plotScene, reticle, notes);
    QVERIFY2(outsideProbes.has_value(),
             "the visible roll did not provide three untouched flat pixels outside the reticle");

    QTest::mouseMove(view, start);
    QTest::mousePress(view, Qt::RightButton, Qt::NoModifier, start);
    const auto releaseMouse =
        qScopeGuard([&] { QTest::mouseRelease(view, Qt::RightButton, Qt::NoModifier, finish); });
    QTest::mouseMove(view, finish, 20);
    QTRY_VERIFY_WITH_TIMEOUT(visiblePrimitiveCount(overlay, QRectF(reticle)) >= 5, 5'000);

    QVERIFY(gridcheck::awaitFrame(view));
    const QImage during = view->grabWindow();
    QVERIFY(!during.isNull());
    QCOMPARE(during.size(), baseline.size());
    QCOMPARE(during.devicePixelRatio(), baseline.devicePixelRatio());

    for (const PixelProbe &probe : *outsideProbes) {
        const QColor actualOutside = pixelAt(during, probe.point);
        const QString failure =
            QStringLiteral("selection fill escaped its reticle at untouched pixel (%1,%2): "
                           "before %3, during %4")
                .arg(probe.point.x())
                .arg(probe.point.y())
                .arg(probe.baseline.name(QColor::HexArgb))
                .arg(actualOutside.name(QColor::HexArgb));
        QVERIFY2(colorsNear(actualOutside, probe.baseline), qPrintable(failure));
    }

    QColor selectionFill = themes::color(themes::Role::song_view_selection_fill);
    selectionFill.setAlpha(kSelectionFillAlpha);
    std::array<QColor, 2> actual;
    for (std::size_t index = 0; index < probes->size(); ++index) {
        const PixelProbe &probe = probes->at(index);
        const QColor expected = sourceOver(selectionFill, probe.baseline);
        actual[index] = pixelAt(during, probe.point);
        const QString failure =
            QStringLiteral("selection fill at (%1,%2): baseline %3, expected %4, actual %5")
                .arg(probe.point.x())
                .arg(probe.point.y())
                .arg(probe.baseline.name(QColor::HexArgb))
                .arg(expected.name(QColor::HexArgb))
                .arg(actual[index].name(QColor::HexArgb));
        QVERIFY2(colorsNear(actual[index], expected), qPrintable(failure));
    }
    QVERIFY2(actual[0].rgb() != actual[1].rgb(),
             "the reticle erased contrast between distinct underlying pixels");

    const QColor expectedNote = sourceOver(selectionFill, noteProbe->baseline);
    const QColor actualNote = pixelAt(during, noteProbe->point);
    const QString noteFailure =
        QStringLiteral("note face under selection fill: baseline %1, expected %2, actual %3")
            .arg(noteProbe->baseline.name(QColor::HexArgb))
            .arg(expectedNote.name(QColor::HexArgb))
            .arg(actualNote.name(QColor::HexArgb));
    QVERIFY2(colorsNear(actualNote, expectedNote), qPrintable(noteFailure));

    const QColor edge = themes::color(themes::Role::song_view_selection_edge);
    const QRectF leftEdge(reticle.left() - 2.0, reticle.top(), 4.0, reticle.height());
    const HorizontalEdgeScan topEdge = scanHorizontalEdge(during, reticle, edge);
    QVERIFY2(topEdge.matches >= 4, "the reticle's horizontal dashed edge was not visible");
    QVERIFY2(topEdge.matches <= topEdge.span * 3 / 4,
             "the reticle's horizontal edge rendered solid instead of dashed");
    QVERIFY2(matchingPixelCount(during, leftEdge, edge) >= 4,
             "the reticle's vertical dashed edge was not visible");
}

int runSwiftGridBoundaryCheck(const QString &mode, const QString &projectRoot,
                              const QString &songLabel, const QStringList &qtArguments)
{
    SwiftRollGatedTest test(mode, projectRoot, songLabel);
    QStringList arguments = {QStringLiteral("swift-grid-boundary")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
