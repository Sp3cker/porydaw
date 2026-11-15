import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawCore
@testable import PorydawDocument
import QtBridge

func pitchBendFixtureSnap(_ tick: Double, fine: Bool) -> Int {
    let stride = Double(fine ? 1 : 12)
    let lower = (max(0, tick) / stride).rounded(.down) * stride
    return Int(tick - lower <= stride / 2 ? lower : lower + stride)
}

func pitchBendFixtureSnapUp(_ tick: Double, fine: Bool) -> Int {
    let stride = Double(fine ? 1 : 12)
    return Int(((max(0, tick) + 0.5) / stride).rounded(.up) * stride)
}

@MainActor
public func runPitchBendChecks(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let geometry = PitchBendGeometry(fontPx: 14, lineSpacing: 17, dpr: 2)
    let origin = [96: 0, 192: 0]
    var curve = PitchBendKernel(
        lane: .pitch, geometry: geometry,
        startTick: 96, endTick: 192,
        fineTicks: 1, snap: pitchBendFixtureSnap,
        snapUp: pitchBendFixtureSnapUp,
        points: origin, endValue: 0)
    let fromX = curve.x(at: 120)
    let toX = curve.x(at: 168)
    let keyboardBeforeStroke = curve.keyboardTick
    let liveBeforeStroke = curve.liveValue
    curve.begin(x: fromX, y: curve.y(at: 4096), line: true)
    curve.update(x: toX, y: curve.y(at: -4096), fine: false)
    report.expect(
        curve.hasGesture && curve.points[120] != nil
            && curve.points[144] != nil && curve.points[168] != nil
            && curve.points[144] != curve.points[120]
            && curve.points[144] != curve.points[168]
            && curve.points[96] == 0 && curve.points[192] == 0,
        cppID: "swiftcore/PitchBendEditingTest::shiftDragDrawsLinearRamp",
        message: "a Shift stroke previews an angled interior ramp without changing endpoints")
    report.expect(
        curve.liveValue == curve.value(atY: curve.y(at: -4096))
            && curve.liveValue != liveBeforeStroke,
        cppID: "swiftcore/PitchBendEditingTest::shiftDragDrawsLinearRamp",
        message: "moving the stroke previews the live controller value")
    curve.cancelGesture()
    report.expect(
        !curve.hasGesture && curve.points == origin,
        cppID: "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand",
        message: "cancel discards the complete uncommitted stroke")
    report.expect(
        curve.keyboardTick == keyboardBeforeStroke
            && curve.liveValue == liveBeforeStroke,
        cppID: "swiftcore/PitchBendEditingTest::shiftDragDrawsLinearRamp",
        message: "cancelling the preview restores the keyboard cursor and live value")

    curve.begin(x: fromX, y: curve.y(at: 4096), line: false)
    report.expect(
        curve.hasGesture && curve.selectedTick == nil,
        cppID: "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand",
        message: "pressing an empty curve starts a selection-free stroke")
    curve.update(x: toX, y: curve.y(at: -4096), fine: false)
    curve.finish()
    report.expect(
        curve.points[120] != nil && curve.points[132] != nil
            && curve.points[144] != nil && curve.points[156] != nil
            && curve.points[168] != nil,
        cppID: "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand",
        message: "freehand stroke fills each crossed snap cell")
    let chosenTick = 144
    guard let chosenValue = curve.points[chosenTick] else {
        report.fail(
            "swiftcore/PitchBendEditingTest::vertexHitTestAndSelection",
            "the drawn curve lacks its middle vertex")
        return
    }
    let vertex = curve.hitTest(x: curve.x(at: chosenTick), y: curve.y(at: chosenValue))
    report.expect(
        vertex?.tick == chosenTick,
        cppID: "swiftcore/PitchBendEditingTest::vertexHitTestAndSelection",
        message: "the middle vertex is hit at its painted position")
    let beforeMove = curve.points
    curve.begin(x: curve.x(at: chosenTick), y: curve.y(at: chosenValue), line: false)
    curve.update(x: curve.x(at: 180), y: curve.y(at: 8191), fine: true)
    report.expect(
        curve.points[180] != nil && curve.points[chosenTick] == nil
            && curve.points[192] == 0,
        cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
        message: "dragging an interior vertex moves it but preserves the note-off endpoint")
    report.expect(
        curve.points[180] == 2048,
        cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
        message: "Alt moves the vertex vertically at quarter speed while retaining playable pitch steps")
    curve.cancelGesture()
    report.expect(
        curve.points == beforeMove,
        cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
        message: "cancelling a vertex move restores the original curve")
    curve.select(chosenTick)
    report.expect(
        curve.removeSelectedVertex() && curve.points[chosenTick] == nil
            && curve.points[192] == 0,
        cppID: "swiftcore/PitchBendEditingTest::vertexDeletion",
        message: "Delete removes only the selected interior vertex")

    let modulation = PitchBendKernel(
        lane: .modulation, geometry: geometry,
        startTick: 96, endTick: 192,
        fineTicks: 1, snap: pitchBendFixtureSnap,
        snapUp: pitchBendFixtureSnapUp,
        points: origin, endValue: 0)
    report.expect(
        modulation.value(atY: geometry.canvasY + geometry.canvasHeight) == 0,
        cppID: "swiftcore/PitchBendEditingTest::vertexCreation",
        message: "modulation clamps values below the graph to zero")
    pitchBendDenseVertexDragPredicates(report, geometry: geometry)
    pitchBendSharedGridPredicates(report, viewport: viewport)
    pitchBendGridRulePredicates(report, suite: session)
    pitchBendReadoutPredicates(report, viewport: viewport)
    pitchBendDocumentPredicates(report, viewport: viewport)
    pitchBendOwnerLifetimePredicates(report, suite: session)
    pitchBendExternalPreviewPredicates(report, suite: session)
    pitchBendUnterminatedPredicates(report, suite: session)
    pitchBendParityPredicates(report, suite: session)
    pitchBendControllerPredicates(report, viewport: viewport)
    pitchBendResetPredicates(report, viewport: viewport)
    pitchBendSetterPredicates(report, viewport: viewport)
    pitchBendFineRampPredicates(report, viewport: viewport)
    pitchBendVertexPredicates(report, suite: session)
    pitchBendFineVerticalPredicates(report, geometry: geometry)
}

@MainActor
private func pitchBendDenseVertexDragPredicates(_ report: CheckReport, geometry: PitchBendGeometry) {
    let id = "swiftcore/PitchBendEditingTest::denseVertexDragStaysLocal"
    for lane: PitchBendKernel.Lane in [.pitch, .modulation] {
        let originalValue = lane == .pitch ? 3001 : 61
        var original = [96: 0, 192: 0]
        for tick in 100...170 { original[tick] = 0 }
        original[137] = originalValue
        var curve = PitchBendKernel(
            lane: lane, geometry: geometry, startTick: 96, endTick: 192,
            fineTicks: 1, snap: pitchBendFixtureSnap, snapUp: pitchBendFixtureSnapUp,
            points: original, endValue: 0)
        let grabX = curve.x(at: 137) + 2
        let grabY = curve.y(at: originalValue) - 2
        curve.begin(x: grabX, y: grabY, line: false)
        curve.update(x: grabX, y: grabY, fine: false)
        curve.finish()
        report.expect(
            curve.points == original && curve.selectedTick == 137,
            cppID: id, message: "\(lane): selecting an off-grid vertex preserves its exact tick and value")

        curve.setCurve(original, endValue: 0)
        curve.begin(x: grabX, y: grabY, line: false)
        let dy = geometry.canvasHeight / 4
        var vertical = original
        vertical[137] = curve.value(atY: curve.y(at: originalValue) + dy)
        curve.update(x: grabX + 1, y: grabY + dy, fine: false)
        report.expect(
            curve.points == vertical && curve.selectedTick == 137,
            cppID: id, message: "\(lane): a vertical drag changes only the grabbed off-grid vertex")

        curve.update(x: curve.x(at: 144) + 2, y: grabY + dy, fine: false)
        report.expect(
            curve.points == vertical && curve.selectedTick == 137,
            cppID: id, message: "\(lane): an occupied destination never sends the vertex to a distant gap")

        curve.update(x: curve.x(at: 180) + 2, y: grabY, fine: false)
        var moved = original
        moved.removeValue(forKey: 137)
        moved[180] = originalValue
        report.expect(
            curve.points == moved && curve.selectedTick == 180,
            cppID: id, message: "\(lane): a horizontal drag reaches a free tick without changing its value")
        curve.update(x: grabX, y: grabY, fine: false)
        report.expect(
            curve.points == original && curve.selectedTick == 137,
            cppID: id, message: "\(lane): returning to the grab position restores the exact original curve")
        curve.cancelGesture()
    }
}

@MainActor
private func pitchBendFineVerticalPredicates(_ report: CheckReport, geometry: PitchBendGeometry) {
    let id = "swiftcore/PitchBendKernel::altFineVerticalAdjustment"
    for lane: PitchBendKernel.Lane in [.pitch, .modulation, .lfoSpeed] {
        let initial = lane == .pitch ? 2048 : lane == .modulation ? 8 : 32
        let original = [96: initial, 144: initial, 192: 0]
        var curve = PitchBendKernel(
            lane: lane, geometry: geometry, startTick: 96, endTick: 192,
            fineTicks: 1, snap: pitchBendFixtureSnap, snapUp: pitchBendFixtureSnapUp,
            points: original, endValue: 0)
        let x = curve.x(at: 144)
        let y = curve.y(at: initial)
        curve.begin(x: x, y: y, line: false, fine: true)
        curve.update(x: x, y: y - 10, fine: true)
        let fineValue = curve.liveValue
        curve.cancelGesture()
        curve.begin(x: x, y: y, line: false)
        curve.update(x: x, y: y - 10, fine: false)
        let normalDelta = curve.liveValue - initial
        let fineDelta = fineValue - initial
        let step = lane == .pitch ? 128 : 1
        report.expect(
            fineDelta > 0 && fineDelta < normalDelta && abs(4 * fineDelta - normalDelta) <= step * 4,
            cppID: id, message: "\(lane): Alt uses quarter-speed vertical movement at the same pointer distance")
        curve.cancelGesture()

        curve.begin(x: x, y: y, line: false)
        curve.update(x: x, y: y - 10, fine: false)
        let beforeAlt = curve.liveValue
        curve.update(x: x, y: y - 10, fine: true)
        report.expect(
            curve.liveValue == beforeAlt && curve.isFineAdjusting,
            cppID: id, message: "\(lane): pressing Alt without moving preserves the current value")
        curve.update(x: x, y: y - 14, fine: true)
        let beforeRelease = curve.liveValue
        curve.update(x: x, y: y - 14, fine: false)
        report.expect(
            curve.liveValue == beforeRelease && !curve.isFineAdjusting,
            cppID: id, message: "\(lane): releasing Alt does not jump back to absolute pointer mapping")
        curve.cancelGesture()
        report.expect(
            curve.points == original && !curve.isFineAdjusting,
            cppID: id, message: "\(lane): cancel restores the exact curve and clears precision feedback")

        let strokeX = curve.x(at: 120)
        curve.begin(x: strokeX, y: y, line: true, fine: true)
        let initialStrokeValue = curve.liveValue
        curve.update(x: curve.x(at: 168), y: y - 10, fine: true)
        report.expect(
            curve.liveValue > initialStrokeValue
                && abs((curve.liveValue - initialStrokeValue) - fineDelta) <= step
                && curve.points[192] == 0,
            cppID: id, message: "\(lane): fine line strokes use the same vertical sensitivity and preserve note off")
        curve.finish()
        report.expect(!curve.isFineAdjusting, cppID: id, message: "\(lane): finishing clears precision feedback")
    }

    var pitch = PitchBendKernel(
        lane: .pitch, geometry: geometry, startTick: 96, endTick: 192,
        fineTicks: 1, snap: pitchBendFixtureSnap, snapUp: pitchBendFixtureSnapUp,
        points: [96: 0, 144: 0, 192: 0], endValue: 0)
    let x = pitch.x(at: 144)
    let y = pitch.y(at: 0)
    let distance = 128 * 4 * (geometry.canvasHeight - 1) / 16383
    pitch.begin(x: x, y: y, line: false, fine: true)
    for sample in 1...8 {
        pitch.update(x: x, y: y - distance * Double(sample) / 8, fine: true)
    }
    report.expect(
        pitch.liveValue == 128 && pitch.points[144] == 128,
        cppID: id, message: "subpixel fine movement accumulates to the first playable bend near zero")
    pitch.update(x: x, y: y - 10000, fine: true)
    report.expect(pitch.liveValue == 8191, cppID: id, message: "fine movement reaches the exact positive limit")
    pitch.update(x: x, y: y + 10000, fine: true)
    report.expect(pitch.liveValue == -8192, cppID: id, message: "fine movement clamps at the exact negative limit")
    pitch.cancelGesture()
    pitch.begin(x: pitch.x(at: 192), y: y, line: false, fine: true)
    pitch.update(x: pitch.x(at: 192), y: y - 20, fine: true)
    report.expect(
        pitch.points[192] == 0 && !pitch.isFineAdjusting,
        cppID: id, message: "the immutable note-off point neither changes nor advertises an active fine adjustment")
}
