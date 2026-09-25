import Foundation
import PorydawCore
import PorydawApp
import PorydawAppEventList

private let remapNotifyOrderID = "eventviews/EventViewsRemapTest::notifyOrder"
private let bucketSumID = "eventviews/ViewBucketsGridTest::bucketSum"
private let clockLatticeID = "eventviews/ViewBucketsGridTest::clockLatticeCrossesSignatureSeam"

@MainActor
func runEventViewsRemapBucketsParityChecks(_ report: CheckReport) {
    remapParityAnchorTracking(report)
    bucketParitySum(report)
    clockParityLattice(report)
}

@MainActor
private func remapParityTempoFile() -> MidiFile {
    let primary: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
        .meta(tick: 0, type: 0x58, data: [4, 2, 0x18, 8]),
        .meta(tick: 0, type: 0x06, data: Array("fixture marker".utf8)),
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 8, status: 0xB0, data0: 7, data1: 80),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 30, status: 0x80, data0: 60),
        .meta(tick: 50, type: 0x58, data: [3, 2, 0x18, 8]),
        .channel(tick: 60, status: 0xB0, data0: 7, data1: 20),
        .channel(tick: 60, status: 0xB0, data0: 10, data1: 30),
        .channel(tick: 70, status: 0x90, data0: 64, data1: 70),
        .channel(tick: 90, status: 0x80, data0: 64)
    ]
    return MidiFile(division: 24, chunks: [
        MidiChunk(events: primary, endTick: 120),
        MidiChunk(events: [.meta(tick: 5, type: 0x06, data: Array("metadata only".utf8))], endTick: 120),
        MidiChunk(events: [
            .channel(status: 0xC1, data0: 1),
            .channel(tick: 24, status: 0xB1, data0: 7, data1: 64),
            .channel(tick: 48, status: 0x91, data0: 67, data1: 90),
            .channel(tick: 72, status: 0x81, data0: 67)
        ], endTick: 120)
    ])
}

@MainActor
private func remapParityRowCount(_ document: SongDocument, chunk: Int) -> Int {
    guard document.rawChunks.indices.contains(chunk) else { return -1 }
    let model = EventListModel(chunk: document.rawChunks[chunk])
    return model.rowCount
}
@MainActor
private func remapParityExpectedCount(_ document: SongDocument, chunk: Int) -> Int {
    guard document.rawChunks.indices.contains(chunk) else { return -1 }
    return document.rawChunks[chunk].events.count + 1
}

@MainActor
private func remapParityAnchorTracking(_ report: CheckReport) {
    let document = SongDocument(file: remapParityTempoFile())
    var changes: [DocumentChange] = []
    document.onChange = { changes.append($0) }
    var trackedChunk = 2
    var trackedEngine = 1
    report.expectEqual(expected: 2, actual: document.engineTracks.tracks[1].midiChunk ?? -1, cppID: remapNotifyOrderID, what: "initial second engine owns the third chunk")
    let moved = document.moveTrack(1, to: 0)
    report.expectEqual(expected: true, actual: moved, cppID: remapNotifyOrderID, what: "move accepts the second track")
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "move publishes a track remap")
    report.expect(changes.last?.trackRemap?.chunkMap.indices.contains(2) == true && changes.last?.trackRemap?.chunkMap[2] == 0, cppID: remapNotifyOrderID, message: "move maps the third chunk to the front")
    if let remap = changes.last?.trackRemap {
        if remap.chunkMap.indices.contains(trackedChunk) {
            trackedChunk = remap.chunkMap[trackedChunk] ?? -1
        } else {
            trackedChunk = -1
        }
        if remap.engineTrackMap.indices.contains(trackedEngine) {
            trackedEngine = remap.engineTrackMap[trackedEngine] ?? -1
        } else {
            trackedEngine = -1
        }
    }
    report.expectEqual(expected: 0, actual: trackedChunk, cppID: remapNotifyOrderID, what: "chunk anchor follows the move")
    report.expectEqual(expected: 0, actual: trackedEngine, cppID: remapNotifyOrderID, what: "engine anchor follows the move")
    report.expectEqual(expected: remapParityExpectedCount(document, chunk: trackedChunk), actual: remapParityRowCount(document, chunk: trackedChunk), cppID: remapNotifyOrderID, what: "moved chunk projects its events and sentinel")
    _ = document.history.undoDocument()
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "move undo publishes the inverse remap")
    if let remap = changes.last?.trackRemap {
        if remap.chunkMap.indices.contains(trackedChunk) {
            trackedChunk = remap.chunkMap[trackedChunk] ?? -1
        } else {
            trackedChunk = -1
        }
        if remap.engineTrackMap.indices.contains(trackedEngine) {
            trackedEngine = remap.engineTrackMap[trackedEngine] ?? -1
        } else {
            trackedEngine = -1
        }
    }
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "undo restores the chunk anchor")
    report.expectEqual(expected: 1, actual: trackedEngine, cppID: remapNotifyOrderID, what: "undo restores the engine anchor")
    report.expectEqual(expected: remapParityExpectedCount(document, chunk: trackedChunk), actual: remapParityRowCount(document, chunk: trackedChunk), cppID: remapNotifyOrderID, what: "undo restores the chunk projection")
    _ = document.history.redoDocument()
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "move redo republishes the forward remap")
    if let remap = changes.last?.trackRemap {
        if remap.chunkMap.indices.contains(trackedChunk) {
            trackedChunk = remap.chunkMap[trackedChunk] ?? -1
        } else {
            trackedChunk = -1
        }
        if remap.engineTrackMap.indices.contains(trackedEngine) {
            trackedEngine = remap.engineTrackMap[trackedEngine] ?? -1
        } else {
            trackedEngine = -1
        }
    }
    report.expectEqual(expected: 0, actual: trackedChunk, cppID: remapNotifyOrderID, what: "redo follows the moved chunk again")
    report.expectEqual(expected: remapParityExpectedCount(document, chunk: trackedChunk), actual: remapParityRowCount(document, chunk: trackedChunk), cppID: remapNotifyOrderID, what: "redo rebuilds the moved chunk projection")
    _ = document.history.undoDocument()
    if let remap = changes.last?.trackRemap {
        if remap.chunkMap.indices.contains(trackedChunk) {
            trackedChunk = remap.chunkMap[trackedChunk] ?? -1
        } else {
            trackedChunk = -1
        }
        if remap.engineTrackMap.indices.contains(trackedEngine) {
            trackedEngine = remap.engineTrackMap[trackedEngine] ?? -1
        } else {
            trackedEngine = -1
        }
    }
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "restoring undo returns the anchor before rename")
    document.renameTrack(1, to: "event view fixture rename")
    report.expect(changes.last?.trackRemap == nil, cppID: remapNotifyOrderID, message: "rename publishes no track remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "rename keeps the chunk anchor")
    report.expectEqual(expected: remapParityExpectedCount(document, chunk: trackedChunk), actual: remapParityRowCount(document, chunk: trackedChunk), cppID: remapNotifyOrderID, what: "rename keeps the projected row count")
    _ = document.history.undoDocument()
    report.expect(changes.last?.trackRemap == nil, cppID: remapNotifyOrderID, message: "rename undo publishes no track remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "rename undo keeps the chunk anchor")
    _ = document.history.redoDocument()
    report.expect(changes.last?.trackRemap == nil, cppID: remapNotifyOrderID, message: "rename redo publishes no track remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "rename redo keeps the chunk anchor")
    _ = document.history.undoDocument()
    report.expect(document.canAddTrack, cppID: remapNotifyOrderID, message: "track budget admits one more track")
    let added = document.addTrack(voice: 0)
    report.expect(added != nil, cppID: remapNotifyOrderID, message: "add returns the new engine slot")
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "add publishes a track remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "add keeps the chunk anchor")
    report.expectEqual(expected: remapParityExpectedCount(document, chunk: trackedChunk), actual: remapParityRowCount(document, chunk: trackedChunk), cppID: remapNotifyOrderID, what: "add keeps the projected row count")
    _ = document.history.undoDocument()
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "add undo publishes the inverse remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "add undo keeps the chunk anchor")
    _ = document.history.redoDocument()
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "add redo republishes the forward remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "add redo keeps the chunk anchor")
    _ = document.history.undoDocument()
    let duplicated = document.duplicateTrack(0)
    report.expect(duplicated != nil, cppID: remapNotifyOrderID, message: "duplicate returns the new engine slot")
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "duplicate publishes a track remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "duplicate keeps the chunk anchor")
    report.expectEqual(expected: remapParityExpectedCount(document, chunk: trackedChunk), actual: remapParityRowCount(document, chunk: trackedChunk), cppID: remapNotifyOrderID, what: "duplicate keeps the projected row count")
    _ = document.history.undoDocument()
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "duplicate undo publishes the inverse remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "duplicate undo keeps the chunk anchor")
    _ = document.history.redoDocument()
    report.expect(changes.last?.trackRemap != nil, cppID: remapNotifyOrderID, message: "duplicate redo republishes the forward remap")
    report.expectEqual(expected: 2, actual: trackedChunk, cppID: remapNotifyOrderID, what: "duplicate redo keeps the chunk anchor")
}

@MainActor
private func bucketParityFile(addUnpaired: Bool, addOrphan: Bool) -> MidiFile {
    var primary: [MidiEvent] = [
        .meta(tick: 0, type: 0x58, data: [4, 2, 0x18, 8]),
        .meta(tick: 0, type: 0x06, data: Array("fixture marker".utf8)),
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 8, status: 0xB0, data0: 7, data1: 80),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 30, status: 0x80, data0: 60),
        .meta(tick: 50, type: 0x58, data: [3, 2, 0x18, 8]),
        .channel(tick: 60, status: 0xB0, data0: 7, data1: 20),
        .channel(tick: 60, status: 0xB0, data0: 10, data1: 30),
        .channel(tick: 70, status: 0x90, data0: 64, data1: 70),
        .channel(tick: 90, status: 0x80, data0: 64)
    ]
    if addUnpaired {
        primary.append(.channel(tick: 100, status: 0x90, data0: 72, data1: 100))
    }
    if addOrphan {
        primary.append(.channel(tick: 110, status: 0x80, data0: 73))
    }
    return MidiFile(division: 24, chunks: [MidiChunk(events: primary, endTick: 120)])
}

@MainActor
private func bucketParitySum(_ report: CheckReport) {
    let cases: [(name: String, unpaired: Bool, orphan: Bool, notes: Int, pairedOffs: Int, events: Int)] = [
        ("ordinary events", false, false, 2, 2, 9),
        ("unterminated note", true, false, 3, 2, 10),
        ("orphan note off", false, true, 2, 2, 10)
    ]
    for entry in cases {
        let document = SongDocument(file: bucketParityFile(addUnpaired: entry.unpaired, addOrphan: entry.orphan))
        report.expect(!document.rawChunks.isEmpty, cppID: bucketSumID, message: entry.name + ": single chunk fixture is present")
        let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48000.0)
        report.expect(timeline.ticksPerBeat == 24, cppID: bucketSumID, message: entry.name + ": timeline keeps the fixture timebase")
        report.expect(timeline.tempoMap.count == 1 && timeline.tempoMap[0].tick == 0 && timeline.tempoMap[0].microsecondsPerQuarterNote == TimeDefaults.defaultTempoMicrosecondsPerQuarterNote, cppID: bucketSumID, message: entry.name + ": synthetic tick-zero tempo default exists")
        let notes = document.notes(in: 0)
        report.expectEqual(expected: entry.notes, actual: notes.count, cppID: bucketSumID, what: entry.name + ": paired note count")
        let laneSeven = document.lanePoints(track: 0, lane: .controller(7)).count
        let laneTen = document.lanePoints(track: 0, lane: .controller(10)).count
        report.expectEqual(expected: 3, actual: laneSeven + laneTen, cppID: bucketSumID, what: entry.name + ": audible lane point count")
        report.expectEqual(expected: 1, actual: document.lanePoints(track: 0, lane: .voice).count, cppID: bucketSumID, what: entry.name + ": voice point count")
        let unterminated = notes.filter { $0.isUnterminated }.count
        let expectedUnterminated = entry.unpaired ? 1 : 0
        report.expectEqual(expected: expectedUnterminated, actual: unterminated, cppID: bucketSumID, what: entry.name + ": unterminated note count")
        report.expectEqual(expected: entry.events, actual: timeline.events.count, cppID: bucketSumID, what: entry.name + ": timeline event total with tempo")
        report.expectEqual(expected: 1, actual: timeline.otherEvents.count, cppID: bucketSumID, what: entry.name + ": marker survives as one other event")
        let terminated = notes.count - unterminated
        report.expectEqual(expected: entry.pairedOffs, actual: terminated, cppID: bucketSumID, what: entry.name + ": paired off count follows terminated notes")
    }
}

@MainActor
private func clockParityFile() -> MidiFile {
    return MidiFile(division: 48, chunks: [
        MidiChunk(events: [
            .meta(tick: 0, type: 0x58, data: [4, 2, 0x18, 8]),
            .meta(tick: 0, type: 0x06, data: Array("fixture marker".utf8)),
            .channel(status: 0xC0, data0: 0),
            .channel(tick: 8, status: 0xB0, data0: 7, data1: 80),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 90),
            .channel(tick: 30, status: 0x80, data0: 60),
            .meta(tick: 36, type: 0x58, data: [6, 3, 0x18, 8]),
            .meta(tick: 50, type: 0x58, data: [3, 2, 0x18, 8]),
            .channel(tick: 60, status: 0xB0, data0: 7, data1: 20),
            .channel(tick: 70, status: 0x90, data0: 64, data1: 70),
            .channel(tick: 90, status: 0x80, data0: 64)
        ], endTick: 120)
    ])
}

@MainActor
private func clockParityLattice(_ report: CheckReport) {
    let document = SongDocument(file: clockParityFile())
    document.setTimeSignature(tick: 37, numerator: 5, denominatorPower: 3)
    let axis = TimeAxis(map: TimeMap(ticksPerBeat: UInt32(max(1, document.ticksPerBeat)), timeSigs: document.timeSignatures.map { TimeSigPoint(tick: $0.tick, numerator: $0.numerator, denomPow2: $0.denominatorPower) }))
    report.expect(axis.segmentAt(37).start == 37, cppID: clockLatticeID, message: "off-lattice seam starts its own segment")
    report.expect(axis.segmentAt(36).next == 37, cppID: clockLatticeID, message: "previous segment ends at the seam")
    let clock = TimelineSnapPolicy.clockTicks(division: document.ticksPerBeat, extendedClocks: document.state.config.extendedClocks)
    report.expect(clock > 1 && 37 % clock != 0, cppID: clockLatticeID, message: "seam sits off the clock lattice")
}
