#include "lanemoveplan.h"

#include <map>

std::optional<LaneMovePlan> planLaneMoves(const std::vector<LaneMovePoint> &existing,
                                          const std::vector<LaneMoveRequest> &requests)
{
    if (requests.empty())
        return LaneMovePlan{};
    for (const LaneMoveRequest &request : requests) {
        if (request.sourceId >= existing.size())
            return std::nullopt;
    }
    std::vector<LaneMoveRequest> unique;
    unique.reserve(requests.size());
    std::map<size_t, size_t> indexBySource;
    for (const LaneMoveRequest &request : requests) {
        const auto [it, inserted] = indexBySource.emplace(request.sourceId, unique.size());
        if (inserted)
            unique.push_back(request);
        else
            unique[it->second] = request;
    }
    std::map<uint64_t, uint64_t> destBySourceTick;
    for (const LaneMoveRequest &request : unique)
        destBySourceTick[existing[request.sourceId].tick] = request.toTick;
    for (LaneMoveRequest &request : unique)
        request.toTick = destBySourceTick[existing[request.sourceId].tick];
    std::map<uint64_t, uint64_t> winningSourceTick;
    for (const LaneMoveRequest &request : unique)
        winningSourceTick[request.toTick] = existing[request.sourceId].tick;
    std::vector<char> winning(existing.size(), 0);
    for (const LaneMoveRequest &request : unique) {
        if (winningSourceTick[request.toTick] == existing[request.sourceId].tick)
            winning[request.sourceId] = 1;
    }
    std::vector<char> remove(existing.size(), 0);
    LaneMovePlan plan;
    plan.writes.reserve(unique.size());
    for (const LaneMoveRequest &request : unique) {
        if (!winning[request.sourceId]) {
            remove[request.sourceId] = 1;
            continue;
        }
        const LaneMovePoint &source = existing[request.sourceId];
        if (request.toTick == source.tick && request.toValue == source.value)
            continue;
        plan.writes.push_back({request.sourceId, request.toTick, request.toValue});
        if (request.toTick != source.tick)
            remove[request.sourceId] = 1;
    }
    for (const auto &entry : winningSourceTick) {
        for (size_t id = 0; id < existing.size(); ++id) {
            if (existing[id].tick == entry.first && !winning[id])
                remove[id] = 1;
        }
    }
    for (size_t id = 0; id < existing.size(); ++id) {
        if (remove[id])
            plan.removeIds.push_back(id);
    }
    return plan;
}
