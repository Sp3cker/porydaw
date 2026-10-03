import Foundation
import PorydawCore

@MainActor
private final class XcmdRangeFixture {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 9216),
    ]))

    struct Snapshot {
        let bytes: [UInt8]
        let revision: UInt64
        let identity: DocumentIdentity
    }

    struct CcByte: Equatable {
        let tick: Tick
        let controller: UInt8
        let value: UInt8

        init(_ tick: Tick, _ controller: UInt8, _ value: UInt8) {
            self.tick = tick
            self.controller = controller
            self.value = value
        }
    }

    var snapshot: Snapshot {
        do {
            return Snapshot(bytes: try document.captureSave().bytes, revision: document.revision,
                            identity: document.history.currentIdentity)
        } catch {
            preconditionFailure("in-memory XCMD fixture could not be saved: \(error)")
        }
    }

    func oneEdit(_ before: Snapshot) -> Bool {
        document.revision == before.revision + 1 && document.history.currentIdentity != before.identity
    }

    func undoToRoot(_ root: Snapshot) -> Bool {
        while document.history.canUndo {
            guard document.history.undoDocument() else { return false }
        }
        return snapshot.bytes == root.bytes && snapshot.identity == root.identity
    }

    func setLane(_ lane: UInt8, _ points: [(Tick, Int)]) {
        document.writeLane(track: 0, lane: .controller(lane), from: 0,
                           through: TimeDefaults.noTick,
                           points: points.map { LaneWrite(tick: $0.0, value: $0.1) })
    }

    func insertCc(_ tick: Tick, _ controller: UInt8, _ value: UInt8) {
        document.insertRawEvent(chunk: 0, event: .channel(tick: tick, status: 0xB0,
                                                          data0: controller, data1: value))
    }

    func clearXcmd() {
        setLane(Xcmd.echoVolumeLane, [])
        setLane(Xcmd.echoLengthLane, [])
    }

    func seedBaseline() {
        setLane(10, [(0, 80), (384, 110)])
        setLane(7, [(0, 64), (288, 48)])
    }

    func points(_ lane: UInt8, track: Int = 0) -> [LanePoint] {
        document.lanePoints(track: track, lane: .controller(lane))
    }

    func values(_ lane: UInt8, track: Int = 0) -> [String] {
        points(lane, track: track).map(coreTimePointShape)
    }

    func ccChain(track: Int = 0) -> [CcByte] {
        let tracks = document.engineTracks.tracks
        let chunks = document.rawChunks
        guard tracks.indices.contains(track), let chunk = tracks[track].midiChunk,
              chunks.indices.contains(chunk) else { return [] }
        return chunks[chunk].events.compactMap { event in
            guard case let .channel(status, controller, value) = event.payload,
                  status >> 4 == 0xB,
                  controller == 7 || controller == 10 ||
                  controller == Xcmd.selectorController || controller == Xcmd.payloadController ||
                  controller == Xcmd.alternatePayloadController else { return nil }
            return CcByte(event.tick, controller, value)
        }
    }

    func xcmdBytes(at tick: Tick, track: Int = 0) -> [CcByte] {
        ccChain(track: track).filter {
            $0.tick == tick && $0.controller != 7 && $0.controller != 10
        }
    }
}

@MainActor
func coreTimeXcmdRangeEdits(_ report: CheckReport) {
    xcmdTimeRangeCuts(report)
    xcmdRangeRemoveOnly(report)
    xcmdRangeMoves(report)
    xcmdExpansionPaste(report)
}

@MainActor
private func xcmdTimeRangeCuts(_ report: CheckReport) {
    let cppID = "automation-domain/AutomationDomainTest::xcmdTimeRangeCuts"
    let fixture = XcmdRangeFixture()
    let document = fixture.document
    fixture.setLane(Xcmd.echoVolumeLane, [(96, 34)])
    fixture.setLane(Xcmd.echoLengthLane, [(96, 17)])
    let rangeBefore = fixture.snapshot
    let range = TimeRange(startTick: 96, endTick: 192)
    let volumeScope = TimeScope(lanes: [.init(track: 0, lane: .controller(Xcmd.echoVolumeLane))])
    report.expect(document.removeTime(range, scope: volumeScope), cppID: cppID,
                  message: "A029 volume-scoped cut changes the document")
    report.expectEqual(expected: [String](), actual: fixture.values(Xcmd.echoVolumeLane), cppID: cppID,
                       what: "A030 volume is empty after the scoped cut")
    report.expectEqual(expected: [XcmdRangeFixture.CcByte(96, Xcmd.selectorController, 0x09),
                        .init(96, Xcmd.payloadController, 17)], actual: fixture.xcmdBytes(at: 96),
                       cppID: cppID, what: "A031 the scoped cut retains length bytes at tick 96")
    report.expect(document.history.undoDocument() && fixture.snapshot.bytes == rangeBefore.bytes,
                  cppID: cppID, message: "A032 undo restores the pre-cut bytes")

    guard document.history.redoDocument(), document.history.undoDocument() else {
        report.fail(cppID, "scoped cut redo and undo before whole-song cut failed")
        return
    }
    fixture.clearXcmd()
    fixture.setLane(Xcmd.echoVolumeLane, [(96, 34)])
    fixture.setLane(Xcmd.echoLengthLane, [(96, 17), (192, 18)])
    let cutBefore = fixture.snapshot
    report.expect(document.removeTime(range, scope: TimeScope(wholeSong: true)), cppID: cppID,
                  message: "A033 whole-song cut changes the document")
    report.expectEqual(expected: [String](), actual: fixture.values(Xcmd.echoVolumeLane), cppID: cppID,
                       what: "A034 whole-song cut removes volume")
    report.expectEqual(expected: ["96:18"], actual: fixture.values(Xcmd.echoLengthLane), cppID: cppID,
                       what: "A035 surviving length reanchors to the cut edge")
    report.expectEqual(expected: [XcmdRangeFixture.CcByte(96, Xcmd.selectorController, 0x09),
                        .init(96, Xcmd.payloadController, 18)], actual: fixture.xcmdBytes(at: 96),
                       cppID: cppID, what: "A036 reanchored length has canonical bytes")
    report.expect(document.history.undoDocument() && fixture.snapshot.bytes == cutBefore.bytes,
                  cppID: cppID, message: "A037 undo restores the whole-song cut bytes")
    guard document.history.redoDocument() else {
        report.fail(cppID, "whole-song cut redo failed")
        return
    }
    report.expectEqual(expected: [String](), actual: fixture.values(Xcmd.echoVolumeLane), cppID: cppID,
                       what: "A038 redo again removes volume")
    report.expectEqual(expected: ["96:18"], actual: fixture.values(Xcmd.echoLengthLane), cppID: cppID,
                       what: "A039 redo reanchors length at tick 96")
}

@MainActor
private func xcmdRangeRemoveOnly(_ report: CheckReport) {
    let cppID = "automation-domain/AutomationDomainTest::xcmdRangeRemoveOnly"
    let fixture = XcmdRangeFixture()
    let document = fixture.document
    fixture.setLane(Xcmd.echoVolumeLane, [(96, 34), (192, 35)])
    fixture.setLane(Xcmd.echoLengthLane, [(96, 17)])
    fixture.seedBaseline()
    let before = fixture.snapshot
    guard let volume = fixture.points(Xcmd.echoVolumeLane).first,
          let length = fixture.points(Xcmd.echoLengthLane).first else {
        report.fail(cppID, "remove-only fixture did not project both points at tick 96")
        return
    }
    let removed = [volume, length]
    let applied = document.applyRangeEdit(RangeEdit(removePoints: removed))
    report.expect(applied && fixture.oneEdit(before), cppID: cppID,
                  message: "A043 remove-only range edit is one document edit")
    let after = fixture.snapshot
    report.expectEqual(expected: ["192:35"], actual: fixture.values(Xcmd.echoVolumeLane), cppID: cppID,
                       what: "A044 remove-only retains the later volume point")
    report.expectEqual(expected: [String](), actual: fixture.values(Xcmd.echoLengthLane), cppID: cppID,
                       what: "A045 remove-only clears length")
    report.expectEqual(expected: [XcmdRangeFixture.CcByte(0, 0x0A, 80),
                        .init(0, 0x07, 64),
                        .init(192, Xcmd.selectorController, 0x08),
                        .init(192, Xcmd.payloadController, 35),
                        .init(288, 0x07, 48),
                        .init(384, 0x0A, 110)], actual: fixture.ccChain(), cppID: cppID,
                       what: "A046 remove-only preserves baseline CC and later volume byte order")
    report.expect(document.history.undoDocument() && fixture.snapshot.bytes == before.bytes,
                  cppID: cppID, message: "A047 remove-only undo restores bytes")
    report.expect(document.history.redoDocument() && fixture.snapshot.bytes == after.bytes,
                  cppID: cppID, message: "A048 remove-only redo restores edited bytes")
}

@MainActor
private func xcmdRangeMoves(_ report: CheckReport) {
    let cppID = "automation-domain/AutomationDomainTest::xcmdRangeMoves"
    let fixture = XcmdRangeFixture()
    let document = fixture.document
    fixture.setLane(Xcmd.echoLengthLane, [(96, 17), (192, 18)])
    fixture.setLane(Xcmd.echoVolumeLane, [(192, 34)])
    fixture.seedBaseline()
    let leftBefore = fixture.snapshot
    let movedLeft = document.moveRange(notes: [], points: fixture.points(Xcmd.echoVolumeLane), by: -48)
    report.expect(movedLeft && fixture.oneEdit(leftBefore), cppID: cppID,
                  message: "A049 left range move is one document edit")
    let leftAfter = fixture.snapshot
    report.expectEqual(expected: [XcmdRangeFixture.CcByte(0, 0x0A, 80),
                        .init(0, 0x07, 64),
                        .init(96, Xcmd.selectorController, 0x09),
                        .init(96, Xcmd.payloadController, 17),
                        .init(144, Xcmd.selectorController, 0x08),
                        .init(144, Xcmd.payloadController, 34),
                        .init(192, Xcmd.selectorController, 0x09),
                        .init(192, Xcmd.payloadController, 18),
                        .init(288, 0x07, 48),
                        .init(384, 0x0A, 110)], actual: fixture.ccChain(), cppID: cppID,
                       what: "A050 left move rebuilds length and volume in original byte order")
    report.expect(document.history.undoDocument() && fixture.snapshot.bytes == leftBefore.bytes,
                  cppID: cppID, message: "A051 left range move undo restores bytes")
    report.expect(document.history.redoDocument() && fixture.snapshot.bytes == leftAfter.bytes,
                  cppID: cppID, message: "A052 left range move redo restores bytes")

    fixture.clearXcmd()
    fixture.setLane(Xcmd.echoLengthLane, [(96, 17), (192, 18)])
    fixture.setLane(Xcmd.echoVolumeLane, [(96, 34)])
    let rightBefore = fixture.snapshot
    let movedRight = document.moveRange(notes: [], points: fixture.points(Xcmd.echoVolumeLane), by: 96)
    report.expect(movedRight && fixture.oneEdit(rightBefore), cppID: cppID,
                  message: "A053 right range move is one document edit")
    let rightAfter = fixture.snapshot
    report.expectEqual(expected: [XcmdRangeFixture.CcByte(0, 0x0A, 80),
                        .init(0, 0x07, 64),
                        .init(96, Xcmd.selectorController, 0x09),
                        .init(96, Xcmd.payloadController, 17),
                        .init(192, Xcmd.selectorController, 0x09),
                        .init(192, Xcmd.payloadController, 18),
                        .init(192, Xcmd.selectorController, 0x08),
                        .init(192, Xcmd.payloadController, 34),
                        .init(288, 0x07, 48),
                        .init(384, 0x0A, 110)], actual: fixture.ccChain(), cppID: cppID,
                       what: "A054 right move places the length pair before equal-tick volume")
    report.expect(document.history.undoDocument() && fixture.snapshot.bytes == rightBefore.bytes,
                  cppID: cppID, message: "A055 right range move undo restores bytes")
    report.expect(document.history.redoDocument() && fixture.snapshot.bytes == rightAfter.bytes,
                  cppID: cppID, message: "A056 right range move redo restores bytes")

    let mixed = XcmdRangeFixture()
    mixed.setLane(Xcmd.echoLengthLane, [(192, 18)])
    mixed.setLane(Xcmd.echoVolumeLane, [(96, 34)])
    mixed.setLane(7, [(96, 48)])
    let mixedBefore = mixed.snapshot
    let moving = mixed.points(Xcmd.echoVolumeLane) + mixed.points(7)
    report.expect(mixed.document.moveRange(notes: [], points: moving, by: 96),
                  cppID: cppID, message: "logical XCMD and ordinary CC move together")
    report.expectEqual(expected: [XcmdRangeFixture.CcByte(192, Xcmd.selectorController, 0x09),
                        .init(192, Xcmd.payloadController, 18),
                        .init(192, Xcmd.selectorController, 0x08),
                        .init(192, Xcmd.payloadController, 34),
                        .init(192, 7, 48)], actual: mixed.ccChain(), cppID: cppID,
                       what: "same-tick logical XCMD bytes precede the moved ordinary CC")
    report.expect(mixed.document.history.undoDocument() && mixed.snapshot.bytes == mixedBefore.bytes,
                  cppID: cppID, message: "mixed-lane move undo restores original MIDI bytes")
}

@MainActor
private func xcmdExpansionPaste(_ report: CheckReport) {
    let cppID = "automation-domain/AutomationDomainTest::xcmdExpansionPaste"
    let fixture = XcmdRangeFixture()
    let document = fixture.document
    let newTrack = document.engineTracks.usedTrackCount
    let before = fixture.snapshot
    let edit = RangeEdit(minimumEngineTrackCount: newTrack + 1,
                         addNotes: [NewNote(track: newTrack, tick: 0, pitch: 60,
                                            duration: 96, velocity: 100)],
                         addPoints: [RangeEdit.LaneInsertion(
                             track: newTrack, lane: .controller(Xcmd.echoVolumeLane),
                             points: [LaneWrite(tick: 96, value: 34)])])
    let applied = document.applyRangeEdit(edit)
    report.expect(applied && fixture.oneEdit(before), cppID: cppID,
                  message: "A057 expansion paste is one document edit")
    let after = fixture.snapshot
    report.expectEqual(expected: newTrack + 1, actual: document.engineTracks.usedTrackCount, cppID: cppID,
                       what: "A058 expansion paste grows the used engine tracks")
    report.expectEqual(expected: ["96:34"], actual: fixture.values(Xcmd.echoVolumeLane, track: newTrack), cppID: cppID,
                       what: "A059 expanded track projects the inserted volume point")
    report.expectEqual(expected: [XcmdRangeFixture.CcByte(96, Xcmd.selectorController, 0x08),
                        .init(96, Xcmd.payloadController, 34)], actual: fixture.ccChain(track: newTrack),
                       cppID: cppID, what: "A060 expanded track has its canonical XCMD byte pair")
    report.expect(document.history.undoDocument() && fixture.snapshot.bytes == before.bytes,
                  cppID: cppID, message: "A061 expansion paste undo restores bytes")
    report.expect(document.history.redoDocument() && fixture.snapshot.bytes == after.bytes,
                  cppID: cppID, message: "A062 expansion paste redo restores edited bytes")
}
