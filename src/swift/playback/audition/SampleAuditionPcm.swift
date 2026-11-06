import Dispatch
import Foundation

/// Immutable native PCM storage shared by audition notes and their release tails.
/// Preparation and final reclamation run off the main actor; publication only retains it.
public final class SampleAuditionPcm {
    actor Allocation {
        private static let queue = DispatchSerialQueue(label: "porydaw.audition.reclaim", qos: .utility)

        nonisolated var unownedExecutor: UnownedSerialExecutor {
            Self.queue.asUnownedSerialExecutor()
        }
        private let bytes: DispatchData

        init(bytes: DispatchData) { self.bytes = bytes }

        /// Drains previously queued isolated destruction without retaining its allocation.
        static func reclamationSettled() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async { continuation.resume() }
            }
        }

        // Default actors can deinitialize inline; this executor keeps native frees off main.
        isolated deinit {}
    }

    public let count: Int
    let data: UnsafeMutablePointer<Int8>
    private let allocation: Allocation

    init?(samples: [Int8]) {
        guard !samples.isEmpty, samples.count <= Int(UInt32.max) else { return nil }
        guard let raw = malloc(samples.count + 1) else { return nil }
        count = samples.count
        let bytes = DispatchData(
            bytesNoCopy: UnsafeRawBufferPointer(start: raw, count: count + 1), deallocator: .free)
        allocation = Allocation(bytes: bytes)
        data = raw.bindMemory(to: Int8.self, capacity: count + 1)
        samples.withUnsafeBufferPointer { (source: UnsafeBufferPointer<Int8>) in
            guard let base = source.baseAddress else {
                preconditionFailure("Nonempty audition PCM must have storage")
            }
            data.initialize(from: base, count: source.count)
        }
        data.advanced(by: count).initialize(to: samples[count - 1])
    }

    /// Copies a new PCM payload once, including the native interpolation guard byte.
    /// - Returns: Uniquely transferred storage, or nil for empty, oversized or cancelled input.
    @concurrent
    public static func prepare(samples: [Int8]) async -> sending SampleAuditionPcm? {
        guard !Task.isCancelled else { return nil }
        let pcm = SampleAuditionPcm(samples: samples)
        return Task.isCancelled ? nil : pcm
    }

}
