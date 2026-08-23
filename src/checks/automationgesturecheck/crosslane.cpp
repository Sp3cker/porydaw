#include "domains.h"
#include "support.h"

#include <array>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

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
    Check check;
    const char *scenario = "";

    Context(AutomationGestureCheckRig &rig, const AutomationGestureCheck &fn, const char *scenario)
        : rig(rig)
        , check(fn, QStringLiteral("cross-lane %1").arg(QLatin1String(scenario)))
        , scenario(scenario)
    {}
};

struct Scenario {
    const char *name;
    void (*run)(Context &);
};

constexpr uint32_t kPreservedTempoUs = 499999;
constexpr uint64_t kMovedTick = 144;
constexpr uint64_t kUnrelatedLate = 384;

std::vector<SongDocument::LanePointValue> laneValues(const std::vector<DocLanePoint> &points)
{
    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const auto &point : points)
        values.push_back({point.tick, point.value});
    return values;
}

std::vector<NodePoint> effectiveTempo(const SongDocument &document)
{
    std::vector<NodePoint> out;
    for (const auto &point : document.tempoPoints())
        out.push_back({point.tick, tempoBpm(point.microsecondsPerQuarterNote)});
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

uint32_t tempoUsAt(const SongDocument &document, uint64_t tick)
{
    for (const auto &point : document.tempoPoints()) {
        if (point.tick == tick)
            return point.microsecondsPerQuarterNote;
    }
    return 0;
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
    edit.add = {{0, tempoUsForBpm(80)},
                {kFixtureTick, kPreservedTempoUs},
                {kUnrelatedLate, tempoUsForBpm(64)}};
    if (rig.document().tempoPoints() != edit.add)
        rig.document().applyTempoEdit(edit);
    if (occupyMovedPan)
        writeLane(rig.document(), rig.pan,
                  {{0, 80},
                   {kFixtureTick, 10},
                   {kFixtureTick, 20},
                   {kMovedTick, 70},
                   {kMovedTick, 80},
                   {kUnrelatedLate, 110}});
    else
        writeLane(rig.document(), rig.pan,
                  {{0, 80}, {kFixtureTick, 10}, {kFixtureTick, 20}, {kUnrelatedLate, 110}});
    writeLane(rig.document(), rig.lfo, {{0, 32}, {kFixtureTick, 96}, {kUnrelatedLate, 64}});
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

void expectUnchanged(const Context &ctx, const DocSnapshot &before, const char *label)
{
    ctx.check.require(
        isUnchanged(before, snapshot(ctx.rig.document())),
        QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
}

bool requirePanLfo(Context &ctx)
{
    if (ctx.rig.handleFor(ctx.rig.pan).valid() && ctx.rig.handleFor(ctx.rig.lfo).valid())
        return true;
    ctx.check.require(false, QStringLiteral("pan or LFO lane body is missing"));
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
void runBandIsolation(Context &ctx)
{
    auto &rig = ctx.rig;
    if (!requirePanLfo(ctx) || !rig.expandTempo()) {
        ctx.check.require(false, QStringLiteral("Tempo, pan, or LFO lane body is missing"));
        return;
    }
    seedMixed(rig);
    auto &selectionModel = rig.view().selectionModel();
    selectionModel.clearTimeSelection();
    rig.pump();

    const int selectedBpm = tempoBpm(kPreservedTempoUs);
    const QPointF tempoStart = rig.tempoBodyPoint(kFixtureTick - 24, selectedBpm);
    const QPointF panEnd = rig.pointAt(rig.pan, kMovedTick, 64).position;
    rig.mousePress(tempoStart, Qt::NoModifier, Qt::RightButton);
    rig.mouseMove(panEnd, Qt::RightButton);
    rig.mouseRelease(panEnd, Qt::NoModifier, Qt::RightButton);
    rig.pump();

    const auto &tempoSelection = selectionModel.timeSelection();
    ctx.check.require(
        tempoSelection.active() &&
            tempoSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
            tempoSelection.tempo && tempoSelection.lanes.empty() &&
            selectionModel.timeSelectionCoversTempo(1u) &&
            !selectionModel.timeSelectionCoversLane(rig.pan.track, rig.pan.controller, 1u) &&
            !selectionModel.timeSelectionCoversLane(rig.lfo.track, rig.lfo.controller, 1u),
        QStringLiteral("Tempo band selection leaked into CC rows"));

    const auto beforeTempoDrag = snapshot(rig.document());
    const auto panBefore = laneValues(rig.document().lanePoints(rig.pan.track, rig.pan.controller));
    const auto lfoBefore = laneValues(rig.document().lanePoints(rig.lfo.track, rig.lfo.controller));
    const QPointF tempoDragEnd =
        shiftDragPreview(rig, LaneHandle{0}, kFixtureTick, kMovedTick, selectedBpm);
    rig.mouseRelease(tempoDragEnd, Qt::ShiftModifier);
    rig.pump();
    ctx.check.require(
        isOneEdit(beforeTempoDrag, snapshot(rig.document())) &&
            sameRawPoints(rig.document().lanePoints(rig.pan.track, rig.pan.controller),
                          panBefore) &&
            sameRawPoints(rig.document().lanePoints(rig.lfo.track, rig.lfo.controller), lfoBefore),
        QStringLiteral("dragging a Tempo band selection moved a CC row"));

    rig.document().undoStack()->undo();
    rig.documentChanged();
    selectionModel.clearTimeSelection();
    rig.pump();

    const QPointF ccStart = rig.pointAt(rig.volume, kFixtureTick - 24, 64).position;
    const QPointF ccEnd = rig.pointAt(rig.volume, kMovedTick, 64).position;
    rig.mousePress(ccStart, Qt::NoModifier, Qt::RightButton);
    rig.mouseMove(ccEnd, Qt::RightButton);
    rig.mouseRelease(ccEnd, Qt::NoModifier, Qt::RightButton);
    rig.pump();

    const auto &ccSelection = selectionModel.timeSelection();
    ctx.check.require(
        ccSelection.active() &&
            ccSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
            !ccSelection.tempo &&
            ccSelection.lanes ==
                std::vector<std::pair<int, uint8_t>>{{rig.volume.track, rig.volume.controller}} &&
            !selectionModel.timeSelectionCoversTempo(1u),
        QStringLiteral("CC band selection leaked into Tempo"));
}

void expectOneCommittedEdit(const Context &ctx, const DocSnapshot &before, const char *label)
{
    auto &document = ctx.rig.document();
    const auto after = snapshot(document);
    ctx.check.require(isOneEdit(before, after),
                      QStringLiteral("%1 did not commit exactly one revision and one undo")
                          .arg(QLatin1String(label)));
    document.undoStack()->undo();
    const auto undone = snapshot(document);
    ctx.check.require(
        undone.undoIndex == before.undoIndex && undone.smf == before.smf,
        QStringLiteral("%1 undo did not restore SMF and undo index").arg(QLatin1String(label)));
    document.undoStack()->redo();
    const auto redone = snapshot(document);
    ctx.check.require(
        redone.undoIndex == after.undoIndex && redone.smf == after.smf,
        QStringLiteral("%1 redo did not restore the committed SMF").arg(QLatin1String(label)));
}

void expectMovedPanGroup(const Context &ctx)
{
    auto &document = ctx.rig.document();
    const auto &pan = ctx.rig.pan;
    ctx.check.require(
        sameNodePoints(effectiveLane(document, pan.track, pan.controller),
                       {{0, 80}, {kMovedTick, 20}, {kUnrelatedLate, 110}}) &&
            rawValuesAt(document, pan.track, pan.controller, kFixtureTick).empty() &&
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
    publishMixedSelection(rig, kFixtureTick, kMovedTick);
    const auto preservedBpm = tempoBpm(kPreservedTempoUs);
    const auto hoverBefore = snapshot(rig.document());
    rig.mouseMove(rig.pointAt(LaneHandle{0}, kFixtureTick, preservedBpm).position, Qt::NoButton);
    rig.pump();
    expectUnchanged(ctx, hoverBefore, "mixed-selection hover");
    // Horizontal Shift-drag of the selected Tempo node; pan and LFO must follow in one edit.
    // Selection is [96, 144) so the hidden pan occupant at 144 is not selected.
    const auto dragBefore = snapshot(rig.document());
    const auto end = shiftDragPreview(rig, LaneHandle{0}, kFixtureTick, kMovedTick, preservedBpm);
    expectUnchanged(ctx, dragBefore, "mixed selection-drag preview");
    rig.mouseRelease(end, Qt::ShiftModifier);
    expectOneCommittedEdit(ctx, dragBefore, "selection-drag");
    ctx.check.require(
        sameNodePoints(effectiveTempo(rig.document()),
                       {{0, 80}, {kMovedTick, preservedBpm}, {kUnrelatedLate, 64}}) &&
            tempoUsAt(rig.document(), kMovedTick) == kPreservedTempoUs,
        QStringLiteral("Tempo did not keep the shared tick delta and exact microseconds"));
    expectMovedPanGroup(ctx);
    ctx.check.require(
        sameNodePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                       {{0, 32}, {kMovedTick, 96}, {kUnrelatedLate, 64}}),
        QStringLiteral("LFO normalized points did not follow the shared tick delta"));
    ctx.check.require(
        sameRawPoints(rig.document().lanePoints(rig.volume.track, rig.volume.controller), volume),
        QStringLiteral("unrelated volume points did not survive the selection-drag"));
    ctx.check.require(
        mixedSelection(rig.view().selectionModel().timeSelection(), kMovedTick,
                       kMovedTick + (kMovedTick - kFixtureTick), rig) &&
            rig.isIdle(),
        QStringLiteral("selection-drag did not keep the mixed range or left a live gesture"));
    // Restore the seeded points, then Delete through the leftover empty mixed range (no-op).
    seedMixed(rig);
    const auto emptyDeleteBefore = snapshot(rig.document());
    rig.keyToArea(QEvent::KeyPress, Qt::Key_Delete);
    expectUnchanged(ctx, emptyDeleteBefore, "Delete over the empty leftover mixed range");
    publishMixedSelection(rig, kFixtureTick, kMovedTick);
    const auto deleteBefore = snapshot(rig.document());
    rig.keyToArea(QEvent::KeyPress, Qt::Key_Delete);
    expectOneCommittedEdit(ctx, deleteBefore, "mixed Delete");
    ctx.check.require(
        sameNodePoints(effectiveTempo(rig.document()), {{0, 80}, {kUnrelatedLate, 64}}) &&
            tempoUsAt(rig.document(), kFixtureTick) == 0,
        QStringLiteral("mixed Delete did not remove the selected Tempo point"));
    ctx.check.require(
        sameRawPoints(rig.document().lanePoints(rig.pan.track, rig.pan.controller),
                      {{0, 80}, {kUnrelatedLate, 110}}) &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, kFixtureTick).empty(),
        QStringLiteral("mixed Delete left pan group events or removed unrelated pan points"));
    ctx.check.require(
        sameNodePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                       {{0, 32}, {kUnrelatedLate, 64}}),
        QStringLiteral("mixed Delete left the selected LFO point or removed unrelated LFO points"));
    ctx.check.require(
        sameRawPoints(rig.document().lanePoints(rig.volume.track, rig.volume.controller), volume) &&
            rig.isIdle(),
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
    publishMixedSelection(rig, kFixtureTick, kMovedTick);
    const auto preservedBpm = tempoBpm(kPreservedTempoUs);
    const auto before = snapshot(rig.document());
    const auto end = shiftDragPreview(rig, LaneHandle{0}, kFixtureTick, kMovedTick, preservedBpm);
    expectUnchanged(ctx, before, "stale-batch preview");
    // Public documentChanged rebuilds the stack and cancels; release must not commit.
    rig.documentChanged();
    rig.mouseRelease(end, Qt::ShiftModifier);
    rig.pump();
    ctx.check.require(isUnchanged(before, snapshot(rig.document())),
                      QStringLiteral("stale rebuild release committed a revision or undo"));
    ctx.check.require(
        sameNodePoints(effectiveTempo(rig.document()),
                       {{0, 80}, {kFixtureTick, preservedBpm}, {kUnrelatedLate, 64}}) &&
            tempoUsAt(rig.document(), kFixtureTick) == kPreservedTempoUs &&
            sameNodePoints(effectiveLane(rig.document(), rig.pan.track, rig.pan.controller),
                           {{0, 80}, {kFixtureTick, 20}, {kUnrelatedLate, 110}}) &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, kFixtureTick) ==
                std::vector<int>{10, 20} &&
            sameNodePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                           {{0, 32}, {kFixtureTick, 96}, {kUnrelatedLate, 64}}),
        QStringLiteral("stale rebuild release moved a mixed-selection lane"));
    ctx.check.require(
        mixedSelection(rig.view().selectionModel().timeSelection(), kFixtureTick, kMovedTick,
                       rig) &&
            rig.isIdle(),
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
    publishMixedSelection(rig, kFixtureTick, kMovedTick, false);
    const auto preservedBpm = tempoBpm(kPreservedTempoUs);
    const auto before = snapshot(rig.document());
    const auto end = shiftDragPreview(rig, panHandle, kFixtureTick, kMovedTick, 20);
    expectUnchanged(ctx, before, "pan+LFO selection-drag preview");
    rig.mouseRelease(end, Qt::ShiftModifier);
    expectOneCommittedEdit(ctx, before, "pan+LFO selection-drag");
    ctx.check.require(
        sameNodePoints(effectiveTempo(rig.document()),
                       {{0, 80}, {kFixtureTick, preservedBpm}, {kUnrelatedLate, 64}}) &&
            tempoUsAt(rig.document(), kFixtureTick) == kPreservedTempoUs,
        QStringLiteral("pan+LFO RangeEdit moved Tempo"));
    expectMovedPanGroup(ctx);
    ctx.check.require(
        sameNodePoints(effectiveLane(rig.document(), rig.lfo.track, rig.lfo.controller),
                       {{0, 32}, {kMovedTick, 96}, {kUnrelatedLate, 64}}),
        QStringLiteral("LFO did not follow the pan+LFO shared tick delta"));
    ctx.check.require(
        sameRawPoints(rig.document().lanePoints(rig.volume.track, rig.volume.controller), volume) &&
            mixedSelection(rig.view().selectionModel().timeSelection(), kMovedTick,
                           kMovedTick + (kMovedTick - kFixtureTick), rig, false) &&
            rig.isIdle(),
        QStringLiteral("pan+LFO RangeEdit mutated volume, dropped the range, or left a gesture"));
    restoreLfo(rig, initialLfo);
}

// One raw 0xB channel byte of the stream, for exact byte-level assertions.
struct CcByte {
    uint64_t tick = 0;
    uint8_t data0 = 0;
    uint8_t data1 = 0;
};

bool sameCcBytes(const std::vector<CcByte> &left, const std::vector<CcByte> &right)
{
    if (left.size() != right.size())
        return false;
    for (auto i = std::size_t{0}; i < left.size(); ++i) {
        if (left[i].tick != right[i].tick || left[i].data0 != right[i].data0 ||
            left[i].data1 != right[i].data1)
            return false;
    }
    return true;
}

QString formatCcBytes(const std::vector<CcByte> &bytes)
{
    QString formatted;
    for (const CcByte &byte : bytes)
        formatted += QStringLiteral(" {%1,%2,%3}").arg(byte.tick).arg(byte.data0).arg(byte.data1);
    return formatted;
}

std::vector<CcByte> ccChain(const SongDocument &document, int engineTrack)
{
    std::vector<CcByte> bytes;
    const int smfTrack = document.smfTrackFor(engineTrack);
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return bytes;
    for (const SmfEvent &event : document.smf().tracks[std::size_t(smfTrack)].events) {
        if (!event.isChannel() || event.typeNibble() != 0xB)
            continue;
        if (event.data0 == 7 || event.data0 == 10 || event.data0 == xcmd::kSelectorController ||
            event.data0 == xcmd::kPayloadController ||
            event.data0 == xcmd::kAlternatePayloadController)
            bytes.push_back({event.tick, event.data0, event.data1});
    }
    return bytes;
}

void clearXcmd(SongDocument &document, int track)
{
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(track, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});
}

// Deterministic baseline around the XCMD traffic: an untouched raw CC pair on
// the same track (pan/volume), so byte-level comparisons prove unrelated
// events survive edits byte-for-byte.
void seedXcmdBaseline(AutomationGestureCheckRig &rig)
{
    auto &document = rig.document();
    const int track = rig.pan.track;
    document.writeLanePoints(track, rig.pan.controller, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, 80}, {384, 110}});
    document.writeLanePoints(track, rig.volume.controller, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, 64}, {288, 48}});
    rig.documentChanged();
}

std::vector<SongDocument::LanePointValue> laneFor(SongDocument &document, int track,
                                                  uint8_t controller)
{
    std::vector<SongDocument::LanePointValue> values;
    for (const DocLanePoint &point : document.lanePoints(track, controller))
        values.push_back({point.tick, point.value});
    return values;
}

void runXcmdRemoveOnly(Context &ctx)
{
    auto &rig = ctx.rig;
    auto &document = rig.document();
    const int track = rig.pan.track;
    const auto initialPan = laneFor(document, track, rig.pan.controller);
    const auto initialVolume = laneFor(document, track, rig.volume.controller);
    clearXcmd(document, track);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 96, 34);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 192, 35);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 96, 17);
    seedXcmdBaseline(rig);
    const auto before = snapshot(document);
    // The batch-delete gesture builds exactly this shape: removePoints only,
    // no XCMD lane write anywhere in the edit.
    SongDocument::RangeEdit edit;
    edit.removePoints.push_back(document.lanePoints(track, DOC_CC_ECHO_VOLUME).front());
    edit.removePoints.push_back(document.lanePoints(track, DOC_CC_ECHO_LENGTH).front());
    document.applyRangeEdit(QStringLiteral("xcmd remove-only"), edit);
    expectOneCommittedEdit(ctx, before, "remove-only XCMD batch");
    const auto volume = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    ctx.check.require(
        volume.size() == 1 && volume.front().tick == 192 && volume.front().value == 35 &&
            document.lanePoints(track, DOC_CC_ECHO_LENGTH).empty(),
        QStringLiteral("remove-only batch kept a deleted point or lost the survivor"));
    ctx.check.require(
        sameCcBytes(ccChain(document, track), {{0, 0x0A, 80},
                                               {0, 0x07, 64},
                                               {192, xcmd::kSelectorController, 0x08},
                                               {192, xcmd::kPayloadController, 35},
                                               {288, 0x07, 48},
                                               {384, 0x0A, 110}}),
        QStringLiteral("remove-only batch left dead protocol bytes behind or touched unrelated "
                       "events"));
    clearXcmd(document, track);
    document.writeLanePoints(track, rig.pan.controller, 0, std::numeric_limits<uint64_t>::max(),
                             initialPan);
    document.writeLanePoints(track, rig.volume.controller, 0, std::numeric_limits<uint64_t>::max(),
                             initialVolume);
    rig.documentChanged();
}

void runXcmdRangeMoves(Context &ctx)
{
    auto &rig = ctx.rig;
    auto &document = rig.document();
    const int track = rig.pan.track;
    const auto initialPan = laneFor(document, track, rig.pan.controller);
    const auto initialVolume = laneFor(document, track, rig.volume.controller);

    // Left move into the span of the disjoint length epoch: both epochs are
    // rebuilt as explicit pairs — the moved volume point at 144, length
    // survivors at 96 and 192 — with no restoration bytes.
    clearXcmd(document, track);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 96, 17);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 192, 18);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 192, 34);
    seedXcmdBaseline(rig);
    auto before = snapshot(document);
    document.moveRange({}, document.lanePoints(track, DOC_CC_ECHO_VOLUME), -48);
    expectOneCommittedEdit(ctx, before, "XCMD left range move");
    ctx.check.require(
        sameCcBytes(ccChain(document, track), {{0, 0x0A, 80},
                                               {0, 0x07, 64},
                                               {96, xcmd::kSelectorController, 0x09},
                                               {96, xcmd::kPayloadController, 17},
                                               {144, xcmd::kSelectorController, 0x08},
                                               {144, xcmd::kPayloadController, 34},
                                               {192, xcmd::kSelectorController, 0x09},
                                               {192, xcmd::kPayloadController, 18},
                                               {288, 0x07, 48},
                                               {384, 0x0A, 110}}),
        QStringLiteral("left move did not rebuild both epochs as explicit pairs; got%1")
            .arg(formatCcBytes(ccChain(document, track))));

    // Right move onto an unrelated length payload's tick: the destination
    // epoch and the moved point each rebuild as explicit pairs, in stream
    // order, with no duplicate selectors.
    clearXcmd(document, track);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 96, 17);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 192, 18);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 96, 34);
    seedXcmdBaseline(rig);
    before = snapshot(document);
    document.moveRange({}, document.lanePoints(track, DOC_CC_ECHO_VOLUME), 96);
    expectOneCommittedEdit(ctx, before, "XCMD right range move");
    ctx.check.require(
        sameCcBytes(ccChain(document, track), {{0, 0x0A, 80},
                                               {0, 0x07, 64},
                                               {96, xcmd::kSelectorController, 0x09},
                                               {96, xcmd::kPayloadController, 17},
                                               {192, xcmd::kSelectorController, 0x09},
                                               {192, xcmd::kPayloadController, 18},
                                               {192, xcmd::kSelectorController, 0x08},
                                               {192, xcmd::kPayloadController, 34},
                                               {288, 0x07, 48},
                                               {384, 0x0A, 110}}),
        QStringLiteral("right move did not rebuild the destination epoch and the moved point as "
                       "explicit pairs; got%1")
            .arg(formatCcBytes(ccChain(document, track))));
    clearXcmd(document, track);
    document.writeLanePoints(track, rig.pan.controller, 0, std::numeric_limits<uint64_t>::max(),
                             initialPan);
    document.writeLanePoints(track, rig.volume.controller, 0, std::numeric_limits<uint64_t>::max(),
                             initialVolume);
    rig.documentChanged();
}

// Regression: a range paste that expands the engine-track count must carry
// descriptor-lane writes onto the freshly created track through the same
// canonical plan — the new stream is empty, so its epoch is built from
// nothing instead of being silently dropped.
void runXcmdExpansionPaste(Context &ctx)
{
    auto &rig = ctx.rig;
    auto &document = rig.document();
    const int newEngineTrack = document.engineTrackCount();
    const auto before = snapshot(document);
    SongDocument::RangeEdit edit;
    edit.minimumEngineTrackCount = newEngineTrack + 1;
    edit.addNotes.push_back({newEngineTrack, {{0, 60, 96, 100}}});
    edit.addPoints.push_back({newEngineTrack, DOC_CC_ECHO_VOLUME, {{96, 34}}});
    document.applyRangeEdit(QStringLiteral("xcmd expansion paste"), edit);
    expectOneCommittedEdit(ctx, before, "expansion paste with XCMD lane");
    ctx.check.require(document.engineTrackCount() == newEngineTrack + 1,
                      QStringLiteral("paste did not create the requested track"));
    const auto volume = document.lanePoints(newEngineTrack, DOC_CC_ECHO_VOLUME);
    ctx.check.require(volume.size() == 1 && volume.front().tick == 96 && volume.front().value == 34,
                      QStringLiteral("expansion paste lost the echo volume point"));
    ctx.check.require(
        sameCcBytes(ccChain(document, newEngineTrack),
                    {{96, xcmd::kSelectorController, 0x08}, {96, xcmd::kPayloadController, 34}}),
        QStringLiteral("new-track echo point did not become a canonical epoch; got%1")
            .arg(formatCcBytes(ccChain(document, newEngineTrack))));
}

constexpr std::array kCrossLaneScenarios{
    Scenario{"band-isolation", runBandIsolation},
    Scenario{"tempo-pan-lfo", runTempoPanLfo},
    Scenario{"stale-batch", runStaleBatch},
    Scenario{"pan-lfo", runPanLfoRangeEdit},
    Scenario{"xcmd-remove-only", runXcmdRemoveOnly},
    Scenario{"xcmd-range-moves", runXcmdRangeMoves},
    Scenario{"xcmd-expansion-paste", runXcmdExpansionPaste},
};

} // namespace

void runNodeLaneCrossLaneParity(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    for (const auto &scenario : kCrossLaneScenarios) {
        Context ctx{rig, check, scenario.name};
        scenario.run(ctx);
    }
}
