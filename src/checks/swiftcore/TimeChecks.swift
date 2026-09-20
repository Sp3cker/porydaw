import Foundation
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func runTimeEditsSuite(_ report: CheckReport) {
    rangeEditing(report)
    rangeMovement(report)
    removalAndSeams(report)
    insertionAndBoundaries(report)
    duplicationAndGlobals(report)
    xcmdTimeTraffic(report)
    clipboardRangeScenarios(report)
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
    let before = bytes(document)
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
    report.expectEqual(3, document.engineTracks.usedTrackCount,
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "range insertion expands tracks under budget")
    report.expectEqual(["60:65:8"], document.notes(in: 2).map(noteShape),
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "inserted note lands on expanded track")
    report.expectEqual(["60:70"], document.lanePoints(track: 2, lane: .controller(7)).map(pointShape),
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "lane insertion shares the atomic candidate")
    report.expectEqual(1, document.lanePoints(track: 2, lane: .controller(7)).count,
                       cppID: "editcheck/EditCheckTest::rangeLaneConverge",
                       what: "same-stream same-tick range writes converge last-wins")
    report.expect(document.state.tempo.contains {
        $0.tick == 61 && $0.microsecondsPerQuarterNote == 400_000
    }, cppID: "editcheck/EditCheckTest::rangeEdit", message: "tempo replacement is atomic")
    expectNoteTempoOracleParity(document, cppID: "editcheck/EditCheckTest::rangeEdit",
                                row: "post-transform frozen observation", report: report)
    _ = document.history.undoDocument()
    report.expectEqual(before, bytes(document),
                       cppID: "editcheck/EditCheckTest::rangeEdit",
                       what: "one undo restores every stream and track count")

    let collision = timeDocument(trackBudget: 2)
    let collisionBefore = bytes(collision)
    let rejected = RangeEdit(minimumEngineTrackCount: 2, addNotes: [
        NewNote(track: 1, tick: 10, pitch: 60, duration: 20, velocity: 80),
        NewNote(track: 1, tick: 20, pitch: 60, duration: 20, velocity: 90),
    ], addPoints: [RangeEdit.LaneInsertion(
        track: 1, lane: .controller(7), points: [LaneWrite(tick: 10, value: 90)])])
    report.expect(!collision.applyRangeEdit(rejected) && bytes(collision) == collisionBefore,
                  cppID: "editcheck/EditCheckTest::rangeEditCollisionRejects",
                  message: "conflicting participants reject before track expansion")

    let limited = timeDocument(trackBudget: 1)
    let limitedBefore = bytes(limited)
    report.expect(!limited.applyRangeEdit(RangeEdit(
        minimumEngineTrackCount: 2,
        addNotes: [NewNote(track: 1, tick: 1, pitch: 60, duration: 1, velocity: 90)])) &&
        bytes(limited) == limitedBefore,
        cppID: "editcheck/EditCheckTest::rangeEditCollisionRejects",
        message: "budget-constrained expansion leaves the prior state intact")

    let progressive = timeDocument()
    _ = try? progressive.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 100, velocity: 91),
    ])
    let original = bytes(progressive)
    let multiSpan = RangeEdit(addNotes: [
        NewNote(track: 0, tick: 10, pitch: 60, duration: 10, velocity: 80),
        NewNote(track: 0, tick: 30, pitch: 60, duration: 10, velocity: 81),
    ])
    let accepted = progressive.applyRangeEdit(multiSpan)
    let forward = progressive.notes(in: 0).map(noteShape)
    _ = progressive.history.undoDocument()
    let undoRestored = bytes(progressive) == original
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
    let before = bytes(document)
    report.expect(document.moveRange(notes: notes, points: lane, by: 12, tempo: tempo),
                  cppID: "editcheck/EditCheckTest::rangeMove",
                  message: "mixed range move commits")
    report.expectEqual(["92:60:8", "104:64:8"], document.notes(in: 0).map(noteShape),
                       cppID: "editcheck/EditCheckTest::rangeMove",
                       what: "notes retain duration after exact-byte relocation")
    report.expectEqual(["92:45"], document.lanePoints(track: 0, lane: .controller(7)).map(pointShape),
                       cppID: "editcheck/EditCheckTest::rangeLaneBulk",
                       what: "lane event relocates with the range")
    report.expect(document.state.tempo.contains { $0.tick == 93 },
                  cppID: "editcheck/EditCheckTest::rangeLaneConverge",
                  message: "tempo point relocates in the same history entry")
    _ = document.history.undoDocument()
    report.expectEqual(before, bytes(document),
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
    report.expectEqual(["100:60:20", "120:60:20"], headTrim.notes(in: 0).map(noteShape),
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
    report.expectEqual(["100:61:50"], fullCover.notes(in: 0).map(noteShape),
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
    let before = bytes(document)
    report.expect(document.removeTime(TimeRange(startTick: 20, endTick: 50),
                                      scope: TimeScope(tracks: [0])),
                  cppID: "editcheck/EditCheckTest::timeRangeRemoveRippleTrim",
                  message: "scoped gap removal commits")
    report.expectEqual(["0:60:80", "80:60:10"], document.notes(in: 0).map(noteShape),
                       cppID: "editcheck/EditCheckTest::timeRangeRemove",
                       what: "crossing note trims and later note ripples")
    report.expectEqual("20:44", document.lanePoints(track: 0, lane: .controller(7)).first.map(pointShape),
                       cppID: "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults",
                       what: "last in-range value survives at the seam")
    report.expectEqual(untouched?.tick, document.note(ids[2])?.tick,
                       cppID: "editcheck/EditCheckTest::timeRangeRemoveRippleTrim",
                       what: "unscoped track is unchanged")
    _ = document.history.undoDocument()
    report.expectEqual(before, bytes(document),
                       cppID: "editcheck/EditCheckTest::timeRangeRemove",
                       what: "single undo restores scoped removal")

    let whole = timeDocument()
    _ = try? whole.addNotes([NewNote(track: 0, tick: 66, pitch: 65, duration: 4, velocity: 90)])
    whole.setTimeSignature(tick: 62, numerator: 3, denominatorPower: 2)
    whole.editTempo(TempoEdit(add: [TempoPoint(tick: 63, microsecondsPerQuarterNote: 333_333)]))
    whole.insertRawEvent(chunk: 0, event: .meta(tick: 64, type: 0x06, data: [0x5B]))
    let oldEnd = whole.rawChunks.map(\.endTick)
    let wholeBefore = bytes(whole)
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
    report.expectEqual(oldEnd, whole.rawChunks.map(\.endTick),
                       cppID: "editcheck/EditCheckTest::songWholeSongRemove",
                       what: "one undo restores every stored end tick")
    report.expectEqual(wholeBefore, bytes(whole),
                       cppID: "editcheck/EditCheckTest::timeRangeWholeSong",
                       what: "one undo restores globals, events, and end-of-track state")
}

@MainActor
private func insertionAndBoundaries(_ report: CheckReport) {
    let document = timeDocument()
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 35, pitch: 60, duration: 10, velocity: 90),
        NewNote(track: 0, tick: 60, pitch: 61, duration: 5, velocity: 80),
    ]) else { return }
    let crossingID = ids[0], laterID = ids[1]
    let before = bytes(document)
    report.expect(document.insertBlankTime(TimeRange(startTick: 40, endTick: 45),
                                           scope: TimeScope(tracks: [0])),
                  cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                  message: "blank insertion commits")
    let split = document.notes(in: 0).filter { $0.pitch == 60 }
    report.expectEqual(["35:60:5", "45:60:5"], split.map(noteShape),
                       cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                       what: "crossing note splits around a silent interval")
    report.expect(split.count == 2 && split[0].id == crossingID && split[1].id != crossingID,
                  cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                  message: "split right half receives a new identity")
    report.expectEqual(Tick(65), document.note(laterID)?.tick,
                       cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                       what: "later note shifts and preserves identity")
    _ = document.history.undoDocument()
    report.expectEqual(before, bytes(document),
                       cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
                       what: "one undo restores the split")

    let emptyRevision = document.revision
    report.expect(!document.removeTime(TimeRange(startTick: 20, endTick: 20), scope: TimeScope()) &&
        !document.insertBlankTime(TimeRange(startTick: 20, endTick: 10), scope: TimeScope()) &&
        !document.duplicateTime(TimeRange(startTick: 20, endTick: TimeDefaults.noTick),
                                scope: TimeScope(tracks: [0])) &&
        document.revision == emptyRevision,
        cppID: "editcheck/EditCheckTest::timeRangeNoOps",
        message: "empty and reserved ranges create no state or history")

    let zero = timeDocument()
    _ = try? zero.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 2, velocity: 80),
    ])
    report.expect(zero.insertBlankTime(TimeRange(startTick: 0, endTick: 1),
                                       scope: TimeScope(tracks: [0])) &&
        zero.notes(in: 0).contains { $0.tick == 1 && $0.duration == 2 },
        cppID: "editcheck/EditCheckTest::timeRangeInsertScopeAndSplit",
        message: "tick-zero insertion is an ordinary right shift")

    let overflow = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 0),
        .channel(tick: TimeDefaults.maxTick, status: 0xB0, data0: 7, data1: 1),
    ], endTick: TimeDefaults.maxTick)]))
    let overflowBefore = overflow.state
    report.expect(!overflow.insertBlankTime(TimeRange(startTick: 0, endTick: 1),
                                            scope: TimeScope(tracks: [0])) &&
        overflow.state == overflowBefore,
        cppID: "editcheck/EditCheckTest::timeRangeInsertBlankOverflow",
        message: "maximum-tick overflow rejects before candidate installation")
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
    let before = bytes(document)
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
    report.expectEqual(before, bytes(document),
                       cppID: "editcheck/EditCheckTest::timeRangeDuplicateClippingAndOrder",
                       what: "one undo restores the duplicated range transaction")

    let unterminated = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 220, status: 0x90, data0: 68, data1: 77),
    ], endTick: 300)]))
    let leftID = unterminated.notes(in: 0)[0].id
    _ = unterminated.insertBlankTime(TimeRange(startTick: 240, endTick: 250),
                                     scope: TimeScope(tracks: [0]))
    let parts = unterminated.notes(in: 0).filter { $0.pitch == 68 }
    report.expect(parts.count == 2 && parts[0].id == leftID && parts[0].duration == 20 &&
        parts[1].id != leftID && parts[1].isUnterminated,
        cppID: "editcheck/EditCheckTest::timeRangeUnterminated",
        message: "blank insertion closes and resumes an unterminated note")

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

    let orphans = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 90, status: 0x90, data0: 61, data1: 11),
        .channel(tick: 110, status: 0x90, data0: 62, data1: 22),
        .channel(tick: 120, status: 0x80, data0: 66, data1: 13),
        .channel(tick: 130, status: 0x80, data0: 63, data1: 12),
        .channel(tick: 130, status: 0x90, data0: 64, data1: 33),
        .channel(tick: 140, status: 0x90, data0: 65, data1: 44),
    ], endTick: 160)]))
    _ = orphans.removeTime(TimeRange(startTick: 100, endTick: 130),
                           scope: TimeScope(tracks: [0]))
    let orphanEvents = orphans.rawChunks[0].events
    report.expect(!hasChannel(orphanEvents, tick: 110, type: 0x9, key: 62) &&
        hasChannel(orphanEvents, tick: 100, type: 0x8, key: 63) &&
        hasChannel(orphanEvents, tick: 100, type: 0x9, key: 64) &&
        hasChannel(orphanEvents, tick: 110, type: 0x9, key: 65),
        cppID: "editcheck/EditCheckTest::timeRangeSignatureAndOrphans",
        message: "orphan note bytes use half-open remove and pinned seam ordering")
}

@MainActor
private func xcmdTimeTraffic(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 10, status: 0xB0, data0: Xcmd.selectorController, data1: 0x08),
        .channel(tick: 12, status: 0xB0, data0: Xcmd.payloadController, data1: 40),
        .channel(tick: 30, status: 0xB0, data0: Xcmd.selectorController, data1: 0x2A),
        .channel(tick: 31, status: 0xB0, data0: Xcmd.payloadController, data1: 99),
        .channel(tick: 40, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 44, status: 0x90, data0: 60),
    ], endTick: 60)]))
    let scope = TimeScope(lanes: [TimeScope.ScopedLane(
        track: 0, lane: .controller(Xcmd.echoVolumeLane))])
    report.expect(document.duplicateTime(TimeRange(startTick: 10, endTick: 20), scope: scope),
                  cppID: "automation-domain/AutomationDomainTest::xcmdRangeMoves",
                  message: "XCMD lane duplicate reconciles through epoch planner")
    report.expectEqual(["12:40", "22:40"], document.lanePoints(
        track: 0, lane: .controller(Xcmd.echoVolumeLane)).map(pointShape),
        cppID: "automation-domain/AutomationDomainTest::xcmdCanonicalEdits",
        what: "known copied points rebuild canonically")
    let assessment = Xcmd.assess(xcmdTraffic(document.rawChunks[0]))
    report.expect(assessment.blocks.contains { $0.kind == .unknownSelectorEpoch && $0.payloadCount == 1 },
                  cppID: "automation-domain/AutomationDomainTest::xcmdOccurrencesAndOpaqueProtection",
                  message: "unselected opaque epoch remains byte-exact")
    let beforeCut = bytes(document)
    _ = document.removeTime(TimeRange(startTick: 20, endTick: 25), scope: scope)
    report.expect(!document.lanePoints(track: 0, lane: .controller(Xcmd.echoVolumeLane))
        .contains { $0.tick == 22 },
        cppID: "automation-domain/AutomationDomainTest::xcmdRangeRemoveOnly",
        message: "range cut removes copied logical point")
    report.expect(document.notes(in: 0).count == 1,
                  cppID: "automation-domain/AutomationDomainTest::xcmdSweepPreservesNotes",
                  message: "lane-only XCMD sweep preserves notes")
    _ = document.history.undoDocument()
    report.expectEqual(beforeCut, bytes(document),
                       cppID: "automation-domain/AutomationDomainTest::xcmdTimeRangeCuts",
                       what: "XCMD cut is one reversible history entry")

    let expansion = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 20),
    ]), trackBudget: 2)
    let xcmdEdit = RangeEdit(minimumEngineTrackCount: 2,
        addPoints: [RangeEdit.LaneInsertion(track: 1,
            lane: .controller(Xcmd.echoLengthLane),
            points: [LaneWrite(tick: 5, value: 64)])])
    report.expect(expansion.applyRangeEdit(xcmdEdit) &&
        expansion.lanePoints(track: 1, lane: .controller(Xcmd.echoLengthLane)).count == 1,
        cppID: "automation-domain/AutomationDomainTest::xcmdExpansionPaste",
        message: "track expansion builds descriptor traffic through the canonical planner")
}

@MainActor
private func clipboardRangeScenarios(_ report: CheckReport) {
    let merge = timeDocument()
    _ = try? merge.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 48, pitch: 64, duration: 24, velocity: 100),
    ])
    let source = merge.notes(in: 0).first!
    let before = bytes(merge)
    let edit = RangeEdit(removeNotes: [source], addNotes: [
        NewNote(track: 0, tick: 24, pitch: 60, duration: 12, velocity: 120),
        NewNote(track: 0, tick: 36, pitch: 60, duration: 12, velocity: 100),
    ])
    _ = merge.applyRangeEdit(edit)
    report.expectEqual(["24:60:12", "36:60:12", "48:64:24"],
                       merge.notes(in: 0).map(noteShape),
                       cppID: "clipcheck/ClipCheckTest::mergeTimeRangeAndUndo",
                       what: "merge writes the scaled time-range payload atomically")
    _ = merge.history.undoDocument()
    report.expectEqual(before, bytes(merge),
                       cppID: "clipcheck/ClipCheckTest::mergeTimeRangeAndUndo",
                       what: "clipboard merge has one undo step")

    let empty = timeDocument()
    let revision = empty.revision
    report.expect(!empty.applyRangeEdit(RangeEdit()) && empty.revision == revision,
                  cppID: "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop",
                  message: "empty lane payload is a true no-op")

    let tiled = timeDocument()
    _ = tiled.applyRangeEdit(RangeEdit(addNotes: [
        NewNote(track: 0, tick: 0, pitch: 60, duration: 24, velocity: 100),
    ]))
    _ = tiled.applyRangeEdit(RangeEdit(addNotes: [
        NewNote(track: 0, tick: 96, pitch: 60, duration: 24, velocity: 100),
    ]))
    _ = tiled.history.undoDocument()
    report.expectEqual([Tick(0)], tiled.notes(in: 0).map(\.tick),
                       cppID: "clipcheck/ClipCheckTest::tiledTimePasteUndoesOneTileAtATime",
                       what: "each tile is a separate range transaction")
    _ = tiled.history.undoDocument()
    report.expect(tiled.notes(in: 0).isEmpty,
                  cppID: "clipcheck/ClipCheckTest::tiledTimePasteUndoesOneTileAtATime",
                  message: "second undo removes the first tile")

    let crossTPQN = timeDocument(division: 48)
    _ = crossTPQN.applyRangeEdit(RangeEdit(addNotes: [
        NewNote(track: 0, tick: 24, pitch: 60, duration: 48, velocity: 100),
    ]))
    report.expectEqual(["24:60:48"], crossTPQN.notes(in: 0).map(noteShape),
                       cppID: "clipcheck/ClipCheckTest::crossTpbNotePaste",
                       what: "pre-scaled cross-TPQN payload retains destination duration")
}

@MainActor
private func timeDocument(division: UInt16 = 24, trackBudget: Int = 3) -> SongDocument {
    SongDocument(file: MidiFile(division: division, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 240),
        MidiChunk(events: [.channel(status: 0xC1, data0: 1)], endTick: 240),
    ]), trackBudget: trackBudget)
}

@MainActor
private func bytes(_ document: SongDocument) -> [UInt8] {
    do { return try document.captureSave().bytes }
    catch { return [] }
}

private func xcmdTraffic(_ chunk: MidiChunk) -> [Xcmd.Event] {
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

private func pointShape(_ point: LanePoint) -> String {
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
private func expectNoteTempoOracleParity(_ document: SongDocument, cppID: String, row: String,
                                         report: CheckReport) {
    guard let snapshot = try? document.captureSave() else {
        report.fail(cppID, "\(row): Swift save capture failed")
        return
    }
    var output = Array<CChar>(repeating: 0, count: 16_384)
    let count = snapshot.bytes.withUnsafeBufferPointer { bytes in
        output.withUnsafeMutableBufferPointer { buffer in
            oracle_document_summary(bytes.baseAddress, bytes.count,
                                    buffer.baseAddress, buffer.count)
        }
    }
    guard count >= 0 else {
        report.fail(cppID, "\(row): frozen C++ document observation failed")
        return
    }
    let oracle = String(decoding: output.prefix(Int(count)).map { UInt8(bitPattern: $0) },
                        as: UTF8.self)
    var parts: [String] = ["tempo=\(document.state.tempo.count)"]
    for track in 0..<document.engineTracks.usedTrackCount {
        for note in document.notes(in: track) {
            parts.append("n=\(track),\(note.tick),\(note.duration),\(note.pitch),\(note.velocity),\(note.isUnterminated ? 1 : 0)")
        }
    }
    report.expectEqual(oracle, parts.joined(separator: ";"), cppID: cppID, what: row)
}
