import PorydawPlaybackNative
import Synchronization

/// One completed SoundMain estimate and its position in the song.
public struct AudioCpuFrame: Equatable, Sendable {
    public let sequencer: Int
    public let cgb: Int
    public let mixer: Int
    public let total: Int
    public let sample: UInt64
    public let valid: Bool
    public let sequencerEstimated: Bool
}

public struct AudioCpuBatch: Sendable {
    public let generation: UInt64
    public let frames: [AudioCpuFrame]
}

/// One audio producer and one UI consumer. Each slot is atomically versioned so
/// a slow consumer cannot observe a mixture of two frames after ring wrap.
final class AudioCpuTelemetry {
    private static let capacity = 1024
    private static let stride = 6
    private static let nativeCapacity = 64
    private let slots: UnsafeMutablePointer<Atomic<UInt64>>
    private let native: UnsafeMutablePointer<M4AFrameCost>
    private let published = Atomic<UInt64>(0)
    private let generation = Atomic<UInt64>(0)
    private var nativeCursor: UInt64 = 0
    private var consumerCursor: UInt64 = 0

    init() {
        slots = .allocate(capacity: Self.capacity * Self.stride)
        for index in 0..<(Self.capacity * Self.stride) {
            (slots + index).initialize(to: Atomic(0))
        }
        native = .allocate(capacity: Self.nativeCapacity)
        native.initialize(repeating: M4AFrameCost(), count: Self.nativeCapacity)
    }

    deinit {
        native.deinitialize(count: Self.nativeCapacity)
        native.deallocate()
        slots.deinitialize(count: Self.capacity * Self.stride)
        slots.deallocate()
    }

    /// A reset is an atomic generation change, never a write into the producer's ring.
    func reset() { generation.wrappingAdd(1, ordering: .acquiringAndReleasing) }

    /// Cold only: the old driver has been destroyed or its callback is parked.
    func resetNativeCursor() { nativeCursor = 0 }

    /// Callback only: the driver ring is read on the same thread that wrote it.
    func collect(
        driver: UnsafeMutablePointer<M4ADriver>, startCycle: UInt64, startSample: UInt64, sampleRate: Double,
        loopStart: UInt64, loopEnd: UInt64, looping: Bool
    ) {
        let epoch = generation.load(ordering: .acquiring)
        while true {
            let count = m4a_driver_cpu_read(driver, &nativeCursor, native, Self.nativeCapacity)
            if count == 0 { return }
            for index in 0..<count {
                let frame = native[index]
                let elapsed = frame.cycle >= startCycle ? frame.cycle - startCycle : 0
                let offset = UInt64(Double(elapsed) * sampleRate / 16_777_216)
                var sample = startSample &+ offset
                if looping && loopEnd > loopStart && sample >= loopEnd {
                    sample = loopStart + (sample - loopEnd) % (loopEnd - loopStart)
                }
                publish(frame, sample: sample, epoch: epoch)
            }
        }
    }

    private func publish(_ frame: M4AFrameCost, sample: UInt64, epoch: UInt64) {
        let sequence = published.load(ordering: .relaxed)
        let slot = slots + Int(sequence % UInt64(Self.capacity)) * Self.stride
        slot[0].store(sequence &* 2 &+ 1, ordering: .sequentiallyConsistent)
        slot[1].store(
            UInt64(UInt32(bitPattern: frame.sequencer))
                | UInt64(UInt32(bitPattern: frame.cgb)) << 32, ordering: .sequentiallyConsistent)
        slot[2].store(
            UInt64(UInt32(bitPattern: frame.mixer))
                | UInt64(UInt32(bitPattern: frame.total)) << 32, ordering: .sequentiallyConsistent)
        slot[3].store(sample, ordering: .sequentiallyConsistent)
        slot[4].store(epoch, ordering: .sequentiallyConsistent)
        slot[5].store((frame.valid ? 1 : 0) | (frame.sequencerEstimated ? 2 : 0), ordering: .sequentiallyConsistent)
        slot[0].store(sequence &* 2 &+ 2, ordering: .sequentiallyConsistent)
        published.store(sequence &+ 1, ordering: .releasing)
    }

    /// Control thread only. Array allocation and history maintenance happen here.
    func consume() -> AudioCpuBatch {
        let epoch = generation.load(ordering: .acquiring)
        let end = published.load(ordering: .acquiring)
        if end &- consumerCursor > UInt64(Self.capacity) {
            consumerCursor = end &- UInt64(Self.capacity)
        }
        var frames: [AudioCpuFrame] = []
        frames.reserveCapacity(Int(end &- consumerCursor))
        while consumerCursor < end {
            let sequence = consumerCursor
            consumerCursor &+= 1
            let slot = slots + Int(sequence % UInt64(Self.capacity)) * Self.stride
            let version = sequence &* 2 &+ 2
            guard slot[0].load(ordering: .sequentiallyConsistent) == version else { continue }
            let seqCgb = slot[1].load(ordering: .sequentiallyConsistent)
            let mixTotal = slot[2].load(ordering: .sequentiallyConsistent)
            let sample = slot[3].load(ordering: .sequentiallyConsistent)
            let entryEpoch = slot[4].load(ordering: .sequentiallyConsistent)
            let flags = slot[5].load(ordering: .sequentiallyConsistent)
            guard slot[0].load(ordering: .sequentiallyConsistent) == version, entryEpoch == epoch else { continue }
            frames.append(
                AudioCpuFrame(
                    sequencer: Int(Int32(bitPattern: UInt32(truncatingIfNeeded: seqCgb))),
                    cgb: Int(Int32(bitPattern: UInt32(truncatingIfNeeded: seqCgb >> 32))),
                    mixer: Int(Int32(bitPattern: UInt32(truncatingIfNeeded: mixTotal))),
                    total: Int(Int32(bitPattern: UInt32(truncatingIfNeeded: mixTotal >> 32))),
                    sample: sample, valid: flags & 1 != 0, sequencerEstimated: flags & 2 != 0))
        }
        return AudioCpuBatch(generation: epoch, frames: frames)
    }
}
