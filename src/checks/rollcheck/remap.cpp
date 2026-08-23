#include "checks/rollcheck/rollcheck.h"

#include <QByteArray>
#include <QObject>
#include <QTemporaryDir>
#include <QWidget>
#include <algorithm>
#include <utility>
#include <vector>

#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/songview.h"

namespace checks::rollcheck {

ScenarioContinuation runRemapScenarios(Harness &check, const SongInfo &song)
{
    auto fail = [&](const char *what) { check.fail(what); };
    // Track ownership remaps arrive before documentChanged. Every SongView
    // owner follows its mapping; removed owners drop state, and inverse
    // insertions begin with defaults rather than resurrecting it.
    {
        SongDocument remapDoc;
        QString remapError;
        if (!remapDoc.load(song, &remapError)) {
            fail("could not load track-remap fixture");
        } else if (remapDoc.engineTrackCount() < 2 || !remapDoc.canAddTrack()) {
            fail("track-remap fixture lacks two tracks and an insertion slot");
        } else {
            auto remapTimeline = remapDoc.buildTimeline(48000.0);
            SongView remapView;
            remapView.resize(800, 480);
            remapView.setSong(remapTimeline.get(), nullptr);
            remapView.setDocument(&remapDoc);
            std::vector<QString> order;
            QObject::connect(&remapDoc, &SongDocument::tracksRemapped, &remapView,
                             [&] { order.push_back(QStringLiteral("remap")); });
            QObject::connect(&remapDoc, &SongDocument::documentChanged, &remapView, [&] {
                auto rebuilt = remapDoc.buildTimeline(48000.0);
                remapView.updateSong(rebuilt.get());
                remapTimeline = std::move(rebuilt);
                order.push_back(QStringLiteral("document"));
            });
            const auto headersMatchTimeline = [&] {
                for (int track = 0; track < 16; ++track) {
                    const bool hasHeader =
                        remapView.findChild<QWidget *>(
                            QStringLiteral("trackHeaderRow%1").arg(track)) != nullptr;
                    if (hasHeader != remapTimeline->tracks[track].used)
                        return false;
                }
                return true;
            };
            const auto expectRemapBeforeDocument = [&](const char *what) {
                if (order.size() != 2 || order[0] != QStringLiteral("remap") ||
                    order[1] != QStringLiteral("document")) {
                    fail(what);
                }
                if (!headersMatchTimeline())
                    fail("track header list did not follow the rebuilt timeline");
                order.clear();
            };
            const auto hasEmptyLane = [](const EditorViewState &state, int owner, uint8_t cc) {
                return state.emptyLanes.find(EditorAutomationRowId{
                           EditorAutomationRowKind::ControlChange, uint8_t(owner), cc}) !=
                       state.emptyLanes.end();
            };
            const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
            const auto controllerRow = [](int owner, uint8_t cc) {
                return EditorAutomationRowId{EditorAutomationRowKind::ControlChange, uint8_t(owner),
                                             cc};
            };
            const auto hasRowValue = [](const auto &rows, const EditorAutomationRowId &row,
                                        int value) {
                const auto found = rows.find(row);
                return found != rows.end() && int(found->second) == value;
            };
            const auto hasNoOwnerCosmetics = [&](const EditorViewState &state, int owner) {
                const auto owns = [owner](const auto &entry) {
                    return entry.first.kind != EditorAutomationRowKind::Tempo &&
                           entry.first.track == owner;
                };
                return std::none_of(state.laneHeights.cbegin(), state.laneHeights.cend(), owns) &&
                       std::none_of(state.laneRanges.cbegin(), state.laneRanges.cend(), owns) &&
                       !hasEmptyLane(state, owner, 7) && !hasEmptyLane(state, owner, 10);
            };
            EditorViewState remapCosmetics;
            remapCosmetics.laneHeight = 64;
            remapCosmetics.laneHeights.emplace(tempo, 94);
            remapCosmetics.laneHeights.emplace(controllerRow(0, 7), 67);
            remapCosmetics.laneHeights.emplace(controllerRow(1, 10), 77);
            remapCosmetics.laneRanges.emplace(tempo, 116);
            remapCosmetics.laneRanges.emplace(controllerRow(0, 7), 102);
            remapCosmetics.laneRanges.emplace(controllerRow(1, 10), 92);
            remapCosmetics.emptyLanes.emplace(controllerRow(0, 7));
            remapCosmetics.emptyLanes.emplace(controllerRow(1, 10));
            remapView.applyEditorViewState(remapCosmetics);
            const auto hasRemappedCosmetics = [&](const EditorViewState &state, int zeroOwner,
                                                  int oneOwner) {
                return state.laneHeight == 64 && state.laneHeights.size() == 3 &&
                       state.laneRanges.size() == 3 && state.emptyLanes.size() == 2 &&
                       hasRowValue(state.laneHeights, tempo, 94) &&
                       hasRowValue(state.laneHeights, controllerRow(zeroOwner, 7), 67) &&
                       hasRowValue(state.laneHeights, controllerRow(oneOwner, 10), 77) &&
                       hasRowValue(state.laneRanges, tempo, 116) &&
                       hasRowValue(state.laneRanges, controllerRow(zeroOwner, 7), 102) &&
                       hasRowValue(state.laneRanges, controllerRow(oneOwner, 10), 92) &&
                       hasEmptyLane(state, zeroOwner, 7) && hasEmptyLane(state, oneOwner, 10);
            };
            const auto hasRawCosmetics = [&](const EditorViewState &state, int owner) {
                return state.laneHeight == 64 && state.laneHeights.size() == 2 &&
                       state.laneRanges.size() == 2 && state.emptyLanes.size() == 1 &&
                       hasRowValue(state.laneHeights, tempo, 94) &&
                       hasRowValue(state.laneHeights, controllerRow(owner, 7), 67) &&
                       hasRowValue(state.laneRanges, tempo, 116) &&
                       hasRowValue(state.laneRanges, controllerRow(owner, 7), 102) &&
                       hasEmptyLane(state, owner, 7);
            };
            const auto hasTimeSelectionLanes =
                [&](const std::vector<std::pair<int, uint8_t>> &expected) {
                    const songview::EditorSelectionModel::TimeSelection &selection =
                        remapView.selectionModel().timeSelection();
                    return selection.scope ==
                               songview::EditorSelectionModel::TimeSelection::Lanes &&
                           selection.startTick == 24 && selection.endTick == 48 &&
                           selection.lanes == expected;
                };
            const auto hasMovedTrackState = [&] {
                return remapView.selectionModel().primaryTrack() == 0 &&
                       remapView.selectionModel().storedTrackScope() == 0x3 &&
                       remapView.trackMuted(1) && !remapView.trackMuted(0) &&
                       remapView.trackSoloed(0) && !remapView.trackSoloed(1) &&
                       hasRemappedCosmetics(remapView.editorViewState(), 1, 0);
            };
            const auto hasOriginalTrackState = [&] {
                return remapView.selectionModel().primaryTrack() == 1 &&
                       remapView.selectionModel().storedTrackScope() == 0x3 &&
                       remapView.trackMuted(0) && !remapView.trackMuted(1) &&
                       remapView.trackSoloed(1) && !remapView.trackSoloed(0) &&
                       hasRemappedCosmetics(remapView.editorViewState(), 0, 1);
            };
            const auto hasMovedOwnerState = [&] {
                return hasMovedTrackState() && hasTimeSelectionLanes({{1, 7}, {0, 10}});
            };
            const auto hasOriginalOwnerState = [&] {
                return hasOriginalTrackState() && hasTimeSelectionLanes({{0, 7}, {1, 10}});
            };
            // Restore the complete fixture before exercising the main remap matrix.
            remapView.applyEditorViewState(remapCosmetics);
            remapView.selectionModel().clearNoteSelection();
            remapView.selectionModel().clearTimeSelection();
            remapView.setTrackMute(0, false);
            remapView.setTrackMute(1, false);
            remapView.setTrackSolo(0, false);
            remapView.setTrackSolo(1, false);

            remapView.selectTrack(1);
            remapView.trackHeaderClicked(0, Qt::ControlModifier);
            remapView.setTrackMute(0, true);
            remapView.setTrackSolo(1, true);
            songview::EditorSelectionModel::TimeSelection lanes;
            lanes.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
            lanes.startTick = 24;
            lanes.endTick = 48;
            lanes.lanes = {{0, 7}, {1, 10}};
            remapView.selectionModel().setTimeSelection(lanes);

            remapDoc.moveTrack(0, 1);
            expectRemapBeforeDocument("move did not remap before documentChanged");
            if (!hasMovedOwnerState())
                fail("move did not re-address complete SongView track state");
            remapDoc.undoStack()->undo();
            expectRemapBeforeDocument("move undo did not remap before documentChanged");
            if (!hasOriginalOwnerState())
                fail("move undo did not restore remapped owners");
            remapDoc.undoStack()->redo();
            expectRemapBeforeDocument("move redo did not remap before documentChanged");
            if (!hasMovedOwnerState())
                fail("move redo did not restore remapped owners");

            // Later track-structure cases start without the move case's
            // lane-selection payload.
            remapView.selectionModel().clearTimeSelection();
            remapView.selectionModel().clearNoteSelection();

            const int inserted = remapDoc.addTrack(0);
            if (inserted < 0) {
                fail("track-remap fixture could not insert a track");
            } else {
                expectRemapBeforeDocument("insert did not remap before documentChanged");
                if (remapView.trackMuted(inserted) || remapView.trackSoloed(inserted) ||
                    (remapView.selectionModel().storedTrackScope() & (1u << inserted)) ||
                    !hasMovedTrackState() ||
                    !hasNoOwnerCosmetics(remapView.editorViewState(), inserted)) {
                    fail("inserted track inherited existing SongView state");
                }
                remapDoc.undoStack()->undo();
                expectRemapBeforeDocument("insert undo did not remap before documentChanged");
                if (!hasMovedTrackState())
                    fail("insert undo did not restore existing SongView state");

                remapDoc.undoStack()->redo();
                expectRemapBeforeDocument("insert redo did not remap before documentChanged");
                if (!hasMovedTrackState())
                    fail("insert redo did not preserve existing SongView state");
            }

            const int duplicate = remapDoc.duplicateTrack(0);
            if (duplicate < 0) {
                fail("track-remap fixture could not duplicate a track");
            } else {
                expectRemapBeforeDocument("duplicate did not remap before documentChanged");
                if (remapView.trackMuted(duplicate) || remapView.trackSoloed(duplicate) ||
                    (remapView.selectionModel().storedTrackScope() & (1u << duplicate)) ||
                    !hasMovedTrackState() ||
                    !hasNoOwnerCosmetics(remapView.editorViewState(), duplicate)) {
                    fail("duplicated track inherited existing SongView state");
                }
                remapDoc.undoStack()->undo();
                expectRemapBeforeDocument("duplicate undo did not remap before documentChanged");
                if (!hasMovedTrackState())
                    fail("duplicate undo did not restore existing SongView state");

                remapDoc.undoStack()->redo();
                expectRemapBeforeDocument("duplicate redo did not remap before documentChanged");
                if (!hasMovedTrackState())
                    fail("duplicate redo did not preserve existing SongView state");

                remapView.selectTrack(duplicate);
                remapView.setTrackMute(duplicate, true);
                remapView.setTrackSolo(duplicate, true);
                remapView.addEmptyLane(duplicate, 74);
                EditorViewState deletedCosmetics = remapView.editorViewState();
                deletedCosmetics.laneHeights.emplace(controllerRow(duplicate, 74), 123);
                deletedCosmetics.laneRanges.emplace(controllerRow(duplicate, 74), 120);
                remapView.applyEditorViewState(deletedCosmetics);

                songview::EditorSelectionModel::TimeSelection deletedLanes;
                deletedLanes.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
                deletedLanes.startTick = 24;
                deletedLanes.endTick = 48;
                deletedLanes.lanes = {{duplicate, 74}};
                remapView.selectionModel().setTimeSelection(deletedLanes);
                const std::vector<DocNote> duplicateNotes = remapDoc.notesForTrack(duplicate);
                if (!duplicateNotes.empty())
                    remapView.selectionModel().setNoteSelection({duplicateNotes.front().noteId});
                remapDoc.deleteTrack(duplicate);
                expectRemapBeforeDocument("delete did not remap before documentChanged");
                if (remapView.selectionModel().primaryTrack() == duplicate ||
                    !remapView.selectionModel().noteSelection().empty() ||
                    remapView.selectionModel().timeSelection().active() ||
                    remapView.trackMuted(duplicate) ||
                    remapView.trackSoloed(duplicate) ||
                    hasEmptyLane(remapView.editorViewState(), duplicate, 74)) {
                    fail("deleted track left SongView-owned state behind");
                }
                const int fallback = std::min(duplicate, remapDoc.engineTrackCount() - 1);
                if (remapView.selectionModel().primaryTrack() != fallback ||
                    remapView.selectionModel().storedTrackScope() != (1u << fallback) ||
                    remapView.trackMuted(0) || !remapView.trackMuted(1) ||
                    remapView.trackSoloed(1) || !remapView.trackSoloed(0) ||
                    !hasRemappedCosmetics(remapView.editorViewState(), 1, 0)) {
                    fail("delete did not drop cosmetic state from its removed owner");
                }

                remapDoc.undoStack()->undo();
                expectRemapBeforeDocument("delete undo did not remap before documentChanged");
                if (!remapView.selectionModel().noteSelection().empty() ||
                    remapView.selectionModel().timeSelection().active() ||
                    remapView.trackMuted(duplicate) ||
                    remapView.trackSoloed(duplicate) ||
                    hasEmptyLane(remapView.editorViewState(), duplicate, 74)) {
                    fail("restored track inherited dropped SongView state");
                }
                if (remapView.selectionModel().primaryTrack() != duplicate - 1 ||
                    remapView.selectionModel().storedTrackScope() != (1u << (duplicate - 1)) ||
                    remapView.trackMuted(0) || !remapView.trackMuted(1) ||
                    remapView.trackSoloed(1) || !remapView.trackSoloed(0) ||
                    !hasRemappedCosmetics(remapView.editorViewState(), 1, 0)) {
                    fail("delete undo did not restore surviving SongView state");
                }

                remapDoc.undoStack()->redo();
                expectRemapBeforeDocument("delete redo did not remap before documentChanged");
                if (remapView.selectionModel().primaryTrack() != duplicate - 1 ||
                    remapView.selectionModel().storedTrackScope() != (1u << (duplicate - 1)) ||
                    remapView.trackMuted(0) || !remapView.trackMuted(1) ||
                    remapView.trackSoloed(1) || !remapView.trackSoloed(0) ||
                    !hasRemappedCosmetics(remapView.editorViewState(), 1, 0)) {
                    fail("delete redo did not keep dropped SongView state absent");
                }
            }
            const int metadataSelected = remapView.selectionModel().primaryTrack();
            const uint32_t metadataHeaderMask = remapView.selectionModel().storedTrackScope();
            const EditorViewState metadataCosmetics = remapView.editorViewState();
            const bool metadataMute0 = remapView.trackMuted(0);
            const bool metadataMute1 = remapView.trackMuted(1);
            const bool metadataMute2 = remapView.trackMuted(2);
            const bool metadataSolo0 = remapView.trackSoloed(0);
            const bool metadataSolo1 = remapView.trackSoloed(1);
            const bool metadataSolo2 = remapView.trackSoloed(2);
            const auto metadataStateUnchanged = [&] {
                return remapView.selectionModel().primaryTrack() == metadataSelected &&
                       remapView.selectionModel().storedTrackScope() == metadataHeaderMask &&
                       remapView.editorViewState() == metadataCosmetics &&
                       remapView.trackMuted(0) == metadataMute0 &&
                       remapView.trackMuted(1) == metadataMute1 &&
                       remapView.trackMuted(2) == metadataMute2 &&
                       remapView.trackSoloed(0) == metadataSolo0 &&
                       remapView.trackSoloed(1) == metadataSolo1 &&
                       remapView.trackSoloed(2) == metadataSolo2;
            };

            remapDoc.renameTrack(0, QStringLiteral("rollcheck remap metadata"));
            if (order.size() != 1 || order.front() != QStringLiteral("document") ||
                !metadataStateUnchanged()) {
                fail("metadata-only edit changed SongView owner state");
            }
            order.clear();
            remapDoc.undoStack()->undo();
            if (order.size() != 1 || order.front() != QStringLiteral("document") ||
                !metadataStateUnchanged()) {
                fail("metadata-only undo changed SongView owner state");
            }
            order.clear();
            remapDoc.undoStack()->redo();
            if (order.size() != 1 || order.front() != QStringLiteral("document") ||
                !metadataStateUnchanged()) {
                fail("metadata-only redo changed SongView owner state");
            }
            QTemporaryDir rawDir;
            SmfFile rawSmf;
            rawSmf.tracks.resize(2);
            rawSmf.tracks[0].endTick = 96;
            rawSmf.tracks[1].endTick = 96;
            SmfEvent metadata;
            metadata.status = 0xFF;
            metadata.metaType = 0x01;
            metadata.blob = QByteArrayLiteral("metadata");
            rawSmf.tracks[0].events.push_back(metadata);
            SmfEvent originalProgram;
            originalProgram.status = 0xC1;
            originalProgram.data0 = 4;
            rawSmf.tracks[1].events.push_back(originalProgram);
            SongInfo rawInfo;
            rawInfo.label = QStringLiteral("rollcheck_raw_remap");
            rawInfo.midPath = rawDir.filePath(QStringLiteral("raw-remap.mid"));
            rawInfo.hasMid = true;
            QString rawError;
            if (!rawDir.isValid() || !rawSmf.writeFile(rawInfo.midPath, &rawError)) {
                fail("could not write raw metadata-to-engine remap fixture");
            } else {
                SongDocument rawDoc;
                if (!rawDoc.load(rawInfo, &rawError)) {
                    fail("could not load raw metadata-to-engine remap fixture");
                } else if (rawDoc.engineTrackCount() != 1) {
                    fail("raw metadata-to-engine fixture did not start with one engine owner");
                } else {
                    auto rawTimeline = rawDoc.buildTimeline(48000.0);
                    SongView rawView;
                    rawView.resize(800, 480);
                    rawView.setSong(rawTimeline.get(), nullptr);
                    rawView.setDocument(&rawDoc);
                    std::vector<QString> rawOrder;
                    QObject::connect(&rawDoc, &SongDocument::tracksRemapped, &rawView,
                                     [&] { rawOrder.push_back(QStringLiteral("remap")); });
                    QObject::connect(&rawDoc, &SongDocument::documentChanged, &rawView, [&] {
                        auto rebuilt = rawDoc.buildTimeline(48000.0);
                        rawView.updateSong(rebuilt.get());
                        rawTimeline = std::move(rebuilt);
                        rawOrder.push_back(QStringLiteral("document"));
                    });
                    const auto expectRawRemapBeforeDocument = [&](const char *what) {
                        if (rawOrder.size() != 2 || rawOrder[0] != QStringLiteral("remap") ||
                            rawOrder[1] != QStringLiteral("document")) {
                            fail(what);
                        }
                        rawOrder.clear();
                    };
                    EditorViewState rawCosmetics;
                    rawCosmetics.laneHeight = 64;
                    rawCosmetics.laneHeights.emplace(tempo, 94);
                    rawCosmetics.laneHeights.emplace(controllerRow(0, 7), 67);
                    rawCosmetics.laneRanges.emplace(tempo, 116);
                    rawCosmetics.laneRanges.emplace(controllerRow(0, 7), 102);
                    rawCosmetics.emptyLanes.emplace(controllerRow(0, 7));
                    rawView.applyEditorViewState(rawCosmetics);
                    rawView.setTrackSolo(0, true);
                    songview::EditorSelectionModel::TimeSelection rawTracks;
                    rawTracks.startTick = 24;
                    rawTracks.endTick = 48;
                    rawView.selectionModel().setTimeSelection(rawTracks);
                    SmfEvent promotedProgram;
                    promotedProgram.status = 0xC0;
                    promotedProgram.data0 = 3;
                    rawDoc.insertRawEvent(0, promotedProgram);
                    expectRawRemapBeforeDocument(
                        "metadata-to-engine raw edit did not remap before documentChanged");
                    if (rawView.selectionModel().primaryTrack() != 1 ||
                        rawView.selectionModel().storedTrackScope() != 0x2 ||
                        rawView.trackMuted(0) || rawView.trackMuted(1) || rawView.trackSoloed(0) ||
                        !rawView.trackSoloed(1) ||
                        !rawView.selectionModel().timeSelection().active() ||
                        !hasRawCosmetics(rawView.editorViewState(), 1) ||
                        !hasNoOwnerCosmetics(rawView.editorViewState(), 0)) {
                        fail("metadata-to-engine raw edit did not remap SongView owners");
                    }
                    rawView.selectTrack(0);
                    rawView.setTrackMute(0, true);
                    rawView.selectionModel().setTimeSelection(rawTracks);
                    rawDoc.undoStack()->undo();
                    expectRawRemapBeforeDocument(
                        "engine-to-metadata raw undo did not remap before documentChanged");
                    if (rawView.selectionModel().primaryTrack() != 0 ||
                        rawView.selectionModel().storedTrackScope() != 0x1 ||
                        rawView.trackMuted(0) || !rawView.trackSoloed(0) ||
                        rawView.selectionModel().timeSelection().active() ||
                        !hasRawCosmetics(rawView.editorViewState(), 0) ||
                        !hasNoOwnerCosmetics(rawView.editorViewState(), 1)) {
                        fail("engine-to-metadata fallback rebound SongView state to the wrong "
                             "owner");
                    }
                    rawDoc.undoStack()->redo();
                    expectRawRemapBeforeDocument(
                        "metadata-to-engine raw redo did not remap before documentChanged");
                    if (rawView.selectionModel().primaryTrack() != 1 ||
                        rawView.selectionModel().storedTrackScope() != 0x2 ||
                        rawView.trackMuted(0) || rawView.trackMuted(1) || rawView.trackSoloed(0) ||
                        !rawView.trackSoloed(1) ||
                        rawView.selectionModel().timeSelection().active() ||
                        !hasRawCosmetics(rawView.editorViewState(), 1) ||
                        !hasNoOwnerCosmetics(rawView.editorViewState(), 0)) {
                        fail("metadata-to-engine redo did not preserve remapped SongView owners");
                    }
                }
            }
        }
    }

    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
