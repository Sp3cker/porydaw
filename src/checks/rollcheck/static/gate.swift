import PorydawApp
import PorydawDocument

@MainActor
func runGateChecks(_ report: CheckReport, viewport: DocumentViewport) {
    checkReadyRollZoom(report, viewport: viewport)
    checkReadyRulerAndScroll(report, viewport: viewport)
}

@MainActor
private func checkReadyRollZoom(_ report: CheckReport, viewport: DocumentViewport) {
    let grid = PianoGrid(viewport: viewport)
    let originalCamera = viewport.camera
    defer { viewport.mutateCamera { $0 = originalCamera } }

    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    viewport.mutateCamera { _ = $0.setTimeZoom(35) }
    let readyZoom = viewport.camera.snapshot.pixelsPerBeat
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120,
        pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.noScroll.rawValue,
        overGutter: false, anchorX: 80, anchorY: 100)
    report.expect(
        viewport.camera.snapshot.pixelsPerBeat > readyZoom,
        cppID: "swiftcore/PianoRollStaticTest::gatedAndReadyRollZoom",
        message: "a roll wheel at (80, 100) changes time zoom on a ready song")
}

@MainActor
private func checkReadyRulerAndScroll(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let grid = PianoGrid(viewport: viewport)
    let originalCamera = viewport.camera
    let originalCursor = session.editCursor
    defer {
        viewport.mutateCamera { $0 = originalCamera }
        session.editCursor = originalCursor
    }

    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    let ruler = RulerMenuPresenter(viewport: viewport, grid: grid, automation: AutomationPage())
    session.editCursor = 0
    let rulerX = viewport.camera.leadPad + 140
    ruler.beginSweep(contentX: rulerX, pointerY: 12)
    ruler.endSweep(contentX: rulerX, pointerY: 12)
    report.expect(
        session.editCursor > 0,
        cppID: "swiftcore/PianoRollStaticTest::gatedAndReadyRulerScrub",
        message: "a ready ruler click parks the edit cursor at the clicked grid tick")
    let clickedCursor = session.editCursor
    ruler.updateSweep(contentX: rulerX + grid.beatWidth, pointerY: 12)
    report.expect(
        session.editCursor == clickedCursor && session.timeSelection?.isActive != true,
        cppID: "swiftcore/PianoRollStaticTest::gatedAndReadyRulerScrub",
        message: "the released ready ruler click leaves no active sweep")

    grid.setCameraHScroll(value: 0)
    let beforeScroll = viewport.camera.snapshot.scrollX
    grid.scrollHorizontalByWheel(
        pixelX: 0, pixelY: 0, angleX: 0, angleY: -120,
        wheelScrollLines: 3)
    report.expect(
        viewport.camera.snapshot.scrollX > beforeScroll,
        cppID: "swiftcore/PianoRollStaticTest::gatedAndReadyScrollbarWheel",
        message: "a ready horizontal scrollbar wheel advances the loaded camera")
}
