#pragma once

// The tap-session state behind the Tempo parameter row's tap-tempo gesture.
// Pure state — no QObject, no clock of its own: the canvas supplies the
// monotonic nanoseconds per call and owns the idle-commit timer, so nothing
// here allocates beyond the fixed interval ring and nothing can outlive it.

#include <algorithm>
#include <array>
#include <cstdint>

#include <QtGlobal>

#include "core/timedefaults.h"

// A tap becomes tap one after this idle gap; that distance only decides
// session boundaries. The idle commit that lands a draft fires sooner,
// scaled to the tapped tempo: idleCommitMs() returns ~1.5 beats' worth of
// silence, clamped to [kTapCommitMinMs, kTapCommitMaxMs]. The commit must
// stay at or under the gap distance — otherwise a slow next tap would read
// as a fresh session start and silently drop the pending draft.
constexpr int kTapGapMs = 2000;
constexpr int kTapCommitMinMs = 600;
constexpr int kTapCommitMaxMs = kTapGapMs;
// The commit lands after this many tapped beats' worth of silence.
inline constexpr double kTapCommitBeats = 1.5;
static_assert(kTapCommitMinMs <= kTapCommitMaxMs,
              "a draft must land before a slow next tap can start a fresh session");

// Rounded mean over the newest intervals kept in the ring; the earliest gap
// never enters the mean, and the ring holds the window bounded by kTapWindow.
inline constexpr unsigned kTapWindow = 8;

// Two taps have one interval, which already yields a rounded draft.
inline constexpr unsigned kTapMinTaps = 2;

class TapTempoSession
{
  public:
    void reset() { *this = TapTempoSession{}; }

    // nowNs is caller-supplied monotonic nanoseconds. The first tap (or a tap
    // past the gap distance) starts a session and produces no draft; every
    // later tap recomputes the draft from the clipped mean of the last
    // intervals.
    void registerTap(qint64 nowNs)
    {
        const qint64 gapNs = nowNs - m_lastNs;
        if (m_tapCount == 0 || gapNs > qint64(kTapGapMs) * 1'000'000) {
            *this = TapTempoSession{};
            m_lastNs = nowNs;
            m_tapCount = 1;
            return;
        }
        m_intervals[m_head] = gapNs;
        m_head = (m_head + 1) % kTapWindow;
        m_lastNs = nowNs;
        ++m_tapCount;
        const unsigned used = std::min(m_tapCount - 1, kTapWindow);
        qint64 sumNs = 0;
        for (unsigned i = 0; i < used; ++i)
            sumNs += m_intervals[(m_head + kTapWindow - 1 - i) % kTapWindow];
        m_draftBpm = bpmForMeanIntervalNs(sumNs / qint64(used));
    }

    unsigned tapCount() const noexcept { return m_tapCount; }
    int draftBpm() const noexcept { return m_draftBpm; }
    bool readyToCommit() const noexcept { return m_tapCount >= kTapMinTaps; }

    // Idle silence that lands the current draft: ~1.5 tapped beats' worth of
    // time, so the commit stays clear of the cadence itself while landing
    // soon after the last tap. A draft-less session (a lone stray tap) stays
    // alive for exactly the gap distance: any next tap that could still join
    // the session must find it running.
    int idleCommitMs() const noexcept
    {
        if (m_draftBpm <= 0)
            return kTapGapMs;
        return std::clamp(qRound(kTapCommitBeats * 60'000.0 / m_draftBpm), kTapCommitMinMs,
                          kTapCommitMaxMs);
    }

    static int bpmForMeanIntervalNs(qint64 meanIntervalNs)
    {
        if (meanIntervalNs <= 0)
            return CoreTimeDefaults::kMaxTempoBpm;
        return std::clamp(qRound(60'000'000'000.0 / double(meanIntervalNs)),
                          CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm);
    }

  private:
    using TapCount = unsigned;

    std::array<qint64, kTapWindow> m_intervals{};
    TapCount m_head = 0;
    qint64 m_lastNs = 0;
    TapCount m_tapCount = 0;
    int m_draftBpm = 0;
};
