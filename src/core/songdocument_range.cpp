#include "songdocument.h"

#include <algorithm>
#include <set>
#include <utility>
#include <vector>

void SongDocument::applyRangeEdit(const QString &text, const RangeEdit &edit)
{
    if (edit.empty())
        return;
    std::vector<EditOp> ops;
    const int targetEngineTrackCount =
        std::clamp(edit.minimumEngineTrackCount, engineTrackCount(), 16);
    std::vector<int> engineToSmf = m_engineToSmf;
    std::vector<uint8_t> engineChannels = m_engineChannel;
    bool usedChannels[16] = {};
    for (uint8_t channel : engineChannels)
        usedChannels[channel] = true;
    int nextSmfTrack = int(m_smf.tracks.size());
    for (int engineTrack = engineTrackCount(); engineTrack < targetEngineTrackCount;
         ++engineTrack) {
        int channel = 0;
        while (usedChannels[channel])
            ++channel;
        usedChannels[channel] = true;
        EditOp insertTrack;
        insertTrack.type = EditOp::InsertTrack;
        insertTrack.smfTrack = nextSmfTrack;
        ops.push_back(insertTrack);
        engineToSmf.push_back(nextSmfTrack);
        engineChannels.push_back(uint8_t(channel));
        const bool writesInitialVoice = std::any_of(
            edit.addPoints.begin(), edit.addPoints.end(), [&](const RangeEdit::LaneWrite &write) {
                return write.engineTrack == engineTrack && write.cc == DOC_CC_VOICE &&
                       std::any_of(write.points.begin(), write.points.end(),
                                   [](const LanePointValue &point) { return point.tick == 0; });
            });
        if (!writesInitialVoice) {
            EditOp seed;
            seed.type = EditOp::InsertEvent;
            seed.smfTrack = nextSmfTrack;
            seed.event = makeChannelEvent(0xC, uint8_t(channel), 0, 0, 0);
            ops.push_back(seed);
        }
        ++nextSmfTrack;
    }
    std::vector<EditOp> trims;
    if (!m_smf.tracks.empty()) {
        std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
        for (const DocNote &note : edit.removeNotes) {
            if (note.smfTrack < 0 || note.smfTrack >= int(removals.size()))
                continue;
            removals[size_t(note.smfTrack)].push_back(note.onIndex);
            if (!note.unterminated())
                removals[size_t(note.smfTrack)].push_back(note.endIndex);
        }
        // Candidate descriptor point identities to remove plus every
        // descriptor lane write of the range, collected per track. Each
        // affected track is then rewritten exactly once; the flat patches
        // merge with the ordinary removals/insertions into one atomic
        // command.
        std::vector<std::vector<uint64_t>> removeCandidates(m_smf.tracks.size());
        std::vector<std::vector<xcmd::PointWrite>> writes(m_smf.tracks.size());
        for (const DocLanePoint &pt : edit.removePoints) {
            if (pt.smfTrack < 0 || pt.smfTrack >= int(removeCandidates.size()))
                continue;
            removeCandidates[size_t(pt.smfTrack)].push_back(uint64_t(pt.index));
        }
        for (const RangeEdit::LaneWrite &lw : edit.addPoints) {
            const int smfTrack = smfTrackFor(lw.engineTrack);
            if (smfTrack < 0)
                continue;
            if (const xcmd::Descriptor *descriptor = xcmd::descriptorForLane(lw.cc)) {
                std::vector<xcmd::PointWrite> &trackWrites = writes[size_t(smfTrack)];
                for (const LanePointValue &point : lw.points) {
                    const int clamped = std::clamp(point.value, int(descriptor->minimumValue),
                                                   int(descriptor->maximumValue));
                    trackWrites.push_back({point.tick, lw.cc, uint8_t(clamped),
                                           uint8_t(lw.engineTrack), channelFor(lw.engineTrack)});
                }
            }
        }
        // One rewrite per affected track. Only tracks with remove candidates
        // need the projection — it classifies each candidate (a known
        // descriptor point leaves through the canonical plan, a stale
        // identity as a plain raw removal). A rejection (unknown identity,
        // opaque-span destination) fails the whole command before anything
        // is pushed.
        std::vector<EditOp> xcmdInserts;
        for (size_t track = 0; track < m_smf.tracks.size(); track++) {
            if (removeCandidates[track].empty() && writes[track].empty())
                continue;
            const std::vector<xcmd::Event> events = xcmdEvents(int(track));
            std::vector<uint64_t> removeIdentities;
            if (!removeCandidates[track].empty()) {
                const xcmd::Projection projection = xcmd::projectEvents(events);
                for (const uint64_t index : removeCandidates[track]) {
                    bool known = false;
                    for (const xcmd::Point &point : projection.points) {
                        if (point.index == index) {
                            known = true;
                            break;
                        }
                    }
                    if (known)
                        removeIdentities.push_back(index);
                    else
                        removals[track].push_back(size_t(index));
                }
            }
            if (removeIdentities.empty() && writes[track].empty())
                continue;
            const auto patch = xcmd::rewritePoints(events, removeIdentities, writes[track]);
            if (!patch)
                return; // semantics unsatisfiable: fail without mutation
            appendXcmdPatchOps(removals, xcmdInserts, int(track), *patch);
        }
        std::vector<PlannedNote> written;
        for (const RangeEdit::TrackNotes &tn : edit.addNotes) {
            for (const NewNote &note : tn.notes)
                written.push_back({tn.engineTrack, note.key, note.tick,
                                   note.tick + std::max<uint32_t>(1, note.duration)});
        }
        resolveNoteOverlaps(written, edit.removeNotes, removals, trims);
        // All removals first (per SMF track, descending — appendRemoveOps sorts
        // and dedups), so every recorded index stays valid at apply time.
        for (size_t t = 0; t < m_smf.tracks.size(); t++)
            appendRemoveOps(ops, int(t), std::move(removals[t]));
        ops.insert(ops.end(), xcmdInserts.begin(), xcmdInserts.end());
    }
    for (const RangeEdit::TrackNotes &tn : edit.addNotes) {
        if (tn.engineTrack < 0 || tn.engineTrack >= int(engineToSmf.size()))
            continue;
        const int smfTrack = engineToSmf[size_t(tn.engineTrack)];
        const uint8_t channel = engineChannels[size_t(tn.engineTrack)];
        for (const NewNote &note : tn.notes)
            appendNoteInsertOps(ops, smfTrack, channel, note.tick, note.key, note.duration,
                                note.velocity);
    }
    for (const RangeEdit::LaneWrite &lw : edit.addPoints) {
        if (lw.engineTrack < 0 || lw.engineTrack >= int(engineToSmf.size()))
            continue;
        if (xcmd::descriptorForLane(lw.cc))
            continue; // already emitted through the canonical plan above
        const int smfTrack = engineToSmf[size_t(lw.engineTrack)];
        const uint8_t channel = engineChannels[size_t(lw.engineTrack)];
        for (const LanePointValue &pt : lw.points) {
            EditOp op;
            op.type = EditOp::InsertEvent;
            op.smfTrack = smfTrack;
            op.event = makeLaneEvent(lw.cc, channel, pt.tick, pt.value);
            ops.push_back(op);
        }
    }
    ops.insert(ops.end(), trims.begin(), trims.end());
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
        std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
        const auto mark = [&](int smfTrack, size_t index) {
            if (smfTrack >= 0 && smfTrack < int(moved.size())) {
                moved[size_t(smfTrack)].push_back(index);
                removals[size_t(smfTrack)].push_back(index);
            }
        };
        for (const DocNote &note : notes) {
            mark(note.smfTrack, note.onIndex);
            if (!note.unterminated())
                mark(note.smfTrack, note.endIndex);
        }
        // Candidate descriptor lane point identities to move, collected per
        // track. Each affected track is then rewritten exactly once: the
        // projection classifies every candidate — a known descriptor point
        // leaves and lands as explicit selector+payload pairs at its shifted
        // tick, an identity that no longer projects shifts as a plain
        // exact-byte event — and supplies the writes in scan order, so a
        // same-tick same-lane collision is won by the stream-later point.
        std::vector<std::vector<uint64_t>> candidates(m_smf.tracks.size());
        for (const DocLanePoint &pt : points) {
            if (pt.smfTrack < 0 || pt.smfTrack >= int(m_smf.tracks.size()))
                continue;
            candidates[size_t(pt.smfTrack)].push_back(uint64_t(pt.index));
        }
        // Patch inserts are deferred until every fixed-index removal has
        // been appended: applyOps reads removal indices at apply time, so an
        // earlier insert would shift them and erase unrelated events.
        std::vector<EditOp> xcmdInserts;
        for (size_t t = 0; t < m_smf.tracks.size(); t++) {
            std::vector<uint64_t> &identities = candidates[t];
            if (identities.empty())
                continue;
            const std::vector<xcmd::Event> events = xcmdEvents(int(t));
            const xcmd::Projection projection = xcmd::projectEvents(events);
            std::vector<uint64_t> removeIdentities;
            for (const uint64_t index : identities) {
                bool known = false;
                for (const xcmd::Point &point : projection.points) {
                    if (point.index == index) {
                        known = true;
                        break;
                    }
                }
                if (known)
                    removeIdentities.push_back(index);
                else
                    mark(int(t), size_t(index));
            }
            if (removeIdentities.empty())
                continue;
            std::sort(removeIdentities.begin(), removeIdentities.end());
            removeIdentities.erase(std::unique(removeIdentities.begin(), removeIdentities.end()),
                                   removeIdentities.end());
            std::vector<xcmd::PointWrite> writes;
            for (const xcmd::Point &point : projection.points) {
                if (!std::binary_search(removeIdentities.begin(), removeIdentities.end(),
                                        point.index))
                    continue;
                writes.push_back({uint64_t(std::max<int64_t>(0, int64_t(point.tick) + dTick)),
                                  point.lane, uint8_t(point.value), point.stream, point.channel});
            }
            const auto patch = xcmd::rewritePoints(events, removeIdentities, writes);
            if (!patch)
                return; // semantics unsatisfiable: fail without mutation
            appendXcmdPatchOps(removals, xcmdInserts, int(t), *patch);
        }
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
        std::vector<EditOp> trims;
        resolveNoteOverlaps(written, notes, removals, trims);
        // All removals first (indices are read at apply time), then the
        // canonical XCMD emissions, then the events' exact bytes re-inserted
        // at the shifted ticks.
        for (size_t t = 0; t < m_smf.tracks.size(); t++)
            appendRemoveOps(ops, int(t), std::move(removals[t]));
        ops.insert(ops.end(), xcmdInserts.begin(), xcmdInserts.end());
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
    std::set<uint32_t> moving;
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