#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

// Per-lane move planner over primitive existing points and requested source
// identities. Encodes destination collision once: every requested identity
// must exist, a same-source-tick group that is requested together keeps order,
// the last source group wins a destination tick, losing groups and unrelated
// destination occupants are removed, and an identity same-tick/value landing
// is a no-op. Output ids index `existing` so core can modify-vs-insert while
// RangeEdit can remove-then-write.
struct LaneMovePoint {
    uint64_t tick = 0;
    int value = 0;
};

struct LaneMoveRequest {
    size_t sourceId = 0;
    uint64_t toTick = 0;
    int toValue = 0;
};

struct LaneMoveWrite {
    size_t sourceId = 0;
    uint64_t tick = 0;
    int value = 0;
};

struct LaneMovePlan {
    std::vector<size_t> removeIds;
    std::vector<LaneMoveWrite> writes;

    bool empty() const noexcept { return removeIds.empty() && writes.empty(); }
};

std::optional<LaneMovePlan> planLaneMoves(const std::vector<LaneMovePoint> &existing,
                                          const std::vector<LaneMoveRequest> &requests);
