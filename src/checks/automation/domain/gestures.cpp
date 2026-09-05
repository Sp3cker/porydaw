#include "checks/automation/domain/tst_automationdomain.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <utility>
#include <vector>

#include <QtTest>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/gesture.h"

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kPan = 10;

NodeDrag laneNode(const DocLanePoint &point, NodePoint current)
{
    return {LaneHandle{0}, {point.tick, point.value}, current, 0, 127};
}

bool hasPoint(const NodePoint &point, uint64_t tick, int value)
{
    return point.tick == tick && point.value == value;
}

} // namespace

void AutomationDomainTest::sweepSteppingAndRampFinish()
{
    const auto nextGridTick = [](uint64_t tick, bool, uint64_t) { return tick + 1; };

    SweepGesture sweep;
    sweep.lane = LaneHandle{0};
    sweep.current = {10, 100};
    sweep.previousRawTick = 0.0;
    sweep.previousValue = 0;
    extendSweepPoints(sweep, 0, 10, 10.0, false, nextGridTick);
    QCOMPARE(sweep.points.size(), std::size_t{11});
    for (std::size_t index = 0; index < sweep.points.size(); ++index)
        QVERIFY(hasPoint(sweep.points[index], index, int(index) * 10));

    SweepGesture update;
    update.lane = LaneHandle{0};
    update.current = {0, 0};
    update.previousRawTick = 0.0;
    update.previousValue = 0;
    update.update({5, 50}, 0, 5, 5.0, false, nextGridTick);
    QVERIFY(hasPoint(update.current, 5, 50));
    QCOMPARE(update.points.size(), std::size_t{6});
    for (std::size_t index = 0; index < update.points.size(); ++index)
        QVERIFY(hasPoint(update.points[index], index, int(index) * 10));

    SweepGesture ramp;
    ramp.mode = SweepGesture::Mode::Ramp;
    ramp.anchor = {0, 0};
    ramp.current = {10, 100};
    const std::vector<NodePoint> existing;
    const NodeLaneEdit::Completion completion =
        ramp.finish(LaneHandle{0}, document().revision(), existing, false, nextGridTick);
    QVERIFY(!completion.unchanged);
    QCOMPARE(completion.points.size(), std::size_t{11});
    QVERIFY(hasPoint(completion.points.front(), 0, 0));
    QVERIFY(hasPoint(completion.points.back(), 10, 100));
}

void AutomationDomainTest::panNeutralSnap()
{
    SongDocument &doc = document();
    CCLaneAdapter pan(doc, kTrack, kPan);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const QRect body(0, 0, 480, std::max(1, geometry.rowDefaultHeight));
    AutomationProjection projection(geometry, static_cast<const AutomationPage *>(nullptr));
    const int span = pan.maximumValue() - pan.minimumValue();
    const int snapThreshold = span * geometry.neutralSnapRadius / body.height();

    int yNear = -1;
    int valueNear = -1;
    for (int y = body.top(); y < body.bottom() + 1; ++y) {
        const int value = qRound(AutomationProjection::valueAtY(body, geometry, pan.minimumValue(),
                                                                pan.maximumValue(), qreal(y)));
        if (value != 64 && std::abs(value - 64) <= snapThreshold) {
            yNear = y;
            valueNear = value;
            break;
        }
    }
    QVERIFY(yNear >= 0);

    NodePoint point;
    updateValuePoint(projection, pan, body, point, yNear, 100, false, geometry.neutralSnapRadius,
                     64);
    QCOMPARE(point.tick, uint64_t{100});
    QCOMPARE(point.value, valueNear);
    updateValuePoint(projection, pan, body, point, yNear, 100, true, geometry.neutralSnapRadius,
                     64);
    QCOMPARE(point.tick, uint64_t{100});
    QCOMPARE(point.value, 64);

    const int yAtNeutral = qRound(
        AutomationProjection::valueY(body, geometry, pan.minimumValue(), pan.maximumValue(), 64));
    updateValuePoint(projection, pan, body, point, yAtNeutral, 200, true,
                     geometry.neutralSnapRadius, 64);
    QVERIFY(hasPoint(point, 200, 64));
}

void AutomationDomainTest::nodeDragAndPhantomOutcomes()
{
    {
        NodeDragGesture gesture;
        const NodeDragFinish finish = gesture.finish();
        QCOMPARE(finish.release, PointDragRelease::NoOp);
        QVERIFY(!finish.changed);
    }
    {
        NodeDragGesture gesture;
        const DocLanePoint original{kTrack, 7, 24, 60};
        gesture.points = {laneNode(original, {24, 60})};
        gesture.drag.press({100.0, 100.0}, false);
        const NodeDragFinish finish = gesture.finish();
        QCOMPARE(finish.release, PointDragRelease::NoOp);
        QVERIFY(!finish.changed);
    }
    {
        NodeDragGesture gesture;
        const DocLanePoint original{kTrack, 7, 24, 60};
        gesture.points = {laneNode(original, {24, 60})};
        gesture.drag.press({100.0, 100.0}, true);
        const NodeDragFinish finish = gesture.finish();
        QCOMPARE(finish.release, PointDragRelease::StationaryDelete);
        QVERIFY(!finish.changed);
    }
    {
        NodeDragGesture gesture;
        const DocLanePoint original{kTrack, 7, 24, 60};
        gesture.points = {laneNode(original, {24, 60})};
        gesture.drag.press({100.0, 100.0}, true);
        gesture.drag.dragSlop.markExceeded({105.0, 100.0});
        const NodeDragFinish unchanged = gesture.finish();
        QCOMPARE(unchanged.release, PointDragRelease::Move);
        QVERIFY(!unchanged.changed);

        gesture.points.front().current = {30, 80};
        const NodeDragFinish moved = gesture.finish();
        QCOMPARE(moved.release, PointDragRelease::Move);
        QVERIFY(moved.changed);
        QCOMPARE(moved.dTick, int64_t{6});
    }
    {
        NodeDragGesture gesture;
        const DocLanePoint original0{kTrack, 7, 24, 60};
        const DocLanePoint original1{kTrack, 7, 48, 80};
        gesture.points = {laneNode(original0, {30, 70}), laneNode(original1, {54, 90})};
        gesture.selectionDrag = true;
        gesture.drag.press({100.0, 100.0}, true);
        gesture.drag.dragSlop.markExceeded({105.0, 100.0});
        const NodeDragFinish finish = gesture.finish();
        QCOMPARE(finish.release, PointDragRelease::Move);
        QVERIFY(finish.changed);
        QCOMPARE(finish.dTick, int64_t{6});
        QVERIFY(finish.selectionDrag);
        QVERIFY(hasPoint(gesture.points[0].current, 30, 70));
        QVERIFY(hasPoint(gesture.points[1].current, 54, 90));
    }
    {
        const DocLanePoint original{kTrack, 7, 24, 60};
        PhantomGesture gesture;
        gesture.point = laneNode(original, {24, 60});
        gesture.drag.press({100.0, 100.0}, false);
        gesture.update({PointDragUpdate::Phase::Reset, {}, AxisLock::None}, 127);
        QVERIFY(hasPoint(gesture.point.current, 24, 60));
        gesture.drag.dragSlop.markExceeded({100.0, 110.0});
        gesture.update({PointDragUpdate::Phase::Dragging, {}, AxisLock::None}, 200);
        const std::optional<NodeDrag> moved = gesture.finish();
        QVERIFY(moved.has_value());
        QCOMPARE(moved->original.tick, moved->current.tick);
        QCOMPARE(moved->current.value, 127);
    }
}

void AutomationDomainTest::pointRangeAndPencilReplacements()
{
    using LaneEdit = NodeLaneEdit;
    const LaneEdit::Target target{LaneHandle{0}, document().revision()};
    const LaneEdit pointRange(target, {{24, 64}, {48, 64}});
    QVERIFY(pointRange.replacePointRange(24, 48, {{24, 64}, {48, 64}}).unchanged);
    QVERIFY(!pointRange.replacePointRange(24, 48, {{24, 64}}).unchanged);

    const LaneEdit heldSpan(target, {{0, 20}, {24, 60}, {72, 90}});
    const LaneEdit::Completion restored = heldSpan.replaceHeldSpan(24, 48, 96, 0, 127, {{24, 80}});
    QVERIFY(!restored.unchanged);
    QCOMPARE(restored.points.size(), std::size_t{2});
    QVERIFY(hasPoint(restored.points[0], 24, 80));
    QVERIFY(hasPoint(restored.points[1], 48, 60));

    const AutomationPencilGesture::Sample finalSample{24.0, 24.0, {24, 80}, 80.0};
    auto emptyLaneGesture = AutomationPencilGesture::start(target, 0, 127, 96, 24, {},
                                                           NodePoint{0, 20}, finalSample, {24, 48});
    QVERIFY(emptyLaneGesture.has_value());
    const LaneEdit::Completion emptyCompletion = std::move(*emptyLaneGesture).finish();
    QVERIFY(!emptyCompletion.unchanged);
    QCOMPARE(emptyCompletion.points.size(), std::size_t{2});
    QVERIFY(hasPoint(emptyCompletion.points[0], 24, 80));
    QVERIFY(hasPoint(emptyCompletion.points[1], 48, 20));

    auto pastLastGesture = AutomationPencilGesture::start(target, 0, 127, 96, 24, {{0, 20}},
                                                          std::nullopt, finalSample, {24, 48});
    QVERIFY(pastLastGesture.has_value());
    const LaneEdit::Completion pastLastCompletion = std::move(*pastLastGesture).finish();
    QVERIFY(!pastLastCompletion.unchanged);
    QCOMPARE(pastLastCompletion.points.size(), std::size_t{2});
    QVERIFY(hasPoint(pastLastCompletion.points[0], 24, 80));
    QVERIFY(hasPoint(pastLastCompletion.points[1], 48, 20));

    const LaneEdit::Completion flat = heldSpan.replaceHeldSpan(36, 48, 96, 0, 127, {{36, 60}});
    QVERIFY(flat.unchanged);
    QVERIFY(flat.points.empty());
    const LaneEdit::Completion deletion = heldSpan.replaceHeldSpan(24, 96, 96, 0, 127, {});
    QVERIFY(!deletion.unchanged);
    QVERIFY(deletion.points.empty());
}
