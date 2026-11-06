import Foundation
import PorydawAppAudio
import PorydawPlayback
import PorydawSample

@MainActor
public final class PcmAuditionPlayer {
    typealias Preparation = @Sendable ([Int8]) async -> sending SampleAuditionPcm?
    private let preparePcm: Preparation
    private var lane: SampleAuditionArbiter?
    private weak var owner: AnyObject?
    private var request: UInt64?
    private var rendered: ProcessedSample?
    private var preparedPcm: SampleAuditionPcm?
    private var preparedRevision: UInt64 = 0
    private var preparation: Task<Void, Never>?
    private var preparingRevision: UInt64?
    private var key: UInt8 = 60
    private var adsr = AudioADSR()
    private var toneKey: UInt8 = 60
    private var looped = false
    private var size = 0
    private var loopStart = 0
    private var rate = 0.0
    private var position = 0.0
    private var gap = 0.0
    private var republishPending = false
    private var lastTick: ContinuousClock.Instant?

    public var playing = false
    public var onPlayhead: ((Int?) -> Void)?
    public var onStarted: (() -> Void)?
    /// Automatic one-shot gap repeats may request fresh content from the holder.
    public var onWillRestart: (() -> Void)?
    /// Playback is already false when the holder is notified; it must not stop a successor.
    public var onTerminated: (() -> Void)?
    public var playheadPosition: Double { position }

    public init(lane: SampleAuditionArbiter?) {
        self.lane = lane
        preparePcm = { samples in await SampleAuditionPcm.prepare(samples: samples) }
    }

    init(lane: SampleAuditionArbiter?, prepare: @escaping Preparation) {
        self.lane = lane
        preparePcm = prepare
    }

    /// Waits through the running preparation and any newest-content replacement it starts.
    func preparationSettled() async {
        while let preparation { await preparation.value }
    }

    isolated deinit { preparation?.cancel() }

    private func publishPrepared() {
        guard let lane, let owner, let request else {
            clearPlayback()
            return
        }
        guard let rendered, let preparedPcm, preparedRevision == rendered.pcmRevision else { return }
        guard lane.isCurrent(owner: owner, request: request) else {
            clearPlayback()
            return
        }
        republishPending = !lane.publish(
            owner: owner, request: request, pcm: preparedPcm,
            frequency: rendered.freq, loopStart: rendered.loopStart,
            looped: looped, key: key, adsr: adsr, toneKey: toneKey)
        lastTick = ContinuousClock.now
        if !republishPending {
            onPlayhead?(0)
            onStarted?()
        }
    }

    private func prepareLatest() {
        guard playing, let rendered else { return }
        guard let owner, let request, lane?.isCurrent(owner: owner, request: request) == true else {
            clearPlayback()
            return
        }
        if preparedRevision == rendered.pcmRevision, preparedPcm != nil {
            preparation?.cancel()
            publishPrepared()
            return
        }
        if preparation != nil {
            if preparingRevision != rendered.pcmRevision { preparation?.cancel() }
            return
        }
        let revision = rendered.pcmRevision
        let samples = rendered.s8
        preparingRevision = revision
        let prepare = preparePcm
        preparation = Task { [weak self] in
            let pcm = await prepare(samples)
            guard let self else { return }
            self.preparation = nil
            self.preparingRevision = nil
            guard self.playing else { return }
            if !Task.isCancelled, self.rendered?.pcmRevision == revision, let pcm {
                self.preparedPcm = pcm
                self.preparedRevision = revision
                self.publishPrepared()
            } else if !Task.isCancelled, self.rendered?.pcmRevision == revision {
                self.stopCurrent()
            } else if self.preparedRevision != self.rendered?.pcmRevision {
                self.prepareLatest()
            }
        }
    }

    public func play(
        owner: AnyObject, rendered: ProcessedSample,
        looped requestedLoop: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) {
        guard let lane, !rendered.s8.isEmpty, let request = lane.begin(owner: owner) else {
            stop(owner: owner)
            return
        }
        self.owner = owner
        self.request = request
        self.rendered = rendered
        self.key = key
        self.adsr = adsr
        self.toneKey = toneKey
        looped = requestedLoop && rendered.looped
        size = rendered.s8.count
        loopStart = Int(rendered.loopStart)
        rate = Double(rendered.freq) / 1024 * pow(2, Double(Int(key) - Int(toneKey)) / 12)
        position = 0
        gap = 0
        lastTick = nil
        republishPending = false
        playing = true
        prepareLatest()
    }

    public func restart(looped: Bool) {
        guard let owner, let rendered else { return }
        play(owner: owner, rendered: rendered, looped: looped, key: key, adsr: adsr, toneKey: toneKey)
    }

    public func stop(owner: AnyObject) {
        if let request, lane?.isCurrent(owner: owner, request: request) == true {
            lane?.stop(owner: owner)
        }
        clearPlayback()
    }

    private func stopCurrent() {
        if let owner, let request, lane?.isCurrent(owner: owner, request: request) == true {
            lane?.stop(owner: owner)
        }
        clearPlayback()
    }

    public func close() {
        stopCurrent()
        preparedPcm = nil
        preparedRevision = 0
        lane = nil
    }

    public func tick() {
        let now = ContinuousClock.now
        defer { if lastTick != nil { lastTick = now } }
        guard let lastTick else {
            advance(bySeconds: 0)
            return
        }
        let duration = lastTick.duration(to: now)
        advance(bySeconds: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    public func advance(bySeconds dt: Double) {
        guard playing else { return }
        guard let owner, let request, lane?.isCurrent(owner: owner, request: request) == true else {
            clearPlayback()
            return
        }
        guard lastTick != nil else { return }
        if republishPending {
            publishPrepared()
            return
        }
        guard dt.isFinite, dt >= 0 else { return }
        if gap > 0 {
            gap -= dt
            if gap <= 0 { automaticallyRestart(looped: false) }
            return
        }
        position += dt * rate
        if looped {
            let length = Double(size - loopStart)
            if length > 0, position >= Double(size) {
                position = Double(loopStart) + (position - Double(loopStart)).truncatingRemainder(dividingBy: length)
            }
        } else if position >= Double(size) {
            gap = 0.5
            onPlayhead?(nil)
            return
        }
        onPlayhead?(Int(position.rounded()))
    }

    private func automaticallyRestart(looped: Bool) {
        if let onWillRestart { onWillRestart() } else { restart(looped: looped) }
    }

    private func clearPlayback() {
        preparation?.cancel()
        let wasPlaying = playing
        playing = false
        request = nil
        owner = nil
        lastTick = nil
        republishPending = false
        rendered = nil
        onPlayhead?(nil)
        if wasPlaying { onTerminated?() }
    }
}
