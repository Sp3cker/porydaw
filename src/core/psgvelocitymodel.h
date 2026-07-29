#pragma once

#include <cstdint>
#include <optional>
#include <vector>

extern "C" {
#include "m4a_engine.h"
}

struct PsgVelocityContext {
  uint8_t voiceType;
  uint8_t volMR;
  uint8_t volML;
  int8_t rhythmPan;

  bool operator==(const PsgVelocityContext &other) const {
    return voiceType == other.voiceType && volMR == other.volMR &&
           volML == other.volML && rhythmPan == other.rhythmPan;
  }
  bool operator!=(const PsgVelocityContext &other) const {
    return !(*this == other);
  }
};

struct VelocityDetentLevel {
  uint8_t velocity;
  bool audible;
};

struct VelocityDetentInfo {
  uint8_t voiceType;
  std::vector<VelocityDetentLevel> levels;
};

std::optional<PsgVelocityContext> makePsgVelocityContext(const ToneData &tone,
                                                         uint8_t key, int cc7,
                                                         int cc10,
                                                         int masterVolume);
uint8_t psgVelocityLevel(const PsgVelocityContext &context,
                         uint8_t storedVelocity);
uint8_t psgCanonicalVelocity(const PsgVelocityContext &context,
                             int proposedVelocity);
VelocityDetentInfo psgVelocityDetents(const PsgVelocityContext &context);
bool velocityDetentsCompatible(const VelocityDetentInfo &left,
                               const VelocityDetentInfo &right);
std::optional<uint8_t> psgVelocityForLevel(const VelocityDetentInfo &detents,
                                           uint8_t requestedLevel);
