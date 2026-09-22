import Foundation
@testable import PorydawApp

private let cameraTransformID = "swiftcore/EditorCamera::transformsAndBounds"
private let cameraZoomID = "swiftcore/EditorCamera::anchoredZoomAndRestore"
private let cameraPitchID = "swiftcore/EditorCamera::pitchProjectionAndReveal"

@MainActor
func runEditorCameraChecks(_ report: CheckReport) {
    let limits = EditorCamera.Limits(
        defaultPixelsPerBeat: 32, minPixelsPerBeat: 4, maxPixelsPerBeat: 640,
        defaultKeyHeight: 12, minKeyHeight: 4, maxKeyHeight: 32,
        revealViewportFraction: 1.0 / 3.0, minimumPlotWidth: 50)
    let compact = EditorCamera(ticksPerBeat: 24, lengthTicks: 0,
                               viewportWidth: 1, rollHeight: 1, limits: limits)
    report.expect(near(compact.snapshot.viewportWidth, 50) &&
                  near(compact.snapshot.minHScroll, -48) &&
                  near(compact.snapshot.maxHScroll, 0),
                  cppID: cameraTransformID,
                  message: "caller-resolved minimum viewport produces observable camera bounds")
    var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                              viewportWidth: 200, rollHeight: 120, limits: limits)

    _ = camera.setHScroll(10.25)
    let content = camera.contentX(tick: 96)
    report.expect(near(camera.tickAtContentX(content), 96), cppID: cameraTransformID,
                  message: "tick/content transforms round-trip with a fractional offset")
    report.expect(near(camera.snapshot.scrollX, 10.25), cppID: cameraTransformID,
                  message: "horizontal restoration preserves fractional offsets")
    report.expect(near(camera.displayX(tick: 24, origin: 0.2, dpr: 2), 22),
                  cppID: cameraTransformID, message: "display projection snaps to a physical pixel")
    _ = camera.setHScroll(-10_000)
    report.expect(near(camera.snapshot.scrollX, -48) && near(camera.snapshot.minHScroll, -48),
                  cppID: cameraTransformID, message: "horizontal scrolling clamps to production pre-roll")
    _ = camera.setHScroll(10_000)
    report.expect(near(camera.snapshot.scrollX, 640), cppID: cameraTransformID,
                  message: "bound timeline end reaches the plot origin")

    var viewportCamera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                                      viewportWidth: 1_000, rollHeight: 120, limits: limits)
    _ = viewportCamera.setHScroll(-100)
    viewportCamera.updateViewport(width: 200, rollHeight: 120)
    report.expect(near(viewportCamera.snapshot.scrollX, -48),
                  cppID: cameraTransformID,
                  message: "bound viewport shrink reclamps the changed pre-roll floor")
    _ = viewportCamera.setHScroll(10.25)
    viewportCamera.updateViewport(width: 400, rollHeight: 120)
    report.expect(near(viewportCamera.snapshot.scrollX, 10.25),
                  cppID: cameraTransformID,
                  message: "bound viewport updates preserve a legal fractional offset")

    _ = camera.setHScroll(100)
    let anchorX = 50.0
    let anchoredTick = camera.tickAtContentX(anchorX)
    let zoom = camera.zoomAroundContentX(factor: 2, anchorContentX: anchorX)
    report.expect(zoom.zoomChanged && zoom.scrollChanged &&
                  near(camera.tickAtContentX(anchorX), anchoredTick), cppID: cameraZoomID,
                  message: "interactive time zoom preserves its tick anchor")

    var clampedTimeZoom = EditorCamera(ticksPerBeat: 24, lengthTicks: 24,
                                       viewportWidth: 200, rollHeight: 120, limits: limits)
    let boundedAnchor = 190.0
    let tickBeforeBoundedZoom = clampedTimeZoom.tickAtContentX(boundedAnchor)
    _ = clampedTimeZoom.zoomAroundContentX(factor: 2, anchorContentX: boundedAnchor)
    report.expect(near(clampedTimeZoom.snapshot.scrollX, 64) &&
                  !near(clampedTimeZoom.tickAtContentX(boundedAnchor), tickBeforeBoundedZoom),
                  cppID: cameraZoomID,
                  message: "time zoom reaches its bound when the pointer anchor is unreachable")
    camera.restore(pixelsPerBeat: 48, keyHeight: 16, scrollX: 10.5, scrollY: 20.25)
    report.expect(near(camera.snapshot.pixelsPerBeat, 48) &&
                  near(camera.snapshot.keyHeight, 16) && near(camera.snapshot.scrollX, 10.5) &&
                  near(camera.snapshot.scrollY, 20.25), cppID: cameraZoomID,
                  message: "unanchored restoration keeps valid fractional camera state")

    var sanitized = camera
    sanitized.restore(pixelsPerBeat: .nan, keyHeight: .infinity,
                      scrollX: .nan, scrollY: -.infinity)
    report.expect(near(sanitized.snapshot.pixelsPerBeat, 32) &&
                  near(sanitized.snapshot.keyHeight, 12) &&
                  near(sanitized.snapshot.scrollX, 0) && near(sanitized.snapshot.scrollY, 0),
                  cppID: cameraZoomID,
                  message: "restoration sanitizes non-finite transient view-state values independently")

    _ = camera.setHScroll(100)
    camera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: 10)
    report.expect(near(camera.snapshot.scrollX, 20), cppID: cameraTransformID,
                  message: "content shrink reclamps the horizontal offset")
    camera.updateViewport(width: 800, rollHeight: 3_000)
    report.expect(near(camera.snapshot.viewportWidth, 800) && near(camera.snapshot.scrollY, 0),
                  cppID: cameraTransformID,
                  message: "viewport growth reclamps vertical content")
    camera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: nil)
    report.expect(near(camera.snapshot.scrollX, -80), cppID: cameraTransformID,
                  message: "an unbound timeline homes to its lead pad")
    camera.updateViewport(width: 1_000, rollHeight: 120)
    report.expect(near(camera.snapshot.scrollX, -100), cppID: cameraTransformID,
                  message: "unbound viewport updates follow the resolved home")

    let chromatic = PitchProjection()
    report.expect(chromatic.visibleRowCount == 128 && (0..<128).allSatisfy { pitch in
        chromatic.row(forPitch: pitch) == 127 - pitch &&
            chromatic.visiblePitch(at: 127 - pitch) == pitch
    }, cppID: cameraPitchID,
    message: "chromatic pitch mapping remains bijective across the full MIDI range")

    let folded = PitchProjection(visiblePitches: [60, 64, 67])
    let emptyProjection = PitchProjection(visiblePitches: [])
    report.expect(folded.visiblePitch(at: 0) == 67 && folded.row(forPitch: 60) == 2 &&
                  folded.row(forPitch: 61) == PitchProjection.hiddenRow &&
                  folded.nearestVisiblePitch(to: 62) == 60 &&
                  folded.nearestVisiblePitch(to: 100) == 67 &&
                  folded.nearestVisiblePitch(to: -5) == 60 &&
                  emptyProjection.nearestVisiblePitch(to: 60) == nil,
                  cppID: cameraPitchID,
                  message: "pitch rows and nearest lookup preserve production ordering")
    report.expect(folded.row(atY: 10, keyHeight: 10, scrollY: 0, dpr: 2) == 1 &&
                  folded.pitch(atY: 29.75, keyHeight: 10, scrollY: 0, dpr: 2) == 60,
                  cppID: cameraPitchID, message: "DPR-snapped row and pitch inverses agree")
    report.expect(near(folded.rowBottom(0, keyHeight: 10.2, scrollY: 0.1, dpr: 1.5) ?? -1,
                       10) &&
                  folded.row(atY: 9.99, keyHeight: 10.2, scrollY: 0.1, dpr: 1.5) == 0 &&
                  folded.row(atY: 10, keyHeight: 10.2, scrollY: 0.1, dpr: 1.5) == 1,
                  cppID: cameraPitchID,
                  message: "fractional DPR snapping defines the inverse row boundary")

    var projectedContent = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                                        viewportWidth: 200, rollHeight: 15, limits: limits)
    _ = projectedContent.setKeyHeight(10)
    _ = projectedContent.setVScroll(100.25)
    projectedContent.updateProjection(folded)
    report.expect(near(projectedContent.snapshot.scrollY, 15),
                  cppID: cameraPitchID,
                  message: "pitch projection shrink reclamps the vertical offset")

    var pitchCamera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                                   viewportWidth: 200, rollHeight: 15, limits: limits,
                                   projection: folded)
    _ = pitchCamera.setKeyHeight(10)
    report.expect(near(pitchCamera.snapshot.maxVScroll, 15), cppID: cameraPitchID,
                  message: "vertical bounds derive from projected row height")
    _ = pitchCamera.setVScroll(5.5)
    let anchorY = 7.0
    let anchoredRow = (anchorY + pitchCamera.snapshot.scrollY) / pitchCamera.snapshot.keyHeight
    _ = pitchCamera.zoomKeyHeight(factor: 2, anchorY: anchorY)
    let resultingRow = (anchorY + pitchCamera.snapshot.scrollY) / pitchCamera.snapshot.keyHeight
    report.expect(near(anchoredRow, resultingRow), cppID: cameraZoomID,
                  message: "pitch zoom preserves its row anchor when bounds permit")

    var clampedPitchZoom = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                                        viewportWidth: 200, rollHeight: 15, limits: limits,
                                        projection: folded)
    _ = clampedPitchZoom.setKeyHeight(10)
    _ = clampedPitchZoom.setVScroll(15)
    let rowBeforeBoundedZoom = clampedPitchZoom.snapshot.scrollY /
        clampedPitchZoom.snapshot.keyHeight
    _ = clampedPitchZoom.zoomKeyHeight(factor: 0.5, anchorY: 0)
    let rowAfterBoundedZoom = clampedPitchZoom.snapshot.scrollY /
        clampedPitchZoom.snapshot.keyHeight
    report.expect(near(clampedPitchZoom.snapshot.scrollY, 0) &&
                  near(clampedPitchZoom.snapshot.maxVScroll, 0) &&
                  !near(rowAfterBoundedZoom, rowBeforeBoundedZoom),
                  cppID: cameraZoomID,
                  message: "pitch zoom reaches its bound when the row anchor is unreachable")
    _ = pitchCamera.setKeyHeight(10)
    _ = pitchCamera.setVScroll(0)
    report.expect(pitchCamera.ensureKeyVisible(60) && near(pitchCamera.snapshot.scrollY, 15),
                  cppID: cameraPitchID, message: "key reveal scrolls only enough to show its row")
    report.expect(!pitchCamera.ensureKeyVisible(61), cppID: cameraPitchID,
                  message: "hidden pitches do not move the camera")

    var reveal = EditorCamera(ticksPerBeat: 24, lengthTicks: 4_800,
                              viewportWidth: 200, rollHeight: 120, limits: limits)
    report.expect(reveal.ensureTickVisible(480, dpr: 2) &&
                  near(reveal.snapshot.scrollX, 573.3333333333),
                  cppID: cameraTransformID,
                  message: "tick reveal uses the production one-third anchor")
    _ = reveal.setHScroll(0)
    report.expect(!reveal.ensureRangeVisible(startTick: 0, endTick: 149,
                                             preferEnd: false, dpr: 1) &&
                  near(reveal.snapshot.scrollX, 0), cppID: cameraTransformID,
                  message: "a fitting range on the physical right boundary stays visible")
    report.expect(reveal.ensureRangeVisible(startTick: 240, endTick: 480,
                                            preferEnd: false, dpr: 1) &&
                  near(reveal.contentX(tick: 240), 0), cppID: cameraTransformID,
                  message: "wide range reveal prefers its requested leading edge")
    _ = reveal.setHScroll(0)
    report.expect(reveal.ensureRangeVisible(startTick: 240, endTick: 480,
                                            preferEnd: true, dpr: 1) &&
                  near(reveal.contentX(tick: 480), 199), cppID: cameraTransformID,
                  message: "wide range reveal honors the requested trailing edge")
}

private func near(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

@MainActor
func checkGridCameraWheel(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid,
    counters: GridCameraIntegrationCounters
) {
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = session.mutateCamera {
        _ = $0.setTimeZoom(35)
        _ = $0.setKeyHeight(13)
        _ = $0.setHScroll(100)
        _ = $0.setVScroll(min(100, $0.snapshot.maxVScroll))
    }
    counters.camera = 0
    let anchorX = 200.0
    for phase in [QtScrollPhase.noScroll, .begin, .update, .end] {
        let before = session.camera.snapshot
        let anchorTick = session.camera.tickAtContentX(anchorX)
        let publications = counters.camera
        grid.handleWheel(
            angleDeltaX: 0, angleDeltaY: 1, pixelDeltaX: 0, pixelDeltaY: 0,
            modifiers: 0, phase: phase.rawValue, overGutter: false,
            anchorX: anchorX, anchorY: 100)
        let after = session.camera.snapshot
        report.expect(
            after.pixelsPerBeat > before.pixelsPerBeat
                && gridCameraNear(session.camera.tickAtContentX(anchorX), anchorTick, tolerance: 1e-7)
                && counters.camera == publications + 1,
            cppID: gridCameraWheelID, message: "phase \(phase.rawValue) performs one anchored time zoom publication")
    }

    let beforeMomentum = session.camera.snapshot
    let momentumPublications = counters.camera
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.momentum.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        session.camera.snapshot == beforeMomentum && counters.camera == momentumPublications,
        cppID: gridCameraWheelID, message: "momentum suppresses time zoom without publishing")

    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let angleZoom = session.camera.snapshot.pixelsPerBeat
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 24,
        modifiers: 0, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(angleZoom, 35 * pow(1.0015, 120), tolerance: 1e-7)
            && gridCameraNear(session.camera.snapshot.pixelsPerBeat,
                    angleZoom * pow(1.0015, 120), tolerance: 1e-7),
        cppID: gridCameraWheelID, message: "pixel deltas receive five-times angle weighting")
    report.expect(
        counters.camera == 2,
        cppID: gridCameraWheelID, message: "effective angle and pixel zooms each publish once")

    _ = session.mutateCamera { _ = $0.setHScroll(100) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 10, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(session.camera.snapshot.scrollX, 90) && counters.camera == 1,
        cppID: gridCameraWheelID, message: "Shift wheel pans by negative selected delta exactly once")
    _ = session.mutateCamera { _ = $0.setHScroll(0) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let minimumPan = session.camera.snapshot
    let minimumPublications = counters.camera
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(minimumPan.scrollX, minimumPan.minHScroll)
            && minimumPublications == 1 && counters.camera == minimumPublications,
        cppID: gridCameraWheelID, message: "Shift pan clamps at minimum and repeated clamped pan is silent")

    _ = session.mutateCamera { _ = $0.setHScroll($0.snapshot.maxHScroll - 1) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let maximumPan = session.camera.snapshot
    let maximumPublications = counters.camera
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(maximumPan.scrollX, maximumPan.maxHScroll)
            && maximumPublications == 1 && counters.camera == maximumPublications,
        cppID: gridCameraWheelID, message: "Shift pan clamps at maximum and repeated clamped pan is silent")

    _ = session.mutateCamera { _ = $0.setHScroll(100) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: -12, angleDeltaY: 0, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.momentum.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(session.camera.snapshot.scrollX, 112) && counters.camera == 1,
        cppID: gridCameraWheelID, message: "horizontal-only momentum still pans exactly once")

    let pitchBefore = session.camera.snapshot
    let pitchRow = (pitchBefore.scrollY + 100) / pitchBefore.keyHeight
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0400_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let pitchAfter = session.camera.snapshot
    report.expect(
        pitchAfter.keyHeight > pitchBefore.keyHeight
            && gridCameraNear((pitchAfter.scrollY + 100) / pitchAfter.keyHeight, pitchRow, tolerance: 1e-7)
            && counters.camera == 1,
        cppID: gridCameraWheelID, message: "Ctrl wheel performs one row-anchored pitch zoom publication")
    let pitchMomentum = session.camera.snapshot
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0400_0000, phase: QtScrollPhase.momentum.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        session.camera.snapshot == pitchMomentum && counters.camera == 0,
        cppID: gridCameraWheelID, message: "momentum suppresses pitch zoom without publishing")

    let gutterBefore = session.camera.snapshot.scrollY
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -12, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.update.rawValue,
        overGutter: true, anchorX: 20, anchorY: 100)
    report.expect(
        gridCameraNear(session.camera.snapshot.scrollY, gutterBefore + 6) && counters.camera == 1,
        cppID: gridCameraWheelID, message: "gutter wheel scrolls by negative half-delta exactly once")
}
