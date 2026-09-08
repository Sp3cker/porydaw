#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QEnterEvent>
#include <QImage>
#include <QQuickItem>
#include <QScopeGuard>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

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
    const EditorViewState originalState = view.editorViewState();
    const int originalScroll = page->verticalScroll();
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
        if (view.editorViewState() != originalState)
            view.applyEditorViewState(originalState);
        if (page->verticalScroll() != originalScroll)
            page->setVerticalScroll(originalScroll);
        checks::support::pumpQuick();
    });

    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange,
                                     static_cast<uint8_t>(track), CoreTimeDefaults::kCcModulation};
    const auto findLane = [&] {
        const auto &rows = canvas->rows();
        for (int index = 0; index < int(rows.size()); ++index) {
            if (rows[std::size_t(index)].id == lane)
                return LaneHandle{index + 1};
        }
        return LaneHandle{};
    };
    LaneHandle handle = findLane();
    if (!handle.valid()) {
        EditorViewState fixture = view.editorViewState();
        fixture.emptyLanes.insert(lane);
        fixture.unhideLane(lane);
        view.applyEditorViewState(fixture);
        checks::support::pumpQuick();
        handle = findLane();
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
    page->setVerticalScroll((std::clamp)(body.center().y() - inputSize.height() / 2, 0,
                                         page->automationContentHeight()));
    checks::support::pumpQuick();

    const int scroll = page->verticalScroll();
    const QRect liveBody = canvas->laneBody(handle);
    const QRect inputBounds{QPoint{}, inputSize};
    const QRect visible = liveBody.translated(0, -scroll).intersected(inputBounds);
    const QRect interior =
        liveBody.adjusted(0, layout::singlePixel() + 1, 0, -layout::singlePixel())
            .translated(0, -scroll)
            .intersected(inputBounds);
    const QRect tempo = canvas->pinnedTempoRect().translated(0, -scroll).intersected(inputBounds);
    QVERIFY(!visible.isEmpty());
    QVERIFY(!interior.isEmpty());
    const int x = (std::clamp)(inputSize.width() * 2 / 3, interior.left(), interior.right());
    QRect probe{x, interior.top(), 1, interior.height()};
    if (tempo.intersects(probe)) {
        QRect above = probe;
        above.setBottom(tempo.top() - 1);
        QRect below = probe;
        below.setTop(tempo.bottom() + 1);
        probe = above.isEmpty() || (!below.isEmpty() && below.height() > above.height()) ? below
                                                                                         : above;
    }
    QVERIFY(!probe.isEmpty());
    const QPoint point{x, probe.center().y()};
    QVERIFY(inputBounds.contains(point));
    QVERIFY(liveBody.contains(point + QPoint{0, scroll}));
    QVERIFY(!tempo.contains(point));
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
