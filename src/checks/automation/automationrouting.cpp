#include "checks/automation/tst_automationediting.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <utility>
#include <variant>
#include <vector>

#include <QtTest>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"

namespace {

constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;
constexpr uint8_t kVolumeController = 7;

using LanePoints = std::vector<std::pair<uint64_t, int>>;

LanePoints lanePoints(const SongDocument &document, uint8_t controller)
{
    LanePoints points;
    for (const DocLanePoint &point : document.lanePoints(0, controller))
        points.emplace_back(point.tick, point.value);
    return points;
}

EditorAutomationRowId controlRow(uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, 0, controller};
}

std::vector<int> laneHeights(const AutomationPage &page)
{
    std::vector<int> heights;
    const auto &rows = page.canvas()->rows();
    heights.reserve(rows.size());
    for (int index = 0; index < int(rows.size()); ++index)
        heights.push_back(page.canvas()->laneBody(LaneHandle{index + 1}).height());
    return heights;
}

bool onlyHeightChanged(const std::vector<int> &before, const std::vector<int> &after,
                       int changedIndex)
{
    if (before.size() != after.size() || changedIndex < 0 || changedIndex >= int(before.size()) ||
        before[std::size_t(changedIndex)] == after[std::size_t(changedIndex)]) {
        return false;
    }
    for (int index = 0; index < int(before.size()); ++index) {
        if (index != changedIndex && before[std::size_t(index)] != after[std::size_t(index)])
            return false;
    }
    return true;
}

void showVoiceChanges(SongView &view)
{
    view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 160);
}

} // namespace

void AutomationEditingTest::middlePanIsolated()
{
    const LaneHandle pan = findRow(controlRow(kPanController));
    QVERIFY(pan.valid());
    const QPointF input = inputPoint(pan, 48, 64);
    const FrozenDocumentState frozen = frozenDocumentState();
    const std::vector<int> heightsBefore = laneHeights(page());
    const uint64_t cursorBefore = tab().view().editCursorTick();

    mousePress(Qt::MiddleButton,
               automation_test::windowFromContent(page(), automationInput(), input));

    QVERIFY(page().canvas()->isPanning());
    QVERIFY(tab().view().userGestureActive());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);

    mouseRelease(Qt::MiddleButton,
                 automation_test::windowFromContent(page(), automationInput(), input));
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
}

void AutomationEditingTest::voicePressIsolated()
{
    showVoiceChanges(tab().view());
    QTRY_VERIFY(!voiceChangeInput().bounds().isEmpty());
    const LaneHandle pan = findRow(controlRow(kPanController));
    QVERIFY(pan.valid());
    const FrozenDocumentState frozen = frozenDocumentState();
    const std::vector<int> heightsBefore = laneHeights(page());
    const QRect tempoBefore = page().canvas()->pinnedTempoRect();
    const uint64_t cursorBefore = tab().view().editCursorTick();
    const QPointF input = voicePoint(48);

    mousePress(voiceChangeInput(), Qt::LeftButton, input);
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(page().canvas()->pinnedTempoRect(), tempoBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, input);
}

void AutomationEditingTest::tempoHeaderExpansionIsolated()
{
    const LaneHandle tempo = findRow({EditorAutomationRowKind::Tempo, 0, 0});
    QVERIFY(tempo.valid());
    const LaneHandle pan = findRow(controlRow(kPanController));
    QVERIFY(pan.valid());

    const FrozenDocumentState frozen = frozenDocumentState();
    const std::vector<int> heightsBefore = laneHeights(page());
    const uint64_t cursorBefore = tab().view().editCursorTick();
    const bool expandedBefore = !laneBody(tempo).isEmpty();

    const bool expandedAfter = expandTempo();

    QVERIFY(expandedAfter != expandedBefore);
    QCOMPARE(!laneBody(tempo).isEmpty(), expandedAfter);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);
}

void AutomationEditingTest::rowResizeChangesOnlyTarget()
{
    const LaneHandle pan = findRow(controlRow(kPanController));
    QVERIFY(pan.valid());
    const auto &rows = page().canvas()->rows();
    const int panIndex = pan.index - 1;
    QVERIFY(panIndex >= 0 && panIndex < int(rows.size()));
    const QRect body = laneBody(pan);
    QVERIFY(!body.isEmpty());
    const std::vector<int> heightsBefore = laneHeights(page());
    const FrozenDocumentState frozen = frozenDocumentState();
    const uint64_t cursorBefore = tab().view().editCursorTick();
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const int grow = geometry.rowMaximumHeight - body.height();
    const int shrink = body.height() - geometry.rowMinimumHeight;
    const int distance = std::max(1, geometry.rowWheelIncrement);
    const int delta = grow > 0 ? std::min(grow, distance) : -std::min(shrink, distance);
    QVERIFY(delta != 0);
    const QPointF input(automationGutterInput().bounds().center().x(), body.bottom());

    mousePress(automationGutterInput(), Qt::LeftButton, input);

    QVERIFY(tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);

    const QPointF moved = input + QPointF(0, delta);
    mouseMove(automationGutterInput(), moved);
    const std::vector<int> heightsAfter = laneHeights(page());
    QVERIFY(onlyHeightChanged(heightsBefore, heightsAfter, panIndex));
    QCOMPARE(heightsAfter[std::size_t(panIndex)], heightsBefore[std::size_t(panIndex)] + delta);
    QVERIFY(frozenDocumentState() == frozen);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);

    mouseRelease(automationGutterInput(), Qt::LeftButton, moved);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
}

void AutomationEditingTest::rightBandPreviewIsolated()
{
    const LaneHandle pan = findRow(controlRow(kPanController));
    QVERIFY(pan.valid());
    const QPointF input = inputPoint(pan, 144, 48);
    const FrozenDocumentState frozen = frozenDocumentState();
    const std::vector<int> heightsBefore = laneHeights(page());
    const uint64_t cursorBefore = tab().view().editCursorTick();

    mousePress(Qt::RightButton,
               automation_test::windowFromContent(page(), automationInput(), input));

    QVERIFY(tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);

    mouseMove(
        automation_test::windowFromContent(page(), automationInput(), input + QPointF(20, 0)));
    QTRY_VERIFY(page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);

    keyClick(Qt::Key_Escape);
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!tab().view().userGestureActive());
}

void AutomationEditingTest::pencilEditTargetsOnlyItsLane()
{
    tab().document().writeLanePoints(0, kPanController, 0, (std::numeric_limits<uint64_t>::max)(),
                                     {});
    page().addEmptyLane(0, kPanController);
    QTRY_VERIFY(findRow(controlRow(kPanController)).valid());
    const LaneHandle pan = findRow(controlRow(kPanController));
    setPencilMode(true);
    const AutomationProjection projection(AutomationGeometry::resolve(), &page());
    const AutomationGridCell inputCell = projection.snapCellAt(144.0);
    const double inputTick =
        double(inputCell.tickBegin) + double(inputCell.tickEnd - inputCell.tickBegin) / 2.0;
    const QPointF input = inputPoint(pan, inputTick, 83);
    const QPoint inputWindow = automation_test::windowFromContent(page(), automationInput(), input);
    const QPointF deliveredViewport = automationInput().mapFromScene(QPointF(inputWindow));
    QVERIFY(automationInput().bounds().contains(deliveredViewport));
    const QPointF deliveredContent =
        automation_test::contentFromWindow(page(), automationInput(), inputWindow);
    const AutomationProjection::PointerMapping mapped = pointerMapping(pan, deliveredContent);
    const FrozenDocumentState frozen = frozenDocumentState();
    const std::vector<int> heightsBefore = laneHeights(page());
    const LanePoints lfoBefore = lanePoints(tab().document(), kLfoController);
    const LanePoints volumeBefore = lanePoints(tab().document(), kVolumeController);
    const LanePoints voiceBefore = lanePoints(tab().document(), DOC_CC_VOICE);
    const LanePoints bendBefore = lanePoints(tab().document(), DOC_CC_BEND);
    const std::vector<TempoPoint> tempoBefore = tab().document().tempoPoints();
    const uint64_t cursorBefore = tab().view().editCursorTick();

    mousePress(Qt::LeftButton, inputWindow);

    QVERIFY(tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);

    mouseRelease(Qt::LeftButton, inputWindow);
    DocLanePoint inserted;
    QVERIFY(tab().document().findLanePoint(0, kPanController, mapped.point.tick, &inserted));
    QCOMPARE(inserted.value, mapped.point.value);
    QVERIFY(tab().document().smf().write() != frozen.smf);
    QCOMPARE(tab().document().revision(), frozen.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), frozen.undoIndex + 1);
    QVERIFY(lanePoints(tab().document(), kLfoController) == lfoBefore);
    QVERIFY(lanePoints(tab().document(), kVolumeController) == volumeBefore);
    QVERIFY(lanePoints(tab().document(), DOC_CC_VOICE) == voiceBefore);
    QVERIFY(lanePoints(tab().document(), DOC_CC_BEND) == bendBefore);
    QVERIFY(tab().document().tempoPoints() == tempoBefore);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
}

void AutomationEditingTest::defaultBodyClickSetsCursorOnly()
{
    const LaneHandle pan = findRow(controlRow(kPanController));
    QVERIFY(pan.valid());
    tab().document().writeLanePoints(0, kPanController, 0, (std::numeric_limits<uint64_t>::max)(),
                                     {});
    setPencilMode(false);
    const QPointF input = inputPoint(pan, 384, 41);
    const uint64_t expectedCursor =
        tab().view().grid().snapTick(tab().view().camera().tickAtContentX(input.x()), false);
    const FrozenDocumentState frozen = frozenDocumentState();
    const std::vector<int> heightsBefore = laneHeights(page());
    const uint64_t cursorBefore = tab().view().editCursorTick();
    QVERIFY(expectedCursor != cursorBefore);

    mousePress(Qt::LeftButton,
               automation_test::windowFromContent(page(), automationInput(), input));

    QVERIFY(tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QCOMPARE(tab().view().editCursorTick(), cursorBefore);

    mouseRelease(Qt::LeftButton,
                 automation_test::windowFromContent(page(), automationInput(), input));
    QTRY_COMPARE(tab().view().editCursorTick(), expectedCursor);
    QVERIFY(frozenDocumentState() == frozen);
    QVERIFY(laneHeights(page()) == heightsBefore);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
}

void AutomationEditingTest::firstCcRowOriginRebuildAndUndo()
{
    const auto &rows = page().canvas()->rows();
    QVERIFY(!rows.empty());
    const LaneHandle firstRow{1};
    const QRect firstBody = laneBody(firstRow);
    QVERIFY(!firstBody.isEmpty());
    QCOMPARE(firstBody.top(), 0);
    const EditorAutomationRowId firstRowId = rows.front().id;
    QVERIFY(firstRowId.kind == EditorAutomationRowKind::ControlChange);
    setPencilMode(true);
    const QPointF input = inputPoint(firstRow, 144, 112);
    const QPoint inputWindow = automation_test::windowFromContent(page(), automationInput(), input);
    const QPointF deliveredViewport = automationInput().mapFromScene(QPointF(inputWindow));
    QVERIFY(automationInput().bounds().contains(deliveredViewport));
    const QPointF deliveredContent =
        automation_test::contentFromWindow(page(), automationInput(), inputWindow);
    const AutomationProjection::PointerMapping mapped = pointerMapping(firstRow, deliveredContent);
    const FrozenDocumentState frozen = frozenDocumentState();

    mousePress(Qt::LeftButton, inputWindow);
    mouseRelease(Qt::LeftButton, inputWindow);

    DocLanePoint committed;
    QVERIFY(tab().document().findLanePoint(firstRowId.track, firstRowId.controller,
                                           mapped.point.tick, &committed));
    QCOMPARE(committed.value, mapped.point.value);
    QCOMPARE(tab().document().revision(), frozen.revision + 1);
    QCOMPARE(tab().document().undoStack()->index(), frozen.undoIndex + 1);
    page().documentChanged();
    QTRY_COMPARE(laneBody(firstRow).top(), 0);
    QTRY_VERIFY(!laneBody(firstRow).isEmpty());

    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tab().document().smf().write(), frozen.smf);
    QTRY_COMPARE(laneBody(firstRow).top(), 0);
    QVERIFY(!laneBody(firstRow).isEmpty());
}
