import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge
private let latticeID = "rollcheck/PianoRollStaticTest::tickRangeWalksFractionalLattice"
private let contentWindowID = "swiftcore/EditorGridCamera::contentWindowBoundaryReversal"

@MainActor
func checkFractionalGridLattice(_ report: CheckReport, session: DocumentSession) {
    let originalCamera = session.camera
    let originalSelection = session.grid.selection
    defer {
        session.grid.setSelection(originalSelection)
        _ = session.mutateCamera { $0 = originalCamera }
    }
    _ = session.mutateCamera { _ = $0.setTimeZoom(384) }
    session.grid.setSelection(.auto)
    let axis = session.grid.axis
    let segment = axis.segmentAt(96)
    report.expect(
        segment.start <= 96, cppID: latticeID,
        message: "A018 fractional window segment begins at or before tick 96")
    report.expect(
        segment.next >= 289, cppID: latticeID,
        message: "A019 fractional window segment reaches past tick 289")
    let left = 96.75
    let right = 289.25
    let begin = TimeDefaults.tick(from: left)
    let end = Tick(ceil(right) + 1)
    var seen: [Tick] = []
    session.grid.forEachSubdivision(from: begin, to: end, camera: session.camera) { tick, _ in
        seen.append(tick)
    }
    var expected: [Tick] = []
    for tick in Tick(96)..<Tick(291) where tick % 24 != 0 {
        expected.append(tick)
    }
    report.expect(
        seen == expected, cppID: latticeID,
        message: "A022 fractional window emits the independently enumerated lattice")
    let stride = session.grid.gridTicksAt(96, camera: session.camera)
    report.expect(
        stride > 0 && stride < segment.beatTicks,
        cppID: latticeID, message: "segment lattice stride is positive")
    var visible: [Tick] = []
    session.grid.forEachSubdivision(from: 96, to: 289, camera: session.camera) { tick, _ in
        visible.append(tick)
    }
    report.expect(
        !visible.isEmpty
            && visible.allSatisfy {
                $0 >= 96 && $0 < 289 && $0 % stride == 0 && $0 % 24 != 0
            }, cppID: latticeID, message: "visible auto sub-grid is culled to the viewport and skips beats")
    _ = session.mutateCamera { _ = $0.setTimeZoom(192) }
    session.grid.setSelection(.musical(16))
    let snap = session.grid.snapTicksAt(96, camera: session.camera)
    let coarse = session.grid.gridTicksAt(96, camera: session.camera)
    report.expect(
        snap >= 3 && 24 % snap == 0 && coarse > 1 && 96 % coarse == 0,
        cppID: latticeID, message: "coarse lattice divides the beat")
    report.expect(
        coarse < segment.beatTicks, cppID: latticeID,
        message: "A025 drawn coarse stride remains below one beat")
    report.expect(
        UInt64(coarse) * 2 < UInt64(segment.next - 96), cppID: latticeID,
        message: "A029 segment has room for two subdivision steps")
    report.expect(
        session.grid.nextSubdivisionTickAfter(96, camera: session.camera) == 96 + coarse
            && session.grid.nextSubdivisionTickAfter(97, camera: session.camera) == 96 + coarse,
        cppID: latticeID, message: "subdivision restarts at the segment anchor")
    var firstOutside: [Tick] = []
    session.grid.forEachSubdivision(from: 97, to: 98, camera: session.camera) { tick, _ in
        firstOutside.append(tick)
    }
    report.expect(
        firstOutside.isEmpty, cppID: latticeID,
        message: "A032 a first candidate beyond the window emits no subdivision")
    var crossingBeat: [Tick] = []
    session.grid.forEachSubdivision(from: 95, to: 110, camera: session.camera) { tick, _ in
        crossingBeat.append(tick)
    }
    report.expect(
        crossingBeat == [102, 108], cppID: latticeID,
        message: "A033 the pre-seam lattice skips the beat but resumes at ticks 102 and 108")
    let midpoint = 96.0 + Double(snap) / 2
    report.expect(
        session.grid.snapTick(midpoint, camera: session.camera) == 96
            && session.grid.snapTick(midpoint - 0.25, camera: session.camera) == 96
            && session.grid.snapTick(midpoint + 0.25, camera: session.camera) == 96 + snap,
        cppID: latticeID, message: "auto tie rounds down")
    report.expectEqual(
        expected: 96,
        actual: session.grid.snapTickDown(midpoint + 0.25, camera: session.camera),
        cppID: latticeID, what: "tie down is floor")
    report.expectEqual(
        expected: 96 + snap,
        actual: session.grid.snapTickUp(midpoint - 0.25, camera: session.camera),
        cppID: latticeID, what: "tie up is ceil")

    let document = session.document
    document.setTimeSignature(tick: 102, numerator: 5, denominatorPower: 3)
    defer {
        _ = document.history.undoDocument()
        _ = document.history.undoDocument()
    }
    report.expect(
        session.grid.axis.segmentAt(102).start == 102, cppID: latticeID,
        message: "A039 inserted 5/8 seam starts its segment at tick 102")
    report.expect(
        session.grid.axis.segmentAt(101).next == 102, cppID: latticeID,
        message: "A040 pre-seam segment ends at tick 102")
    report.expect(
        session.grid.snapTickDown(103.5, camera: session.camera) == 102
            && session.grid.snapTickUp(101.5, camera: session.camera) == 102
            && session.grid.nextSubdivisionTickAfter(101, camera: session.camera) == 102
            && session.grid.nextSubdivisionTickAfter(102, camera: session.camera) == 102 + coarse,
        cppID: latticeID, message: "sub-grid restarts at the signature seam")
    var seamWalk: [Tick] = []
    session.grid.forEachSubdivision(from: 95, to: 130, camera: session.camera) { tick, _ in
        seamWalk.append(tick)
    }
    report.expect(
        seamWalk == [108, 120], cppID: latticeID,
        message: "A041 the seam walk emits ticks 108 and 120 while skipping the 5/8 beats")
    var innerSeam: [Tick] = []
    session.grid.forEachSubdivision(from: 100, to: 110, camera: session.camera) { tick, _ in
        innerSeam.append(tick)
    }
    report.expect(
        innerSeam == [108], cppID: latticeID,
        message: "A042 the short seam window emits only the tick 108 subdivision")
    report.expect(
        session.grid.snapTick(103.5, camera: session.camera) == 102,
        cppID: latticeID, message: "A047 nearest snap after the seam resolves to tick 102")
    report.expect(
        session.grid.snapTick(103.5 + Double(snap), camera: session.camera) == 102 + snap,
        cppID: latticeID, message: "A048 nearest snap one stride later resolves to tick 108")
    document.deleteTimeSignature(at: 102)
    report.expect(
        session.grid.axis.segmentAt(102) == axis.segmentAt(102), cppID: latticeID,
        message: "A049 deleting the signature restores the plain segment grid")
}

@MainActor
func checkContentWindowBoundaryReversal(_ report: CheckReport) {
    let axis = TimeAxis(map: TimeMap(ticksPerBeat: 24, lengthTicks: 32_768))
    let metrics = GridMetrics(
        baseFontPx: 13, dpr: 2, width: 1024, height: 320,
        timeAxis: axis)
    var camera = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 32_768,
        viewportWidth: 1024, rollHeight: 320,
        limits: GridCameraPolicy.limits(baseFontPx: 13))
    _ = camera.setTimeZoom(24)
    _ = camera.setHScroll(1023)
    var input = GridSceneInput(
        metrics: metrics, grid: RollGrid(axis: axis, clockTicks: 1, metrics: metrics),
        palette: GridPalette(), camera: camera, fontSpec: { _ in [:] })
    let scene = GridScene()
    scene.rebuildStatic(input)
    scene.rebuildNotes(input)
    let initialKey = scene.listContentKey
    let initialDisplay = scene.displayRevision
    let initialSegments = latticeSegments(input.metrics.timeAxis)
    var retained = initialKey != nil && !initialSegments.isEmpty
    for scroll in [1025.0, 1023, 1025, 1023, 1025, 1023] {
        _ = input.camera.setHScroll(scroll)
        scene.rebuildStatic(input)
        scene.rebuildNotes(input)
        retained =
            retained && scene.listContentKey == initialKey
            && scene.displayRevision != initialDisplay
            && latticeSegments(input.metrics.timeAxis) == initialSegments
    }
    report.expect(
        retained, cppID: contentWindowID,
        message: "two-pixel camera reversals leave the content key untouched while display frames rebuild")

    var monotonicRetained = true
    var reversalRetained = true
    for scroll in stride(from: 1025.0, through: 16_383, by: 128) {
        _ = input.camera.setHScroll(scroll)
        scene.rebuildStatic(input)
        scene.rebuildNotes(input)
        monotonicRetained =
            monotonicRetained
            && scene.listContentKey == initialKey
            && scene.displayRevision != initialDisplay
        _ = input.camera.setHScroll(scroll - 2)
        scene.rebuildStatic(input)
        scene.rebuildNotes(input)
        reversalRetained =
            reversalRetained
            && scene.listContentKey == initialKey
            && scene.displayRevision != initialDisplay
    }
    report.expect(
        monotonicRetained, cppID: contentWindowID,
        message: "monotonic camera scroll leaves the content key untouched while display frames rebuild")
    report.expect(
        reversalRetained, cppID: contentWindowID,
        message: "a reverse camera step leaves the content key untouched while display frames rebuild")
    var resizeInput = input
    resizeInput.camera = camera
    resizeInput.camera.updateViewport(width: 1023, rollHeight: 320)
    scene.rebuildStatic(resizeInput)
    scene.rebuildNotes(resizeInput)
    let resizeKey = scene.listContentKey
    let resizeDisplay = scene.displayRevision
    let rows = latticeRows(resizeInput)
    let segments = latticeSegments(resizeInput.metrics.timeAxis)
    var resizeRetained = resizeKey != nil && !rows.isEmpty && !segments.isEmpty
    for width in [1025.0, 1023, 1025, 1023, 1025, 1023] {
        resizeInput.camera.updateViewport(width: width, rollHeight: 320)
        scene.rebuildStatic(resizeInput)
        scene.rebuildNotes(resizeInput)
        resizeRetained =
            resizeRetained && scene.listContentKey == resizeKey
            && scene.displayRevision != resizeDisplay
            && latticeRows(resizeInput) == rows
            && latticeSegments(resizeInput.metrics.timeAxis) == segments
    }
    report.expect(
        resizeRetained, cppID: contentWindowID,
        message: "width reversals leave the content key untouched while display frames rebuild")
}

// Axis segments without a scene: the implicit opening segment plus one
// start per explicit signature, same-tick duplicates merged.
@MainActor
private func latticeSegments(_ axis: TimeAxis) -> [RollContentProbe.Segment] {
    return axis.signatureStarts.map { start in
        let segment = axis.segmentAt(start)
        let signature = axis.signatureAt(start)
        return RollContentProbe.Segment(
            start: Int(start), next: Int(segment.next),
            beatTicks: Int(segment.beatTicks),
            beatsPerBar: Int(segment.beatsPerBar),
            numerator: signature.numerator, denomPow2: signature.denomPow2,
            implicit: signature.implicit)
    }
}

// Projected row pitches without a scene: scroll-neutral content.
@MainActor
private func latticeRows(_ input: GridSceneInput) -> [Int] {
    let projection = input.camera.projection
    return (0..<projection.visibleRowCount).compactMap { projection.visiblePitch(at: $0) }
}
