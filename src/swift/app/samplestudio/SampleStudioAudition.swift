import Foundation
import PorydawCore
import PorydawDocument
import PorydawSample
import PorydawSampleUI
import PorydawPlayback
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioAudition: QmlUncreatable {
    private let presenter: SampleStudioPresenter
    private let player: PcmAuditionPlayer
    private var lane: SampleAuditionArbiter?
    private let destinationAdsr: VoiceListAdsr?
    private var looped = false
    private var crop = 0
    private var ratio = 1.0

    @QtIgnored public var onPlayhead: ((Int?) -> Void)?
    @QtIgnored public var onStarted: (() -> Void)?
    public var available: Bool
    @QtTracked public var playing = false
    @QtTracked public var playText = "Listen"
    @QtTracked public var auditionKey = 60
    public var hasDestinationAdsr: Bool
    public var useDestinationAdsr: Bool

    @QtIgnored
    public init(presenter: SampleStudioPresenter, lane: SampleAuditionArbiter?, destinationAdsr: VoiceListAdsr?) {
        self.presenter = presenter
        player = PcmAuditionPlayer(lane: lane)
        self.lane = lane
        self.destinationAdsr = destinationAdsr
        available = lane?.isAvailable ?? false
        hasDestinationAdsr = destinationAdsr != nil
        useDestinationAdsr = destinationAdsr != nil
        player.onPlayhead = { [weak self] (frame: Int?) in
            guard let self else { return }
            let sourceFrame = frame.map { (_: Int) -> Int in
                self.crop + Int((self.player.playheadPosition / self.ratio).rounded())
            }
            self.onPlayhead?(sourceFrame)
        }
        player.onStarted = { [weak self] in self?.onStarted?() }
        player.onWillRestart = { [weak self] in
            // Gap restarts occur only for one-shots; retries preserve the current loop mode.
            guard let self else { return }
            self.start(looped: self.looped)
        }
        presenter.addRenderObserver { [weak self] in
            guard let self, self.playing, self.looped else { return }
            self.start(looped: true)
        }
    }

    public func toggle() {
        guard available, !presenter.processed.s8.isEmpty else { return }
        if playing { stop() } else { start(looped: presenter.processed.looped) }
    }

    public func stop() {
        playing = false
        playText = "Listen"
        player.stop(owner: self)
    }

    public func setAuditionKey(key: Int) {
        let clamped = min(max(0, key), 127)
        guard clamped != auditionKey else { return }
        auditionKey = clamped
        if playing { start(looped: looped) }
    }

    public func setUseDestinationAdsr(enabled: Bool) {
        guard hasDestinationAdsr, enabled != useDestinationAdsr else { return }
        useDestinationAdsr = enabled
        if playing { start(looped: looped) }
    }

    public func tick() { player.tick() }

    @QtIgnored public func advance(bySeconds dt: Double) {
        guard playing else { return }
        player.advance(bySeconds: dt)
    }

    @QtIgnored public func close() {
        playing = false
        playText = "Listen"
        player.close()
        lane = nil
        available = false
    }

    private func start(looped requestedLoop: Bool) {
        guard lane != nil, !presenter.processed.s8.isEmpty else { stop(); return }
        let rendered = presenter.processed
        looped = requestedLoop && rendered.looped
        let envelope: AudioADSR
        if useDestinationAdsr, let destinationAdsr {
            envelope = AudioADSR(
                attack: UInt8(clamping: destinationAdsr.attack),
                decay: UInt8(clamping: destinationAdsr.decay),
                sustain: UInt8(clamping: destinationAdsr.sustain),
                release: UInt8(clamping: destinationAdsr.release))
        } else {
            envelope = AudioADSR()
        }
        ratio =
            rendered.outputRate > 0 && presenter.source.sampleRate > 0
            ? rendered.outputRate / presenter.source.sampleRate : 1
        crop = presenter.params.cropStart
        playing = true
        playText = "Stop"
        player.play(
            owner: self, rendered: rendered, looped: looped, key: UInt8(auditionKey),
            adsr: envelope, toneKey: 60)
    }
}
