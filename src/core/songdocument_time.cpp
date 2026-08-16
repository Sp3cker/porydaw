#include "songdocument.h"

#include <algorithm>
#include <map>
#include <set>
#include <utility>

#include "core/timedefaults.h"

class SongDocument::TimeEditor
{
  public:
    TimeEditor(SongDocument &document, const SongDocument::TimeRange &range,
               const SongDocument::TimeScope &scope)
        : m_document(document)
        , m_range(range)
        , m_scope(scope)
    {
        for (int track : m_scope.tracks)
            m_trackScope.insert(track);
        for (const auto &lane : m_scope.lanes) {
            m_laneScope.insert({lane.first, lane.second});
            if (lane.second == DOC_CC_TEMPO && lane.first < 0)
                m_tempoLaneScope = true;
        }
    }

    bool rippleDelete();
    bool insertBlank();
    bool duplicate();

  private:
    enum class EventKind {
        Note,
        ChannelState,
        Tempo,
        TimeSig,
        Other,
    };
    enum class MoveMode {
        SkipUnchanged,
        MoveEvenIfUnchanged,
    };
    enum class TrackEndMode {
        ShiftRight,
        RippleLeft,
    };
    enum class StreamKind {
        Tempo,
        TimeSig,
        Channel,
    };

    struct LaneIdentity {
        int engineTrack = -1;
        uint8_t cc = 0;

        bool operator<(const LaneIdentity &other) const
        {
            if (engineTrack != other.engineTrack)
                return engineTrack < other.engineTrack;
            return cc < other.cc;
        }
    };
    struct StreamIdentity {
        StreamKind kind = StreamKind::Channel;
        int smfTrack = -1;
        uint8_t status = 0;
        uint8_t data0 = 0;

        bool operator<(const StreamIdentity &other) const
        {
            if (kind != other.kind)
                return static_cast<int>(kind) < static_cast<int>(other.kind);
            if (smfTrack != other.smfTrack)
                return smfTrack < other.smfTrack;
            if (status != other.status)
                return status < other.status;
            return data0 < other.data0;
        }
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

    static bool metaIsTimeSig(const SmfEvent &event)
    {
        return event.isMeta() && event.metaType == 0x58 && event.blob.size() >= 2;
    }

    static StreamIdentity channelStream(int smfTrack, const SmfEvent &event)
    {
        const uint8_t type = event.typeNibble();
        return {StreamKind::Channel, smfTrack, event.status,
                (type == 0xA || type == 0xB) ? event.data0 : uint8_t{0}};
    }

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
    std::vector<SongDocument::EditOp>
    timeEditTrackEnds(const SongDocument::TimeRange &range, const std::vector<bool> &affectedTracks,
                      const std::vector<SongDocument::EditOp> &inserts, TrackEndMode mode,
                      uint64_t threshold) const;
    std::vector<SongDocument::EditOp>
    assembleTimeEditOps(std::vector<std::vector<size_t>> removals,
                        std::vector<SongDocument::EditOp> inserts,
                        std::vector<SongDocument::EditOp> trackEnds) const;

    SongDocument &m_document;
    SongDocument::TimeRange m_range;
    SongDocument::TimeScope m_scope;
    std::set<int> m_trackScope;
    bool m_tempoLaneScope = false;
    std::set<LaneIdentity> m_laneScope;
};

std::optional<uint8_t> SongDocument::TimeEditor::laneForEvent(const SmfEvent &event) const
{
    if (event.isChannel()) {
        switch (event.typeNibble()) {
        case 0xB:
            return event.data0;
        case 0xC:
            return DOC_CC_VOICE;
        case 0xE:
            return DOC_CC_BEND;
        default:
            return std::nullopt;
        }
    }
    if (event.isMeta() && event.metaType == 0x51 && event.blob.size() == 3)
        return DOC_CC_TEMPO;
    return std::nullopt;
}

bool SongDocument::TimeEditor::eventCovered(int smfTrack, int engineTrack,
                                            const SmfEvent &event) const
{
    if (m_scope.wholeSong)
        return !event.isChannel() || engineTrack >= 0;
    const bool trackCovered =
        engineTrack >= 0 && m_trackScope.find(engineTrack) != m_trackScope.end();
    if (event.isChannel() && trackCovered)
        return true;

    const auto lane = laneForEvent(event);
    if (!lane)
        return false;
    if (*lane == DOC_CC_TEMPO)
        return smfTrack == 0 && m_tempoLaneScope;
    return engineTrack >= 0 &&
           m_laneScope.find(LaneIdentity{engineTrack, *lane}) != m_laneScope.end();
}

std::vector<bool> SongDocument::TimeEditor::timeEditAffectedSmfTracks() const
{
    std::vector<bool> affected(m_document.m_smf.tracks.size(), false);
    if (m_scope.wholeSong) {
        std::fill(affected.begin(), affected.end(), true);
        return affected;
    }
    for (int engineTrack : m_scope.tracks) {
        const int smfTrack = m_document.smfTrackFor(engineTrack);
        if (smfTrack >= 0)
            affected[size_t(smfTrack)] = true;
    }
    for (const LaneIdentity &lane : m_laneScope) {
        int smfTrack = -1;
        if (lane.cc == DOC_CC_TEMPO) {
            if (lane.engineTrack < 0)
                smfTrack = 0;
        } else if (lane.engineTrack >= 0 && lane.engineTrack < m_document.engineTrackCount() &&
                   (lane.cc <= 0x7F || lane.cc == DOC_CC_BEND || lane.cc == DOC_CC_VOICE)) {
            smfTrack = m_document.smfTrackFor(lane.engineTrack);
        }
        if (smfTrack >= 0)
            affected[size_t(smfTrack)] = true;
    }
    return affected;
}

std::vector<std::vector<bool>> SongDocument::TimeEditor::makeTimeEditTaken() const
{
    std::vector<std::vector<bool>> taken(m_document.m_smf.tracks.size());
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++)
        taken[t].assign(m_document.m_smf.tracks[t].events.size(), false);
    return taken;
}

bool SongDocument::TimeEditor::consumeTimeEditEvent(std::vector<std::vector<bool>> &taken,
                                                    int smfTrack, size_t index)
{
    if (smfTrack < 0 || smfTrack >= int(taken.size()) || index >= taken[size_t(smfTrack)].size() ||
        taken[size_t(smfTrack)][index])
        return false;
    taken[size_t(smfTrack)][index] = true;
    return true;
}

void SongDocument::TimeEditor::appendTimeEditInsert(std::vector<SongDocument::EditOp> &inserts,
                                                    int smfTrack, const SmfEvent &source,
                                                    uint64_t tick, bool preserveNoteId)
{
    SongDocument::EditOp op;
    op.type = SongDocument::EditOp::InsertEvent;
    op.smfTrack = smfTrack;
    op.event = source;
    op.event.tick = tick;
    op.preservesNoteId = preserveNoteId && op.event.isNoteOn();
    inserts.push_back(std::move(op));
}

void SongDocument::TimeEditor::appendTimeEditRemove(std::vector<std::vector<size_t>> &removals,
                                                    std::vector<std::vector<bool>> &taken,
                                                    int smfTrack, size_t index) const
{
    if (consumeTimeEditEvent(taken, smfTrack, index))
        removals[size_t(smfTrack)].push_back(index);
}

bool SongDocument::TimeEditor::appendTimeEditMove(std::vector<std::vector<size_t>> &removals,
                                                  std::vector<SongDocument::EditOp> &inserts,
                                                  std::vector<std::vector<bool>> &taken,
                                                  int smfTrack, size_t index, uint64_t tick,
                                                  MoveMode mode) const
{
    if (!consumeTimeEditEvent(taken, smfTrack, index))
        return false;
    const SmfEvent &event = m_document.m_smf.tracks[size_t(smfTrack)].events[index];
    if (mode == MoveMode::SkipUnchanged && event.tick == tick)
        return true;
    removals[size_t(smfTrack)].push_back(index);
    appendTimeEditInsert(inserts, smfTrack, event, tick, event.isNoteOn());
    return true;
}

std::vector<SongDocument::EditOp> SongDocument::TimeEditor::timeEditTrackEnds(
    const SongDocument::TimeRange &range, const std::vector<bool> &affectedTracks,
    const std::vector<SongDocument::EditOp> &inserts, TrackEndMode mode, uint64_t threshold) const
{
    if (mode == TrackEndMode::RippleLeft && !m_scope.wholeSong)
        return {};

    std::vector<SongDocument::EditOp> trackEnds;
    const uint64_t span = range.span();
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++) {
        const uint64_t end = m_document.m_smf.tracks[t].endTick;
        uint64_t newEnd = end;
        if (mode == TrackEndMode::ShiftRight) {
            if (affectedTracks[t] && end >= threshold)
                newEnd = end + span;
            for (const SongDocument::EditOp &insert : inserts) {
                if (insert.smfTrack == int(t))
                    newEnd = std::max(newEnd, insert.event.tick);
            }
        } else {
            newEnd =
                end >= range.endTick ? end - span : (end > range.startTick ? range.startTick : end);
        }
        if (newEnd == end)
            continue;
        SongDocument::EditOp op;
        op.type = SongDocument::EditOp::SetTrackEnd;
        op.smfTrack = int(t);
        op.event.tick = newEnd;
        trackEnds.push_back(op);
    }
    return trackEnds;
}

std::vector<SongDocument::EditOp>
SongDocument::TimeEditor::assembleTimeEditOps(std::vector<std::vector<size_t>> removals,
                                              std::vector<SongDocument::EditOp> inserts,
                                              std::vector<SongDocument::EditOp> trackEnds) const
{
    std::vector<SongDocument::EditOp> ops;
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++)
        m_document.appendRemoveOps(ops, int(t), std::move(removals[t]));
    ops.insert(ops.end(), inserts.begin(), inserts.end());
    ops.insert(ops.end(), trackEnds.begin(), trackEnds.end());
    return ops;
}

SongDocument::TimeEditor::TimeEditPlan SongDocument::TimeEditor::buildTimeEditPlan() const
{
    TimeEditPlan plan;
    plan.selected.resize(m_document.m_smf.tracks.size());
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++) {
        const int engineTrack = m_document.engineTrackForChunk(int(t));
        const auto &events = m_document.m_smf.tracks[t].events;
        plan.selected[t].assign(events.size(), false);
        for (size_t i = 0; i < events.size(); i++) {
            const SmfEvent &event = events[i];
            if (!eventCovered(int(t), engineTrack, event))
                continue;
            plan.selected[t][i] = true;
            TimeEventRef ref;
            ref.smfTrack = int(t);
            ref.index = i;
            ref.tick = event.tick;
            if (event.isChannel()) {
                if (event.isNoteOn() || event.isNoteEnd()) {
                    ref.kind = EventKind::Note;
                } else {
                    ref.kind = EventKind::ChannelState;
                    ref.stream = channelStream(int(t), event);
                }
            } else if (event.isMeta() && event.metaType == 0x51 && event.blob.size() == 3) {
                ref.kind = EventKind::Tempo;
                ref.stream = {StreamKind::Tempo};
            } else if (metaIsTimeSig(event)) {
                ref.kind = EventKind::TimeSig;
                ref.stream = {StreamKind::TimeSig};
            }
            plan.events.push_back(ref);
        }
    }
    for (int engineTrack = 0; engineTrack < m_document.engineTrackCount(); engineTrack++) {
        if (!m_scope.wholeSong && m_trackScope.find(engineTrack) == m_trackScope.end())
            continue;
        for (const DocNote &note : m_document.notesForTrack(engineTrack)) {
            if (note.smfTrack < 0 || note.smfTrack >= int(plan.selected.size()) ||
                note.onIndex >= plan.selected[size_t(note.smfTrack)].size() ||
                !plan.selected[size_t(note.smfTrack)][note.onIndex])
                continue;
            if (!note.unterminated() &&
                (note.endIndex >= plan.selected[size_t(note.smfTrack)].size() ||
                 !plan.selected[size_t(note.smfTrack)][note.endIndex]))
                continue;
            plan.notes.push_back(note);
        }
    }
    return plan;
}

std::vector<std::vector<const SongDocument::TimeEditor::TimeEventRef *>>
SongDocument::TimeEditor::timeEditStreams(const TimeEditPlan &plan) const
{
    std::map<StreamIdentity, std::vector<const TimeEventRef *>> grouped;
    for (const TimeEventRef &ref : plan.events) {
        if (ref.kind == EventKind::ChannelState || ref.kind == EventKind::Tempo ||
            ref.kind == EventKind::TimeSig)
            grouped[ref.stream].push_back(&ref);
    }
    std::vector<std::vector<const TimeEventRef *>> streams;
    streams.reserve(grouped.size());
    for (auto &entry : grouped) {
        auto &points = entry.second;
        std::sort(points.begin(), points.end(), [](const TimeEventRef *a, const TimeEventRef *b) {
            if (a->tick != b->tick)
                return a->tick < b->tick;
            if (a->smfTrack != b->smfTrack)
                return a->smfTrack < b->smfTrack;
            return a->index < b->index;
        });
        streams.push_back(std::move(points));
    }
    return streams;
}

bool SongDocument::TimeEditor::rippleDelete()
{
    if (m_range.empty() || m_document.m_smf.tracks.empty())
        return false;
    const uint64_t s = m_range.startTick;
    const uint64_t e = m_range.endTick;
    const uint64_t span = m_range.span();
    const TimeEditPlan plan = buildTimeEditPlan();
    std::vector<std::vector<size_t>> removals(m_document.m_smf.tracks.size());
    std::vector<SongDocument::EditOp> inserts;
    std::vector<std::vector<bool>> taken = makeTimeEditTaken();
    for (const DocNote &note : plan.notes) {
        if (note.tick >= e) {
            appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.onIndex,
                               note.tick - span, MoveMode::SkipUnchanged);
            if (!note.unterminated()) {
                const uint64_t endTick =
                    m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick;
                appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.endIndex,
                                   endTick - span, MoveMode::SkipUnchanged);
            }
        } else if (note.tick >= s) {
            appendTimeEditRemove(removals, taken, note.smfTrack, note.onIndex);
            if (!note.unterminated())
                appendTimeEditRemove(removals, taken, note.smfTrack, note.endIndex);
        } else {
            consumeTimeEditEvent(taken, note.smfTrack, note.onIndex);
            if (!note.unterminated())
                consumeTimeEditEvent(taken, note.smfTrack, note.endIndex);
        }
    }
    // DocNotes consume both events of every paired note. Ripple any selected
    // note event left behind as an orphan raw event using half-open semantics.
    for (const TimeEventRef &ref : plan.events) {
        if (ref.kind != EventKind::Note || taken[size_t(ref.smfTrack)][ref.index])
            continue;
        if (ref.tick < s)
            consumeTimeEditEvent(taken, ref.smfTrack, ref.index);
        else if (ref.tick >= e)
            appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, ref.tick - span,
                               MoveMode::SkipUnchanged);
        else
            appendTimeEditRemove(removals, taken, ref.smfTrack, ref.index);
    }
    const auto streams = timeEditStreams(plan);
    for (const auto &points : streams) {
        bool seamCovered = false;
        int winner = -1;
        for (size_t i = 0; i < points.size(); i++) {
            if (points[i]->tick == e)
                seamCovered = true;
            if (points[i]->tick >= s && points[i]->tick < e)
                winner = int(i);
        }
        for (size_t i = 0; i < points.size(); i++) {
            const TimeEventRef &ref = *points[i];
            if (ref.tick < s)
                consumeTimeEditEvent(taken, ref.smfTrack, ref.index);
            else if (ref.tick >= e)
                appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index,
                                   ref.tick - span, MoveMode::SkipUnchanged);
            else if (int(i) == winner && !seamCovered)
                appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, s,
                                   MoveMode::SkipUnchanged);
            else
                appendTimeEditRemove(removals, taken, ref.smfTrack, ref.index);
        }
    }
    if (m_scope.wholeSong) {
        for (const TimeEventRef &ref : plan.events) {
            if (ref.kind != EventKind::Other)
                continue;
            if (ref.tick >= e)
                appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index,
                                   ref.tick - span, MoveMode::SkipUnchanged);
            else if (ref.tick > s)
                appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, s,
                                   MoveMode::SkipUnchanged);
            else
                consumeTimeEditEvent(taken, ref.smfTrack, ref.index);
        }
    }
    const std::vector<bool> noAffectedTracks;
    const std::vector<SongDocument::EditOp> noInserts;
    std::vector<SongDocument::EditOp> ops = assembleTimeEditOps(
        std::move(removals), std::move(inserts),
        timeEditTrackEnds(m_range, noAffectedTracks, noInserts, TrackEndMode::RippleLeft, 0));
    if (ops.empty())
        return false;
    m_document.pushEdit(m_document.tr("remove range"), std::move(ops));
    return true;
}

bool SongDocument::TimeEditor::insertBlank()
{
    if (m_range.empty() || m_document.m_smf.tracks.empty())
        return false;
    const uint64_t s = m_range.startTick;
    const uint64_t e = m_range.endTick;
    const uint64_t span = m_range.span();
    const TimeEditPlan plan = buildTimeEditPlan();
    const std::vector<bool> affectedTracks = timeEditAffectedSmfTracks();
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++)
        if (affectedTracks[t] && m_document.m_smf.tracks[t].endTick >= s &&
            m_document.m_smf.tracks[t].endTick > UINT64_MAX - span)
            return false;
    for (const TimeEventRef &ref : plan.events)
        if (ref.tick >= s && ref.tick > UINT64_MAX - span)
            return false;
    std::vector<std::vector<size_t>> removals(m_document.m_smf.tracks.size());
    std::vector<SongDocument::EditOp> inserts;
    std::vector<std::vector<bool>> taken = makeTimeEditTaken();
    for (const DocNote &note : plan.notes) {
        const uint64_t endTick =
            note.unterminated()
                ? 0
                : m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick;
        if (note.tick >= s) {
            appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.onIndex,
                               note.tick + span, MoveMode::MoveEvenIfUnchanged);
            if (!note.unterminated())
                appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.endIndex,
                                   endTick + span, MoveMode::MoveEvenIfUnchanged);
        } else if (!note.unterminated() && endTick == s) {
            consumeTimeEditEvent(taken, note.smfTrack, note.endIndex);
        } else if (!note.unterminated() && endTick > s) {
            const SmfEvent &on =
                m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex];
            const SmfEvent &end =
                m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex];
            consumeTimeEditEvent(taken, note.smfTrack, note.onIndex);
            consumeTimeEditEvent(taken, note.smfTrack, note.endIndex);
            removals[size_t(note.smfTrack)].push_back(note.endIndex);
            appendTimeEditInsert(inserts, note.smfTrack, end, s, false);
            appendTimeEditInsert(inserts, note.smfTrack, on, e, false);
            appendTimeEditInsert(inserts, note.smfTrack, end, endTick + span, false);
        } else if (note.unterminated()) {
            // Keep the original left note-on, close it at the seam, and start
            // a fresh note-on after the silent interval.
            const SmfEvent &on =
                m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex];
            consumeTimeEditEvent(taken, note.smfTrack, note.onIndex);
            appendTimeEditInsert(inserts, note.smfTrack,
                                 m_document.makeChannelEvent(0x8, note.channel, s, note.key, 0), s,
                                 false);
            appendTimeEditInsert(inserts, note.smfTrack, on, e, false);
        }
    }
    for (const TimeEventRef &ref : plan.events) {
        if (taken[size_t(ref.smfTrack)][ref.index])
            continue;
        if (ref.tick >= s)
            appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, ref.tick + span,
                               MoveMode::MoveEvenIfUnchanged);
    }
    const std::vector<SongDocument::EditOp> trackEnds =
        timeEditTrackEnds(m_range, affectedTracks, inserts, TrackEndMode::ShiftRight, s);
    std::vector<SongDocument::EditOp> ops =
        assembleTimeEditOps(std::move(removals), std::move(inserts), std::move(trackEnds));
    if (ops.empty())
        return false;
    m_document.pushEdit(m_document.tr("insert blank time"), std::move(ops));
    return true;
}

bool SongDocument::TimeEditor::duplicate()
{
    if (m_range.empty() || m_document.m_smf.tracks.empty() ||
        m_range.endTick > UINT64_MAX - m_range.span())
        return false;
    const uint64_t s = m_range.startTick;
    const uint64_t e = m_range.endTick;
    const uint64_t span = m_range.span();
    const uint64_t destinationEnd = e + span;
    const TimeEditPlan plan = buildTimeEditPlan();
    const std::vector<bool> affectedTracks = timeEditAffectedSmfTracks();
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++)
        if (affectedTracks[t] && m_document.m_smf.tracks[t].endTick >= e &&
            m_document.m_smf.tracks[t].endTick > UINT64_MAX - span)
            return false;
    for (const TimeEventRef &ref : plan.events)
        if (ref.tick >= e && ref.tick > UINT64_MAX - span)
            return false;
    std::vector<std::vector<size_t>> removals(m_document.m_smf.tracks.size());
    std::vector<SongDocument::EditOp> inserts;
    std::vector<std::vector<bool>> taken = makeTimeEditTaken();
    std::vector<std::vector<bool>> paired(m_document.m_smf.tracks.size());
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++)
        paired[t].assign(m_document.m_smf.tracks[t].events.size(), false);
    for (const DocNote &note : plan.notes) {
        paired[size_t(note.smfTrack)][note.onIndex] = true;
        const uint64_t endTick =
            note.unterminated()
                ? 0
                : m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick;
        if (!note.unterminated())
            paired[size_t(note.smfTrack)][note.endIndex] = true;
        if (note.tick >= e) {
            appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.onIndex,
                               note.tick + span, MoveMode::MoveEvenIfUnchanged);
            if (!note.unterminated())
                appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.endIndex,
                                   endTick + span, MoveMode::MoveEvenIfUnchanged);
        } else if (!note.unterminated() && endTick >= e) {
            if (endTick == e)
                consumeTimeEditEvent(taken, note.smfTrack, note.endIndex);
            else {
                const SmfEvent &on =
                    m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex];
                const SmfEvent &end =
                    m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex];
                consumeTimeEditEvent(taken, note.smfTrack, note.endIndex);
                removals[size_t(note.smfTrack)].push_back(note.endIndex);
                appendTimeEditInsert(inserts, note.smfTrack, end, e, false);
                appendTimeEditInsert(inserts, note.smfTrack, on, destinationEnd, false);
                appendTimeEditInsert(inserts, note.smfTrack, end, endTick + span, false);
            }
        }
    }
    for (const TimeEventRef &ref : plan.events) {
        if (taken[size_t(ref.smfTrack)][ref.index])
            continue;
        if (ref.tick >= e)
            appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, ref.tick + span,
                               MoveMode::MoveEvenIfUnchanged);
    }
    for (const DocNote &note : plan.notes) {
        if (note.tick >= e)
            continue;
        const uint64_t endTick =
            note.unterminated()
                ? e
                : m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick;
        const uint64_t sourceStart = std::max(note.tick, s);
        const uint64_t sourceEnd = std::min(endTick, e);
        if (sourceEnd <= sourceStart)
            continue;
        const SmfEvent &on = m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex];
        appendTimeEditInsert(inserts, note.smfTrack, on, e + (sourceStart - s), false);
        SmfEvent end;
        if (!note.unterminated()) {
            end = m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex];
        } else {
            end = m_document.makeChannelEvent(0x8, note.channel, destinationEnd, note.key, 0);
        }
        end.tick = e + (sourceEnd - s);
        appendTimeEditInsert(inserts, note.smfTrack, end, end.tick, false);
    }
    const auto streams = timeEditStreams(plan);
    for (const auto &points : streams) {
        const TimeEventRef *atStart = nullptr;
        const TimeEventRef *firstInside = nullptr;
        for (const TimeEventRef *ref : points) {
            if (ref->tick <= s)
                atStart = ref;
            else if (ref->tick < e && !firstInside)
                firstInside = ref;
        }
        const TimeEventRef *prototype = atStart ? atStart : firstInside;
        if (!prototype)
            continue;
        if (atStart) {
            const SmfEvent &source =
                m_document.m_smf.tracks[size_t(atStart->smfTrack)].events[atStart->index];
            appendTimeEditInsert(inserts, atStart->smfTrack, source, e, false);
        } else {
            int defaultValue = -1;
            if (prototype->kind == EventKind::Tempo) {
                defaultValue = CoreTimeDefaults::kTempoBpm;
            } else if (prototype->kind == EventKind::TimeSig) {
                defaultValue = 1;
            } else {
                const SmfEvent &source =
                    m_document.m_smf.tracks[size_t(prototype->smfTrack)].events[prototype->index];
                if (source.typeNibble() == 0xE)
                    defaultValue = 0;
                else if (source.typeNibble() == 0xB)
                    defaultValue = CoreTimeDefaults::controllerDefault(source.data0);
            }
            if (defaultValue >= 0) {
                SmfEvent synthetic;
                int targetTrack = prototype->smfTrack;
                if (prototype->kind == EventKind::Tempo) {
                    synthetic.status = 0xFF;
                    synthetic.metaType = 0x51;
                    synthetic.blob = QByteArray(3, 0);
                    const uint32_t usPerBeat = uint32_t(60000000 / defaultValue);
                    synthetic.blob[0] = char((usPerBeat >> 16) & 0xFF);
                    synthetic.blob[1] = char((usPerBeat >> 8) & 0xFF);
                    synthetic.blob[2] = char(usPerBeat & 0xFF);
                } else if (prototype->kind == EventKind::TimeSig) {
                    synthetic.status = 0xFF;
                    synthetic.metaType = 0x58;
                    synthetic.blob = QByteArray(4, 0);
                    synthetic.blob[0] = 4;
                    synthetic.blob[1] = 2;
                    synthetic.blob[2] = 24;
                    synthetic.blob[3] = 8;
                    targetTrack = 0;
                } else {
                    const SmfEvent &source = m_document.m_smf.tracks[size_t(prototype->smfTrack)]
                                                 .events[prototype->index];
                    const uint8_t type = source.typeNibble();
                    const uint8_t data0 = type == 0xB ? source.data0 : 0;
                    const uint8_t data1 = type == 0xE ? 64 : uint8_t(defaultValue);
                    synthetic =
                        m_document.makeChannelEvent(type, source.channel(), e, data0, data1);
                }
                appendTimeEditInsert(inserts, targetTrack, synthetic, e, false);
            }
        }
        for (const TimeEventRef *ref : points) {
            if (ref->tick <= s || ref->tick >= e)
                continue;
            const SmfEvent &source =
                m_document.m_smf.tracks[size_t(ref->smfTrack)].events[ref->index];
            appendTimeEditInsert(inserts, ref->smfTrack, source, e + (ref->tick - s), false);
        }
    }
    if (m_scope.wholeSong) {
        for (const TimeEventRef &ref : plan.events) {
            if (ref.kind != EventKind::Other || ref.tick < s || ref.tick >= e)
                continue;
            const SmfEvent &source =
                m_document.m_smf.tracks[size_t(ref.smfTrack)].events[ref.index];
            appendTimeEditInsert(inserts, ref.smfTrack, source, e + (ref.tick - s), false);
        }
    }
    for (const TimeEventRef &ref : plan.events) {
        if (ref.kind != EventKind::Note || paired[size_t(ref.smfTrack)][ref.index] ||
            ref.tick < s || ref.tick >= e)
            continue;
        const SmfEvent &source = m_document.m_smf.tracks[size_t(ref.smfTrack)].events[ref.index];
        appendTimeEditInsert(inserts, ref.smfTrack, source, e + (ref.tick - s), false);
    }
    const std::vector<SongDocument::EditOp> trackEnds =
        timeEditTrackEnds(m_range, affectedTracks, inserts, TrackEndMode::ShiftRight, e);
    std::vector<SongDocument::EditOp> ops =
        assembleTimeEditOps(std::move(removals), std::move(inserts), std::move(trackEnds));
    if (ops.empty())
        return false;
    m_document.pushEdit(m_document.tr("duplicate time range"), std::move(ops));
    return true;
}

bool SongDocument::rippleDeleteTimeRange(const TimeRange &range, const TimeScope &scope)
{
    return TimeEditor(*this, range, scope).rippleDelete();
}

bool SongDocument::insertBlankTime(const TimeRange &range, const TimeScope &scope)
{
    return TimeEditor(*this, range, scope).insertBlank();
}

bool SongDocument::duplicateTimeRange(const TimeRange &range, const TimeScope &scope)
{
    return TimeEditor(*this, range, scope).duplicate();
}
