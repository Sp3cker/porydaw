#include "ui/editordrawer/laneselection.h"

#include <algorithm>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editorviewstate.h"
#include "ui/songview/editorselectionmodel.h"

LaneSelection::LaneSelection(const songview::EditorSelectionModel &model,
                             const std::vector<AutomationRow> &rows,
                             uint32_t usedTrackMask) noexcept
    : m_model(model)
    , m_rows(rows)
    , m_usedTrackMask(usedTrackMask)
{}
void LaneSelection::setUsedTrackMask(uint32_t usedTrackMask) noexcept
{
    m_usedTrackMask = usedTrackMask;
}

bool LaneSelection::active() const noexcept
{
    return m_model.timeSelection().active();
}

std::optional<std::pair<uint64_t, uint64_t>> LaneSelection::activeTickRange() const noexcept
{
    if (!active())
        return std::nullopt;
    const auto &selection = m_model.timeSelection();
    return std::pair{std::min(selection.startTick, selection.endTick),
                     std::max(selection.startTick, selection.endTick)};
}

bool LaneSelection::coversLane(EditorAutomationRowId id) const noexcept
{
    return covers(id, true);
}

bool LaneSelection::coversNodes(EditorAutomationRowId id) const noexcept
{
    return covers(id, false);
}

bool LaneSelection::covers(EditorAutomationRowId id, bool laneScoped) const noexcept
{
    if (!active())
        return false;
    switch (id.kind) {
    case EditorAutomationRowKind::Tempo:
        return m_model.timeSelectionCoversTempo(m_usedTrackMask);
    case EditorAutomationRowKind::ControlChange:
        if (laneScoped &&
            m_model.timeSelection().scope != songview::EditorSelectionModel::TimeSelection::Lanes)
            return false;
        if (findRowById(id) == m_rows.cend())
            return false;
        return m_model.timeSelectionCoversLane(int(id.track), id.controller, m_usedTrackMask);
    }
    return false;
}

std::vector<AutomationRow>::const_iterator
LaneSelection::findRowById(EditorAutomationRowId id) const noexcept
{
    return std::find_if(m_rows.cbegin(), m_rows.cend(),
                        [id](const AutomationRow &row) { return row.id == id; });
}

bool LaneSelection::hitTest(EditorAutomationRowId id, qreal x,
                            const AutomationProjection &projection, qreal dpr) const noexcept
{
    if (!coversLane(id))
        return false;
    const auto &selection = m_model.timeSelection();
    // Sanitize does not reorder ticks, so the endpoint order is an explicit
    // min/max here, not an assumption about selection ordering.
    const qreal startX = projection.displayX(selection.startTick, dpr);
    const qreal endX = projection.displayX(selection.endTick, dpr);
    return x >= std::min(startX, endX) && x < std::max(startX, endX);
}

std::vector<std::pair<int, uint8_t>> LaneSelection::visibleLanes() const noexcept
{
    std::vector<std::pair<int, uint8_t>> lanes;
    if (!active())
        return lanes;
    const auto &selection = m_model.timeSelection();
    for (const AutomationRow &row : m_rows) {
        const auto identity = std::pair{int(row.id.track), row.id.controller};
        if (std::find(selection.lanes.cbegin(), selection.lanes.cend(), identity) !=
            selection.lanes.cend())
            lanes.push_back(identity);
    }
    return lanes;
}

std::pair<bool, std::vector<std::pair<int, uint8_t>>>
LaneSelection::laneSet(EditorAutomationRowId first, EditorAutomationRowId last) const noexcept
{
    const bool firstTempo = first.kind == EditorAutomationRowKind::Tempo;
    const bool lastTempo = last.kind == EditorAutomationRowKind::Tempo;
    const bool firstCc = first.kind == EditorAutomationRowKind::ControlChange;
    const bool lastCc = last.kind == EditorAutomationRowKind::ControlChange;
    std::vector<std::pair<int, uint8_t>> lanes;
    if ((!firstTempo && !firstCc) || (!lastTempo && !lastCc))
        return {false, lanes};
    const auto firstRow = firstCc ? findRowById(first) : m_rows.cend();
    const auto lastRow = lastCc ? findRowById(last) : m_rows.cend();
    if ((firstCc && firstRow == m_rows.cend()) || (lastCc && lastRow == m_rows.cend()))
        return {false, lanes};
    if (firstTempo && lastTempo)
        return {true, lanes};

    const auto start = firstTempo || lastTempo ? m_rows.cbegin() : std::min(firstRow, lastRow);
    const auto end = firstTempo ? lastRow : lastTempo ? firstRow : std::max(firstRow, lastRow);
    for (auto row = start; row != m_rows.cend(); ++row) {
        lanes.emplace_back(int(row->id.track), row->id.controller);
        if (row == end)
            break;
    }
    return {firstTempo || lastTempo, lanes};
}