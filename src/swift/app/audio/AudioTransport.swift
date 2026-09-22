import Synchronization

public enum AudioTransportState: Int32 { case stopped, paused, playing }

/// Owns requested transport and sample-accurate gain envelopes; no engine or publication ownership.
final class AudioTransport {
    private let request = Atomic<Int32>(AudioTransportState.stopped.rawValue)
    private let volume = Atomic<Int>(100)
    let pendingSeek = Atomic<UInt64>(UInt64.max)
    private(set) var applied = AudioTransportState.stopped
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

    init(sampleRate: Double, periodFrames: Int) {
        rampSamples = max(1, UInt32(sampleRate * 0.01))
        settleSamples = UInt32(max(1, periodFrames)) + max(1, UInt32(sampleRate * 2 / 59.7275))
            + 2 * 1536 + max(1, UInt32((sampleRate / 8192).rounded(.up)))
    }

    var requested: AudioTransportState {
        get { AudioTransportState(rawValue: request.load(ordering: .relaxed))! }
        set { request.store(newValue.rawValue, ordering: .relaxed) }
    }
    var outputVolume: Int {
        get { volume.load(ordering: .relaxed) }
        set { volume.store(min(100, max(0, newValue)), ordering: .relaxed) }
    }
    func stop() {
        pendingSeek.store(UInt64.max, ordering: .releasing)
        requested = .stopped
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
        pendingSeek.store(UInt64.max, ordering: .releasing)
        requested = .stopped
        applied = .stopped
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
                if target == .playing && prior != .playing { remaining = 0 }
                else { applied = target }
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
