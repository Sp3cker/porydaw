#include "checks/rollcheck/rollcheck.h"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songviewmodel.h"

namespace checks::rollcheck {

ScenarioContinuation runIdentityScenarios(Harness &check, const SongInfo &song)
{
    SongView &view = check.view();
    songview::TimelineInputItem &rollInput = check.rollInput();
    const int track = check.track();
    auto fail = [&](const char *what) { check.fail(what); };
    // Coordinates cannot distinguish duplicate notes; their document IDs must
    // survive the timeline and view-model projections independently.
    {
        SongDocument projectionDoc;
        QString projectionError;
        if (!projectionDoc.load(song, &projectionError)) {
            fail("could not load note identity projection fixture");
        } else {
            const std::vector<DocNote> before = projectionDoc.notesForTrack(track);
            const SongDocument::NewNote duplicate{480, 60, 24, 100};
            projectionDoc.addNotes(track, {duplicate, duplicate});
            const std::vector<DocNote> after = projectionDoc.notesForTrack(track);
            std::vector<DocNote> duplicates;
            for (const DocNote &candidate : after) {
                const bool existed =
                    std::any_of(before.begin(), before.end(), [&](const DocNote &previous) {
                        return previous.noteId == candidate.noteId;
                    });
                if (!existed)
                    duplicates.push_back(candidate);
            }
            if (duplicates.size() != 2 || !duplicates[0].noteId.isAssigned() ||
                !duplicates[1].noteId.isAssigned() ||
                duplicates[0].noteId == duplicates[1].noteId ||
                duplicates[0].tick != duplicates[1].tick ||
                duplicates[0].duration != duplicates[1].duration ||
                duplicates[0].key != duplicates[1].key ||
                duplicates[0].velocity != duplicates[1].velocity) {
                fail("document did not mint distinct equal-visible duplicate note IDs");
            } else {
                const auto projectionTimeline = projectionDoc.buildTimeline(48000.0);
                const SongViewModel projection = buildSongViewModel(*projectionTimeline);
                std::vector<NoteId> projectedIds;
                for (const ViewNote &note : projection.notes) {
                    if (note.noteId == duplicates[0].noteId || note.noteId == duplicates[1].noteId)
                        projectedIds.push_back(note.noteId);
                }
                bool idsResolve = projectedIds.size() == 2;
                for (NoteId id : projectedIds) {
                    DocNote resolved;
                    if (!projectionDoc.findNote(id, &resolved) || resolved.noteId != id)
                        idsResolve = false;
                }
                if (!idsResolve || projectedIds[0] == projectedIds[1]) {
                    fail("duplicate note IDs did not project to their document notes");
                } else {
                    auto identityTimeline = projectionDoc.buildTimeline(48000.0);
                    SongView identityView;
                    identityView.resize(800, 480);
                    identityView.setSong(identityTimeline.get(), nullptr);
                    identityView.setDocument(&projectionDoc);
                    QObject::connect(&projectionDoc, &SongDocument::documentChanged, &identityView,
                                     [&] {
                                         auto rebuilt = projectionDoc.buildTimeline(48000.0);
                                         identityView.updateSong(rebuilt.get());
                                         identityTimeline = std::move(rebuilt);
                                     });
                    identityView.selectTrack(track);
                    identityView.selectionModel().setNoteSelection(
                        {duplicates[0].noteId, duplicates[1].noteId});
                    identityView.trackHeaderClicked(track, Qt::NoModifier);
                    if (!identityView.selectionModel().noteSelection().empty())
                        fail("plain click on the active track header did not clear note selection");

                    const DocNote firstBefore = duplicates[0];
                    const DocNote secondBefore = duplicates[1];
                    const auto sameNoteIdentityAndValue = [](const DocNote &lhs,
                                                             const DocNote &rhs) {
                        return lhs.noteId == rhs.noteId && lhs.engineTrack == rhs.engineTrack &&
                               lhs.smfTrack == rhs.smfTrack && lhs.tick == rhs.tick &&
                               lhs.duration == rhs.duration && lhs.key == rhs.key &&
                               lhs.velocity == rhs.velocity && lhs.channel == rhs.channel;
                    };
                    identityView.selectionModel().setNoteSelection({firstBefore.noteId});
                    projectionDoc.moveNotes({firstBefore}, 0, 1);
                    DocNote firstMoved;
                    DocNote secondUntouched;
                    DocNote expectedMoved = firstBefore;
                    expectedMoved.key++;
                    const bool firstEdit =
                        projectionDoc.findNote(firstBefore.noteId, &firstMoved) &&
                        sameNoteIdentityAndValue(firstMoved, expectedMoved);
                    const bool secondStable =
                        projectionDoc.findNote(secondBefore.noteId, &secondUntouched) &&
                        sameNoteIdentityAndValue(secondUntouched, secondBefore);
                    const std::vector<NoteId> &editedSelection =
                        identityView.selectionModel().noteSelection();
                    if (!firstEdit || !secondStable || editedSelection.size() != 1 ||
                        editedSelection.front() != firstBefore.noteId) {
                        fail("one-ID edit changed the wrong duplicate");
                    }

                    projectionDoc.undoStack()->undo();
                    DocNote firstRestored;
                    DocNote secondRestored;
                    const bool undoRestored =
                        projectionDoc.findNote(firstBefore.noteId, &firstRestored) &&
                        projectionDoc.findNote(secondBefore.noteId, &secondRestored) &&
                        sameNoteIdentityAndValue(firstRestored, firstBefore) &&
                        sameNoteIdentityAndValue(secondRestored, secondBefore);
                    const std::vector<NoteId> &undoSelection =
                        identityView.selectionModel().noteSelection();
                    if (!undoRestored || undoSelection.size() != 1 ||
                        undoSelection.front() != firstBefore.noteId) {
                        fail("one-ID SongView edit did not restore both duplicates on Undo");
                    }

                    identityView.selectionModel().setNoteSelection(
                        {duplicates[0].noteId, duplicates[1].noteId});
                    const int otherTrack = track == 0 ? 1 : 0;
                    if (otherTrack < projectionDoc.engineTrackCount()) {
                        identityView.trackHeaderClicked(otherTrack, Qt::NoModifier);
                        if (!identityView.selectionModel().noteSelection().empty())
                            fail("switching track headers did not clear note selection");
                    }
                }
            }
        }
    }

    {
        MidiTimeline ordinaryTimeline;
        ordinaryTimeline.lengthTicks = 288;
        ordinaryTimeline.events = {
            {0, 240, 0x9, 2, 65, 83, NoteId{}},
            {0, 288, 0x8, 2, 65, 0, NoteId{}},
        };
        const SongViewModel ordinary = buildSongViewModel(ordinaryTimeline);
        if (ordinary.notes.size() != 1) {
            fail("ordinary unassigned timeline note did not project");
        } else {
            const ViewNote &note = ordinary.notes.front();
            if (note.noteId.isAssigned() || note.startTick != 240 || note.endTick != 288 ||
                note.key != 65 || note.velocity != 83 || note.track != 2 || note.unterminated) {
                fail("ordinary unassigned timeline note changed during projection");
            }
        }
    }

    // Camera/grid state and typed drawer cosmetics are detached snapshots.
    {
        const SongView::ViewState before = view.viewState();
        const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), 7};
        EditorViewState cosmetics;
        cosmetics.laneHeight = 64;
        cosmetics.laneHeights.emplace(lane, 96);
        cosmetics.laneRanges.emplace(lane, 91);
        cosmetics.emptyLanes.emplace(lane);
        view.applyEditorViewState(cosmetics);
        if (view.editorViewState() != cosmetics)
            fail("SongView did not retain typed cosmetic EditorViewState");
        view.setEditCursorTick(view.grid().snapTick(96.0));
        const SongView::ViewState snapshot = view.viewState();
        SongView::ViewState perturbed = snapshot;
        perturbed.pxPerBeat = snapshot.pxPerBeat < 64.0 ? 64.0 : 16.0;
        perturbed.keyHeight = snapshot.keyHeight < 16.0 ? 16.0 : 8.0;
        perturbed.scrollPx = snapshot.scrollPx == 0.0 ? 1.0 : 0.0;
        perturbed.scrollY = snapshot.scrollY == 0.0 ? 1.0 : 0.0;
        int alternateTrack = snapshot.selectedTrack;
        for (int candidate = 0; candidate < 16; ++candidate) {
            if (candidate != snapshot.selectedTrack && check.timeline().tracks[candidate].used) {
                alternateTrack = candidate;
                break;
            }
        }
        perturbed.selectedTrack = alternateTrack;
        perturbed.editCursorTick = snapshot.editCursorTick == 0 ? 1 : 0;
        perturbed.gridMinDenom = snapshot.gridMinDenom == 4 ? 8 : 4;
        perturbed.gridTriplet = !snapshot.gridTriplet;
        perturbed.eventList = !snapshot.eventList;
        SongView::ViewState expected = perturbed;
        expected.pxPerBeat = std::clamp(perturbed.pxPerBeat, 4.0, 640.0);
        expected.keyHeight = std::clamp(perturbed.keyHeight, 4.0, 32.0);
        const double tpb = double(check.timeline().ticksPerBeat);
        const double maxHScroll =
            std::max(0.0, double(check.timeline().lengthTicks) * expected.pxPerBeat / tpb + 100.0 -
                              std::max<qreal>(50, rollInput.width()));
        expected.scrollPx = std::clamp(perturbed.scrollPx, 0.0, maxHScroll);
        const double maxRollScroll = std::max(0.0, 128.0 * expected.keyHeight - rollInput.height());
        expected.scrollY = std::clamp(perturbed.scrollY, 0.0, maxRollScroll);
        expected.selectedTrack = snapshot.selectedTrack;
        if (perturbed.selectedTrack >= 0 && perturbed.selectedTrack < 16 &&
            check.timeline().tracks[perturbed.selectedTrack].used)
            expected.selectedTrack = perturbed.selectedTrack;
        expected.editCursorTick = std::min(perturbed.editCursorTick, check.timeline().lengthTicks);
        expected.gridMinDenom = perturbed.gridMinDenom == 4 || perturbed.gridMinDenom == 8 ||
                                        perturbed.gridMinDenom == 16 || perturbed.gridMinDenom == 32
                                    ? perturbed.gridMinDenom
                                    : 0;
        view.applyViewState(perturbed);
        const SongView::ViewState applied = view.viewState();
        const auto sameViewState = [](const SongView::ViewState &lhs,
                                      const SongView::ViewState &rhs) {
            return lhs.valid == rhs.valid && std::abs(lhs.pxPerBeat - rhs.pxPerBeat) <= 1e-12 &&
                   std::abs(lhs.keyHeight - rhs.keyHeight) <= 1e-12 &&
                   std::abs(lhs.scrollPx - rhs.scrollPx) <= 1e-12 &&
                   std::abs(lhs.scrollY - rhs.scrollY) <= 1e-12 &&
                   lhs.selectedTrack == rhs.selectedTrack &&
                   lhs.editCursorTick == rhs.editCursorTick &&
                   lhs.gridMinDenom == rhs.gridMinDenom && lhs.gridTriplet == rhs.gridTriplet &&
                   lhs.eventList == rhs.eventList;
        };
        const auto differs = [](double lhs, double rhs) { return std::abs(lhs - rhs) > 1e-12; };
        if (!differs(expected.pxPerBeat, snapshot.pxPerBeat) ||
            !differs(expected.keyHeight, snapshot.keyHeight) ||
            !differs(expected.scrollPx, snapshot.scrollPx) ||
            !differs(expected.scrollY, snapshot.scrollY) ||
            expected.selectedTrack == snapshot.selectedTrack ||
            expected.editCursorTick == snapshot.editCursorTick ||
            expected.gridMinDenom == snapshot.gridMinDenom ||
            expected.gridTriplet == snapshot.gridTriplet ||
            expected.eventList == snapshot.eventList) {
            fail("ViewState perturbation did not change every retained field");
        }
        if (!sameViewState(applied, expected))
            fail("ViewState apply did not retain every normalized perturbed field");
        view.applyViewState(snapshot);
        const SongView::ViewState restored = view.viewState();
        if (view.editorViewState() != cosmetics || !sameViewState(restored, snapshot)) {
            fail(
                "ViewState capture/apply did not restore runtime state without changing cosmetics");
        }
        view.applyViewState(before);
    }

    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
