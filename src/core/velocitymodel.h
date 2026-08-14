#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>

extern "C" {
#include "m4a_engine.h"
}

// How a track's velocities reach the hardware. A note's stored MIDI velocity
// is continuous (1-127) on DirectSound voices, but the CGB channels have only
// a handful of real loudness steps, so several stored values sound identical.
// VelocityMap answers, for one resolved voice, which stored values collapse
// together and which value best represents each step.
enum class VelocityVoice : uint8_t {
    Unresolved, // no voice at all (no program, no voicegroup)
    Invalid,    // a voice that has no velocity behavior to model (cry, nested keysplit)
    Keyless,    // a keysplit asked about without a key to resolve it with
    DirectSound,
    Square1,
    Square2,
    Wave,
    Noise,
};

// The inclusive stored-velocity span that shares one hardware level.
struct VelocityLevelRange {
    uint8_t first = 1;
    uint8_t last = 127;
};

class VelocityMap
{
  public:
    VelocityMap() = default;
    // key resolves keysplit voices; without one a keysplit stays unresolved
    // rather than guessing a child voice.
    static VelocityMap resolve(const ToneData *tone, std::optional<uint8_t> key);
    // A keysplit asked about without a key: the section plays on whichever
    // channel each key resolves to, so it has no one level table of its own.
    bool isKeyless() const;
    // True only for the four CGB channels, the voices with real detents.
    bool isPsg() const;
    bool operator==(const VelocityMap &other) const;
    bool operator!=(const VelocityMap &other) const;
    // Whether two notes can share one intrinsic (detent) editing context:
    // both PSG and the same channel, since the channels' level tables differ.
    bool compatibleWith(const VelocityMap &other) const;
    const char *voiceName() const;
    // 0 on non-PSG voices — a continuous voice has no levels to count.
    std::size_t levelCount() const;
    VelocityLevelRange levelRange(int requestedLevel) const;
    std::optional<std::size_t> levelOf(int storedVelocity) const;
    uint8_t representative(int requestedLevel) const;
    // The representative of the level a value falls in; the value unchanged
    // on continuous voices.
    uint8_t canonicalize(int proposedVelocity) const;
    // Steps delta levels from a value that need not be a representative, so a
    // gesture that returns to its origin level restores the exact origin.
    uint8_t moveLevels(uint8_t exactOrigin, int delta) const;

  private:
    explicit VelocityMap(VelocityVoice voice) : m_voice(voice) {}

    VelocityVoice m_voice = VelocityVoice::Unresolved;
};
