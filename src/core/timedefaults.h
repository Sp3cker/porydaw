#pragma once

#include <algorithm>
#include <cstdint>
#include <optional>

namespace CoreTimeDefaults {

inline constexpr int kTempoBpm = 120;
inline constexpr int kMinTempoBpm = 20;
inline constexpr int kMaxTempoBpm = 255;
inline constexpr uint32_t kMicrosecondsPerMinute = 60'000'000;
inline constexpr uint32_t kDefaultTempoUspqn = 500000;

struct ControllerDefault {
    uint8_t cc;
    uint8_t value;
};

// mid2agb CC mnemonics used across the automation surface. kControllerDefaults
// is keyed by these; the surface policies below reuse them.
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
// Default-visible lanes: the automation surface always exposes a row for
// Volume and Pitch Bend, even when the song writes neither (shown empty).
// This drives row building and the remove-empty-lane handling.
inline constexpr uint8_t kDefaultVisibleControllers[] = {kCcVolume, kLaneCcBend};

constexpr bool isDefaultVisibleController(uint8_t cc)
{
    for (const uint8_t entry : kDefaultVisibleControllers) {
        if (entry == cc)
            return true;
    }
    return false;
}

// Synthetic engine-default node: mid2agb initializes a track with Volume=127
// and Pan=64 when the song never writes them, so the automation surface
// projects an implicit tick-0 node for exactly these two lanes. The projected
// value comes from controllerDefault(cc) above. Distinct from the
// default-visible policy: Pan is synthetic-default but not default-visible.
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
