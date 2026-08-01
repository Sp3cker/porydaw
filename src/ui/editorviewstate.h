#pragma once

#include <QVector>

#include <cstdint>
#include <map>
#include <set>
#include <vector>

// This value selects the drawer page stored with one song. Page instances keep
// transient runtime data independently.
enum class EditorDrawerPage : uint8_t {
    Automations,
    Velocity,
};

enum class EditorAutomationRowKind : uint8_t {
    Tempo,
    Voice,
    ControlChange,
};

// This value identifies one automation lane in saved data. It contains only
// value fields; it does not include a page, document, or voice pointer.
struct EditorAutomationRowId {
    EditorAutomationRowKind kind = EditorAutomationRowKind::Tempo;
    uint8_t track = 0;
    uint8_t controller = 0;

    bool operator==(const EditorAutomationRowId &other) const noexcept
    {
        return kind == other.kind && track == other.track && controller == other.controller;
    }

    bool operator!=(const EditorAutomationRowId &other) const noexcept { return !(*this == other); }

    bool operator<(const EditorAutomationRowId &other) const noexcept
    {
        if (kind != other.kind)
            return kind < other.kind;
        if (track != other.track)
            return track < other.track;
        return controller < other.controller;
    }
};

// This sidecar contains value-only view data with the song. Runtime pointers and
// transient interaction data stay in the concrete editor pages,
// so runtime object changes do not invalidate the saved data.
struct EditorViewState {
    bool drawerVisible = true;
    EditorDrawerPage drawerPage = EditorDrawerPage::Automations;
    int drawerHeight = 0; // A value of 0 uses the drawer's layout default.
    int laneHeight = 0;   // A value of 0 uses the default lane height.
    std::map<EditorAutomationRowId, int> laneHeights;
    std::map<EditorAutomationRowId, uint8_t> laneRanges;
    std::set<EditorAutomationRowId> emptyLanes;

    // hideLane() appends new lane IDs and rejects duplicates. hiddenLanes() gives
    // the lane IDs in the sequence added by hideLane().
    bool hideLane(EditorAutomationRowId lane);
    bool unhideLane(const EditorAutomationRowId &lane);
    bool isLaneHidden(const EditorAutomationRowId &lane) const noexcept;
    // Remap automation rows owned by engine tracks. Tempo rows remain fixed;
    // duplicate destinations reject the whole operation without mutation.
    bool remapEngineTracks(const QVector<int> &engineTrackMap);

    const std::vector<EditorAutomationRowId> &hiddenLanes() const noexcept
    {
        return m_hiddenLanes;
    }

    bool operator==(const EditorViewState &other) const noexcept;
    bool operator!=(const EditorViewState &other) const noexcept;

  private:
    std::vector<EditorAutomationRowId> m_hiddenLanes;
};
