import Foundation
import PorydawCore

// Node-drag, projected-origin, and captured value-prompt transactions. They
// resolve frozen interaction state only; document mutation remains in AutomationCommit.

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
    public private(set) var laneFacts: [AutomationFrozenFacts]
    public private(set) var targets: [AutomationNodeDragTarget]
    public let grabbedPoint: Int
    public let selectionDrag: Bool
    public var drag: AutomationPointDrag

    public init(facts: AutomationFrozenFacts, targets: [AutomationNodeDragTarget],
                grabbedPoint: Int, selectionDrag: Bool, press: (x: Double, y: Double),
                deleteOnStationary: Bool) {
        self.facts = facts
        laneFacts = [facts]
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
        var transaction = AutomationNodeDragTransaction(facts: facts, targets: targets,
                                             grabbedPoint: grabbedPoint, selectionDrag: true,
                                             press: press, deleteOnStationary: deleteOnStationary)
        transaction.laneFacts = lanes.map {
            AutomationFrozenFacts(parameter: $0.parameter, snapshot: $0.snapshot,
                                  camera: facts.camera, selection: facts.selection,
                                  modifiers: facts.modifiers, songEndTick: facts.songEndTick)
        }
        return transaction
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
