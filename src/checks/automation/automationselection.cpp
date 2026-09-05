#include "checks/automation/tst_automationediting.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <utility>
#include <variant>
#include <vector>

#include <QByteArray>
#include <QSignalSpy>
#include <QtTest>

#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "core/songhistory.h"
#include "core/tempo.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kPanController = CoreTimeDefaults::kCcPan;
constexpr uint8_t kVolumeController = CoreTimeDefaults::kCcVolume;
constexpr uint8_t kLfoController = CoreTimeDefaults::kCcLfoSpeed;
constexpr uint64_t kSelectionTick = 96;
constexpr uint64_t kDestinationTick = 144;
constexpr uint64_t kLateTick = 384;
constexpr uint32_t kPreservedTempoUs = 499999;

SmfEvent programChange(uint64_t tick, uint8_t program)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xC0;
    event.data0 = program;
    return event;
}

SmfEvent controlChange(uint64_t tick, uint8_t controller, uint8_t value)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xB0;
    event.data0 = controller;
    event.data1 = value;
    return event;
}

SmfEvent tempo(uint64_t tick, uint32_t microsecondsPerQuarterNote)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xFF;
    event.metaType = 0x51;
    event.blob = QByteArray(3, Qt::Uninitialized);
    event.blob[0] = char(microsecondsPerQuarterNote >> 16);
    event.blob[1] = char(microsecondsPerQuarterNote >> 8);
    event.blob[2] = char(microsecondsPerQuarterNote);
    return event;
}

SmfFile mixedSelectionSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;

    SmfTrack track;
    track.events = {
        programChange(0, 0),
        tempo(0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(80)),
        controlChange(0, kPanController, 80),
        controlChange(0, kLfoController, 32),
        controlChange(24, kVolumeController, 32),
        tempo(kSelectionTick, kPreservedTempoUs),
        controlChange(kSelectionTick, kPanController, 10),
        controlChange(kSelectionTick, kPanController, 20),
        controlChange(kSelectionTick, kLfoController, 96),
        controlChange(kDestinationTick, kPanController, 70),
        controlChange(kDestinationTick, kPanController, 80),
        tempo(kLateTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(64)),
        controlChange(kLateTick, kPanController, 110),
        controlChange(kLateTick, kLfoController, 64),
    };
    track.endTick = kLateTick + 48;
    smf.tracks.push_back(std::move(track));
    return smf;
}

std::vector<int> valuesAt(const SongDocument &document, uint8_t controller, uint64_t tick)
{
    std::vector<int> values;
    for (const DocLanePoint &point : document.lanePoints(kTrack, controller)) {
        if (point.tick == tick)
            values.push_back(point.value);
    }
    return values;
}

std::vector<SongDocument::LanePointValue> laneValues(const SongDocument &document,
                                                     uint8_t controller)
{
    std::vector<SongDocument::LanePointValue> values;
    for (const DocLanePoint &point : document.lanePoints(kTrack, controller))
        values.push_back({point.tick, point.value});
    return values;
}

bool sameLaneValues(const std::vector<SongDocument::LanePointValue> &left,
                    const std::vector<SongDocument::LanePointValue> &right)
{
    if (left.size() != right.size())
        return false;
    for (std::size_t index = 0; index < left.size(); ++index) {
        if (left[index].tick != right[index].tick || left[index].value != right[index].value)
            return false;
    }
    return true;
}

uint32_t tempoAt(const SongDocument &document, uint64_t tick)
{
    for (const TempoPoint &point : document.tempoPoints()) {
        if (point.tick == tick)
            return point.microsecondsPerQuarterNote;
    }
    return 0;
}

std::vector<int> timelineValuesAt(const SongTab &tab, uint8_t controller, uint64_t tick)
{
    std::vector<int> values;
    const std::shared_ptr<const MidiTimeline> timeline = tab.timeline();
    if (!timeline)
        return values;
    for (const TimelineEvent &event : timeline->events) {
        if (event.type == 0xB && event.track == kTrack && event.tick == tick &&
            event.data0 == controller) {
            values.push_back(event.data1);
        }
    }
    return values;
}

bool timelineHasTempo(const SongTab &tab, uint64_t tick, double bpm)
{
    const std::shared_ptr<const MidiTimeline> timeline = tab.timeline();
    if (!timeline)
        return false;
    for (const TempoMapPoint &point : timeline->tempoMap) {
        if (point.tick == tick && std::abs(point.bpm - bpm) < 0.001)
            return true;
    }
    return false;
}

songview::EditorSelectionModel::TimeSelection mixedSelection(bool includeTempo)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kSelectionTick;
    selection.endTick = kDestinationTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.tempo = includeTempo;
    selection.lanes = {{kTrack, kPanController}, {kTrack, kLfoController}};
    return selection;
}

bool selectionMatches(const songview::EditorSelectionModel::TimeSelection &selection,
                      uint64_t first, uint64_t last, bool tempoSelected,
                      const std::vector<std::pair<int, uint8_t>> &lanes)
{
    return selection.active() &&
           selection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
           selection.startTick == first && selection.endTick == last &&
           selection.tempo == tempoSelected && selection.lanes == lanes;
}

} // namespace

void AutomationEditingTest::bandSelectionIsolatesTempoAndControlChangeRows()
{
    QVERIFY(stage(mixedSelectionSmf()));
    QVERIFY(expandTempo());

    const LaneHandle tempoLane = findRow({EditorAutomationRowKind::Tempo, 0, 0});
    const LaneHandle panLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    const LaneHandle volumeLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kVolumeController});
    QVERIFY(tempoLane.valid());
    QVERIFY(panLane.valid());
    QVERIFY(volumeLane.valid());
    setRowMaximumHeight({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    setRowMaximumHeight({EditorAutomationRowKind::ControlChange, kTrack, kVolumeController});
    QVERIFY(!laneBody(tempoLane).isEmpty());
    QVERIFY(!laneBody(panLane).isEmpty());
    QVERIFY(!laneBody(volumeLane).isEmpty());

    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState beforeBand =
        frozenDocumentState(documentChanged.count(), edited.count());
    const QPointF tempoBandStart = inputPoint(tempoLane, kSelectionTick - 24, 120);
    const QPointF panBandEnd = inputPoint(panLane, kDestinationTick, 64);
    mousePress(Qt::RightButton, automationWindowPoint(tempoBandStart));
    mouseMove(automationWindowPoint(panBandEnd));
    mouseRelease(Qt::RightButton, automationWindowPoint(panBandEnd));

    const auto &tempoSelection = tab().view().selectionModel().timeSelection();
    QVERIFY(selectionMatches(tempoSelection, kSelectionTick - 24, kDestinationTick, true, {}));
    QVERIFY(tab().view().selectionModel().timeSelectionCoversTempo(1u));
    QVERIFY(!tab().view().selectionModel().timeSelectionCoversLane(kTrack, kPanController, 1u));
    QVERIFY(!tab().view().selectionModel().timeSelectionCoversLane(kTrack, kLfoController, 1u));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == beforeBand);

    const std::vector<SongDocument::LanePointValue> panBefore =
        laneValues(tab().document(), kPanController);
    const std::vector<SongDocument::LanePointValue> lfoBefore =
        laneValues(tab().document(), kLfoController);
    const FrozenDocumentState beforeTempoDrag =
        frozenDocumentState(documentChanged.count(), edited.count());
    const QPointF tempoPoint =
        inputPoint(tempoLane, kSelectionTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs));
    const QPointF tempoTarget =
        inputPoint(tempoLane, kDestinationTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs));
    const QPointF activation =
        tempoPoint + QPointF(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0.0);
    const QPoint activationWindow = automationWindowPoint(activation);
    const QPoint dragEnd =
        activationWindow + (automationWindowPoint(tempoTarget) - automationWindowPoint(tempoPoint));
    mousePress(Qt::LeftButton, automationWindowPoint(tempoPoint), Qt::ShiftModifier);
    mouseMove(activationWindow, Qt::ShiftModifier);
    mouseMove(dragEnd, Qt::ShiftModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == beforeTempoDrag);
    mouseRelease(Qt::LeftButton, dragEnd, Qt::ShiftModifier);

    QCOMPARE(tab().document().revision(), beforeTempoDrag.revision + 1);
    QVERIFY(sameLaneValues(laneValues(tab().document(), kPanController), panBefore));
    QVERIFY(sameLaneValues(laneValues(tab().document(), kLfoController), lfoBefore));
    QCOMPARE(tempoAt(tab().document(), kDestinationTick), kPreservedTempoUs);
    QTRY_VERIFY(
        timelineHasTempo(tab(), kDestinationTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs)));

    QVERIFY(tab().history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), kPreservedTempoUs);

    tab().view().selectionModel().clearTimeSelection();
    const QPointF ccBandStart = inputPoint(volumeLane, kSelectionTick - 24, 64);
    const QPointF ccBandEnd = inputPoint(volumeLane, kDestinationTick, 64);
    mousePress(Qt::RightButton, automationWindowPoint(ccBandStart));
    mouseMove(automationWindowPoint(ccBandEnd));
    mouseRelease(Qt::RightButton, automationWindowPoint(ccBandEnd));

    const auto &ccSelection = tab().view().selectionModel().timeSelection();
    QVERIFY(selectionMatches(ccSelection, kSelectionTick - 24, kDestinationTick, false,
                             {{kTrack, kVolumeController}}));
    QVERIFY(!tab().view().selectionModel().timeSelectionCoversTempo(1u));
}

void AutomationEditingTest::multiLaneSelectionDragPreservesTempoAndCcOrder()
{
    QVERIFY(stage(mixedSelectionSmf()));
    QVERIFY(expandTempo());
    const LaneHandle tempoLane = findRow({EditorAutomationRowKind::Tempo, 0, 0});
    const LaneHandle panLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    const LaneHandle lfoLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kLfoController});
    QVERIFY(tempoLane.valid());
    QVERIFY(panLane.valid());
    QVERIFY(lfoLane.valid());
    setRowMaximumHeight({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    setRowMaximumHeight({EditorAutomationRowKind::ControlChange, kTrack, kLfoController});

    tab().view().selectionModel().setTimeSelection(mixedSelection(true));
    QVERIFY(selectionMatches(tab().view().selectionModel().timeSelection(), kSelectionTick,
                             kDestinationTick, true,
                             {{kTrack, kPanController}, {kTrack, kLfoController}}));
    const std::vector<SongDocument::LanePointValue> volumeBefore =
        laneValues(tab().document(), kVolumeController);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState preview =
        frozenDocumentState(documentChanged.count(), edited.count());

    const QPointF source =
        inputPoint(tempoLane, kSelectionTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs));
    const QPointF target =
        inputPoint(tempoLane, kDestinationTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs));
    const QPointF activation =
        source + QPointF(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0.0);
    const QPoint activationWindow = automationWindowPoint(activation);
    const QPoint end =
        activationWindow + (automationWindowPoint(target) - automationWindowPoint(source));
    mousePress(Qt::LeftButton, automationWindowPoint(source), Qt::ShiftModifier);
    mouseMove(activationWindow, Qt::ShiftModifier);
    mouseMove(end, Qt::ShiftModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == preview);
    mouseRelease(Qt::LeftButton, end, Qt::ShiftModifier);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(tab().document().revision(), preview.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), preview.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), preview.undoIndex + 1);
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), uint32_t{0});
    QCOMPARE(tempoAt(tab().document(), kDestinationTick), kPreservedTempoUs);
    QCOMPARE(valuesAt(tab().document(), kPanController, kSelectionTick), std::vector<int>{});
    QCOMPARE(valuesAt(tab().document(), kPanController, kDestinationTick),
             std::vector<int>({10, 20}));
    QCOMPARE(valuesAt(tab().document(), kLfoController, kSelectionTick), std::vector<int>{});
    QCOMPARE(valuesAt(tab().document(), kLfoController, kDestinationTick), std::vector<int>({96}));
    QVERIFY(sameLaneValues(laneValues(tab().document(), kVolumeController), volumeBefore));
    QVERIFY(selectionMatches(tab().view().selectionModel().timeSelection(), kDestinationTick,
                             kDestinationTick + (kDestinationTick - kSelectionTick), true,
                             {{kTrack, kPanController}, {kTrack, kLfoController}}));

    const std::vector<int> movedPan{10, 20};
    const std::vector<int> movedLfo{96};
    QTRY_VERIFY(timelineValuesAt(tab(), kPanController, kDestinationTick) == movedPan);
    QTRY_VERIFY(timelineValuesAt(tab(), kLfoController, kDestinationTick) == movedLfo);
    QTRY_VERIFY(
        timelineHasTempo(tab(), kDestinationTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs)));

    QVERIFY(tab().history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), kPreservedTempoUs);
    QCOMPARE(valuesAt(tab().document(), kPanController, kSelectionTick),
             std::vector<int>({10, 20}));
    QCOMPARE(valuesAt(tab().document(), kLfoController, kSelectionTick), std::vector<int>({96}));
    QTRY_VERIFY(timelineValuesAt(tab(), kPanController, kSelectionTick) == movedPan);

    QVERIFY(tab().history().canRedo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestRedo()));
    QCOMPARE(tempoAt(tab().document(), kDestinationTick), kPreservedTempoUs);
    QCOMPARE(valuesAt(tab().document(), kPanController, kDestinationTick), movedPan);
    QCOMPARE(valuesAt(tab().document(), kLfoController, kDestinationTick), movedLfo);
    QTRY_VERIFY(timelineValuesAt(tab(), kPanController, kDestinationTick) == movedPan);
}

void AutomationEditingTest::multiLaneSelectionDeleteAndEmptyDeleteNoop()
{
    QVERIFY(stage(mixedSelectionSmf()));
    QVERIFY(expandTempo());
    const LaneHandle tempoLane = findRow({EditorAutomationRowKind::Tempo, 0, 0});
    const LaneHandle panLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    const LaneHandle lfoLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kLfoController});
    QVERIFY(tempoLane.valid());
    QVERIFY(panLane.valid());
    QVERIFY(lfoLane.valid());

    tab().view().selectionModel().setTimeSelection(mixedSelection(true));
    const std::vector<SongDocument::LanePointValue> volumeBefore =
        laneValues(tab().document(), kVolumeController);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState beforeDelete =
        frozenDocumentState(documentChanged.count(), edited.count());
    keyClick(Qt::Key_Delete);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(tab().document().revision(), beforeDelete.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), beforeDelete.undoCount + 1);
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), uint32_t{0});
    QCOMPARE(valuesAt(tab().document(), kPanController, kSelectionTick), std::vector<int>{});
    QCOMPARE(valuesAt(tab().document(), kLfoController, kSelectionTick), std::vector<int>{});
    QVERIFY(sameLaneValues(laneValues(tab().document(), kVolumeController), volumeBefore));
    const std::vector<int> noValues;
    QTRY_VERIFY(timelineValuesAt(tab(), kPanController, kSelectionTick) == noValues);
    QTRY_VERIFY(timelineValuesAt(tab(), kLfoController, kSelectionTick) == noValues);

    QVERIFY(tab().history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), kPreservedTempoUs);
    QCOMPARE(valuesAt(tab().document(), kPanController, kSelectionTick),
             std::vector<int>({10, 20}));
    QCOMPARE(valuesAt(tab().document(), kLfoController, kSelectionTick), std::vector<int>({96}));
    QTRY_VERIFY(
        timelineHasTempo(tab(), kSelectionTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs)));

    QVERIFY(tab().history().canRedo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestRedo()));
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), uint32_t{0});
    const std::vector<int> noValuesAfterRedo;
    QTRY_VERIFY(timelineValuesAt(tab(), kPanController, kSelectionTick) == noValuesAfterRedo);

    // The shared fixture deliberately keeps pan occupants at kDestinationTick for
    // drag-collision coverage. Probe the following half-open cell for the no-op.
    constexpr uint64_t selectionSpan = kDestinationTick - kSelectionTick;
    songview::EditorSelectionModel::TimeSelection empty = mixedSelection(true);
    empty.startTick = kDestinationTick + selectionSpan;
    empty.endTick = empty.startTick + selectionSpan;
    tab().view().selectionModel().setTimeSelection(std::move(empty));
    const FrozenDocumentState beforeEmptyDelete =
        frozenDocumentState(documentChanged.count(), edited.count());
    keyClick(Qt::Key_Delete);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == beforeEmptyDelete);
    QVERIFY(sameLaneValues(laneValues(tab().document(), kVolumeController), volumeBefore));
}

void AutomationEditingTest::multiLaneSelectionDragAbortsOnDocumentRebuild()
{
    QVERIFY(stage(mixedSelectionSmf()));
    QVERIFY(expandTempo());
    const LaneHandle tempoLane = findRow({EditorAutomationRowKind::Tempo, 0, 0});
    const LaneHandle panLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    const LaneHandle lfoLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kLfoController});
    QVERIFY(tempoLane.valid());
    QVERIFY(panLane.valid());
    QVERIFY(lfoLane.valid());

    tab().view().selectionModel().setTimeSelection(mixedSelection(true));
    const QPointF source =
        inputPoint(tempoLane, kSelectionTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs));
    const QPointF target =
        inputPoint(tempoLane, kDestinationTick, CoreTimeDefaults::tempoBpm(kPreservedTempoUs));
    const QPointF activation =
        source + QPointF(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0.0);
    const QPoint activationWindow = automationWindowPoint(activation);
    const QPoint end =
        activationWindow + (automationWindowPoint(target) - automationWindowPoint(source));
    mousePress(Qt::LeftButton, automationWindowPoint(source), Qt::ShiftModifier);
    mouseMove(activationWindow, Qt::ShiftModifier);
    mouseMove(end, Qt::ShiftModifier);

    const std::vector<SongDocument::LanePointValue> panBefore =
        laneValues(tab().document(), kPanController);
    const std::vector<SongDocument::LanePointValue> lfoBefore =
        laneValues(tab().document(), kLfoController);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    // This is the production AutomationPage cancellation/rebuild entry point.
    // It must discard the stale preview without altering the document itself.
    const FrozenDocumentState beforeRebuild =
        frozenDocumentState(documentChanged.count(), edited.count());
    page().documentChanged();
    const FrozenDocumentState afterRebuild =
        frozenDocumentState(documentChanged.count(), edited.count());
    QVERIFY(afterRebuild == beforeRebuild);
    mouseRelease(Qt::LeftButton, end, Qt::ShiftModifier);

    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == afterRebuild);
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), kPreservedTempoUs);
    QCOMPARE(tempoAt(tab().document(), kDestinationTick), uint32_t{0});
    QVERIFY(sameLaneValues(laneValues(tab().document(), kPanController), panBefore));
    QVERIFY(sameLaneValues(laneValues(tab().document(), kLfoController), lfoBefore));
    QCOMPARE(valuesAt(tab().document(), kVolumeController, 24), std::vector<int>({32}));
    QVERIFY(selectionMatches(tab().view().selectionModel().timeSelection(), kSelectionTick,
                             kDestinationTick, true,
                             {{kTrack, kPanController}, {kTrack, kLfoController}}));
    const std::vector<int> originalPan{10, 20};
    QTRY_VERIFY(timelineValuesAt(tab(), kPanController, kSelectionTick) == originalPan);
}

void AutomationEditingTest::multiCcLaneSelectionDragExcludesTempoAndVolume()
{
    QVERIFY(stage(mixedSelectionSmf()));
    const LaneHandle panLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    const LaneHandle lfoLane =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kLfoController});
    QVERIFY(panLane.valid());
    QVERIFY(lfoLane.valid());
    setRowMaximumHeight({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    setRowMaximumHeight({EditorAutomationRowKind::ControlChange, kTrack, kLfoController});

    tab().view().selectionModel().setTimeSelection(mixedSelection(false));
    const std::vector<SongDocument::LanePointValue> volumeBefore =
        laneValues(tab().document(), kVolumeController);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState beforeDrag =
        frozenDocumentState(documentChanged.count(), edited.count());
    const QPointF source = inputPoint(panLane, kSelectionTick, 20);
    const QPointF target = inputPoint(panLane, kDestinationTick, 20);
    const QPointF activation =
        source + QPointF(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0.0);
    const QPoint activationWindow = automationWindowPoint(activation);
    const QPoint end =
        activationWindow + (automationWindowPoint(target) - automationWindowPoint(source));
    mousePress(Qt::LeftButton, automationWindowPoint(source), Qt::ShiftModifier);
    mouseMove(activationWindow, Qt::ShiftModifier);
    mouseMove(end, Qt::ShiftModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == beforeDrag);
    mouseRelease(Qt::LeftButton, end, Qt::ShiftModifier);

    QCOMPARE(tab().document().revision(), beforeDrag.revision + 1);
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), kPreservedTempoUs);
    QCOMPARE(tempoAt(tab().document(), kDestinationTick), uint32_t{0});
    QCOMPARE(valuesAt(tab().document(), kPanController, kDestinationTick),
             std::vector<int>({10, 20}));
    QCOMPARE(valuesAt(tab().document(), kLfoController, kDestinationTick), std::vector<int>({96}));
    QVERIFY(sameLaneValues(laneValues(tab().document(), kVolumeController), volumeBefore));
    QVERIFY(selectionMatches(tab().view().selectionModel().timeSelection(), kDestinationTick,
                             kDestinationTick + (kDestinationTick - kSelectionTick), false,
                             {{kTrack, kPanController}, {kTrack, kLfoController}}));

    const std::vector<int> movedPan{10, 20};
    const std::vector<int> movedLfo{96};
    QTRY_VERIFY(timelineValuesAt(tab(), kPanController, kDestinationTick) == movedPan);
    QTRY_VERIFY(timelineValuesAt(tab(), kLfoController, kDestinationTick) == movedLfo);

    QVERIFY(tab().history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tempoAt(tab().document(), kSelectionTick), kPreservedTempoUs);
    QCOMPARE(valuesAt(tab().document(), kPanController, kSelectionTick),
             std::vector<int>({10, 20}));
    QCOMPARE(valuesAt(tab().document(), kLfoController, kSelectionTick), std::vector<int>({96}));

    QVERIFY(tab().history().canRedo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestRedo()));
    QCOMPARE(tempoAt(tab().document(), kDestinationTick), uint32_t{0});
    QCOMPARE(valuesAt(tab().document(), kPanController, kDestinationTick), movedPan);
    QCOMPARE(valuesAt(tab().document(), kLfoController, kDestinationTick), movedLfo);
}
