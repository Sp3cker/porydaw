import Foundation
import QtBridge

/// The legacy popup's font-relative chrome and graph-local editing canvas, in DIPs.
public struct PitchBendGeometry {
    public let popupWidth: Double
    public let popupHeight: Double
    public let headerHeight: Double
    public let graphHeight: Double
    public let outerInset: Double
    public let titleHeight: Double
    public let descriptionHeight: Double
    public let controlsHeight: Double
    public let fieldWidth: Double
    public let fieldHeight: Double
    public let resetWidth: Double
    public let resetHeight: Double
    public let axisLabelHeight: Double
    public let canvasX: Double
    public let canvasY: Double
    public let canvasWidth: Double
    public let canvasHeight: Double
    public let zeroDetent: Double
    public let nodeHitRadius: Double
    public let nodePaintRadius: Double
    public let selectedRingRadius: Double
    public let curveStroke: Double
    public let scrubThreshold: Double
    public let hairline: Double

    public init(fontPx b: Double, lineSpacing: Double, dpr: Double) {
        let space = fontPx(b, 0.25)
        outerInset = fontPx(b, 4.0 / 7.0)
        titleHeight = lineSpacing
        descriptionHeight = lineSpacing
        fieldHeight = fontPx(b, 12.0 / 7.0)
        controlsHeight = fieldHeight
        fieldWidth = fontPx(b, 39.0 / 7.0)
        resetWidth = fontPx(b, 30.0 / 7.0)
        resetHeight = fontPx(b, 13.0 / 7.0)
        axisLabelHeight = lineSpacing + space
        headerHeight = outerInset + titleHeight + descriptionHeight + space + controlsHeight + space
        canvasX = fontPx(b, 26.0 / 7.0)
        canvasY = titleHeight + fontPx(b, 1.5)
        canvasWidth = fontPx(b, 20.0)
        canvasHeight = fontPx(b, 8.0)
        graphHeight = canvasY + canvasHeight + axisLabelHeight + space
        popupWidth = canvasX + canvasWidth + outerInset
        popupHeight = headerHeight + 2 * graphHeight
        zeroDetent = fontPxF(b, 4.0 / 7.0)
        nodeHitRadius = fontPxF(b, 4.0 / 7.0)
        nodePaintRadius = fontPxF(b, 3.0 / 14.0)
        selectedRingRadius = fontPxF(b, 3.0 / 7.0)
        curveStroke = fontPxF(b, 1.0 / 7.0)
        scrubThreshold = fontPxF(b, 3.0 / 14.0)
        hairline = physicalPixel(dpr)
    }

    public var metrics: [String: QVariantSettable] {
        ["popupWidth": popupWidth, "popupHeight": popupHeight,
         "headerHeight": headerHeight, "graphHeight": graphHeight,
         "outerInset": outerInset, "titleHeight": titleHeight,
         "descriptionHeight": descriptionHeight, "controlsHeight": controlsHeight,
         "fieldWidth": fieldWidth, "fieldHeight": fieldHeight,
         "resetWidth": resetWidth, "resetHeight": resetHeight,
         "axisLabelHeight": axisLabelHeight, "hairline": hairline,
         "scrubThreshold": scrubThreshold]
    }

    public var canvasRect: [String: QVariantSettable] {
        ["x": canvasX, "y": canvasY, "width": canvasWidth, "height": canvasHeight]
    }

    public func contains(_ x: Double, _ y: Double) -> Bool {
        x >= canvasX && x <= canvasX + canvasWidth - 1
            && y >= canvasY && y <= canvasY + canvasHeight - 1
    }
}
