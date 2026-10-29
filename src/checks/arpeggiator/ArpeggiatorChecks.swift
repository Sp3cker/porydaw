import PorydawAppAudio
import PorydawCore

@MainActor
public func runArpeggiatorChecks(_ report: CheckReport) {
    let source = arpeggiatorDocument(pitches: [60, 67, 64], end: 96)
    let original = source.state
    let history = source.history.undoCount
    var settings = ArpeggiatorSettings()
    settings.steps = 32
    let playback = PlaybackSettings(exactGate: true)

    func generate(
        _ options: ArpeggiatorSettings, start: Tick = 0, end: Tick = 24,
        document: SongDocument = source, policy: PlaybackSettings = playback
    ) throws -> ArpeggiatorResult {
        try Arpeggiator.generate(
            notes: document.notes(in: 0), track: 0, start: start, end: end,
            ticksPerBeat: UInt32(document.ticksPerBeat), playbackSettings: policy,
            settings: options)
    }

    do {
        var cycleSettings = ArpeggiatorSettings()
        cycleSettings.steps = 3
        cycleSettings.rateDenominator = 8
        cycleSettings.shuffle = 50
        let cycle = try Arpeggiator.patternRange(
            start: 1001, ticksPerBeat: 480, playbackSettings: playback, settings: cycleSettings)
        report.expectEqual(
            expected: [Tick(960), 1680], actual: [cycle.start, cycle.end],
            cppID: "arpeggiator/cycle", what: "three eighth steps form a beat-anchored cycle without end-beat padding")
        let up = try generate(settings)
        report.expectEqual(
            expected: [UInt8(60), 64, 67, 60], actual: up.notes.map(\.pitch),
            cppID: "arpeggiator/modes", what: "Up sorts chord pitches rather than MIDI storage order")
        report.expectEqual(
            expected: [Tick(0), 6, 12, 18], actual: up.notes.map(\.tick),
            cppID: "arpeggiator/clock", what: "sixteenth notes use six normal GBA clocks")
        settings.mode = .down
        report.expectEqual(
            expected: [UInt8(67), 64, 60, 67], actual: try generate(settings).notes.map(\.pitch),
            cppID: "arpeggiator/modes", what: "Down descends through the chord")
        settings.mode = .upDown
        report.expectEqual(
            expected: [UInt8(60), 64, 67, 64, 60, 64],
            actual: try generate(settings, end: 36).notes.map(\.pitch),
            cppID: "arpeggiator/modes", what: "UpDown does not repeat endpoints")
        settings.mode = .manual
        report.expectEqual(
            expected: [UInt8(60), 67, 64, 60], actual: try generate(settings).notes.map(\.pitch),
            cppID: "arpeggiator/modes", what: "Manual uses deterministic source note-on order")
        settings.mode = .poly
        let poly = try generate(settings, end: 12)
        report.expectEqual(
            expected: [Tick(0), 0, 0, 6, 6, 6], actual: poly.notes.map(\.tick).sorted(),
            cppID: "arpeggiator/modes", what: "Poly emits the full chord on each step")
        report.expectEqual(
            expected: Set<UInt8>([60, 64, 67]), actual: Set(poly.notes.map(\.pitch)),
            cppID: "arpeggiator/modes", what: "Poly retains each chord member")

        settings = ArpeggiatorSettings()
        settings.octaves = 2
        report.expectEqual(
            expected: [UInt8(60), 64, 67, 72, 76, 79],
            actual: try generate(settings, end: 36).notes.map(\.pitch),
            cppID: "arpeggiator/pitch", what: "octaves expand upward in complete chord blocks")
        settings.mode = .poly
        settings.transpose = 12
        let highChord = arpeggiatorDocument(pitches: [112, 120], end: 24)
        let clipped = try generate(settings, end: 6, document: highChord)
        report.expectEqual(
            expected: [UInt8(124)], actual: clipped.notes.map(\.pitch),
            cppID: "arpeggiator/pitch", what: "transpose omits out-of-range pitches rather than wrapping or clamping")
        report.expectEqual(
            expected: 3, actual: clipped.droppedPitchCount,
            cppID: "arpeggiator/pitch", what: "omitted octave and transpose pitches are reported")

        settings = ArpeggiatorSettings()
        settings.enabledSteps &= ~((UInt32(1) << 1) | (UInt32(1) << 3))
        let rests = try generate(settings)
        report.expectEqual(
            expected: [Tick(0), 12], actual: rests.notes.map(\.tick),
            cppID: "arpeggiator/pads", what: "disabled pads retain their silent time slots")
        report.expectEqual(
            expected: [UInt8(60), 67], actual: rests.notes.map(\.pitch),
            cppID: "arpeggiator/pads", what: "disabled pads advance note order")
        settings.accentSteps = 1
        settings.accentAmount = -100
        let negativeAccent = try generate(settings)
        report.expectEqual(
            expected: [Tick(12)], actual: negativeAccent.notes.map(\.tick),
            cppID: "arpeggiator/velocity", what: "negative full accent silences only accented steps")
        settings.masterVelocity = 0
        let silent = try generate(settings)
        report.expect(
            silent.notes.isEmpty, cppID: "arpeggiator/velocity",
            message: "zero master velocity produces silence instead of MIDI note-on velocity one")

        settings = ArpeggiatorSettings()
        settings.steps = 4
        settings.enabledSteps = 0b0101
        settings.gate = 101
        let tied = try generate(settings)
        report.expectEqual(
            expected: [Tick(12), 12], actual: tied.notes.map(\.duration),
            cppID: "arpeggiator/gate", what: "Tie spans rests but stops at the next sounding group or loop end")

        settings = ArpeggiatorSettings()
        settings.rateDenominator = 32
        settings.mode = .down
        settings.insert = .lowest
        settings.gate = 100
        let inserted = try generate(settings, end: 6)
        report.expectEqual(
            expected: [Tick(0), 1, 3, 4], actual: inserted.notes.map(\.tick),
            cppID: "arpeggiator/insert", what: "odd three-clock slots split into one then two clocks")
        report.expectEqual(
            expected: [UInt8(60), 67, 60, 64], actual: inserted.notes.map(\.pitch),
            cppID: "arpeggiator/insert", what: "Insert emits lowest before the selected descending member")
        settings.shuffle = 99
        let shuffled = try generate(settings, end: 12)
        report.expectEqual(
            expected: [Tick(0), 4, 6, 10], actual: shuffled.stepTicks,
            cppID: "arpeggiator/shuffle", what: "shuffle is clock-resolved and retains two clocks for Insert")
        report.expectEqual(
            expected: [0, 1, 2, 3], actual: shuffled.stepIndices,
            cppID: "arpeggiator/shuffle", what: "shuffled clock events retain their matching pad indices")
        report.expectEqual(
            expected: 1, actual: shuffled.shuffleClocks,
            cppID: "arpeggiator/shuffle", what: "the effective shuffle reports its one-clock delay")
        report.expectEqual(
            expected: [1, 2, 1, 2], actual: inserted.gateClocks,
            cppID: "arpeggiator/insert", what: "copied Insert gates preserve the one-plus-two clock split")
        report.expect(
            shuffled.notes.allSatisfy { (note: NewNote) in note.duration >= 1 && note.tick + note.duration <= 12 },
            cppID: "arpeggiator/shuffle", message: "shuffle and Insert never collapse or cross the loop end")

        settings = ArpeggiatorSettings()
        settings.mode = .custom
        settings.customPattern = "31------"
        report.expectEqual(
            expected: [UInt8(67), 60, 67, 60], actual: try generate(settings).notes.map(\.pitch),
            cppID: "arpeggiator/custom", what: "Custom indexes pitch order and ignores padding")
        settings.customPattern = "R-------"
        settings.seed = 42
        let randomA = try generate(settings, end: 96)
        let randomB = try generate(settings, end: 96)
        report.expectEqual(
            expected: randomA.notes, actual: randomB.notes,
            cppID: "arpeggiator/random", what: "a frozen seed preserves the exact audition and copied notes")
        report.expect(
            randomA.notes.allSatisfy { (note: NewNote) in [UInt8(60), 64, 67].contains(note.pitch) },
            cppID: "arpeggiator/random", message: "Random chooses only available chord members")

        settings = ArpeggiatorSettings()
        let carried = try generate(settings, start: 12, end: 24)
        report.expectEqual(
            expected: [UInt8(60), 64], actual: carried.notes.map(\.pitch),
            cppID: "arpeggiator/source", what: "notes sustaining into the loop supply pitches immediately")
        report.expectEqual(
            expected: [Tick(12), 18], actual: carried.notes.map(\.tick),
            cppID: "arpeggiator/source", what: "the pattern is anchored at the song loop start")
        let progression = arpeggiatorProgression()
        let changed = try generate(settings, document: progression)
        report.expectEqual(
            expected: [UInt8(60), 64, 62, 65], actual: changed.notes.map(\.pitch),
            cppID: "arpeggiator/source", what: "a new source chord retriggers note order and uses new pitches")
        settings.restartOnNoteOn = false
        report.expectEqual(
            expected: [UInt8(60), 64, 69, 62],
            actual: try generate(settings, document: progression).notes.map(\.pitch),
            cppID: "arpeggiator/trigger", what: "trigger off keeps note order continuous across source note-ons")
        settings.steps = 2
        let wrapped = try generate(settings)
        report.expectEqual(
            expected: [UInt8(60), 64, 60, 64], actual: wrapped.notes.map(\.pitch),
            cppID: "arpeggiator/trigger", what: "trigger off restarts note order at the selected pattern length")
        report.expectEqual(
            expected: [0, 1, 0, 1], actual: wrapped.stepIndices,
            cppID: "arpeggiator/trigger", what: "the audition pad index wraps with the selected pattern length")
        settings = ArpeggiatorSettings()
        settings.rateNumerator = 3
        settings.rateDenominator = 16
        report.expectEqual(
            expected: [Tick(0), 18, 36], actual: try generate(settings, end: 54).notes.map(\.tick),
            cppID: "arpeggiator/clock", what: "dotted eighth notes use eighteen normal GBA clocks")
        settings = ArpeggiatorSettings()

        let fine = arpeggiatorDocument(pitches: [60, 64, 67], division: 480, end: 1920)
        settings.rateDenominator = 32
        let clocked = try generate(settings, end: 480, document: fine)
        report.expect(
            clocked.notes.allSatisfy { (note: NewNote) in note.tick % 20 == 0 && note.duration % 20 == 0 },
            cppID: "arpeggiator/clock", message: "high MIDI PPQ never creates fractional GBA-clock boundaries")
        report.expectEqual(
            expected: Tick(20), actual: clocked.quantumTicks,
            cppID: "arpeggiator/clock", what: "480 PPQ exposes a twenty-tick hardware quantum")
        let offGrid = SongDocument(
            file: MidiFile(
                division: 480,
                chunks: [
                    MidiChunk(
                        events: [
                            .channel(status: 0x90, data0: 60, data1: 100),
                            .channel(tick: 21, status: 0x80, data0: 60),
                            .channel(tick: 21, status: 0x90, data0: 67, data1: 100),
                            .channel(tick: 240, status: 0x80, data0: 67),
                        ], endTick: 240)
                ]))
        let offGridResult = try generate(settings, end: 240, document: offGrid)
        report.expectEqual(
            expected: Tick(40), actual: offGridResult.notes.first(where: { (note: NewNote) in note.pitch == 67 })?.tick,
            cppID: "arpeggiator/trigger",
            what: "an off-lattice chord retriggers at the next clock, not before its source onset or one step late")
        let extended = try generate(
            settings, policy: PlaybackSettings(exactGate: true, extendedClocks: true))
        report.expectEqual(
            expected: 2, actual: extended.quantumClocks,
            cppID: "arpeggiator/clock", what: "24 PPQ cannot store every 48-clock boundary")
        report.expect(
            extended.notes.allSatisfy { (note: NewNote) in note.duration >= 1 },
            cppID: "arpeggiator/clock", message: "extended clock generation still respects document resolution")

        settings.rateDenominator = 1
        settings.gate = 27
        let tableGates = try generate(
            settings, end: 96, policy: PlaybackSettings(exactGate: false))
        report.expect(
            tableGates.notes.allSatisfy { (note: NewNote) in
                mid2agbEffectiveDuration(
                    Int64(note.duration), division: 24, extendedClocks: false,
                    exactGate: false) == Int(note.duration)
            }, cppID: "arpeggiator/gate", message: "stored gates are fixed points of the export duration table")
        report.expectEqual(
            expected: original, actual: source.state,
            cppID: "arpeggiator/source", what: "generation never changes source events or metadata")
        report.expectEqual(
            expected: history, actual: source.history.undoCount,
            cppID: "arpeggiator/source", what: "generation creates no undo entries")
    } catch {
        report.fail("arpeggiator/generation", "unexpected error: \(error)")
    }

    let coarse = arpeggiatorDocument(pitches: [60], division: 12, end: 48)
    var invalid = ArpeggiatorSettings()
    invalid.rateDenominator = 32
    expectArpeggiatorError(report, "nonrepresentable rate", expectedCase: .unsupportedTiming("")) {
        _ = try generate(invalid, document: coarse)
    }
    invalid.rateDenominator = 48
    invalid.insert = .lowest
    expectArpeggiatorError(report, "Insert cannot fit into one editable quantum", expectedCase: .unsupportedTiming(""))
    {
        _ = try generate(invalid, document: coarse)
    }
    invalid = ArpeggiatorSettings()
    invalid.customPattern = "12X-----"
    invalid.mode = .custom
    expectArpeggiatorError(report, "invalid Custom draft", expectedCase: .invalidSettings("")) {
        _ = try generate(invalid)
    }
    invalid = ArpeggiatorSettings()
    invalid.steps = 0
    expectArpeggiatorError(report, "zero-length pattern", expectedCase: .invalidSettings("")) {
        _ = try generate(invalid)
    }
    expectArpeggiatorError(report, "cycle exceeds the document", expectedCase: .invalidRange("")) {
        _ = try Arpeggiator.patternRange(
            start: TimeDefaults.maxTick, ticksPerBeat: 24, playbackSettings: playback,
            settings: ArpeggiatorSettings())
    }
    report.expect(
        Arpeggiator.supportsTiming(ticksPerBeat: 24, playbackSettings: playback, settings: ArpeggiatorSettings()),
        cppID: "arpeggiator/availability", message: "the normal sixteenth-note rate is available")
    invalid = ArpeggiatorSettings()
    invalid.rateDenominator = 32
    report.expect(
        !Arpeggiator.supportsTiming(ticksPerBeat: 12, playbackSettings: playback, settings: invalid),
        cppID: "arpeggiator/availability", message: "the rate menu disables fractions of a document clock quantum")
    invalid.rateDenominator = 48
    invalid.insert = .lowest
    report.expect(
        !Arpeggiator.supportsTiming(ticksPerBeat: 12, playbackSettings: playback, settings: invalid),
        cppID: "arpeggiator/availability", message: "Insert is unavailable when a step holds only one shared quantum")
    let fineMarkers = arpeggiatorDocument(pitches: [60], division: 480, end: 480)
    expectArpeggiatorError(report, "off-clock loop marker", expectedCase: .invalidRange("")) {
        _ = try generate(ArpeggiatorSettings(), start: 1, end: 480, document: fineMarkers)
    }
    invalid = ArpeggiatorSettings()
    invalid.rateDenominator = 48
    invalid.enabledSteps = 0
    expectArpeggiatorError(report, "excessive silent clock events", expectedCase: .outputTooLarge) {
        _ = try generate(invalid, end: 131_074)
    }
    invalid.enabledSteps = .max
    invalid.mode = .poly
    let longChord = arpeggiatorDocument(pitches: [60, 64, 67], end: 43_700)
    expectArpeggiatorError(report, "excessive emitted notes", expectedCase: .outputTooLarge) {
        _ = try generate(invalid, end: 43_700, document: longChord)
    }
    do {
        try checkArpeggiatorAudition(report)
    } catch {
        report.fail("arpeggiator/audition", "unexpected renderer error: \(error)")
    }
}

@MainActor
private func arpeggiatorDocument(
    pitches: [UInt8], division: UInt16 = 24, end: Tick
) -> SongDocument {
    var events = pitches.map { (pitch: UInt8) -> MidiEvent in
        .channel(status: 0x90, data0: pitch, data1: 100)
    }
    events += pitches.map { (pitch: UInt8) -> MidiEvent in
        .channel(tick: end, status: 0x80, data0: pitch)
    }
    return SongDocument(file: MidiFile(division: division, chunks: [MidiChunk(events: events, endTick: end)]))
}

@MainActor
private func arpeggiatorProgression() -> SongDocument {
    let events: [MidiEvent] = [
        .channel(status: 0x90, data0: 60, data1: 100),
        .channel(status: 0x90, data0: 64, data1: 100),
        .channel(status: 0x90, data0: 67, data1: 100),
        .channel(tick: 12, status: 0x80, data0: 60),
        .channel(tick: 12, status: 0x80, data0: 64),
        .channel(tick: 12, status: 0x80, data0: 67),
        .channel(tick: 12, status: 0x90, data0: 62, data1: 100),
        .channel(tick: 12, status: 0x90, data0: 65, data1: 100),
        .channel(tick: 12, status: 0x90, data0: 69, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 62),
        .channel(tick: 24, status: 0x80, data0: 65),
        .channel(tick: 24, status: 0x80, data0: 69),
    ]
    return SongDocument(file: MidiFile(chunks: [MidiChunk(events: events, endTick: 24)]))
}

private func checkArpeggiatorAudition(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    let original = rig.timeline(retriggerAt: 48)
    audio.bind(timeline: original, voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    _ = rig.render(24_000)
    let songPosition = audio.playheadSamples
    let file = MidiFile(
        chunks: [
            MidiChunk(
                events: [
                    .meta(type: 0x01, data: Array("[".utf8)),
                    .meta(tick: 96, type: 0x01, data: Array("]".utf8)),
                ], endTick: 96),
            MidiChunk(
                events: [
                    .channel(status: 0xC0, data0: 0),
                    .channel(tick: 24, status: 0x90, data0: 67, data1: 100),
                    .channel(tick: 30, status: 0x80, data0: 67),
                ], endTick: 36),
        ])
    let pattern = PlaybackTimeline.build(
        file: file, sampleRate: Double(rig.rate), loopRange: (start: 24, end: 36))
    audio.startPatternAudition(pattern)
    let frames = Int(rig.rate) / 4 * 3 + 137
    let sounding = rig.render(frames, chunk: 127)
    report.expect(
        audioControllerCheckPeak(sounding[...]) > 1 / 32768,
        cppID: "arpeggiator/audition", message: "the isolated pattern renders audible source-instrument samples")
    report.expectEqual(
        expected: UInt64(rig.rate) / 2 + 137, actual: audio.patternAuditionPositionSamples,
        cppID: "arpeggiator/audition",
        what: "explicit audition range overrides song markers and wraps through three cycles")
    report.expectEqual(
        expected: songPosition, actual: audio.playheadSamples,
        cppID: "arpeggiator/audition", what: "pattern audition does not advance the original song")
    report.expectEqual(
        expected: original.events, actual: audio.timeline?.events,
        cppID: "arpeggiator/audition", what: "pattern audition retains the original song timeline")
    audio.stopPatternAudition()
    report.expect(
        !audio.isPatternAuditioning && audio.transport == .paused,
        cppID: "arpeggiator/audition", message: "stopping the pattern leaves the original song paused")
    let stopped = rig.render(4096)
    report.expect(
        audioControllerCheckPeak(stopped[...]) <= 1 / 32768,
        cppID: "arpeggiator/audition", message: "stopped pattern notes cannot leak into ordinary preview output")
    let resumeTarget = original.sample(for: 48)
    let resumeFrames =
        Int(resumeTarget - songPosition) + rig.ramp + rig.settle + audio.periodSizeFrames + 4096
    audio.play()
    let resumed = rig.render(resumeFrames)
    report.expect(
        audio.playheadSamples >= resumeTarget + 4096,
        cppID: "arpeggiator/audition", message: "normal Play advances beyond the retained song's later note-on")
    report.expect(
        rig.sustaining(60) && audioControllerCheckPeak(resumed.suffix(4096)) > 1 / 32768,
        cppID: "arpeggiator/audition", message: "a later original song note-on sounds after pattern audition")
    audio.stop()
    _ = rig.render(rig.settle + rig.ramp * 3 + 1024)
    report.expectEqual(
        expected: UInt64(0), actual: audio.playheadSamples,
        cppID: "arpeggiator/audition", what: "normal Stop still rewinds the retained song after audition")
}

private func expectArpeggiatorError(
    _ report: CheckReport, _ scenario: String, expectedCase: ArpeggiatorError, _ body: () throws -> Void
) {
    do {
        try body()
        report.fail("arpeggiator/rejection", "\(scenario) unexpectedly accepted")
    } catch let error as ArpeggiatorError {
        switch (expectedCase, error) {
        case (.invalidSettings, .invalidSettings), (.invalidRange, .invalidRange),
            (.unsupportedTiming, .unsupportedTiming), (.outputTooLarge, .outputTooLarge):
            report.pass("arpeggiator/rejection", row: scenario)
        default:
            report.fail("arpeggiator/rejection", "\(scenario) rejected with the wrong error category: \(error)")
        }
    } catch {
        report.fail("arpeggiator/rejection", "\(scenario) threw an unexpected error: \(error)")
    }
}
