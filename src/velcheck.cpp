#include <array>
#include <cstdio>
#include <cstring>
#include <optional>

#include "core/velocitymodel.h"

// --velmodelcheck: PSG velocity model check (self-contained, no project
// needed). VelocityMap is the engine-behavior half of the velocity lane: it
// decides which voice a note plays on and which stored velocities that voice
// cannot tell apart. The numbers here are the engine's, not a design choice —
// the effective-velocity rounding is m4a's, the 16 envelope steps are the CGB
// channels', and the wave channel's five loudness classes are gCgb3Vol's
// distinct outputs (external/poryaaaa/plugin/m4a_tables.c).
// Ported from specker/cleanup/psg-velocity-history-pr's velocity-model check.

namespace {

bool equals(const std::optional<std::size_t> &value, std::size_t expected)
{
    return value && *value == expected;
}

} // namespace

int runVelocityModelCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "velmodelcheck: FAIL: %s\n", message);
            ++failures;
        }
    };

    ToneData squareTone{};
    squareTone.type = VOICE_SQUARE_1;
    ToneData squareTwoTone{};
    squareTwoTone.type = VOICE_SQUARE_2;
    ToneData noiseTone{};
    noiseTone.type = VOICE_NOISE;
    ToneData waveTone{};
    waveTone.type = VOICE_PROGRAMMABLE_WAVE;
    ToneData directSoundTone{};
    directSoundTone.type = VOICE_DIRECTSOUND;
    const VelocityMap square = VelocityMap::resolve(&squareTone, 60);
    const VelocityMap squareTwo = VelocityMap::resolve(&squareTwoTone, 60);
    const VelocityMap noise = VelocityMap::resolve(&noiseTone, 60);
    const VelocityMap wave = VelocityMap::resolve(&waveTone, 60);
    const VelocityMap directSound = VelocityMap::resolve(&directSoundTone, 60);
    const VelocityMap unresolved = VelocityMap::resolve(nullptr, std::nullopt);

    check(square.isPsg() && std::strcmp(square.voiceName(), "Square 1") == 0,
          "Square 1 should resolve intrinsically");
    check(squareTwo.isPsg() && std::strcmp(squareTwo.voiceName(), "Square 2") == 0,
          "Square 2 should resolve intrinsically");
    check(noise.isPsg() && std::strcmp(noise.voiceName(), "Noise") == 0,
          "Noise should resolve intrinsically");
    check(wave.isPsg() && std::strcmp(wave.voiceName(), "Programmable Wave") == 0,
          "Wave should resolve intrinsically");
    check(!directSound.isPsg() && directSound.levelCount() == 0,
          "DirectSound should remain continuous");
    check(!unresolved.isPsg() && unresolved.levelCount() == 0,
          "missing voice should remain unresolved");

    // The CGB mask keeps the alternate voice types on their channel.
    ToneData squareAltTone{};
    squareAltTone.type = VOICE_SQUARE_1_ALT;
    ToneData directSoundAltTone{};
    directSoundAltTone.type = VOICE_DIRECTSOUND_ALT;
    check(VelocityMap::resolve(&squareAltTone, 60) == square,
          "the alternate Square 1 type should map to the same voice");
    check(!VelocityMap::resolve(&directSoundAltTone, 60).isPsg() &&
              VelocityMap::resolve(&directSoundAltTone, 60) == directSound,
          "the alternate DirectSound type should stay continuous");

    ToneData invalidTone{};
    invalidTone.type = VOICE_CRY;
    const VelocityMap invalid = VelocityMap::resolve(&invalidTone, 60);
    check(!invalid.isPsg() && invalid != directSound,
          "a cry voice masks to no CGB channel and is not DirectSound either");
    // The nested child's CGB bits would classify as Square 1 if the second
    // keysplit hop were followed instead of refused.
    std::array<ToneData, 128> nestedChildren{};
    nestedChildren[60].type = VOICE_KEYSPLIT | VOICE_SQUARE_1;
    ToneData nestedSplit{};
    nestedSplit.type = VOICE_KEYSPLIT_ALL;
    nestedSplit.subGroup = nestedChildren.data();
    check(!VelocityMap::resolve(&nestedSplit, 60).isPsg(), "nested keysplit should be invalid");
    // The children here are PSG, so only refusing to guess a key keeps this
    // keysplit continuous.
    std::array<ToneData, 128> psgChildren{};
    psgChildren[60].type = VOICE_SQUARE_1;
    ToneData keylessSplit{};
    keylessSplit.type = VOICE_KEYSPLIT_ALL;
    keylessSplit.subGroup = psgChildren.data();
    check(!VelocityMap::resolve(&keylessSplit, std::nullopt).isPsg() &&
              VelocityMap::resolve(&keylessSplit, 60).isPsg(),
          "keyless keysplit should remain continuous");
    ToneData subgroupLessSplit{};
    subgroupLessSplit.type = VOICE_KEYSPLIT_ALL;
    check(!VelocityMap::resolve(&subgroupLessSplit, 60).isPsg(),
          "a keysplit without a subgroup must not be dereferenced");
    std::array<ToneData, 128> splitChildren{};
    std::array<uint8_t, 128> splitTable{};
    splitChildren[7].type = VOICE_PROGRAMMABLE_WAVE;
    splitTable[60] = 7;
    ToneData splitTone{};
    splitTone.type = VOICE_KEYSPLIT;
    splitTone.subGroup = splitChildren.data();
    splitTone.keySplitTable = splitTable.data();
    const VelocityMap keyedSplit = VelocityMap::resolve(&splitTone, 60);
    check(keyedSplit.isPsg() && std::strcmp(keyedSplit.voiceName(), "Programmable Wave") == 0,
          "keyed keysplit should resolve its selected voice");
    ToneData tableLessSplit{};
    tableLessSplit.type = VOICE_KEYSPLIT;
    tableLessSplit.subGroup = splitChildren.data();
    check(!VelocityMap::resolve(&tableLessSplit, 60).isPsg(),
          "a table-less VOICE_KEYSPLIT must not be indexed");

    const std::array<uint8_t, 16> squareNoiseRepresentatives = {
        1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
    };
    const std::array<uint8_t, 5> waveRepresentatives = {1, 32, 64, 96, 127};
    const auto representativesMatch = [](const VelocityMap &map, const auto &expected) {
        if (map.levelCount() != expected.size())
            return false;
        for (std::size_t level = 0; level < expected.size(); ++level) {
            if (map.representative(int(level)) != expected[level])
                return false;
        }
        return true;
    };
    check(representativesMatch(square, squareNoiseRepresentatives),
          "Square representatives should be exact");
    check(representativesMatch(wave, waveRepresentatives), "Wave representatives should be exact");
    check(representativesMatch(noise, squareNoiseRepresentatives),
          "Noise representatives should describe every hardware level");
    check(equals(square.levelOf(1), 0) && equals(square.levelOf(127), 15) &&
              equals(wave.levelOf(1), 0) && equals(wave.levelOf(127), 4),
          "intrinsic levels should include velocity boundaries");
    check(!directSound.levelOf(1) && !unresolved.levelOf(64),
          "continuous voices should not gain an intrinsic level");
    check(square.compatibleWith(square), "matching maps should be compatible");
    check(!square.compatibleWith(squareTwo) && !square.compatibleWith(noise) &&
              !directSound.compatibleWith(directSound),
          "different PSG identities — and continuous voices — should be incompatible");

    // Every stored velocity must land in the level whose range contains it,
    // and the ranges must tile 1-127 without gaps or overlap.
    const auto rangesTile = [&](const VelocityMap &map) {
        int expectedFirst = 1;
        for (std::size_t level = 0; level < map.levelCount(); ++level) {
            const VelocityLevelRange range = map.levelRange(int(level));
            if (range.first != expectedFirst || range.last < range.first)
                return false;
            for (int velocity = range.first; velocity <= range.last; ++velocity) {
                if (!equals(map.levelOf(velocity), level))
                    return false;
            }
            const uint8_t representative = map.representative(int(level));
            if (representative < range.first || representative > range.last)
                return false;
            expectedFirst = range.last + 1;
        }
        return expectedFirst == 128;
    };
    check(rangesTile(square) && rangesTile(noise) && rangesTile(wave),
          "level ranges should tile the velocity domain and contain their representatives");
    check(square.levelRange(-1).first == 1 && square.levelRange(99).last == 127 &&
              directSound.levelRange(64).first == 64 && directSound.levelRange(64).last == 64 &&
              directSound.representative(64) == 64,
          "level ranges should clamp, and a continuous voice's range is the velocity itself");

    check(square.canonicalize(1) == 1 && square.canonicalize(127) == 127,
          "Square canonicalization should retain endpoints");
    check(square.canonicalize(64) == 60 && wave.canonicalize(80) == 64,
          "canonicalization should select the representative for its hardware class");
    check(square.canonicalize(8) == 1 && square.canonicalize(9) == 12 &&
              noise.canonicalize(8) == 1 && noise.canonicalize(9) == 12 &&
              wave.canonicalize(112) == 96,
          "canonicalization should preserve hardware classes at their boundaries");
    check(wave.canonicalize(65) == 64 && square.canonicalize(65) == 68 &&
              noise.canonicalize(65) == 68 && directSound.canonicalize(65) == 65 &&
              invalid.canonicalize(65) == 65,
          "canonicalization should respect every voice type and fallback");
    check(square.canonicalize(0) == 1 && square.canonicalize(200) == 127 &&
              directSound.canonicalize(0) == 1 && directSound.canonicalize(200) == 127,
          "canonicalization should clamp out-of-range proposals into the MIDI domain");

    const std::optional<std::size_t> originLevel = wave.levelOf(95);
    check(equals(originLevel, 3) && wave.moveLevels(95, 0) == 95 && wave.moveLevels(95, -1) == 64,
          "returning to an origin level should restore its exact value");
    const std::array<uint8_t, 3> moved = {
        wave.moveLevels(95, 1),
        square.moveLevels(60, 1),
        directSound.moveLevels(65, 1),
    };
    check(moved == std::array<uint8_t, moved.size()>{127, 68, 66},
          "level movement should preserve heterogeneous exact origins");
    check(wave.moveLevels(1, -1) == 1 && square.moveLevels(127, 1) == 127 &&
              directSound.moveLevels(1, -1) == 1 && directSound.moveLevels(127, 1) == 127,
          "level movement should clamp at both velocity endpoints");
    // A non-representative origin only survives while the gesture is still on
    // its own level; stepping away and back lands on the representative.
    check(square.moveLevels(square.moveLevels(65, 1), -1) == 68,
          "stepping off a level and back should land on that level's representative");

    if (failures != 0) {
        std::fprintf(stderr, "velmodelcheck: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("velmodelcheck: PASS (velocity model)\n");
    return 0;
}
