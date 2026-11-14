import Synchronization

public enum AudioTransportState: Int32, Sendable { case stopped, paused, playing }

public final class AudioTransportEndpoint: Sendable {
    let status: AudioStatus
    let volume = Atomic<Int>(100)
    let pendingSeek = Atomic<UInt64>(UInt64.max)

    init(status: AudioStatus) { self.status = status }

    public func play() {
        guard status.songLoaded else { return }
        if status.requestedTransport == .stopped { status.invalidateTelemetry() }
        status.requested.store(AudioTransportState.playing.rawValue, ordering: .relaxed)
        status.clock.invalidateRequest()
    }

    public func pause() {
        if status.requestedTransport == .playing {
            status.requested.store(AudioTransportState.paused.rawValue, ordering: .relaxed)
            status.clock.invalidateRequest()
        }
    }

    public func stop() {
        pendingSeek.store(UInt64.max, ordering: .releasing)
        status.requested.store(AudioTransportState.stopped.rawValue, ordering: .relaxed)
        status.clock.invalidateRequest()
    }

    public func seek(_ sample: UInt64) {
        if status.songLoaded {
            pendingSeek.store(sample, ordering: .releasing)
            status.clock.invalidateRequest()
        }
    }

    public func setOutputVolume(_ percent: Int) {
        volume.store(min(100, max(0, percent)), ordering: .relaxed)
    }
}

/// Owns requested transport and sample-accurate gain envelopes; no engine or publication ownership.
final class AudioTransport {
    private let status: AudioStatus
    let endpoint: AudioTransportEndpoint
    private(set) var applied = AudioTransportState.stopped {
        didSet { status.applied.store(applied.rawValue, ordering: .relaxed) }
    }
    private(set) var cutting = false
    private var rising = false
    private(set) var target = AudioTransportState.stopped
    private(set) var cutGain: Float = 1
    private var cutStep: Float = 0
    private var remaining: UInt32 = 0
    private var hold: UInt32 = 0
    private let rampSamples: UInt32
    private let settleSamples: UInt32
    private var volumeTarget = 100
    private var gain: Float = 1
    private var gainTarget: Float = 1
    private var gainStep: Float = 0
    private var gainRemaining: UInt32 = 0

    init(sampleRate: Double, periodFrames: Int, status: AudioStatus, endpoint: AudioTransportEndpoint) {
        self.status = status
        self.endpoint = endpoint
        rampSamples = max(1, UInt32(sampleRate * 0.01))
        settleSamples =
            UInt32(max(1, periodFrames)) + max(1, UInt32(sampleRate * 2 / 59.7275))
            + 2 * 1536 + max(1, UInt32((sampleRate / 8192).rounded(.up)))
    }

    var requested: AudioTransportState {
        get { status.requestedTransport }
        set { status.requested.store(newValue.rawValue, ordering: .relaxed) }
    }
    var outputVolume: Int {
        get { endpoint.volume.load(ordering: .relaxed) }
        set { endpoint.setOutputVolume(newValue) }
    }
    func stop() {
        endpoint.stop()
    }
    func resetCut() {
        cutting = false
        rising = false
        target = applied
        cutGain = 1
        cutStep = 0
        remaining = 0
        hold = 0
    }
    func reset() {
        resetCut()
        endpoint.pendingSeek.store(UInt64.max, ordering: .releasing)
        requested = .stopped
        applied = .stopped
    }
    /// Cold only: park transport without rewinding the separately owned sequencer.
    func pauseImmediately() {
        resetCut()
        endpoint.pendingSeek.store(UInt64.max, ordering: .releasing)
        requested = .paused
        applied = .paused
    }

    /// Returns true exactly when preview bookkeeping must be invalidated before the down-ramp.
    func transition() -> Bool {
        let next = requested
        if cutting {
            if !rising { target = next }
            return false
        }
        guard next != applied else { return false }
        cutting = true
        rising = false
        target = next
        hold = 0
        cutGain = min(1, max(0, cutGain))
        remaining = rampSamples
        cutStep = cutGain / Float(remaining)
        return true
    }

    func prepareVolume() {
        let next = outputVolume
        guard next != volumeTarget else { return }
        volumeTarget = next
        gainTarget = Float(next) / 100
        gainRemaining = rampSamples
        gainStep = (gainTarget - gain) / Float(rampSamples)
    }

    enum SampleAction { case none, cut(AudioTransportState, resetStats: Bool), clearSuppression }

    /// Called once per emitted stereo frame, after synthesis and suppression.
    func advance() -> SampleAction {
        if gainRemaining > 0 {
            gainRemaining -= 1
            gain = gainRemaining == 0 ? gainTarget : gain + gainStep
        }
        guard cutting else { return .none }
        if hold > 0 {
            hold -= 1
            cutGain = 0
            let clear = hold == 0 && target == .stopped
            if hold == 0 && remaining == 0 && target == .playing && applied != target {
                cutting = false
                rising = false
                cutGain = 1
                applied = target
            }
            return clear ? .clearSuppression : .none
        }
        if remaining > 0 {
            remaining -= 1
            cutGain = rising ? min(1, cutGain + cutStep) : max(0, cutGain - cutStep)
            if !rising && remaining == 0 {
                cutGain = 0
                rising = true
                remaining = rampSamples
                cutStep = 1 / Float(remaining)
                hold = settleSamples
                target = requested
                let prior = applied
                if target == .playing && prior != .playing { remaining = 0 } else { applied = target }
                return .cut(target, resetStats: target == .playing && prior == .stopped)
            }
        } else {
            cutting = false
            cutGain = 1
        }
        return .none
    }

    var outputGain: Float { gain * cutGain }
}
