#include "ui/editordrawer/automationviewmodel.h"

#include <algorithm>
#include <cstdint>
#include <utility>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/songview/detail.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

template <class Point>
bool anyPointInRange(const std::vector<Point> &points,
                     const std::optional<std::pair<Tick, Tick>> &range) noexcept
{
    if (!range)
        return false;
    return std::any_of(points.cbegin(), points.cend(), [&range](const Point &point) {
        return point.tick >= range->first && point.tick < range->second;
    });
}

} // namespace

std::span<const AutomationViewModel::Row> AutomationViewModel::visibleRows() const noexcept
{
    return {rows.data(), std::min(visibleRowCount, rows.size())};
}

const AutomationViewModel::Row *AutomationViewModel::find(EditorAutomationRowId id) const noexcept
{
    const auto row = std::find_if(rows.cbegin(), rows.cend(),
                                  [id](const Row &candidate) { return candidate.id == id; });
    return row == rows.cend() ? nullptr : &*row;
}

bool AutomationViewModel::hitTest(EditorAutomationRowId id, qreal x,
                                  const AutomationProjection &projection, qreal dpr,
                                  const songview::EditorSelectionModel &selection) const noexcept
{
    const Row *row = find(id);
    if (!row || !row->coversLane)
        return false;
    const auto &timeSelection = selection.timeSelection();
    const qreal startX = projection.displayX(timeSelection.startTick, dpr);
    const qreal endX = projection.displayX(timeSelection.endTick, dpr);
    return x >= std::min(startX, endX) && x < std::max(startX, endX);
}

std::vector<std::pair<int, uint8_t>>
AutomationViewModel::visibleLanes(const songview::EditorSelectionModel &selection) const noexcept
{
    std::vector<std::pair<int, uint8_t>> lanes;
    if (!selection.timeSelection().active())
        return lanes;
    const auto &timeSelection = selection.timeSelection();
    const auto visible = visibleRows();
    for (auto row = visible.begin() + (visible.empty() ? 0 : 1); row != visible.end(); ++row) {
        if (row->id.kind != EditorAutomationRowKind::ControlChange)
            continue;
        const auto identity = std::pair{int(row->id.track), row->id.controller};
        if (std::find(timeSelection.lanes.cbegin(), timeSelection.lanes.cend(), identity) !=
            timeSelection.lanes.cend())
            lanes.push_back(identity);
    }
    return lanes;
}

std::pair<bool, std::vector<std::pair<int, uint8_t>>>
AutomationViewModel::laneSet(EditorAutomationRowId first, EditorAutomationRowId last) const noexcept
{
    const bool firstTempo = first.kind == EditorAutomationRowKind::Tempo;
    const bool lastTempo = last.kind == EditorAutomationRowKind::Tempo;
    const bool firstCc = first.kind == EditorAutomationRowKind::ControlChange;
    const bool lastCc = last.kind == EditorAutomationRowKind::ControlChange;
    std::vector<std::pair<int, uint8_t>> lanes;
    if ((!firstTempo && !firstCc) || (!lastTempo && !lastCc))
        return {false, lanes};

    const auto visible = visibleRows();
    const auto findVisible = [visible](EditorAutomationRowId id) {
        return std::find_if(visible.begin(), visible.end(),
                            [id](const Row &row) { return row.id == id; });
    };
    const auto firstRow = firstCc ? findVisible(first) : visible.end();
    const auto lastRow = lastCc ? findVisible(last) : visible.end();
    if ((firstCc && firstRow == visible.end()) || (lastCc && lastRow == visible.end()))
        return {false, lanes};
    if (firstTempo && lastTempo)
        return {true, lanes};

    const auto firstCcRow = visible.begin() + (visible.empty() ? 0 : 1);
    const auto start = firstTempo || lastTempo ? firstCcRow : std::min(firstRow, lastRow);
    const auto end = firstTempo ? lastRow : lastTempo ? firstRow : std::max(firstRow, lastRow);
    for (auto row = start; row != visible.end(); ++row) {
        if (row->id.kind == EditorAutomationRowKind::ControlChange)
            lanes.emplace_back(int(row->id.track), row->id.controller);
        if (row == end)
            break;
    }
    return {firstTempo || lastTempo, lanes};
}

AutomationViewModel buildAutomationViewModel(const SongDocument &document,
                                             const MidiTimeline *timeline,
                                             const songview::EditorSelectionModel &selection,
                                             bool pageReady)
{
    AutomationViewModel model;
    const auto &timeSelection = selection.timeSelection();
    if (timeSelection.active()) {
        model.activeTickRange = std::pair{std::min(timeSelection.startTick, timeSelection.endTick),
                                          std::max(timeSelection.startTick, timeSelection.endTick)};
    }

    const uint32_t usedTrackMask = songview::detail::usedTrackMask(timeline);
    const bool tempoCoverage = selection.timeSelectionCoversTempo(usedTrackMask);
    const auto &tempoPoints = document.tempoPoints();
    const EditorAutomationRowId tempoId{EditorAutomationRowKind::Tempo, 0, 0};
    model.rows.push_back({tempoId, tempoPoints.size(), tempoCoverage, tempoCoverage,
                          tempoCoverage && anyPointInRange(tempoPoints, model.activeTickRange)});

    const int primaryTrack = selection.primaryTrack();
    if (primaryTrack >= 0 && primaryTrack <= 0xFF) {
        const bool visible = pageReady && timeline != nullptr && primaryTrack >= 0;
        for (const uint8_t controller : CCLanes::supportedControllers()) {
            const EditorAutomationRowId id{EditorAutomationRowKind::ControlChange,
                                           uint8_t(primaryTrack), controller};
            const auto points = document.lanePoints(primaryTrack, controller);
            const bool coversNodes = visible && selection.timeSelectionCoversLane(
                                                    primaryTrack, controller, usedTrackMask);
            const bool coversLane =
                coversNodes &&
                timeSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes;
            model.rows.push_back({id, points.size(), coversLane, coversNodes,
                                  coversNodes && anyPointInRange(points, model.activeTickRange)});
        }
    }

    model.visibleRowCount =
        pageReady && timeline != nullptr && primaryTrack >= 0 ? model.rows.size() : 1;
    return model;
}
