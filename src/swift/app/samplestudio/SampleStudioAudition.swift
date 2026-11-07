import Foundation
import PorydawAppAudio
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
    private let destinationAdsr: VoiceListAdsr?
    private let isAudioAvailable: () -> Bool
    private var looped = false
    private var crop = 0
    private var closed = false
    private var ratio = 1.0

    @QtIgnored public var onPlayhead: ((Int?) -> Void)?
    public private(set) var lastPublishedRenderRevision = -1
    @QtTracked public var available = false
    @QtTracked public var playing = false
    @QtTracked public var playText = "Listen"
    @QtTracked public var auditionKey = 60
    public var hasDestinationAdsr: Bool
    public var useDestinationAdsr: Bool

    @QtIgnored
    public init(
        presenter: SampleStudioPresenter,
        beginSampleAudition: @escaping (@escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease?,
        isAudioAvailable: @escaping () -> Bool,
        destinationAdsr: VoiceListAdsr?
    ) {
        self.presenter = presenter
        player = PcmAuditionPlayer(beginSampleAudition: beginSampleAudition)
        self.destinationAdsr = destinationAdsr
        self.isAudioAvailable = isAudioAvailable
        hasDestinationAdsr = destinationAdsr != nil
        useDestinationAdsr = destinationAdsr != nil
        available = isAudioAvailable()
        player.onPlayhead = { [weak self] (frame: Int) in
            guard let self else { return }
            self.onPlayhead?(self.crop + Int((Double(frame) / self.ratio).rounded()))
        }
        player.onLifecycle = { [weak self] (lifecycle: PcmAuditionPlayer.Lifecycle) in
            guard let self else { return }
            switch lifecycle {
            case .starting, .sounding:
                self.playing = true
                self.playText = "Stop"
                if case .starting = lifecycle { self.onPlayhead?(nil) }
            case .repeatGap:
                self.onPlayhead?(nil)
            case .ended:
                self.playing = false
                self.playText = "Listen"
                self.onPlayhead?(nil)
            }
        }
        presenter.addRenderObserver { [weak self] in
            guard let self, self.player.canRepublish else { return }
            guard let note = self.makeNote() else { self.player.stop(); return }
            self.player.republish(note)
        }
    }

    public func toggle() {
        refreshAvailability()
        guard !closed else { return }
        if playing { stop() } else if available { start() }
    }

    public func stop() { player.stop() }

    public func setAuditionKey(key: Int) {
        let clamped = min(max(0, key), 127)
        guard clamped != auditionKey else { return }
        auditionKey = clamped
        if player.canRepublish, let note = makeNote() { player.republish(note) }
    }

    public func setUseDestinationAdsr(enabled: Bool) {
        guard hasDestinationAdsr, enabled != useDestinationAdsr else { return }
        useDestinationAdsr = enabled
        if player.canRepublish, let note = makeNote() { player.republish(note) }
    }

    public func tick() { player.tick() }

    @QtIgnored public func advance(bySeconds dt: Double) { player.advance(bySeconds: dt) }

    @QtIgnored public func refreshAvailability() {
        available = !closed && isAudioAvailable()
    }

    @QtIgnored public func close() {
        closed = true
        available = false
        player.close()
    }

    private func start() {
        guard !presenter.processed.s8.isEmpty, let lease = player.claim() else { return }
        looped = presenter.processed.looped
        guard let note = makeNote() else { lease.stop(); return }
        player.play(
            note, lease: lease,
            repeatPolicy: .repeatFresh { [weak self] () -> SampleAuditionNote? in
                self?.makeNote()
            })
    }

    private func makeNote() -> SampleAuditionNote? {
        let rendered = presenter.processed
        guard !rendered.s8.isEmpty else { return nil }
        lastPublishedRenderRevision = presenter.renderRevision
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
            rendered.outputRate > 0 && presenter.renderedSource.sampleRate > 0
            ? rendered.outputRate / presenter.renderedSource.sampleRate : 1
        crop = presenter.renderedParams.cropStart
        return SampleAuditionNote(
            id: .unassigned,
            source: .pcm(
                samples: rendered.s8, frequency: rendered.freq, loopStart: rendered.loopStart,
                looped: looped && rendered.looped),
            key: UInt8(auditionKey), adsr: envelope, toneKey: 60)
    }
}
