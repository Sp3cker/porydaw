#include "trackactivity.h"

#include <algorithm>
#include <cmath>

namespace {
constexpr auto kAttackSeconds = 0.015f;
constexpr auto kReleaseSeconds = 0.250f;
constexpr auto kResumeAttackSeconds = 5.0f * kAttackSeconds;
constexpr auto kVisibleFloor = 0.002f;
constexpr auto kResumeDuration = kResumeAttackSeconds;
} // namespace

bool TrackActivity::advance(const TrackActivityLevels &levels, float elapsedSeconds, bool playing)
{
    const auto elapsed = std::max(0.0f, elapsedSeconds);

    // Transition table:
    //   paused -> PausedFilling: approach full brightness at release speed;
    //   PausedFilling -> playing: enter Resuming for one fast-descent window;
    //   Resuming -> Playing: use ordinary release after that window expires.
    if (!playing) {
        const auto fillAmount = 1.0f - std::exp(-elapsed / kReleaseSeconds);
        bool animating = false;
        const auto fillSide = [elapsed, fillAmount, &animating](float &intensity) {
            intensity += (1.0f - intensity) * fillAmount;
            if (elapsed > 0.0f && 1.0f - intensity < kVisibleFloor)
                intensity = 1.0f;
            else if (intensity < 1.0f)
                animating = true;
        };
        for (auto &intensity : m_intensities) {
            fillSide(intensity.left);
            fillSide(intensity.right);
        }
        m_phase = Phase::PausedFilling;
        m_resumeRemainingSeconds = kResumeDuration;
        return animating;
    }

    if (m_phase == Phase::PausedFilling) {
        m_phase = Phase::Resuming;
        m_resumeRemainingSeconds = kResumeDuration;
    }

    const auto attackAmount = 1.0f - std::exp(-elapsed / kAttackSeconds);
    const auto releaseAmount = 1.0f - std::exp(-elapsed / kReleaseSeconds);
    const auto descendingAmount = m_phase == Phase::Resuming ? attackAmount : releaseAmount;
    const auto advanceSide = [elapsed, attackAmount, descendingAmount](float &intensity,
                                                                        float target) {
        const auto amount = target > intensity ? attackAmount : descendingAmount;
        intensity += (target - intensity) * amount;
        if (elapsed > 0.0f && target == 0.0f && intensity < kVisibleFloor)
            intensity = 0.0f;
    };
    for (size_t track = 0; track < kMaxTracks; ++track) {
        const auto target = levelToIntensity(levels[track]);
        advanceSide(m_intensities[track].left, target.left);
        advanceSide(m_intensities[track].right, target.right);
    }

    if (m_phase == Phase::Resuming) {
        m_resumeRemainingSeconds = std::max(0.0f, m_resumeRemainingSeconds - elapsed);
        if (m_resumeRemainingSeconds == 0.0f)
            m_phase = Phase::Playing;
    }
    return true;
}

void TrackActivity::reset()
{
    m_intensities.fill({});
    m_phase = Phase::Playing;
    m_resumeRemainingSeconds = 0.0f;
}

void TrackActivity::resetPaused()
{
    m_intensities.fill({1.0f, 1.0f});
    m_phase = Phase::PausedFilling;
    m_resumeRemainingSeconds = kResumeDuration;
}

TrackActivityIntensity TrackActivity::intensity(int track) const
{
    if (track < 0 || track >= int(kMaxTracks))
        return {};
    return m_intensities[size_t(track)];
}
