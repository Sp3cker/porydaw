import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
func checkGridCameraWheel(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid,
    counters: GridCameraIntegrationCounters
) {
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    _ = viewport.mutateCamera {
        _ = $0.setTimeZoom(35)
        _ = $0.setKeyHeight(13)
        _ = $0.setHScroll(100)
        _ = $0.setVScroll(min(100, $0.snapshot.maxVScroll))
    }
    counters.camera = 0
    let anchorX = 200.0
    for phase in [QtScrollPhase.noScroll, .begin, .update, .end] {
        let before = viewport.camera.snapshot
        let anchorTick = viewport.camera.tickAtContentX(anchorX)
        let publications = counters.camera
        grid.handleWheel(
            angleDeltaX: 0, angleDeltaY: 1, pixelDeltaX: 0, pixelDeltaY: 0,
            modifiers: 0, phase: phase.rawValue, overGutter: false,
            anchorX: anchorX, anchorY: 100)
        let after = viewport.camera.snapshot
        report.expect(
            after.pixelsPerBeat > before.pixelsPerBeat
                && gridCameraNear(viewport.camera.tickAtContentX(anchorX), anchorTick, tolerance: 1e-7)
                && counters.camera == publications + 1,
            cppID: gridCameraWheelID, message: "phase \(phase.rawValue) performs one anchored time zoom publication")
    }

    let beforeMomentum = viewport.camera.snapshot
    let momentumPublications = counters.camera
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.momentum.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        viewport.camera.snapshot == beforeMomentum && counters.camera == momentumPublications,
        cppID: gridCameraWheelID, message: "momentum suppresses time zoom without publishing")

    _ = viewport.mutateCamera { _ = $0.setTimeZoom(35) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let angleZoom = viewport.camera.snapshot.pixelsPerBeat
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 24,
        modifiers: 0, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(angleZoom, 35 * pow(1.0015, 120), tolerance: 1e-7)
            && gridCameraNear(
                viewport.camera.snapshot.pixelsPerBeat,
                angleZoom * pow(1.0015, 120), tolerance: 1e-7),
        cppID: gridCameraWheelID, message: "pixel deltas receive five-times angle weighting")
    report.expect(
        counters.camera == 2,
        cppID: gridCameraWheelID, message: "effective angle and pixel zooms each publish once")

    _ = viewport.mutateCamera { _ = $0.setHScroll(100) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 10, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(viewport.camera.snapshot.scrollX, 90) && counters.camera == 1,
        cppID: gridCameraWheelID, message: "Shift wheel pans by negative selected delta exactly once")
    _ = viewport.mutateCamera { _ = $0.setHScroll(0) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let minimumPan = viewport.camera.snapshot
    let minimumPublications = counters.camera
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(minimumPan.scrollX, minimumPan.minHScroll)
            && minimumPublications == 1 && counters.camera == minimumPublications,
        cppID: gridCameraWheelID, message: "Shift pan clamps at minimum and repeated clamped pan is silent")

    _ = viewport.mutateCamera { _ = $0.setHScroll($0.snapshot.maxHScroll - 1) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let maximumPan = viewport.camera.snapshot
    let maximumPublications = counters.camera
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(maximumPan.scrollX, maximumPan.maxHScroll)
            && maximumPublications == 1 && counters.camera == maximumPublications,
        cppID: gridCameraWheelID, message: "Shift pan clamps at maximum and repeated clamped pan is silent")

    _ = viewport.mutateCamera { _ = $0.setHScroll(100) }
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: -12, angleDeltaY: 0, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.momentum.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        gridCameraNear(viewport.camera.snapshot.scrollX, 112) && counters.camera == 1,
        cppID: gridCameraWheelID, message: "horizontal-only momentum still pans exactly once")

    let pitchBefore = viewport.camera.snapshot
    let pitchRow = (pitchBefore.scrollY + 100) / pitchBefore.keyHeight
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0400_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    let pitchAfter = viewport.camera.snapshot
    report.expect(
        pitchAfter.keyHeight > pitchBefore.keyHeight
            && gridCameraNear((pitchAfter.scrollY + 100) / pitchAfter.keyHeight, pitchRow, tolerance: 1e-7)
            && counters.camera == 1,
        cppID: gridCameraWheelID, message: "Ctrl wheel performs one row-anchored pitch zoom publication")
    let pitchMomentum = viewport.camera.snapshot
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: 120, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0400_0000, phase: QtScrollPhase.momentum.rawValue,
        overGutter: false, anchorX: anchorX, anchorY: 100)
    report.expect(
        viewport.camera.snapshot == pitchMomentum && counters.camera == 0,
        cppID: gridCameraWheelID, message: "momentum suppresses pitch zoom without publishing")

    let gutterBefore = viewport.camera.snapshot.scrollY
    counters.camera = 0
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -12, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0, phase: QtScrollPhase.update.rawValue,
        overGutter: true, anchorX: 20, anchorY: 100)
    report.expect(
        gridCameraNear(viewport.camera.snapshot.scrollY, gutterBefore + 6) && counters.camera == 1,
        cppID: gridCameraWheelID, message: "gutter wheel scrolls by negative half-delta exactly once")
    checkVerticalCameraWheelContract(report, viewport: viewport, grid: grid)
    checkKeyboardGutterHoverTracksRows(report, viewport: viewport, grid: grid)
    checkHorizontalCameraWheelContract(report, viewport: viewport, grid: grid)
}

@MainActor
private func checkVerticalCameraWheelContract(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid
) {
    let id = "swiftcore/EditorCamera::verticalCameraWheelContract"
    let anchorY = 200.0
    grid.configureViewport(width: 640, height: 320, fontPx: 6, dpr: 2)
    func restore() {
        _ = viewport.mutateCamera {
            $0.restore(pixelsPerBeat: 35, keyHeight: 8, scrollX: 0, scrollY: 300)
        }
    }
    func wheel(
        angle: Double = 0, pixel: Double = 0, phase: QtScrollPhase = .noScroll,
        overGutter: Bool = false
    ) {
        grid.handleWheel(
            angleDeltaX: 0, angleDeltaY: angle, pixelDeltaX: 0, pixelDeltaY: pixel,
            modifiers: overGutter ? 0 : 0x0400_0000, phase: phase.rawValue,
            overGutter: overGutter, anchorX: 40, anchorY: anchorY)
    }

    restore()
    for _ in 0..<4 { wheel(angle: 30) }
    let partial = viewport.camera.snapshot
    restore()
    wheel(angle: 120)
    let full = viewport.camera.snapshot
    report.expect(
        gridCameraNear(full.keyHeight, partial.keyHeight, tolerance: 1e-12)
            && gridCameraNear(full.scrollY, partial.scrollY, tolerance: 1e-10),
        cppID: id, message: "four quarter-notch pitch zooms equal one full notch")
    wheel(angle: 120, phase: .momentum)
    report.expect(
        viewport.camera.snapshot == full, cppID: id,
        message: "pitch-zoom momentum leaves height and scroll unchanged")

    restore()
    let anchoredRow =
        (anchorY + viewport.camera.snapshot.scrollY)
        / viewport.camera.snapshot.keyHeight
    wheel(angle: 30)
    let anchored = viewport.camera.snapshot
    report.expect(
        gridCameraNear(
            (anchorY + anchored.scrollY) / anchored.keyHeight,
            anchoredRow, tolerance: 1e-12),
        cppID: id, message: "quarter-notch zoom holds the fractional pitch row")
    restore()
    for _ in 0..<10 { wheel(angle: 120) }
    report.expect(
        gridCameraNear(viewport.camera.snapshot.keyHeight, 16, tolerance: 1e-12),
        cppID: id, message: "ten pitch notches clamp at the font-scaled 16px maximum")
    restore()
    wheel(pixel: 240)
    report.expect(
        gridCameraNear(viewport.camera.snapshot.keyHeight, 16, tolerance: 1e-12),
        cppID: id, message: "240px wheel delta reaches the same pitch-height maximum")
    let gutterBefore = viewport.camera.snapshot.scrollY
    wheel(pixel: 1, overGutter: true)
    report.expect(
        gridCameraNear(viewport.camera.snapshot.scrollY, gutterBefore - 0.5, tolerance: 1e-12),
        cppID: id, message: "one gutter pixel pans pitch by a negative half-pixel")

    restore()
    for _ in 0..<4 { wheel(angle: 30) }
    for _ in 0..<4 { wheel(angle: -30) }
    let returned = viewport.camera.snapshot
    report.expect(
        gridCameraNear(returned.keyHeight, 8, tolerance: 1e-12)
            && gridCameraNear(returned.scrollY, 300, tolerance: 1e-10),
        cppID: id, message: "opposite quarter-notches restore pitch height and offset")
    _ = viewport.mutateCamera {
        $0.restore(pixelsPerBeat: 35, keyHeight: 9.375, scrollX: 0, scrollY: 257.625)
    }
    let fractional = viewport.camera.snapshot
    report.expect(
        fractional.keyHeight == 9.375 && fractional.scrollY == 257.625,
        cppID: id, message: "fractional pitch height and scroll restore without rounding")
    let boundaryRow = 40
    let boundary = ((Double(boundaryRow) * fractional.keyHeight - fractional.scrollY) * 2).rounded() / 2
    grid.updateHover(x: 4, y: boundary - 0.25)
    report.expect(
        grid.hoverKey == 128 - boundaryRow, cppID: id,
        message: "DPR-snapped row boundary minus a quarter pixel selects upper pitch")
    grid.updateHover(x: 4, y: boundary + 0.25)
    report.expect(
        grid.hoverKey == 127 - boundaryRow, cppID: id,
        message: "DPR-snapped row boundary plus a quarter pixel selects lower pitch")
    grid.clearKeyboardHover()
    report.expect(
        grid.hoverKey == -1, cppID: id,
        message: "leaving the keyboard clears the projected hover pitch")
    _ = viewport.mutateCamera {
        $0.restore(pixelsPerBeat: 35, keyHeight: 11, scrollX: 0, scrollY: 217)
    }
    report.expect(
        viewport.camera.snapshot.keyHeight == 11 && viewport.camera.snapshot.scrollY == 217,
        cppID: id, message: "integral pitch height and scroll restore exactly")
}

@MainActor
private func checkKeyboardGutterHoverTracksRows(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid
) {
    let id = "swiftcore/EditorCamera::keyboardGutterHoverTracksRows"
    let y = 160.0
    let camera = viewport.camera.snapshot
    let expected =
        viewport.camera.projection.pitch(
            atY: y, keyHeight: camera.keyHeight, scrollY: camera.scrollY, dpr: 2) ?? -1
    grid.updateHover(x: 4, y: y)
    report.expect(
        expected > 0 && grid.hoverKey == expected, cppID: id,
        message: "gutter midpoint hover selects the projected pitch")
    report.expect(
        RollContentProbe(grid).keyboardHighlightRects().count == 1, cppID: id,
        message: "gutter midpoint hover paints one keyboard highlight record")
    grid.updateHover(x: 4, y: y + camera.keyHeight)
    report.expect(
        grid.hoverKey == expected - 1, cppID: id,
        message: "adjacent lower gutter row changes hover pitch by one")
    grid.clearKeyboardHover()
    report.expect(
        grid.hoverKey == -1, cppID: id,
        message: "gutter leave clears the hover pitch")
    report.expect(
        RollContentProbe(grid).keyboardHighlightRects().isEmpty, cppID: id,
        message: "gutter leave removes the painted keyboard highlight")
}

@MainActor
private func checkHorizontalCameraWheelContract(
    _ report: CheckReport, viewport: DocumentViewport, grid: PianoGrid
) {
    let id = "swiftcore/EditorCamera::horizontalCameraWheelContract"
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let anchorX = 73.375
    func restore(_ pixelsPerBeat: Double = 300.125, _ scrollX: Double = 23.625) {
        _ = viewport.mutateCamera {
            $0.restore(
                pixelsPerBeat: pixelsPerBeat, keyHeight: 13,
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
    let partial = viewport.camera.snapshot
    restore()
    wheel(angle: 120)
    let full = viewport.camera.snapshot
    // camera.cpp:278 fixes the full-notch expectation for its 300.125 scale fixture.
    let expectedScale = 359.2664053212564
    report.expect(
        gridCameraNear(
            full.pixelsPerBeat, expectedScale,
            tolerance: expectedScale * 1e-12)
            && gridCameraNear(full.pixelsPerBeat, partial.pixelsPerBeat, tolerance: 1e-12)
            && gridCameraNear(full.scrollX, partial.scrollX, tolerance: 1e-9),
        cppID: id, message: "four quarter-notch time zooms equal a full notch")
    restore()
    wheel(pixelY: 24)
    report.expect(
        gridCameraNear(
            viewport.camera.snapshot.pixelsPerBeat, full.pixelsPerBeat,
            tolerance: 1e-12)
            && gridCameraNear(viewport.camera.snapshot.scrollX, full.scrollX, tolerance: 1e-9),
        cppID: id, message: "24px wheel equals one full angle notch")
    restore()
    wheel(pixelX: 8)
    report.expect(
        gridCameraNear(viewport.camera.snapshot.scrollX, 23.625 - 8, tolerance: 1e-12)
            && gridCameraNear(viewport.camera.snapshot.pixelsPerBeat, 300.125, tolerance: 1e-12),
        cppID: id, message: "horizontal pixel wheel pans without changing scale")
    restore(300.125, 0)
    wheel(pixelX: 8)
    report.expect(
        viewport.camera.snapshot.scrollX == -8, cppID: id,
        message: "A099 eight-pixel wheel pan from bound zero reaches negative eight")
    restore()
    let tick = viewport.camera.tickAtContentX(anchorX)
    wheel(angle: 30)
    report.expect(
        gridCameraNear(viewport.camera.tickAtContentX(anchorX), tick, tolerance: 1e-9),
        cppID: id, message: "quarter-notch time zoom preserves fractional tick anchor")
    restore()
    for _ in 0..<4 { wheel(angle: 30) }
    for _ in 0..<4 { wheel(angle: -30) }
    report.expect(
        gridCameraNear(viewport.camera.snapshot.pixelsPerBeat, 300.125, tolerance: 1e-10)
            && gridCameraNear(viewport.camera.snapshot.scrollX, 23.625, tolerance: 1e-9),
        cppID: id, message: "opposite quarter-notches restore scale and offset")
    restore(311.375, 47.625)
    report.expect(
        viewport.camera.snapshot.pixelsPerBeat == 311.375
            && viewport.camera.snapshot.scrollX == 47.625,
        cppID: id, message: "fractional time scale and offset restore exactly")
}
