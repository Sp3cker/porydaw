import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

/// The shell's transport chrome reads the same engine and document as the editor.
/// The clock is sampled from the audio device, never extrapolated from wall time.
@MainActor
@QtBridgeable
public final class TransportBarPresenter: QmlUncreatable {
    private weak var session: ApplicationSession?

    @QtTracked public var state = 0  // unavailable, stopped, paused, playing
    @QtTracked public var timeText = "0:00.0 / 0:00.0"
    @QtTracked public var measureText = "1:1"
    @QtTracked public var loopEnabled = true
    @QtTracked public var loopBounds = ""
    @QtTracked public var masterVolume = 127
    @QtTracked public var outputVolume = 100
    @QtTracked public var tempo = TimeDefaults.tempoBPM
    @QtTracked public var keySignature = "C"
    @QtTracked public var scaleRoot = ScaleID.defaultRoot
    @QtTracked public var scaleType = ScaleID.defaultScale.rawValue
    @QtTracked public var scaleHighlight = false
    @QtTracked public var scaleFold = false
    @QtTracked public var scaleNames = ScaleID.displayOrder.map(\.displayName)
    @QtTracked public var followPlayhead = true
    @QtTracked public var resonanceSuppression = false
    @QtTracked public var polyMeterVisible = false
    @QtTracked public var pcmText = ""
    @QtTracked public var cgbText = ""
    @QtTracked public var lostText = ""
    @QtTracked public var lostVisible = false
    @QtTracked public var promptStyle = PromptStyle()
    private weak var keyDocument: SongDocument?
    private var keyRevision: UInt64 = 0
    private var keyEvents: [(tick: Tick, label: String)] = []

    public init() {}

    @QtIgnored public var onAvailabilityChanged: (() -> Void)?

    @QtIgnored public func attach(session: ApplicationSession) {
        self.session = session
        refresh()
    }

    public func refreshPromptStyle(inset: Double) {
        guard let session else { return }
        var metrics = PromptAppearance.Layout(base: Double(session.baseFontPx))
        metrics.radius = inset / 2
        metrics.horizontalPadding = inset
        metrics.verticalPadding = 0
        metrics.dragThreshold = inset
        promptStyle.update(
            metrics: metrics, palette: session.palette, font: session.typographyFonts.body,
            surface: .transport)
    }

    @QtIgnored
    func audioBecameReady(_ audio: NativeAudio) {
        audio.setOutputVolume(outputVolume)
        audio.setResonanceSuppression(resonanceSuppression)
        refresh()
    }

    public func refresh() {
        let availabilityBefore = (state, loopEnabled, resonanceSuppression)
        defer {
            if (state, loopEnabled, resonanceSuppression) != availabilityBefore {
                onAvailabilityChanged?()
            }
        }
        let scale = session?.workspace?.viewport.scale ?? ScaleProjection()
        publish(\.scaleRoot, scale.root)
        publish(\.scaleType, scale.scale.rawValue)
        publish(\.scaleHighlight, scale.highlight)
        publish(\.scaleFold, scale.fold)
        guard let session, session.songOpen, let document = session.selectedDocument,
            let audio = session.transportAudio, audio.songLoaded
        else {
            publish(\.state, 0)
            publish(\.timeText, "0:00.0 / 0:00.0")
            publish(\.measureText, "1:1")
            publish(\.loopBounds, "")
            publish(\.keySignature, "C")
            publish(\.polyMeterVisible, false)
            publish(\.pcmText, "")
            publish(\.cgbText, "")
            publish(\.lostText, "")
            publish(\.lostVisible, false)
            // Scale remains available on a document even when audio failed to bind.
            publish(\.masterVolume, 127)
            if let audio = self.session?.transportAudio {
                publish(\.loopEnabled, audio.loopEnabled)
                publish(\.resonanceSuppression, audio.resonanceSuppression)
            }
            return
        }
        let transportState = Int(audio.transport) + 1
        publish(\.state, transportState)
        publish(\.polyMeterVisible, true)
        let pcm = "\(audio.activePcmChannels)/\(audio.maxPcmChannels)"
        publish(\.pcmText, pcm)
        let cgb = "\(audio.activeCgbChannels)/4"
        publish(\.cgbText, cgb)
        let lost = audio.polyLostTotal
        let hasLost = lost > 0
        publish(\.lostVisible, hasLost)
        let lostLabel = hasLost ? "\(lost)" : ""
        publish(\.lostText, lostLabel)
        let timeline = document.timeline
        let sample = audio.playheadSamples
        let time =
            Self.clock(sample: sample, sampleRate: audio.sampleRate) + " / "
            + Self.clock(sample: timeline.lengthSamples, sampleRate: audio.sampleRate)
        publish(\.timeText, time)
        let tick = TimeDefaults.tick(from: timeline.tick(for: sample))
        let measure = Self.measure(at: tick, timeline: timeline)
        publish(\.measureText, measure)
        let bounds =
            timeline.hasLoop
            ? "\(Self.measure(at: timeline.loopStartTick, timeline: timeline)) – "
                + Self.measure(at: timeline.loopEndTick, timeline: timeline)
            : ""
        publish(\.loopBounds, bounds)
        let volume = document.document.state.config.masterVolume
        publish(\.masterVolume, volume)
        publish(\.loopEnabled, audio.loopEnabled)
        publish(\.resonanceSuppression, audio.resonanceSuppression)
        let tempoPoint = document.document.state.tempo.last { $0.tick <= tick }
        let micros =
            tempoPoint?.microsecondsPerQuarterNote
            ?? TimeDefaults.defaultTempoMicrosecondsPerQuarterNote
        let bpm = Int((Double(TimeDefaults.microsecondsPerMinute) / Double(max(1, micros))).rounded())
        publish(\.tempo, bpm)
        if keyDocument !== document.document || keyRevision != document.document.revision {
            keyEvents = Self.keyEvents(in: document.document)
            keyDocument = document.document
            keyRevision = document.document.revision
        }
        let key = keyEvents.last { $0.tick <= tick }?.label ?? "C"
        publish(\.keySignature, key)
    }

    public func setScaleRoot(root: Int) {
        guard session?.songOpen == true, let viewport = session?.workspace?.viewport else { return }
        viewport.setScale(root: root)
        refresh()
    }

    public func setScaleType(type: Int) {
        guard session?.songOpen == true, let viewport = session?.workspace?.viewport,
            let scale = ScaleID(rawValue: type)
        else { return }
        viewport.setScale(type: scale)
        refresh()
    }

    public func setScaleHighlight(enabled: Bool) {
        guard session?.songOpen == true, let viewport = session?.workspace?.viewport else { return }
        viewport.setScale(highlight: enabled)
        refresh()
    }

    public func setScaleFold(enabled: Bool) {
        guard session?.songOpen == true, let viewport = session?.workspace?.viewport else { return }
        viewport.setScale(fold: enabled)
        refresh()
    }

    public func play() {
        guard state != 0, state != 3 else { return }
        session?.play()
        refresh()
    }

    public func pause() {
        guard state == 3 else { return }
        session?.playPause()
        refresh()
    }

    public func playPause() {
        guard state != 0 else { return }
        session?.playPause()
        refresh()
    }

    public func stop() {
        guard state > 1 else { return }
        session?.stop()
        refresh()
    }

    public func goToStart() {
        guard state != 0 else { return }
        session?.goToStart()
        refresh()
    }

    public func setLoopEnabled(enabled: Bool) {
        guard state != 0, let audio = session?.transportAudio else { return }
        audio.setLoopEnabled(enabled)
        refresh()
    }

    public func setFollowPlayhead(enabled: Bool) {
        guard followPlayhead != enabled else { return }
        followPlayhead = enabled
        onAvailabilityChanged?()
        session?.playheadPresenter().setFollowEnabled(enabled)
        let store = PreferencesStore()
        store.setBool(key: "followPlayhead", value: enabled)
        store.synchronize()
    }

    public func setResonanceSuppression(enabled: Bool) {
        let changed = resonanceSuppression != enabled
        resonanceSuppression = enabled
        session?.transportAudio?.setResonanceSuppression(enabled)
        refresh()
        if changed { onAvailabilityChanged?() }
        let store = PreferencesStore()
        store.setBool(key: "dsp.resonanceSuppression", value: resonanceSuppression)
        store.synchronize()
    }

    public func restoreTransportToggles() {
        let store = PreferencesStore()
        setFollowPlayhead(enabled: store.bool(key: "followPlayhead", fallback: true))
        setResonanceSuppression(enabled: store.bool(key: "dsp.resonanceSuppression", fallback: false))
    }

    public func restoreOutputVolume() {
        setOutputVolume(percent: PreferencesStore().int(key: "outputVolume", fallback: 100))
    }

    public func commitOutputVolume(percent: Int) {
        setOutputVolume(percent: percent)
        let store = PreferencesStore()
        store.setInt(key: "outputVolume", value: outputVolume)
        store.synchronize()
    }

    public func setOutputVolume(percent: Int) {
        outputVolume = min(100, max(0, percent))
        session?.transportAudio?.setOutputVolume(outputVolume)
    }

    public func setMasterVolume(value: Int) {
        guard (0...127).contains(value), let session = session?.selectedDocument else { return }
        var config = session.document.state.config
        guard config.masterVolume != value else { return }
        config.masterVolume = value
        session.document.setConfig(config)
        self.session?.transportAudio?.updateSettings(config: config)
        refresh()
    }

    static func clock(sample: UInt64, sampleRate: Double) -> String {
        let tenths = Int(Double(sample) / sampleRate * 10)
        return "\(tenths / 600):\(String(format: "%02d", tenths / 10 % 60)).\(tenths % 10)"
    }

    static func measure(at tick: Tick, timeline: PlaybackTimeline) -> String {
        let position = MusicalPosition(
            tick: tick, signatures: timeline.timeSignatures, ticksPerBeat: timeline.ticksPerBeat)
        return "\(position.bar):\(position.beat)"
    }

    private static func keyEvents(in document: SongDocument) -> [(tick: Tick, label: String)] {
        let sharp = ["C", "G", "D", "A", "E", "B", "F♯", "C♯"]
        let flat = ["C", "F", "B♭", "E♭", "A♭", "D♭", "G♭", "C♭"]
        var result: [(tick: Tick, label: String)] = []
        for chunk in document.state.file.chunks {
            for event in chunk.events {
                guard case .meta(let type, let data) = event.payload,
                    type == 0x59, data.count == 2
                else { continue }
                let fifths = Int(Int8(bitPattern: data[0]))
                let names = fifths < 0 ? flat : sharp
                let position = min(names.count - 1, abs(fifths))
                result.append((event.tick, names[position] + (data[1] == 1 ? "m" : "")))
            }
        }
        result.sort { $0.tick < $1.tick }
        return result
    }
}
