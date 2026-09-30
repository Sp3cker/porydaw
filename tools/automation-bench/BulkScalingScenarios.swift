import Foundation
import PorydawAppCommands
import PorydawCore

@testable import PorydawApp

// One --bulk-points clip pasted over the first or the last nodes of the dense lane, plus isolated undo/redo.
// The clip round-trips through ClipboardCodec in memory; the native system clipboard is never touched.

private enum BulkPlacement: String, CaseIterable {
    case start
    case end
}

@MainActor
private final class BulkBox {
    let drawing = DrawingBox()
    var notes: [[Note]] = []
    var songBefore: [UInt8] = []
    var songAfter: [UInt8] = []
}

/// Every engine track's notes; a lane paste must leave all of them untouched.
@MainActor
private func bulkNotes(_ f: BenchFixture) -> [[Note]] {
    (0..<f.document.engineTracks.usedTrackCount).map { f.document.notes(in: $0) }
}

/// `points` clip nodes one quarter apart at the dataset's mid value, built from the
/// parameter alone so both placements paste the identical clip.
@MainActor
private func bulkClip(_ f: BenchFixture, points: Int) throws -> PorydawClip {
    let value = midValue(f)
    let span = Tick(points * 24)
    switch f.parameter {
    case .tempo:
        let microseconds = UInt32(TimeDefaults.microsecondsPerQuarterNote(forBPM: value))
        return PorydawClip(
            span: span,
            tempo: (0..<points).map {
                ClipTempo(relTick: Tick($0 * 24), microsecondsPerQuarterNote: microseconds)
            })
    case .controlChange(let track, _), .pitchBend(let track):
        guard let lane = f.parameter.lane else { throw BenchFailure(description: "the parameter has no lane") }
        let cc: UInt8
        switch lane {
        case .controller(let controller): cc = controller
        case .voice: cc = TimeDefaults.laneCCVoice
        case .pitchBend: cc = TimeDefaults.laneCCBend
        }
        return PorydawClip(
            span: span,
            lanes: [
                ClipLane(
                    track: track, cc: cc,
                    points: (0..<points).map { ClipLanePoint(relTick: UInt32($0 * 24), value: value) })
            ])
    }
}

/// Seeds the companion lane, encodes the clip, and derives the exact lane the paste must leave.
@MainActor
private func bulkStage(_ f: BenchFixture, _ box: BulkBox, _ placement: BulkPlacement) throws {
    let d = box.drawing
    d.reset()
    try drawingSeedCompanion(f, d)
    let count = min(f.workload.bulkPoints, f.nodes - 1)
    try f.check(count >= 1, "--bulk-points resolves to \(count) clip points")
    let cursor = placement == .start ? f.sourceTick : Tick((f.nodes - count + 1) * 24)
    try f.check(placement == .start || cursor > f.sourceTick, "End paste must use a distinct cursor")
    let clip = try bulkClip(f, points: count)
    guard let data = ClipboardCodec.encode(clip, ticksPerBeat: UInt32(f.document.ticksPerBeat)),
        ClipboardCodec.decode(data)?.clip == clip
    else { throw BenchFailure(description: "the bulk clip does not round-trip through ClipboardCodec") }
    d.s.clipData = data
    d.s.pasteCursor = cursor
    d.s.pasteTrack = f.page.activeTrack() ?? 0
    d.s.pasteSpan = clip.span
    drawingCapture(f, d)
    let mid = midValue(f)
    let targets = (0..<count).map { cursor + Tick($0 * 24) }
    let occupants = Dictionary(grouping: d.s.before, by: \.tick)
    try f.check(
        targets.allSatisfy { occupants[$0]?.count == 1 && occupants[$0]?.first?.value != mid },
        "\(placement.rawValue): every pasted tick must hold exactly one node of another value")
    let overwritten = Set(targets)
    d.s.expected =
        d.s.before.filter { !overwritten.contains($0.tick) }
        + targets.map { AutomationLanePoint(tick: $0, value: mid) }
    box.notes = bulkNotes(f)
    box.songBefore = try f.document.captureSave().bytes
}

/// The production paste body minus the native clipboard read: decode, rescale, one
/// atomic semantic paste, cursor, selection and camera reveal in one state publication.
@MainActor
private func bulkPaste(_ f: BenchFixture, _ d: DrawingBox) -> Bool {
    guard let data = d.s.clipData, let decoded = ClipboardCodec.decode(data) else { return false }
    let clip = ClipboardCodec.rescale(
        decoded.clip, sourceTicksPerBeat: decoded.ticksPerBeat,
        destinationTicksPerBeat: UInt32(f.document.ticksPerBeat))
    let cursor = d.s.pasteCursor
    let track = d.s.pasteTrack
    guard ClipboardSemantics.pasteCursor(for: clip, at: cursor) != nil else { return false }
    return f.session.withStateChanges { () -> Bool in
        guard let result = ClipboardSemantics.paste(clip, at: cursor, selectedTrack: track, into: f.document)
        else { return false }
        f.session.editCursor = result.nextCursor
        f.page.clearTimeSelection()
        f.page.refreshFromDocument()
        _ = f.session.mutateCamera { _ = $0.ensureTickVisible(UInt64(cursor), dpr: f.page.devicePixelRatio) }
        return true
    }
}

/// Companion lane and every track's notes equal their pre-paste capture.
@MainActor
private func bulkExpectUnrelated(_ f: BenchFixture, _ box: BulkBox, _ what: String) throws {
    try drawingExpectCompanion(f, box.drawing, box.drawing.s.companionBefore, what)
    try f.check(bulkNotes(f) == box.notes, "\(what): note content changed")
}

@MainActor
private func bulkExpectPasted(_ f: BenchFixture, _ box: BulkBox, _ what: String) throws {
    let d = box.drawing
    try f.check(f.runResult, "\(what): the paste wrote nothing")
    try drawingExpectOneEdit(f, d, what)
    try drawingExpectLane(f, d.s.expected, what)
    let ticks = drawingSources(f, f.parameter).map(\.tick)
    try f.check(Set(ticks).count == ticks.count, "\(what): an overwritten tick kept two occurrences")
    try bulkExpectUnrelated(f, box, what)
    try f.check(
        f.session.editCursor == d.s.pasteCursor + d.s.pasteSpan,
        "\(what): the edit cursor is \(f.session.editCursor), expected the paste end")
}

/// Pastes untimed, validates it, and records the pasted song bytes.
@MainActor
private func bulkPrepared(_ f: BenchFixture, _ box: BulkBox, _ placement: BulkPlacement) throws {
    try bulkStage(f, box, placement)
    f.runResult = bulkPaste(f, box.drawing)
    try bulkExpectPasted(f, box, "prepared \(placement.rawValue) paste")
    box.songAfter = try f.document.captureSave().bytes
    try f.check(box.songAfter != box.songBefore, "the prepared paste left the song bytes unchanged")
}

/// The history after one undo (`undone`) or undo+redo of the prepared paste.
@MainActor
private func bulkExpectHistory(_ f: BenchFixture, _ box: BulkBox, undone: Bool, _ what: String) throws {
    let d = box.drawing
    let history = f.document.history
    try f.check(f.runResult, "\(what): the history step reported nothing")
    try f.check(
        f.document.revision == d.s.revision + (undone ? 2 : 3),
        "\(what): revision \(f.document.revision) after paste at \(d.s.revision)")
    try f.check(
        history.undoIndex == d.s.undoIndex + (undone ? 0 : 1) && history.undoCount == d.s.undoCount + 1
            && history.canRedo == undone,
        "\(what): history is \(history.undoIndex)/\(history.undoCount)")
    try drawingExpectLane(f, undone ? d.s.before : d.s.expected, what)
    try bulkExpectUnrelated(f, box, what)
    try f.check(
        try f.document.captureSave().bytes == (undone ? box.songBefore : box.songAfter),
        "\(what): song bytes differ from the \(undone ? "pre-paste" : "pasted") capture")
}

@MainActor
func bulkScalingScenarios() -> [BenchScenario] {
    BulkPlacement.allCases.flatMap { placement -> [BenchScenario] in
        let paste = BulkBox()
        let undo = BulkBox()
        let redo = BulkBox()
        let suffix = placement.rawValue
        return [
            BenchScenario(
                name: "bulk.paste.\(suffix)",
                prepare: { f in try bulkStage(f, paste, placement) },
                run: { f in f.runResult = bulkPaste(f, paste.drawing) },
                validate: { f in try bulkExpectPasted(f, paste, "bulk.paste.\(suffix)") }),
            BenchScenario(
                name: "bulk.undo.\(suffix)",
                prepare: { f in try bulkPrepared(f, undo, placement) },
                run: { f in f.runResult = try await f.session.undo() },
                validate: { f in try bulkExpectHistory(f, undo, undone: true, "bulk.undo.\(suffix)") }),
            BenchScenario(
                name: "bulk.redo.\(suffix)",
                prepare: { f in
                    try bulkPrepared(f, redo, placement)
                    f.runResult = try await f.session.undo()
                    try bulkExpectHistory(f, redo, undone: true, "prepared undo")
                },
                run: { f in f.runResult = try await f.session.redo() },
                validate: { f in try bulkExpectHistory(f, redo, undone: false, "bulk.redo.\(suffix)") }),
        ]
    }
}
