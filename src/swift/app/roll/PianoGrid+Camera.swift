import Foundation
import PorydawCore
import PorydawDocument
import QtBridge
import PorydawAppCommands

@MainActor
extension PianoGrid {
    func configureViewportImpl(
        width: Double, height: Double,
        fontPx: Double, dpr: Double
    ) {
        let oldFont = metrics.baseFontPx
        let newFont = max(1, fontPx)
        let nextBase = Int(newFont.rounded())
        if nextBase != roleTypography.baseFontPx {
            roleTypography = Typography(baseFontPx: nextBase)
        }
        metrics = GridMetrics(
            baseFontPx: newFont, dpr: max(0.1, dpr),
            width: max(0, width), height: max(0, height),
            timeAxis: metrics.timeAxis)
        viewport.grid.metrics = metrics
        baseFontPx = metrics.baseFontPx
        drawThreshold = metrics.drawThreshold
        devicePixelRatio = metrics.dpr

        let oldLimits = GridCameraPolicy.limits(baseFontPx: oldFont)
        let newLimits = GridCameraPolicy.limits(baseFontPx: newFont)
        viewport.mutateCamera { camera in
            let priorScale = camera.snapshot
            let scaledPixelsPerBeat =
                priorScale.pixelsPerBeat
                * newLimits.defaultPixelsPerBeat / oldLimits.defaultPixelsPerBeat
            let scaledKeyHeight =
                priorScale.keyHeight
                * newLimits.defaultKeyHeight / oldLimits.defaultKeyHeight
            camera.updateLimits(newLimits)
            if newFont != oldFont {
                _ = camera.setTimeZoom(scaledPixelsPerBeat)
                _ = camera.setKeyHeight(scaledKeyHeight)
            }
            let oldViewport = camera.snapshot
            let wasAtHome = oldViewport.scrollX == oldViewport.minHScroll
            camera.updateViewport(width: max(0, width), rollHeight: max(0, height))
            let newViewport = camera.snapshot
            if wasAtHome && newViewport.scrollX == oldViewport.minHScroll {
                _ = camera.setHScroll(newViewport.minHScroll)
            }
            camera.updateTimeDomain(
                ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
                lengthTicks: UInt64(session.timeline.lengthTicks))
            if !didApplyInitialHome, height > 0 {
                _ = camera.setVScroll(defaultVerticalScroll(camera: camera))
                didApplyInitialHome = true
            }
        }
        refreshCamera()
    }

    func resetCameraScrollImpl() {
        viewport.mutateCamera { camera in
            _ = camera.setHScroll(camera.snapshot.minHScroll)
            _ = camera.setVScroll(defaultVerticalScroll(camera: camera))
        }
    }

    func setCameraHScrollImpl(value: Double) {
        viewport.mutateCamera { _ = $0.setHScroll(value) }
    }

    func setCameraVScrollImpl(value: Double) {
        viewport.mutateCamera { _ = $0.setVScroll(value) }
    }

    func scrollHorizontalByWheelImpl(
        pixelX: Double, pixelY: Double,
        angleX: Double, angleY: Double,
        wheelScrollLines: Double
    ) {
        let delta = TimelineScrollbar.wheelDips(
            horizontal: true, pixelX: pixelX, pixelY: pixelY,
            angleX: angleX, angleY: angleY, wheelScrollLines: wheelScrollLines)
        viewport.mutateCamera { _ = $0.scrollByPx(delta) }
    }

    func scrollVerticalByWheelImpl(
        pixelX: Double, pixelY: Double,
        angleX: Double, angleY: Double,
        wheelScrollLines: Double
    ) {
        let delta = TimelineScrollbar.wheelDips(
            horizontal: false, pixelX: pixelX, pixelY: pixelY,
            angleX: angleX, angleY: angleY, wheelScrollLines: wheelScrollLines)
        viewport.mutateCamera { _ = $0.scrollRollBy(delta) }
    }

    func handleWheelImpl(
        angleDeltaX: Double, angleDeltaY: Double,
        pixelDeltaX: Double, pixelDeltaY: Double,
        modifiers: Int, phase: Int, overGutter: Bool,
        anchorX: Double, anchorY: Double
    ) {
        guard let phase = QtScrollPhase(rawValue: phase) else {
            preconditionFailure("Unsupported Qt scroll phase: \(phase)")
        }
        let isPixel = pixelDeltaX != 0 || pixelDeltaY != 0
        let dx = isPixel ? pixelDeltaX : angleDeltaX
        let dy = isPixel ? pixelDeltaY : angleDeltaY
        let d = dy != 0 ? dy : dx
        let weightedDy = dy * (isPixel ? 5 : 1)
        if modifiers & QtFact.controlModifier != 0 {
            guard phase != .momentum else { return }
            viewport.mutateCamera {
                _ = $0.zoomKeyHeight(factor: exp2(weightedDy / 1200), anchorY: anchorY)
            }
        } else if modifiers & QtFact.shiftModifier != 0 {
            viewport.mutateCamera { _ = $0.scrollByPx(-d) }
        } else if dy == 0, dx != 0 {
            viewport.mutateCamera { _ = $0.scrollByPx(-dx) }
        } else if overGutter {
            viewport.mutateCamera { _ = $0.scrollRollBy(-dy / 2) }
        } else {
            guard phase != .momentum else { return }
            viewport.mutateCamera {
                _ = $0.zoomAroundContentX(
                    factor: pow(1.0015, weightedDy), anchorContentX: anchorX)
            }
        }
    }

}
