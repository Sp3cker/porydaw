import Synchronization
import PorydawCore

/// Single control-thread producer and realtime consumer. All allocation and
/// reclamation happens on the producer; the callback only exchanges pointers.
final class AudioTimelineHandoff {
    private let pending = Atomic<UnsafeMutablePointer<PlaybackTimeline>?>(nil)
    private let adopted = Atomic<UnsafeMutablePointer<PlaybackTimeline>?>(nil)
    private var current: UnsafeMutablePointer<PlaybackTimeline>?
    private var retired: [UnsafeMutablePointer<PlaybackTimeline>] = []

    /// Borrowed until the consumer's next acquisition, or a quiescent reset.
    /// Reading a value for UI use must stay on the single producer thread.
    var active: UnsafeMutablePointer<PlaybackTimeline>? { adopted.load(ordering: .acquiring) }

    func publish(_ timeline: PlaybackTimeline) {
        let publication = Self.allocate(timeline)
        let previous = current
        current = publication
        if pending.exchange(publication, ordering: .acquiringAndReleasing) == nil {
            // Acquisition follows all callback use of older retired timelines.
            // Keep the advertised pointer too: the consumer may be between its
            // pending exchange and adopted store, and the producer can read it.
            let advertised = adopted.load(ordering: .acquiring)
            retired.removeAll { storage in
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

    func acquirePending() -> UnsafeMutablePointer<PlaybackTimeline>? {
        let publication = pending.exchange(nil, ordering: .acquiringAndReleasing)
        if let publication { adopted.store(publication, ordering: .releasing) }
        return publication
    }

    /// Cold only: callback must be quiescent before resetting or destroying.
    func reset(_ initial: PlaybackTimeline? = nil) {
        let publication = initial.map { Self.allocate($0) }
        pending.store(nil, ordering: .releasing)
        adopted.store(publication, ordering: .releasing)
        for storage in retired { Self.release(storage) }
        Self.release(current)
        retired.removeAll(keepingCapacity: true)
        current = publication
    }

    deinit { reset() }

    private static func allocate(_ timeline: PlaybackTimeline) -> UnsafeMutablePointer<PlaybackTimeline> {
        let storage = UnsafeMutablePointer<PlaybackTimeline>.allocate(capacity: 1)
        storage.initialize(to: timeline)
        return storage
    }

    private static func release(_ storage: UnsafeMutablePointer<PlaybackTimeline>?) {
        guard let storage else { return }
        storage.deinitialize(count: 1)
        storage.deallocate()
    }
}
