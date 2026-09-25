import Foundation
import PorydawCore

private func duplicateFixtureFile() -> MidiFile {
    MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x01, data: Array("conductor".utf8)),
            .meta(tick: 24, type: 0x51, data: [0x5B, 0x8D, 0x80]),
            .meta(tick: 48, type: 0x51, data: [0x07, 0xA1, 0x20]),
            .meta(tick: 48, type: 0x51, data: [0x06, 0x1A, 0x80]),
            .meta(tick: 48, type: 0x01, data: Array("shared tick".utf8)),
            .meta(tick: 72, type: 0x51, data: [0x03, 0x0D, 0x40]),
            .meta(tick: 96, type: 0x51, data: [0x05, 0xB8, 0xD9]),
        ], endTick: 120),
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 5),
            .channel(status: 0xB0, data0: 7, data1: 100),
            .channel(status: 0xC0, data0: 9),
            .channel(status: 0xB0, data0: 7, data1: 80),
            .channel(status: 0x90, data0: 60, data1: 100),
            .meta(tick: 48, type: 0x51, data: [0x09, 0x27, 0xC0]),
            .channel(tick: 96, status: 0x80, data0: 60, data1: 0),
        ], endTick: 96),
    ])
}

@MainActor
func xcmdSaveSnapshotContract(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 96),
    ]))
    let base: Tick = 100
    document.insertRawEvent(chunk: 0, event: .channel(tick: base + 1, status: 0xB0,
                                                    data0: Xcmd.selectorController, data1: 0x08))
    document.insertRawEvent(chunk: 0, event: .channel(tick: base + 2, status: 0xB0,
                                                    data0: Xcmd.payloadController, data1: 34))
    document.insertRawEvent(chunk: 0, event: .channel(tick: base + 3, status: 0xB0,
                                                    data0: Xcmd.selectorController, data1: 0x09))
    guard let historyDepth = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot"
    ) else {
        report.fail("editcheck/EditCheckTest::xcmdSaveSnapshot",
                    "cannot count undo entries before capture")
        return
    }
    let liveBytes = try? document.state.file.encoded()
    let revision = document.revision
    let dirty = document.isDirty
    guard let snapshot = try? document.captureSave() else {
        report.fail("editcheck/EditCheckTest::xcmdSaveSnapshot", "captureSave failed")
        return
    }
    report.expectEqual(expected: liveBytes, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "capture leaves live bytes untouched")
    report.expectEqual(expected: revision, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "capture records no history entry")
    report.expectEqual(expected: dirty, actual: document.isDirty,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "capture leaves the dirty flag untouched")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                  message: "capture leaves the undo cursor at the tip")
    report.expectEqual(expected: historyDepth, actual: try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot"),
        cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
        what: "capture leaves the undo depth unchanged")
    guard let saved = try? MidiFile.decode(snapshot.bytes) else {
        report.fail("editcheck/EditCheckTest::xcmdSaveSnapshot",
                    "snapshot bytes do not decode")
        return
    }
    let events = saved.chunks[0].events
    report.expect(!events.contains {
        $0.tick == base + 1 && channelFields($0)?.data0 == Xcmd.selectorController
    }, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
    message: "delayed selector is not saved")
    let payload = events.filter {
        guard $0.tick == base + 2, let fields = channelFields($0) else { return false }
        return fields.data0 == Xcmd.selectorController || fields.data0 == Xcmd.payloadController
    }
    report.expectEqual(expected: 2, actual: payload.count,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "canonical selector/payload pair is saved")
    guard payload.count == 2 else { return }
    report.expectEqual(expected: Xcmd.selectorController, actual: channelFields(payload[0])?.data0,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved pair leads with the selector controller")
    report.expectEqual(expected: UInt8(0x08), actual: channelFields(payload[0])?.data1,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved selector carries its value")
    report.expectEqual(expected: Xcmd.payloadController, actual: channelFields(payload[1])?.data0,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved pair follows with the payload controller")
    report.expectEqual(expected: UInt8(34), actual: channelFields(payload[1])?.data1,
                       cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
                       what: "saved payload carries its value")
    report.expect(!events.contains {
        $0.tick == base + 3 && channelFields($0)?.data0 == Xcmd.selectorController
    }, cppID: "editcheck/EditCheckTest::xcmdSaveSnapshot",
    message: "dangling selector is not saved")
}

@MainActor
func duplicateLaneAndTempoLoadContract(_ report: CheckReport) {
    let document = SongDocument(file: duplicateFixtureFile())
    let liveBytes = try? document.state.file.encoded()
    report.expectEqual(expected: 2, actual: document.lanePoints(track: 0, lane: .voice).count,
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "both voice lane points load")
    report.expectEqual(expected: 2, actual: document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
        what: "both CC7 duplicates load at tick zero")
    report.expectEqual(expected: 80, actual: document.lanePoints(track: 0, lane: .controller(7))
        .last { $0.tick == 0 }?.value,
        cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
        what: "last CC7 duplicate wins the loaded value")
    report.expectEqual(expected: 9, actual: document.lanePoints(track: 0, lane: .voice)
        .last { $0.tick == 0 }?.value,
        cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
        what: "last voice duplicate wins the loaded value")
    report.expectEqual(expected: [
        TempoPoint(tick: 24, microsecondsPerQuarterNote: 3_000_000),
        TempoPoint(tick: 48, microsecondsPerQuarterNote: 400_000),
        TempoPoint(tick: 72, microsecondsPerQuarterNote: 235_294),
        TempoPoint(tick: 96, microsecondsPerQuarterNote: 375_001),
    ], actual: document.state.tempo,
    cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
    what: "clamped and exact tempo points load in order")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: 5, actual: timeline.tempoMap.count,
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "tempo map gains the default tick-zero point")
    report.expectEqual(expected: 120.0, actual: timeline.tempoMap.first?.beatsPerMinute,
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "tempo map fronts the default tempo")
    var expected = document.state.file
    let typedTempoEvents: [MidiEvent] = document.state.tempo.map { point in
        let value = point.microsecondsPerQuarterNote
        return .meta(tick: point.tick, type: 0x51,
                     data: [UInt8((value >> 16) & 0xFF),
                            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
    guard typedTempoEvents.count == 4, expected.chunks.first?.events.count == 2 else {
        report.fail("editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                    "cannot construct expected saved file")
        return
    }
    expected.chunks[0].events.insert(contentsOf: typedTempoEvents[0..<2], at: 1)
    expected.chunks[0].events.insert(contentsOf: typedTempoEvents[2..<4], at: 4)
    guard let snapshot = try? document.captureSave() else {
        report.fail("editcheck/EditCheckTest::duplicateLaneAndTempoLoad", "capture failed")
        return
    }
    report.expectEqual(expected: snapshot.bytes, actual: try? expected.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "saved bytes match the live file with typed tempos inserted")
    report.expectEqual(expected: liveBytes, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateLaneAndTempoLoad",
                       what: "capture leaves live bytes untouched")
}

@MainActor
func duplicateCanonicalizationContract(_ report: CheckReport) {
    let document = SongDocument(file: duplicateFixtureFile())
    let baseline = try? document.state.file.encoded()
    var changedCount = 0
    document.onChange = { _ in changedCount += 1 }
    guard let point = document.lanePoints(track: 0, lane: .controller(7))
        .first(where: { $0.tick == 0 }) else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "no CC7 lane point at tick zero")
        return
    }
    guard let undoCount = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateCanonicalization"
    ) else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "cannot count undo entries before canonicalization")
        return
    }
    let revision = document.revision
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: point.tick, value: point.value)])
    report.expectEqual(expected: 1, actual: document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "no-op move collapses the duplicate lane points")
    report.expectEqual(expected: revision + 1, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "canonicalizing move records one revision")
    report.expectEqual(expected: 1, actual: changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "canonicalizing move publishes one change")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                  message: "canonicalizing move advances the undo cursor to the tip")
    report.expectEqual(expected: undoCount + 1, actual: try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateCanonicalization"),
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "canonicalizing move adds one undo entry")
    let canonicalState = document.state
    let canonicalIdentity = document.history.currentIdentity
    let canonicalRevision = document.revision
    changedCount = 0
    guard document.history.undoDocument() else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "canonicalizing move cannot be undone")
        return
    }
    let restored = document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }
    report.expectEqual(expected: 2, actual: restored.count,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores both duplicates")
    report.expectEqual(expected: 100, actual: restored.first?.value,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores the first duplicate value")
    report.expectEqual(expected: 80, actual: restored.dropFirst().first?.value,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores the second duplicate value")
    report.expectEqual(expected: baseline, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo restores the baseline bytes")
    report.expectEqual(expected: canonicalRevision + 1, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo records another revision")
    report.expectEqual(expected: 1, actual: changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                       what: "undo publishes one change")
    let undoneState = document.state
    let undoneIdentity = document.history.currentIdentity
    report.expect(!document.history.canUndo && document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
                  message: "undo returns the cursor to zero with redo available")
    guard document.history.redoDocument() else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "canonicalizing move cannot be redone")
        return
    }
    report.expect(document.state == canonicalState &&
        document.history.currentIdentity == canonicalIdentity,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        message: "redo restores the canonical state and identity")
    report.expectEqual(expected: undoCount + 1, actual: try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateCanonicalization"),
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "undo retains the canonicalizing entry")
    guard document.history.undoDocument() else {
        report.fail("editcheck/EditCheckTest::duplicateCanonicalization",
                    "cannot restore the undone cursor")
        return
    }
    report.expect(document.state == undoneState &&
        document.history.currentIdentity == undoneIdentity &&
        !document.history.canUndo && document.history.canRedo,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        message: "redo/undo restores the exact undone state, identity and cursor")
    document.writeLane(track: 0, lane: .controller(7), from: 0, through: 0,
                       points: [LaneWrite(tick: 0, value: 70)])
    report.expectEqual(expected: 1, actual: document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateCanonicalization",
        what: "lane write collapses the restored duplicates")
}

@MainActor
func duplicateReplacementsAndNoOpsContract(_ report: CheckReport) {
    let document = SongDocument(file: duplicateFixtureFile())
    let baseline = try? document.state.file.encoded()
    var changedCount = 0
    document.onChange = { _ in changedCount += 1 }
    document.writeLane(track: 0, lane: .controller(7), from: 48, through: 48,
                       points: [LaneWrite(tick: 48, value: 55)])
    guard let point = document.lanePoints(track: 0, lane: .controller(7))
        .first(where: { $0.tick == 48 }) else {
        report.fail("editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                    "no CC7 lane point at tick 48")
        return
    }
    report.expectEqual(expected: 1, actual: document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 48 }.count,
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "lane write leaves one point at the tick")
    guard let noOpUndoCount = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"
    ) else {
        report.fail("editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                    "cannot count undo entries before the lane no-op")
        return
    }
    let noOpBytes = try? document.state.file.encoded()
    let noOpRevision = document.revision
    changedCount = 0
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: point.tick, value: point.value)])
    report.expectEqual(expected: noOpBytes, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "no-op lane move leaves bytes untouched")
    report.expectEqual(expected: noOpRevision, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "no-op lane move leaves the revision untouched")
    report.expectEqual(expected: 0, actual: changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "no-op lane move publishes no change")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                  message: "no-op lane move leaves the undo cursor at the tip")
    report.expectEqual(expected: noOpUndoCount, actual: try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"),
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "no-op lane move adds no history entry")
    document.moveLanePoints(track: 0, lane: .controller(7), moves: [
        LanePointMove(point: point, tick: 0, value: 55)])
    report.expectEqual(expected: 1, actual: document.lanePoints(track: 0, lane: .controller(7))
        .filter { $0.tick == 0 }.count,
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "move onto an occupied tick collapses to one point")
    report.expect(document.lanePoints(track: 0, lane: .controller(7))
        .allSatisfy { $0.tick != 48 },
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        message: "source tick is vacated by the move")
    let noOpTempo = TempoPoint(tick: 48, microsecondsPerQuarterNote: 500_000)
    document.editTempo(TempoEdit(add: [noOpTempo]))
    report.expect(document.state.tempo.contains(noOpTempo),
                  cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                  message: "applied tempo point is present")
    guard let tempoUndoCount = try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"
    ) else {
        report.fail("editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                    "cannot count undo entries before the tempo no-op")
        return
    }
    let tempoBytes = try? document.state.file.encoded()
    let tempoPoints = document.state.tempo
    let tempoRevision = document.revision
    changedCount = 0
    document.editTempo(TempoEdit(add: [noOpTempo]))
    report.expectEqual(expected: tempoBytes, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply leaves bytes untouched")
    report.expectEqual(expected: tempoPoints, actual: document.state.tempo,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply leaves tempo points untouched")
    report.expectEqual(expected: tempoRevision, actual: document.revision,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply leaves the revision untouched")
    report.expectEqual(expected: 0, actual: changedCount,
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "duplicate tempo apply publishes no change")
    report.expect(document.history.canUndo && !document.history.canRedo,
                  cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                  message: "duplicate tempo apply leaves the undo cursor at the tip")
    report.expectEqual(expected: tempoUndoCount, actual: try? coreEditHistoryCountAtTip(
        document, report: report, cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps"),
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        what: "duplicate tempo apply adds no history entry")
    _ = document.history.undoDocument()
    report.expect(document.state.tempo.contains(
        TempoPoint(tick: 48, microsecondsPerQuarterNote: 400_000)),
        cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
        message: "undo restores the replaced tempo point")
    _ = document.history.redoDocument()
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(expected: baseline, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::duplicateReplacementsAndNoOps",
                       what: "undo-all restores the baseline bytes")
}

