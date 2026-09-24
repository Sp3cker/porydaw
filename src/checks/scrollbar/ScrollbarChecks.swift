import PorydawApp

@MainActor
func runTimelineScrollbarChecks(_ report: CheckReport) {
    let id = "scrollbar/TimelineScrollbar::geometryAndInput"
    let limits = EditorCamera.Limits(
        defaultPixelsPerBeat: 32, minPixelsPerBeat: 4, maxPixelsPerBeat: 640,
        defaultKeyHeight: 12, minKeyHeight: 4, maxKeyHeight: 32,
        revealViewportFraction: 1.0 / 3.0, minimumPlotWidth: 50)
    var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480,
                              viewportWidth: 200, rollHeight: 120, limits: limits)
    _ = camera.setHScroll(200)
    let first = camera.snapshot
    let horizontal = TimelineScrollbar(
        minimum: first.minHScroll, maximum: first.maxHScroll,
        value: first.scrollX, pageStep: first.viewportWidth,
        trackLength: 400, minimumThumbLength: 24)
    report.expect(abs(horizontal.thumbLength - 400 * 200 / 888) < 0.01
                  && horizontal.thumbTravel > 0
                  && horizontal.thumbPosition > 0,
                  cppID: id, message: "camera viewport and scroll span size the time thumb")
    report.expect(horizontal.dragValue(from: first.scrollX, startPosition: 100,
                                       position: 1_000) == first.maxHScroll
                  && horizontal.dragValue(from: first.scrollX, startPosition: 100,
                                          position: -1_000) == first.minHScroll,
                  cppID: id, message: "drag overshoots clamp at both time bounds")
    let reverse = horizontal.dragValue(from: first.scrollX, startPosition: 100,
                                       position: 100 + horizontal.thumbTravel / 4)
    report.expect(reverse > first.scrollX
                  && horizontal.dragValue(from: reverse, startPosition: 180,
                                          position: 160) < reverse,
                  cppID: id, message: "rebased drag reverses without jumping after zoom")

    _ = camera.setVScroll(300)
    let beforeFold = camera.snapshot
    let vertical = TimelineScrollbar(
        minimum: 0, maximum: beforeFold.maxVScroll, value: beforeFold.scrollY,
        pageStep: beforeFold.rollHeight, trackLength: 320, minimumThumbLength: 24)
    camera.updateViewport(width: 200, rollHeight: 300)
    let afterResize = camera.snapshot
    let resized = TimelineScrollbar(
        minimum: 0, maximum: afterResize.maxVScroll, value: afterResize.scrollY,
        pageStep: afterResize.rollHeight, trackLength: 320, minimumThumbLength: 24)
    report.expect(resized.thumbLength > vertical.thumbLength
                  && resized.span < vertical.span,
                  cppID: id, message: "taller roll viewport shortens span and lengthens thumb")
    camera.updateProjection(PitchProjection(visiblePitches: [60]))
    let folded = camera.snapshot
    let foldedBar = TimelineScrollbar(
        minimum: 0, maximum: folded.maxVScroll, value: folded.scrollY,
        pageStep: folded.rollHeight, trackLength: 320, minimumThumbLength: 24)
    report.expect(folded.scrollY == 0 && !foldedBar.scrollable
                  && foldedBar.thumbLength == 320,
                  cppID: id, message: "single-pitch fold removes roll scroll and fills its track")

    report.expect(TimelineScrollbar.wheelDips(horizontal: true, pixelX: -12, pixelY: 8,
                                              angleX: 120, angleY: 120,
                                              wheelScrollLines: 3) == 12
                  && TimelineScrollbar.wheelDips(horizontal: false, pixelX: 0, pixelY: 0,
                                                 angleX: 120, angleY: 0,
                                                 wheelScrollLines: 3) == -3,
                  cppID: id, message: "wheel favors pixel then axis angle and retains natural sign")
}
