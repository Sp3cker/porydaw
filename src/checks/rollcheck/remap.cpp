#include "checks/rollcheck/tst_pianoroll.h"

#include <QtTest>

#include <QTemporaryDir>
#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "checks/rollcheck/headerchecksupport.h"
#include "checks/support/songfixture.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/songview.h"

namespace {
using checks::rollcheck::headercheck::model;
using checks::rollcheck::headercheck::recordsMatchTimeline;

struct RemapFixture {
    SongDocument document;
    std::unique_ptr<MidiTimeline> timeline;
    SongView view;
    std::vector<QString> order;

    bool prepare(const SongInfo &song, QString *error)
    {
        if (!document.load(song, error))
            return false;
        timeline = document.buildTimeline(48000.0);
        view.resize(800, 480);
        view.setSong(timeline.get(), nullptr);
        view.setDocument(&document);
        QObject::connect(&document, &SongDocument::tracksRemapped, &view,
                         [this] { order.push_back(QStringLiteral("remap")); });
        QObject::connect(&document, &SongDocument::documentChanged, &view, [this] {
            auto rebuilt = document.buildTimeline(48000.0);
            view.updateSong(rebuilt.get());
            timeline = std::move(rebuilt);
            order.push_back(QStringLiteral("document"));
        });
        return true;
    }

    bool remapPrecedesDocument() const
    {
        return order.size() == 2 && order[0] == QStringLiteral("remap") &&
               order[1] == QStringLiteral("document");
    }

    bool documentOnly() const
    {
        return order.size() == 1 && order.front() == QStringLiteral("document");
    }

    bool headersFollowTimeline()
    {
        auto *headers = model(view);
        return headers && recordsMatchTimeline(*headers, *timeline, document.canAddTrack());
    }

    void clearOrder() { order.clear(); }
};

EditorAutomationRowId controllerRow(int owner, uint8_t cc)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(owner), cc};
}

bool hasEmptyLane(const EditorViewState &state, int owner, uint8_t cc)
{
    return state.emptyLanes.find(controllerRow(owner, cc)) != state.emptyLanes.end();
}

bool hasRowValue(const auto &rows, const EditorAutomationRowId &row, int value)
{
    const auto found = rows.find(row);
    return found != rows.end() && int(found->second) == value;
}

bool hasNoOwnerCosmetics(const EditorViewState &state, int owner)
{
    const auto owns = [owner](const auto &entry) {
        return entry.first.kind != EditorAutomationRowKind::Tempo && entry.first.track == owner;
    };
    return std::none_of(state.laneHeights.cbegin(), state.laneHeights.cend(), owns) &&
           std::none_of(state.laneRanges.cbegin(), state.laneRanges.cend(), owns) &&
           !hasEmptyLane(state, owner, 7) && !hasEmptyLane(state, owner, 10) &&
           !hasEmptyLane(state, owner, 74);
}

EditorViewState remapCosmetics()
{
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    EditorViewState cosmetics;
    cosmetics.laneHeight = 64;
    cosmetics.laneHeights.emplace(tempo, 94);
    cosmetics.laneHeights.emplace(controllerRow(0, 7), 67);
    cosmetics.laneHeights.emplace(controllerRow(1, 10), 77);
    cosmetics.laneRanges.emplace(tempo, 116);
    cosmetics.laneRanges.emplace(controllerRow(0, 7), 102);
    cosmetics.laneRanges.emplace(controllerRow(1, 10), 92);
    cosmetics.emptyLanes.emplace(controllerRow(0, 7));
    cosmetics.emptyLanes.emplace(controllerRow(1, 10));
    return cosmetics;
}

bool hasRemappedCosmetics(const EditorViewState &state, int zeroOwner, int oneOwner)
{
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    return state.laneHeight == 64 && state.laneHeights.size() == 3 &&
           state.laneRanges.size() == 3 && state.emptyLanes.size() == 2 &&
           hasRowValue(state.laneHeights, tempo, 94) &&
           hasRowValue(state.laneHeights, controllerRow(zeroOwner, 7), 67) &&
           hasRowValue(state.laneHeights, controllerRow(oneOwner, 10), 77) &&
           hasRowValue(state.laneRanges, tempo, 116) &&
           hasRowValue(state.laneRanges, controllerRow(zeroOwner, 7), 102) &&
           hasRowValue(state.laneRanges, controllerRow(oneOwner, 10), 92) &&
           hasEmptyLane(state, zeroOwner, 7) && hasEmptyLane(state, oneOwner, 10);
}

bool hasRawCosmetics(const EditorViewState &state, int owner)
{
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    return state.laneHeight == 64 && state.laneHeights.size() == 2 &&
           state.laneRanges.size() == 2 && state.emptyLanes.size() == 1 &&
           hasRowValue(state.laneHeights, tempo, 94) &&
           hasRowValue(state.laneHeights, controllerRow(owner, 7), 67) &&
           hasRowValue(state.laneRanges, tempo, 116) &&
           hasRowValue(state.laneRanges, controllerRow(owner, 7), 102) &&
           hasEmptyLane(state, owner, 7);
}

bool hasTimeSelectionLanes(const SongView &view,
                           const std::vector<std::pair<int, uint8_t>> &expected)
{
    const songview::EditorSelectionModel::TimeSelection &selection =
        view.selectionModel().timeSelection();
    return selection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
           selection.startTick == 24 && selection.endTick == 48 && selection.lanes == expected;
}

bool hasMovedTrackState(const SongView &view)
{
    return view.selectionModel().primaryTrack() == 0 &&
           view.selectionModel().storedTrackScope() == 0x3 && view.trackMuted(1) &&
           !view.trackMuted(0) && view.trackSoloed(0) && !view.trackSoloed(1) &&
           hasRemappedCosmetics(view.editorViewState(), 1, 0);
}

bool hasOriginalTrackState(const SongView &view)
{
    return view.selectionModel().primaryTrack() == 1 &&
           view.selectionModel().storedTrackScope() == 0x3 && view.trackMuted(0) &&
           !view.trackMuted(1) && view.trackSoloed(1) && !view.trackSoloed(0) &&
           hasRemappedCosmetics(view.editorViewState(), 0, 1);
}
} // namespace

void PianoRollTest::trackRemapMove()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    RemapFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error))
        QFAIL("could not load track-remap fixture");
    if (fixture.document.engineTrackCount() < 2 || !fixture.document.canAddTrack())
        QFAIL("track-remap fixture lacks two tracks and an insertion slot");

    fixture.view.applyEditorViewState(remapCosmetics());
    fixture.view.selectionModel().clearNoteSelection();
    fixture.view.selectionModel().clearTimeSelection();
    fixture.view.setTrackMute(0, false);
    fixture.view.setTrackMute(1, false);
    fixture.view.setTrackSolo(0, false);
    fixture.view.setTrackSolo(1, false);
    fixture.view.selectTrack(1);
    fixture.view.trackHeaderClicked(0, Qt::ControlModifier);
    fixture.view.setTrackMute(0, true);
    fixture.view.setTrackSolo(1, true);
    songview::EditorSelectionModel::TimeSelection lanes;
    lanes.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    lanes.startTick = 24;
    lanes.endTick = 48;
    lanes.lanes = {{0, 7}, {1, 10}};
    fixture.view.selectionModel().setTimeSelection(lanes);

    fixture.document.moveTrack(0, 1);
    if (!fixture.remapPrecedesDocument())
        QFAIL("move did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!hasMovedTrackState(fixture.view) ||
        !hasTimeSelectionLanes(fixture.view, {{1, 7}, {0, 10}})) {
        QFAIL("move did not re-address complete SongView track state");
    }

    fixture.document.undoStack()->undo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("move undo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!hasOriginalTrackState(fixture.view) ||
        !hasTimeSelectionLanes(fixture.view, {{0, 7}, {1, 10}})) {
        QFAIL("move undo did not restore remapped owners");
    }

    fixture.document.undoStack()->redo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("move redo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!hasMovedTrackState(fixture.view) ||
        !hasTimeSelectionLanes(fixture.view, {{1, 7}, {0, 10}})) {
        QFAIL("move redo did not restore remapped owners");
    }
}

void PianoRollTest::trackRemapInsert()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    RemapFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error))
        QFAIL("could not load track-remap fixture");
    if (fixture.document.engineTrackCount() < 2 || !fixture.document.canAddTrack())
        QFAIL("track-remap fixture lacks two tracks and an insertion slot");

    fixture.view.applyEditorViewState(remapCosmetics());
    fixture.view.selectTrack(1);
    fixture.view.trackHeaderClicked(0, Qt::ControlModifier);
    fixture.view.setTrackMute(0, true);
    fixture.view.setTrackSolo(1, true);
    fixture.view.selectionModel().clearTimeSelection();
    fixture.view.selectionModel().clearNoteSelection();
    const int inserted = fixture.document.addTrack(0);
    if (inserted < 0)
        QFAIL("track-remap fixture could not insert a track");
    if (!fixture.remapPrecedesDocument())
        QFAIL("insert did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (fixture.view.trackMuted(inserted) || fixture.view.trackSoloed(inserted) ||
        (fixture.view.selectionModel().storedTrackScope() & (1u << inserted)) ||
        !hasOriginalTrackState(fixture.view) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), inserted)) {
        QFAIL("inserted track inherited existing SongView state");
    }

    fixture.document.undoStack()->undo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("insert undo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!hasOriginalTrackState(fixture.view))
        QFAIL("insert undo did not restore existing SongView state");

    fixture.document.undoStack()->redo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("insert redo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!hasOriginalTrackState(fixture.view))
        QFAIL("insert redo did not preserve existing SongView state");
}

void PianoRollTest::trackRemapDuplicate()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    RemapFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error))
        QFAIL("could not load track-remap fixture");
    if (fixture.document.engineTrackCount() < 2 || !fixture.document.canAddTrack())
        QFAIL("track-remap fixture lacks two tracks and an insertion slot");

    fixture.view.applyEditorViewState(remapCosmetics());
    fixture.view.selectTrack(1);
    fixture.view.trackHeaderClicked(0, Qt::ControlModifier);
    fixture.view.setTrackMute(0, true);
    fixture.view.setTrackSolo(1, true);
    fixture.view.selectionModel().clearTimeSelection();
    fixture.view.selectionModel().clearNoteSelection();
    const int duplicate = fixture.document.duplicateTrack(0);
    if (duplicate < 0)
        QFAIL("track-remap fixture could not duplicate a track");
    if (!fixture.remapPrecedesDocument())
        QFAIL("duplicate did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (fixture.view.trackMuted(duplicate) || fixture.view.trackSoloed(duplicate) ||
        (fixture.view.selectionModel().storedTrackScope() & (1u << duplicate)) ||
        !hasOriginalTrackState(fixture.view) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), duplicate)) {
        QFAIL("duplicated track inherited existing SongView state");
    }

    fixture.document.undoStack()->undo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("duplicate undo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!hasOriginalTrackState(fixture.view))
        QFAIL("duplicate undo did not restore existing SongView state");

    fixture.document.undoStack()->redo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("duplicate redo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!hasOriginalTrackState(fixture.view))
        QFAIL("duplicate redo did not preserve existing SongView state");
}

void PianoRollTest::trackRemapDelete()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    RemapFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error))
        QFAIL("could not load track-remap fixture");
    if (fixture.document.engineTrackCount() < 2)
        QFAIL("track-remap fixture lacks two tracks and an insertion slot");

    constexpr int removed = 1;
    fixture.view.selectTrack(0);
    fixture.view.trackHeaderClicked(removed, Qt::ControlModifier);
    fixture.view.setTrackMute(0, true);
    fixture.view.setTrackMute(removed, true);
    fixture.view.setTrackSolo(removed, true);
    fixture.view.addEmptyLane(removed, 74);
    EditorViewState deletedCosmetics = fixture.view.editorViewState();
    deletedCosmetics.laneHeights.emplace(controllerRow(removed, 74), 123);
    deletedCosmetics.laneRanges.emplace(controllerRow(removed, 74), 120);
    fixture.view.applyEditorViewState(deletedCosmetics);
    songview::EditorSelectionModel::TimeSelection deletedLanes;
    deletedLanes.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    deletedLanes.startTick = 24;
    deletedLanes.endTick = 48;
    deletedLanes.lanes = {{removed, 74}};
    fixture.view.selectionModel().setTimeSelection(deletedLanes);
    const std::vector<DocNote> duplicateNotes = fixture.document.notesForTrack(removed);
    if (!duplicateNotes.empty())
        fixture.view.selectionModel().setNoteSelection({duplicateNotes.front().noteId});

    fixture.document.deleteTrack(removed);
    if (!fixture.remapPrecedesDocument())
        QFAIL("delete did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (fixture.view.selectionModel().primaryTrack() == removed ||
        !fixture.view.selectionModel().noteSelection().empty() ||
        fixture.view.selectionModel().timeSelection().active() ||
        fixture.view.trackMuted(removed) || fixture.view.trackSoloed(removed) ||
        hasEmptyLane(fixture.view.editorViewState(), removed, 74)) {
        QFAIL("deleted track left SongView-owned state behind");
    }
    const int fallback = std::min(removed, fixture.document.engineTrackCount() - 1);
    if (fixture.view.selectionModel().primaryTrack() != fallback ||
        fixture.view.selectionModel().storedTrackScope() != (1u << fallback) ||
        !fixture.view.trackMuted(0) || fixture.view.trackSoloed(0) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), removed)) {
        QFAIL("delete did not drop cosmetic state from its removed owner");
    }

    fixture.document.undoStack()->undo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("delete undo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (!fixture.view.selectionModel().noteSelection().empty() ||
        fixture.view.selectionModel().timeSelection().active() ||
        fixture.view.trackMuted(removed) || fixture.view.trackSoloed(removed) ||
        hasEmptyLane(fixture.view.editorViewState(), removed, 74)) {
        QFAIL("restored track inherited dropped SongView state");
    }
    if (fixture.view.selectionModel().primaryTrack() != 0 ||
        fixture.view.selectionModel().storedTrackScope() != 0x1 || !fixture.view.trackMuted(0) ||
        fixture.view.trackSoloed(0) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), removed)) {
        QFAIL("delete undo did not restore surviving SongView state");
    }

    fixture.document.undoStack()->redo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("delete redo did not remap before documentChanged");
    if (!fixture.headersFollowTimeline())
        QFAIL("track header list did not follow the rebuilt timeline");
    fixture.clearOrder();
    if (fixture.view.selectionModel().primaryTrack() != 0 ||
        fixture.view.selectionModel().storedTrackScope() != 0x1 || !fixture.view.trackMuted(0) ||
        fixture.view.trackSoloed(0) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), removed)) {
        QFAIL("delete redo did not keep dropped SongView state absent");
    }
}

void PianoRollTest::trackRemapMetadata()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    RemapFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error))
        QFAIL("could not load track-remap fixture");
    if (fixture.document.engineTrackCount() < 2)
        QFAIL("track-remap fixture lacks two tracks and an insertion slot");

    fixture.view.applyEditorViewState(remapCosmetics());
    fixture.view.selectTrack(1);
    fixture.view.trackHeaderClicked(0, Qt::ControlModifier);
    fixture.view.setTrackMute(0, true);
    fixture.view.setTrackSolo(1, true);
    const int selected = fixture.view.selectionModel().primaryTrack();
    const uint32_t headerMask = fixture.view.selectionModel().storedTrackScope();
    const EditorViewState cosmetics = fixture.view.editorViewState();
    const bool mute0 = fixture.view.trackMuted(0);
    const bool mute1 = fixture.view.trackMuted(1);
    const bool mute2 = fixture.view.trackMuted(2);
    const bool solo0 = fixture.view.trackSoloed(0);
    const bool solo1 = fixture.view.trackSoloed(1);
    const bool solo2 = fixture.view.trackSoloed(2);
    const auto stateUnchanged = [&] {
        return fixture.view.selectionModel().primaryTrack() == selected &&
               fixture.view.selectionModel().storedTrackScope() == headerMask &&
               fixture.view.editorViewState() == cosmetics && fixture.view.trackMuted(0) == mute0 &&
               fixture.view.trackMuted(1) == mute1 && fixture.view.trackMuted(2) == mute2 &&
               fixture.view.trackSoloed(0) == solo0 && fixture.view.trackSoloed(1) == solo1 &&
               fixture.view.trackSoloed(2) == solo2;
    };

    fixture.document.renameTrack(0, QStringLiteral("rollcheck remap metadata"));
    if (!fixture.documentOnly() || !stateUnchanged())
        QFAIL("metadata-only edit changed SongView owner state");
    fixture.clearOrder();
    fixture.document.undoStack()->undo();
    if (!fixture.documentOnly() || !stateUnchanged())
        QFAIL("metadata-only undo changed SongView owner state");
    fixture.clearOrder();
    fixture.document.undoStack()->redo();
    if (!fixture.documentOnly() || !stateUnchanged())
        QFAIL("metadata-only redo changed SongView owner state");
}

void PianoRollTest::trackRemapEnginePromotion()
{
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
    QString error;
    if (!rawDir.isValid() || !rawSmf.writeFile(rawInfo.midPath, &error))
        QFAIL("could not write raw metadata-to-engine remap fixture");

    RemapFixture fixture;
    if (!fixture.prepare(rawInfo, &error))
        QFAIL("could not load raw metadata-to-engine remap fixture");
    if (fixture.document.engineTrackCount() != 1)
        QFAIL("raw metadata-to-engine fixture did not start with one engine owner");

    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    EditorViewState cosmetics;
    cosmetics.laneHeight = 64;
    cosmetics.laneHeights.emplace(tempo, 94);
    cosmetics.laneHeights.emplace(controllerRow(0, 7), 67);
    cosmetics.laneRanges.emplace(tempo, 116);
    cosmetics.laneRanges.emplace(controllerRow(0, 7), 102);
    cosmetics.emptyLanes.emplace(controllerRow(0, 7));
    fixture.view.applyEditorViewState(cosmetics);
    fixture.view.setTrackSolo(0, true);
    songview::EditorSelectionModel::TimeSelection tracks;
    tracks.startTick = 24;
    tracks.endTick = 48;
    fixture.view.selectionModel().setTimeSelection(tracks);

    SmfEvent promotedProgram;
    promotedProgram.status = 0xC0;
    promotedProgram.data0 = 3;
    fixture.document.insertRawEvent(0, promotedProgram);
    if (!fixture.remapPrecedesDocument())
        QFAIL("metadata-to-engine raw edit did not remap before documentChanged");
    fixture.clearOrder();
    if (fixture.view.selectionModel().primaryTrack() != 1 ||
        fixture.view.selectionModel().storedTrackScope() != 0x2 || fixture.view.trackMuted(0) ||
        fixture.view.trackMuted(1) || fixture.view.trackSoloed(0) || !fixture.view.trackSoloed(1) ||
        !fixture.view.selectionModel().timeSelection().active() ||
        !hasRawCosmetics(fixture.view.editorViewState(), 1) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), 0)) {
        QFAIL("metadata-to-engine raw edit did not remap SongView owners");
    }

    fixture.view.selectTrack(0);
    fixture.view.setTrackMute(0, true);
    fixture.view.selectionModel().setTimeSelection(tracks);
    fixture.document.undoStack()->undo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("engine-to-metadata raw undo did not remap before documentChanged");
    fixture.clearOrder();
    if (fixture.view.selectionModel().primaryTrack() != 0 ||
        fixture.view.selectionModel().storedTrackScope() != 0x1 || fixture.view.trackMuted(0) ||
        !fixture.view.trackSoloed(0) || fixture.view.selectionModel().timeSelection().active() ||
        !hasRawCosmetics(fixture.view.editorViewState(), 0) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), 1)) {
        QFAIL("engine-to-metadata fallback rebound SongView state to the wrong owner");
    }

    fixture.document.undoStack()->redo();
    if (!fixture.remapPrecedesDocument())
        QFAIL("metadata-to-engine raw redo did not remap before documentChanged");
    fixture.clearOrder();
    if (fixture.view.selectionModel().primaryTrack() != 1 ||
        fixture.view.selectionModel().storedTrackScope() != 0x2 || fixture.view.trackMuted(0) ||
        fixture.view.trackMuted(1) || fixture.view.trackSoloed(0) || !fixture.view.trackSoloed(1) ||
        fixture.view.selectionModel().timeSelection().active() ||
        !hasRawCosmetics(fixture.view.editorViewState(), 1) ||
        !hasNoOwnerCosmetics(fixture.view.editorViewState(), 0)) {
        QFAIL("metadata-to-engine redo did not preserve remapped SongView owners");
    }
}
