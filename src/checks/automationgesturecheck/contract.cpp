#include "domains.h"
#include "support.h"

#include <array>
#include <cstdint>
#include <limits>
#include <vector>

#include <QCoreApplication>
#include <QPointF>
#include <QString>
#include <QUndoStack>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/laneselection.h"
#include "ui/editordrawer/nodelane/batchcommit.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/m4asemantics.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

enum class AdapterKind { Tempo, Cc };

struct Session {
    SongDocument &document;
    songview::EditorSelectionModel &selection;
    uint32_t usedTrackMask = 0;
    int engineTrack = 0;
    uint8_t controller = 11;
};

struct Adapter {
    AdapterKind kind = AdapterKind::Tempo;
    const char *name = "";
    NodeLane *lane = nullptr;
};

struct CaseContext {
    Session &session;
    Adapter &adapter;
    const char *row = "";
    Check check;

    CaseContext(Session &session, Adapter &adapter, const char *row,
                const AutomationGestureCheck &fn)
        : session(session)
        , adapter(adapter)
        , row(row)
        , check(fn, QStringLiteral("%1 %2").arg(QLatin1String(adapter.name), QLatin1String(row)))
    {}
};

struct Case {
    const char *name;
    void (*run)(const CaseContext &);
};

constexpr uint32_t kPreservedTempoUs = 499999;
constexpr uint32_t kFractionalTempoUs = 398406;

TempoPoint tempoAt(uint64_t tick, int bpm)
{
    return {tick, tempoUsForBpm(bpm)};
}

void setTempo(SongDocument &document, const std::vector<TempoPoint> &points)
{
    if (document.tempoPoints() == points)
        return;
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = points;
    document.applyTempoEdit(edit);
}

void setLaneValues(SongDocument &document, int track, uint8_t controller,
                   const std::vector<SongDocument::LanePointValue> &points)
{
    document.writeLanePoints(track, controller, 0, std::numeric_limits<uint64_t>::max(), points);
}

void insertCcEvent(SongDocument &document, int track, uint8_t controller, uint64_t tick, int value)
{
    SmfEvent event;
    event.tick = tick;
    event.status = uint8_t((0xB << 4) | (document.channelFor(track) & 0x0F));
    event.data0 = controller;
    event.data1 = uint8_t(value);
    document.insertRawEvent(document.smfTrackFor(track), event);
}

void seedUnique(const CaseContext &context, const std::vector<NodePoint> &points)
{
    auto &document = context.session.document;
    if (context.adapter.kind == AdapterKind::Tempo) {
        std::vector<TempoPoint> tempo;
        tempo.reserve(points.size());
        for (const auto &point : points)
            tempo.push_back(tempoAt(point.tick, point.value));
        setTempo(document, tempo);
        return;
    }
    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const auto &point : points)
        values.push_back({point.tick, point.value});
    setLaneValues(document, context.session.engineTrack, context.session.controller, values);
}

void expectPoints(const CaseContext &context, const std::vector<NodePoint> &expected)
{
    const auto actual = context.adapter.lane->points();
    context.check.require(
        sameNodePoints(actual, expected),
        QStringLiteral("expected %1, got %2").arg(formatPoints(expected), formatPoints(actual)));
}

void expectOneEdit(const CaseContext &context, const DocSnapshot &before)
{
    const auto after = snapshot(context.session.document);
    context.check.require(
        isOneEdit(before, after),
        QStringLiteral("expected revision %1 and undo %2, got revision %3 and undo %4")
            .arg(before.revision + 1)
            .arg(before.undoIndex + 1)
            .arg(after.revision)
            .arg(after.undoIndex));
}

bool applyMoves(const CaseContext &context, const std::vector<NodePointMove> &moves)
{
    auto &document = context.session.document;
    SongDocument::RangeEdit edit;
    if (context.adapter.kind == AdapterKind::Tempo) {
        const auto resolved = nodelane::resolveTempoMoves(document, moves);
        if (!resolved)
            return false;
        nodelane::appendResolvedTempoMoves(edit, *resolved);
    } else {
        const auto resolved = nodelane::resolveCcMoves(document, context.session.engineTrack,
                                                       context.session.controller, moves);
        if (!resolved)
            return false;
        nodelane::appendResolvedCcMoves(edit, *resolved);
    }
    if (edit.empty())
        return false;
    document.applyRangeEdit(QStringLiteral("automation test move"), edit);
    return true;
}

bool applyDeletes(const CaseContext &context, const std::vector<uint64_t> &ticks)
{
    auto &document = context.session.document;
    std::vector<uint64_t> tempoTicks;
    std::vector<nodelane::CcDeleteRequest> ccDeletes;
    if (context.adapter.kind == AdapterKind::Tempo)
        tempoTicks = ticks;
    else if (!ticks.empty())
        ccDeletes.push_back({context.session.engineTrack, context.session.controller, ticks});
    const auto edit = nodelane::resolveBatchDeletes(document, tempoTicks, ccDeletes);
    if (!edit || edit->empty())
        return false;
    document.applyRangeEdit(QStringLiteral("automation test delete"), *edit);
    return true;
}

void checkUndoRestores(const CaseContext &context, const DocSnapshot &before,
                       const std::vector<NodePoint> &beforePoints,
                       const std::vector<NodePoint> &afterPoints)
{
    auto &document = context.session.document;
    auto &lane = *context.adapter.lane;
    document.undoStack()->undo();
    const auto undone = snapshot(document);
    context.check.require(
        undone.undoIndex == before.undoIndex && undone.smf == before.smf &&
            sameNodePoints(lane.points(), beforePoints),
        QStringLiteral("undo did not restore SMF, undo index, and points %1 (got %2)")
            .arg(formatPoints(beforePoints))
            .arg(formatPoints(lane.points())));
    document.undoStack()->redo();
    const auto redone = snapshot(document);
    context.check.require(
        redone.undoIndex == before.undoIndex + 1 && sameNodePoints(lane.points(), afterPoints),
        QStringLiteral("redo did not restore points %1 or the committed undo index (got %2)")
            .arg(formatPoints(afterPoints))
            .arg(redone.undoIndex));
    document.undoStack()->undo();
}

QString expectedTitle(const CaseContext &context)
{
    if (context.adapter.kind == AdapterKind::Tempo)
        return QCoreApplication::translate("AutomationCanvas", "Tempo (BPM)");
    const auto info = m4aClassifyCc(context.session.controller);
    return QStringLiteral("%1 (%2)").arg(QLatin1String(info.display), QLatin1String(info.name));
}

void selectTicks(const CaseContext &context, uint64_t start, uint64_t end, bool coverThisLane)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = start;
    selection.endTick = end;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    if (coverThisLane) {
        if (context.adapter.kind == AdapterKind::Tempo)
            selection.tempo = true;
        else
            selection.lanes.push_back({context.session.engineTrack, context.session.controller});
    } else if (context.adapter.kind == AdapterKind::Tempo) {
        selection.lanes.push_back({context.session.engineTrack, context.session.controller});
    } else {
        selection.tempo = true;
    }
    context.session.selection.setTimeSelection(std::move(selection));
}

void checkEffectivePoints(const CaseContext &context)
{
    auto &document = context.session.document;
    auto &lane = *context.adapter.lane;
    seedUnique(context, {});
    context.check.require(lane.points().empty(),
                          QStringLiteral("empty lane exposed %1").arg(formatPoints(lane.points())));
    if (context.adapter.kind == AdapterKind::Tempo) {
        setTempo(document, {tempoAt(288, 110), tempoAt(0, 120), tempoAt(96, 150)});
        expectPoints(context, {{0, 120}, {96, 150}, {288, 110}});
        return;
    }
    setLaneValues(document, context.session.engineTrack, context.session.controller, {});
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 288, 40);
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 0, 64);
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 96, 10);
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 96, 20);
    expectPoints(context, {{0, 64}, {96, 20}, {288, 40}});
    const auto sameTick =
        rawValuesAt(document, context.session.engineTrack, context.session.controller, 96);
    context.check.require(sameTick == std::vector<int>{10, 20},
                          QStringLiteral("same-tick seed did not keep both raw events in order"));
}

void checkRangesTextSelection(const CaseContext &context)
{
    auto &lane = *context.adapter.lane;
    auto &selection = context.session.selection;
    selection.clearTimeSelection();
    context.check.require(lane.title() == expectedTitle(context),
                          QStringLiteral("title was %1").arg(lane.title()));
    if (context.adapter.kind == AdapterKind::Tempo) {
        context.check.require(lane.minimumValue() == CoreTimeDefaults::kMinTempoBpm &&
                                  lane.maximumValue() == CoreTimeDefaults::kMaxTempoBpm,
                              QStringLiteral("Tempo range was [%1, %2]")
                                  .arg(lane.minimumValue())
                                  .arg(lane.maximumValue()));
        setTempo(context.session.document, {tempoAt(0, 150), {96, kFractionalTempoUs}});
        const auto fractional = tempoBpm(kFractionalTempoUs);
        context.check.require(lane.valueText(150) == QStringLiteral("150") &&
                                  lane.valueText(fractional) == QString::number(fractional),
                              QStringLiteral("Tempo valueText was %1 / %2")
                                  .arg(lane.valueText(150), lane.valueText(fractional)));
        const auto points = lane.points();
        context.check.require(
            points.size() == 2 && points[1].value == fractional,
            QStringLiteral("fractional Tempo node was %1").arg(formatPoints(points)));
    } else {
        context.check.require(
            lane.minimumValue() == CoreTimeDefaults::laneValueMinimum(context.session.controller) &&
                lane.maximumValue() ==
                    CoreTimeDefaults::laneValueMaximum(context.session.controller),
            QStringLiteral("CC range was [%1, %2]")
                .arg(lane.minimumValue())
                .arg(lane.maximumValue()));
        context.check.require(
            lane.valueText(64) == m4aFormatCcValue(context.session.controller, 64) &&
                lane.valueText(0) == m4aFormatCcValue(context.session.controller, 0),
            QStringLiteral("CC valueText was %1 / %2").arg(lane.valueText(64), lane.valueText(0)));
        CCLaneAdapter bend(context.session.document, context.session.engineTrack, DOC_CC_BEND);
        context.check.require(bend.minimumValue() == CoreTimeDefaults::kMinBendValue &&
                                  bend.maximumValue() == CoreTimeDefaults::kMaxBendValue &&
                                  bend.valueText(0) == m4aFormatBend(0) &&
                                  bend.valueText(100) == m4aFormatBend(100),
                              QStringLiteral("bend range/text was [%1, %2] %3")
                                  .arg(bend.minimumValue())
                                  .arg(bend.maximumValue())
                                  .arg(bend.valueText(0)));
    }
    uint32_t usedTrackMask = 0;
    const auto trackCount = context.session.document.engineTrackCount();
    for (int track = 0; track < trackCount && track < 16; ++track)
        usedTrackMask |= uint32_t{1} << track;
    const std::vector<AutomationRow> rows{
        {EditorAutomationRowId{EditorAutomationRowKind::ControlChange,
                               uint8_t(context.session.engineTrack), context.session.controller}}};
    const LaneSelection laneSelection(context.session.selection, rows, usedTrackMask);
    const auto selectionId = context.adapter.kind == AdapterKind::Tempo
                                 ? EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0}
                                 : EditorAutomationRowId{EditorAutomationRowKind::ControlChange,
                                                         uint8_t(context.session.engineTrack),
                                                         context.session.controller};
    selectTicks(context, 50, 150, true);
    const auto coveredRange = laneSelection.activeTickRange();
    context.check.require(
        coveredRange && coveredRange->first == 50 && coveredRange->second == 150 &&
            laneSelection.coversLane(selectionId),
        QStringLiteral("LaneSelection did not cover the selected lane and tick range"));
    selectTicks(context, 50, 150, false);
    const auto uncoveredRange = laneSelection.activeTickRange();
    context.check.require(uncoveredRange && uncoveredRange->first == 50 &&
                              uncoveredRange->second == 150 &&
                              !laneSelection.coversLane(selectionId),
                          QStringLiteral("LaneSelection covered an unselected lane"));
    selection.clearTimeSelection();
    context.check.require(!laneSelection.active() && !laneSelection.coversLane(selectionId),
                          QStringLiteral("cleared time selection remained active"));
}

void checkDelete(const CaseContext &context)
{
    auto &lane = *context.adapter.lane;
    const std::vector<NodePoint> fixture{{0, 120}, {96, 100}, {288, 110}};
    seedUnique(context, fixture);
    const auto before = snapshot(context.session.document);
    applyDeletes(context, {});
    context.check.require(isUnchanged(before, snapshot(context.session.document)),
                          QStringLiteral("empty delete mutated the document"));
    applyDeletes(context, {uint64_t{99999}});
    context.check.require(isUnchanged(before, snapshot(context.session.document)),
                          QStringLiteral("unknown-tick delete mutated the document"));
    applyDeletes(context, {uint64_t{96}});
    expectOneEdit(context, before);
    expectPoints(context, {{0, 120}, {288, 110}});
    if (context.adapter.kind == AdapterKind::Cc) {
        context.check.require(rawValuesAt(context.session.document, context.session.engineTrack,
                                          context.session.controller, 96)
                                  .empty(),
                              QStringLiteral("delete left raw events at the removed tick"));
    }
    checkUndoRestores(context, before, fixture, {{0, 120}, {288, 110}});
    if (context.adapter.kind != AdapterKind::Cc)
        return;
    setLaneValues(context.session.document, context.session.engineTrack, context.session.controller,
                  {{0, 64}});
    insertCcEvent(context.session.document, context.session.engineTrack, context.session.controller,
                  96, 10);
    insertCcEvent(context.session.document, context.session.engineTrack, context.session.controller,
                  96, 20);
    const auto grouped = snapshot(context.session.document);
    const auto groupedPoints = lane.points();
    applyDeletes(context, {uint64_t{96}});
    expectOneEdit(context, grouped);
    expectPoints(context, {{0, 64}});
    context.check.require(rawValuesAt(context.session.document, context.session.engineTrack,
                                      context.session.controller, 96)
                              .empty(),
                          QStringLiteral("same-tick delete left hidden events"));
    checkUndoRestores(context, grouped, groupedPoints, {{0, 64}});
}

void checkMove(const CaseContext &context)
{
    auto &document = context.session.document;
    auto &lane = *context.adapter.lane;
    if (context.adapter.kind == AdapterKind::Tempo) {
        setTempo(document, {{96, kPreservedTempoUs}, tempoAt(288, 110)});
        const auto before = snapshot(document);
        const auto beforePoints = lane.points();
        applyMoves(context, {});
        context.check.require(isUnchanged(before, snapshot(document)),
                              QStringLiteral("empty move mutated the document"));
        applyMoves(context, {{uint64_t{99999}, NodePoint{192, 120}}});
        context.check.require(isUnchanged(before, snapshot(document)),
                              QStringLiteral("unknown-tick move mutated the document"));
        const auto preservedBpm = tempoBpm(kPreservedTempoUs);
        applyMoves(context, {{uint64_t{96}, NodePoint{192, preservedBpm}}});
        expectOneEdit(context, before);
        expectPoints(context, {{192, preservedBpm}, {288, 110}});
        const auto moved = document.tempoPoints();
        context.check.require(moved.size() == 2 && moved.front().tick == 192 &&
                                  moved.front().microsecondsPerQuarterNote == kPreservedTempoUs,
                              QStringLiteral("unchanged-value Tempo move discarded microseconds"));
        checkUndoRestores(context, before, beforePoints, {{192, preservedBpm}, {288, 110}});
        const auto rewriteBefore = snapshot(document);
        const auto rewriteBeforePoints = lane.points();
        applyMoves(context, {{uint64_t{96}, NodePoint{192, 140}}});
        expectOneEdit(context, rewriteBefore);
        expectPoints(context, {{192, 140}, {288, 110}});
        const auto rewritten = document.tempoPoints();
        context.check.require(
            rewritten.size() == 2 && rewritten.front().tick == 192 &&
                rewritten.front().microsecondsPerQuarterNote == tempoUsForBpm(140),
            QStringLiteral("value-changing Tempo move did not rewrite microseconds"));
        checkUndoRestores(context, rewriteBefore, rewriteBeforePoints, {{192, 140}, {288, 110}});
        return;
    }
    setLaneValues(document, context.session.engineTrack, context.session.controller, {{288, 40}});
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 96, 10);
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 96, 20);
    const auto before = snapshot(document);
    const auto beforePoints = lane.points();
    applyMoves(context, {});
    context.check.require(isUnchanged(before, snapshot(document)),
                          QStringLiteral("empty move mutated the document"));
    applyMoves(context, {{uint64_t{99999}, NodePoint{192, 20}}});
    context.check.require(isUnchanged(before, snapshot(document)),
                          QStringLiteral("unknown-tick move mutated the document"));
    applyMoves(context, {{uint64_t{96}, NodePoint{192, 20}}});
    expectOneEdit(context, before);
    expectPoints(context, {{192, 20}, {288, 40}});
    context.check.require(
        rawValuesAt(document, context.session.engineTrack, context.session.controller, 96)
                .empty() &&
            rawValuesAt(document, context.session.engineTrack, context.session.controller, 192) ==
                std::vector<int>{10, 20},
        QStringLiteral("CC same-tick move did not keep the group ordered at the destination"));
    checkUndoRestores(context, before, beforePoints, {{192, 20}, {288, 40}});
}

void checkReplaceSpan(const CaseContext &context)
{
    auto &document = context.session.document;
    auto &lane = *context.adapter.lane;
    seedUnique(context, {});
    const auto emptyBefore = snapshot(document);
    lane.replaceSpan(0, 10000, {});
    context.check.require(
        isUnchanged(emptyBefore, snapshot(document)) && lane.points().empty(),
        QStringLiteral("empty replaceSpan on an empty lane mutated the document"));
    lane.replaceSpan(0, 10000, {{96, 90}});
    expectOneEdit(context, emptyBefore);
    expectPoints(context, {{96, 90}});
    checkUndoRestores(context, emptyBefore, {}, {{96, 90}});
    const std::vector<NodePoint> fixture{{0, 120}, {96, 100}, {288, 110}};
    seedUnique(context, fixture);
    const auto before = snapshot(document);
    lane.replaceSpan(96, 96, {{96, 100}});
    context.check.require(isUnchanged(before, snapshot(document)),
                          QStringLiteral("identical replaceSpan mutated the document"));
    lane.replaceSpan(96, 200, {{96, 80}, {128, 70}});
    expectOneEdit(context, before);
    expectPoints(context, {{0, 120}, {96, 80}, {128, 70}, {288, 110}});
    checkUndoRestores(context, before, fixture, {{0, 120}, {96, 80}, {128, 70}, {288, 110}});
    const auto clearBefore = snapshot(document);
    lane.replaceSpan(0, 10000, {});
    expectOneEdit(context, clearBefore);
    expectPoints(context, {});
    checkUndoRestores(context, clearBefore, fixture, {});
    if (context.adapter.kind != AdapterKind::Tempo)
        return;
    setTempo(document, {{96, kFractionalTempoUs}});
    const auto displayed = tempoBpm(kFractionalTempoUs);
    const auto fractionalBefore = snapshot(document);
    const auto fractionalBeforePoints = lane.points();
    lane.replaceSpan(96, 96, {{96, displayed}});
    expectOneEdit(context, fractionalBefore);
    expectPoints(context, {{96, displayed}});
    const auto converted = document.tempoPoints();
    const auto expectedUs = tempoUsForBpm(displayed);
    context.check.require(converted.size() == 1 && converted.front().tick == 96 &&
                              converted.front().microsecondsPerQuarterNote == expectedUs,
                          QStringLiteral("fractional Tempo replaceSpan preserved microseconds"));
    checkUndoRestores(context, fractionalBefore, fractionalBeforePoints, {{96, displayed}});
}

void checkMoveCollision(const CaseContext &context)
{
    auto &document = context.session.document;
    auto &lane = *context.adapter.lane;
    if (context.adapter.kind == AdapterKind::Tempo) {
        setTempo(document, {{96, kPreservedTempoUs}, tempoAt(288, 110)});
        const auto before = snapshot(document);
        const auto beforePoints = lane.points();
        const auto preservedBpm = tempoBpm(kPreservedTempoUs);
        applyMoves(context, {{uint64_t{96}, NodePoint{288, preservedBpm}}});
        expectOneEdit(context, before);
        expectPoints(context, {{288, preservedBpm}});
        const auto moved = document.tempoPoints();
        context.check.require(
            moved.size() == 1 && moved.front().tick == 288 &&
                moved.front().microsecondsPerQuarterNote == kPreservedTempoUs,
            QStringLiteral("Tempo move onto an occupied tick did not keep exactly one "
                           "destination with source microseconds"));
        checkUndoRestores(context, before, beforePoints, {{288, preservedBpm}});
        return;
    }
    setLaneValues(document, context.session.engineTrack, context.session.controller, {{288, 40}});
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 96, 10);
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 96, 20);
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 192, 70);
    insertCcEvent(document, context.session.engineTrack, context.session.controller, 192, 80);
    const auto before = snapshot(document);
    const auto beforePoints = lane.points();
    applyMoves(context, {{uint64_t{96}, NodePoint{192, 20}}});
    expectOneEdit(context, before);
    expectPoints(context, {{192, 20}, {288, 40}});
    context.check.require(
        rawValuesAt(document, context.session.engineTrack, context.session.controller, 96)
                .empty() &&
            rawValuesAt(document, context.session.engineTrack, context.session.controller, 192) ==
                std::vector<int>{10, 20},
        QStringLiteral("CC move onto an occupied tick left destination ghosts or reordered the "
                       "source group"));
    checkUndoRestores(context, before, beforePoints, {{192, 20}, {288, 40}});
}

void checkEngineDefaultNodes(Session &session, const AutomationGestureCheck &fn)
{
    Check check{fn, QStringLiteral("engine-default")};
    auto &document = session.document;
    setLaneValues(document, session.engineTrack, 7, {});
    setLaneValues(document, session.engineTrack, 10, {});
    setLaneValues(document, session.engineTrack, 1, {});
    CCLaneAdapter volume(document, session.engineTrack, 7);
    CCLaneAdapter pan(document, session.engineTrack, 10);
    CCLaneAdapter modulation(document, session.engineTrack, 1);
    check.require(sameNodePoints(volume.points(), {{0, 127}}),
                  QStringLiteral("Volume did not expose its engine-default tick-zero node"));
    check.require(sameNodePoints(pan.points(), {{0, 64}}),
                  QStringLiteral("Pan did not expose its engine-default tick-zero node"));
    check.require(modulation.points().empty(),
                  QStringLiteral("a non-Volume/Pan lane exposed a synthetic default node"));

    const auto checkPromotion = [&](CCLaneAdapter &lane, uint8_t controller, int value,
                                    const QString &name) {
        const auto before = snapshot(document);
        const auto resolved = nodelane::resolveCcMoves(document, session.engineTrack, controller,
                                                       {{uint64_t{0}, NodePoint{96, value}}});
        SongDocument::RangeEdit edit;
        if (resolved)
            nodelane::appendResolvedCcMoves(edit, *resolved);
        check.require(resolved && !edit.empty(),
                      QStringLiteral("%1 engine-default move could not be resolved").arg(name));
        if (!resolved || edit.empty())
            return;
        document.applyRangeEdit(QStringLiteral("automation test move"), edit);
        const auto raw = document.lanePoints(session.engineTrack, controller);
        check.require(isOneEdit(before, snapshot(document)) && raw.size() == 1 &&
                          raw.front().tick == 96 && raw.front().value == value,
                      QStringLiteral("%1 engine-default node did not promote to one document point")
                          .arg(name));
        document.undoStack()->undo();
        check.require(snapshot(document).smf == before.smf &&
                          sameNodePoints(lane.points(), {{0, controller == 7 ? 127 : 64}}),
                      QStringLiteral("%1 default-node promotion did not undo cleanly").arg(name));
    };
    checkPromotion(volume, 7, 100, QStringLiteral("Volume"));
    checkPromotion(pan, 10, 32, QStringLiteral("Pan"));
}

std::vector<SmfEvent> noteEvents(const SongDocument &document, int engineTrack)
{
    const int smfTrack = document.smfTrackFor(engineTrack);
    std::vector<SmfEvent> notes;
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return notes;
    for (const SmfEvent &event : document.smf().tracks[size_t(smfTrack)].events) {
        if (event.isNoteOn() || event.isNoteEnd())
            notes.push_back(event);
    }
    return notes;
}

std::vector<std::pair<uint8_t, uint8_t>> xcmdBytes(const SongDocument &document, int engineTrack)
{
    const int smfTrack = document.smfTrackFor(engineTrack);
    std::vector<std::pair<uint8_t, uint8_t>> bytes;
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return bytes;
    for (const SmfEvent &event : document.smf().tracks[size_t(smfTrack)].events) {
        if ((event.status >> 4) != 0xB)
            continue;
        if (event.data0 == xcmd::kSelectorController || event.data0 == xcmd::kPayloadController ||
            event.data0 == xcmd::kAlternatePayloadController)
            bytes.emplace_back(event.data0, event.data1);
    }
    return bytes;
}

std::vector<std::pair<uint8_t, uint8_t>> xcmdBytesAt(const SongDocument &document, int engineTrack,
                                                     uint64_t tick)
{
    std::vector<std::pair<uint8_t, uint8_t>> bytes;
    const int smfTrack = document.smfTrackFor(engineTrack);
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return bytes;
    for (const SmfEvent &event : document.smf().tracks[std::size_t(smfTrack)].events) {
        if (event.tick != tick || (event.status >> 4) != 0xB)
            continue;
        if (event.data0 == xcmd::kSelectorController || event.data0 == xcmd::kPayloadController ||
            event.data0 == xcmd::kAlternatePayloadController)
            bytes.emplace_back(event.data0, event.data1);
    }
    return bytes;
}

QString formatXcmdBytes(const std::vector<std::pair<uint8_t, uint8_t>> &bytes)
{
    QStringList parts;
    for (const auto &[controller, value] : bytes)
        parts.append(QStringLiteral("%1:%2").arg(controller).arg(value));
    return QStringLiteral("[%1]").arg(parts.join(QStringLiteral(", ")));
}

void checkLogicalXcmdOccurrences(Session &session, const AutomationGestureCheck &fn)
{
    Check check{fn, QStringLiteral("xcmd-occurrences")};
    auto &document = session.document;
    const int track = session.engineTrack;

    // Every known point is an explicit selector+payload pair; points never
    // share a selector event. Deleting one point of an epoch rebuilds the
    // epoch: the survivor is re-emitted as its own pair, and no dead
    // selector stays behind.
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(track, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 96, 34);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 192, 35);
    auto volume = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    check.require(volume.size() == 2 &&
                      xcmdBytesAt(document, track, 96) ==
                          std::vector<std::pair<uint8_t, uint8_t>>{
                              {xcmd::kSelectorController, 0x08}, {xcmd::kPayloadController, 34}} &&
                      xcmdBytesAt(document, track, 192) ==
                          std::vector<std::pair<uint8_t, uint8_t>>{
                              {xcmd::kSelectorController, 0x08}, {xcmd::kPayloadController, 35}},
                  QStringLiteral("two echo points did not each get an explicit selector+payload "
                                 "pair"));
    document.deleteLanePoints(track, DOC_CC_ECHO_VOLUME, {volume[0]});
    volume = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    check.require(
        volume.size() == 1 && volume.front().tick == 192 && volume.front().value == 35 &&
            xcmdBytesAt(document, track, 96).empty() &&
            xcmdBytesAt(document, track, 192) ==
                std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                         {xcmd::kPayloadController, 35}},
        QStringLiteral("deleting the first of two points did not rebuild the survivor as an "
                       "explicit pair"));
    document.deleteLanePoints(track, DOC_CC_ECHO_VOLUME, {volume[0]});
    check.require(document.lanePoints(track, DOC_CC_ECHO_VOLUME).empty() &&
                      xcmdBytes(document, track).empty(),
                  QStringLiteral("deleting the last point left protocol events behind"));

    // Moving one point of a known epoch is a canonical rebuild: the whole
    // epoch leaves, the survivor is re-emitted as its own explicit pair, and
    // the moved point lands as its own pair at the destination.
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 96, 34);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 192, 35);
    volume = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    document.moveLanePoints({{track, DOC_CC_ECHO_VOLUME, volume[0], 384, 36}});
    volume = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    check.require(
        volume.size() == 2 &&
            xcmdBytesAt(document, track, 384) ==
                std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                         {xcmd::kPayloadController, 36}} &&
            xcmdBytesAt(document, track, 96).empty() &&
            xcmdBytesAt(document, track, 192) ==
                std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                         {xcmd::kPayloadController, 35}},
        QStringLiteral("moving one of two points did not rebuild the survivor and destination as "
                       "explicit pairs"));
    document.writeLanePoints(track, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});

    // Moving into the span of a disjoint known epoch rebuilds both epochs as
    // explicit pairs (no restoration bytes); only a collision with an opaque
    // epoch's span is rejected atomically.
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 96, 34);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 96, 17);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 192, 18);
    check.require(document.lanePoints(track, DOC_CC_ECHO_LENGTH).size() == 2 &&
                      xcmdBytesAt(document, track, 192) ==
                          std::vector<std::pair<uint8_t, uint8_t>>{
                              {xcmd::kSelectorController, 0x09}, {xcmd::kPayloadController, 18}},
                  QStringLiteral("second length point did not get its own explicit pair"));
    volume = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    document.moveLanePoints({{track, DOC_CC_ECHO_VOLUME, volume.front(), 160, 36}});
    volume = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    check.require(
        volume.size() == 1 && volume.front().tick == 160 && volume.front().value == 36 &&
            xcmdBytesAt(document, track, 160) ==
                std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                         {xcmd::kPayloadController, 36}} &&
            xcmdBytesAt(document, track, 96) ==
                std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x09},
                                                         {xcmd::kPayloadController, 17}} &&
            xcmdBytesAt(document, track, 192) ==
                std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x09},
                                                         {xcmd::kPayloadController, 18}},
        QStringLiteral("move into another known epoch's span did not rebuild both epochs as "
                       "explicit pairs"));
    document.writeLanePoints(track, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});

    // A write inside an opaque epoch's occupied tick span is rejected
    // atomically: the opaque bytes would be re-rolled by a canonical pair.
    insertCcEvent(document, track, xcmd::kSelectorController, 0, 0x01);
    insertCcEvent(document, track, xcmd::kPayloadController, 1, 1);
    insertCcEvent(document, track, xcmd::kPayloadController, 2, 2);
    const auto opaqueBefore = snapshot(document);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 1, 30);
    check.require(isUnchanged(opaqueBefore, snapshot(document)),
                  QStringLiteral("write inside an opaque epoch's span was not rejected"));
    document.undoStack()->undo();
    document.undoStack()->undo();
    document.undoStack()->undo();

    // Malformed and multi-byte traffic is preserved byte-identically across
    // lane writes: a dangling four-byte fragment and a stray payload after
    // an unsupported selector survive untouched.
    insertCcEvent(document, track, xcmd::kSelectorController, 4, 0x01);
    insertCcEvent(document, track, xcmd::kPayloadController, 5, 1);
    insertCcEvent(document, track, xcmd::kPayloadController, 6, 2);
    insertCcEvent(document, track, xcmd::kSelectorController, 8, 0x03);
    insertCcEvent(document, track, xcmd::kPayloadController, 9, 99);
    const auto rawBefore = snapshot(document);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 400, 30);
    check.require(
        snapshot(document).revision == rawBefore.revision + 1 &&
            xcmdBytes(document, track) ==
                std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x01},
                                                         {xcmd::kPayloadController, 1},
                                                         {xcmd::kPayloadController, 2},
                                                         {xcmd::kSelectorController, 0x03},
                                                         {xcmd::kPayloadController, 99},
                                                         {xcmd::kSelectorController, 0x08},
                                                         {xcmd::kPayloadController, 30}},
        QStringLiteral("lane write disturbed dangling or stray XCMD traffic"));
    // A write that would turn the stray payload into consumed XCMD traffic
    // must fail without mutating anything.
    const auto rejectedBefore = snapshot(document);
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 8, 8, {{8, 30}});
    check.require(isUnchanged(rejectedBefore, snapshot(document)),
                  QStringLiteral("stray-consuming rewrite was not rejected without mutation"));
    document.undoStack()->undo(); // drop the addLanePoint above
    document.undoStack()->undo();
    document.undoStack()->undo();
    document.undoStack()->undo();
    document.undoStack()->undo();
    document.undoStack()->undo(); // back past the five raw inserts
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(track, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});

    // Lane-scoped time ranges: cutting the Echo Volume lane removes its
    // point atomically and leaves the Echo Length lane byte-identical; no
    // selector survives for the removed lane.
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 96, 34);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 96, 17);
    const auto rangeBefore = snapshot(document);
    SongDocument::TimeScope volumeScope;
    volumeScope.lanes = {{track, uint8_t(DOC_CC_ECHO_VOLUME)}};
    const bool removed = document.removeTimeRange({96, 192}, volumeScope);
    check.require(removed && document.lanePoints(track, DOC_CC_ECHO_VOLUME).empty() &&
                      xcmdBytesAt(document, track, 96) ==
                          std::vector<std::pair<uint8_t, uint8_t>>{
                              {xcmd::kSelectorController, 0x09}, {xcmd::kPayloadController, 17}},
                  QStringLiteral("lane-scoped cut left volume events or removed length events"));
    document.undoStack()->undo();
    check.require(document.smf().write() == rangeBefore.smf,
                  QStringLiteral("lane cut undo was not byte-identical"));
    document.undoStack()->redo();
    document.undoStack()->undo();
    document.writeLanePoints(track, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});

    // A whole-song cut rebuilds the surviving shifted point as an explicit
    // pair at its new tick; nothing of the removed range survives. Undo is
    // byte-identical.
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, 96, 34);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 96, 17);
    document.addLanePoint(track, DOC_CC_ECHO_LENGTH, 192, 18);
    const auto cutBefore = snapshot(document);
    SongDocument::TimeScope wholeSong;
    wholeSong.wholeSong = true;
    check.require(document.removeTimeRange({96, 192}, wholeSong),
                  QStringLiteral("whole-song cut did not mutate"));
    const auto volumeAfter = document.lanePoints(track, DOC_CC_ECHO_VOLUME);
    const auto lengthAfter = document.lanePoints(track, DOC_CC_ECHO_LENGTH);
    check.require(volumeAfter.empty() && lengthAfter.size() == 1 &&
                      lengthAfter.front().tick == 96 && lengthAfter.front().value == 18 &&
                      xcmdBytesAt(document, track, 96) ==
                          std::vector<std::pair<uint8_t, uint8_t>>{
                              {xcmd::kSelectorController, 0x09}, {xcmd::kPayloadController, 18}},
                  QStringLiteral("whole-song cut did not rebuild the shifted survivor as an "
                                 "explicit pair; got %1")
                      .arg(formatXcmdBytes(xcmdBytesAt(document, track, 96))));
    document.undoStack()->undo();
    check.require(document.smf().write() == cutBefore.smf,
                  QStringLiteral("whole-song cut undo was not byte-identical"));
    document.undoStack()->redo();
    check.require(document.lanePoints(track, DOC_CC_ECHO_VOLUME).empty() &&
                      document.lanePoints(track, DOC_CC_ECHO_LENGTH).size() == 1,
                  QStringLiteral("whole-song cut redo did not reproduce the state"));
}

void checkLogicalXcmdEdits(Session &session, const AutomationGestureCheck &fn)
{
    Check check{fn, QStringLiteral("xcmd-edits")};
    auto &document = session.document;
    document.writeLanePoints(session.engineTrack, DOC_CC_ECHO_VOLUME, 0,
                             std::numeric_limits<uint64_t>::max(), {});
    document.writeLanePoints(session.engineTrack, DOC_CC_ECHO_LENGTH, 0,
                             std::numeric_limits<uint64_t>::max(), {});
    const auto before = snapshot(document);

    document.addLanePoint(session.engineTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    document.addLanePoint(session.engineTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    const std::vector<std::pair<uint8_t, uint8_t>> expected{
        {xcmd::kSelectorController, 0x08},
        {xcmd::kPayloadController, 34},
        {xcmd::kSelectorController, 0x09},
        {xcmd::kPayloadController, 17},
    };
    const auto volume = document.lanePoints(session.engineTrack, DOC_CC_ECHO_VOLUME);
    const auto length = document.lanePoints(session.engineTrack, DOC_CC_ECHO_LENGTH);
    check.require(volume.size() == 1 && volume.front().tick == 96 && volume.front().value == 34 &&
                      length.size() == 1 && length.front().tick == 96 &&
                      length.front().value == 17 &&
                      xcmdBytesAt(document, session.engineTrack, 96) == expected,
                  QStringLiteral("logical echo lanes did not write ordered canonical XCMD pairs"));

    const auto moveBefore = snapshot(document);
    document.moveLanePoints({{session.engineTrack, DOC_CC_ECHO_VOLUME, volume.front(), 192, 35}});
    const auto moved = document.lanePoints(session.engineTrack, DOC_CC_ECHO_VOLUME);
    const std::vector<std::pair<uint8_t, uint8_t>> movedBytes{
        {xcmd::kSelectorController, 0x08},
        {xcmd::kPayloadController, 35},
    };
    check.require(isOneEdit(moveBefore, snapshot(document)) && moved.size() == 1 &&
                      moved.front().tick == 192 && moved.front().value == 35 &&
                      xcmdBytesAt(document, session.engineTrack, 192) == movedBytes,
                  QStringLiteral("moving a logical echo lane did not preserve canonical XCMD "
                                 "framing"));

    document.undoStack()->undo();
    document.undoStack()->undo();
    document.undoStack()->undo();
    check.require(snapshot(document).smf == before.smf &&
                      document.lanePoints(session.engineTrack, DOC_CC_ECHO_VOLUME).empty() &&
                      document.lanePoints(session.engineTrack, DOC_CC_ECHO_LENGTH).empty(),
                  QStringLiteral("logical echo-lane edits did not undo to the original SMF"));
}

void checkXcmdSweepPreservesNotes(Session &session, const AutomationGestureCheck &fn)
{
    Check check{fn, QStringLiteral("xcmd-note-preservation")};
    auto &document = session.document;
    const int track = document.engineTrackCount() > 3 ? 3 : session.engineTrack;
    const auto before = snapshot(document);
    document.writeLanePoints(track, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(track, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});

    constexpr uint64_t dragBegin = 8736;
    constexpr uint64_t noteBegin = 8772;
    constexpr uint64_t noteEnd = 8808;
    constexpr uint64_t existingPoint = 8844;
    SmfEvent noteOn;
    noteOn.tick = noteBegin;
    noteOn.status = uint8_t((0x9 << 4) | (document.channelFor(track) & 0x0F));
    noteOn.data0 = 60;
    noteOn.data1 = 100;
    SmfEvent noteOff = noteOn;
    noteOff.tick = noteEnd;
    noteOff.status = uint8_t((0x8 << 4) | (document.channelFor(track) & 0x0F));
    noteOff.data1 = 0;
    document.insertRawEvent(document.smfTrackFor(track), noteOn);
    document.insertRawEvent(document.smfTrackFor(track), noteOff);
    document.addLanePoint(track, DOC_CC_ECHO_VOLUME, existingPoint, 48);
    const auto notesBeforeSweep = noteEvents(document, track);

    CCLaneAdapter xIecvLane(document, track, DOC_CC_ECHO_VOLUME);
    xIecvLane.replaceSpan(dragBegin, existingPoint, {{dragBegin, 32}, {existingPoint, 48}});
    check.require(
        noteEvents(document, track) == notesBeforeSweep &&
            sameRawPoints(document.lanePoints(track, DOC_CC_ECHO_VOLUME),
                          {{dragBegin, 32}, {existingPoint, 48}}),
        QStringLiteral("cross-measure xIECV sweep deleted or changed intervening note events"));

    while (document.undoStack()->index() > before.undoIndex)
        document.undoStack()->undo();
    check.require(snapshot(document).smf == before.smf,
                  QStringLiteral("xIECV note-preservation setup did not undo cleanly"));
}

void checkRowRebuildHandles(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    const Check rowCheck{check, QStringLiteral("lane-rebuild")};
    constexpr uint8_t insertedController = 11;
    const AutomationGestureCheckRig::Lane inserted{
        {EditorAutomationRowKind::ControlChange, 0, insertedController}, 0, insertedController};
    if (!rig.expandTempo()) {
        rowCheck.require(false, QStringLiteral("Tempo body was not available before row rebuild"));
        return;
    }

    const auto tempoBefore = AutomationGestureCheckRig::kTempoHandle;
    const auto panBefore = rig.handleFor(rig.pan);
    const auto lfoBefore = rig.handleFor(rig.lfo);
    const auto rowMatches = [&rig](LaneHandle handle, const EditorAutomationRowId &id) {
        const auto &rows = rig.canvas().rows();
        const int row = handle.index - 1;
        return handle.index > 0 && row < int(rows.size()) && rows[std::size_t(row)].id == id;
    };
    rowCheck.require(rowMatches(panBefore, rig.pan.row) && rowMatches(lfoBefore, rig.lfo.row) &&
                         !rig.bodyFor(tempoBefore).isEmpty(),
                     QStringLiteral("initial lane handles did not resolve their row identities"));

    const auto grabbed = rig.pointAt(rig.lfo, kFixtureTick, 96);
    const auto activation =
        grabbed.position + QPointF(rig.geometry().nodeDragActivationDistance + 2, 0.0);
    const auto before = snapshot(rig.document());
    rig.mousePress(grabbed.position);
    rig.mouseMove(activation);
    rig.pump();
    rowCheck.require(isUnchanged(before, snapshot(rig.document())),
                     QStringLiteral("arming a row-rebuild stale-handle gesture mutated data"));

    rig.page().addEmptyLane(inserted.track, inserted.controller);
    rig.pump();
    const auto insertedHandle = rig.handleFor(inserted);
    const auto panAfter = rig.handleFor(rig.pan);
    const auto lfoAfter = rig.handleFor(rig.lfo);
    rowCheck.require(rowMatches(panAfter, rig.pan.row) && rowMatches(lfoAfter, rig.lfo.row) &&
                         rowMatches(insertedHandle, inserted.row) &&
                         lfoAfter.index == lfoBefore.index + 1 &&
                         !rig.bodyFor(tempoBefore).isEmpty(),
                     QStringLiteral("row rebuild lost Tempo/CC handle identity or ordering"));
    rowCheck.require(rig.bodyFor(LaneHandle{}).isEmpty() && rig.bodyFor(LaneHandle{9999}).isEmpty(),
                     QStringLiteral("invalid lane handles resolved to a body"));

    rig.mouseRelease(activation);
    rig.pump();
    rowCheck.require(isUnchanged(before, snapshot(rig.document())) && rig.isIdle(),
                     QStringLiteral("release after a row rebuild committed a stale lane handle "
                                    "or changed the undo count"));

    rig.page().removeEmptyLane(inserted.track, inserted.controller);
    rig.pump();
    rowCheck.require(rig.handleFor(rig.pan) == panBefore && rig.handleFor(rig.lfo) == lfoBefore &&
                         rowMatches(rig.handleFor(rig.pan), rig.pan.row) &&
                         rowMatches(rig.handleFor(rig.lfo), rig.lfo.row),
                     QStringLiteral("removing the rebuilt row did not restore CC handle mapping"));
}

constexpr std::array kCases{
    Case{"points", checkEffectivePoints},
    Case{"ranges", checkRangesTextSelection},
    Case{"delete", checkDelete},
    Case{"move", checkMove},
    Case{"move-collision", checkMoveCollision},
    Case{"replace-span", checkReplaceSpan},
};

} // namespace

void checkNodeContract(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    auto &document = rig.document();
    if (document.engineTrackCount() <= 0 || document.smfTrackFor(0) < 0) {
        check(false, QStringLiteral("fixture has no engine track 0"));
        return;
    }
    checkRowRebuildHandles(rig, check);
    songview::EditorSelectionModel selection;
    auto usedTrackMask = uint32_t{0};
    for (int track = 0; track < document.engineTrackCount() && track < 16; ++track)
        usedTrackMask |= uint32_t{1} << track;
    TempoLane tempoLane(document);
    CCLaneAdapter ccLane(document, 0, uint8_t{11});
    Session session{document, selection, usedTrackMask, 0, uint8_t{11}};
    std::array adapters{
        Adapter{AdapterKind::Tempo, "Tempo", &tempoLane},
        Adapter{AdapterKind::Cc, "CC", &ccLane},
    };
    for (const auto &row : kCases) {
        for (auto &adapter : adapters) {
            CaseContext context{session, adapter, row.name, check};
            row.run(context);
        }
    }
    checkEngineDefaultNodes(session, check);
    checkLogicalXcmdEdits(session, check);
    checkXcmdSweepPreservesNotes(session, check);
    checkLogicalXcmdOccurrences(session, check);
}
