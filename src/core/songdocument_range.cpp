#include "songdocument.h"

#include <algorithm>
#include <set>

void SongDocument::applyRangeEdit(const QString &text, const RangeEdit &edit)
{
    if (edit.empty())
        return;
    std::vector<EditOp> ops;
    if (!m_smf.tracks.empty()) {
        std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
        for (const DocNote &note : edit.removeNotes) {
            if (note.smfTrack < 0 || note.smfTrack >= int(removals.size()))
                continue;
            removals[size_t(note.smfTrack)].push_back(note.onIndex);
            if (!note.unterminated())
                removals[size_t(note.smfTrack)].push_back(note.endIndex);
        }
        for (const DocLanePoint &pt : edit.removePoints) {
            if (pt.smfTrack >= 0 && pt.smfTrack < int(removals.size()))
                removals[size_t(pt.smfTrack)].push_back(pt.index);
        }
        std::vector<PlannedNote> written;
        for (const RangeEdit::TrackNotes &tn : edit.addNotes) {
            for (const NewNote &note : tn.notes)
                written.push_back({tn.engineTrack, note.key, note.tick,
                                   note.tick + std::max<uint32_t>(1, note.duration)});
        }
        std::vector<EditOp> trims;
        resolveNoteOverlaps(written, edit.removeNotes, removals, trims);
        // All removals first (per SMF track, descending — appendRemoveOps sorts
        // and dedups), so every recorded index stays valid at apply time.
        for (size_t t = 0; t < m_smf.tracks.size(); t++)
            appendRemoveOps(ops, int(t), std::move(removals[t]));
        for (const RangeEdit::TrackNotes &tn : edit.addNotes) {
            const int smfTrack = smfTrackFor(tn.engineTrack);
            if (smfTrack < 0)
                continue;
            const uint8_t channel = channelFor(tn.engineTrack);
            for (const NewNote &note : tn.notes)
                appendNoteInsertOps(ops, smfTrack, channel, note.tick, note.key, note.duration,
                                    note.velocity);
        }
        for (const RangeEdit::LaneWrite &lw : edit.addPoints) {
            const int smfTrack = smfTrackFor(lw.engineTrack);
            if (smfTrack < 0)
                continue;
            const uint8_t channel = channelFor(lw.engineTrack);
            for (const LanePointValue &pt : lw.points) {
                EditOp op;
                op.type = EditOp::InsertEvent;
                op.smfTrack = smfTrack;
                op.event = makeLaneEvent(lw.cc, channel, pt.tick, pt.value);
                ops.push_back(op);
            }
        }
        ops.insert(ops.end(), trims.begin(), trims.end());
    }
    if (edit.removeTempo.empty() && edit.addTempo.empty()) {
        pushEdit(text, std::move(ops));
        return;
    }
    std::vector<TempoPoint> nextTempo = m_tempoPoints;
    std::set<uint64_t> removeTicks;
    for (const TempoPoint &point : edit.removeTempo)
        removeTicks.insert(point.tick);
    std::erase_if(nextTempo,
                  [&](const TempoPoint &point) { return removeTicks.contains(point.tick); });
    nextTempo.insert(nextTempo.end(), edit.addTempo.begin(), edit.addTempo.end());
    pushEdit(text, std::move(ops), std::move(nextTempo));
}

void SongDocument::moveRange(const std::vector<DocNote> &notes,
                             const std::vector<DocLanePoint> &points, int64_t dTick,
                             const std::vector<TempoPoint> &tempo)
{
    if ((notes.empty() && points.empty() && tempo.empty()) || dTick == 0)
        return;
    std::vector<EditOp> ops;
    if (!m_smf.tracks.empty() && (!notes.empty() || !points.empty())) {
        std::vector<std::vector<size_t>> moved(m_smf.tracks.size());
        const auto mark = [&](int smfTrack, size_t index) {
            if (smfTrack >= 0 && smfTrack < int(moved.size()))
                moved[size_t(smfTrack)].push_back(index);
        };
        for (const DocNote &note : notes) {
            mark(note.smfTrack, note.onIndex);
            if (!note.unterminated())
                mark(note.smfTrack, note.endIndex);
        }
        for (const DocLanePoint &pt : points)
            mark(pt.smfTrack, pt.index);
        // Ascending + deduped so the raw re-inserts below mirror the removals
        // exactly and same-tick events keep their relative order.
        for (std::vector<size_t> &indices : moved) {
            std::sort(indices.begin(), indices.end());
            indices.erase(std::unique(indices.begin(), indices.end()), indices.end());
        }
        std::vector<PlannedNote> written;
        for (const DocNote &note : notes) {
            if (note.unterminated())
                continue;
            const uint64_t newTick = uint64_t(std::max<int64_t>(0, int64_t(note.tick) + dTick));
            written.push_back({note.engineTrack, note.key, newTick, newTick + note.duration});
        }
        std::vector<std::vector<size_t>> removals = moved;
        std::vector<EditOp> trims;
        resolveNoteOverlaps(written, notes, removals, trims);
        // All removals first (indices are read at apply time), then the events'
        // exact bytes re-inserted at the shifted ticks.
        for (size_t t = 0; t < m_smf.tracks.size(); t++)
            appendRemoveOps(ops, int(t), std::move(removals[t]));
        for (size_t t = 0; t < m_smf.tracks.size(); t++) {
            for (size_t index : moved[t]) {
                EditOp op;
                op.type = EditOp::InsertEvent;
                op.smfTrack = int(t);
                op.event = m_smf.tracks[t].events[index];
                op.event.tick = uint64_t(std::max<int64_t>(0, int64_t(op.event.tick) + dTick));
                op.preservesNoteId = op.event.isNoteOn();
                ops.push_back(op);
            }
        }
        ops.insert(ops.end(), trims.begin(), trims.end());
    }
    if (tempo.empty()) {
        pushEdit(tr("move range"), std::move(ops));
        return;
    }
    std::vector<TempoPoint> nextTempo = m_tempoPoints;
    std::set<uint64_t> moving;
    for (const TempoPoint &point : tempo)
        moving.insert(point.tick);
    std::erase_if(nextTempo, [&](const TempoPoint &point) { return moving.contains(point.tick); });
    for (const TempoPoint &point : tempo) {
        TempoPoint shifted = point;
        shifted.tick = uint64_t(std::max<int64_t>(0, int64_t(point.tick) + dTick));
        nextTempo.push_back(shifted);
    }
    pushEdit(tr("move range"), std::move(ops), std::move(nextTempo));
}
