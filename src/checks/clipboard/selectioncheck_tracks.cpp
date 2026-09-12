#include "checks/clipboard/selectioncheck_test.h"

#include <QtTest>

#include <vector>

#include "core/songdocument.h"

namespace checks::clipboard {

namespace {

using EditorSelectionModel = songview::EditorSelectionModel;
using SelectionChange = EditorSelectionModel::SelectionChange;

constexpr uint32_t kPrimaryTrack = static_cast<uint32_t>(SelectionChange::PrimaryTrack);
constexpr uint32_t kTrackScope = static_cast<uint32_t>(SelectionChange::TrackScope);
constexpr uint32_t kNoteSelection = static_cast<uint32_t>(SelectionChange::NoteSelection);
constexpr uint32_t kTimeSelection = static_cast<uint32_t>(SelectionChange::TimeSelection);

EditorSelectionModel::TimeSelection trackRange(Tick start, Tick end)
{
    EditorSelectionModel::TimeSelection selection;
    selection.startTick = start;
    selection.endTick = end;
    return selection;
}

} // namespace

void SelectionCheckTest::trackScopeGesturesPreserveOrClearAtTheRightBoundary()
{
    EditorSelectionModel model;
    NotificationLog notifications;
    notifications.attach(model);
    const uint32_t usedTracks =
        trackBit(0) | trackBit(1) | trackBit(2) | trackBit(3) | trackBit(4) | trackBit(5);

    model.applyPrimaryTrackTransition(1);
    QCOMPARE(model.primaryTrack(), 1);
    QCOMPARE(model.storedTrackScope(), trackBit(1));
    QVERIFY(hasTransition(notifications, 0, kPrimaryTrack | kTrackScope));
    notifications.clear();

    model.applyTrackScopeAdjustment(3, usedTracks, EditorSelectionModel::TrackScopeAction::Toggle);
    QCOMPARE(model.storedTrackScope(), trackBit(1) | trackBit(3));
    QVERIFY(hasTransition(notifications, 0, kTrackScope));
    notifications.clear();

    model.setTimeSelection(trackRange(30, 60));
    notifications.clear();
    model.applyTrackScopeAdjustment(1, usedTracks, EditorSelectionModel::TrackScopeAction::Toggle);
    QCOMPARE(model.primaryTrack(), 3);
    QCOMPARE(model.storedTrackScope(), trackBit(3));
    QVERIFY(model.timeSelection().active());
    QVERIFY(hasTransition(notifications, 0, kPrimaryTrack | kTrackScope));
    const auto &handoff = notifications.transitions.back();
    QCOMPARE(handoff.previousTrackTime.startTick, uint64_t{30});
    QCOMPARE(handoff.previousTrackTime.endTick, uint64_t{60});
    QCOMPARE(handoff.previousTrackTime.trackScope, trackBit(1) | trackBit(3));
    QCOMPARE(handoff.trackTime.startTick, uint64_t{30});
    QCOMPARE(handoff.trackTime.endTick, uint64_t{60});
    QCOMPARE(handoff.trackTime.trackScope, trackBit(3));

    model.applyTrackScopeAdjustment(4, usedTracks, EditorSelectionModel::TrackScopeAction::Toggle);
    notifications.clear();
    model.applyTrackScopeAdjustment(3, usedTracks, EditorSelectionModel::TrackScopeAction::Plain);
    QCOMPARE(model.primaryTrack(), 3);
    QCOMPARE(model.storedTrackScope(), trackBit(3));
    QVERIFY(model.timeSelection().active());
    QVERIFY(hasTransition(notifications, 0, kTrackScope));
    const auto &collapsed = notifications.transitions.back();
    QCOMPARE(collapsed.previousTrackTime.trackScope, trackBit(3) | trackBit(4));
    QCOMPARE(collapsed.trackTime.trackScope, trackBit(3));

    notifications.clear();
    model.applyTrackScopeAdjustment(5, usedTracks, EditorSelectionModel::TrackScopeAction::Range);
    QCOMPARE(model.storedTrackScope(), trackBit(3) | trackBit(4) | trackBit(5));
    QVERIFY(hasTransition(notifications, 0, kTrackScope));
    const auto &ranged = notifications.transitions.back();
    QCOMPARE(ranged.previousTrackTime.trackScope, trackBit(3));
    QCOMPARE(ranged.trackTime.trackScope, trackBit(3) | trackBit(4) | trackBit(5));

    EditorSelectionModel noteHandoff;
    NotificationLog noteNotifications;
    noteNotifications.attach(noteHandoff);
    noteHandoff.applyPrimaryTrackTransition(1);
    noteHandoff.applyTrackScopeAdjustment(3, usedTracks,
                                          EditorSelectionModel::TrackScopeAction::Toggle);
    noteHandoff.setNoteSelection({NoteId{55}});
    noteNotifications.clear();
    noteHandoff.applyTrackScopeAdjustment(1, usedTracks,
                                          EditorSelectionModel::TrackScopeAction::Toggle);
    QCOMPARE(noteHandoff.primaryTrack(), 3);
    QCOMPARE(noteHandoff.storedTrackScope(), trackBit(3));
    QVERIFY(noteHandoff.noteSelection().empty());
    QVERIFY(hasTransition(noteNotifications, 0, kPrimaryTrack | kTrackScope | kNoteSelection));

    EditorSelectionModel plainTransition;
    NotificationLog plainNotifications;
    plainNotifications.attach(plainTransition);
    plainTransition.applyPrimaryTrackTransition(1);
    plainTransition.setTimeSelection(trackRange(30, 60));
    plainNotifications.clear();
    plainTransition.applyTrackScopeAdjustment(3, usedTracks,
                                              EditorSelectionModel::TrackScopeAction::Plain);
    QCOMPARE(plainTransition.primaryTrack(), 3);
    QCOMPARE(plainTransition.storedTrackScope(), trackBit(3));
    QVERIFY(!plainTransition.timeSelection().active());
    QVERIFY(hasTransition(plainNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection));
    const auto &plain = plainNotifications.transitions.back();
    QCOMPARE(plain.previousTrackTime.startTick, uint64_t{30});
    QCOMPARE(plain.previousTrackTime.endTick, uint64_t{60});
    QCOMPARE(plain.previousTrackTime.trackScope, trackBit(1));
    QCOMPARE(plain.trackTime.trackScope, uint32_t{0});
}

void SelectionCheckTest::coverageQueriesAndLaneScopeSanitization()
{
    EditorSelectionModel model;
    const uint32_t usedTracks = trackBit(0) | trackBit(2);
    model.applyTrackScopeAdjustment(2, usedTracks, EditorSelectionModel::TrackScopeAction::Toggle);
    model.setTimeSelection(trackRange(100, 200));

    QVERIFY(model.timeSelectionCoversTrack(0, usedTracks));
    QVERIFY(model.timeSelectionCoversTrack(2, usedTracks));
    QVERIFY(!model.timeSelectionCoversTrack(1, usedTracks));
    QCOMPARE(model.resolvedTrackScope(usedTracks), usedTracks);
    QVERIFY(model.timeSelectionCoversLane(0, 7, usedTracks));
    QVERIFY(model.timeSelectionCoversLane(2, DOC_CC_BEND, usedTracks));
    QVERIFY(!model.timeSelectionCoversLane(1, 7, usedTracks));
    QVERIFY(model.timeSelectionCoversTempo(usedTracks));
    QVERIFY(!model.timeSelectionCoversTempo(usedTracks | trackBit(1)));
    QVERIFY(!model.timeSelectionCoversTempo(0));

    EditorSelectionModel::TimeSelection lanes;
    lanes.startTick = 300;
    lanes.endTick = 400;
    lanes.scope = EditorSelectionModel::TimeSelection::Lanes;
    lanes.lanes = {{2, 7}, {2, 7}, {-2, 8}, {16, 9}};
    lanes.tempo = true;
    model.setTimeSelection(lanes);
    QVERIFY(model.timeSelection().active());
    QVERIFY((model.timeSelection().lanes == std::vector<std::pair<int, uint8_t>>{{2, 7}}));
    QVERIFY(model.timeSelection().tempo);
    QVERIFY(!model.timeSelectionCoversTrack(2, usedTracks));
    QVERIFY(model.timeSelectionCoversLane(2, 7, usedTracks));
    QVERIFY(model.timeSelectionCoversTempo(usedTracks));
    QVERIFY(!model.timeSelectionCoversLane(2, 8, usedTracks));

    lanes.lanes.clear();
    lanes.tempo = false;
    model.setTimeSelection(lanes);
    QVERIFY(!model.timeSelection().active());
    QVERIFY(model.timeSelection().lanes.empty());
    QVERIFY(!model.timeSelection().tempo);
}

void SelectionCheckTest::outOfRangeTrackMasksAreIgnored()
{
    EditorSelectionModel model;
    NotificationLog notifications;
    notifications.attach(model);
    model.applyPrimaryTrackTransition(15);
    notifications.clear();

    // The model owns a 16-bit track domain; this test helper never shifts by
    // an out-of-range width, and the API masks an otherwise representable bit 20.
    model.setTrackScope(trackBit(15) | (uint32_t{1} << 20));
    QCOMPARE(model.storedTrackScope(), trackBit(15));
    QVERIFY(notifications.transitions.empty());
    model.applyTrackScopeAdjustment(16, trackBit(15),
                                    EditorSelectionModel::TrackScopeAction::Toggle);
    QCOMPARE(model.storedTrackScope(), trackBit(15));
    QVERIFY(notifications.transitions.empty());
    QCOMPARE(trackBit(32), uint32_t{0});
    model.setTrackScope(trackBit(32));
    QCOMPARE(model.storedTrackScope(), trackBit(15));
    QVERIFY(notifications.transitions.empty());
}

void SelectionCheckTest::resetForSongSwapNotifiesExactState()
{
    EditorSelectionModel model;
    NotificationLog notifications;
    notifications.attach(model);
    model.applyPrimaryTrackTransition(5);
    model.setNoteSelection({NoteId{73}});
    notifications.clear();

    model.resetForSongSwap(14);
    QCOMPARE(model.primaryTrack(), 14);
    QCOMPARE(model.storedTrackScope(), trackBit(14));
    QVERIFY(model.noteSelection().empty());
    QVERIFY(!model.timeSelection().active());
    QVERIFY(hasTransition(notifications, 0, kPrimaryTrack | kTrackScope | kNoteSelection));
    QCOMPARE(notifications.transitions.back().previousTrackTime.trackScope, uint32_t{0});
    QCOMPARE(notifications.transitions.back().trackTime.trackScope, uint32_t{0});
    const size_t beforeEquivalent = notifications.transitions.size();
    model.resetForSongSwap(14);
    QCOMPARE(notifications.transitions.size(), beforeEquivalent);

    EditorSelectionModel timeModel;
    NotificationLog timeNotifications;
    timeNotifications.attach(timeModel);
    timeModel.setTimeSelection(trackRange(1, 2));
    timeNotifications.clear();
    timeModel.resetForSongSwap(6);
    QCOMPARE(timeModel.primaryTrack(), 6);
    QVERIFY(!timeModel.timeSelection().active());
    QVERIFY(hasTransition(timeNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection));
    const auto &transition = timeNotifications.transitions.back();
    QCOMPARE(transition.previousTrackTime.startTick, uint64_t{1});
    QCOMPARE(transition.previousTrackTime.endTick, uint64_t{2});
    QCOMPARE(transition.previousTrackTime.trackScope, trackBit(0));
    QCOMPARE(transition.trackTime.trackScope, uint32_t{0});
}

void SelectionCheckTest::remapPreservesMeaningfulSelection()
{
    const uint32_t usedTracks = trackBit(0) | trackBit(1) | trackBit(2);
    TrackRemap remap;
    remap.engineTrackMap = {2, 4, -1};
    remap.newEngineTrackCount = 5;

    EditorSelectionModel model;
    NotificationLog notifications;
    notifications.attach(model);
    model.applyPrimaryTrackTransition(1);
    model.applyTrackScopeAdjustment(0, usedTracks, EditorSelectionModel::TrackScopeAction::Toggle);
    model.setNoteSelection({NoteId{91}});
    notifications.clear();
    model.applyRemap(remap);
    QCOMPARE(model.primaryTrack(), 4);
    QCOMPARE(model.storedTrackScope(), trackBit(2) | trackBit(4));
    QVERIFY((model.noteSelection() == std::vector<NoteId>{NoteId{91}}));
    QVERIFY(hasTransition(notifications, 0, kPrimaryTrack | kTrackScope));
    QCOMPARE(notifications.transitions.back().previousTrackTime.trackScope, uint32_t{0});
    QCOMPARE(notifications.transitions.back().trackTime.trackScope, uint32_t{0});

    EditorSelectionModel laneModel;
    NotificationLog laneNotifications;
    laneNotifications.attach(laneModel);
    laneModel.applyPrimaryTrackTransition(1);
    laneModel.applyTrackScopeAdjustment(0, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Toggle);
    EditorSelectionModel::TimeSelection lanes;
    lanes.startTick = 8;
    lanes.endTick = 18;
    lanes.scope = EditorSelectionModel::TimeSelection::Lanes;
    lanes.lanes = {{0, 7}, {1, 8}, {1, 8}};
    lanes.tempo = true;
    laneModel.setTimeSelection(lanes);
    laneNotifications.clear();
    laneModel.applyRemap(remap);
    QCOMPARE(laneModel.primaryTrack(), 4);
    QCOMPARE(laneModel.storedTrackScope(), trackBit(2) | trackBit(4));
    QVERIFY(
        (laneModel.timeSelection().lanes == std::vector<std::pair<int, uint8_t>>{{2, 7}, {4, 8}}));
    QVERIFY(laneModel.timeSelection().tempo);
    QVERIFY(hasTransition(laneNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection));
    QCOMPARE(laneNotifications.transitions.back().previousTrackTime.trackScope, uint32_t{0});
    QCOMPARE(laneNotifications.transitions.back().trackTime.trackScope, uint32_t{0});

    TrackRemap deletedRemap;
    deletedRemap.engineTrackMap = {0, -1, -1};
    deletedRemap.newEngineTrackCount = 1;

    EditorSelectionModel deletedTrack;
    NotificationLog deletedNotifications;
    deletedNotifications.attach(deletedTrack);
    deletedTrack.applyPrimaryTrackTransition(2);
    deletedTrack.applyTrackScopeAdjustment(0, usedTracks,
                                           EditorSelectionModel::TrackScopeAction::Toggle);
    deletedTrack.setTimeSelection(trackRange(20, 30));
    deletedNotifications.clear();
    deletedTrack.applyRemap(deletedRemap);
    QCOMPARE(deletedTrack.primaryTrack(), 0);
    QCOMPARE(deletedTrack.storedTrackScope(), trackBit(0));
    QVERIFY(!deletedTrack.timeSelection().active());
    QVERIFY(hasTransition(deletedNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection));
    const auto &deletedTrackTransition = deletedNotifications.transitions.back();
    QCOMPARE(deletedTrackTransition.previousTrackTime.startTick, uint64_t{20});
    QCOMPARE(deletedTrackTransition.previousTrackTime.endTick, uint64_t{30});
    QCOMPARE(deletedTrackTransition.previousTrackTime.trackScope, trackBit(0) | trackBit(2));
    QCOMPARE(deletedTrackTransition.trackTime.trackScope, uint32_t{0});

    EditorSelectionModel deletedLane;
    NotificationLog deletedLaneNotifications;
    deletedLaneNotifications.attach(deletedLane);
    EditorSelectionModel::TimeSelection deletedLanes;
    deletedLanes.startTick = 40;
    deletedLanes.endTick = 50;
    deletedLanes.scope = EditorSelectionModel::TimeSelection::Lanes;
    deletedLanes.lanes = {{1, 7}};
    deletedLane.setTimeSelection(deletedLanes);
    deletedLaneNotifications.clear();
    deletedLane.applyRemap(deletedRemap);
    QVERIFY(!deletedLane.timeSelection().active());
    QVERIFY(deletedLane.timeSelection().lanes.empty());
    QVERIFY(hasTransition(deletedLaneNotifications, 0, kTimeSelection));
    QCOMPARE(deletedLaneNotifications.transitions.back().previousTrackTime.trackScope, uint32_t{0});
    QCOMPARE(deletedLaneNotifications.transitions.back().trackTime.trackScope, uint32_t{0});
}

} // namespace checks::clipboard
