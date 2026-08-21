#include "domains.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QByteArray>
#include <QEvent>
#include <QPointF>
#include <QString>
#include <QUndoStack>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

struct Context {
    AutomationGestureCheckRig &rig;
    const AutomationGestureCheck &check;
    const char *scenario = "";
};

struct Snapshot {
    QByteArray smf;
    uint64_t revision = 0;
    int undoIndex = 0;
};

struct Scenario {
    const char *name;
    void (*run)(Context &);
};

constexpr uint32_t kPreservedTempoUs = 499999;
constexpr uint64_t kSelectedTick = 96;
constexpr uint64_t kMovedTick = 144;
constexpr uint64_t kUnrelatedLate = 384;

void report(const Context &ctx, bool condition, const QString &message)
{
    ctx.check(condition,
              QStringLiteral("cross-lane %1: %2").arg(QLatin1String(ctx.scenario), message));
}

Snapshot snapshot(SongDocument &document)
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

bool oneEdit(const Snapshot &before, const Snapshot &after)
{
    return after.revision == before.revision + 1 && after.undoIndex == before.undoIndex + 1;
}

bool unchanged(const Snapshot &before, const Snapshot &after)
{
    return after.smf == before.smf && after.revision == before.revision &&
           after.undoIndex == before.undoIndex;
}

bool samePoints(const std::vector<NodePoint> &left, const std::vector<NodePoint> &right)
{
    if (left.size() != right.size())
        return false;
    for (auto i = std::size_t{0}; i < left.size(); ++i) {
        if (left[i].tick != right[i].tick || left[i].value != right[i].value)
            return false;
    }
    return true;
}

bool sameRaw(const std::vector<DocLanePoint> &points,
             const std::vector<SongDocument::LanePointValue> &expected)
{
    if (points.size() != expected.size())
        return false;
    for (auto i = std::size_t{0}; i < points.size(); ++i) {
        if (points[i].tick != expected[i].tick || points[i].value != expected[i].value)
            return false;
    }
    return true;
}

std::vector<SongDocument::LanePointValue> laneValues(const std::vector<DocLanePoint> &points)
{
    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const auto &point : points)
        values.push_back({point.tick, point.value});
    return values;
}

int tempoValue(uint32_t microseconds)
{
    return int(std::lround(CoreTimeDefaults::tempoBpm(microseconds)));
}

std::vector<NodePoint> effectiveTempo(const SongDocument &document)
{
    std::vector<NodePoint> out;
    for (const auto &point : document.tempoPoints())
        out.push_back({point.tick, tempoValue(point.microsecondsPerQuarterNote)});
    return out;
}

std::vector<NodePoint> effectiveLane(const SongDocument &document, int track, uint8_t controller)
{
    std::vector<NodePoint> out;
    for (const auto &point : document.lanePoints(track, controller)) {
        if (!out.empty() && out.back().tick == point.tick)
            out.back().value = point.value;
        else
            out.push_back({point.tick, point.value});
    }
    return out;
}

std::vector<int> rawValuesAt(const SongDocument &document, int track, uint8_t controller,
                             uint64_t tick)
{
    std::vector<int> values;
    for (const auto &point : document.lanePoints(track, controller)) {
        if (point.tick == tick)
            values.push_back(point.value);
    }
    return values;
}

uint32_t tempoUsAt(const SongDocument &document, uint64_t tick)
{
    for (const auto &point : document.tempoPoints()) {
        if (point.tick == tick)
            return point.microsecondsPerQuarterNote;
    }
    return 0;
}

bool idle(const AutomationGestureCheckRig &rig)
{
    return !rig.canvas().isPanning() && !rig.view().userGestureActive();
}

void writeLane(SongDocument &document, const AutomationGestureCheckRig::Lane &lane,
               const std::vector<SongDocument::LanePointValue> &points)
{
    document.writeLanePoints(lane.track, lane.controller, 0, std::numeric_limits<uint64_t>::max(),
                             points);
}

void seedMixed(AutomationGestureCheckRig &rig, bool occupyMovedPan = false)
{
    TempoEdit edit;
    edit.remove = rig.document().tempoPoints();
    edit.add = {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(80)},
                {kSelectedTick, kPreservedTempoUs},
                {kUnrelatedLate, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(64)}};
    if (rig.document().tempoPoints() != edit.add)
        rig.document().applyTempoEdit(edit);
    if (occupyMovedPan)
        writeLane(rig.document(), rig.pan,
                  {{0, 80},
                   {kSelectedTick, 10},
                   {kSelectedTick, 20},
                   {kMovedTick, 70},
                   {kMovedTick, 80},
                   {kUnrelatedLate, 110}});
    else
        writeLane(rig.document(), rig.pan,
                  {{0, 80}, {kSelectedTick, 10}, {kSelectedTick, 20}, {kUnrelatedLate, 110}});
    writeLane(rig.document(), rig.lfo, {{0, 32}, {kSelectedTick, 96}, {kUnrelatedLate, 64}});
    rig.documentChanged();
}

void publishMixedSelection(AutomationGestureCheckRig &rig, uint64_t first, uint64_t last,
                           bool includeTempo = true)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = first;
    selection.endTick = last;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.tempo = includeTempo;
    selection.lanes = {{rig.pan.track, rig.pan.controller}, {rig.lfo.track, rig.lfo.controller}};
    rig.view().selectionModel().setTimeSelection(std::move(selection));
    rig.pump();
}

bool mixedSelection(const songview::EditorSelectionModel::TimeSelection &selection, uint64_t first,
                    uint64_t last, const AutomationGestureCheckRig &rig, bool includeTempo = true)
{
    const auto hasLane = [&selection](int track, uint8_t controller) {
        for (const auto &lane : selection.lanes) {
            if (lane.first == track && lane.second == controller)
                return true;
        }
        return false;
    };
    return selection.active() &&
           selection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
           selection.tempo == includeTempo && selection.startTick == first &&
           selection.endTick == last && hasLane(rig.pan.track, rig.pan.controller) &&
           hasLane(rig.lfo.track, rig.lfo.controller);
}

void expectUnchanged(const Context &ctx, const Snapshot &before, const char *label)
{
    report(ctx, unchanged(before, snapshot(ctx.rig.document())),
           QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
}

bool requirePanLfo(Context &ctx)
{
    if (ctx.rig.handleFor(ctx.rig.pan).valid() && ctx.rig.handleFor(ctx.rig.lfo).valid())
        return true;
    report(ctx, false, QStringLiteral("pan or LFO lane body is missing"));
    return false;
}

QPointF shiftDragPreview(AutomationGestureCheckRig &rig, LaneHandle handle, uint64_t fromTick,
                         uint64_t toTick, int value)
{
    const auto start = rig.pointAt(handle, fromTick, value).position;
    const auto target = rig.pointAt(handle, toTick, value).position;
    const QPointF activation = start + QPointF(rig.geometry().nodeDragActivationDistance + 2, 0.0);
    const QPointF end = activation + target - start;
    rig.mousePress(start, Qt::ShiftModifier);
    rig.mouseMove(activation, Qt::LeftButton, Qt::ShiftModifier);
    rig.mouseMove(end, Qt::LeftButton, Qt::ShiftModifier);
    rig.pump();
    return end;
}

void expectOneCommittedEdit(const Context &ctx, const Snapshot &before, const char *label)
{
    auto &document = ctx.rig.document();
    const auto after = snapshot(document);
    report(ctx, oneEdit(before, after),
           QStringLiteral("%1 did not commit exactly one revision and one undo")
               .arg(QLatin1String(label)));
    document.undoStack()->undo();
    const auto undone = snapshot(document);
    report(ctx, undone.undoIndex == before.undoIndex && undone.smf == before.smf,
           QStringLiteral("%1 undo did not restore SMF and undo index").arg(QLatin1String(label)));
    document.undoStack()->redo();
    const auto redone = snapshot(document);
    report(ctx, redone.undoIndex == after.undoIndex && redone.smf == after.smf,
           QStringLiteral("%1 redo did not restore the committed SMF").arg(QLatin1String(label)));
}

void expectMovedPanGroup(const Context &ctx)
{
    auto &document = ctx.rig.document();
    const auto &pan = ctx.rig.pan;
    report(ctx,
           samePoints(effectiveLane(document, pan.track, pan.controller),
                      {{0, 80}, {kMovedTick, 20}, {kUnrelatedLate, 110}}) &&
               rawValuesAt(document, pan.track, pan.controller, kSelectedTick).empty() &&
               rawValuesAt(document, pan.track, pan.controller, kMovedTick) ==
                   std::vector<int>{10, 20},
           QStringLiteral("pan dest occupant survived, source was not emptied, or same-tick group "
                          "order/effective value changed"));
}

void restoreLfo(AutomationGestureCheckRig &rig, const std::vector<DocLanePoint> &initialLfo)
{
    writeLane(rig.document(), rig.lfo, laneValues(initialLfo));
    rig.documentChanged();
}

void runTempoPanLfo(Context &ctx)
{
    auto &rig = ctx.rig;
    if (!requirePanLfo(ctx))
        return;
    const auto initialLfo = rig.document().lanePoints(rig.lfo.track, rig.lfo.controller);
    const auto volume =
        laneValues(rig.document().lanePoints(rig.volume.track, rig.volume.controller));
    seedMixed(rig, true);
    publishMixedSelection(rig, kSelectedTick, kMovedTick);
    const auto preservedBpm = tempoValue(kPreservedTempoUs);
    const auto hoverBefore = snapshot(rig.document());
    rig.mouseMove(rig.pointAt(LaneHandle{0}, kSelectedTick, preservedBpm).position, Qt::NoButton);
    rig.pump();
    expectUnchanged(ctx, hoverBefore, "mixed-selection hover");
    // Horizontal Shift-drag of the selected Tempo node; pan and LFO must follow in one edit.
    // Selection is [96, 144) so the hidden pan occupant at 144 is not selected.
    const auto dragBefore = snapshot(rig.document());
    const auto end = shiftDragPreview(rig, LaneHandle{0}, kSelectedTick, kMovedTick, preservedBpm);
    expectUnchanged(ctx, dragBefore, "mixed selection-drag preview");
    rig.mouseRelease(end, Qt::ShiftModifier);
    expectOneCommittedEdit(ctx, dragBefore, "selection-drag");
    report(ctx,
           samePoints(effectiveTempo(rig.document()),
                      {{0, 80}, {kMovedTick, preservedBpm}, {kUnrelatedLate, 64}}) &&
               tempoUsAt(rig.document(), kMovedTick) == kPreservedTempoUs,
           QStringLiteral("Tempo did not keep the shared tick delta and exact microseconds"));
    expectMovedPanGroup(ctx);
    report(ctx,
           samePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                      {{0, 32}, {kMovedTick, 96}, {kUnrelatedLate, 64}}),
           QStringLiteral("LFO normalized points did not follow the shared tick delta"));
    report(ctx, sameRaw(rig.document().lanePoints(rig.volume.track, rig.volume.controller), volume),
           QStringLiteral("unrelated volume points did not survive the selection-drag"));
    report(ctx,
           mixedSelection(rig.view().selectionModel().timeSelection(), kMovedTick,
                          kMovedTick + (kMovedTick - kSelectedTick), rig) &&
               idle(rig),
           QStringLiteral("selection-drag did not keep the mixed range or left a live gesture"));
    // Restore the seeded points, then Delete through the leftover empty mixed range (no-op).
    seedMixed(rig);
    const auto emptyDeleteBefore = snapshot(rig.document());
    rig.keyToArea(QEvent::KeyPress, Qt::Key_Delete);
    expectUnchanged(ctx, emptyDeleteBefore, "Delete over the empty leftover mixed range");
    publishMixedSelection(rig, kSelectedTick, kMovedTick);
    const auto deleteBefore = snapshot(rig.document());
    rig.keyToArea(QEvent::KeyPress, Qt::Key_Delete);
    expectOneCommittedEdit(ctx, deleteBefore, "mixed Delete");
    report(ctx,
           samePoints(effectiveTempo(rig.document()), {{0, 80}, {kUnrelatedLate, 64}}) &&
               tempoUsAt(rig.document(), kSelectedTick) == 0,
           QStringLiteral("mixed Delete did not remove the selected Tempo point"));
    report(
        ctx,
        sameRaw(rig.document().lanePoints(rig.pan.track, rig.pan.controller),
                {{0, 80}, {kUnrelatedLate, 110}}) &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, kSelectedTick).empty(),
        QStringLiteral("mixed Delete left pan group events or removed unrelated pan points"));
    report(
        ctx,
        samePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                   {{0, 32}, {kUnrelatedLate, 64}}),
        QStringLiteral("mixed Delete left the selected LFO point or removed unrelated LFO points"));
    report(ctx,
           sameRaw(rig.document().lanePoints(rig.volume.track, rig.volume.controller), volume) &&
               idle(rig),
           QStringLiteral("mixed Delete mutated unrelated volume points or left a live gesture"));
    restoreLfo(rig, initialLfo);
}

void runStaleBatch(Context &ctx)
{
    auto &rig = ctx.rig;
    if (!requirePanLfo(ctx))
        return;
    const auto initialLfo = rig.document().lanePoints(rig.lfo.track, rig.lfo.controller);
    seedMixed(rig);
    publishMixedSelection(rig, kSelectedTick, kMovedTick);
    const auto preservedBpm = tempoValue(kPreservedTempoUs);
    const auto before = snapshot(rig.document());
    const auto end = shiftDragPreview(rig, LaneHandle{0}, kSelectedTick, kMovedTick, preservedBpm);
    expectUnchanged(ctx, before, "stale-batch preview");
    // Public documentChanged rebuilds the stack and cancels; release must not commit.
    rig.documentChanged();
    rig.mouseRelease(end, Qt::ShiftModifier);
    rig.pump();
    report(ctx, unchanged(before, snapshot(rig.document())),
           QStringLiteral("stale rebuild release committed a revision or undo"));
    report(ctx,
           samePoints(effectiveTempo(rig.document()),
                      {{0, 80}, {kSelectedTick, preservedBpm}, {kUnrelatedLate, 64}}) &&
               tempoUsAt(rig.document(), kSelectedTick) == kPreservedTempoUs &&
               samePoints(effectiveLane(rig.document(), rig.pan.track, rig.pan.controller),
                          {{0, 80}, {kSelectedTick, 20}, {kUnrelatedLate, 110}}) &&
               rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, kSelectedTick) ==
                   std::vector<int>{10, 20} &&
               samePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                          {{0, 32}, {kSelectedTick, 96}, {kUnrelatedLate, 64}}),
           QStringLiteral("stale rebuild release moved a mixed-selection lane"));
    report(
        ctx,
        mixedSelection(rig.view().selectionModel().timeSelection(), kSelectedTick, kMovedTick,
                       rig) &&
            idle(rig),
        QStringLiteral("stale rebuild release moved the mixed selection or left a live gesture"));
    restoreLfo(rig, initialLfo);
}

void runPanLfoRangeEdit(Context &ctx)
{
    auto &rig = ctx.rig;
    if (!requirePanLfo(ctx))
        return;
    const auto panHandle = rig.handleFor(rig.pan);
    const auto initialLfo = rig.document().lanePoints(rig.lfo.track, rig.lfo.controller);
    const auto volume =
        laneValues(rig.document().lanePoints(rig.volume.track, rig.volume.controller));
    seedMixed(rig, true);
    publishMixedSelection(rig, kSelectedTick, kMovedTick, false);
    const auto preservedBpm = tempoValue(kPreservedTempoUs);
    const auto before = snapshot(rig.document());
    const auto end = shiftDragPreview(rig, panHandle, kSelectedTick, kMovedTick, 20);
    expectUnchanged(ctx, before, "pan+LFO selection-drag preview");
    rig.mouseRelease(end, Qt::ShiftModifier);
    expectOneCommittedEdit(ctx, before, "pan+LFO selection-drag");
    report(ctx,
           samePoints(effectiveTempo(rig.document()),
                      {{0, 80}, {kSelectedTick, preservedBpm}, {kUnrelatedLate, 64}}) &&
               tempoUsAt(rig.document(), kSelectedTick) == kPreservedTempoUs,
           QStringLiteral("pan+LFO RangeEdit moved Tempo"));
    expectMovedPanGroup(ctx);
    report(ctx,
           samePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                      {{0, 32}, {kMovedTick, 96}, {kUnrelatedLate, 64}}),
           QStringLiteral("LFO did not follow the pan+LFO shared tick delta"));
    report(
        ctx,
        sameRaw(rig.document().lanePoints(rig.volume.track, rig.volume.controller), volume) &&
            mixedSelection(rig.view().selectionModel().timeSelection(), kMovedTick,
                           kMovedTick + (kMovedTick - kSelectedTick), rig, false) &&
            idle(rig),
        QStringLiteral("pan+LFO RangeEdit mutated volume, dropped the range, or left a gesture"));
    restoreLfo(rig, initialLfo);
}

constexpr std::array kCrossLaneScenarios{
    Scenario{"tempo-pan-lfo", runTempoPanLfo},
    Scenario{"stale-batch", runStaleBatch},
    Scenario{"pan-lfo", runPanLfoRangeEdit},
};

} // namespace

void runNodeLaneCrossLaneParity(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    for (const auto &scenario : kCrossLaneScenarios) {
        Context ctx{rig, check, scenario.name};
        scenario.run(ctx);
    }
}
