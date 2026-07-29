#include "psgvelocitymodel.h"

#include "core/mid2agbtables.h"

#include <algorithm>
#include <cstddef>

namespace {

const ToneData *resolveVoice(const ToneData &tone, uint8_t key) {
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

uint8_t representativeVelocity(int low, int high) {
  if (low == 1)
    return 1;
  if (high == 127)
    return 127;
  return uint8_t((low + high) / 2);
}

} // namespace

std::optional<PsgVelocityContext> makePsgVelocityContext(const ToneData &tone,
                                                         uint8_t key) {
  const ToneData *voice = resolveVoice(tone, key);
  if (!voice)
    return std::nullopt;

  const uint8_t voiceType = voice->type & VOICE_TYPE_CGB_MASK;
  if (voiceType < VOICE_SQUARE_1 || voiceType > VOICE_NOISE)
    return std::nullopt;
  return PsgVelocityContext{voiceType};
}

uint8_t psgVelocityLevel(const PsgVelocityContext &context,
                         uint8_t storedVelocity) {
  const uint8_t hardwareLevel = uint8_t(
      (mid2agbEffectiveVelocity(std::clamp<int>(storedVelocity, 1, 127)) - 1) /
      8);
  if (context.voiceType != VOICE_PROGRAMMABLE_WAVE)
    return hardwareLevel;
  if (hardwareLevel <= 1)
    return 0;
  if (hardwareLevel <= 5)
    return 1;
  if (hardwareLevel <= 9)
    return 2;
  if (hardwareLevel <= 13)
    return 3;
  return 4;
}

VelocityDetentInfo psgVelocityDetents(const PsgVelocityContext &context) {
  VelocityDetentInfo result{context.voiceType, {}};
  int runStart = 1;
  uint8_t runLevel = psgVelocityLevel(context, 1);
  for (int velocity = 2; velocity <= 127; ++velocity) {
    const uint8_t level = psgVelocityLevel(context, uint8_t(velocity));
    if (level == runLevel)
      continue;
    result.levels.push_back(
        {representativeVelocity(runStart, velocity - 1), runLevel != 0});
    runStart = velocity;
    runLevel = level;
  }
  result.levels.push_back(
      {representativeVelocity(runStart, 127), runLevel != 0});
  return result;
}

bool velocityDetentsCompatible(const VelocityDetentInfo &left,
                               const VelocityDetentInfo &right) {
  if (left.voiceType != right.voiceType ||
      left.levels.size() != right.levels.size())
    return false;
  return std::equal(
      left.levels.begin(), left.levels.end(), right.levels.begin(),
      [](const VelocityDetentLevel &a, const VelocityDetentLevel &b) {
        return a.velocity == b.velocity && a.audible == b.audible;
      });
}

uint8_t psgCanonicalVelocity(const PsgVelocityContext &context,
                             int proposedVelocity) {
  const uint8_t proposed = uint8_t(std::clamp(proposedVelocity, 1, 127));
  const uint8_t level = psgVelocityLevel(context, proposed);
  int low = proposed;
  while (low > 1 && psgVelocityLevel(context, uint8_t(low - 1)) == level) {
    --low;
  }
  int high = proposed;
  while (high < 127 && psgVelocityLevel(context, uint8_t(high + 1)) == level) {
    ++high;
  }
  return representativeVelocity(low, high);
}

std::optional<uint8_t> psgVelocityForLevel(const VelocityDetentInfo &detents,
                                           uint8_t requestedLevel) {
  if (detents.levels.empty())
    return std::nullopt;
  const std::size_t level =
      std::min<std::size_t>(requestedLevel, detents.levels.size() - 1);
  return detents.levels[level].velocity;
}
