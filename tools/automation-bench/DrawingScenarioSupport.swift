import Foundation
import PorydawCore

@testable import PorydawApp

// Shared state, lane reads, the expected-document model, companion lanes, and pointer strokes
// for the drawing, range, and history scenarios. Nothing here runs inside a timed region except strokes.

struct DrawingPoint {
    var x: Double
    var y: Double
}

struct DrawingStroke {
    var pencil: Bool
    var modifiers: Int
    var press: DrawingPoint
    var moves: [DrawingPoint]
    var release: DrawingPoint { moves.last ?? press }
}

struct DrawingSnapshot {
    var stroke: DrawingStroke?
    var companion: AutomationParameter?
    var before: [AutomationLanePoint] = []
    var companionBefore: [AutomationLanePoint] = []
    var after: [AutomationLanePoint] = []
    var companionAfter: [AutomationLanePoint] = []
    var expected: [AutomationLanePoint] = []
    var companionExpected: [AutomationLanePoint] = []
    var revision: UInt64 = 0
    var undoIndex = 0
    var undoCount = 0
    var gesture: AutomationGesture?
    var frozen: AutomationFrozenFacts?
    var camera: EditorCamera?
    var edit: AutomationLaneEdit?
    var clipData: Data?
    var pasteCursor: Tick = 0
    var pasteTrack = 0
    var pasteSpan: Tick = 0
}

@MainActor
final class DrawingBox {
    var s = DrawingSnapshot()
    func reset() { s = DrawingSnapshot() }
}

// MARK: - Lane reads and the expected-document model

@MainActor
func drawingSources(_ f: BenchFixture, _ parameter: AutomationParameter) -> [AutomationLanePoint] {
    AutomationLaneSnapshot(
        parameter: parameter, in: f.document,
        songEndTick: f.session.timeline.lengthTicks
    ).sources.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }
}

/// Stable tick order: same-tick occurrences keep their document order.
func drawingOrdered(_ points: [AutomationLanePoint]) -> [AutomationLanePoint] {
    points.enumerated().sorted {
        $0.element.tick != $1.element.tick ? $0.element.tick < $1.element.tick : $0.offset < $1.offset
    }.map(\.element)
}

/// A held-span replacement's document contract: `writeLane(from:through:)` and
/// `editTempo` replace every occurrence in the inclusive span with the edit's points.
func drawingApplying(_ edit: AutomationLaneEdit, to before: [AutomationLanePoint]) -> [AutomationLanePoint] {
    drawingOrdered(before.filter { $0.tick < edit.tickBegin || $0.tick > edit.tickEnd } + edit.points)
}

func drawingHeld(_ points: [AutomationLanePoint], at tick: Tick) -> Int? {
    drawingOrdered(points).last { $0.tick <= tick }?.value
}

func drawingDescribe(_ points: [AutomationLanePoint]) -> String {
    let text = points.prefix(12).map { "\($0.tick):\($0.value)" }.joined(separator: " ")
    return points.count > 12 ? "\(text) … (\(points.count) points)" : text
}

@MainActor
func drawingCapture(_ f: BenchFixture, _ box: DrawingBox) {
    box.s.before = drawingSources(f, f.parameter)
    box.s.companionBefore = box.s.companion.map { drawingSources(f, $0) } ?? []
    box.s.revision = f.document.revision
    box.s.undoIndex = f.document.history.undoIndex
    box.s.undoCount = f.document.history.undoCount
}

@MainActor
func drawingExpectLane(_ f: BenchFixture, _ expected: [AutomationLanePoint], _ what: String) throws {
    let actual = drawingOrdered(drawingSources(f, f.parameter))
    try f.check(
        actual == drawingOrdered(expected),
        "\(what): lane is [\(drawingDescribe(actual))], expected [\(drawingDescribe(drawingOrdered(expected)))]")
}

@MainActor
func drawingExpectCompanion(
    _ f: BenchFixture, _ box: DrawingBox,
    _ expected: [AutomationLanePoint], _ what: String
) throws {
    guard let companion = box.s.companion else { return }
    let actual = drawingOrdered(drawingSources(f, companion))
    try f.check(
        actual == drawingOrdered(expected),
        "\(what): companion lane is [\(drawingDescribe(actual))], expected [\(drawingDescribe(drawingOrdered(expected)))]"
    )
}

/// One new applied history entry. `exactRevision` is false after an undo/redo
/// round trip, whose revision numbering is the history's own business.
@MainActor
func drawingExpectOneEdit(
    _ f: BenchFixture, _ box: DrawingBox, _ what: String,
    exactRevision: Bool = true
) throws {
    try f.check(
        !exactRevision || f.document.revision == box.s.revision + 1,
        "\(what): revision \(f.document.revision), expected \(box.s.revision + 1)")
    try f.check(
        f.document.history.undoIndex == box.s.undoIndex + 1
            && f.document.history.undoCount == box.s.undoCount + 1
            && f.document.history.canUndo && !f.document.history.canRedo,
        "\(what): history index/count \(f.document.history.undoIndex)/\(f.document.history.undoCount), expected one new entry after \(box.s.undoIndex)/\(box.s.undoCount)"
    )
}

@MainActor
func drawingExpectUntouched(_ f: BenchFixture, _ box: DrawingBox, _ what: String) throws {
    try f.check(
        f.document.revision == box.s.revision,
        "\(what): revision moved from \(box.s.revision) to \(f.document.revision)")
    try f.check(
        f.document.history.undoIndex == box.s.undoIndex
            && f.document.history.undoCount == box.s.undoCount,
        "\(what): history moved to \(f.document.history.undoIndex)/\(f.document.history.undoCount)")
    try drawingExpectLane(f, box.s.before, what)
    try drawingExpectCompanion(f, box, box.s.companionBefore, what)
}

// MARK: - Companion lane

/// A second written lane on the tested parameter's track, used for multi-lane
/// range deletes, lane-menu clipboard sources, and out-of-gesture writes.
func drawingCompanion(of parameter: AutomationParameter) -> AutomationParameter {
    let track = parameter.track ?? 0
    let pan = AutomationParameter.controlChange(track: track, controller: TimeDefaults.ccPan)
    return parameter == pan ? .controlChange(track: track, controller: TimeDefaults.ccVolume) : pan
}

/// Writes the companion lane: tick zero plus one point between every pair of the
/// tested lane's nodes, values alternating 100/30 (valid for Pan and Volume).
@MainActor
func drawingSeedCompanion(_ f: BenchFixture, _ box: DrawingBox) throws {
    let companion = drawingCompanion(of: f.parameter)
    guard let track = companion.track, let lane = companion.lane else {
        throw BenchFailure(description: "the companion lane has no document lane")
    }
    let writes =
        [LaneWrite(tick: 0, value: 100)]
        + (0..<f.nodes).map {
            LaneWrite(tick: Tick($0 * 24 + 12), value: $0.isMultiple(of: 2) ? 100 : 30)
        }
    f.document.writeLane(track: track, lane: lane, from: 0, through: TimeDefaults.noTick, points: writes)
    f.page.refreshFromDocument()
    box.s.companion = companion
    try f.check(
        drawingSources(f, companion).count == writes.count,
        "the companion lane did not receive its \(writes.count) seeded points")
}

// MARK: - Strokes

/// Two pointer heights 16px and 32px above the dataset's high node, clamped under the plot top, so
/// wide domains (Pitch bend spans 16384 values) still draw pixel-distinct values.
@MainActor
func drawingLevels(_ f: BenchFixture) throws -> (primaryY: Double, alternateY: Double) {
    let metadata = AutomationParameterMetadata(parameter: f.parameter)
    let highY = f.y(max(f.lowValue, f.highValue))
    let topY = max(f.y(metadata.maximum), 0) + 1
    let levels = (primaryY: max(topY, highY - 32), alternateY: max(topY, highY - 16))
    try f.check(
        levels.alternateY - levels.primaryY >= 8 && highY - levels.alternateY >= 8,
        "no room above the dataset for two pixel-distinct drawn values (high node at y \(highY))")
    return levels
}

/// Press at `emptyTick`, then exactly `f.samples` moves spread to the last visible tick (bounded by
/// song end - 24): a fixed on-screen span whatever the node count, crossing at least three grid cells.
@MainActor
func drawingStroke(_ f: BenchFixture, pencil: Bool, modifiers: Int) throws -> DrawingStroke {
    let levels = try drawingLevels(f)
    let songEnd = f.session.timeline.lengthTicks
    let projection = f.page.makeProjection(facts: f.facts(), camera: f.page.liveCamera())
    let pressX = f.x(f.emptyTick)
    var endTick = min(projection.rawTick(atX: f.page.plotWidth - 1), Double(songEnd) - 24)
    let endCell = projection.cell(atRawTick: endTick)
    // The release cell must close before the song end, or no held tail is restored.
    if endCell.tickEnd >= songEnd { endTick = Double(endCell.tickBegin) - 1 }
    let endX = f.session.camera.contentX(tick: endTick)
    let cells = projection.cellsCrossed(from: projection.rawTick(atX: pressX), to: endTick).count
    try f.check(
        endX > pressX && endX <= f.page.plotWidth && cells >= 3,
        "the stroke span x \(pressX)...\(endX) crosses \(cells) grid cells inside a \(f.page.plotWidth)px plot")
    let samples = max(1, f.samples)
    let moves = (1...samples).map { sample -> DrawingPoint in
        let fraction = Double(sample) / Double(samples)
        let y = (samples - sample).isMultiple(of: 2) ? levels.primaryY : levels.alternateY
        return DrawingPoint(x: pressX + (endX - pressX) * fraction, y: y)
    }
    return DrawingStroke(
        pencil: pencil, modifiers: modifiers,
        press: DrawingPoint(x: pressX, y: levels.alternateY), moves: moves)
}

@MainActor
func drawingPress(_ f: BenchFixture, _ stroke: DrawingStroke) -> Bool {
    let pressed = f.page.pointerPress(
        x: stroke.press.x, y: stroke.press.y,
        surface: AutomationInputSurface.plot.rawValue,
        button: AutomationQtButton.left, modifiers: stroke.modifiers)
    for point in stroke.moves {
        _ = f.page.pointerMove(
            x: point.x, y: point.y, buttons: AutomationQtButton.left,
            modifiers: stroke.modifiers)
    }
    return pressed
}

@MainActor
func drawingRelease(_ f: BenchFixture, _ stroke: DrawingStroke) -> Bool {
    f.page.pointerRelease(
        x: stroke.release.x, y: stroke.release.y,
        button: AutomationQtButton.left, modifiers: stroke.modifiers)
}

/// One complete stroke. With a box, the live draft, its frozen facts and camera
/// are retained (three stored references) just before release for validation.
@MainActor
func drawingPerform(_ f: BenchFixture, _ stroke: DrawingStroke, stash box: DrawingBox?) -> Bool {
    _ = drawingPress(f, stroke)
    if let box {
        box.s.gesture = f.page.gesture
        box.s.frozen = f.page.frozen
        box.s.camera = f.page.frozenCamera
    }
    return drawingRelease(f, stroke)
}

@MainActor
func drawingPrepareStroke(_ f: BenchFixture, _ box: DrawingBox, pencil: Bool, modifiers: Int) throws {
    box.reset()
    f.page.isPencilMode = pencil
    box.s.stroke = try drawingStroke(f, pencil: pencil, modifiers: modifiers)
    drawingCapture(f, box)
    try f.check(box.s.before == f.originalPoints, "the prepared lane differs from the fixture dataset")
}
