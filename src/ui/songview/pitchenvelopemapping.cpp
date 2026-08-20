#include "ui/songview/pitchenvelopemapping.h"

#include "core/miditimeline.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <map>
#include <tuple>

namespace {

uint64_t roundedTick(double tick)
{
    if (tick <= 0.0)
        return 0;
    if (tick >= double(std::numeric_limits<uint64_t>::max()))
        return std::numeric_limits<uint64_t>::max();
    return uint64_t(std::llround(tick));
}

uint64_t nextTick(uint64_t tick)
{
    return tick == std::numeric_limits<uint64_t>::max() ? tick : tick + 1;
}

uint64_t saturatedAdd(uint64_t value, uint64_t offset)
{
    return value > std::numeric_limits<uint64_t>::max() - offset
               ? std::numeric_limits<uint64_t>::max()
               : value + offset;
}
} // namespace

namespace songview {
namespace pitch_envelope {

uint64_t creationEndTick(const MidiTimeline *timeline, uint64_t startTick)
{
    if (!timeline || timeline->sampleRate <= 0.0)
        return nextTick(startTick);
    const uint64_t startSample = timeline->sampleForTick(startTick);
    const uint64_t windowSamples =
        uint64_t(std::llround(kWindowMilliseconds * timeline->sampleRate / 1000.0));
    const uint64_t endSample = saturatedAdd(startSample, windowSamples);
    return std::max(nextTick(startTick), roundedTick(timeline->tickForSample(endSample)));
}

double elapsedMilliseconds(const MidiTimeline *timeline, uint64_t startTick, uint64_t tick)
{
    if (!timeline || timeline->sampleRate <= 0.0)
        return 0.0;
    const uint64_t startSample = timeline->sampleForTick(startTick);
    const uint64_t sample = timeline->sampleForTick(tick);
    return sample >= startSample ? double(sample - startSample) * 1000.0 / timeline->sampleRate
                                 : 0.0;
}

uint64_t tickForMilliseconds(const MidiTimeline *timeline, uint64_t startTick, uint64_t endTick,
                             double milliseconds)
{
    if (!timeline || timeline->sampleRate <= 0.0)
        return startTick;
    const uint64_t startSample = timeline->sampleForTick(startTick);
    const auto sampleOffset = std::llround(milliseconds * timeline->sampleRate / 1000.0);
    const uint64_t offset = sampleOffset > 0 ? uint64_t(sampleOffset) : 0;
    const uint64_t sample = saturatedAdd(startSample, offset);
    return std::clamp(roundedTick(timeline->tickForSample(sample)), startTick, endTick);
}

double bendToSemitones(int bendValue, int bendRange)
{
    const int bend = std::clamp(bendValue, -int(kNegativeBendScale), int(kPositiveBendScale));
    if (bendRange <= 0 || bend == 0)
        return 0.0;
    const double scale = bend > 0 ? kPositiveBendScale : kNegativeBendScale;
    return double(bend) * double(bendRange) / scale;
}

int semitonesToBend(double semitones, int bendRange)
{
    if (bendRange <= 0 || semitones == 0.0)
        return 0;
    const double limited = std::clamp(semitones, -double(bendRange), double(bendRange));
    const double scale = limited > 0.0 ? kPositiveBendScale : kNegativeBendScale;
    return std::clamp(int(std::llround(limited * scale / double(bendRange))),
                      -int(kNegativeBendScale), int(kPositiveBendScale));
}

LaneWrite compileLaneWrite(const MidiTimeline *timeline, const std::vector<CurveSample> &curve,
                           const std::vector<Projection> &projections)
{
    std::vector<Projection> spans;
    spans.reserve(projections.size());
    for (const Projection &projection : projections) {
        if (projection.endTick >= projection.startTick)
            spans.push_back(projection);
    }
    std::sort(spans.begin(), spans.end(), [](const Projection &lhs, const Projection &rhs) {
        return std::tie(lhs.startTick, lhs.endTick, lhs.windowEndTick, lhs.bendRange) <
               std::tie(rhs.startTick, rhs.endTick, rhs.windowEndTick, rhs.bendRange);
    });
    LaneWrite write;
    write.ranges.reserve(spans.size());
    std::map<uint64_t, int> projected;
    for (const Projection &projection : spans) {
        if (write.ranges.empty() || projection.startTick > write.ranges.back().tickEnd) {
            write.ranges.push_back({projection.startTick, projection.endTick});
        } else {
            write.ranges.back().tickEnd = std::max(write.ranges.back().tickEnd, projection.endTick);
        }
        const uint64_t windowEndTick = std::max(projection.startTick, projection.windowEndTick);
        for (const CurveSample &sample : curve) {
            const double milliseconds = std::clamp(sample.milliseconds, 0.0, kWindowMilliseconds);
            const uint64_t tick =
                tickForMilliseconds(timeline, projection.startTick, windowEndTick, milliseconds);
            if (tick > projection.startTick && tick < projection.endTick)
                projected[tick] = semitonesToBend(sample.semitones, projection.bendRange);
        }
        projected[projection.startTick] = 0;
        projected[projection.endTick] = 0;
    }
    write.points.reserve(projected.size());
    for (const auto &[tick, value] : projected)
        write.points.push_back({tick, value});
    return write;
}

} // namespace pitch_envelope
} // namespace songview
