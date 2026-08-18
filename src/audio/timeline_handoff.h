#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <utility>

#include "core/miditimeline.h"

// Single-producer (UI thread), single-consumer (Audio thread) lock-free snapshot
// handoff for MidiTimeline using double-buffered atomic publications.
//
// Thread Model:
//  - UI Thread (Hot): Calls publish() and reclaim(). Retains shared ownership
//    of active and retired timelines until audio callback acknowledgement.
//    Zero dynamic heap allocations.
//  - UI Thread (Cold): Calls reset() or adoptImmediately() ONLY when the audio
//    device is stopped or audio callback is quiesced.
//  - Audio Callback (Hot): Calls acquirePending(), active(), and acknowledge().
//    Guaranteed zero allocations, zero deallocations, zero locks, zero shared_ptr writes.
class TimelineHandoff
{
  public:
    TimelineHandoff() = default;

    // Cold: destruction must only occur when the audio callback is quiesced.
    ~TimelineHandoff() { reset(); }

    TimelineHandoff(const TimelineHandoff &) = delete;
    TimelineHandoff &operator=(const TimelineHandoff &) = delete;

    // =========================================================================
    // UI Thread (Single Producer)
    // =========================================================================

    // Publishes a new shared snapshot for the audio thread. Non-blocking and
    // zero heap allocations.
    void publish(std::shared_ptr<const MidiTimeline> timeline)
    {
        reclaim();
        if (!timeline)
            return;

        const uint64_t generation = ++m_nextGeneration;

        // If the audio thread already adopted the previous snapshot, retire it
        // until this new generation is acknowledged. If the audio thread hasn't
        // picked up the previous pending snapshot yet, that unadopted snapshot
        // is simply replaced in place.
        if (m_currentTimeline) {
            m_retiredTimeline = std::move(m_currentTimeline);
            m_retiredReleaseGeneration = generation;
        }
        m_currentTimeline = std::move(timeline);

        // Populate the next publication slot (alternate between 0 and 1)
        m_slotIndex ^= 1;
        Publication &pub = m_slots[m_slotIndex];
        pub.timeline = m_currentTimeline.get();
        pub.generation = generation;

        // Atomically publish the slot pointer (single atomic pointer exchange)
        m_pendingPublication.exchange(&pub, std::memory_order_acq_rel);
    }

    // Reclaims retired snapshots once acknowledged by the audio callback.
    void reclaim()
    {
        const uint64_t applied = m_appliedGeneration.load(std::memory_order_acquire);
        if (m_retiredTimeline && applied >= m_retiredReleaseGeneration)
            m_retiredTimeline.reset();
    }

    // Cold adoption: immediately updates the active timeline when the audio device
    // is not running callbacks (e.g. headless/offscreen tests).
    void adoptImmediately()
    {
        Publication *pub = m_pendingPublication.exchange(nullptr, std::memory_order_acq_rel);
        if (!pub)
            return;
        m_activeTimeline.store(pub->timeline, std::memory_order_release);
        m_appliedGeneration.store(pub->generation, std::memory_order_release);
        reclaim();
    }

    // Cold reset: clears publication state and snapshot ownership.
    // Precondition: Audio device must be stopped or audio callback quiesced.
    void reset(std::shared_ptr<const MidiTimeline> initial = nullptr)
    {
        m_pendingPublication.store(nullptr, std::memory_order_release);
        m_appliedGeneration.store(m_nextGeneration, std::memory_order_release);
        m_retiredTimeline.reset();
        m_retiredReleaseGeneration = 0;
        m_currentTimeline = std::move(initial);
        m_activeTimeline.store(m_currentTimeline.get(), std::memory_order_release);
    }

    // Latest published snapshot for UI-thread inspection
    const MidiTimeline *current() const { return m_currentTimeline.get(); }
    std::shared_ptr<const MidiTimeline> currentShared() const { return m_currentTimeline; }

    // =========================================================================
    // Audio Thread (Single Consumer)
    // =========================================================================

    struct Adoption {
        const MidiTimeline *raw = nullptr;
        uint64_t generation = 0;
    };

    // Checks for a pending update at the start of the audio callback.
    // Returns non-null raw pointer and generation if a replacement is ready.
    Adoption acquirePending()
    {
        Publication *pub = m_pendingPublication.exchange(nullptr, std::memory_order_acq_rel);
        if (!pub)
            return {nullptr, 0};
        m_activeTimeline.store(pub->timeline, std::memory_order_release);
        return {pub->timeline, pub->generation};
    }

    // Acknowledges that the audio callback has rendered through this generation.
    void acknowledge(uint64_t generation)
    {
        m_appliedGeneration.store(generation, std::memory_order_release);
    }

    // Active raw pointer currently held by the audio thread (acquire semantics)
    const MidiTimeline *active() const { return m_activeTimeline.load(std::memory_order_acquire); }

  private:
    struct Publication {
        const MidiTimeline *timeline = nullptr;
        uint64_t generation = 0;
    };

    static_assert(std::atomic<Publication *>::is_always_lock_free,
                  "TimelineHandoff requires lock-free pointer exchange");
    static_assert(std::atomic<uint64_t>::is_always_lock_free,
                  "TimelineHandoff requires lock-free 64-bit generation tracking");
    static_assert(std::atomic<const MidiTimeline *>::is_always_lock_free,
                  "TimelineHandoff requires lock-free active pointer access");

    // UI-thread state (single producer)
    std::shared_ptr<const MidiTimeline> m_currentTimeline;
    std::shared_ptr<const MidiTimeline> m_retiredTimeline;
    uint64_t m_retiredReleaseGeneration = 0;
    uint64_t m_nextGeneration = 0;
    Publication m_slots[2]{};
    int m_slotIndex = 0;

    // Inter-thread synchronization atomics
    std::atomic<Publication *> m_pendingPublication{nullptr};
    std::atomic<uint64_t> m_appliedGeneration{0};
    std::atomic<const MidiTimeline *> m_activeTimeline{nullptr};
};
