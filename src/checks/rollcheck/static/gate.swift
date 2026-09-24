import PorydawApp

@MainActor
func runGateChecks(_ report: CheckReport, session: DocumentSession) {
    checkReadyRollZoom(report, session: session)
}

@MainActor
private func checkReadyRollZoom(_ report: CheckReport, session: DocumentSession) {
    let grid = PianoGrid(session: session)
    let originalCamera = session.camera
    defer { session.mutateCamera { $0 = originalCamera } }

    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    session.mutateCamera { _ = $0.setTimeZoom(35) }
    let readyZoom = session.camera.snapshot.pixelsPerBeat
    grid.handleWheel(angleDeltaX: 0, angleDeltaY: 120,
                     pixelDeltaX: 0, pixelDeltaY: 0,
                     modifiers: 0, phase: QtScrollPhase.noScroll.rawValue,
                     overGutter: false, anchorX: 80, anchorY: 100)
    report.expect(session.camera.snapshot.pixelsPerBeat > readyZoom,
                  cppID: "swiftcore/PianoRollStaticTest::gatedAndReadyRollZoom",
                  message: "a roll wheel at (80, 100) changes time zoom on a ready song")
}
