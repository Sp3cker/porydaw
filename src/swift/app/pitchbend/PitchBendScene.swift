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
    public var strokeColor: String

    public init(x0: Double, y0: Double, x1: Double, y1: Double,
                width: Double, color: String) {
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
    public var fillColor: String
    public var ringColor: String
    public var ringWidth: Double

    public init(x: Double, y: Double, radius: Double, fill: String,
                ring: String = "transparent", ringWidth: Double = 0) {
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
    private let track: Int
    public var canvasRect: [String: QVariantSettable] = [:]
    @QtTracked public var liveValueText = ""
    @QtTracked public var upperValueText = ""
    @QtTracked public var lowerValueText = ""
    @QtTracked public var endLabel = "Note off"
    @QtTracked public var curveColor = ""
    @QtTracked public var plotBackground = ""
    @QtTracked public var focusColor = ""
    @QtTracked public var laneTitle = ""
    @QtTracked public var bipolar = false
    public var gridLines: QListModel<SceneRect> = QListModel()
    public var curveLines: QListModel<PitchBendLine> = QListModel()
    public var vertices: QListModel<PitchBendVertex> = QListModel()
    @QtIgnored public var onCommit: (() -> Void)?
    @QtIgnored public var onWheelSteps: ((Int) -> Void)?
    @QtIgnored public var bendRange = 2
    private var gestureStartingPoints: [Int: Int]?

    public init(kernel: PitchBendKernel, palette: GridPalette, track: Int) {
        self.kernel = kernel
        self.palette = palette
        self.track = track
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
        kernel.finish()
        let changed = gestureStartingPoints != kernel.points
        gestureStartingPoints = nil
        rebuild()
        if changed { onCommit?() }
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
        onCommit?()
    }

    public func hitVertex(x: Double, y: Double) -> Int {
        kernel.hitTest(x: x, y: y)?.tick ?? -1
    }

    @QtIgnored
    public func rebuild() {
        let k = kernel
        let g = k.geometry
        canvasRect = g.canvasRect
        curveColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(track)]
        plotBackground = palette.rollBackground
        focusColor = palette.focusOutline
        let gridColor = palette.gridLine
        var rules: [SceneRect] = []
        var tick = (k.startTick / k.snapTicks + 1) * k.snapTicks
        while tick < k.endTick {
            rules.append(SceneRect(x: k.x(at: tick), y: g.canvasY, width: g.hairline,
                                   height: g.canvasHeight, fillColor: gridColor))
            tick += k.snapTicks
        }
        let zero = k.y(at: 0)
        var x = g.canvasX
        while x < g.canvasX + g.canvasWidth {
            rules.append(SceneRect(x: x, y: zero, width: min(4 * g.hairline,
                g.canvasX + g.canvasWidth - x), height: g.hairline,
                fillColor: palette.separator))
            x += 6 * g.hairline
        }
        syncModel(gridLines, rules, matches: { $0.matches($1) })

        let ordered = k.orderedPoints
        var strokes: [PitchBendLine] = []
        for (index, point) in ordered.enumerated() {
            let next = index + 1 < ordered.count ? ordered[index + 1] : nil
            let x0 = k.x(at: point.tick)
            let x1 = next.map { k.x(at: $0.tick) } ?? g.canvasX + g.canvasWidth - 1
            let y = k.y(at: point.value)
            let angled = next.map { $0.tick - point.tick == k.fineTicks } ?? false
            strokes.append(PitchBendLine(
                x0: x0, y0: y, x1: x1,
                y1: angled ? k.y(at: next?.value ?? point.value) : y,
                width: g.curveStroke, color: curveColor))
            if let next, !angled {
                strokes.append(PitchBendLine(x0: x1, y0: y, x1: x1, y1: k.y(at: next.value),
                                             width: g.curveStroke, color: curveColor))
            }
        }
        if let preview = k.linePreview {
            let first = preview.0
            let last = preview.1
            strokes.append(PitchBendLine(
                x0: k.x(at: first.tick), y0: k.y(at: first.value),
                x1: k.x(at: last.tick), y1: k.y(at: last.value),
                width: g.hairline, color: palette.editCursor))
        }
        syncModel(curveLines, strokes, matches: {
            $0.x0 == $1.x0 && $0.y0 == $1.y0 && $0.x1 == $1.x1 && $0.y1 == $1.y1
                && $0.strokeWidth == $1.strokeWidth && $0.strokeColor == $1.strokeColor
        })
        var dots: [PitchBendVertex] = ordered.map { point in
            let selected = k.selectedTick == point.tick
            let endpoint = point.tick == k.startTick || point.tick == k.endTick
            return PitchBendVertex(x: k.x(at: point.tick), y: k.y(at: point.value),
                radius: selected ? g.selectedRingRadius : g.nodePaintRadius,
                fill: endpoint && !selected ? palette.secondaryText : curveColor,
                ring: selected ? palette.focusOutline : "transparent",
                ringWidth: selected ? g.hairline * 1.5 : 0)
        }
        dots.append(PitchBendVertex(x: k.x(at: k.keyboardTick), y: k.y(at: k.liveValue),
                                     radius: g.nodePaintRadius, fill: "transparent",
                                     ring: palette.editCursor, ringWidth: g.hairline))
        syncModel(vertices, dots, matches: {
            $0.x == $1.x && $0.y == $1.y && $0.radius == $1.radius
                && $0.fillColor == $1.fillColor && $0.ringColor == $1.ringColor
                && $0.ringWidth == $1.ringWidth
        })
        if k.lane == .modulation {
            liveValueText = String(k.liveValue)
            upperValueText = "127"
            lowerValueText = "0"
        } else {
            let semitones = Double(k.liveValue) * Double(bendRange)
                / Double(k.liveValue > 0 ? 8191 : 8192)
            liveValueText = k.liveValue == 0 || bendRange == 0 ? "0 st"
                : String(format: "%@%.2f st", semitones > 0 ? "+" : "", semitones)
            upperValueText = bendRange == 0 ? "0 st" : "+\(bendRange) st"
            lowerValueText = bendRange == 0 ? "0 st" : "-\(bendRange) st"
        }
    }
}
