import PorydawCore

private func rawOn(_ tick: Int64, _ pitch: Int, _ velocity: Int = 100, id: Int32? = nil) -> RawNoteEvent {
    RawNoteEvent(tick: tick, pitch: pitch, velocity: velocity, isOn: true, noteID: id)
}

private func rawOff(_ tick: Int64, _ pitch: Int, id: Int32? = nil) -> RawNoteEvent {
    RawNoteEvent(tick: tick, pitch: pitch, velocity: 0, isOn: false, noteID: id)
}

@MainActor
private func checkEngineLattice(_ report: CheckReport) throws {
    let normal = try EngineNoteLattice(ticksPerBeat: 480, playbackSettings: PlaybackSettings())
    let extended = try EngineNoteLattice(
        ticksPerBeat: 96, playbackSettings: PlaybackSettings(extendedClocks: true))
    let coarse = try EngineNoteLattice(
        ticksPerBeat: 24, playbackSettings: PlaybackSettings(extendedClocks: true))
    report.expectEqual(
        expected: [Int64(20), 1, 2, 1, 1, 2],
        actual: [
            normal.quantumTicks, normal.quantumClocks, extended.quantumTicks,
            extended.quantumClocks, coarse.quantumTicks, coarse.quantumClocks,
        ],
        cppID: "normalizer/lattice", what: "the gcd lattice covers fine, extended and coarser-than-clock divisions")
    report.expectEqual(
        expected: [Int64(-20), 0, 0, 20, 20, 40],
        actual: [-11, -10, 9, 10, 29, 30].map { (tick: Int64) -> Int64 in normal.snap(tick) },
        cppID: "normalizer/snap", what: "nearest rounding chooses later points at positive and negative half quanta")
    report.expect(
        normal.isOnLattice(40) && normal.isOnLattice(-20) && !normal.isOnLattice(21),
        cppID: "normalizer/lattice", message: "lattice membership uses exact tick divisibility")
    report.expectEqual(
        expected: Optional<Int64>.none, actual: normal.durationTicks(target: 19, maximum: 19),
        cppID: "normalizer/duration", what: "a slot shorter than one quantum cannot hold a duration")
    for exact in [false, true] {
        let lattice = try EngineNoteLattice(ticksPerBeat: 24, playbackSettings: PlaybackSettings(exactGate: exact))
        report.expectEqual(
            expected: Int64?(exact ? 26 : 28), actual: lattice.durationTicks(target: 26, maximum: 96),
            cppID: "normalizer/duration", what: "nearest duration honors Exact Gate and later fixed-point ties")
        for target in 1...192 {
            if let ticks = lattice.durationTicks(target: Double(target), maximum: 192) {
                report.expectEqual(
                    expected: Int(ticks),
                    actual: mid2agbEffectiveDuration(ticks, division: 24, extendedClocks: false, exactGate: exact),
                    cppID: "normalizer/fixedpoint", what: "every selected duration survives export unchanged")
            } else {
                report.fail("normalizer/fixedpoint", "a positive duration unexpectedly had no fixed point")
            }
        }
    }
    do {
        _ = try EngineNoteLattice(ticksPerBeat: 0, playbackSettings: PlaybackSettings())
        report.fail("normalizer/lattice", "zero division was accepted")
    } catch ArpeggiatorError.unsupportedTiming {
        report.expect(true, cppID: "normalizer/lattice", message: "zero division reports unsupported timing")
    }
}

@MainActor
private func checkEnginePairing(_ report: CheckReport) throws {
    let lattice = try EngineNoteLattice(ticksPerBeat: 24, playbackSettings: PlaybackSettings(exactGate: true))
    let range = TimeRange(startTick: 0, endTick: 24)
    let identified = try EngineNoteNormalizer.normalize(
        [rawOff(10, 62, id: 7), rawOn(2, 62, id: 8), rawOff(6, 60, id: 8), rawOn(0, 60, id: 7)],
        track: 3, range: range, lattice: lattice)
    report.expectEqual(
        expected: [
            NewNote(track: 3, tick: 0, pitch: 60, duration: 10, velocity: 100),
            NewNote(track: 3, tick: 2, pitch: 62, duration: 4, velocity: 100),
        ],
        actual: identified.notes, cppID: "normalizer/pair-id",
        what: "positive IDs pair independently of off pitch and input order")
    let reused = try EngineNoteNormalizer.normalize(
        [rawOn(0, 60, id: 9), rawOn(2, 62, id: 9), rawOff(4, 62, id: 9), rawOff(8, 60, id: 9)],
        track: 0, range: range, lattice: lattice)
    report.expectEqual(
        expected: [Tick(4), 6], actual: reused.notes.map(\.duration), cppID: "normalizer/pair-id",
        what: "concurrently reused positive IDs consume their onsets FIFO")
    let fifo = try EngineNoteNormalizer.normalize(
        [rawOn(0, 60), rawOn(2, 60, id: 0), rawOff(6, 60, id: -1), rawOff(10, 60)],
        track: 0, range: range, lattice: lattice)
    report.expectEqual(
        expected: [Tick(2), 8], actual: fifo.notes.map(\.duration), cppID: "normalizer/pair-fifo",
        what: "nil and nonpositive IDs share a pitch FIFO, then the earlier overlap is trimmed")
    report.expectEqual(
        expected: 1, actual: fifo.report.overlapsTrimmed, cppID: "normalizer/overlap",
        what: "one surviving prior note was trimmed")
    let retrigger = try EngineNoteNormalizer.normalize(
        [
            rawOn(0, 60), rawOn(6, 60), rawOff(6, 60),
            RawNoteEvent(tick: 12, pitch: 60, velocity: 0, isOn: true), rawOff(15, 67), rawOn(18, 64),
        ],
        track: 0, range: range, lattice: lattice)
    report.expectEqual(
        expected: [Tick(6), 6, 6], actual: retrigger.notes.map(\.duration), cppID: "normalizer/pair-order",
        what: "offs precede equal-tick ons, velocity-zero ons release, and open notes close at range end")
    report.expectEqual(
        expected: 1, actual: retrigger.report.orphanOffs, cppID: "normalizer/orphan",
        what: "an unmatched release is counted once")
    report.expectEqual(
        expected: 1, actual: retrigger.report.unterminatedNotes, cppID: "normalizer/unterminated",
        what: "one open onset was closed at the range end")
}

@MainActor
private func checkEngineNormalizationPolicy(_ report: CheckReport) throws {
    let fine = try EngineNoteLattice(ticksPerBeat: 480, playbackSettings: PlaybackSettings(exactGate: true))
    let range = TimeRange(startTick: 0, endTick: 100)
    let dropped = try EngineNoteNormalizer.normalize(
        [
            rawOn(-21, -1, 200, id: 1), rawOff(40, -1, id: 1),
            rawOn(100, 128, 200, id: 2), rawOff(120, 128, id: 2),
            rawOn(40, 128, 200, id: 3), rawOff(80, 128, id: 3),
            rawOn(10, 60, 200, id: 4), rawOff(39, 60, id: 4),
            rawOn(60, -1, 200, id: 5), rawOff(80, -1, id: 5),
        ],
        track: 0, range: range, lattice: fine)
    var expectedDrops = NormalizationReport()
    expectedDrops.droppedBeforeRange = 1
    expectedDrops.droppedAfterRange = 1
    expectedDrops.droppedPitch = 2
    expectedDrops.droppedTooShort = 1
    report.expectEqual(
        expected: expectedDrops, actual: dropped.report, cppID: "normalizer/drops",
        what: "ordered rejection counts one drop per onset and no adjustments for discarded notes")
    let duplicates = try EngineNoteNormalizer.normalize(
        [
            rawOn(1, 60, 200, id: 1), rawOff(61, 60, id: 1),
            rawOn(0, 64, 100, id: 2), rawOff(80, 64, id: 2),
            rawOn(2, 60, 100, id: 3), rawOff(80, 60, id: 3),
        ],
        track: 2, range: range, lattice: fine)
    report.expectEqual(
        expected: [UInt8(64), 60], actual: duplicates.notes.map(\.pitch), cppID: "normalizer/duplicates",
        what: "later same-pitch events win while chords and surviving event order remain intact")
    var expectedDuplicates = NormalizationReport()
    expectedDuplicates.notes = 2
    expectedDuplicates.snappedOnsets = 1
    expectedDuplicates.duplicatesSuppressed = 1
    report.expectEqual(
        expected: expectedDuplicates, actual: duplicates.report, cppID: "normalizer/report",
        what: "discarded duplicate velocity and duration adjustments do not leak into the report")
    let snapped = try EngineNoteNormalizer.normalize(
        [rawOn(10, 0, -4), rawOff(70, 0), rawOn(80, 127, 999), rawOff(140, 127)],
        track: 5, range: TimeRange(startTick: 0, endTick: 120), lattice: fine)
    report.expectEqual(
        expected: [
            NewNote(track: 5, tick: 20, pitch: 0, duration: 60, velocity: 1),
            NewNote(track: 5, tick: 80, pitch: 127, duration: 40, velocity: 127),
        ],
        actual: snapped.notes, cppID: "normalizer/bounds",
        what: "pitch endpoints survive, velocities clamp and durations preserve release targets within range")
    report.expectEqual(
        expected: [1, 2, 2, 2],
        actual: [
            snapped.report.snappedOnsets, snapped.report.adjustedDurations,
            snapped.report.velocityClamped, snapped.report.notes,
        ],
        cppID: "normalizer/report", what: "surviving onset, gate, velocity and note counts are exact")
    for exact in [false, true] {
        let lattice = try EngineNoteLattice(ticksPerBeat: 24, playbackSettings: PlaybackSettings(exactGate: exact))
        let result = try EngineNoteNormalizer.normalize(
            [rawOn(0, 60), rawOff(26, 60), rawOn(40, 60), rawOff(90, 60)],
            track: 0, range: TimeRange(startTick: 0, endTick: 96), lattice: lattice)
        report.expectEqual(
            expected: Tick(exact ? 26 : 28), actual: result.notes[0].duration,
            cppID: "normalizer/fixedpoint", what: "batch duration selection uses the shared fixed-point policy")
        report.expect(
            result.notes.allSatisfy { (note: NewNote) -> Bool in
                mid2agbEffectiveDuration(
                    Int64(note.duration), division: 24, extendedClocks: false,
                    exactGate: exact) == Int(note.duration)
            }, cppID: "normalizer/fixedpoint", message: "every batch note duration is an export fixed point")
    }
    let table = try EngineNoteLattice(ticksPerBeat: 24, playbackSettings: PlaybackSettings())
    let trimmed = try EngineNoteNormalizer.normalize(
        [rawOn(0, 60), rawOff(90, 60), rawOn(26, 60), rawOff(80, 60)],
        track: 0, range: TimeRange(startTick: 0, endTick: 96), lattice: table)
    report.expectEqual(
        expected: Tick(24), actual: trimmed.notes[0].duration, cppID: "normalizer/overlap",
        what: "overlap trimming chooses a fixed point not later than the next onset")
    report.expectEqual(
        expected: 1, actual: trimmed.report.overlapsTrimmed, cppID: "normalizer/overlap",
        what: "fixed-point overlap trimming is counted on the surviving prior note")
}

@MainActor
private func checkEngineNormalizationLimits(_ report: CheckReport) throws {
    let lattice = try EngineNoteLattice(ticksPerBeat: 24, playbackSettings: PlaybackSettings(exactGate: true))
    let range = TimeRange(startTick: 0, endTick: Tick((EngineNoteNormalizer.noteLimit + 1) * 2))
    var events: [RawNoteEvent] = []
    events.reserveCapacity((EngineNoteNormalizer.noteLimit + 1) * 2)
    for index in 0..<EngineNoteNormalizer.noteLimit {
        events.append(rawOn(Int64(index * 2), 60))
        events.append(rawOff(Int64(index * 2 + 1), 60))
    }
    let boundary = try EngineNoteNormalizer.normalize(events, track: 0, range: range, lattice: lattice)
    report.expectEqual(
        expected: EngineNoteNormalizer.noteLimit, actual: boundary.report.notes, cppID: "normalizer/limit",
        what: "exactly 65,536 surviving notes are accepted")
    events.append(rawOn(0, 60))
    events.append(rawOff(1, 60))
    let suppressed = try EngineNoteNormalizer.normalize(events, track: 0, range: range, lattice: lattice)
    report.expectEqual(
        expected: EngineNoteNormalizer.noteLimit, actual: suppressed.report.notes, cppID: "normalizer/limit",
        what: "a duplicate above the raw onset limit is suppressed before enforcing the output limit")
    report.expectEqual(
        expected: 1, actual: suppressed.report.duplicatesSuppressed, cppID: "normalizer/limit",
        what: "the extra same-tick event replaces its stable predecessor")
    events.append(rawOn(Int64(EngineNoteNormalizer.noteLimit * 2), 60))
    events.append(rawOff(Int64(EngineNoteNormalizer.noteLimit * 2 + 1), 60))
    do {
        _ = try EngineNoteNormalizer.normalize(events, track: 0, range: range, lattice: lattice)
        report.fail("normalizer/limit", "65,537 surviving notes were accepted")
    } catch NormalizationError.tooManyNotes {
        report.expect(true, cppID: "normalizer/limit", message: "oversized output throws tooManyNotes")
    }
    for invalid in [TimeRange(startTick: 1, endTick: 1), TimeRange(startTick: 0, endTick: TimeDefaults.noTick)] {
        do {
            _ = try EngineNoteNormalizer.normalize([], track: 0, range: invalid, lattice: lattice)
            report.fail("normalizer/range", "invalid range was accepted")
        } catch NormalizationError.invalidRange {
            report.expect(true, cppID: "normalizer/range", message: "empty and reserved bounds are rejected")
        }
    }
}

@MainActor
public func runEngineNoteNormalizerChecks(_ report: CheckReport) {
    do {
        try checkEngineLattice(report)
        try checkEnginePairing(report)
        try checkEngineNormalizationPolicy(report)
        try checkEngineNormalizationLimits(report)
    } catch {
        report.fail("normalizer/unexpected", "unexpected normalization error: \(error)")
    }
}
