#include "ui/songview/pitchenvelopemapping.h"

#include "core/miditimeline.h"

#include <algorithm>
#include <cmath>
#include <iterator>
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

uint64_t saturatedMultiply(uint64_t value, uint64_t factor)
{
    return factor != 0 && value > std::numeric_limits<uint64_t>::max() / factor
               ? std::numeric_limits<uint64_t>::max()
               : value * factor;
}

uint64_t sixtyFourthBoundaryTick(uint64_t startTick, uint64_t index, uint64_t ticksPerBeat)
{
    constexpr uint64_t kSubdivisionPerQuarter = 16;
    const uint64_t whole = saturatedMultiply(index / kSubdivisionPerQuarter, ticksPerBeat);
    const uint64_t fractionalNumerator = index % kSubdivisionPerQuarter * ticksPerBeat;
    const uint64_t fractional =
        (fractionalNumerator + kSubdivisionPerQuarter / 2) / kSubdivisionPerQuarter;
    return saturatedAdd(startTick, saturatedAdd(whole, fractional));
}

double linearCurveValue(const std::vector<songview::pitch_envelope::CurveSample> &curve,
                        double milliseconds)
{
    if (curve.empty())
        return 0.0;
    const auto upper =
        std::upper_bound(curve.begin(), curve.end(), milliseconds,
                         [](double value, const songview::pitch_envelope::CurveSample &sample) {
                             return value < sample.milliseconds;
                         });
    if (upper == curve.begin())
        return upper->semitones;
    const auto lower = std::prev(upper);
    if (upper == curve.end() || upper->milliseconds <= lower->milliseconds)
        return lower->semitones;
    const double fraction =
        (milliseconds - lower->milliseconds) / (upper->milliseconds - lower->milliseconds);
    return lower->semitones + fraction * (upper->semitones - lower->semitones);
}

int effectiveM4ABend(int bend14)
{
    return bend14 >> 7;
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
        projected[projection.startTick] = 0;
        if (timeline && projection.endTick > projection.startTick) {
            const uint64_t ticksPerBeat = std::max<uint32_t>(1, timeline->ticksPerBeat);
            int previousEffectiveBend = 0;
            bool hasPendingSample = false;
            uint64_t pendingTick = 0;
            int pendingBend = 0;
            const auto writePendingSample = [&] {
                const int effectiveBend = effectiveM4ABend(pendingBend);
                if (effectiveBend != previousEffectiveBend)
                    projected[pendingTick] = pendingBend;
                previousEffectiveBend = effectiveBend;
            };
            for (uint64_t index = 1; index != std::numeric_limits<uint64_t>::max(); ++index) {
                const uint64_t tick =
                    sixtyFourthBoundaryTick(projection.startTick, index, ticksPerBeat);
                if (tick >= projection.endTick)
                    break;
                if (tick <= projection.startTick)
                    continue;
                const double milliseconds =
                    std::clamp(elapsedMilliseconds(timeline, projection.startTick, tick), 0.0,
                               kWindowMilliseconds);
                const int bend =
                    semitonesToBend(linearCurveValue(curve, milliseconds), projection.bendRange);
                if (hasPendingSample && tick == pendingTick) {
                    pendingBend = bend;
                    continue;
                }
                if (hasPendingSample)
                    writePendingSample();
                pendingTick = tick;
                pendingBend = bend;
                hasPendingSample = true;
            }
            if (hasPendingSample)
                writePendingSample();
        }
        projected[projection.endTick] = 0;
    }
    write.points.reserve(projected.size());
    for (const auto &[tick, value] : projected)
        write.points.push_back({tick, value});
    return write;
}

} // namespace pitch_envelope
} // namespace songview
