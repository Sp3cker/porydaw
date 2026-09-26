import Foundation
import PorydawCore
import QtBridge

/// The shell's transport chrome reads the same engine and document as the editor.
/// The clock is sampled from the audio device, never extrapolated from wall time.
@MainActor
@QtBridgeable
public final class TransportBarPresenter {
    private weak var session: ApplicationSession?

    @QtTracked public var state = 0 // unavailable, stopped, paused, playing
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
    private weak var keyDocument: SongDocument?
    private var keyRevision: UInt64 = 0
    private var keyEvents: [(tick: Tick, label: String)] = []

    public init() {}

    @QtIgnored public var onAvailabilityChanged: (() -> Void)?

    @QtIgnored public func attach(session: ApplicationSession) {
        self.session = session
        session.transportAudio?.setOutputVolume(outputVolume)
        refresh()
    }

    public func refresh() {
        let availabilityBefore = (state, loopEnabled, resonanceSuppression)
        defer {
            if (state, loopEnabled, resonanceSuppression) != availabilityBefore {
                onAvailabilityChanged?()
            }
        }
        let scale = session?.selectedDocument?.scaleProjection ?? ScaleProjection()
        scaleRoot = scale.root
        scaleType = scale.scale.rawValue
        scaleHighlight = scale.highlight
        scaleFold = scale.fold
        guard let session, session.songOpen, let document = session.selectedDocument,
              let audio = session.transportAudio, audio.songLoaded else {
            state = 0
            timeText = "0:00.0 / 0:00.0"
            measureText = "1:1"
            loopBounds = ""
            keySignature = "C"
            polyMeterVisible = false
            pcmText = ""
            cgbText = ""
            lostText = ""
            lostVisible = false
            // Scale remains available on a document even when audio failed to bind.
            masterVolume = 127
            if let audio = self.session?.transportAudio {
                loopEnabled = audio.loopEnabled
                resonanceSuppression = audio.resonanceSuppression
            }
            return
        }
        state = Int(audio.transport) + 1
        polyMeterVisible = true
        pcmText = "\(audio.activePcmChannels)/\(audio.maxPcmChannels)"
        cgbText = "\(audio.activeCgbChannels)/4"
        let lost = audio.polyLostTotal
        lostVisible = lost > 0
        lostText = lostVisible ? "\(lost)" : ""
        let timeline = document.timeline
        let sample = audio.playheadSamples
        timeText = Self.clock(sample: sample, sampleRate: audio.sampleRate) + " / "
            + Self.clock(sample: timeline.lengthSamples, sampleRate: audio.sampleRate)
        let tick = TimeDefaults.tick(from: timeline.tick(for: sample))
        measureText = Self.measure(at: tick, timeline: timeline)
        loopBounds = timeline.hasLoop
            ? "\(Self.measure(at: timeline.loopStartTick, timeline: timeline)) – "
                + Self.measure(at: timeline.loopEndTick, timeline: timeline)
            : ""
        masterVolume = document.document.state.config.masterVolume
        loopEnabled = audio.loopEnabled
        resonanceSuppression = audio.resonanceSuppression
        let tempoPoint = document.document.state.tempo.last { $0.tick <= tick }
        let micros = tempoPoint?.microsecondsPerQuarterNote
            ?? TimeDefaults.defaultTempoMicrosecondsPerQuarterNote
        tempo = Int((Double(TimeDefaults.microsecondsPerMinute) / Double(max(1, micros))).rounded())
        if keyDocument !== document.document || keyRevision != document.document.revision {
            keyEvents = Self.keyEvents(in: document.document)
            keyDocument = document.document
            keyRevision = document.document.revision
        }
        keySignature = keyEvents.last { $0.tick <= tick }?.label ?? "C"
    }

    public func setScaleRoot(root: Int) {
        guard session?.songOpen == true, let document = session?.selectedDocument else { return }
        document.setScale(root: root)
        refresh()
    }

    public func setScaleType(type: Int) {
        guard session?.songOpen == true, let document = session?.selectedDocument,
              let scale = ScaleID(rawValue: type) else { return }
        document.setScale(type: scale)
        refresh()
    }

    public func setScaleHighlight(enabled: Bool) {
        guard session?.songOpen == true, let document = session?.selectedDocument else { return }
        document.setScale(highlight: enabled)
        refresh()
    }

    public func setScaleFold(enabled: Bool) {
        guard session?.songOpen == true, let document = session?.selectedDocument else { return }
        document.setScale(fold: enabled)
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
        guard state != 0, let audio = session?.transportAudio else { return }
        audio.seek(sample: 0)
        session?.playheadPresenter().refreshImmediate()
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
        guard let audio = session?.transportAudio else { return }
        audio.setResonanceSuppression(enabled)
        refresh()
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

    public func setTempo(bpm: Int) {
        guard (TimeDefaults.minimumTempoBPM...TimeDefaults.maximumTempoBPM).contains(bpm),
              let document = session?.selectedDocument?.document else { return }
        let tick = TimeDefaults.tick(from: session?.playheadPresenter().tick ?? 0)
        let prior = document.state.tempo.last { $0.tick <= tick }
        let target = TempoPoint(tick: prior?.tick ?? 0,
            microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(forBPM: bpm))
        document.editTempo(TempoEdit(remove: prior.map { [$0] } ?? [], add: [target]))
        refresh()
    }

    static func clock(sample: UInt64, sampleRate: Double) -> String {
        let tenths = Int(Double(sample) / sampleRate * 10)
        return "\(tenths / 600):\(String(format: "%02d", tenths / 10 % 60)).\(tenths % 10)"
    }

    static func measure(at tick: Tick, timeline: PlaybackTimeline) -> String {
        let signatures = timeline.timeSignatures
        var segmentStart: Tick = 0
        var bars = 1
        var beatTicks = max(1, Int(timeline.ticksPerBeat))
        var beatsPerBar = 4
        for signature in signatures where signature.tick <= tick {
            if signature.tick > segmentStart {
                let beats = (Int(signature.tick - segmentStart) + beatTicks - 1) / beatTicks
                bars += (beats + beatsPerBar - 1) / beatsPerBar
            }
            segmentStart = signature.tick
            beatTicks = max(1, Int(timeline.ticksPerBeat) * 4
                >> min(Int(signature.denominatorPowerOfTwo), 31))
            beatsPerBar = max(1, Int(signature.numerator))
        }
        let beats = Int(tick - segmentStart) / beatTicks
        return "\(bars + beats / beatsPerBar):\(beats % beatsPerBar + 1)"
    }

    private static func keyEvents(in document: SongDocument) -> [(tick: Tick, label: String)] {
        let sharp = ["C", "G", "D", "A", "E", "B", "F♯", "C♯"]
        let flat = ["C", "F", "B♭", "E♭", "A♭", "D♭", "G♭", "C♭"]
        var result: [(tick: Tick, label: String)] = []
        for chunk in document.state.file.chunks {
            for event in chunk.events {
                guard case let .meta(type, data) = event.payload,
                      type == 0x59, data.count == 2 else { continue }
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
