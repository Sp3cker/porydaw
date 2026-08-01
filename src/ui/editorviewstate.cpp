#include "ui/editorviewstate.h"

#include <algorithm>
#include <utility>

bool EditorViewState::hideLane(EditorAutomationRowId lane)
{
    if (isLaneHidden(lane))
        return false;
    m_hiddenLanes.push_back(lane);
    return true;
}

bool EditorViewState::unhideLane(const EditorAutomationRowId &lane)
{
    const auto it = std::find(m_hiddenLanes.begin(), m_hiddenLanes.end(), lane);
    if (it == m_hiddenLanes.end())
        return false;
    m_hiddenLanes.erase(it);
    return true;
}

bool EditorViewState::isLaneHidden(const EditorAutomationRowId &lane) const noexcept
{
    return std::find(m_hiddenLanes.begin(), m_hiddenLanes.end(), lane) != m_hiddenLanes.end();
}

bool EditorViewState::remapEngineTracks(const QVector<int> &engineTrackMap)
{
    std::set<int> mappedTracks;
    for (const int destination : engineTrackMap) {
        if (destination >= 0 && !mappedTracks.insert(destination).second)
            return false;
    }

    const auto remapRow = [&engineTrackMap](EditorAutomationRowId row,
                                            EditorAutomationRowId *mapped) {
        if (row.kind == EditorAutomationRowKind::Tempo) {
            *mapped = row;
            return true;
        }
        const int source = int(row.track);
        if (source >= int(engineTrackMap.size()))
            return false;
        const int destination = engineTrackMap[source];
        if (destination < 0)
            return false;
        row.track = uint8_t(destination);
        *mapped = row;
        return true;
    };

    auto remapped = *this;
    remapped.laneHeights.clear();
    remapped.laneRanges.clear();
    remapped.emptyLanes.clear();
    remapped.m_hiddenLanes.clear();
    remapped.m_hiddenLanes.reserve(m_hiddenLanes.size());

    for (const auto &[row, height] : laneHeights) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.laneHeights.emplace(destination, height);
    }
    for (const auto &[row, range] : laneRanges) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.laneRanges.emplace(destination, range);
    }
    for (const auto &row : emptyLanes) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.emptyLanes.insert(destination);
    }
    for (const auto &row : m_hiddenLanes) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.hideLane(destination);
    }

    *this = std::move(remapped);
    return true;
}

bool EditorViewState::operator==(const EditorViewState &other) const noexcept
{
    return drawerVisible == other.drawerVisible && drawerPage == other.drawerPage &&
           drawerHeight == other.drawerHeight && laneHeight == other.laneHeight &&
           laneHeights == other.laneHeights && laneRanges == other.laneRanges &&
           emptyLanes == other.emptyLanes && m_hiddenLanes == other.m_hiddenLanes;
}

bool EditorViewState::operator!=(const EditorViewState &other) const noexcept
{
    return !(*this == other);
}
