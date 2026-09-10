#include "checks/automation/tst_automationediting.h"

#include <algorithm>
#include <iterator>
#include <limits>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include <QAction>
#include <QKeySequence>

#include <QColor>
#include <QSignalSpy>
#include <QtTest>

#include "checks/support/timelinequickcheck.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelinequickscene.h"

namespace {

// The pilot lane nodes the armed drag targets: the grabbed node at
// kPilotNodeTick moves value-only, and its independent sibling must never
// move with it.
constexpr uint64_t kPilotNodeTick = 48;
constexpr int kPilotNodeValue = 40;
constexpr int kPilotCommittedValue = 84;
constexpr uint64_t kPilotSiblingTick = 96;
constexpr int kPilotSiblingValue = 100;

constexpr uint8_t kPanController = 10;

bool heldValueAt(const std::vector<DocLanePoint> &points, uint64_t tick, int *value)
{
    const auto firstAfterTick = std::upper_bound(
        points.cbegin(), points.cend(), tick,
        [](uint64_t needle, const DocLanePoint &point) { return needle < point.tick; });
    if (firstAfterTick == points.cbegin())
        return false;
    *value = std::prev(firstAfterTick)->value;
    return true;
}

std::optional<DocLanePoint> pointAt(const SongDocument &document, uint64_t tick)
{
    DocLanePoint point;
    if (!document.findLanePoint(0, kPanController, tick, &point))
        return std::nullopt;
    return point;
}

} // namespace

void AutomationEditingTest::tracksSelectionRings()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    tab().document().writeLanePoints(0, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                                     {{48, 32}, {96, 64}, {144, 96}, {192, 80}});

    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    const quint64 revisionBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = 24;
    selection.endTick = 192;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
    tab().view().selectionModel().setTimeSelection(selection);

    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision >
                revisionBefore);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const QColor color = automationInput().palette().highlight().color();
    const auto ringPaintedAt = [&](const QPointF &contentPoint) {
        const QPoint window =
            automation_test::windowFromContent(page(), automationInput(), contentPoint);
        const QPointF viewportPoint = automationInput().mapFromScene(QPointF(window));
        return checks::support::layerHasRingAt(
            scene->layer(songview::TimelineQuickLayer::AutomationNodes), viewportPoint,
            geometry.selectedNodeRingRadius, geometry.selectedNodeRingDipWidth, color);
    };

    QVERIFY(ringPaintedAt(inputPoint(pan, 48, 32)));
    QVERIFY(ringPaintedAt(inputPoint(pan, 96, 64)));
    QVERIFY(ringPaintedAt(inputPoint(pan, 144, 96)));
    QVERIFY(!ringPaintedAt(inputPoint(pan, 192, 80)));
}

void AutomationEditingTest::tracksSelectionGroupDragUndo()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    tab().document().writeLanePoints(0, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                                     {{48, 32}, {96, 64}, {144, 96}, {192, 80}});
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = 24;
    selection.endTick = 192;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
    tab().view().selectionModel().setTimeSelection(selection);

    const uint64_t revisionBefore = tab().document().revision();
    const int undoCountBefore = tab().document().undoStack()->count();
    const int undoIndexBefore = tab().document().undoStack()->index();
    const QPointF source = inputPoint(pan, 96, 64);
    const QPointF target = inputPoint(pan, 120, 64);
    const int activationDistance = AutomationGeometry::resolve().nodeDragActivationDistance + 2;
    const QPointF activation = source + QPointF(activationDistance, 0.0);
    const QPoint sourceWindow =
        automation_test::windowFromContent(page(), automationInput(), source);
    const QPoint targetWindow =
        automation_test::windowFromContent(page(), automationInput(), target);
    const QPoint activationWindow =
        automation_test::windowFromContent(page(), automationInput(), activation);
    const QPoint endWindow = activationWindow + (targetWindow - sourceWindow);
    const QPointF effectiveTarget = automation_test::effectiveDragContent(
        page(), automationInput(), sourceWindow, activationWindow, endWindow);
    const AutomationProjection::PointerMapping effectiveTargetMapping =
        pointerMapping(pan, effectiveTarget);
    QCOMPARE(effectiveTargetMapping.point.tick, uint64_t{120});
    QCOMPARE(effectiveTargetMapping.point.value, 64);

    mousePress(Qt::LeftButton, sourceWindow);
    mouseMove(activationWindow);
    mouseMove(endWindow, Qt::AltModifier);
    mouseRelease(Qt::LeftButton, endWindow, Qt::AltModifier);

    QTRY_COMPARE(tab().document().revision(), revisionBefore + 1);
    QCOMPARE(tab().document().undoStack()->count(), undoCountBefore + 1);
    QCOMPARE(tab().document().undoStack()->index(), undoIndexBefore + 1);
    const std::optional<DocLanePoint> moved72 = pointAt(tab().document(), 72);
    const std::optional<DocLanePoint> moved120 = pointAt(tab().document(), 120);
    const std::optional<DocLanePoint> moved168 = pointAt(tab().document(), 168);
    const std::optional<DocLanePoint> untouched192 = pointAt(tab().document(), 192);
    QVERIFY(moved72.has_value());
    QVERIFY(moved120.has_value());
    QVERIFY(moved168.has_value());
    QVERIFY(untouched192.has_value());
    QCOMPARE(moved72->value, 32);
    QCOMPARE(moved120->value, 64);
    QCOMPARE(moved168->value, 96);
    QCOMPARE(untouched192->value, 80);
    QVERIFY(!pointAt(tab().document(), 48).has_value());
    QVERIFY(!pointAt(tab().document(), 96).has_value());
    QVERIFY(!pointAt(tab().document(), 144).has_value());
    const auto &movedSelection = tab().view().selectionModel().timeSelection();
    QCOMPARE(movedSelection.startTick, uint64_t(48));
    QCOMPARE(movedSelection.endTick, uint64_t(216));
    QCOMPARE(movedSelection.scope, songview::EditorSelectionModel::TimeSelection::Tracks);
    QVERIFY(movedSelection.lanes.empty());
    QVERIFY(!movedSelection.tempo);

    QVERIFY(tab().history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QVERIFY(pointAt(tab().document(), 48).has_value());
    QVERIFY(pointAt(tab().document(), 96).has_value());
    QVERIFY(pointAt(tab().document(), 144).has_value());
    QVERIFY(pointAt(tab().document(), 192).has_value());
    QVERIFY(!pointAt(tab().document(), 72).has_value());
    QVERIFY(!pointAt(tab().document(), 120).has_value());
    QVERIFY(!pointAt(tab().document(), 168).has_value());

    QVERIFY(tab().history().canRedo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestRedo()));
    QVERIFY(pointAt(tab().document(), 120).has_value());
}

void AutomationEditingTest::pencilModeChangeRetainsPencilGesture()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    setPencilMode(true);
    QAction *const action = pencilModeAction();
    QVERIFY(action);
    QVERIFY(action->shortcut().count() == 1);
    const QKeyCombination shortcut = action->shortcut()[0];
    QVERIFY(shortcut.key() != Qt::Key_unknown);
    const QPointF start = inputPoint(pan, 24, 36);
    const QPointF end = inputPoint(pan, 120, 92);
    const AutomationProjection projection(AutomationGeometry::resolve(), &page());
    const AutomationGridCell endCell = projection.snapCellAt(projection.rawTickAt(end.x()));

    mousePress(Qt::LeftButton,
               automation_test::windowFromContent(page(), automationInput(), start));
    keyClick(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(!action->isChecked());
    mouseMove(automation_test::windowFromContent(page(), automationInput(), end));
    mouseRelease(Qt::LeftButton,
                 automation_test::windowFromContent(page(), automationInput(), end));

    QTRY_VERIFY(pointAt(tab().document(), endCell.tickBegin).has_value());
    const std::optional<DocLanePoint> endPoint = pointAt(tab().document(), endCell.tickBegin);
    QVERIFY(endPoint.has_value());
    QCOMPARE(endPoint->value, 92);
}

void AutomationEditingTest::pencilModeChangeRetainsNodeGesture()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    setPencilMode(false);
    tab().document().writeLanePoints(0, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                                     {{72, 64}});
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = 72;
    selection.endTick = 96;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{0, kPanController}};
    tab().view().selectionModel().setTimeSelection(selection);

    const QPointF source = inputPoint(pan, 72, 64);
    const QPointF target = inputPoint(pan, 168, 96);
    const int activationDistance = AutomationGeometry::resolve().nodeDragActivationDistance + 2;
    const QPointF activation = source + QPointF(activationDistance, 0.0);
    const QPoint sourceWindow =
        automation_test::windowFromContent(page(), automationInput(), source);
    const QPoint targetWindow =
        automation_test::windowFromContent(page(), automationInput(), target);
    const QPoint activationWindow =
        automation_test::windowFromContent(page(), automationInput(), activation);
    const QPoint endWindow = activationWindow + (targetWindow - sourceWindow);
    const QPointF effectiveTarget = automation_test::effectiveDragContent(
        page(), automationInput(), sourceWindow, activationWindow, endWindow);
    const AutomationProjection::PointerMapping effectiveTargetMapping =
        pointerMapping(pan, effectiveTarget);
    QCOMPARE(effectiveTargetMapping.point.tick, uint64_t{168});
    QCOMPARE(effectiveTargetMapping.point.value, 96);

    QAction *const action = pencilModeAction();
    QVERIFY(action);
    QVERIFY(action->shortcut().count() == 1);
    const QKeyCombination shortcut = action->shortcut()[0];
    QVERIFY(shortcut.key() != Qt::Key_unknown);

    mousePress(Qt::LeftButton, sourceWindow);
    keyClick(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());
    mouseMove(activationWindow);
    mouseMove(endWindow);
    mouseRelease(Qt::LeftButton, endWindow);

    QTRY_VERIFY(pointAt(tab().document(), 168).has_value());
    const std::optional<DocLanePoint> movedPoint = pointAt(tab().document(), 168);
    QVERIFY(movedPoint.has_value());
    QCOMPARE(movedPoint->value, 96);
    QVERIFY(!pointAt(tab().document(), 72).has_value());
    const auto &movedSelection = tab().view().selectionModel().timeSelection();
    QCOMPARE(movedSelection.startTick, uint64_t(168));
    QCOMPARE(movedSelection.endTick, uint64_t(192));
    QCOMPARE(movedSelection.scope, songview::EditorSelectionModel::TimeSelection::Lanes);
    const std::vector<std::pair<int, uint8_t>> expectedLanes{{0, kPanController}};
    QCOMPARE(movedSelection.lanes, expectedLanes);
}

void AutomationEditingTest::pencilStrokeOutsideSelectionClearsSelection()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    setPencilMode(true);
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = 24;
    selection.endTick = 72;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{0, kPanController}};
    tab().view().selectionModel().setTimeSelection(selection);

    const QPointF start = inputPoint(pan, 144, 32);
    const QPointF end = inputPoint(pan, 216, 96);
    mousePress(Qt::LeftButton,
               automation_test::windowFromContent(page(), automationInput(), start));
    mouseMove(automation_test::windowFromContent(page(), automationInput(), end));
    mouseRelease(Qt::LeftButton,
                 automation_test::windowFromContent(page(), automationInput(), end));

    QTRY_VERIFY(!tab().view().selectionModel().timeSelection().active());
}

void AutomationEditingTest::detailThresholdHiddenVisibleNodePrecedence()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    QVERIFY(geometry.pointDetailThreshold > 1);
    using DeliveredPoint = std::pair<QPoint, AutomationProjection::PointerMapping>;
    const auto deliveredPoint = [this, pan](double tick, int value, uint64_t expectedTick) {
        const QPoint seed = automation_test::windowFromContent(page(), automationInput(),
                                                               inputPoint(pan, tick, value));
        const auto mapWindow = [this, pan](const QPoint &window) {
            const QPointF content =
                automation_test::contentFromWindow(page(), automationInput(), window);
            return DeliveredPoint{window, pointerMapping(pan, content)};
        };
        DeliveredPoint delivered = mapWindow(seed);
        for (const int offset : {0, 1, -1, 2, -2}) {
            const DeliveredPoint candidate = mapWindow(seed + QPoint(offset, 0));
            if (automationInput().bounds().contains(
                    automationInput().mapFromScene(QPointF(candidate.first))) &&
                candidate.second.point.tick == expectedTick) {
                return candidate;
            }
        }
        return delivered;
    };

    tab().view().setEditorTimeZoom(double(geometry.pointDetailThreshold - 1));
    QTRY_VERIFY(!AutomationProjection(geometry, &page()).nodeMarkersVisible());
    setPencilMode(true);
    const AutomationProjection hiddenProjection(geometry, &page());
    const AutomationGridCell hiddenSourceCell = hiddenProjection.snapCellAt(72.0);
    QCOMPARE(hiddenSourceCell.tickBegin, uint64_t{72});
    const DeliveredPoint hiddenSource = deliveredPoint(72.0, 40, hiddenSourceCell.tickBegin);
    QCOMPARE(hiddenSource.second.point.tick, uint64_t{72});
    tab().document().writeLanePoints(
        0, kPanController, 0, std::numeric_limits<uint64_t>::max(),
        {{hiddenSource.second.point.tick, hiddenSource.second.point.value}});
    const AutomationGridCell hiddenEndCell = hiddenProjection.snapCellAt(192.0);
    const DeliveredPoint hiddenEnd = deliveredPoint(192.0, 96, hiddenEndCell.tickBegin);
    QCOMPARE(hiddenEnd.second.point.tick, hiddenEndCell.tickBegin);

    mousePress(Qt::LeftButton, hiddenSource.first);
    mouseMove(hiddenEnd.first);
    mouseRelease(Qt::LeftButton, hiddenEnd.first);

    QTRY_VERIFY(pointAt(tab().document(), 72).has_value());
    const std::optional<DocLanePoint> hiddenPoint = pointAt(tab().document(), 72);
    QVERIFY(hiddenPoint.has_value());
    QCOMPARE(hiddenPoint->value, hiddenSource.second.point.value);
    int hiddenValue = -1;
    QVERIFY(heldValueAt(tab().document().lanePoints(0, kPanController),
                        hiddenEnd.second.cell.tickBegin +
                            (hiddenEnd.second.cell.tickEnd - hiddenEnd.second.cell.tickBegin) / 2,
                        &hiddenValue));
    QVERIFY(std::abs(hiddenValue - hiddenEnd.second.point.value) <= 1);

    tab().view().setEditorTimeZoom(double(geometry.pointDetailThreshold));
    QTRY_VERIFY(AutomationProjection(geometry, &page()).nodeMarkersVisible());
    setPencilMode(true);
    const AutomationProjection visibleProjection(geometry, &page());
    const AutomationGridCell visibleSourceCell = visibleProjection.snapCellAt(72.0);
    QCOMPARE(visibleSourceCell.tickBegin, uint64_t{72});
    const DeliveredPoint visibleSource = deliveredPoint(72.0, 40, visibleSourceCell.tickBegin);
    QCOMPARE(visibleSource.second.point.tick, uint64_t{72});
    tab().document().writeLanePoints(
        0, kPanController, 0, std::numeric_limits<uint64_t>::max(),
        {{visibleSource.second.point.tick, visibleSource.second.point.value}});
    const AutomationGridCell visibleTargetCell = visibleProjection.snapCellAt(168.0);
    const DeliveredPoint visibleTarget = deliveredPoint(168.0, 96, visibleTargetCell.tickBegin);
    QCOMPARE(visibleTarget.second.point.tick, visibleTargetCell.tickBegin);
    const int activationDistance = geometry.nodeDragActivationDistance + 2;
    const QPoint activationWindow = visibleSource.first + QPoint(activationDistance, 0);
    const QPoint endWindow = activationWindow + (visibleTarget.first - visibleSource.first);
    const QPointF effectiveTarget = automation_test::effectiveDragContent(
        page(), automationInput(), visibleSource.first, activationWindow, endWindow);
    const AutomationProjection::PointerMapping effectiveTargetMapping =
        pointerMapping(pan, effectiveTarget);
    QCOMPARE(effectiveTargetMapping.point.tick, visibleTarget.second.point.tick);
    QCOMPARE(effectiveTargetMapping.point.value, visibleTarget.second.point.value);

    mousePress(Qt::LeftButton, visibleSource.first);
    mouseMove(activationWindow);
    mouseMove(endWindow);
    mouseRelease(Qt::LeftButton, endWindow);

    QTRY_VERIFY(pointAt(tab().document(), visibleTargetCell.tickBegin).has_value());
    const std::optional<DocLanePoint> visiblePoint =
        pointAt(tab().document(), visibleTargetCell.tickBegin);
    QVERIFY(visiblePoint.has_value());
    QCOMPARE(visiblePoint->value, visibleTarget.second.point.value);
    QVERIFY(!pointAt(tab().document(), 72).has_value());

    mousePress(Qt::LeftButton, visibleTarget.first);
    mouseRelease(Qt::LeftButton, visibleTarget.first);
    QTRY_VERIFY(!pointAt(tab().document(), visibleTargetCell.tickBegin).has_value());
}

// A parameter switch during a live provisional drag cancels the owned
// gesture: the old pointer's release commits nothing, no grab or
// follow-scroll pause survives, and the reactivated parameter's next
// ordinary drag commits exactly once.
void AutomationEditingTest::parameterSwitchCancelsNodeDrag()
{
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());

    const std::optional<ArmedCcDrag> arm = armCcDrag(scene);
    QVERIFY(arm.has_value());

    // The provisional preview is live: the retained transient layer carries
    // the grabbed node while the document stays frozen.
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                arm->transientRevisionBefore);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    QTRY_VERIFY(tab().view().userGestureActive());
    QTRY_VERIFY(quickWindow().mouseGrabberItem() == &automationInput());

    // Switching to Tempo mid-gesture ends the owned provisional gesture: the
    // pointer grab and the follow-scroll pause release, and the old
    // transient preview clears.
    const int pilotIndex = page().canvas()->activeParameter();
    const int tempoIndex = page().canvas()->parameterIndex({EditorAutomationRowKind::Tempo, 0, 0});
    QVERIFY(tempoIndex >= 0);
    page().canvas()->activateParameter(tempoIndex);
    QCOMPARE(page().canvas()->activeParameter(), tempoIndex);
    QTRY_VERIFY(!quickWindow().mouseGrabberItem());
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->gestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).rects.empty());
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).triangles.empty());
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);

    // The old pointer's release lands on the cancelled gesture: no
    // transaction, and both pilot points keep their original values.
    mouseRelease(Qt::LeftButton, arm->dragEndWindow, Qt::NoModifier);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    const std::optional<DocLanePoint> heldNode = pointAt(tab().document(), kPilotNodeTick);
    QVERIFY(heldNode.has_value());
    QCOMPARE(heldNode->value, kPilotNodeValue);
    const std::optional<DocLanePoint> sibling = pointAt(tab().document(), kPilotSiblingTick);
    QVERIFY(sibling.has_value());
    QCOMPARE(sibling->value, kPilotSiblingValue);

    // Reactivating the pilot parameter through its rendered label restores
    // its plot, and an ordinary drag commits exactly once again.
    const EditorAutomationRowId pilotRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    QVERIFY(activateParameter(pilotRow));
    QCOMPARE(page().canvas()->activeParameter(), pilotIndex);
    const LaneHandle pilot = findRow(pilotRow);
    QVERIFY(pilot.valid());
    QTRY_VERIFY(!laneBody(pilot).isEmpty());
    const std::optional<ArmedCcDrag> rearmed = armCcDrag(scene);
    QVERIFY(rearmed.has_value());
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                rearmed->transientRevisionBefore);
    mouseRelease(Qt::LeftButton, rearmed->dragEndWindow, Qt::NoModifier);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(tab().document().revision(), frozen.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), frozen.undoIndex + 1);
    const std::optional<DocLanePoint> committed = pointAt(tab().document(), kPilotNodeTick);
    QVERIFY(committed.has_value());
    QCOMPARE(committed->value, kPilotCommittedValue);
    const std::optional<DocLanePoint> survivingSibling =
        pointAt(tab().document(), kPilotSiblingTick);
    QVERIFY(survivingSibling.has_value());
    QCOMPARE(survivingSibling->value, kPilotSiblingValue);
}
