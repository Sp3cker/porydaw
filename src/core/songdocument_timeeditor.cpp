#include "songdocument_timeeditor.hpp"

#include <algorithm>
#include <map>
#include <utility>

#include "core/timedefaults.h"

namespace time_edit_detail {

std::vector<TempoPoint> removeTempoPoints(const std::vector<TempoPoint> &src,
                                          const SongDocument::TimeRange &range)
{
    const uint64_t s = range.startTick;
    const uint64_t e = range.endTick;
    const uint64_t span = range.span();
    bool seamCovered = false;
    int winner = -1;
    for (int i = 0; i < int(src.size()); i++) {
        if (src[size_t(i)].tick == e)
            seamCovered = true;
        if (src[size_t(i)].tick >= s && src[size_t(i)].tick < e)
            winner = i;
    }
    std::vector<TempoPoint> out;
    out.reserve(src.size());
    for (int i = 0; i < int(src.size()); i++) {
        const TempoPoint &point = src[size_t(i)];
        if (point.tick < s)
            out.push_back(point);
        else if (point.tick >= e)
            out.push_back({point.tick - span, point.microsecondsPerQuarterNote});
        else if (i == winner && !seamCovered)
            out.push_back({s, point.microsecondsPerQuarterNote});
    }
    return out;
}

std::vector<TempoPoint> insertBlankTempoPoints(const std::vector<TempoPoint> &src,
                                               const SongDocument::TimeRange &range)
{
    const uint64_t s = range.startTick;
    const uint64_t span = range.span();
    std::vector<TempoPoint> out;
    out.reserve(src.size());
    for (const TempoPoint &point : src) {
        if (point.tick >= s)
            out.push_back({point.tick + span, point.microsecondsPerQuarterNote});
        else
            out.push_back(point);
    }
    return out;
}

std::vector<TempoPoint> duplicateTempoPoints(const std::vector<TempoPoint> &src,
                                             const SongDocument::TimeRange &range)
{
    const uint64_t s = range.startTick;
    const uint64_t e = range.endTick;
    const uint64_t span = range.span();
    const TempoPoint *atStart = nullptr;
    const TempoPoint *firstInside = nullptr;
    for (const TempoPoint &point : src) {
        if (point.tick <= s)
            atStart = &point;
        else if (point.tick < e && firstInside == nullptr)
            firstInside = &point;
    }
    std::vector<TempoPoint> out;
    out.reserve(src.size() + 2);
    for (const TempoPoint &point : src) {
        if (point.tick >= e)
            out.push_back({point.tick + span, point.microsecondsPerQuarterNote});
        else
            out.push_back(point);
    }
    if (atStart)
        out.push_back({e, atStart->microsecondsPerQuarterNote});
    else if (firstInside)
        out.push_back({e, CoreTimeDefaults::kDefaultTempoUspqn});
    for (const TempoPoint &point : src) {
        if (point.tick > s && point.tick < e)
            out.push_back({e + (point.tick - s), point.microsecondsPerQuarterNote});
    }
    return out;
}

} // namespace time_edit_detail

SongDocument::TimeEditor::TimeEditor(SongDocument &document, const TimeRange &range,
                                     const TimeScope &scope)
    : m_document(document)
    , m_range(range)
    , m_scope(scope)
{
    for (int track : m_scope.tracks)
        m_trackScope.insert(track);
    for (const auto &lane : m_scope.lanes)
        m_laneScope.insert({lane.first, lane.second});
    // The per-track XCMD index is built lazily (xcmdTrackIndex) on first
    // access, one projection pass per track the edit actually touches.
    m_xcmdLaneByEvent.resize(m_document.m_smf.tracks.size());
    m_xcmdConsumedOfEvent.resize(m_document.m_smf.tracks.size());
}

void SongDocument::TimeEditor::xcmdTrackIndex(int smfTrack) const
{
    if (smfTrack < 0 || smfTrack >= int(m_xcmdLaneByEvent.size()))
        return;
    auto &lanes = m_xcmdLaneByEvent[size_t(smfTrack)];
    auto &consumed = m_xcmdConsumedOfEvent[size_t(smfTrack)];
    if (!consumed.empty())
        return; // already built for this track
    const auto &events = m_document.m_smf.tracks[size_t(smfTrack)].events;
    lanes.assign(events.size(), std::nullopt);
    consumed.assign(events.size(), 0);
    const std::vector<xcmd::Event> rows = m_document.xcmdEvents(smfTrack);
    const xcmd::Projection projection = xcmd::projectEvents(rows);
    for (uint64_t index : projection.consumed)
        if (index < consumed.size())
            consumed[size_t(index)] = 1;
    for (const xcmd::Point &point : projection.points)
        if (point.index < lanes.size())
            lanes[size_t(point.index)] = point.lane;
}

bool SongDocument::TimeEditor::isSeamKeeperEligible(const TimeEventRef &ref) const
{
    return ref.smfTrack < 0 || !isXcmdConsumed(ref.smfTrack, ref.index);
}

bool SongDocument::TimeEditor::isXcmdConsumed(int smfTrack, size_t index) const
{
    if (smfTrack < 0 || smfTrack >= int(m_xcmdConsumedOfEvent.size()))
        return false;
    xcmdTrackIndex(smfTrack);
    const auto &consumed = m_xcmdConsumedOfEvent[size_t(smfTrack)];
    return index < consumed.size() && consumed[index] != 0;
}

bool SongDocument::TimeEditor::metaIsTimeSig(const SmfEvent &event)
{
    return event.isMeta() && event.metaType == 0x58 && event.blob.size() >= 2;
}

SongDocument::TimeEditor::StreamIdentity
SongDocument::TimeEditor::channelStream(int smfTrack, const SmfEvent &event)
{
    const uint8_t type = event.typeNibble();
    return {StreamKind::Channel, smfTrack, event.status,
            (type == 0xA || type == 0xB) ? event.data0 : uint8_t{0}};
}

std::optional<uint8_t> SongDocument::TimeEditor::logicalXcmdLane(int smfTrack, size_t index) const
{
    if (smfTrack < 0 || smfTrack >= int(m_xcmdLaneByEvent.size()))
        return std::nullopt;
    xcmdTrackIndex(smfTrack);
    const auto &lanes = m_xcmdLaneByEvent[size_t(smfTrack)];
    if (index >= lanes.size())
        return std::nullopt;
    const std::optional<uint8_t> lane = lanes[index];
    if (!lane)
        return std::nullopt;
    const int engineTrack = m_document.engineTrackForChunk(smfTrack);
    if (m_scope.wholeSong || m_trackScope.contains(engineTrack) ||
        !m_laneScope.contains({engineTrack, *lane}))
        return std::nullopt;
    return lane;
}

std::optional<uint8_t> SongDocument::TimeEditor::laneForEvent(int smfTrack, size_t index,
                                                              const SmfEvent &event) const
{
    // Only channel events can be protocol bytes; consulting the XCMD lane
    // for a meta would be a wasted per-track build.
    if (event.isChannel()) {
        if (const auto lane = logicalXcmdLane(smfTrack, index))
            return lane;
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
    return std::nullopt;
}

bool SongDocument::TimeEditor::eventCovered(int smfTrack, size_t index, int engineTrack,
                                            const SmfEvent &event) const
{
    if (isTempoMeta(event))
        return false;
    if (m_scope.wholeSong)
        return !event.isChannel() || engineTrack >= 0;
    const bool trackCovered =
        engineTrack >= 0 && m_trackScope.find(engineTrack) != m_trackScope.end();
    if (event.isChannel() && trackCovered)
        return true;
    const auto lane = laneForEvent(smfTrack, index, event);
    if (!lane)
        return false;
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
        if (lane.engineTrack >= 0 && lane.engineTrack < m_document.engineTrackCount() &&
            (lane.cc <= 0x7F || lane.cc == DOC_CC_BEND || lane.cc == DOC_CC_VOICE ||
             xcmd::isLaneController(lane.cc))) {
            const int smfTrack = m_document.smfTrackFor(lane.engineTrack);
            if (smfTrack >= 0)
                affected[size_t(smfTrack)] = true;
        }
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
                                                  MoveMode mode,
                                                  std::vector<XcmdEventRecord> &records) const
{
    if (!consumeTimeEditEvent(taken, smfTrack, index))
        return false;
    const SmfEvent &event = m_document.m_smf.tracks[size_t(smfTrack)].events[index];
    if (mode == MoveMode::SkipUnchanged && event.tick == tick)
        return true;
    removals[size_t(smfTrack)].push_back(index);
    appendTimeEditInsert(inserts, smfTrack, event, tick, event.isNoteOn());
    if (isXcmdConsumed(smfTrack, index)) {
        // Source-indexed relocation for the deep planner: the moved byte's
        // epoch is rebuilt canonically and this generic insert is replaced
        // by the patch (moved at its destination tick, kept bytes re-emitted
        // in place). Selector glue and opaque members record too — the
        // planner treats them per its own epoch rules.
        const size_t opIndex = inserts.size() - 1;
        recordXcmdRelocation(smfTrack, index, tick, opIndex, false, records);
    }
    return true;
}

std::vector<SongDocument::EditOp> SongDocument::TimeEditor::timeEditCloseGapTrackEnds() const
{
    if (!m_scope.wholeSong)
        return {};
    std::vector<SongDocument::EditOp> trackEnds;
    const uint64_t span = m_range.span();
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++) {
        const uint64_t end = m_document.m_smf.tracks[t].endTick;
        const uint64_t newEnd = end >= m_range.endTick
                                    ? end - span
                                    : (end > m_range.startTick ? m_range.startTick : end);
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

std::vector<SongDocument::EditOp> SongDocument::TimeEditor::timeEditShiftRightTrackEnds(
    const std::vector<bool> &affectedTracks, const std::vector<SongDocument::EditOp> &inserts,
    uint64_t threshold) const
{
    std::vector<SongDocument::EditOp> trackEnds;
    const uint64_t span = m_range.span();
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++) {
        const uint64_t end = m_document.m_smf.tracks[t].endTick;
        uint64_t newEnd = end;
        if (affectedTracks[t] && end >= threshold)
            newEnd = end + span;
        for (const SongDocument::EditOp &insert : inserts) {
            if (insert.smfTrack == int(t))
                newEnd = std::max(newEnd, insert.event.tick);
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
            if (!eventCovered(int(t), i, engineTrack, event))
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
                    if (const auto lane = logicalXcmdLane(int(t), i))
                        ref.stream = {StreamKind::Channel, int(t), event.status, *lane};
                    else
                        ref.stream = channelStream(int(t), event);
                }
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
        if (ref.kind == EventKind::ChannelState || ref.kind == EventKind::TimeSig)
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

bool SongDocument::TimeEditor::remove()
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
    std::vector<XcmdEventRecord> xcmdEventRecords;
    for (const DocNote &note : plan.notes) {
        if (note.tick >= e) {
            appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.onIndex,
                               note.tick - span, MoveMode::SkipUnchanged, xcmdEventRecords);
            if (!note.unterminated()) {
                const uint64_t endTick =
                    m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick;
                appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.endIndex,
                                   endTick - span, MoveMode::SkipUnchanged, xcmdEventRecords);
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
    // DocNotes consume both events of every paired note. Close any selected
    // note event left behind as an orphan raw event using half-open semantics.
    for (const TimeEventRef &ref : plan.events) {
        if (ref.kind != EventKind::Note || taken[size_t(ref.smfTrack)][ref.index])
            continue;
        if (ref.tick < s)
            consumeTimeEditEvent(taken, ref.smfTrack, ref.index);
        else if (ref.tick >= e)
            appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, ref.tick - span,
                               MoveMode::SkipUnchanged, xcmdEventRecords);
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
            if (points[i]->tick >= s && points[i]->tick < e) {
                // Value streams keep their last-point winner so the state
                // the shifted content was authored under survives the seam;
                // consumed XCMD events are never winners (isSeamKeeperEligible).
                if (!isSeamKeeperEligible(*points[i]))
                    continue;
                winner = int(i);
            }
        }
        for (size_t i = 0; i < points.size(); i++) {
            const TimeEventRef &ref = *points[i];
            if (ref.tick < s)
                consumeTimeEditEvent(taken, ref.smfTrack, ref.index);
            else if (ref.tick >= e)
                appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index,
                                   ref.tick - span, MoveMode::SkipUnchanged, xcmdEventRecords);
            else if (int(i) == winner && !seamCovered)
                appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, s,
                                   MoveMode::SkipUnchanged, xcmdEventRecords);
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
                                   ref.tick - span, MoveMode::SkipUnchanged, xcmdEventRecords);
            else if (ref.tick > s)
                appendTimeEditMove(removals, inserts, taken, ref.smfTrack, ref.index, s,
                                   MoveMode::SkipUnchanged, xcmdEventRecords);
            else
                consumeTimeEditEvent(taken, ref.smfTrack, ref.index);
        }
    }
    auto opsOpt = xcmdAssembleOps(std::move(removals), std::move(inserts),
                                  timeEditCloseGapTrackEnds(), xcmdEventRecords);
    if (!opsOpt)
        return false; // XCMD reconciliation unrepresentable: fail without mutating
    std::vector<SongDocument::EditOp> ops = std::move(*opsOpt);
    std::vector<TempoPoint> nextTempo = m_document.m_tempoPoints;
    if (m_scope.coversTempo())
        nextTempo = time_edit_detail::removeTempoPoints(nextTempo, m_range);
    if (ops.empty() && nextTempo == m_document.m_tempoPoints)
        return false;
    if (nextTempo == m_document.m_tempoPoints)
        m_document.pushEdit(m_document.tr("remove range"), std::move(ops));
    else
        m_document.pushEdit(m_document.tr("remove range"), std::move(ops), std::move(nextTempo));
    return true;
}

bool SongDocument::removeTimeRange(const TimeRange &range, const TimeScope &scope)
{
    return TimeEditor(*this, range, scope).remove();
}

bool SongDocument::insertBlankTime(const TimeRange &range, const TimeScope &scope)
{
    return TimeEditor(*this, range, scope).insertBlank();
}

bool SongDocument::duplicateTimeRange(const TimeRange &range, const TimeScope &scope)
{
    return TimeEditor(*this, range, scope).duplicate();
}
