import PorydawCore

private func coreTimeTempo(_ tick: Tick, _ bpm: UInt32) -> TempoPoint {
    TempoPoint(tick: tick, microsecondsPerQuarterNote: 60_000_000 / bpm)
}

@MainActor
private func coreTimeTracksSorted(_ document: SongDocument) -> Bool {
    document.rawChunks.allSatisfy { chunk in
        zip(chunk.events, chunk.events.dropFirst()).allSatisfy { $0.tick <= $1.tick }
    }
}

@MainActor
internal func coreTimeCorpusChecks(_ report: CheckReport) {
    do {
        var rows = 0
        for loaded in try coreEditCorpusSongs(report) {
            let file = try MidiFile.decode(loaded.midiBytes)
            let classified = SongDocument(file: file, config: loaded.config,
                                          source: loaded.source)
            guard firstNoteTrack(classified) != nil else { continue } // Native EditableTrack rows.
            rows += 1
            for (scenario, pathSite, loadSite, trackSite) in [
                ("timeRangeRemove", "A001", "A002", "A003"),
                ("songWholeSongRemove", "A013", "A014", "A015"),
                ("automationLanePoints", "A041", "A042", "A043"),
                ("voiceLanePoint", "A033", "A034", "A035"),
            ] {
                let id = "editcheck/EditCheckTest::\(scenario)[\(loaded.label)]"
                report.expect(!loaded.midiPath.isEmpty, cppID: id,
                              message: "\(pathSite) editable row has a MIDI path")
                do {
                    let document = SongDocument(file: try MidiFile.decode(loaded.midiBytes),
                                                config: loaded.config, source: loaded.source)
                    report.pass(id, row: "\(loadSite) staged MIDI decoded and loaded")
                    let track = firstNoteTrack(document)
                    report.expect(track != nil, cppID: id,
                                  message: "\(trackSite) reloaded row has an editable track")
                    guard let track else { continue }
                    let base = coreEditDistantBase(document)
                    let clocksPerBeat = 24 * (document.state.config.extendedClocks ? 2 : 1)
                    let step = Tick(max(1, document.ticksPerBeat / clocksPerBeat))
                    switch scenario {
                    case "timeRangeRemove":
                        try coreTimeRemoveRow(report, document, track, base, step, id)
                    case "songWholeSongRemove":
                        try coreTimeWholeSongRow(report, document, track, base, step, id)
                    case "automationLanePoints":
                        try coreTimeAutomationRow(report, document, track, base, step, id)
                    default:
                        try coreTimeVoiceRow(report, document, track, base, step, id)
                    }
                } catch {
                    report.fail(id, "time corpus row failed: \(error)")
                }
            }
        }
        report.expect(rows > 0, cppID: "editcheck/EditCheckTest::timeCorpusRows",
                      message: "corpus contains an EditableTrack row")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeRemove",
                    "time corpus failed: \(error)")
    }
}

@MainActor
private func coreTimeRemoveRow(_ report: CheckReport, _ document: SongDocument,
                               _ track: Int, _ base: Tick, _ step: Tick,
                               _ id: String) throws {
    let inserted = try document.addNotes([
        NewNote(track: track, tick: base + 50 * step, pitch: 60, duration: step, velocity: 90),
        NewNote(track: track, tick: base + 52 * step, pitch: 62, duration: step, velocity: 90),
        NewNote(track: track, tick: base + 56 * step, pitch: 64, duration: step,
                velocity: 90),
    ])
    document.writeLane(track: track, lane: .controller(7), from: base + 51 * step,
                       through: base + 52 * step,
                       points: [LaneWrite(tick: base + 51 * step, value: 30),
                                LaneWrite(tick: base + 52 * step, value: 40)])
    let originalTempo = document.state.tempo
    let before = coreTimeBytes(document)
    let position = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    report.expect(document.removeTime(TimeRange(startTick: base + 51 * step,
                                                endTick: base + 54 * step),
                                      scope: TimeScope(tracks: [track])),
                  cppID: id, message: "scoped removal commits")
    report.expect(document.notes(in: track).contains {
        $0.tick == base + 50 * step && $0.pitch == 60
    }, cppID: id, message: "pre-range note survives")
    report.expect(document.notes(in: track).contains {
        $0.id == inserted[2] && $0.tick == base + 53 * step && $0.pitch == 64
    }, cppID: id, message: "post-range note ripples left")
    report.expect(!document.notes(in: track).contains { $0.id == inserted[1] },
                  cppID: id, message: "in-range note is removed")
    report.expectEqual("\(base + 51 * step):40",
                       document.lanePoints(track: track, lane: .controller(7))
                           .first(where: { $0.tick == base + 51 * step }).map(coreTimePointShape),
                       cppID: id, what: "last in-range CC7 value is rescued to the seam")
    report.expectEqual(position + 1,
                       try coreEditHistoryCountAtTip(document, report: report,
                                                     cppID: id),
                       cppID: id, what: "removal adds one history entry")
    let after = coreTimeBytes(document)
    _ = document.history.undoDocument()
    report.expectEqual(before, coreTimeBytes(document), cppID: id,
                       what: "one undo restores the removal")
    report.expect(document.notes(in: track).contains {
        $0.id == inserted[1] && $0.tick == base + 52 * step && $0.pitch == 62
    }, cppID: id, message: "undo restores the removed note")
    _ = document.history.redoDocument()
    report.expectEqual(after, coreTimeBytes(document), cppID: id,
                       what: "one redo restores the removal")
    report.expect(document.notes(in: track).contains {
        $0.id == inserted[2] && $0.tick == base + 53 * step && $0.pitch == 64
    }, cppID: id, message: "redo restores the rippled note")
    report.expectEqual(originalTempo, document.state.tempo, cppID: id,
                       what: "track-scoped removal leaves tempo untouched")
}

@MainActor
private func coreTimeWholeSongRow(_ report: CheckReport, _ document: SongDocument,
                                  _ track: Int, _ base: Tick, _ step: Tick,
                                  _ id: String) throws {
    let shiftedID = try document.addNotes([
        NewNote(track: track, tick: base + 66 * step, pitch: 65, duration: step, velocity: 90),
    ])[0]
    document.setTimeSignature(tick: base + 62 * step, numerator: 3, denominatorPower: 2)
    let tempo = coreTimeTempo(base + 63 * step, 150)
    document.editTempo(TempoEdit(add: [tempo]))
    let originalTempo = document.state.tempo
    let before = coreTimeBytes(document)
    let endBefore = document.rawChunks.map(\.endTick).max() ?? 0
    let loopBefore = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    let position = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    report.expect(document.removeTime(TimeRange(startTick: base + 61 * step,
                                                endTick: base + 65 * step),
                                      scope: TimeScope(wholeSong: true)),
                  cppID: id, message: "whole-song removal commits")
    report.expect(coreTimeTracksSorted(document), cppID: id,
                  message: "all chunk events stay tick-sorted after the removal")
    report.expect(document.timeSignatures.contains {
        $0.tick == base + 61 * step && $0.numerator == 3 && $0.denominatorPower == 2
    }, cppID: id, message: "3/2 signature is rescued to the closing seam")
    report.expect(document.state.tempo.contains {
        $0.tick == base + 61 * step && $0.microsecondsPerQuarterNote == 400_000
    }, cppID: id, message: "150 BPM tempo is rescued to the closing seam")
    report.expect(document.notes(in: track).contains {
        $0.id == shiftedID && $0.tick == base + 62 * step && $0.pitch == 65
    }, cppID: id, message: "later note shifts by the removed span")
    let loopAfter = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(loopBefore.loopStartTick, loopAfter.loopStartTick,
                       cppID: id, what: "loop start stays put across removal")
    report.expectEqual(loopBefore.loopEndTick, loopAfter.loopEndTick,
                       cppID: id, what: "loop end stays put across removal")
    report.expectEqual(endBefore - 4 * step, document.rawChunks.map(\.endTick).max() ?? 0,
                       cppID: id, what: "song end closes by exactly four clocks")
    report.expectEqual(position + 1,
                       try coreEditHistoryCountAtTip(document, report: report,
                                                     cppID: id),
                       cppID: id, what: "whole-song removal adds one history entry")
    let after = coreTimeBytes(document)
    _ = document.history.undoDocument()
    report.expectEqual(before, coreTimeBytes(document), cppID: id,
                       what: "one undo restores the whole-song removal")
    report.expectEqual(originalTempo, document.state.tempo, cppID: id,
                       what: "undo restores the tempo points")
    report.expect(document.notes(in: track).contains {
        $0.id == shiftedID && $0.tick == base + 66 * step && $0.pitch == 65
    }, cppID: id, message: "undo restores the shifted note")
    let loopUndone = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(loopBefore.loopStartTick, loopUndone.loopStartTick,
                       cppID: id, what: "loop start stays put across undo")
    report.expectEqual(loopBefore.loopEndTick, loopUndone.loopEndTick,
                       cppID: id, what: "loop end stays put across undo")
    report.expectEqual(endBefore, document.rawChunks.map(\.endTick).max() ?? 0,
                       cppID: id, what: "undo restores the song end")
    _ = document.history.redoDocument()
    report.expectEqual(after, coreTimeBytes(document), cppID: id,
                       what: "one redo restores the whole-song removal")
    report.expect(document.notes(in: track).contains {
        $0.id == shiftedID && $0.tick == base + 62 * step && $0.pitch == 65
    }, cppID: id, message: "redo restores the shifted note")
    let loopRedone = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(loopBefore.loopStartTick, loopRedone.loopStartTick,
                       cppID: id, what: "loop start stays put across redo")
    report.expectEqual(loopBefore.loopEndTick, loopRedone.loopEndTick,
                       cppID: id, what: "loop end stays put across redo")
    report.expect(coreTimeTracksSorted(document), cppID: id,
                  message: "all chunk events stay tick-sorted")
}

@MainActor
private func coreTimeAutomationRow(_ report: CheckReport, _ document: SongDocument,
                                   _ track: Int, _ base: Tick, _ step: Tick,
                                   _ id: String) throws {
    let originalBytes = coreTimeBytes(document)
    let originalTempos = document.state.tempo
    let originalDepth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    document.writeLane(track: track, lane: .controller(7), from: base,
                       through: base + step,
                       points: [LaneWrite(tick: base, value: 30),
                                LaneWrite(tick: base + step, value: 44)])
    document.writeLane(track: track, lane: .pitchBend, from: base,
                       through: base, points: [LaneWrite(tick: base, value: 500)])
    let before = coreTimeBytes(document)
    let position = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    report.expect(document.insertBlankTime(TimeRange(startTick: base + step,
                                                     endTick: base + 2 * step),
                                           scope: TimeScope(tracks: [track])),
                  cppID: id, message: "insertion shifts lane points")
    report.expectEqual("\(base):30", document.lanePoints(track: track,
                                                         lane: .controller(7))
        .first(where: { $0.tick == base }).map(coreTimePointShape),
        cppID: id, what: "pre-range lane point keeps its tick")
    report.expectEqual("\(base + 2 * step):44", document.lanePoints(track: track,
                                                                    lane: .controller(7))
        .first(where: { $0.tick == base + 2 * step }).map(coreTimePointShape),
        cppID: id, what: "post-range lane point shifts right")
    report.expectEqual(position + 1,
                       try coreEditHistoryCountAtTip(document, report: report,
                                                     cppID: id),
                       cppID: id, what: "insertion adds one history entry")
    let after = coreTimeBytes(document)
    _ = document.history.undoDocument()
    report.expectEqual(before, coreTimeBytes(document), cppID: id,
                       what: "one undo restores the lane insertion")
    _ = document.history.redoDocument()
    report.expectEqual(after, coreTimeBytes(document), cppID: id,
                       what: "one redo restores the lane insertion")
    document.writeLane(track: track, lane: .controller(7), from: base + 2 * step,
                       through: base + 2 * step,
                       points: [LaneWrite(tick: base + 2 * step, value: 100)])
    document.writeLane(track: track, lane: .pitchBend, from: base + 3 * step,
                       through: base + 3 * step,
                       points: [LaneWrite(tick: base + 3 * step, value: -1024)])
    let tempo = coreTimeTempo(base + 4 * step, 150)
    document.editTempo(TempoEdit(add: [tempo]))
    guard let cc = document.lanePoints(track: track, lane: .controller(7))
        .first(where: { $0.tick == base + 2 * step && $0.value == 100 }),
        document.lanePoints(track: track, lane: .pitchBend)
            .contains(where: { $0.tick == base + 3 * step && $0.value == -1024 }) else {
        report.fail(id, "CC7=100 and pitch bend=-1024 must be readable before moving")
        return
    }
    report.expect(document.state.tempo.contains(tempo), cppID: id,
                  message: "150 BPM tempo is inserted at clock four")
    document.moveLanePoints(track: track, lane: .controller(7),
                            moves: [LanePointMove(point: cc, tick: base + 5 * step, value: 90)])
    report.expectEqual("\(base + 5 * step):90",
                       document.lanePoints(track: track, lane: .controller(7))
                           .first(where: { $0.tick == base + 5 * step }).map(coreTimePointShape),
                       cppID: id, what: "CC7 moves to clock five with value 90")
    report.expect(document.lanePoints(track: track, lane: .pitchBend).contains {
        $0.tick == base + 3 * step && $0.value == -1024
    }, cppID: id, message: "moving CC7 preserves the pitch bend")
    guard let bend = document.lanePoints(track: track, lane: .pitchBend)
        .first(where: { $0.tick == base + 3 * step && $0.value == -1024 }) else {
        report.fail(id, "moving CC7 must leave the bend available for deletion")
        return
    }
    document.deleteLanePoints(track: track, lane: .pitchBend, points: [bend])
    report.expect(!document.lanePoints(track: track, lane: .pitchBend).contains {
        $0.tick == base + 3 * step
    }, cppID: id, message: "deleting the pitch bend removes it")
    document.editTempo(TempoEdit(remove: [tempo]))
    report.expect(!document.state.tempo.contains(tempo), cppID: id,
                  message: "deleting the tempo removes it")
    guard let movedCC = document.lanePoints(track: track, lane: .controller(7))
        .first(where: { $0.tick == base + 5 * step && $0.value == 90 }) else {
        report.fail(id, "deleting the tempo must preserve the moved CC7")
        return
    }
    document.deleteLanePoints(track: track, lane: .controller(7), points: [movedCC])
    report.expect(!document.lanePoints(track: track, lane: .controller(7)).contains {
        $0.tick == base + 5 * step
    }, cppID: id, message: "deleting CC7 removes its moved point")
    let editedBytes = coreTimeBytes(document)
    let editedTempos = document.state.tempo
    let editedDepth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    let applied = editedDepth - originalDepth
    guard applied > 0 else {
        report.fail(id, "the lifecycle must add history entries without unwinding prior history")
        return
    }
    for _ in 0..<applied {
        report.expect(document.history.undoDocument(), cppID: id,
                      message: "each applied edit can be undone")
    }
    report.expectEqual(originalBytes, coreTimeBytes(document), cppID: id,
                       what: "counted undo restores the original song bytes")
    report.expectEqual(originalTempos, document.state.tempo, cppID: id,
                       what: "counted undo restores the original tempos")
    for _ in 0..<applied {
        report.expect(document.history.redoDocument(), cppID: id,
                      message: "each applied edit can be redone")
    }
    report.expectEqual(editedBytes, coreTimeBytes(document), cppID: id,
                       what: "counted redo restores the edited song bytes")
    report.expectEqual(editedTempos, document.state.tempo, cppID: id,
                       what: "counted redo restores the edited tempos")
}

@MainActor
private func coreTimeVoiceRow(_ report: CheckReport, _ document: SongDocument,
                              _ track: Int, _ base: Tick, _ step: Tick,
                              _ id: String) throws {
    document.writeLane(track: track, lane: .voice, from: base, through: base,
                       points: [LaneWrite(tick: base, value: 5)])
    document.writeLane(track: track, lane: .voice, from: base + step,
                       through: base + step,
                       points: [LaneWrite(tick: base + step, value: 9)])
    document.writeLane(track: track, lane: .voice, from: base + 3 * step,
                       through: base + 3 * step,
                       points: [LaneWrite(tick: base + 3 * step, value: 12)])
    let before = coreTimeBytes(document)
    let position = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    report.expect(document.removeTime(TimeRange(startTick: base + step,
                                                endTick: base + 2 * step),
                                      scope: TimeScope(tracks: [track])),
                  cppID: id, message: "removal shifts voice points")
    report.expectEqual("\(base):5", document.lanePoints(track: track, lane: .voice)
        .first(where: { $0.tick == base }).map(coreTimePointShape),
        cppID: id, what: "pre-range voice point keeps its tick")
    report.expectEqual("\(base + 2 * step):12",
                       document.lanePoints(track: track, lane: .voice)
                           .first(where: { $0.tick == base + 2 * step })
                           .map(coreTimePointShape),
                       cppID: id, what: "post-range voice point ripples left one clock")
    report.expectEqual(position + 1,
                       try coreEditHistoryCountAtTip(document, report: report,
                                                     cppID: id),
                       cppID: id, what: "removal adds one history entry")
    let after = coreTimeBytes(document)
    _ = document.history.undoDocument()
    report.expectEqual(before, coreTimeBytes(document), cppID: id,
                       what: "one undo restores the voice removal")
    _ = document.history.redoDocument()
    report.expectEqual(after, coreTimeBytes(document), cppID: id,
                       what: "one redo restores the voice removal")
    document.writeLane(track: track, lane: .voice, from: base + step,
                       through: base + step,
                       points: [LaneWrite(tick: base + step, value: 5)])
    guard let voice = document.lanePoints(track: track, lane: .voice)
        .first(where: { $0.tick == base + step && $0.value == 5 }) else {
        report.fail(id, "voice program 5 must be readable at clock one")
        return
    }
    document.moveLanePoints(track: track, lane: .voice,
                            moves: [LanePointMove(point: voice, tick: base + step, value: 9)])
    guard let updated = document.lanePoints(track: track, lane: .voice)
        .first(where: { $0.tick == base + step && $0.value == 9 }) else {
        report.fail(id, "in-place move must set voice program 9")
        return
    }
    document.moveLanePoints(track: track, lane: .voice,
                            moves: [LanePointMove(point: updated, tick: base + 6 * step, value: 9)])
    guard let relocated = document.lanePoints(track: track, lane: .voice)
        .first(where: { $0.tick == base + 6 * step && $0.value == 9 }) else {
        report.fail(id, "voice program 9 must relocate to clock six")
        return
    }
    document.deleteLanePoints(track: track, lane: .voice, points: [relocated])
    report.expect(!document.lanePoints(track: track, lane: .voice).contains {
        $0.tick == base + 6 * step
    }, cppID: id, message: "deleting the relocated voice removes it")
}
