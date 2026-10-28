import Foundation
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func removalAndSeams(_ report: CheckReport) {
    let document = timeDocument()
    guard
        let ids = try? document.addNotes([
            NewNote(track: 0, tick: 0, pitch: 60, duration: 100, velocity: 81),
            NewNote(track: 0, tick: 110, pitch: 60, duration: 10, velocity: 92),
            NewNote(track: 1, tick: 110, pitch: 62, duration: 10, velocity: 73),
        ])
    else { return }
    document.writeLane(
        track: 0, lane: .controller(7), from: 25, through: 50,
        points: [LaneWrite(tick: 25, value: 30), LaneWrite(tick: 40, value: 44)])
    let untouched = document.note(ids[2])
    let before = coreTimeBytes(document)
    report.expect(
        document.removeTime(
            TimeRange(startTick: 20, endTick: 50),
            scope: TimeScope(tracks: [0])),
        cppID: "editcheck/EditCheckTest::timeRangeRemoveRippleTrim",
        message: "scoped gap removal commits")
    report.expectEqual(
        expected: ["0:60:80", "80:60:10"], actual: document.notes(in: 0).map(noteShape),
        cppID: "editcheck/EditCheckTest::timeRangeRemove",
        what: "crossing note trims and later note ripples")
    report.expectEqual(
        expected: "20:44", actual: document.lanePoints(track: 0, lane: .controller(7)).first.map(coreTimePointShape),
        cppID: "editcheck/EditCheckTest::timeRangeAutomationSeamsAndDefaults",
        what: "last in-range value survives at the seam")
    report.expectEqual(
        expected: untouched?.tick, actual: document.note(ids[2])?.tick,
        cppID: "editcheck/EditCheckTest::timeRangeRemoveRippleTrim",
        what: "unscoped track is unchanged")
    _ = document.history.undoDocument()
    report.expectEqual(
        expected: before, actual: coreTimeBytes(document),
        cppID: "editcheck/EditCheckTest::timeRangeRemove",
        what: "single undo restores scoped removal")

    let whole = timeDocument()
    _ = try? whole.addNotes([NewNote(track: 0, tick: 66, pitch: 65, duration: 4, velocity: 90)])
    whole.setTimeSignature(tick: 62, numerator: 3, denominatorPower: 2)
    whole.editTempo(TempoEdit(add: [TempoPoint(tick: 63, microsecondsPerQuarterNote: 333_333)]))
    whole.insertRawEvent(chunk: 0, event: .meta(tick: 64, type: 0x06, data: [0x5B]))
    let oldEnd = whole.rawChunks.map(\.endTick)
    let wholeBefore = coreTimeBytes(whole)
    report.expect(
        whole.removeTime(
            TimeRange(startTick: 61, endTick: 65),
            scope: TimeScope(wholeSong: true)),
        cppID: "editcheck/EditCheckTest::songWholeSongRemove",
        message: "whole-song close commits")
    report.expect(
        whole.timeSignatures.contains { $0.tick == 61 && $0.numerator == 3 }
            && whole.state.tempo.contains { $0.tick == 61 }
            && whole.rawChunks[0].events.contains { $0.metaType == 0x06 && $0.tick == 61 },
        cppID: "editcheck/EditCheckTest::timeRangeWholeSong",
        message: "globals are rescued to the closing seam")
    let closedEnds = zip(oldEnd, whole.rawChunks.map(\.endTick)).allSatisfy { pair in
        let (before, after) = pair
        let expected = before >= 65 ? before - 4 : (before > 61 ? 61 : before)
        return after == expected
    }
    report.expect(
        closedEnds,
        cppID: "editcheck/EditCheckTest::songWholeSongRemove",
        message: "whole-song removal closes every stored end tick")
    _ = whole.history.undoDocument()
    report.expectEqual(
        expected: oldEnd, actual: whole.rawChunks.map(\.endTick),
        cppID: "editcheck/EditCheckTest::songWholeSongRemove",
        what: "one undo restores every stored end tick")
    report.expectEqual(
        expected: wholeBefore, actual: coreTimeBytes(whole),
        cppID: "editcheck/EditCheckTest::timeRangeWholeSong",
        what: "one undo restores globals, events, and end-of-track state")

    // timeRangeRemoveRippleTrim: full earlierEnd loop over the faithful
    // three-chunk timeRangeFile fixture (conductor plus two engine tracks).
    for earlierEnd: Tick in [100, 80, 70] {
        let id = "editcheck/EditCheckTest::timeRangeRemoveRippleTrim[end=\(earlierEnd)]"
        do {
            let trim = try timeRangeDocument()
            report.expectEqual(
                expected: 2, actual: trim.engineTracks.usedTrackCount, cppID: id,
                what: "timeRangeFile fixture loads two editable tracks")
            _ = try trim.addNotes([
                NewNote(track: 0, tick: 0, pitch: 60, duration: earlierEnd, velocity: 81),
                NewNote(track: 0, tick: 110, pitch: 60, duration: 10, velocity: 92),
            ])
            _ = try trim.addNotes([
                NewNote(track: 1, tick: 0, pitch: 60, duration: 100, velocity: 73),
                NewNote(track: 1, tick: 110, pitch: 60, duration: 10, velocity: 74),
            ])
            report.expect(
                coreRangeNotePairsConsistent(trim, track: 0), cppID: id,
                message: "track 0 on/off pairs consistent before removal")
            report.expect(
                coreRangeNotePairsConsistent(trim, track: 1), cppID: id,
                message: "track 1 on/off pairs consistent before removal")
            let original = trim.notes(in: 0)
            let otherChunk = trim.engineTracks.tracks[1].midiChunk
            let other = otherChunk.map { trim.rawChunks[$0].events }
            let trimBefore = coreTimeBytes(trim)
            let trimPosition = try coreEditHistoryCountAtTip(trim, report: report, cppID: id)
            report.expect(
                trim.removeTime(
                    TimeRange(startTick: 20, endTick: 50),
                    scope: TimeScope(tracks: [0])),
                cppID: id, message: "scoped gap removal commits")
            report.expect(
                coreRangeNotePairsConsistent(trim, track: 0), cppID: id,
                message: "track 0 on/off pairs consistent after removal")
            report.expect(
                coreRangeNotePairsConsistent(trim, track: 1), cppID: id,
                message: "track 1 on/off pairs consistent after removal")
            let notes = trim.notes(in: 0)
            report.expectEqual(
                expected: 2, actual: notes.count, cppID: id,
                what: "two notes remain after the scoped removal")
            report.expectEqual(
                expected: Tick(0), actual: notes.first?.tick, cppID: id,
                what: "crossing note keeps its start tick")
            report.expectEqual(
                expected: min(earlierEnd, Tick(80)), actual: notes.first?.duration, cppID: id,
                what: "crossing note trims to the rippled neighbor")
            report.expectEqual(
                expected: Tick(80), actual: notes.last?.tick, cppID: id,
                what: "later note ripples left by the span")
            report.expectEqual(
                expected: Tick(10), actual: notes.last?.duration, cppID: id,
                what: "later note keeps its duration")
            for (note, source) in zip(notes, original) {
                report.expectEqual(
                    expected: source.id, actual: note.id, cppID: id,
                    what: "removal preserves note identity")
                report.expectEqual(
                    expected: source.velocity, actual: note.velocity, cppID: id,
                    what: "removal preserves note velocity")
            }
            if let otherChunk, let other {
                report.expectEqual(
                    expected: other, actual: trim.rawChunks[otherChunk].events, cppID: id,
                    what: "unscoped track events are byte-identical")
            } else {
                report.fail(id, "unscoped engine track has no MIDI chunk")
            }
            report.expectEqual(
                expected: trimPosition + 1,
                actual: try coreEditHistoryCountAtTip(trim, report: report, cppID: id),
                cppID: id, what: "removal adds one history entry")
            let trimAfter = coreTimeBytes(trim)
            _ = trim.history.undoDocument()
            report.expectEqual(
                expected: trimBefore, actual: coreTimeBytes(trim), cppID: id,
                what: "one undo restores the removal")
            _ = trim.history.redoDocument()
            report.expectEqual(
                expected: trimAfter, actual: coreTimeBytes(trim), cppID: id,
                what: "one redo restores the removal")
            report.expect(
                coreRangeNotePairsConsistent(trim, track: 0), cppID: id,
                message: "track 0 on/off pairs consistent after redo")
            report.expect(
                coreRangeNotePairsConsistent(trim, track: 1), cppID: id,
                message: "track 1 on/off pairs consistent after redo")
        } catch {
            report.fail(id, "removal fixture failed: \(error)")
        }
    }
    for duplicate in [false, true] {
        let id = "editcheck/EditCheckTest::timeRangeRemoveRippleTrim[\(duplicate ? "duplicate" : "insert")]"
        do {
            let branch = try timeRangeDocument()
            report.expectEqual(
                expected: 2, actual: branch.engineTracks.usedTrackCount, cppID: id,
                what: "timeRangeFile fixture loads two editable tracks")
            _ = try branch.addNotes([
                NewNote(track: 0, tick: 0, pitch: 60, duration: 30, velocity: 81),
                NewNote(track: 0, tick: 30, pitch: 60, duration: 20, velocity: 92),
            ])
            report.expect(
                coreRangeNotePairsConsistent(branch, track: 0), cppID: id,
                message: "on/off pairs consistent before the edit")
            let branchBefore = coreTimeBytes(branch)
            if duplicate {
                report.expect(
                    branch.duplicateTime(
                        TimeRange(startTick: 10, endTick: 40),
                        scope: TimeScope(tracks: [0])),
                    cppID: id, message: "duplicate branch commits")
            } else {
                report.expect(
                    branch.insertBlankTime(
                        TimeRange(startTick: 10, endTick: 40),
                        scope: TimeScope(tracks: [0])),
                    cppID: id, message: "insert branch commits")
            }
            report.expect(
                coreRangeNotePairsConsistent(branch, track: 0), cppID: id,
                message: "on/off pairs consistent after the edit")
            let branchAfter = coreTimeBytes(branch)
            _ = branch.history.undoDocument()
            report.expectEqual(
                expected: branchBefore, actual: coreTimeBytes(branch), cppID: id,
                what: "one undo restores the branch")
            _ = branch.history.redoDocument()
            report.expectEqual(
                expected: branchAfter, actual: coreTimeBytes(branch), cppID: id,
                what: "one redo restores the branch")
            report.expect(
                coreRangeNotePairsConsistent(branch, track: 0), cppID: id,
                message: "on/off pairs consistent after redo")
        } catch {
            report.fail(id, "duplicate/insert fixture failed: \(error)")
        }
    }
}
