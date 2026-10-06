import Synchronization
import PorydawCore

/// Single control-thread producer and realtime consumer. All allocation and
/// reclamation happens on the producer; the callback only exchanges pointers.
final class AudioTimelineHandoff {
    private let pending = Atomic<UnsafeMutablePointer<PlaybackTimeline>?>(nil)
    private let adopted = Atomic<UnsafeMutablePointer<PlaybackTimeline>?>(nil)
    private var current: UnsafeMutablePointer<PlaybackTimeline>?
    private var retired: [UnsafeMutablePointer<PlaybackTimeline>] = []
    private var free: [UnsafeMutablePointer<PlaybackTimeline>] = []

    /// Borrowed until the consumer's next acquisition, or a quiescent reset.
    /// Reading a value for UI use must stay on the single producer thread.
    var active: UnsafeMutablePointer<PlaybackTimeline>? { adopted.load(ordering: .acquiring) }

    func publish(_ timeline: PlaybackTimeline, reclaim: (PlaybackTimeline) -> Void = { _ in }) {
        let publication = allocate(timeline)
        let previous = current
        current = publication
        if pending.exchange(publication, ordering: .acquiringAndReleasing) == nil {
            // Keep the advertised pointer across the consumer's pending→adopted update.
            // The producer also reads the advertised pointer.
            let advertised = adopted.load(ordering: .acquiring)
            retired.removeAll { storage in
                guard storage != advertised else { return false }
                release(storage, reclaim: reclaim)
                return true
            }
            if let previous { retired.append(previous) }
        } else {
            // The replaced pending snapshot was never acquired by the callback.
            if let previous { release(previous, reclaim: reclaim) }
        }
    }

    func acquirePending() -> UnsafeMutablePointer<PlaybackTimeline>? {
        let publication = pending.exchange(nil, ordering: .acquiringAndReleasing)
        if let publication { adopted.store(publication, ordering: .releasing) }
        return publication
    }

    /// Cold only: callback must be quiescent before resetting or destroying.
    func reset(_ initial: PlaybackTimeline? = nil) {
        pending.store(nil, ordering: .releasing)
        adopted.store(nil, ordering: .releasing)
        for storage in retired { release(storage) }
        if let current { release(current) }
        retired.removeAll(keepingCapacity: true)
        current = initial.map { allocate($0) }
        adopted.store(current, ordering: .releasing)
    }

    deinit {
        reset()
        for storage in free { storage.deallocate() }
    }

    private func allocate(_ timeline: PlaybackTimeline) -> UnsafeMutablePointer<PlaybackTimeline> {
        let storage = free.popLast() ?? UnsafeMutablePointer<PlaybackTimeline>.allocate(capacity: 1)
        storage.initialize(to: timeline)
        return storage
    }

    private func release(
        _ storage: UnsafeMutablePointer<PlaybackTimeline>,
        reclaim: (PlaybackTimeline) -> Void = { _ in }
    ) {
        let timeline = storage.move()
        free.append(storage)
        reclaim(timeline)
    }
}
