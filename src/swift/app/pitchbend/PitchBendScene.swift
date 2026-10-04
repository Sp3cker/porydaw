import Foundation
import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class PitchBendLine: QVariantGettable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double
    public var strokeWidth: Double
    public var strokeColor: QmlColor

    public init(
        x0: Double, y0: Double, x1: Double, y1: Double,
        width: Double, color: QmlColor
    ) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
        strokeWidth = width
        strokeColor = color
    }
}

@MainActor
@QtBridgeable
public final class PitchBendVertex: QVariantGettable {
    public var x: Double
    public var y: Double
    public var radius: Double
    public var fillColor: QmlColor
    public var ringColor: QmlColor
    public var ringWidth: Double

    public init(
        x: Double, y: Double, radius: Double, fill: QmlColor,
        ring: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0), ringWidth: Double = 0
    ) {
        self.x = x - radius
        self.y = y - radius
        self.radius = radius
        fillColor = fill
        ringColor = ring
        self.ringWidth = ringWidth
    }
}

/// Per-lane, document-independent raster projection and pointer input.
@MainActor
@QtBridgeable
public final class PitchBendLane {
    @QtIgnored public var kernel: PitchBendKernel
    private let palette: GridPalette
    private let identityColor: QmlColor
    public var canvasX: Double = 0
    public var canvasY: Double = 0
    public var canvasWidth: Double = 0
    public var canvasHeight: Double = 0
    @QtTracked public var liveValueText = ""
    @QtTracked public var upperValueText = ""
    @QtTracked public var lowerValueText = ""
    @QtTracked public var endLabel = "Note off"
    public var curveColor: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var plotBackground: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    public var focusColor: QmlColor = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
    @QtTracked public var laneTitle = ""
    @QtTracked public var bipolar = false
    public var gridLines: QListModel<SceneRect> = QListModel()
    public var curveLines: QListModel<PitchBendLine> = QListModel()
    public var vertices: QListModel<PitchBendVertex> = QListModel()
    @QtIgnored public var onCommit: ((Bool) -> Void)?
    @QtIgnored public var onWheelSteps: ((Int) -> Void)?
    @QtIgnored public var bendRange = 2
    private var gestureStartingPoints: [Int: Int]?

    public init(kernel: PitchBendKernel, palette: GridPalette, track: Int) {
        self.kernel = kernel
        self.palette = palette
        identityColor = PaletteMath.trackIdentityColors[PaletteMath.trackIdentityIndex(track)]
        laneTitle = kernel.lane == .pitch ? "Pitch bend (BEND)" : "Mod wheel (CC1)"
        bipolar = kernel.lane == .pitch
        rebuild()
    }

    public func refreshGeometry(geometry: PitchBendGeometry) {
        kernel.geometry = geometry
        rebuild()
    }

    public func press(x: Double, y: Double, modifiers: Int) {
        guard kernel.geometry.contains(x, y) else { return }
        gestureStartingPoints = kernel.points
        kernel.begin(x: x, y: y, line: modifiers & (0x0200_0000 | 0x0800_0000) != 0)
        rebuild()
    }

    public func drag(x: Double, y: Double, modifiers: Int) {
        guard kernel.update(x: x, y: y, fine: modifiers & 0x0800_0000 != 0) else { return }
        rebuild()
    }

    public func release(x: Double, y: Double, modifiers: Int) {
        guard kernel.hasGesture else { return }
        _ = kernel.update(x: x, y: y, fine: modifiers & 0x0800_0000 != 0)
        settleGesture()
    }

    public func settleGesture() {
        guard kernel.hasGesture else { return }
        let sampledStroke = kernel.isSampledStroke
        kernel.finish()
        let changed = gestureStartingPoints != kernel.points
        gestureStartingPoints = nil
        rebuild()
        if changed { onCommit?(sampledStroke) }
    }

    public func cancelGesture() {
        gestureStartingPoints = nil
        kernel.cancelGesture()
        rebuild()
    }

    public func wheel(angleY: Double, pixelY: Double, momentum: Bool) {
        guard kernel.lane == .pitch, !momentum else { return }
        let steps = kernel.accumulateWheel(pixelY != 0 ? pixelY * 5 : angleY)
        if steps != 0 { onWheelSteps?(steps) }
    }

    public func removeSelectedVertex() {
        guard kernel.removeSelectedVertex() else { return }
        rebuild()
        onCommit?(false)
    }

    public func hitVertex(x: Double, y: Double) -> Int {
        kernel.hitTest(x: x, y: y)?.tick ?? -1
    }

    @QtIgnored
    public func rebuild() {
        let k = kernel
        let g = k.geometry
        setPublished(canvasX, g.canvasX) { canvasX = $0 }
        setPublished(canvasY, g.canvasY) { canvasY = $0 }
        setPublished(canvasWidth, g.canvasWidth) { canvasWidth = $0 }
        setPublished(canvasHeight, g.canvasHeight) { canvasHeight = $0 }
        setPublished(curveColor, identityColor) { curveColor = $0 }
        setPublished(plotBackground, palette.rollBackground) { plotBackground = $0 }
        setPublished(focusColor, palette.focusOutline) { focusColor = $0 }
        var ruleCount = 0
        for tick in k.gridTicks {
            publishRule(
                at: ruleCount, x: k.x(at: tick), y: g.canvasY,
                width: g.hairline, height: g.canvasHeight, color: palette.gridLine)
            ruleCount += 1
        }
        let zero = k.y(at: 0)
        var x = g.canvasX
        while x < g.canvasX + g.canvasWidth {
            publishRule(
                at: ruleCount, x: x, y: zero,
                width: min(4 * g.hairline, g.canvasX + g.canvasWidth - x),
                height: g.hairline, color: palette.separator)
            ruleCount += 1
            x += 6 * g.hairline
        }
        if ruleCount < gridLines.count {
            gridLines.replaceSubrange(ruleCount..<gridLines.count, with: [])
        }

        let ordered = k.orderedPoints
        var lineCount = 0
        for (index, point) in ordered.enumerated() {
            let next = index + 1 < ordered.count ? ordered[index + 1] : nil
            let x0 = k.x(at: point.tick)
            let x1 = next.map { k.x(at: $0.tick) } ?? g.canvasX + g.canvasWidth - 1
            let y = k.y(at: point.value)
            let angled = next.map { $0.tick - point.tick == k.fineTicks } ?? false
            publishLine(
                at: lineCount, x0: x0, y0: y, x1: x1,
                y1: angled ? k.y(at: next?.value ?? point.value) : y,
                width: g.curveStroke, color: curveColor)
            lineCount += 1
            if let next, !angled {
                publishLine(
                    at: lineCount, x0: x1, y0: y, x1: x1, y1: k.y(at: next.value),
                    width: g.curveStroke, color: curveColor)
                lineCount += 1
            }
        }
        if let preview = k.linePreview {
            publishLine(
                at: lineCount, x0: k.x(at: preview.0.tick), y0: k.y(at: preview.0.value),
                x1: k.x(at: preview.1.tick), y1: k.y(at: preview.1.value),
                width: g.hairline, color: palette.editCursor)
            lineCount += 1
        }
        if lineCount < curveLines.count {
            curveLines.replaceSubrange(lineCount..<curveLines.count, with: [])
        }
        let transparent = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
        for (index, point) in ordered.enumerated() {
            let selected = k.selectedTick == point.tick
            let endpoint = point.tick == k.startTick || point.tick == k.endTick
            publishVertex(
                at: index, x: k.x(at: point.tick), y: k.y(at: point.value),
                radius: selected ? g.selectedRingRadius : g.nodePaintRadius,
                fill: endpoint && !selected ? palette.secondaryText : curveColor,
                ring: selected ? palette.focusOutline : transparent,
                ringWidth: selected ? g.hairline * 1.5 : 0)
        }
        publishVertex(
            at: ordered.count, x: k.x(at: k.keyboardTick), y: k.y(at: k.liveValue),
            radius: g.nodePaintRadius, fill: transparent,
            ring: palette.editCursor, ringWidth: g.hairline)
        let vertexCount = ordered.count + 1
        if vertexCount < vertices.count {
            vertices.replaceSubrange(vertexCount..<vertices.count, with: [])
        }
        if k.lane == .modulation {
            liveValueText = String(k.liveValue)
            upperValueText = "127"
            lowerValueText = "0"
        } else {
            let semitones =
                Double(k.liveValue) * Double(bendRange)
                / Double(k.liveValue > 0 ? 8191 : 8192)
            liveValueText =
                k.liveValue == 0 || bendRange == 0
                ? "0 st"
                : String(format: "%@%.2f st", semitones > 0 ? "+" : "", semitones)
            upperValueText = bendRange == 0 ? "0 st" : "+\(bendRange) st"
            lowerValueText = bendRange == 0 ? "0 st" : "-\(bendRange) st"
        }
    }

    private func publishRule(
        at index: Int, x: Double, y: Double, width: Double, height: Double, color: QmlColor
    ) {
        let value = SceneRectValue(x: x, y: y, width: width, height: height, fillColor: color)
        guard index < gridLines.count else {
            gridLines.append(SceneRect(value))
            return
        }
        let row = gridLines[index]
        if row.update(value) { gridLines[index] = row }
    }

    private func publishLine(
        at index: Int, x0: Double, y0: Double, x1: Double, y1: Double,
        width: Double, color: QmlColor
    ) {
        guard index < curveLines.count else {
            curveLines.append(PitchBendLine(x0: x0, y0: y0, x1: x1, y1: y1, width: width, color: color))
            return
        }
        let row = curveLines[index]
        guard
            row.x0 != x0 || row.y0 != y0 || row.x1 != x1 || row.y1 != y1
                || row.strokeWidth != width || row.strokeColor != color
        else { return }
        setPublished(row.x0, x0) { row.x0 = $0 }
        setPublished(row.y0, y0) { row.y0 = $0 }
        setPublished(row.x1, x1) { row.x1 = $0 }
        setPublished(row.y1, y1) { row.y1 = $0 }
        setPublished(row.strokeWidth, width) { row.strokeWidth = $0 }
        setPublished(row.strokeColor, color) { row.strokeColor = $0 }
        curveLines[index] = row
    }

    private func publishVertex(
        at index: Int, x: Double, y: Double, radius: Double, fill: QmlColor,
        ring: QmlColor, ringWidth: Double
    ) {
        guard index < vertices.count else {
            vertices.append(
                PitchBendVertex(
                    x: x, y: y, radius: radius, fill: fill, ring: ring, ringWidth: ringWidth))
            return
        }
        let row = vertices[index]
        let left = x - radius
        let top = y - radius
        guard
            row.x != left || row.y != top || row.radius != radius || row.fillColor != fill
                || row.ringColor != ring || row.ringWidth != ringWidth
        else { return }
        setPublished(row.x, left) { row.x = $0 }
        setPublished(row.y, top) { row.y = $0 }
        setPublished(row.radius, radius) { row.radius = $0 }
        setPublished(row.fillColor, fill) { row.fillColor = $0 }
        setPublished(row.ringColor, ring) { row.ringColor = $0 }
        setPublished(row.ringWidth, ringWidth) { row.ringWidth = $0 }
        vertices[index] = row
    }
}
