import Foundation
import PorydawCore

// Shared frozen-input vocabulary for Automation interactions: modifier policy,
// pointer mechanics, revision-bound facts, and the canonical lane freeze passed
// to drawing, node, prompt, and edit resolvers. This file owns no document
// mutation or history.
//
// Behaviour follows `src/ui/editordrawer/nodelane/{gesture,pencilgesture,
// nodelane,batchcommit}.cpp` and the canvas interaction paths
// (`automationcanvas_gesture.cpp`, `automationcanvas_menu.cpp`,
// `automationcanvas_pointmenu.cpp`).

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
