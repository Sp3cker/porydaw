#include "domains.h"
#include "support.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

#include <QSize>

#include <QString>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelinequickscene.h"

#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

enum class AdapterKind { Tempo, Cc };

struct Adapter {
    AdapterKind kind = AdapterKind::Tempo;
    const char *name = "";
};

struct Context {
    AutomationGestureCheckRig &rig;
    Check check;
    Adapter adapter;
    const char *scenario = "";
    LaneHandle handle;
    int track = 0;
    uint8_t controller = 10;

    Context(AutomationGestureCheckRig &rig, const AutomationGestureCheck &fn, Adapter adapter,
            const char *scenario, LaneHandle handle, int track, uint8_t controller)
        : rig(rig)
        , check(fn,
                QStringLiteral("%1 %2").arg(QLatin1String(adapter.name), QLatin1String(scenario)))
        , adapter(adapter)
        , scenario(scenario)
        , handle(handle)
        , track(track)
        , controller(controller)
    {}
};

struct Scenario {
    const char *name;
    void (*run)(Context &);
};

constexpr uint32_t kPreservedTempoUs = 499999;
constexpr std::array kAdapters{
    Adapter{AdapterKind::Tempo, "Tempo"},
    Adapter{AdapterKind::Cc, "CC"},
};
const std::vector<NodePoint> kFixture{{0, 80}, {kFixtureTick, 100}, {288, 64}};
const std::vector<NodePoint> kMulti{{0, 80}, {kFixtureTick, 100}, {192, 64}, {384, 110}};

bool containsPoint(const std::vector<NodePoint> &points, uint64_t tick, int value)
{
    return std::any_of(points.cbegin(), points.cend(), [tick, value](const NodePoint &point) {
        return point.tick == tick && point.value == value;
    });
}

struct HorizontalSpan {
    qreal y = 0.0;
    qreal length = 0.0;
};

std::optional<HorizontalSpan> longestHorizontalSpan(const songview::TimelineQuickLayerData &layer)
{
    const qreal tolerance = layout::singlePixel();
    std::optional<HorizontalSpan> result;
    for (const auto &triangle : layer.triangles) {
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

std::vector<NodePoint> pointsOf(const Context &ctx)
{
    std::vector<NodePoint> out;
    if (ctx.adapter.kind == AdapterKind::Tempo) {
        for (const auto &point : ctx.rig.document().tempoPoints())
            out.push_back({point.tick, tempoBpm(point.microsecondsPerQuarterNote)});
        return out;
    }
    for (const auto &point : ctx.rig.document().lanePoints(ctx.track, ctx.controller)) {
        if (!out.empty() && out.back().tick == point.tick)
            out.back().value = point.value;
        else
            out.push_back({point.tick, point.value});
    }
    return out;
}

void setTempo(Context &ctx, const std::vector<TempoPoint> &points)
{
    if (ctx.rig.document().tempoPoints() == points)
        return;
    TempoEdit edit;
    edit.remove = ctx.rig.document().tempoPoints();
    edit.add = points;
    ctx.rig.document().applyTempoEdit(edit);
    ctx.rig.documentChanged();
}

void seed(Context &ctx, const std::vector<NodePoint> &points)
{
    if (ctx.adapter.kind == AdapterKind::Tempo) {
        std::vector<TempoPoint> tempo;
        tempo.reserve(points.size());
        for (const auto &point : points) {
            tempo.push_back({point.tick, tempoUsForBpm(point.value)});
        }
        setTempo(ctx, tempo);
        return;
    }
    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const auto &point : points)
        values.push_back({point.tick, point.value});
    ctx.rig.document().writeLanePoints(ctx.track, ctx.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), values);
    ctx.rig.documentChanged();
}

AutomationGestureCheckRig::InputPoint at(const Context &ctx, double tick, int value)
{
    return ctx.rig.pointAt(ctx.handle, tick, value);
}

void activatedDrag(const Context &ctx, const QPointF &start, const QPointF &target,
                   Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    const QPointF activation =
        start + QPointF(ctx.rig.geometry().nodeDragActivationDistance + 2, 0.0);
    const QPointF end = activation + target - start;
    ctx.rig.mousePress(start, modifiers);
    ctx.rig.mouseMove(activation, Qt::LeftButton, modifiers);
    ctx.rig.mouseMove(end, Qt::LeftButton, modifiers);
    ctx.rig.mouseRelease(end, modifiers);
}

void selectRange(Context &ctx, uint64_t first, uint64_t last)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = first;
    selection.endTick = last;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    if (ctx.adapter.kind == AdapterKind::Tempo)
        selection.tempo = true;
    else
        selection.lanes = {{ctx.track, ctx.controller}};
    ctx.rig.view().selectionModel().setTimeSelection(std::move(selection));
    ctx.rig.pump();
}

void expectOneEdit(const Context &ctx, const DocSnapshot &before,
                   const std::vector<NodePoint> &expected)
{
    const auto after = snapshot(ctx.rig.document());
    ctx.check.require(
        isOneEdit(before, after) && sameNodePoints(pointsOf(ctx), expected),
        QStringLiteral("completed gesture did not commit one edit with the shared node result"));
}

void expectUnchanged(const Context &ctx, const DocSnapshot &before, const char *label)
{
    ctx.check.require(
        isUnchanged(before, snapshot(ctx.rig.document())),
        QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
}

void runHoverInsertion(Context &ctx)
{
    seed(ctx, kFixture);
    const auto before = snapshot(ctx.rig.document());
    ctx.rig.mouseMove(at(ctx, 48, 90).position, Qt::NoButton);
    ctx.rig.pump();
    expectUnchanged(ctx, before, "insertion hover");
}

void runClickDelete(Context &ctx)
{
    seed(ctx, kFixture);
    const auto node = at(ctx, kFixtureTick, 100);
    const auto before = snapshot(ctx.rig.document());
    ctx.rig.mousePress(node.position);
    ctx.rig.mouseRelease(node.position);
    expectOneEdit(ctx, before, {{0, 80}, {288, 64}});
    const auto afterDelete = snapshot(ctx.rig.document());
    ctx.rig.mouseDoubleClick(node.position);
    ctx.rig.pump();
    expectUnchanged(ctx, afterDelete, "double-click after delete");
    seed(ctx, kFixture);
    const auto shiftBefore = snapshot(ctx.rig.document());
    ctx.rig.mousePress(node.position, Qt::ShiftModifier);
    ctx.rig.mouseRelease(node.position, Qt::ShiftModifier);
    expectUnchanged(ctx, shiftBefore, "Shift+stationary click");
}

void runNodeDrag(Context &ctx)
{
    seed(ctx, kFixture);
    auto before = snapshot(ctx.rig.document());
    activatedDrag(ctx, at(ctx, kFixtureTick, 100).position, at(ctx, 192, 100).position);
    expectOneEdit(ctx, before, {{0, 80}, {192, 100}, {288, 64}});
    seed(ctx, kFixture);
    activatedDrag(ctx, at(ctx, kFixtureTick, 100).position, at(ctx, 192, 64).position,
                  Qt::ShiftModifier);
    ctx.check.require(sameNodePoints(pointsOf(ctx), {{0, 80}, {192, 100}, {288, 64}}),
                      QStringLiteral("horizontal Shift drag did not lock value"));
    seed(ctx, kFixture);
    const auto axisStart = at(ctx, kFixtureTick, 100).position;
    const auto valueActivation = axisStart + QPointF(2.0, 28.0);
    const auto valueTarget = at(ctx, kFixtureTick, 64).position;
    const auto valueEnd = valueActivation + valueTarget - axisStart;
    ctx.rig.mousePress(axisStart, Qt::ShiftModifier);
    ctx.rig.mouseMove(valueActivation, Qt::LeftButton, Qt::ShiftModifier);
    ctx.rig.mouseMove(valueEnd, Qt::LeftButton, Qt::ShiftModifier);
    ctx.rig.mouseRelease(valueEnd, Qt::ShiftModifier);
    ctx.check.require(sameNodePoints(pointsOf(ctx), {{0, 80}, {kFixtureTick, 64}, {288, 64}}),
                      QStringLiteral("vertical Shift drag did not lock time"));
    if (ctx.adapter.kind == AdapterKind::Tempo) {
        setTempo(ctx, {{kFixtureTick, kPreservedTempoUs}, {288, tempoUsForBpm(64)}});
        const auto preserved = tempoBpm(kPreservedTempoUs);
        before = snapshot(ctx.rig.document());
        activatedDrag(ctx, at(ctx, kFixtureTick, preserved).position,
                      at(ctx, 192, preserved).position);
        ctx.check.require(isOneEdit(before, snapshot(ctx.rig.document())),
                          QStringLiteral("fractional Tempo drag did not commit one edit"));
        const auto moved = ctx.rig.document().tempoPoints();
        ctx.check.require(moved.size() == 2 && moved.front().tick == 192 &&
                              moved.front().microsecondsPerQuarterNote == kPreservedTempoUs,
                          QStringLiteral("unchanged-value Tempo drag discarded microseconds"));
        return;
    }
    ctx.rig.document().writeLanePoints(ctx.track, ctx.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), {{288, 40}});
    SmfEvent first;
    first.tick = kFixtureTick;
    first.status = uint8_t((0xB << 4) | (ctx.rig.document().channelFor(ctx.track) & 0x0F));
    first.data0 = ctx.controller;
    first.data1 = 10;
    ctx.rig.document().insertRawEvent(ctx.rig.document().smfTrackFor(ctx.track), first);
    SmfEvent second = first;
    second.data1 = 20;
    ctx.rig.document().insertRawEvent(ctx.rig.document().smfTrackFor(ctx.track), second);
    ctx.rig.documentChanged();
    before = snapshot(ctx.rig.document());
    activatedDrag(ctx, at(ctx, kFixtureTick, 20).position, at(ctx, 192, 20).position);
    ctx.check.require(
        isOneEdit(before, snapshot(ctx.rig.document())) &&
            rawValuesAt(ctx.rig.document(), ctx.track, ctx.controller, kFixtureTick).empty() &&
            rawValuesAt(ctx.rig.document(), ctx.track, ctx.controller, 192) ==
                std::vector<int>{10, 20},
        QStringLiteral("CC same-tick drag did not keep the grouped events ordered"));
}

void runSelection(Context &ctx)
{
    seed(ctx, kMulti);
    selectRange(ctx, kFixtureTick, 288);
    auto before = snapshot(ctx.rig.document());
    activatedDrag(ctx, at(ctx, kFixtureTick, 100).position, at(ctx, 144, 100).position);
    const auto &moved = ctx.rig.view().selectionModel().timeSelection();
    ctx.check.require(
        isOneEdit(before, snapshot(ctx.rig.document())) &&
            sameNodePoints(pointsOf(ctx), {{0, 80}, {144, 100}, {240, 64}, {384, 110}}) &&
            moved.startTick == 144 && moved.endTick == 336,
        QStringLiteral("selection drag did not move every selected node and range"));
    seed(ctx, kMulti);
    selectRange(ctx, kFixtureTick, 288);
    before = snapshot(ctx.rig.document());
    ctx.rig.keyToArea(QEvent::KeyPress, Qt::Key_Delete);
    expectOneEdit(ctx, before, {{0, 80}, {384, 110}});
}

void runSweepRamp(Context &ctx)
{
    seed(ctx, kFixture);
    auto start = at(ctx, 48, 80);
    auto target = at(ctx, 144, 110);
    auto before = snapshot(ctx.rig.document());
    activatedDrag(ctx, start.position, target.position);
    const auto sweep = pointsOf(ctx);
    const bool hasTarget =
        containsPoint(sweep, target.mapped.point.tick, target.mapped.point.value);
    ctx.check.require(isOneEdit(before, snapshot(ctx.rig.document())) && hasTarget,
                      QStringLiteral("sweep did not commit the mapped target in one edit"));
    seed(ctx, kFixture);
    start = at(ctx, 48, 80);
    target = at(ctx, 144, 110);
    before = snapshot(ctx.rig.document());
    ctx.rig.mousePress(start.position, Qt::ShiftModifier);
    ctx.rig.mouseMove(target.position, Qt::LeftButton, Qt::ShiftModifier);
    ctx.rig.mouseRelease(target.position, Qt::ShiftModifier);
    const auto ramp = pointsOf(ctx);
    const bool hasEnds = containsPoint(ramp, start.mapped.point.tick, start.mapped.point.value) &&
                         containsPoint(ramp, target.mapped.point.tick, target.mapped.point.value);
    ctx.check.require(
        isOneEdit(before, snapshot(ctx.rig.document())) && hasEnds,
        QStringLiteral("Shift-ramp did not commit both mapped endpoints in one edit"));
}

void runPencil(Context &ctx)
{
    seed(ctx, {});
    ctx.rig.setPersistentPencil(true);
    const auto start = at(ctx, 36, 80);
    const auto end = at(ctx, 144, 110);
    const auto before = snapshot(ctx.rig.document());
    ctx.rig.mousePress(start.position);
    ctx.rig.mouseMove(end.position);
    ctx.rig.pump();
    expectUnchanged(ctx, before, "Pencil preview");
    ctx.rig.mouseRelease(end.position);
    ctx.rig.commitTimers();
    const auto after = snapshot(ctx.rig.document());
    ctx.check.require(isOneEdit(before, after) && !pointsOf(ctx).empty(),
                      QStringLiteral("Pencil stroke did not commit one edit"));
    ctx.rig.setPersistentPencil(false);
}

void runBandSelect(Context &ctx)
{
    seed(ctx, kFixture);
    ctx.rig.view().selectionModel().clearTimeSelection();
    ctx.rig.pump();
    const auto start = at(ctx, kFixtureTick, 80);
    const auto end = at(ctx, 288, 80);
    const uint64_t expectedStart = ctx.rig.projection().snapTickAt(start.position.x(), false);
    const uint64_t expectedEnd = ctx.rig.projection().snapTickAt(end.position.x(), false);
    ctx.rig.mousePress(start.position, Qt::NoModifier, Qt::RightButton);
    ctx.rig.mouseMove(end.position, Qt::RightButton);
    ctx.rig.mouseRelease(end.position, Qt::NoModifier, Qt::RightButton);
    ctx.rig.pump();
    const auto &selection = ctx.rig.view().selectionModel().timeSelection();
    const bool tempo = ctx.adapter.kind == AdapterKind::Tempo;
    const bool lanesMatch = tempo ? selection.lanes.empty()
                                  : selection.lanes.size() == 1 &&
                                        selection.lanes.front().first == ctx.track &&
                                        selection.lanes.front().second == ctx.controller;
    ctx.check.require(selection.active() &&
                          selection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
                          selection.tempo == tempo && lanesMatch &&
                          selection.startTick == expectedStart && selection.endTick == expectedEnd,
                      QStringLiteral("right-drag band did not publish the shared time selection"));
}

void runEscapeCancel(Context &ctx)
{
    seed(ctx, kFixture);
    const auto before = snapshot(ctx.rig.document());
    const auto start = at(ctx, kFixtureTick, 100).position;
    const auto target = at(ctx, 192, 64).position;
    const QPointF activation =
        start + QPointF(ctx.rig.geometry().nodeDragActivationDistance + 2, 0.0);
    ctx.rig.mousePress(start);
    ctx.rig.mouseMove(activation);
    ctx.rig.mouseMove(activation + target - start);
    ctx.rig.keyToArea(QEvent::KeyPress, Qt::Key_Escape);
    ctx.rig.mouseRelease(activation + target - start);
    expectUnchanged(ctx, before, "Escape");
    ctx.check.require(ctx.rig.isIdle(), QStringLiteral("Escape left a live gesture"));
}

void runRebuildCancel(Context &ctx)
{
    seed(ctx, kFixture);
    const auto grab = at(ctx, kFixtureTick, 100);
    const qreal arm = qreal(ctx.rig.geometry().nodeDragActivationDistance + 2);
    const QPointF armed = grab.position + QPointF(arm, 0.0);
    auto before = snapshot(ctx.rig.document());
    ctx.rig.mousePress(grab.position);
    ctx.rig.mouseMove(armed);
    ctx.rig.pump();
    ctx.rig.documentChanged();
    ctx.rig.mouseRelease(armed);
    ctx.rig.pump();
    ctx.check.require(isUnchanged(before, snapshot(ctx.rig.document())) && ctx.rig.isIdle(),
                      QStringLiteral("release after document rebuild committed a stale handle"));
    const QSize size = ctx.rig.automationViewportSize();
    before = snapshot(ctx.rig.document());
    ctx.rig.mousePress(at(ctx, kFixtureTick, 100).position);
    ctx.rig.mouseMove(at(ctx, kFixtureTick, 100).position + QPointF(arm, 0.0));
    ctx.rig.pump();
    ctx.rig.resizeAutomationViewport(QSize(size.width() + 48, size.height()));
    ctx.rig.pump();
    ctx.rig.mouseRelease(at(ctx, kFixtureTick, 100).position + QPointF(arm, 0.0));
    ctx.rig.pump();
    ctx.check.require(
        isUnchanged(before, snapshot(ctx.rig.document())) && ctx.rig.isIdle() &&
            !ctx.rig.canvas().bandPreviewContainsLane(ctx.handle),
        QStringLiteral("release after a geometry stack rebuild committed a stale handle"));
    const auto followGrab = at(ctx, kFixtureTick, 100);
    const auto followTarget = at(ctx, 192, 100);
    before = snapshot(ctx.rig.document());
    activatedDrag(ctx, followGrab.position, followTarget.position);
    ctx.check.require(isOneEdit(before, snapshot(ctx.rig.document())) && ctx.rig.isIdle(),
                      QStringLiteral("input did not recover after stack-rebuild cancellation"));
}

void runSemanticNoOp(Context &ctx)
{
    seed(ctx, kFixture);
    const auto empty = at(ctx, 48, 90);
    const auto before = snapshot(ctx.rig.document());
    ctx.rig.mousePress(empty.position);
    ctx.rig.mouseRelease(empty.position);
    expectUnchanged(ctx, before, "empty-plot click");
    const int slop = ctx.rig.geometry().nodeDragActivationDistance;
    ctx.rig.mousePress(empty.position);
    ctx.rig.mouseMove(empty.position + QPointF(std::max(0, slop - 1), 0.0));
    ctx.rig.mouseRelease(empty.position + QPointF(std::max(0, slop - 1), 0.0));
    ctx.check.require(isUnchanged(before, snapshot(ctx.rig.document())) &&
                          sameNodePoints(pointsOf(ctx), kFixture),
                      QStringLiteral("sub-threshold empty jitter mutated the document"));
}

void runOriginPhantom(Context &ctx)
{
    seed(ctx, kFixture);
    ctx.rig.setAutomationZoom(96.0);
    ctx.rig.setAutomationScroll(0.0);
    ctx.rig.pump();
    const qreal originX = qreal(ctx.rig.geometry().plotOrigin);
    const qreal coveredX = at(ctx, kFixtureTick, 100).position.x();
    ctx.rig.setAutomationScroll(coveredX - originX + 2.0 * ctx.rig.geometry().pointHitRadius);
    ctx.rig.pump();
    const QPointF start(originX, at(ctx, kFixtureTick, 100).position.y());
    const QPointF target(originX, at(ctx, kFixtureTick, 110).position.y());
    const QPointF hover = ctx.adapter.kind == AdapterKind::Cc
                              ? start - QPointF(ctx.rig.geometry().pointHitRadius / 2.0, 0.0)
                              : start;
    ctx.rig.mouseMove(hover, Qt::NoButton);
    ctx.rig.pump();
    ctx.check.require(ctx.rig.automationCursor().shape() == Qt::ArrowCursor,
                      QStringLiteral("origin phantom hover did not keep the arrow cursor"));
    const auto before = snapshot(ctx.rig.document());
    const qreal arm = qreal(ctx.rig.geometry().nodeDragActivationDistance + 2);
    const QPointF activation = start + QPointF(0.0, target.y() < start.y() ? -arm : arm);
    const QPointF end = activation + target - start;
    const qreal minimumCurveSpan = 2.0 * ctx.rig.geometry().pointHitRadius;
    const auto transientBefore =
        ctx.rig.quickScene().layer(songview::TimelineQuickLayer::AutomationTransient);
    ctx.rig.mousePress(start);
    ctx.rig.mouseMove(activation);
    ctx.rig.pump();
    const auto originalLayer =
        ctx.rig.quickScene().layer(songview::TimelineQuickLayer::AutomationTransient);
    ctx.rig.mouseMove(end);
    ctx.rig.pump();
    const auto movedLayer =
        ctx.rig.quickScene().layer(songview::TimelineQuickLayer::AutomationTransient);
    const auto originalCurve = longestHorizontalSpan(originalLayer);
    const auto movedCurve = longestHorizontalSpan(movedLayer);
    const qreal targetDelta = target.y() - start.y();
    const bool curveUpdated =
        originalCurve && movedCurve && originalCurve->length > minimumCurveSpan &&
        movedCurve->length > minimumCurveSpan &&
        std::abs(movedCurve->y - originalCurve->y) > layout::singlePixel() / 2.0 &&
        (movedCurve->y - originalCurve->y) * targetDelta > 0.0;
    ctx.check.require(originalLayer.revision > transientBefore.revision &&
                          movedLayer.revision > originalLayer.revision && curveUpdated,
                      QStringLiteral("origin phantom drag did not update its retained Quick "
                                     "held-value curve"));
    ctx.check.require(isUnchanged(before, snapshot(ctx.rig.document())),
                      QStringLiteral("origin phantom preview mutated the document before release"));
    ctx.rig.mouseRelease(end);
    ctx.rig.pump();
    const auto actual = pointsOf(ctx);
    ctx.check.require(isOneEdit(before, snapshot(ctx.rig.document())) &&
                          sameNodePoints(actual, {{0, 80}, {kFixtureTick, 110}, {288, 64}}),
                      QStringLiteral("origin phantom drag produced %1").arg(formatPoints(actual)));
    ctx.rig.setAutomationScroll(0.0);
}

constexpr std::array kScenarios{
    Scenario{"hover-insertion", runHoverInsertion},
    Scenario{"click-delete", runClickDelete},
    Scenario{"node-drag", runNodeDrag},
    Scenario{"origin-phantom", runOriginPhantom},
    Scenario{"selection", runSelection},
    Scenario{"sweep-ramp", runSweepRamp},
    Scenario{"pencil", runPencil},
    Scenario{"band-select", runBandSelect},
    Scenario{"escape", runEscapeCancel},
    Scenario{"rebuild-cancel", runRebuildCancel},
    Scenario{"semantic-no-op", runSemanticNoOp},
};

} // namespace

void runNodeLaneCrossLaneParity(AutomationGestureCheckRig &rig,
                                const AutomationGestureCheck &check);

void checkNodeLaneParity(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    rig.setAutomationZoom(96.0);
    rig.setAutomationScroll(0.0);
    rig.setPersistentPencil(false);
    rig.pump();
    check(rig.expandTempo(), QStringLiteral("Tempo header did not expose the expanded body"));
    const auto initialTempo = rig.document().tempoPoints();
    const auto initialPan = rig.document().lanePoints(rig.pan.track, rig.pan.controller);
    const auto restore = [&] {
        rig.view().selectionModel().clearTimeSelection();
        rig.setPersistentPencil(false);
        TempoEdit edit;
        edit.remove = rig.document().tempoPoints();
        edit.add = initialTempo;
        if (rig.document().tempoPoints() != initialTempo)
            rig.document().applyTempoEdit(edit);
        std::vector<SongDocument::LanePointValue> pan;
        pan.reserve(initialPan.size());
        for (const auto &point : initialPan)
            pan.push_back({point.tick, point.value});
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), pan);
        rig.documentChanged();
        rig.pump();
    };
    for (const auto &scenario : kScenarios) {
        for (const auto &adapter : kAdapters) {
            Context ctx{rig, check, adapter, scenario.name, {}, rig.pan.track, rig.pan.controller};
            ctx.handle =
                adapter.kind == AdapterKind::Tempo ? LaneHandle{0} : rig.handleFor(rig.pan);
            if (!ctx.handle.valid()) {
                check(false, QStringLiteral("%1 %2: lane body is missing")
                                 .arg(QLatin1String(adapter.name), QLatin1String(scenario.name)));
                continue;
            }
            scenario.run(ctx);
            restore();
        }
    }
    runNodeLaneCrossLaneParity(rig, check);
}
