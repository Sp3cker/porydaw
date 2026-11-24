import Foundation
import PorydawCore
import PorydawDocument

// Coordinate mapping and identity facts for automation input.

/// Where a pointer event landed in the page body: the selector tabs own the
/// gutter column, the plot owns editing. Mirrors the production
/// `TimelineInputSurface` split and the sibling pages' own surface enums.
public enum AutomationInputSurface: Int, Sendable {
    case tabs = 0
    case plot = 1
}

/// Qt keyboard modifier bits as QML carries them (`mouse.modifiers`).
public enum AutomationQtModifier {
    public static let shift = 0x0200_0000
    public static let control = 0x0400_0000
    public static let alt = 0x0800_0000
    public static let meta = 0x1000_0000
    public static let shortcutMask = shift | control | alt | meta

    /// `NodeLane`'s own mapping: Alt is the fine (clock) lattice, Control is the
    /// value snap, Shift selects the ramp/locking behaviour. Direct checks drive
    /// this mapping with the raw Qt bits QML carries.
    public static func automation(_ flags: Int) -> AutomationModifiers {
        AutomationModifiers(
            fine: flags & alt != 0, snapValue: flags & control != 0,
            shift: flags & shift != 0)
    }
}

/// The cursor the plot publishes (`Qt::CursorShape` ordinals), exactly the set
/// the production band claims: an idle arrow, the pencil tool, the two axis-lock
/// arrows and the closed hand of a pan.
public enum AutomationCursorKind: Int, Sendable {
    case arrow = 0
    case pencil = 1
    case sizeVertical = 2
    case sizeHorizontal = 3
    case closedHand = 4
}

enum AutomationHoverHintTarget: Equatable, Sendable {
    case background
    case node
    case originPhantom
}

/// One hover over the plot: the node under the pointer, its projected origin
/// phantom, or the background tick with the value the lane holds there.
public struct AutomationHover: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let tick: Tick
    public let value: Int?
    public let text: String
    public let hasPoint: Bool
    let hintTarget: AutomationHoverHintTarget
    let nodeMarkersVisible: Bool

    static func resolve(
        x: Double,
        y: Double,
        facts: AutomationFrozenFacts,
        lane: AutomationLaneProjection,
        projection: AutomationProjection,
        pointHitRadius: Double,
        isPencilMode: Bool
    ) -> Self {
        let markersVisible = projection.markersVisible()
        if !isPencilMode || markersVisible {
            let node = lane.hitTest(x: x, y: y, radius: pointHitRadius)
            if let hit = node ?? lane.hitTestOriginPhantom(x: x, y: y, radius: pointHitRadius) {
                return Self(
                    parameter: facts.parameter,
                    tick: hit.tick,
                    value: hit.displayValue,
                    text: facts.snapshot.valueText(hit.value, at: hit.tick),
                    hasPoint: true,
                    hintTarget: node == nil ? .originPhantom : .node,
                    nodeMarkersVisible: markersVisible)
            }
        }
        // The background tick is the fine lattice, or the insert cell while
        // the pencil is armed; the readout is the value the lane holds there.
        let tick =
            isPencilMode
            ? projection.cell(atRawTick: projection.rawTick(atX: x)).tickBegin
            : projection.tick(atX: x, fine: true)
        let rawHeld =
            isPencilMode
            ? projection.value(atY: y, metadata: facts.metadata)
            : lane.heldValue(at: tick)
        let held = rawHeld.map { facts.snapshot.editedValue($0, at: tick) }
        return Self(
            parameter: facts.parameter,
            tick: tick,
            value: held,
            text: held.map { facts.snapshot.valueText($0, at: tick) } ?? "",
            hasPoint: false,
            hintTarget: .background,
            nodeMarkersVisible: markersVisible)
    }

    static func hintTarget(
        x: Double,
        y: Double,
        lane: AutomationLaneProjection,
        pointHitRadius: Double
    ) -> AutomationHoverHintTarget {
        if lane.hitTest(x: x, y: y, radius: pointHitRadius) != nil {
            return .node
        }
        if lane.hitTestOriginPhantom(x: x, y: y, radius: pointHitRadius) != nil {
            return .originPhantom
        }
        return .background
    }
}

enum AutomationGesture {
    case pencil(AutomationPencilTransaction)
    case sweep(AutomationSweepTransaction)
    case node(AutomationNodeDragTransaction)
    case phantom(AutomationPhantomDragTransaction)
}

/// The range press: production's band. It freezes the revision and the
/// parameter it started on, and its release publishes one time selection or
/// opens the captured menu — never a retarget.
struct AutomationRangeBand {
    let revision: UInt64
    let parameter: AutomationParameter
    let anchorTick: Tick
    var currentTick: Tick
    let pressX: Double
    let pressY: Double
    var active = false
    /// The press landed inside the explicit selection that was active then.
    let insideSelection: Bool
}

@MainActor
extension AutomationPage {
    /// The pointer's hover: the node under it, or the background tick with the
    /// value the lane holds there.
    func updateHover(
        x: Double, y: Double, facts: AutomationFrozenFacts,
        projection: AutomationProjection
    ) {
        guard let lane = laneProjection(facts: facts, projection: projection) else { return }
        let next = AutomationHover.resolve(
            x: x,
            y: y,
            facts: facts,
            lane: lane,
            projection: projection,
            pointHitRadius: geometry.pointHitRadius,
            isPencilMode: isPencilMode)
        guard applyHover(next, countingPublication: true) else { return }
        publishHover()
    }

    func mappedPoint(
        x: Double, y: Double, facts: AutomationFrozenFacts,
        modifiers: AutomationModifiers,
        projection: AutomationProjection
    ) -> AutomationLanePoint {
        let tick = projection.tick(atX: x, fine: modifiers.fine)
        return AutomationLanePoint(
            tick: tick,
            value: facts.snapshot.editedValue(
                facts.metadata.snappedValue(
                    projection.value(atY: y, metadata: facts.metadata),
                    snapValue: modifiers.snapValue,
                    plotHeight: plotHeight, neutralSnapRadius: geometry.neutralSnapRadius),
                at: tick))
    }

    func snapped(tickAtX x: Double, modifiers: Int) -> Tick {
        guard let facts = frozenFacts(modifiers: .init()) else { return 0 }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        return projection.tick(atX: x, fine: modifiers & AutomationQtModifier.alt != 0)
    }

}

func source(
    of identity: AutomationPointIdentity,
    facts: AutomationFrozenFacts
) -> AutomationSourcePoint? {
    if let source = facts.snapshot.sources.first(where: { $0.identity == identity }) {
        return source
    }
    // The projected engine node has no written occurrence: a drag on it is the
    // promotion write the resolver performs for a projected tick-zero node.
    guard identity.occurrence == -1, identity.tick == 0,
        facts.snapshot.projectedTickZero
    else { return nil }
    return AutomationSourcePoint(
        identity: identity, tick: identity.tick, value: identity.value,
        lanePoint: nil, tempoPoint: nil)
}

func shiftedAutomationSelection(
    _ selection: AutomationTimeSelection?,
    by delta: Int64
) -> AutomationTimeSelection? {
    guard var moved = selection else { return nil }
    let start = TimeDefaults.shiftTickClamped(moved.range.startTick, by: delta)
    let end = TimeDefaults.shiftTickClamped(moved.range.endTick, by: delta)
    guard end > start else { return nil }
    moved.range = TimeRange(startTick: start, endTick: end)
    return moved
}
