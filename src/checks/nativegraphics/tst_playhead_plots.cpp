#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QCoreApplication>
#include <QEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSizeF>

#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

namespace {

std::unique_ptr<checks::nativegraphics::Rig> plotRig(const QString &projectRoot,
                                                     const QString &songLabel)
{
    QString error;
    std::unique_ptr<checks::nativegraphics::Rig> rig =
        checks::nativegraphics::makeRig(projectRoot, songLabel, QSize{1280, 800}, error);
    if (!rig)
        QTest::qFail(qPrintable(error), __FILE__, __LINE__);
    return rig;
}

bool sameRect(const QRectF &actual, const QRectF &expected)
{
    return qAbs(actual.left() - expected.left()) <= 0.2 &&
           qAbs(actual.top() - expected.top()) <= 0.2 &&
           qAbs(actual.width() - expected.width()) <= 0.2 &&
           qAbs(actual.height() - expected.height()) <= 0.2;
}

} // namespace

void RenderingPlayheadTest::plotGeometryAndLifecycle()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = plotRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *quick = view.quickView();
    QVERIFY(quick && quick->rootObject() && quick->quickWindow());
    QQuickItem *root = quick->rootObject();
    auto *rollInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    QQuickItem *rollBand =
        rollInput && rollInput->parentItem() ? rollInput->parentItem()->parentItem() : nullptr;
    QVERIFY(rollBand);

    const songview::TimelineBandLayout canonical = view.timelineBandLayout();
    const std::optional<songview::TimelineBandGeometry> &roll =
        canonical.geometry(songview::TimelineBand::Roll);
    QVERIFY(roll);
    const auto quickRect = [quick, root](const QQuickItem &item) {
        return QRectF(item.mapToItem(root, QPointF{}), item.size());
    };
    // Canonical band rects are already Quick-window-local; no host offset
    // translation remains.
    const auto canonicalQuickRect = [](const QRect &rect) { return QRectF(rect); };
    QVERIFY(rollBand->isVisible());
    QVERIFY(rollInput->isVisible());
    QVERIFY(sameRect(quickRect(*rollBand), canonicalQuickRect(roll->rect)));
    QVERIFY(sameRect(quickRect(*rollInput), canonicalQuickRect(roll->plotRect)));
    QQuickWindow *window = quick->quickWindow();
    QVERIFY(window);
    const QSize originalSize = window->size();
    const QSize shrunkSize(originalSize.width(),
                           originalSize.height() - 4 * layout::space(layout::Space::One));
    window->resize(shrunkSize);
    checks::support::pumpQuick();
    QCOMPARE(window->size(), shrunkSize);
    const std::optional<songview::TimelineBandGeometry> &resizedRoll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(resizedRoll);
    QVERIFY(sameRect(quickRect(*rollBand), QRectF(resizedRoll->rect)));
    QVERIFY(sameRect(quickRect(*rollInput), QRectF(resizedRoll->plotRect)));
    window->resize(originalSize);
    checks::support::pumpQuick();

    // The composed canvas can resize while its shared Quick window remains
    // fixed. Canonical bands and live items must follow that page viewport,
    // not the unchanged outer surface.
    const QSizeF originalCanvasSize = root->size();
    const QSizeF viewportOnlySize{originalCanvasSize.width() - 37.0,
                                  originalCanvasSize.height() - 29.0};
    root->setSize(viewportOnlySize);
    checks::support::pumpQuick();
    QCOMPARE(window->size(), originalSize);
    QCOMPARE(root->size(), viewportOnlySize);
    const std::optional<songview::TimelineBandGeometry> &viewportOnlyRoll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(viewportOnlyRoll);
    QVERIFY(sameRect(quickRect(*rollBand), QRectF(viewportOnlyRoll->rect)));
    QVERIFY(sameRect(quickRect(*rollInput), QRectF(viewportOnlyRoll->plotRect)));
    root->setSize(originalCanvasSize);
    checks::support::pumpQuick();
    QCOMPARE(root->size(), originalCanvasSize);

    QEvent densityChange{QEvent::DevicePixelRatioChange};
    QCoreApplication::sendEvent(window, &densityChange);
    checks::support::pumpQuick();

    QVERIFY(view.timelineBandLayout() == canonical);
    const std::optional<songview::TimelineBandGeometry> &liveRoll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(liveRoll);
    const QRectF expectedRoll = QRectF(liveRoll->rect);
    const QRectF expectedPlot = QRectF(liveRoll->plotRect);
    QCOMPARE(root->property("rollBandVisible").toBool(), true);
    QVERIFY(sameRect(root->property("rollBandRect").toRectF(), expectedRoll));
    QVERIFY(sameRect(root->property("rollBandPlotRect").toRectF(), expectedPlot));
    QVERIFY(quick->quickWindow()->mask().isEmpty());
    QVERIFY(sameRect(quickRect(*rollBand), expectedRoll));
    QVERIFY(sameRect(quickRect(*rollInput), expectedPlot));
}
