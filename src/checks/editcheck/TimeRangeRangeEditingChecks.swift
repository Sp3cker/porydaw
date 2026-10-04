import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func rangeEditing(_ report: CheckReport) {
    let document = timeDocument(trackBudget: 3)
    guard
        let originalIDs = try? document.addNotes([
            NewNote(track: 0, tick: 30, pitch: 60, duration: 8, velocity: 90),
            NewNote(track: 0, tick: 42, pitch: 62, duration: 8, velocity: 91),
        ])
    else {
        report.fail("editcheck/EditCheckTest::rangeEdit", "fixture note insertion failed")
        return
    }
    document.writeLane(
        track: 0, lane: .controller(7), from: 30, through: 30,
        points: [LaneWrite(tick: 30, value: 80)])
    document.editTempo(
        TempoEdit(add: [
            TempoPoint(tick: 31, microsecondsPerQuarterNote: 600_000)
        ]))
    let before = coreTimeBytes(document)
    let edit = RangeEdit(
        minimumEngineTrackCount: 3,
        removeNotes: originalIDs.compactMap { document.note($0) },
        removePoints: document.lanePoints(track: 0, lane: .controller(7)),
        addNotes: [NewNote(track: 2, tick: 60, pitch: 65, duration: 8, velocity: 99)],
        addPoints: [
            RangeEdit.LaneInsertion(
                track: 2, lane: .controller(7),
                points: [LaneWrite(tick: 60, value: 60), LaneWrite(tick: 60, value: 70)])
        ],
        removeTempo: [TempoPoint(tick: 31, microsecondsPerQuarterNote: 600_000)],
        addTempo: [TempoPoint(tick: 61, microsecondsPerQuarterNote: 400_000)])
    report.expect(
        document.applyRangeEdit(edit),
        cppID: "editcheck/EditCheckTest::rangeEdit",
        message: "mixed cross-stream range edit commits")
    report.expectEqual(
        expected: 3, actual: document.engineTracks.usedTrackCount,
        cppID: "editcheck/EditCheckTest::rangeEdit",
        what: "range insertion expands tracks under budget")
    report.expectEqual(
        expected: ["60:65:8"], actual: document.notes(in: 2).map(noteShape),
        cppID: "editcheck/EditCheckTest::rangeEdit",
        what: "inserted note lands on expanded track")
    report.expectEqual(
        expected: ["60:60", "60:70"],
        actual: document.lanePoints(track: 2, lane: .controller(7)).map(coreTimePointShape),
        cppID: "editcheck/EditCheckTest::rangeEdit",
        what: "lane insertion shares the atomic candidate")
    report.expectEqual(
        expected: 2, actual: document.lanePoints(track: 2, lane: .controller(7)).count,
        cppID: "editcheck/EditCheckTest::rangeEdit",
        what: "range insertion preserves separate same-tick occurrences")
    report.expect(
        document.state.tempo.contains {
            $0.tick == 61 && $0.microsecondsPerQuarterNote == 400_000
        }, cppID: "editcheck/EditCheckTest::rangeEdit", message: "tempo replacement is atomic")
    _ = document.history.undoDocument()
    report.expectEqual(
        expected: before, actual: coreTimeBytes(document),
        cppID: "editcheck/EditCheckTest::rangeEdit",
        what: "one undo restores every stream and track count")

    let collision = timeDocument(trackBudget: 2)
    let collisionBefore = coreTimeBytes(collision)
    let rejected = RangeEdit(
        minimumEngineTrackCount: 2,
        addNotes: [
            NewNote(track: 1, tick: 10, pitch: 60, duration: 20, velocity: 80),
            NewNote(track: 1, tick: 20, pitch: 60, duration: 20, velocity: 90),
        ],
        addPoints: [
            RangeEdit.LaneInsertion(
                track: 1, lane: .controller(7), points: [LaneWrite(tick: 10, value: 90)])
        ])
    report.expect(
        !collision.applyRangeEdit(rejected) && coreTimeBytes(collision) == collisionBefore,
        cppID: "editcheck/EditCheckTest::rangeEditCollisionRejects",
        message: "conflicting participants reject before track expansion")

    let limited = timeDocument(trackBudget: 1)
    let limitedBefore = coreTimeBytes(limited)
    report.expect(
        !limited.applyRangeEdit(
            RangeEdit(
                minimumEngineTrackCount: 2,
                addNotes: [NewNote(track: 1, tick: 1, pitch: 60, duration: 1, velocity: 90)]))
            && coreTimeBytes(limited) == limitedBefore,
        cppID: "editcheck/EditCheckTest::rangeEditCollisionRejects",
        message: "budget-constrained expansion leaves the prior state intact")

    let progressive = timeDocument()
    _ = try? progressive.addNotes([
        NewNote(track: 0, tick: 0, pitch: 60, duration: 100, velocity: 91)
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
    report.expect(
        accepted && forward == ["0:60:10", "10:60:10", "30:60:10"] && undoRestored
            && progressive.notes(in: 0).map(noteShape) == forward,
        cppID: "editcheck/EditCheckTest::rangeEdit",
        message: "successive inserted spans resolve against the progressively shortened stationary note")
}
