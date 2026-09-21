import Foundation
import PorydawCore

// Frozen Automation interactions and their semantic commit policy. Every
// gesture freezes its target set, before-values, revision, camera and modifier
// policy at begin; motion only rebuilds the preview; the release resolves into
// one plan and the plan commits through one existing `SongDocument` operation,
// so one completed user action is at most one history entry.
//
// Behaviour follows `src/ui/editordrawer/nodelane/{gesture,pencilgesture,
// nodelane,batchcommit}.cpp` and the canvas commit paths
// (`automationcanvas_gesture.cpp`, `automationcanvas_menu.cpp`,
// `automationcanvas_pointmenu.cpp`). Nothing here encodes MIDI, owns history,
// or claims native clipboard interoperability: the semantic clipboard payload
// stays an in-process Swift value.

// MARK: - Modifier policy and pointer mechanics

/// One pointer event's modifier policy, resolved once at the event's begin.
public struct AutomationModifiers: Equatable, Sendable {
    /// Alt: snap to the document clock lattice instead of the visible grid.
    public var fine: Bool
    /// Control: snap the value onto the parameter's neutral.
    public var snapValue: Bool
    /// Shift: arm the axis lock, or select a ramp sweep.
    public var shift: Bool

    public init(fine: Bool = false, snapValue: Bool = false, shift: Bool = false) {
        self.fine = fine
        self.snapValue = snapValue
        self.shift = shift
    }
}

public enum AutomationAxisLock: Equatable, Sendable {
    case none
    case time
    case value

    /// `resolveAxisLock`: only a shift-held move past the activation distance
    /// picks an axis, and it keeps the axis it picked.
    public static func resolve(current: AutomationAxisLock, shiftHeld: Bool,
                               originX: Double, originY: Double, x: Double, y: Double,
                               activationDistance: Double) -> AutomationAxisLock {
        guard shiftHeld else { return .none }
        if current != .none { return current }
        let dx = x - originX
        let dy = y - originY
        guard abs(dx) + abs(dy) >= activationDistance else { return .none }
        return abs(dx) >= abs(dy) ? .time : .value
    }

    /// `applyAxisLock`: a time lock keeps the original value, a value lock keeps
    /// the original tick.
    public func applied(original: AutomationLanePoint, to current: AutomationLanePoint)
        -> AutomationLanePoint {
        switch self {
        case .none: return current
        case .time: return AutomationLanePoint(tick: current.tick, value: original.value)
        case .value: return AutomationLanePoint(tick: original.tick, value: current.value)
        }
    }
}

public enum AutomationPointRelease: Equatable, Sendable {
    case noOp
    case stationaryDelete
    case move
}

/// `PointDragGesture`: slop, activation and axis resolution for one pointer.
public struct AutomationPointDrag: Equatable, Sendable {
    public struct Update: Equatable, Sendable {
        public enum Phase: Equatable, Sendable { case pending, reset, dragging }

        public let phase: Phase
        public let effectiveX: Double
        public let effectiveY: Double
        public let axisLock: AutomationAxisLock

        public init(phase: Phase, effectiveX: Double, effectiveY: Double,
                    axisLock: AutomationAxisLock) {
            self.phase = phase
            self.effectiveX = effectiveX
            self.effectiveY = effectiveY
            self.axisLock = axisLock
        }
    }

    public let pressX: Double
    public let pressY: Double
    public let deleteOnStationary: Bool
    public private(set) var exceeded = false
    public private(set) var axisLock: AutomationAxisLock = .none
    private var slopOriginX: Double
    private var slopOriginY: Double

    public init(pressX: Double, pressY: Double, deleteOnStationary: Bool) {
        self.pressX = pressX
        self.pressY = pressY
        self.deleteOnStationary = deleteOnStationary
        slopOriginX = pressX
        slopOriginY = pressY
    }

    public mutating func update(x: Double, y: Double, shiftHeld: Bool,
                                activationDistance: Double) -> Update {
        guard exceeded else {
            let travel = abs(x - pressX) + abs(y - pressY)
            guard travel >= activationDistance else {
                return Update(phase: .pending, effectiveX: pressX, effectiveY: pressY,
                              axisLock: .none)
            }
            exceeded = true
            slopOriginX = x
            slopOriginY = y
            return Update(phase: .reset, effectiveX: pressX, effectiveY: pressY, axisLock: .none)
        }
        axisLock = AutomationAxisLock.resolve(
            current: axisLock, shiftHeld: shiftHeld, originX: pressX, originY: pressY,
            x: x, y: y, activationDistance: activationDistance)
        if shiftHeld, axisLock == .none {
            return Update(phase: .reset, effectiveX: pressX, effectiveY: pressY, axisLock: .none)
        }
        return Update(phase: .dragging, effectiveX: pressX + x - slopOriginX,
                      effectiveY: pressY + y - slopOriginY, axisLock: axisLock)
    }

    public func release() -> AutomationPointRelease {
        guard exceeded else { return deleteOnStationary ? .stationaryDelete : .noOp }
        return .move
    }
}

// MARK: - Frozen inputs

/// Everything an interaction freezes at begin: the document revision, the
/// parameter and its metadata, the selected track, the shared camera, the
/// explicit selection, the modifier policy, and every occupant of the lane.
/// Collision occupants are the frozen snapshot's own points, so they cannot
/// drift while a preview runs.
public struct AutomationFrozenFacts: Equatable, Sendable {
    public let revision: UInt64
    public let parameter: AutomationParameter
    public let metadata: AutomationParameterMetadata
    public let songEndTick: Tick
    public let camera: EditorCamera.Snapshot
    public let selection: AutomationTimeSelection?
    public let modifiers: AutomationModifiers
    public let snapshot: AutomationLaneSnapshot

    public init(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot,
                camera: EditorCamera.Snapshot, selection: AutomationTimeSelection?,
                modifiers: AutomationModifiers, songEndTick: Tick) {
        self.revision = snapshot.revision
        self.parameter = parameter
        self.metadata = snapshot.metadata
        self.songEndTick = songEndTick
        self.camera = camera
        self.selection = selection
        self.modifiers = modifiers
        self.snapshot = snapshot
    }

    /// The lane's displayed points at begin: tick-deduped, with the projected
    /// tick-zero node and without the lead-in.
    public var displayPoints: [AutomationLanePoint] {
        snapshot.displaySeries.map { AutomationLanePoint(tick: $0.tick, value: $0.value) }
    }

    /// The lane's written points alone: the projected engine node is not one.
    public var writtenPoints: [AutomationLanePoint] {
        snapshot.displaySeries.filter { !$0.projected }
            .map { AutomationLanePoint(tick: $0.tick, value: $0.value) }
    }

    public func occupants(at tick: Tick) -> [AutomationSourcePoint] {
        snapshot.occurrences(at: tick)
    }

    public var occupiedTicks: Set<Tick> { snapshot.occupiedTicks }

    /// The lane a replacement is computed against, optionally with the pencil's
    /// lead-in inserted as the pre-roll held value.
    public func freeze(includingLeadIn: Bool = false) -> AutomationLaneFreeze {
        var original = displayPoints
        if includingLeadIn, let leadIn = snapshot.leadInValue {
            original.insert(AutomationLanePoint(tick: 0, value: metadata.clamp(leadIn)), at: 0)
        }
        return AutomationLaneFreeze(parameter: parameter, revision: revision,
                                    metadata: metadata, songEndTick: songEndTick,
                                    original: original)
    }
}

/// The lane one replacement is computed against: canonical displayed points and
/// the revision they were read at.
public struct AutomationLaneFreeze: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let revision: UInt64
    public let metadata: AutomationParameterMetadata
    public let songEndTick: Tick
    public let original: [AutomationLanePoint]

    public init(parameter: AutomationParameter, revision: UInt64,
                metadata: AutomationParameterMetadata, songEndTick: Tick,
                original: [AutomationLanePoint]) {
        self.parameter = parameter
        self.revision = revision
        self.metadata = metadata
        self.songEndTick = songEndTick
        self.original = original
    }
}

// MARK: - Lane replacement

/// One complete span replacement: the replacement points a lane write will
/// store, and whether they already match the frozen lane.
public struct AutomationLaneEdit: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let revision: UInt64
    public let tickBegin: Tick
    public let tickEnd: Tick
    public let points: [AutomationLanePoint]
    public let unchanged: Bool
}

/// `NodeLaneEdit`: canonicalization, held-value lookup and range comparison.
public enum AutomationLaneReplacement {
    /// Sort by tick, keep the last at each tick, drop anything outside
    /// `[begin, end]`, clamp into the parameter's domain, and drop runs that
    /// repeat the value already in effect.
    public static func canonical(_ points: [AutomationLanePoint], begin: Tick, end: Tick,
                                 minimum: Int, maximum: Int,
                                 priorValue: Int?) -> [AutomationLanePoint] {
        let ordered = points.enumerated().sorted(by: {
            $0.element.tick == $1.element.tick ? $0.offset < $1.offset
                                               : $0.element.tick < $1.element.tick
        }).map(\.element)
        var result: [AutomationLanePoint] = []
        var prior = priorValue
        var index = 0
        while index < ordered.count {
            // Same-tick occupants collapse: the last one at the tick wins.
            var point = ordered[index]
            index += 1
            while index < ordered.count, ordered[index].tick == point.tick {
                point = ordered[index]
                index += 1
            }
            if point.tick < begin || point.tick > end { continue }
            let value = min(max(point.value, minimum), maximum)
            if prior == value { continue }
            result.append(AutomationLanePoint(tick: point.tick, value: value))
            prior = value
        }
        return result
    }

    /// `heldValue`: the value in effect at `tick`, or at the last point before
    /// it when `inclusive` is false.
    public static func held(_ points: [AutomationLanePoint], at tick: Tick,
                            inclusive: Bool) -> Int? {
        var held: Int?
        for point in points {
            if point.tick < tick || (inclusive && point.tick == tick) { held = point.value }
            if point.tick > tick { break }
        }
        return held
    }

    /// `rangeMatches`: do the original points inside `[begin, end]` already equal
    /// the replacement, tick for tick and value for value?
    public static func matches(_ original: [AutomationLanePoint], begin: Tick, end: Tick,
                               replacement: [AutomationLanePoint]) -> Bool {
        original.filter { $0.tick >= begin && $0.tick <= end } == replacement
    }

    /// `replacePointRange`: the replacement stands as given.
    public static func pointRange(_ freeze: AutomationLaneFreeze, begin: Tick, end: Tick,
                                 points: [AutomationLanePoint]) -> AutomationLaneEdit {
        AutomationLaneEdit(parameter: freeze.parameter, revision: freeze.revision,
                           tickBegin: begin, tickEnd: end, points: points,
                           unchanged: matches(freeze.original, begin: begin, end: end,
                                              replacement: points))
    }

    /// `replaceHeldSpan`: a lane that keeps its value past the stroke re-anchors
    /// the original held value one grid step after the release, so drawing 25
    /// over a flat 85 lane leaves the tail at 85.
    public static func heldSpan(_ freeze: AutomationLaneFreeze, begin: Tick, end: Tick,
                                points: [AutomationLanePoint]) -> AutomationLaneEdit {
        var replacement = points
        if end < freeze.songEndTick, let endpoint = held(freeze.original, at: end, inclusive: true) {
            replacement.append(AutomationLanePoint(tick: end, value: endpoint))
        }
        let canonical = canonical(replacement, begin: begin, end: end,
                                  minimum: freeze.metadata.minimum,
                                  maximum: freeze.metadata.maximum,
                                  priorValue: held(freeze.original, at: begin, inclusive: false))
        return AutomationLaneEdit(parameter: freeze.parameter, revision: freeze.revision,
                                  tickBegin: begin, tickEnd: end, points: canonical,
                                  unchanged: matches(freeze.original, begin: begin, end: end,
                                                     replacement: canonical))
    }
}

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
                                     plotHeight: Double) -> Double {
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
        let span = Double(facts.metadata.maximum - facts.metadata.minimum)
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

// MARK: - Node drag

/// One frozen drag participant: its document occurrence, the value range it
/// clamps into, and the destination its preview publishes.
public struct AutomationNodeDragTarget: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let source: AutomationSourcePoint
    public let minimum: Int
    public let maximum: Int
    public var current: AutomationLanePoint

    public init(parameter: AutomationParameter, source: AutomationSourcePoint,
                minimum: Int, maximum: Int) {
        self.parameter = parameter
        self.source = source
        self.minimum = minimum
        self.maximum = maximum
        current = AutomationLanePoint(tick: source.tick, value: source.value)
    }

    public var original: AutomationLanePoint {
        AutomationLanePoint(tick: source.tick, value: source.value)
    }
}

public struct AutomationNodeDragFinish: Equatable, Sendable {
    public let release: AutomationPointRelease
    public let changed: Bool
    public let dTick: Int64
    public let selectionDrag: Bool
}

/// `NodeDragGesture`: one grabbed node, or a whole selected set moved by one
/// shared delta that clamps at tick zero so the group keeps its spacing.
public struct AutomationNodeDragTransaction: Sendable {
    public let facts: AutomationFrozenFacts
    public private(set) var targets: [AutomationNodeDragTarget]
    public let grabbedPoint: Int
    public let selectionDrag: Bool
    public var drag: AutomationPointDrag

    public init(facts: AutomationFrozenFacts, targets: [AutomationNodeDragTarget],
                grabbedPoint: Int, selectionDrag: Bool, press: (x: Double, y: Double),
                deleteOnStationary: Bool) {
        self.facts = facts
        self.targets = targets
        self.grabbedPoint = targets.indices.contains(grabbedPoint) ? grabbedPoint : 0
        self.selectionDrag = selectionDrag
        drag = AutomationPointDrag(pressX: press.x, pressY: press.y,
                                   deleteOnStationary: deleteOnStationary)
    }

    /// One grabbed node with nothing selected behind it.
    public static func single(facts: AutomationFrozenFacts, source: AutomationSourcePoint,
                              press: (x: Double, y: Double),
                              deleteOnStationary: Bool) -> AutomationNodeDragTransaction {
        AutomationNodeDragTransaction(
            facts: facts,
            targets: [AutomationNodeDragTarget(parameter: facts.parameter, source: source,
                                               minimum: facts.metadata.minimum,
                                               maximum: facts.metadata.maximum)],
            grabbedPoint: 0, selectionDrag: false, press: press,
            deleteOnStationary: deleteOnStationary)
    }

    /// `collectSelectedNodeDrags`: every point of the covered parameters inside
    /// the frozen selection joins the shared delta, in catalog order.
    public static func selection(facts: AutomationFrozenFacts,
                                 lanes: [(parameter: AutomationParameter,
                                          snapshot: AutomationLaneSnapshot)],
                                 grabbed: (parameter: AutomationParameter,
                                           source: AutomationSourcePoint),
                                 range: TimeRange, press: (x: Double, y: Double),
                                 deleteOnStationary: Bool) -> AutomationNodeDragTransaction? {
        var targets: [AutomationNodeDragTarget] = []
        var grabbedPoint: Int?
        for lane in lanes {
            let metadata = AutomationParameterMetadata(parameter: lane.parameter)
            for source in lane.snapshot.sources where range.contains(source.tick) {
                if lane.parameter == grabbed.parameter, source.tick == grabbed.source.tick,
                   source.identity == grabbed.source.identity {
                    grabbedPoint = targets.count
                }
                targets.append(AutomationNodeDragTarget(parameter: lane.parameter, source: source,
                                                        minimum: metadata.minimum,
                                                        maximum: metadata.maximum))
            }
        }
        guard let grabbedPoint, !targets.isEmpty else { return nil }
        return AutomationNodeDragTransaction(facts: facts, targets: targets,
                                             grabbedPoint: grabbedPoint, selectionDrag: true,
                                             press: press, deleteOnStationary: deleteOnStationary)
    }

    public var grabbed: AutomationNodeDragTarget? {
        targets.indices.contains(grabbedPoint) ? targets[grabbedPoint] : nil
    }

    /// `NodeDragGesture::update`: a reset restores the grabbed node's source, a
    /// drag maps the pointer and applies the axis lock, and every participant
    /// follows the grabbed node's delta.
    public mutating func update(_ update: AutomationPointDrag.Update,
                                mapped: AutomationLanePoint) -> AutomationAxisLock {
        guard let grabbedTarget = grabbed, update.phase != .pending else { return .none }
        let current = update.phase == .reset
            ? grabbedTarget.original
            : update.axisLock.applied(original: grabbedTarget.original, to: mapped)
        applyDrag(grabCurrent: current)
        return update.axisLock
    }

    /// `NodeDragGesture::applyDrag`: one clamped common delta for the whole set.
    public mutating func applyDrag(grabCurrent: AutomationLanePoint) {
        guard let grabbedTarget = grabbed else { return }
        let requested = Int64(grabCurrent.tick) - Int64(grabbedTarget.original.tick)
        let earliest = targets.map(\.original.tick).min() ?? 0
        let dTick = max(requested, -Int64(earliest))
        let dValue = grabCurrent.value - grabbedTarget.original.value
        for index in targets.indices {
            targets[index].current = AutomationLanePoint(
                tick: TimeDefaults.shiftTickClamped(targets[index].original.tick, by: dTick),
                value: min(max(targets[index].original.value + dValue, targets[index].minimum),
                           targets[index].maximum))
        }
    }

    public func finish() -> AutomationNodeDragFinish {
        guard let grabbedTarget = grabbed else {
            return AutomationNodeDragFinish(release: .noOp, changed: false, dTick: 0,
                                            selectionDrag: selectionDrag)
        }
        return AutomationNodeDragFinish(
            release: drag.release(),
            changed: targets.contains { $0.current != $0.original },
            dTick: Int64(grabbedTarget.current.tick) - Int64(grabbedTarget.original.tick),
            selectionDrag: selectionDrag)
    }

    /// The moves a committed drag writes: every participant's source tick to its
    /// previewed destination.
    public var moves: [AutomationNodeMove] {
        targets.map {
            AutomationNodeMove(parameter: $0.parameter, sourceTick: $0.source.tick,
                               tick: $0.current.tick, value: $0.current.value)
        }
    }

    public var deleteTicks: [Tick] { grabbed.map { [$0.source.tick] } ?? [] }
}

/// `PhantomGesture`: the projected node at the plot origin, which only ever
/// moves in value and never in time.
public struct AutomationPhantomDragTransaction: Sendable {
    public let facts: AutomationFrozenFacts
    public private(set) var target: AutomationNodeDragTarget
    public var drag: AutomationPointDrag

    public init(facts: AutomationFrozenFacts, source: AutomationSourcePoint,
                press: (x: Double, y: Double)) {
        self.facts = facts
        target = AutomationNodeDragTarget(parameter: facts.parameter, source: source,
                                          minimum: facts.metadata.minimum,
                                          maximum: facts.metadata.maximum)
        drag = AutomationPointDrag(pressX: press.x, pressY: press.y, deleteOnStationary: false)
    }

    /// A reset restores the source value; a drag clamps the mapped value at the
    /// original tick. The axis is always the value axis.
    public mutating func update(_ update: AutomationPointDrag.Update,
                                mappedValue: Int) -> AutomationAxisLock {
        guard update.phase != .pending else { return .none }
        target.current = update.phase == .dragging
            ? AutomationLanePoint(tick: target.original.tick,
                                  value: min(max(mappedValue, target.minimum), target.maximum))
            : target.original
        return .value
    }

    /// `PhantomGesture::finish`: a stroke that never moved is no edit.
    public func finish() -> AutomationNodeDragTarget? {
        guard drag.release() == .move, target.current.value != target.original.value else {
            return nil
        }
        return target
    }

    public var move: AutomationNodeMove? {
        guard let target = finish() else { return nil }
        return AutomationNodeMove(parameter: target.parameter, sourceTick: target.source.tick,
                                  tick: target.original.tick, value: target.current.value)
    }
}

// MARK: - Value prompt

/// `PendingValuePrompt`: one frozen inline value edit. Opening it writes
/// nothing; acceptance revalidates the frozen revision and either rewrites the
/// node it captured or inserts at the empty tick it captured.
public struct AutomationPromptTransaction: Equatable, Sendable {
    public let facts: AutomationFrozenFacts
    public let anchor: AutomationLanePoint
    public let source: AutomationSourcePoint?
    public let forExistingNode: Bool
    public let prompt: AutomationValuePrompt

    public init?(facts: AutomationFrozenFacts, anchor: AutomationLanePoint,
                source: AutomationSourcePoint?, forExistingNode: Bool,
                metadata: AutomationParameterMetadata) {
        guard anchor.tick <= facts.songEndTick else { return nil }
        self.facts = facts
        self.anchor = anchor
        self.source = source
        self.forExistingNode = forExistingNode
        prompt = metadata.prompt(storedValue: anchor.value)
    }

    public func storedValue(displayed: Int) -> Int {
        facts.metadata.storedValue(prompted: min(max(displayed, prompt.minimum), prompt.maximum))
    }

    /// What accepting a displayed value does: nothing, a same-tick value write
    /// for the node the prompt captured, or an insertion at the empty tick it
    /// captured. An accepted value the lane already holds changes nothing.
    public func outcome(displayed: Int) -> AutomationPromptOutcome {
        let stored = storedValue(displayed: displayed)
        if forExistingNode {
            guard stored != anchor.value else { return .none }
            return .move(AutomationNodeMove(parameter: facts.parameter, sourceTick: anchor.tick,
                                            tick: anchor.tick, value: stored))
        }
        let duplicate = facts.snapshot.occurrences(at: anchor.tick)
            .contains { $0.value == stored }
        guard !duplicate else { return .none }
        return .insert(AutomationLaneReplacement.pointRange(
            facts.freeze(), begin: anchor.tick, end: anchor.tick,
            points: [AutomationLanePoint(tick: anchor.tick, value: stored)]))
    }
}

/// The three semantic outcomes an accepted value prompt can have.
public enum AutomationPromptOutcome: Equatable, Sendable {
    case none
    case move(AutomationNodeMove)
    case insert(AutomationLaneEdit)
}

// MARK: - Resolved plans

/// The document identity of one lane occurrence, which is what a removal set
/// deduplicates by.
private struct AutomationLanePointKey: Hashable {
    let chunk: Int
    let eventIndex: Int

    init(_ point: LanePoint) {
        chunk = point.chunk
        eventIndex = point.eventIndex
    }
}

/// One resolved node move: a source tick to its destination tick and value.
public struct AutomationNodeMove: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let sourceTick: Tick
    public let tick: Tick
    public let value: Int

    public init(parameter: AutomationParameter, sourceTick: Tick, tick: Tick, value: Int) {
        self.parameter = parameter
        self.sourceTick = sourceTick
        self.tick = tick
        self.value = value
    }
}

/// The points one parameter's lane receives as a single write.
public struct AutomationLaneSpanWrite: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let points: [AutomationLanePoint]

    public init(parameter: AutomationParameter, points: [AutomationLanePoint]) {
        self.parameter = parameter
        self.points = points
    }
}

/// One resolved multi-lane edit: removals, per-lane writes and tempo changes
/// that commit as a single `RangeEdit`, so one user action is one history entry.
public struct AutomationDocumentPlan: Equatable, Sendable {
    public let revision: UInt64
    public var removePoints: [LanePoint] = []
    public var writes: [AutomationLaneSpanWrite] = []
    public var removeTempo: [TempoPoint] = []
    public var addTempo: [TempoPoint] = []

    public init(revision: UInt64) {
        self.revision = revision
    }

    public var isEmpty: Bool {
        removePoints.isEmpty && writes.isEmpty && removeTempo.isEmpty && addTempo.isEmpty
    }
}

/// `resolveCcMoves`, `resolveTempoMoves` and `resolveBatchDeletes`: the frozen
/// occurrences a finished interaction writes, resolved by identity at the frozen
/// revision. A source tick that no longer holds an occurrence resolves to `nil`,
/// so a stale target writes nothing instead of retargeting another node.
public enum AutomationNodeResolver {
    public struct LaneMoves: Sendable {
        public let facts: AutomationFrozenFacts
        public let moves: [AutomationNodeMove]

        public init(_ facts: AutomationFrozenFacts, _ moves: [AutomationNodeMove]) {
            self.facts = facts
            self.moves = moves
        }
    }

    public struct LaneDeletes: Sendable {
        public let parameter: AutomationParameter
        public let snapshot: AutomationLaneSnapshot
        public let ticks: [Tick]

        public init(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot,
                    ticks: [Tick]) {
            self.parameter = parameter
            self.snapshot = snapshot
            self.ticks = ticks
        }
    }

    public static func moves(_ requests: [LaneMoves]) -> AutomationDocumentPlan? {
        guard let revision = requests.first?.facts.revision else { return nil }
        var plan = AutomationDocumentPlan(revision: revision)
        var removals: [AutomationLanePointKey: LanePoint] = [:]
        for request in requests {
            let moved = request.facts.parameter.isTempo
                ? tempoMoves(request, plan: &plan)
                : laneMoves(request, plan: &plan, removals: &removals)
            guard moved else { return nil }
        }
        plan.removePoints = removals.values.sorted {
            ($0.chunk, $0.eventIndex) < ($1.chunk, $1.eventIndex)
        }
        return plan
    }

    public static func deletions(revision: UInt64,
                                 _ requests: [LaneDeletes]) -> AutomationDocumentPlan? {
        var plan = AutomationDocumentPlan(revision: revision)
        var removals: [AutomationLanePointKey: LanePoint] = [:]
        for request in requests {
            var seen = Set<Tick>()
            for tick in request.ticks where seen.insert(tick).inserted {
                if request.parameter.isTempo {
                    guard let point = request.snapshot.sources
                        .first(where: { $0.tick == tick })?.tempoPoint else { return nil }
                    plan.removeTempo.append(point)
                    continue
                }
                let group = request.snapshot.occurrences(at: tick)
                if group.isEmpty {
                    // The projected engine node is deletable and removes nothing.
                    guard tick == 0, request.snapshot.projectedTickZero else { return nil }
                    continue
                }
                for source in group {
                    if let point = source.lanePoint { removals[AutomationLanePointKey(point)] = point }
                }
            }
        }
        plan.removePoints = removals.values.sorted {
            ($0.chunk, $0.eventIndex) < ($1.chunk, $1.eventIndex)
        }
        return plan
    }

    /// `lastMovesBySourceTick`: only the last move naming a source tick counts.
    private static func lastBySourceTick(_ moves: [AutomationNodeMove]) -> [AutomationNodeMove] {
        var lastIndex: [Tick: Int] = [:]
        for (index, move) in moves.enumerated() { lastIndex[move.sourceTick] = index }
        return moves.enumerated().filter { lastIndex[$0.element.sourceTick] == $0.offset }
            .map(\.element)
    }

    private static func laneMoves(_ request: LaneMoves, plan: inout AutomationDocumentPlan,
                                  removals: inout [AutomationLanePointKey: LanePoint]) -> Bool {
        let facts = request.facts
        guard facts.parameter.lane != nil else { return false }
        let parameter = facts.parameter
        var requests: [(destination: Tick, value: Int, source: AutomationSourcePoint?)] = []
        for move in lastBySourceTick(request.moves) {
            let group = facts.occupants(at: move.sourceTick)
            if group.isEmpty {
                // A projected tick-zero node is promoted into a written event.
                guard move.sourceTick == 0, facts.snapshot.projectedTickZero else { return false }
                requests.append((move.tick, facts.metadata.clamp(move.value), nil))
                continue
            }
            let newValue = facts.metadata.clamp(move.value)
            for (index, source) in group.enumerated() {
                let value = index + 1 == group.count ? newValue : source.value
                requests.append((move.tick, value, source))
            }
        }
        var winningSource: [Tick: Tick] = [:]
        for request in requests { winningSource[request.destination] = request.source?.tick ?? 0 }
        var written: [AutomationLanePoint] = []
        for request in requests {
            let isWinner = winningSource[request.destination] == (request.source?.tick ?? 0)
            guard isWinner else {
                if let point = request.source?.lanePoint { removals[AutomationLanePointKey(point)] = point }
                continue
            }
            if let source = request.source, let point = source.lanePoint {
                if request.destination == source.tick, request.value == source.value { continue }
                removals[AutomationLanePointKey(point)] = point
            }
            written.append(AutomationLanePoint(tick: request.destination, value: request.value))
        }
        // An occupant of a destination the drag moved onto is evicted.
        for (destination, source) in winningSource {
            for occupant in facts.occupants(at: destination) where occupant.tick != source {
                if let point = occupant.lanePoint {
                    removals[AutomationLanePointKey(point)] = point
                }
            }
        }
        guard !written.isEmpty else { return true }
        AutomationSweepTransaction.upsertAll(&written)
        plan.writes.append(AutomationLaneSpanWrite(parameter: parameter, points: written))
        return true
    }

    private static func tempoMoves(_ request: LaneMoves,
                                   plan: inout AutomationDocumentPlan) -> Bool {
        let facts = request.facts
        let frozen = facts.snapshot.sources.compactMap(\.tempoPoint)
        var removals: [Tick: TempoPoint] = [:]
        var additions: [Tick: TempoPoint] = [:]
        for move in lastBySourceTick(request.moves) {
            guard let source = frozen.first(where: { $0.tick == move.sourceTick }) else {
                return false
            }
            let bpm = Int(TimeDefaults.tempoBPM(
                forMicrosecondsPerQuarterNote: source.microsecondsPerQuarterNote).rounded())
            var destination = TempoPoint(tick: move.tick,
                                         microsecondsPerQuarterNote: source.microsecondsPerQuarterNote)
            if move.value != bpm {
                destination.microsecondsPerQuarterNote =
                    TimeDefaults.microsecondsPerQuarterNote(forBPM: move.value)
            }
            guard destination != source else { continue }
            removals[source.tick] = source
            additions[destination.tick] = destination
        }
        for (tick, addition) in additions.sorted(by: { $0.key < $1.key }) {
            if let occupant = frozen.first(where: { $0.tick == tick }) {
                removals[occupant.tick] = occupant
            }
            plan.addTempo.append(addition)
        }
        plan.removeTempo.append(contentsOf: removals.values.sorted { $0.tick < $1.tick })
        return true
    }
}

// MARK: - Range edits and clipboard

/// The frozen range edit the Automation lane menu and time-selection commands
/// perform: a whole-lane replacement, a clear, or a delete across the parameters
/// the explicit selection covers.
public enum AutomationRangeEditor {
    /// One lane's whole-lane replacement: the lane menu's Paste (replace) and
    /// Clear. It compares against the lane's written points, so a lane holding
    /// only a projected engine node is already empty.
    public static func replaceLane(_ facts: AutomationFrozenFacts,
                                   points: [AutomationLanePoint]) -> AutomationLaneEdit {
        let written = AutomationLaneFreeze(
            parameter: facts.parameter, revision: facts.revision, metadata: facts.metadata,
            songEndTick: facts.songEndTick, original: facts.writtenPoints)
        let clamped = AutomationLaneReplacement.canonical(
            points, begin: 0, end: TimeDefaults.noTick, minimum: facts.metadata.minimum,
            maximum: facts.metadata.maximum, priorValue: nil)
        return AutomationLaneReplacement.pointRange(written, begin: 0, end: TimeDefaults.noTick,
                                                    points: clamped)
    }

    /// Delete every covered occurrence inside the range: points by tick group and
    /// tempo points by tick, as one plan.
    public static func deletion(range: TimeRange,
                                lanes: [(parameter: AutomationParameter,
                                         snapshot: AutomationLaneSnapshot)]) -> AutomationDocumentPlan? {
        guard !range.isEmpty, !lanes.isEmpty,
              let revision = lanes.first?.snapshot.revision else { return nil }
        var requests: [AutomationNodeResolver.LaneDeletes] = []
        for lane in lanes {
            let ticks = Set(lane.snapshot.sources.map(\.tick)).filter { range.contains($0) }
            guard !ticks.isEmpty else { continue }
            requests.append(AutomationNodeResolver.LaneDeletes(
                parameter: lane.parameter, snapshot: lane.snapshot, ticks: ticks.sorted()))
        }
        guard !requests.isEmpty else { return nil }
        return AutomationNodeResolver.deletions(revision: revision, requests)
    }
}

/// The page's in-process semantic clipboard: the existing Swift `PorydawClip`
/// payload, never the native pasteboard. The four native MIME clipboard gaps
/// stay separately named until their own capability exists.
public struct AutomationClipboardTransaction: Equatable, Sendable {
    public private(set) var clip: PorydawClip?

    public init() {}

    @MainActor
    public mutating func copy(range: TimeRange, scope: TimeScope, from document: SongDocument,
                              unterminatedDuration: Tick) -> Bool {
        guard let extracted = ClipboardSemantics.extractTimeRange(
            range, scope: scope, from: document,
            unterminatedDuration: unterminatedDuration) else { return false }
        clip = extracted
        return true
    }

    /// Copy, then delete: the cut's deletion is the only document write.
    @MainActor
    public mutating func cut(range: TimeRange, scope: TimeScope, from document: SongDocument,
                             unterminatedDuration: Tick) -> Bool {
        guard copy(range: range, scope: scope, from: document,
                   unterminatedDuration: unterminatedDuration) else { return false }
        return ClipboardSemantics.deleteTimeRange(range, scope: scope, from: document)
    }

    @MainActor
    public func paste(at cursor: Tick, selectedTrack: Int,
                      into document: SongDocument) -> Tick? {
        guard let clip else { return nil }
        return ClipboardSemantics.paste(clip, at: cursor, selectedTrack: selectedTrack,
                                        into: document)?.nextCursor
    }

    public mutating func clear() { clip = nil }
}

// MARK: - Commit policy

/// The single commit chokepoint. Every route revalidates the frozen revision and
/// then calls exactly one existing `SongDocument` semantic operation; a stale
/// revision, an unchanged edit or an empty plan writes nothing.
@MainActor
public enum AutomationCommit {
    /// A held-span replacement: one `writeLane`/`editTempo` call.
    @discardableResult
    public static func apply(_ edit: AutomationLaneEdit, in document: SongDocument) -> Bool {
        guard document.revision == edit.revision, !edit.unchanged else { return false }
        let before = document.revision
        switch edit.parameter {
        case .tempo:
            document.editTempo(TempoEdit(
                remove: document.state.tempo.filter {
                    $0.tick >= edit.tickBegin && $0.tick <= edit.tickEnd
                },
                add: edit.points.map {
                    TempoPoint(tick: $0.tick,
                               microsecondsPerQuarterNote:
                                   TimeDefaults.microsecondsPerQuarterNote(forBPM: $0.value))
                }))
        case let .controlChange(track, controller):
            document.writeLane(track: track, lane: .controller(controller),
                               from: edit.tickBegin, through: edit.tickEnd,
                               points: edit.points.map { LaneWrite(tick: $0.tick, value: $0.value) })
        case let .pitchBend(track):
            document.writeLane(track: track, lane: .pitchBend,
                               from: edit.tickBegin, through: edit.tickEnd,
                               points: edit.points.map { LaneWrite(tick: $0.tick, value: $0.value) })
        }
        return document.revision != before
    }

    /// A resolved multi-lane plan: one `applyRangeEdit`.
    @discardableResult
    public static func apply(_ plan: AutomationDocumentPlan, in document: SongDocument) -> Bool {
        guard document.revision == plan.revision, !plan.isEmpty else { return false }
        let insertions = plan.writes.compactMap { write -> RangeEdit.LaneInsertion? in
            guard let track = write.parameter.track, let lane = write.parameter.lane else {
                return nil
            }
            return RangeEdit.LaneInsertion(
                track: track, lane: lane,
                points: write.points.map { LaneWrite(tick: $0.tick, value: $0.value) })
        }
        return document.applyRangeEdit(RangeEdit(
            removePoints: plan.removePoints, addPoints: insertions,
            removeTempo: plan.removeTempo, addTempo: plan.addTempo))
    }
}
