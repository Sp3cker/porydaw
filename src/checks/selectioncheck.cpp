#include <cstdint>
#include <cstdio>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "ui/songview/editorselectionmodel.hpp"

namespace {

using Change = songview::EditorSelectionModel::Change;
using TimeSelection = songview::TimeSelection;

TimeSelection trackTime(uint64_t startTick, uint64_t endTick)
{
    TimeSelection selection;
    selection.startTick = startTick;
    selection.endTick = endTick;
    selection.scope = TimeSelection::Tracks;
    return selection;
}

TimeSelection laneTime(uint64_t startTick, uint64_t endTick,
                       std::vector<std::pair<int, uint8_t>> lanes)
{
    TimeSelection selection;
    selection.startTick = startTick;
    selection.endTick = endTick;
    selection.scope = TimeSelection::Lanes;
    selection.lanes = std::move(lanes);
    return selection;
}

bool sameTime(const TimeSelection &actual, const TimeSelection &expected)
{
    return actual.startTick == expected.startTick && actual.endTick == expected.endTick &&
           actual.scope == expected.scope && actual.lanes == expected.lanes;
}

TrackRemap engineRemap(std::vector<int> map, int newTrackCount)
{
    TrackRemap remap;
    remap.engineTrackMap = std::move(map);
    remap.newEngineTrackCount = newTrackCount;
    return remap;
}

} // namespace

int runSelectionCheck()
{
    auto failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "selectioncheck: FAIL: %s\n", message);
            ++failures;
        }
    };
    {
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        check(model.primaryTrack() == 0 && model.storedTrackScope() == 1u,
              "new model must start on track 0 with a single-track scope");
        check(model.resolvedTrackScope(1u << 20) == 0,
              "resolved scope must ignore tracks outside the model mask");
        model.resetForSong((1u << 4) | (1u << 7));
        check(model.primaryTrack() == 4 && model.storedTrackScope() == (1u << 4),
              "song reset must choose the first used track");
        check(model.resolvedTrackScope((1u << 4) | (1u << 7)) == (1u << 4),
              "song reset must resolve its single-track scope");
        model.resetForSong(0);
        check(model.primaryTrack() == 0 && model.storedTrackScope() == 1u,
              "song reset must fall back to track 0 when no track is used");
        check(notifications.size() == 2 &&
                  notifications[0] == (Change::PrimaryTrack | Change::TrackScope) &&
                  notifications[1] == (Change::PrimaryTrack | Change::TrackScope),
              "song reset must report each changed primary and scope atomically");
        model.setNoteSelection({NoteId(71)});
        notifications.clear();
        model.resetForSong(1u);
        check(model.noteSelection().empty(), "song reset must clear note selection");
        model.setTimeSelection(trackTime(1, 2));
        notifications.clear();
        model.resetForSong(1u);
        check(!model.timeSelection().active(), "song reset must clear time selection");
    }
    {
        songview::EditorSelectionModel model;
        model.resetForSong(1u << 2);
        model.adjustTrackScope(5, (1u << 2) | (1u << 5), songview::TrackScopeAction::Toggle);
        check(model.storedTrackScope() == ((1u << 2) | (1u << 5)),
              "stored scope must retain every selected track");
        check(model.resolvedTrackScope(1u << 2) == (1u << 2),
              "resolved scope must filter tracks that are not used");
        check(model.resolvedTrackScope((1u << 5) | (1u << 7)) == (1u << 5),
              "resolved scope must follow a changed used-track mask");
        check(model.resolvedTrackScope(1u << 20) == 0,
              "resolved scope must ignore high used-track bits");
    }
    {
        const NoteId first(7);
        const NoteId second(3);
        songview::EditorSelectionModel model;
        model.setNoteSelection({NoteId(), first, first, second, first, second});
        check(model.noteSelection() == std::vector<NoteId>{first, second},
              "note assignment must remove unassigned IDs and stable-deduplicate");
        check(model.isNoteSelected(first) && model.isNoteSelected(second) &&
                  !model.isNoteSelected(NoteId()),
              "note membership must use assigned note IDs");
    }
    {
        const NoteId first(11);
        const NoteId second(12);
        const auto time = trackTime(10, 20);
        std::vector<Change> notifications;
        std::vector<NoteId> expectedNotes{first, second};
        bool callbackSawCompleteState = false;
        songview::EditorSelectionModel model;
        model.setChangeCallback([&](Change changes) {
            notifications.push_back(changes);
            callbackSawCompleteState =
                model.noteSelection() == expectedNotes && !model.timeSelection().active();
        });
        model.setTimeSelection(time);
        notifications.clear();
        model.setNoteSelection({first, second});
        check(notifications.size() == 1 &&
                  notifications.front() == (Change::NoteSelection | Change::TimeSelection),
              "note assignment and time clearing must notify once with both categories");
        check(callbackSawCompleteState && model.noteSelection() == expectedNotes &&
                  !model.timeSelection().active(),
              "mutual-exclusion notification must observe the completed note transition");
        model.clearSelections();
        model.setNoteSelection({first});
        notifications.clear();
        bool timeCallbackSawCompleteState = false;
        model.setChangeCallback([&](Change changes) {
            notifications.push_back(changes);
            timeCallbackSawCompleteState =
                model.noteSelection().empty() && sameTime(model.timeSelection(), time);
        });
        model.setTimeSelection(time);
        check(notifications.size() == 1 &&
                  notifications.front() == (Change::NoteSelection | Change::TimeSelection),
              "time assignment and note clearing must notify once with both categories");
        check(timeCallbackSawCompleteState,
              "mutual-exclusion notification must observe the completed time transition");
    }
    {
        const auto used = (1u << 1) | (1u << 4);
        std::vector<Change> notifications;
        bool callbackSawCompleteState = false;
        int expectedPrimary = 4;
        songview::EditorSelectionModel model;
        model.resetForSong(used);
        model.setTimeSelection(trackTime(20, 30));
        model.setChangeCallback([&](Change changes) {
            notifications.push_back(changes);
            if (songview::hasChange(changes, Change::PrimaryTrack))
                callbackSawCompleteState = model.primaryTrack() == expectedPrimary &&
                                           model.storedTrackScope() == (1u << expectedPrimary) &&
                                           model.noteSelection().empty() &&
                                           !model.timeSelection().active();
        });
        model.transitionPrimaryTrack(4);
        check(callbackSawCompleteState && notifications.size() == 1 &&
                  notifications.front() ==
                      (Change::PrimaryTrack | Change::TrackScope | Change::TimeSelection),
              "primary transition must clear time and expose one completed notification");

        model.setNoteSelection({NoteId(19)});
        notifications.clear();
        callbackSawCompleteState = false;
        expectedPrimary = 1;
        model.transitionPrimaryTrack(1);
        check(model.noteSelection().empty() && callbackSawCompleteState &&
                  notifications.size() == 1 &&
                  notifications.front() ==
                      (Change::PrimaryTrack | Change::TrackScope | Change::NoteSelection),
              "primary transition must clear notes and expose one completed notification");
    }
    {
        const auto time = trackTime(30, 40);
        songview::EditorSelectionModel model;
        model.setTimeSelection(time);
        std::vector<Change> notifications;
        model.setChangeCallback(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.setNoteSelection({NoteId(), NoteId()});
        check(model.noteSelection().empty() && sameTime(model.timeSelection(), time),
              "an empty sanitized note assignment must preserve active time selection");
        check(notifications.empty(), "an invalid note assignment must be a no-op");
    }
    {
        const std::vector<std::pair<int, uint8_t>> expectedLanes{{1, 7}, {-1, DOC_CC_TEMPO}};
        songview::EditorSelectionModel model;
        model.setTimeSelection(laneTime(
            2, 8, {{1, 7}, {-1, DOC_CC_TEMPO}, {1, 7}, {16, 9}, {-2, 4}, {-1, DOC_CC_TEMPO}}));
        check(model.timeSelection().scope == TimeSelection::Lanes &&
                  model.timeSelection().lanes == expectedLanes,
              "lane assignment must stable-deduplicate and remove invalid identities");
        model.setTimeSelection(laneTime(4, 9, {}));
        check(sameTime(model.timeSelection(), TimeSelection()),
              "an active empty lane selection must canonicalize to the empty selection");
    }
    {
        const auto used = (1u << 1) | (1u << 2) | (1u << 3) | (1u << 5);
        const auto activeTime = trackTime(10, 20);
        const NoteId note(21);
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.resetForSong(used);
        model.adjustTrackScope(3, used, songview::TrackScopeAction::Toggle);
        model.setTimeSelection(activeTime);
        notifications.clear();
        model.adjustTrackScope(1, used, songview::TrackScopeAction::Plain);
        check(model.primaryTrack() == 1 && model.storedTrackScope() == (1u << 1) &&
                  sameTime(model.timeSelection(), activeTime),
              "plain click on the primary track must collapse scope and preserve time");
        check(notifications.size() == 1 && notifications.front() == Change::TrackScope,
              "plain scope collapse must report only its scope change");
        model.clearTimeSelection();
        model.setNoteSelection({note});
        notifications.clear();
        model.adjustTrackScope(1, used, songview::TrackScopeAction::Plain);
        check(model.noteSelection().empty() && notifications.size() == 1 &&
                  notifications.front() == Change::NoteSelection,
              "plain click on the primary track must clear notes atomically");
        model.setTimeSelection(activeTime);
        notifications.clear();
        model.adjustTrackScope(5, used, songview::TrackScopeAction::Plain);
        check(model.primaryTrack() == 5 && model.storedTrackScope() == (1u << 5) &&
                  !model.timeSelection().active(),
              "plain click on another track must perform a real primary transition");
        check(notifications.size() == 1 &&
                  notifications.front() ==
                      (Change::PrimaryTrack | Change::TrackScope | Change::TimeSelection),
              "plain primary transition must notify all changed categories once");
    }
    {
        const auto used = (1u << 1) | (1u << 3);
        const auto activeTime = trackTime(50, 60);
        const NoteId note(31);
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.resetForSong(used);
        model.setTimeSelection(activeTime);
        notifications.clear();
        model.adjustTrackScope(3, used, songview::TrackScopeAction::Toggle);
        check(model.storedTrackScope() == ((1u << 1) | (1u << 3)) &&
                  sameTime(model.timeSelection(), activeTime),
              "toggle must add the clicked track without clearing time");
        check(notifications.size() == 1 && notifications.front() == Change::TrackScope,
              "toggle add must report only its scope change");
        notifications.clear();
        model.adjustTrackScope(1, used, songview::TrackScopeAction::Toggle);
        check(model.primaryTrack() == 3 && model.storedTrackScope() == (1u << 3) &&
                  sameTime(model.timeSelection(), activeTime),
              "removing primary by toggle must hand off atomically and preserve time");
        check(notifications.size() == 1 &&
                  notifications.front() == (Change::PrimaryTrack | Change::TrackScope),
              "primary handoff must not expose an intermediate time clear");
        model.clearTimeSelection();
        model.setNoteSelection({note});
        model.adjustTrackScope(1, used, songview::TrackScopeAction::Toggle);
        notifications.clear();
        model.adjustTrackScope(3, used, songview::TrackScopeAction::Toggle);
        check(model.primaryTrack() == 1 && model.storedTrackScope() == (1u << 1) &&
                  model.noteSelection().empty(),
              "toggle primary handoff must clear note selection");
        check(notifications.size() == 1 &&
                  notifications.front() ==
                      (Change::PrimaryTrack | Change::TrackScope | Change::NoteSelection),
              "toggle primary handoff must notify its complete state once");
        notifications.clear();
        model.adjustTrackScope(1, used, songview::TrackScopeAction::Toggle);
        check(notifications.empty() && model.storedTrackScope() == (1u << 1),
              "toggle must never allow an empty scope");
    }
    {
        const auto used = (1u << 1) | (1u << 2) | (1u << 3) | (1u << 5);
        const auto activeTime = trackTime(70, 80);
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.resetForSong(used);
        model.setTimeSelection(activeTime);
        notifications.clear();
        model.adjustTrackScope(5, used, songview::TrackScopeAction::Range);
        check(model.primaryTrack() == 1 &&
                  model.storedTrackScope() == ((1u << 1) | (1u << 2) | (1u << 3) | (1u << 5)) &&
                  sameTime(model.timeSelection(), activeTime),
              "range must select used tracks in the inclusive primary-to-clicked span");
        check(notifications.size() == 1 && notifications.front() == Change::TrackScope,
              "range must preserve time and report only its scope change");
    }
    {
        const auto used = (1u << 1) | (1u << 3);
        songview::EditorSelectionModel model;
        model.resetForSong(1u << 1);
        model.adjustTrackScope(3, used, songview::TrackScopeAction::Toggle);
        model.setTimeSelection(trackTime(90, 100));
        check(model.timeSelectionCoversTrack(1, used) && model.timeSelectionCoversTrack(3, used),
              "track-scoped time selection must cover every resolved scoped track");
        check(!model.timeSelectionCoversTrack(3, 1u << 1) &&
                  !model.timeSelectionCoversTrack(2, used) &&
                  !model.timeSelectionCoversTrack(-1, used) &&
                  !model.timeSelectionCoversTrack(16, used),
              "track coverage must resolve live used-track context and reject invalid tracks");
        check(model.timeSelectionCoversLane(1, 7, used) &&
                  model.timeSelectionCoversLane(3, DOC_CC_BEND, used) &&
                  !model.timeSelectionCoversLane(2, 7, used),
              "track-scoped lane coverage must follow live track scope");
        model.resetForSong(1u << 1);
        model.setTimeSelection(trackTime(90, 100));
        check(model.timeSelectionCoversLane(-1, DOC_CC_TEMPO, 1u << 1) &&
                  !model.timeSelectionCoversLane(-1, DOC_CC_TEMPO, used),
              "tempo coverage must require every currently used track");
        model.adjustTrackScope(3, used, songview::TrackScopeAction::Toggle);
        check(model.timeSelectionCoversLane(-1, DOC_CC_TEMPO, used) &&
                  !model.timeSelectionCoversLane(-1, DOC_CC_TEMPO, 0),
              "tempo coverage must become live when the scope covers all used tracks");
        model.setTimeSelection(laneTime(90, 100, {{1, 7}, {-1, DOC_CC_TEMPO}}));
        check(model.timeSelectionCoversLane(1, 7, 0) &&
                  model.timeSelectionCoversLane(-1, DOC_CC_TEMPO, 0) &&
                  !model.timeSelectionCoversLane(1, 8, used) &&
                  !model.timeSelectionCoversTrack(1, used),
              "lane-scoped coverage must use only explicit lane identities");
    }
    {
        const NoteId first(41);
        const NoteId second(42);
        const NoteId third(43);
        const auto time = trackTime(110, 120);
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.setNoteSelection({first, second});
        notifications.clear();
        model.clearNoteSelectionForDocument();
        check(model.noteSelection().empty() && notifications.size() == 1 &&
                  notifications.front() == Change::NoteSelection,
              "document attachment must clear note selection");
        model.setTimeSelection(time);
        notifications.clear();
        model.clearNoteSelectionForDocument();
        check(sameTime(model.timeSelection(), time) && notifications.empty(),
              "document attachment must preserve time selection on reattachment");
        model.clearTimeSelection();
        model.setNoteSelection({first, second, third});
        notifications.clear();
        model.reconcileNoteSelection({third, first, third});
        check(model.noteSelection() == std::vector<NoteId>{first, third} &&
                  notifications.size() == 1 && notifications.front() == Change::NoteSelection,
              "valid-ID reconciliation must retain surviving IDs in original order");
        notifications.clear();
        model.reconcileNoteSelection({first, third});
        check(notifications.empty(), "unchanged valid-ID reconciliation must not notify");
    }
    {
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.resetForSong(1u << 5);
        model.adjustTrackScope(2, (1u << 2) | (1u << 5), songview::TrackScopeAction::Toggle);
        model.setTimeSelection(trackTime(130, 140));
        notifications.clear();
        model.applyTrackRemap(engineRemap({0, 1, 1, 2, 3, -1, -1, -1}, 4));
        check(model.primaryTrack() == 3 && model.storedTrackScope() == ((1u << 1) | (1u << 3)) &&
                  !model.timeSelection().active(),
              "primary deletion must use the clamped fallback and clear track time");
        check(notifications.size() == 1 &&
                  notifications.front() ==
                      (Change::PrimaryTrack | Change::TrackScope | Change::TimeSelection),
              "primary deletion remap must notify its complete state once");
    }
    {
        const std::vector<std::pair<int, uint8_t>> expectedLanes{
            {4, 7}, {2, 8}, {-1, DOC_CC_TEMPO}};
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.resetForSong(1u << 1);
        model.adjustTrackScope(3, (1u << 1) | (1u << 3), songview::TrackScopeAction::Toggle);
        model.setTimeSelection(
            laneTime(150, 160, {{1, 7}, {3, 8}, {5, 9}, {-1, DOC_CC_TEMPO}, {3, 8}}));
        notifications.clear();
        model.applyTrackRemap(engineRemap({0, 4, 1, 2, -1, -1}, 5));
        check(model.primaryTrack() == 4 && model.storedTrackScope() == ((1u << 4) | (1u << 2)) &&
                  model.timeSelection().active() && model.timeSelection().lanes == expectedLanes,
              "track remap must move scope and lane identities while preserving tempo");
        check(notifications.size() == 1 &&
                  notifications.front() ==
                      (Change::PrimaryTrack | Change::TrackScope | Change::TimeSelection),
              "scope and lane remap must notify once with complete categories");
        model.clearTimeSelection();
        const NoteId retained(51);
        model.setNoteSelection({retained});
        notifications.clear();
        model.applyTrackRemap(engineRemap({0, 4, 1, 2, 3}, 4));
        check(model.isNoteSelected(retained) && notifications.size() == 1 &&
                  notifications.front() == (Change::PrimaryTrack | Change::TrackScope),
              "track remap must retain note IDs for later document reconciliation");
    }
    {
        songview::EditorSelectionModel model;
        model.resetForSong(1u << 0);
        model.setTimeSelection(laneTime(170, 180, {{2, 7}}));
        std::vector<Change> notifications;
        model.setChangeCallback(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.applyTrackRemap(engineRemap({0, 1, -1}, 2));
        check(sameTime(model.timeSelection(), TimeSelection()),
              "removing every lane identity must clear lane time selection");
        check(notifications.size() == 1 && notifications.front() == Change::TimeSelection,
              "lane-empty remap must notify only its time-selection change");
    }
    {
        const NoteId note(61);
        const auto time = trackTime(190, 200);
        std::vector<Change> notifications;
        songview::EditorSelectionModel model(
            [&notifications](Change changes) { notifications.push_back(changes); });
        model.setNoteSelection({note});
        notifications.clear();
        model.setNoteSelection({NoteId(), note, note});
        check(notifications.empty(), "equivalent sanitized note assignment must not notify");
        model.setTimeSelection(time);
        notifications.clear();
        model.setTimeSelection(time);
        check(notifications.empty(), "equivalent time assignment must not notify");
        model.clearTimeSelection();
        notifications.clear();
        model.clearTimeSelection();
        check(notifications.empty(), "clearing an empty time selection must not notify");
        model.clearSelections();
        check(notifications.empty(), "clearing already empty selections must not notify");
        model.transitionPrimaryTrack(0);
        model.transitionPrimaryTrack(-1);
        model.transitionPrimaryTrack(16);
        model.adjustTrackScope(-1, 1u, songview::TrackScopeAction::Plain);
        model.adjustTrackScope(16, 1u, songview::TrackScopeAction::Toggle);
        model.adjustTrackScope(0, 1u, songview::TrackScopeAction::Toggle);
        check(notifications.empty(), "invalid and empty-scope transitions must not notify");
        model.reconcileNoteSelection({});
        check(notifications.empty(), "reconciling an empty note selection must not notify");
        model.resetForSong(1u);
        model.clearNoteSelectionForDocument();
        model.applyTrackRemap(engineRemap({0}, 1));
        check(notifications.empty(), "identity reset and remap mutations must not notify");
    }
    if (failures == 0)
        std::printf("selectioncheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
