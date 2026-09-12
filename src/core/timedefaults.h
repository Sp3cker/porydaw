#pragma once

#include <algorithm>
#include <cstdint>
#include <limits>
#include <optional>

// Canonical musical position. A position is always a Tick — content streams
// (DocNote, TempoPoint, timeline events), SMF storage, and viewer fields all
// share it. Not a strong type: ticks mix with uint32_t durations, int64_t
// deltas, and start + duration sums that can exceed the Tick range.
using Tick = uint32_t;

namespace CoreTimeDefaults {
inline constexpr Tick kNoTick = std::numeric_limits<Tick>::max(); // absent loop; parse bound
inline constexpr Tick kMaxTick = Tick(kNoTick - 1);               // highest representable tick

// Mathematical tick + delta saturated to [0, kMaxTick]; never emits kNoTick.
// Headroom is classified before any arithmetic so INT64_MIN/INT64_MAX deltas
// and a sentinel-valued tick stay safe: no int64_t(tick) + delta overflow and
// no negation of INT64_MIN.
constexpr Tick shiftTickClamped(Tick tick, int64_t delta)
{
    if (delta <= -int64_t(tick))
        return 0;
    if (delta >= int64_t(kMaxTick) - int64_t(tick))
        return kMaxTick;
    return Tick(int64_t(tick) + delta);
}

// Floating position to Tick: NaN and non-positive inputs map to 0, finite
// values below double(kNoTick) truncate toward zero, and anything at or above
// double(kNoTick) (including +inf) saturates to kMaxTick. No out-of-range
// floating-to-integer conversion executes; rounding stays at each caller.
inline Tick tickFromDouble(double tick)
{
    if (!(tick > 0.0))
        return 0;
    if (tick >= double(kNoTick))
        return kMaxTick;
    return Tick(tick);
}

inline constexpr int kTempoBpm = 120;
inline constexpr int kMinTempoBpm = 20;
inline constexpr int kMaxTempoBpm = 255;
inline constexpr uint32_t kMicrosecondsPerMinute = 60'000'000;
inline constexpr uint32_t kDefaultTempoUspqn = 500000;

struct ControllerDefault {
    uint8_t cc;
    uint8_t value;
};

// mid2agb CC mnemonics used across the automation surface and kControllerDefaults.
inline constexpr uint8_t kCcModulation = 0x01; // MOD
inline constexpr uint8_t kCcPortamento = 0x05; // PORTAMENTO
inline constexpr uint8_t kCcVolume = 0x07;     // VOL
inline constexpr uint8_t kCcPan = 0x0A;        // PAN
inline constexpr uint8_t kCcBendRange = 0x14;  // BENDR
inline constexpr uint8_t kCcLfoSpeed = 0x15;   // LFOS
inline constexpr uint8_t kCcPwmCycle = 0x17;   // PWMC
inline constexpr uint8_t kCcPwmWidth = 0x19;   // PWMS

inline constexpr ControllerDefault kControllerDefaults[] = {
    {kCcModulation, 0}, // MOD
    {kCcPortamento, 0}, // PORTAMENTO
    {kCcVolume, 127},   // VOL
    {kCcPan, 64},       // PAN
    {kCcBendRange, 2},  // BENDR
    {kCcLfoSpeed, 22},  // LFOS
    {kCcPwmCycle, 0},   // PWMC
    {kCcPwmWidth, 0},   // PWMS
};

constexpr int controllerDefault(uint8_t cc)
{
    for (const ControllerDefault &entry : kControllerDefaults) {
        if (entry.cc == cc)
            return entry.value;
    }
    return -1;
}

inline constexpr int kMinCcValue = 0;
inline constexpr int kMaxCcValue = 127;
inline constexpr int kMinBendValue = -8192;
inline constexpr int kMaxBendValue = 8191;
inline constexpr uint8_t kLaneCcBend = 0xFF;  // pitch-bend events (0xE)
inline constexpr uint8_t kLaneCcVoice = 0xFD; // program changes (0xC)

constexpr int laneValueMinimum(uint8_t cc)
{
    return cc == kLaneCcBend ? kMinBendValue : kMinCcValue;
}

constexpr int laneValueMaximum(uint8_t cc)
{
    return cc == kLaneCcBend ? kMaxBendValue : kMaxCcValue;
}

constexpr int clampLaneValue(uint8_t cc, int value)
{
    return std::clamp(value, laneValueMinimum(cc), laneValueMaximum(cc));
}

// --- Automation-surface lane policies ---------------------------------------
//
// Synthetic engine-default node: mid2agb initializes a track with Volume=127
// and Pan=64 when the song never writes them, so the automation surface
// projects an implicit tick-0 node for exactly these two lanes. The projected
// value comes from controllerDefault(cc) above.
constexpr bool hasEngineDefaultNode(uint8_t cc)
{
    return cc == kCcVolume || cc == kCcPan;
}

// Synthetic tick-zero projection: returns the projected engine-default value
// when the lane currently shows the synthetic tick-0 node (default-eligible
// controller, no real tick-0 point superseding it), std::nullopt otherwise.
// One injection decision shared by the CC lane adapter and the batch
// move/delete resolvers.
template <typename Points>
constexpr std::optional<int> syntheticTickZero(uint8_t cc, const Points &points)
{
    if (!hasEngineDefaultNode(cc))
        return std::nullopt;
    for (const auto &point : points) {
        if (point.tick == 0)
            return std::nullopt;
    }
    return controllerDefault(cc);
}

inline uint32_t microsecondsPerQuarterNoteForBpm(int bpm)
{
    bpm = std::clamp(bpm, kMinTempoBpm, kMaxTempoBpm);
    return uint32_t(double(kMicrosecondsPerMinute) / double(bpm) + 0.5);
}

inline double tempoBpm(uint32_t microsecondsPerQuarterNote)
{
    if (microsecondsPerQuarterNote == 0)
        return kTempoBpm;
    return double(kMicrosecondsPerMinute) / double(microsecondsPerQuarterNote);
}

inline uint32_t clampTempoUspqn(uint32_t microsecondsPerQuarterNote)
{
    return std::clamp(microsecondsPerQuarterNote, microsecondsPerQuarterNoteForBpm(kMaxTempoBpm),
                      microsecondsPerQuarterNoteForBpm(kMinTempoBpm));
}

} // namespace CoreTimeDefaults
