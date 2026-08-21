#pragma once

#include <algorithm>
#include <cstdint>

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

inline constexpr ControllerDefault kControllerDefaults[] = {
    {0x01, 0},   // MOD
    {0x05, 0},   // PORTAMENTO
    {0x07, 127}, // VOL
    {0x0A, 64},  // PAN
    {0x14, 2},   // BENDR
    {0x15, 22},  // LFOS
    {0x17, 0},   // PWMC
    {0x19, 0},   // PWMS
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
