#pragma once

#include <cstdint>
#include <vector>

class MidiTimeline;

namespace songview {
namespace pitch_envelope {

constexpr double kWindowMilliseconds = 100.0;
constexpr double kPositiveBendScale = 8191.0;
constexpr double kNegativeBendScale = 8192.0;

struct Projection {
    uint64_t startTick = 0;
    uint64_t endTick = 0;
    uint64_t windowEndTick = 0;
    int bendRange = 0;
};

struct CurveSample {
    double milliseconds = 0.0;
    double semitones = 0.0;
};

struct LanePoint {
    uint64_t tick = 0;
    int value = 0;
};

struct LaneRange {
    uint64_t tickBegin = 0;
    uint64_t tickEnd = 0;
};

struct LaneWrite {
    std::vector<LaneRange> ranges;
    std::vector<LanePoint> points;
};

uint64_t creationEndTick(const MidiTimeline *timeline, uint64_t startTick);
double elapsedMilliseconds(const MidiTimeline *timeline, uint64_t startTick, uint64_t tick);
uint64_t tickForMilliseconds(const MidiTimeline *timeline, uint64_t startTick, uint64_t endTick,
                             double milliseconds);
double bendToSemitones(int bendValue, int bendRange);
int semitonesToBend(double semitones, int bendRange);
LaneWrite compileLaneWrite(const MidiTimeline *timeline, const std::vector<CurveSample> &curve,
                           const std::vector<Projection> &projections);

} // namespace pitch_envelope
} // namespace songview
