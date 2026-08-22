#include "domains.h"
#include "support.h"

#include <array>
#include <cstdint>
#include <limits>
#include <vector>

#include <QCoreApplication>
#include <QString>
#include <QUndoStack>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "rig.h"
#include "ui/editordrawer/cclanes.h"
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
            .arg(formatPoints(beforePoints), formatPoints(lane.points())));
    document.undoStack()->redo();
    context.check.require(sameNodePoints(lane.points(), afterPoints),
                          QStringLiteral("redo did not restore points %1 (got %2)")
                              .arg(formatPoints(afterPoints), formatPoints(lane.points())));
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
        CCLaneAdapter bend(context.session.document, context.session.selection,
                           context.session.usedTrackMask, context.session.engineTrack, DOC_CC_BEND);
        context.check.require(bend.minimumValue() == CoreTimeDefaults::kMinBendValue &&
                                  bend.maximumValue() == CoreTimeDefaults::kMaxBendValue &&
                                  bend.valueText(0) == m4aFormatBend(0) &&
                                  bend.valueText(100) == m4aFormatBend(100),
                              QStringLiteral("bend range/text was [%1, %2] %3")
                                  .arg(bend.minimumValue())
                                  .arg(bend.maximumValue())
                                  .arg(bend.valueText(0)));
    }
    seedUnique(context, {{0, 120}, {96, 100}, {288, 110}});
    selectTicks(context, 50, 150, true);
    context.check.require(
        !lane.pointSelected(0) && lane.pointSelected(50) && lane.pointSelected(96) &&
            !lane.pointSelected(150) && !lane.pointSelected(288),
        QStringLiteral("time-selection membership was wrong for the covered lane"));
    selectTicks(context, 50, 150, false);
    context.check.require(!lane.pointSelected(50) && !lane.pointSelected(96) &&
                              !lane.pointSelected(0),
                          QStringLiteral("uncovered lane reported a selected tick"));
    selection.clearTimeSelection();
    context.check.require(!lane.pointSelected(96),
                          QStringLiteral("cleared time selection still selected a tick"));
}

void checkDelete(const CaseContext &context)
{
    auto &lane = *context.adapter.lane;
    const std::vector<NodePoint> fixture{{0, 120}, {96, 100}, {288, 110}};
    seedUnique(context, fixture);
    const auto before = snapshot(context.session.document);
    lane.deletePoints({});
    context.check.require(isUnchanged(before, snapshot(context.session.document)),
                          QStringLiteral("empty delete mutated the document"));
    lane.deletePoints({uint64_t{99999}});
    context.check.require(isUnchanged(before, snapshot(context.session.document)),
                          QStringLiteral("unknown-tick delete mutated the document"));
    lane.deletePoints({uint64_t{96}});
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
    lane.deletePoints({uint64_t{96}});
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
        lane.movePoints({});
        context.check.require(isUnchanged(before, snapshot(document)),
                              QStringLiteral("empty move mutated the document"));
        lane.movePoints({{uint64_t{99999}, NodePoint{192, 120}}});
        context.check.require(isUnchanged(before, snapshot(document)),
                              QStringLiteral("unknown-tick move mutated the document"));
        const auto preservedBpm = tempoBpm(kPreservedTempoUs);
        lane.movePoints({{uint64_t{96}, NodePoint{192, preservedBpm}}});
        expectOneEdit(context, before);
        expectPoints(context, {{192, preservedBpm}, {288, 110}});
        const auto moved = document.tempoPoints();
        context.check.require(moved.size() == 2 && moved.front().tick == 192 &&
                                  moved.front().microsecondsPerQuarterNote == kPreservedTempoUs,
                              QStringLiteral("unchanged-value Tempo move discarded microseconds"));
        checkUndoRestores(context, before, beforePoints, {{192, preservedBpm}, {288, 110}});
        const auto rewriteBefore = snapshot(document);
        const auto rewriteBeforePoints = lane.points();
        lane.movePoints({{uint64_t{96}, NodePoint{192, 140}}});
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
    lane.movePoints({});
    context.check.require(isUnchanged(before, snapshot(document)),
                          QStringLiteral("empty move mutated the document"));
    lane.movePoints({{uint64_t{99999}, NodePoint{192, 20}}});
    context.check.require(isUnchanged(before, snapshot(document)),
                          QStringLiteral("unknown-tick move mutated the document"));
    lane.movePoints({{uint64_t{96}, NodePoint{192, 20}}});
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
        lane.movePoints({{uint64_t{96}, NodePoint{288, preservedBpm}}});
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
    lane.movePoints({{uint64_t{96}, NodePoint{192, 20}}});
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
    CCLaneAdapter volume(document, session.selection, session.usedTrackMask, session.engineTrack,
                         7);
    CCLaneAdapter pan(document, session.selection, session.usedTrackMask, session.engineTrack, 10);
    CCLaneAdapter modulation(document, session.selection, session.usedTrackMask,
                             session.engineTrack, 1);
    check.require(sameNodePoints(volume.points(), {{0, 127}}),
                  QStringLiteral("Volume did not expose its engine-default tick-zero node"));
    check.require(sameNodePoints(pan.points(), {{0, 64}}),
                  QStringLiteral("Pan did not expose its engine-default tick-zero node"));
    check.require(modulation.points().empty(),
                  QStringLiteral("a non-Volume/Pan lane exposed a synthetic default node"));

    const auto checkPromotion = [&](CCLaneAdapter &lane, uint8_t controller, int value,
                                    const QString &name) {
        const auto before = snapshot(document);
        lane.movePoints({{uint64_t{0}, NodePoint{96, value}}});
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
    songview::EditorSelectionModel selection;
    auto usedTrackMask = uint32_t{0};
    for (int track = 0; track < document.engineTrackCount() && track < 16; ++track)
        usedTrackMask |= uint32_t{1} << track;
    TempoLane tempoLane(document, selection, usedTrackMask);
    CCLaneAdapter ccLane(document, selection, usedTrackMask, 0, uint8_t{11});
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
}
