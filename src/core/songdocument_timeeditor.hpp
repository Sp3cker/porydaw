#pragma once

#include <compare>
#include <set>
#include <vector>

#include "songdocument.h"

class SongDocument::TimeEditor
{
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
    struct XcmdEventRecord {
        int smfTrack = -1;
        size_t eventIndex = 0; // source event this byte came from
        uint64_t newTick = 0;
        size_t opIndex = 0;
        uint8_t channel = 0; // MIDI channel of the relocated source event
        bool isCopy = false; // source kept (duplicate) vs. moved (removed)
    };
    static bool metaIsTimeSig(const SmfEvent &event);
    static StreamIdentity channelStream(int smfTrack, const SmfEvent &event);
    std::optional<uint8_t> laneForEvent(int smfTrack, size_t index, const SmfEvent &event) const;
    // The lane controller a known XCMD point payload projects onto
    // (std::nullopt when the byte is not a known point payload, lies outside
    // the edit's scope, or the whole track is covered). XCMD payload bytes
    // share CC numbers across lanes (selector/alternate glue), so stream
    // grouping must use the logical lane, not the raw controller.
    std::optional<uint8_t> logicalXcmdLane(int smfTrack, size_t index) const;
    bool eventCovered(int smfTrack, size_t index, int engineTrack, const SmfEvent &event) const;
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
                            uint64_t tick, MoveMode mode,
                            std::vector<XcmdEventRecord> &records) const;
    std::vector<SongDocument::EditOp> timeEditCloseGapTrackEnds() const;
    std::vector<SongDocument::EditOp>
    timeEditShiftRightTrackEnds(const std::vector<bool> &affectedTracks,
                                const std::vector<SongDocument::EditOp> &inserts,
                                uint64_t threshold) const;
    // Per-track XCMD reconciliation (see songdocument_timeeditor_xcmd.cpp):
    // plans consumed-byte removals/relocations through xcmd::reconcileRaw,
    // translates each patch via the document's adapter, and assembles with
    // the generic ops. Returns nullopt when a raw edit is unrepresentable —
    // the caller then fails without mutating.
    std::optional<std::vector<SongDocument::EditOp>>
    xcmdAssembleOps(std::vector<std::vector<size_t>> removals,
                    std::vector<SongDocument::EditOp> inserts,
                    std::vector<SongDocument::EditOp> trackEnds,
                    const std::vector<XcmdEventRecord> &records) const;
    // Records a moved or duplicated consumed XCMD byte so xcmdAssembleOps can
    // re-plan it: the generic insert it names (opIndex) is suppressed and the
    // byte handled by the deep planner instead. Operation-local: records is
    // the per-edit vector threaded through the pass.
    void recordXcmdRelocation(int smfTrack, size_t eventIndex, uint64_t newTick, size_t opIndex,
                              bool isCopy, std::vector<XcmdEventRecord> &records) const;
    // True when a stream point may act as the remove-seam value keeper.
    // Consumed XCMD bytes are never eligible: their epochs are rebuilt
    // canonically or removed by the plan, so keeping one as the seam state
    // would leave a stale protocol byte.
    bool isSeamKeeperEligible(const TimeEventRef &ref) const;
    // True when the byte is consumed by the XCMD protocol (selector glue,
    // known point payloads, opaque epoch members) — the events
    // xcmdAssembleOps must reconcile through the planner rather than treat
    // as raw events. Value streams can never keep such a byte as their
    // remove-seam winner: its epoch is rebuilt or removed by the plan.
    bool isXcmdConsumed(int smfTrack, size_t index) const;
    // Builds the per-track projection memo for smfTrack on first access.
    // The memo is const over immutable document bytes (the edit's own event
    // snapshot), so the lazy fill is constness-honest.
    void xcmdTrackIndex(int smfTrack) const;
    // Event index -> known LANE controller of the projecting point payload
    // (std::nullopt otherwise: selector glue and opaque bytes are not
    // lane-owned). Built per track on first access via xcmdTrackIndex.
    mutable std::vector<std::vector<std::optional<uint8_t>>> m_xcmdLaneByEvent;
    // Event index -> protocol-consumed (1) or plain (0). Built per track on
    // first access via xcmdTrackIndex.
    mutable std::vector<std::vector<uint8_t>> m_xcmdConsumedOfEvent;

    SongDocument &m_document;
    SongDocument::TimeRange m_range;
    SongDocument::TimeScope m_scope;
    std::set<int> m_trackScope;
    std::set<LaneIdentity> m_laneScope;
};