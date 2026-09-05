#include "checks/automation/tst_automationediting.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

#include <QCoreApplication>
#include <QSignalSpy>
#include <QtTest>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelinequickscene.h"

namespace {

constexpr int kTempo = 0;
constexpr int kCc = 1;
constexpr uint8_t kController = 10;
constexpr uint64_t kFirstTick = 0;
constexpr uint64_t kNodeTick = 96;
constexpr uint64_t kMovedTick = 192;
constexpr uint64_t kLateTick = 288;
constexpr uint64_t kLastTick = 384;
constexpr int kFirstValue = 80;
constexpr int kNodeValue = 100;
constexpr int kLowValue = 64;
constexpr int kLateValue = 64;
constexpr int kLastValue = 110;
constexpr uint32_t kPreservedTempoUs = 499999;

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
            edit.add.push_back(
                {point.tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
        }
        if (edit.remove != edit.add)
            document.applyTempoEdit(edit);
        return;
    }

    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const NodePoint &point : points)
        values.push_back({point.tick, point.value});
    document.writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(), values);
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

bool samePoints(const std::vector<NodePoint> &actual, const std::vector<NodePoint> &expected)
{
    return actual.size() == expected.size() &&
           std::equal(actual.cbegin(), actual.cend(), expected.cbegin(),
                      [](const NodePoint &left, const NodePoint &right) {
                          return left.tick == right.tick && left.value == right.value;
                      });
}

QPoint dragEnd(const QPoint &source, const QPoint &target, const QPoint &activation)
{
    return activation + target - source;
}

std::vector<int> rawValuesAt(const SongDocument &document, uint64_t tick)
{
    std::vector<int> values;
    const int track = document.smfTrackFor(0);
    if (track < 0 || track >= int(document.smf().tracks.size()))
        return values;
    for (const SmfEvent &event : document.smf().tracks[std::size_t(track)].events) {
        if (event.tick == tick && (event.status >> 4) == 0xB && event.data0 == kController)
            values.push_back(event.data1);
    }
    return values;
}

struct HorizontalSpan {
    qreal y = 0.0;
    qreal length = 0.0;
};

std::optional<HorizontalSpan> longestHorizontalSpan(const songview::TimelineQuickLayerData &layer)
{
    std::optional<HorizontalSpan> result;
    const qreal tolerance = layout::singlePixel();
    for (const songview::TimelineQuickTriangle &triangle : layer.triangles) {
        const qreal minX = std::min({triangle.first.x(), triangle.second.x(), triangle.third.x()});
        const qreal maxX = std::max({triangle.first.x(), triangle.second.x(), triangle.third.x()});
        const qreal minY = std::min({triangle.first.y(), triangle.second.y(), triangle.third.y()});
        const qreal maxY = std::max({triangle.first.y(), triangle.second.y(), triangle.third.y()});
        const qreal length = maxX - minX;
        if (maxY - minY <= 2.0 * tolerance && length > 0.0 &&
            (!result || length > result->length)) {
            result = HorizontalSpan{(minY + maxY) / 2.0, length};
        }
    }
    return result;
}

} // namespace

void AutomationEditingTest::nodeDragCommits_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::nodeDragCommits()
{
    QFETCH(int, adapter);
    setPoints(m_tab->document(), adapter,
              {{kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}});
    if (adapter == kTempo)
        QVERIFY(expandTempo());
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    const QPoint source = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kNodeTick, kNodeValue));
    const QPoint target = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kMovedTick, kNodeValue));
    const QPoint activation =
        source + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
    const QPoint end = dragEnd(source, target, activation);
    const auto effectiveMapping =
        pointerMapping(lane, automation_test::effectiveDragContent(page(), automationInput(),
                                                                   source, activation, end));
    const uint64_t revision = m_tab->document().revision();
    const int undoIndex = m_tab->document().undoStack()->index();

    mousePress(Qt::LeftButton, source, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    mouseMove(end, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, end, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), revision + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), undoIndex + 1);
    QCOMPARE(effectiveMapping.point.tick, kMovedTick);
    const int movedValue = adapter == kTempo ? effectiveMapping.point.value : kNodeValue;
    const std::vector<NodePoint> expected{
        {kFirstTick, kFirstValue}, {kMovedTick, movedValue}, {kLateTick, kLateValue}};
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter), expected));

    if (adapter == kTempo) {
        TempoEdit edit;
        edit.remove = m_tab->document().tempoPoints();
        edit.add = {{kNodeTick, kPreservedTempoUs},
                    {kLateTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kLateValue)}};
        m_tab->document().applyTempoEdit(edit);
        const int preservedValue = int(std::lround(CoreTimeDefaults::tempoBpm(kPreservedTempoUs)));
        const QPoint fractionalSource = automation_test::windowFromContent(
            page(), automationInput(), inputPoint(lane, kNodeTick, preservedValue));
        const QPoint fractionalTarget = automation_test::windowFromContent(
            page(), automationInput(), inputPoint(lane, kMovedTick, preservedValue));
        const QPoint fractionalActivation =
            fractionalSource +
            QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
        const uint64_t fractionalRevision = m_tab->document().revision();

        mousePress(Qt::LeftButton, fractionalSource, Qt::ShiftModifier);
        mouseMove(fractionalActivation, Qt::ShiftModifier);
        mouseMove(dragEnd(fractionalSource, fractionalTarget, fractionalActivation),
                  Qt::ShiftModifier);
        mouseRelease(Qt::LeftButton,
                     dragEnd(fractionalSource, fractionalTarget, fractionalActivation),
                     Qt::ShiftModifier);

        QCOMPARE(m_tab->document().revision(), fractionalRevision + 1);
        QCOMPARE(m_tab->document().tempoPoints().size(), std::size_t{2});
        QCOMPARE(m_tab->document().tempoPoints().front().tick, kMovedTick);
        QCOMPARE(m_tab->document().tempoPoints().front().microsecondsPerQuarterNote,
                 kPreservedTempoUs);
        return;
    }

    m_tab->document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                      {{kLateTick, 40}});
    SmfEvent first;
    first.tick = kNodeTick;
    first.status = uint8_t((0xB << 4) | (m_tab->document().channelFor(0) & 0x0F));
    first.data0 = kController;
    first.data1 = 10;
    m_tab->document().insertRawEvent(m_tab->document().smfTrackFor(0), first);
    SmfEvent second = first;
    second.data1 = 20;
    m_tab->document().insertRawEvent(m_tab->document().smfTrackFor(0), second);
    const QPoint groupedSource = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kNodeTick, 20));
    const QPoint groupedTarget = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kMovedTick, 20));
    const QPoint groupedActivation =
        groupedSource + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
    const uint64_t groupedRevision = m_tab->document().revision();

    mousePress(Qt::LeftButton, groupedSource, Qt::NoModifier);
    mouseMove(groupedActivation, Qt::NoModifier);
    mouseMove(dragEnd(groupedSource, groupedTarget, groupedActivation), Qt::NoModifier);
    mouseRelease(Qt::LeftButton, dragEnd(groupedSource, groupedTarget, groupedActivation),
                 Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), groupedRevision + 1);
    QVERIFY(rawValuesAt(m_tab->document(), kNodeTick).empty());
    QCOMPARE(rawValuesAt(m_tab->document(), kMovedTick), std::vector<int>({10, 20}));
}

void AutomationEditingTest::nodeDragShiftAxisLocks_data()
{
    QTest::addColumn<int>("adapter");
    QTest::addColumn<bool>("horizontal");
    QTest::newRow("tempo-horizontal") << kTempo << true;
    QTest::newRow("tempo-vertical") << kTempo << false;
    QTest::newRow("cc-horizontal") << kCc << true;
    QTest::newRow("cc-vertical") << kCc << false;
}

void AutomationEditingTest::nodeDragShiftAxisLocks()
{
    QFETCH(int, adapter);
    QFETCH(bool, horizontal);
    setPoints(m_tab->document(), adapter,
              {{kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}});
    if (adapter == kTempo)
        QVERIFY(expandTempo());
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    const QPoint source = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kNodeTick, kNodeValue));
    const QPoint target =
        horizontal ? automation_test::windowFromContent(page(), automationInput(),
                                                        inputPoint(lane, kMovedTick, kLowValue))
                   : automation_test::windowFromContent(page(), automationInput(),
                                                        inputPoint(lane, kNodeTick, kLowValue));
    const QPoint activation =
        horizontal
            ? source + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0)
            : source + QPoint(2, AutomationGeometry::resolve().nodeDragActivationDistance + 2);
    const QPoint end = dragEnd(source, target, activation);
    const uint64_t revision = m_tab->document().revision();

    mousePress(Qt::LeftButton, source, Qt::ShiftModifier);
    mouseMove(activation, Qt::ShiftModifier);
    mouseMove(end, Qt::ShiftModifier);
    mouseRelease(Qt::LeftButton, end, Qt::ShiftModifier);

    QCOMPARE(m_tab->document().revision(), revision + 1);
    if (horizontal) {
        QVERIFY(samePoints(
            pointsOf(m_tab->document(), adapter),
            {{kFirstTick, kFirstValue}, {kMovedTick, kNodeValue}, {kLateTick, kLateValue}}));
    } else {
        QVERIFY(samePoints(
            pointsOf(m_tab->document(), adapter),
            {{kFirstTick, kFirstValue}, {kNodeTick, kLowValue}, {kLateTick, kLateValue}}));
    }
}

void AutomationEditingTest::scrolledOriginPhantomCommits_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::scrolledOriginPhantomCommits()
{
    QFETCH(int, adapter);
    setPoints(m_tab->document(), adapter,
              {{kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}});
    if (adapter == kTempo)
        QVERIFY(expandTempo());
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    m_tab->view().setEditorTimeZoom(96.0);
    const qreal coveredX = inputPoint(lane, kNodeTick, kNodeValue).x();
    m_tab->view().setEditorHorizontalScroll(coveredX +
                                            2.0 * AutomationGeometry::resolve().pointHitRadius);
    const QPointF sourceContent(0.0, inputPoint(lane, kNodeTick, kNodeValue).y());
    const QPointF targetContent(0.0, inputPoint(lane, kNodeTick, 110).y());
    const QPoint source =
        automation_test::windowFromContent(page(), automationInput(), sourceContent);
    const QPoint target =
        automation_test::windowFromContent(page(), automationInput(), targetContent);
    const int armDistance = AutomationGeometry::resolve().nodeDragActivationDistance + 2;
    const QPoint activation =
        source + QPoint(0, target.y() < source.y() ? -armDistance : armDistance);
    const QPoint end = dragEnd(source, target, activation);
    const auto effectiveMapping =
        pointerMapping(lane, automation_test::effectiveDragContent(page(), automationInput(),
                                                                   source, activation, end));
    auto *scene = quickScene();
    QVERIFY(scene);
    const auto beforeLayer = scene->layer(songview::TimelineQuickLayer::AutomationTransient);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    mouseMove(source, Qt::NoModifier);
    QCOMPARE(automationInput().cursor().shape(), Qt::ArrowCursor);
    mousePress(Qt::LeftButton, source, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    const auto originalLayer = scene->layer(songview::TimelineQuickLayer::AutomationTransient);
    mouseMove(end, Qt::NoModifier);
    const auto movedLayer = scene->layer(songview::TimelineQuickLayer::AutomationTransient);
    const std::optional<HorizontalSpan> originalCurve = longestHorizontalSpan(originalLayer);
    const std::optional<HorizontalSpan> movedCurve = longestHorizontalSpan(movedLayer);

    QVERIFY(originalLayer.revision > beforeLayer.revision);
    QVERIFY(movedLayer.revision > originalLayer.revision);
    QVERIFY(originalCurve.has_value());
    QVERIFY(movedCurve.has_value());
    QVERIFY(originalCurve->length > 2.0 * AutomationGeometry::resolve().pointHitRadius);
    QVERIFY(movedCurve->length > 2.0 * AutomationGeometry::resolve().pointHitRadius);
    QVERIFY(std::abs(movedCurve->y - originalCurve->y) > layout::singlePixel() / 2.0);
    QVERIFY((movedCurve->y - originalCurve->y) * (targetContent.y() - sourceContent.y()) > 0.0);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);

    mouseRelease(Qt::LeftButton, end, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), before.revision + 1);
    const int movedValue = adapter == kTempo ? effectiveMapping.point.value : 110;
    const std::vector<NodePoint> expected{
        {kFirstTick, kFirstValue}, {kNodeTick, movedValue}, {kLateTick, kLateValue}};
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter), expected));
}

void AutomationEditingTest::selectedRangeDragAndDelete_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::selectedRangeDragAndDelete()
{
    QFETCH(int, adapter);
    const std::vector<NodePoint> fixture{{kFirstTick, kFirstValue},
                                         {kNodeTick, kNodeValue},
                                         {kMovedTick, kLateValue},
                                         {kLastTick, kLastValue}};
    setPoints(m_tab->document(), adapter, fixture);
    if (adapter == kTempo)
        QVERIFY(expandTempo());
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kNodeTick;
    selection.endTick = kLateTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.tempo = adapter == kTempo;
    if (adapter == kCc)
        selection.lanes = {{0, kController}};
    m_tab->view().selectionModel().setTimeSelection(selection);
    const QPoint source = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kNodeTick, kNodeValue));
    const QPoint target = automation_test::windowFromContent(page(), automationInput(),
                                                             inputPoint(lane, 144, kNodeValue));
    const QPoint activation =
        source + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
    const QPoint end = dragEnd(source, target, activation);
    const auto effectiveMapping =
        pointerMapping(lane, automation_test::effectiveDragContent(page(), automationInput(),
                                                                   source, activation, end));
    const uint64_t revision = m_tab->document().revision();

    mousePress(Qt::LeftButton, source, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    mouseMove(end, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, end, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), revision + 1);
    QCOMPARE(effectiveMapping.point.tick, uint64_t{144});
    const int valueDelta = adapter == kTempo ? effectiveMapping.point.value - kNodeValue : 0;
    const std::vector<NodePoint> expected{{kFirstTick, kFirstValue},
                                          {144, kNodeValue + valueDelta},
                                          {240, kLateValue + valueDelta},
                                          {kLastTick, kLastValue}};
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter), expected));
    QCOMPARE(m_tab->view().selectionModel().timeSelection().startTick, uint64_t{144});
    QCOMPARE(m_tab->view().selectionModel().timeSelection().endTick, uint64_t{336});

    setPoints(m_tab->document(), adapter, fixture);
    m_tab->view().selectionModel().setTimeSelection(selection);
    const uint64_t deleteRevision = m_tab->document().revision();
    const int deleteUndo = m_tab->document().undoStack()->index();
    keyClick(Qt::Key_Delete, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), deleteRevision + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), deleteUndo + 1);
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter),
                       {{kFirstTick, kFirstValue}, {kLastTick, kLastValue}}));
}

void AutomationEditingTest::escapeCancelsAdapterDrag_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::escapeCancelsAdapterDrag()
{
    QFETCH(int, adapter);
    setPoints(m_tab->document(), adapter,
              {{kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}});
    if (adapter == kTempo)
        QVERIFY(expandTempo());
    const LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    const QPoint source = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kNodeTick, kNodeValue));
    const QPoint target = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kMovedTick, kLowValue));
    const QPoint activation =
        source + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
    const QPoint end = dragEnd(source, target, activation);
    auto *scene = quickScene();
    QVERIFY(scene);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(Qt::LeftButton, source, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    mouseMove(end, Qt::NoModifier);
    QTRY_VERIFY(!scene->layer(songview::TimelineQuickLayer::AutomationTransient).triangles.empty());
    keyClick(Qt::Key_Escape, Qt::NoModifier);

    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).triangles.empty());
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).rects.empty());
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
    mouseMove(end, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, end, Qt::NoModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::rebuildCancelsAdapterDragAndRecovers_data()
{
    QTest::addColumn<int>("adapter");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationEditingTest::rebuildCancelsAdapterDragAndRecovers()
{
    QFETCH(int, adapter);
    const std::vector<NodePoint> fixture{
        {kFirstTick, kFirstValue}, {kNodeTick, kNodeValue}, {kLateTick, kLateValue}};
    setPoints(m_tab->document(), adapter, fixture);
    if (adapter == kTempo)
        QVERIFY(expandTempo());
    LaneHandle lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    QPoint source = automation_test::windowFromContent(page(), automationInput(),
                                                       inputPoint(lane, kNodeTick, kNodeValue));
    QPoint activation =
        source + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);

    mousePress(Qt::LeftButton, source, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    m_tab->document().writeLanePoints(0, 11, 0, std::numeric_limits<uint64_t>::max(), {{0, 1}});
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState rebuilt =
        frozenDocumentState(documentChanged.count(), edited.count());
    mouseRelease(Qt::LeftButton, activation, Qt::NoModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == rebuilt);

    lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    source = automation_test::windowFromContent(page(), automationInput(),
                                                inputPoint(lane, kNodeTick, kNodeValue));
    activation = source + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
    mousePress(Qt::LeftButton, source, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    m_tab->resize(m_tab->width() + 48, m_tab->height());
    QCoreApplication::processEvents();
    mouseRelease(Qt::LeftButton, activation, Qt::NoModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == rebuilt);
    QVERIFY(!m_page->canvas()->bandPreviewContainsLane(findRow(rowId(adapter))));

    lane = findRow(rowId(adapter));
    QVERIFY(lane.valid());
    source = automation_test::windowFromContent(page(), automationInput(),
                                                inputPoint(lane, kNodeTick, kNodeValue));
    const QPoint target = automation_test::windowFromContent(
        page(), automationInput(), inputPoint(lane, kMovedTick, kNodeValue));
    activation = source + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
    const QPoint end = dragEnd(source, target, activation);
    const auto effectiveMapping =
        pointerMapping(lane, automation_test::effectiveDragContent(page(), automationInput(),
                                                                   source, activation, end));
    const uint64_t recoveryRevision = m_tab->document().revision();
    mousePress(Qt::LeftButton, source, Qt::NoModifier);
    mouseMove(activation, Qt::NoModifier);
    mouseMove(end, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, end, Qt::NoModifier);

    QCOMPARE(m_tab->document().revision(), recoveryRevision + 1);
    QCOMPARE(effectiveMapping.point.tick, kMovedTick);
    const int movedValue = adapter == kTempo ? effectiveMapping.point.value : kNodeValue;
    const std::vector<NodePoint> expected{
        {kFirstTick, kFirstValue}, {kMovedTick, movedValue}, {kLateTick, kLateValue}};
    QVERIFY(samePoints(pointsOf(m_tab->document(), adapter), expected));
}
