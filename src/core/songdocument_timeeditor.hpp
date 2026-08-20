#pragma once

#include <compare>
#include <set>

#include "songdocument.h"

class SongDocument::TimeEditor {
  public:
    TimeEditor(SongDocument &document, const SongDocument::TimeRange &range,
               const SongDocument::TimeScope &scope);
    bool remove();
    bool insertBlank();
    bool duplicate();

  private:
    enum class EventKind { Note, ChannelState, TimeSig, Other };
    enum class MoveMode { SkipUnchanged, MoveEvenIfUnchanged };
    enum class StreamKind { TimeSig, Channel };
    struct LaneIdentity {
        int engineTrack = -1;
        uint8_t cc = 0;
        auto operator<=>(const LaneIdentity &) const = default;
    };
    struct StreamIdentity {
        StreamKind kind = StreamKind::Channel;
        int smfTrack = -1;
        uint8_t status = 0;
        uint8_t data0 = 0;
        auto operator<=>(const StreamIdentity &) const = default;
    };
    struct TimeEventRef {
        int smfTrack = -1;
        size_t index = 0;
        uint64_t tick = 0;
        StreamIdentity stream;
        EventKind kind = EventKind::Other;
    };
    struct TimeEditPlan {
        std::vector<TimeEventRef> events;
        std::vector<DocNote> notes;
        std::vector<std::vector<bool>> selected;
    };
    static bool metaIsTimeSig(const SmfEvent &event);
    static StreamIdentity channelStream(int smfTrack, const SmfEvent &event);
    std::optional<uint8_t> laneForEvent(const SmfEvent &event) const;
    bool eventCovered(int smfTrack, int engineTrack, const SmfEvent &event) const;
    TimeEditPlan buildTimeEditPlan() const;
    std::vector<std::vector<const TimeEventRef *>> timeEditStreams(const TimeEditPlan &plan) const;
    std::vector<bool> timeEditAffectedSmfTracks() const;
    std::vector<std::vector<bool>> makeTimeEditTaken() const;
    static bool consumeTimeEditEvent(std::vector<std::vector<bool>> &taken, int smfTrack,
                                     size_t index);
    static void appendTimeEditInsert(std::vector<SongDocument::EditOp> &inserts, int smfTrack,
                                     const SmfEvent &source, uint64_t tick, bool preserveNoteId);
    void appendTimeEditRemove(std::vector<std::vector<size_t>> &removals,
                              std::vector<std::vector<bool>> &taken, int smfTrack,
                              size_t index) const;
    bool appendTimeEditMove(std::vector<std::vector<size_t>> &removals,
                            std::vector<SongDocument::EditOp> &inserts,
                            std::vector<std::vector<bool>> &taken, int smfTrack, size_t index,
                            uint64_t tick, MoveMode mode) const;
    std::vector<SongDocument::EditOp> timeEditCloseGapTrackEnds() const;
    std::vector<SongDocument::EditOp>
    timeEditShiftRightTrackEnds(const std::vector<bool> &affectedTracks,
                                const std::vector<SongDocument::EditOp> &inserts,
                                uint64_t threshold) const;
    std::vector<SongDocument::EditOp>
    assembleTimeEditOps(std::vector<std::vector<size_t>> removals,
                        std::vector<SongDocument::EditOp> inserts,
                        std::vector<SongDocument::EditOp> trackEnds) const;

    SongDocument &m_document;
    SongDocument::TimeRange m_range;
    SongDocument::TimeScope m_scope;
    std::set<int> m_trackScope;
    std::set<LaneIdentity> m_laneScope;
};
