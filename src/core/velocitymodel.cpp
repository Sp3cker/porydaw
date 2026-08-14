#include "core/velocitymodel.h"

#include <algorithm>
#include <array>

namespace {

constexpr int kMinimumVelocity = 1;
constexpr int kMaximumVelocity = 127;
// The engine drives a CGB channel's envelope from the top 4 bits of the
// effective velocity, so the 127 stored values collapse onto 16 levels. Each
// representative is the value the UI writes for its level; the endpoints keep
// 1 and 127 so a canonicalized velocity never leaves the MIDI range.
constexpr std::array<uint8_t, 16> kPsgRepresentatives = {
    1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
};
// The wave channel's NR32 has only five distinct output levels, so gCgb3Vol
// maps groups of the 16 envelope steps onto the same loudness (see
// m4a_tables.c: steps 0-1 mute, 2-5, 6-9, 10-13, then 14-15).
constexpr std::array<uint8_t, 5> kWaveRepresentatives = {1, 32, 64, 96, 127};
constexpr std::array<VelocityLevelRange, 5> kWaveRanges = {
    VelocityLevelRange{1, 16},   VelocityLevelRange{17, 48},   VelocityLevelRange{49, 80},
    VelocityLevelRange{81, 112}, VelocityLevelRange{113, 127},
};

uint8_t clampVelocity(int velocity)
{
    return uint8_t(std::clamp(velocity, kMinimumVelocity, kMaximumVelocity));
}

bool isDirectSoundVoiceType(uint8_t voiceType)
{
    return voiceType == VOICE_DIRECTSOUND || voiceType == VOICE_DIRECTSOUND_NO_RESAMPLE ||
           voiceType == VOICE_DIRECTSOUND_ALT;
}

VelocityVoice velocityVoiceForType(uint8_t voiceType)
{
    switch (voiceType & VOICE_TYPE_CGB_MASK) {
    case VOICE_SQUARE_1:
        return VelocityVoice::Square1;
    case VOICE_SQUARE_2:
        return VelocityVoice::Square2;
    case VOICE_PROGRAMMABLE_WAVE:
        return VelocityVoice::Wave;
    case VOICE_NOISE:
        return VelocityVoice::Noise;
    default:
        // The CGB mask leaves cry and other non-PSG types at 0, so only the
        // real DirectSound types may claim the continuous voice.
        return isDirectSoundVoiceType(voiceType) ? VelocityVoice::DirectSound
                                                 : VelocityVoice::Invalid;
    }
}

const ToneData *resolveVoice(const ToneData *tone, std::optional<uint8_t> key,
                             VelocityVoice *failure)
{
    if (!tone) {
        *failure = VelocityVoice::Unresolved;
        return nullptr;
    }
    if (tone->type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL)) {
        if (!key) {
            *failure = VelocityVoice::Keyless;
            return nullptr;
        }
        const auto *subgroup = static_cast<const ToneData *>(tone->subGroup);
        if (!subgroup || ((tone->type & VOICE_KEYSPLIT) && !tone->keySplitTable)) {
            *failure = VelocityVoice::Invalid;
            return nullptr;
        }
        const ToneData *resolved = nullptr;
        if (tone->type & VOICE_KEYSPLIT_ALL)
            resolved = &subgroup[*key];
        else
            resolved = &subgroup[tone->keySplitTable[*key]];
        // The engine does not follow a second hop, so neither does this.
        if (resolved->type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL)) {
            *failure = VelocityVoice::Invalid;
            return nullptr;
        }
        return resolved;
    }
    return tone;
}

} // namespace

VelocityMap VelocityMap::resolve(const ToneData *tone, std::optional<uint8_t> key)
{
    VelocityVoice failure = VelocityVoice::Invalid;
    const ToneData *resolved = resolveVoice(tone, key, &failure);
    if (!resolved)
        return VelocityMap(failure);
    return VelocityMap(velocityVoiceForType(resolved->type));
}

bool VelocityMap::isKeyless() const
{
    return m_voice == VelocityVoice::Keyless;
}

bool VelocityMap::isPsg() const
{
    return m_voice == VelocityVoice::Square1 || m_voice == VelocityVoice::Square2 ||
           m_voice == VelocityVoice::Wave || m_voice == VelocityVoice::Noise;
}

bool VelocityMap::operator==(const VelocityMap &other) const
{
    return m_voice == other.m_voice;
}

bool VelocityMap::operator!=(const VelocityMap &other) const
{
    return !(*this == other);
}

bool VelocityMap::compatibleWith(const VelocityMap &other) const
{
    return isPsg() && other.isPsg() && m_voice == other.m_voice;
}

const char *VelocityMap::voiceName() const
{
    switch (m_voice) {
    case VelocityVoice::Square1:
        return "Square 1";
    case VelocityVoice::Square2:
        return "Square 2";
    case VelocityVoice::Wave:
        return "Programmable Wave";
    case VelocityVoice::Noise:
        return "Noise";
    default:
        return "";
    }
}

std::size_t VelocityMap::levelCount() const
{
    if (!isPsg())
        return 0;
    return m_voice == VelocityVoice::Wave ? kWaveRepresentatives.size()
                                          : kPsgRepresentatives.size();
}

VelocityLevelRange VelocityMap::levelRange(int requestedLevel) const
{
    if (!isPsg()) {
        // A continuous voice's "level" is the velocity itself.
        const uint8_t velocity = clampVelocity(requestedLevel);
        return {velocity, velocity};
    }
    const int highestLevel = int(levelCount()) - 1;
    const int level = std::clamp(requestedLevel, 0, highestLevel);
    if (m_voice == VelocityVoice::Wave)
        return kWaveRanges[std::size_t(level)];
    return {
        uint8_t(level == 0 ? kMinimumVelocity : level * 8 + 1),
        uint8_t(level == highestLevel ? kMaximumVelocity : (level + 1) * 8),
    };
}

std::optional<std::size_t> VelocityMap::levelOf(int storedVelocity) const
{
    if (!isPsg())
        return std::nullopt;
    const int stored = clampVelocity(storedVelocity);
    // The engine's effective velocity: quantized up to a multiple of 4 and
    // capped at 127 before the envelope takes its top 4 bits.
    const int effective = std::min(((stored + 3) / 4) * 4, kMaximumVelocity);
    const int hardwareLevel = (effective - 1) / 8;
    if (m_voice != VelocityVoice::Wave)
        return std::size_t(hardwareLevel);
    if (hardwareLevel <= 1)
        return std::size_t{0};
    if (hardwareLevel <= 5)
        return std::size_t{1};
    if (hardwareLevel <= 9)
        return std::size_t{2};
    if (hardwareLevel <= 13)
        return std::size_t{3};
    return std::size_t{4};
}

uint8_t VelocityMap::representative(int requestedLevel) const
{
    if (!isPsg())
        return clampVelocity(requestedLevel);
    if (m_voice == VelocityVoice::Wave) {
        const int highestLevel = int(kWaveRepresentatives.size()) - 1;
        const std::size_t level = std::size_t(std::clamp(requestedLevel, 0, highestLevel));
        return kWaveRepresentatives[level];
    }
    const int highestLevel = int(kPsgRepresentatives.size()) - 1;
    const std::size_t level = std::size_t(std::clamp(requestedLevel, 0, highestLevel));
    return kPsgRepresentatives[level];
}

uint8_t VelocityMap::canonicalize(int proposedVelocity) const
{
    const uint8_t proposed = clampVelocity(proposedVelocity);
    const std::optional<std::size_t> level = levelOf(proposed);
    return level ? representative(int(*level)) : proposed;
}

uint8_t VelocityMap::moveLevels(uint8_t exactOrigin, int delta) const
{
    const uint8_t origin = clampVelocity(exactOrigin);
    if (!isPsg())
        return clampVelocity(int(origin) + delta);
    const std::size_t originLevel = *levelOf(origin);
    const int highestLevel = int(levelCount()) - 1;
    const int targetLevel = std::clamp(int(originLevel) + delta, 0, highestLevel);
    // Staying put keeps the origin exactly, so a round trip through other
    // levels never quietly rewrites a value the user did not aim at.
    if (targetLevel == int(originLevel))
        return origin;
    return representative(targetLevel);
}
