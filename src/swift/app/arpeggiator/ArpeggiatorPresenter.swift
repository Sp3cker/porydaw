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
    public var rangeLabel: String = ""
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
    private struct Draft {
        let range: (start: Tick, end: Tick)
        let result: ArpeggiatorResult
        var timeline: PlaybackTimeline?
    }

    private var draft: Draft? {
        didSet { canCopy = draft.map { !$0.result.notes.isEmpty } ?? false }
    }
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
        draft = nil
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
        return Arpeggiator.supportsTiming(
            ticksPerBeat: timeline.ticksPerBeat, playbackSettings: timeline.settings, settings: candidate)
    }

    public func toggleAudition() {
        if isAuditioning {
            stopAudition()
            return
        }
        guard let timeline = auditionTimeline() else { return }
        audio.startPatternAudition(timeline)
        isAuditioning = true
        pollAudition()
    }

    public func copyNotes() {
        guard canCopy, let draft else { return }
        let result = draft.result
        let sourceRange = draft.range
        let timeline = session.timeline
        let notes = result.notes.map { note in
            ClipNote(
                relTick: note.tick - sourceRange.start, key: note.pitch,
                duration: note.duration, velocity: note.velocity)
        }
        let clip = PorydawClip(
            span: sourceRange.end - sourceRange.start,
            tracks: [ClipTrack(track: sourceTrack, notes: notes)], lanes: [], tempo: [])
        status =
            clipboard.write(clip, ticksPerBeat: timeline.ticksPerBeat)
            ? "Copied \(notes.count) notes." : "Could not write notes to the clipboard."
    }

    @QtIgnored
    @discardableResult
    func pollAudition() -> SharedPlayheadPreview? {
        guard isOpen, let draft else {
            currentStep = -1
            return nil
        }
        guard isAuditioning, audio.isPatternAuditioning, let timeline = draft.timeline else {
            isAuditioning = false
            currentStep = -1
            return SharedPlayheadPreview(start: draft.range.start, end: draft.range.end)
        }
        let result = draft.result
        let tick = timeline.tick(for: audio.patternAuditionPositionSamples)
        guard tick >= Double(draft.range.start), tick < Double(draft.range.end) else {
            // The callback has not adopted the replacement yet; it restarts at the loop start.
            currentStep = -1
            return SharedPlayheadPreview(
                start: draft.range.start, end: draft.range.end, tick: Double(draft.range.start))
        }
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
        return SharedPlayheadPreview(start: draft.range.start, end: draft.range.end, tick: tick)
    }

    private func stopAudition() {
        if isAuditioning { audio.stopPatternAudition() }
        isAuditioning = false
        currentStep = -1
    }

    private func resolveSourceStart() -> (tick: Tick, selection: Bool)? {
        if let selection = session.timeSelection, selection.isActive,
            !selection.range.hasReservedEndpoint,
            session.timeSelectionCoversTrack(sourceTrack)
        {
            return (selection.range.startTick, true)
        }
        guard let first = session.document.notes(in: sourceTrack).min(by: { $0.tick < $1.tick }) else { return nil }
        return (first.tick, false)
    }

    private func regenerate() {
        draft = nil
        timingLabel = ""
        stepRevision &+= 1
        if isOpen { generateDraft() }
        guard isAuditioning else { return }
        // Replace the sounding loop in place; empty or failed drafts stop audition.
        guard audio.isPatternAuditioning, let timeline = auditionTimeline() else {
            stopAudition()
            return
        }
        audio.replacePatternAudition(timeline)
        pollAudition()
    }

    private func generateDraft() {
        let timeline = session.timeline
        guard let source = resolveSourceStart() else {
            rangeLabel = ""
            status = "This track has no notes to arpeggiate."
            return
        }
        do {
            let range = try Arpeggiator.patternRange(
                start: source.tick, ticksPerBeat: timeline.ticksPerBeat,
                playbackSettings: timeline.settings, settings: settings)
            rangeLabel = "\(source.selection ? "Selection" : "Track start") · ticks \(range.start)–\(range.end)"
            let generated = try Arpeggiator.generate(
                notes: session.document.notes(in: sourceTrack),
                track: sourceTrack, start: range.start, end: range.end,
                ticksPerBeat: timeline.ticksPerBeat, playbackSettings: timeline.settings, settings: settings)
            let bounds = (start: range.start, end: range.end)
            draft = Draft(range: bounds, result: generated, timeline: nil)
            let gates = Set(generated.gateClocks).sorted().map(String.init).joined(separator: ", ")
            timingLabel =
                "\(timeline.settings.extendedClocks ? "Extended" : "Normal") clocks · quantum \(generated.quantumClocks) · step \(generated.stepClocks) · shuffle \(generated.shuffleClocks) · gate \(gates.isEmpty ? "—" : gates)"
            status =
                canCopy
                ? "\(generated.notes.count) notes · \(generated.droppedPitchCount) pitches omitted"
                : "No sounding generated notes."
        } catch {
            status = error.localizedDescription
        }
    }

    /// Lazily projects the sounding draft, retaining it for playhead mapping.
    private func auditionTimeline() -> PlaybackTimeline? {
        guard canCopy, var draft else { return nil }
        if let timeline = draft.timeline { return timeline }
        let timeline = PlaybackTimeline.pattern(
            source: session.timeline, notes: draft.result.notes, track: sourceTrack, range: draft.range)
        draft.timeline = timeline
        self.draft = draft
        return timeline
    }
}
