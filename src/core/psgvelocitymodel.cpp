#include "psgvelocitymodel.h"

#include "core/mid2agbtables.h"

#include <algorithm>
#include <cstddef>

extern "C" {
#include "m4a_channel.h"
}

namespace {

const ToneData *resolveVoice(const ToneData &tone, uint8_t key)
{
    const ToneData *resolved = &tone;
    if (tone.type & VOICE_KEYSPLIT_ALL) {
        const auto *subGroup = static_cast<const ToneData *>(tone.subGroup);
        if (!subGroup || key >= 128)
            return nullptr;
        resolved = &subGroup[key];
    } else if (tone.type & VOICE_KEYSPLIT) {
        const auto *subGroup = static_cast<const ToneData *>(tone.subGroup);
        if (!subGroup || !tone.keySplitTable || key >= 128)
            return nullptr;
        const uint8_t index = tone.keySplitTable[key];
        if (index >= 128)
            return nullptr;
        resolved = &subGroup[index];
    }

    if (resolved->type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL))
        return nullptr;
    return resolved;
}

uint8_t representativeVelocity(int low, int high)
{
    if (low == 1)
        return 1;
    if (high == 127)
        return 127;
    return uint8_t((low + high) / 2);
}

} // namespace

std::optional<PsgVelocityContext>
makePsgVelocityContext(const ToneData &tone, uint8_t key, int cc7, int cc10,
                       int masterVolume)
{
    const ToneData *voice = resolveVoice(tone, key);
    if (!voice)
        return std::nullopt;

    const uint8_t voiceType = voice->type & VOICE_TYPE_CGB_MASK;
    if (voiceType < VOICE_SQUARE_1 || voiceType > VOICE_NOISE)
        return std::nullopt;

    const uint32_t volume =
        uint32_t(std::clamp(cc7, 0, 127) *
                 std::clamp(masterVolume, 0, 127) / 127);
    const uint32_t scaledVolume = volume * 64 >> 5;
    const int pan = std::clamp(2 * (std::clamp(cc10, 0, 127) - 64),
                               -128, 127);
    int8_t rhythmPan = 0;
    if ((tone.type & VOICE_KEYSPLIT_ALL) && (voice->panSweep & 0x80))
        rhythmPan = int8_t((int(voice->panSweep) - 0xC0) * 2);

    return PsgVelocityContext{
        voiceType,
        uint8_t(uint32_t(pan + 128) * scaledVolume >> 8),
        uint8_t(uint32_t(127 - pan) * scaledVolume >> 8),
        rhythmPan,
    };
}

uint8_t psgVelocityLevel(const PsgVelocityContext &context,
                         uint8_t storedVelocity)
{
    const uint32_t effectiveVelocity = uint32_t(mid2agbEffectiveVelocity(
        std::clamp<int>(storedVelocity, 1, 127)));
    const uint32_t panR = uint32_t(0x80 + context.rhythmPan);
    const uint32_t panL = uint32_t(0x7F - context.rhythmPan);

    M4ACGBChannel channel{};
    channel.type = context.voiceType;
    channel.rightVolume = uint8_t(std::min<uint32_t>(
        (panR * effectiveVelocity * context.volMR) >> 14, 0xFF));
    channel.leftVolume = uint8_t(std::min<uint32_t>(
        (panL * effectiveVelocity * context.volML) >> 14, 0xFF));
    channel.panMask = 0xFF;
    m4a_cgb_mod_vol(&channel);

    const uint8_t envelopeGoal = channel.envelopeGoal & 0x0F;
    if (context.voiceType != VOICE_PROGRAMMABLE_WAVE)
        return envelopeGoal;
    if (envelopeGoal <= 1)
        return 0;
    if (envelopeGoal <= 5)
        return 1;
    if (envelopeGoal <= 9)
        return 2;
    if (envelopeGoal <= 13)
        return 3;
    return 4;
}

VelocityDetentInfo psgVelocityDetents(const PsgVelocityContext &context)
{
    VelocityDetentInfo result{context.voiceType, {}};
    int runStart = 1;
    uint8_t runLevel = psgVelocityLevel(context, 1);
    for (int velocity = 2; velocity <= 127; ++velocity) {
        const uint8_t level =
            psgVelocityLevel(context, uint8_t(velocity));
        if (level == runLevel)
            continue;
        result.levels.push_back({
            representativeVelocity(runStart, velocity - 1), runLevel != 0});
        runStart = velocity;
        runLevel = level;
    }
    result.levels.push_back(
        {representativeVelocity(runStart, 127), runLevel != 0});
    return result;
}

uint8_t psgCanonicalVelocity(const PsgVelocityContext &context,
                             int proposedVelocity)
{
    const uint8_t proposed =
        uint8_t(std::clamp(proposedVelocity, 1, 127));
    const uint8_t level = psgVelocityLevel(context, proposed);
    int low = proposed;
    while (low > 1 &&
           psgVelocityLevel(context, uint8_t(low - 1)) == level) {
        --low;
    }
    int high = proposed;
    while (high < 127 &&
           psgVelocityLevel(context, uint8_t(high + 1)) == level) {
        ++high;
    }
    return representativeVelocity(low, high);
}

std::optional<uint8_t> psgVelocityForLevel(const VelocityDetentInfo &detents,
                                           uint8_t requestedLevel)
{
    if (detents.levels.empty())
        return std::nullopt;
    const std::size_t level =
        std::min<std::size_t>(requestedLevel, detents.levels.size() - 1);
    return detents.levels[level].velocity;
}
