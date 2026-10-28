import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

// Pencil-stroke scenarios paired with gestures.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationPencilStrokeFilters(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
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
    guard
        var jitter = AutomationPencilTransaction(
            facts: jitterFacts, firstSample: pencilSample(36, 48),
            firstCell: jitterCells[0], clockTicks: 24)
    else {
        report.fail(jitterID, "the jitter stroke did not start")
        return
    }
    let slop = jitterLane.page.geometry.nodeDragActivationDistance
    report.expect(slop > 0, cppID: jitterID, message: "the activation slop is positive")
    let jittered = jitter.sampleValue(
        logicalX: 38, logicalY: 60, locking: false, freehand: false,
        verticalSlopDistance: slop, plotHeight: 120)
    report.expectEqual(
        expected: 48.0, actual: jittered, cppID: jitterID,
        what: "pure horizontal jitter keeps the stroke's continuous value")
    jitter.applySnappedSegment(pencilSample(38, jittered), cells: [jitterCells[0]])
    report.expectEqual(
        expected: 1, actual: jitter.strokePoints.count, cppID: jitterID,
        what: "a same-cell revisit keeps one point for the cell")
    jitter.applySnappedSegment(pencilSample(60, 48), cells: [jitterCells[1]])
    jitter.applySnappedSegment(pencilSample(84, 48), cells: [jitterCells[2]])
    report.expectEqual(
        expected: ["24:48", "48:48", "72:48"], actual: jitterLane.laneValues(jitter.strokePoints),
        cppID: jitterID, what: "one point per crossed cell holds the jittered value")
    let zigzagID = "automation/AutomationEditingTest::pencilZigzagStrokePreservesDirectionalExtrema"
    let zigzagLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let zigzagFacts = zigzagLane.facts(zigzagLane.modulationLane)
    let zigzagValues: [Int] = [32, 100, 28, 92, 44, 84]
    let zigzagCells: [AutomationGridCell] = (0..<6).map { (index: Int) in pencilCell(Tick(24 + index * 24)) }
    guard
        var zigzag = AutomationPencilTransaction(
            facts: zigzagFacts, firstSample: pencilSample(36, Double(zigzagValues[0])),
            firstCell: zigzagCells[0], clockTicks: 24)
    else {
        report.fail(zigzagID, "the zigzag stroke did not start")
        return
    }
    for index in 1..<6 {
        zigzag.applySnappedSegment(
            pencilSample(Double(36 + index * 24), Double(zigzagValues[index])),
            cells: [zigzagCells[index]])
    }
    report.expectEqual(
        expected: (0..<6).map { (index: Int) -> Tick in Tick(24 + index * 24) },
        actual: zigzag.strokePoints.map(\.tick),
        cppID: zigzagID, what: "the zigzag keeps one point per crossed cell")
    report.expectEqual(
        expected: zigzagValues, actual: zigzag.strokePoints.map(\.value), cppID: zigzagID,
        what: "each zigzag cell holds its own extremum")
    let extrema = zigzag.strokePoints.map(\.value)
    report.expect(
        extrema[0] < extrema[1] && extrema[1] > extrema[2] && extrema[2] < extrema[3]
            && extrema[3] > extrema[4] && extrema[4] < extrema[5],
        cppID: zigzagID, message: "the zigzag preserves every directional extremum")
    let verticalID = "automation/AutomationEditingTest::pencilVerticalMotionInSingleCellRetainsFinalValue"
    let verticalLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let verticalFacts = verticalLane.facts(verticalLane.modulationLane)
    let verticalCell = pencilCell(24)
    guard
        var vertical = AutomationPencilTransaction(
            facts: verticalFacts, firstSample: pencilSample(36, 32),
            firstCell: verticalCell, clockTicks: 24)
    else {
        report.fail(verticalID, "the vertical stroke did not start")
        return
    }
    vertical.applySnappedSegment(pencilSample(36, 96), cells: [verticalCell])
    report.expectEqual(
        expected: [AutomationLanePoint(tick: 24, value: 96)], actual: vertical.strokePoints,
        cppID: verticalID,
        what: "vertical motion in one cell keeps only the final value")
    let densityID = "automation/AutomationEditingTest::pencilDiagonalStrokeEventDensityInvariance"
    let densityLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let densityFacts = densityLane.facts(densityLane.modulationLane)
    let densityCells: [AutomationGridCell] = (0..<6).map { (index: Int) in pencilCell(Tick(24 + index * 24)) }
    func densityStroke(intermediates: Int) -> [AutomationLanePoint]? {
        guard
            var stroke = AutomationPencilTransaction(
                facts: densityFacts, firstSample: pencilSample(36, 8),
                firstCell: densityCells[0], clockTicks: 24)
        else { return nil }
        for step in 1...intermediates {
            let rawTick = 36 + 120 * Double(step) / Double(intermediates + 1)
            stroke.applySnappedSegment(
                pencilSample(rawTick, 8 + 112 * (rawTick - 36) / 120),
                cells: densityCells)
        }
        stroke.applySnappedSegment(pencilSample(156, 120), cells: densityCells)
        return stroke.completion().points
    }
    guard let sparse = densityStroke(intermediates: 10),
        let dense = densityStroke(intermediates: 50)
    else {
        report.fail(densityID, "the density strokes did not start")
        return
    }
    report.expect(
        !sparse.isEmpty, cppID: densityID,
        message: "the sparse diagonal stroke writes points")
    report.expectEqual(
        expected: sparse, actual: dense, cppID: densityID,
        what: "10 vs 50 intermediate samples give identical completion points")
    let requested: [Int] = [8, 30, 53, 75, 98, 120]
    report.expect(
        sparse.count >= requested.count
            && dense.count >= requested.count
            && zip(densityCells, requested).enumerated().allSatisfy {
                let (index, sample) = $0
                return sparse[index].tick == sample.0.tickBegin
                    && dense[index].tick == sample.0.tickBegin
                    && abs(sparse[index].value - sample.1) <= 1
                    && abs(dense[index].value - sample.1) <= 1
            }
            && sparse == dense,
        cppID: densityID,
        message: "sparse and dense strokes commit identical points within one of the requested value")
    let backtrackID = "automation/AutomationEditingTest::pencilBacktrackingStrokeRetainsExtremaAndLatestRevisit"
    let backtrackLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let backtrackFacts = backtrackLane.facts(backtrackLane.modulationLane)
    let outward = [pencilCell(24), pencilCell(48), pencilCell(72)]
    guard
        var backtrack = AutomationPencilTransaction(
            facts: backtrackFacts, firstSample: pencilSample(36, 28),
            firstCell: outward[0], clockTicks: 24)
    else {
        report.fail(backtrackID, "the backtracking stroke did not start")
        return
    }
    backtrack.applySnappedSegment(pencilSample(84, 100), cells: outward)
    backtrack.applySnappedSegment(pencilSample(36, 68), cells: Array(outward.reversed()))
    report.expectEqual(
        expected: ["24:68", "48:84", "72:100"], actual: backtrackLane.laneValues(backtrack.strokePoints),
        cppID: backtrackID,
        what: "revisited cells hold the leftward values while the far extremum stands")
    report.expectEqual(
        expected: [Tick(24), Tick(48), Tick(72)], actual: backtrack.strokePoints.map(\.tick),
        cppID: backtrackID, what: "the backtracking stroke stays sorted by tick")
}

@MainActor
func drawerAutomationPencilStrokeModifiers(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
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
    guard
        var locked = AutomationPencilTransaction(
            facts: lockedFacts, firstSample: pencilSample(36, 64),
            firstCell: lockedCells[0], clockTicks: 24)
    else {
        report.fail(shiftID, "the locked stroke did not start")
        return
    }
    let slop = lockedLane.page.geometry.nodeDragActivationDistance
    let firstLocked = locked.sampleValue(
        logicalX: 60, logicalY: 10, locking: true, freehand: false,
        verticalSlopDistance: slop, plotHeight: 120)
    let secondLocked = locked.sampleValue(
        logicalX: 84, logicalY: 110, locking: true,
        freehand: false, verticalSlopDistance: slop,
        plotHeight: 120)
    report.expectEqual(
        expected: 64.0, actual: firstLocked, cppID: shiftID,
        what: "a locked run keeps the initial value")
    report.expectEqual(
        expected: 64.0, actual: secondLocked, cppID: shiftID,
        what: "a locked run ignores later vertical travel")
    locked.applySnappedSegment(pencilSample(60, firstLocked), cells: [lockedCells[1]])
    locked.applySnappedSegment(pencilSample(84, secondLocked), cells: [lockedCells[2]])
    report.expectEqual(
        expected: ["24:64", "48:64", "72:64"], actual: lockedLane.laneValues(locked.strokePoints),
        cppID: shiftID, what: "the locked stroke writes its constant initial value")
    let unlockedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard
        var unlocked = AutomationPencilTransaction(
            facts: unlockedLane.facts(unlockedLane.modulationLane),
            firstSample: pencilSample(36, 64), firstCell: lockedCells[0], clockTicks: 24)
    else {
        report.fail(shiftID, "the unlocked stroke did not start")
        return
    }
    let unlockedValue = unlocked.sampleValue(
        logicalX: 60, logicalY: 10, locking: false,
        freehand: false, verticalSlopDistance: slop,
        plotHeight: 120)
    report.expect(
        unlockedValue != 64, cppID: shiftID,
        message: "the same travel unlocked moves the value")
    let controlID = "automation/AutomationEditingTest::pencilControlModifierDrawsUnsnappedClockQuantizedPoints"
    let freehandLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard
        var freehand = AutomationPencilTransaction(
            facts: freehandLane.facts(freehandLane.modulationLane),
            firstSample: pencilSample(24, 30), firstCell: pencilCell(24), clockTicks: 6)
    else {
        report.fail(controlID, "the freehand stroke did not start")
        return
    }
    freehand.applyFreehandSegment(pencilSample(31.5, 90))
    report.expectEqual(
        expected: [Tick(24), Tick(30)], actual: freehand.strokePoints.map(\.tick), cppID: controlID,
        what: "a freehand run lands on clock ticks off the snapped grid")
    report.expect(
        freehand.strokePoints.allSatisfy { $0.tick % 6 == 0 }, cppID: controlID,
        message: "every freehand point is clock-quantized")
    report.expect(
        freehand.strokePoints.contains { $0.tick % 24 != 0 }, cppID: controlID,
        message: "the freehand run escapes the snapped cell lattice")
    let densityControlID = "automation/AutomationEditingTest::pencilControlModifierDrawsUnsnappedClockQuantizedPoints"
    let densityControlLane = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        modulation: [])
    let start = pencilSample(31.25, 30)
    let turn = pencilSample(103.375, 90)
    let reverseTurn = pencilSample(103.375, 60)
    let far = pencilSample(151.625, 30)
    let end = pencilSample(55.75, 90)
    func freehandValues(reverse: Bool, dense: Bool) -> [AutomationLanePoint]? {
        guard
            var stroke = AutomationPencilTransaction(
                facts: densityControlLane.facts(densityControlLane.modulationLane),
                firstSample: start, firstCell: pencilCell(24), clockTicks: 6)
        else { return nil }
        var previous = start
        for next in (reverse ? [far, reverseTurn, end] : [turn, far]) {
            if dense {
                for step in 1...3 {
                    let fraction = Double(step) / 4
                    let tick = previous.rawTick + (next.rawTick - previous.rawTick) * fraction
                    let value =
                        previous.continuousValue
                        + (next.continuousValue - previous.continuousValue) * fraction
                    stroke.applyFreehandSegment(pencilSample(tick, value))
                }
            }
            stroke.applyFreehandSegment(next)
            previous = next
        }
        return stroke.completion().points
    }
    func heldNear(_ points: [AutomationLanePoint], tick: Tick, requested: Int) -> Bool {
        AutomationLaneReplacement.held(points, at: tick, inclusive: true)
            .map { abs($0 - requested) <= 1 } == true
    }
    if let forwardSparse = freehandValues(reverse: false, dense: false),
        let forwardDense = freehandValues(reverse: false, dense: true),
        let reverseSparse = freehandValues(reverse: true, dense: false),
        let reverseDense = freehandValues(reverse: true, dense: true)
    {
        report.expect(
            heldNear(forwardSparse, tick: 102, requested: 90)
                && heldNear(forwardDense, tick: 102, requested: 90)
                && heldNear(forwardSparse, tick: 150, requested: 30)
                && heldNear(forwardDense, tick: 150, requested: 30)
                && heldNear(reverseSparse, tick: 102, requested: 60)
                && heldNear(reverseDense, tick: 102, requested: 60)
                && heldNear(reverseSparse, tick: 54, requested: 90)
                && heldNear(reverseDense, tick: 54, requested: 90),
            cppID: densityControlID,
            message: "sparse and dense freehand turns and ends stay within one of their requested values")
    } else {
        report.fail(densityControlID, "the freehand density strokes did not start")
    }
    let mixedID = "automation/AutomationEditingTest::pencilMixedModifierComposesFreehandAndSnappedSegments"
    let mixedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard
        var mixed = AutomationPencilTransaction(
            facts: mixedLane.facts(mixedLane.modulationLane),
            firstSample: pencilSample(36, 36), firstCell: pencilCell(24), clockTicks: 6)
    else {
        report.fail(mixedID, "the mixed stroke did not start")
        return
    }
    mixed.applySnappedSegment(pencilSample(60, 76), cells: [pencilCell(24), pencilCell(48)])
    mixed.applyFreehandSegment(pencilSample(70.5, 104))
    report.expect(
        mixed.completion().points.first(where: { $0.tick == 66 })
            .map { abs($0.value - 104) <= 1 } == true,
        cppID: mixedID, message: "the freehand end value is within one of the requested sample")
    report.expectEqual(
        expected: [Tick(24), Tick(48), Tick(60), Tick(66)], actual: mixed.strokePoints.map(\.tick),
        cppID: mixedID,
        what: "snapped then freehand segments compose contiguously")
    report.expectEqual(
        expected: 36, actual: mixed.strokePoints.first?.value ?? -1, cppID: mixedID,
        what: "the snapped head keeps its cell value")
    report.expectEqual(
        expected: Tick(24), actual: mixed.tickBegin, cppID: mixedID,
        what: "the mixed stroke spans from its first cell")
    let altID = "automation/AutomationEditingTest::pencilAltModifierIsIgnoredDuringStroke"
    let plainLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    plainLane.activate(plainLane.panLane)
    plainLane.page.isPencilMode = true
    let plainBits = drawerAutomationQtModifiers(AutomationModifiers())
    let plainBefore = plainLane.snapshot
    guard
        plainLane.page.pointerPress(
            x: plainLane.x(48), y: plainLane.y(plainLane.panLane, 36),
            surface: 1, button: 1, modifiers: plainBits)
    else {
        report.fail(altID, "the plain stroke did not start")
        return
    }
    plainLane.page.pointerMove(
        x: plainLane.x(120), y: plainLane.y(plainLane.panLane, 96),
        buttons: 1, modifiers: plainBits)
    report.expectEqual(
        expected: plainBefore, actual: plainLane.snapshot, cppID: altID,
        what: "a pencil preview mutates nothing until release")
    guard
        plainLane.page.pointerRelease(
            x: plainLane.x(120), y: plainLane.y(plainLane.panLane, 96),
            button: 1, modifiers: plainBits)
    else {
        report.fail(altID, "the plain stroke did not commit")
        return
    }
    let altLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    altLane.activate(altLane.panLane)
    altLane.page.isPencilMode = true
    let altBits = drawerAutomationQtModifiers(AutomationModifiers(fine: true))
    guard
        altLane.page.pointerPress(
            x: altLane.x(48), y: altLane.y(altLane.panLane, 36),
            surface: 1, button: 1, modifiers: altBits)
    else {
        report.fail(altID, "the fine stroke did not start")
        return
    }
    altLane.page.pointerMove(
        x: altLane.x(120), y: altLane.y(altLane.panLane, 96),
        buttons: 1, modifiers: altBits)
    guard
        altLane.page.pointerRelease(
            x: altLane.x(120), y: altLane.y(altLane.panLane, 96),
            button: 1, modifiers: altBits)
    else {
        report.fail(altID, "the fine stroke did not commit")
        return
    }
    let plain = plainLane.values(plainLane.panLane)
    report.expect(!plain.isEmpty, cppID: altID, message: "the plain stroke writes the empty lane")
    report.expectEqual(
        expected: plain, actual: altLane.values(altLane.panLane), cppID: altID,
        what: "the fine modifier leaves the stroke unchanged")
    func pointerProjection(
        _ fixture: drawerAutomationAutomationFixture,
        parameter: AutomationParameter
    ) -> AutomationProjection {
        AutomationProjection(
            camera: fixture.viewport.camera,
            bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
            geometry: fixture.page.geometry,
            snapPolicy: AutomationProjectionCache().snapPolicy(
                viewport: fixture.viewport, font: fixture.page.baseFontPx, dpr: 1),
            songEndTick: fixture.songEndTick,
            displayMaximum: AutomationProjection.displayMaximum(
                snapshot: fixture.laneSnapshot(parameter), range: fixture.page.laneRanges[parameter]))
    }
    let modulation = drawerAutomationAutomationFixture(
        suite: suite, service: service, modulation: [])
    modulation.activate(modulation.modulationLane)
    guard
        modulation.page.openParameterMenu(
            index: modulation.page.catalogIndex(of: modulation.modulationLane), x: 0, y: 0),
        modulation.page.consumeMenuAction(actionId: AutomationMenuAction.range127.rawValue)
    else {
        report.fail(altID, "the empty Modulation stroke requires its full value range")
        return
    }
    modulation.page.isPencilMode = true
    let modulationProjection = pointerProjection(modulation, parameter: modulation.modulationLane)
    let modulationEndX = modulation.x(144)
    let modulationEndY = modulation.y(modulation.modulationLane, 96)
    let modulationTailTick = modulationProjection.insertionTick(atX: modulationEndX, pencil: true)
    let modulationTailValue = modulationProjection.value(
        atY: modulationEndY, metadata: modulation.facts(modulation.modulationLane).metadata)
    guard
        modulation.page.pointerPress(
            x: modulation.x(48),
            y: modulation.y(modulation.modulationLane, 40),
            surface: 1, button: 1)
    else {
        report.fail(altID, "the empty Modulation pencil stroke did not start")
        return
    }
    _ = modulation.page.pointerMove(
        x: modulation.x(96),
        y: modulation.y(modulation.modulationLane, 72), buttons: 1)
    _ = modulation.page.pointerMove(x: modulationEndX, y: modulationEndY, buttons: 1)
    guard
        modulation.page.pointerRelease(
            x: modulationEndX, y: modulationEndY,
            button: 1)
    else {
        report.fail(altID, "the empty Modulation pencil stroke did not commit")
        return
    }
    let modulationTail = modulation.lanePoints(modulation.modulationLane)
        .first { $0.tick == modulationTailTick }
    let tailMatchesPointer =
        modulationTail.map {
            abs(Int($0.value) - modulationTailValue) <= 1
        } ?? false
    let playbackMatchesPointer = modulation.playbackValues(
        modulation.modulationLane,
        at: modulationTailTick
    )
    .contains { abs(Int($0) - modulationTailValue) <= 1 }
    report.expect(
        modulationTailTick == 144 && modulationTailValue == 96
            && tailMatchesPointer && playbackMatchesPointer,
        cppID: altID,
        message: "the empty Modulation pencil tail reaches playback within one value")
    let restoredPan = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 60), (288, 60)])
    restoredPan.activate(restoredPan.panLane)
    restoredPan.page.isPencilMode = true
    let panY = restoredPan.y(restoredPan.panLane, 96)
    let panBefore = restoredPan.snapshot
    let panIndex = restoredPan.document.history.undoIndex
    let panBytes = try? restoredPan.document.state.file.encoded()
    let panProjection = pointerProjection(restoredPan, parameter: restoredPan.panLane)
    let panEndX = restoredPan.x(120)
    let panCell = panProjection.cell(atRawTick: panProjection.rawTick(atX: panEndX))
    let panBoundaryTick = panCell.tickEnd
    report.expect(
        restoredPan.page.pointerPress(
            x: restoredPan.x(48), y: panY,
            surface: 1, button: 1),
        cppID: altID, message: "the pencil press over written Pan starts a held stroke")
    _ = restoredPan.page.pointerMove(x: panEndX, y: panY, buttons: 1)
    report.expect(
        restoredPan.page.pointerRelease(x: panEndX, y: panY, button: 1),
        cppID: altID, message: "the written Pan pencil stroke commits")
    let panPoints = restoredPan.lanePoints(restoredPan.panLane)
    report.expect(
        panBoundaryTick == 126
            && panPoints.contains { $0.tick >= 48 && $0.tick < panBoundaryTick && $0.value != 60 }
            && panPoints.contains { $0.tick == panBoundaryTick && $0.value == 60 }
            && restoredPan.playbackValues(restoredPan.panLane, at: panBoundaryTick)
                == [UInt8(60)],
        cppID: altID,
        message: "the Pan end-cell boundary restores the baseline in playback")
    report.expect(
        restoredPan.document.revision == panBefore.revision + 1
            && restoredPan.document.history.undoIndex == panIndex + 1,
        cppID: altID, message: "the Pan pencil stroke commits one revision and undo index")
    report.expect(
        restoredPan.undo() && restoredPan.document.history.undoIndex == panIndex
            && (try? restoredPan.document.state.file.encoded()) == panBytes,
        cppID: altID, message: "one undo restores the original written Pan bytes")
    report.expectEqual(
        expected: plainBefore.revision + 1,
        actual: plainLane.document.revision, cppID: altID,
        what: "a pencil stroke on an empty lane commits once")
    report.expect(
        plainLane.undo(), cppID: altID,
        message: "the empty-lane stroke is undoable")
    report.expectEqual(
        expected: plainBefore.identity,
        actual: plainLane.snapshot.identity, cppID: altID,
        what: "one undo restores the empty pencil lane")
    report.expect(
        plainLane.values(plainLane.panLane).isEmpty, cppID: altID,
        message: "undo removes the empty-lane stroke")
}
