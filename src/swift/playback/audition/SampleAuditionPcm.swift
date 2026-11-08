/// Immutable signed 8-bit PCM plus the engine's interpolation guard sample. Audition slots retain
/// it, so retriggered notes and their release tails share one copy.
final class SampleAuditionPcm {
    let count: Int
    let data: UnsafeMutablePointer<Int8>

    /// Copies `samples` once; nil when empty or beyond the engine's 32-bit wave size.
    init?(samples: [Int8]) {
        guard let last = samples.last, samples.count <= Int(UInt32.max) else { return nil }
        count = samples.count
        data = .allocate(capacity: count + 1)
        _ = UnsafeMutableBufferPointer(start: data, count: count).initialize(fromContentsOf: samples)
        (data + count).initialize(to: last)
    }

    deinit { data.deallocate() }
}
