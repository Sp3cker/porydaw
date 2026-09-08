#include "checks/automation/tst_automationediting.h"

#include <QtTest>
#include <cmath>
#include <optional>

#include <variant>
#include <vector>

#include <QCoreApplication>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelinequickscene.h"
#include <algorithm>
#include <limits>
Q_DECLARE_METATYPE(songview::GridSelection)
Q_DECLARE_METATYPE(std::optional<uint64_t>)

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kPanController = 10;
constexpr uint8_t kExpressionController = 11;

struct PencilPoint {
    QPointF content;
    QPoint window;
    AutomationProjection::PointerMapping mapping;
};

// Pencil endpoints commit against the editing grid, never the camera zoom;
// kPencilTimeZoom keeps the historical view for callers that do not vary it.
constexpr double kPencilTimeZoom = 96.0;

void resetPencilView(SongView &view, double timeZoom = kPencilTimeZoom)
{
    view.setEditorTimeZoom(timeZoom);
    view.setEditorHorizontalScroll(0.0);
    QCoreApplication::processEvents();
}

PencilPoint pencilPoint(SongView &view, AutomationPage &page, songview::TimelineInputItem &input,
                        const NodeLane &lane, LaneHandle handle, uint64_t tick, int value)
{
    AutomationCanvas *const canvas = page.canvas();
    const QRect body = canvas ? canvas->laneBody(handle) : QRect{};
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const QPointF intended(view.camera().displayX(double(tick), 0.0, input.devicePixelRatio()),
                           AutomationProjection::valueY(body, geometry, lane.minimumValue(),
                                                        lane.maximumValue(), value));
    const QPoint window = automation_test::windowFromContent(page, input, intended);
    const QPointF content = automation_test::contentFromWindow(page, input, window);
    const AutomationProjection projection(geometry, &page);
    return {content, window, projection.pointerMapping(lane, body, content.x(), content.y())};
}

PencilPoint pencilPointInCell(SongView &view, AutomationPage &page,
                              songview::TimelineInputItem &input, const NodeLane &lane,
                              LaneHandle handle, uint64_t tick, int value)
{
    const PencilPoint probe = pencilPoint(view, page, input, lane, handle, tick, value);
    const AutomationGridCell &cell = probe.mapping.cell;
    if (cell.tickBegin <= tick && tick < cell.tickEnd)
        return pencilPoint(view, page, input, lane, handle,
                           double(cell.tickBegin) + double(cell.tickEnd - cell.tickBegin) / 2.0,
                           value);
    // Narrow zooms round neighbouring cell boundaries onto shared window
    // pixels, so a boundary probe can land one cell early; scan a few window
    // offsets for a delivery that reaches the cell containing the requested
    // tick (the ownership detail-threshold test uses the same strategy).
    const AutomationProjection projection(AutomationGeometry::resolve(), &page);
    const QRect body = page.canvas() ? page.canvas()->laneBody(handle) : QRect{};
    for (const int offset : {1, -1, 2, -2, 3, -3}) {
        const QPoint candidate = probe.window + QPoint(offset, 0);
        if (!input.bounds().contains(input.mapFromScene(QPointF(candidate))))
            continue;
        const QPointF content = automation_test::contentFromWindow(page, input, candidate);
        const AutomationProjection::PointerMapping mapping =
            projection.pointerMapping(lane, body, content.x(), content.y());
        if (mapping.cell.tickBegin <= tick && tick < mapping.cell.tickEnd)
            return pencilPoint(view, page, input, lane, handle,
                               double(mapping.cell.tickBegin) +
                                   double(mapping.cell.tickEnd - mapping.cell.tickBegin) / 2.0,
                               value);
    }
    return probe;
}

PencilPoint nextCellPoint(SongView &view, AutomationPage &page, songview::TimelineInputItem &input,
                          const NodeLane &lane, LaneHandle handle, const PencilPoint &point,
                          int value)
{
    return pencilPointInCell(view, page, input, lane, handle, point.mapping.cell.tickEnd, value);
}

bool containsPoint(const std::vector<DocLanePoint> &points, uint64_t tick, int value)
{
    return std::any_of(points.cbegin(), points.cend(), [tick, value](const DocLanePoint &point) {
        return point.tick == tick && point.value == value;
    });
}

bool containsPointWithin(const std::vector<DocLanePoint> &points, uint64_t tick, int value,
                         int tolerance)
{
    return std::any_of(points.cbegin(), points.cend(),
                       [tick, value, tolerance](const DocLanePoint &point) {
                           return point.tick == tick && std::abs(point.value - value) <= tolerance;
                       });
}

int timelineControllerValue(const MidiTimeline &timeline, uint8_t controller, uint64_t tick)
{
    for (const TimelineEvent &event : timeline.events) {
        if (event.type == 0xB && event.track == kTrack && event.tick == tick &&
            event.data0 == controller) {
            return event.data1;
        }
    }
    return -1;
}

} // namespace

void AutomationEditingTest::pencilStrokeOnEmptyLaneCommitsOnce_data()
{
    QTest::addColumn<songview::GridSelection>("selection");
    QTest::addColumn<uint64_t>("paintedTick");
    QTest::addColumn<uint64_t>("expectedEndTick");
    QTest::addColumn<double>("timeZoom");
    // The six-tick rows straddle the grid-guide detail threshold from the
    // fixedEditingAndAdaptiveGuides oracle: below 4*cell the displayed guides
    // merge to 12-tick spacing, at 4*cell they match the six-tick cells, and
    // the pencil must still commit 48, 54 and 60 at both zooms.
    const double cell = double(layout::fontPx(4.0 / 3.0));
    QTest::newRow("fixed6/guides-coarse")
        << songview::GridSelection::musical(16) << 48ULL << 60ULL << 4.0 * cell - 1.0;
    QTest::newRow("fixed6/guides-fine")
        << songview::GridSelection::musical(16) << 48ULL << 60ULL << 4.0 * cell;
    QTest::newRow("clock") << songview::GridSelection::clock() << 48ULL << 50ULL << kPencilTimeZoom;
}

void AutomationEditingTest::pencilStrokeOnEmptyLaneCommitsOnce()
{
    QFETCH(songview::GridSelection, selection);
    QFETCH(uint64_t, paintedTick);
    QFETCH(double, timeZoom);
    QFETCH(uint64_t, expectedEndTick);
    // Independent editing-cell literals, not point.mapping.cell reads: at the
    // selected six ticks the stroke paints the cells beginning at 48, 54 and
    // 60; at Clock 48, 49 and 50.
    selectEditingGrid(selection);
    AutomationPage &page = *m_page;
    AutomationCanvas &canvas = *page.canvas();
    SongDocument &document = m_tab->document();
    resetPencilView(m_tab->view(), timeZoom);
    page.addEmptyLane(kTrack, kExpressionController);

    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, kTrack,
                                    kExpressionController};
    const LaneHandle handle = findRow(row);
    QVERIFY(handle.valid());
    setRowMaximumHeight(row);
    QTRY_VERIFY(!canvas.laneBody(findRow(row)).isEmpty());

    CCLaneAdapter lane(document, kTrack, kExpressionController);
    const PencilPoint start = pencilPointInCell(m_tab->view(), page, *m_automationInput, lane,
                                                findRow(row), paintedTick, 40);
    const PencilPoint middle =
        nextCellPoint(m_tab->view(), page, *m_automationInput, lane, findRow(row), start, 72);
    const PencilPoint end =
        nextCellPoint(m_tab->view(), page, *m_automationInput, lane, findRow(row), middle, 96);
    QVERIFY(m_automationInput->bounds().contains(
        m_automationInput->mapFromScene(QPointF(start.window))));
    QVERIFY(
        m_automationInput->bounds().contains(m_automationInput->mapFromScene(QPointF(end.window))));

    setPencilMode(true);
    QSignalSpy documentChanged(&document, &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(Qt::LeftButton, start.window, Qt::NoModifier);
    mouseMove(middle.window, Qt::NoModifier);
    mouseMove(end.window, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, end.window, Qt::NoModifier);

    QCOMPARE(documentChanged.count(), before.documentChanges + 1);
    QCOMPARE(edited.count(), before.edits + 1);
    QCOMPARE(document.revision(), before.revision + 1);
    QCOMPARE(document.undoStack()->count(), before.undoCount + 1);
    QCOMPARE(document.undoStack()->index(), before.undoIndex + 1);
    QVERIFY(document.smf().write() != before.smf);
    const std::vector<DocLanePoint> committed = document.lanePoints(kTrack, kExpressionController);
    QVERIFY(!committed.empty());
    QVERIFY(containsPoint(committed, paintedTick, start.mapping.point.value));
    QVERIFY(containsPointWithin(committed, expectedEndTick, end.mapping.point.value, 1));
    QTRY_VERIFY(std::abs(timelineControllerValue(*m_tab->timeline(), kExpressionController,
                                                 expectedEndTick) -
                         end.mapping.point.value) <= 1);

    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(m_tab->history().requestUndo()));
    QVERIFY(document.lanePoints(kTrack, kExpressionController).empty());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(m_tab->history().requestRedo()));
    QVERIFY(!document.lanePoints(kTrack, kExpressionController).empty());
}

void AutomationEditingTest::pencilPreviewDoesNotMutateUntilRelease()
{
    AutomationPage &page = *m_page;
    SongDocument &document = m_tab->document();
    CCLaneAdapter lane(document, kTrack, kPanController);
    const LaneHandle handle =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    const PencilPoint start =
        pencilPoint(m_tab->view(), page, *m_automationInput, lane, handle, 48, 28);
    const PencilPoint end =
        nextCellPoint(m_tab->view(), page, *m_automationInput, lane, handle, start, 104);
    auto *quickScene = m_tab->view().findChild<songview::TimelineQuickScene *>();
    QVERIFY(quickScene);

    setPencilMode(true);
    QSignalSpy documentChanged(&document, &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    const quint64 transientBefore =
        quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;

    mousePress(Qt::LeftButton, start.window, Qt::NoModifier);
    mouseMove(end.window, Qt::NoModifier);

    QTRY_VERIFY(quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                transientBefore);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
    QCOMPARE(laneValue(48), 40);
    QCOMPARE(laneValue(96), 100);

    mouseRelease(Qt::LeftButton, end.window, Qt::NoModifier);
    QCOMPARE(documentChanged.count(), before.documentChanges + 1);
    QCOMPARE(edited.count(), before.edits + 1);
    QCOMPARE(document.revision(), before.revision + 1);
    QCOMPARE(document.undoStack()->index(), before.undoIndex + 1);
    QVERIFY(document.smf().write() != before.smf);
}

void AutomationEditingTest::pencilStrokeRestoresHeldEndpointValue()
{
    AutomationPage &page = *m_page;
    SongDocument &document = m_tab->document();
    resetPencilView(m_tab->view());
    CCLaneAdapter lane(document, kTrack, kPanController);
    LaneHandle handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    const PencilPoint baselineProbe =
        pencilPointInCell(m_tab->view(), page, *m_automationInput, lane, handle, 96, 72);
    const int baseline = baselineProbe.mapping.point.value;
    document.writeLanePoints(kTrack, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, baseline}});
    QTRY_COMPARE(laneValue(0), baseline);
    handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());

    setPencilMode(true);
    const PencilPoint start =
        pencilPointInCell(m_tab->view(), page, *m_automationInput, lane, handle, 96, 28);
    const PencilPoint end =
        nextCellPoint(m_tab->view(), page, *m_automationInput, lane, handle, start, 104);
    const FrozenDocumentState before = frozenDocumentState(0, 0);
    mousePress(Qt::LeftButton, start.window, Qt::NoModifier);
    mouseMove(end.window, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, end.window, Qt::NoModifier);

    DocLanePoint restored;
    QVERIFY(document.findLanePoint(kTrack, kPanController, end.mapping.cell.tickEnd, &restored));
    QCOMPARE(restored.value, baseline);
    QCOMPARE(document.revision(), before.revision + 1);
    QCOMPARE(document.undoStack()->index(), before.undoIndex + 1);
    QVERIFY(document.smf().write() != before.smf);
    QTRY_COMPARE(
        timelineControllerValue(*m_tab->timeline(), kPanController, end.mapping.cell.tickEnd),
        baseline);
}

void AutomationEditingTest::pencilSingleClickOnTempoLaneRestoresDefaultTempoAtCellEnd_data()
{
    QTest::addColumn<songview::GridSelection>("selection");
    QTest::addColumn<uint64_t>("paintedTick");
    QTest::addColumn<uint64_t>("restoredTick");
    QTest::addColumn<std::optional<uint64_t>>("signatureTick");
    QTest::addColumn<double>("timeZoom");
    // Same grid-guide straddle as the stroke table; the clock and signature
    // cells stay single-zoom partial cases.
    const double cell = double(layout::fontPx(4.0 / 3.0));
    QTest::newRow("fixed6/guides-coarse") << songview::GridSelection::musical(16) << 48ULL << 54ULL
                                          << std::optional<uint64_t>{} << 4.0 * cell - 1.0;
    QTest::newRow("fixed6/guides-fine") << songview::GridSelection::musical(16) << 48ULL << 54ULL
                                        << std::optional<uint64_t>{} << 4.0 * cell;
    QTest::newRow("clock") << songview::GridSelection::clock() << 48ULL << 49ULL
                           << std::optional<uint64_t>{} << kPencilTimeZoom;
    QTest::newRow("signature61") << songview::GridSelection::musical(16) << 60ULL << 61ULL
                                 << std::optional<uint64_t>{61} << kPencilTimeZoom;
}

void AutomationEditingTest::pencilSingleClickOnTempoLaneRestoresDefaultTempoAtCellEnd()
{
    QFETCH(songview::GridSelection, selection);
    QFETCH(uint64_t, paintedTick);
    QFETCH(uint64_t, restoredTick);
    QFETCH(double, timeZoom);
    QFETCH(std::optional<uint64_t>, signatureTick);
    // Independent table oracles cover the fixed six-tick cell, the clock
    // cell, and the cell split by the signature change at tick 61.
    selectEditingGrid(selection);
    AutomationPage &page = *m_page;
    SongDocument &document = m_tab->document();
    if (signatureTick)
        document.setTimeSig(*signatureTick, 4, 2);
    resetPencilView(m_tab->view(), timeZoom);
    if (!document.tempoPoints().empty())
        document.applyTempoEdit({document.tempoPoints(), {}});
    QCoreApplication::processEvents();
    QVERIFY(expandTempo());

    const LaneHandle handle = findRow({EditorAutomationRowKind::Tempo, 0, 0});
    QVERIFY(handle.valid());
    TempoLane lane(document);
    const PencilPoint point =
        pencilPointInCell(m_tab->view(), page, *m_automationInput, lane, handle, paintedTick, 200);
    setPencilMode(true);
    const FrozenDocumentState before = frozenDocumentState(0, 0);
    mousePress(Qt::LeftButton, point.window, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, point.window, Qt::NoModifier);

    const auto &points = document.tempoPoints();
    const auto painted = std::find_if(
        points.cbegin(), points.cend(), [&point, paintedTick](const TempoPoint &tempo) {
            return tempo.tick == paintedTick &&
                   tempo.microsecondsPerQuarterNote ==
                       CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(
                           point.mapping.point.value);
        });
    const auto restored =
        std::find_if(points.cbegin(), points.cend(), [restoredTick](const TempoPoint &tempo) {
            return tempo.tick == restoredTick &&
                   tempo.microsecondsPerQuarterNote ==
                       CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(
                           CoreTimeDefaults::kTempoBpm);
        });
    QCOMPARE(points.size(), std::size_t{2});
    QVERIFY(painted != points.cend());
    QVERIFY(restored != points.cend());
    QCOMPARE(document.revision(), before.revision + 1);
    QCOMPARE(document.undoStack()->index(), before.undoIndex + 1);
}

void AutomationEditingTest::pencilSingleClickOnPitchBendLaneRestoresCenterAtCellEnd_data()
{
    QTest::addColumn<songview::GridSelection>("selection");
    QTest::addColumn<uint64_t>("paintedTick");
    QTest::addColumn<uint64_t>("restoredTick");
    QTest::addColumn<double>("timeZoom");
    // Same grid-guide straddle as the stroke table; the clock cell stays a
    // single-zoom partial case.
    const double cell = double(layout::fontPx(4.0 / 3.0));
    QTest::newRow("fixed6/guides-coarse")
        << songview::GridSelection::musical(16) << 48ULL << 54ULL << 4.0 * cell - 1.0;
    QTest::newRow("fixed6/guides-fine")
        << songview::GridSelection::musical(16) << 48ULL << 54ULL << 4.0 * cell;
    QTest::newRow("clock") << songview::GridSelection::clock() << 48ULL << 49ULL << kPencilTimeZoom;
}

void AutomationEditingTest::pencilSingleClickOnPitchBendLaneRestoresCenterAtCellEnd()
{
    QFETCH(songview::GridSelection, selection);
    QFETCH(uint64_t, paintedTick);
    QFETCH(double, timeZoom);
    QFETCH(uint64_t, restoredTick);
    // Independent table oracles cover the fixed six-tick and clock cells.
    selectEditingGrid(selection);
    AutomationPage &page = *m_page;
    AutomationCanvas &canvas = *page.canvas();
    SongDocument &document = m_tab->document();
    resetPencilView(m_tab->view(), timeZoom);
    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, kTrack, DOC_CC_BEND};
    document.writeLanePoints(kTrack, DOC_CC_BEND, 0, std::numeric_limits<uint64_t>::max(), {});
    const LaneHandle handle = findRow(row);
    QVERIFY(handle.valid());
    setRowMaximumHeight(row);
    QTRY_VERIFY(!canvas.laneBody(findRow(row)).isEmpty());

    CCLaneAdapter lane(document, kTrack, DOC_CC_BEND);
    const PencilPoint point = pencilPointInCell(m_tab->view(), page, *m_automationInput, lane,
                                                findRow(row), paintedTick, 4096);
    setPencilMode(true);
    const FrozenDocumentState before = frozenDocumentState(0, 0);
    mousePress(Qt::LeftButton, point.window, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, point.window, Qt::NoModifier);

    const std::vector<DocLanePoint> points = document.lanePoints(kTrack, DOC_CC_BEND);
    QCOMPARE(points.size(), std::size_t{2});
    QVERIFY(containsPoint(points, paintedTick, point.mapping.point.value));
    QVERIFY(containsPoint(points, restoredTick, 0));
    QCOMPARE(document.revision(), before.revision + 1);
    QCOMPARE(document.undoStack()->index(), before.undoIndex + 1);
}

void AutomationEditingTest::pencilFlatStrokeAndRedundantClickAreNoOps()
{
    AutomationPage &page = *m_page;
    SongDocument &document = m_tab->document();
    CCLaneAdapter lane(document, kTrack, kPanController);
    LaneHandle handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    const PencilPoint probe =
        pencilPoint(m_tab->view(), page, *m_automationInput, lane, handle, 144, 60);
    document.writeLanePoints(kTrack, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, probe.mapping.point.value}});
    handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    setPencilMode(true);
    const PencilPoint start = pencilPoint(m_tab->view(), page, *m_automationInput, lane, handle,
                                          144, probe.mapping.point.value);
    const PencilPoint end = nextCellPoint(m_tab->view(), page, *m_automationInput, lane, handle,
                                          start, probe.mapping.point.value);

    const FrozenDocumentState strokeBefore = frozenDocumentState(0, 0);
    mousePress(Qt::LeftButton, start.window, Qt::NoModifier);
    mouseMove(end.window, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, end.window, Qt::NoModifier);
    QVERIFY(frozenDocumentState(0, 0) == strokeBefore);

    const FrozenDocumentState clickBefore = frozenDocumentState(0, 0);
    mousePress(Qt::LeftButton, start.window, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, start.window, Qt::NoModifier);
    QVERIFY(frozenDocumentState(0, 0) == clickBefore);
}

void AutomationEditingTest::pencilClickOnExcursionNodeDeletesExcursion()
{
    AutomationPage &page = *m_page;
    SongDocument &document = m_tab->document();
    resetPencilView(m_tab->view());
    CCLaneAdapter lane(document, kTrack, kPanController);
    LaneHandle handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    PencilPoint deletionPoint =
        pencilPointInCell(m_tab->view(), page, *m_automationInput, lane, handle, 144, 60);
    const int baseline = deletionPoint.mapping.point.value;
    const int excursion = baseline < 64 ? baseline + 32 : baseline - 32;
    document.writeLanePoints(kTrack, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, baseline},
                              {deletionPoint.mapping.cell.tickBegin, excursion},
                              {deletionPoint.mapping.cell.tickEnd, baseline}});
    handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    deletionPoint =
        pencilPointInCell(m_tab->view(), page, *m_automationInput, lane, handle, 144, baseline);
    setPencilMode(true);
    const FrozenDocumentState before = frozenDocumentState(0, 0);

    mousePress(Qt::LeftButton, deletionPoint.window, Qt::NoModifier);
    mouseRelease(Qt::LeftButton, deletionPoint.window, Qt::NoModifier);

    const std::vector<DocLanePoint> after = document.lanePoints(kTrack, kPanController);
    QCOMPARE(after.size(), std::size_t{1});
    QCOMPARE(after.front().tick, uint64_t{0});
    QCOMPARE(after.front().value, baseline);
    QCOMPARE(document.revision(), before.revision + 1);
    QCOMPARE(document.undoStack()->index(), before.undoIndex + 1);
}

void AutomationEditingTest::pencilCancellationRoutesAbortGestureWithoutCommit_data()
{
    QTest::addColumn<int>("route");
    QTest::newRow("escape") << 0;
    QTest::newRow("hide") << 1;
    QTest::newRow("deactivate") << 2;
    QTest::newRow("external-document-change") << 3;
}

void AutomationEditingTest::pencilCancellationRoutesAbortGestureWithoutCommit()
{
    QFETCH(int, route);
    AutomationPage &page = *m_page;
    SongDocument &document = m_tab->document();
    CCLaneAdapter lane(document, kTrack, kPanController);
    LaneHandle handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    document.writeLanePoints(kTrack, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, 36}});
    handle = findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(handle.valid());
    setPencilMode(true);
    const PencilPoint start =
        pencilPoint(m_tab->view(), page, *m_automationInput, lane, handle, 144, 28);
    const PencilPoint end =
        nextCellPoint(m_tab->view(), page, *m_automationInput, lane, handle, start, 100);
    mousePress(Qt::LeftButton, start.window, Qt::NoModifier);
    mouseMove(end.window, Qt::NoModifier);

    if (route == 0) {
        keyClick(Qt::Key_Escape);
    } else if (route == 1) {
        m_tab->view().hide();
        QCoreApplication::processEvents();
        m_tab->view().show();
    } else if (route == 2) {
        sendWindowDeactivate();
    } else {
        document.writeLanePoints(kTrack, kExpressionController, 0,
                                 std::numeric_limits<uint64_t>::max(), {{0, 48}});
    }
    const FrozenDocumentState afterCancellation = frozenDocumentState(0, 0);
    mouseRelease(Qt::LeftButton, end.window, Qt::NoModifier);

    QVERIFY(frozenDocumentState(0, 0) == afterCancellation);
    QCOMPARE(laneValue(0), 36);
}
