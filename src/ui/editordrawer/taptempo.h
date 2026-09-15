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

// A tap becomes tap one after this idle gap; the idle commit fires after the
// same span without another tap. One distance keeps the semantics symmetric:
// you cannot commit a draft whose newest tap would already read as a fresh
// session start.
constexpr int kTapGapMs = 2000;
constexpr int kTapCommitMs = 2000;
static_assert(kTapGapMs == kTapCommitMs,
              "the tap gap and the idle commit window share one distance");

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
