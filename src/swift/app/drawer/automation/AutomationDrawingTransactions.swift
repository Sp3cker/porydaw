import Foundation
import PorydawCore

// Pencil and sweep transaction state. These types freeze gesture input and
// resolve previews into lane edits; document mutation remains in AutomationCommit.

// MARK: - Sweep

/// `SweepGesture`: the drag sweep that steps a value across the grid, and the
/// ramp sweep that fills every grid step between its anchor and its release.
public struct AutomationSweepTransaction: Sendable {
    public enum Mode: Equatable, Sendable { case drag, ramp }

    public let facts: AutomationFrozenFacts
    public let mode: Mode
    public let pressX: Double
    public let pressY: Double
    public private(set) var anchor: AutomationLanePoint
    public private(set) var current: AutomationLanePoint
    public private(set) var points: [AutomationLanePoint] = []
    public private(set) var slopExceeded = false
    /// The raw tick the last step was drawn from.
    public private(set) var previousRawTick: Double
    private var previousValue: Int
    private var slopOriginX: Double
    private var slopOriginY: Double

    public init(facts: AutomationFrozenFacts, mode: Mode, mapped: AutomationLanePoint,
                rawTick: Double, pressX: Double, pressY: Double) {
        self.facts = facts
        self.mode = mode
        anchor = mapped
        current = mapped
        previousRawTick = rawTick
        previousValue = mapped.value
        self.pressX = pressX
        self.pressY = pressY
        slopOriginX = pressX
        slopOriginY = pressY
        // A ramp is armed from its press; a drag sweep waits for the slop.
        slopExceeded = mode == .ramp
    }

    /// `SweepGesture::dragPosition`: the effective pointer once the stroke is
    /// live, ignoring motion below the activation distance.
    public mutating func dragPosition(x: Double, y: Double, activate: Bool,
                                      activationDistance: Double) -> (x: Double, y: Double)? {
        guard slopExceeded else {
            let travel = abs(x - pressX) + abs(y - pressY)
            guard activate, travel >= activationDistance else { return nil }
            slopExceeded = true
            slopOriginX = x
            slopOriginY = y
            return nil
        }
        return (pressX + x - slopOriginX, pressY + y - slopOriginY)
    }

    /// `SweepGesture::update(mapped)` for a ramp, which samples the release
    /// position only.
    public mutating func updateRamp(mapped: AutomationLanePoint) {
        current = mapped
    }

    /// `SweepGesture::update`: step the draft through every grid tick between the
    /// previous and the current raw tick, interpolating the value across them.
    public mutating func update(mapped: AutomationLanePoint, first: Tick, last: Tick,
                                rawTick: Double, fine: Bool,
                                projection: AutomationProjection) {
        current = mapped
        extend(first: first, last: last, rawTick: rawTick, fine: fine, projection: projection)
    }

    private mutating func extend(first: Tick, last: Tick, rawTick: Double, fine: Bool,
                                 projection: AutomationProjection) {
        let from = previousRawTick
        var tick = first
        while true {
            var value = current.value
            if rawTick != from {
                let fraction = min(max((Double(tick) - from) / (rawTick - from), 0), 1)
                value = previousValue
                    + Int((fraction * Double(current.value - previousValue)).rounded())
            }
            AutomationSweepTransaction.upsert(&points, AutomationLanePoint(tick: tick, value: value))
            if tick >= last { break }
            let next = projection.nextGridTick(after: tick, fine: fine)
            // A lattice that cannot advance ends the stroke instead of cycling.
            guard next > tick else { break }
            tick = next
        }
        previousRawTick = rawTick
        previousValue = current.value
    }

    /// `SweepGesture::finishedPoints`: a drag sweep keeps the points it stepped
    /// through; a ramp fills every grid tick between its endpoints.
    public func finishedPoints(fine: Bool, projection: AutomationProjection) -> [AutomationLanePoint] {
        guard mode == .ramp else { return points }
        var first = anchor
        var last = current
        if first.tick > last.tick {
            swap(&first, &last)
        }
        var result: [AutomationLanePoint] = []
        var tick = first.tick
        while true {
            let value = AutomationInterpolation.ramp.value(at: Double(tick), from: first,
                                                           to: last)
            result.append(AutomationLanePoint(tick: tick, value: value))
            if tick >= last.tick { break }
            let next = projection.nextGridTick(after: tick, fine: fine)
            guard next > tick else { break }
            tick = next
        }
        return result
    }

    /// `SweepGesture::finish`: a live sweep becomes one held-span replacement,
    /// with the trailing held value restored one grid step past the release.
    /// `nil` while the stroke never produced a point.
    public func finish(fine: Bool, projection: AutomationProjection) -> AutomationLaneEdit? {
        let result = finishedPoints(fine: fine, projection: projection)
        guard let first = result.first, let last = result.last else { return nil }
        var tickEnd = last.tick
        if tickEnd < facts.songEndTick {
            let restore = projection.nextGridTick(after: tickEnd, fine: fine)
            if restore > tickEnd { tickEnd = restore }
        }
        return AutomationLaneReplacement.heldSpan(facts.freeze(), begin: first.tick, end: tickEnd,
                                                  points: result)
    }

    /// The live draft the page paints while the stroke runs.
    public var preview: [AutomationLanePoint] { points }

    /// Insert or replace by tick, keeping the draft in tick order.
    static func upsert(_ points: inout [AutomationLanePoint], _ point: AutomationLanePoint) {
        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].tick < point.tick { low = middle + 1 } else { high = middle }
        }
        if low < points.count, points[low].tick == point.tick {
            points[low] = point
        } else {
            points.insert(point, at: low)
        }
    }

    /// The write list one lane receives: tick order with the last at a tick
    /// winning, which is the canonical shape `writeLane` stores.
    static func upsertAll(_ points: inout [AutomationLanePoint]) {
        var result: [AutomationLanePoint] = []
        result.reserveCapacity(points.count)
        for point in points.enumerated().sorted(by: {
            $0.element.tick == $1.element.tick ? $0.offset < $1.offset
                                               : $0.element.tick < $1.element.tick
        }).map(\.element) {
            if let last = result.last, last.tick == point.tick {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        points = result
    }
}

// MARK: - Pencil

/// `AutomationPencilGesture`: one deferred pencil stroke. The caller maps the
/// pointer to a sample and the crossed cells; the stroke owns the point set, its
/// provisional freehand endpoint, and the held-span preview it produces.
public struct AutomationPencilTransaction: Sendable {
    public struct Sample: Equatable, Sendable {
        public var rawTick: Double
        public var logicalX: Double
        public var logicalY: Double
        public var point: AutomationLanePoint
        public var continuousValue: Double

        public init(rawTick: Double, logicalX: Double, logicalY: Double,
                    point: AutomationLanePoint, continuousValue: Double) {
            self.rawTick = rawTick
            self.logicalX = logicalX
            self.logicalY = logicalY
            self.point = point
            self.continuousValue = continuousValue
        }
    }

    public let facts: AutomationFrozenFacts
    public let clockTicks: Tick
    public private(set) var strokePoints: [AutomationLanePoint] = []
    public private(set) var tickBegin: Tick
    public private(set) var tickEnd: Tick
    public private(set) var preview: AutomationLaneEdit
    private let freeze: AutomationLaneFreeze
    private let initialCell: AutomationGridCell
    private let initialPoint: AutomationLanePoint
    private var initialCellExited = false
    private var previous: Sample
    private var provisionalEndpoint: AutomationLanePoint?
    private var freehandStart: Sample?
    private var snappedStart: Sample?
    private var previousY: Double
    private var verticalSlopOriginX: Double
    private var verticalSlopOriginY: Double
    private var verticalSlopExceeded = false

    public init?(facts: AutomationFrozenFacts, firstSample: Sample,
                firstCell: AutomationGridCell, clockTicks: Tick) {
        guard firstSample.rawTick.isFinite, firstSample.logicalX.isFinite,
              firstSample.continuousValue.isFinite,
              firstCell.tickBegin < firstCell.tickEnd,
              firstCell.tickEnd <= facts.songEndTick else { return nil }
        self.facts = facts
        self.clockTicks = max(1, clockTicks)
        freeze = facts.freeze(includingLeadIn: true)
        initialCell = firstCell
        tickBegin = firstCell.tickBegin
        tickEnd = firstCell.tickEnd
        previous = Self.normalized(firstSample, songEndTick: facts.songEndTick)
        previousY = firstSample.logicalY
        verticalSlopOriginX = firstSample.logicalX
        verticalSlopOriginY = firstSample.logicalY
        initialPoint = AutomationLanePoint(
            tick: firstCell.tickBegin, value: Self.rounded(firstSample.continuousValue,
                                                           metadata: facts.metadata))
        preview = AutomationLaneEdit(parameter: facts.parameter, revision: facts.revision,
                                     tickBegin: tickBegin, tickEnd: tickEnd, points: [],
                                     unchanged: true)
        eraseStrokePoints(in: firstCell.tickBegin, firstCell.tickEnd)
        AutomationSweepTransaction.upsert(&strokePoints, initialPoint)
        rebuildPreview()
    }

    /// `PencilGesture::update`'s value track: while the pointer only wobbles
    /// within the vertical slop, or the axis is locked to time, the stroke keeps
    /// its previous continuous value instead of following y.
    public mutating func sampleValue(logicalX: Double, logicalY: Double, locking: Bool,
                                     freehand: Bool, verticalSlopDistance: Double,
                                     plotHeight: Double, displaySpan: Int? = nil) -> Double {
        var withinVerticalSlop = false
        if !freehand, !locking, !verticalSlopExceeded {
            let dx = abs(logicalX - verticalSlopOriginX)
            let dy = abs(logicalY - verticalSlopOriginY)
            let travel = dx + dy
            if dy < verticalSlopDistance,
               travel < verticalSlopDistance || dy == 0 || dx > dy * Self.pencilSlopAspect {
                withinVerticalSlop = true
            } else {
                verticalSlopExceeded = true
                verticalSlopOriginX = logicalX
                verticalSlopOriginY = logicalY
            }
        } else if locking, !verticalSlopExceeded {
            // A locked stretch re-bases the slop, so releasing the lock does not
            // trip it with travel that belonged to the lock.
            verticalSlopOriginX = logicalX
            verticalSlopOriginY = logicalY
        }
        let span = Double(displaySpan ?? (facts.metadata.maximum - facts.metadata.minimum))
        let delta = locking || withinVerticalSlop
            ? 0 : (previousY - logicalY) * span / max(1, plotHeight)
        return min(max(previous.continuousValue + delta, Double(facts.metadata.minimum)),
                   Double(facts.metadata.maximum))
    }

    /// `kPencilSlopAspect`: horizontal travel above this multiple of the
    /// vertical travel always counts as real paint.
    static let pencilSlopAspect = 4.0

    /// The logical x of the last applied sample, which the next cell traversal
    /// starts from.
    public var previousLogicalX: Double { previous.logicalX }

    /// `applySnappedSegment`: one cell per crossed grid cell, each carrying the
    /// value the stroke had at the cell's midpoint. Leaving the first cell
    /// restores its original point.
    @discardableResult
    public mutating func applySnappedSegment(_ sample: Sample,
                                             cells: [AutomationGridCell]) -> Bool {
        guard sample.rawTick.isFinite, sample.logicalX.isFinite, sample.continuousValue.isFinite,
              !cells.isEmpty,
              cells.allSatisfy({ $0.tickBegin < $0.tickEnd && $0.tickEnd <= facts.songEndTick })
        else { return false }
        let sample = Self.normalized(sample, songEndTick: facts.songEndTick)
        let previousWasFreehand = freehandStart != nil
        provisionalEndpoint = nil
        freehandStart = nil

        let previous = self.previous
        var continuesSnappedLine = false
        if let start = snappedStart {
            continuesSnappedLine = Self.collinearForward(
                previous.logicalX - start.logicalX, previous.continuousValue - start.continuousValue,
                sample.logicalX - previous.logicalX, sample.continuousValue - previous.continuousValue)
        }
        let anchor = continuesSnappedLine ? snappedStart! : previous
        let deltaTick = sample.rawTick - anchor.rawTick
        let interpolationBegin = min(anchor.rawTick, sample.rawTick)
        let interpolationEnd = max(anchor.rawTick, sample.rawTick)
        var endingCell = cells.count - 1
        var startingCell: Int?
        for (index, cell) in cells.enumerated() {
            if cell.contains(previous.rawTick) { startingCell = index }
            if cell.contains(sample.rawTick) { endingCell = index }
        }
        let exitsInitialCell = !initialCellExited && initialCell.contains(previous.rawTick)
            && !initialCell.contains(sample.rawTick)
        let restoreInitialPoint = exitsInitialCell && (snappedStart == nil || continuesSnappedLine)

        for (index, cell) in cells.enumerated() {
            if snappedStart != nil, let startingCell, index == startingCell, index != endingCell,
               !previousWasFreehand, !continuesSnappedLine {
                continue
            }
            let midpoint = Double(cell.tickBegin) + Double(cell.tickEnd - cell.tickBegin) / 2.0
            let sampleTick = min(max(midpoint, interpolationBegin), interpolationEnd)
            let fraction = deltaTick == 0 ? 1
                : min(max((sampleTick - anchor.rawTick) / deltaTick, 0), 1)
            let continuous = anchor.continuousValue
                + (sample.continuousValue - anchor.continuousValue) * fraction
            eraseStrokePoints(in: cell.tickBegin, cell.tickEnd)
            AutomationSweepTransaction.upsert(
                &strokePoints,
                AutomationLanePoint(tick: cell.tickBegin,
                                    value: Self.rounded(continuous, metadata: facts.metadata)))
            tickBegin = min(tickBegin, cell.tickBegin)
            tickEnd = max(tickEnd, cell.tickEnd)
        }

        if restoreInitialPoint {
            AutomationSweepTransaction.upsert(&strokePoints, initialPoint)
        }
        if exitsInitialCell { initialCellExited = true }
        self.previous = sample
        previousY = sample.logicalY
        if !continuesSnappedLine { snappedStart = previous }
        rebuildPreview()
        return true
    }

    /// `applyFreehandSegment`: sample the segment at every integer logical x,
    /// quantize to the document clock, and keep a non-integral endpoint
    /// provisional until the next segment proves it collinear.
    @discardableResult
    public mutating func applyFreehandSegment(_ sample: Sample) -> Bool {
        guard sample.rawTick.isFinite, sample.logicalX.isFinite, sample.continuousValue.isFinite
        else { return false }
        let sample = Self.normalized(sample, songEndTick: facts.songEndTick)
        snappedStart = nil
        let previous = self.previous
        let deltaX = sample.logicalX - previous.logicalX
        var preservedTurnTick: Tick?
        if let provisional = provisionalEndpoint {
            var continuesFreehandLine = false
            if let start = freehandStart {
                continuesFreehandLine = Self.collinearForward(
                    previous.logicalX - start.logicalX,
                    previous.continuousValue - start.continuousValue, deltaX,
                    sample.continuousValue - previous.continuousValue)
            }
            if !continuesFreehandLine {
                AutomationSweepTransaction.upsert(&strokePoints, provisional)
                preservedTurnTick = provisional.tick
            }
        }
        provisionalEndpoint = nil

        func apply(at logicalX: Double, provisional: Bool, interior: Bool) {
            let fraction = deltaX == 0 ? 1
                : min(max((logicalX - previous.logicalX) / deltaX, 0), 1)
            let rawTick = previous.rawTick + (sample.rawTick - previous.rawTick) * fraction
            let continuous = previous.continuousValue
                + (sample.continuousValue - previous.continuousValue) * fraction
            let integerTick = Self.clampedTick(rawTick, songEndTick: facts.songEndTick)
            let clockTick = (integerTick / clockTicks) * clockTicks
            let point = AutomationLanePoint(
                tick: clockTick, value: Self.rounded(continuous, metadata: facts.metadata))
            if provisional {
                provisionalEndpoint = point
            } else if !interior || preservedTurnTick != point.tick {
                AutomationSweepTransaction.upsert(&strokePoints, point)
            }
            let rangeEnd = Self.nextClockTick(clockTick, clockTicks: clockTicks,
                                              songEndTick: facts.songEndTick)
            tickBegin = min(tickBegin, clockTick)
            tickEnd = max(tickEnd, rangeEnd)
        }

        if deltaX > 0 {
            var x = previous.logicalX.rounded(.down) + 1
            while x < sample.logicalX { apply(at: x, provisional: false, interior: true); x += 1 }
        } else if deltaX < 0 {
            var x = previous.logicalX.rounded(.up) - 1
            while x > sample.logicalX { apply(at: x, provisional: false, interior: true); x -= 1 }
        }
        apply(at: sample.logicalX, provisional: sample.logicalX.rounded(.down) != sample.logicalX,
              interior: false)

        freehandStart = previous
        self.previous = sample
        previousY = sample.logicalY
        rebuildPreview()
        return true
    }

    /// The stroke's held-span replacement: the canonical points the release
    /// commits, with the trailing held value restored.
    public func completion() -> AutomationLaneEdit {
        AutomationLaneReplacement.heldSpan(freeze, begin: tickBegin, end: tickEnd,
                                           points: strokePoints)
    }

    private mutating func rebuildPreview() {
        var points = strokePoints
        if let provisional = provisionalEndpoint, provisional.tick >= tickBegin,
           provisional.tick <= tickEnd {
            AutomationSweepTransaction.upsert(&points, provisional)
        }
        preview = AutomationLaneReplacement.heldSpan(freeze, begin: tickBegin, end: tickEnd,
                                                     points: points)
    }

    private mutating func eraseStrokePoints(in begin: Tick, _ end: Tick) {
        strokePoints.removeAll { $0.tick >= begin && $0.tick < end }
    }

    private static func normalized(_ sample: Sample, songEndTick: Tick) -> Sample {
        var result = sample
        result.rawTick = min(max(0, sample.rawTick), Double(songEndTick))
        return result
    }

    private static func clampedTick(_ tick: Double, songEndTick: Tick) -> Tick {
        let limit = Double(songEndTick)
        let clamped = min(max(0, tick), limit)
        return clamped >= limit ? songEndTick : Tick(clamped.rounded(.down))
    }

    private static func nextClockTick(_ tick: Tick, clockTicks: Tick, songEndTick: Tick) -> Tick {
        if tick >= songEndTick || clockTicks > songEndTick - tick { return songEndTick }
        return tick + clockTicks
    }

    private static func rounded(_ continuous: Double,
                                metadata: AutomationParameterMetadata) -> Int {
        metadata.clamp(Int(min(max(continuous, Double(metadata.minimum)),
                               Double(metadata.maximum)).rounded()))
    }

    /// `collinearForward`: the provisional endpoint stands only while the
    /// previous and current segments continue the same forward line.
    static func collinearForward(_ previousAxis: Double, _ previousValue: Double,
                                 _ axis: Double, _ value: Double) -> Bool {
        if previousAxis == 0 || axis == 0 || (previousAxis > 0) != (axis > 0) { return false }
        let left = previousAxis * value
        let right = previousValue * axis
        let tolerance = max(Double.ulpOfOne * 64 * max(1, abs(left), abs(right)),
                            0.5 * max(abs(previousAxis), abs(axis)))
        return abs(left - right) <= tolerance
    }
}
