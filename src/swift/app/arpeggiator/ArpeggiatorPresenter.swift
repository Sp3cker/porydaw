import Foundation
import PorydawAppCommands
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

/// Workspace-local draft: generation never enters document history or normal playback.
@MainActor
@QtBridgeable
public final class ArpeggiatorPresenter {
    public var isOpen: Bool = false
    public var sourceLabel: String = ""
    public var loopLabel: String = ""
    public var status: String = ""
    public var timingLabel: String = ""
    public var canCopy: Bool = false
    public var isAuditioning: Bool = false
    public var baseFontPx: Double = 13
    public var currentStep: Int = -1
    @QtTracked public var promptStyle = PromptStyle()
    @QtTracked public var colors: GridPalette
    @QtTracked public var bodyFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var masterVelocity: Int = 100
    public var transpose: Int = 0
    public var accentAmount: Int = 25
    public var rateIndex: Int = 9
    public var mode: Int = 0
    public var octaves: Int = 1
    public var insert: Int = 0
    public var shuffle: Int = 0
    public var gate: Int = 80
    public var steps: Int = 16
    public var restartOnNoteOn: Bool = true
    public var customPattern: String = "1234----"
    public var stepRevision: Int = 0
    public let rateLabels: [String] = [
        "4/1", "2/1", "1/1", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32", "1/48",
        "1/8 dotted",
    ]

    private let session: DocumentSession
    private unowned let audio: NativeAudio
    private let clipboard = GridClipboard()
    private var settings = ArpeggiatorSettings()
    private var sourceTrack = -1
    private var result: ArpeggiatorResult?
    private var auditionTimeline: PlaybackTimeline?
    private static let rates: [(Int, Int)] = [
        (4, 1), (2, 1), (1, 1), (1, 2), (1, 3), (1, 4), (1, 6), (1, 8), (1, 12), (1, 16), (1, 24), (1, 32), (1, 48),
        (3, 16),
    ]

    @QtIgnored
    public init(session: DocumentSession, audio: NativeAudio, palette: GridPalette, typography: Typography) {
        self.session = session
        self.audio = audio
        colors = palette
        configure(fontPx: Double(typography.baseFontPx))
    }

    public func configure(fontPx: Double) {
        guard fontPx.isFinite, fontPx > 0 else { return }
        baseFontPx = fontPx
        bodyFont = Typography(baseFontPx: Int(fontPx.rounded())).body.qmlFont
        refreshAppearance()
    }

    @QtIgnored
    public func refreshAppearance() {
        promptStyle.update(metrics: PromptAppearance.Layout(base: baseFontPx), palette: colors, font: bodyFont)
    }

    public func open(track: Int) {
        close()
        guard !session.isClosed, (0..<session.document.engineTracks.usedTrackCount).contains(track) else { return }
        sourceTrack = track
        let name = session.timeline.tracks[track].name.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceLabel = name.isEmpty ? "Track \(track + 1)" : name
        isOpen = true
        regenerate()
    }

    public func close() {
        stopAudition()
        isOpen = false
        canCopy = false
        result = nil
        auditionTimeline = nil
    }

    public func setParameter(name: String, value: Int) {
        let previous = settings
        switch name {
        case "masterVelocity":
            masterVelocity = value
            settings.masterVelocity = value
        case "transpose":
            transpose = value
            settings.transpose = value
        case "accentAmount":
            accentAmount = value
            settings.accentAmount = value
        case "rateIndex":
            guard Self.rates.indices.contains(value) else { return }
            rateIndex = value
            settings.rateNumerator = Self.rates[value].0
            settings.rateDenominator = Self.rates[value].1
        case "mode":
            guard let next = ArpeggiatorMode(rawValue: value) else { return }
            mode = value
            settings.mode = next
        case "octaves":
            octaves = value
            settings.octaves = value
        case "insert":
            guard let next = ArpeggiatorInsert(rawValue: value) else { return }
            insert = value
            settings.insert = next
        case "shuffle":
            shuffle = value
            settings.shuffle = value
        case "gate":
            gate = value
            settings.gate = value
        case "steps":
            steps = value
            settings.steps = value
        default: return
        }
        guard settings != previous else { return }
        regenerate()
    }

    public func setCustomPattern(value: String) {
        customPattern = value
        settings.customPattern = value
        regenerate()
    }

    public func setRestartOnNoteOn(enabled: Bool) {
        restartOnNoteOn = enabled
        settings.restartOnNoteOn = enabled
        regenerate()
    }

    public func toggleStep(index: Int, accent: Bool) {
        guard (0..<32).contains(index) else { return }
        let bit = UInt32(1) << index
        if accent { settings.accentSteps ^= bit } else { settings.enabledSteps ^= bit }
        regenerate()
    }

    public func stepEnabled(index: Int) -> Bool {
        (0..<32).contains(index) && settings.enabledSteps & (UInt32(1) << index) != 0
    }

    public func stepAccented(index: Int) -> Bool {
        (0..<32).contains(index) && settings.accentSteps & (UInt32(1) << index) != 0
    }

    public func reshuffle() {
        settings.seed &+= 1
        regenerate()
    }

    public func rateAvailable(index: Int) -> Bool {
        guard Self.rates.indices.contains(index) else { return false }
        var candidate = settings
        candidate.rateNumerator = Self.rates[index].0
        candidate.rateDenominator = Self.rates[index].1
        return timingAvailable(candidate)
    }

    public func insertAvailable(value: Int) -> Bool {
        guard let insert = ArpeggiatorInsert(rawValue: value) else { return false }
        var candidate = settings
        candidate.insert = insert
        return timingAvailable(candidate)
    }

    private func timingAvailable(_ candidate: ArpeggiatorSettings) -> Bool {
        let timeline = session.timeline
        guard timeline.hasLoop else { return false }
        return Arpeggiator.supportsTiming(
            ticksPerBeat: timeline.ticksPerBeat, playbackSettings: timeline.settings, settings: candidate)
    }

    public func toggleAudition() {
        if isAuditioning {
            stopAudition()
            return
        }
        guard canCopy, let auditionTimeline else { return }
        audio.startPatternAudition(auditionTimeline)
        isAuditioning = true
        pollAudition()
    }

    public func copyNotes() {
        guard canCopy, let result else { return }
        let timeline = session.timeline
        let notes = result.notes.map { note in
            ClipNote(
                relTick: note.tick - timeline.loopStartTick, key: note.pitch,
                duration: note.duration, velocity: note.velocity)
        }
        let clip = PorydawClip(
            span: timeline.loopEndTick - timeline.loopStartTick,
            tracks: [ClipTrack(track: sourceTrack, notes: notes)], lanes: [], tempo: [])
        status =
            clipboard.write(clip, ticksPerBeat: timeline.ticksPerBeat)
            ? "Copied \(notes.count) notes." : "Could not write notes to the clipboard."
    }

    @QtIgnored
    public func pollAudition() {
        guard isAuditioning, let result, let auditionTimeline else {
            currentStep = -1
            return
        }
        guard audio.isPatternAuditioning else {
            isAuditioning = false
            currentStep = -1
            return
        }
        let tick = auditionTimeline.tick(for: audio.patternAuditionPositionSamples)
        var lower = 0
        var upper = result.stepTicks.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if Double(result.stepTicks[middle]) <= tick {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        currentStep = lower == 0 ? -1 : result.stepIndices[lower - 1]
    }

    private func stopAudition() {
        if isAuditioning { audio.stopPatternAudition() }
        isAuditioning = false
        currentStep = -1
    }

    private func regenerate() {
        let resume = isAuditioning
        stopAudition()
        result = nil
        auditionTimeline = nil
        canCopy = false
        timingLabel = ""
        stepRevision &+= 1
        guard isOpen else { return }
        let timeline = session.timeline
        guard timeline.hasLoop else {
            loopLabel = "No song loop"
            status = "Set song loop markers to generate notes."
            return
        }
        loopLabel = "Loop \(timeline.loopStartTick)–\(timeline.loopEndTick)"
        do {
            let generated = try Arpeggiator.generate(
                notes: session.document.notes(in: sourceTrack),
                track: sourceTrack, start: timeline.loopStartTick, end: timeline.loopEndTick,
                ticksPerBeat: timeline.ticksPerBeat, playbackSettings: timeline.settings, settings: settings)
            let isolated = makeTimeline(generated)
            result = generated
            auditionTimeline = isolated
            canCopy = !generated.notes.isEmpty
            let gates = Set(generated.gateClocks).sorted().map(String.init).joined(separator: ", ")
            timingLabel =
                "\(timeline.settings.extendedClocks ? "Extended" : "Normal") clocks · quantum \(generated.quantumClocks) · step \(generated.stepClocks) · shuffle \(generated.shuffleClocks) · gate \(gates.isEmpty ? "—" : gates)"
            status =
                canCopy
                ? "\(generated.notes.count) notes · \(generated.droppedPitchCount) pitches omitted"
                : "No sounding generated notes."
            if resume, canCopy { toggleAudition() }
        } catch {
            status = error.localizedDescription
        }
    }

    private func makeTimeline(_ generated: ArpeggiatorResult) -> PlaybackTimeline {
        var file = session.document.state.file
        let mapping = session.document.engineTracks
        for chunk in file.chunks.indices {
            file.chunks[chunk].events.removeAll { event in event.typeNibble == 0x8 || event.typeNibble == 0x9 }
        }
        // Retain hardware track identities even for a channel that contained only notes.
        for track in 0..<mapping.usedTrackCount {
            let entry = mapping.tracks[track]
            guard let chunk = entry.midiChunk else { continue }
            if !file.chunks[chunk].events.contains(where: { $0.isChannel && $0.channel == entry.channel }) {
                file.chunks[chunk].events.insert(.channel(status: 0xC0 | entry.channel, data0: 0), at: 0)
            }
        }
        let entry = mapping.tracks[sourceTrack]
        if let chunk = entry.midiChunk {
            for note in generated.notes {
                file.chunks[chunk].events.append(
                    .channel(
                        tick: note.tick, status: 0x90 | entry.channel,
                        data0: note.pitch, data1: note.velocity))
                file.chunks[chunk].events.append(
                    .channel(
                        tick: note.tick + note.duration, status: 0x80 | entry.channel,
                        data0: note.pitch))
            }
            file.chunks[chunk].events = file.chunks[chunk].events.enumerated().sorted { left, right in
                left.element.tick == right.element.tick
                    ? left.offset < right.offset : left.element.tick < right.element.tick
            }.map(\.element)
        }
        return PlaybackTimeline.build(
            file: file, tempo: session.document.state.tempo,
            sampleRate: session.timeline.sampleRate, settings: session.timeline.settings)
    }
}
