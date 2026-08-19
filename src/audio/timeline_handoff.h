#pragma once

#include <atomic>
#include <memory>
#include <utility>

#include "core/miditimeline.h"

// Single-producer (UI thread), single-consumer (audio thread) lock-free snapshot
// handoff for MidiTimeline.
//
// The UI thread owns the current publication and the timeline most recently
// acquired by audio. Publishing atomically replaces the pending raw pointer:
// a non-null replaced pointer was never acquired and can be discarded; null
// means the previous current timeline was acquired and must become the retired
// owner. This coalesces arbitrarily many pending updates without releasing the
// timeline still used by audio.
//
// Thread model:
//  - UI Thread (Hot): Calls publish(). Zero dynamic heap allocations.
//  - UI Thread (Cold): Calls reset() or adoptImmediately() only while the audio
//    callback is quiesced.
//  - Audio Callback (Hot): Calls acquirePending() and active(). Zero allocations,
//    deallocations, locks, and shared_ptr writes.
class TimelineHandoff
{
  public:
    TimelineHandoff() = default;

    // Cold: destruction must only occur when the audio callback is quiesced.
    ~TimelineHandoff() { reset(); }

    TimelineHandoff(const TimelineHandoff &) = delete;
    TimelineHandoff &operator=(const TimelineHandoff &) = delete;

    // UI thread: publishes the latest snapshot without waiting for audio.
    // Intermediate pending snapshots are coalesced.
    void publish(std::shared_ptr<const MidiTimeline> timeline)
    {
        if (!timeline)
            return;

        std::shared_ptr<const MidiTimeline> previous = std::move(m_currentTimeline);
        m_currentTimeline = std::move(timeline);
        const MidiTimeline *superseded =
            m_pendingTimeline.exchange(m_currentTimeline.get(), std::memory_order_acq_rel);
        if (!superseded)
            m_retiredTimeline = std::move(previous);
    }

    // Cold adoption: immediately updates the active timeline while callbacks
    // are quiesced (for example, headless/offscreen tests).
    void adoptImmediately()
    {
        const MidiTimeline *timeline =
            m_pendingTimeline.exchange(nullptr, std::memory_order_acq_rel);
        if (!timeline)
            return;
        m_activeTimeline.store(timeline, std::memory_order_release);
        m_retiredTimeline.reset();
    }

    // Cold reset: clears publication state and snapshot ownership.
    void reset(std::shared_ptr<const MidiTimeline> initial = nullptr)
    {
        m_pendingTimeline.store(nullptr, std::memory_order_release);
        m_retiredTimeline.reset();
        m_currentTimeline = std::move(initial);
        m_activeTimeline.store(m_currentTimeline.get(), std::memory_order_release);
    }

    // Latest published snapshot for UI-thread inspection.
    const MidiTimeline *current() const { return m_currentTimeline.get(); }
    std::shared_ptr<const MidiTimeline> currentShared() const { return m_currentTimeline; }

    // Audio callback: acquires the latest pending snapshot, if any.
    const MidiTimeline *acquirePending()
    {
        const MidiTimeline *timeline =
            m_pendingTimeline.exchange(nullptr, std::memory_order_acq_rel);
        if (timeline)
            m_activeTimeline.store(timeline, std::memory_order_release);
        return timeline;
    }

    const MidiTimeline *active() const { return m_activeTimeline.load(std::memory_order_acquire); }

  private:
    static_assert(std::atomic<const MidiTimeline *>::is_always_lock_free,
                  "TimelineHandoff requires lock-free pointer exchange");

    // UI-thread ownership. The audio thread only observes their raw pointers.
    std::shared_ptr<const MidiTimeline> m_currentTimeline;
    std::shared_ptr<const MidiTimeline> m_retiredTimeline;

    std::atomic<const MidiTimeline *> m_pendingTimeline{nullptr};
    std::atomic<const MidiTimeline *> m_activeTimeline{nullptr};
};
