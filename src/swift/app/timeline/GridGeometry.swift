import Foundation
import PorydawCore
import PorydawDocument

public func fontPx(_ base: Double, _ multiplier: Double) -> Double {
    multiplier == 0.0 ? 0.0 : max(1.0, (base * multiplier).rounded())
}

public func fontPxF(_ base: Double, _ multiplier: Double) -> Double {
    base * multiplier
}

public func physicalPixel(_ dpr: Double) -> Double {
    dpr > 0.0 ? 1.0 / dpr : 1.0
}

public func gridLineThickness(baseFontPx: Double, devicePixelRatio: Double) -> Double {
    fontPx(baseFontPx, 1.0 / 6.0) * physicalPixel(devicePixelRatio)
}

public enum GridCameraPolicy {
    public static let seedBaseFontPx = 13.0

    public static func limits(baseFontPx b: Double) -> EditorCamera.Limits {
        EditorCamera.Limits(
            defaultPixelsPerBeat: fontPx(b, 8.0 / 3.0),
            minPixelsPerBeat: fontPx(b, 1.0 / 3.0),
            maxPixelsPerBeat: fontPx(b, 160.0 / 3.0),
            defaultKeyHeight: fontPx(b, 1.0),
            minKeyHeight: fontPx(b, 1.0 / 3.0),
            maxKeyHeight: fontPx(b, 8.0 / 3.0),
            revealViewportFraction: 1.0 / 3.0,
            minimumPlotWidth: fontPx(b, 25.0 / 6.0))
    }
}

public enum GridFeel: Equatable, Sendable {
    case straight
    case triplet
}

public enum GridSelection: Equatable, Sendable {
    case auto
    case musical(Int)
    case clock

    public func toMenuId() -> Int {
        switch self {
        case .auto: -1
        case .musical(let denominator): denominator
        case .clock: 0
        }
    }

    public static func fromMenuId(_ id: Int) -> GridSelection {
        id < 0 ? .auto : id == 0 ? .clock : .musical(id)
    }
}

public struct RollGrid: Sendable {
    private static let straightLadder = [32, 16, 8, 4, 2, 1]
    private static let tripletLadder = [48, 24, 12, 6, 3, 1]
    public var axis: TimeAxis
    public var metrics: GridMetrics
    public private(set) var feel: GridFeel = .straight
    public private(set) var selection: GridSelection = .auto
    private var clock: Tick = 0

    public init(
        axis: TimeAxis = TimeAxis(), clockTicks: Tick = 0,
        metrics: GridMetrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)
    ) {
        self.axis = axis
        self.clock = clockTicks
        self.metrics = metrics
    }

    public var clockTicks: Tick { max(1, clock) }

    private func musicalTicks(_ selection: GridSelection, feel: GridFeel) -> Tick {
        guard case .musical(let denominator) = selection,
            denominator >= 4, denominator <= Int(UInt32.max),
            denominator & (denominator - 1) == 0
        else { return 0 }
        let numerator = UInt64(axis.ticksPerBeat) * (feel == .straight ? 4 : 8)
        let divisor = UInt64(denominator) * (feel == .straight ? 1 : 3)
        return numerator % divisor == 0 ? Tick(numerator / divisor) : 0
    }

    public var selections: [GridSelection] {
        var ladder: [GridSelection] = [.auto]
        var denominator = 4
        while denominator <= Int(UInt32.max) {
            let candidate = GridSelection.musical(denominator)
            let ticks = musicalTicks(candidate, feel: feel)
            if ticks == 0 || ticks <= clockTicks { break }
            ladder.append(candidate)
            if denominator > Int(UInt32.max) / 2 { break }
            denominator *= 2
        }
        ladder.append(.clock)
        return ladder
    }

    private func canonical(_ candidate: GridSelection) -> GridSelection {
        if candidate == .auto { return .auto }
        if case .musical = candidate, musicalTicks(candidate, feel: feel) > clockTicks {
            return candidate
        }
        return .clock
    }

    @discardableResult
    mutating func setState(_ candidate: GridSelection, feel newFeel: GridFeel) -> Bool {
        let oldFeel = feel
        let oldSelection = selection
        feel = newFeel
        selection = canonical(candidate)
        return feel != oldFeel || selection != oldSelection
    }

    @discardableResult
    public mutating func setSelection(_ candidate: GridSelection) -> Bool {
        setState(candidate, feel: feel)
    }

    @discardableResult
    public mutating func setFeel(_ newFeel: GridFeel) -> Bool {
        setState(selection, feel: newFeel)
    }

    @discardableResult
    public mutating func setTicksPerClock(_ ticks: Tick) -> Bool {
        let changed = clock != ticks
        clock = ticks
        let recanonicalized = setState(selection, feel: feel)
        return recanonicalized || changed
    }

    @discardableResult
    public mutating func narrow() -> Bool {
        let ladder = selections
        guard let index = ladder.firstIndex(of: selection) else { return setSelection(selection) }
        return index + 1 < ladder.count && setSelection(ladder[index + 1])
    }

    @discardableResult
    public mutating func widen() -> Bool {
        let ladder = selections
        guard let index = ladder.firstIndex(of: selection) else { return setSelection(selection) }
        return index > 0 && setSelection(ladder[index - 1])
    }

    @discardableResult
    public mutating func toggleFeel() -> Bool {
        let previousFeel = feel
        let previousSelection = selection
        let previousSpacing = musicalTicks(previousSelection, feel: previousFeel)
        feel = previousFeel == .straight ? .triplet : .straight
        guard case .musical = previousSelection else { return true }
        if canonical(previousSelection) == previousSelection { return true }
        let towardFiner = previousFeel == .straight
        var nearest: GridSelection = .clock
        var nearestSpacing: Tick = towardFiner ? 0 : Tick.max
        for candidate in selections {
            guard case .musical = candidate else { continue }
            let spacing = musicalTicks(candidate, feel: feel)
            if towardFiner
                ? (spacing <= previousSpacing && spacing > nearestSpacing)
                : (spacing >= previousSpacing && spacing < nearestSpacing)
            {
                nearest = candidate
                nearestSpacing = spacing
            }
        }
        selection = nearest
        return true
    }

    private func adaptiveTicks(_ segment: GridSegment, camera: EditorCamera, snap: Bool) -> Tick {
        let ladder = feel == .straight ? Self.straightLadder : Self.tripletLadder
        let beat = UInt64(segment.beatTicks)
        let width = Double(beat) * camera.snapshot.pixelsPerTick
        let step =
            ladder.firstIndex {
                width / Double($0) >= metrics.autoGridMinCell
            } ?? ladder.count - 1
        let visible = max(UInt64(clockTicks), beat / UInt64(ladder[step]))
        guard snap && step > 0 else { return Tick(visible) }
        let fine = max(1, beat / UInt64(ladder[step - 1]))
        var a = visible
        var b = fine
        while b != 0 { (a, b) = (b, a % b) }
        return Tick(max(UInt64(clockTicks), a))
    }

    private var fixedTicks: Tick {
        switch selection {
        case .musical: max(clockTicks, musicalTicks(selection, feel: feel))
        case .auto, .clock: clockTicks
        }
    }

    public func gridTicksAt(_ tick: Tick, camera: EditorCamera) -> Tick {
        selection == .auto
            ? adaptiveTicks(axis.segmentAt(tick), camera: camera, snap: false)
            : fixedTicks
    }

    public func snapTicksAt(_ tick: Tick, camera: EditorCamera) -> Tick {
        selection == .auto
            ? adaptiveTicks(axis.segmentAt(tick), camera: camera, snap: true)
            : fixedTicks
    }

    public func fineGridTicks(camera: EditorCamera) -> Tick {
        clock == 0 ? gridTicksAt(0, camera: camera) : clockTicks
    }

    /// The bar owning `tick`, clipped to its signature segment.
    private func barSpan(at tick: Tick) -> (segment: GridSegment, start: UInt64, end: UInt64) {
        let segment = axis.segmentAt(tick)
        let bar = UInt64(segment.beatTicks) * UInt64(segment.beatsPerBar)
        let start = UInt64(segment.start) + (UInt64(tick) - UInt64(segment.start)) / bar * bar
        return (segment, start, min(start + bar, UInt64(segment.next)))
    }

    /// Musical lattices restart at every bar, so bar lines always snap and a
    /// stride that does not fit leaves a short last cell; the clock lattice is absolute.
    private func snapLattice(at tick: Tick) -> (anchor: UInt64, limit: UInt64) {
        if selection == .clock { return (0, UInt64(TimeDefaults.maxTick)) }
        let bar = barSpan(at: tick)
        return (bar.start, min(bar.end, UInt64(TimeDefaults.maxTick)))
    }

    /// Painted sub-grid stride: the selection, else the nearest coarser ladder rung whose
    /// lines don't touch, so a finer selection never paints fewer lines; auto adapts to zoom.
    private func paintedStride(
        _ segment: GridSegment, camera: EditorCamera
    )
        -> (stride: UInt64, absolute: Bool)?
    {
        let ppt = camera.snapshot.pixelsPerTick
        func fits(_ ticks: Tick) -> Bool {
            ticks > 0 && Double(ticks) * ppt >= metrics.gridLineStroke
        }
        switch selection {
        case .auto:
            guard Double(segment.beatTicks) * ppt >= metrics.detailMinPxPerBeat else { return nil }
            return (UInt64(adaptiveTicks(segment, camera: camera, snap: false)), false)
        case .musical(var denominator):
            while denominator >= 4 {
                let ticks = musicalTicks(.musical(denominator), feel: feel)
                if fits(ticks) { return (UInt64(ticks), false) }
                denominator /= 2
            }
            return nil
        case .clock:
            if fits(clockTicks) { return (UInt64(clockTicks), true) }
            var finest: Tick = 0
            var denominator = 4
            while denominator <= Int(UInt32.max) / 2 {
                let ticks = musicalTicks(.musical(denominator), feel: feel)
                guard ticks > clockTicks, fits(ticks) else { break }
                finest = ticks
                denominator *= 2
            }
            return finest > 0 ? (UInt64(finest), false) : nil
        }
    }

    /// Ink of a bar/beat line, nil for a beat too dense to paint (auto hides beats below
    /// detail zoom, fixed grids once they touch); fixed grids demote beats they cannot snap to.
    public func beatLineWeight(_ tick: Tick, isBar: Bool, camera: EditorCamera) -> BeatLineWeight? {
        if isBar { return .bar }
        let minimum = selection == .auto ? metrics.detailMinPxPerBeat : metrics.gridLineStroke
        guard Double(axis.segmentAt(tick).beatTicks) * camera.snapshot.pixelsPerTick >= minimum
        else { return nil }
        if selection != .auto {
            let anchor = snapLattice(at: tick).anchor
            if (UInt64(tick) - anchor) % UInt64(fixedTicks) != 0 { return .offGrid }
        }
        return gridTicksAt(tick, camera: camera) == 1 ? .beatFine : .beat
    }

    /// The painted cell around `tick`; without painted sub-grid lines, the beat (auto: bar).
    public func visibleGridCellContaining(_ tick: Tick, camera: EditorCamera) -> (start: Tick, end: Tick) {
        let span = barSpan(at: tick)
        let segment = span.segment
        let painted = paintedStride(segment, camera: camera)
        let stride =
            painted?.stride ?? UInt64(segment.beatTicks)
            * (selection == .auto ? UInt64(segment.beatsPerBar) : 1)
        let absolute = painted?.absolute ?? false
        let anchor = absolute ? 0 : span.start
        let limit = min(absolute ? UInt64(TimeDefaults.maxTick) : span.end, UInt64(TimeDefaults.maxTick))
        let start = anchor + (UInt64(tick) - anchor) / stride * stride
        let next =
            start > UInt64(TimeDefaults.maxTick) - stride
            ? UInt64(TimeDefaults.noTick) : start + stride
        return (Tick(start), Tick(min(next, limit)))
    }

    private func lattice(
        _ tick: Double, camera: EditorCamera, fine: Bool
    )
        -> (anchor: UInt64, stride: UInt64, limit: UInt64, tiesUp: Bool)
    {
        if fine || selection == .clock {
            return (0, UInt64(fineGridTicks(camera: camera)), UInt64(TimeDefaults.maxTick), true)
        }
        let position = TimeDefaults.tick(from: tick)
        let span = snapLattice(at: position)
        return (span.anchor, UInt64(snapTicksAt(position, camera: camera)), span.limit, false)
    }

    private func floor(
        _ tick: Double,
        lattice: (
            anchor: UInt64, stride: UInt64,
            limit: UInt64, tiesUp: Bool
        )
    ) -> Tick {
        let position = min(max(tick, Double(lattice.anchor)), Double(lattice.limit))
        return TimeDefaults.tick(
            from: min(
                Double(lattice.limit),
                Double(lattice.anchor)
                    + ((position - Double(lattice.anchor))
                    / Double(lattice.stride)).rounded(.down) * Double(lattice.stride)))
    }

    private func ceil(
        _ tick: Double,
        lattice: (
            anchor: UInt64, stride: UInt64,
            limit: UInt64, tiesUp: Bool
        )
    ) -> Tick {
        let low = floor(tick, lattice: lattice)
        return Double(low) >= tick
            ? low
            : Tick(min(UInt64(low) + lattice.stride, lattice.limit))
    }

    public func snapTickDown(_ tick: Double, camera: EditorCamera, fine: Bool = false) -> Tick {
        floor(max(0, tick), lattice: lattice(tick, camera: camera, fine: fine))
    }

    public func snapTickUp(_ tick: Double, camera: EditorCamera, fine: Bool = false) -> Tick {
        ceil(max(0, tick), lattice: lattice(tick, camera: camera, fine: fine))
    }

    public func snapTick(_ tick: Double, camera: EditorCamera, fine: Bool = false) -> Tick {
        let lattice = lattice(tick, camera: camera, fine: fine)
        let low = floor(max(0, tick), lattice: lattice)
        let high = ceil(max(0, tick), lattice: lattice)
        let below = tick - Double(low)
        let above = Double(high) - tick
        return (lattice.tiesUp ? below < above : below <= above) ? low : high
    }

    public func nextSubdivisionTickAfter(_ tick: Tick, camera: EditorCamera) -> Tick {
        let stride = UInt64(gridTicksAt(tick, camera: camera))
        let lattice = snapLattice(at: tick)
        let next = lattice.anchor + ((UInt64(tick) - lattice.anchor) / stride + 1) * stride
        return Tick(min(next, lattice.limit))
    }

    public func nextSnapTickAfter(_ tick: Tick, camera: EditorCamera, fine: Bool = false) -> Tick {
        if fine || selection == .clock {
            let stride = UInt64(fineGridTicks(camera: camera))
            let next = (UInt64(tick) / stride + 1) * stride
            return Tick(min(next, UInt64(TimeDefaults.maxTick)))
        }
        let stride = UInt64(snapTicksAt(tick, camera: camera))
        let lattice = snapLattice(at: tick)
        let next = lattice.anchor + ((UInt64(tick) - lattice.anchor) / stride + 1) * stride
        return Tick(min(next, lattice.limit))
    }

    /// Painted sub-grid lines off the beat, walked bar by bar. A painted stride that does not
    /// divide the beat cannot inherit the beat hierarchy, so all its lines paint at level 1.
    public func forEachSubdivision(
        from begin: Tick, to end: Tick, camera: EditorCamera,
        _ visit: (Tick, Int) -> Void
    ) {
        var start = begin
        while start < end {
            let span = barSpan(at: start)
            let segment = span.segment
            let stop = Tick(min(UInt64(end), span.end))
            let beat = UInt64(segment.beatTicks)
            if let painted = paintedStride(segment, camera: camera), painted.stride % beat != 0 {
                let stride = painted.stride
                let offBeat = beat % stride != 0
                let anchor = painted.absolute ? 0 : span.start
                let relative = UInt64(start) - anchor
                var tick = anchor + (relative / stride + (relative % stride == 0 ? 0 : 1)) * stride
                while tick < UInt64(stop) {
                    let beatRelative = (tick - UInt64(segment.start)) % beat
                    if beatRelative != 0 {
                        let level: Int
                        if offBeat || beatRelative % max(1, beat / (feel == .triplet ? 3 : 2)) == 0 {
                            level = 1
                        } else if beatRelative % max(1, beat / (feel == .triplet ? 6 : 4)) == 0 {
                            level = 2
                        } else {
                            level = 3
                        }
                        visit(Tick(tick), level)
                    }
                    tick += stride
                }
            }
            start = stop
        }
    }
}

public enum BeatLineWeight: Equatable, Sendable {
    case bar
    case beat
    case beatFine
    case offGrid
}

public struct GridMetrics: Sendable {
    public var baseFontPx: Double = 13
    public var dpr: Double = 1
    public var timeAxis = TimeAxis()

    public var keyboardWidth: Double = 56
    public var noteMinWidth: Double = 2
    var noteMinHeight: Double = 2
    public var edgeGripReach: Double = 3.25
    var moveZoneMinWidth: Double = 6.5
    var selectionRingDip: Double = 1.625
    public var chipHPadding: Double = 9
    public var chipVPadding: Double = 2
    public var chipRightInset: Double = 2
    public var chipRadius: Double = 3
    public var keyLabelRightInset: Double = 3
    public var drawThreshold: Double = 3

    var detailMinPxPerBeat: Double = 11
    public let gridLineStroke: Double
    var autoGridMinCell: Double = 17

    public var rulerBeatLabelZoomFactor: Double = 3.0
    public var spaceHalf: Double = 2
    public var spaceTwo: Double = 7
    public var pixel: Double = 1

    public static let ticksPerBeat = 24
    public static let songLengthTicks = 384

    public init(
        baseFontPx: Double, dpr: Double, width _: Double, height _: Double,
        timeAxis: TimeAxis = TimeAxis()
    ) {
        self.baseFontPx = baseFontPx
        self.dpr = dpr
        self.timeAxis = timeAxis
        let b = baseFontPx
        keyboardWidth = fontPx(b, 13.0 / 3.0)
        noteMinWidth = fontPx(b, 1.0 / 6.0)
        noteMinHeight = fontPx(b, 1.0 / 6.0)
        edgeGripReach = fontPxF(b, 0.25)
        moveZoneMinWidth = fontPxF(b, 0.5)
        selectionRingDip = fontPxF(b, 1.0 / 8.0)
        chipHPadding = fontPx(b, 2.0 / 3.0)
        chipVPadding = fontPx(b, 1.0 / 6.0)
        chipRightInset = fontPx(b, 1.0 / 6.0)
        chipRadius = fontPx(b, 0.25)
        keyLabelRightInset = fontPx(b, 0.25)
        drawThreshold = fontPx(b, 0.25)
        detailMinPxPerBeat = fontPx(b, 5.0 / 6.0)
        gridLineStroke = gridLineThickness(baseFontPx: baseFontPx, devicePixelRatio: dpr)
        autoGridMinCell = fontPx(b, 4.0 / 3.0)
        spaceHalf = fontPx(b, 0.125)
        spaceTwo = fontPx(b, 0.5)
        pixel = physicalPixel(dpr)
    }

    public func noteRect(
        camera: EditorCamera, x0: Double, x1: Double, pitch: Int
    ) -> (x: Double, y: Double, w: Double, h: Double) {
        let snapshot = camera.snapshot
        let row = camera.projection.row(forPitch: min(127, max(0, pitch)))
        guard row != PitchProjection.hiddenRow,
            let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight,
                scrollY: snapshot.scrollY, dpr: dpr),
            let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight,
                scrollY: snapshot.scrollY, dpr: dpr)
        else { return (x0, 0, 0, 0) }
        return (
            x0, top + pixel, max(noteMinWidth, x1 - x0),
            max(noteMinHeight * pixel, bottom - top - pixel)
        )
    }

    public func noteBox(
        camera: EditorCamera, x0: Double, x1: Double, pitch: Int
    ) -> (x: Double, y: Double, w: Double, h: Double) {
        let r = noteRect(camera: camera, x0: x0, x1: x1, pitch: pitch)
        return (r.x, r.y, r.w, r.h - pixel)
    }

    public func edgeGripInnerReach(rectWidth: Double) -> Double {
        min(edgeGripReach, max(0.0, (rectWidth - moveZoneMinWidth) / 2.0))
    }

    public func fittedFrameThickness(
        rectWidth: Double, rectHeight: Double,
        requestedPixels: Int, insetPixels: Int
    ) -> Int {
        let minDim = Int((min(rectWidth, rectHeight) * dpr).rounded())
        return min(requestedPixels, max(0, (minDim - 1) / 2 - insetPixels))
    }

    public var noteBorderPixels: Int { max(1, Int(dpr.rounded())) }
    public var selectionRingPixels: Int { max(1, Int((selectionRingDip * dpr).rounded())) }
}
