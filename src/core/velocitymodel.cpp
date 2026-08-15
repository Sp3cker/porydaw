#include "core/velocitymodel.h"

#include <algorithm>
#include <array>

#include "core/mid2agbtables.h"

namespace {

constexpr int kMinimumVelocity = 1;
constexpr int kMaximumVelocity = 127;
// The engine's own default for a track's volume multiplier (m4a_engine.c
// sets volX = 64 when a track is initialized). Nothing in a .mid can change
// it — only MPlayVolumeControl, which songs do not carry — so the detents
// take it as fixed.
constexpr int kDefaultVolX = 64;
// gCgb3Vol (m4a_tables.c): the wave channel's NR32 has only five distinct
// output levels, so groups of envelope steps share one loudness — steps 0-1
// mute, 2-5 at 25%, 6-9 at 50%, 10-13 at 75%, then 14-15 at 100%.
constexpr std::array<uint8_t, 16> kWaveClassOfEnvelopeGoal = {
    0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4,
};

uint8_t clampVelocity(int velocity)
{
    return uint8_t(std::clamp(velocity, kMinimumVelocity, kMaximumVelocity));
}

// The 4-bit envelope goal a CGB channel is started at — the number NRx2's
// initial-volume nibble receives, and so the only thing about a note the
// hardware actually hears. This is the engine's chain verbatim
// (external/poryaaaa/plugin/m4a_engine.c and m4a_channel.c):
//
//   mid2agb rounds the stored velocity up to a multiple of 4,
//   TrkVolPitSet   x = (volume * volX) >> 5, then volMR/volML from the pan,
//   ChnVolSetAsm   right/left = (pan * velocity * volMR/volML) >> 14, cap 255,
//   CgbModVol      goal = (left + right) / 16.
//
// Pan is taken as centered. It is not an omission: hard-panning doubles one
// side and zeroes the other, so CgbModVol's sum — and therefore the goal —
// comes out the same to within a step. Volume is the term that really moves
// the levels, and it is the one this takes.
int cgbEnvelopeGoal(int storedVelocity, int trackVolume)
{
    const int velocity = mid2agbEffectiveVelocity(clampVelocity(storedVelocity));
    const int x = (trackVolume * kDefaultVolX) >> 5;
    const int volMR = (128 * x) >> 8; // centered pan: y = 0
    const int volML = (127 * x) >> 8;
    const int right = std::min(255, (128 * velocity * volMR) >> 14);
    const int left = std::min(255, (127 * velocity * volML) >> 14);
    return (left + right) / 16;
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

uint8_t m4aEffectiveTrackVolume(int volumeEvent, int masterVolume)
{
    const int volume = std::clamp(volumeEvent, 0, kM4aMaxVolume);
    const int master = std::clamp(masterVolume, 0, kM4aMaxVolume);
    return uint8_t(volume * master / kM4aMaxVolume);
}

VelocityMap VelocityMap::resolve(const ToneData *tone, std::optional<uint8_t> key,
                                 uint8_t trackVolume)
{
    VelocityVoice failure = VelocityVoice::Invalid;
    const ToneData *resolved = resolveVoice(tone, key, &failure);
    if (!resolved)
        return VelocityMap(failure, trackVolume);
    return VelocityMap(velocityVoiceForType(resolved->type), trackVolume);
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

bool VelocityMap::hasDetents() const
{
    return levelCount() > 1;
}

bool VelocityMap::operator==(const VelocityMap &other) const
{
    // Two CGB maps under different volumes describe different level tables,
    // so they are not the same ruler even on the same channel.
    return m_voice == other.m_voice && (!isPsg() || m_trackVolume == other.m_trackVolume);
}

bool VelocityMap::operator!=(const VelocityMap &other) const
{
    return !(*this == other);
}

bool VelocityMap::compatibleWith(const VelocityMap &other) const
{
    return isPsg() && other.isPsg() && m_voice == other.m_voice &&
           m_trackVolume == other.m_trackVolume;
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

std::size_t VelocityMap::levelAt(int storedVelocity) const
{
    const int goal = cgbEnvelopeGoal(storedVelocity, m_trackVolume);
    return m_voice == VelocityVoice::Wave ? kWaveClassOfEnvelopeGoal[std::size_t(goal)]
                                          : std::size_t(goal);
}

std::size_t VelocityMap::levelCount() const
{
    if (!isPsg())
        return 0;
    // The levels run from 0 (silence) up to whatever velocity 127 reaches,
    // with none skipped: one step of effective velocity moves CgbModVol's sum
    // by at most 8, so it can never jump a whole 16-wide goal.
    return levelAt(kMaximumVelocity) + 1;
}

VelocityLevelRange VelocityMap::levelRange(int requestedLevel) const
{
    if (!isPsg()) {
        // A continuous voice's "level" is the velocity itself.
        const uint8_t velocity = clampVelocity(requestedLevel);
        return {velocity, velocity};
    }
    const std::size_t level = std::size_t(std::clamp(requestedLevel, 0, int(levelCount()) - 1));
    // levelAt is non-decreasing in the stored velocity, so each level owns one
    // contiguous run and its ends are two binary searches. This is on the
    // per-note paint path, so it is worth not walking all 127 values.
    const auto firstReaching = [this](std::size_t wanted) {
        int low = kMinimumVelocity;
        int high = kMaximumVelocity;
        while (low < high) {
            const int mid = low + (high - low) / 2;
            if (levelAt(mid) < wanted)
                low = mid + 1;
            else
                high = mid;
        }
        return low;
    };
    const int first = firstReaching(level);
    const int last = level + 1 == levelCount() ? kMaximumVelocity : firstReaching(level + 1) - 1;
    return {uint8_t(first), uint8_t(last)};
}

std::optional<std::size_t> VelocityMap::levelOf(int storedVelocity) const
{
    if (!isPsg())
        return std::nullopt;
    return levelAt(storedVelocity);
}

uint8_t VelocityMap::representative(int requestedLevel) const
{
    if (!isPsg())
        return clampVelocity(requestedLevel);
    const int level = std::clamp(requestedLevel, 0, int(levelCount()) - 1);
    const VelocityLevelRange range = levelRange(level);
    // The value the UI writes for the level. The outermost levels keep 1 and
    // 127 so a canonicalized velocity still spans the whole MIDI range; the
    // rest take the middle of their band, as far from either neighbour as the
    // level's own width allows.
    if (level == 0)
        return range.first;
    if (level + 1 == int(levelCount()))
        return range.last;
    return uint8_t((int(range.first) + int(range.last)) / 2);
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
