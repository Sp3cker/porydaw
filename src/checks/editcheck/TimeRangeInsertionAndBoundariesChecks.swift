import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func insertionAndBoundaries(_ report: CheckReport) {
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
