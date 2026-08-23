#include "songdocument_timeeditor.hpp"

#include "core/timedefaults.h"

namespace time_edit_detail {

std::vector<TempoPoint> insertBlankTempoPoints(const std::vector<TempoPoint> &src,
                                               const SongDocument::TimeRange &range);
std::vector<TempoPoint> duplicateTempoPoints(const std::vector<TempoPoint> &src,
                                             const SongDocument::TimeRange &range);

} // namespace time_edit_detail

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
    if (m_scope.coversTempo()) {
        for (const TempoPoint &point : m_document.m_tempoPoints)
            if (point.tick >= s && point.tick > UINT64_MAX - span)
                return false;
    }
    std::vector<std::vector<size_t>> removals(m_document.m_smf.tracks.size());
    std::vector<SongDocument::EditOp> inserts;
    std::vector<std::vector<bool>> taken = makeTimeEditTaken();
    std::vector<XcmdEventRecord> xcmdEventRecords;
    for (const DocNote &note : plan.notes) {
        const uint64_t endTick =
            note.unterminated()
                ? 0
                : m_document.m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick;
        if (note.tick >= s) {
            appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.onIndex,
                               note.tick + span, MoveMode::MoveEvenIfUnchanged, xcmdEventRecords);
            if (!note.unterminated())
                appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.endIndex,
                                   endTick + span, MoveMode::MoveEvenIfUnchanged, xcmdEventRecords);
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
                               MoveMode::MoveEvenIfUnchanged, xcmdEventRecords);
    }
    const std::vector<SongDocument::EditOp> trackEnds =
        timeEditShiftRightTrackEnds(affectedTracks, inserts, s);
    auto opsOpt = xcmdAssembleOps(std::move(removals), std::move(inserts), std::move(trackEnds),
                                  xcmdEventRecords);
    if (!opsOpt)
        return false; // XCMD reconciliation unrepresentable: fail without mutating
    std::vector<SongDocument::EditOp> ops = std::move(*opsOpt);
    std::vector<TempoPoint> nextTempo = m_document.m_tempoPoints;
    if (m_scope.coversTempo())
        nextTempo = time_edit_detail::insertBlankTempoPoints(nextTempo, m_range);
    if (ops.empty() && nextTempo == m_document.m_tempoPoints)
        return false;
    if (nextTempo == m_document.m_tempoPoints)
        m_document.pushEdit(m_document.tr("insert blank time"), std::move(ops));
    else
        m_document.pushEdit(m_document.tr("insert blank time"), std::move(ops),
                            std::move(nextTempo));
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
    if (m_scope.coversTempo()) {
        for (const TempoPoint &point : m_document.m_tempoPoints)
            if (point.tick >= e && point.tick > UINT64_MAX - span)
                return false;
    }
    std::vector<std::vector<size_t>> removals(m_document.m_smf.tracks.size());
    std::vector<SongDocument::EditOp> inserts;
    std::vector<std::vector<bool>> taken = makeTimeEditTaken();
    std::vector<XcmdEventRecord> xcmdEventRecords;
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
                               note.tick + span, MoveMode::MoveEvenIfUnchanged, xcmdEventRecords);
            if (!note.unterminated())
                appendTimeEditMove(removals, inserts, taken, note.smfTrack, note.endIndex,
                                   endTick + span, MoveMode::MoveEvenIfUnchanged, xcmdEventRecords);
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
                               MoveMode::MoveEvenIfUnchanged, xcmdEventRecords);
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
            recordXcmdRelocation(atStart->smfTrack, atStart->index, e, inserts.size() - 1, true,
                                 xcmdEventRecords);
        } else {
            int defaultValue = -1;
            if (prototype->kind == EventKind::TimeSig) {
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
                if (prototype->kind == EventKind::TimeSig) {
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
            recordXcmdRelocation(ref->smfTrack, ref->index, e + (ref->tick - s), inserts.size() - 1,
                                 true, xcmdEventRecords);
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
        timeEditShiftRightTrackEnds(affectedTracks, inserts, e);
    auto opsOpt = xcmdAssembleOps(std::move(removals), std::move(inserts), std::move(trackEnds),
                                  xcmdEventRecords);
    if (!opsOpt)
        return false; // XCMD reconciliation unrepresentable: fail without mutating
    std::vector<SongDocument::EditOp> ops = std::move(*opsOpt);
    std::vector<TempoPoint> nextTempo = m_document.m_tempoPoints;
    if (m_scope.coversTempo())
        nextTempo = time_edit_detail::duplicateTempoPoints(nextTempo, m_range);
    if (ops.empty() && nextTempo == m_document.m_tempoPoints)
        return false;
    if (nextTempo == m_document.m_tempoPoints)
        m_document.pushEdit(m_document.tr("duplicate time range"), std::move(ops));
    else
        m_document.pushEdit(m_document.tr("duplicate time range"), std::move(ops),
                            std::move(nextTempo));
    return true;
}
