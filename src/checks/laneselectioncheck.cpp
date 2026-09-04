#include <cstdint>
#include <cstdio>
#include <memory>
#include <utility>
#include <vector>

#include "core/miditimeline.h"
#include "core/smf.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/laneselection.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

using EditorSelectionModel = songview::EditorSelectionModel;

EditorAutomationRowId ccId(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

AutomationRow ccRow(int track, uint8_t controller)
{
    return AutomationRow{ccId(track, controller)};
}

EditorAutomationRowId tempoId()
{
    return {EditorAutomationRowKind::Tempo, 0, 0};
}

EditorAutomationRowId invalidId()
{
    return ccId(0, 99);
}

// A focused model with the requested time selection already applied. The
// model sanitizes identities the same way the production path does.
EditorSelectionModel selectionModel(uint64_t startTick, uint64_t endTick,
                                    EditorSelectionModel::TimeSelection::Scope scope,
                                    std::vector<std::pair<int, uint8_t>> lanes = {},
                                    bool tempo = false)
{
    EditorSelectionModel model;
    EditorSelectionModel::TimeSelection selection;
    selection.startTick = startTick;
    selection.endTick = endTick;
    selection.scope = scope;
    selection.lanes = std::move(lanes);
    selection.tempo = tempo;
    model.setTimeSelection(selection);
    return model;
}

// A real projection over a SongView with an empty timeline, so hitTest's
// tick -> x mapping is the production one. Expected hit ranges are derived
// from the projection itself, keeping the cases independent of zoom/scroll.
struct ProjectionRig {
    ProjectionRig()
    {
        m_timeline = MidiTimeline::build(SmfFile{}, 48000.0);
        m_view.setSong(m_timeline.get(), nullptr);
        m_view.setEditorTimeZoom(96.0);
        m_projection = std::make_unique<AutomationProjection>(
            AutomationGeometry::resolve(m_view.timelineSplitX()), &m_view);
    }

    AutomationProjection &projection() noexcept { return *m_projection; }

  private:
    std::unique_ptr<MidiTimeline> m_timeline;
    SongView m_view;
    std::unique_ptr<AutomationProjection> m_projection;
};

} // namespace

int runLaneSelectionCheck()
{
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        ++failures;
        std::fprintf(stderr, "laneselectioncheck: %s\n", what);
    };
    const auto expect = [&fail](bool condition, const char *what) {
        if (!condition)
            fail(what);
    };

    const uint32_t usedTracks = uint32_t{1} << 0; // only engine track 0 used
    const std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};

    {
        // Empty selection: inactive view, no lane or node coverage.
        auto model = EditorSelectionModel{};
        LaneSelection view(model, rows, usedTracks);
        expect(!view.active(), "default model reported an active selection");
        expect(!view.coversLane(tempoId()) && !view.coversNodes(tempoId()),
               "empty selection covered tempo");
        expect(!view.coversLane(ccId(0, 7)) && !view.coversNodes(ccId(0, 7)),
               "empty selection covered a CC lane");
        expect(!view.coversLane(invalidId()) && !view.coversNodes(invalidId()),
               "empty selection covered an invalid row identity");
        expect(view.visibleLanes().empty(), "empty selection reported visible lanes");
        const auto set = view.laneSet(tempoId(), ccId(0, 10));
        expect(set.first && set.second.size() == 2 &&
                   set.second == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 10}},
               "laneSet over an empty selection changed span shape");
    }

    {
        // Lanes scope: lane-range and node coverage both name only the
        // listed, present rows; tempo is covered only when selected.
        auto model = selectionModel(24, 48, EditorSelectionModel::TimeSelection::Lanes,
                                    {{0, 7}, {0, 21}}, true);
        LaneSelection view(model, rows, usedTracks);
        expect(view.active(), "active lane selection not reported active");
        expect(view.coversLane(tempoId()) && view.coversNodes(tempoId()),
               "tempo-flagged selection did not cover tempo");
        expect(view.coversLane(ccId(0, 7)) && view.coversNodes(ccId(0, 7)),
               "listed row 0/7 was not covered");
        expect(view.coversLane(ccId(0, 21)) && view.coversNodes(ccId(0, 21)),
               "listed row 0/21 was not covered");
        expect(!view.coversLane(ccId(0, 10)) && !view.coversNodes(ccId(0, 10)),
               "unlisted row 0/10 was covered");
        expect(!view.coversLane(ccId(0, 99)) && !view.coversNodes(ccId(0, 99)),
               "out-of-table row identity was covered");
        expect(view.visibleLanes() == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 21}},
               "visibleLanes did not filter rows in row order");
        const auto tempoOnly =
            selectionModel(24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}}, false);
        LaneSelection noTempo{tempoOnly, rows, usedTracks};
        expect(!noTempo.coversLane(tempoId()) && !noTempo.coversNodes(tempoId()),
               "non-tempo lane selection covered the tempo row");
    }

    {
        // Tracks scope: CC lane-range coverage is gated off for menus and
        // reticles, while node coverage follows the selected track.
        auto model = selectionModel(24, 48, EditorSelectionModel::TimeSelection::Tracks);
        LaneSelection full{model, rows, usedTracks};
        expect(full.coversLane(tempoId()) && full.coversNodes(tempoId()),
               "Tracks-scope selection over every used track did not cover tempo");
        expect(!full.coversLane(ccId(0, 7)) && full.coversNodes(ccId(0, 7)),
               "Tracks-scope selection did not distinguish CC lane and node coverage");
        LaneSelection partial{model, rows, usedTracks | (uint32_t{1} << 1)};
        expect(!partial.coversLane(tempoId()) && !partial.coversNodes(tempoId()),
               "Tracks-scope selection covered tempo with an unmasked used track");
    }

    {
        // Hidden-lane filtering: a model lane absent from the row table is
        // not covered and stays out of visibleLanes.
        auto model = selectionModel(24, 48, EditorSelectionModel::TimeSelection::Lanes,
                                    {{0, 7}, {0, 21}}, false);
        const std::vector<AutomationRow> hidden = {ccRow(0, 7), ccRow(0, 10)};
        LaneSelection view{model, hidden, usedTracks};
        expect(view.coversLane(ccId(0, 7)) && view.coversNodes(ccId(0, 7)) &&
                   !view.coversLane(ccId(0, 10)) && !view.coversNodes(ccId(0, 10)),
               "hidden lane was covered or a visible lane was not");
        expect(view.visibleLanes() == std::vector<std::pair<int, uint8_t>>{{0, 7}},
               "visibleLanes did not drop the hidden lane");
    }

    {
        // The view is live over the row table: a rebuild may insert a CC
        // between existing rows, but coverage follows each row identity and
        // stale identities stop resolving when the row disappears.
        auto model = selectionModel(24, 48, EditorSelectionModel::TimeSelection::Lanes,
                                    {{0, 7}, {0, 21}}, true);
        std::vector<AutomationRow> rebuilt = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        LaneSelection view{model, rebuilt, usedTracks};
        rebuilt = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 11), ccRow(0, 21)};
        expect(view.coversLane(tempoId()) && view.coversLane(ccId(0, 7)) &&
                   !view.coversLane(ccId(0, 10)) && !view.coversLane(ccId(0, 11)) &&
                   view.coversLane(ccId(0, 21)) &&
                   view.visibleLanes() == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 21}},
               "row rebuild remapped tempo or CC coverage by stale identity");
        rebuilt = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        expect(view.coversLane(ccId(0, 21)) && !view.coversLane(ccId(0, 11)) &&
                   view.laneSet(ccId(0, 11), ccId(0, 11)).second.empty(),
               "row removal left a stale CC identity resolvable");

        auto trackModel =
            selectionModel(24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 10}}, false);
        const std::vector<AutomationRow> trackRows = {ccRow(0, 10), ccRow(1, 10)};
        LaneSelection trackView{trackModel, trackRows, usedTracks | (uint32_t{1} << 1)};
        expect(trackView.coversLane(ccId(0, 10)) && !trackView.coversLane(ccId(1, 10)) &&
                   trackView.coversNodes(ccId(0, 10)) && !trackView.coversNodes(ccId(1, 10)),
               "CC identity coverage ignored the track component");
    }

    {
        // hitTest maps the tick range through the projection with an
        // explicit min/max. The model's active() = endTick > startTick, so
        // a swapped selection is inactive and the min/max here is a pure
        // defensive reorder; the half-open [startX, endX) range is asserted
        // on the canonical row identity.
        ProjectionRig rig;
        auto model =
            selectionModel(48, 96, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}}, false);
        LaneSelection view{model, rows, usedTracks};
        const qreal startX = rig.projection().displayX(48, 1.0);
        const qreal endX = rig.projection().displayX(96, 1.0);
        const qreal midX = (startX + endX) / 2.0;
        expect(view.hitTest(ccId(0, 7), startX, rig.projection(), 1.0),
               "hitTest rejected the range start");
        expect(view.hitTest(ccId(0, 7), midX, rig.projection(), 1.0),
               "hitTest rejected mid-range x");
        expect(!view.hitTest(ccId(0, 7), startX - 1.0, rig.projection(), 1.0),
               "hitTest accepted x before the range");
        expect(!view.hitTest(ccId(0, 7), endX, rig.projection(), 1.0),
               "hitTest accepted the half-open range end");
        expect(!view.hitTest(ccId(0, 10), midX, rig.projection(), 1.0),
               "hitTest hit an uncovered lane");
        expect(!view.hitTest(tempoId(), midX, rig.projection(), 1.0),
               "hitTest hit tempo without a tempo selection");
    }

    {
        // laneSet: semantic endpoint identities derive the inclusive visual
        // interval and publish one {tempo, lanes} payload; unknown identities
        // yield empty.
        auto model = EditorSelectionModel{};
        LaneSelection view{model, rows, usedTracks};
        const auto tempoOnly = view.laneSet(tempoId(), tempoId());
        expect(tempoOnly.first && tempoOnly.second.empty(),
               "tempo-only laneSet was not tempo-only");
        const auto ccOnly = view.laneSet(ccId(0, 7), ccId(0, 7));
        expect(!ccOnly.first && ccOnly.second == std::vector<std::pair<int, uint8_t>>{{0, 7}},
               "single CC laneSet was wrong");
        const auto mixed = view.laneSet(tempoId(), ccId(0, 10));
        expect(mixed.first && mixed.second == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 10}},
               "mixed laneSet was wrong");
        const auto reversed = view.laneSet(ccId(0, 10), tempoId());
        expect(reversed.first && reversed.second == mixed.second,
               "reversed laneSet did not match the forward span");
        const auto invalid = view.laneSet(invalidId(), ccId(0, 7));
        expect(!invalid.first && invalid.second.empty(), "invalid laneSet span reported lanes");
    }

    return failures == 0 ? 0 : 1;
}