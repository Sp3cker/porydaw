import Foundation
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func rangeMovement(_ report: CheckReport) {
    let document = timeDocument()
    guard
        let ids = try? document.addNotes([
            NewNote(track: 0, tick: 80, pitch: 60, duration: 8, velocity: 90),
            NewNote(track: 0, tick: 92, pitch: 64, duration: 8, velocity: 91),
        ])
    else { return }
    document.writeLane(
        track: 0, lane: .controller(7), from: 80, through: 80,
        points: [LaneWrite(tick: 80, value: 45)])
    document.editTempo(TempoEdit(add: [TempoPoint(tick: 81, microsecondsPerQuarterNote: 600_000)]))
    let notes = ids.compactMap { document.note($0) }
    let lane = document.lanePoints(track: 0, lane: .controller(7))
    let tempo = document.state.tempo.filter { $0.tick == 81 }
    let before = coreTimeBytes(document)
    report.expect(
        document.moveRange(notes: notes, points: lane, by: 12, tempo: tempo),
        cppID: "editcheck/EditCheckTest::rangeMove",
        message: "mixed range move commits")
    report.expectEqual(
        expected: ["92:60:8", "104:64:8"], actual: document.notes(in: 0).map(noteShape),
        cppID: "editcheck/EditCheckTest::rangeMove",
        what: "notes retain duration after exact-byte relocation")
    report.expectEqual(
        expected: ["92:45"], actual: document.lanePoints(track: 0, lane: .controller(7)).map(coreTimePointShape),
        cppID: "editcheck/EditCheckTest::rangeLaneBulk",
        what: "lane event relocates with the range")
    report.expect(
        document.state.tempo.contains { $0.tick == 93 },
        cppID: "editcheck/EditCheckTest::rangeLaneConverge",
        message: "tempo point relocates in the same history entry")
    _ = document.history.undoDocument()
    report.expectEqual(
        expected: before, actual: coreTimeBytes(document),
        cppID: "editcheck/EditCheckTest::rangeMove",
        what: "one undo restores the mixed move")

    let opaque = timeDocument()
    opaque.insertRawEvent(
        chunk: 0,
        event: .systemExclusive(tick: 12, status: 0xF0, data: [0x7D, 4, 5, 0xF7]))
    guard let index = opaque.rawChunks[0].events.firstIndex(where: { $0.isSystemExclusive }) else { return }
    let point = LanePoint(chunk: 0, eventIndex: index, tick: 12, value: 0)
    _ = opaque.moveRange(notes: [], points: [point], by: 5)
    report.expect(
        opaque.rawChunks[0].events.contains {
            $0.tick == 17 && $0.blob == [0x7D, 4, 5, 0xF7]
        }, cppID: "editcheck/EditCheckTest::rangeMove",
        message: "opaque relocation preserves exact payload bytes")

    let headTrim = timeDocument()
    guard
        let headIDs = try? headTrim.addNotes([
            NewNote(track: 0, tick: 50, pitch: 60, duration: 20, velocity: 80),
            NewNote(track: 0, tick: 110, pitch: 60, duration: 30, velocity: 90),
        ]), let headMover = headTrim.note(headIDs[0])
    else {
        report.fail("editcheck/EditCheckTest::rangeMove", "head-trim fixture insertion failed")
        return
    }
    report.expect(
        headTrim.moveRange(notes: [headMover], points: [], by: 50),
        cppID: "editcheck/EditCheckTest::rangeMove",
        message: "moving range trims a stationary note head")
    report.expectEqual(
        expected: ["100:60:20", "120:60:20"], actual: headTrim.notes(in: 0).map(noteShape),
        cppID: "editcheck/EditCheckTest::rangeMove",
        what: "stationary note starts at the moved note end")

    let fullCover = timeDocument()
    guard
        let coverIDs = try? fullCover.addNotes([
            NewNote(track: 0, tick: 50, pitch: 61, duration: 50, velocity: 80),
            NewNote(track: 0, tick: 110, pitch: 61, duration: 20, velocity: 90),
        ]), let coverMover = fullCover.note(coverIDs[0])
    else {
        report.fail("editcheck/EditCheckTest::rangeMove", "full-cover fixture insertion failed")
        return
    }
    report.expect(
        fullCover.moveRange(notes: [coverMover], points: [], by: 50),
        cppID: "editcheck/EditCheckTest::rangeMove",
        message: "moving range fully covers a stationary note")
    report.expectEqual(
        expected: ["100:61:50"], actual: fullCover.notes(in: 0).map(noteShape),
        cppID: "editcheck/EditCheckTest::rangeMove",
        what: "fully covered stationary note is removed")
}
