#include "ui/songview/pitchenvelopemapping.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <map>
#include <tuple>

namespace {

uint64_t saturatedAdd(uint64_t value, uint64_t offset)
{
    return value > std::numeric_limits<uint64_t>::max() - offset
               ? std::numeric_limits<uint64_t>::max()
               : value + offset;
}

} // namespace

namespace songview {
namespace pitch_envelope {

uint64_t creationEndTick(uint64_t startTick, uint64_t windowTicks)
{
    return saturatedAdd(startTick, windowTicks);
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

LaneWrite compileLaneWrite(const std::vector<CurveSample> &curve,
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
    const auto last =
        std::unique(spans.begin(), spans.end(), [](const Projection &lhs, const Projection &rhs) {
            return lhs.startTick == rhs.startTick;
        });
    spans.erase(last, spans.end());
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
        const uint64_t span = projection.endTick - projection.startTick;
        for (const CurveSample &sample : curve) {
            if (sample.offsetTick <= 0.0)
                continue;
            const uint64_t offset = uint64_t(std::llround(sample.offsetTick));
            if (offset >= span)
                continue;
            projected[projection.startTick + offset] =
                semitonesToBend(sample.semitones, projection.bendRange);
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
