import Foundation
import PorydawAppAudio
import PorydawSample

@MainActor
public final class PcmAuditionPlayer {
    private var lane: SampleAuditionArbiter?
    private weak var owner: AnyObject?
    private var rendered: ProcessedSample?
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

    public var playing = false
    public var onPlayhead: ((Int?) -> Void)?
    public var onStarted: (() -> Void)?
    /// When set, automatic retry/gap repeats call the holder to replay fresh content.
    /// When nil, the player restarts its cached sample instead.
    public var onWillRestart: (() -> Void)?
    public var playheadPosition: Double { position }

    public init(lane: SampleAuditionArbiter?) {
        self.lane = lane
    }

    public func play(
        owner: AnyObject, rendered: ProcessedSample,
        looped requestedLoop: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) {
        guard let lane, !rendered.s8.isEmpty else {
            stop(owner: owner)
            return
        }
        self.owner = owner
        self.rendered = rendered
        self.key = key
        self.adsr = adsr
        self.toneKey = toneKey
        looped = requestedLoop && rendered.looped
        republishPending = !lane.publish(
            owner: owner, samples: rendered.s8, frequency: rendered.freq,
            loopStart: rendered.loopStart, looped: looped, key: key,
            adsr: adsr, toneKey: toneKey)
        size = rendered.s8.count
        loopStart = Int(rendered.loopStart)
        rate = Double(rendered.freq) / 1024 * pow(2, Double(Int(key) - Int(toneKey)) / 12)
        position = 0
        gap = 0
        playing = true
        onPlayhead?(0)
        if !republishPending { onStarted?() }
    }

    public func restart(looped: Bool) {
        guard let owner, let rendered else { return }
        play(owner: owner, rendered: rendered, looped: looped, key: key, adsr: adsr, toneKey: toneKey)
    }

    public func stop(owner: AnyObject) {
        lane?.stop(owner: owner)
        clearPlayback()
    }

    public func close() {
        if let owner { lane?.stop(owner: owner) }
        clearPlayback()
        lane = nil
    }

    public func advance(bySeconds dt: Double) {
        guard playing else { return }
        if republishPending {
            automaticallyRestart(looped: looped)
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
        playing = false
        republishPending = false
        owner = nil
        rendered = nil
        onPlayhead?(nil)
    }
}
