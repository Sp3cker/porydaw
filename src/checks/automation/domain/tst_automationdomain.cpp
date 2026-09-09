#include "checks/automation/domain/tst_automationdomain.h"

#include <cmath>
#include <limits>
#include <optional>
#include <utility>

#include <QCoreApplication>
#include <QtTest>

#include "core/m4asemantics.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/laneselection.h"
#include "ui/editordrawer/nodelane/batchcommit.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

constexpr int kTempo = 0;
constexpr int kCc = 1;
constexpr int kTrack = 0;
constexpr uint8_t kController = 11;
constexpr uint32_t kPreservedTempoUs = 499999;
constexpr uint32_t kFractionalTempoUs = 398406;

TempoPoint tempoPoint(uint64_t tick, int bpm)
{
    return {tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm)};
}

} // namespace

void AutomationDomainTest::init()
{
    m_document = std::make_unique<SongDocument>();
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events.push_back({.tick = 0, .status = 0xC0, .data0 = 0});
    track.endTick = 9216;
    smf.tracks.push_back(std::move(track));

    SongInfo song;
    song.label = QStringLiteral("automation-domain");
    song.hasMid = true;
    QString error;
    QVERIFY2(m_document->adoptSmf(std::move(smf), song, &error), qPrintable(error));
    QCOMPARE(m_document->engineTrackCount(), 1);
    QCOMPARE(m_document->smfTrackFor(kTrack), 0);
}

void AutomationDomainTest::cleanup()
{
    m_document.reset();
}

SongDocument &AutomationDomainTest::document() const
{
    return *m_document;
}

AutomationDomainTest::Snapshot AutomationDomainTest::snapshot() const
{
    return {document().smf().write(), document().revision(), document().undoStack()->index()};
}

bool AutomationDomainTest::isOneEdit(const Snapshot &before, const Snapshot &after)
{
    return after.revision == before.revision + 1 && after.undoIndex == before.undoIndex + 1;
}

bool AutomationDomainTest::samePoints(const std::vector<NodePoint> &actual,
                                      const std::vector<NodePoint> &expected)
{
    if (actual.size() != expected.size())
        return false;
    for (std::size_t index = 0; index < actual.size(); ++index) {
        if (actual[index].tick != expected[index].tick ||
            actual[index].value != expected[index].value)
            return false;
    }
    return true;
}

std::vector<int> AutomationDomainTest::rawValuesAt(const SongDocument &document, int track,
                                                   uint8_t controller, uint64_t tick)
{
    std::vector<int> values;
    for (const DocLanePoint &point : document.lanePoints(track, controller)) {
        if (point.tick == tick)
            values.push_back(point.value);
    }
    return values;
}

int AutomationDomainTest::tempoBpm(uint32_t microsecondsPerQuarterNote)
{
    return int(std::lround(CoreTimeDefaults::tempoBpm(microsecondsPerQuarterNote)));
}

uint32_t AutomationDomainTest::tempoUsForBpm(int bpm)
{
    return CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm);
}

void AutomationDomainTest::setTempo(SongDocument &document, const std::vector<TempoPoint> &points)
{
    if (document.tempoPoints() == points)
        return;
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = points;
    document.applyTempoEdit(edit);
}

void AutomationDomainTest::setLane(SongDocument &document, int track, uint8_t controller,
                                   const std::vector<SongDocument::LanePointValue> &points)
{
    document.writeLanePoints(track, controller, 0, std::numeric_limits<uint64_t>::max(), points);
}

void AutomationDomainTest::insertCc(SongDocument &document, int track, uint8_t controller,
                                    uint64_t tick, int value)
{
    SmfEvent event;
    event.tick = tick;
    event.status = uint8_t(0xB0 | (document.channelFor(track) & 0x0F));
    event.data0 = controller;
    event.data1 = uint8_t(value);
    document.insertRawEvent(document.smfTrackFor(track), event);
}

void AutomationDomainTest::setUniquePoints(SongDocument &document, int adapterKind,
                                           const std::vector<NodePoint> &points)
{
    if (adapterKind == kTempo) {
        std::vector<TempoPoint> tempo;
        tempo.reserve(points.size());
        for (const NodePoint &point : points)
            tempo.push_back(tempoPoint(point.tick, point.value));
        setTempo(document, tempo);
        return;
    }
    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const NodePoint &point : points)
        values.push_back({point.tick, point.value});
    setLane(document, kTrack, kController, values);
}

bool AutomationDomainTest::applyMoves(SongDocument &document, int adapterKind,
                                      const std::vector<NodePointMove> &moves)
{
    SongDocument::RangeEdit edit;
    if (adapterKind == kTempo) {
        const auto resolved = nodelane::resolveTempoMoves(document, moves);
        if (!resolved)
            return false;
        nodelane::appendResolvedTempoMoves(edit, *resolved);
    } else {
        const auto resolved = nodelane::resolveCcMoves(document, kTrack, kController, moves);
        if (!resolved)
            return false;
        nodelane::appendResolvedCcMoves(edit, *resolved);
    }
    if (edit.empty())
        return false;
    document.applyRangeEdit(QStringLiteral("automation domain move"), edit);
    return true;
}

bool AutomationDomainTest::applyDeletes(SongDocument &document, int adapterKind,
                                        const std::vector<uint64_t> &ticks)
{
    std::vector<uint64_t> tempoTicks;
    std::vector<nodelane::CcDeleteRequest> ccDeletes;
    if (adapterKind == kTempo)
        tempoTicks = ticks;
    else if (!ticks.empty())
        ccDeletes.push_back({kTrack, kController, ticks});
    const auto edit = nodelane::resolveBatchDeletes(document, tempoTicks, ccDeletes);
    if (!edit || edit->empty())
        return false;
    document.applyRangeEdit(QStringLiteral("automation domain delete"), *edit);
    return true;
}
bool AutomationDomainTest::undoRedoRestores(const Snapshot &before,
                                            const std::vector<NodePoint> &beforePoints,
                                            const std::vector<NodePoint> &afterPoints,
                                            NodeLane &lane)
{
    document().undoStack()->undo();
    const bool undone = snapshot().smf == before.smf &&
                        document().undoStack()->index() == before.undoIndex &&
                        samePoints(lane.points(), beforePoints);
    document().undoStack()->redo();
    const bool redone = document().undoStack()->index() == before.undoIndex + 1 &&
                        samePoints(lane.points(), afterPoints);
    document().undoStack()->undo();
    return undone && redone && snapshot().smf == before.smf &&
           document().undoStack()->index() == before.undoIndex &&
           samePoints(lane.points(), beforePoints);
}

void AutomationDomainTest::effectivePoints_data()
{
    QTest::addColumn<int>("adapterKind");
    QTest::newRow("tempo") << kTempo;
    QTest::newRow("cc") << kCc;
}

void AutomationDomainTest::effectivePoints()
{
    QFETCH(int, adapterKind);
    SongDocument &doc = document();
    TempoLane tempo(doc);
    CCLaneAdapter cc(doc, kTrack, kController);
    NodeLane &lane =
        adapterKind == kTempo ? static_cast<NodeLane &>(tempo) : static_cast<NodeLane &>(cc);

    QVERIFY(lane.points().empty());
    if (adapterKind == kTempo) {
        setTempo(doc, {tempoPoint(288, 110), tempoPoint(0, 120), tempoPoint(96, 150)});
        QVERIFY(samePoints(lane.points(), {{0, 120}, {96, 150}, {288, 110}}));
        return;
    }

    insertCc(doc, kTrack, kController, 288, 40);
    insertCc(doc, kTrack, kController, 0, 64);
    insertCc(doc, kTrack, kController, 96, 10);
    insertCc(doc, kTrack, kController, 96, 20);
    QVERIFY(samePoints(lane.points(), {{0, 64}, {96, 20}, {288, 40}}));
    QVERIFY(rawValuesAt(doc, kTrack, kController, 96) == (std::vector<int>{10, 20}));
}

void AutomationDomainTest::rangesAndSelection_data()
{
    effectivePoints_data();
}

void AutomationDomainTest::rangesAndSelection()
{
    QFETCH(int, adapterKind);
    SongDocument &doc = document();
    TempoLane tempo(doc);
    CCLaneAdapter cc(doc, kTrack, kController);
    NodeLane &lane =
        adapterKind == kTempo ? static_cast<NodeLane &>(tempo) : static_cast<NodeLane &>(cc);

    if (adapterKind == kTempo) {
        QCOMPARE(lane.title(), QCoreApplication::translate("AutomationCanvas", "Tempo (BPM)"));
        QCOMPARE(lane.minimumValue(), CoreTimeDefaults::kMinTempoBpm);
        QCOMPARE(lane.maximumValue(), CoreTimeDefaults::kMaxTempoBpm);
        setTempo(doc, {tempoPoint(0, 150), {96, kFractionalTempoUs}});
        const int fractional = tempoBpm(kFractionalTempoUs);
        QCOMPARE(lane.valueText(150), QStringLiteral("150"));
        QCOMPARE(lane.valueText(fractional), QString::number(fractional));
        QVERIFY(samePoints(lane.points(), {{0, 150}, {96, fractional}}));
    } else {
        const M4aCcInfo info = m4aClassifyCc(kController);
        QCOMPARE(lane.title(), QStringLiteral("%1 (%2)").arg(QLatin1String(info.display),
                                                             QLatin1String(info.name)));
        QCOMPARE(lane.minimumValue(), CoreTimeDefaults::laneValueMinimum(kController));
        QCOMPARE(lane.maximumValue(), CoreTimeDefaults::laneValueMaximum(kController));
        QCOMPARE(lane.valueText(64), m4aFormatCcValue(kController, 64));
        QCOMPARE(lane.valueText(0), m4aFormatCcValue(kController, 0));
        CCLaneAdapter bend(doc, kTrack, DOC_CC_BEND);
        QCOMPARE(bend.minimumValue(), CoreTimeDefaults::kMinBendValue);
        QCOMPARE(bend.maximumValue(), CoreTimeDefaults::kMaxBendValue);
        QCOMPARE(bend.valueText(0), m4aFormatBend(0));
        QCOMPARE(bend.valueText(100), m4aFormatBend(100));
    }

    songview::EditorSelectionModel selection;
    const std::vector<AutomationRow> rows{{EditorAutomationRowId{
        EditorAutomationRowKind::ControlChange, uint8_t(kTrack), kController}}};
    LaneSelection laneSelection(selection, rows, 1u);
    const EditorAutomationRowId selectedId =
        adapterKind == kTempo ? EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0}
                              : rows.front().id;
    songview::EditorSelectionModel::TimeSelection timeSelection;
    timeSelection.startTick = 50;
    timeSelection.endTick = 150;
    timeSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    if (adapterKind == kTempo)
        timeSelection.tempo = true;
    else
        timeSelection.lanes.push_back({kTrack, kController});
    selection.setTimeSelection(std::move(timeSelection));
    QVERIFY(laneSelection.activeTickRange() ==
            (std::optional<std::pair<uint64_t, uint64_t>>{{50, 150}}));
    QVERIFY(laneSelection.coversLane(selectedId));

    auto unselected = selection.timeSelection();
    unselected.tempo = adapterKind != kTempo;
    unselected.lanes.clear();
    if (adapterKind == kTempo)
        unselected.lanes.push_back({kTrack, kController});
    selection.setTimeSelection(std::move(unselected));
    QVERIFY(!laneSelection.coversLane(selectedId));
    selection.clearTimeSelection();
    QVERIFY(!laneSelection.active());
    QVERIFY(!laneSelection.coversLane(selectedId));
}

void AutomationDomainTest::deletes_data()
{
    effectivePoints_data();
}

void AutomationDomainTest::deletes()
{
    QFETCH(int, adapterKind);
    SongDocument &doc = document();
    TempoLane tempo(doc);
    CCLaneAdapter cc(doc, kTrack, kController);
    NodeLane &lane =
        adapterKind == kTempo ? static_cast<NodeLane &>(tempo) : static_cast<NodeLane &>(cc);
    const std::vector<NodePoint> fixture{{0, 120}, {96, 100}, {288, 110}};
    setUniquePoints(doc, adapterKind, fixture);
    const Snapshot before = snapshot();
    QVERIFY(!applyDeletes(doc, adapterKind, {}));
    QVERIFY(snapshot() == before);
    QVERIFY(!applyDeletes(doc, adapterKind, {99999}));
    QVERIFY(snapshot() == before);
    QVERIFY(applyDeletes(doc, adapterKind, {96}));
    QVERIFY(isOneEdit(before, snapshot()));
    QVERIFY(samePoints(lane.points(), {{0, 120}, {288, 110}}));
    if (adapterKind == kCc)
        QVERIFY(rawValuesAt(doc, kTrack, kController, 96).empty());
    QVERIFY(undoRedoRestores(before, fixture, {{0, 120}, {288, 110}}, lane));

    if (adapterKind == kCc) {
        setLane(doc, kTrack, kController, {{0, 64}});
        insertCc(doc, kTrack, kController, 96, 10);
        insertCc(doc, kTrack, kController, 96, 20);
        const Snapshot groupedBefore = snapshot();
        const std::vector<NodePoint> groupedPoints = lane.points();
        QVERIFY(applyDeletes(doc, adapterKind, {96}));
        QVERIFY(isOneEdit(groupedBefore, snapshot()));
        QVERIFY(samePoints(lane.points(), {{0, 64}}));
        QVERIFY(rawValuesAt(doc, kTrack, kController, 96).empty());
        QVERIFY(undoRedoRestores(groupedBefore, groupedPoints, {{0, 64}}, lane));
    }
}

void AutomationDomainTest::moves_data()
{
    effectivePoints_data();
}

void AutomationDomainTest::moves()
{
    QFETCH(int, adapterKind);
    SongDocument &doc = document();
    TempoLane tempo(doc);
    CCLaneAdapter cc(doc, kTrack, kController);
    NodeLane &lane =
        adapterKind == kTempo ? static_cast<NodeLane &>(tempo) : static_cast<NodeLane &>(cc);

    if (adapterKind == kTempo) {
        setTempo(doc, {{96, kPreservedTempoUs}, tempoPoint(288, 110)});
        const Snapshot before = snapshot();
        const std::vector<NodePoint> beforePoints = lane.points();
        QVERIFY(!applyMoves(doc, adapterKind, {}));
        QVERIFY(snapshot() == before);
        QVERIFY(!applyMoves(doc, adapterKind, {{99999, {192, 120}}}));
        QVERIFY(snapshot() == before);
        const int preservedBpm = tempoBpm(kPreservedTempoUs);
        QVERIFY(applyMoves(doc, adapterKind, {{96, {192, preservedBpm}}}));
        QVERIFY(isOneEdit(before, snapshot()));
        QVERIFY(samePoints(lane.points(), {{192, preservedBpm}, {288, 110}}));
        QCOMPARE(doc.tempoPoints().front().microsecondsPerQuarterNote, kPreservedTempoUs);
        QVERIFY(undoRedoRestores(before, beforePoints, {{192, preservedBpm}, {288, 110}}, lane));

        const Snapshot rewriteBefore = snapshot();
        const std::vector<NodePoint> rewriteBeforePoints = lane.points();
        QVERIFY(applyMoves(doc, adapterKind, {{96, {192, 140}}}));
        QVERIFY(isOneEdit(rewriteBefore, snapshot()));
        QCOMPARE(doc.tempoPoints().front().microsecondsPerQuarterNote, tempoUsForBpm(140));
        QVERIFY(
            undoRedoRestores(rewriteBefore, rewriteBeforePoints, {{192, 140}, {288, 110}}, lane));
        return;
    }

    setLane(doc, kTrack, kController, {{288, 40}});
    insertCc(doc, kTrack, kController, 96, 10);
    insertCc(doc, kTrack, kController, 96, 20);
    const Snapshot before = snapshot();
    const std::vector<NodePoint> beforePoints = lane.points();
    QVERIFY(!applyMoves(doc, adapterKind, {}));
    QVERIFY(snapshot() == before);
    QVERIFY(!applyMoves(doc, adapterKind, {{99999, {192, 20}}}));
    QVERIFY(snapshot() == before);
    QVERIFY(applyMoves(doc, adapterKind, {{96, {192, 20}}}));
    QVERIFY(isOneEdit(before, snapshot()));
    QVERIFY(samePoints(lane.points(), {{192, 20}, {288, 40}}));
    QVERIFY(rawValuesAt(doc, kTrack, kController, 192) == (std::vector<int>{10, 20}));
    QVERIFY(undoRedoRestores(before, beforePoints, {{192, 20}, {288, 40}}, lane));
}

void AutomationDomainTest::moveCollisions_data()
{
    effectivePoints_data();
}

void AutomationDomainTest::moveCollisions()
{
    QFETCH(int, adapterKind);
    SongDocument &doc = document();
    TempoLane tempo(doc);
    CCLaneAdapter cc(doc, kTrack, kController);
    NodeLane &lane =
        adapterKind == kTempo ? static_cast<NodeLane &>(tempo) : static_cast<NodeLane &>(cc);
    const int preservedBpm = tempoBpm(kPreservedTempoUs);

    if (adapterKind == kTempo) {
        setTempo(doc, {{96, kPreservedTempoUs}, tempoPoint(288, 110)});
        const Snapshot before = snapshot();
        const std::vector<NodePoint> beforePoints = lane.points();
        QVERIFY(applyMoves(doc, adapterKind, {{96, {288, preservedBpm}}}));
        QVERIFY(isOneEdit(before, snapshot()));
        QVERIFY(samePoints(lane.points(), {{288, preservedBpm}}));
        QCOMPARE(doc.tempoPoints().front().microsecondsPerQuarterNote, kPreservedTempoUs);
        QVERIFY(undoRedoRestores(before, beforePoints, {{288, preservedBpm}}, lane));
        return;
    }

    setLane(doc, kTrack, kController, {{288, 40}});
    insertCc(doc, kTrack, kController, 96, 10);
    insertCc(doc, kTrack, kController, 96, 20);
    insertCc(doc, kTrack, kController, 192, 70);
    insertCc(doc, kTrack, kController, 192, 80);
    const Snapshot before = snapshot();
    const std::vector<NodePoint> beforePoints = lane.points();
    QVERIFY(applyMoves(doc, adapterKind, {{96, {192, 20}}}));
    QVERIFY(isOneEdit(before, snapshot()));
    QVERIFY(samePoints(lane.points(), {{192, 20}, {288, 40}}));
    QVERIFY(rawValuesAt(doc, kTrack, kController, 192) == (std::vector<int>{10, 20}));
    QVERIFY(undoRedoRestores(before, beforePoints, {{192, 20}, {288, 40}}, lane));
}

void AutomationDomainTest::replaceSpans_data()
{
    effectivePoints_data();
}

void AutomationDomainTest::replaceSpans()
{
    QFETCH(int, adapterKind);
    SongDocument &doc = document();
    TempoLane tempo(doc);
    CCLaneAdapter cc(doc, kTrack, kController);
    NodeLane &lane =
        adapterKind == kTempo ? static_cast<NodeLane &>(tempo) : static_cast<NodeLane &>(cc);

    const Snapshot emptyBefore = snapshot();
    lane.replaceSpan(0, 10000, {});
    QVERIFY(snapshot() == emptyBefore);
    lane.replaceSpan(0, 10000, {{96, 90}});
    QVERIFY(isOneEdit(emptyBefore, snapshot()));
    QVERIFY(samePoints(lane.points(), {{96, 90}}));
    QVERIFY(undoRedoRestores(emptyBefore, {}, {{96, 90}}, lane));

    const std::vector<NodePoint> fixture{{0, 120}, {96, 100}, {288, 110}};
    setUniquePoints(doc, adapterKind, fixture);
    const Snapshot before = snapshot();
    lane.replaceSpan(96, 96, {{96, 100}});
    QVERIFY(snapshot() == before);
    lane.replaceSpan(96, 200, {{96, 80}, {128, 70}});
    QVERIFY(isOneEdit(before, snapshot()));
    const std::vector<NodePoint> replacement{{0, 120}, {96, 80}, {128, 70}, {288, 110}};
    QVERIFY(samePoints(lane.points(), replacement));
    QVERIFY(undoRedoRestores(before, fixture, replacement, lane));

    const Snapshot clearBefore = snapshot();
    lane.replaceSpan(0, 10000, {});
    QVERIFY(isOneEdit(clearBefore, snapshot()));
    QVERIFY(lane.points().empty());
    QVERIFY(undoRedoRestores(clearBefore, fixture, {}, lane));

    if (adapterKind == kTempo) {
        setTempo(doc, {{96, kFractionalTempoUs}});
        const int displayed = tempoBpm(kFractionalTempoUs);
        const Snapshot fractionalBefore = snapshot();
        const std::vector<NodePoint> beforePoints = lane.points();
        lane.replaceSpan(96, 96, {{96, displayed}});
        QVERIFY(isOneEdit(fractionalBefore, snapshot()));
        QCOMPARE(doc.tempoPoints().front().microsecondsPerQuarterNote, tempoUsForBpm(displayed));
        QVERIFY(undoRedoRestores(fractionalBefore, beforePoints, {{96, displayed}}, lane));
    }
}

void AutomationDomainTest::defaultNodePromotion()
{
    SongDocument &doc = document();
    setLane(doc, kTrack, 7, {});
    setLane(doc, kTrack, 10, {});
    setLane(doc, kTrack, 1, {});
    setLane(doc, kTrack, DOC_CC_BEND, {});
    CCLaneAdapter volume(doc, kTrack, 7);
    CCLaneAdapter pan(doc, kTrack, 10);
    CCLaneAdapter modulation(doc, kTrack, 1);
    CCLaneAdapter bend(doc, kTrack, DOC_CC_BEND);
    QVERIFY(samePoints(volume.points(), {{0, 127}}));
    QVERIFY(samePoints(pan.points(), {{0, 64}}));
    QVERIFY(modulation.points().empty());
    const std::optional<NodePoint> modulationLeadIn = modulation.leadIn();
    QVERIFY(modulationLeadIn && modulationLeadIn->tick == 0 && modulationLeadIn->value == 0);
    QVERIFY(bend.points().empty());
    const std::optional<NodePoint> bendLeadIn = bend.leadIn();
    QVERIFY(bendLeadIn && bendLeadIn->tick == 0 && bendLeadIn->value == 0);

    const Snapshot volumeBefore = snapshot();
    const auto volumeResolved = nodelane::resolveCcMoves(doc, kTrack, 7, {{0, {96, 100}}});
    QVERIFY(volumeResolved.has_value());
    SongDocument::RangeEdit volumeEdit;
    nodelane::appendResolvedCcMoves(volumeEdit, *volumeResolved);
    QVERIFY(!volumeEdit.empty());
    doc.applyRangeEdit(QStringLiteral("automation volume default promotion"), volumeEdit);
    QVERIFY(isOneEdit(volumeBefore, snapshot()));
    QVERIFY(rawValuesAt(doc, kTrack, 7, 96) == (std::vector<int>{100}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), volumeBefore.smf);
    QVERIFY(samePoints(volume.points(), {{0, 127}}));

    const Snapshot panBefore = snapshot();
    const auto panResolved = nodelane::resolveCcMoves(doc, kTrack, 10, {{0, {96, 32}}});
    QVERIFY(panResolved.has_value());
    SongDocument::RangeEdit panEdit;
    nodelane::appendResolvedCcMoves(panEdit, *panResolved);
    QVERIFY(!panEdit.empty());
    doc.applyRangeEdit(QStringLiteral("automation pan default promotion"), panEdit);
    QVERIFY(isOneEdit(panBefore, snapshot()));
    QVERIFY(rawValuesAt(doc, kTrack, 10, 96) == (std::vector<int>{32}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), panBefore.smf);
    QVERIFY(samePoints(pan.points(), {{0, 64}}));
}

int runAutomationDomainCheck(const QStringList &qtArguments)
{
    AutomationDomainTest test;
    QStringList arguments{QStringLiteral("automation-domain")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
