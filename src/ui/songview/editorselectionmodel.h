#pragma once

#include <cstdint>
#include <functional>
#include <span>
#include <utility>
#include <vector>

#include "core/noteid.h"

struct TrackRemap;

namespace songview {

using TrackMask = uint32_t;
inline constexpr uint32_t kTrackMask = (uint32_t{1} << 16) - 1;

class EditorSelectionModel
{
  public:
    struct TimeSelection {
        enum Scope { Tracks, Lanes };

        uint64_t startTick = 0;
        uint64_t endTick = 0;
        Scope scope = Tracks;
        std::vector<std::pair<int, uint8_t>> lanes;
        bool tempo = false;

        bool active() const noexcept { return endTick > startTick; }
    };

    enum class SelectionChange : uint32_t {
        None = 0,
        PrimaryTrack = 1u << 0,
        TrackScope = 1u << 1,
        NoteSelection = 1u << 2,
        TimeSelection = 1u << 3,
    };

    enum class TrackScopeAction { Plain, Toggle, Range };
    using Observer = std::function<void(SelectionChange)>;

    EditorSelectionModel() noexcept = default;

    EditorSelectionModel(const EditorSelectionModel &) = delete;
    EditorSelectionModel &operator=(const EditorSelectionModel &) = delete;
    EditorSelectionModel(EditorSelectionModel &&) noexcept = default;
    EditorSelectionModel &operator=(EditorSelectionModel &&) noexcept = default;

    void setObserver(Observer observer);

    int primaryTrack() const noexcept { return m_primaryTrack; }
    uint32_t storedTrackScope() const noexcept { return m_trackScope; }
    uint32_t resolvedTrackScope(uint32_t usedTrackMask) const noexcept;
    const std::vector<NoteId> &noteSelection() const noexcept { return m_noteSelection; }
    bool isNoteSelected(NoteId noteId) const noexcept;
    const TimeSelection &timeSelection() const noexcept { return m_timeSelection; }
    bool timeSelectionCoversTrack(int track, uint32_t usedTrackMask) const noexcept;
    bool timeSelectionCoversLane(int track, uint8_t controller,
                                 uint32_t usedTrackMask) const noexcept;
    bool timeSelectionCoversTempo(uint32_t usedTrackMask) const noexcept;

    void setNoteSelection(std::vector<NoteId> ids);
    void clearNoteSelection();
    void setTimeSelection(TimeSelection selection);
    void setTimeSelectionAndTrackScope(TimeSelection selection, TrackMask trackScope);
    void clearTimeSelection();
    void setTrackScope(TrackMask trackScope);
    void clearBothSelections();
    void applyPrimaryTrackTransition(int track);
    void applyTrackScopeAdjustment(int clickedTrack, uint32_t usedTrackMask,
                                   TrackScopeAction action);
    void reconcileNoteSelection(std::span<const NoteId> validIds);
    void resetForSongSwap(int firstUsedTrack);
    void applyRemap(const TrackRemap &remap);

  private:
    enum class Phase { Idle, Notifying };

    void notify(SelectionChange changes);
    static bool sameTimeSelection(const TimeSelection &a, const TimeSelection &b) noexcept;
    static TimeSelection sanitizeTimeSelection(TimeSelection selection);
    static int firstTrack(uint32_t mask) noexcept;
    bool isNotifying() const noexcept { return m_phase == Phase::Notifying; }
    void commit(TimeSelection time, TrackMask scope, std::vector<NoteId> notes);

    int m_primaryTrack = 0;
    TrackMask m_trackScope = 1u << 0;
    std::vector<NoteId> m_noteSelection;
    TimeSelection m_timeSelection;
    Observer m_observer;
    Phase m_phase = Phase::Idle;
};

constexpr EditorSelectionModel::SelectionChange
operator|(EditorSelectionModel::SelectionChange a, EditorSelectionModel::SelectionChange b) noexcept
{
    return static_cast<EditorSelectionModel::SelectionChange>(static_cast<uint32_t>(a) |
                                                              static_cast<uint32_t>(b));
}

constexpr EditorSelectionModel::SelectionChange
operator&(EditorSelectionModel::SelectionChange a, EditorSelectionModel::SelectionChange b) noexcept
{
    return static_cast<EditorSelectionModel::SelectionChange>(static_cast<uint32_t>(a) &
                                                              static_cast<uint32_t>(b));
}

constexpr bool hasSelectionChange(EditorSelectionModel::SelectionChange changes,
                                  EditorSelectionModel::SelectionChange category) noexcept
{
    return static_cast<uint32_t>(changes & category) != 0;
}

} // namespace songview
