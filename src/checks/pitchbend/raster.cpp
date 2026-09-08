#include "checks/pitchbend/tst_pitchbendediting.h"

#include <QCoreApplication>
#include <QtTest>

#include "ui/theme/themeruntime.h"

namespace {
QPoint canvasPoint(const songview::PitchBendGraph &graph, qreal xFraction, qreal yFraction)
{
    const QRect canvas = graph.canvasRect();
    return QPoint(qRound(canvas.left() + canvas.width() * xFraction),
                  qRound(canvas.top() + canvas.height() * yFraction));
}

QColor scenePixel(const QImage &image, QPoint scenePoint)
{
    const qreal dpr = image.devicePixelRatio();
    const QPoint pixel(qRound(scenePoint.x() * dpr), qRound(scenePoint.y() * dpr));
    return image.pixelColor(pixel);
}

int coloredHits(const QImage &image, const songview::PitchBendGraph &graph, QPoint start,
                QPoint finish)
{
    int hits = 0;
    const QColor background =
        scenePixel(image, graph.mapToScene(graph.canvasRect().topLeft()).toPoint());
    for (int i = 0; i < 7; ++i) {
        const qreal fraction = qreal(i + 1) / 8.0;
        const QPoint graphPoint = start + (finish - start) * fraction;
        const QColor pixel = scenePixel(image, graph.mapToScene(graphPoint).toPoint());
        if (pixel != background && pixel.alpha() == 255)
            ++hits;
    }
    return hits;
}

} // namespace

void PitchBendRasterTest::init()
{
    QVERIFY(m_fixture.setUp());
}

void PitchBendRasterTest::cleanup()
{
    m_fixture.tearDown();
}

void PitchBendRasterTest::popupSurfaceIsOpaqueAndUsesWindowBackground()
{
    songview::PitchBendEditor *editor = m_fixture.openPopup();
    QVERIFY(editor);
    QQuickItem *content = m_fixture.formContent();
    QVERIFY(content);
    const QImage image = m_fixture.timelineWindow().grabWindow();
    QVERIFY(!image.isNull());
    // Crop the shared canvas grab to the popup form before asserting opacity.
    const QPointF contentScene = content->mapToScene(QPointF(0, 0));
    const qreal dpr = image.devicePixelRatio();
    const QRect surfaceRect((contentScene * dpr).toPoint(),
                            QSize(qRound(content->width() * dpr), qRound(content->height() * dpr)));
    const QImage surface = image.copy(surfaceRect.intersected(image.rect()));
    QVERIFY(!surface.isNull());
    for (int y = 0; y < surface.height(); ++y) {
        for (int x = 0; x < surface.width(); ++x)
            QCOMPARE(surface.pixelColor(x, y).alpha(), 255);
    }
    const QColor background = themes::color(themes::Role::window_background);
    QCOMPARE(surface.pixelColor(qRound(4 * dpr), qRound(24 * dpr)), background);
    QCOMPARE(surface.pixelColor(qRound(4 * dpr), qRound(80 * dpr)), background);
    QCOMPARE(surface.pixelColor(qRound(4 * dpr), surface.height() - qRound(4 * dpr)), background);
}

void PitchBendRasterTest::shiftCurvePaintsDiagonal()
{
    QPointer<songview::PitchBendEditor> editor = m_fixture.openPopup();
    QVERIFY(editor);
    QPointer<songview::PitchBendGraph> graph = m_fixture.graph(QStringLiteral("pitchBendGraph"));
    QVERIFY(graph);
    const QPoint start = canvasPoint(*graph, 0.15, 0.80);
    const QPoint finish = canvasPoint(*graph, 0.85, 0.20);
    QVERIFY(m_fixture.stroke(*graph, start, finish, Qt::ShiftModifier));
    QCoreApplication::processEvents();
    if (!editor || !editor->isOpen()) {
        QFAIL("pitch-bend popup was dismissed while rendering its Shift line");
        return;
    }
    const QImage image = m_fixture.timelineWindow().grabWindow();
    QVERIFY(!image.isNull());
    QVERIFY(coloredHits(image, *graph, start, finish) >= 4);
}

void PitchBendRasterTest::altRampPaintsDiagonalAfterReopen()
{
    songview::PitchBendEditor *editor = m_fixture.openPopup();
    QVERIFY(editor);
    songview::PitchBendGraph *graph = m_fixture.graph(QStringLiteral("pitchBendGraph"));
    QVERIFY(graph);
    const QPoint start = canvasPoint(*graph, 0.10, 0.85);
    const QPoint finish = canvasPoint(*graph, 0.90, 0.15);
    QVERIFY(m_fixture.stroke(*graph, start, finish, Qt::AltModifier));
    m_fixture.closePopupViaEscape();
    editor = m_fixture.openPopup();
    QVERIFY(editor);
    graph = m_fixture.graph(QStringLiteral("pitchBendGraph"));
    QVERIFY(graph);
    const QImage image = m_fixture.timelineWindow().grabWindow();
    QVERIFY(!image.isNull());
    QVERIFY(coloredHits(image, *graph, start, finish) >= 4);
}

int runPitchBendRasterCheck(const QStringList &qtArguments)
{
    PitchBendRasterTest test;
    QStringList arguments{QStringLiteral("pitch-bend-raster")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
