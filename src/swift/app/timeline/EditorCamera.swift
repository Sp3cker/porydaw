public struct PitchProjection: Equatable, Sendable {
    public static let hiddenRow = -1

    private var pitchesByRow: [UInt8]
    private var rowsByPitch: [Int8]

    public init() {
        pitchesByRow = Array((UInt8(0)...UInt8(127)).reversed())
        rowsByPitch = Array((Int8(0)...Int8(127)).reversed())
    }

    public init(visiblePitches: [UInt8]) {
        precondition(visiblePitches.count <= 128)
        for index in visiblePitches.indices {
            precondition(visiblePitches[index] < 128)
            precondition(index == visiblePitches.startIndex ||
                         visiblePitches[index] > visiblePitches[visiblePitches.index(before: index)])
        }
        pitchesByRow = Array(visiblePitches.reversed())
        rowsByPitch = Array(repeating: Int8(Self.hiddenRow), count: 128)
        for (row, pitch) in pitchesByRow.enumerated() { rowsByPitch[Int(pitch)] = Int8(row) }
    }

    public var visibleRowCount: Int { pitchesByRow.count }

    public func visiblePitch(at row: Int) -> Int? {
        pitchesByRow.indices.contains(row) ? Int(pitchesByRow[row]) : nil
    }

    public func row(forPitch pitch: Int) -> Int {
        (0..<128).contains(pitch) ? Int(rowsByPitch[pitch]) : Self.hiddenRow
    }

    public func nearestVisiblePitch(to pitch: Int) -> Int? {
        guard !pitchesByRow.isEmpty else { return nil }
        var firstNotHigher = 0
        var end = pitchesByRow.count
        while firstNotHigher < end {
            let middle = firstNotHigher + (end - firstNotHigher) / 2
            if Int(pitchesByRow[middle]) > pitch { firstNotHigher = middle + 1 }
            else { end = middle }
        }
        if firstNotHigher == 0 { return Int(pitchesByRow[0]) }
        if firstNotHigher == pitchesByRow.count { return Int(pitchesByRow[pitchesByRow.count - 1]) }
        let lower = Int(pitchesByRow[firstNotHigher])
        let higher = Int(pitchesByRow[firstNotHigher - 1])
        return abs(pitch - lower) <= abs(higher - pitch) ? lower : higher
    }

    public func totalHeight(keyHeight: Double) -> Double {
        Double(visibleRowCount) * max(0, keyHeight.isFinite ? keyHeight : 0)
    }

    public func rowTop(_ row: Int, keyHeight: Double, scrollY: Double, dpr: Double) -> Double? {
        guard pitchesByRow.indices.contains(row) else { return nil }
        return Self.snappedEdge(row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
    }

    public func rowBottom(_ row: Int, keyHeight: Double, scrollY: Double, dpr: Double) -> Double? {
        guard pitchesByRow.indices.contains(row) else { return nil }
        return Self.snappedEdge(row + 1, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
    }

    public func row(atY y: Double, keyHeight: Double, scrollY: Double, dpr: Double) -> Int {
        guard visibleRowCount > 0, y.isFinite, keyHeight.isFinite, keyHeight > 0,
              let top = rowTop(0, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr),
              let bottom = rowBottom(visibleRowCount - 1, keyHeight: keyHeight,
                                     scrollY: scrollY, dpr: dpr),
              y >= top, y < bottom else { return Self.hiddenRow }
        var first = 0
        var end = visibleRowCount
        while first < end {
            let middle = first + (end - first) / 2
            let edge = Self.snappedEdge(middle + 1, keyHeight: keyHeight,
                                        scrollY: scrollY, dpr: dpr)
            if y < edge { end = middle } else { first = middle + 1 }
        }
        return first
    }

    public func pitch(atY y: Double, keyHeight: Double, scrollY: Double, dpr: Double) -> Int? {
        visiblePitch(at: row(atY: y, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr))
    }

    private static func snappedEdge(_ row: Int, keyHeight: Double,
                                    scrollY: Double, dpr: Double) -> Double {
        let scale = dpr.isFinite && dpr > 0 ? dpr : 1
        return ((Double(row) * keyHeight - scrollY) * scale).rounded() / scale
    }
}

public struct EditorCamera: Sendable {
    public struct Limits: Equatable, Sendable {
        public let defaultPixelsPerBeat: Double
        public let minPixelsPerBeat: Double
        public let maxPixelsPerBeat: Double
        public let defaultKeyHeight: Double
        public let minKeyHeight: Double
        public let maxKeyHeight: Double
        public let revealViewportFraction: Double
        public let minimumPlotWidth: Double

        public init(defaultPixelsPerBeat: Double, minPixelsPerBeat: Double,
                    maxPixelsPerBeat: Double, defaultKeyHeight: Double,
                    minKeyHeight: Double, maxKeyHeight: Double,
                    revealViewportFraction: Double, minimumPlotWidth: Double) {
            self.defaultPixelsPerBeat = defaultPixelsPerBeat
            self.minPixelsPerBeat = minPixelsPerBeat
            self.maxPixelsPerBeat = maxPixelsPerBeat
            self.defaultKeyHeight = defaultKeyHeight
            self.minKeyHeight = minKeyHeight
            self.maxKeyHeight = maxKeyHeight
            self.revealViewportFraction = revealViewportFraction
            self.minimumPlotWidth = minimumPlotWidth
        }
    }

    public struct Snapshot: Equatable, Sendable {
        public let pixelsPerBeat: Double
        public let pixelsPerTick: Double
        public let scrollX: Double
        public let keyHeight: Double
        public let scrollY: Double
        public let minHScroll: Double
        public let maxHScroll: Double
        public let maxVScroll: Double
        public let viewportWidth: Double
        public let rollHeight: Double
    }
    /// The camera fields that affect a publication route.
    ///
    /// `zoom` covers both the horizontal/time scale (`pixelsPerBeat`) and the
    /// roll row-height scale (`keyHeight`); `geometry` covers the viewport,
    /// bounds and pitch projection.
    public struct Change: OptionSet, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let scrollX = Change(rawValue: 1 << 0)
        public static let scrollY = Change(rawValue: 1 << 1)
        public static let zoom = Change(rawValue: 1 << 2)
        public static let geometry = Change(rawValue: 1 << 3)

        public static func between(_ old: Snapshot, _ new: Snapshot,
                                   projectionChanged: Bool = false) -> Change {
            var result: Change = []
            if old.scrollX != new.scrollX { result.insert(.scrollX) }
            if old.scrollY != new.scrollY { result.insert(.scrollY) }
            if old.pixelsPerBeat != new.pixelsPerBeat
                || old.pixelsPerTick != new.pixelsPerTick
                || old.keyHeight != new.keyHeight
            {
                result.insert(.zoom)
            }
            if old.viewportWidth != new.viewportWidth
                || old.rollHeight != new.rollHeight
                || old.minHScroll != new.minHScroll
                || old.maxHScroll != new.maxHScroll
                || old.maxVScroll != new.maxVScroll
                || projectionChanged
            {
                result.insert(.geometry)
            }
            return result
        }
    }

    public struct ZoomResult: Equatable, Sendable {
        public let zoomChanged: Bool
        public let scrollChanged: Bool
    }

    public private(set) var projection: PitchProjection
    private var limits: Limits
    private var ticksPerBeat: UInt32
    private var lengthTicks: UInt64?
    private var viewportWidth: Double
    private var rollHeight: Double
    private var pixelsPerBeat: Double
    private var scrollX: Double
    private var keyHeight: Double
    private var scrollY: Double

    public init(ticksPerBeat: UInt32, lengthTicks: UInt64?, viewportWidth: Double,
                rollHeight: Double, limits: Limits,
                projection: PitchProjection = PitchProjection()) {
        self.limits = limits
        self.ticksPerBeat = max(1, ticksPerBeat)
        self.lengthTicks = lengthTicks
        self.viewportWidth = Self.dimension(viewportWidth, floor: limits.minimumPlotWidth)
        self.rollHeight = Self.dimension(rollHeight, floor: 0)
        pixelsPerBeat = Self.clampFinite(limits.defaultPixelsPerBeat,
                                         limits.minPixelsPerBeat, limits.maxPixelsPerBeat)
        keyHeight = Self.clampFinite(limits.defaultKeyHeight,
                                     limits.minKeyHeight, limits.maxKeyHeight)
        scrollX = 0
        scrollY = 0
        self.projection = projection
        reconcile(homeWhenUnbound: true)
    }

    public var snapshot: Snapshot {
        Snapshot(pixelsPerBeat: pixelsPerBeat, pixelsPerTick: pixelsPerTick,
                 scrollX: scrollX, keyHeight: keyHeight, scrollY: scrollY,
                 minHScroll: minHScroll, maxHScroll: maxHScroll,
                 maxVScroll: maxVScroll, viewportWidth: viewportWidth,
                 rollHeight: rollHeight)
    }

    public var pixelsPerTick: Double { pixelsPerBeat / Double(ticksPerBeat) }
    public var leadPad: Double { min(max((viewportWidth * 0.10).rounded(), 48), 256) }
    public var minHScroll: Double { -leadPad }
    public var maxHScroll: Double {
        lengthTicks.map { Double($0) * pixelsPerTick } ?? 0
    }
    public var maxVScroll: Double {
        max(0, projection.totalHeight(keyHeight: keyHeight) - rollHeight)
    }

    public func contentX(tick: Double) -> Double { tick * pixelsPerTick - scrollX }
    public func tickAtContentX(_ x: Double) -> Double { (x + scrollX) / pixelsPerTick }
    public func displayX(tick: Double, origin: Double, dpr: Double) -> Double {
        let x = origin + contentX(tick: tick)
        return dpr.isFinite && dpr > 0 ? (x * dpr).rounded() / dpr : x
    }

    public mutating func updateLimits(_ limits: Limits) {
        self.limits = limits
        _ = setTimeZoom(pixelsPerBeat)
        _ = setKeyHeight(keyHeight)
        viewportWidth = Self.dimension(viewportWidth, floor: limits.minimumPlotWidth)
        reconcile(homeWhenUnbound: lengthTicks == nil)
    }

    public mutating func updateTimeDomain(ticksPerBeat: UInt32, lengthTicks: UInt64?) {
        self.ticksPerBeat = max(1, ticksPerBeat)
        self.lengthTicks = lengthTicks
        reconcile(homeWhenUnbound: lengthTicks == nil)
    }

    public mutating func updateViewport(width: Double, rollHeight: Double) {
        viewportWidth = Self.dimension(width, floor: limits.minimumPlotWidth)
        self.rollHeight = Self.dimension(rollHeight, floor: 0)
        reconcile(homeWhenUnbound: lengthTicks == nil)
    }

    public mutating func updateProjection(_ projection: PitchProjection) {
        self.projection = projection
        let currentScroll = scrollY
        _ = setVScroll(currentScroll)
    }

    @discardableResult public mutating func setHScroll(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        let next = min(max(value, minHScroll), maxHScroll)
        defer { scrollX = next }
        return next != scrollX
    }

    @discardableResult public mutating func setVScroll(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        let next = min(max(value, 0), maxVScroll)
        defer { scrollY = next }
        return next != scrollY
    }

    @discardableResult public mutating func setTimeZoom(_ value: Double) -> Bool {
        let next = Self.clampFinite(value, limits.minPixelsPerBeat, limits.maxPixelsPerBeat)
        let changed = next != pixelsPerBeat
        pixelsPerBeat = next
        return changed
    }

    @discardableResult public mutating func setKeyHeight(_ value: Double) -> Bool {
        let next = Self.clampFinite(value, limits.minKeyHeight, limits.maxKeyHeight)
        let changed = next != keyHeight
        keyHeight = next
        return changed
    }

    @discardableResult public mutating func scrollByPx(_ delta: Double) -> Bool {
        delta.isFinite ? setHScroll(scrollX + delta) : false
    }

    @discardableResult public mutating func scrollRollBy(_ delta: Double) -> Bool {
        delta.isFinite ? setVScroll(scrollY + delta) : false
    }

    public mutating func zoomAroundContentX(factor: Double, anchorContentX: Double) -> ZoomResult {
        guard factor.isFinite, factor > 0, anchorContentX.isFinite else {
            return ZoomResult(zoomChanged: false, scrollChanged: false)
        }
        let oldZoom = pixelsPerBeat
        let oldScroll = scrollX
        pixelsPerBeat = Self.clampFinite(oldZoom * factor,
                                         limits.minPixelsPerBeat, limits.maxPixelsPerBeat)
        let anchorBeat = (anchorContentX + oldScroll) / oldZoom
        _ = setHScroll(anchorBeat * pixelsPerBeat - anchorContentX)
        return ZoomResult(zoomChanged: pixelsPerBeat != oldZoom, scrollChanged: scrollX != oldScroll)
    }

    @discardableResult public mutating func zoomKeyHeight(factor: Double, anchorY: Double) -> Bool {
        guard factor.isFinite, factor > 0, anchorY.isFinite else { return false }
        let oldHeight = keyHeight
        let next = Self.clampFinite(oldHeight * factor, limits.minKeyHeight, limits.maxKeyHeight)
        guard next != oldHeight else { return false }
        let anchorRow = (anchorY + scrollY) / oldHeight
        keyHeight = next
        _ = setVScroll(anchorRow * next - anchorY)
        return true
    }

    public mutating func restore(pixelsPerBeat: Double, keyHeight: Double,
                                 scrollX: Double, scrollY: Double) {
        _ = setTimeZoom(pixelsPerBeat.isFinite ? pixelsPerBeat : limits.defaultPixelsPerBeat)
        _ = setKeyHeight(keyHeight.isFinite ? keyHeight : limits.defaultKeyHeight)
        _ = setHScroll(scrollX.isFinite ? scrollX : 0)
        _ = setVScroll(scrollY.isFinite ? scrollY : 0)
    }

    @discardableResult public mutating func ensureTickVisible(_ tick: UInt64, dpr: Double) -> Bool {
        let physicalPixel = dpr.isFinite && dpr > 0 ? 1 / dpr : 1
        let x = displayX(tick: Double(tick), origin: 0, dpr: dpr)
        guard x < 0 || x > viewportWidth - physicalPixel else { return false }
        return setHScroll(Double(tick) * pixelsPerTick - viewportWidth * limits.revealViewportFraction)
    }

    @discardableResult public mutating func ensureRangeVisible(startTick: UInt64, endTick: UInt64,
                                                                preferEnd: Bool, dpr: Double) -> Bool {
        let x0 = contentX(tick: Double(startTick)), x1 = contentX(tick: Double(endTick))
        let physicalPixel = dpr.isFinite && dpr > 0 ? 1 / dpr : 1
        let right = viewportWidth - physicalPixel
        let displayed0 = displayX(tick: Double(startTick), origin: 0, dpr: dpr)
        let displayed1 = displayX(tick: Double(endTick), origin: 0, dpr: dpr)
        let delta: Double
        if displayed1 - displayed0 > right { delta = preferEnd ? x1 - right : x0 }
        else if displayed1 > right { delta = x1 - right }
        else if displayed0 < 0 { delta = x0 }
        else { return false }
        return setHScroll(scrollX + delta)
    }

    @discardableResult public mutating func ensureKeyVisible(_ pitch: Int) -> Bool {
        let row = projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow else { return false }
        let top = Double(row) * keyHeight - scrollY
        let bottom = top + keyHeight
        if top < 0 { return setVScroll(scrollY + top) }
        if bottom > rollHeight { return setVScroll(scrollY + bottom - rollHeight) }
        return false
    }

    private mutating func reconcile(homeWhenUnbound: Bool) {
        let currentX = scrollX
        let currentY = scrollY
        if homeWhenUnbound { scrollX = minHScroll } else { _ = setHScroll(currentX) }
        _ = setVScroll(currentY)
    }

    private static func dimension(_ value: Double, floor: Double) -> Double {
        value.isFinite ? max(floor, value) : floor
    }

    private static func clampFinite(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        let lo = lower.isFinite ? lower : 0
        let hi = upper.isFinite ? max(lo, upper) : lo
        return min(max(value.isFinite ? value : lo, lo), hi)
    }
}
