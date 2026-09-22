import Foundation
import PorydawCore

/// The plot owns editing; the selector tabs own the gutter.
public enum AutomationInputSurface: Int, Sendable {
    case tabs = 0
    case plot = 1
}

/// Qt::CursorShape ordinals published by the plot.
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

public struct AutomationHover: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let tick: Tick
    public let value: Int?
    public let text: String
    public let hasPoint: Bool
    let hintTarget: AutomationHoverHintTarget
    let nodeMarkersVisible: Bool

    static func resolve(x: Double, y: Double, facts: AutomationFrozenFacts,
                        lane: AutomationLaneProjection, projection: AutomationProjection,
                        pointHitRadius: Double, isPencilMode: Bool) -> Self {
        let markersVisible = projection.markersVisible()
        var hintTarget = AutomationHoverHintTarget.background
        if !isPencilMode || markersVisible {
            if let hit = lane.hitTest(x: x, y: y, radius: pointHitRadius) {
                hintTarget = hit.x < 0 ? .originPhantom : .node
                return Self(parameter: facts.parameter, tick: hit.tick, value: hit.value,
                            text: facts.metadata.valueText(hit.value), hasPoint: true,
                            hintTarget: hintTarget, nodeMarkersVisible: markersVisible)
            }
            if let phantom = lane.originPhantom {
                let dy = phantom.point.y - y
                if x * x + dy * dy <= pointHitRadius * pointHitRadius {
                    hintTarget = .originPhantom
                }
            }
        }
        let tick = isPencilMode
            ? projection.cell(atRawTick: projection.rawTick(atX: x)).tickBegin
            : projection.tick(atX: x, fine: true)
        let held = isPencilMode ? projection.value(atY: y, metadata: facts.metadata)
            : lane.heldValue(at: tick)
        return Self(parameter: facts.parameter, tick: tick, value: held,
                    text: held.map(facts.metadata.valueText) ?? "", hasPoint: false,
                    hintTarget: hintTarget, nodeMarkersVisible: markersVisible)
    }

    static func hintTarget(x: Double, y: Double, lane: AutomationLaneProjection,
                           pointHitRadius: Double) -> AutomationHoverHintTarget {
        if let hit = lane.hitTest(x: x, y: y, radius: pointHitRadius) {
            return hit.x < 0 ? .originPhantom : .node
        }
        if let phantom = lane.originPhantom {
            let dy = phantom.point.y - y
            if x * x + dy * dy <= pointHitRadius * pointHitRadius { return .originPhantom }
        }
        return .background
    }
}

/// Resolves pointer input without reaching into a page, document, or Qt object.
enum AutomationInteraction {
    static func reduce(_ state: inout AutomationState, surface: AutomationInputSurface,
                       input: DrawerPointerInput,
                       context: AutomationPointerContext?) -> AutomationTransition {
        guard state.document.attached else { return AutomationTransition() }
        switch input.phase {
        case .press:
            return press(&state, surface: surface, input: input, context: context)
        case .move:
            return move(&state, input: input, context: context)
        case .release:
            return release(&state, input: input, context: context)
        case .leave:
            guard state.hover != nil else { return AutomationTransition() }
            state.hover = nil
            return AutomationTransition(publication: [.hover, .hoverHint], hoverBuild: true)
        }
    }

    private static func press(_ state: inout AutomationState, surface: AutomationInputSurface,
                              input: DrawerPointerInput,
                              context: AutomationPointerContext?) -> AutomationTransition {
        state.hover = nil
        guard surface == .plot, let context else {
            return AutomationTransition(publication: [.hover, .hoverHint])
        }
        let x = input.x
        let y = input.y
        state.hoverX = x
        var result = AutomationTransition(publication: [.hover, .hoverHint])
        if input.changedButton == .primary || input.changedButton == .secondary {
            let tick = context.projection.tick(atX: x, fine: false)
            if let selection = state.selection, selection.isActive,
               !selectionContains(state, tick: tick, facts: context.facts) {
                state.selection = nil
                result.publication.formUnion(.content)
                result.selectionBuild = true
                result.commandAvailabilityChanged = true
            }
        }
        switch input.changedButton {
        case .middle:
            state.pointer = .pan(previousX: x)
            state.cursor = .closedHand
            result.publication.formUnion(.interaction)
        case .secondary:
            let facts = context.facts
            let tick = context.projection.tick(atX: x, fine: false)
            let inside = selectionContains(state, tick: tick, facts: facts)
            let band = AutomationRangeBand(
                facts: facts, projection: context.projection, lane: context.lane,
                anchorTick: tick, currentTick: tick, pressX: x, pressY: y,
                x: x, y: y, active: false, beganInsideSelection: inside)
            state.pointer = .pendingBand(band)
            result.publication.formUnion([.band, .interaction])
        case .primary:
            let facts = context.facts
            let projection = context.projection
            let lane = context.lane
            let modifiers = AutomationModifiers(input.modifiers)
            state.pointer = .idle
            if (!state.isPencilMode || projection.markersVisible()),
               let hit = lane.hitTest(x: x, y: y, radius: state.body.geometry.pointHitRadius),
               !state.isPencilMode
                    || projection.cell(atRawTick: projection.rawTick(atX: x))
                        .contains(Double(hit.tick)),
               let source = source(of: hit.identity, facts: facts) {
                let selectionDrag: AutomationNodeDragTransaction? = {
                    guard let selection = state.selection, selection.isActive,
                          selectionContains(state, tick: hit.tick, facts: facts) else { return nil }
                    return AutomationNodeDragTransaction.selection(
                        facts: facts,
                        lanes: context.coveredLanes.map { ($0.parameter, $0.snapshot) },
                        grabbed: (facts.parameter, source), range: selection.range,
                        press: (x, y), deleteOnStationary: !modifiers.shift)
                }()
                let transaction = selectionDrag ?? AutomationNodeDragTransaction.single(
                    facts: facts, source: source, press: (x, y),
                    deleteOnStationary: !modifiers.shift)
                state.pointer = .node(transaction: transaction, projection: projection)
            } else if !state.isPencilMode, let phantom = lane.originPhantom,
                      x * x + (phantom.point.y - y) * (phantom.point.y - y)
                        <= state.body.geometry.pointHitRadius * state.body.geometry.pointHitRadius,
                      let source = source(of: phantom.point.identity, facts: facts) {
                state.pointer = .phantom(transaction: AutomationPhantomDragTransaction(
                    facts: facts, source: source, press: (x, y)), projection: projection)
            } else if state.isPencilMode {
                let sample = AutomationPencilTransaction.Sample(
                    rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
                    point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init(),
                                       projection: projection, state: state),
                    continuousValue: Double(projection.value(atY: y, metadata: facts.metadata)))
                guard let stroke = AutomationPencilTransaction(
                    facts: facts, firstSample: sample,
                    firstCell: projection.cell(atRawTick: projection.rawTick(atX: x)),
                    clockTicks: projection.snapPolicy.clockTicks) else { return result }
                state.pointer = .pencil(transaction: stroke, projection: projection)
            } else {
                state.pointer = .sweep(transaction: AutomationSweepTransaction(
                    facts: facts, mode: modifiers.shift ? .ramp : .drag,
                    mapped: mappedPoint(x: x, y: y, facts: facts, modifiers: modifiers,
                                        projection: projection, state: state),
                    rawTick: projection.rawTick(atX: x), pressX: x, pressY: y),
                    projection: projection)
            }
            result.publication.formUnion([.preview, .interaction])
        default:
            return result
        }
        result.outcome.consumed = true
        result.outcome.accepted = true
        return result
    }

    private static func move(_ state: inout AutomationState, input: DrawerPointerInput,
                             context: AutomationPointerContext?) -> AutomationTransition {
        let x = input.x
        let y = input.y
        state.hoverX = x
        state.hoverY = y
        switch state.pointer {
        case let .pan(previousX):
            guard input.heldButtons.contains(.middle) else {
                state.pointer = .idle
                state.cursor = .arrow
                return AutomationTransition(publication: .interaction,
                                            outcome: AutomationOutcome(consumed: true, accepted: true))
            }
            state.pointer = .pan(previousX: x)
            let delta = x - previousX
            return AutomationTransition(effects: delta == 0 ? [] : [.panCamera(delta)],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))
        case var .pendingBand(band), var .band(band):
            band.currentTick = band.projection.tick(atX: x, fine: input.modifiers.alt)
            band.x = x
            band.y = y
            band.active = band.active
                || abs(x - band.pressX) + abs(y - band.pressY) >= state.body.dragDistance
            state.pointer = band.active ? .band(band) : .pendingBand(band)
            return AutomationTransition(publication: .band,
                                        outcome: AutomationOutcome(consumed: true, accepted: true))
        case .idle:
            guard input.heldButtons.held.isEmpty, let context else { return AutomationTransition() }
            let hover = AutomationHover.resolve(
                x: x, y: y, facts: context.facts, lane: context.lane,
                projection: context.projection, pointHitRadius: state.body.geometry.pointHitRadius,
                isPencilMode: state.isPencilMode)
            let changed = state.hover != hover
            state.hover = hover
            return AutomationTransition(
                publication: changed ? [.hover, .hoverHint, .interaction] : [.interaction],
                outcome: AutomationOutcome(consumed: true, accepted: true),
                hoverBuild: changed)
        default:
            updateGesture(&state, x: x, y: y, modifiers: AutomationModifiers(input.modifiers),
                          activateSweep: true)
            return AutomationTransition(publication: .preview,
                                        outcome: AutomationOutcome(consumed: true, accepted: true))
        }
    }

    private static func release(_ state: inout AutomationState, input: DrawerPointerInput,
                                context: AutomationPointerContext?) -> AutomationTransition {
        switch input.changedButton {
        case .middle:
            guard state.pointer.isPanning else { return AutomationTransition() }
            state.pointer = .idle
            state.cursor = .arrow
            return AutomationTransition(publication: .interaction,
                                        outcome: AutomationOutcome(consumed: true, accepted: true))
        case .secondary:
            guard let band = state.pointer.rangeBand else { return AutomationTransition() }
            state.pointer = .idle
            var result = AutomationTransition(publication: [.band, .interaction],
                                              outcome: AutomationOutcome(consumed: true,
                                                                         accepted: true))
            guard band.revision == state.document.revision,
                  band.parameter == state.activeParameter else { return result }
            let current = band.projection.tick(atX: input.x, fine: input.modifiers.alt)
            if band.active {
                let first = min(band.anchorTick, current)
                let last = max(band.anchorTick, current)
                let selection: AutomationTimeSelection? = last > first
                    ? AutomationTimeSelection(range: TimeRange(startTick: first, endTick: last),
                                              scope: .lanes, lanes: [band.parameter],
                                              tempo: band.parameter == .tempo)
                    : nil
                if state.selection != selection {
                    state.selection = selection
                    result.publication.formUnion(.content)
                    result.selectionBuild = true
                    result.commandAvailabilityChanged = true
                }
            } else if let context {
                let target: AutomationMenuTarget?
                if let hit = band.lane.hitTest(x: input.x, y: input.y,
                                               radius: state.body.geometry.pointHitRadius) {
                    target = .point(tick: hit.tick, value: hit.value)
                } else {
                    target = band.beganInsideSelection ? .range : nil
                }
                if let target {
                    result.merge(AutomationModal.reduce(&state, event: .openMenu(
                        facts: band.facts, target: target,
                        x: input.x + state.body.plotOrigin, y: input.y,
                        selectionScopeAvailable: context.selectionScopeAvailable,
                        systemClipboardAvailable: context.systemClipboardAvailable,
                        laneClipboardAvailable: !state.laneClipboardPoints.isEmpty)))
                }
            }
            return result
        case .primary:
            guard state.pointer.isGesture,
                  let facts = state.pointer.gestureFacts else { return AutomationTransition() }
            let valid = facts.revision == state.document.revision
                && facts.parameter == state.activeParameter
            if valid {
                updateGesture(&state, x: input.x, y: input.y,
                              modifiers: AutomationModifiers(input.modifiers),
                              activateSweep: false)
            }
            let pointer = state.pointer
            state.pointer = .idle
            state.cursor = state.isPencilMode ? .pencil : .arrow
            var result = AutomationTransition(publication: [.preview, .interaction],
                                              outcome: AutomationOutcome())
            guard valid else { return result }
            switch pointer {
            case let .node(transaction, _):
                let finish = transaction.finish()
                switch (finish.release, finish.changed) {
                case (.stationaryDelete, _) where transaction.grabbed != nil:
                    if let plan = AutomationNodeResolver.deletions(
                        revision: facts.revision,
                        [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                          snapshot: facts.snapshot,
                                                          ticks: transaction.deleteTicks)]) {
                        result.effects.append(.commitDocument(plan, selectionDelta: nil))
                    }
                case (.move, true):
                    let moves = transaction.moves
                    let requests = transaction.laneFacts.map { lane in
                        AutomationNodeResolver.LaneMoves(
                            lane, moves.filter { $0.parameter == lane.parameter })
                    }
                    if let plan = AutomationNodeResolver.moves(requests) {
                        result.effects.append(.commitDocument(
                            plan, selectionDelta: finish.selectionDrag && finish.dTick != 0
                                ? finish.dTick : nil))
                    }
                default: break
                }
            case let .phantom(transaction, _):
                if let move = transaction.move,
                   let plan = AutomationNodeResolver.moves([
                    AutomationNodeResolver.LaneMoves(facts, [move])]) {
                    result.effects.append(.commitDocument(plan, selectionDelta: nil))
                }
            case let .pencil(transaction, _):
                result.effects.append(.commitLane(transaction.completion()))
            case let .sweep(transaction, projection):
                if transaction.mode == .drag, !transaction.slopExceeded {
                    result.effects.append(.setEditCursor(projection.tick(
                        atX: transaction.pressX, fine: false)))
                } else if let edit = transaction.finish(fine: input.modifiers.alt,
                                                      projection: projection) {
                    result.effects.append(.commitLane(edit))
                }
            default: break
            }
            result.outcome.written = result.effects.contains { effect in
                switch effect {
                case .commitDocument, .commitLane: true
                default: false
                }
            }
            result.outcome.consumed = result.outcome.written
            result.outcome.accepted = result.outcome.written
            return result
        default:
            return AutomationTransition()
        }
    }

    private static func updateGesture(_ state: inout AutomationState, x: Double, y: Double,
                                      modifiers: AutomationModifiers, activateSweep: Bool) {
        switch state.pointer {
        case var .node(transaction, projection):
            let facts = transaction.facts
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: modifiers.shift,
                activationDistance: state.body.geometry.nodeDragActivationDistance)
            if update.phase != .pending {
                _ = transaction.update(update, mapped: mappedPoint(
                    x: update.effectiveX, y: update.effectiveY, facts: facts,
                    modifiers: modifiers, projection: projection, state: state))
            }
            state.pointer = .node(transaction: transaction, projection: projection)
            state.cursor = transaction.drag.axisLock == .time ? .sizeHorizontal
                : transaction.drag.axisLock == .value ? .sizeVertical : .arrow
        case var .phantom(transaction, projection):
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: modifiers.shift,
                activationDistance: state.body.geometry.nodeDragActivationDistance)
            _ = transaction.update(update, mappedValue: projection.value(
                atY: update.effectiveY, metadata: transaction.facts.metadata))
            state.pointer = .phantom(transaction: transaction, projection: projection)
            state.cursor = .sizeVertical
        case var .sweep(transaction, projection):
            let facts = transaction.facts
            if transaction.mode == .ramp {
                transaction.updateRamp(mapped: mappedPoint(x: x, y: y, facts: facts,
                    modifiers: modifiers, projection: projection, state: state))
            } else if let effective = transaction.dragPosition(
                x: x, y: y, activate: activateSweep,
                activationDistance: state.body.geometry.nodeDragActivationDistance),
                transaction.slopExceeded {
                let rawTick = projection.rawTick(atX: effective.x)
                let first = projection.snapPolicy.snap(min(transaction.previousRawTick, rawTick),
                                                       fine: modifiers.fine,
                                                       camera: projection.camera)
                let last = projection.snapPolicy.snap(max(transaction.previousRawTick, rawTick),
                                                      fine: modifiers.fine,
                                                      camera: projection.camera)
                transaction.update(mapped: mappedPoint(
                    x: effective.x, y: effective.y, facts: facts, modifiers: modifiers,
                    projection: projection, state: state), first: first, last: last,
                    rawTick: rawTick, fine: modifiers.fine, projection: projection)
            }
            state.pointer = .sweep(transaction: transaction, projection: projection)
        case var .pencil(transaction, projection):
            let facts = transaction.facts
            let freehand = modifiers.snapValue
            let continuous = transaction.sampleValue(
                logicalX: x, logicalY: y, locking: modifiers.shift, freehand: freehand,
                verticalSlopDistance: state.body.geometry.nodeDragActivationDistance,
                plotHeight: state.body.plotHeight,
                displaySpan: (projection.displayMaximum ?? facts.metadata.maximum)
                    - facts.metadata.minimum)
            let sample = AutomationPencilTransaction.Sample(
                rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
                point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init(),
                                   projection: projection, state: state),
                continuousValue: continuous)
            if freehand {
                _ = transaction.applyFreehandSegment(sample)
            } else {
                _ = transaction.applySnappedSegment(
                    sample, cells: projection.cellsCrossed(
                        from: transaction.previousLogicalX, to: x))
            }
            state.pointer = .pencil(transaction: transaction, projection: projection)
        default: break
        }
    }

    private static func mappedPoint(x: Double, y: Double, facts: AutomationFrozenFacts,
                                    modifiers: AutomationModifiers,
                                    projection: AutomationProjection,
                                    state: AutomationState) -> AutomationLanePoint {
        projection.mappedPoint(x: x, y: y, facts: facts, modifiers: modifiers,
                               plotHeight: state.body.plotHeight,
                               neutralSnapRadius: state.body.geometry.neutralSnapRadius)
    }


    private static func selectionContains(_ state: AutomationState, tick: Tick,
                                          facts: AutomationFrozenFacts) -> Bool {
        guard let selection = state.selection, selection.isActive,
              selection.range.contains(tick) else { return false }
        if facts.parameter == .tempo {
            return selection.coversTempo(usedTracks: state.document.usedTracks)
        }
        return selection.covers(facts.parameter, usedTracks: state.document.usedTracks)
    }
}

func source(of identity: AutomationPointIdentity,
            facts: AutomationFrozenFacts) -> AutomationSourcePoint? {
    if let source = facts.snapshot.sources.first(where: { $0.identity == identity }) {
        return source
    }
    // The projected engine node has no written occurrence; dragging promotes it.
    guard identity.occurrence == -1, identity.tick == 0,
          facts.snapshot.projectedTickZero else { return nil }
    return AutomationSourcePoint(identity: identity, tick: identity.tick, value: identity.value,
                                 lanePoint: nil, tempoPoint: nil)
}

func shiftedAutomationSelection(_ selection: AutomationTimeSelection?,
                                by delta: Int64) -> AutomationTimeSelection? {
    guard var moved = selection else { return nil }
    let start = TimeDefaults.shiftTickClamped(moved.range.startTick, by: delta)
    let end = TimeDefaults.shiftTickClamped(moved.range.endTick, by: delta)
    guard end > start else { return nil }
    moved.range = TimeRange(startTick: start, endTick: end)
    return moved
}
