import Foundation
@testable import PorydawApp
import PorydawCore

private let cameraTransformID = "swiftcore/EditorCamera::transformsAndBounds"
private let cameraZoomID = "swiftcore/EditorCamera::anchoredZoomAndRestore"
private let cameraPitchID = "swiftcore/EditorCamera::pitchProjectionAndReveal"

@MainActor
func runEditorCameraChecks(_ report: CheckReport) {
    let limits = EditorCamera.Limits(
        defaultPixelsPerBeat: 32, minPixelsPerBeat: 4, maxPixelsPerBeat: 640,
        defaultKeyHeight: 12, minKeyHeight: 4, maxKeyHeight: 32,
        revealViewportFraction: 1.0 / 3.0, minimumPlotWidth: 50)
    let compact = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 0,
        viewportWidth: 1, rollHeight: 1, limits: limits)
    report.expect(
        gridCameraNear(compact.snapshot.viewportWidth, 50) && gridCameraNear(compact.snapshot.minHScroll, -48)
            && gridCameraNear(compact.snapshot.maxHScroll, 0),
        cppID: cameraTransformID,
        message: "caller-resolved minimum viewport produces observable camera bounds")
    let tickRangeID = "rollcheck/PianoRollStaticTest::tickRangeRejectsInvalidBounds"
    report.expect(
        TimeDefaults.tick(from: -0.75) == 0, cppID: tickRangeID,
        message: "A011 negative content clamps to tick zero")
    report.expect(
        TimeDefaults.tick(from: 96.75) == 96, cppID: tickRangeID,
        message: "A013 fractional content resolves to the preceding tick")
    report.expect(
        TimeDefaults.tick(from: Double(TimeDefaults.noTick).nextDown) == TimeDefaults.maxTick,
        cppID: tickRangeID,
        message: "A015 largest double below the tick ceiling converts exactly")
    var camera = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 480,
        viewportWidth: 200, rollHeight: 120, limits: limits)

    _ = camera.setHScroll(10.25)
    let content = camera.contentX(tick: 96)
    report.expect(
        gridCameraNear(camera.tickAtContentX(content), 96), cppID: cameraTransformID,
        message: "tick/content transforms round-trip with a fractional offset")
    report.expect(
        gridCameraNear(camera.snapshot.scrollX, 10.25), cppID: cameraTransformID,
        message: "horizontal restoration preserves fractional offsets")
    report.expect(
        gridCameraNear(
            camera.viewX(tick: 24, dpr: 2),
            camera.contentTickX(tick: 24, dpr: 2) - (10.25 * 2).rounded() / 2),
        cppID: cameraTransformID, message: "display projection snaps to a physical pixel")
    _ = camera.setHScroll(-10_000)
    report.expect(
        gridCameraNear(camera.snapshot.scrollX, -48) && gridCameraNear(camera.snapshot.minHScroll, -48),
        cppID: cameraTransformID, message: "horizontal scrolling clamps to production pre-roll")
    _ = camera.setHScroll(10_000)
    report.expect(
        gridCameraNear(camera.snapshot.scrollX, 640), cppID: cameraTransformID,
        message: "bound timeline end reaches the plot origin")

    var viewportCamera = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 480,
        viewportWidth: 1_000, rollHeight: 120, limits: limits)
    _ = viewportCamera.setHScroll(-100)
    viewportCamera.updateViewport(width: 200, rollHeight: 120)
    report.expect(
        gridCameraNear(viewportCamera.snapshot.scrollX, -48),
        cppID: cameraTransformID,
        message: "bound viewport shrink reclamps the changed pre-roll floor")
    _ = viewportCamera.setHScroll(10.25)
    viewportCamera.updateViewport(width: 400, rollHeight: 120)
    report.expect(
        gridCameraNear(viewportCamera.snapshot.scrollX, 10.25),
        cppID: cameraTransformID,
        message: "bound viewport updates preserve a legal fractional offset")
    let halfPad = -viewportCamera.leadPad / 2
    _ = viewportCamera.setHScroll(halfPad)
    viewportCamera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: 480)
    report.expect(
        viewportCamera.snapshot.scrollX == halfPad, cppID: cameraTransformID,
        message: "A100 fractional pre-roll scroll reads back exactly after a bound domain update")

    _ = camera.setHScroll(100)
    let anchorX = 50.0
    let anchoredTick = camera.tickAtContentX(anchorX)
    let zoom = camera.zoomAroundContentX(factor: 2, anchorContentX: anchorX)
    report.expect(
        zoom.zoomChanged && zoom.scrollChanged && gridCameraNear(camera.tickAtContentX(anchorX), anchoredTick),
        cppID: cameraZoomID,
        message: "interactive time zoom preserves its tick anchor")

    var clampedTimeZoom = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 24,
        viewportWidth: 200, rollHeight: 120, limits: limits)
    let boundedAnchor = 190.0
    let tickBeforeBoundedZoom = clampedTimeZoom.tickAtContentX(boundedAnchor)
    _ = clampedTimeZoom.zoomAroundContentX(factor: 2, anchorContentX: boundedAnchor)
    report.expect(
        gridCameraNear(clampedTimeZoom.snapshot.scrollX, 64)
            && !gridCameraNear(clampedTimeZoom.tickAtContentX(boundedAnchor), tickBeforeBoundedZoom),
        cppID: cameraZoomID,
        message: "time zoom reaches its bound when the pointer anchor is unreachable")
    camera.restore(pixelsPerBeat: 48, keyHeight: 16, scrollX: 10.5, scrollY: 20.25)
    report.expect(
        gridCameraNear(camera.snapshot.pixelsPerBeat, 48) && gridCameraNear(camera.snapshot.keyHeight, 16)
            && gridCameraNear(camera.snapshot.scrollX, 10.5) && gridCameraNear(camera.snapshot.scrollY, 20.25),
        cppID: cameraZoomID,
        message: "unanchored restoration keeps valid fractional camera state")

    var sanitized = camera
    sanitized.restore(
        pixelsPerBeat: .nan, keyHeight: .infinity,
        scrollX: .nan, scrollY: -.infinity)
    report.expect(
        gridCameraNear(sanitized.snapshot.pixelsPerBeat, 32) && gridCameraNear(sanitized.snapshot.keyHeight, 12)
            && gridCameraNear(sanitized.snapshot.scrollX, 0) && gridCameraNear(sanitized.snapshot.scrollY, 0),
        cppID: cameraZoomID,
        message: "restoration sanitizes non-finite transient view-state values independently")

    _ = camera.setHScroll(100)
    camera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: 10)
    report.expect(
        gridCameraNear(camera.snapshot.scrollX, 20), cppID: cameraTransformID,
        message: "content shrink reclamps the horizontal offset")
    camera.updateViewport(width: 800, rollHeight: 3_000)
    report.expect(
        gridCameraNear(camera.snapshot.viewportWidth, 800) && gridCameraNear(camera.snapshot.scrollY, 0),
        cppID: cameraTransformID,
        message: "viewport growth reclamps vertical content")
    camera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: nil)
    report.expect(
        gridCameraNear(camera.snapshot.scrollX, -80), cppID: cameraTransformID,
        message: "an unbound timeline homes to its lead pad")
    camera.updateViewport(width: 1_000, rollHeight: 120)
    report.expect(
        gridCameraNear(camera.snapshot.scrollX, -100), cppID: cameraTransformID,
        message: "unbound viewport updates follow the resolved home")

    let chromatic = PitchProjection()
    report.expect(
        chromatic.visibleRowCount == 128
            && (0..<128).allSatisfy { pitch in
                chromatic.row(forPitch: pitch) == 127 - pitch && chromatic.visiblePitch(at: 127 - pitch) == pitch
            }, cppID: cameraPitchID,
        message: "chromatic pitch mapping remains bijective across the full MIDI range")

    let folded = PitchProjection(visiblePitches: [60, 64, 67])
    let emptyProjection = PitchProjection(visiblePitches: [])
    report.expect(
        folded.visiblePitch(at: 0) == 67 && folded.row(forPitch: 60) == 2
            && folded.row(forPitch: 61) == PitchProjection.hiddenRow && folded.nearestVisiblePitch(to: 62) == 60
            && folded.nearestVisiblePitch(to: 100) == 67 && folded.nearestVisiblePitch(to: -5) == 60
            && emptyProjection.nearestVisiblePitch(to: 60) == nil,
        cppID: cameraPitchID,
        message: "pitch rows and nearest lookup preserve production ordering")
    report.expect(
        folded.row(atY: 10, keyHeight: 10, scrollY: 0, dpr: 2) == 1
            && folded.pitch(atY: 29.75, keyHeight: 10, scrollY: 0, dpr: 2) == 60,
        cppID: cameraPitchID, message: "DPR-snapped row and pitch inverses agree")
    report.expect(
        gridCameraNear(
            folded.rowBottom(0, keyHeight: 10.2, scrollY: 0.1, dpr: 1.5) ?? -1,
            10) && folded.row(atY: 9.99, keyHeight: 10.2, scrollY: 0.1, dpr: 1.5) == 0
            && folded.row(atY: 10, keyHeight: 10.2, scrollY: 0.1, dpr: 1.5) == 1,
        cppID: cameraPitchID,
        message: "fractional DPR snapping defines the inverse row boundary")

    var projectedContent = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 480,
        viewportWidth: 200, rollHeight: 15, limits: limits)
    _ = projectedContent.setKeyHeight(10)
    _ = projectedContent.setVScroll(100.25)
    projectedContent.updateProjection(folded)
    report.expect(
        gridCameraNear(projectedContent.snapshot.scrollY, 15),
        cppID: cameraPitchID,
        message: "pitch projection shrink reclamps the vertical offset")

    var pitchCamera = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 480,
        viewportWidth: 200, rollHeight: 15, limits: limits,
        projection: folded)
    _ = pitchCamera.setKeyHeight(10)
    report.expect(
        gridCameraNear(pitchCamera.snapshot.maxVScroll, 15), cppID: cameraPitchID,
        message: "vertical bounds derive from projected row height")
    _ = pitchCamera.setVScroll(5.5)
    let anchorY = 7.0
    let anchoredRow = (anchorY + pitchCamera.snapshot.scrollY) / pitchCamera.snapshot.keyHeight
    _ = pitchCamera.zoomKeyHeight(factor: 2, anchorY: anchorY)
    let resultingRow = (anchorY + pitchCamera.snapshot.scrollY) / pitchCamera.snapshot.keyHeight
    report.expect(
        gridCameraNear(anchoredRow, resultingRow), cppID: cameraZoomID,
        message: "pitch zoom preserves its row anchor when bounds permit")

    var clampedPitchZoom = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 480,
        viewportWidth: 200, rollHeight: 15, limits: limits,
        projection: folded)
    _ = clampedPitchZoom.setKeyHeight(10)
    _ = clampedPitchZoom.setVScroll(15)
    let rowBeforeBoundedZoom = clampedPitchZoom.snapshot.scrollY / clampedPitchZoom.snapshot.keyHeight
    _ = clampedPitchZoom.zoomKeyHeight(factor: 0.5, anchorY: 0)
    let rowAfterBoundedZoom = clampedPitchZoom.snapshot.scrollY / clampedPitchZoom.snapshot.keyHeight
    report.expect(
        gridCameraNear(clampedPitchZoom.snapshot.scrollY, 0) && gridCameraNear(clampedPitchZoom.snapshot.maxVScroll, 0)
            && !gridCameraNear(rowAfterBoundedZoom, rowBeforeBoundedZoom),
        cppID: cameraZoomID,
        message: "pitch zoom reaches its bound when the row anchor is unreachable")
    _ = pitchCamera.setKeyHeight(10)
    _ = pitchCamera.setVScroll(0)
    report.expect(
        pitchCamera.ensureKeyVisible(60) && gridCameraNear(pitchCamera.snapshot.scrollY, 15),
        cppID: cameraPitchID, message: "key reveal scrolls only enough to show its row")
    report.expect(
        !pitchCamera.ensureKeyVisible(61), cppID: cameraPitchID,
        message: "hidden pitches do not move the camera")

    var reveal = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 4_800,
        viewportWidth: 200, rollHeight: 120, limits: limits)
    report.expect(
        reveal.ensureTickVisible(480, dpr: 2) && gridCameraNear(reveal.snapshot.scrollX, 573.3333333333),
        cppID: cameraTransformID,
        message: "tick reveal uses the production one-third anchor")
    _ = reveal.setHScroll(0)
    report.expect(
        !reveal.ensureRangeVisible(
            startTick: 0, endTick: 149,
            preferEnd: false, dpr: 1) && gridCameraNear(reveal.snapshot.scrollX, 0), cppID: cameraTransformID,
        message: "a fitting range on the physical right boundary stays visible")
    report.expect(
        reveal.ensureRangeVisible(
            startTick: 240, endTick: 480,
            preferEnd: false, dpr: 1) && gridCameraNear(reveal.contentX(tick: 240), 0), cppID: cameraTransformID,
        message: "wide range reveal prefers its requested leading edge")
    _ = reveal.setHScroll(0)
    report.expect(
        reveal.ensureRangeVisible(
            startTick: 240, endTick: 480,
            preferEnd: true, dpr: 1) && gridCameraNear(reveal.contentX(tick: 480), 199), cppID: cameraTransformID,
        message: "wide range reveal honors the requested trailing edge")
    checkAffineCameraProjection(report, limits: limits)
    checkFallbackCamera(report, limits: limits)
}

@MainActor
private func checkAffineCameraProjection(_ report: CheckReport, limits: EditorCamera.Limits) {
    let id = "swiftcore/EditorCamera::affineCameraProjection"
    let axis = TimeAxis(map: TimeMap(ticksPerBeat: 24, lengthTicks: 4_800))
    let metrics = GridMetrics(
        baseFontPx: 13, dpr: 1, width: 960, height: 320,
        timeAxis: axis)
    var grid = RollGrid(axis: axis, clockTicks: 1, metrics: metrics)
    grid.setSelection(.musical(16))
    // camera.cpp affineCameraProjection_data: fixture scale/offset and tick 24's x.
    for (pixelsPerBeat, scrollX, expectedX) in [
        (37.125, 0.375, 36.75),
        (37.375, 13.625, 23.75),
        (512.5, 71.3125, 441.1875),
    ] {
        var camera = EditorCamera(
            ticksPerBeat: 24, lengthTicks: 4_800,
            viewportWidth: 960, rollHeight: 320, limits: limits)
        camera.restore(
            pixelsPerBeat: pixelsPerBeat, keyHeight: 12,
            scrollX: scrollX, scrollY: 0)
        report.expect(
            gridCameraNear(camera.contentX(tick: 24), expectedX), cppID: id,
            message: "recorded fractional affine projection at tick 24")
        let affineTick = camera.tickAtContentX(960 * 0.371) + 0.375
        report.expect(
            gridCameraNear(
                camera.tickAtContentX(camera.contentX(tick: affineTick)),
                affineTick),
            cppID: id, message: "fractional affine tick round-trip at \(pixelsPerBeat)")
        for tick in [0.0, 24.0, 96.0, 289.0] {
            for dpr in [1.0, 2.0] {
                let expected =
                    camera.contentTickX(tick: tick, dpr: dpr)
                    - (scrollX * dpr).rounded() / dpr
                report.expect(
                    gridCameraNear(camera.viewX(tick: tick, dpr: dpr), expected),
                    cppID: id, message: "physical-pixel affine projection")
            }
        }
        var inverse = true
        var advances = true
        var visible = 0
        var tick: Tick = 0
        while tick < TimeDefaults.maxTick {
            let projected = camera.contentX(tick: Double(tick))
            if projected >= 960 { break }
            if projected >= 0 {
                visible += 1
                for dpr in [1.0, 2.0] {
                    let displayed = camera.viewX(tick: Double(tick), dpr: dpr)
                    let recovered = camera.tickAtContentX(displayed)
                    inverse = inverse && grid.snapTick(recovered, camera: camera) == tick
                }
            }
            let next = grid.nextSnapTickAfter(tick, camera: camera)
            advances = advances && next > tick
            if next <= tick { break }
            tick = next
        }
        report.expect(
            visible >= 2 && inverse, cppID: id,
            message: "A083 all visible affine lattice ticks survive snapped DPR inverse projection")
        report.expect(
            advances, cppID: id,
            message: "A084 each affine lattice successor strictly advances")
    }
}

@MainActor
private func checkFallbackCamera(_ report: CheckReport, limits: EditorCamera.Limits) {
    let id = "swiftcore/EditorCamera::fallbackCamera"
    for (width, pad) in [
        (1280.0, 128.0), (1000.0, 100.0), (1500.0, 150.0),
        (50.0, 48.0), (3000.0, 256.0),
    ] {
        let camera = EditorCamera(
            ticksPerBeat: 24, lengthTicks: nil,
            viewportWidth: width, rollHeight: 800, limits: limits)
        report.expect(
            camera.leadPad > 0 && gridCameraNear(camera.leadPad, pad)
                && gridCameraNear(camera.contentX(tick: 0), pad),
            cppID: id, message: "unbound viewport homes tick zero at its lead pad")
    }
}
