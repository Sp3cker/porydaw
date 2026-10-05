import Foundation
import PorydawCore
import QtBridge

struct PitchBendLineValue: Equatable {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
    var width: Double
    var color: QmlColor
}

struct PitchBendVertexValue: Equatable {
    var x: Double
    var y: Double
    var radius: Double
    var fill: QmlColor
    var ring: QmlColor
    var ringWidth: Double
}

@MainActor
@QtBridgeable
public final class PitchBendLine: QVariantGettable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double
    public var strokeWidth: Double
    public var strokeColor: QmlColor
    @QtIgnored var current: PitchBendLineValue

    @QtIgnored
    init(_ value: PitchBendLineValue) {
        current = value
        x0 = value.x0
        y0 = value.y0
        x1 = value.x1
        y1 = value.y1
        strokeWidth = value.width
        strokeColor = value.color
    }

    @QtIgnored
    func update(_ value: PitchBendLineValue) -> Bool {
        guard current != value else { return false }
        current = value
        publish(\.x0, value.x0)
        publish(\.y0, value.y0)
        publish(\.x1, value.x1)
        publish(\.y1, value.y1)
        publish(\.strokeWidth, value.width)
        publish(\.strokeColor, value.color)
        return true
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
    @QtIgnored var current: PitchBendVertexValue

    @QtIgnored
    init(_ value: PitchBendVertexValue) {
        current = value
        x = value.x
        y = value.y
        radius = value.radius
        fillColor = value.fill
        ringColor = value.ring
        ringWidth = value.ringWidth
    }

    @QtIgnored
    func update(_ value: PitchBendVertexValue) -> Bool {
        guard current != value else { return false }
        current = value
        publish(\.x, value.x)
        publish(\.y, value.y)
        publish(\.radius, value.radius)
        publish(\.fillColor, value.fill)
        publish(\.ringColor, value.ring)
        publish(\.ringWidth, value.ringWidth)
        return true
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
    public var curveColor: QmlColor = .clear
    public var plotBackground: QmlColor = .clear
    public var focusColor: QmlColor = .clear
    @QtTracked public var laneTitle = ""
    @QtTracked public var bipolar = false
    public var gridLines: QListModel<SceneRect> = QListModel()
    public var curveLines: QListModel<PitchBendLine> = QListModel()
    public var vertices: QListModel<PitchBendVertex> = QListModel()
    @QtIgnored public var onCommit: ((Bool) -> Void)?
    @QtIgnored public var onWheelSteps: ((Int) -> Void)?
    @QtIgnored public var bendRange = 2
    private var gestureStartingPoints: [Int: Int]?
    private var ruleValues: [SceneRectValue] = []
    private var lineValues: [PitchBendLineValue] = []
    private var vertexValues: [PitchBendVertexValue] = []

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
        publish(\.canvasX, g.canvasX)
        publish(\.canvasY, g.canvasY)
        publish(\.canvasWidth, g.canvasWidth)
        publish(\.canvasHeight, g.canvasHeight)
        publish(\.curveColor, identityColor)
        publish(\.plotBackground, palette.rollBackground)
        publish(\.focusColor, palette.focusOutline)
        ruleValues.removeAll(keepingCapacity: true)
        for tick in k.gridTicks {
            ruleValues.append(
                SceneRectValue(
                    x: k.x(at: tick), y: g.canvasY,
                    width: g.hairline, height: g.canvasHeight, fillColor: palette.gridLine))
        }
        let zero = k.y(at: 0)
        var x = g.canvasX
        while x < g.canvasX + g.canvasWidth {
            ruleValues.append(
                SceneRectValue(
                    x: x, y: zero,
                    width: min(4 * g.hairline, g.canvasX + g.canvasWidth - x),
                    height: g.hairline, fillColor: palette.separator))
            x += 6 * g.hairline
        }
        syncRetained(gridLines, ruleValues, make: SceneRect.init, update: { $0.update($1) })

        let ordered = k.orderedPoints
        lineValues.removeAll(keepingCapacity: true)
        for (index, point) in ordered.enumerated() {
            let next = index + 1 < ordered.count ? ordered[index + 1] : nil
            let x0 = k.x(at: point.tick)
            let x1 = next.map { k.x(at: $0.tick) } ?? g.canvasX + g.canvasWidth - 1
            let y = k.y(at: point.value)
            let angled = next.map { $0.tick - point.tick == k.fineTicks } ?? false
            lineValues.append(
                PitchBendLineValue(
                    x0: x0, y0: y, x1: x1,
                    y1: angled ? k.y(at: next?.value ?? point.value) : y,
                    width: g.curveStroke, color: curveColor
                ))
            if let next, !angled {
                lineValues.append(
                    PitchBendLineValue(
                        x0: x1, y0: y, x1: x1, y1: k.y(at: next.value),
                        width: g.curveStroke, color: curveColor
                    ))
            }
        }
        if let preview = k.linePreview {
            lineValues.append(
                PitchBendLineValue(
                    x0: k.x(at: preview.0.tick), y0: k.y(at: preview.0.value),
                    x1: k.x(at: preview.1.tick), y1: k.y(at: preview.1.value),
                    width: g.hairline, color: palette.editCursor
                ))
        }
        syncRetained(curveLines, lineValues, make: PitchBendLine.init, update: { $0.update($1) })
        vertexValues.removeAll(keepingCapacity: true)
        for point in ordered {
            let selected = k.selectedTick == point.tick
            let endpoint = point.tick == k.startTick || point.tick == k.endTick
            let radius = selected ? g.selectedRingRadius : g.nodePaintRadius
            vertexValues.append(
                PitchBendVertexValue(
                    x: k.x(at: point.tick) - radius, y: k.y(at: point.value) - radius,
                    radius: radius,
                    fill: endpoint && !selected ? palette.secondaryText : curveColor,
                    ring: selected ? palette.focusOutline : .clear,
                    ringWidth: selected ? g.hairline * 1.5 : 0
                ))
        }
        vertexValues.append(
            PitchBendVertexValue(
                x: k.x(at: k.keyboardTick) - g.nodePaintRadius,
                y: k.y(at: k.liveValue) - g.nodePaintRadius,
                radius: g.nodePaintRadius, fill: .clear,
                ring: palette.editCursor, ringWidth: g.hairline
            ))
        syncRetained(vertices, vertexValues, make: PitchBendVertex.init, update: { $0.update($1) })
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
}
