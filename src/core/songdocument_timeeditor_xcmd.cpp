#include "songdocument_timeeditor.hpp"

#include <algorithm>
#include <span>
#include <utility>

// ---------------------------------------------------------------------------
// TimeEditor XCMD reconciliation adapter.
//
// The generic remove/insertBlank/duplicate passes operate on raw events and
// know nothing of the XCMD protocol; this TU is the thin per-track adapter.
// For every track touched by the edit it:
//   1. collects the consumed protocol events the generic pass removes as
//      raw removals, and the consumed events it moves or duplicates as
//      operation-local source-indexed relocations/copies (records, threaded
//      through each edit pass — no member state);
//   2. plans one raw reconciliation through xcmd::reconcileRaw — known points rebuild
//      canonically as explicit selector+payload pairs, opaque blocks may
//      only be removed/moved/copied as a whole group, and interior landings
//      or partial edits reject;
//   3. translates the returned patch through the document's own adapter —
//      its removals replace the generic removals of protocol bytes, its
//      canonical insertions are CC SmfEvents on the patch channel, its
//      verbatim insertions re-insert the named original event with only its
//      tick restamped — and assembles it with the untouched non-XCMD ops.
//
// There is no selector-state simulation, no selector restoration, no opaque
// grouping policy, and no final-stream ordering policy here: an
// unrepresentable raw edit returns nullopt and the caller fails without
// mutating. Events come from SongDocument::xcmdEvents, the one adapter.
// ---------------------------------------------------------------------------

std::optional<std::vector<SongDocument::EditOp>> SongDocument::TimeEditor::xcmdAssembleOps(
    std::vector<std::vector<size_t>> removals, std::vector<SongDocument::EditOp> inserts,
    std::vector<SongDocument::EditOp> trackEnds, const std::vector<XcmdEventRecord> &records) const
{
    // Per-track raw ops the generic pass produced: removed consumed bytes,
    // relocated consumed bytes (moves and copies kept apart). A moved
    // byte's removal is implicit in the move op — naming it twice would be
    // a mixed-operation conflict.
    const size_t trackCount = m_document.m_smf.tracks.size();
    std::vector<std::vector<uint64_t>> rawRemovals(trackCount);
    std::vector<std::vector<xcmd::Relocation>> rawMoves(trackCount);
    std::vector<std::vector<xcmd::Relocation>> rawCopies(trackCount);
    std::vector<std::vector<size_t>> relocated(trackCount);
    for (const XcmdEventRecord &record : records) {
        if (record.smfTrack < 0 || record.smfTrack >= int(trackCount))
            continue;
        relocated[size_t(record.smfTrack)].push_back(record.eventIndex);
        const xcmd::Relocation relocation{uint64_t(record.eventIndex), record.newTick,
                                          record.channel};
        std::vector<xcmd::Relocation> &target =
            record.isCopy ? rawCopies[size_t(record.smfTrack)] : rawMoves[size_t(record.smfTrack)];
        target.push_back(relocation);
    }
    std::vector<std::vector<size_t>> plainRemovals(m_document.m_smf.tracks.size());
    for (size_t t = 0; t < removals.size(); ++t) {
        auto &plain = plainRemovals[t];
        plain.reserve(removals[t].size());
        for (size_t index : removals[t]) {
            if (std::find(relocated[t].begin(), relocated[t].end(), index) != relocated[t].end())
                continue; // the relocation op owns this byte's removal
            if (isXcmdConsumed(int(t), index))
                rawRemovals[t].push_back(uint64_t(index));
            else
                plain.push_back(index);
        }
    }
    // The patch replaces every generic insert that relocated a protocol
    // byte; everything else assembles untouched.
    std::vector<char> suppressed(inserts.size(), 0);
    for (const XcmdEventRecord &record : records)
        if (record.opIndex < suppressed.size())
            suppressed[record.opIndex] = 1;

    std::vector<std::vector<size_t>> finalRemovals(m_document.m_smf.tracks.size());
    std::vector<SongDocument::EditOp> finalInserts;
    finalInserts.reserve(inserts.size() + records.size() * 2);
    for (size_t t = 0; t < removals.size(); ++t) {
        const auto &rem = rawRemovals[t];
        const auto &mov = rawMoves[t];
        const auto &cop = rawCopies[t];
        if (rem.empty() && mov.empty() && cop.empty()) {
            finalRemovals[t] = std::move(plainRemovals[t]);
            continue;
        }
        const auto events = m_document.xcmdEvents(int(t));
        const std::optional<xcmd::Patch> patch = xcmd::reconcileRaw(events, rem, mov, cop);
        if (!patch)
            return std::nullopt; // unrepresentable: fail without mutating
        // The patch's removals are authoritative for protocol bytes (a
        // block rebuild removes its selector even when only a payload was
        // addressed); non-protocol removals are already in place. The
        // document's adapter appends both and translates the ordered
        // emissions.
        finalRemovals[t] = std::move(plainRemovals[t]);
        m_document.appendXcmdPatchOps(finalRemovals, finalInserts, int(t), *patch);
    }

    std::vector<SongDocument::EditOp> ops;
    for (size_t t = 0; t < m_document.m_smf.tracks.size(); t++)
        m_document.appendRemoveOps(ops, int(t), std::move(finalRemovals[t]));
    ops.insert(ops.end(), finalInserts.begin(), finalInserts.end());
    for (size_t i = 0; i < inserts.size(); ++i)
        if (!suppressed[i])
            ops.push_back(std::move(inserts[i]));
    ops.insert(ops.end(), trackEnds.begin(), trackEnds.end());
    return ops;
}

void SongDocument::TimeEditor::recordXcmdRelocation(int smfTrack, size_t eventIndex,
                                                    uint64_t newTick, size_t opIndex, bool isCopy,
                                                    std::vector<XcmdEventRecord> &records) const
{
    if (smfTrack < 0 || smfTrack >= int(m_xcmdConsumedOfEvent.size()))
        return;
    if (!isXcmdConsumed(smfTrack, eventIndex))
        return; // not protocol traffic: nothing for the planner to do
    const uint8_t channel = m_document.m_smf.tracks[size_t(smfTrack)].events[eventIndex].channel();
    records.push_back({smfTrack, eventIndex, newTick, opIndex, channel, isCopy});
}