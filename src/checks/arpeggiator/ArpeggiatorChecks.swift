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
    checkArpeggiatorProjection(report)
    do {
        try checkArpeggiatorAudition(report)
        try checkArpeggiatorReplacement(report)
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

private func checkArpeggiatorProjection(_ report: CheckReport) {
    let rate = 48_000.0
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
                    .meta(type: 0x58, data: [0x04, 0x02, 0x18, 0x08]),
                    .meta(tick: 6, type: 0x01, data: Array("verse".utf8)),
                    .meta(tick: 12, type: 0x51, data: [0x0F, 0x42, 0x40]),
                    .meta(tick: 36, type: 0x58, data: [0x03, 0x02, 0x18, 0x08]),
                    .meta(tick: 40, type: 0x01, data: Array("outro".utf8)),
                ], endTick: 48),
            MidiChunk(
                events: [
                    .channel(status: 0xC0, data0: 5),
                    .channel(status: 0x90, data0: 60, data1: 100),
                    .channel(tick: 6, status: 0xB0, data0: 7, data1: 90),
                    .channel(tick: 12, status: 0xE0, data0: 0, data1: 0x50),
                    .channel(tick: 24, status: 0x80, data0: 60),
                    .channel(tick: 30, status: 0xB0, data0: 10, data1: 20),
                    .channel(tick: 40, status: 0xC0, data0: 9),
                ], endTick: 48),
            // Note-only, then notes plus a controller after the loop: neither keeps channel state.
            MidiChunk(
                events: [
                    .channel(status: 0x91, data0: 48, data1: 100),
                    .channel(tick: 24, status: 0x81, data0: 48),
                ], endTick: 48),
            MidiChunk(
                events: [
                    .channel(status: 0x92, data0: 50, data1: 100),
                    .channel(tick: 6, status: 0x82, data0: 50),
                    .channel(tick: 30, status: 0xB2, data0: 7, data1: 64),
                ], endTick: 48),
        ])
    let source = PlaybackTimeline.build(
        file: file, sampleRate: rate, settings: PlaybackSettings(exactGate: true))
    let range = (start: Tick(12), end: Tick(24))
    func eventFacts(_ event: PlaybackEvent) -> String {
        "\(event.tick):\(event.type):\(event.track):\(event.data0):\(event.data1)@\(event.sample)"
    }
    func trackFacts(_ track: PlaybackTrack) -> String { "\(track.used):\(track.noteCount):\(track.firstProgram)" }

    let pattern = PlaybackTimeline.pattern(
        source: source,
        notes: [
            NewNote(track: 0, tick: 12, pitch: 64, duration: 3, velocity: 100),
            NewNote(track: 0, tick: 18, pitch: 67, duration: 3, velocity: 100),
        ], track: 0, range: range)
    // 120 BPM is 1000 samples per tick at 24 PPQ; 60 BPM from tick 12 is 2000.
    report.expectEqual(
        expected: [
            "0:1:0:120:0@0", "0:12:0:5:0@0", "0:12:1:0:0@0", "0:12:2:0:0@0", "6:11:0:7:90@6000",
            "12:1:0:60:0@12000", "12:14:0:0:80@12000", "12:9:0:64:100@12000", "15:8:0:64:0@18000",
            "18:9:0:67:100@24000", "21:8:0:67:0@30000",
        ],
        actual: pattern.events.map(eventFacts),
        cppID: "arpeggiator/projection",
        what: "pattern keeps source tempo and controls through the loop end, drops source notes, "
            + "gives channel-less tracks program 0 and orders same-tick controls before generated notes")
    report.expectEqual(
        expected: ["true:2:5", "true:0:0", "true:0:0", "false:0:-1"],
        actual: pattern.tracks.prefix(4).map(trackFacts),
        cppID: "arpeggiator/projection", what: "track metadata counts generated notes and surviving programs")
    report.expectEqual(
        expected: source.tempoMap, actual: pattern.tempoMap,
        cppID: "arpeggiator/projection", what: "the full source tempo map remains authoritative")
    report.expectEqual(
        expected: [UInt64(12_000), 36_000, 30_000],
        actual: [pattern.loopStartSample, pattern.loopEndSample, pattern.lengthSamples],
        cppID: "arpeggiator/projection",
        what: "loop samples cross the tempo change and length follows scheduled events")
    let meters = pattern.timeSignatures.map(\.tick)
    let texts = pattern.otherEvents.map(\.tick)
    report.expectEqual(
        expected: [Tick(24), 0, 6], actual: [pattern.lengthTicks] + meters + texts,
        cppID: "arpeggiator/projection", what: "meters and text after the loop end are trimmed")
    report.expect(
        pattern.usedTrackCount == 3 && pattern.settings == source.settings && pattern.sampleRate == rate,
        cppID: "arpeggiator/projection",
        message: "pattern keeps the source track count, gate policy and sample rate")

    let noteOnly = PlaybackTimeline.pattern(
        source: source, notes: [NewNote(track: 1, tick: 12, pitch: 50, duration: 6, velocity: 90)],
        track: 1, range: range)
    report.expectEqual(
        expected: ["0:12:1:0:0@0", "12:9:1:50:90@12000", "18:8:1:50:0@24000"],
        actual: noteOnly.events.filter { (event: PlaybackEvent) -> Bool in event.track == 1 }.map(eventFacts),
        cppID: "arpeggiator/projection", what: "a note-only source track keeps its hardware identity and program 0")
    report.expectEqual(
        expected: ["true:0:5", "true:1:0"], actual: noteOnly.tracks.prefix(2).map(trackFacts),
        cppID: "arpeggiator/projection", what: "only the selected track counts generated notes")

    // The program-0 fallback follows the primary MIDI channel, not other channels sharing its track.
    let channels = PlaybackTimeline.build(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(status: 0x90, data0: 60, data1: 100),
                        .channel(status: 0xB1, data0: 7, data1: 90),
                        .channel(status: 0xD1, data0: 40),
                        .channel(tick: 24, status: 0x80, data0: 60),
                        .channel(tick: 30, status: 0xC0, data0: 9),
                    ], endTick: 48)
            ]),
        sampleRate: rate, settings: PlaybackSettings(exactGate: true))
    let leadNotes = [NewNote(track: 0, tick: 0, pitch: 64, duration: 6, velocity: 100)]
    let lead = PlaybackTimeline.pattern(source: channels, notes: leadNotes, track: 0, range: (start: 0, end: 24))
    report.expectEqual(
        expected: ["0:12:0:0:0@0", "0:11:0:7:90@0", "0:9:0:64:100@0", "6:8:0:64:0@6000"],
        actual: lead.events.filter { (event: PlaybackEvent) -> Bool in event.type != playbackTempoEventType }
            .map(eventFacts),
        cppID: "arpeggiator/projection",
        what: "a primary channel left with only notes gets program 0 even when another channel keeps controls")
    report.expectEqual(
        expected: ["true:1:0"], actual: lead.tracks.prefix(1).map(trackFacts),
        cppID: "arpeggiator/projection", what: "the fallback program is the multi-channel track's first program")
    let reprojected = PlaybackTimeline.pattern(
        source: lead, notes: leadNotes, track: 0, range: (start: 0, end: 24))
    report.expectEqual(
        expected: lead.events.map(eventFacts), actual: reprojected.events.map(eventFacts),
        cppID: "arpeggiator/projection",
        what: "a projected pattern is a valid source whose program-0 fallback is not added twice")

    // 240 BPM at 30000 PPQ is 0.4 samples per tick, so ticks 30000 and 30001 share sample 12000
    // and the earlier chunk's post-range controller precedes the later chunk's in-range one.
    let rounded = PlaybackTimeline.build(
        file: MidiFile(
            division: 30_000,
            chunks: [
                MidiChunk(events: [.meta(type: 0x51, data: [0x03, 0xD0, 0x90])], endTick: 30_001),
                MidiChunk(
                    events: [
                        .channel(status: 0x90, data0: 60, data1: 100),
                        .channel(tick: 15_000, status: 0x80, data0: 60),
                        .channel(tick: 30_001, status: 0xB0, data0: 7, data1: 11),
                    ], endTick: 30_001),
                MidiChunk(
                    events: [
                        .channel(status: 0x91, data0: 48, data1: 100),
                        .channel(tick: 15_000, status: 0x81, data0: 48),
                        .channel(tick: 30_000, status: 0xB1, data0: 7, data1: 22),
                    ], endTick: 30_001),
            ]),
        sampleRate: rate, settings: PlaybackSettings(exactGate: true))
    report.expectEqual(
        expected: [UInt64(12_000), 12_000], actual: [rounded.sample(for: 30_000), rounded.sample(for: 30_001)],
        cppID: "arpeggiator/projection", what: "the boundary controllers round to one sample")
    let roundedPattern = PlaybackTimeline.pattern(
        source: rounded, notes: [NewNote(track: 0, tick: 0, pitch: 64, duration: 3_000, velocity: 100)],
        track: 0, range: (start: 0, end: 30_000))
    report.expectEqual(
        expected: ["0:12:0:0:0@0", "30000:11:1:7:22@12000"],
        actual: roundedPattern.events.filter { (event: PlaybackEvent) -> Bool in
            event.type == 0xB || event.type == 0xC || event.type == 0xE
        }.map(eventFacts),
        cppID: "arpeggiator/projection",
        what: "a post-range controller sharing a sample with a later track's in-range controller "
            + "is dropped without hiding the in-range one")

    let steady = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .channel(status: 0xC0, data0: 0),
                    .channel(status: 0x90, data0: 60, data1: 100),
                    .channel(tick: 48, status: 0x80, data0: 60),
                ], endTick: 48)
        ])
    let gated = [
        NewNote(track: 0, tick: 0, pitch: 60, duration: 27, velocity: 100),
        NewNote(track: 0, tick: 0, pitch: 64, duration: 13, velocity: 100),
    ]
    func releases(_ settings: PlaybackSettings) -> [String] {
        let source = PlaybackTimeline.build(file: steady, sampleRate: rate, settings: settings)
        let pattern = PlaybackTimeline.pattern(source: source, notes: gated, track: 0, range: (start: 0, end: 48))
        return pattern.events.filter { (event: PlaybackEvent) -> Bool in event.type == 0x8 }
            .map { (event: PlaybackEvent) -> String in "\(event.data0):\(event.tick)@\(event.sample)" }
    }
    report.expectEqual(
        expected: ["64:13@13000", "60:27@24000"], actual: releases(PlaybackSettings()),
        cppID: "arpeggiator/projection", what: "table gates shorten a 27-clock release to 24 clocks")
    report.expectEqual(
        expected: ["64:13@13000", "60:27@27000"], actual: releases(PlaybackSettings(exactGate: true)),
        cppID: "arpeggiator/projection", what: "exact gates release at the generated note end")
    report.expectEqual(
        expected: ["64:13@12000", "60:27@27000"], actual: releases(PlaybackSettings(extendedClocks: true)),
        cppID: "arpeggiator/projection", what: "extended clocks apply the gate table to 48-clock durations")
    report.expectEqual(
        expected: ["64:13@13000", "60:27@27000"],
        actual: releases(PlaybackSettings(exactGate: true, extendedClocks: true)),
        cppID: "arpeggiator/projection", what: "exact extended gates keep both generated releases")
}

private func checkArpeggiatorReplacement(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    let song = rig.timeline(retriggerAt: 48)
    audio.bind(timeline: song, voicegroup: rig.voices, settings: AudioSettings())
    audio.play()
    _ = rig.render(24_000)
    let songPosition = audio.playheadSamples
    func loop(_ pitch: UInt8, at tick: Tick, duration: Tick) -> PlaybackTimeline {
        PlaybackTimeline.pattern(
            source: song, notes: [NewNote(track: 0, tick: tick, pitch: pitch, duration: duration, velocity: 100)],
            track: 0, range: (start: 24, end: 48))
    }
    let sustained = loop(72, at: 24, duration: 20)
    let superseded = loop(48, at: 30, duration: 12)
    let latest = loop(60, at: 24, duration: 6)
    audio.startPatternAudition(sustained)
    _ = rig.render(6_000)
    audio.replacePatternAudition(superseded)
    audio.replacePatternAudition(latest)
    report.expect(
        audio.isPatternAuditioning, cppID: "arpeggiator/replacement",
        message: "a published replacement keeps audition active before the callback adopts it")
    let adopted = rig.render(512)
    report.expectEqual(
        expected: latest.loopStartSample + 512, actual: audio.patternAuditionPositionSamples,
        cppID: "arpeggiator/replacement", what: "the next callback adopts the newest replacement at its loop start")
    // Through one wrap at the 24000-sample loop length, with the same callback boundaries as the reference.
    let hot = adopted + rig.render(29_488)
    let reference = try AudioControllerCheckFixture()
    reference.renderer.startPatternAudition(latest)
    let cold = reference.render(30_000)
    let difference = zip(hot, cold).reduce(Float(0)) { (worst: Float, pair: (Float, Float)) -> Float in
        max(worst, abs(pair.0 - pair.1))
    }
    report.expect(
        audioControllerCheckPeak(hot[...]) > 1 / 32768, cppID: "arpeggiator/replacement",
        message: "the replacement renders audible source-instrument notes")
    report.expect(
        difference <= 1 / 32768, cppID: "arpeggiator/replacement",
        message: "hot replacement matches a cold start of the newest loop without superseded pitches or buffered audio")
    report.expectEqual(
        expected: songPosition, actual: audio.playheadSamples,
        cppID: "arpeggiator/replacement", what: "replacement does not advance the original song")
    report.expectEqual(
        expected: song.events, actual: audio.timeline?.events,
        cppID: "arpeggiator/replacement", what: "replacement retains the original song timeline")
    report.expect(
        audio.transport == .paused, cppID: "arpeggiator/replacement",
        message: "replacement leaves the song transport paused")

    func expectCancelled(_ scenario: String, _ cancel: () -> Void) {
        audio.startPatternAudition(sustained)
        _ = rig.render(2_048)
        audio.replacePatternAudition(latest)
        cancel()
        audio.replacePatternAudition(superseded)
        report.expect(
            !audio.isPatternAuditioning, cppID: "arpeggiator/replacement",
            message: "\(scenario) clears a pending replacement and refuses later ones")
        report.expect(
            audioControllerCheckPeak(rig.render(4_096)[...]) <= 1 / 32768, cppID: "arpeggiator/replacement",
            message: "\(scenario) cannot resurrect a replaced pattern")
    }
    expectCancelled("stop") { audio.stopPatternAudition() }
    expectCancelled("settings replacement") { audio.updateSettings(AudioSettings()) }
    expectCancelled("bank replacement") { audio.updateVoicegroup(rig.voices) }
    expectCancelled("unload") { audio.unload() }
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
