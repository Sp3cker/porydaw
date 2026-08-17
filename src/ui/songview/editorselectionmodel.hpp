#pragma once

#include <cstdint>
#include <functional>
#include <utility>
#include <vector>

#include "core/noteid.h"

struct TrackRemap;

namespace songview {

struct TimeSelection {
    enum Scope { Tracks, Lanes };

    uint64_t startTick = 0;
    uint64_t endTick = 0;
    Scope scope = Tracks;
    std::vector<std::pair<int, uint8_t>> lanes;

    bool active() const noexcept { return endTick > startTick; }
};

enum class TrackScopeAction { Plain, Toggle, Range };

class EditorSelectionModel
{
  public:
    enum class Change : uint8_t {
        None = 0,
        PrimaryTrack = 1u << 0,
        TrackScope = 1u << 1,
        NoteSelection = 1u << 2,
        TimeSelection = 1u << 3,
    };
    using ChangeCallback = std::function<void(Change)>;

    EditorSelectionModel() noexcept = default;
    explicit EditorSelectionModel(ChangeCallback callback);

    EditorSelectionModel(const EditorSelectionModel &) = delete;
    EditorSelectionModel &operator=(const EditorSelectionModel &) = delete;
    EditorSelectionModel(EditorSelectionModel &&) noexcept = default;
    EditorSelectionModel &operator=(EditorSelectionModel &&) noexcept = default;

    void setChangeCallback(ChangeCallback callback);
    void setNoteSelection(std::vector<NoteId> ids);
    void clearNoteSelection();
    void setTimeSelection(TimeSelection selection);
    void clearTimeSelection();
    void clearSelections();
    void transitionPrimaryTrack(int track);
    void adjustTrackScope(int clickedTrack, uint32_t usedTrackMask, TrackScopeAction action);
    void reconcileNoteSelection(const std::vector<NoteId> &validIds);
    void resetForSong(uint32_t usedTrackMask);
    void clearNoteSelectionForDocument();
    void applyTrackRemap(const TrackRemap &remap);

    int primaryTrack() const noexcept { return m_primaryTrack; }
    uint32_t storedTrackScope() const noexcept { return m_trackScope; }
    uint32_t resolvedTrackScope(uint32_t usedTrackMask) const noexcept;
    const std::vector<NoteId> &noteSelection() const noexcept { return m_noteSelection; }
    bool isNoteSelected(NoteId noteId) const noexcept;
    const TimeSelection &timeSelection() const noexcept { return m_timeSelection; }
    bool timeSelectionCoversTrack(int track, uint32_t usedTrackMask) const noexcept;
    bool timeSelectionCoversLane(int track, uint8_t controller,
                                 uint32_t usedTrackMask) const noexcept;

  private:
    static constexpr uint32_t kTrackMask = (uint32_t{1} << 16) - 1;

    void notify(Change changes);
    bool canMutate() const noexcept;
    static bool sameTimeSelection(const TimeSelection &a, const TimeSelection &b) noexcept;
    static TimeSelection sanitizeTimeSelection(TimeSelection selection);
    static int firstTrack(uint32_t mask) noexcept;

    int m_primaryTrack = 0;
    uint32_t m_trackScope = 1u;
    std::vector<NoteId> m_noteSelection;
    TimeSelection m_timeSelection;
    ChangeCallback m_changeCallback;
    bool m_notifying = false;
};

constexpr EditorSelectionModel::Change operator|(EditorSelectionModel::Change a,
                                                 EditorSelectionModel::Change b) noexcept
{
    return static_cast<EditorSelectionModel::Change>(static_cast<uint8_t>(a) |
                                                     static_cast<uint8_t>(b));
}

constexpr EditorSelectionModel::Change operator&(EditorSelectionModel::Change a,
                                                 EditorSelectionModel::Change b) noexcept
{
    return static_cast<EditorSelectionModel::Change>(static_cast<uint8_t>(a) &
                                                     static_cast<uint8_t>(b));
}

constexpr bool hasChange(EditorSelectionModel::Change changes,
                         EditorSelectionModel::Change category) noexcept
{
    return static_cast<uint8_t>(changes & category) != 0;
}

} // namespace songview
