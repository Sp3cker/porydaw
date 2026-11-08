import Synchronization
import PorydawCore

struct AudioTimelinePublication {
    let timeline: PlaybackTimeline
    let identity: UInt64
}

/// Single control-thread producer and realtime consumer. All allocation and
/// reclamation happens on the producer; the callback only exchanges pointers.
final class AudioTimelineHandoff {
    private let pending = Atomic<UnsafeMutablePointer<AudioTimelinePublication>?>(nil)
    private let adopted = Atomic<UnsafeMutablePointer<AudioTimelinePublication>?>(nil)
    private var current: UnsafeMutablePointer<AudioTimelinePublication>?
    private var retired: [UnsafeMutablePointer<AudioTimelinePublication>] = []

    /// Borrowed only by control while parked, or by the callback until its next acquisition.
    var active: UnsafeMutablePointer<AudioTimelinePublication>? { adopted.load(ordering: .acquiring) }
    /// Producer-owned: whether a timeline has been published since the last empty reset,
    /// including one the consumer has not yet acquired.
    var isPublished: Bool { current != nil }

    func publish(_ timeline: PlaybackTimeline, identity: UInt64 = 0) {
        let publication = Self.allocate(timeline, identity: identity)
        let previous = current
        current = publication
        if pending.exchange(publication, ordering: .acquiringAndReleasing) == nil {
            // Acquisition follows all callback use of older retired timelines.
            // Keep the advertised pointer too: the consumer may be between its
            // pending exchange and adopted store, and the producer can read it.
            let advertised = adopted.load(ordering: .acquiring)
            retired.removeAll { (storage: UnsafeMutablePointer<AudioTimelinePublication>) in
                guard storage != advertised else { return false }
                Self.release(storage)
                return true
            }
            if let previous { retired.append(previous) }
        } else {
            // The replaced pending snapshot was never acquired by the callback.
            Self.release(previous)
        }
    }

    func acquirePending() -> UnsafeMutablePointer<AudioTimelinePublication>? {
        let publication = pending.exchange(nil, ordering: .acquiringAndReleasing)
        if let publication { adopted.store(publication, ordering: .releasing) }
        return publication
    }

    /// Cold only: callback must be quiescent before resetting or destroying.
    func reset(_ initial: PlaybackTimeline? = nil, identity: UInt64 = 0) {
        let publication = initial.map { (timeline: PlaybackTimeline) in Self.allocate(timeline, identity: identity) }
        pending.store(nil, ordering: .releasing)
        adopted.store(publication, ordering: .releasing)
        for storage in retired { Self.release(storage) }
        Self.release(current)
        retired.removeAll(keepingCapacity: true)
        current = publication
    }

    deinit { reset() }

    private static func allocate(
        _ timeline: PlaybackTimeline, identity: UInt64
    ) -> UnsafeMutablePointer<AudioTimelinePublication> {
        let storage = UnsafeMutablePointer<AudioTimelinePublication>.allocate(capacity: 1)
        storage.initialize(to: AudioTimelinePublication(timeline: timeline, identity: identity))
        return storage
    }

    private static func release(_ storage: UnsafeMutablePointer<AudioTimelinePublication>?) {
        guard let storage else { return }
        storage.deinitialize(count: 1)
        storage.deallocate()
    }
}
