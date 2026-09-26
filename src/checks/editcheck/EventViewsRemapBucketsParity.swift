import Foundation
import PorydawCore
@testable import PorydawApp
import PorydawAppEventList

private let remapNotifyOrderID = "eventviews/EventViewsRemapTest::notifyOrder"
private let bucketSumID = "eventviews/ViewBucketsGridTest::bucketSum"
private let clockLatticeID = "eventviews/ViewBucketsGridTest::clockLatticeCrossesSignatureSeam"
private let snapLadderID = "eventviews/ViewBucketsGridTest::snapLadder"
private let linesSnappableID = "eventviews/ViewBucketsGridTest::gridLinesSnappable"
private let densityID = "eventviews/ViewBucketsGridTest::fixedGridPaintDensityGuard"

@MainActor
func runEventViewsRemapBucketsParityChecks(_ report: CheckReport) {
    remapParityAnchorTracking(report)
    bucketParitySum(report)
    clockParityLattice(report)
    gridSnapLadder(report)
    gridLinesSnappable(report)
    fixedGridPaintDensityGuard(report)
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
    let metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 640, height: 320, timeAxis: axis)
    var camera = EditorCamera(ticksPerBeat: 48, lengthTicks: 120, viewportWidth: 640,
                              rollHeight: 320, limits: GridCameraPolicy.limits(baseFontPx: 13))
    _ = camera.setTimeZoom(24 * metrics.autoGridMinCell)
    var grid = RollGrid(axis: axis, clockTicks: clock, metrics: metrics)
    grid.setSelection(.clock)
    report.expectEqual(expected: 36, actual: grid.snapTickDown(37, camera: camera),
                       cppID: clockLatticeID, what: "clock snap down crosses the seam")
    report.expectEqual(expected: 38, actual: grid.snapTickUp(37, camera: camera),
                       cppID: clockLatticeID, what: "clock snap up crosses the seam")
    report.expectEqual(expected: 36, actual: grid.nextSnapTickAfter(35, camera: camera),
                       cppID: clockLatticeID, what: "next snap after 35")
    report.expectEqual(expected: 38, actual: grid.nextSnapTickAfter(36, camera: camera),
                       cppID: clockLatticeID, what: "next snap after 36 skips the seam")
    report.expectEqual(expected: 38, actual: grid.nextSubdivisionTickAfter(36, camera: camera),
                       cppID: clockLatticeID, what: "next subdivision after 36 skips the seam")
    report.expectEqual(expected: 38, actual: grid.nextSnapTickAfter(37, camera: camera),
                       cppID: clockLatticeID, what: "next snap after 37")
    var lines: [Tick] = []
    grid.forEachSubdivision(from: 30, to: 46, camera: camera) { tick, _ in lines.append(tick) }
    let expected: [Tick] = [30, 32, 34, 38, 40, 42, 44]
    report.expectEqual(expected: expected.count, actual: lines.count, cppID: clockLatticeID,
                       what: "clock sub-grid line count")
    report.expect(lines == expected, cppID: clockLatticeID,
                  message: "clock sub-grid ticks are the absolute lattice")
}

@MainActor
private func gridSnapLadder(_ report: CheckReport) {
    let metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 640, height: 320)
    let cell = metrics.autoGridMinCell
    let rows: [(String, Double, GridSelection, GridFeel, Tick, Tick)] = [
        ("straight below", 4 * cell - 1, .auto, .straight, 12, 6),
        ("straight threshold", 4 * cell, .auto, .straight, 6, 3),
        ("triplet", 6 * cell, .auto, .triplet, 4, 2),
        ("triplet eighth fixed", 6 * cell, .musical(8), .triplet, 8, 8),
        ("straight sixteenth fixed", 4 * cell, .musical(16), .straight, 6, 6),
        ("straight quarter fixed", 4 * cell, .musical(4), .straight, 24, 24),
        ("clock fixed", 4 * cell, .clock, .straight, 1, 1)
    ]
    for (name, zoom, selection, feel, visible, snap) in rows {
        var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 120, viewportWidth: 640,
                                  rollHeight: 320, limits: GridCameraPolicy.limits(baseFontPx: 13))
        _ = camera.setTimeZoom(zoom)
        var grid = RollGrid(clockTicks: 1, metrics: metrics)
        grid.setState(selection, feel: feel)
        report.expectEqual(expected: visible, actual: grid.gridTicksAt(0, camera: camera),
                           cppID: snapLadderID, what: "snap ladder \(name): grid ticks")
        report.expectEqual(expected: snap, actual: grid.snapTicksAt(0, camera: camera),
                           cppID: snapLadderID, what: "snap ladder \(name): snap ticks")
    }
}

@MainActor
private func gridLinesSnappable(_ report: CheckReport) {
    for (shape, signatures) in [
        ("flat quarter grid", [TimeSigPoint]()),
        ("mid-song signature restart", [TimeSigPoint(tick: 37, numerator: 5, denomPow2: 3)]),
        ("denominator rescale", [TimeSigPoint(tick: 48, numerator: 3, denomPow2: 3)])
    ] {
        let axis = TimeAxis(map: TimeMap(ticksPerBeat: 24, lengthTicks: 120,
                                        timeSigs: signatures))
        let grid = RollGrid(axis: axis, clockTicks: 1)
        let camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 120, viewportWidth: 640,
                                  rollHeight: 320, limits: GridCameraPolicy.limits(baseFontPx: 13))
        var count = 0
        var unsnappable: [Tick] = []
        axis.forEachGridLine(from: 0, to: 120) { tick, _, _, _ in
            count += 1
            if grid.snapTick(Double(tick), camera: camera) != tick { unsnappable.append(tick) }
        }
        report.expect(count > 0, cppID: linesSnappableID,
                      message: "\(shape): grid lines exist")
        report.expect(unsnappable.isEmpty, cppID: linesSnappableID,
                      message: "\(shape): every drawn grid line is snappable")
    }
}

@MainActor
private func fixedGridPaintDensityGuard(_ report: CheckReport) {
    let metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 640, height: 320)
    let cell = metrics.autoGridMinCell
    var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 120, viewportWidth: 640,
                              rollHeight: 320, limits: GridCameraPolicy.limits(baseFontPx: 13))
    var grid = RollGrid(clockTicks: 1, metrics: metrics)
    func lines() -> [Tick] {
        var result: [Tick] = []
        grid.forEachSubdivision(from: 0, to: 120, camera: camera) { tick, _ in
            result.append(tick)
        }
        return result
    }
    grid.setSelection(.musical(8))
    _ = camera.setTimeZoom(2 * cell)
    report.expect(!lines().isEmpty, cppID: densityID,
                  message: "fixed eighth sub-grid paints at twice the cell")
    _ = camera.setTimeZoom(cell)
    report.expect(lines().isEmpty, cppID: densityID,
                  message: "fixed eighth sub-grid suppresses at the cell")
    report.expectEqual(expected: 12, actual: grid.snapTicksAt(0, camera: camera),
                       cppID: densityID, what: "fixed snap ignores paint suppression")
    report.expectEqual(expected: 36, actual: grid.snapTickDown(37, camera: camera),
                       cppID: densityID, what: "fixed snap ignores paint suppression")
    report.expectEqual(expected: 36, actual: grid.nextSnapTickAfter(24, camera: camera),
                       cppID: densityID, what: "fixed snap ignores paint suppression")
    grid.setSelection(.clock)
    let clock = grid.snapTicksAt(0, camera: camera)
    _ = camera.setTimeZoom(6 * cell)
    report.expect(!lines().isEmpty, cppID: densityID,
                  message: "clock sub-grid paints at six cells")
    _ = camera.setTimeZoom(2 * cell)
    report.expect(lines().isEmpty, cppID: densityID,
                  message: "clock sub-grid suppresses at two cells")
    report.expectEqual(expected: clock, actual: grid.snapTicksAt(0, camera: camera),
                       cppID: densityID, what: "clock snap ignores paint suppression")
}
