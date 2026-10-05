import Foundation
@testable import PorydawApp
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
func runPitchBendChecks(_ report: CheckReport, session: DocumentSession) {
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
    curve.update(x: toX, y: curve.y(at: -4096), fine: true)
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
        curve.points[180] == 8191,
        cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
        message: "a vertex drag previews the moved controller value at full bend")
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

    var modulation = PitchBendKernel(
        lane: .modulation, geometry: geometry,
        startTick: 96, endTick: 192,
        fineTicks: 1, snap: pitchBendFixtureSnap,
        snapUp: pitchBendFixtureSnapUp,
        points: origin, endValue: 0)
    modulation.begin(x: modulation.x(at: 144), y: geometry.canvasY, line: false)
    modulation.finish()
    report.expect(
        modulation.points[144] == 126
            && modulation.value(
                atY: geometry.canvasY
                    + geometry.canvasHeight) == 0,
        cppID: "swiftcore/PitchBendEditingTest::vertexCreation",
        message: "modulation uses the oracle's QRect-height scaling at the top pixel and clamps below zero")
    pitchBendSharedGridPredicates(report, session: session)
    pitchBendGridRulePredicates(report, suite: session)
    pitchBendReadoutPredicates(report, session: session)
    pitchBendDocumentPredicates(report, session: session)
    pitchBendOwnerLifetimePredicates(report, suite: session)
    pitchBendExternalPreviewPredicates(report, suite: session)
    pitchBendUnterminatedPredicates(report, suite: session)
    pitchBendParityPredicates(report, suite: session)
    pitchBendControllerPredicates(report, session: session)
    pitchBendResetPredicates(report, session: session)
    pitchBendSetterPredicates(report, session: session)
    pitchBendFineRampPredicates(report, session: session)
    pitchBendVertexPredicates(report, suite: session)
}
