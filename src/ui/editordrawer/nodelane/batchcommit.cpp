#include "ui/editordrawer/nodelane/batchcommit.h"

#include <algorithm>
#include <map>
#include <set>
#include <utility>

#include <QtGlobal>

#include "core/lanemoveplan.h"
#include "core/timedefaults.h"

namespace nodelane {
namespace {

std::vector<NodePointMove> lastMovesBySourceTick(const std::vector<NodePointMove> &moves)
{
    std::vector<NodePointMove> unique;
    std::set<uint64_t> seen;
    unique.reserve(moves.size());
    for (auto it = moves.crbegin(); it != moves.crend(); ++it) {
        if (seen.insert(it->fromTick).second)
            unique.push_back(*it);
    }
    std::reverse(unique.begin(), unique.end());
    return unique;
}

const TempoPoint *tempoAtTick(const std::vector<TempoPoint> &points, uint64_t tick)
{
    for (const TempoPoint &point : points) {
        if (point.tick == tick)
            return &point;
    }
    return nullptr;
}

TempoPoint tempoDestination(const TempoPoint &source, const NodePoint &to)
{
    const int currentBpm = qRound(CoreTimeDefaults::tempoBpm(source.microsecondsPerQuarterNote));
    TempoPoint destination{to.tick, source.microsecondsPerQuarterNote};
    if (to.value != currentBpm)
        destination.microsecondsPerQuarterNote =
            CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(to.value);
    return destination;
}

} // namespace

std::optional<TempoEdit> resolveTempoMoves(const SongDocument &document,
                                           const std::vector<NodePointMove> &moves)
{
    TempoEdit edit;
    if (moves.empty())
        return edit;
    const auto &tempoPoints = document.tempoPoints();
    for (const NodePointMove &move : moves) {
        if (!tempoAtTick(tempoPoints, move.fromTick))
            return std::nullopt;
    }
    const auto unique = lastMovesBySourceTick(moves);
    std::map<uint64_t, TempoPoint> addByTick;
    std::set<uint64_t> removedTicks;
    const auto removePoint = [&](const TempoPoint &point) {
        if (!removedTicks.insert(point.tick).second)
            return;
        edit.remove.push_back(point);
    };
    for (const NodePointMove &move : unique) {
        const TempoPoint *source = tempoAtTick(tempoPoints, move.fromTick);
        const TempoPoint destination = tempoDestination(*source, move.to);
        if (destination == *source)
            continue;
        removePoint(*source);
        addByTick[destination.tick] = destination;
    }
    for (const auto &entry : addByTick) {
        if (const TempoPoint *occupant = tempoAtTick(tempoPoints, entry.first))
            removePoint(*occupant);
        edit.add.push_back(entry.second);
    }
    return edit;
}

std::optional<CcResolvedMoves> resolveCcMoves(const SongDocument &document, int engineTrack,
                                              uint8_t controller,
                                              const std::vector<NodePointMove> &moves)
{
    CcResolvedMoves resolved;
    resolved.write.engineTrack = engineTrack;
    resolved.write.cc = controller;
    if (moves.empty())
        return resolved;
    const auto raw = document.lanePoints(engineTrack, controller);
    std::vector<LaneMovePoint> existing;
    existing.reserve(raw.size());
    std::map<uint64_t, std::vector<size_t>> idsByTick;
    for (size_t id = 0; id < raw.size(); ++id) {
        existing.push_back({raw[id].tick, raw[id].value});
        idsByTick[raw[id].tick].push_back(id);
    }
    for (const NodePointMove &move : moves) {
        const auto found = idsByTick.find(move.fromTick);
        if (found == idsByTick.end() || found->second.empty())
            return std::nullopt;
    }
    std::vector<LaneMoveRequest> requests;
    for (const NodePointMove &move : moves) {
        const auto &group = idsByTick[move.fromTick];
        const int newValue = CoreTimeDefaults::clampLaneValue(controller, move.to.value);
        for (size_t index = 0; index < group.size(); ++index) {
            const size_t id = group[index];
            const int value = index + 1 == group.size() ? newValue : existing[id].value;
            requests.push_back({id, move.to.tick, value});
        }
    }
    const auto plan = planLaneMoves(existing, requests);
    if (!plan)
        return std::nullopt;
    std::set<size_t> removed;
    const auto removeId = [&](size_t id) {
        if (!removed.insert(id).second)
            return;
        resolved.removePoints.push_back(raw[id]);
    };
    for (size_t id : plan->removeIds)
        removeId(id);
    for (const LaneMoveWrite &write : plan->writes) {
        removeId(write.sourceId);
        resolved.write.points.push_back({write.tick, write.value});
    }
    return resolved;
}

std::optional<SongDocument::RangeEdit>
resolveBatchDeletes(const SongDocument &document, const std::vector<uint64_t> &tempoTicks,
                    const std::vector<CcDeleteRequest> &ccDeletes)
{
    SongDocument::RangeEdit edit;
    const auto &tempoPoints = document.tempoPoints();
    std::set<uint64_t> seenTempo;
    for (uint64_t tick : tempoTicks) {
        const TempoPoint *point = tempoAtTick(tempoPoints, tick);
        if (!point)
            return std::nullopt;
        if (!seenTempo.insert(tick).second)
            continue;
        edit.removeTempo.push_back(*point);
    }
    for (const CcDeleteRequest &lane : ccDeletes) {
        const auto raw = document.lanePoints(lane.engineTrack, lane.controller);
        std::map<uint64_t, std::vector<DocLanePoint>> groups;
        for (const DocLanePoint &point : raw)
            groups[point.tick].push_back(point);
        std::set<uint64_t> seen;
        for (uint64_t tick : lane.ticks) {
            const auto found = groups.find(tick);
            if (found == groups.end() || found->second.empty())
                return std::nullopt;
            if (!seen.insert(tick).second)
                continue;
            edit.removePoints.insert(edit.removePoints.end(), found->second.begin(),
                                     found->second.end());
        }
    }
    return edit;
}

void appendResolvedTempoMoves(SongDocument::RangeEdit &edit, const TempoEdit &resolved)
{
    edit.removeTempo.insert(edit.removeTempo.end(), resolved.remove.begin(), resolved.remove.end());
    edit.addTempo.insert(edit.addTempo.end(), resolved.add.begin(), resolved.add.end());
}

void appendResolvedCcMoves(SongDocument::RangeEdit &edit, const CcResolvedMoves &resolved)
{
    edit.removePoints.insert(edit.removePoints.end(), resolved.removePoints.begin(),
                             resolved.removePoints.end());
    if (!resolved.write.points.empty())
        edit.addPoints.push_back(resolved.write);
}

} // namespace nodelane
