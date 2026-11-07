import Foundation
import PorydawAppAudio
import PorydawPlayback
import PorydawSample

@MainActor
public final class PcmAuditionPlayer {
    private var audition: AudioAudition?
    private var lease: SampleAuditionLease?
    private var rendered: ProcessedSample?
    // Replays of one render (key, envelope, stop/listen, Busy retries) reuse its native copy.
    private var prepared: (source: [Int8], pcm: SampleAuditionPcm)?
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

    public init(audition: AudioAudition?) {
        self.audition = audition
    }

    /// Busy slots leave the lease held; `advance` retries until a slot retires or the lease is superseded.
    private func publish() {
        guard let lease, let rendered, let pcm = prepared?.pcm else { return }
        republishPending = !lease.publish(
            pcm: pcm, frequency: rendered.freq, loopStart: rendered.loopStart,
            looped: looped, key: key, adsr: adsr, toneKey: toneKey)
        if !republishPending { onStarted?() }
    }

    public func play(
        rendered: ProcessedSample, looped requestedLoop: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) {
        guard let audition, !rendered.s8.isEmpty else {
            stop()
            return
        }
        // Array equality short-circuits on shared storage, so replaying one render never recopies it.
        if prepared?.source != rendered.s8 {
            guard let pcm = SampleAuditionPcm(samples: rendered.s8) else {
                stop()
                return
            }
            prepared = (rendered.s8, pcm)
        }
        lease = audition.beginSample()
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
        lastTick = ContinuousClock.now
        playing = true
        onPlayhead?(0)
        publish()
    }

    public func restart(looped: Bool) {
        guard let rendered else { return }
        play(rendered: rendered, looped: looped, key: key, adsr: adsr, toneKey: toneKey)
    }

    public func stop() {
        lease?.stop()
        clearPlayback()
    }

    public func close() {
        stop()
        prepared = nil
        audition = nil
    }

    public func tick() {
        let now = ContinuousClock.now
        defer { lastTick = now }
        guard let lastTick else { return }
        let duration = lastTick.duration(to: now)
        advance(bySeconds: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    public func advance(bySeconds dt: Double) {
        guard playing else { return }
        guard lease?.isCurrent == true else {
            clearPlayback()
            return
        }
        if republishPending {
            publish()
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
        let wasPlaying = playing
        playing = false
        lease = nil
        lastTick = nil
        republishPending = false
        rendered = nil
        onPlayhead?(nil)
        if wasPlaying { onTerminated?() }
    }
}
