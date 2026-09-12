#include "checks/automation/tst_automationediting.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QSignalSpy>
#include <QtTest>

#include "checks/automation/automationvalueprompt.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelinequickscene.h"

namespace {

constexpr int kTempo = 0;
constexpr int kCc = 1;
constexpr uint8_t kController = 10;
constexpr Tick kFirstTick = 0;
constexpr Tick kNodeTick = 96;
constexpr Tick kLateTick = 288;
constexpr Tick kSweepStartTick = 48;
constexpr Tick kSweepEndTick = 144;
constexpr int kFirstValue = 80;
constexpr int kNodeValue = 100;
constexpr int kLateValue = 64;

EditorAutomationRowId rowId(int adapter)
{
    return adapter == kTempo
               ? EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0}
               : EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kController};
}

void setPoints(SongDocument &document, int adapter, const std::vector<NodePoint> &points)
{
    if (adapter == kTempo) {
        TempoEdit edit;
        edit.remove = document.tempoPoints();
        edit.add.reserve(points.size());
        for (const NodePoint &point : points) {
            edit.add.push_back({Tick(point.tick),
                                CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
        }
        if (edit.remove != edit.add)
            document.applyTempoEdit(edit);
        return;
    }

    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const NodePoint &point : points)
        values.push_back({Tick(point.tick), point.value});
    document.writeLanePoints(0, kController, 0, CoreTimeDefaults::kNoTick, values);
}

std::vector<NodePoint> pointsOf(const SongDocument &document, int adapter)
{
    std::vector<NodePoint> points;
    if (adapter == kTempo) {
        points.reserve(document.tempoPoints().size());
        for (const TempoPoint &point : document.tempoPoints()) {
            points.push_back(
                {point.tick,
                 int(std::lround(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote)))});
        }
        return points;
    }

    for (const DocLanePoint &point : document.lanePoints(0, kController))
        points.push_back({point.tick, point.value});
    return points;
}

bool containsPoint(const std::vector<NodePoint> &points, Tick tick, int value)
{
    return std::any_of(points.cbegin(), points.cend(), [tick, value](const NodePoint &point) {
        return point.tick == tick && point.value == value;
    });
}

bool samePoints(const std::vector<NodePoint> &actual, const std::vector<NodePoint> &expected)
{
    return actual.size() == expected.size() &&
           std::equal(actual.cbegin(), actual.cend(), expected.cbegin(),
                      [](const NodePoint &left, const NodePoint &right) {
                          return left.tick == right.tick && left.value == right.value;
                      });
}

QPoint dragActivation(const QPoint &source, const QPoint &target, int distance)
{
    const QPoint activation = source + QPoint(distance + 2, 0);
    return activation + target - source;
}

} // namespace

void AutomationEditingTest::hoverInsertionDoesNotMutateDocument_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::hoverInsertionDoesNotMutateDocument()
{
    QFETCH(int, adapter);
    setPoints(m_tab->document(), adapter,
              {{kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}});

    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    const QPointF hover = inputPoint(lane, kSweepStartTick, 90);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());

    mouseMove(automation_test::windowFromContent(page(), automationInput(), hover), Qt::NoModifier);

    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::stationaryNodeInteractions_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::stationaryNodeInteractions()
{
    QFETCH(int, adapter);
    const std::vector<NodePoint> fixture{
        {kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}};
    setPoints(m_tab->document(), adapter, fixture);
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    const QPoint node = automation_test::windowFromContent(page(), automationInput(),
                                                           inputPoint(lane, kNodeTick, kNodeValue));
    const uint64_t revision = m_tab->document().revision();
    const int undoIndex = m_tab->document().undoStack()->index();

    mousePress(Qt::LeftButton, node, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, node, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), revision + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), undoIndex + 1);
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter),
                       {{kFirstTick, kFirstValue}, {kLateTick, kLateValue}}));

    setPoints(m_tab->document(), adapter, fixture);
    QSignalSpy shiftDocumentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy shiftEdited(&tab(), &SongTab::edited);
    QVERIFY(shiftDocumentChanged.isValid());
    QVERIFY(shiftEdited.isValid());
    const FrozenDocumentState beforeShift =
        frozenDocumentState(shiftDocumentChanged.count(), shiftEdited.count());
    mousePress(Qt::LeftButton, node, Qt::ShiftModifier);
    mouseRelease(Qt::LeftButton, node, Qt::ShiftModifier);

    QVERIFY(frozenDocumentState(shiftDocumentChanged.count(), shiftEdited.count()) == beforeShift);
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter), fixture));
}

void AutomationEditingTest::independentDoubleClickAfterDeleteOpensValuePrompt_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::independentDoubleClickAfterDeleteOpensValuePrompt()
{
    QFETCH(int, adapter);
    const std::vector<NodePoint> fixture{
        {kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}};
    setPoints(m_tab->document(), adapter, fixture);
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    const QPoint node = automation_test::windowFromContent(page(), automationInput(),
                                                           inputPoint(lane, kNodeTick, kNodeValue));

    mousePress(Qt::LeftButton, node, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, node, Qt::NoModifier);
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter),
                       {{kFirstTick, kFirstValue}, {kLateTick, kLateValue}}));

    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState afterDelete =
        frozenDocumentState(documentChanged.count(), edited.count());

    // A double click away from the surviving nodes opens the inline value
    // prompt; rejecting it with Escape must leave the document frozen.
    DrawerChrome &chrome = m_tab->view().editorDrawer()->chrome();
    mouseDClick(Qt::LeftButton, node, Qt::NoModifier);
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QQuickItem *const prompt = automation_valueprompt::focusedTextInput(quickWindow());
    QVERIFY2(prompt, "the double-click insertion prompt did not take active focus");
    QTest::keyClick(&quickWindow(), Qt::Key_Escape);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == afterDelete);
}

void AutomationEditingTest::doubleClickDeletesOnceWithoutValuePrompt_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::doubleClickDeletesOnceWithoutValuePrompt()
{
    QFETCH(int, adapter);
    const std::vector<NodePoint> fixture{
        {kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}};
    setPoints(m_tab->document(), adapter, fixture);
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    const QPoint node = automation_test::windowFromContent(page(), automationInput(),
                                                           inputPoint(lane, kNodeTick, kNodeValue));
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const uint64_t revision = m_tab->document().revision();
    const int undoCount = m_tab->document().undoStack()->count();
    const int undoIndex = m_tab->document().undoStack()->index();

    // The double click lands on an existing node, so it deletes exactly once
    // and must not leave the inline value prompt behind.
    DrawerChrome &chrome = m_tab->view().editorDrawer()->chrome();
    mouseDClick(Qt::LeftButton, node, Qt::NoModifier);

    QVERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revision + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoCount + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), undoIndex + 1);
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter),
                       {{kFirstTick, kFirstValue}, {kLateTick, kLateValue}}));
}

void AutomationEditingTest::sweepAndRampCommit_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::sweepAndRampCommit()
{
    QFETCH(int, adapter);
    const std::vector<NodePoint> fixture{
        {kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}};
    setPoints(m_tab->document(), adapter, fixture);
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    const QPoint start = automation_test::windowFromContent(page(), automationInput(),
                                                            inputPoint(lane, kSweepStartTick, 80));
    const QPoint target = automation_test::windowFromContent(page(), automationInput(),
                                                             inputPoint(lane, kSweepEndTick, 110));
    const int activationDistance = AutomationGeometry::resolve().nodeDragActivationDistance;
    const QPoint activation = start + QPoint(activationDistance + 2, 0);
    const QPoint activatedTarget = dragActivation(start, target, activationDistance);
    const auto deliveredStart =
        pointerMapping(lane, automation_test::contentFromWindow(page(), automationInput(), start));
    const auto deliveredTarget =
        pointerMapping(lane, automation_test::contentFromWindow(page(), automationInput(), target));
    const auto effectiveSweepTarget =
        pointerMapping(lane, automation_test::effectiveDragContent(page(), automationInput(), start,
                                                                   activation, activatedTarget));
    QCOMPARE(deliveredStart.point.tick, kSweepStartTick);
    QCOMPARE(deliveredTarget.point.tick, kSweepEndTick);
    QCOMPARE(effectiveSweepTarget.point.tick, kSweepEndTick);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState sweepBefore =
        frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(Qt::LeftButton, start, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    mouseMove(activatedTarget, Qt::NoModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == sweepBefore);
    mouseRelease(Qt::LeftButton, activatedTarget, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), sweepBefore.revision + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), sweepBefore.undoIndex + 1);
    const std::vector<NodePoint> sweep = pointsOf(m_tab->document(), adapter);
    QVERIFY(containsPoint(sweep, kFirstTick, kFirstValue));
    QVERIFY(containsPoint(sweep, kSweepEndTick, effectiveSweepTarget.point.value));
    QVERIFY(containsPoint(sweep, kLateTick, kLateValue));

    setPoints(m_tab->document(), adapter, fixture);
    const FrozenDocumentState rampBefore =
        frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(Qt::LeftButton, start, Qt::ShiftModifier);
    mouseMove(target, Qt::ShiftModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == rampBefore);
    mouseRelease(Qt::LeftButton, target, Qt::ShiftModifier);

    QCOMPARE(m_tab->document().revision(), rampBefore.revision + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), rampBefore.undoIndex + 1);
    const std::vector<NodePoint> ramp = pointsOf(m_tab->document(), adapter);
    QVERIFY(containsPoint(ramp, kFirstTick, kFirstValue));
    QVERIFY(containsPoint(ramp, kSweepStartTick, deliveredStart.point.value));
    QVERIFY(containsPoint(ramp, kSweepEndTick, deliveredTarget.point.value));
    QVERIFY(containsPoint(ramp, kLateTick, kLateValue));
}

void AutomationEditingTest::pencilPreviewCommits_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::pencilPreviewCommits()
{
    QFETCH(int, adapter);
    setPoints(m_tab->document(), adapter, {});
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    setPencilMode(true);
    const QPoint start =
        automation_test::windowFromContent(page(), automationInput(), inputPoint(lane, 36, 80));
    const QPoint end = automation_test::windowFromContent(page(), automationInput(),
                                                          inputPoint(lane, kSweepEndTick, 110));
    auto *scene = quickScene();
    QVERIFY(scene);
    const uint64_t transientRevision =
        scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(Qt::LeftButton, start, Qt::NoModifier);
    mouseMove(end, Qt::NoModifier);

    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                transientRevision);
    QVERIFY(!scene->layer(songview::TimelineQuickLayer::AutomationTransient).triangles.empty());
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);

    mouseRelease(Qt::LeftButton, end, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), before.revision + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), before.undoIndex + 1);
    QVERIFY(!pointsOf(m_tab->document(), adapter).empty());
}

void AutomationEditingTest::laneBandSelectsRange_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::laneBandSelectsRange()
{
    QFETCH(int, adapter);
    setPoints(m_tab->document(), adapter,
              {{kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}});
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    m_tab->view().selectionModel().clearTimeSelection();
    const QPoint start = automation_test::windowFromContent(page(), automationInput(),
                                                            inputPoint(lane, kNodeTick, 80));
    const QPoint end = automation_test::windowFromContent(page(), automationInput(),
                                                          inputPoint(lane, kLateTick, 80));

    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(Qt::RightButton, start, Qt::NoModifier);
    mouseMove(end, Qt::NoModifier);
    mouseRelease(Qt::RightButton, end, Qt::NoModifier);

    const auto &selection = m_tab->view().selectionModel().timeSelection();
    QVERIFY(selection.active());
    QCOMPARE(selection.scope, songview::EditorSelectionModel::TimeSelection::Lanes);
    QCOMPARE(selection.startTick, kNodeTick);
    QCOMPARE(selection.endTick, kLateTick);
    QCOMPARE(selection.tempo, adapter == kTempo);
    if (adapter == kTempo)
        QVERIFY(selection.lanes.empty());
    else
        QCOMPARE(selection.lanes, (std::vector<std::pair<int, uint8_t>>{{0, kController}}));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::blankAndSubThresholdNoOps_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::blankAndSubThresholdNoOps()
{
    QFETCH(int, adapter);
    const std::vector<NodePoint> fixture{
        {kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}};
    setPoints(m_tab->document(), adapter, fixture);
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QVERIFY(activateParameter(rowId(adapter)));
    const QPoint blank = automation_test::windowFromContent(page(), automationInput(),
                                                            inputPoint(lane, kSweepStartTick, 90));
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(Qt::LeftButton, blank, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, blank, Qt::NoModifier);
    mousePress(Qt::LeftButton, blank, Qt::NoModifier);
    mouseMove(
        blank +
            QPoint(std::max(0, AutomationGeometry::resolve().nodeDragActivationDistance - 1), 0),
        Qt::NoModifier);
    mouseRelease(
        Qt::LeftButton,
        blank +
            QPoint(std::max(0, AutomationGeometry::resolve().nodeDragActivationDistance - 1), 0),
        Qt::NoModifier);

    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}
