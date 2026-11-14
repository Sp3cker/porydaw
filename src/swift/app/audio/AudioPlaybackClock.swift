import Synchronization

/// A rendered cursor and its monotonic callback-end timestamp, not a hardware presentation time.
public struct AudioPlaybackClockSnapshot: Sendable {
    public let sample: UInt64
    public let uptimeNanoseconds: UInt64
    public let transport: AudioTransportState
    public let pattern: Bool
    public let timelineIdentity: UInt64
    /// Identity of the adopted pattern timeline, or zero for song playback.
    public let patternIdentity: UInt64
    public let loopStartSample: UInt64
    public let loopEndSample: UInt64
    public let looping: Bool
    /// Prediction is limited to two rendered callback buffers, even if callbacks stall.
    public let predictionFrames: UInt64

    public init(
        sample: UInt64, uptimeNanoseconds: UInt64, transport: AudioTransportState, pattern: Bool,
        timelineIdentity: UInt64, patternIdentity: UInt64 = 0,
        loopStartSample: UInt64, loopEndSample: UInt64, looping: Bool, predictionFrames: UInt64
    ) {
        self.sample = sample
        self.uptimeNanoseconds = uptimeNanoseconds
        self.transport = transport
        self.pattern = pattern
        self.timelineIdentity = timelineIdentity
        self.patternIdentity = patternIdentity
        self.loopStartSample = loopStartSample
        self.loopEndSample = loopEndSample
        self.looping = looping
        self.predictionFrames = predictionFrames
    }

    /// Predicts only a bounded number of frames from the rendered cursor.
    public func sample(at uptimeNanoseconds: UInt64, sampleRate: Double) -> UInt64 {
        guard pattern || transport == .playing, uptimeNanoseconds > self.uptimeNanoseconds,
            sampleRate.isFinite, sampleRate > 0, predictionFrames > 0
        else { return sample }
        let elapsed = Double(uptimeNanoseconds - self.uptimeNanoseconds) * sampleRate / 1_000_000_000
        let frames = elapsed >= Double(predictionFrames) ? predictionFrames : UInt64(elapsed)
        guard frames > 0 else { return sample }
        guard looping, loopEndSample > loopStartSample else {
            let (result, overflow) = sample.addingReportingOverflow(frames)
            return overflow ? UInt64.max : result
        }
        let position = sample >= loopEndSample ? loopStartSample : sample
        let untilEnd = loopEndSample - position
        guard frames >= untilEnd else { return position + frames }
        return loopStartSample + (frames - untilEnd) % (loopEndSample - loopStartSample)
    }
}

/// Single-writer seqlock; cold writers must exclude the callback. Readers never retry.
final class AudioPlaybackClock: Sendable {
    private let version = Atomic<UInt64>(0)
    private let request = Atomic<UInt64>(0)
    private let publishedRequest = Atomic<UInt64>(0)
    private let pendingChanges = Atomic<Int>(0)
    private let sample = Atomic<UInt64>(0)
    private let time = Atomic<UInt64>(0)
    private let identity = Atomic<UInt64>(0)
    private let patternIdentity = Atomic<UInt64>(0)
    private let loopStart = Atomic<UInt64>(0)
    private let loopEnd = Atomic<UInt64>(0)
    private let horizon = Atomic<UInt64>(0)
    // Bit 0: valid; bits 1-2: transport; bit 3: pattern; bit 4: looping.
    private let flags = Atomic<UInt64>(0)

    /// May be called concurrently with rendering, after publishing a control request.
    func invalidateRequest() {
        request.wrappingAdd(1, ordering: .sequentiallyConsistent)
    }

    var requestGeneration: UInt64 { request.load(ordering: .sequentiallyConsistent) }
    func beginChange() {
        pendingChanges.wrappingAdd(1, ordering: .sequentiallyConsistent)
    }

    func endChange() {
        invalidateRequest()
        pendingChanges.wrappingAdd(-1, ordering: .sequentiallyConsistent)
    }

    func invalidate() {
        version.wrappingAdd(1, ordering: .sequentiallyConsistent)
        flags.store(0, ordering: .sequentiallyConsistent)
        version.wrappingAdd(1, ordering: .sequentiallyConsistent)
    }

    func publish(_ value: AudioPlaybackClockSnapshot, requestGeneration: UInt64) {
        version.wrappingAdd(1, ordering: .sequentiallyConsistent)
        publishedRequest.store(requestGeneration, ordering: .sequentiallyConsistent)
        sample.store(value.sample, ordering: .sequentiallyConsistent)
        time.store(value.uptimeNanoseconds, ordering: .sequentiallyConsistent)
        identity.store(value.timelineIdentity, ordering: .sequentiallyConsistent)
        patternIdentity.store(value.patternIdentity, ordering: .sequentiallyConsistent)
        loopStart.store(value.loopStartSample, ordering: .sequentiallyConsistent)
        loopEnd.store(value.loopEndSample, ordering: .sequentiallyConsistent)
        horizon.store(value.predictionFrames, ordering: .sequentiallyConsistent)
        let bits =
            UInt64(1) | (UInt64(value.transport.rawValue) << 1)
            | (value.pattern ? 8 : 0) | (value.looping ? 16 : 0)
        flags.store(bits, ordering: .sequentiallyConsistent)
        version.wrappingAdd(1, ordering: .sequentiallyConsistent)
    }

    var snapshot: AudioPlaybackClockSnapshot? {
        guard pendingChanges.load(ordering: .sequentiallyConsistent) == 0 else { return nil }
        let before = version.load(ordering: .sequentiallyConsistent)
        guard before & 1 == 0 else { return nil }
        let bits = flags.load(ordering: .sequentiallyConsistent)
        let position = sample.load(ordering: .sequentiallyConsistent)
        let timestamp = time.load(ordering: .sequentiallyConsistent)
        let generation = request.load(ordering: .sequentiallyConsistent)
        let timeline = identity.load(ordering: .sequentiallyConsistent)
        let patternTimeline = patternIdentity.load(ordering: .sequentiallyConsistent)
        let start = loopStart.load(ordering: .sequentiallyConsistent)
        let end = loopEnd.load(ordering: .sequentiallyConsistent)
        let publicationGeneration = publishedRequest.load(ordering: .sequentiallyConsistent)
        let bound = horizon.load(ordering: .sequentiallyConsistent)
        guard before == version.load(ordering: .sequentiallyConsistent), bits & 1 != 0,
            generation == publicationGeneration, generation == request.load(ordering: .sequentiallyConsistent),
            pendingChanges.load(ordering: .sequentiallyConsistent) == 0,
            generation == request.load(ordering: .sequentiallyConsistent),
            let transport = AudioTransportState(rawValue: Int32((bits >> 1) & 3))
        else { return nil }
        return AudioPlaybackClockSnapshot(
            sample: position, uptimeNanoseconds: timestamp, transport: transport, pattern: bits & 8 != 0,
            timelineIdentity: timeline, patternIdentity: patternTimeline, loopStartSample: start, loopEndSample: end,
            looping: bits & 16 != 0, predictionFrames: bound)
    }
}
