import PorydawPlayback
import Synchronization

// One callback writer and one main-thread reader publish indices with release/acquire.
// Storage is reclaimed only after slot detachment and reader shutdown; neither side waits.
public final class LiveTakeRing: @unchecked Sendable {
    public static let capacity = 8192
    private let storage: ManagedBuffer<Void, LiveTakeEvent>
    private let readIndex = Atomic<UInt64>(0)
    private let writeIndex = Atomic<UInt64>(0)
    private let lost = Atomic<UInt64>(0)

    public init() {
        storage = ManagedBuffer<Void, LiveTakeEvent>.create(minimumCapacity: Self.capacity) {
            (_: ManagedBuffer<Void, LiveTakeEvent>) in ()
        }
        storage.withUnsafeMutablePointerToElements { (elements: UnsafeMutablePointer<LiveTakeEvent>) in
            elements.initialize(repeating: LiveTakeEvent(), count: Self.capacity)
        }
    }

    deinit {
        storage.withUnsafeMutablePointerToElements { (elements: UnsafeMutablePointer<LiveTakeEvent>) in
            _ = elements.deinitialize(count: Self.capacity)
        }
    }

    public var dropped: UInt64 { lost.load(ordering: .relaxed) }
    public var degraded: Bool { dropped != 0 }

    /// Called only by the attached slot's callback producer.
    @discardableResult
    public func push(_ entry: LiveTakeEvent) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        guard write &- readIndex.load(ordering: .acquiring) < UInt64(Self.capacity) else {
            lost.wrappingAdd(1, ordering: .relaxed)
            return false
        }
        storage.withUnsafeMutablePointerToElements { (elements: UnsafeMutablePointer<LiveTakeEvent>) in
            var slot = MutableSpan(_unsafeStart: elements.advanced(by: Int(write % UInt64(Self.capacity))), count: 1)
            slot[0] = entry
        }
        writeIndex.store(write &+ 1, ordering: .releasing)
        return true
    }

    /// Called only by the main-thread consumer.
    public func pop() -> LiveTakeEvent? {
        let read = readIndex.load(ordering: .relaxed)
        guard read != writeIndex.load(ordering: .acquiring) else { return nil }
        let entry = storage.withUnsafeMutablePointerToElements { (elements: UnsafeMutablePointer<LiveTakeEvent>) in
            let slot = Span(_unsafeStart: elements.advanced(by: Int(read % UInt64(Self.capacity))), count: 1)
            return slot[0]
        }
        readIndex.store(read &+ 1, ordering: .releasing)
        return entry
    }
}
