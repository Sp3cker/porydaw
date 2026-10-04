import Foundation
import PorydawApp
import PorydawCore

// MARK: - Pure policy

/// The authoritative tempo-map arithmetic the presenter's mapping must resolve.
@MainActor
func checkPureMapping(_ report: CheckReport) {
    let timeline = PlaybackTimeline.build(file: sharedPlayheadFixture(), sampleRate: 48_000)
    report.expect(
        near(timeline.tick(for: 0), 0, tolerance: mappingTolerance),
        cppID: sharedPlayheadMappingID, message: "sample zero maps to tick zero")
    report.expect(
        near(timeline.tick(for: 24_000), 24, tolerance: mappingTolerance),
        cppID: sharedPlayheadMappingID, message: "pre-boundary samples map at the first tempo")
    report.expect(
        near(timeline.tick(for: 48_000), 48, tolerance: mappingTolerance),
        cppID: sharedPlayheadMappingID,
        message: "the tempo boundary begins at the sample its first segment reaches")
    report.expect(
        near(timeline.tick(for: 54_000), 60, tolerance: mappingTolerance),
        cppID: sharedPlayheadMappingID, message: "post-boundary samples map at the second tempo")
    report.expect(
        near(Double(timeline.sample(for: 48)), 48_000, tolerance: mappingTolerance)
            && near(Double(timeline.sample(for: 60)), 54_000, tolerance: mappingTolerance),
        cppID: sharedPlayheadMappingID,
        message: "the mapping round-trips across the boundary in both directions")
}

/// Visibility, transport flags, the follow rule, and loop wrap as an ordinary
/// backward observation. Synthetic camera: 24 ticks/beat, 32 px/beat, 320 px
/// viewport, scrolled to the plot origin.
@MainActor
func checkPureVisibilityFollowAndWrap(_ report: CheckReport) {
    var camera = EditorCamera(
        ticksPerBeat: 24, lengthTicks: 480, viewportWidth: 320,
        rollHeight: 240,
        limits: EditorCamera.Limits(
            defaultPixelsPerBeat: 32, minPixelsPerBeat: 4,
            maxPixelsPerBeat: 640, defaultKeyHeight: 12,
            minKeyHeight: 4, maxKeyHeight: 32,
            revealViewportFraction: 1.0 / 3.0, minimumPlotWidth: 50))
    _ = camera.setHScroll(0)
    let width = camera.snapshot.viewportWidth

    let atZero = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(0), transport: 0, timelineAttached: true, camera: camera)
    let beforeZero = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(-5), transport: 0, timelineAttached: true, camera: camera)
    let insideRight = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(width - 1), transport: 0, timelineAttached: true, camera: camera)
    let pastRight = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(width + 1), transport: 0, timelineAttached: true, camera: camera)
    let detached = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(4), transport: 0, timelineAttached: false, camera: camera)

    report.expect(
        atZero.visible && near(atZero.contentX, 0), cppID: visibilityID,
        message: "a projection at the plot origin renders")
    report.expect(
        !beforeZero.visible && beforeZero.contentX < 0, cppID: visibilityID,
        message: "a negative projection is hidden, never moved")
    report.expect(
        insideRight.visible, cppID: visibilityID,
        message: "a projection inside the viewport renders")
    report.expect(
        !pastRight.visible && pastRight.contentX > width, cppID: visibilityID,
        message: "a projection past the viewport width is hidden")
    report.expect(
        !detached.visible && !detached.timelineAttached, cppID: visibilityID,
        message: "no attached timeline renders nothing")

    let playing = SharedPlayheadPolicy.presentation(
        tick: 0, transport: SharedPlayheadPolicy.playingTransport,
        timelineAttached: true, camera: camera)
    let paused = SharedPlayheadPolicy.presentation(
        tick: 0, transport: 1, timelineAttached: true, camera: camera)
    let stopped = SharedPlayheadPolicy.presentation(
        tick: 0, transport: 0, timelineAttached: true, camera: camera)
    report.expect(
        playing.playing && !paused.playing && !stopped.playing, cppID: transportID,
        message: "only transport 2 reports playing")
    report.expect(
        paused.timelineAttached && paused.visible && stopped.visible,
        cppID: transportID,
        message: "a paused or stopped position stays attached and visible in viewport")

    let open = SharedPlayheadInteractions()
    let followTick = camera.tickAtContentX(width + 4)
    let expectedTarget = followTick * camera.snapshot.pixelsPerTick - width / 10
    let target = SharedPlayheadPolicy.followTarget(
        tick: followTick, camera: camera, playing: true, followEnabled: true,
        interactions: open)
    report.expect(
        target.map { near($0, expectedTarget) } ?? false, cppID: followID,
        message: "follow scrolls to tick * pixelsPerTick - viewportWidth / 10")
    report.expect(
        SharedPlayheadPolicy.followTarget(
            tick: camera.tickAtContentX(width * 0.85 - 1), camera: camera, playing: true,
            followEnabled: true, interactions: open) == nil, cppID: followID,
        message: "follow stays put below 85% of the viewport width")
    report.expect(
        SharedPlayheadPolicy.followTarget(
            tick: camera.tickAtContentX(width * 0.85 + 1), camera: camera, playing: true,
            followEnabled: true, interactions: open) != nil, cppID: followID,
        message: "follow re-enters past 85% of the viewport width")
    report.expect(
        SharedPlayheadPolicy.followTarget(
            tick: camera.tickAtContentX(-5), camera: camera, playing: true, followEnabled: true,
            interactions: open) != nil, cppID: followID,
        message: "a projection left of the plot re-enters follow")
    report.expect(
        SharedPlayheadPolicy.followTarget(
            tick: 0, camera: camera, playing: true, followEnabled: true, interactions: open) == nil,
        cppID: followID, message: "an in-viewport projection never moves the camera")

    let gated: [(String, Double?)] = [
        (
            "paused transport",
            SharedPlayheadPolicy.followTarget(
                tick: followTick, camera: camera, playing: false, followEnabled: true,
                interactions: open)
        ),
        (
            "follow disabled",
            SharedPlayheadPolicy.followTarget(
                tick: followTick, camera: camera, playing: true, followEnabled: false,
                interactions: open)
        ),
        (
            "grid gesture",
            SharedPlayheadPolicy.followTarget(
                tick: followTick, camera: camera, playing: true, followEnabled: true,
                interactions: SharedPlayheadInteractions(gridActive: true))
        ),
        (
            "drawer resize",
            SharedPlayheadPolicy.followTarget(
                tick: followTick, camera: camera, playing: true, followEnabled: true,
                interactions: SharedPlayheadInteractions(drawerActive: true))
        ),
        (
            "explicit suspension",
            SharedPlayheadPolicy.followTarget(
                tick: followTick, camera: camera, playing: true, followEnabled: true,
                interactions: SharedPlayheadInteractions(explicitSuspension: true))
        ),
    ]
    for (name, gatedTarget) in gated {
        report.expect(gatedTarget == nil, cppID: followID, message: "\(name) suspends follow")
    }

    let late = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(width + 4), transport: SharedPlayheadPolicy.playingTransport,
        timelineAttached: true, camera: camera)
    let wrapped = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(4), transport: SharedPlayheadPolicy.playingTransport,
        timelineAttached: true, camera: camera)
    report.expect(
        late.tick > wrapped.tick && late.contentX > wrapped.contentX, cppID: loopWrapID,
        message: "a wrapped sample presents a backward tick and projection")
    report.expect(
        wrapped.timelineAttached && wrapped.playing && wrapped.visible,
        cppID: loopWrapID,
        message: "a wrapped sample keeps the same attached playing presentation")
}
