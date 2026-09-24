import PorydawApp

@MainActor
func runPitchBendChecks(_ report: CheckReport) {
    let geometry = PitchBendGeometry(fontPx: 14, lineSpacing: 17, dpr: 2)
    let origin = [96: 0, 192: 0]
    var curve = PitchBendKernel(lane: .pitch, geometry: geometry,
                                startTick: 96, endTick: 192,
                                snapTicks: 12, fineTicks: 1,
                                points: origin, endValue: 0)
    let fromX = curve.x(at: 120)
    let toX = curve.x(at: 168)
    curve.begin(x: fromX, y: curve.y(at: 4096), line: true)
    curve.update(x: toX, y: curve.y(at: -4096), fine: true)
    report.expect(curve.hasGesture && curve.points[120] != nil
                  && curve.points[144] != nil && curve.points[168] != nil
                  && curve.points[144] != curve.points[120]
                  && curve.points[144] != curve.points[168]
                  && curve.points[96] == 0 && curve.points[192] == 0,
                  cppID: "swiftcore/PitchBendEditingTest::shiftDragDrawsLinearRamp",
                  message: "a Shift stroke previews an angled interior ramp without changing endpoints")
    curve.cancelGesture()
    report.expect(!curve.hasGesture && curve.points == origin,
                  cppID: "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand",
                  message: "cancel discards the complete uncommitted stroke")

    curve.begin(x: fromX, y: curve.y(at: 4096), line: false)
    curve.update(x: toX, y: curve.y(at: -4096), fine: false)
    curve.finish()
    report.expect(curve.points[120] != nil && curve.points[132] != nil
                  && curve.points[144] != nil && curve.points[156] != nil
                  && curve.points[168] != nil,
                  cppID: "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand",
                  message: "freehand stroke fills each crossed snap cell")
    let chosenTick = 144
    guard let chosenValue = curve.points[chosenTick] else {
        report.fail("swiftcore/PitchBendEditingTest::vertexHitTestAndSelection",
                    "the drawn curve lacks its middle vertex")
        return
    }
    let vertex = curve.hitTest(x: curve.x(at: chosenTick), y: curve.y(at: chosenValue))
    report.expect(vertex?.tick == chosenTick,
                  cppID: "swiftcore/PitchBendEditingTest::vertexHitTestAndSelection",
                  message: "the middle vertex is hit at its painted position")
    let beforeMove = curve.points
    curve.begin(x: curve.x(at: chosenTick), y: curve.y(at: chosenValue), line: false)
    curve.update(x: curve.x(at: 180), y: curve.y(at: 8191), fine: true)
    report.expect(curve.points[180] != nil && curve.points[chosenTick] == nil
                  && curve.points[192] == 0,
                  cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
                  message: "dragging an interior vertex moves it but preserves the note-off endpoint")
    curve.cancelGesture()
    report.expect(curve.points == beforeMove,
                  cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
                  message: "cancelling a vertex move restores the original curve")
    curve.select(chosenTick)
    report.expect(curve.removeSelectedVertex() && curve.points[chosenTick] == nil
                  && curve.points[192] == 0,
                  cppID: "swiftcore/PitchBendEditingTest::vertexDeletion",
                  message: "Delete removes only the selected interior vertex")

    var modulation = PitchBendKernel(lane: .modulation, geometry: geometry,
                                     startTick: 96, endTick: 192,
                                     snapTicks: 12, fineTicks: 1,
                                     points: origin, endValue: 0)
    modulation.begin(x: modulation.x(at: 144), y: geometry.canvasY, line: false)
    modulation.finish()
    report.expect(modulation.points[144] == 126 && modulation.value(atY: geometry.canvasY
                  + geometry.canvasHeight) == 0,
                  cppID: "swiftcore/PitchBendEditingTest::vertexCreation",
                  message: "modulation uses the oracle's QRect-height scaling at the top pixel and clamps below zero")
}
