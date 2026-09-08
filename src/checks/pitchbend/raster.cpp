#include "checks/pitchbend/tst_pitchbendediting.h"

#include <QCoreApplication>
#include <QImage>
#include <QtMath>
#include <QtTest>

#include "ui/theme/themeruntime.h"

#include "checks/support/eventsynth.h"

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

QPoint noteEdgePoint(const PitchBendFixture &fixture)
{
    const qreal dpr = fixture.rollInput().devicePixelRatio();
    return QPoint(qRound(fixture.view().camera().displayX(double(fixture.note().tick), 0.0, dpr)),
                  fixture.notePoint().y());
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
    QVERIFY(editor && editor->view());
    const QImage image = editor->view()->grabWindow();
    QVERIFY(!image.isNull());
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x)
            QCOMPARE(image.pixelColor(x, y).alpha(), 255);
    }
    const QColor background = themes::color(themes::Role::window_background);
    QCOMPARE(image.pixelColor(qRound(4 * image.devicePixelRatio()),
                              qRound(24 * image.devicePixelRatio())),
             background);
    QCOMPARE(image.pixelColor(qRound(4 * image.devicePixelRatio()),
                              qRound(80 * image.devicePixelRatio())),
             background);
    QCOMPARE(image.pixelColor(qRound(4 * image.devicePixelRatio()),
                              image.height() - qRound(4 * image.devicePixelRatio())),
             background);
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
    const QImage image = editor->view()->grabWindow();
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
    const QImage image = editor->view()->grabWindow();
    QVERIFY(!image.isNull());
    QVERIFY(coloredHits(image, *graph, start, finish) >= 4);
}

void PitchBendRasterTest::noteEdgeCursorPixmapAndArrowRestore()
{
    const QPoint edge = noteEdgePoint(m_fixture);
    const QPoint empty(1, edge.y());
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, edge, Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QTRY_VERIFY(!m_fixture.rollInput().cursor().pixmap().isNull());
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, empty, Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QCOMPARE(m_fixture.rollInput().cursor().shape(), Qt::ArrowCursor);
    QVERIFY(m_fixture.openPopup());
    m_fixture.closePopupViaEscape();
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, edge, Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QTRY_VERIFY(!m_fixture.rollInput().cursor().pixmap().isNull());
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, empty, Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QCOMPARE(m_fixture.rollInput().cursor().shape(), Qt::ArrowCursor);
}

void PitchBendRasterTest::guideDensityIndependentOfEditingSelection()
{
    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);
    int quarterGuides = 0;
    int sixteenthGuides = 0;
    int clockGuides = 0;
    const auto countVerticalGuides = [&](int &runs) {
        songview::PitchBendEditor *editor = m_fixture.openPopup();
        QVERIFY(editor && editor->view());
        songview::PitchBendGraph *graph = m_fixture.graph(QStringLiteral("pitchBendGraph"));
        QVERIFY(graph);
        QCoreApplication::processEvents();
        const QImage image = editor->view()->grabWindow();
        QVERIFY(!image.isNull());
        const qreal dpr = image.devicePixelRatio();
        const QRect canvas = graph->canvasRect();
        const QPoint topLeft = graph->mapToScene(canvas.topLeft()).toPoint();
        const int pixelY = qRound((topLeft.y() + canvas.height() * 0.25) * dpr);
        const int edgeInset = qCeil(2.0 * dpr);
        const int firstPixel = qRound(topLeft.x() * dpr) + edgeInset;
        const int lastPixel =
            qRound(graph->mapToScene(canvas.bottomRight()).toPoint().x() * dpr) - edgeInset;
        runs = 0;
        bool inRun = false;
        for (int x = firstPixel; x <= lastPixel; ++x) {
            // The translucent theme grid is composited into an opaque native
            // framebuffer. At this clear scanline, every non-background run
            // is a rendered vertical guide; comparing against the unblended
            // theme grid color would only work on an uncomposited surface.
            const bool guide = image.pixelColor(x, pixelY) != background;
            if (guide && !inRun)
                ++runs;
            inRun = guide;
        }
        m_fixture.closePopupViaEscape();
    };

    // Popup guides are a display query driven by the popup pixel scale; the
    // editing selection must never change their density. Counting rendered
    // guide runs along a curve-free scanline must give the same nonzero guide
    // count for a quarter, a sixteenth, and the Clock floor.
    m_fixture.view().setGridSelection(songview::GridSelection::musical(4));
    countVerticalGuides(quarterGuides);
    m_fixture.view().setGridSelection(songview::GridSelection::musical(16));
    countVerticalGuides(sixteenthGuides);
    m_fixture.view().setGridSelection(songview::GridSelection::clock());
    countVerticalGuides(clockGuides);
    QVERIFY(quarterGuides > 0);
    QCOMPARE(sixteenthGuides, quarterGuides);
    QCOMPARE(clockGuides, quarterGuides);
}

int runPitchBendRasterCheck(const QStringList &qtArguments)
{
    PitchBendRasterTest test;
    QStringList arguments{QStringLiteral("pitch-bend-raster")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
