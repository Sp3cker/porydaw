#pragma once

#include <array>

#include "audio/trackactivitylevel.h"

class TrackActivity
{
  public:
    // Advances the sole playback/pause state machine. The return value is
    // true while playback needs ticks, or while paused fill remains visible.
    bool advance(const TrackActivityLevels &levels, float elapsedSeconds, bool playing);
    void reset();
    void resetPaused();
    TrackActivityIntensity intensity(int track) const;

  private:
    enum class Phase { Playing, PausedFilling, Resuming };

    std::array<TrackActivityIntensity, kMaxTracks> m_intensities{};
    Phase m_phase = Phase::Playing;
    float m_resumeRemainingSeconds = 0.0f;
};
