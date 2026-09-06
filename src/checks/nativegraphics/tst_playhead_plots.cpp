#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QCoreApplication>
#include <QEvent>
#include <QQuickItem>

#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
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
        checks::nativegraphics::makeRig(projectRoot, songLabel, QSize{1280, 800}, true, error);
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
    auto *drawer = view.editorDrawer();
    QVERIFY(quick && quick->rootObject() && quick->quickWindow());
    QVERIFY(drawer);
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
    const auto canonicalQuickRect = [quick](const QRect &rect) {
        return QRectF(rect.translated(-quick->geometry().topLeft()));
    };
    QVERIFY(rollBand->isVisible());
    QVERIFY(rollInput->isVisible());
    QVERIFY(sameRect(quickRect(*rollBand), canonicalQuickRect(roll->rect)));
    QVERIFY(sameRect(quickRect(*rollInput), canonicalQuickRect(roll->plotRect)));
    const QSize originalSize = view.size();
    view.resize(originalSize.width(),
                originalSize.height() - 4 * layout::space(layout::Space::One));
    checks::support::pumpQuick();
    const std::optional<songview::TimelineBandGeometry> &resizedRoll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(resizedRoll);
    const QRect resizedHost =
        checks::support::canonicalVisibleQuickHostRect(view, &drawer->chrome());
    QCOMPARE(quick->geometry(), resizedHost);
    QVERIFY(sameRect(quickRect(*rollBand),
                     QRectF(resizedRoll->rect.translated(-resizedHost.topLeft()))));
    QVERIFY(sameRect(quickRect(*rollInput),
                     QRectF(resizedRoll->plotRect.translated(-resizedHost.topLeft()))));
    view.resize(originalSize);
    checks::support::pumpQuick();

    QEvent winIdChange{QEvent::WinIdChange};
    QCoreApplication::sendEvent(&view, &winIdChange);
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
    QEvent densityChange{QEvent::DevicePixelRatioChange};
#else
    QEvent densityChange{QEvent::ScreenChangeInternal};
#endif
    QCoreApplication::sendEvent(&view, &densityChange);
    view.hide();
    checks::support::pumpQuick();
    view.show();
    QTRY_VERIFY(view.windowHandle() && view.windowHandle()->isExposed());
    checks::support::pumpQuick();

    QVERIFY(view.timelineBandLayout() == canonical);
    const QRect expectedHost =
        checks::support::canonicalVisibleQuickHostRect(view, &drawer->chrome());
    QCOMPARE(quick->geometry(), expectedHost);
    const std::optional<songview::TimelineBandGeometry> &liveRoll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(liveRoll);
    const QRectF expectedRoll = QRectF(liveRoll->rect.translated(-expectedHost.topLeft()));
    const QRectF expectedPlot = QRectF(liveRoll->plotRect.translated(-expectedHost.topLeft()));
    QCOMPARE(root->property("rollBandVisible").toBool(), true);
    QVERIFY(sameRect(root->property("rollBandRect").toRectF(), expectedRoll));
    QVERIFY(sameRect(root->property("rollBandPlotRect").toRectF(), expectedPlot));
    QVERIFY(quick->quickWindow()->mask().isEmpty());
    QVERIFY(sameRect(quickRect(*rollBand), expectedRoll));
    QVERIFY(sameRect(quickRect(*rollInput), expectedPlot));
}
