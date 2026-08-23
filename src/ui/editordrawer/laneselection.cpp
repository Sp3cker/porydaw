#include "ui/editordrawer/laneselection.h"

#include <algorithm>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editorviewstate.h"
#include "ui/songview/editorselectionmodel.h"

LaneSelection::LaneSelection(const songview::EditorSelectionModel &model,
                             const std::vector<AutomationRow> &rows,
                             uint32_t usedTrackMask) noexcept
    : m_model(&model)
    , m_rows(&rows)
    , m_usedTrackMask(usedTrackMask)
{}

bool LaneSelection::active() const noexcept
{
    return m_model != nullptr && m_model->timeSelection().active();
}

bool LaneSelection::covers(LaneHandle handle) const noexcept
{
    if (!active() || !handle.valid())
        return false;
    if (handle.index == 0)
        return m_model->timeSelectionCoversTempo(m_usedTrackMask);
    const int rowIndex = handle.index - 1;
    if (m_rows == nullptr || rowIndex >= int(m_rows->size()))
        return false;
    const AutomationRow &row = (*m_rows)[std::size_t(rowIndex)];
    const auto identity = std::pair{int(row.id.track), row.id.controller};
    return m_model->timeSelection().scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
           m_model->timeSelectionCoversLane(identity.first, identity.second, m_usedTrackMask);
}

bool LaneSelection::hitTest(LaneHandle handle, qreal x, const AutomationProjection &projection,
                            qreal dpr) const noexcept
{
    if (!covers(handle) || m_model == nullptr)
        return false;
    const auto &selection = m_model->timeSelection();
    // Sanitize does not reorder ticks, so the endpoint order is an explicit
    // min/max here, not an assumption about selection ordering.
    const qreal startX = projection.displayX(selection.startTick, dpr);
    const qreal endX = projection.displayX(selection.endTick, dpr);
    return x >= std::min(startX, endX) && x < std::max(startX, endX);
}

std::vector<std::pair<int, uint8_t>> LaneSelection::visibleLanes() const noexcept
{
    std::vector<std::pair<int, uint8_t>> lanes;
    if (!active() || m_rows == nullptr)
        return lanes;
    const auto &selection = m_model->timeSelection();
    for (const AutomationRow &row : *m_rows) {
        const auto identity = std::pair{int(row.id.track), row.id.controller};
        if (std::find(selection.lanes.cbegin(), selection.lanes.cend(), identity) !=
            selection.lanes.cend())
            lanes.push_back(identity);
    }
    return lanes;
}

std::pair<bool, std::vector<std::pair<int, uint8_t>>>
LaneSelection::laneSet(LaneHandle first, LaneHandle last) const noexcept
{
    bool tempo = false;
    std::vector<std::pair<int, uint8_t>> lanes;
    if (m_rows == nullptr || !first.valid() || !last.valid())
        return {tempo, lanes};
    const int firstIndex = std::min(first.index, last.index);
    const int lastIndex = std::max(first.index, last.index);
    for (int index = firstIndex; index <= lastIndex && index < int(m_rows->size()) + 1; ++index) {
        if (index == 0) {
            tempo = true;
            continue;
        }
        const AutomationRow &row = (*m_rows)[std::size_t(index - 1)];
        lanes.push_back({int(row.id.track), row.id.controller});
    }
    return {tempo, lanes};
}