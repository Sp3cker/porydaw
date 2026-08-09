#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <vector>

// This value selects the active drawer page. Page instances keep transient
// runtime data independently.
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

// Value-only drawer chrome. MainWindow persists this application-wide; runtime
// pointers and transient interaction data stay in the concrete editor pages.
struct DrawerSectionState {
    bool visible = true;
    std::optional<int> height; // nullopt uses layout default.

    int effectiveHeight(int fallback) const { return height.value_or(fallback); }

    bool operator==(const DrawerSectionState &other) const noexcept;
    bool operator!=(const DrawerSectionState &other) const noexcept;
};

struct EditorDrawerState {
    DrawerSectionState velocity{false, std::nullopt};
    DrawerSectionState automation{true, std::nullopt};
    EditorDrawerPage activePage = EditorDrawerPage::Automations;

    bool operator==(const EditorDrawerState &other) const noexcept;
    bool operator!=(const EditorDrawerState &other) const noexcept;
};

struct EditorViewState {
    DrawerSectionState velocity{false, std::nullopt};
    DrawerSectionState automation{true, std::nullopt};
    EditorDrawerPage activePage = EditorDrawerPage::Automations;
    int laneHeight = 0; // A value of 0 uses the default lane height.
    std::map<EditorAutomationRowId, int> laneHeights;
    std::map<EditorAutomationRowId, uint8_t> laneRanges;
    std::set<EditorAutomationRowId> emptyLanes;

    EditorDrawerState drawerState() const noexcept;
    void setDrawerState(const EditorDrawerState &state) noexcept;

    // hideLane() appends new lane IDs and rejects duplicates. hiddenLanes() gives
    // the lane IDs in the sequence added by hideLane().
    bool hideLane(EditorAutomationRowId lane);
    bool unhideLane(const EditorAutomationRowId &lane);
    bool isLaneHidden(const EditorAutomationRowId &lane) const noexcept;
    // Remap automation rows owned by engine tracks. Tempo rows remain fixed;
    // duplicate destinations reject the whole operation without mutation.
    bool remapEngineTracks(const std::vector<int> &engineTrackMap);

    const std::vector<EditorAutomationRowId> &hiddenLanes() const noexcept { return m_hiddenLanes; }

    bool operator==(const EditorViewState &other) const noexcept;
    bool operator!=(const EditorViewState &other) const noexcept;

  private:
    std::vector<EditorAutomationRowId> m_hiddenLanes;
};
