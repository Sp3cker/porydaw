import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func runTimeEditsSuite(_ report: CheckReport) {
    rangeEditing(report)
    coreRangeCorpusChecks(report)
    coreTimeCorpusChecks(report)
    rangeMovement(report)
    removalAndSeams(report)
    insertionAndBoundaries(report)
    duplicationAndGlobals(report)
    coreTimeXcmdTimeTraffic(report)
    coreTimeXcmdRangeEdits(report)
    runClipboardEditingSuite(report)
    runClipboardCodecSuite(report)
}

@MainActor
private func rangeEditing(_ report: CheckReport) {
    let document = timeDocument(trackBudget: 3)
    guard let originalIDs = try? document.addNotes([
        NewNote(track: 0, tick: 30, pitch: 60, duration: 8, velocity: 90),
        NewNote(track: 0, tick: 42, pitch: 62, duration: 8, velocity: 91),
    ]) else {
        report.fail("editcheck/EditCheckTest::rangeEdit", "fixture note insertion failed")
        return
    }
    document.writeLane(track: 0, lane: .controller(7), from: 30, through: 30,
                       points: [LaneWrite(tick: 30, value: 80)])
    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 31, microsecondsPerQuarterNote: 600_000),
    ]))
    let before = coreTimeBytes(document)
    let edit = RangeEdit(
        minimumEngineTrackCount: 3,
        removeNotes: originalIDs.compactMap { document.note($0) },
        removePoints: document.lanePoints(track: 0, lane: .controller(7)),
        addNotes: [NewNote(track: 2, tick: 60, pitch: 65, duration: 8, velocity: 99)],
        addPoints: [RangeEdit.LaneInsertion(
            track: 2, lane: .controller(7),
            points: [LaneWrite(tick: 60, value: 60), LaneWrite(tick: 60, value: 70)])],
        removeTempo: [TempoPoint(tick: 31, microsecondsPerQuarterNote: 600_000)],
        addTempo: [TempoPoint(tick: 61, microsecondsPerQuarterNote: 400_000)])
    report.expect(document.applyRangeEdit(edit),
                  cppID: "editcheck/EditCheckTest::rangeEdit",
                  message: "mixed cross-stream range edit commits")
    report.expectEqual(expected: 3, actual: document.engineTracks.usedTrackCount,
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "range insertion expands tracks under budget")
    report.expectEqual(expected: ["60:65:8"], actual: document.notes(in: 2).map(noteShape),
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "inserted note lands on expanded track")
    report.expectEqual(expected: ["60:60", "60:70"], actual: document.lanePoints(track: 2, lane: .controller(7)).map(coreTimePointShape),
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "lane insertion shares the atomic candidate")
    report.expectEqual(expected: 2, actual: document.lanePoints(track: 2, lane: .controller(7)).count,
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "range insertion preserves separate same-tick occurrences")
    report.expect(document.state.tempo.contains {
        $0.tick == 61 && $0.microsecondsPerQuarterNote == 400_000
    }, cppID: "editcheck/EditCheckTest::rangeEdit", message: "tempo replacement is atomic")
    _ = document.history.undoDocument()
    report.expectEqual(expected: before, actual: coreTimeBytes(document),
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "one undo restores every stream and track count")

    let collision = timeDocument(trackBudget: 2)
    let collisionBefore = coreTimeBytes(collision)
    let rejected = RangeEdit(minimumEngineTrackCount: 2, addNotes: [
        NewNote(track: 1, tick: 10, pitch: 60, duration: 20, velocity: 80),
        NewNote(track: 1, tick: 20, pitch: 60, duration: 20, velocity: 90),
    ], addPoints: [RangeEdit.LaneInsertion(
        track: 1, lane: .controller(7), points: [LaneWrite(tick: 10, value: 90)])])
    report.expect(!collision.applyRangeEdit(rejected) && coreTimeBytes(collision) == collisionBefore,
                  cppID: "editcheck/EditCheckTest::rangeEditCollisionRejects",
                  message: "conflicting participants reject before track expansion")

    let limited = timeDocument(trackBudget: 1)
    let limitedBefore = coreTimeBytes(limited)
    report.expect(!limited.applyRangeEdit(RangeEdit(
        minimumEngineTrackCount: 2,
        addNotes: [NewNote(track: 1, tick: 1, pitch: 60, duration: 1, velocity: 90)])) &&
        coreTimeBytes(limited) == limitedBefore,
        cppID: "editcheck/EditCheckTest::rangeEditCollisionRejects",
        message: "budget-constrained expansion leaves the prior state intact")

    let progressive = timeDocument()
    _ = try? progressive.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 100, velocity: 91),
    ])
    let original = coreTimeBytes(progressive)
    let multiSpan = RangeEdit(addNotes: [
        NewNote(track: 0, tick: 10, pitch: 60, duration: 10, velocity: 80),
        NewNote(track: 0, tick: 30, pitch: 60, duration: 10, velocity: 81),
    ])
    let accepted = progressive.applyRangeEdit(multiSpan)
    let forward = progressive.notes(in: 0).map(noteShape)
    _ = progressive.history.undoDocument()
    let undoRestored = coreTimeBytes(progressive) == original
    _ = progressive.history.redoDocument()
    report.expect(accepted && forward == ["0:60:10", "10:60:10", "30:60:10"] &&
        undoRestored && progressive.notes(in: 0).map(noteShape) == forward,
        cppID: "editcheck/EditCheckTest::rangeEdit",
        message: "successive inserted spans resolve against the progressively shortened stationary note")
}

@MainActor
private func rangeMovement(_ report: CheckReport) {
    let document = timeDocument()
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 80, pitch: 60, duration: 8, velocity: 90),
        NewNote(track: 0, tick: 92, pitch: 64, duration: 8, velocity: 91),
    ]) else { return }
    document.writeLane(track: 0, lane: .controller(7), from: 80, through: 80,
                       points: [LaneWrite(tick: 80, value: 45)])
    document.editTempo(TempoEdit(add: [TempoPoint(tick: 81, microsecondsPerQuarterNote: 600_000)]))
    let notes = ids.compactMap { document.note($0) }
    let lane = document.lanePoints(track: 0, lane: .controller(7))
    let tempo = document.state.tempo.filter { $0.tick == 81 }
    let before = coreTimeBytes(document)
    report.expect(document.moveRange(notes: notes, points: lane, by: 12, tempo: tempo),
                  cppID: "editcheck/EditCheckTest::rangeMove",
                  message: "mixed range move commits")
    report.expectEqual(expected: ["92:60:8", "104:64:8"], actual: document.notes(in: 0).map(noteShape),
                       cppID: "editcheck/EditCheckTest::rangeMove",
                       what: "notes retain duration after exact-byte relocation")
    report.expectEqual(expected: ["92:45"], actual: document.lanePoints(track: 0, lane: .controller(7)).map(coreTimePointShape),
                       cppID: "editcheck/EditCheckTest::rangeLaneBulk",
                       what: "lane event relocates with the range")
    report.expect(document.state.tempo.contains { $0.tick == 93 },
                  cppID: "editcheck/EditCheckTest::rangeLaneConverge",
                  message: "tempo point relocates in the same history entry")
    _ = document.history.undoDocument()
    report.expectEqual(expected: before, actual: coreTimeBytes(document),
                       cppID: "editcheck/EditCheckTest::rangeMove",
                       what: "one undo restores the mixed move")

    let opaque = timeDocument()
    opaque.insertRawEvent(chunk: 0,
        event: .systemExclusive(tick: 12, status: 0xF0, data: [0x7D, 4, 5, 0xF7]))
    guard let index = opaque.rawChunks[0].events.firstIndex(where: { $0.isSystemExclusive }) else { return }
    let point = LanePoint(chunk: 0, eventIndex: index, tick: 12, value: 0)
    _ = opaque.moveRange(notes: [], points: [point], by: 5)
    report.expect(opaque.rawChunks[0].events.contains {
        $0.tick == 17 && $0.blob == [0x7D, 4, 5, 0xF7]
    }, cppID: "editcheck/EditCheckTest::rangeMove",
    message: "opaque relocation preserves exact payload bytes")

    let headTrim = timeDocument()
    guard let headIDs = try? headTrim.addNotes([
        NewNote(track: 0, tick: 50, pitch: 60, duration: 20, velocity: 80),
        NewNote(track: 0, tick: 110, pitch: 60, duration: 30, velocity: 90),
    ]), let headMover = headTrim.note(headIDs[0]) else {
        report.fail("editcheck/EditCheckTest::rangeMove", "head-trim fixture insertion failed")
        return
    }
    report.expect(headTrim.moveRange(notes: [headMover], points: [], by: 50),
                  cppID: "editcheck/EditCheckTest::rangeMove",
                  message: "moving range trims a stationary note head")
    report.expectEqual(expected: ["100:60:20", "120:60:20"], actual: headTrim.notes(in: 0).map(noteShape),
                       cppID: "editcheck/EditCheckTest::rangeMove",
                       what: "stationary note starts at the moved note end")

    let fullCover = timeDocument()
    guard let coverIDs = try? fullCover.addNotes([
        NewNote(track: 0, tick: 50, pitch: 61, duration: 50, velocity: 80),
        NewNote(track: 0, tick: 110, pitch: 61, duration: 20, velocity: 90),
    ]), let coverMover = fullCover.note(coverIDs[0]) else {
        report.fail("editcheck/EditCheckTest::rangeMove", "full-cover fixture insertion failed")
        return
    }
    report.expect(fullCover.moveRange(notes: [coverMover], points: [], by: 50),
                  cppID: "editcheck/EditCheckTest::rangeMove",
                  message: "moving range fully covers a stationary note")
    report.expectEqual(expected: ["100:61:50"], actual: fullCover.notes(in: 0).map(noteShape),
                       cppID: "editcheck/EditCheckTest::rangeMove",
                       what: "fully covered stationary note is removed")
}

@MainActor
private func removalAndSeams(_ report: CheckReport) {
    let document = timeDocument()
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 100, velocity: 81),
        NewNote(track: 0, tick: 110, pitch: 60, duration: 10, velocity: 92),
        NewNote(track: 1, tick: 110, pitch: 62, duration: 10, velocity: 73),
    ]) else { return }
    document.writeLane(track: 0, lane: .controller(7), from: 25, through: 50,
                       points: [LaneWrite(tick: 25, value: 30), LaneWrite(tick: 40, value: 44)])
    let untouched = document.note(ids[2])
    let before = coreTimeBytes(document)
    report.expect(document.removeTime(TimeRange(startTick: 20, endTick: 50),
                                      scope: TimeScope(tracks: [0])),
                  cppID: "editcheck/EditCheckTest::timeRangeRemoveRippleTrim",
                  message: "scoped gap removal commits")
    report.expectEqual(expected: ["0:60:80", "80:60:10"], actual: document.notes(in: 0).map(noteShape),
                       cppID: "editcheck/EditCheckTest::timeRangeRemove",
                       what: "crossing note trims and later note ripples")
    report.expectEqual(expected: "20:44", actual: document.lanePoints(track: 0, lane: .controller(7)).first.map(coreTimePointShape),
                       cppID: "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults",
                       what: "last in-range value survives at the seam")
    report.expectEqual(expected: untouched?.tick, actual: document.note(ids[2])?.tick,
                       cppID: "editcheck/EditCheckTest::timeRangeRemoveRippleTrim",
                       what: "unscoped track is unchanged")
    _ = document.history.undoDocument()
    report.expectEqual(expected: before, actual: coreTimeBytes(document),
                       cppID: "editcheck/EditCheckTest::timeRangeRemove",
                       what: "single undo restores scoped removal")

    let whole = timeDocument()
    _ = try? whole.addNotes([NewNote(track: 0, tick: 66, pitch: 65, duration: 4, velocity: 90)])
    whole.setTimeSignature(tick: 62, numerator: 3, denominatorPower: 2)
    whole.editTempo(TempoEdit(add: [TempoPoint(tick: 63, microsecondsPerQuarterNote: 333_333)]))
    whole.insertRawEvent(chunk: 0, event: .meta(tick: 64, type: 0x06, data: [0x5B]))
    let oldEnd = whole.rawChunks.map(\.endTick)
    let wholeBefore = coreTimeBytes(whole)
    report.expect(whole.removeTime(TimeRange(startTick: 61, endTick: 65),
                                  scope: TimeScope(wholeSong: true)),
                  cppID: "editcheck/EditCheckTest::songWholeSongRemove",
                  message: "whole-song close commits")
    report.expect(whole.timeSignatures.contains { $0.tick == 61 && $0.numerator == 3 } &&
        whole.state.tempo.contains { $0.tick == 61 } &&
        whole.rawChunks[0].events.contains { $0.metaType == 0x06 && $0.tick == 61 },
        cppID: "editcheck/EditCheckTest::timeRangeWholeSong",
        message: "globals are rescued to the closing seam")
    let closedEnds = zip(oldEnd, whole.rawChunks.map(\.endTick)).allSatisfy { pair in
        let (before, after) = pair
        let expected = before >= 65 ? before - 4 : (before > 61 ? 61 : before)
        return after == expected
    }
    report.expect(closedEnds,
        cppID: "editcheck/EditCheckTest::songWholeSongRemove",
        message: "whole-song removal closes every stored end tick")
    _ = whole.history.undoDocument()
    report.expectEqual(expected: oldEnd, actual: whole.rawChunks.map(\.endTick),
                       cppID: "editcheck/EditCheckTest::songWholeSongRemove",
                       what: "one undo restores every stored end tick")
    report.expectEqual(expected: wholeBefore, actual: coreTimeBytes(whole),
                       cppID: "editcheck/EditCheckTest::timeRangeWholeSong",
                       what: "one undo restores globals, events, and end-of-track state")

    // timeRangeRemoveRippleTrim: full earlierEnd loop over the faithful
    // three-chunk timeRangeFile fixture (conductor plus two engine tracks).
    for earlierEnd: Tick in [100, 80, 70] {
        let id = "editcheck/EditCheckTest::timeRangeRemoveRippleTrim[end=\(earlierEnd)]"
        do {
            let trim = try timeRangeDocument()
            report.expectEqual(expected: 2, actual: trim.engineTracks.usedTrackCount, cppID: id,
                               what: "timeRangeFile fixture loads two editable tracks")
            _ = try trim.addNotes([
                NewNote(track: 0, tick: 0, pitch: 60, duration: earlierEnd, velocity: 81),
                NewNote(track: 0, tick: 110, pitch: 60, duration: 10, velocity: 92),
            ])
            _ = try trim.addNotes([
                NewNote(track: 1, tick: 0, pitch: 60, duration: 100, velocity: 73),
                NewNote(track: 1, tick: 110, pitch: 60, duration: 10, velocity: 74),
            ])
            report.expect(coreRangeNotePairsConsistent(trim, track: 0), cppID: id,
                          message: "track 0 on/off pairs consistent before removal")
            report.expect(coreRangeNotePairsConsistent(trim, track: 1), cppID: id,
                          message: "track 1 on/off pairs consistent before removal")
            let original = trim.notes(in: 0)
            let otherChunk = trim.engineTracks.tracks[1].midiChunk
            let other = otherChunk.map { trim.rawChunks[$0].events }
            let trimBefore = coreTimeBytes(trim)
            let trimPosition = try coreEditHistoryCountAtTip(trim, report: report, cppID: id)
            report.expect(trim.removeTime(TimeRange(startTick: 20, endTick: 50),
                                          scope: TimeScope(tracks: [0])),
                          cppID: id, message: "scoped gap removal commits")
            report.expect(coreRangeNotePairsConsistent(trim, track: 0), cppID: id,
                          message: "track 0 on/off pairs consistent after removal")
            report.expect(coreRangeNotePairsConsistent(trim, track: 1), cppID: id,
                          message: "track 1 on/off pairs consistent after removal")
            let notes = trim.notes(in: 0)
            report.expectEqual(expected: 2, actual: notes.count, cppID: id,
                               what: "two notes remain after the scoped removal")
            report.expectEqual(expected: Tick(0), actual: notes.first?.tick, cppID: id,
                               what: "crossing note keeps its start tick")
            report.expectEqual(expected: min(earlierEnd, Tick(80)), actual: notes.first?.duration, cppID: id,
                               what: "crossing note trims to the rippled neighbor")
            report.expectEqual(expected: Tick(80), actual: notes.last?.tick, cppID: id,
                               what: "later note ripples left by the span")
            report.expectEqual(expected: Tick(10), actual: notes.last?.duration, cppID: id,
                               what: "later note keeps its duration")
            for (note, source) in zip(notes, original) {
                report.expectEqual(expected: source.id, actual: note.id, cppID: id,
                                   what: "removal preserves note identity")
                report.expectEqual(expected: source.velocity, actual: note.velocity, cppID: id,
                                   what: "removal preserves note velocity")
            }
            if let otherChunk, let other {
                report.expectEqual(expected: other, actual: trim.rawChunks[otherChunk].events, cppID: id,
                                   what: "unscoped track events are byte-identical")
            } else {
                report.fail(id, "unscoped engine track has no MIDI chunk")
            }
            report.expectEqual(expected: trimPosition + 1,
                               actual: try coreEditHistoryCountAtTip(trim, report: report, cppID: id),
                               cppID: id, what: "removal adds one history entry")
            let trimAfter = coreTimeBytes(trim)
            _ = trim.history.undoDocument()
            report.expectEqual(expected: trimBefore, actual: coreTimeBytes(trim), cppID: id,
                               what: "one undo restores the removal")
            _ = trim.history.redoDocument()
            report.expectEqual(expected: trimAfter, actual: coreTimeBytes(trim), cppID: id,
                               what: "one redo restores the removal")
            report.expect(coreRangeNotePairsConsistent(trim, track: 0), cppID: id,
                          message: "track 0 on/off pairs consistent after redo")
            report.expect(coreRangeNotePairsConsistent(trim, track: 1), cppID: id,
                          message: "track 1 on/off pairs consistent after redo")
        } catch {
            report.fail(id, "removal fixture failed: \(error)")
        }
    }
    for duplicate in [false, true] {
        let id = "editcheck/EditCheckTest::timeRangeRemoveRippleTrim[\(duplicate ? "duplicate" : "insert")]"
        do {
            let branch = try timeRangeDocument()
            report.expectEqual(expected: 2, actual: branch.engineTracks.usedTrackCount, cppID: id,
                               what: "timeRangeFile fixture loads two editable tracks")
            _ = try branch.addNotes([
                NewNote(track: 0, tick: 0, pitch: 60, duration: 30, velocity: 81),
                NewNote(track: 0, tick: 30, pitch: 60, duration: 20, velocity: 92),
            ])
            report.expect(coreRangeNotePairsConsistent(branch, track: 0), cppID: id,
                          message: "on/off pairs consistent before the edit")
            let branchBefore = coreTimeBytes(branch)
            if duplicate {
                report.expect(branch.duplicateTime(TimeRange(startTick: 10, endTick: 40),
                                                   scope: TimeScope(tracks: [0])),
                              cppID: id, message: "duplicate branch commits")
            } else {
                report.expect(branch.insertBlankTime(TimeRange(startTick: 10, endTick: 40),
                                                     scope: TimeScope(tracks: [0])),
                              cppID: id, message: "insert branch commits")
            }
            report.expect(coreRangeNotePairsConsistent(branch, track: 0), cppID: id,
                          message: "on/off pairs consistent after the edit")
            let branchAfter = coreTimeBytes(branch)
            _ = branch.history.undoDocument()
            report.expectEqual(expected: branchBefore, actual: coreTimeBytes(branch), cppID: id,
                               what: "one undo restores the branch")
            _ = branch.history.redoDocument()
            report.expectEqual(expected: branchAfter, actual: coreTimeBytes(branch), cppID: id,
                               what: "one redo restores the branch")
            report.expect(coreRangeNotePairsConsistent(branch, track: 0), cppID: id,
                          message: "on/off pairs consistent after redo")
        } catch {
            report.fail(id, "duplicate/insert fixture failed: \(error)")
        }
    }
}

@MainActor
private func insertionAndBoundaries(_ report: CheckReport) {
    do {
        let document = try timeRangeDocument()
        let splitID = "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit"
        report.expectEqual(expected: 2, actual: document.engineTracks.usedTrackCount, cppID: splitID,
                           what: "timeRangeFile fixture loads two editable tracks")
        _ = try document.addNotes([
            NewNote(track: 0, tick: 35, pitch: 60, duration: 10, velocity: 90),
            NewNote(track: 0, tick: 60, pitch: 61, duration: 5, velocity: 80),
        ])
        report.expect(document.notes(in: 0).contains { $0.tick == 60 && $0.pitch == 61 },
                      cppID: splitID, message: "pre-insertion note (0,60,61) exists")
        guard let crossing = document.notes(in: 0).first(where: {
            $0.tick == 35 && $0.pitch == 60
        }), let later = document.notes(in: 0).first(where: {
            $0.tick == 60 && $0.pitch == 61
        }) else {
            report.fail(splitID, "pre-insertion notes (0,35,60) and (0,60,61) missing")
            return
        }
        let crossingID = crossing.id
        let laterID = later.id
        let before = coreTimeBytes(document)
        let splitPosition = try coreEditHistoryCountAtTip(document, report: report,
                                                        cppID: splitID)
        report.expect(document.insertBlankTime(TimeRange(startTick: 40, endTick: 45),
                                               scope: TimeScope(tracks: [0])),
                      cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                      message: "blank insertion commits")
        let split = document.notes(in: 0).filter { $0.pitch == 60 }
        report.expectEqual(expected: ["35:60:5", "45:60:5"], actual: split.map(noteShape),
                           cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                           what: "crossing note splits around a silent interval")
        report.expect(split.count == 2 && split[0].id == crossingID && split[1].id != crossingID,
                      cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                      message: "split right half receives a new identity")
        report.expectEqual(expected: Tick(65), actual: document.note(laterID)?.tick,
                           cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                           what: "later note shifts and preserves identity")
        report.expectEqual(expected: splitPosition + 1,
                           actual: try coreEditHistoryCountAtTip(document, report: report,
                                                         cppID: splitID),
                           cppID: splitID, what: "insertion adds one history entry")
        let splitAfter = coreTimeBytes(document)
        _ = document.history.undoDocument()
        report.expectEqual(expected: before, actual: coreTimeBytes(document),
                           cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                           what: "one undo restores the split")
        _ = document.history.redoDocument()
        report.expectEqual(expected: splitAfter, actual: coreTimeBytes(document),
                           cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                           what: "one redo restores the split")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                    "split fixture failed: \(error)")
    }

    // timeRangeInsertScopeAndSplit lane-scoped block: faithful port.
    do {
        let lane = try timeRangeDocument()
        let laneID = "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit"
        report.expectEqual(expected: 2, actual: lane.engineTracks.usedTrackCount, cppID: laneID,
                           what: "timeRangeFile fixture loads two editable tracks")
        lane.writeLane(track: 0, lane: .controller(7), from: 300, through: 300,
                       points: [LaneWrite(tick: 300, value: 10)])
        lane.writeLane(track: 0, lane: .controller(10), from: 300, through: 300,
                       points: [LaneWrite(tick: 300, value: 20)])
        lane.writeLane(track: 1, lane: .controller(7), from: 300, through: 300,
                       points: [LaneWrite(tick: 300, value: 30)])
        guard let selectedChunk = lane.engineTracks.tracks[0].midiChunk,
              let untouchedChunk = lane.engineTracks.tracks[1].midiChunk else {
            report.fail(laneID, "engine tracks lack MIDI chunks")
            return
        }
        let selectedEnd = lane.rawChunks[selectedChunk].endTick
        let untouchedEnd = lane.rawChunks[untouchedChunk].endTick
        let laneBefore = coreTimeBytes(lane)
        report.expect(lane.insertBlankTime(TimeRange(startTick: 300, endTick: 320),
                                           scope: TimeScope(lanes: [
                                               TimeScope.ScopedLane(track: 0,
                                                                    lane: .controller(7)),
                                           ])),
                      cppID: laneID, message: "lane-scoped insertion commits")
        report.expectEqual(expected: "320:10", actual: lane.lanePoints(track: 0, lane: .controller(7))
            .first(where: { $0.tick == 320 }).map(coreTimePointShape),
            cppID: laneID, what: "scoped lane point shifts right")
        report.expectEqual(expected: "300:20", actual: lane.lanePoints(track: 0, lane: .controller(10))
            .first(where: { $0.tick == 300 }).map(coreTimePointShape),
            cppID: laneID, what: "unscoped lane on the same track stays")
        report.expectEqual(expected: "300:30", actual: lane.lanePoints(track: 1, lane: .controller(7))
            .first(where: { $0.tick == 300 }).map(coreTimePointShape),
            cppID: laneID, what: "same lane on another track stays")
        report.expectEqual(expected: selectedEnd + 20, actual: lane.rawChunks[selectedChunk].endTick,
                           cppID: laneID, what: "selected chunk end tick grows")
        report.expectEqual(expected: untouchedEnd, actual: lane.rawChunks[untouchedChunk].endTick,
                           cppID: laneID, what: "untouched chunk end tick stays")
        let laneAfter = coreTimeBytes(lane)
        _ = lane.history.undoDocument()
        report.expectEqual(expected: laneBefore, actual: coreTimeBytes(lane), cppID: laneID,
                           what: "one undo restores the lane insertion")
        _ = lane.history.redoDocument()
        report.expectEqual(expected: laneAfter, actual: coreTimeBytes(lane), cppID: laneID,
                           what: "one redo restores the lane insertion")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                    "lane fixture failed: \(error)")
    }

    // timeRangeInsertScopeAndSplit track-scoped block: faithful port.
    do {
        let track = try timeRangeDocument()
        let trackID = "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit"
        report.expectEqual(expected: 2, actual: track.engineTracks.usedTrackCount, cppID: trackID,
                           what: "timeRangeFile fixture loads two editable tracks")
        _ = try track.addNotes([
            NewNote(track: 0, tick: 400, pitch: 62, duration: 5, velocity: 90),
            NewNote(track: 1, tick: 400, pitch: 63, duration: 5, velocity: 90),
        ])
        track.writeLane(track: 0, lane: .controller(7), from: 400, through: 400,
                        points: [LaneWrite(tick: 400, value: 40)])
        track.writeLane(track: 1, lane: .controller(7), from: 400, through: 400,
                        points: [LaneWrite(tick: 400, value: 50)])
        guard let trackChunk = track.engineTracks.tracks[0].midiChunk,
              let otherChunk = track.engineTracks.tracks[1].midiChunk else {
            report.fail(trackID, "engine tracks lack MIDI chunks")
            return
        }
        let trackEnd = track.rawChunks[trackChunk].endTick
        let otherEnd = track.rawChunks[otherChunk].endTick
        let trackBefore = coreTimeBytes(track)
        report.expect(track.insertBlankTime(TimeRange(startTick: 400, endTick: 420),
                                            scope: TimeScope(tracks: [0])),
                      cppID: trackID, message: "track-scoped insertion commits")
        report.expect(track.notes(in: 0).contains { $0.tick == 420 && $0.pitch == 62 },
                      cppID: trackID, message: "scoped track note shifts right")
        report.expect(track.notes(in: 1).contains { $0.tick == 400 && $0.pitch == 63 },
                      cppID: trackID, message: "unscoped track note stays")
        report.expectEqual(expected: trackEnd + 20, actual: track.rawChunks[trackChunk].endTick,
                           cppID: trackID, what: "scoped chunk end tick grows")
        report.expectEqual(expected: otherEnd, actual: track.rawChunks[otherChunk].endTick,
                           cppID: trackID, what: "unscoped chunk end tick stays")
        let trackAfter = coreTimeBytes(track)
        _ = track.history.undoDocument()
        report.expectEqual(expected: trackBefore, actual: coreTimeBytes(track), cppID: trackID,
                           what: "one undo restores the track insertion")
        _ = track.history.redoDocument()
        report.expectEqual(expected: trackAfter, actual: coreTimeBytes(track), cppID: trackID,
                           what: "one redo restores the track insertion")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                    "track fixture failed: \(error)")
    }

    // timeRangeNoOps: faithful empty/reserved-range rejection port.
    do {
        let noopDoc = try timeRangeDocument()
        let noopID = "editcheck/EditCheckTest::timeRangeNoOps"
        report.expectEqual(expected: 2, actual: noopDoc.engineTracks.usedTrackCount, cppID: noopID,
                           what: "timeRangeFile fixture loads two editable tracks")
        let noopTempos = noopDoc.state.tempo
        let noopBefore = coreTimeBytes(noopDoc)
        let noopPosition = try coreEditHistoryCountAtTip(noopDoc, report: report, cppID: noopID)
        let emptyRevision = noopDoc.revision
        report.expect(!noopDoc.removeTime(TimeRange(startTick: 20, endTick: 20), scope: TimeScope()) &&
            !noopDoc.insertBlankTime(TimeRange(startTick: 20, endTick: 10), scope: TimeScope()) &&
            !noopDoc.duplicateTime(TimeRange(startTick: 20, endTick: TimeDefaults.noTick),
                                    scope: TimeScope(tracks: [0])) &&
            noopDoc.revision == emptyRevision,
            cppID: "editcheck/EditCheckTest::timeRangeNoOps",
            message: "empty and reserved ranges create no state or history")
        report.expect(!noopDoc.duplicateTime(TimeRange(startTick: 20, endTick: 10),
                                             scope: TimeScope()),
                      cppID: noopID, message: "reversed range rejects duplicate")
        report.expect(!noopDoc.removeTime(TimeRange(startTick: 20, endTick: 30),
                                          scope: TimeScope(tracks: [99])),
                      cppID: noopID, message: "invalid track rejects remove")
        report.expect(!noopDoc.insertBlankTime(TimeRange(startTick: 20, endTick: 30),
                                               scope: TimeScope(tracks: [99])),
                      cppID: noopID, message: "invalid track rejects insert")
        report.expect(!noopDoc.duplicateTime(TimeRange(startTick: 20, endTick: 30),
                                             scope: TimeScope(tracks: [99])),
                      cppID: noopID, message: "invalid track rejects duplicate")
        report.expectEqual(expected: noopBefore, actual: coreTimeBytes(noopDoc), cppID: noopID,
                           what: "rejected ranges leave bytes unchanged")
        report.expectEqual(expected: noopTempos, actual: noopDoc.state.tempo, cppID: noopID,
                           what: "rejected ranges leave tempo unchanged")
        report.expectEqual(expected: noopPosition,
                           actual: try coreEditHistoryCountAtTip(noopDoc, report: report,
                                                         cppID: noopID),
                           cppID: noopID, what: "rejected ranges add no history")
        _ = try noopDoc.addNotes([
            NewNote(track: 0, tick: 30, pitch: 60, duration: 10, velocity: 90),
        ])
        let sentinelBefore = coreTimeBytes(noopDoc)
        let sentinelPosition = try coreEditHistoryCountAtTip(noopDoc, report: report,
                                                             cppID: noopID)
        report.expect(!noopDoc.removeTime(TimeRange(startTick: 20,
                                                    endTick: TimeDefaults.noTick),
                                          scope: TimeScope(tracks: [0])),
                      cppID: noopID, message: "reserved end tick rejects remove")
        report.expect(!noopDoc.insertBlankTime(TimeRange(startTick: 20,
                                                         endTick: TimeDefaults.noTick),
                                               scope: TimeScope(tracks: [0])),
                      cppID: noopID, message: "reserved end tick rejects insert")
        report.expect(!noopDoc.duplicateTime(TimeRange(startTick: 20,
                                                       endTick: TimeDefaults.noTick),
                                             scope: TimeScope(tracks: [0])),
                      cppID: noopID, message: "reserved end tick rejects duplicate")
        report.expectEqual(expected: sentinelBefore, actual: coreTimeBytes(noopDoc), cppID: noopID,
                           what: "sentinel rejections leave bytes unchanged")
        report.expectEqual(expected: noopTempos, actual: noopDoc.state.tempo, cppID: noopID,
                           what: "sentinel rejections leave tempo unchanged")
        report.expectEqual(expected: sentinelPosition,
                           actual: try coreEditHistoryCountAtTip(noopDoc, report: report,
                                                         cppID: noopID),
                           cppID: noopID, what: "sentinel rejections add no history")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeNoOps",
                    "no-op fixture failed: \(error)")
    }


    let zero = timeDocument()
    _ = try? zero.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 2, velocity: 80),
    ])
    report.expect(zero.insertBlankTime(TimeRange(startTick: 0, endTick: 1),
                                       scope: TimeScope(tracks: [0])) &&
        zero.notes(in: 0).contains { $0.tick == 1 && $0.duration == 2 },
        cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
        message: "tick-zero insertion is an ordinary right shift")

    // timeRangeInsertBlankOverflow: faithful maxTick rejection port.
    do {
        let overflow = try timeRangeDocument()
        let overflowID = "editcheck/EditCheckTest::timeRangeInsertBlankOverflow"
        report.expectEqual(expected: 2, actual: overflow.engineTracks.usedTrackCount, cppID: overflowID,
                           what: "timeRangeFile fixture loads two editable tracks")
        guard let overflowChunk = overflow.engineTracks.tracks[0].midiChunk else {
            report.fail(overflowID, "engine track 0 has no MIDI chunk")
            return
        }
        overflow.insertRawEvent(chunk: overflowChunk,
                                    event: .channel(tick: TimeDefaults.maxTick,
                                                    status: 0xB0, data0: 7, data1: 1))
        let overflowBefore = overflow.state
        let overflowBytesBefore = coreTimeBytes(overflow)
        let overflowPosition = try coreEditHistoryCountAtTip(overflow, report: report,
                                                             cppID: overflowID)
        report.expect(!overflow.insertBlankTime(TimeRange(startTick: 0, endTick: 1),
                                                scope: TimeScope(tracks: [0])) &&
            overflow.state == overflowBefore,
            cppID: "editcheck/EditCheckTest::timeRangeInsertBlankOverflow",
            message: "maximum-tick overflow rejects before candidate installation")
        report.expectEqual(expected: overflowBytesBefore, actual: coreTimeBytes(overflow), cppID: overflowID,
                           what: "rejected overflow leaves bytes unchanged")
        report.expectEqual(expected: overflowPosition,
                           actual: try coreEditHistoryCountAtTip(overflow, report: report,
                                                         cppID: overflowID),
                           cppID: overflowID, what: "rejected overflow adds no history")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeInsertBlankOverflow",
                    "overflow fixture failed: \(error)")
    }
}

@MainActor
private func duplicationAndGlobals(_ report: CheckReport) {
    let document = timeDocument()
    _ = try? document.addNotes([
        NewNote(track: 0, tick: 595, pitch: 67, duration: 30, velocity: 60),
        NewNote(track: 0, tick: 610, pitch: 64, duration: 10, velocity: 90),
    ])
    document.writeLane(track: 0, lane: .controller(7), from: 580, through: 610,
                       points: [LaneWrite(tick: 580, value: 33), LaneWrite(tick: 610, value: 44)])
    let originalIDs = Set(document.notes(in: 0).map(\.id))
    let before = coreTimeBytes(document)
    report.expect(document.duplicateTime(TimeRange(startTick: 600, endTick: 620),
                                         scope: TimeScope(tracks: [0])),
                  cppID: "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
                  message: "time duplication commits")
    let copies = document.notes(in: 0).filter { $0.tick >= 620 && $0.tick < 640 }
    report.expect(copies.count == 2 && copies.allSatisfy { !originalIDs.contains($0.id) },
                  cppID: "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
                  message: "clipped duplicates all receive fresh identities")
    report.expect(document.lanePoints(track: 0, lane: .controller(7)).contains {
        $0.tick == 620 && $0.value == 33
    }, cppID: "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults",
    message: "duplicate seeds the effective value at its destination seam")
    _ = document.history.undoDocument()
    report.expectEqual(expected: before, actual: coreTimeBytes(document),
                       cppID: "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
                       what: "one undo restores the duplicated range transaction")

    // timeRangeDuplicateClippingAndOrder: faithful four-note clipping port.
    do {
        let clipID = "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder"
        let clipping = try timeRangeDocument()
        report.expectEqual(expected: 2, actual: clipping.engineTracks.usedTrackCount, cppID: clipID,
                           what: "timeRangeFile fixture loads two editable tracks")
        let start: Tick = 600
        _ = try clipping.addNotes([
            NewNote(track: 0, tick: start + 10, pitch: 64, duration: 10, velocity: 90),
            NewNote(track: 0, tick: start - 5, pitch: 65, duration: 15, velocity: 80),
            NewNote(track: 0, tick: start + 10, pitch: 66, duration: 20, velocity: 70),
            NewNote(track: 0, tick: start - 5, pitch: 67, duration: 30, velocity: 60),
        ])
        func clipNote(_ tick: Tick, _ pitch: UInt8) -> Note? {
            clipping.notes(in: 0).first { $0.tick == tick && $0.pitch == pitch }
        }
        guard let contained = clipNote(start + 10, 64),
              let leftCross = clipNote(start - 5, 65),
              let rightCross = clipNote(start + 10, 66),
              let bothCross = clipNote(start - 5, 67) else {
            report.fail(clipID, "pre-duplication notes missing")
            return
        }
        let original = [contained.id, leftCross.id, rightCross.id, bothCross.id]
        let clipBefore = coreTimeBytes(clipping)
        report.expect(clipping.duplicateTime(TimeRange(startTick: start, endTick: start + 20),
                                             scope: TimeScope(tracks: [0])),
                      cppID: clipID, message: "time duplication commits")
        guard let copiedContained = clipNote(start + 30, 64),
              let copiedLeft = clipNote(start + 20, 65),
              let copiedRight = clipNote(start + 30, 66),
              let copiedBoth = clipNote(start + 20, 67) else {
            report.fail(clipID, "duplicated notes missing at expected ticks")
            return
        }
        report.expectEqual(expected: Tick(10), actual: copiedContained.duration, cppID: clipID,
                           what: "contained copy keeps its duration")
        report.expectEqual(expected: Tick(10), actual: copiedLeft.duration, cppID: clipID,
                           what: "left-crossing copy clips to the range")
        report.expectEqual(expected: Tick(10), actual: copiedRight.duration, cppID: clipID,
                           what: "right-crossing copy clips to the range")
        report.expectEqual(expected: Tick(20), actual: copiedBoth.duration, cppID: clipID,
                           what: "both-crossing copy clips to the range")
        let copies = [copiedContained.id, copiedLeft.id, copiedRight.id, copiedBoth.id]
        for (index, copy) in copies.enumerated() {
            for source in original {
                report.expect(copy != source, cppID: clipID,
                              message: "copy \(index) receives a fresh identity")
            }
            for other in copies.dropFirst(index + 1) {
                report.expect(copy != other, cppID: clipID,
                              message: "copy \(index) is unique among copies")
            }
        }
        let clipAfter = coreTimeBytes(clipping)
        _ = clipping.history.undoDocument()
        report.expectEqual(expected: clipBefore, actual: coreTimeBytes(clipping), cppID: clipID,
                           what: "one undo restores the clipping duplication")
        _ = clipping.history.redoDocument()
        report.expectEqual(expected: clipAfter, actual: coreTimeBytes(clipping), cppID: clipID,
                           what: "one redo restores the clipping duplication")
        guard let clipChunk = clipping.engineTracks.tracks[0].midiChunk else {
            report.fail(clipID, "engine track 0 has no MIDI chunk")
            return
        }
        clipping.insertRawEvent(chunk: clipChunk,
                                    event: .channel(tick: 700, status: 0x80,
                                                    data0: 72, data1: 0))
        clipping.insertRawEvent(chunk: clipChunk,
                                    event: .channel(tick: 700, status: 0x90,
                                                    data0: 72, data1: 55))
        report.expect(clipping.duplicateTime(TimeRange(startTick: 700, endTick: 720),
                                             scope: TimeScope(tracks: [0])),
                      cppID: clipID, message: "unterminated-source duplication commits")
        report.expect(coreTimeNoteEndsBeforeOnsAt(clipping, track: 0, tick: 720),
                      cppID: clipID,
                      message: "duplicated unterminated note ends before later ons")
        clipping.insertRawEvent(chunk: clipChunk,
                                    event: .channel(tick: 800, status: 0x80,
                                                    data0: 73, data1: 0))
        clipping.insertRawEvent(chunk: clipChunk,
                                    event: .channel(tick: 800, status: 0x90,
                                                    data0: 73, data1: 66))
        report.expect(clipping.insertBlankTime(TimeRange(startTick: 800, endTick: 820),
                                               scope: TimeScope(tracks: [0])),
                      cppID: clipID, message: "insertion over unterminated source commits")
        report.expect(coreTimeNoteEndsBeforeOnsAt(clipping, track: 0, tick: 820),
                      cppID: clipID,
                      message: "inserted unterminated note ends before later ons")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
                    "clipping fixture failed: \(error)")
    }

    // timeRangeUnterminated: faithful port over the timeRangeFile fixture.
    do {
        let unterminated = try timeRangeDocument()
        let unterminatedID = "editcheck/EditCheckTest::timeRangeUnterminated"
        report.expectEqual(expected: 2, actual: unterminated.engineTracks.usedTrackCount, cppID: unterminatedID,
                           what: "timeRangeFile fixture loads two editable tracks")
        guard let unterminatedChunk = unterminated.engineTracks.tracks[0].midiChunk else {
            report.fail(unterminatedID, "engine track 0 has no MIDI chunk")
            return
        }
        unterminated.insertRawEvent(chunk: unterminatedChunk,
                                        event: .channel(tick: 220, status: 0x90,
                                                        data0: 68, data1: 77))
        guard let source = unterminated.notes(in: 0).first(where: {
            $0.tick == 220 && $0.pitch == 68
        }) else {
            report.fail(unterminatedID, "unterminated source note missing")
            return
        }
        report.expect(source.isUnterminated, cppID: unterminatedID,
                      message: "raw note-on without a note-off is unterminated")
        let leftID = source.id
        let unterminatedBefore = coreTimeBytes(unterminated)
        report.expect(unterminated.insertBlankTime(TimeRange(startTick: 240, endTick: 250),
                                                   scope: TimeScope(tracks: [0])),
                      cppID: unterminatedID, message: "blank insertion commits")
        guard let left = unterminated.notes(in: 0).first(where: {
            $0.tick == 220 && $0.pitch == 68
        }), let right = unterminated.notes(in: 0).first(where: {
            $0.tick == 250 && $0.pitch == 68
        }) else {
            report.fail(unterminatedID, "split halves missing after insertion")
            return
        }
        report.expect(!left.isUnterminated, cppID: unterminatedID,
                      message: "left half is terminated by the insertion")
        report.expectEqual(expected: Tick(20), actual: left.duration, cppID: unterminatedID,
                           what: "left half ends at the insertion start")
        report.expectEqual(expected: leftID, actual: left.id, cppID: unterminatedID,
                           what: "left half keeps the source identity")
        report.expect(right.isUnterminated, cppID: unterminatedID,
                      message: "right half resumes unterminated")
        report.expect(right.id != left.id, cppID: unterminatedID,
                      message: "right half receives a fresh identity")
        let unterminatedEvents = unterminated.rawChunks[unterminatedChunk].events
        report.expect(hasChannel(unterminatedEvents, tick: 220, type: 0x9, key: 68) &&
                      hasChannel(unterminatedEvents, tick: 240, type: 0x8, key: 68) &&
                      hasChannel(unterminatedEvents, tick: 250, type: 0x9, key: 68),
                      cppID: unterminatedID,
                      message: "insertion emits source on, generated off, and resumed on")
        let parts = unterminated.notes(in: 0).filter { $0.pitch == 68 }
        report.expect(parts.count == 2 && parts[0].id == leftID && parts[0].duration == 20 &&
            parts[1].id != leftID && parts[1].isUnterminated,
            cppID: "editcheck/EditCheckTest::timeRangeUnterminated",
            message: "blank insertion closes and resumes an unterminated note")
        let unterminatedAfter = coreTimeBytes(unterminated)
        _ = unterminated.history.undoDocument()
        report.expectEqual(expected: unterminatedBefore, actual: coreTimeBytes(unterminated),
                           cppID: unterminatedID,
                           what: "one undo restores the unterminated insertion")
        _ = unterminated.history.redoDocument()
        report.expectEqual(expected: unterminatedAfter, actual: coreTimeBytes(unterminated),
                           cppID: unterminatedID,
                           what: "one redo restores the unterminated insertion")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeUnterminated",
                    "unterminated fixture failed: \(error)")
    }

    let globals = timeDocument()
    globals.setTimeSignature(tick: 960, numerator: 3, denominatorPower: 2)
    globals.insertRawEvent(chunk: 0, event: .meta(tick: 965, type: 0x01, data: [65, 66]))
    globals.editTempo(TempoEdit(add: [TempoPoint(tick: 970, microsecondsPerQuarterNote: 333_333)]))
    _ = globals.duplicateTime(TimeRange(startTick: 960, endTick: 980),
                              scope: TimeScope(wholeSong: true))
    report.expect(globals.timeSignatures.contains { $0.tick == 980 && $0.numerator == 3 } &&
        globals.rawChunks[0].events.contains { $0.tick == 985 && $0.metaType == 0x01 } &&
        globals.state.tempo.contains { $0.tick == 990 },
        cppID: "editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
        message: "signature, opaque global and tempo duplicate with their stream rules")

    // timeRangeSignatureAndOrphans: faithful signature-insert port.
    do {
        let signature = try timeRangeDocument()
        let signatureID = "editcheck/EditCheckTest::timeRangeSignatureAndOrphans"
        report.expectEqual(expected: 2, actual: signature.engineTracks.usedTrackCount, cppID: signatureID,
                           what: "timeRangeFile fixture loads two editable tracks")
        let seam: Tick = 960
        let bar = 3 * Tick(signature.state.file.division)
        signature.setTimeSignature(tick: 0, numerator: 4, denominatorPower: 2)
        signature.setTimeSignature(tick: seam, numerator: 3, denominatorPower: 2)
        let signatureBefore = coreTimeBytes(signature)
        report.expect(signature.insertBlankTime(TimeRange(startTick: seam,
                                                          endTick: seam + bar),
                                                scope: TimeScope(wholeSong: true)),
                      cppID: signatureID, message: "whole-song signature insertion commits")
        let signatures = signature.timeSignatures.filter {
            $0.numerator == 3 && $0.denominatorPower == 2
        }
        report.expect(signatures.contains { $0.tick == seam }, cppID: signatureID,
                      message: "signature stays at the seam")
        report.expect(signatures.contains { $0.tick == seam + bar }, cppID: signatureID,
                      message: "signature copy lands one bar later")
        let signatureAfter = coreTimeBytes(signature)
        _ = signature.history.undoDocument()
        report.expectEqual(expected: signatureBefore, actual: coreTimeBytes(signature), cppID: signatureID,
                           what: "one undo restores the signature insertion")
        _ = signature.history.redoDocument()
        report.expectEqual(expected: signatureAfter, actual: coreTimeBytes(signature), cppID: signatureID,
                           what: "one redo restores the signature insertion")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
                    "signature fixture failed: \(error)")
    }

    // timeRangeSignatureAndOrphans: faithful orphan-removal port.
    do {
        let orphans = try timeRangeDocument()
        let orphanID = "editcheck/EditCheckTest::timeRangeSignatureAndOrphans"
        report.expectEqual(expected: 2, actual: orphans.engineTracks.usedTrackCount, cppID: orphanID,
                           what: "timeRangeFile fixture loads two editable tracks")
        guard let orphanChunk = orphans.engineTracks.tracks[0].midiChunk else {
            report.fail(orphanID, "engine track 0 has no MIDI chunk")
            return
        }
        _ = try orphans.addNotes([
            NewNote(track: 0, tick: 40, pitch: 60, duration: 10, velocity: 90),
        ])
        orphans.insertRawEvent(chunk: orphanChunk,
                                   event: .channel(tick: 90, status: 0x90,
                                                   data0: 61, data1: 11))
        orphans.insertRawEvent(chunk: orphanChunk,
                                   event: .channel(tick: 120, status: 0x80,
                                                   data0: 66, data1: 13))
        orphans.insertRawEvent(chunk: orphanChunk,
                                   event: .channel(tick: 110, status: 0x90,
                                                   data0: 62, data1: 22))
        orphans.insertRawEvent(chunk: orphanChunk,
                                   event: .channel(tick: 130, status: 0x80,
                                                   data0: 63, data1: 12))
        orphans.insertRawEvent(chunk: orphanChunk,
                                   event: .channel(tick: 130, status: 0x90,
                                                   data0: 64, data1: 33))
        orphans.insertRawEvent(chunk: orphanChunk,
                                   event: .channel(tick: 140, status: 0x90,
                                                   data0: 65, data1: 44))
        let orphanBefore = coreTimeBytes(orphans)
        report.expect(orphans.removeTime(TimeRange(startTick: 100, endTick: 130),
                                         scope: TimeScope(tracks: [0])),
                      cppID: orphanID, message: "orphan removal commits")
        let orphanEvents = orphans.rawChunks[orphanChunk].events
        report.expect(hasChannel(orphanEvents, tick: 90, type: 0x9, key: 61),
                      cppID: orphanID, message: "note-on before the range survives")
        report.expect(!hasChannel(orphanEvents, tick: 110, type: 0x9, key: 62),
                      cppID: orphanID, message: "note-on inside the range is removed")
        report.expect(!orphanEvents.contains { event in
            guard case let .channel(status, data0, _) = event.payload else { return false }
            return status == 0x80 && data0 == 66
        }, cppID: orphanID, message: "orphaned note-off inside the range is removed")
        report.expect(!hasChannel(orphanEvents, tick: 110, type: 0x9, key: 62) &&
            hasChannel(orphanEvents, tick: 100, type: 0x8, key: 63) &&
            hasChannel(orphanEvents, tick: 100, type: 0x9, key: 64) &&
            hasChannel(orphanEvents, tick: 110, type: 0x9, key: 65),
            cppID: "editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
            message: "orphan note bytes use half-open remove and pinned seam ordering")
        report.expect(coreTimeNoteEndsBeforeOnsAt(orphans, track: 0, tick: 100),
                      cppID: orphanID,
                      message: "every note end at the seam precedes later note-ons")
        guard let paired = orphans.notes(in: 0).first(where: {
            $0.tick == 40 && $0.pitch == 60
        }) else {
            report.fail(orphanID, "paired note missing after removal")
            return
        }
        report.expect(!paired.isUnterminated, cppID: orphanID,
                      message: "paired note stays terminated")
        report.expectEqual(expected: Tick(10), actual: paired.duration, cppID: orphanID,
                           what: "paired note keeps its duration")
        let orphanAfter = coreTimeBytes(orphans)
        _ = orphans.history.undoDocument()
        report.expectEqual(expected: orphanBefore, actual: coreTimeBytes(orphans), cppID: orphanID,
                           what: "one undo restores the orphan removal")
        _ = orphans.history.redoDocument()
        report.expectEqual(expected: orphanAfter, actual: coreTimeBytes(orphans), cppID: orphanID,
                           what: "one redo restores the orphan removal")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
                    "orphan fixture failed: \(error)")
    }

    // timeRangeAutomationSeamsAndDefaults: faithful seam/defaults/tempo/voice port.
    do {
        let autoID = "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults"
        let automation = try timeRangeDocument()
        report.expectEqual(expected: 2, actual: automation.engineTracks.usedTrackCount, cppID: autoID,
                           what: "timeRangeFile fixture loads two editable tracks")
        let seam: Tick = 1000
        automation.writeLane(track: 0, lane: .controller(7), from: seam - 20,
                             through: seam - 20,
                             points: [LaneWrite(tick: seam - 20, value: 33)])
        automation.writeLane(track: 0, lane: .controller(7), from: seam + 10,
                             through: seam + 10,
                             points: [LaneWrite(tick: seam + 10, value: 44)])
        let seamBefore = coreTimeBytes(automation)
        let seamPosition = try coreEditHistoryCountAtTip(automation, report: report,
                                                         cppID: autoID)
        report.expect(automation.duplicateTime(TimeRange(startTick: seam,
                                                         endTick: seam + 40),
                                               scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: .controller(7))])),
                      cppID: autoID, message: "lane-scoped duplication commits")
        report.expectEqual(expected: "1040:33", actual: automation.lanePoints(track: 0, lane: .controller(7))
            .first(where: { $0.tick == seam + 40 }).map(coreTimePointShape),
            cppID: autoID, what: "seam copy seeds the effective value")
        report.expectEqual(expected: "1050:44", actual: automation.lanePoints(track: 0, lane: .controller(7))
            .first(where: { $0.tick == seam + 50 }).map(coreTimePointShape),
            cppID: autoID, what: "in-range point copies to its shifted tick")
        report.expectEqual(expected: seamPosition + 1,
                           actual: try coreEditHistoryCountAtTip(automation, report: report,
                                                         cppID: autoID),
                           cppID: autoID, what: "lane duplication adds one history entry")
        let seamAfter = coreTimeBytes(automation)
        _ = automation.history.undoDocument()
        report.expectEqual(expected: seamBefore, actual: coreTimeBytes(automation), cppID: autoID,
                           what: "one undo restores the seam duplication")
        _ = automation.history.redoDocument()
        report.expectEqual(expected: seamAfter, actual: coreTimeBytes(automation), cppID: autoID,
                           what: "one redo restores the seam duplication")

        let defaults = try timeRangeDocument()
        report.expectEqual(expected: 2, actual: defaults.engineTracks.usedTrackCount, cppID: autoID,
                           what: "timeRangeFile fixture loads two editable tracks")
        let cases: [(lane: Lane, source: Int, expected: Int)] = [
            (.controller(0x01), 11, 0),
            (.controller(0x05), 12, 0),
            (.controller(0x07), 80, 127),
            (.controller(0x0A), 81, 64),
            (.controller(0x14), 3, 2),
            (.controller(0x15), 4, 22),
            (.controller(0x17), 5, 0),
            (.controller(0x19), 6, 0),
            (.pitchBend, 500, 0),
        ]
        for index in stride(from: cases.count - 1, through: 0, by: -1) {
            let entry = cases[index]
            let start: Tick = 1100 + Tick(index) * 40
            defaults.writeLane(track: 0, lane: entry.lane, from: start + 10,
                               through: start + 10,
                               points: [LaneWrite(tick: start + 10, value: entry.source)])
            let caseBefore = coreTimeBytes(defaults)
            let casePosition = try coreEditHistoryCountAtTip(defaults, report: report,
                                                             cppID: autoID)
            report.expect(defaults.duplicateTime(TimeRange(startTick: start,
                                                           endTick: start + 20),
                                                 scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: entry.lane)])),
                          cppID: autoID, message: "default-seeding duplication commits")
            report.expectEqual(expected: "\(start + 20):\(entry.expected)",
                               actual: defaults.lanePoints(track: 0, lane: entry.lane)
                .first(where: { $0.tick == start + 20 }).map(coreTimePointShape),
                cppID: autoID, what: "destination seam seeds the lane default")
            report.expectEqual(expected: casePosition + 1,
                               actual: try coreEditHistoryCountAtTip(defaults, report: report,
                                                             cppID: autoID),
                               cppID: autoID,
                               what: "default duplication adds one history entry")
            let caseAfter = coreTimeBytes(defaults)
            _ = defaults.history.undoDocument()
            report.expectEqual(expected: caseBefore, actual: coreTimeBytes(defaults), cppID: autoID,
                               what: "one undo restores the default duplication")
            _ = defaults.history.redoDocument()
            report.expectEqual(expected: caseAfter, actual: coreTimeBytes(defaults), cppID: autoID,
                               what: "one redo restores the default duplication")
        }

        defaults.editTempo(TempoEdit(
            remove: [TempoPoint(tick: 0, microsecondsPerQuarterNote: 500_000)],
            add: [TempoPoint(tick: 1510, microsecondsPerQuarterNote: 400_000)]))
        let tempoBytesBefore = coreTimeBytes(defaults)
        let temposBefore = defaults.state.tempo
        let tempoPosition = try coreEditHistoryCountAtTip(defaults, report: report,
                                                          cppID: autoID)
        report.expect(defaults.duplicateTime(TimeRange(startTick: 1500, endTick: 1520),
                                             scope: TimeScope(tempo: true)),
                      cppID: autoID, message: "tempo-scoped duplication commits")
        report.expect(defaults.state.tempo.contains(
            TempoPoint(tick: 1520, microsecondsPerQuarterNote: 500_000)),
            cppID: autoID, message: "boundary tempo copies to the destination seam")
        report.expect(defaults.state.tempo.contains(
            TempoPoint(tick: 1530, microsecondsPerQuarterNote: 400_000)),
            cppID: autoID, message: "in-range tempo copies to its shifted tick")
        let timeline = PlaybackTimeline.build(state: defaults.state, sampleRate: 44_100)
        report.expect(!timeline.tempoMap.isEmpty, cppID: autoID,
                      message: "tempo map is non-empty after duplication")
        report.expectEqual(expected: 120.0, actual: timeline.tempoMap.first?.beatsPerMinute, cppID: autoID,
                           what: "tempo map starts at 120 bpm")
        report.expectEqual(expected: tempoPosition + 1,
                           actual: try coreEditHistoryCountAtTip(defaults, report: report,
                                                         cppID: autoID),
                           cppID: autoID, what: "tempo duplication adds one history entry")
        let tempoBytesAfter = coreTimeBytes(defaults)
        let temposAfter = defaults.state.tempo
        _ = defaults.history.undoDocument()
        report.expectEqual(expected: tempoBytesBefore, actual: coreTimeBytes(defaults), cppID: autoID,
                           what: "one undo restores the tempo duplication")
        report.expectEqual(expected: temposBefore, actual: defaults.state.tempo, cppID: autoID,
                           what: "one undo restores the tempo points")
        _ = defaults.history.redoDocument()
        report.expectEqual(expected: tempoBytesAfter, actual: coreTimeBytes(defaults), cppID: autoID,
                           what: "one redo restores the tempo duplication")
        report.expectEqual(expected: temposAfter, actual: defaults.state.tempo, cppID: autoID,
                           what: "one redo restores the tempo points")

        defaults.writeLane(track: 0, lane: .voice, from: 1610, through: 1610,
                           points: [LaneWrite(tick: 1610, value: 12)])
        let voiceBefore = coreTimeBytes(defaults)
        let voicePosition = try coreEditHistoryCountAtTip(defaults, report: report,
                                                          cppID: autoID)
        report.expect(defaults.duplicateTime(TimeRange(startTick: 1600, endTick: 1620),
                                             scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: .voice)])),
                      cppID: autoID, message: "voice-scoped duplication commits")
        report.expectEqual(expected: "1620:1", actual: defaults.lanePoints(track: 0, lane: .voice)
            .first(where: { $0.tick == 1620 }).map(coreTimePointShape),
            cppID: autoID, what: "voice seam seeds the default program")
        report.expectEqual(expected: "1630:12", actual: defaults.lanePoints(track: 0, lane: .voice)
            .first(where: { $0.tick == 1630 }).map(coreTimePointShape),
            cppID: autoID, what: "voice point copies to its shifted tick")
        report.expectEqual(expected: voicePosition + 1,
                           actual: try coreEditHistoryCountAtTip(defaults, report: report,
                                                         cppID: autoID),
                           cppID: autoID, what: "voice duplication adds one history entry")
        let voiceAfter = coreTimeBytes(defaults)
        _ = defaults.history.undoDocument()
        report.expectEqual(expected: voiceBefore, actual: coreTimeBytes(defaults), cppID: autoID,
                           what: "one undo restores the voice duplication")
        _ = defaults.history.redoDocument()
        report.expectEqual(expected: voiceAfter, actual: coreTimeBytes(defaults), cppID: autoID,
                           what: "one redo restores the voice duplication")

        let downstream: Tick = 1700
        defaults.writeLane(track: 0, lane: .controller(7), from: downstream,
                           through: downstream,
                           points: [LaneWrite(tick: downstream, value: 11)])
        defaults.writeLane(track: 0, lane: .controller(7), from: downstream + 20,
                           through: downstream + 20,
                           points: [LaneWrite(tick: downstream + 20, value: 99)])
        let downstreamBefore = coreTimeBytes(defaults)
        let downstreamPosition = try coreEditHistoryCountAtTip(defaults, report: report,
                                                             cppID: autoID)
        report.expect(defaults.duplicateTime(TimeRange(startTick: downstream,
                                                       endTick: downstream + 20),
                                             scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: .controller(7))])),
                      cppID: autoID, message: "downstream lane duplication commits")
        report.expectEqual(expected: "1720:11", actual: defaults.lanePoints(track: 0, lane: .controller(7))
            .first(where: { $0.tick == downstream + 20 }).map(coreTimePointShape),
            cppID: autoID, what: "downstream seam seeds the effective value")
        report.expectEqual(expected: "1740:99", actual: defaults.lanePoints(track: 0, lane: .controller(7))
            .first(where: { $0.tick == downstream + 40 }).map(coreTimePointShape),
            cppID: autoID, what: "downstream point copies to its shifted tick")
        report.expectEqual(expected: downstreamPosition + 1,
                           actual: try coreEditHistoryCountAtTip(defaults, report: report,
                                                         cppID: autoID),
                           cppID: autoID,
                           what: "downstream duplication adds one history entry")
        let downstreamAfter = coreTimeBytes(defaults)
        _ = defaults.history.undoDocument()
        report.expectEqual(expected: downstreamBefore, actual: coreTimeBytes(defaults), cppID: autoID,
                           what: "one undo restores the downstream duplication")
        _ = defaults.history.redoDocument()
        report.expectEqual(expected: downstreamAfter, actual: coreTimeBytes(defaults), cppID: autoID,
                           what: "one redo restores the downstream duplication")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults",
                    "automation fixture failed: \(error)")
    }

    // timeRangeWholeSong: faithful whole-song duplication port.
    do {
        let wholeID = "editcheck/EditCheckTest::timeRangeWholeSong"
        let wholeDuplicate = try timeRangeDocument()
        report.expectEqual(expected: 2, actual: wholeDuplicate.engineTracks.usedTrackCount, cppID: wholeID,
                           what: "timeRangeFile fixture loads two editable tracks")
        let start: Tick = 1800
        _ = try wholeDuplicate.addNotes([
            NewNote(track: 0, tick: 1900, pitch: 70, duration: 5, velocity: 50),
        ])
        wholeDuplicate.setTimeSignature(tick: start + 10, numerator: 3,
                                        denominatorPower: 2)
        wholeDuplicate.editTempo(TempoEdit(
            add: [TempoPoint(tick: start + 10,
                             microsecondsPerQuarterNote: 333_333)]))
        wholeDuplicate.insertRawEvent(chunk: 0,
                                          event: .meta(tick: start + 15, type: 0x01,
                                                       data: Array("global".utf8)))
        let wholeDuplicateBefore = coreTimeBytes(wholeDuplicate)
        report.expect(wholeDuplicate.duplicateTime(TimeRange(startTick: start,
                                                             endTick: start + 20),
                                                   scope: TimeScope(wholeSong: true)),
                      cppID: wholeID, message: "whole-song duplication commits")
        report.expect(wholeDuplicate.rawChunks[0].events.contains { event in
            event.tick == start + 35 && event.metaType == 0x01 &&
                event.blob == Array("global".utf8)
        }, cppID: wholeID, message: "text meta copies to the duplicated seam")
        report.expect(wholeDuplicate.timeSignatures.contains {
            $0.tick == start + 30 && $0.numerator == 3
        }, cppID: wholeID, message: "signature copies to the duplicated seam")
        report.expect(wholeDuplicate.state.tempo.contains(
            TempoPoint(tick: start + 20, microsecondsPerQuarterNote: 500_000)),
            cppID: wholeID, message: "default tempo copies to the seam")
        report.expect(wholeDuplicate.state.tempo.contains(
            TempoPoint(tick: start + 30, microsecondsPerQuarterNote: 333_333)),
            cppID: wholeID, message: "in-range tempo copies to its shifted tick")
        guard let shifted = wholeDuplicate.notes(in: 0).first(where: {
            $0.tick == 1920 && $0.pitch == 70
        }) else {
            report.fail(wholeID, "shifted note missing after duplication")
            return
        }
        guard let wholeChunk = wholeDuplicate.engineTracks.tracks[0].midiChunk else {
            report.fail(wholeID, "engine track 0 has no MIDI chunk")
            return
        }
        report.expect(wholeDuplicate.rawChunks[wholeChunk].endTick >=
            UInt64(shifted.tick) + UInt64(shifted.duration),
            cppID: wholeID,
            message: "chunk end tick covers the duplicated note")
        let wholeDuplicateAfter = coreTimeBytes(wholeDuplicate)
        _ = wholeDuplicate.history.undoDocument()
        report.expectEqual(expected: wholeDuplicateBefore, actual: coreTimeBytes(wholeDuplicate),
                           cppID: wholeID,
                           what: "one undo restores the whole-song duplication")
        _ = wholeDuplicate.history.redoDocument()
        report.expectEqual(expected: wholeDuplicateAfter, actual: coreTimeBytes(wholeDuplicate),
                           cppID: wholeID,
                           what: "one redo restores the whole-song duplication")
    } catch {
        report.fail("editcheck/EditCheckTest::timeRangeWholeSong",
                    "whole-song duplication fixture failed: \(error)")
    }
}


@MainActor
private func timeDocument(division: UInt16 = 24, trackBudget: Int = 3) -> SongDocument {
    SongDocument(file: MidiFile(division: division, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 240),
        MidiChunk(events: [.channel(status: 0xC1, data0: 1)], endTick: 240),
    ]), trackBudget: trackBudget)
}

@MainActor
func coreTimeBytes(_ document: SongDocument) -> [UInt8] {
    do { return try document.captureSave().bytes }
    catch { return [] }
}

func coreTimeXcmdTraffic(_ chunk: MidiChunk) -> [Xcmd.Event] {
    chunk.events.enumerated().compactMap { index, event in
        guard case let .channel(status, controller, value) = event.payload,
              status >> 4 == 0xB else { return nil }
        return Xcmd.Event(index: UInt64(index), tick: event.tick, stream: 0,
                          controller: controller, value: value, channel: status & 0x0F)
    }
}


private func noteShape(_ note: Note) -> String {
    "\(note.tick):\(note.pitch):\(note.duration)"
}

func coreTimePointShape(_ point: LanePoint) -> String {
    "\(point.tick):\(point.value)"
}

private func hasChannel(_ events: [MidiEvent], tick: Tick, type: UInt8, key: UInt8) -> Bool {
    events.contains { event in
        guard event.tick == tick,
              case let .channel(status, data0, _) = event.payload else { return false }
        return status >> 4 == type && data0 == key
    }
}


@MainActor
private func timeRangeDocument() throws -> SongDocument {
    SongDocument(file: try MidiFile.decode(MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 200),
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 200),
        MidiChunk(events: [.channel(status: 0xC1, data0: 2)], endTick: 200),
    ]).encoded()))
}

@MainActor
private func coreTimeNoteEndsBeforeOnsAt(_ document: SongDocument, track: Int,
                                         tick: Tick) -> Bool {
    guard let chunk = document.engineTracks.tracks[track].midiChunk else { return true }
    var sawNoteOn = false
    for event in document.rawChunks[chunk].events where event.tick == tick && event.isChannel {
        if event.isNoteOn {
            sawNoteOn = true
        } else if event.isNoteEnd && sawNoteOn {
            return false
        }
    }
    return true
}
