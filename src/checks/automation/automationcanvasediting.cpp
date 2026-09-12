// Qt Test coverage for automation canvas transactions not already covered by adapter parity.

#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <algorithm>
#include <optional>

#include <QCoreApplication>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/layout.h"

#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

constexpr uint8_t kController = 10;
constexpr Tick kFirstPointTick = 48;
constexpr Tick kBlankPointTick = 144;
constexpr int kFirstPointValue = 40;
constexpr int kBlankPointValue = 64;

enum class CancellationRoute : int {
    Explicit,
    UngrabMouse,
    WindowDeactivated,
    PageHidden,
};

songview::EditorSelectionModel::TimeSelection laneSelection(Tick begin, Tick end,
                                                            uint8_t controller)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = begin;
    selection.endTick = end;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{0, controller}};
    return selection;
}

QString routeName(CancellationRoute route)
{
    switch (route) {
    case CancellationRoute::Explicit:
        return QStringLiteral("explicit cancellation");
    case CancellationRoute::UngrabMouse:
        return QStringLiteral("mouse ungrab");
    case CancellationRoute::WindowDeactivated:
        return QStringLiteral("window deactivation");
    case CancellationRoute::PageHidden:
        return QStringLiteral("drawer page hide");
    }
    return {};
}

} // namespace

void AutomationEditingTest::activationSlopDoesNotCommit()
{
    const LaneHandle lane =
        findRow(EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(lane.valid());
    const QPointF blank = inputPoint(lane, kBlankPointTick, kBlankPointValue);
    const QPoint blankWindow = automation_test::windowFromContent(page(), automationInput(), blank);
    const QPoint activationWindow = automation_test::windowFromContent(
        page(), automationInput(),
        blank + QPointF(0.0, AutomationGeometry::resolve().nodeDragActivationDistance));
    QVERIFY(
        automationInput().bounds().contains(automationInput().mapFromScene(QPointF(blankWindow))));

    const FrozenDocumentState frozen = frozenDocumentState();
    mousePress(Qt::LeftButton, blankWindow);
    mouseMove(activationWindow);
    mouseRelease(Qt::LeftButton, activationWindow);

    QVERIFY(frozenDocumentState() == frozen);
    QCOMPARE(laneValue(kBlankPointTick), -1);
}

void AutomationEditingTest::selectionClearingAndMultilaneReplacement()
{
    SongView &view = tab().view();
    const LaneHandle lane =
        findRow(EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(lane.valid());
    const QPoint outside = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, 120, kBlankPointValue));
    const songview::EditorSelectionModel::TimeSelection selection =
        laneSelection(24, 72, kController);

    view.selectionModel().setTimeSelection(selection);
    mousePress(Qt::LeftButton, outside);
    QVERIFY(!view.selectionModel().timeSelection().active());
    mouseRelease(Qt::LeftButton, outside);

    view.selectionModel().setTimeSelection(selection);
    mousePress(Qt::RightButton, outside);
    QVERIFY(!view.selectionModel().timeSelection().active());
    mouseRelease(Qt::RightButton, outside);

    view.selectionModel().setTimeSelection(selection);
    QVERIFY(activateParameter({EditorAutomationRowKind::Tempo, 0, 0}));
    QVERIFY(view.selectionModel().timeSelection().active());
    QVERIFY(view.selectionModel().timeSelection().lanes == selection.lanes);
    QCOMPARE(view.selectionModel().timeSelection().scope, selection.scope);
    QCOMPARE(view.selectionModel().timeSelection().startTick, selection.startTick);
    QCOMPARE(view.selectionModel().timeSelection().endTick, selection.endTick);

    view.selectionModel().setTimeSelection(selection);
    keyClick(Qt::Key_Escape);
    const auto &cleared = view.selectionModel().timeSelection();
    QVERIFY(!cleared.active());
    QCOMPARE(cleared.scope, songview::EditorSelectionModel::TimeSelection::Tracks);
    QCOMPARE(cleared.startTick, uint64_t{0});
    QCOMPARE(cleared.endTick, uint64_t{0});
    QVERIFY(cleared.lanes.empty());

    page().canvas()->rebuildRows();
    const auto &afterRebuild = view.selectionModel().timeSelection();
    QVERIFY(!afterRebuild.active());
    QVERIFY(afterRebuild.lanes.empty());

    const EditorAutomationRowId bend{EditorAutomationRowKind::ControlChange, 0, DOC_CC_BEND};
    songview::EditorSelectionModel::TimeSelection noncontiguous =
        laneSelection(24, 72, kController);
    noncontiguous.lanes.push_back({int(bend.track), bend.controller});
    view.selectionModel().setTimeSelection(noncontiguous);
    QVERIFY(view.selectionModel().timeSelection().lanes == noncontiguous.lanes);

    noncontiguous.lanes = {{0, 21}};
    view.selectionModel().setTimeSelection(noncontiguous);
    QVERIFY(view.selectionModel().timeSelection().lanes == noncontiguous.lanes);
    keyClick(Qt::Key_Escape);
    QVERIFY(!view.selectionModel().timeSelection().active());
    QVERIFY(view.selectionModel().timeSelection().lanes.empty());
}

void AutomationEditingTest::additionalDragCancellationRoutesLeaveDocumentUntouched_data()
{
    QTest::addColumn<int>("routeValue");
    QTest::newRow("explicit") << static_cast<int>(CancellationRoute::Explicit);
    QTest::newRow("ungrab-mouse") << static_cast<int>(CancellationRoute::UngrabMouse);
    QTest::newRow("window-deactivated") << static_cast<int>(CancellationRoute::WindowDeactivated);
    QTest::newRow("page-hidden") << static_cast<int>(CancellationRoute::PageHidden);
}

void AutomationEditingTest::additionalDragCancellationRoutesLeaveDocumentUntouched()
{
    QFETCH(int, routeValue);
    const CancellationRoute route = static_cast<CancellationRoute>(routeValue);
    const LaneHandle lane =
        findRow(EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kController});
    QVERIFY(lane.valid());
    const QPointF source = inputPoint(lane, kFirstPointTick, kFirstPointValue);
    const QPointF activation =
        source + QPointF(0.0, -AutomationGeometry::resolve().nodeDragActivationDistance - 2);
    const QPointF target = activation + QPointF(40.0, 8.0);
    const QPoint sourceWindow =
        automation_test::windowFromContent(page(), automationInput(), source);
    const QPoint activationWindow =
        automation_test::windowFromContent(page(), automationInput(), activation);
    const QPoint targetWindow =
        automation_test::windowFromContent(page(), automationInput(), target);
    const FrozenDocumentState frozen = frozenDocumentState();

    mousePress(Qt::LeftButton, sourceWindow);
    mouseMove(activationWindow);
    mouseMove(targetWindow);

    switch (route) {
    case CancellationRoute::Explicit:
        page().cancelInteraction();
        break;
    case CancellationRoute::UngrabMouse:
        QTRY_VERIFY(quickWindow().mouseGrabberItem() == &automationInput());
        automationInput().ungrabMouse();
        QTRY_VERIFY(!quickWindow().mouseGrabberItem());
        break;
    case CancellationRoute::WindowDeactivated:
        sendWindowDeactivate();
        break;
    case CancellationRoute::PageHidden:
        tab().view().editorDrawer()->cancelVisiblePageInteraction();
        break;
    }

    mouseRelease(Qt::LeftButton, targetWindow);
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY2(tab().document().findLanePoint(0, kController, kFirstPointTick, nullptr),
             qPrintable(routeName(route)));
}

void AutomationEditingTest::voiceContextFollowsPlaybackOrEditCursor()
{
    SongView &view = tab().view();
    tab().document().addLanePoint(0, DOC_CC_VOICE, 24, 3);
    QTRY_VERIFY(tab().timeline());
    QTRY_COMPARE(view.voiceContext(24).voiceSlot, 3);
    const MidiTimeline *const timeline = tab().timeline().get();
    EditorDrawer *const drawer = view.editorDrawer();
    QVERIFY(timeline);
    QVERIFY(drawer);

    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    VelocityArea *const velocity = drawer->velocityArea();
    QVERIFY(velocity);

    DrawerPageLiveState negativePlayback;
    negativePlayback.documentRevision = tab().document().revision();
    negativePlayback.playback = {-3.0, true};
    velocity->refreshLiveState(negativePlayback);
    QVERIFY(velocity->axis().map() == VelocityMap::resolve(&m_bank.voices[0], std::nullopt));

    struct PlaybackBoundary {
        uint64_t sample = 0;
        double tick = 0.0;
        Tick contextTick = 0;
        int voiceSlot = 0;
    };
    const uint64_t tickTenSample = timeline->sampleForTick(10);
    const uint64_t samplesPerTick = timeline->sampleForTick(11) - tickTenSample;
    QCOMPARE(samplesPerTick, uint64_t{1000});
    for (const PlaybackBoundary &boundary :
         {PlaybackBoundary{timeline->sampleForTick(0), 0.0, 0, 0},
          PlaybackBoundary{timeline->sampleForTick(10), 10.0, 10, 0},
          PlaybackBoundary{tickTenSample + 490, 10.49, 10, 0},
          PlaybackBoundary{tickTenSample + 500, 10.5, 11, 0},
          PlaybackBoundary{tickTenSample + 510, 10.51, 11, 0},
          PlaybackBoundary{timeline->sampleForTick(11), 11.0, 11, 0},
          PlaybackBoundary{timeline->sampleForTick(24), 24.0, 24, 3}}) {
        view.setPlayheadSample(boundary.sample, true);
        QCOMPARE(view.playheadTick(), boundary.tick);
        const Tick roundedPlayhead = CoreTimeDefaults::tickFromDouble(view.playheadTick() + 0.5);
        QCOMPARE(roundedPlayhead, boundary.contextTick);
        const DrawerPageVoiceContext context = view.voiceContext(roundedPlayhead);
        QCOMPARE(context.voice, &m_bank.voices[boundary.voiceSlot]);
        QCOMPARE(context.voiceSlot, boundary.voiceSlot);
        QVERIFY(velocity->axis().map() ==
                VelocityMap::resolve(&m_bank.voices[boundary.voiceSlot], std::nullopt));
    }

    view.setEditCursorTick(24);
    view.setPlayheadSample(timeline->sampleForTick(10), false);
    const DrawerPageVoiceContext stopped = view.voiceContext(view.editCursorTick());
    QCOMPARE(stopped.voice, &m_bank.voices[3]);
    QCOMPARE(stopped.voiceSlot, 3);
    QVERIFY(velocity->axis().map() == VelocityMap::resolve(&m_bank.voices[3], std::nullopt));
}
