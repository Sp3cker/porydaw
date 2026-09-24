import Foundation
import PorydawApp

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
    report.expect(gridCameraNear(compact.snapshot.viewportWidth, 50) &&
                  gridCameraNear(compact.snapshot.minHScroll, -48) &&
                  gridCameraNear(compact.snapshot.maxHScroll, 0),
                  cppID: cameraTransformID,
                  message: "caller-resolved minimum viewport produces observable camera bounds")
    var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                              viewportWidth: 200, rollHeight: 120, limits: limits)

    _ = camera.setHScroll(10.25)
    let content = camera.contentX(tick: 96)
    report.expect(gridCameraNear(camera.tickAtContentX(content), 96), cppID: cameraTransformID,
                  message: "tick/content transforms round-trip with a fractional offset")
    report.expect(gridCameraNear(camera.snapshot.scrollX, 10.25), cppID: cameraTransformID,
                  message: "horizontal restoration preserves fractional offsets")
    report.expect(gridCameraNear(camera.displayX(tick: 24, origin: 0.2, dpr: 2), 22),
                  cppID: cameraTransformID, message: "display projection snaps to a physical pixel")
    _ = camera.setHScroll(-10_000)
    report.expect(gridCameraNear(camera.snapshot.scrollX, -48) && gridCameraNear(camera.snapshot.minHScroll, -48),
                  cppID: cameraTransformID, message: "horizontal scrolling clamps to production pre-roll")
    _ = camera.setHScroll(10_000)
    report.expect(gridCameraNear(camera.snapshot.scrollX, 640), cppID: cameraTransformID,
                  message: "bound timeline end reaches the plot origin")

    var viewportCamera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                                      viewportWidth: 1_000, rollHeight: 120, limits: limits)
    _ = viewportCamera.setHScroll(-100)
    viewportCamera.updateViewport(width: 200, rollHeight: 120)
    report.expect(gridCameraNear(viewportCamera.snapshot.scrollX, -48),
                  cppID: cameraTransformID,
                  message: "bound viewport shrink reclamps the changed pre-roll floor")
    _ = viewportCamera.setHScroll(10.25)
    viewportCamera.updateViewport(width: 400, rollHeight: 120)
    report.expect(gridCameraNear(viewportCamera.snapshot.scrollX, 10.25),
                  cppID: cameraTransformID,
                  message: "bound viewport updates preserve a legal fractional offset")

    _ = camera.setHScroll(100)
    let anchorX = 50.0
    let anchoredTick = camera.tickAtContentX(anchorX)
    let zoom = camera.zoomAroundContentX(factor: 2, anchorContentX: anchorX)
    report.expect(zoom.zoomChanged && zoom.scrollChanged &&
                  gridCameraNear(camera.tickAtContentX(anchorX), anchoredTick), cppID: cameraZoomID,
                  message: "interactive time zoom preserves its tick anchor")

    var clampedTimeZoom = EditorCamera(ticksPerBeat: 24, lengthTicks: 24,
                                       viewportWidth: 200, rollHeight: 120, limits: limits)
    let boundedAnchor = 190.0
    let tickBeforeBoundedZoom = clampedTimeZoom.tickAtContentX(boundedAnchor)
    _ = clampedTimeZoom.zoomAroundContentX(factor: 2, anchorContentX: boundedAnchor)
    report.expect(gridCameraNear(clampedTimeZoom.snapshot.scrollX, 64) &&
                  !gridCameraNear(clampedTimeZoom.tickAtContentX(boundedAnchor), tickBeforeBoundedZoom),
                  cppID: cameraZoomID,
                  message: "time zoom reaches its bound when the pointer anchor is unreachable")
    camera.restore(pixelsPerBeat: 48, keyHeight: 16, scrollX: 10.5, scrollY: 20.25)
    report.expect(gridCameraNear(camera.snapshot.pixelsPerBeat, 48) &&
                  gridCameraNear(camera.snapshot.keyHeight, 16) && gridCameraNear(camera.snapshot.scrollX, 10.5) &&
                  gridCameraNear(camera.snapshot.scrollY, 20.25), cppID: cameraZoomID,
                  message: "unanchored restoration keeps valid fractional camera state")

    var sanitized = camera
    sanitized.restore(pixelsPerBeat: .nan, keyHeight: .infinity,
                      scrollX: .nan, scrollY: -.infinity)
    report.expect(gridCameraNear(sanitized.snapshot.pixelsPerBeat, 32) &&
                  gridCameraNear(sanitized.snapshot.keyHeight, 12) &&
                  gridCameraNear(sanitized.snapshot.scrollX, 0) && gridCameraNear(sanitized.snapshot.scrollY, 0),
                  cppID: cameraZoomID,
                  message: "restoration sanitizes non-finite transient view-state values independently")

    _ = camera.setHScroll(100)
    camera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: 10)
    report.expect(gridCameraNear(camera.snapshot.scrollX, 20), cppID: cameraTransformID,
                  message: "content shrink reclamps the horizontal offset")
    camera.updateViewport(width: 800, rollHeight: 3_000)
    report.expect(gridCameraNear(camera.snapshot.viewportWidth, 800) && gridCameraNear(camera.snapshot.scrollY, 0),
                  cppID: cameraTransformID,
                  message: "viewport growth reclamps vertical content")
    camera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: nil)
    report.expect(gridCameraNear(camera.snapshot.scrollX, -80), cppID: cameraTransformID,
                  message: "an unbound timeline homes to its lead pad")
    camera.updateViewport(width: 1_000, rollHeight: 120)
    report.expect(gridCameraNear(camera.snapshot.scrollX, -100), cppID: cameraTransformID,
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
    report.expect(gridCameraNear(folded.rowBottom(0, keyHeight: 10.2, scrollY: 0.1, dpr: 1.5) ?? -1,
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
    report.expect(gridCameraNear(projectedContent.snapshot.scrollY, 15),
                  cppID: cameraPitchID,
                  message: "pitch projection shrink reclamps the vertical offset")

    var pitchCamera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                                   viewportWidth: 200, rollHeight: 15, limits: limits,
                                   projection: folded)
    _ = pitchCamera.setKeyHeight(10)
    report.expect(gridCameraNear(pitchCamera.snapshot.maxVScroll, 15), cppID: cameraPitchID,
                  message: "vertical bounds derive from projected row height")
    _ = pitchCamera.setVScroll(5.5)
    let anchorY = 7.0
    let anchoredRow = (anchorY + pitchCamera.snapshot.scrollY) / pitchCamera.snapshot.keyHeight
    _ = pitchCamera.zoomKeyHeight(factor: 2, anchorY: anchorY)
    let resultingRow = (anchorY + pitchCamera.snapshot.scrollY) / pitchCamera.snapshot.keyHeight
    report.expect(gridCameraNear(anchoredRow, resultingRow), cppID: cameraZoomID,
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
    report.expect(gridCameraNear(clampedPitchZoom.snapshot.scrollY, 0) &&
                  gridCameraNear(clampedPitchZoom.snapshot.maxVScroll, 0) &&
                  !gridCameraNear(rowAfterBoundedZoom, rowBeforeBoundedZoom),
                  cppID: cameraZoomID,
                  message: "pitch zoom reaches its bound when the row anchor is unreachable")
    _ = pitchCamera.setKeyHeight(10)
    _ = pitchCamera.setVScroll(0)
    report.expect(pitchCamera.ensureKeyVisible(60) && gridCameraNear(pitchCamera.snapshot.scrollY, 15),
                  cppID: cameraPitchID, message: "key reveal scrolls only enough to show its row")
    report.expect(!pitchCamera.ensureKeyVisible(61), cppID: cameraPitchID,
                  message: "hidden pitches do not move the camera")

    var reveal = EditorCamera(ticksPerBeat: 24, lengthTicks: 4_800,
                              viewportWidth: 200, rollHeight: 120, limits: limits)
    report.expect(reveal.ensureTickVisible(480, dpr: 2) &&
                  gridCameraNear(reveal.snapshot.scrollX, 573.3333333333),
                  cppID: cameraTransformID,
                  message: "tick reveal uses the production one-third anchor")
    _ = reveal.setHScroll(0)
    report.expect(!reveal.ensureRangeVisible(startTick: 0, endTick: 149,
                                             preferEnd: false, dpr: 1) &&
                  gridCameraNear(reveal.snapshot.scrollX, 0), cppID: cameraTransformID,
                  message: "a fitting range on the physical right boundary stays visible")
    report.expect(reveal.ensureRangeVisible(startTick: 240, endTick: 480,
                                            preferEnd: false, dpr: 1) &&
                  gridCameraNear(reveal.contentX(tick: 240), 0), cppID: cameraTransformID,
                  message: "wide range reveal prefers its requested leading edge")
    _ = reveal.setHScroll(0)
    report.expect(reveal.ensureRangeVisible(startTick: 240, endTick: 480,
                                            preferEnd: true, dpr: 1) &&
                  gridCameraNear(reveal.contentX(tick: 480), 199), cppID: cameraTransformID,
                  message: "wide range reveal honors the requested trailing edge")
    checkAffineCameraProjection(report, limits: limits)
    checkFallbackCamera(report, limits: limits)
}

@MainActor
private func checkAffineCameraProjection(_ report: CheckReport, limits: EditorCamera.Limits) {
    let id = "swiftcore/EditorCamera::affineCameraProjection"
    // camera.cpp affineCameraProjection_data: fixture scale/offset and tick 24's x.
    for (pixelsPerBeat, scrollX, expectedX) in [(37.125, 0.375, 36.75),
                                                (37.375, 13.625, 23.75),
                                                (512.5, 71.3125, 441.1875)] {
        var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 4_800,
                                  viewportWidth: 960, rollHeight: 320, limits: limits)
        camera.restore(pixelsPerBeat: pixelsPerBeat, keyHeight: 12,
                       scrollX: scrollX, scrollY: 0)
        report.expect(gridCameraNear(camera.contentX(tick: 24), expectedX), cppID: id,
                      message: "recorded fractional affine projection at tick 24")
        let affineTick = camera.tickAtContentX(960 * 0.371) + 0.375
        report.expect(gridCameraNear(camera.tickAtContentX(camera.contentX(tick: affineTick)),
                           affineTick),
                      cppID: id, message: "fractional affine tick round-trip at \(pixelsPerBeat)")
        for tick in [0.0, 24.0, 96.0, 289.0] {
            let x = camera.contentX(tick: tick)
            for origin in [0.0, 0.25] {
                for dpr in [1.0, 2.0] {
                    let displayed = camera.displayX(tick: tick, origin: origin, dpr: dpr)
                    report.expect(gridCameraNear(displayed, ((origin + x) * dpr).rounded() / dpr),
                                  cppID: id, message: "physical-pixel affine projection")
                }
            }
        }
    }
}

@MainActor
private func checkFallbackCamera(_ report: CheckReport, limits: EditorCamera.Limits) {
    let id = "swiftcore/EditorCamera::fallbackCamera"
    for (width, pad) in [(1280.0, 128.0), (1000.0, 100.0), (1500.0, 150.0),
                         (50.0, 48.0), (3000.0, 256.0)] {
        let camera = EditorCamera(ticksPerBeat: 24, lengthTicks: nil,
                                  viewportWidth: width, rollHeight: 800, limits: limits)
        report.expect(camera.leadPad > 0 && gridCameraNear(camera.leadPad, pad)
                          && gridCameraNear(camera.contentX(tick: 0), pad),
                      cppID: id, message: "unbound viewport homes tick zero at its lead pad")
    }
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
    checkVerticalCameraWheelContract(report, session: session, grid: grid)
    checkKeyboardGutterHoverTracksRows(report, session: session, grid: grid)
    checkHorizontalCameraWheelContract(report, session: session, grid: grid)
}

@MainActor
private func checkVerticalCameraWheelContract(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid
) {
    let id = "swiftcore/EditorCamera::verticalCameraWheelContract"
    let anchorY = 200.0
    grid.configureViewport(width: 640, height: 320, fontPx: 6, dpr: 2)
    func restore() {
        _ = session.mutateCamera {
            $0.restore(pixelsPerBeat: 35, keyHeight: 8, scrollX: 0, scrollY: 300)
        }
    }
    func wheel(angle: Double = 0, pixel: Double = 0, phase: QtScrollPhase = .noScroll,
               overGutter: Bool = false) {
        grid.handleWheel(
            angleDeltaX: 0, angleDeltaY: angle, pixelDeltaX: 0, pixelDeltaY: pixel,
            modifiers: overGutter ? 0 : 0x0400_0000, phase: phase.rawValue,
            overGutter: overGutter, anchorX: 40, anchorY: anchorY)
    }

    restore()
    for _ in 0..<4 { wheel(angle: 30) }
    let partial = session.camera.snapshot
    restore()
    wheel(angle: 120)
    let full = session.camera.snapshot
    report.expect(gridCameraNear(full.keyHeight, partial.keyHeight, tolerance: 1e-12)
                      && gridCameraNear(full.scrollY, partial.scrollY, tolerance: 1e-10),
                  cppID: id, message: "four quarter-notch pitch zooms equal one full notch")
    wheel(angle: 120, phase: .momentum)
    report.expect(session.camera.snapshot == full, cppID: id,
                  message: "pitch-zoom momentum leaves height and scroll unchanged")

    restore()
    let anchoredRow = (anchorY + session.camera.snapshot.scrollY)
        / session.camera.snapshot.keyHeight
    wheel(angle: 30)
    let anchored = session.camera.snapshot
    report.expect(gridCameraNear((anchorY + anchored.scrollY) / anchored.keyHeight,
                       anchoredRow, tolerance: 1e-12),
                  cppID: id, message: "quarter-notch zoom holds the fractional pitch row")
    restore()
    for _ in 0..<10 { wheel(angle: 120) }
    report.expect(gridCameraNear(session.camera.snapshot.keyHeight, 16, tolerance: 1e-12),
                  cppID: id, message: "ten pitch notches clamp at the font-scaled 16px maximum")
    restore()
    wheel(pixel: 240)
    report.expect(gridCameraNear(session.camera.snapshot.keyHeight, 16, tolerance: 1e-12),
                  cppID: id, message: "240px wheel delta reaches the same pitch-height maximum")
    let gutterBefore = session.camera.snapshot.scrollY
    wheel(pixel: 1, overGutter: true)
    report.expect(gridCameraNear(session.camera.snapshot.scrollY, gutterBefore - 0.5, tolerance: 1e-12),
                  cppID: id, message: "one gutter pixel pans pitch by a negative half-pixel")

    restore()
    for _ in 0..<4 { wheel(angle: 30) }
    for _ in 0..<4 { wheel(angle: -30) }
    let returned = session.camera.snapshot
    report.expect(gridCameraNear(returned.keyHeight, 8, tolerance: 1e-12)
                      && gridCameraNear(returned.scrollY, 300, tolerance: 1e-10),
                  cppID: id, message: "opposite quarter-notches restore pitch height and offset")
    _ = session.mutateCamera {
        $0.restore(pixelsPerBeat: 35, keyHeight: 9.375, scrollX: 0, scrollY: 257.625)
    }
    let fractional = session.camera.snapshot
    report.expect(fractional.keyHeight == 9.375 && fractional.scrollY == 257.625,
                  cppID: id, message: "fractional pitch height and scroll restore without rounding")
    let boundaryRow = 40
    let boundary = ((Double(boundaryRow) * fractional.keyHeight - fractional.scrollY) * 2).rounded() / 2
    grid.updateHover(x: 4, y: boundary - 0.25)
    report.expect(grid.hoverKey == 128 - boundaryRow, cppID: id,
                  message: "DPR-snapped row boundary minus a quarter pixel selects upper pitch")
    grid.updateHover(x: 4, y: boundary + 0.25)
    report.expect(grid.hoverKey == 127 - boundaryRow, cppID: id,
                  message: "DPR-snapped row boundary plus a quarter pixel selects lower pitch")
    grid.clearKeyboardHover()
    report.expect(grid.hoverKey == -1, cppID: id,
                  message: "leaving the keyboard clears the projected hover pitch")
    _ = session.mutateCamera {
        $0.restore(pixelsPerBeat: 35, keyHeight: 11, scrollX: 0, scrollY: 217)
    }
    report.expect(session.camera.snapshot.keyHeight == 11 && session.camera.snapshot.scrollY == 217,
                  cppID: id, message: "integral pitch height and scroll restore exactly")
}

@MainActor
private func checkKeyboardGutterHoverTracksRows(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid
) {
    let id = "swiftcore/EditorCamera::keyboardGutterHoverTracksRows"
    let y = 160.0
    let camera = session.camera.snapshot
    let expected = session.camera.projection.pitch(
        atY: y, keyHeight: camera.keyHeight, scrollY: camera.scrollY, dpr: 2) ?? -1
    grid.updateHover(x: 4, y: y)
    report.expect(expected > 0 && grid.hoverKey == expected, cppID: id,
                  message: "gutter midpoint hover selects the projected pitch")
    grid.updateHover(x: 4, y: y + camera.keyHeight)
    report.expect(grid.hoverKey == expected - 1, cppID: id,
                  message: "adjacent lower gutter row changes hover pitch by one")
    grid.clearKeyboardHover()
    report.expect(grid.hoverKey == -1, cppID: id,
                  message: "gutter leave clears the hover pitch")
}

@MainActor
private func checkHorizontalCameraWheelContract(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid
) {
    let id = "swiftcore/EditorCamera::horizontalCameraWheelContract"
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let anchorX = 73.375
    func restore(_ pixelsPerBeat: Double = 300.125, _ scrollX: Double = 23.625) {
        _ = session.mutateCamera {
            $0.restore(pixelsPerBeat: pixelsPerBeat, keyHeight: 13,
                       scrollX: scrollX, scrollY: 100)
        }
    }
    func wheel(angle: Double = 0, pixelY: Double = 0, pixelX: Double = 0) {
        grid.handleWheel(
            angleDeltaX: 0, angleDeltaY: angle, pixelDeltaX: pixelX, pixelDeltaY: pixelY,
            modifiers: 0, phase: QtScrollPhase.noScroll.rawValue,
            overGutter: false, anchorX: anchorX, anchorY: 200)
    }

    restore()
    for _ in 0..<4 { wheel(angle: 30) }
    let partial = session.camera.snapshot
    restore()
    wheel(angle: 120)
    let full = session.camera.snapshot
    // camera.cpp:278 fixes the full-notch expectation for its 300.125 scale fixture.
    let expectedScale = 359.2664053212564
    report.expect(gridCameraNear(full.pixelsPerBeat, expectedScale,
                       tolerance: expectedScale * 1e-12)
                      && gridCameraNear(full.pixelsPerBeat, partial.pixelsPerBeat, tolerance: 1e-12)
                      && gridCameraNear(full.scrollX, partial.scrollX, tolerance: 1e-9),
                  cppID: id, message: "four quarter-notch time zooms equal a full notch")
    restore()
    wheel(pixelY: 24)
    report.expect(gridCameraNear(session.camera.snapshot.pixelsPerBeat, full.pixelsPerBeat,
                       tolerance: 1e-12)
                      && gridCameraNear(session.camera.snapshot.scrollX, full.scrollX, tolerance: 1e-9),
                  cppID: id, message: "24px wheel equals one full angle notch")
    restore()
    wheel(pixelX: 8)
    report.expect(gridCameraNear(session.camera.snapshot.scrollX, 23.625 - 8, tolerance: 1e-12)
                      && gridCameraNear(session.camera.snapshot.pixelsPerBeat, 300.125, tolerance: 1e-12),
                  cppID: id, message: "horizontal pixel wheel pans without changing scale")
    restore()
    let tick = session.camera.tickAtContentX(anchorX)
    wheel(angle: 30)
    report.expect(gridCameraNear(session.camera.tickAtContentX(anchorX), tick, tolerance: 1e-9),
                  cppID: id, message: "quarter-notch time zoom preserves fractional tick anchor")
    restore()
    for _ in 0..<4 { wheel(angle: 30) }
    for _ in 0..<4 { wheel(angle: -30) }
    report.expect(gridCameraNear(session.camera.snapshot.pixelsPerBeat, 300.125, tolerance: 1e-10)
                      && gridCameraNear(session.camera.snapshot.scrollX, 23.625, tolerance: 1e-9),
                  cppID: id, message: "opposite quarter-notches restore scale and offset")
    restore(311.375, 47.625)
    report.expect(session.camera.snapshot.pixelsPerBeat == 311.375
                      && session.camera.snapshot.scrollX == 47.625,
                  cppID: id, message: "fractional time scale and offset restore exactly")
}
