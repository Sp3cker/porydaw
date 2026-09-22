import PorydawCore

@MainActor
internal func coreRangeCorpusChecks(_ report: CheckReport) {
    do {
        try coreRangeCollisionChecks(report)
        var rows = 0
        for loaded in try coreEditCorpusSongs(report) {
            let file = try MidiFile.decode(loaded.midiBytes)
            let classified = SongDocument(file: file, config: loaded.config, source: loaded.source)
            guard let track = (0..<classified.engineTracks.usedTrackCount).first(where: {
                !classified.notes(in: $0).isEmpty
            }) else { continue } // Native EditableTrack data-row classification.
            rows += 1
            for scenario in ["rangeEdit", "rangeMove", "rangeLaneBulk", "rangeLaneConverge"] {
                let id = "editcheck/EditCheckTest::\(scenario)[\(loaded.label)]"
                report.expect(!loaded.midiPath.isEmpty, cppID: id, message: "editable row has a MIDI path")
                let document = SongDocument(file: try MidiFile.decode(loaded.midiBytes),
                                            config: loaded.config, source: loaded.source)
                report.expect(!document.notes(in: track).isEmpty, cppID: id,
                              message: "classified row reloads with an editable track")
                let base = coreEditDistantBase(document)
                let step = Tick(max(1, document.ticksPerBeat /
                    (24 * (document.state.config.extendedClocks ? 2 : 1))))
                switch scenario {
                case "rangeEdit": try coreRangeEditRow(report, document, track, base, step, id)
                case "rangeMove": try coreRangeMoveRow(report, document, track, base, step, id)
                default: try coreRangeLaneRow(report, document, track, base, step, id,
                                              converge: scenario == "rangeLaneConverge")
                }
            }
        }
        report.expect(rows > 0, cppID: "editcheck/EditCheckTest::addSongRows",
                      message: "corpus contains an EditableTrack row")
    } catch {
        report.fail("editcheck/EditCheckTest::rangeEdit", "range corpus failed: \(error)")
    }
}

@MainActor
internal func coreRangeHistoryPosition(_ document: SongDocument, _ report: CheckReport,
                                       _ id: String) -> [Int] {
    let state = document.state
    let identity = document.history.currentIdentity
    var index = 0
    while document.history.undoDocument() { index += 1 }
    var count = 0
    while document.history.redoDocument() { count += 1 }
    for _ in index..<count { _ = document.history.undoDocument() }
    report.expect(document.state == state && document.history.currentIdentity == identity,
                  cppID: id, message: "history observation restores original cursor, state and identity")
    return [count, index]
}

@MainActor
private func coreRangeExpectRejected(_ document: SongDocument, _ report: CheckReport,
                                     _ id: String, operation: () -> Void) throws {
    let position = coreRangeHistoryPosition(document, report, id)
    let state = document.state
    let bytes = try state.file.encoded()
    let revision = document.revision
    let identity = document.history.currentIdentity
    let dirty = document.isDirty
    let canRedo = document.history.canRedo
    let tracks = document.engineTracks.usedTrackCount
    let notes = document.notes(in: 0)
    operation()
    // Observe revision before the second public history traversal increments it.
    report.expect(document.state == state && document.revision == revision &&
        document.history.currentIdentity == identity && document.isDirty == dirty &&
        document.history.canRedo == canRedo && document.engineTracks.usedTrackCount == tracks &&
        document.notes(in: 0) == notes, cppID: id,
        message: "rejected range preserves state, revision, save identity, clean flag, redo, tracks and notes")
    report.expectEqual(bytes, try document.state.file.encoded(), cppID: id,
                       what: "rejected range preserves exact MIDI bytes")
    report.expectEqual(position, coreRangeHistoryPosition(document, report, id), cppID: id,
                       what: "rejected range preserves history count and cursor")
}

@MainActor
internal func coreRangeNotePairsConsistent(_ document: SongDocument, track: Int) -> Bool {
    guard let chunk = document.engineTracks.tracks[track].midiChunk else { return false }
    let events = document.rawChunks[chunk].events
    var starts = Array(repeating: 0, count: events.count)
    var ends = starts
    var lastEnd = Array(repeating: UInt64(0), count: 128)
    for note in document.notes(in: track) {
        guard let endIndex = note.endIndex, note.duration > 0,
              events.indices.contains(note.onIndex), events.indices.contains(endIndex),
              note.pitch < 128, UInt64(note.tick) >= lastEnd[Int(note.pitch)] else { return false }
        let on = events[note.onIndex]
        let end = events[endIndex]
        guard case let .channel(_, onKey, _) = on.payload,
              case let .channel(_, endKey, _) = end.payload,
              on.isNoteOn, end.isNoteEnd, onKey == endKey, on.channel == end.channel,
              end.tick > on.tick, UInt64(on.tick) + UInt64(note.duration) == UInt64(end.tick)
        else { return false }
        starts[note.onIndex] += 1
        ends[endIndex] += 1
        guard starts[note.onIndex] == 1, ends[endIndex] == 1 else { return false }
        lastEnd[Int(note.pitch)] = UInt64(end.tick)
    }
    for (index, event) in events.enumerated() where event.isChannel &&
        event.channel == document.engineTracks.tracks[track].channel {
        if (event.isNoteOn && starts[index] != 1) || (event.isNoteEnd && ends[index] != 1) { return false }
    }
    return true
}

@MainActor
private func coreRangeCollisionChecks(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::rangeEditCollisionRejects"
    let chunks = [
        MidiChunk(events: [.meta(type: 0x01, data: Array("contract fixture".utf8))], endTick: 48),
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 200),
    ]
    for empty in [false, true] {
        // Encoding and decoding exercise the original synthetic SMF fixture boundary.
        let file = try MidiFile.decode(MidiFile(division: 24, chunks: empty ? [] : chunks).encoded())
        let document = SongDocument(file: file)
        if !empty {
            _ = try document.addNotes([NewNote(track: 0, tick: 0, pitch: 60, duration: 100, velocity: 91)])
            document.writeLane(track: 0, lane: .controller(7), from: 20, through: 20,
                               points: [LaneWrite(tick: 20, value: 80)])
            _ = try document.addNotes([NewNote(track: 0, tick: 150, pitch: 61, duration: 10, velocity: 92)])
            _ = document.history.undoDocument()
        }
        let edit = RangeEdit(minimumEngineTrackCount: 2,
            removeNotes: empty ? [] : document.notes(in: 0),
            addNotes: [NewNote(track: 1, tick: 10, pitch: 60, duration: 20, velocity: 80),
                       NewNote(track: 1, tick: 20, pitch: 60, duration: 20, velocity: 90)],
            addPoints: [RangeEdit.LaneInsertion(track: 1, lane: .controller(7),
                                               points: [LaneWrite(tick: 10, value: 90)])],
            addTempo: [coreRangeTempo(10, 150)])
        try coreRangeExpectRejected(document, report, id) { _ = document.applyRangeEdit(edit) }
    }
    let document = SongDocument(file: try MidiFile.decode(MidiFile(division: 24, chunks: chunks).encoded()))
    _ = try document.addNotes([
        NewNote(track: 0, tick: 20, pitch: 60, duration: 10, velocity: 81),
        NewNote(track: 0, tick: 30, pitch: 60, duration: 70, velocity: 92),
    ])
    document.writeLane(track: 0, lane: .controller(7), from: 10, through: 10,
                       points: [LaneWrite(tick: 10, value: 80)])
    document.editTempo(TempoEdit(add: [coreRangeTempo(10, 150)]))
    let first = document.notes(in: 0)[0]
    try coreRangeExpectRejected(document, report, id) {
        _ = document.moveRange(notes: [first], points: document.lanePoints(track: 0, lane: .controller(7)),
                               by: -30, tempo: document.state.tempo)
    }
    _ = try document.addNotes([NewNote(track: 0, tick: 60, pitch: 60, duration: 20, velocity: 73)])
    guard let moving = document.notes(in: 0).first(where: { $0.tick == 30 && $0.pitch == 60 }) else {
        report.fail(id, "moving note at30 exists"); return
    }
    let before = try document.state.file.encoded()
    _ = document.moveRange(notes: [moving], points: [], by: -40)
    report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                  message: "clipped move retains consistent on/off pairs")
    for (tick, duration): (Tick, Tick) in [(60, 20), (20, 10), (0, 20)] {
        report.expectEqual(duration, document.notes(in: 0).first { $0.tick == tick && $0.pitch == 60 }?.duration,
                           cppID: id, what: "note at\(tick) exists with original expected duration")
    }
    let after = try document.state.file.encoded()
    _ = document.history.undoDocument()
    report.expectEqual(before, try document.state.file.encoded(), cppID: id, what: "clipped move undo bytes")
    _ = document.history.redoDocument()
    report.expectEqual(after, try document.state.file.encoded(), cppID: id, what: "clipped move redo bytes")
    report.expect(coreRangeNotePairsConsistent(document, track: 0), cppID: id,
                  message: "redo retains consistent on/off pairs")
}

private func coreRangeTempo(_ tick: Tick, _ bpm: UInt32) -> TempoPoint {
    TempoPoint(tick: tick, microsecondsPerQuarterNote: 60_000_000 / bpm)
}

@MainActor
private func coreRangeEditRow(_ report: CheckReport, _ document: SongDocument,
                              _ track: Int, _ base: Tick, _ step: Tick, _ id: String) throws {
    func tick(_ clock: Tick) -> Tick { base + step * clock }
    func note(_ clock: Tick, _ pitch: UInt8) -> Note? {
        document.notes(in: track).first { $0.tick == tick(clock) && $0.pitch == pitch }
    }
    _ = try document.addNotes([
        NewNote(track: track, tick: tick(30), pitch: 60, duration: step * 2, velocity: 90),
        NewNote(track: track, tick: tick(32), pitch: 62, duration: step * 2, velocity: 90),
    ])
    document.writeLane(track: track, lane: .controller(7), from: tick(30), through: tick(30),
                       points: [LaneWrite(tick: tick(30), value: 80)])
    document.editTempo(TempoEdit(add: [coreRangeTempo(tick(31), 140)]))
    let edit = RangeEdit(
        removeNotes: document.notes(in: track).filter { $0.tick == tick(30) || $0.tick == tick(32) },
        removePoints: document.lanePoints(track: track, lane: .controller(7)).filter { $0.tick == tick(30) },
        addNotes: [NewNote(track: track, tick: tick(40), pitch: 65, duration: step * 2, velocity: 90)],
        addPoints: [RangeEdit.LaneInsertion(track: track, lane: .controller(7),
                                          points: [LaneWrite(tick: tick(40), value: 70)])],
        removeTempo: [coreRangeTempo(tick(31), 140)], addTempo: [coreRangeTempo(tick(41), 155)])
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    _ = document.applyRangeEdit(edit)
    report.expect(note(30, 60) == nil && note(32, 62) == nil && note(40, 65) != nil,
                  cppID: id, message: "old notes removed and replacement present")
    report.expectEqual(70, document.lanePoints(track: track, lane: .controller(7))
        .first { $0.tick == tick(40) }?.value, cppID: id, what: "replacement lane exists with value70")
    report.expect(document.state.tempo.contains(coreRangeTempo(tick(41), 155)),
                  cppID: id, message: "replacement tempo exists")
    report.expectEqual(before + 1, try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "mixed edit adds one history entry")
    _ = document.history.undoDocument()
    report.expect(note(30, 60) != nil && note(32, 62) != nil && note(40, 65) == nil &&
        !document.state.tempo.contains(coreRangeTempo(tick(41), 155)),
        cppID: id, message: "undo restores originals and removes replacement note and tempo")
    _ = document.history.redoDocument()
    report.expect(note(40, 65) != nil, cppID: id, message: "redo restores replacement note")
}

@MainActor
private func coreRangeMoveRow(_ report: CheckReport, _ document: SongDocument,
                              _ track: Int, _ base: Tick, _ step: Tick, _ id: String) throws {
    func tick(_ clock: Tick) -> Tick { base + step * clock }
    func note(_ clock: Tick, _ pitch: UInt8) -> Note? {
        document.notes(in: track).first { $0.tick == tick(clock) && $0.pitch == pitch }
    }
    func point(_ clock: Tick) -> LanePoint? {
        document.lanePoints(track: track, lane: .controller(7)).first { $0.tick == tick(clock) }
    }
    _ = try document.addNotes([
        NewNote(track: track, tick: tick(80), pitch: 60, duration: step * 2, velocity: 90),
        NewNote(track: track, tick: tick(82), pitch: 64, duration: step * 2, velocity: 90),
    ])
    document.writeLane(track: track, lane: .controller(7), from: tick(80), through: tick(80),
                       points: [LaneWrite(tick: tick(80), value: 45)])
    document.editTempo(TempoEdit(add: [coreRangeTempo(tick(81), 140)]))
    guard let first = note(80, 60), let second = note(82, 64), let lane = point(80) else {
        report.fail(id, "both source notes and lane point must exist"); return
    }
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    _ = document.moveRange(notes: [first, second], points: [lane], by: Int64(step) * 3,
                           tempo: [coreRangeTempo(tick(81), 140)])
    report.expectEqual(step * 2, note(83, 60)?.duration, cppID: id, what: "first moved note duration")
    report.expectEqual(step * 2, note(85, 64)?.duration, cppID: id, what: "second moved note duration")
    report.expectEqual(45, point(83)?.value, cppID: id, what: "moved lane point value")
    report.expect(document.state.tempo.contains(coreRangeTempo(tick(84), 140)),
                  cppID: id, message: "tempo moves with the range")
    report.expectEqual(before + 1, try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "range move adds one history entry")
    guard let moved = note(83, 60), let movedLane = point(83) else {
        report.fail(id, "moved first note and lane must exist"); return
    }
    _ = document.moveRange(notes: [moved], points: [movedLane], by: 0, tempo: [])
    report.expectEqual(before + 1, try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "zero delta adds no history entry")
    _ = document.history.undoDocument()
    report.expect(note(80, 60) != nil && note(82, 64) != nil, cppID: id, message: "undo restores source notes")
    _ = document.history.redoDocument()
    report.expect(note(83, 60) != nil, cppID: id, message: "redo restores first destination note")
}

@MainActor
private func coreRangeLaneRow(_ report: CheckReport, _ document: SongDocument,
                              _ track: Int, _ base: Tick, _ step: Tick, _ id: String,
                              converge: Bool) throws {
    func tick(_ clock: Tick) -> Tick { base + step * clock }
    func point(_ clock: Tick) -> LanePoint? {
        document.lanePoints(track: track, lane: .controller(7)).first { $0.tick == tick(clock) }
    }
    let values = converge ? [25, 45] : [20, 40, 60]
    for (offset, value) in values.enumerated() {
        let position = tick(90 + Tick(offset))
        document.writeLane(track: track, lane: .controller(7), from: position, through: position,
                           points: [LaneWrite(tick: position, value: value)])
    }
    guard let first = point(90), let second = point(91) else {
        report.fail(id, "both lane source points must exist"); return
    }
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    document.moveLanePoints(track: track, lane: .controller(7), moves: [
        LanePointMove(point: first, tick: tick(converge ? 97 : 93), value: converge ? 70 : 25),
        LanePointMove(point: second, tick: tick(converge ? 97 : 94), value: converge ? 72 : 45),
    ])
    if converge {
        let destination = document.lanePoints(track: track, lane: .controller(7)).filter { $0.tick == tick(97) }
        for lane in destination {
            report.expectEqual(72, lane.value, cppID: id, what: "every converged destination has later value")
        }
        report.expectEqual(1, destination.count, cppID: id, what: "one converged destination")
    } else {
        report.expectEqual(25, point(93)?.value, cppID: id, what: "first moved lane exists with value25")
        report.expectEqual(45, point(94)?.value, cppID: id, what: "second moved lane exists with value45")
        report.expectEqual(60, point(92)?.value, cppID: id, what: "stationary lane exists with value60")
    }
    report.expectEqual(before + 1, try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "bulk lane move adds one history entry")
    _ = document.history.undoDocument()
    report.expectEqual(values[0], point(90)?.value, cppID: id, what: "undo restores first source")
    report.expectEqual(values[1], point(91)?.value, cppID: id, what: "undo restores second source")
    report.expect(point(converge ? 97 : 93) == nil, cppID: id, message: "undo removes destination")
    if !converge {
        _ = document.history.redoDocument()
        report.expect(point(93) != nil, cppID: id, message: "redo restores first destination")
    }
}
