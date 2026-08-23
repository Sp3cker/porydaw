#include <cstddef>
#include <cstdio>
#include <span>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

using EditorSelectionModel = songview::EditorSelectionModel;
using SelectionChange = EditorSelectionModel::SelectionChange;

constexpr auto kPrimaryTrack = static_cast<uint32_t>(SelectionChange::PrimaryTrack);
constexpr auto kTrackScope = static_cast<uint32_t>(SelectionChange::TrackScope);
constexpr auto kNoteSelection = static_cast<uint32_t>(SelectionChange::NoteSelection);
constexpr auto kTimeSelection = static_cast<uint32_t>(SelectionChange::TimeSelection);

struct NotificationLog {
    std::vector<uint32_t> changes;

    void attach(EditorSelectionModel &model)
    {
        model.setObserver(
            [this](SelectionChange change) { changes.push_back(static_cast<uint32_t>(change)); });
    }
};

uint32_t trackBit(int track)
{
    return uint32_t{1} << track;
}

} // namespace

int runSelectionCheck()
{
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        ++failures;
        std::fprintf(stderr, "selectioncheck: %s\n", what);
    };
    const auto expect = [&fail](bool condition, const char *what) {
        if (!condition)
            fail(what);
    };
    const auto expectEvent = [&fail](const NotificationLog &log, size_t before, uint32_t expected,
                                     const char *what) {
        if (log.changes.size() != before + 1 || log.changes.back() != expected)
            fail(what);
    };
    const auto expectNoEvent = [&fail](const NotificationLog &log, size_t before,
                                       const char *what) {
        if (log.changes.size() != before)
            fail(what);
    };

    {
        auto model = EditorSelectionModel{};
        auto notifications = NotificationLog{};
        notifications.attach(model);

        const auto ids = std::vector<NoteId>{NoteId{}, NoteId{7}, NoteId{7}, NoteId{8}};
        model.setNoteSelection(ids);
        expect(model.noteSelection() == std::vector<NoteId>{NoteId{7}, NoteId{8}},
               "note selection did not sanitize unassigned IDs and duplicates");
        expect(model.isNoteSelected(NoteId{7}) && model.isNoteSelected(NoteId{8}) &&
                   !model.isNoteSelected(NoteId{9}) && !model.isNoteSelected(NoteId{}),
               "note membership query is wrong");
        expectEvent(notifications, 0, kNoteSelection,
                    "sanitized note assignment notified incorrectly");

        const auto before = notifications.changes.size();
        model.setNoteSelection({NoteId{}, NoteId{7}, NoteId{8}, NoteId{8}});
        expectNoEvent(notifications, before, "equivalent sanitized note assignment notified");

        auto tracks = EditorSelectionModel::TimeSelection{};
        tracks.startTick = 10;
        tracks.endTick = 20;
        model.setTimeSelection(tracks);
        expect(model.noteSelection().empty() && model.timeSelection().active(),
               "active time selection did not clear note selection");
        expectEvent(notifications, before, kNoteSelection | kTimeSelection,
                    "mutual exclusion did not report both changed categories");

        const auto afterTime = notifications.changes.size();
        model.setNoteSelection({NoteId{}});
        expect(model.timeSelection().active() && model.noteSelection().empty(),
               "unassigned note selection disturbed active time selection");
        expectNoEvent(notifications, afterTime, "empty sanitized note selection notified");

        model.setNoteSelection({NoteId{19}});
        expect(model.noteSelection() == std::vector<NoteId>{NoteId{19}} &&
                   !model.timeSelection().active(),
               "non-empty note selection did not replace active time selection");
        expectEvent(notifications, afterTime, kNoteSelection | kTimeSelection,
                    "note assignment did not report mutual-exclusion clearing");

        auto inactive = EditorSelectionModel::TimeSelection{};
        const auto beforeInactive = notifications.changes.size();
        model.setTimeSelection(inactive);
        expect(model.noteSelection() == std::vector<NoteId>{NoteId{19}} &&
                   !model.timeSelection().active(),
               "inactive time selection cleared note selection");
        expectNoEvent(notifications, beforeInactive, "inactive time selection no-op notified");

        model.clearNoteSelection();
        expectEvent(notifications, beforeInactive, kNoteSelection,
                    "clearing note selection reported the wrong category");
        const auto beforeBoth = notifications.changes.size();
        model.clearTimeSelection();
        expectNoEvent(notifications, beforeBoth,
                      "clearing an already-empty time selection notified");

        model.setTimeSelection(tracks);
        const auto beforeClearTime = notifications.changes.size();
        model.clearTimeSelection();
        expect(!model.timeSelection().active() && model.noteSelection().empty(),
               "clearTimeSelection did not clear active time selection");
        expectEvent(notifications, beforeClearTime, kTimeSelection,
                    "clearTimeSelection reported the wrong category");
    }

    {
        auto model = EditorSelectionModel{};
        model.applyPrimaryTrackTransition(3);
        auto notifications = NotificationLog{};
        notifications.attach(model);

        auto selection = EditorSelectionModel::TimeSelection{};
        selection.startTick = 40;
        selection.endTick = 80;
        model.setTimeSelectionAndTrackScope(selection, trackBit(1) | trackBit(20));
        expect(model.timeSelection().startTick == 40 && model.timeSelection().endTick == 80 &&
                   model.storedTrackScope() == (trackBit(1) | trackBit(3)),
               "atomic time-and-track assignment did not sanitize or retain the primary track");
        expectEvent(notifications, 0, kTrackScope | kTimeSelection,
                    "atomic time-and-track assignment did not report one coherent transition");

        model.setNoteSelection({NoteId{23}});
        notifications.changes.clear();
        selection.startTick = 50;
        selection.endTick = 90;
        model.setTimeSelectionAndTrackScope(selection, trackBit(2));
        expect(model.noteSelection().empty() &&
                   model.storedTrackScope() == (trackBit(2) | trackBit(3)) &&
                   model.timeSelection().startTick == 50 && model.timeSelection().endTick == 90,
               "atomic time-and-track reassignment did not clear notes or preserve the range");
        expectEvent(notifications, 0, kTrackScope | kNoteSelection | kTimeSelection,
                    "atomic reassignment reported incomplete or intermediate categories");

        const auto beforeNoOp = notifications.changes.size();
        model.setTimeSelectionAndTrackScope(selection, trackBit(2) | trackBit(3));
        expectNoEvent(notifications, beforeNoOp, "equivalent atomic assignment notified");
    }

    {
        auto model = EditorSelectionModel{};
        auto notifications = NotificationLog{};
        notifications.attach(model);
        const auto usedTracks =
            trackBit(0) | trackBit(1) | trackBit(2) | trackBit(3) | trackBit(4) | trackBit(5);

        model.applyPrimaryTrackTransition(1);
        expect(model.primaryTrack() == 1 && model.storedTrackScope() == trackBit(1),
               "primary-track transition did not collapse scope");
        expectEvent(notifications, 0, kPrimaryTrack | kTrackScope,
                    "primary-track transition reported the wrong categories");
        notifications.changes.clear();

        model.applyTrackScopeAdjustment(3, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Toggle);
        expect(model.storedTrackScope() == (trackBit(1) | trackBit(3)),
               "Ctrl scope toggle did not add the clicked track");
        expectEvent(notifications, 0, kTrackScope, "scope toggle reported the wrong category");
        notifications.changes.clear();

        auto tracks = EditorSelectionModel::TimeSelection{};
        tracks.startTick = 30;
        tracks.endTick = 60;
        model.setTimeSelection(tracks);
        notifications.changes.clear();
        model.applyTrackScopeAdjustment(1, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Toggle);
        expect(model.primaryTrack() == 3 && model.storedTrackScope() == trackBit(3) &&
                   model.timeSelection().active(),
               "removing the primary track did not hand off atomically or preserve time selection");
        expectEvent(notifications, 0, kPrimaryTrack | kTrackScope,
                    "scope handoff with time selection reported an intermediate state");

        model.applyTrackScopeAdjustment(4, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Toggle);
        notifications.changes.clear();
        model.applyTrackScopeAdjustment(3, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Plain);
        expect(model.primaryTrack() == 3 && model.storedTrackScope() == trackBit(3) &&
                   model.timeSelection().active(),
               "plain click on primary track did not collapse scope while preserving time");
        expectEvent(notifications, 0, kTrackScope,
                    "plain scope collapse reported the wrong category");

        notifications.changes.clear();
        model.applyTrackScopeAdjustment(5, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Range);
        expect(model.storedTrackScope() == (trackBit(3) | trackBit(4) | trackBit(5)),
               "range scope adjustment did not select the inclusive used-track range");
        expectEvent(notifications, 0, kTrackScope,
                    "range scope adjustment reported the wrong category");

        auto noteHandoff = EditorSelectionModel{};
        auto handoffNotifications = NotificationLog{};
        handoffNotifications.attach(noteHandoff);
        noteHandoff.applyPrimaryTrackTransition(1);
        noteHandoff.applyTrackScopeAdjustment(3, usedTracks,
                                              EditorSelectionModel::TrackScopeAction::Toggle);
        noteHandoff.setNoteSelection({NoteId{55}});
        handoffNotifications.changes.clear();
        noteHandoff.applyTrackScopeAdjustment(1, usedTracks,
                                              EditorSelectionModel::TrackScopeAction::Toggle);
        expect(noteHandoff.primaryTrack() == 3 && noteHandoff.storedTrackScope() == trackBit(3) &&
                   noteHandoff.noteSelection().empty(),
               "primary handoff did not clear note selection");
        expectEvent(handoffNotifications, 0, kPrimaryTrack | kTrackScope | kNoteSelection,
                    "primary handoff did not report all changed categories");

        auto plainTransition = EditorSelectionModel{};
        auto plainNotifications = NotificationLog{};
        plainNotifications.attach(plainTransition);
        plainTransition.applyPrimaryTrackTransition(1);
        plainTransition.setTimeSelection(tracks);
        plainNotifications.changes.clear();
        plainTransition.applyTrackScopeAdjustment(3, usedTracks,
                                                  EditorSelectionModel::TrackScopeAction::Plain);
        expect(plainTransition.primaryTrack() == 3 &&
                   plainTransition.storedTrackScope() == trackBit(3) &&
                   !plainTransition.timeSelection().active(),
               "plain click on another track did not perform a real primary transition");
        expectEvent(plainNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection,
                    "real primary transition did not report time-selection clearing");
    }

    {
        auto model = EditorSelectionModel{};
        auto notifications = NotificationLog{};
        notifications.attach(model);
        const auto usedTracks = trackBit(0) | trackBit(2);
        model.applyTrackScopeAdjustment(2, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Toggle);

        auto tracks = EditorSelectionModel::TimeSelection{};
        tracks.startTick = 100;
        tracks.endTick = 200;
        model.setTimeSelection(tracks);
        notifications.changes.clear();
        expect(model.timeSelectionCoversTrack(0, usedTracks) &&
                   model.timeSelectionCoversTrack(2, usedTracks) &&
                   !model.timeSelectionCoversTrack(1, usedTracks),
               "track-scoped time coverage is wrong");
        expect(model.resolvedTrackScope(usedTracks) == usedTracks,
               "resolved Track Scope did not intersect the used-track mask");
        expect(model.timeSelectionCoversLane(0, 7, usedTracks) &&
                   model.timeSelectionCoversLane(2, DOC_CC_BEND, usedTracks) &&
                   !model.timeSelectionCoversLane(1, 7, usedTracks),
               "normal lane track coverage is wrong");
        expect(model.timeSelectionCoversTempo(usedTracks),
               "tempo was not covered when every used track was scoped");
        expect(!model.timeSelectionCoversTempo(usedTracks | trackBit(1)) &&
                   !model.timeSelectionCoversTempo(0),
               "tempo ignored the all-used-tracks rule");

        auto lanes = EditorSelectionModel::TimeSelection{};
        lanes.startTick = 300;
        lanes.endTick = 400;
        lanes.scope = EditorSelectionModel::TimeSelection::Lanes;
        lanes.lanes = {{2, 7}, {2, 7}, {-2, 8}, {16, 9}};
        lanes.tempo = true;
        model.setTimeSelection(lanes);
        expect(model.timeSelection().active() &&
                   model.timeSelection().lanes == std::vector<std::pair<int, uint8_t>>{{2, 7}} &&
                   model.timeSelection().tempo,
               "lane-scoped time selection did not deduplicate its identities");
        expect(!model.timeSelectionCoversTrack(2, usedTracks) &&
                   model.timeSelectionCoversLane(2, 7, usedTracks) &&
                   model.timeSelectionCoversTempo(usedTracks) &&
                   !model.timeSelectionCoversLane(2, 8, usedTracks),
               "lane-scoped coverage was not limited to explicit identities");

        lanes.lanes.clear();
        lanes.tempo = false;
        model.setTimeSelection(lanes);
        expect(!model.timeSelection().active() && model.timeSelection().lanes.empty() &&
                   !model.timeSelection().tempo,
               "active lane selection without contents was not canonicalized inactive");
    }

    {
        auto model = EditorSelectionModel{};
        auto notifications = NotificationLog{};
        notifications.attach(model);
        model.applyPrimaryTrackTransition(5);
        model.setNoteSelection({NoteId{73}});
        notifications.changes.clear();
        model.resetForSongSwap(14);
        expect(model.primaryTrack() == 14 && model.storedTrackScope() == trackBit(14) &&
                   model.noteSelection().empty() && !model.timeSelection().active(),
               "song reset did not establish the requested primary singleton state");
        expectEvent(notifications, 0, kPrimaryTrack | kTrackScope | kNoteSelection,
                    "song reset did not report all changed categories");
        const auto before = notifications.changes.size();
        model.resetForSongSwap(14);
        expectNoEvent(notifications, before, "equivalent song reset notified");

        auto timeModel = EditorSelectionModel{};
        auto timeNotifications = NotificationLog{};
        timeNotifications.attach(timeModel);
        auto selection = EditorSelectionModel::TimeSelection{};
        selection.startTick = 1;
        selection.endTick = 2;
        timeModel.setTimeSelection(selection);
        timeNotifications.changes.clear();
        timeModel.resetForSongSwap(6);
        expect(timeModel.primaryTrack() == 6 && !timeModel.timeSelection().active(),
               "song reset did not clear time selection");
        expectEvent(timeNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection,
                    "song reset did not report time-selection clearing");
    }

    {
        auto model = EditorSelectionModel{};
        auto notifications = NotificationLog{};
        notifications.attach(model);
        auto tracks = EditorSelectionModel::TimeSelection{};
        tracks.startTick = 5;
        tracks.endTick = 10;
        model.setTimeSelection(tracks);
        notifications.changes.clear();
        model.clearNoteSelection();
        expect(model.timeSelection().active(), "clearing note selection disturbed time selection");
        expect(notifications.changes.empty(), "clearing note selection notified without notes");

        model.clearTimeSelection();
        model.setNoteSelection({NoteId{81}});
        notifications.changes.clear();
        model.clearNoteSelection();
        expect(model.noteSelection().empty(), "clearNoteSelection did not clear note selection");
        expectEvent(notifications, 0, kNoteSelection,
                    "clearing note selection reported the wrong category");
        const auto before = notifications.changes.size();
        model.clearNoteSelection();
        expectNoEvent(notifications, before, "repeated note-selection clear notified");
    }

    {
        auto model = EditorSelectionModel{};
        auto notifications = NotificationLog{};
        notifications.attach(model);
        model.setNoteSelection({NoteId{1}, NoteId{2}, NoteId{3}});
        notifications.changes.clear();
        const auto valid = std::vector<NoteId>{NoteId{3}, NoteId{1}, NoteId{4}, NoteId{1}};
        model.reconcileNoteSelection(std::span<const NoteId>{valid});
        expect(model.noteSelection() == std::vector<NoteId>{NoteId{1}, NoteId{3}},
               "note reconciliation did not preserve surviving insertion order");
        expectEvent(notifications, 0, kNoteSelection,
                    "note reconciliation reported the wrong category");
        const auto before = notifications.changes.size();
        const auto sameValid = std::vector<NoteId>{NoteId{3}, NoteId{1}, NoteId{3}};
        model.reconcileNoteSelection(std::span<const NoteId>{sameValid});
        expectNoEvent(notifications, before, "equivalent note reconciliation notified");
        model.reconcileNoteSelection(std::span<const NoteId>{});
        expect(model.noteSelection().empty(), "empty reconciliation did not clear stale notes");
        expectEvent(notifications, before, kNoteSelection,
                    "empty note reconciliation reported incorrectly");
    }

    {
        auto model = EditorSelectionModel{};
        auto notifications = NotificationLog{};
        notifications.attach(model);
        const auto usedTracks = trackBit(0) | trackBit(1) | trackBit(2);
        model.applyPrimaryTrackTransition(1);
        model.applyTrackScopeAdjustment(0, usedTracks,
                                        EditorSelectionModel::TrackScopeAction::Toggle);
        model.setNoteSelection({NoteId{91}});
        notifications.changes.clear();
        auto remap = TrackRemap{};
        remap.engineTrackMap = {2, 4, -1};
        remap.newEngineTrackCount = 5;
        model.applyRemap(remap);
        expect(model.primaryTrack() == 4 &&
                   model.storedTrackScope() == (trackBit(2) | trackBit(4)) &&
                   model.noteSelection() == std::vector<NoteId>{NoteId{91}},
               "TrackRemap did not map primary, scope, and note identity correctly");
        expectEvent(notifications, 0, kPrimaryTrack | kTrackScope,
                    "TrackRemap reported an unchanged note category");

        auto laneModel = EditorSelectionModel{};
        auto laneNotifications = NotificationLog{};
        laneNotifications.attach(laneModel);
        laneModel.applyPrimaryTrackTransition(1);
        laneModel.applyTrackScopeAdjustment(0, usedTracks,
                                            EditorSelectionModel::TrackScopeAction::Toggle);
        auto lanes = EditorSelectionModel::TimeSelection{};
        lanes.startTick = 8;
        lanes.endTick = 18;
        lanes.scope = EditorSelectionModel::TimeSelection::Lanes;
        lanes.lanes = {{0, 7}, {1, 8}, {1, 8}};
        lanes.tempo = true;
        laneModel.setTimeSelection(lanes);
        laneNotifications.changes.clear();
        laneModel.applyRemap(remap);
        expect(laneModel.primaryTrack() == 4 &&
                   laneModel.storedTrackScope() == (trackBit(2) | trackBit(4)) &&
                   laneModel.timeSelection().lanes ==
                       std::vector<std::pair<int, uint8_t>>{{2, 7}, {4, 8}} &&
                   laneModel.timeSelection().tempo,
               "TrackRemap did not map lanes or preserve Tempo scope");
        expectEvent(laneNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection,
                    "lane TrackRemap reported the wrong categories");

        auto deletedTrack = EditorSelectionModel{};
        auto deletedNotifications = NotificationLog{};
        deletedNotifications.attach(deletedTrack);
        deletedTrack.applyPrimaryTrackTransition(2);
        deletedTrack.applyTrackScopeAdjustment(0, usedTracks,
                                               EditorSelectionModel::TrackScopeAction::Toggle);
        auto selectedTracks = EditorSelectionModel::TimeSelection{};
        selectedTracks.startTick = 20;
        selectedTracks.endTick = 30;
        deletedTrack.setTimeSelection(selectedTracks);
        deletedNotifications.changes.clear();
        auto deletedRemap = TrackRemap{};
        deletedRemap.engineTrackMap = {0, -1, -1};
        deletedRemap.newEngineTrackCount = 1;
        deletedTrack.applyRemap(deletedRemap);
        expect(deletedTrack.primaryTrack() == 0 && deletedTrack.storedTrackScope() == trackBit(0) &&
                   !deletedTrack.timeSelection().active(),
               "deleting primary track did not clamp fallback or clear track time selection");
        expectEvent(deletedNotifications, 0, kPrimaryTrack | kTrackScope | kTimeSelection,
                    "deleting primary track reported the wrong categories");

        auto deletedLane = EditorSelectionModel{};
        auto deletedLaneNotifications = NotificationLog{};
        deletedLaneNotifications.attach(deletedLane);
        auto deletedLanes = EditorSelectionModel::TimeSelection{};
        deletedLanes.startTick = 40;
        deletedLanes.endTick = 50;
        deletedLanes.scope = EditorSelectionModel::TimeSelection::Lanes;
        deletedLanes.lanes = {{1, 7}};
        deletedLane.setTimeSelection(deletedLanes);
        deletedLaneNotifications.changes.clear();
        deletedLane.applyRemap(deletedRemap);
        expect(!deletedLane.timeSelection().active() && deletedLane.timeSelection().lanes.empty(),
               "TrackRemap did not clear a lane selection whose only lane was deleted");
        expectEvent(deletedLaneNotifications, 0, kTimeSelection,
                    "deleted lane TrackRemap reported the wrong category");
    }

    return failures == 0 ? 0 : 1;
}
