#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>

extern "C" {
#include "m4a_engine.h"
}

enum class VelocityVoice : uint8_t {
    Unresolved,
    Invalid,
    Keyless,
    DirectSound,
    Square1,
    Square2,
    Wave,
    Noise,
};

struct VelocityLevelRange {
    uint8_t first = 1;
    uint8_t last = 127;
};

class VelocityMap
{
  public:
    VelocityMap() = default;
    static VelocityMap resolve(const ToneData *tone, std::optional<uint8_t> key);
    bool isPsg() const;
    bool operator==(const VelocityMap &other) const;
    bool operator!=(const VelocityMap &other) const;
    bool compatibleWith(const VelocityMap &other) const;
    const char *voiceName() const;
    std::size_t levelCount() const;
    VelocityLevelRange levelRange(int requestedLevel) const;
    std::optional<std::size_t> levelOf(int storedVelocity) const;
    uint8_t representative(int requestedLevel) const;
    uint8_t canonicalize(int proposedVelocity) const;
    uint8_t moveLevels(uint8_t exactOrigin, int delta) const;

  private:
    explicit VelocityMap(VelocityVoice voice) : m_voice(voice) {}

    VelocityVoice m_voice = VelocityVoice::Unresolved;
};
