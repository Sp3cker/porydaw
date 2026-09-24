import Foundation

/// Note-span curve editor. The document never sees a draft until the gesture ends.
public struct PitchBendKernel {
    public enum Lane { case pitch, modulation }
    public struct Point: Equatable {
        public var tick: Int
        public var value: Int
    }

    private struct Stroke {
        var original: [Int: Int]
        var initialKeyboardTick: Int
        var anchor: Point
        var previous: Point
        var line: Bool
    }
    private struct VertexDrag {
        var original: [Int: Int]
        var originalTick: Int
    }
    private enum Gesture { case stroke(Stroke), vertex(VertexDrag) }

    public let lane: Lane
    public let startTick: Int
    public let endTick: Int
    public let snapTicks: Int
    public let fineTicks: Int
    public var geometry: PitchBendGeometry
    public private(set) var points: [Int: Int]
    public private(set) var endValue: Int
    public private(set) var selectedTick: Int?
    public private(set) var keyboardTick: Int
    public private(set) var liveValue: Int
    private var gesture: Gesture?
    private var wheelRemainder = 0.0

    public init(lane: Lane, geometry: PitchBendGeometry, startTick: Int, endTick: Int,
                snapTicks: Int, fineTicks: Int, points: [Int: Int], endValue: Int) {
        self.lane = lane
        self.geometry = geometry
        self.startTick = startTick
        self.endTick = endTick
        self.snapTicks = max(1, snapTicks)
        self.fineTicks = max(1, fineTicks)
        self.points = points
        self.endValue = min(max(endValue, lane == .pitch ? -8192 : 0),
                            lane == .pitch ? 8191 : 127)
        self.points[endTick] = self.endValue
        keyboardTick = startTick
        liveValue = points[startTick] ?? 0
    }

    public var hasGesture: Bool { gesture != nil }
    public var minimumValue: Int { lane == .pitch ? -8192 : 0 }
    public var maximumValue: Int { lane == .pitch ? 8191 : 127 }
    public var orderedPoints: [Point] {
        points.keys.sorted().compactMap { tick in
            points[tick].map { Point(tick: tick, value: $0) }
        }
    }

    public mutating func setCurve(_ curve: [Int: Int], endValue: Int) {
        points = curve
        self.endValue = min(max(endValue, minimumValue), maximumValue)
        points[endTick] = self.endValue
        if let selectedTick, points[selectedTick] == nil { self.selectedTick = nil }
        gesture = nil
        keyboardTick = startTick
        liveValue = value(at: startTick)
    }

    public mutating func reset() {
        points = [startTick: 0, endTick: endValue]
        selectedTick = nil
        gesture = nil
        keyboardTick = startTick
        liveValue = 0
    }

    public mutating func select(_ tick: Int?) {
        selectedTick = tick.flatMap { points[$0] != nil ? $0 : nil }
    }

    @discardableResult
    public mutating func removeSelectedVertex() -> Bool {
        guard let selectedTick, selectedTick != startTick, selectedTick != endTick,
              points.removeValue(forKey: selectedTick) != nil else { return false }
        self.selectedTick = nil
        liveValue = value(at: keyboardTick)
        return true
    }

    public func x(at tick: Int) -> Double {
        let fraction = endTick > startTick ? Double(tick - startTick) / Double(endTick - startTick) : 0
        return geometry.canvasX + (min(1, max(0, fraction)) * (geometry.canvasWidth - 1)).rounded()
    }

    public func y(at value: Int) -> Double {
        let bottom = geometry.canvasY + geometry.canvasHeight - 1
        if lane == .modulation {
            return bottom - (Double(min(127, max(0, value))) * geometry.canvasHeight / 127).rounded()
        }
        let center = geometry.canvasY + ((geometry.canvasHeight - 1) / 2).rounded(.down)
        if value >= 0 {
            return center - (Double(value) * (center - geometry.canvasY) / 8191).rounded()
        }
        return center + (Double(-value) * (bottom - center) / 8192).rounded()
    }

    public func value(atY y: Double) -> Int {
        let bottom = geometry.canvasY + geometry.canvasHeight - 1
        let clamped = min(bottom, max(geometry.canvasY, y.rounded()))
        if lane == .modulation {
            return min(127, max(0, Int(((bottom - clamped) * 127 / max(1, geometry.canvasHeight)).rounded())))
        }
        let center = geometry.canvasY + ((geometry.canvasHeight - 1) / 2).rounded(.down)
        if abs(clamped - center) <= geometry.zeroDetent { return 0 }
        let raw = clamped <= center
            ? Int(((center - clamped) * 8191 / max(1, center - geometry.canvasY)).rounded())
            : -Int(((clamped - center) * 8192 / max(1, bottom - center)).rounded())
        if raw == -8192 || raw == 8191 { return raw }
        return min(8191, max(-8192, Int((Double(raw) / 128).rounded()) * 128))
    }

    public func value(at tick: Int) -> Int {
        guard let previous = points.keys.filter({ $0 <= tick }).max() else { return 0 }
        return points[previous] ?? 0
    }

    public func hitTest(x: Double, y: Double) -> Point? {
        let radius2 = geometry.nodeHitRadius * geometry.nodeHitRadius
        var nearest: Point?
        var distance = radius2
        for point in orderedPoints {
            let dx = x - self.x(at: point.tick)
            let dy = y - self.y(at: point.value)
            let squared = dx * dx + dy * dy
            if squared <= radius2 && (nearest == nil || squared < distance
                || (abs(squared - distance) < 0.00001 && point.tick < (nearest?.tick ?? Int.max))) {
                distance = squared
                nearest = point
            }
        }
        return nearest
    }

    private func snap(_ tick: Double, fine: Bool) -> Int {
        let stride = Double(fine ? fineTicks : snapTicks)
        let lo = (max(0, tick) / stride).rounded(.down) * stride
        let rounded = tick - lo <= stride / 2 ? lo : lo + stride
        let last = endTick > startTick ? endTick - 1 : startTick
        let lastSnapped = Int((Double(last) / stride).rounded(.down) * stride)
        return min(max(startTick, Int(rounded)), max(startTick, min(last, lastSnapped)))
    }

    public func tick(atX x: Double, fine: Bool = false) -> Int {
        let fraction = min(1, max(0, (x - geometry.canvasX) / max(1, geometry.canvasWidth - 1)))
        return snap(Double(startTick) + fraction * Double(endTick - startTick), fine: fine)
    }

    public mutating func setKeyboardFraction(_ fraction: Double) {
        keyboardTick = snap(Double(startTick) + min(1, max(0, fraction)) * Double(endTick - startTick), fine: false)
        liveValue = value(at: keyboardTick)
    }

    public mutating func begin(x: Double, y: Double, line: Bool) {
        if let hit = hitTest(x: x, y: y) {
            selectedTick = hit.tick
            gesture = .vertex(VertexDrag(original: points, originalTick: hit.tick))
            keyboardTick = hit.tick
            liveValue = hit.value
            return
        }
        selectedTick = nil
        let point = Point(tick: tick(atX: x, fine: line), value: value(atY: y))
        gesture = .stroke(Stroke(original: points, initialKeyboardTick: keyboardTick,
                                 anchor: point, previous: point, line: line))
        replace(from: point, to: point, fine: line)
        keyboardTick = point.tick
        liveValue = point.value
    }

    @discardableResult
    public mutating func update(x: Double, y: Double, fine: Bool) -> Bool {
        guard let gesture else { return false }
        switch gesture {
        case .stroke(var stroke):
            let point = Point(tick: tick(atX: x, fine: stroke.line), value: value(atY: y))
            if stroke.line { points = stroke.original }
            replace(from: stroke.line ? stroke.anchor : stroke.previous, to: point, fine: stroke.line)
            stroke.previous = point
            self.gesture = .stroke(stroke)
            keyboardTick = point.tick
            liveValue = point.value
        case .vertex(let drag):
            points = drag.original
            let endpoint = drag.originalTick == startTick || drag.originalTick == endTick
            var tick = endpoint ? drag.originalTick : min(endTick - 1, max(startTick + 1,
                tick(atX: x, fine: fine)))
            if tick != drag.originalTick && points[tick] != nil {
                let delta = tick > drag.originalTick ? 1 : -1
                while tick > startTick && tick < endTick && points[tick] != nil { tick += delta }
                if tick <= startTick || tick >= endTick { tick = drag.originalTick }
            }
            if tick != drag.originalTick { points.removeValue(forKey: drag.originalTick) }
            let value = drag.originalTick == endTick ? endValue : value(atY: y)
            points[tick] = value
            points[endTick] = endValue
            selectedTick = tick
            keyboardTick = tick
            liveValue = value
        }
        return true
    }

    public mutating func finish() { gesture = nil }

    public mutating func cancelGesture() {
        guard let gesture else { return }
        switch gesture {
        case .stroke(let stroke):
            points = stroke.original
            keyboardTick = stroke.initialKeyboardTick
        case .vertex(let drag):
            points = drag.original
            selectedTick = drag.originalTick
            keyboardTick = drag.originalTick
        }
        liveValue = value(at: keyboardTick)
        self.gesture = nil
    }

    public var linePreview: (Point, Point)? {
        guard case .stroke(let stroke) = gesture, stroke.line else { return nil }
        return (stroke.anchor, stroke.previous)
    }

    public mutating func accumulateWheel(_ units: Double) -> Int {
        wheelRemainder += units
        let steps = Int(wheelRemainder / 120)
        wheelRemainder -= Double(steps) * 120
        return steps
    }

    private mutating func replace(from first: Point, to last: Point, fine: Bool) {
        let low = min(first.tick, last.tick)
        let high = max(first.tick, last.tick)
        for tick in points.keys.filter({ $0 >= low && $0 <= high }) {
            points.removeValue(forKey: tick)
        }
        let stride = max(1, fine ? fineTicks : snapTicks)
        func interpolated(_ tick: Int) -> Int {
            let fraction = first.tick == last.tick ? 1.0
                : min(1, max(0, Double(tick - first.tick) / Double(last.tick - first.tick)))
            return min(max(first.value + Int((fraction * Double(last.value - first.value)).rounded()),
                           minimumValue), maximumValue)
        }
        points[low] = interpolated(low)
        if high > low {
            var tick = (low / stride + 1) * stride
            while tick < high {
                points[tick] = interpolated(tick)
                tick += stride
            }
            points[high] = interpolated(high)
        }
        points[endTick] = endValue
    }
}
