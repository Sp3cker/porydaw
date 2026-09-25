import Foundation
@testable import PorydawApp
import PorydawCore

// Pencil-stroke scenarios paired with gestures.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationPencilStrokeFilters(_ report: CheckReport, suite: DocumentSession,
                                         service: ProjectService) {
    func pencilSample(_ rawTick: Double, _ value: Double) -> AutomationPencilTransaction.Sample {
        AutomationPencilTransaction.Sample(
            rawTick: rawTick, logicalX: rawTick, logicalY: 60,
            point: AutomationLanePoint(tick: Tick(rawTick.rounded(.down)), value: Int(value)),
            continuousValue: value)
    }
    func pencilCell(_ begin: Tick) -> AutomationGridCell {
        AutomationGridCell(tickBegin: begin, tickEnd: begin + 24)
    }
    let jitterID = "automation/AutomationEditingTest::pencilSubCellHorizontalJitterDoesNotAlterStroke"
    let jitterLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let jitterFacts = jitterLane.facts(jitterLane.modulationLane)
    let jitterCells = [pencilCell(24), pencilCell(48), pencilCell(72)]
    guard var jitter = AutomationPencilTransaction(
        facts: jitterFacts, firstSample: pencilSample(36, 48),
        firstCell: jitterCells[0], clockTicks: 24) else {
        report.fail(jitterID, "the jitter stroke did not start")
        return
    }
    let slop = jitterLane.page.geometry.nodeDragActivationDistance
    let jittered = jitter.sampleValue(logicalX: 38, logicalY: 60, locking: false, freehand: false,
                                      verticalSlopDistance: slop, plotHeight: 120)
    report.expectEqual(expected: 48.0, actual: jittered, cppID: jitterID,
                       what: "pure horizontal jitter keeps the stroke's continuous value")
    jitter.applySnappedSegment(pencilSample(38, jittered), cells: [jitterCells[0]])
    report.expectEqual(expected: 1, actual: jitter.strokePoints.count, cppID: jitterID,
                       what: "a same-cell revisit keeps one point for the cell")
    jitter.applySnappedSegment(pencilSample(60, 48), cells: [jitterCells[1]])
    jitter.applySnappedSegment(pencilSample(84, 48), cells: [jitterCells[2]])
    report.expectEqual(expected: ["24:48", "48:48", "72:48"], actual: jitterLane.laneValues(jitter.strokePoints),
                       cppID: jitterID, what: "one point per crossed cell holds the jittered value")
    let zigzagID = "automation/AutomationEditingTest::pencilZigzagStrokePreservesDirectionalExtrema"
    let zigzagLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let zigzagFacts = zigzagLane.facts(zigzagLane.modulationLane)
    let zigzagValues = [32, 100, 28, 92, 44, 84]
    let zigzagCells = (0..<6).map { pencilCell(Tick(24 + $0 * 24)) }
    guard var zigzag = AutomationPencilTransaction(
        facts: zigzagFacts, firstSample: pencilSample(36, Double(zigzagValues[0])),
        firstCell: zigzagCells[0], clockTicks: 24) else {
        report.fail(zigzagID, "the zigzag stroke did not start")
        return
    }
    for index in 1..<6 {
        zigzag.applySnappedSegment(
            pencilSample(Double(36 + index * 24), Double(zigzagValues[index])),
            cells: [zigzagCells[index]])
    }
    report.expectEqual(expected: (0..<6).map { Tick(24 + $0 * 24) }, actual: zigzag.strokePoints.map(\.tick),
                       cppID: zigzagID, what: "the zigzag keeps one point per crossed cell")
    report.expectEqual(expected: zigzagValues, actual: zigzag.strokePoints.map(\.value), cppID: zigzagID,
                       what: "each zigzag cell holds its own extremum")
    let extrema = zigzag.strokePoints.map(\.value)
    report.expect(extrema[0] < extrema[1] && extrema[1] > extrema[2] && extrema[2] < extrema[3]
                      && extrema[3] > extrema[4] && extrema[4] < extrema[5],
                  cppID: zigzagID, message: "the zigzag preserves every directional extremum")
    let verticalID = "automation/AutomationEditingTest::pencilVerticalMotionInSingleCellRetainsFinalValue"
    let verticalLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let verticalFacts = verticalLane.facts(verticalLane.modulationLane)
    let verticalCell = pencilCell(24)
    guard var vertical = AutomationPencilTransaction(
        facts: verticalFacts, firstSample: pencilSample(36, 32),
        firstCell: verticalCell, clockTicks: 24) else {
        report.fail(verticalID, "the vertical stroke did not start")
        return
    }
    vertical.applySnappedSegment(pencilSample(36, 96), cells: [verticalCell])
    report.expectEqual(expected: [AutomationLanePoint(tick: 24, value: 96)], actual: vertical.strokePoints,
                       cppID: verticalID,
                       what: "vertical motion in one cell keeps only the final value")
    let densityID = "automation/AutomationEditingTest::pencilDiagonalStrokeEventDensityInvariance"
    let densityLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let densityFacts = densityLane.facts(densityLane.modulationLane)
    let densityCells = (0..<6).map { pencilCell(Tick(24 + $0 * 24)) }
    func densityStroke(intermediates: Int) -> [AutomationLanePoint]? {
        guard var stroke = AutomationPencilTransaction(
            facts: densityFacts, firstSample: pencilSample(36, 8),
            firstCell: densityCells[0], clockTicks: 24) else { return nil }
        for step in 1...intermediates {
            let rawTick = 36 + 120 * Double(step) / Double(intermediates + 1)
            stroke.applySnappedSegment(pencilSample(rawTick, 8 + 112 * (rawTick - 36) / 120),
                                       cells: densityCells)
        }
        stroke.applySnappedSegment(pencilSample(156, 120), cells: densityCells)
        return stroke.completion().points
    }
    guard let sparse = densityStroke(intermediates: 10),
          let dense = densityStroke(intermediates: 50) else {
        report.fail(densityID, "the density strokes did not start")
        return
    }
    report.expect(!sparse.isEmpty, cppID: densityID,
                  message: "the sparse diagonal stroke writes points")
    report.expectEqual(expected: sparse, actual: dense, cppID: densityID,
                       what: "10 vs 50 intermediate samples give identical completion points")
    let backtrackID = "automation/AutomationEditingTest::pencilBacktrackingStrokeRetainsExtremaAndLatestRevisit"
    let backtrackLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let backtrackFacts = backtrackLane.facts(backtrackLane.modulationLane)
    let outward = [pencilCell(24), pencilCell(48), pencilCell(72)]
    guard var backtrack = AutomationPencilTransaction(
        facts: backtrackFacts, firstSample: pencilSample(36, 28),
        firstCell: outward[0], clockTicks: 24) else {
        report.fail(backtrackID, "the backtracking stroke did not start")
        return
    }
    backtrack.applySnappedSegment(pencilSample(84, 100), cells: outward)
    backtrack.applySnappedSegment(pencilSample(36, 68), cells: Array(outward.reversed()))
    report.expectEqual(expected: ["24:68", "48:84", "72:100"], actual: backtrackLane.laneValues(backtrack.strokePoints),
                       cppID: backtrackID,
                       what: "revisited cells hold the leftward values while the far extremum stands")
    report.expectEqual(expected: [Tick(24), Tick(48), Tick(72)], actual: backtrack.strokePoints.map(\.tick),
                       cppID: backtrackID, what: "the backtracking stroke stays sorted by tick")
}

@MainActor
func drawerAutomationPencilStrokeModifiers(_ report: CheckReport, suite: DocumentSession,
                                           service: ProjectService) {
    func pencilSample(_ rawTick: Double, _ value: Double) -> AutomationPencilTransaction.Sample {
        AutomationPencilTransaction.Sample(
            rawTick: rawTick, logicalX: rawTick, logicalY: 60,
            point: AutomationLanePoint(tick: Tick(rawTick.rounded(.down)), value: Int(value)),
            continuousValue: value)
    }
    func pencilCell(_ begin: Tick) -> AutomationGridCell {
        AutomationGridCell(tickBegin: begin, tickEnd: begin + 24)
    }
    let shiftID = "automation/AutomationEditingTest::pencilShiftModifierLocksValueDimension"
    let lockedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let lockedFacts = lockedLane.facts(lockedLane.modulationLane)
    let lockedCells = [pencilCell(24), pencilCell(48), pencilCell(72)]
    guard var locked = AutomationPencilTransaction(
        facts: lockedFacts, firstSample: pencilSample(36, 64),
        firstCell: lockedCells[0], clockTicks: 24) else {
        report.fail(shiftID, "the locked stroke did not start")
        return
    }
    let slop = lockedLane.page.geometry.nodeDragActivationDistance
    let firstLocked = locked.sampleValue(logicalX: 60, logicalY: 10, locking: true, freehand: false,
                                         verticalSlopDistance: slop, plotHeight: 120)
    let secondLocked = locked.sampleValue(logicalX: 84, logicalY: 110, locking: true,
                                          freehand: false, verticalSlopDistance: slop,
                                          plotHeight: 120)
    report.expectEqual(expected: 64.0, actual: firstLocked, cppID: shiftID,
                       what: "a locked run keeps the initial value")
    report.expectEqual(expected: 64.0, actual: secondLocked, cppID: shiftID,
                       what: "a locked run ignores later vertical travel")
    locked.applySnappedSegment(pencilSample(60, firstLocked), cells: [lockedCells[1]])
    locked.applySnappedSegment(pencilSample(84, secondLocked), cells: [lockedCells[2]])
    report.expectEqual(expected: ["24:64", "48:64", "72:64"], actual: lockedLane.laneValues(locked.strokePoints),
                       cppID: shiftID, what: "the locked stroke writes its constant initial value")
    let unlockedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard var unlocked = AutomationPencilTransaction(
        facts: unlockedLane.facts(unlockedLane.modulationLane),
        firstSample: pencilSample(36, 64), firstCell: lockedCells[0], clockTicks: 24) else {
        report.fail(shiftID, "the unlocked stroke did not start")
        return
    }
    let unlockedValue = unlocked.sampleValue(logicalX: 60, logicalY: 10, locking: false,
                                             freehand: false, verticalSlopDistance: slop,
                                             plotHeight: 120)
    report.expect(unlockedValue != 64, cppID: shiftID,
                  message: "the same travel unlocked moves the value")
    let controlID = "automation/AutomationEditingTest::pencilControlModifierDrawsUnsnappedClockQuantizedPoints"
    let freehandLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard var freehand = AutomationPencilTransaction(
        facts: freehandLane.facts(freehandLane.modulationLane),
        firstSample: pencilSample(24, 30), firstCell: pencilCell(24), clockTicks: 6) else {
        report.fail(controlID, "the freehand stroke did not start")
        return
    }
    freehand.applyFreehandSegment(pencilSample(31.5, 90))
    report.expectEqual(expected: [Tick(24), Tick(30)], actual: freehand.strokePoints.map(\.tick), cppID: controlID,
                       what: "a freehand run lands on clock ticks off the snapped grid")
    report.expect(freehand.strokePoints.allSatisfy { $0.tick % 6 == 0 }, cppID: controlID,
                  message: "every freehand point is clock-quantized")
    report.expect(freehand.strokePoints.contains { $0.tick % 24 != 0 }, cppID: controlID,
                  message: "the freehand run escapes the snapped cell lattice")
    let mixedID = "automation/AutomationEditingTest::pencilMixedModifierComposesFreehandAndSnappedSegments"
    let mixedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard var mixed = AutomationPencilTransaction(
        facts: mixedLane.facts(mixedLane.modulationLane),
        firstSample: pencilSample(36, 36), firstCell: pencilCell(24), clockTicks: 6) else {
        report.fail(mixedID, "the mixed stroke did not start")
        return
    }
    mixed.applySnappedSegment(pencilSample(60, 76), cells: [pencilCell(24), pencilCell(48)])
    mixed.applyFreehandSegment(pencilSample(70.5, 104))
    report.expectEqual(expected: [Tick(24), Tick(48), Tick(60), Tick(66)], actual: mixed.strokePoints.map(\.tick),
                       cppID: mixedID,
                       what: "snapped then freehand segments compose contiguously")
    report.expectEqual(expected: 36, actual: mixed.strokePoints.first?.value ?? -1, cppID: mixedID,
                       what: "the snapped head keeps its cell value")
    report.expectEqual(expected: Tick(24), actual: mixed.tickBegin, cppID: mixedID,
                       what: "the mixed stroke spans from its first cell")
    let altID = "automation/AutomationEditingTest::pencilAltModifierIsIgnoredDuringStroke"
    let plainLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    plainLane.activate(plainLane.panLane)
    plainLane.page.isPencilMode = true
    let plainBits = drawerAutomationQtModifiers(AutomationModifiers())
    guard plainLane.page.pointerPress(x: plainLane.x(48), y: plainLane.y(plainLane.panLane, 36),
                                      surface: 1, button: 1, modifiers: plainBits) else {
        report.fail(altID, "the plain stroke did not start")
        return
    }
    plainLane.page.pointerMove(x: plainLane.x(120), y: plainLane.y(plainLane.panLane, 96),
                               buttons: 1, modifiers: plainBits)
    guard plainLane.page.pointerRelease(x: plainLane.x(120), y: plainLane.y(plainLane.panLane, 96),
                                        button: 1, modifiers: plainBits) else {
        report.fail(altID, "the plain stroke did not commit")
        return
    }
    let altLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    altLane.activate(altLane.panLane)
    altLane.page.isPencilMode = true
    let altBits = drawerAutomationQtModifiers(AutomationModifiers(fine: true))
    guard altLane.page.pointerPress(x: altLane.x(48), y: altLane.y(altLane.panLane, 36),
                                    surface: 1, button: 1, modifiers: altBits) else {
        report.fail(altID, "the fine stroke did not start")
        return
    }
    altLane.page.pointerMove(x: altLane.x(120), y: altLane.y(altLane.panLane, 96),
                             buttons: 1, modifiers: altBits)
    guard altLane.page.pointerRelease(x: altLane.x(120), y: altLane.y(altLane.panLane, 96),
                                      button: 1, modifiers: altBits) else {
        report.fail(altID, "the fine stroke did not commit")
        return
    }
    let plain = plainLane.values(plainLane.panLane)
    report.expect(!plain.isEmpty, cppID: altID, message: "the plain stroke writes the empty lane")
    report.expectEqual(expected: plain, actual: altLane.values(altLane.panLane), cppID: altID,
                       what: "the fine modifier leaves the stroke unchanged")
}
