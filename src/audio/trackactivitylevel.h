#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>

inline constexpr std::size_t kMaxTracks = 16;

template <typename T>
struct StereoActivity {
    T left{};
    T right{};

    bool operator==(const StereoActivity &) const = default;
};

using TrackActivityLevel = StereoActivity<uint8_t>;
using TrackActivityIntensity = StereoActivity<float>;
using TrackActivityLevels = std::array<TrackActivityLevel, kMaxTracks>;

inline constexpr uint32_t packedActivity(TrackActivityLevel level)
{
    return uint32_t(level.left) | (uint32_t(level.right) << 8);
}

inline constexpr TrackActivityLevel unpackedActivity(uint32_t packed)
{
    return {uint8_t(packed), uint8_t(packed >> 8)};
}

inline constexpr TrackActivityLevel maxLevel(TrackActivityLevel a, TrackActivityLevel b)
{
    return {std::max(a.left, b.left), std::max(a.right, b.right)};
}

inline constexpr TrackActivityLevel pcmActivityLevel(uint8_t envelope, uint8_t leftVolume,
                                                     uint8_t rightVolume)
{
    const auto dominantVolume = std::max(leftVolume, rightVolume);
    if (dominantVolume == 0)
        return {};
    return {uint8_t(uint32_t(envelope) * leftVolume / dominantVolume),
            uint8_t(uint32_t(envelope) * rightVolume / dominantVolume)};
}

inline constexpr TrackActivityIntensity levelToIntensity(TrackActivityLevel level)
{
    return {float(level.left) / 255.0f, float(level.right) / 255.0f};
}

inline constexpr uint8_t intensityComponentToLevel(float intensity)
{
    if (!(intensity > 0.0f))
        return 0;
    if (intensity >= 1.0f)
        return 255;
    return uint8_t(intensity * 255.0f + 0.5f);
}

inline constexpr TrackActivityLevel intensityToLevel(TrackActivityIntensity intensity)
{
    return {intensityComponentToLevel(intensity.left), intensityComponentToLevel(intensity.right)};
}

static_assert(unpackedActivity(packedActivity({0, 0})).left == 0 &&
              unpackedActivity(packedActivity({0, 0})).right == 0);
static_assert(unpackedActivity(packedActivity({255, 255})).left == 255 &&
              unpackedActivity(packedActivity({255, 255})).right == 255);
static_assert(unpackedActivity(packedActivity({0x5A, 0xA5})).left == 0x5A &&
              unpackedActivity(packedActivity({0x5A, 0xA5})).right == 0xA5);
static_assert(unpackedActivity(0xDEADBEEFu).left == 0xEFu &&
              unpackedActivity(0xDEADBEEFu).right == 0xBEu);

static_assert(pcmActivityLevel(255, 127, 127).left == 255 &&
              pcmActivityLevel(255, 127, 127).right == 255);
static_assert(pcmActivityLevel(255, 0, 127).left == 0 &&
              pcmActivityLevel(255, 0, 127).right == 255);
static_assert(pcmActivityLevel(128, 32, 64).left == 64 &&
              pcmActivityLevel(128, 32, 64).right == 128);

static_assert(levelToIntensity({0, 255}).left == 0.0f && levelToIntensity({0, 255}).right == 1.0f);
static_assert(levelToIntensity({1, 0}).left > 0.0f && levelToIntensity({1, 0}).left < 1.0f);
static_assert(intensityToLevel({0.0f, 1.0f}).left == 0 &&
              intensityToLevel({0.0f, 1.0f}).right == 255);
static_assert(intensityToLevel({1.0f / 255.0f, 0.0f}).left == 1);
static_assert(intensityToLevel({-0.25f, 1.25f}).left == 0 &&
              intensityToLevel({-0.25f, 1.25f}).right == 255);
