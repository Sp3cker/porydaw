import Foundation
import NativeGridCurve
import QtBridge

private func resizeScratchBuffer<Element>(
    _ buffer: inout [Element], to count: Int, with value: Element
) {
    if buffer.count < count {
        buffer.append(contentsOf: repeatElement(value, count: count - buffer.count))
    } else if buffer.count > count {
        buffer.removeLast(buffer.count - count)
    }
}

struct PitchGraphGeometry {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var hairline: Double
    var zeroDetent: Double
    var hitRadius: Double
    var nodeRadius: Double
    var selectedRadius: Double
    var stroke: Double
    var right: Double { x + width - 1 }
    var bottom: Double { y + height - 1 }
}

@MainActor
@QtBridgeable
public final class GraphMark {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var angle: Double
    public var radius: Double
    public var color: String
    public var borderColor: String
    public var borderWidth: Double

    public init(
        x: Double, y: Double, width: Double, height: Double,
        angle: Double = 0, radius: Double = 0, color: String,
        borderColor: String = "transparent", borderWidth: Double = 0
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.angle = angle
        self.radius = radius
        self.color = color
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }
}

@MainActor
@QtBridgeable
public final class PitchGraph {
    @QtTracked public var marks: QListModel<GraphMark> = QListModel()
    public var canvasRect: [String: QVariantSettable]
    public var laneTitle: String
    public var liveValueText: String = "0"
    public var upperValueText: String = ""
    public var lowerValueText: String = ""
    public var endLabel: String = "Note off"
    public var bipolar: Bool

    @QtSignal public func previewChanged()
    @QtSignal public func commitRequested()
    @QtSignal public func cancelRequested()
    @QtSignal public func auditionRequested()
    @QtSignal public func rangeChangeRequested(steps: Int)

    @QtIgnored private let session: OpaquePointer
    @QtIgnored private let startTick: Int
    @QtIgnored private let endTick: Int
    @QtIgnored private let trackColor: String
    @QtIgnored private var geometry: PitchGraphGeometry
    @QtIgnored private var bendRange: Int
    @QtIgnored private var focused: Bool = false
    @QtIgnored private var state: SGCurveState
    @QtIgnored private var vertices: [SGCurveVertex] = []
    @QtIgnored private var curveValues: [SGCurveValue] = []
    @QtIgnored private var canonical: [Int: Int] = [:]
    init(
        start: Int, end: Int, curve: [Int: Int], endValue: Int,
        track: Int, pitch: Bool, bendRange: Int, geometry: PitchGraphGeometry
    ) {
        startTick = start
        endTick = end
        self.bendRange = bendRange
        self.geometry = geometry
        bipolar = pitch
        laneTitle = pitch ? "Pitch bend (BEND)" : "Mod wheel (CC1)"
        trackColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(track)]
        canvasRect = [
            "x": geometry.x, "y": geometry.y,
            "width": geometry.width, "height": geometry.height,
        ]
        let points = curve.map { SGCurveValue(tick: Int64($0.key), value: Int32($0.value)) }
        session = points.withUnsafeBufferPointer {
            sgc_create(
                pitch ? 0 : 1, Int64(start), Int64(end), $0.baseAddress, $0.count,
                Int32(endValue), Self.nativeMetrics(geometry))!
        }
        state = sgc_state(session)
        refresh()
    }

    isolated deinit { sgc_destroy(session) }

    @QtIgnored
    var points: [Int: Int] { canonical }

    @QtIgnored
    private static func nativeMetrics(_ g: PitchGraphGeometry) -> SGCurveMetrics {
        SGCurveMetrics(
            canvas_x: Int32(g.x), canvas_y: Int32(g.y),
            canvas_width: Int32(g.width), canvas_height: Int32(g.height),
            zero_detent: g.zeroDetent, node_hit_radius: g.hitRadius)
    }

    @QtIgnored
    func setGeometry(_ value: PitchGraphGeometry) {
        geometry = value
        canvasRect = ["x": value.x, "y": value.y, "width": value.width, "height": value.height]
        sgc_set_metrics(session, Self.nativeMetrics(value))
        refresh()
    }

    @QtIgnored
    func setRange(_ value: Int) {
        bendRange = value
        refreshLabels()
    }

    public func setFocused(focused: Bool) {
        self.focused = focused
        redraw()
    }

    public func beginPointer(x: Double, y: Double, modifiers: Int) {
        guard x >= geometry.x, x <= geometry.right,
            y >= geometry.y, y <= geometry.bottom
        else { return }
        sgc_press(session, x, y, modifiers & (0x0200_0000 | 0x0800_0000) != 0 ? 1 : 0)
        refresh()
        previewChanged()
    }

    public func updatePointer(x: Double, y: Double, modifiers: Int) {
        guard state.has_gesture != 0 else { return }
        sgc_move(session, x, y, modifiers & 0x0800_0000 != 0 ? 1 : 0)
        refresh()
        previewChanged()
    }

    public func endPointer(x: Double, y: Double, modifiers: Int) {
        guard state.has_gesture != 0 else { return }
        sgc_release(session, x, y, modifiers & 0x0800_0000 != 0 ? 1 : 0)
        refresh()
        previewChanged()
        commitRequested()
    }

    public func cancelPointer() {
        if cancelPointerSilently() { previewChanged() }
    }

    @QtIgnored
    @discardableResult
    func cancelPointerSilently() -> Bool {
        guard state.has_gesture != 0 else { return false }
        sgc_cancel(session)
        refresh()
        return true
    }

    public func wheelRange(angle: Double, pixels: Double, momentum: Bool) {
        guard bipolar else { return }
        let steps = sgc_wheel_steps(session, momentum ? 0 : (pixels == 0 ? angle : pixels * 5))
        if steps != 0 { rangeChangeRequested(steps: Int(steps)) }
    }

    public func keyPressed(key: Int, autoRepeat: Bool) -> Bool {
        switch key {
        case 0x0100_0000:
            cancelPointerSilently()
            cancelRequested()
        case 0x0100_0003, 0x0100_0007:
            guard state.selected_tick >= 0 else { return false }
            sgc_remove_selected(session)
            refresh()
            previewChanged()
            commitRequested()
        case 0x20:
            if !autoRepeat { auditionRequested() }
        case 0x0100_0004, 0x0100_0005:
            commitRequested()
        default:
            return false
        }
        return true
    }

    public func resetCurve() {
        sgc_reset(session)
        refresh()
        previewChanged()
        commitRequested()
    }

    public func setKeyboardFraction(fraction: Double) {
        sgc_set_keyboard_fraction(session, fraction)
        refresh()
    }

    @QtIgnored
    private func refresh() {
        state = sgc_state(session)
        let count = Int(sgc_point_count(session))
        resizeScratchBuffer(&vertices, to: count, with: SGCurveVertex())
        vertices.withUnsafeMutableBufferPointer { sgc_copy_vertices(session, $0.baseAddress!) }
        resizeScratchBuffer(&curveValues, to: count, with: SGCurveValue())
        let curveCount = curveValues.withUnsafeMutableBufferPointer {
            Int(sgc_copy_curve_points(session, $0.baseAddress!))
        }
        canonical = Dictionary(
            uniqueKeysWithValues: curveValues.prefix(curveCount).lazy.map {
                (Int($0.tick), Int($0.value))
            })
        refreshLabels()
        redraw()
    }

    @QtIgnored
    private func refreshLabels() {
        let liveValue = Int(state.live_value)
        upperValueText = bipolar ? (bendRange == 0 ? "0 st" : "+\(bendRange) st") : "127"
        lowerValueText = bipolar ? (bendRange == 0 ? "0 st" : "-\(bendRange) st") : "0"
        if !bipolar {
            liveValueText = String(liveValue)
        } else if liveValue == 0 || bendRange == 0 {
            liveValueText = "0 st"
        } else {
            let semitones = Double(liveValue * bendRange) / Double(liveValue > 0 ? 8191 : 8192)
            liveValueText = String(format: "%+.2f st", semitones)
        }
    }

    @QtIgnored
    private func redraw() {
        let g = geometry
        var rows: [GraphMark] = []
        func line(
            _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
            _ width: Double, _ color: String
        ) {
            rows.append(
                GraphMark(
                    x: x0, y: y0 - width / 2, width: hypot(x1 - x0, y1 - y0),
                    height: width, angle: atan2(y1 - y0, x1 - x0) * 180 / .pi,
                    color: color))
        }
        func circle(
            _ x: Double, _ y: Double, _ radius: Double, _ color: String,
            _ border: String = "transparent", _ stroke: Double = 0
        ) {
            rows.append(
                GraphMark(
                    x: x - radius, y: y - radius,
                    width: radius * 2, height: radius * 2, radius: radius,
                    color: color, borderColor: border, borderWidth: stroke))
        }
        var gridTick = sgc_next_snap_tick(session, Int64(startTick))
        while gridTick < endTick {
            let x = sgc_x_at_tick(session, gridTick)
            line(x, g.y, x, g.y + g.height, g.hairline, "#3F040000")
            gridTick = sgc_next_snap_tick(session, gridTick)
        }
        let zeroY = sgc_y_at_value(session, 0)
        var dashX = g.x
        while dashX < g.x + g.width {
            line(
                dashX, zeroY, min(g.x + g.width, dashX + 4 * g.hairline),
                zeroY, g.hairline, "#5B5652")
            dashX += 6 * g.hairline
        }
        let fineTicks = Int64(sgc_fine_ticks(session))
        for (index, vertex) in vertices.enumerated() {
            let next = index + 1 < vertices.count ? vertices[index + 1] : nil
            let x1 = next?.x ?? (g.x + g.width)
            if let next, next.tick - vertex.tick == fineTicks {
                line(vertex.x, vertex.y, x1, next.y, g.stroke, trackColor)
            } else {
                line(vertex.x, vertex.y, x1, vertex.y, g.stroke, trackColor)
                if let next { line(x1, vertex.y, x1, next.y, g.stroke, trackColor) }
            }
        }
        for vertex in vertices {
            if vertex.tick == state.selected_tick {
                circle(
                    vertex.x, vertex.y, g.selectedRadius, "transparent", "#8C857F", 1.5 * g.hairline
                )
                circle(vertex.x, vertex.y, g.nodeRadius, trackColor)
            } else {
                circle(
                    vertex.x, vertex.y, max(g.hairline, g.nodeRadius - g.hairline),
                    vertex.tick == startTick || vertex.tick == endTick ? "#57514C" : trackColor)
            }
        }
        circle(
            sgc_x_at_tick(session, state.keyboard_tick), sgc_y_at_value(session, state.live_value),
            g.nodeRadius, "transparent", "#302C29", g.hairline)
        if state.has_line_preview != 0 {
            line(
                state.anchor_x, state.anchor_y, state.pointer_x, state.pointer_y,
                g.hairline, "#302C29")
        }
        if focused {
            rows.append(
                GraphMark(
                    x: g.x + g.hairline, y: g.y + g.hairline,
                    width: g.width - 2 * g.hairline, height: g.height - 2 * g.hairline,
                    color: "transparent", borderColor: "#8C857F", borderWidth: g.hairline))
        }
        let common = min(marks.count, rows.count)
        for index in 0..<common { marks[index] = rows[index] }
        if marks.count > rows.count {
            marks.replaceSubrange(rows.count..<marks.count, with: [])
        } else if rows.count > marks.count {
            marks.replaceSubrange(marks.count..<marks.count, with: rows[marks.count...])
        }
    }
}
