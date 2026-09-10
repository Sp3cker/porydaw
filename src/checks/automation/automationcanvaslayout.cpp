// Qt Test coverage for the automation canvas' published layout and input surface.

#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <QCoreApplication>
#include <QEventLoop>
#include <QQuickItem>
#include <cmath>
#include <optional>

#include "checks/support/timelinequickcheck.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;

void pumpQuick()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
}

QRectF itemSceneRect(const songview::TimelineInputItem &item)
{
    return {item.mapToScene(QPointF{}), QSizeF(item.width(), item.height())};
}

void verifyActivePlot(SongView &view, AutomationPage &page, const QRect &body)
{
    const auto automation = view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    const auto roll = view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(automation.has_value());
    QVERIFY(roll.has_value());
    QCOMPARE(body.topLeft(), QPoint{});
    QCOMPARE(body.height(), page.automationViewportSize().height());
    QCOMPARE(body.size(), automation->plotRect.size());
    QVERIFY(checks::support::visualDescendant(view.quickView()->rootObject(),
                                              QStringLiteral("drawerAutomationScrollBar")) ==
            nullptr);
    QCOMPARE(automation->plotRect.left(), view.timelineSplitX());
    QCOMPARE(roll->plotRect.left(), view.timelineSplitX());
    for (int index = 0; index < 9; ++index) {
        QQuickItem *const label = checks::support::visualDescendant(
            view.quickView()->rootObject(), QStringLiteral("automationParameterTab%1").arg(index));
        QVERIFY(label);
        QVERIFY(QRectF(automation->gutterRect())
                    .contains(label->mapRectToScene(label->boundingRect())));
    }
}

} // namespace

void AutomationEditingTest::automationBandAndInputsExposed()
{
    SongView &view = m_tab->view();
    const std::optional<songview::TimelineBandGeometry> band =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    songview::TimelineQuickView *const quick = view.quickView();
    QObject *const root = quick ? quick->rootObject() : nullptr;
    auto *const gutter = root ? root->findChild<songview::TimelineInputItem *>(
                                    QStringLiteral("timelineAutomationGutterInput"))
                              : nullptr;
    auto *const quickScene = view.findChild<songview::TimelineQuickScene *>();

    QVERIFY(band.has_value());
    QVERIFY(!band->rect.isEmpty());
    QVERIFY(m_automationInput);
    QVERIFY(gutter);
    QVERIFY(quickScene);
    QCOMPARE(m_automationInput->window(), m_quickWindow.data());
    QCOMPARE(gutter->window(), m_quickWindow.data());
}

void AutomationEditingTest::sectionResizeKeepsLabelsClickableWithoutScrollbarStrip()
{
    SongView &view = m_tab->view();
    EditorDrawer *const drawer = view.editorDrawer();
    songview::TimelineQuickView *const quick = view.quickView();
    QVERIFY(drawer);
    QVERIFY(quick);
    QQuickItem *const root = quick->rootObject();
    QVERIFY(root);
    AutomationCanvas *const canvas = m_page->canvas();
    QTRY_VERIFY(canvas->minimumContentHeight() > 0);

    const int originalHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int splitBefore = view.timelineSplitX();
    const FrozenDocumentState frozen = frozenDocumentState();
    const uint64_t cursorBefore = view.editCursorTick();
    const int minimumHeight = canvas->minimumContentHeight();
    QVERIFY(drawer->maximumSectionHeight() > minimumHeight);

    for (const int height : {minimumHeight, drawer->maximumSectionHeight()}) {
        view.setDrawerSectionHeight(EditorDrawerPage::Automations, height);
        pumpQuick();
        QTRY_COMPARE(m_page->automationViewportSize().height(), height);
        const auto automation =
            view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
        const auto roll = view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
        QVERIFY(automation.has_value());
        QVERIFY(roll.has_value());
        QVERIFY(checks::support::visualDescendant(
                    root, QStringLiteral("drawerAutomationScrollBar")) == nullptr);
        QCOMPARE(view.timelineSplitX(), splitBefore);
        QCOMPARE(automation->plotRect.left(), splitBefore);
        QCOMPARE(roll->plotRect.left(), splitBefore);
        QCOMPARE(itemSceneRect(automationGutterInput()), QRectF(automation->gutterRect()));
        QCOMPARE(itemSceneRect(automationInput()), QRectF(automation->plotRect));

        for (int index = 0; index < 9; ++index) {
            const auto row = canvas->parameterRow(index);
            QVERIFY(row.has_value());
            QQuickItem *const label = checks::support::visualDescendant(
                root, QStringLiteral("automationParameterTab%1").arg(index));
            QVERIFY(label);
            QVERIFY(label->isVisible());
            const QRectF labelRect = label->mapRectToScene(label->boundingRect());
            QVERIFY(!labelRect.isEmpty());
            QVERIFY(QRectF(automation->gutterRect()).contains(labelRect));
            QVERIFY(activateParameter(*row));
            QCOMPARE(canvas->activeParameter(), index);
            verifyActivePlot(view, *m_page, laneBody(findRow(*row)));
            QVERIFY(frozenDocumentState() == frozen);
            QCOMPARE(view.editCursorTick(), cursorBefore);
            QCOMPARE(view.timelineSplitX(), splitBefore);
        }
    }
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, originalHeight);
    pumpQuick();
}

void AutomationEditingTest::layoutAlignsPlotGutterAndRollGrid()
{
    SongView &view = m_tab->view();
    songview::TimelineQuickView *const quick = view.quickView();
    QVERIFY(quick);
    QObject *const root = quick->rootObject();
    QVERIFY(root);
    auto *const gutter = root->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationGutterInput"));
    QVERIFY(gutter);

    const std::optional<songview::TimelineBandGeometry> automation =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    const std::optional<songview::TimelineBandGeometry> roll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(automation.has_value());
    QVERIFY(roll.has_value());
    QVERIFY(!automation->plotRect.isEmpty());
    QVERIFY(!roll->plotRect.isEmpty());

    const QRect gutterRect = automation->gutterRect();
    QQuickWindow *const quickWindow = quick->quickWindow();
    QVERIFY(quickWindow);
    QVERIFY(QRect(QPoint(0, 0), quickWindow->size()).contains(gutterRect));
    QCOMPARE(automation->plotRect.left(), view.timelineSplitX());
    QCOMPARE(roll->plotRect.left(), view.timelineSplitX());
    QVERIFY(checks::support::visualDescendant(
                quick->rootObject(), QStringLiteral("drawerAutomationScrollBar")) == nullptr);
    QCOMPARE(itemSceneRect(*m_automationInput), QRectF(automation->plotRect));
    QCOMPARE(itemSceneRect(*gutter), QRectF(gutterRect));
    QCOMPARE(qRound(m_automationInput->width()), automation->plotRect.width());
    QCOMPARE(qRound(gutter->width()), gutterRect.width());
    QCOMPARE(qRound(gutter->height()), automation->rect.height());

    AutomationCanvas *const canvas = m_page->canvas();
    for (int index = 0; index < 9; ++index) {
        const auto row = canvas->parameterRow(index);
        QVERIFY(row.has_value());
        QVERIFY(activateParameter(*row));
        verifyActivePlot(view, *m_page, laneBody(findRow(*row)));
        QQuickItem *const label = checks::support::visualDescendant(
            quick->rootObject(), QStringLiteral("automationParameterTab%1").arg(index));
        QVERIFY(label);
        const QRectF labelRect = label->mapRectToScene(label->boundingRect());
        QVERIFY(!labelRect.isEmpty());
        QVERIFY(QRectF(gutterRect).contains(labelRect));
    }
}

void AutomationEditingTest::middleMousePanSurvivesRefresh()
{
    SongView &view = m_tab->view();
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, 0, kPanController};
    QVERIFY(activateParameter(pan));
    const QRect body = laneBody(findRow(pan));
    QVERIFY(!body.isEmpty());

    const QPointF start(160.0, body.center().y());
    const QPointF firstMove = start - QPointF(24.0, 0.0);
    const QPointF secondMove = start - QPointF(48.0, 0.0);
    const qreal dpr = m_automationInput->devicePixelRatio();
    const qreal before = view.camera().displayX(240.0, 0.0, dpr);

    mousePress(*m_automationInput, Qt::MiddleButton, start);
    mouseMove(*m_automationInput, firstMove);
    QCOMPARE(m_automationInput->cursor().shape(), Qt::ClosedHandCursor);
    mouseMove(*m_automationInput, secondMove);
    mouseRelease(*m_automationInput, Qt::MiddleButton, secondMove);

    const qreal after = view.camera().displayX(240.0, 0.0, dpr);
    QVERIFY(qAbs((before - after) - 48.0) < 0.5);
    view.setEditorHorizontalScroll(0.0);
}

void AutomationEditingTest::emptyParameterSwitchPreservesGridResolution()
{
    SongView &view = m_tab->view();
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    QVERIFY(m_tab->document().lanePoints(0, kLfoController).empty());
    const FrozenDocumentState frozen = frozenDocumentState();
    const uint64_t cursorBefore = view.editCursorTick();
    const int splitBefore = view.timelineSplitX();
    const DrawerPageGridState grid = {
        view.grid().gridTicksAt(48),
        view.grid().snapTicksAt(48),
    };
    const uint64_t snap = view.grid().snapTick(30.0, false);
    const uint64_t spacing = view.grid().snapTicksAt(snap);

    QVERIFY(activateParameter(lfo));
    const LaneHandle lane = findRow(lfo);
    QVERIFY(lane.valid());
    verifyActivePlot(view, *m_page, laneBody(lane));
    QCOMPARE(view.timelineSplitX(), splitBefore);
    QVERIFY(frozenDocumentState() == frozen);
    QCOMPARE(view.editCursorTick(), cursorBefore);
    QCOMPARE(view.grid().gridTicksAt(48), grid.gridTicks);
    QCOMPARE(view.grid().snapTicksAt(48), grid.snapTicks);
    QCOMPARE(view.grid().snapTick(30.0, false), snap);
    QCOMPARE(view.grid().snapTicksAt(snap), spacing);
    QVERIFY(grid.gridTicks > 0);
    QVERIFY(grid.snapTicks > 0);
    QCOMPARE(view.grid().snapTick(double(snap) + 0.1 * double(spacing), false), snap);
    QCOMPARE(view.grid().snapTick(double(snap) + 0.4 * double(spacing), false), snap);
    QVERIFY(view.grid().snapTick(double(snap) + 1.1 * double(spacing), false) != snap);
}

void AutomationEditingTest::viewStateSwitchPreservesAutomationState()
{
    SongView &view = m_tab->view();
    const EditorAutomationRowId bendRange{EditorAutomationRowKind::ControlChange, 0, 20};
    QVERIFY(activateParameter(bendRange));
    m_page->setLaneRange(bendRange, 64);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 300);
    pumpQuick();
    const EditorViewState beforeSwitch = view.editorViewState();
    const FrozenDocumentState frozen = frozenDocumentState();
    const uint64_t cursorBefore = view.editCursorTick();
    const int splitBefore = view.timelineSplitX();
    const int activeBefore = m_page->canvas()->activeParameter();
    const QSize viewportBefore = m_page->automationViewportSize();

    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 240);
    pumpQuick();

    const EditorViewState whileVelocity = view.editorViewState();
    QVERIFY(whileVelocity.automation == beforeSwitch.automation);
    QVERIFY(whileVelocity.laneRanges == beforeSwitch.laneRanges);
    QCOMPARE(m_page->automationViewportSize(), viewportBefore);
    QCOMPARE(m_page->canvas()->activeParameter(), activeBefore);
    QVERIFY(frozenDocumentState() == frozen);
    QCOMPARE(view.editCursorTick(), cursorBefore);

    view.setDrawerActivePage(EditorDrawerPage::Automations);
    pumpQuick();
    verifyActivePlot(view, *m_page, laneBody(findRow(bendRange)));
    QCOMPARE(view.timelineSplitX(), splitBefore);
    QCOMPARE(view.editorViewState().laneRanges.at(bendRange), uint8_t{64});
    QVERIFY(frozenDocumentState() == frozen);
    QCOMPARE(view.editCursorTick(), cursorBefore);
}

void AutomationEditingTest::wheelZoomAndSectionResizePreserveDrawerState()
{
    SongView &view = m_tab->view();
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, 0, kPanController};
    QVERIFY(activateParameter(pan));
    const QRect body = laneBody(findRow(pan));
    QVERIFY(!body.isEmpty());
    const QPointF anchor(200.0, body.center().y());
    const double tickBefore = view.camera().tickAtContentX(anchor.x());
    const double zoomBefore = view.camera().pxPerBeat();
    const EditorViewState beforeZoom = view.editorViewState();
    const FrozenDocumentState frozen = frozenDocumentState();
    const int splitBefore = view.timelineSplitX();
    const uint64_t cursorBefore = view.editCursorTick();
    wheel(*m_automationInput, anchor, QPoint(0, 120));
    pumpQuick();
    QVERIFY(view.camera().pxPerBeat() > zoomBefore);
    QVERIFY(std::abs(view.camera().tickAtContentX(anchor.x()) - tickBefore) < 0.001);
    const EditorViewState afterZoom = view.editorViewState();
    QVERIFY(afterZoom.velocity == beforeZoom.velocity);
    QVERIFY(afterZoom.voiceChanges == beforeZoom.voiceChanges);
    QVERIFY(afterZoom.automation == beforeZoom.automation);
    QVERIFY(afterZoom.activePage == beforeZoom.activePage);

    const int originalHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int minimumHeight = m_page->canvas()->minimumContentHeight();
    const int targetHeight = originalHeight == minimumHeight
                                 ? view.editorDrawer()->maximumSectionHeight()
                                 : minimumHeight;
    QVERIFY(targetHeight != originalHeight);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, targetHeight);
    pumpQuick();
    QTRY_COMPARE(m_page->automationViewportSize().height(), targetHeight);
    verifyActivePlot(view, *m_page, laneBody(findRow(pan)));
    QCOMPARE(view.timelineSplitX(), splitBefore);
    const EditorViewState afterHeight = view.editorViewState();
    QVERIFY(afterHeight.velocity == afterZoom.velocity);
    QVERIFY(afterHeight.voiceChanges == afterZoom.voiceChanges);
    QVERIFY(afterHeight.activePage == afterZoom.activePage);
    QVERIFY(frozenDocumentState() == frozen);
    QCOMPARE(view.editCursorTick(), cursorBefore);
}
