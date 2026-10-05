import Foundation
import PorydawCore
import PorydawSample
import PorydawPlayback
import QtBridge

@MainActor
public protocol SampleAuditionOutput: AnyObject {
    func auditionSample(
        samples: [Int8], frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool
    func auditionSampleOff()
}

extension NativeAudio: SampleAuditionOutput {}

@MainActor
@QtBridgeable
public final class SampleStudioAudition: QmlUncreatable {
    private let presenter: SampleStudioPresenter
    private weak var output: (any SampleAuditionOutput)?
    private let destinationAdsr: VoiceListAdsr?
    private var looped = false
    private var size = 0
    private var loopStart = 0
    private var crop = 0
    private var ratio = 1.0
    private var rate = 0.0
    private var position = 0.0
    private var gap = 0.0
    private var republishPending = false
    private var lastTick: ContinuousClock.Instant?

    @QtIgnored public var onPlayhead: ((Int?) -> Void)?
    public var available: Bool
    @QtTracked public var playing = false
    @QtTracked public var playText = "Play"
    public var playToolTip: String
    @QtTracked public var auditionKey = 60
    @QtTracked public var auditionKeyText = "C4 (60)"
    public var hasDestinationAdsr: Bool
    public var useDestinationAdsr: Bool

    @QtIgnored
    public init(presenter: SampleStudioPresenter, output: SampleAuditionOutput?, destinationAdsr: VoiceListAdsr?) {
        self.presenter = presenter
        self.output = output
        self.destinationAdsr = destinationAdsr
        available = output != nil
        hasDestinationAdsr = destinationAdsr != nil
        useDestinationAdsr = destinationAdsr != nil
        playToolTip =
            output == nil
            ? "Audio is unavailable."
            : "Audition the render — looped when the loop is enabled; one-shots repeat with a short gap until stopped. Space toggles this from anywhere in the dialog."
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
        output?.auditionSampleOff()
        playing = false
        playText = "Play"
        republishPending = false
        lastTick = nil
        onPlayhead?(nil)
    }

    public func setAuditionKeyText(text: String) {
        guard let key = SampleStudioReadouts.midiKey(from: text), key != auditionKey else { return }
        auditionKey = key
        auditionKeyText = "\(midiKeyName(key)) (\(key))"
        if playing { start(looped: looped) }
    }

    public func setUseDestinationAdsr(enabled: Bool) {
        guard hasDestinationAdsr, enabled != useDestinationAdsr else { return }
        useDestinationAdsr = enabled
        if playing { start(looped: looped) }
    }

    public func tick() {
        let now = ContinuousClock.now
        defer { lastTick = now }
        guard let lastTick else { return }
        let duration = lastTick.duration(to: now)
        advance(bySeconds: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    @QtIgnored public func advance(bySeconds dt: Double) {
        guard playing else { return }
        if republishPending {
            start(looped: looped)
            return
        }
        guard dt.isFinite, dt >= 0 else { return }
        if gap > 0 {
            gap -= dt
            if gap <= 0 { start(looped: false) }
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
        onPlayhead?(crop + Int((position / ratio).rounded()))
    }

    @QtIgnored public func close() {
        stop()
        output = nil
        available = false
    }

    private func start(looped requestedLoop: Bool) {
        guard let output, !presenter.processed.s8.isEmpty else { stop(); return }
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
        republishPending = !output.auditionSample(
            samples: rendered.s8, frequency: rendered.freq,
            loopStart: rendered.loopStart, looped: looped, key: UInt8(auditionKey),
            adsr: envelope, toneKey: 60)
        size = rendered.s8.count
        loopStart = Int(rendered.loopStart)
        rate = Double(rendered.freq) / 1024 * pow(2, Double(auditionKey - 60) / 12)
        ratio =
            rendered.outputRate > 0 && presenter.source.sampleRate > 0
            ? rendered.outputRate / presenter.source.sampleRate : 1
        crop = presenter.params.cropStart
        position = 0
        gap = 0
        lastTick = ContinuousClock.now
        playing = true
        playText = "Stop"
        onPlayhead?(crop)
    }
}
