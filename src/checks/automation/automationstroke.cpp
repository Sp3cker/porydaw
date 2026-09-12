#include "checks/automation/tst_automationediting.h"

#include <QtTest>
#include <cstddef>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

#include <QCoreApplication>
#include <QMouseEvent>
#include <QQuickWindow>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kPanController = 10;

using LanePoints = std::vector<std::pair<Tick, int>>;

struct StrokePoint {
    QPointF content;
    QPoint window;
    AutomationProjection::PointerMapping mapping;
};

struct ShiftCapture {
    LanePoints points;
    StrokePoint middle;
    StrokePoint end;
};

struct ControlCapture {
    LanePoints points;
    StrokePoint turn;
    StrokePoint finish;
};

EditorAutomationRowId panRow()
{
    return {EditorAutomationRowKind::ControlChange, kTrack, kPanController};
}

void resetPencilView(SongView &view, double zoom = 96.0)
{
    view.setEditorTimeZoom(zoom);
    view.setEditorHorizontalScroll(0.0);
    QCoreApplication::processEvents();
}

void stageEmptyPanLane(SongDocument &document)
{
    document.writeLanePoints(kTrack, kPanController, 0, CoreTimeDefaults::kNoTick, {});
    QCoreApplication::processEvents();
}

StrokePoint strokePoint(SongView &view, SongDocument &document, AutomationPage &page,
                        songview::TimelineInputItem &input, LaneHandle handle, double tick,
                        int value)
{
    CCLaneAdapter lane(document, kTrack, kPanController);
    const QRect body = page.canvas()->laneBody(handle);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const QPointF intended(view.camera().displayX(tick, 0.0, input.devicePixelRatio()),
                           AutomationProjection::valueY(body, geometry, lane.minimumValue(),
                                                        lane.maximumValue(), value));
    const QPoint window = automation_test::windowFromContent(page, input, intended);
    const QPointF content = automation_test::contentFromWindow(page, input, window);
    return {
        content, window,
        AutomationProjection(geometry, &page).pointerMapping(lane, body, content.x(), content.y())};
}

StrokePoint strokePointInCell(SongView &view, SongDocument &document, AutomationPage &page,
                              songview::TimelineInputItem &input, LaneHandle handle, double tick,
                              int value)
{
    const StrokePoint probe = strokePoint(view, document, page, input, handle, tick, value);
    const AutomationGridCell &cell = probe.mapping.cell;
    const double midpoint = double(cell.tickBegin) + double(cell.tickEnd - cell.tickBegin) / 2.0;
    return strokePoint(view, document, page, input, handle, midpoint, value);
}

StrokePoint nextCellPoint(SongView &view, SongDocument &document, AutomationPage &page,
                          songview::TimelineInputItem &input, LaneHandle handle,
                          const StrokePoint &point, int value)
{
    return strokePointInCell(view, document, page, input, handle, point.mapping.cell.tickEnd,
                             value);
}

LanePoints lanePoints(const SongDocument &document)
{
    LanePoints points;
    for (const DocLanePoint &point : document.lanePoints(kTrack, kPanController))
        points.emplace_back(point.tick, point.value);
    return points;
}

bool pointValue(const LanePoints &points, Tick tick, int *value)
{
    const auto found = std::find_if(points.cbegin(), points.cend(),
                                    [tick](const auto &point) { return point.first == tick; });
    if (found == points.cend())
        return false;
    *value = found->second;
    return true;
}

bool heldValue(const LanePoints &points, Tick tick, int *value)
{
    const auto next =
        std::upper_bound(points.cbegin(), points.cend(), tick,
                         [](Tick candidate, const auto &point) { return candidate < point.first; });
    if (next == points.cbegin())
        return false;
    *value = std::prev(next)->second;
    return true;
}

bool containsInteriorPoint(const LanePoints &points, Tick first, Tick last)
{
    return std::any_of(points.cbegin(), points.cend(), [first, last](const auto &point) {
        return point.first > first && point.first < last;
    });
}

} // namespace

void AutomationEditingTest::pencilSubCellHorizontalJitterDoesNotAlterStroke()
{
    SongDocument &document = tab().document();
    AutomationCanvas &canvas = *page().canvas();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const LaneHandle handle = findRow(panRow());
    setPencilMode(true);
    const auto point = [this, &document, handle](double tick, int value) {
        return strokePointInCell(tab().view(), document, page(), automationInput(), handle, tick,
                                 value);
    };
    const StrokePoint start = point(36, 48);
    const StrokePoint second =
        nextCellPoint(tab().view(), document, page(), automationInput(), handle, start, 48);
    const StrokePoint third =
        nextCellPoint(tab().view(), document, page(), automationInput(), handle, second, 48);
    const int slop = AutomationGeometry::resolve().nodeDragActivationDistance - 1;
    QVERIFY(slop > 0);
    QVERIFY(canvas.pencilMode());

    mousePress(Qt::LeftButton, start.window);
    mouseMove(start.window + QPoint(slop, 0));
    mouseMove(third.window);
    mouseRelease(Qt::LeftButton, third.window);

    const LanePoints points = lanePoints(document);
    int firstValue = -1;
    int secondValue = -1;
    int thirdValue = -1;
    QVERIFY(heldValue(points, start.mapping.cell.tickBegin, &firstValue));
    QVERIFY(heldValue(points, second.mapping.cell.tickBegin, &secondValue));
    QVERIFY(heldValue(points, third.mapping.cell.tickBegin, &thirdValue));
    QCOMPARE(firstValue, start.mapping.point.value);
    QCOMPARE(secondValue, start.mapping.point.value);
    QCOMPARE(thirdValue, start.mapping.point.value);
}

void AutomationEditingTest::pencilZigzagStrokePreservesDirectionalExtrema()
{
    SongDocument &document = tab().document();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const LaneHandle handle = findRow(panRow());
    setPencilMode(true);
    const auto point = [this, &document, handle](double tick, int value) {
        return strokePointInCell(tab().view(), document, page(), automationInput(), handle, tick,
                                 value);
    };
    const std::array<int, 6> values{32, 100, 28, 92, 44, 84};
    std::array<StrokePoint, 6> stroke{};
    stroke.front() = point(36, values.front());
    for (std::size_t index = 1; index < stroke.size(); ++index)
        stroke[index] = nextCellPoint(tab().view(), document, page(), automationInput(), handle,
                                      stroke[index - 1], values[index]);

    mousePress(Qt::LeftButton, stroke.front().window);
    for (std::size_t index = 1; index < stroke.size(); ++index)
        mouseMove(stroke[index].window);
    mouseRelease(Qt::LeftButton, stroke.back().window);

    const LanePoints points = lanePoints(document);
    std::array<int, 6> actual{};
    for (std::size_t index = 0; index < stroke.size(); ++index) {
        QVERIFY(heldValue(points, stroke[index].mapping.cell.tickBegin, &actual[index]));
        QVERIFY(std::abs(actual[index] - stroke[index].mapping.point.value) <= 1);
    }
    QVERIFY(actual[0] < actual[1]);
    QVERIFY(actual[1] > actual[2]);
    QVERIFY(actual[2] < actual[3]);
    QVERIFY(actual[3] > actual[4]);
    QVERIFY(actual[4] < actual[5]);
}

void AutomationEditingTest::pencilVerticalMotionInSingleCellRetainsFinalValue()
{
    SongDocument &document = tab().document();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const LaneHandle handle = findRow(panRow());
    setPencilMode(true);
    const auto point = [this, &document, handle](double tick, int value) {
        return strokePointInCell(tab().view(), document, page(), automationInput(), handle, tick,
                                 value);
    };
    const StrokePoint start = point(48, 32);
    const StrokePoint end = point(start.mapping.cell.tickBegin, 96);
    QCOMPARE(start.mapping.cell.tickBegin, end.mapping.cell.tickBegin);

    mousePress(Qt::LeftButton, start.window);
    mouseMove(end.window);
    mouseRelease(Qt::LeftButton, end.window);

    int value = -1;
    QVERIFY(pointValue(lanePoints(document), start.mapping.cell.tickBegin, &value));
    QVERIFY(std::abs(value - end.mapping.point.value) <= 1);
}

void AutomationEditingTest::pencilDiagonalStrokeEventDensityInvariance_data()
{
    QTest::addColumn<double>("zoom");
    QTest::addColumn<bool>("canonical");
    QTest::newRow("96 pixels-per-beat") << 96.0 << false;
    QTest::newRow("256 pixels-per-beat") << 256.0 << false;
    QTest::newRow("512 pixels-per-beat") << 512.0 << false;
    QTest::newRow("canonical 96 staircase") << 96.0 << true;
}

void AutomationEditingTest::pencilDiagonalStrokeEventDensityInvariance()
{
    QFETCH(double, zoom);
    QFETCH(bool, canonical);
    SongDocument &document = tab().document();
    resetPencilView(tab().view(), zoom);
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const auto capture = [this, &document, canonical, zoom](bool dense) {
        stageEmptyPanLane(document);
        setPencilMode(true);
        const LaneHandle handle = findRow(panRow());
        const auto point = [this, &document, handle](double tick, int value) {
            return strokePointInCell(tab().view(), document, page(), automationInput(), handle,
                                     tick, value);
        };
        const auto deliveredPoint = [this, &document, handle](QPointF content) {
            const QPoint window =
                automation_test::windowFromContent(page(), automationInput(), content);
            content = automation_test::contentFromWindow(page(), automationInput(), window);
            CCLaneAdapter lane(document, kTrack, kPanController);
            const QRect body = page().canvas()->laneBody(handle);
            return StrokePoint{content, window,
                               AutomationProjection(AutomationGeometry::resolve(), &page())
                                   .pointerMapping(lane, body, content.x(), content.y())};
        };
        std::array<StrokePoint, 6> input{};
        constexpr std::array<int, 6> canonicalValues{32, 44, 56, 68, 80, 92};
        const double firstTick = zoom >= 512.0 ? 12.0 : 36.0;
        input.front() = point(firstTick, canonical ? canonicalValues.front() : 8);
        for (std::size_t index = 1; index < input.size(); ++index)
            input[index] = point(double(input[index - 1].mapping.cell.tickEnd) + 0.5,
                                 canonical ? canonicalValues[index] : 64);
        if (!canonical) {
            input.back() = point(input.back().mapping.cell.tickBegin, 120);
            const StrokePoint start = input.front();
            const StrokePoint end = input.back();
            for (std::size_t index = 1; index + 1 < input.size(); ++index) {
                const qreal fraction = (input[index].content.x() - start.content.x()) /
                                       std::max<qreal>(1.0, end.content.x() - start.content.x());
                input[index] = deliveredPoint(
                    QPointF(input[index].content.x(),
                            start.content.y() + (end.content.y() - start.content.y()) * fraction));
            }
        }
        mousePress(Qt::LeftButton, input.front().window);
        for (std::size_t index = 1; index < input.size(); ++index) {
            if (dense && (canonical || index > 1)) {
                for (int sample = 1; sample < 4; ++sample) {
                    const QPointF interpolated =
                        input[index - 1].content +
                        (input[index].content - input[index - 1].content) * (qreal(sample) / 4.0);
                    // Keep extra samples on the same delivered segment: integer
                    // rounding would turn event-density changes into path changes.
                    const QPointF window = automationInput().mapToScene(interpolated);
                    QMouseEvent move(QEvent::MouseMove, window, m_quickWindow->mapToGlobal(window),
                                     Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
                    QCoreApplication::sendEvent(m_quickWindow, &move);
                }
            }
            mouseMove(input[index].window);
        }
        mouseRelease(Qt::LeftButton, input.back().window);
        return std::pair{lanePoints(document), input};
    };

    const auto [sparse, expected] = capture(false);
    const auto [dense, ignored] = capture(true);
    Q_UNUSED(ignored);
    QVERIFY(!sparse.empty());
    QVERIFY(!dense.empty());
    for (const StrokePoint &sample : expected) {
        int sparseValue = -1;
        int denseValue = -1;
        QVERIFY(heldValue(sparse, sample.mapping.cell.tickBegin, &sparseValue));
        QVERIFY(heldValue(dense, sample.mapping.cell.tickBegin, &denseValue));
        QVERIFY(std::abs(sparseValue - denseValue) <= 1);
        QVERIFY(std::abs(sparseValue - sample.mapping.point.value) <= 1);
        QVERIFY(std::abs(denseValue - sample.mapping.point.value) <= 1);
    }
}

void AutomationEditingTest::pencilBacktrackingStrokeRetainsExtremaAndLatestRevisit()
{
    SongDocument &document = tab().document();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const LaneHandle handle = findRow(panRow());
    setPencilMode(true);
    const auto point = [this, &document, handle](double tick, int value) {
        return strokePointInCell(tab().view(), document, page(), automationInput(), handle, tick,
                                 value);
    };
    const StrokePoint start = point(36, 28);
    const StrokePoint middle =
        nextCellPoint(tab().view(), document, page(), automationInput(), handle, start, 64);
    const StrokePoint far =
        nextCellPoint(tab().view(), document, page(), automationInput(), handle, middle, 100);
    const StrokePoint finish = point(36, 68);

    mousePress(Qt::LeftButton, start.window);
    mouseMove(far.window);
    mouseMove(finish.window);
    mouseRelease(Qt::LeftButton, finish.window);

    const LanePoints points = lanePoints(document);
    int startValue = -1;
    int farValue = -1;
    QVERIFY(heldValue(points, start.mapping.cell.tickBegin, &startValue));
    QVERIFY(heldValue(points, far.mapping.cell.tickBegin, &farValue));
    QVERIFY(std::abs(startValue - finish.mapping.point.value) <= 1);
    QVERIFY(std::abs(farValue - far.mapping.point.value) <= 1);
    QVERIFY(std::is_sorted(points.cbegin(), points.cend()));
}

void AutomationEditingTest::pencilShiftModifierLocksValueDimension()
{
    SongDocument &document = tab().document();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const auto capture = [this, &document](bool held) {
        stageEmptyPanLane(document);
        const LaneHandle handle = findRow(panRow());
        setPencilMode(true);
        const auto point = [this, &document, handle](double tick, int value) {
            return strokePointInCell(tab().view(), document, page(), automationInput(), handle,
                                     tick, value);
        };
        const StrokePoint start = point(36, 64);
        const StrokePoint middle =
            nextCellPoint(tab().view(), document, page(), automationInput(), handle, start, 48);
        const StrokePoint end =
            nextCellPoint(tab().view(), document, page(), automationInput(), handle, middle, 96);
        mousePress(Qt::LeftButton, start.window);
        mouseMove(middle.window);
        if (held)
            keyPress(Qt::Key_Shift);
        mouseMove(end.window, held ? Qt::ShiftModifier : Qt::NoModifier);
        mouseRelease(Qt::LeftButton, end.window, held ? Qt::ShiftModifier : Qt::NoModifier);
        if (held)
            keyRelease(Qt::Key_Shift);
        return ShiftCapture{lanePoints(document), middle, end};
    };

    const auto plain = capture(false);
    const auto locked = capture(true);
    int plainMiddle = -1;
    int plainEnd = -1;
    int lockedMiddle = -1;
    int lockedEnd = -1;
    QVERIFY(heldValue(plain.points, plain.middle.mapping.cell.tickBegin, &plainMiddle));
    QVERIFY(heldValue(plain.points, plain.end.mapping.cell.tickBegin, &plainEnd));
    QVERIFY(heldValue(locked.points, locked.middle.mapping.cell.tickBegin, &lockedMiddle));
    QVERIFY(heldValue(locked.points, locked.end.mapping.cell.tickBegin, &lockedEnd));
    QVERIFY(std::abs(plainMiddle - plain.middle.mapping.point.value) <= 1);
    QVERIFY(std::abs(plainEnd - plain.end.mapping.point.value) <= 1);
    QVERIFY(plainEnd != plainMiddle);
    QVERIFY(std::abs(lockedMiddle - locked.middle.mapping.point.value) <= 1);
    QCOMPARE(lockedEnd, lockedMiddle);
}

void AutomationEditingTest::pencilControlModifierDrawsUnsnappedClockQuantizedPoints()
{
    SongDocument &document = tab().document();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const auto capture = [this, &document](bool reverse, bool dense) {
        stageEmptyPanLane(document);
        const LaneHandle handle = findRow(panRow());
        setPencilMode(true);
        const auto point = [this, &document, handle](double tick, int value) {
            return strokePoint(tab().view(), document, page(), automationInput(), handle, tick,
                               value);
        };
        const StrokePoint start = point(31.25, 30);
        const StrokePoint turn = point(103.375, reverse ? 60 : 90);
        const StrokePoint far = point(151.625, 30);
        const StrokePoint end = point(55.75, 90);
        const auto moveSegment = [this, dense](const StrokePoint &from, const StrokePoint &to) {
            if (dense) {
                for (int sample = 1; sample < 4; ++sample) {
                    const QPointF content =
                        from.content + (to.content - from.content) * (qreal(sample) / 4.0);
                    mouseMove(
                        automation_test::windowFromContent(page(), automationInput(), content),
                        Qt::ControlModifier);
                }
            }
            mouseMove(to.window, Qt::ControlModifier);
        };

        keyPress(Qt::Key_Control);
        mousePress(Qt::LeftButton, start.window, Qt::ControlModifier);
        if (reverse) {
            moveSegment(start, far);
            moveSegment(far, turn);
            moveSegment(turn, end);
        } else {
            moveSegment(start, turn);
            moveSegment(turn, far);
        }
        const StrokePoint finish = reverse ? end : far;
        mouseRelease(Qt::LeftButton, finish.window, Qt::ControlModifier);
        keyRelease(Qt::Key_Control);
        return ControlCapture{lanePoints(document), turn, finish};
    };
    const auto clockTick = [&document](const StrokePoint &sample) {
        const Tick raw = Tick(std::floor(std::max(0.0, sample.mapping.rawTick)));
        return (raw / document.ticksPerClock()) * document.ticksPerClock();
    };
    const auto matches = [&clockTick](const ControlCapture &sparse, const ControlCapture &dense) {
        int sparseTurn = -1;
        int denseTurn = -1;
        int sparseFinish = -1;
        int denseFinish = -1;
        return heldValue(sparse.points, clockTick(sparse.turn), &sparseTurn) &&
               heldValue(dense.points, clockTick(dense.turn), &denseTurn) &&
               heldValue(sparse.points, clockTick(sparse.finish), &sparseFinish) &&
               heldValue(dense.points, clockTick(dense.finish), &denseFinish) &&
               std::abs(sparseTurn - sparse.turn.mapping.point.value) <= 1 &&
               std::abs(denseTurn - sparse.turn.mapping.point.value) <= 1 &&
               std::abs(sparseFinish - sparse.finish.mapping.point.value) <= 1 &&
               std::abs(denseFinish - sparse.finish.mapping.point.value) <= 1;
    };

    const ControlCapture forwardSparse = capture(false, false);
    const ControlCapture forwardDense = capture(false, true);
    const ControlCapture reverseSparse = capture(true, false);
    const ControlCapture reverseDense = capture(true, true);
    QVERIFY(matches(forwardSparse, forwardDense));
    QVERIFY(matches(reverseSparse, reverseDense));
    QVERIFY(clockTick(forwardSparse.turn) != forwardSparse.turn.mapping.cell.tickBegin);
}

void AutomationEditingTest::pencilMixedModifierComposesFreehandAndSnappedSegments()
{
    SongDocument &document = tab().document();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const LaneHandle handle = findRow(panRow());
    setPencilMode(true);
    const auto point = [this, &document, handle](double tick, int value) {
        return strokePointInCell(tab().view(), document, page(), automationInput(), handle, tick,
                                 value);
    };
    const StrokePoint start = point(36, 36);
    const StrokePoint middle =
        nextCellPoint(tab().view(), document, page(), automationInput(), handle, start, 76);
    const StrokePoint end =
        nextCellPoint(tab().view(), document, page(), automationInput(), handle, middle, 104);
    const QPointF interior = start.content + (middle.content - start.content) * 0.4;

    keyPress(Qt::Key_Control);
    mousePress(Qt::LeftButton, start.window, Qt::ControlModifier);
    mouseMove(automation_test::windowFromContent(page(), automationInput(), interior),
              Qt::ControlModifier);
    mouseMove(middle.window, Qt::ControlModifier);
    keyRelease(Qt::Key_Control);
    mouseMove(end.window);
    mouseRelease(Qt::LeftButton, end.window);

    const LanePoints points = lanePoints(document);
    QVERIFY(
        containsInteriorPoint(points, start.mapping.cell.tickBegin, middle.mapping.cell.tickBegin));
    int endValue = -1;
    QVERIFY(pointValue(points, end.mapping.cell.tickBegin, &endValue));
    QVERIFY(std::abs(endValue - end.mapping.point.value) <= 1);
    QVERIFY(!containsInteriorPoint(points, end.mapping.cell.tickBegin, end.mapping.cell.tickEnd));
}

void AutomationEditingTest::pencilAltModifierIsIgnoredDuringStroke()
{
    SongDocument &document = tab().document();
    resetPencilView(tab().view());
    stageEmptyPanLane(document);
    QVERIFY(activateParameter(panRow()));
    QTRY_VERIFY(findRow(panRow()).valid());
    QTRY_VERIFY(!laneBody(findRow(panRow())).isEmpty());
    const auto capture = [this, &document](Qt::KeyboardModifiers modifiers) {
        stageEmptyPanLane(document);
        setPencilMode(true);
        const LaneHandle handle = findRow(panRow());
        const StrokePoint start =
            strokePointInCell(tab().view(), document, page(), automationInput(), handle, 36, 36);
        const StrokePoint end =
            nextCellPoint(tab().view(), document, page(), automationInput(), handle, start, 96);
        mousePress(Qt::LeftButton, start.window, modifiers);
        mouseMove(end.window, modifiers);
        mouseRelease(Qt::LeftButton, end.window, modifiers);
        return lanePoints(document);
    };

    const LanePoints plain = capture(Qt::NoModifier);
    keyPress(Qt::Key_Alt);
    const LanePoints alternate = capture(Qt::AltModifier);
    keyRelease(Qt::Key_Alt);
    QVERIFY(!plain.empty());
    QVERIFY(plain == alternate);
}
