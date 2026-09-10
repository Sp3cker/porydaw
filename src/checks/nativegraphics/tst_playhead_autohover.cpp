#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QEnterEvent>
#include <QImage>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScopeGuard>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

// The catalog position comes from the production mapping only; clicking the
// real selector label is the same activation path a user takes.
bool activateAutomationParameter(SongView &view, AutomationCanvas &canvas,
                                 const EditorAutomationRowId &row)
{
    const int index = checks::support::automationParameterIndex(canvas, row);
    if (index < 0)
        return false;
    songview::TimelineQuickView *const quick = view.quickView();
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    if (!root)
        return false;
    QQuickItem *label = nullptr;
    if (!QTest::qWaitFor([&root, &label, index] {
            label = checks::support::visualDescendant(
                root, QStringLiteral("automationParameterTab%1").arg(index));
            return label && label->isVisible() && label->isEnabled() && label->width() > 0.0 &&
                   label->height() > 0.0 && label->window();
        }))
        return false;
    QQuickWindow *const window = label->window();
    QQuickItem *const content = window ? window->contentItem() : nullptr;
    if (!content)
        return false;
    const QPointF point = content->mapFromScene(
        label->mapToScene(QPointF(label->width() / 2.0, label->height() / 2.0)));
    if (!content->boundingRect().contains(point))
        return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    return QTest::qWaitFor([&canvas, index] { return canvas.activeParameter() == index; });
}

} // namespace

void RenderingPlayheadTest::automationHoverDecor()
{
    QString error;
    std::unique_ptr<checks::nativegraphics::Rig> rig =
        checks::nativegraphics::makeRig(m_projectRoot, m_songLabel, QSize{1280, 800}, error);
    QVERIFY2(rig, qPrintable(error));
    SongView &view = rig->song->view();
    auto *page = view.editorDrawer() ? view.editorDrawer()->automationPage() : nullptr;
    auto *canvas = page ? page->canvas() : nullptr;
    auto *quick = view.quickView();
    QVERIFY(page);
    QVERIFY(canvas);
    QVERIFY(quick && quick->rootObject() && quick->quickWindow());
    auto *window = quick->quickWindow();

    const int track = view.selectionModel().primaryTrack();
    QVERIFY(track >= 0 && track < 16);
    const bool originalPencil = canvas->pencilMode();
    songview::TimelineInputItem *input =
        quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationInput"));
    QVERIFY(input);
    QPoint nativeLeavePoint;
    const auto restore = qScopeGuard([&] {
        QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, nativeLeavePoint);
        if (canvas->pencilMode() != originalPencil)
            canvas->setPencilMode(originalPencil);
        checks::support::pumpQuick();
    });

    // Real activation on the shared plot: the CC1 Modulation selector label
    // replaces the old add-empty-lane setup, and the active slot's full-height
    // body replaces the pinned Tempo header. The plot has no vertical
    // automation scroll, so content and input coordinates already agree.
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange,
                                     static_cast<uint8_t>(track), CoreTimeDefaults::kCcModulation};
    QVERIFY2(activateAutomationParameter(view, *canvas, lane),
             "the modulation parameter label did not activate");
    checks::support::pumpQuick();

    LaneHandle handle;
    const auto &rows = canvas->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == lane)
            handle = LaneHandle{index + 1};
    }
    QVERIFY(handle.valid());
    QVERIFY(input->interaction());
    QVERIFY(input->window());

    const QRect body = canvas->laneBody(handle);
    QVERIFY(!body.isEmpty());
    const std::optional<songview::TimelineBandGeometry> &band =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band && band->rect.isValid());
    const QSize inputSize{qFloor(input->width()), qFloor(input->height())};
    QVERIFY(inputSize.width() > 0 && inputSize.height() > 0);
    const QRect inputBounds{QPoint{}, inputSize};
    const QRect interior = body.adjusted(0, layout::singlePixel() + 1, 0, -layout::singlePixel())
                               .intersected(inputBounds);
    QVERIFY(!interior.isEmpty());
    const int x = (std::clamp)(inputSize.width() * 2 / 3, interior.left(), interior.right());
    const QPoint point{x, interior.center().y()};
    QVERIFY(inputBounds.contains(point));
    QVERIFY(body.contains(point));
    const QPoint nativeHoverPoint = input->mapToScene(QPointF(point)).toPoint();
    nativeLeavePoint = input->mapToScene(QPointF{-1.0, -1.0}).toPoint();
    const QRect windowBounds{QPoint{}, window->size()};
    QVERIFY(windowBounds.contains(nativeHoverPoint));
    QVERIFY(windowBounds.contains(nativeLeavePoint));
    QVERIFY(!input->contains(input->mapFromScene(QPointF(nativeLeavePoint))));

    canvas->cancelInteraction();
    canvas->setPencilMode(true);
    // QTest's window mouse delivery does not synthesize the platform Enter
    // event that enables Quick's hover dispatch.
    QEnterEvent enter(QPointF(nativeLeavePoint), QPointF(nativeLeavePoint),
                      window->mapToGlobal(QPointF(nativeLeavePoint)));
    QCoreApplication::sendEvent(window, &enter);
    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, nativeLeavePoint);
    checks::support::pumpQuick();
    QString captureError;
    const QImage baseline = checks::support::captureQuickBand(view, band->rect, &captureError);
    QVERIFY2(!baseline.isNull(), qPrintable(captureError));

    // The first move into a fresh surface may deliver only HoverEnter.
    // Move within the surface before the target so this exercises HoverMove.
    QVERIFY2(checks::events::primeMouseMove(*window, *input, nativeHoverPoint),
             "the automation surface has no interior mouse-move staging point");
    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, nativeHoverPoint);
    checks::support::pumpQuick();
    const QImage hovered = checks::support::captureQuickBand(view, band->rect, &captureError);
    QVERIFY2(!hovered.isNull(), qPrintable(captureError));
    QVERIFY(hovered != baseline);

    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, nativeLeavePoint);
    checks::support::pumpQuick();
    const QImage cleared = checks::support::captureQuickBand(view, band->rect, &captureError);
    QVERIFY2(!cleared.isNull(), qPrintable(captureError));
    QCOMPARE(cleared, baseline);
}
