#pragma once

#include "core/tempo.h"

#include <cstdint>
#include <utility>
#include <vector>

namespace songview {

struct ClipNote {
    uint32_t relTick = 0;
    uint8_t key = 0;
    uint32_t duration = 0;
    uint8_t velocity = 0;
};

struct ClipTrack {
    int track = 0; // source engine track
    std::vector<ClipNote> notes;
};

struct ClipLane {
    int track = 0; // source engine track
    uint8_t cc = 0;
    std::vector<std::pair<uint32_t, int>> points; // (relative tick, value)
};

struct Clip {
    uint64_t span = 0;      // ticks covered; 0 = plain note clip
    bool wholeLane = false; // legacy format-1 field: encode always writes false, decode ignores it
    std::vector<ClipTrack> tracks;
    std::vector<ClipLane> lanes;
    std::vector<TempoPoint> tempo; // relative ticks, microseconds per quarter note

    bool empty() const { return tracks.empty() && lanes.empty() && tempo.empty(); }
};

} // namespace songview
