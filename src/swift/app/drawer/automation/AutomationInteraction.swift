import Foundation
import PorydawCore

// Gesture state coordination, pointer mapping, and frozen input dispatch.
// The AutomationPage keeps the Qt-facing methods; this adapter owns their cohesive internals.

/// Where a pointer event landed in the page body: the selector tabs own the
/// gutter column, the plot owns editing. Mirrors the production
/// `TimelineInputSurface` split and the sibling pages' own surface enums.
public enum AutomationInputSurface: Int, Sendable {
    case tabs = 0
    case plot = 1
}

/// Qt pointer buttons as QML carries them (`mouse.button`).
public enum AutomationQtButton {
    public static let left = 1
    public static let right = 2
    public static let middle = 4
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
        AutomationModifiers(fine: flags & alt != 0, snapValue: flags & control != 0,
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

/// One hover over the plot: the node under the pointer, or the background tick
/// with the value the lane holds there.
public struct AutomationHover: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let tick: Tick
    public let value: Int?
    public let text: String
    public let hasPoint: Bool

    static func resolve(
        x: Double,
        y: Double,
        facts: AutomationFrozenFacts,
        lane: AutomationLaneProjection,
        projection: AutomationProjection,
        pointHitRadius: Double,
        isPencilMode: Bool
    ) -> Self {
        if (!isPencilMode || projection.markersVisible()),
           let hit = lane.hitTest(x: x, y: y, radius: pointHitRadius) {
            return Self(
                parameter: facts.parameter,
                tick: hit.tick,
                value: hit.value,
                text: facts.metadata.valueText(hit.value),
                hasPoint: true)
        }
        // The background tick is the fine lattice, or the insert cell while
        // the pencil is armed; the readout is the value the lane holds there.
        let tick = isPencilMode
            ? projection.cell(atRawTick: projection.rawTick(atX: x)).tickBegin
            : projection.tick(atX: x, fine: true)
        let held = isPencilMode ? projection.value(atY: y, metadata: facts.metadata)
            : lane.heldValue(at: tick)
        return Self(
            parameter: facts.parameter,
            tick: tick,
            value: held,
            text: held.map(facts.metadata.valueText) ?? "",
            hasPoint: false)
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
    // MARK: Internals: input cores

    /// One left press in plot coordinates: a node grab, the projected origin
    /// node's promotion drag, the pencil stroke, or a sweep.
    @discardableResult
    func pressPlot(x: Double, y: Double, modifiers: AutomationModifiers) -> Bool {
        guard let facts = frozenFacts(modifiers: modifiers) else { return false }
        cancelGesture()
        // The gesture's inputs are frozen for its whole life: motion, release and
        // cancellation all read this one revision, camera and value projection.
        frozen = facts
        frozenCamera = liveCamera()
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        guard let lane = laneProjection(facts: facts, projection: projection) else { return false }
        if (!isPencilMode || projection.markersVisible()),
           let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius),
           !isPencilMode || projection.cell(atRawTick: projection.rawTick(atX: x)).contains(Double(hit.tick)),
           let source = source(of: hit.identity, facts: facts) {
            let deleteOnStationary = !modifiers.shift
            gesture = .node(selectedNodesDrag(facts: facts, hit: hit, press: (x, y),
                                              deleteOnStationary: deleteOnStationary)
                ?? AutomationNodeDragTransaction.single(
                    facts: facts, source: source, press: (x, y),
                    deleteOnStationary: deleteOnStationary))
            publishPreview()
            publishInteractionState()
            return true
        }
        if !isPencilMode, let phantom = phantomHit(lane: lane, x: x, y: y),
           let source = source(of: phantom.point.identity, facts: facts) {
            gesture = .phantom(AutomationPhantomDragTransaction(facts: facts, source: source,
                                                               press: (x, y)))
            publishPreview()
            publishInteractionState()
            return true
        }
        if isPencilMode {
            let continuous = Double(projection.value(atY: y, metadata: facts.metadata))
            let first = AutomationPencilTransaction.Sample(
                rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
                point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init(),
                                   projection: projection),
                continuousValue: continuous)
            guard let stroke = AutomationPencilTransaction(
                facts: facts, firstSample: first,
                firstCell: projection.cell(atRawTick: projection.rawTick(atX: x)),
                clockTicks: projection.snapPolicy.clockTicks) else { return false }
            gesture = .pencil(stroke)
        } else {
            gesture = .sweep(AutomationSweepTransaction(
                facts: facts, mode: modifiers.shift ? .ramp : .drag,
                mapped: mappedPoint(x: x, y: y, facts: facts, modifiers: modifiers,
                                    projection: projection),
                rawTick: projection.rawTick(atX: x), pressX: x, pressY: y))
        }
        publishPreview()
        publishInteractionState()
        return true
    }

    /// One left release: the frozen draft resolves into at most one commit, and
    /// every mapping below reads the press-time projection the gesture froze.
    @discardableResult
    func releasePlot(x: Double, y: Double, modifiers: AutomationModifiers) -> Bool {
        guard let session, let facts = frozen else { return false }
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        updateGesture(x: x, y: y, active: modifiers, facts: facts,
                      projection: projection, activateSweep: false)
        guard let gesture else { return false }
        self.gesture = nil
        self.frozen = nil
        frozenCamera = nil
        var committed = false
        switch gesture {
        case let .node(transaction):
            let finish = transaction.finish()
            switch (finish.release, finish.changed) {
            case (.stationaryDelete, _) where transaction.grabbed != nil:
                committed = commit(AutomationNodeResolver.deletions(
                    revision: facts.revision,
                    [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                        snapshot: facts.snapshot,
                                                        ticks: transaction.deleteTicks)]))
            case (.move, true):
                let moves = transaction.moves
                let requests = transaction.laneFacts.map { lane in
                    AutomationNodeResolver.LaneMoves(
                        lane, moves.filter { $0.parameter == lane.parameter })
                }
                committed = commit(AutomationNodeResolver.moves(requests))
                if committed, finish.dTick != 0, finish.selectionDrag {
                    shiftSelection(by: finish.dTick)
                }
            default:
                break
            }
        case let .phantom(transaction):
            if let move = transaction.move {
                committed = commit(AutomationNodeResolver.moves([
                    AutomationNodeResolver.LaneMoves(facts, [move])
                ]))
            }
        case let .pencil(transaction):
            committed = AutomationCommit.apply(transaction.completion(), in: session.document)
        case let .sweep(transaction):
            if transaction.mode == .drag, !transaction.slopExceeded {
                // A press that never travelled parks the edit cursor instead.
                session.editCursor = projection.tick(atX: transaction.pressX, fine: false)
            } else if let edit = transaction.finish(fine: modifiers.fine, projection: projection) {
                committed = AutomationCommit.apply(edit, in: session.document)
            }
        }
        applyPreviewDraft(.empty)
        publishPreview()
        cursorKind = isPencilMode ? AutomationCursorKind.pencil.rawValue : AutomationCursorKind.arrow.rawValue
        if committed {
            refreshFromDocument()
        } else {
            // A release that wrote nothing republishes the hover the pointer now
            // really sits on. Cursor readout changes arrive through the session.
            if let live = frozenFacts(modifiers: modifiers) {
                updateHover(x: x, y: y, facts: live,
                            projection: makeProjection(facts: live, camera: liveCamera()))
            }
            publishInteractionState()
        }
        return committed
    }

    /// One right press's release: a travelled band publishes the selection it
    /// covered, and a stationary one opens the node menu it hit or the range menu
    /// the press started inside. A miss opens nothing.
    func releaseBand(_ live: AutomationRangeBand, x: Double, y: Double) {
        guard let session, live.revision == session.document.revision,
              live.parameter == activeParameter else { return }
        let first = min(live.anchorTick, live.currentTick)
        let last = max(live.anchorTick, live.currentTick)
        if live.active {
            if last > first { selectRange(from: first, to: last) }
            else { applyTimeSelection(nil) }
            return
        }
        guard let facts = frozenFacts(modifiers: .init()) else { return }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        if let lane = laneProjection(facts: facts, projection: projection),
           let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius) {
            openPointMenu(hit: hit, facts: facts, x: x, y: y)
            return
        }
        if live.insideSelection { openRangeMenu(x: x, y: y) }
    }

    func endPan() {
        guard panActive else { return }
        panActive = false
        cursorKind = AutomationCursorKind.arrow.rawValue
        publishInteractionState()
    }

    /// The production press rule: a press outside the explicit selection clears
    /// it, and a press on a covered lane or inside the covered range keeps it.
    func clearSelectionIfPressIsOutside(x: Double) {
        guard let selection, selection.isActive, let facts = frozenFacts(modifiers: .init()) else {
            return
        }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        let tick = projection.tick(atX: x, fine: false)
        if selectionContains(tick: tick, facts: facts) { return }
        applyTimeSelection(nil)
    }

    func selectionContains(tick: Tick, facts: AutomationFrozenFacts) -> Bool {
        guard let selection, selection.isActive,
              selection.covers(facts.parameter, usedTracks: usedTracks()),
              row(facts.parameter)?.coversNodes == true else { return false }
        return selection.range.contains(tick)
    }

    /// The pointer's hover: the node under it, or the background tick with the
    /// value the lane holds there.
    func updateHover(x: Double, y: Double, facts: AutomationFrozenFacts,
                     projection: AutomationProjection) {
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

    func update(sweep transaction: inout AutomationSweepTransaction, x: Double, y: Double,
                        modifiers: AutomationModifiers, facts: AutomationFrozenFacts,
                        projection: AutomationProjection, activate: Bool) {
        if transaction.mode == .ramp {
            transaction.updateRamp(mapped: mappedPoint(x: x, y: y, facts: facts,
                                                       modifiers: modifiers,
                                                       projection: projection))
            return
        }
        guard let effective = transaction.dragPosition(
            x: x, y: y, activate: activate,
            activationDistance: geometry.nodeDragActivationDistance),
              transaction.slopExceeded else { return }
        let rawTick = projection.rawTick(atX: effective.x)
        let first = projection.snapPolicy.snap(min(transaction.previousRawTick, rawTick),
                                               fine: modifiers.fine, camera: projection.camera)
        let last = projection.snapPolicy.snap(max(transaction.previousRawTick, rawTick),
                                              fine: modifiers.fine, camera: projection.camera)
        transaction.update(mapped: mappedPoint(x: effective.x, y: effective.y, facts: facts,
                                               modifiers: modifiers, projection: projection),
                           first: first, last: last, rawTick: rawTick, fine: modifiers.fine,
                           projection: projection)
    }

    func update(pencil transaction: inout AutomationPencilTransaction, x: Double, y: Double,
                        facts: AutomationFrozenFacts, projection: AutomationProjection,
                        modifiers: AutomationModifiers) {
        let freehand = modifiers.snapValue
        let locking = modifiers.shift
        let continuous = transaction.sampleValue(
            logicalX: x, logicalY: y, locking: locking, freehand: freehand,
            verticalSlopDistance: geometry.nodeDragActivationDistance, plotHeight: plotHeight,
            displaySpan: (projection.displayMaximum ?? facts.metadata.maximum) - facts.metadata.minimum)
        let sample = AutomationPencilTransaction.Sample(
            rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
            point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init(),
                               projection: projection),
            continuousValue: continuous)
        if freehand {
            _ = transaction.applyFreehandSegment(sample)
        } else {
            _ = transaction.applySnappedSegment(
                sample, cells: projection.cellsCrossed(from: transaction.previousLogicalX, to: x))
        }
    }

    func mappedPoint(x: Double, y: Double, facts: AutomationFrozenFacts,
                             modifiers: AutomationModifiers,
                             projection: AutomationProjection) -> AutomationLanePoint {
        AutomationLanePoint(
            tick: projection.tick(atX: x, fine: modifiers.fine),
            value: facts.metadata.snappedValue(
                projection.value(atY: y, metadata: facts.metadata), snapValue: modifiers.snapValue,
                plotHeight: plotHeight, neutralSnapRadius: geometry.neutralSnapRadius))
    }

    func phantomHit(lane: AutomationLaneProjection, x: Double,
                            y: Double) -> AutomationOriginPhantom? {
        guard let phantom = lane.originPhantom else { return nil }
        let dy = phantom.point.y - y
        return x * x + dy * dy <= geometry.pointHitRadius * geometry.pointHitRadius
            ? phantom : nil
    }

    func cancelGesture() {
        gesture = nil
        frozen = nil
        frozenCamera = nil
    }

    func snapped(tickAtX x: Double, modifiers: Int) -> Tick {
        guard let facts = frozenFacts(modifiers: .init()) else { return 0 }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        return projection.tick(atX: x, fine: modifiers & AutomationQtModifier.alt != 0)
    }

    func commit(_ plan: AutomationDocumentPlan?) -> Bool {
        guard let session, let plan else { return false }
        return AutomationCommit.apply(plan, in: session.document)
    }


    func selectionScope(_ selection: AutomationTimeSelection) -> TimeScope {
        switch selection.scope {
        case .lanes:
            let lanes = selection.lanes.reduce(into: Set<TimeScope.ScopedLane>()) { result, item in
                guard let track = item.track, let lane = item.lane else { return }
                result.insert(TimeScope.ScopedLane(track: track, lane: lane))
            }
            return TimeScope(tracks: [], lanes: lanes, tempo: selection.tempo)
        case let .tracks(scope):
            return TimeScope(tracks: scope, lanes: [],
                             tempo: selection.coversTempo(usedTracks: usedTracks()))
        }
    }

    /// The parameters the explicit selection covers and that still carry events:
    /// the lanes a range command or a shared-delta drag acts on.
    func coveredLanes()
        -> [(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot)] {
        guard let session else { return [] }
        return rows.compactMap { row in
            guard row.coversNodes, row.selectionHasEvents else { return nil }
            return (row.parameter, projectionFacts.snapshot(row.parameter, session: session))
        }
    }

    /// The written occurrences the explicit selection currently covers.
    func coveredEventCount() -> Int {
        guard let selection, selection.isActive else { return 0 }
        return coveredLanes().reduce(0) { total, lane in
            total + lane.snapshot.sources.filter { selection.range.contains($0.tick) }.count
        }
    }

    func selectedNodesDrag(facts: AutomationFrozenFacts, hit: AutomationProjectedPoint,
                                   press: (x: Double, y: Double), deleteOnStationary: Bool)
        -> AutomationNodeDragTransaction? {
        guard let selection, selection.isActive,
              row(facts.parameter)?.coversNodes == true, selection.range.contains(hit.tick),
              let source = source(of: hit.identity, facts: facts) else { return nil }
        return AutomationNodeDragTransaction.selection(
            facts: facts, lanes: coveredLanes(), grabbed: (facts.parameter, source),
            range: selection.range, press: press, deleteOnStationary: deleteOnStationary)
    }

}

func source(of identity: AutomationPointIdentity,
            facts: AutomationFrozenFacts) -> AutomationSourcePoint? {
    if let source = facts.snapshot.sources.first(where: { $0.identity == identity }) {
        return source
    }
    // The projected engine node has no written occurrence: a drag on it is the
    // promotion write the resolver performs for a projected tick-zero node.
    guard identity.occurrence == -1, identity.tick == 0,
          facts.snapshot.projectedTickZero else { return nil }
    return AutomationSourcePoint(identity: identity, tick: identity.tick, value: identity.value,
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

@MainActor
extension AutomationPage {
    func dispatchPointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int = 0) -> Bool {
        pointerLeave()
        guard session != nil, surface == AutomationInputSurface.plot.rawValue else { return false }
        hoverX = x
        previousX = x
        if button == AutomationQtButton.left || button == AutomationQtButton.right {
            clearSelectionIfPressIsOutside(x: x)
        }
        switch button {
        case AutomationQtButton.middle:
            panActive = true
            cursorKind = AutomationCursorKind.closedHand.rawValue
            publishInteractionState()
            return true
        case AutomationQtButton.right:
            guard let facts = frozenFacts(modifiers: .init()) else { return false }
            let projection = makeProjection(facts: facts, camera: liveCamera())
            let tick = projection.tick(atX: x, fine: false)
            let inside = selectionContains(tick: tick, facts: facts)
            band = AutomationRangeBand(revision: facts.revision, parameter: facts.parameter,
                                       anchorTick: tick, currentTick: tick,
                                       pressX: x, pressY: y, insideSelection: inside)
            publishBand()
            publishInteractionState()
            return true
        case AutomationQtButton.left:
            return pressPlot(x: x, y: y, modifiers: AutomationQtModifier.automation(modifiers))
        default:
            return false
        }
    }

    func dispatchPointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        guard session != nil else { return false }
        hoverX = x
        if panActive {
            guard buttons & AutomationQtButton.middle != 0 else {
                endPan()
                return true
            }
            let delta = x - previousX
            previousX = x
            if delta != 0 {
                // The one camera authority: the shared mutation path clamps and
                // publishes, and every surface reprojects from it.
                session?.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            }
            return true
        }
        if var live = band {
            live.currentTick = snapped(tickAtX: x, modifiers: modifiers)
            live.active = live.active
                || abs(x - live.pressX) + abs(y - live.pressY) >= dragDistance
            band = live
            publishBand()
            return true
        }
        let active = AutomationQtModifier.automation(modifiers)
        guard let facts = frozen ?? frozenFacts(modifiers: active) else { return false }
        // A frozen gesture keeps its press-time camera for its whole life: the
        // facts froze that projection, so every later motion maps through it.
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        guard gesture != nil else {
            guard buttons == 0 else { return false }
            updateHover(x: x, y: y, facts: facts, projection: projection)
            publishInteractionState()
            return true
        }
        previousX = x
        updateGesture(x: x, y: y, active: active, facts: facts,
                      projection: projection, activateSweep: true)
        publishPreview()
        return true
    }

    func updateGesture(x: Double, y: Double, active: AutomationModifiers,
                       facts: AutomationFrozenFacts, projection: AutomationProjection,
                       activateSweep: Bool) {
        guard let gesture else { return }
        switch gesture {
        case let .node(transaction):
            var transaction = transaction
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: active.shift,
                activationDistance: geometry.nodeDragActivationDistance)
            if update.phase != .pending {
                _ = transaction.update(update, mapped: mappedPoint(
                    x: update.effectiveX, y: update.effectiveY, facts: facts,
                    modifiers: active, projection: projection))
            }
            self.gesture = .node(transaction)
            cursorKind = transaction.drag.axisLock == .time ? AutomationCursorKind.sizeHorizontal.rawValue
                : transaction.drag.axisLock == .value ? AutomationCursorKind.sizeVertical.rawValue
                : AutomationCursorKind.arrow.rawValue
        case let .phantom(transaction):
            var transaction = transaction
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: active.shift,
                activationDistance: geometry.nodeDragActivationDistance)
            _ = transaction.update(update, mappedValue: projection.value(
                atY: update.effectiveY, metadata: facts.metadata))
            self.gesture = .phantom(transaction)
            cursorKind = AutomationCursorKind.sizeVertical.rawValue
        case let .sweep(transaction):
            var transaction = transaction
            update(sweep: &transaction, x: x, y: y, modifiers: active, facts: facts,
                   projection: projection, activate: activateSweep)
            self.gesture = .sweep(transaction)
        case let .pencil(transaction):
            var transaction = transaction
            update(pencil: &transaction, x: x, y: y, facts: facts,
                   projection: projection, modifiers: active)
            self.gesture = .pencil(transaction)
        }
    }

    func dispatchPointerRelease(x: Double, y: Double, button: Int, modifiers: Int = 0) -> Bool {
        guard session != nil else { return false }
        switch button {
        case AutomationQtButton.middle:
            guard panActive else { return false }
            endPan()
            return true
        case AutomationQtButton.right:
            guard var live = band else { return false }
            live.currentTick = snapped(tickAtX: x, modifiers: modifiers)
            band = nil
            publishBand()
            releaseBand(live, x: x, y: y)
            publishInteractionState()
            return true
        case AutomationQtButton.left:
            return releasePlot(x: x, y: y, modifiers: AutomationQtModifier.automation(modifiers))
        default:
            return false
        }
    }

    func dispatchPointerDoubleClick(x: Double, y: Double) -> Bool {
        guard session != nil else { return false }
        _ = x
        _ = y
        cancelGesture()
        applyPreviewDraft(.empty)
        publishPreview()
        publishInteractionState()
        return true
    }

    func dispatchPointerLeave() {
        guard hover != nil else { return }
        _ = applyHover(nil, countingPublication: true)
        publishHover()
        publishInteractionState()
    }

    func dispatchEscape() -> Bool {
        if prompt != nil || laneDelete != nil || menu != nil || gesture != nil || band != nil
            || panActive || tapGuard != nil {
            cancelSectionInteraction()
            return true
        }
        guard hover != nil else { return false }
        pointerLeave()
        return true
    }

    func cancelAllInteractions() {
        cancelGesture()
        band = nil
        panActive = false
        menu = nil
        applyPrompt(nil)
        laneDelete = nil
        applyPreviewDraft(.empty)
        resetTapTempo()
        _ = applyHover(nil, countingPublication: false)
        cursorKind = AutomationCursorKind.arrow.rawValue
        publishMenuRows()
        publishPrompt()
        publishBand()
        publishHover()
        publishPreview()
        publishInteractionState()
    }
}
