// ---------------------------------------------------------------------------
// SongDocument-owned lane operations.
//
// This TU owns every lane-point mutation surface of SongDocument: the XCMD
// adapter (xcmdEvents / appendXcmdPatchOps) and the add / write / move /
// delete lane methods over both descriptor lanes (0x08/0x09, through the
// neutral event/plan machinery in core/xcmd) and plain CC/voice/bend lanes.
// Descriptor edits are planned once per affected SMF track: callers build
// decoder rows, project known points, rewrite points via rewritePoints, and
// hand the resulting flat Patch to the op translator — no selector- or
// epoch-state reasoning lives here. songdocument.cpp stays the orchestrator
// for everything else (notes, tempo, tracks, raw events).
// ---------------------------------------------------------------------------

#include "songdocument.h"

#include <algorithm>
#include <set>
#include <utility>

#include "core/lanemoveplan.h"
#include "core/timedefaults.h"

SmfEvent SongDocument::makeLaneEvent(uint8_t cc, uint8_t channel, uint64_t tick, int value) const
{
    value = CoreTimeDefaults::clampLaneValue(cc, value);
    if (cc == DOC_CC_BEND) {
        const auto bend14 = value - CoreTimeDefaults::kMinBendValue;
        return makeChannelEvent(0xE, channel, tick, uint8_t(bend14 & 0x7F),
                                uint8_t((bend14 >> 7) & 0x7F));
    }
    if (cc == DOC_CC_VOICE)
        return makeChannelEvent(0xC, channel, tick, uint8_t(value), 0);
    return makeChannelEvent(0xB, channel, tick, cc, uint8_t(value));
}

void SongDocument::appendLaneInsertOps(std::vector<EditOp> &ops, int smfTrack, uint8_t channel,
                                       uint8_t cc, uint64_t tick, int value) const
{
    // Descriptor lanes never reach this path: their writes go through
    // rewritePoints, which emits the canonical selector+payload pair.
    EditOp op;
    op.type = EditOp::InsertEvent;
    op.smfTrack = smfTrack;
    op.event = makeLaneEvent(cc, channel, tick, value);
    ops.push_back(std::move(op));
}

std::vector<xcmd::Event> SongDocument::xcmdEvents(int smfTrack) const
{
    const auto &events = m_smf.tracks[size_t(smfTrack)].events;
    // Stream identity mirrors playback: MidiTimeline::build maps each SMF
    // chunk to one engine track and the driver keys its extendedCommand
    // state per track, so all of a chunk's XCMD traffic decodes as a single
    // stream no matter which MIDI channel each CC carries. A chunk without
    // an engine slot is never played; a per-track constant keeps its
    // projection self-consistent.
    const int engine = engineTrackForChunk(smfTrack);
    const uint8_t stream = uint8_t(engine >= 0 ? engine : (smfTrack & 0x0F));
    std::vector<xcmd::Event> rows;
    rows.reserve(events.size());
    for (size_t index = 0; index < events.size(); ++index) {
        const SmfEvent &event = events[index];
        if (!event.isChannel() || event.typeNibble() != 0xB)
            continue;
        xcmd::Event row;
        row.index = uint64_t(index);
        row.tick = event.tick;
        row.stream = stream;
        row.controller = uint8_t(event.data0);
        row.value = uint8_t(event.data1);
        row.channel = uint8_t(event.channel());
        rows.push_back(row);
    }
    return rows;
}

void SongDocument::appendXcmdPatchOps(std::vector<std::vector<size_t>> &removals,
                                      std::vector<EditOp> &ops, int smfTrack,
                                      const xcmd::Patch &patch) const
{
    removals[size_t(smfTrack)].reserve(removals[size_t(smfTrack)].size() +
                                       patch.removeEvents.size());
    for (const uint64_t index : patch.removeEvents)
        removals[size_t(smfTrack)].push_back(size_t(index));
    for (const xcmd::Emission &emission : patch.inserts) {
        EditOp op;
        op.type = EditOp::InsertEvent;
        op.smfTrack = smfTrack;
        if (emission.sourceIndex != SIZE_MAX) {
            // Verbatim re-insertion: copy the named event, re-stamp its tick.
            op.event = m_smf.tracks[size_t(smfTrack)].events[size_t(emission.sourceIndex)];
            op.event.tick = emission.tick;
            op.preservesNoteId = false;
        } else {
            // Canonical emission on the patch's MIDI channel.
            op.event = makeChannelEvent(0xB, emission.channel, emission.tick, emission.controller,
                                        emission.value);
        }
        ops.push_back(std::move(op));
    }
}

void SongDocument::addLanePoint(int engineTrack, uint8_t cc, uint64_t tick, int value)
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0 || m_smf.tracks.empty())
        return;
    if (const xcmd::Descriptor *descriptor = xcmd::descriptorForLane(cc)) {
        // Logical write through the canonical planner: the existing point on
        // the tick leaves, the destination lands as an explicit
        // selector+payload pair, and any touched epoch is rebuilt.
        const std::vector<xcmd::Event> events = xcmdEvents(smfTrack);
        const xcmd::Projection projection = xcmd::projectEvents(events);
        std::vector<uint64_t> removeIdentities;
        for (const xcmd::Point &point : projection.points) {
            if (point.lane == cc && point.tick == tick)
                removeIdentities.push_back(point.index);
        }
        const int clamped =
            std::clamp(value, int(descriptor->minimumValue), int(descriptor->maximumValue));
        const std::vector<xcmd::PointWrite> writes{
            {tick, cc, uint8_t(clamped), uint8_t(engineTrack), channelFor(engineTrack)}};
        const auto patch = xcmd::rewritePoints(events, removeIdentities, writes);
        if (!patch)
            return; // semantics unsatisfiable: fail without mutation
        std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
        std::vector<EditOp> ops;
        std::vector<EditOp> insertions;
        appendXcmdPatchOps(removals, insertions, smfTrack, *patch);
        for (size_t track = 0; track < m_smf.tracks.size(); track++)
            appendRemoveOps(ops, int(track), std::move(removals[track]));
        for (EditOp &insertion : insertions)
            ops.push_back(std::move(insertion));
        pushEdit(tr("add automation point"), std::move(ops));
        return;
    }
    std::vector<EditOp> ops;
    // A point already on the tick is replaced, not shadowed: only the last of
    // same-tick duplicates is audible, so keeping the old one would just
    // leave an inert ghost under the new value.
    std::vector<size_t> replaced;
    for (const DocLanePoint &pt : lanePoints(engineTrack, cc)) {
        if (pt.tick == tick)
            replaced.push_back(pt.index);
    }
    appendRemoveOps(ops, smfTrack, std::move(replaced));
    appendLaneInsertOps(ops, smfTrack, channelFor(engineTrack), cc, tick, value);
    pushEdit(cc == DOC_CC_VOICE ? tr("add voice change") : tr("add automation point"),
             std::move(ops));
}

void SongDocument::writeLanePoints(int engineTrack, uint8_t cc, uint64_t tickBegin,
                                   uint64_t tickEnd, const std::vector<LanePointValue> &points)
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0 || m_smf.tracks.empty())
        return;
    if (const xcmd::Descriptor *descriptor = xcmd::descriptorForLane(cc)) {
        const std::vector<xcmd::Event> events = xcmdEvents(smfTrack);
        const xcmd::Projection projection = xcmd::projectEvents(events);
        std::vector<uint64_t> removeIdentities;
        for (const xcmd::Point &point : projection.points) {
            if (point.lane == cc && point.tick >= tickBegin && point.tick <= tickEnd)
                removeIdentities.push_back(point.index);
        }
        if (removeIdentities.empty() && points.empty())
            return;
        std::vector<xcmd::PointWrite> writes;
        writes.reserve(points.size());
        for (const LanePointValue &point : points) {
            const int clamped = std::clamp(point.value, int(descriptor->minimumValue),
                                           int(descriptor->maximumValue));
            writes.push_back(
                {point.tick, cc, uint8_t(clamped), uint8_t(engineTrack), channelFor(engineTrack)});
        }
        const auto patch = xcmd::rewritePoints(events, removeIdentities, writes);
        if (!patch)
            return; // semantics unsatisfiable: fail without mutation
        std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
        std::vector<EditOp> ops;
        std::vector<EditOp> insertions;
        appendXcmdPatchOps(removals, insertions, smfTrack, *patch);
        for (size_t track = 0; track < m_smf.tracks.size(); track++)
            appendRemoveOps(ops, int(track), std::move(removals[track]));
        for (EditOp &insertion : insertions)
            ops.push_back(std::move(insertion));
        pushEdit(tr("draw automation points"), std::move(ops));
        return;
    }
    std::vector<EditOp> ops;
    // Points already inside the swept range are overwritten by the gesture.
    std::vector<size_t> overwritten;
    for (const DocLanePoint &pt : lanePoints(engineTrack, cc)) {
        if (pt.tick >= tickBegin && pt.tick <= tickEnd)
            overwritten.push_back(pt.index);
    }
    if (overwritten.empty() && points.empty())
        return;
    appendRemoveOps(ops, smfTrack, std::move(overwritten));
    const uint8_t channel = channelFor(engineTrack);
    for (const LanePointValue &point : points)
        appendLaneInsertOps(ops, smfTrack, channel, cc, point.tick, point.value);
    pushEdit(tr("draw automation points"), std::move(ops));
}

void SongDocument::moveLanePoints(const std::vector<LanePointMove> &moves)
{
    if (moves.empty() || m_smf.tracks.empty())
        return;
    struct LaneRequests {
        int engineTrack = -1;
        uint8_t cc = 0;
        std::vector<LaneMoveRequest> requests;
        std::vector<DocLanePoint> existingPoints;
        std::vector<LaneMovePoint> existing;
    };
    std::vector<LaneRequests> lanes;
    std::set<std::pair<int, size_t>> sourceIndices;
    // Batch lanes are few (one per (engineTrack, cc) named by the moves), so
    // a linear slot lookup beats a map. The lane's point snapshot is taken
    // once per slot. For descriptor lanes lanePoints is exactly the local
    // projection; for plain lanes it is the raw CC scan.
    const auto laneSlot = [&lanes, this](int engineTrack, uint8_t cc) -> size_t {
        for (size_t i = 0; i < lanes.size(); ++i) {
            if (lanes[i].engineTrack == engineTrack && lanes[i].cc == cc)
                return i;
        }
        LaneRequests lane;
        lane.engineTrack = engineTrack;
        lane.cc = cc;
        lane.existingPoints = lanePoints(engineTrack, cc);
        lane.existing.reserve(lane.existingPoints.size());
        for (const DocLanePoint &point : lane.existingPoints)
            lane.existing.push_back({point.tick, point.value});
        lanes.push_back(std::move(lane));
        return lanes.size() - 1;
    };
    size_t validCount = 0;
    uint8_t singularCc = 0;
    for (const LanePointMove &move : moves) {
        const int smfTrack = smfTrackFor(move.engineTrack);
        if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()) ||
            move.point.smfTrack != smfTrack ||
            move.point.index >= m_smf.tracks[size_t(smfTrack)].events.size())
            continue;
        const SmfEvent &source = m_smf.tracks[size_t(smfTrack)].events[move.point.index];
        // Descriptor-lane identities are trusted as-is: the caller resolved
        // them against this document state and the per-track plan below
        // re-validates every identity before anything is pushed (a stale or
        // cross-lane identity rejects the whole batch). Plain lanes have no
        // planner, so their bytes are verified here.
        if (!xcmd::isLaneController(move.cc) &&
            (!laneEventMatches(source, move.cc) || source.tick != move.point.tick ||
             laneValue(source, move.cc) != move.point.value))
            continue;
        if (!sourceIndices.emplace(smfTrack, move.point.index).second)
            continue;
        LaneRequests &lane = lanes[laneSlot(move.engineTrack, move.cc)];
        size_t sourceId = lane.existingPoints.size();
        for (size_t id = 0; id < lane.existingPoints.size(); ++id) {
            if (lane.existingPoints[id].smfTrack == move.point.smfTrack &&
                lane.existingPoints[id].index == move.point.index) {
                sourceId = id;
                break;
            }
        }
        if (sourceId >= lane.existingPoints.size())
            continue;
        lane.requests.push_back({sourceId, move.newTick, move.newValue});
        singularCc = move.cc;
        ++validCount;
    }
    if (lanes.empty())
        return;
    std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
    std::vector<EditOp> modifications;
    std::vector<EditOp> insertions;
    std::vector<std::vector<uint64_t>> xcmdRemovals(m_smf.tracks.size());
    std::vector<std::vector<xcmd::PointWrite>> xcmdWrites(m_smf.tracks.size());
    for (const LaneRequests &lane : lanes) {
        const auto plan = planLaneMoves(lane.existing, lane.requests);
        if (!plan || plan->empty())
            continue;
        const uint8_t channel = channelFor(lane.engineTrack);
        const bool xcmdLane = xcmd::isLaneController(lane.cc);
        for (size_t id : plan->removeIds) {
            const DocLanePoint &sourcePoint = lane.existingPoints[id];
            if (xcmdLane) {
                // The identity leaves; the destination is re-emitted
                // canonically by the per-track rewrite below.
                xcmdRemovals[size_t(sourcePoint.smfTrack)].push_back(uint64_t(sourcePoint.index));
            } else {
                removals[size_t(sourcePoint.smfTrack)].push_back(sourcePoint.index);
            }
        }
        for (const LaneMoveWrite &write : plan->writes) {
            const DocLanePoint &sourcePoint = lane.existingPoints[write.sourceId];
            if (xcmdLane) {
                const xcmd::Descriptor *descriptor = xcmd::descriptorForLane(lane.cc);
                const int clamped = std::clamp(write.value, int(descriptor->minimumValue),
                                               int(descriptor->maximumValue));
                xcmdWrites[size_t(sourcePoint.smfTrack)].push_back(
                    {write.tick, lane.cc, uint8_t(clamped), uint8_t(lane.engineTrack), channel});
                continue;
            }
            const SmfEvent event = makeLaneEvent(lane.cc, channel, write.tick, write.value);
            if (write.tick == sourcePoint.tick) {
                const SmfEvent &source =
                    m_smf.tracks[size_t(sourcePoint.smfTrack)].events[sourcePoint.index];
                if (event == source)
                    continue;
                EditOp modify;
                modify.type = EditOp::ModifyEvent;
                modify.smfTrack = sourcePoint.smfTrack;
                modify.index = sourcePoint.index;
                modify.event = event;
                modifications.push_back(std::move(modify));
                continue;
            }
            EditOp insert;
            insert.type = EditOp::InsertEvent;
            insert.smfTrack = sourcePoint.smfTrack;
            insert.event = event;
            insertions.push_back(std::move(insert));
        }
    }
    // One rewrite per track settles every XCMD move of the batch: removed
    // identities leave and every destination lands as an explicit
    // selector+payload pair. Any rejection aborts the whole batch.
    for (size_t track = 0; track < m_smf.tracks.size(); track++) {
        const auto &removeIdentities = xcmdRemovals[track];
        const auto &writes = xcmdWrites[track];
        if (removeIdentities.empty() && writes.empty())
            continue;
        const auto patch = xcmd::rewritePoints(xcmdEvents(int(track)), removeIdentities, writes);
        if (!patch)
            return; // semantics unsatisfiable: fail without mutation
        appendXcmdPatchOps(removals, insertions, int(track), *patch);
    }
    const bool hasRemovals =
        std::any_of(removals.begin(), removals.end(),
                    [](const std::vector<size_t> &indices) { return !indices.empty(); });
    if (modifications.empty() && insertions.empty() && !hasRemovals)
        return;
    std::vector<EditOp> ops;
    ops.reserve(modifications.size() + insertions.size() + moves.size());
    for (EditOp &modify : modifications)
        ops.push_back(std::move(modify));
    for (size_t track = 0; track < m_smf.tracks.size(); track++)
        appendRemoveOps(ops, int(track), std::move(removals[track]));
    for (EditOp &insert : insertions)
        ops.push_back(std::move(insert));
    const bool singular = validCount == 1;
    const QString text = singular && singularCc == DOC_CC_VOICE ? tr("change voice")
                         : singular                             ? tr("edit automation point")
                                                                : tr("edit automation points");
    pushEdit(text, std::move(ops));
}

void SongDocument::deleteLanePoints(int engineTrack, uint8_t cc,
                                    const std::vector<DocLanePoint> &points)
{
    Q_UNUSED(engineTrack);
    if (points.empty())
        return;
    std::vector<EditOp> ops;
    if (xcmd::isLaneController(cc)) {
        // Descriptor identities are trusted as-is: callers resolve them
        // fresh (deleteLanePoints receives one lane's points), and the
        // per-track rewrite validates every identity — a stale one rejects
        // the whole command before anything is pushed.
        std::vector<std::vector<uint64_t>> trackRemovals(m_smf.tracks.size());
        for (const DocLanePoint &pt : points) {
            if (pt.smfTrack < 0 || pt.smfTrack >= int(m_smf.tracks.size()))
                continue;
            trackRemovals[size_t(pt.smfTrack)].push_back(uint64_t(pt.index));
        }
        std::vector<EditOp> insertions;
        std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
        for (size_t track = 0; track < m_smf.tracks.size(); track++) {
            const auto &removeIdentities = trackRemovals[track];
            if (removeIdentities.empty())
                continue;
            const auto patch = xcmd::rewritePoints(xcmdEvents(int(track)), removeIdentities, {});
            if (!patch)
                return; // semantics unsatisfiable: fail without mutation
            appendXcmdPatchOps(removals, insertions, int(track), *patch);
        }
        for (size_t track = 0; track < m_smf.tracks.size(); track++)
            appendRemoveOps(ops, int(track), std::move(removals[track]));
        ops.insert(ops.end(), insertions.begin(), insertions.end());
    } else {
        for (size_t t = 0; t < m_smf.tracks.size(); t++) {
            std::vector<size_t> indices;
            for (const DocLanePoint &pt : points) {
                if (pt.smfTrack == int(t))
                    indices.push_back(pt.index);
            }
            appendRemoveOps(ops, int(t), std::move(indices));
        }
    }
    pushEdit(cc == DOC_CC_VOICE ? tr("delete voice change(s)") : tr("delete automation point(s)"),
             std::move(ops));
}