import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawProjectService

@MainActor
func runTimeEditsSuite(_ report: CheckReport) {
    rangeEditing(report)
    rangeMovement(report)
    removalAndSeams(report)
    insertionAndBoundaries(report)
    duplicationAndGlobals(report)
    xcmdTimeTraffic(report)
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
private func runClipboardEditingSuite(_ report: CheckReport) {
    noteClipboardSemantics(report)
    crossTpbClipboardPaste(report)
    timeRangeClipboardCopyAndExpansion(report)
    timeRangeClipboardMerge(report)
    emptyAndTiledClipboardPaste(report)
    rangeClipboardDeleteAndCut(report)
}

@MainActor
private func noteClipboardSemantics(_ report: CheckReport) {
    let crossSource = clipboardDocument()
    guard let crossIDs = try? crossSource.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 36, pitch: 64, duration: 12, velocity: 80),
    ]), let crossClip = ClipboardSemantics.copyNotes(
        crossIDs.compactMap(crossSource.note), from: 0, unterminatedDuration: 6)
    else {
        report.fail("clipcheck/ClipCheckTest::crossViewNoteCopyPaste",
                    "cross-view selected-note copy failed")
        return
    }
    let crossExpected = PorydawClip(tracks: [ClipTrack(track: 0, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
        ClipNote(relTick: 12, key: 64, duration: 12, velocity: 80),
    ])])
    let crossDecoded = ClipboardCodec.encode(crossClip, ticksPerBeat: 24)
        .flatMap(ClipboardCodec.decode)
    let crossTarget = clipboardDocument(trackCount: 2)
    _ = try? crossTarget.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 24, velocity: 90),
    ])
    let crossResult = crossDecoded.flatMap {
        ClipboardSemantics.paste($0.clip, at: 48, selectedTrack: 1, into: crossTarget)
    }
    report.expect(crossDecoded == DecodedPorydawClip(
        ticksPerBeat: 24, clip: crossExpected) &&
        crossTarget.notes(in: 0).map(noteShape) == ["0:70:24"] &&
        crossTarget.notes(in: 1).map(noteShape) == ["48:60:24", "60:64:12"] &&
        crossResult?.insertedNoteIDs.count == 2 && crossResult?.nextCursor == 72,
        cppID: "clipcheck/ClipCheckTest::crossViewNoteCopyPaste",
        message: "exact zero-span 24-TPQN payload retargets across documents without changing the source track")

    let sameDocument = clipboardDocument()
    guard let sameIDs = try? sameDocument.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
    ]), let sameClip = ClipboardSemantics.copyNotes(
        sameIDs.compactMap(sameDocument.note), from: 0, unterminatedDuration: 6)
    else {
        report.fail("clipcheck/ClipCheckTest::sameViewNoteCopyPaste",
                    "same-view selected-note copy failed")
        return
    }
    let sameExpected = PorydawClip(tracks: [ClipTrack(track: 0, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
    ])])
    let sameDecoded = ClipboardCodec.encode(sameClip, ticksPerBeat: 24)
        .flatMap(ClipboardCodec.decode)
    let sameResult = sameDecoded.flatMap {
        ClipboardSemantics.paste($0.clip, at: 48, selectedTrack: 0, into: sameDocument)
    }
    report.expect(sameDecoded == DecodedPorydawClip(
        ticksPerBeat: 24, clip: sameExpected) &&
        sameDocument.notes(in: 0).map(noteShape) == ["24:60:24", "48:60:24"] &&
        sameResult?.insertedNoteIDs.count == 1 && sameResult?.nextCursor == 72,
        cppID: "clipcheck/ClipCheckTest::sameViewNoteCopyPaste",
        message: "exact zero-span 24-TPQN payload pastes in the source document and preserves the original note")
}

@MainActor
private func crossTpbClipboardPaste(_ report: CheckReport) {
    let source = clipboardDocument()
    guard let ids = try? source.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 24, velocity: 100),
    ]), let id = ids.first, let note = source.note(id),
          let copied = ClipboardSemantics.copyNotes([note], from: 0, unterminatedDuration: 6)
    else {
        report.fail("clipcheck/ClipCheckTest::crossTpbNotePaste", "source note copy failed")
        return
    }
    let scaled = ClipboardCodec.rescale(copied, sourceTicksPerBeat: 24,
                                        destinationTicksPerBeat: 48)
    let target = clipboardDocument(division: 48)
    _ = try? target.addNotes([
        NewNote(track: 0, tick: 0, pitch: 70, duration: 24, velocity: 90),
    ])
    let before = bytes(target)
    let result = ClipboardSemantics.paste(scaled, at: 24, selectedTrack: 0, into: target)
    let forward = target.notes(in: 0).map(noteShape)
    let undone = target.history.undoDocument() && bytes(target) == before
    report.expect(forward == ["0:70:24", "24:60:48"] &&
        result?.nextCursor == 72 && undone,
        cppID: "clipcheck/ClipCheckTest::crossTpbNotePaste",
        message: "TPQN rescaling feeds production note paste and records one reversible edit")
}

@MainActor
private func timeRangeClipboardCopyAndExpansion(_ report: CheckReport) {
    let single = clipboardDocument()
    _ = try? single.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 24, velocity: 100),
    ])
    let singleClip = ClipboardSemantics.extractTimeRange(
        TimeRange(startTick: 0, endTick: 96), scope: TimeScope(tracks: [0]),
        from: single, unterminatedDuration: 6)
    let singleExpected = PorydawClip(
        span: 96,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
        ])],
        lanes: [ClipLane(track: 0, cc: TimeDefaults.laneCCVoice, points: [
            ClipLanePoint(relTick: 0, value: 0),
        ])])
    report.expectEqual(singleExpected, singleClip,
        cppID: "clipcheck/ClipCheckTest::timeSelectionCopy",
        what: "track-scoped range clip including the initial voice seed")

    let source = clipboardDocument(trackCount: 3)
    for (track, tick, key, duration, velocity, laneTick, laneValue) in [
        (0, Tick(12), UInt8(60), Tick(12), UInt8(90), Tick(18), 11),
        (1, Tick(24), UInt8(64), Tick(24), UInt8(100), Tick(30), 22),
        (2, Tick(36), UInt8(68), Tick(36), UInt8(110), Tick(42), 33),
    ] {
        _ = try? source.addNotes([
            NewNote(track: track, tick: tick, pitch: key, duration: duration,
                    velocity: velocity),
        ])
        source.writeLane(track: track, lane: .controller(1), from: laneTick,
                         through: laneTick, points: [LaneWrite(tick: laneTick, value: laneValue)])
    }
    guard let clip = ClipboardSemantics.extractTimeRange(
        TimeRange(startTick: 0, endTick: 96), scope: TimeScope(tracks: [0, 1, 2]),
        from: source, unterminatedDuration: 6)
    else {
        report.fail("clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
                    "scoped extraction failed")
        return
    }
    let expected = PorydawClip(
        span: 96,
        tracks: [
            ClipTrack(track: 0, notes: [
                ClipNote(relTick: 12, key: 60, duration: 12, velocity: 90),
            ]),
            ClipTrack(track: 1, notes: [
                ClipNote(relTick: 24, key: 64, duration: 24, velocity: 100),
            ]),
            ClipTrack(track: 2, notes: [
                ClipNote(relTick: 36, key: 68, duration: 36, velocity: 110),
            ]),
        ],
        lanes: [
            ClipLane(track: 0, cc: 1, points: [ClipLanePoint(relTick: 18, value: 11)]),
            ClipLane(track: 0, cc: TimeDefaults.laneCCVoice,
                     points: [ClipLanePoint(relTick: 0, value: 0)]),
            ClipLane(track: 1, cc: 1, points: [ClipLanePoint(relTick: 30, value: 22)]),
            ClipLane(track: 1, cc: TimeDefaults.laneCCVoice,
                     points: [ClipLanePoint(relTick: 0, value: 0)]),
            ClipLane(track: 2, cc: 1, points: [ClipLanePoint(relTick: 42, value: 33)]),
            ClipLane(track: 2, cc: TimeDefaults.laneCCVoice,
                     points: [ClipLanePoint(relTick: 0, value: 0)]),
        ])
    let target = clipboardDocument(trackBudget: 3)
    let before = bytes(target)
    let result = ClipboardSemantics.paste(clip, at: 0, selectedTrack: 0, into: target)
    let expanded = target.engineTracks.usedTrackCount == 3 &&
        target.notes(in: 0).map(noteShape) == ["12:60:12"] &&
        target.notes(in: 1).map(noteShape) == ["24:64:24"] &&
        target.notes(in: 2).map(noteShape) == ["36:68:36"] &&
        target.lanePoints(track: 0, lane: .controller(1)).map(pointShape) == ["18:11"] &&
        target.lanePoints(track: 1, lane: .controller(1)).map(pointShape) == ["30:22"] &&
        target.lanePoints(track: 2, lane: .controller(1)).map(pointShape) == ["42:33"] &&
        target.lanePoints(track: 0, lane: .voice).map(pointShape) == ["0:0"] &&
        target.lanePoints(track: 1, lane: .voice).map(pointShape) == ["0:0"] &&
        target.lanePoints(track: 2, lane: .voice).map(pointShape) == ["0:0"]
    let oneUndo = target.history.undoDocument() &&
        target.engineTracks.usedTrackCount == 1 && bytes(target) == before
    report.expect(clip == expected && expanded && result?.nextCursor == 96 && oneUndo,
        cppID: "clipcheck/ClipCheckTest::scopedRangeCopyPasteCreatesTracks",
        message: "multi-track range paste creates tracks, preserves lanes and voices, and undoes atomically")
}

@MainActor
private func timeRangeClipboardMerge(_ report: CheckReport) {
    let document = clipboardDocument()
    _ = try? document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 48, pitch: 64, duration: 24, velocity: 100),
    ])
    document.writeLane(track: 0, lane: .controller(1), from: 36, through: 36,
                       points: [LaneWrite(tick: 36, value: 40)])
    document.writeLane(track: 0, lane: .controller(1), from: 60, through: 60,
                       points: [LaneWrite(tick: 60, value: 70)])
    document.writeLane(track: 0, lane: .controller(1), from: 96, through: 96,
                       points: [LaneWrite(tick: 96, value: 40)])
    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 0, microsecondsPerQuarterNote: 500_000),
        TempoPoint(tick: 25, microsecondsPerQuarterNote: 600_000),
        TempoPoint(tick: 60, microsecondsPerQuarterNote: 700_000),
    ]))
    let before = bytes(document)
    let source = PorydawClip(
        span: 48,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 0, key: 60, duration: 24, velocity: 120),
        ])],
        lanes: [ClipLane(track: 0, cc: 1, points: [
            ClipLanePoint(relTick: 23, value: 110),
            ClipLanePoint(relTick: 24, value: 120),
        ])],
        tempo: [
            ClipTempo(relTick: 1, microsecondsPerQuarterNote: 300_000),
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 400_000),
        ])
    let clip = ClipboardCodec.rescale(source, sourceTicksPerBeat: 48,
                                      destinationTicksPerBeat: 24)
    let result = ClipboardSemantics.paste(clip, at: 24, selectedTrack: 0, into: document)
    let merged = document.notes(in: 0).map(noteShape) ==
            ["24:60:12", "36:60:12", "48:64:24"] &&
        document.lanePoints(track: 0, lane: .controller(1)).map(pointShape) ==
            ["36:120", "60:70", "96:40"] &&
        document.state.tempo.map { "\($0.tick):\($0.microsecondsPerQuarterNote)" } ==
            ["0:500000", "25:400000", "60:700000"] &&
        result?.nextCursor == 48
    let oneUndo = document.history.undoDocument() && bytes(document) == before
    report.expect(merged && oneUndo,
        cppID: "clipcheck/ClipCheckTest::mergeTimeRangeAndUndo",
        message: "one production range merge applies last-wins exact-tick lane and tempo replacement and undoes atomically")
}

@MainActor
private func emptyAndTiledClipboardPaste(_ report: CheckReport) {
    let emptyDocument = clipboardDocument()
    _ = try? emptyDocument.addNotes([
        NewNote(track: 0, tick: 24, pitch: 62, duration: 24, velocity: 100),
    ])
    emptyDocument.writeLane(track: 0, lane: .controller(7), from: 144, through: 144,
                            points: [LaneWrite(tick: 144, value: 90)])
    let emptyBefore = bytes(emptyDocument)
    let emptyIdentity = emptyDocument.history.currentIdentity
    let empty = PorydawClip(span: 48, lanes: [ClipLane(track: 0, cc: 7, points: [])])
    let emptyResult = ClipboardSemantics.paste(
        empty, at: 120, selectedTrack: 0, into: emptyDocument)
    report.expect(emptyResult == nil && bytes(emptyDocument) == emptyBefore &&
        emptyDocument.history.currentIdentity == emptyIdentity,
        cppID: "clipcheck/ClipCheckTest::emptyLaneMergeIsNoop",
        message: "an empty lane merge returns no cursor and changes neither document nor history")

    let tiled = clipboardDocument()
    let tile = PorydawClip(span: 96, tracks: [ClipTrack(track: 0, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
    ])])
    let first = ClipboardSemantics.paste(tile, at: 0, selectedTrack: 0, into: tiled)
    let second = ClipboardSemantics.paste(
        tile, at: first?.nextCursor ?? 0, selectedTrack: 0, into: tiled)
    let forward = tiled.notes(in: 0).map(noteShape)
    let firstUndo = tiled.history.undoDocument() &&
        tiled.notes(in: 0).map(noteShape) == ["0:60:24"]
    let secondUndo = tiled.history.undoDocument() && tiled.notes(in: 0).isEmpty
    report.expect(forward == ["0:60:24", "96:60:24"] &&
        first?.nextCursor == 96 && second?.nextCursor == 192 && firstUndo && secondUndo,
        cppID: "clipcheck/ClipCheckTest::tiledTimePasteUndoesOneTileAtATime",
        message: "time paste advances by span and each tile is one undo entry")
}

@MainActor
private func rangeClipboardDeleteAndCut(_ report: CheckReport) {
    let document = clipboardDocument()
    _ = try? document.addNotes([
        NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100),
        NewNote(track: 0, tick: 96, pitch: 64, duration: 24, velocity: 80),
    ])
    document.writeLane(track: 0, lane: .voice, from: 24, through: 24,
                       points: [LaneWrite(tick: 24, value: 3)])
    document.writeLane(track: 0, lane: .voice, from: 96, through: 96,
                       points: [LaneWrite(tick: 96, value: 5)])
    document.editTempo(TempoEdit(add: [
        TempoPoint(tick: 24, microsecondsPerQuarterNote: 600_000),
        TempoPoint(tick: 96, microsecondsPerQuarterNote: 400_000),
    ]))
    let range = TimeRange(startTick: 0, endTick: 48)
    let scope = TimeScope(tracks: [0], tempo: true)
    let before = bytes(document)
    let deleted = ClipboardSemantics.deleteTimeRange(range, scope: scope, from: document)
    let afterDelete = document.notes(in: 0).map(noteShape) == ["96:64:24"] &&
        document.lanePoints(track: 0, lane: .voice).map(pointShape) == ["96:5"] &&
        document.state.tempo.map { $0.tick } == [96]
    let deleteUndo = document.history.undoDocument()
    let restoredAfterDelete = document.notes(in: 0).map(noteShape) ==
            ["24:60:24", "96:64:24"] &&
        document.lanePoints(track: 0, lane: .voice).map(pointShape) ==
            ["0:0", "24:3", "96:5"] &&
        document.state.tempo.map { "\($0.tick):\($0.microsecondsPerQuarterNote)" } ==
            ["24:600000", "96:400000"] &&
        bytes(document) == before

    let cut = ClipboardSemantics.extractTimeRange(
        range, scope: scope, from: document, unterminatedDuration: 6)
    let expectedCut = PorydawClip(
        span: 48,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 24, key: 60, duration: 24, velocity: 100),
        ])],
        lanes: [ClipLane(track: 0, cc: TimeDefaults.laneCCVoice, points: [
            ClipLanePoint(relTick: 0, value: 0),
            ClipLanePoint(relTick: 24, value: 3),
        ])],
        tempo: [ClipTempo(relTick: 24, microsecondsPerQuarterNote: 600_000)])
    let cutDeleted = ClipboardSemantics.deleteTimeRange(range, scope: scope, from: document)
    let afterCut = document.notes(in: 0).map(noteShape) == ["96:64:24"] &&
        document.lanePoints(track: 0, lane: .voice).map(pointShape) == ["96:5"] &&
        document.state.tempo.map { $0.tick } == [96]
    let cutUndo = document.history.undoDocument() && bytes(document) == before
    report.expect(deleted && afterDelete && deleteUndo && restoredAfterDelete &&
        cut == expectedCut && cutDeleted && afterCut && cutUndo,
        cppID: "clipcheck/ClipCheckTest::rangeDeleteCutAndUndo",
        message: "delete and extract-then-delete cut preserve the exact payload and each restore in one undo")
}

@MainActor
private func clipboardDocument(division: UInt16 = 24, trackCount: Int = 1,
                               trackBudget: Int = 16) -> SongDocument {
    SongDocument(file: MidiFile(division: division, chunks: (0..<trackCount).map {
        MidiChunk(events: [.channel(status: 0xC0 | UInt8($0), data0: 0)], endTick: 240)
    }), trackBudget: trackBudget)
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
func runClipboardCodecSuite(_ report: CheckReport) {
    let noteClip = PorydawClip(tracks: [ClipTrack(track: 3, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
        ClipNote(relTick: 12, key: 64, duration: 12, velocity: 80),
    ])])
    let timeClip = PorydawClip(
        span: 96,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
            ClipNote(relTick: 72, key: 67, duration: 12, velocity: 90),
        ])],
        lanes: [
            ClipLane(track: 0, cc: 1, points: [
                ClipLanePoint(relTick: 24, value: 80),
                ClipLanePoint(relTick: 72, value: 32),
            ]),
            ClipLane(track: 0, cc: TimeDefaults.laneCCBend, points: [
                ClipLanePoint(relTick: 48, value: 4_096),
            ]),
            ClipLane(track: 0, cc: 7, points: []),
        ],
        tempo: [
            ClipTempo(relTick: 0, microsecondsPerQuarterNote: 500_000),
            ClipTempo(relTick: 48, microsecondsPerQuarterNote: 400_000),
        ])

    roundTrip(noteClip, ticksPerBeat: 24,
              cppID: "clipmimecheck/ClipMimeTest::codecRoundTrips[plain_note_clip]",
              report: report)
    roundTrip(timeClip, ticksPerBeat: 24,
              cppID: "clipmimecheck/ClipMimeTest::codecRoundTrips[time_clip_with_bend_empty_lane_and_tempo]",
              report: report)

    let routedClip = PorydawClip(span: 24, tracks: [ClipTrack(track: 1, notes: [
        ClipNote(relTick: 0, key: 55, duration: 12, velocity: 70),
    ])])
    let routedCore = ClipboardCodec.encode(routedClip, ticksPerBeat: 24)
        .flatMap(ClipboardCodec.decode)
    let routedScaled = routedCore.map {
        ClipboardCodec.rescale($0.clip, sourceTicksPerBeat: $0.ticksPerBeat,
                               destinationTicksPerBeat: 48)
    }
    report.expect(routedCore?.ticksPerBeat == 24 && routedCore?.clip == routedClip
        && routedScaled?.span == 48
        && routedScaled?.tracks.first?.notes.first?.duration == 24,
        cppID: "clipmimecheck/ClipMimeTest::clipboardRoutesClipMime",
        message: "the production codec and rescaler preserve the route payload; native MIME transport remains a host assertion")

    let malformedKinds = [
        "truncated_json", "garbage_bytes", "wrong_format", "missing_ticks_per_beat",
        "zero_ticks_per_beat", "missing_tracks", "wrong_typed_lanes", "missing_tempo",
        "negative_span", "negative_note_tick", "missing_note_velocity",
        "lane_point_missing_value", "tempo_missing_microseconds", "nonfinite_tick",
    ]
    for kind in malformedKinds {
        report.expect(ClipboardCodec.decode(malformedClipboardPayload(kind)) == nil,
                      cppID: "clipmimecheck/ClipMimeTest::malformedPayloads[\(kind)]",
                      message: "the exact malformed baseline payload is rejected")
    }
    report.expect(ClipboardCodec.decode(Data("not json at all".utf8)) == nil,
                  cppID: "clipmimecheck/ClipMimeTest::malformedCustomMimeReportsDecodeFailure",
                  message: "the production decoder rejects the exact corrupt custom-MIME payload; native failure routing remains a host assertion")

    let upInput = PorydawClip(
        span: 12,
        tracks: [ClipTrack(track: 3, notes: [
            ClipNote(relTick: 6, key: 64, duration: 3, velocity: 91),
        ])],
        lanes: [ClipLane(track: 4, cc: 1, points: [
            ClipLanePoint(relTick: 6, value: -12),
        ])],
        tempo: [ClipTempo(relTick: 6, microsecondsPerQuarterNote: 400_000)])
    let upExpected = PorydawClip(
        span: 24,
        tracks: [ClipTrack(track: 3, notes: [
            ClipNote(relTick: 12, key: 64, duration: 6, velocity: 91),
        ])],
        lanes: [ClipLane(track: 4, cc: 1, points: [
            ClipLanePoint(relTick: 12, value: -12),
        ])],
        tempo: [ClipTempo(relTick: 12, microsecondsPerQuarterNote: 400_000)])
    report.expectEqual(
        upExpected,
        ClipboardCodec.rescale(upInput, sourceTicksPerBeat: 24, destinationTicksPerBeat: 48),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[up_24_to_48]",
        what: "exact up-scaled clip")

    let downInput = PorydawClip(
        span: 1,
        tracks: [ClipTrack(track: 2, notes: [
            ClipNote(relTick: 1, key: 60, duration: 1, velocity: 100),
            ClipNote(relTick: 3, key: 61, duration: 0, velocity: 80),
        ])],
        lanes: [ClipLane(track: 2, cc: 7, points: [
            ClipLanePoint(relTick: 2, value: 20),
            ClipLanePoint(relTick: 1, value: 10),
            ClipLanePoint(relTick: 3, value: 30),
        ])],
        tempo: [
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 500_000),
            ClipTempo(relTick: 1, microsecondsPerQuarterNote: 600_000),
            ClipTempo(relTick: 3, microsecondsPerQuarterNote: 700_000),
        ])
    let downExpected = PorydawClip(
        span: 1,
        tracks: [ClipTrack(track: 2, notes: [
            ClipNote(relTick: 1, key: 60, duration: 1, velocity: 100),
            ClipNote(relTick: 2, key: 61, duration: 0, velocity: 80),
        ])],
        lanes: [ClipLane(track: 2, cc: 7, points: [
            ClipLanePoint(relTick: 1, value: 10),
            ClipLanePoint(relTick: 2, value: 30),
        ])],
        tempo: [
            ClipTempo(relTick: 1, microsecondsPerQuarterNote: 600_000),
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 700_000),
        ])
    report.expectEqual(
        downExpected,
        ClipboardCodec.rescale(downInput, sourceTicksPerBeat: 48, destinationTicksPerBeat: 24),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[down_48_to_24_round_up_last_wins]",
        what: "half-up down-scaled clip with stable last-wins collisions")

    let identityInput = PorydawClip(
        tracks: [ClipTrack(track: 7, notes: [
            ClipNote(relTick: 9, key: 72, duration: 5, velocity: 44),
        ])],
        lanes: [ClipLane(track: 7, cc: 1, points: [
            ClipLanePoint(relTick: 4, value: 1),
            ClipLanePoint(relTick: 4, value: 2),
            ClipLanePoint(relTick: 2, value: 3),
        ])],
        tempo: [
            ClipTempo(relTick: 4, microsecondsPerQuarterNote: 500_000),
            ClipTempo(relTick: 4, microsecondsPerQuarterNote: 600_000),
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 700_000),
        ])
    report.expectEqual(
        identityInput,
        ClipboardCodec.rescale(identityInput, sourceTicksPerBeat: 24,
                               destinationTicksPerBeat: 24),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[same_tpb_is_exact_identity]",
        what: "same-TPB clip including duplicate ordering")

    let saturationInput = PorydawClip(
        span: TimeDefaults.noTick,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: .max, key: 127, duration: .max, velocity: 255),
        ])],
        lanes: [ClipLane(track: 0, cc: 1, points: [
            ClipLanePoint(relTick: .max, value: Int(Int32.min)),
        ])],
        tempo: [ClipTempo(relTick: TimeDefaults.noTick,
                          microsecondsPerQuarterNote: .max)])
    var saturationExpected = saturationInput
    saturationExpected.span = TimeDefaults.maxTick
    saturationExpected.tempo[0].relTick = TimeDefaults.maxTick
    report.expectEqual(
        saturationExpected,
        ClipboardCodec.rescale(saturationInput, sourceTicksPerBeat: 1,
                               destinationTicksPerBeat: .max),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[saturates_without_wrap]",
        what: "saturated clip without wrapping")
}



private func roundTrip(_ clip: PorydawClip, ticksPerBeat: UInt32,
                       cppID: String, report: CheckReport) {
    let decoded = ClipboardCodec.encode(clip, ticksPerBeat: ticksPerBeat)
        .flatMap(ClipboardCodec.decode)
    report.expect(decoded == DecodedPorydawClip(ticksPerBeat: ticksPerBeat, clip: clip),
                  cppID: cppID, message: "codec round-trip preserves payload")
}

private func malformedClipboardPayload(_ kind: String) -> Data {
    if kind == "truncated_json" { return Data("{\"format\": 1".utf8) }
    if kind == "garbage_bytes" { return Data("not json at all".utf8) }
    if kind == "nonfinite_tick" {
        return Data("""
        {"format":1,"ticksPerBeat":24,"span":0,"tracks":[{"track":0,"notes":[{"relTick":NaN,"key":60,"duration":24,"velocity":100}]}],"lanes":[],"tempo":[]}
        """.utf8)
    }
    var payload: [String: Any] = [
        "format": 1,
        "ticksPerBeat": 24,
        "span": 0,
        "wholeLane": false,
        "tracks": [[
            "track": 0,
            "notes": [["relTick": 0, "key": 60, "duration": 24, "velocity": 100]],
        ]],
        "lanes": [],
        "tempo": [],
    ]
    switch kind {
    case "wrong_format":
        payload["format"] = 2
    case "missing_ticks_per_beat":
        payload.removeValue(forKey: "ticksPerBeat")
    case "zero_ticks_per_beat":
        payload["ticksPerBeat"] = 0
    case "missing_tracks":
        payload.removeValue(forKey: "tracks")
    case "wrong_typed_lanes":
        payload["lanes"] = [:]
    case "missing_tempo":
        payload.removeValue(forKey: "tempo")
    case "negative_span":
        payload["span"] = -1
    case "negative_note_tick":
        payload["tracks"] = [[
            "track": 0,
            "notes": [["relTick": -1, "key": 60, "duration": 24, "velocity": 100]],
        ]]
    case "missing_note_velocity":
        payload["tracks"] = [[
            "track": 0,
            "notes": [["relTick": 0, "key": 60, "duration": 24]],
        ]]
    case "lane_point_missing_value":
        payload["lanes"] = [["track": 0, "cc": 1, "points": [[12]]]]
    case "tempo_missing_microseconds":
        payload["tempo"] = [["relTick": 12]]
    default:
        return Data()
    }
    return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
}

