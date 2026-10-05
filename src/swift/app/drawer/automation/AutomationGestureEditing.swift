import PorydawCore
import PorydawDocument

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
            let source = source(of: hit.identity, facts: facts)
        {
            let deleteOnStationary = !modifiers.shift
            gesture = .node(
                selectedNodesDrag(
                    facts: facts, hit: hit, press: (x, y),
                    deleteOnStationary: deleteOnStationary)
                    ?? AutomationNodeDragTransaction.single(
                        facts: facts, source: source, press: (x, y),
                        deleteOnStationary: deleteOnStationary))
            publishPreview()
            publishInteractionState()
            return true
        }
        if !isPencilMode, let phantom = phantomHit(lane: lane, x: x, y: y),
            let source = source(of: phantom.point.identity, facts: facts)
        {
            gesture = .phantom(
                AutomationPhantomDragTransaction(
                    facts: facts, source: source,
                    press: (x, y)))
            publishPreview()
            publishInteractionState()
            return true
        }
        if isPencilMode {
            let continuous = projection.value(atY: y, metadata: facts.metadata)
            let rawTick = projection.rawTick(atX: x)
            let firstCell = projection.cell(atRawTick: rawTick)
            let first = AutomationPencilTransaction.Sample(
                rawTick: rawTick, logicalX: x, logicalY: y,
                point: AutomationLanePoint(tick: firstCell.tickBegin, value: continuous),
                continuousValue: Double(continuous))
            guard
                let stroke = AutomationPencilTransaction(
                    facts: facts, firstSample: first,
                    firstCell: firstCell,
                    clockTicks: projection.snapPolicy.clockTicks)
            else { return false }
            gesture = .pencil(stroke)
        } else {
            gesture = .sweep(
                AutomationSweepTransaction(
                    facts: facts, mode: modifiers.shift ? .ramp : .drag,
                    mapped: mappedPoint(
                        x: x, y: y, facts: facts, modifiers: modifiers,
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
        updateGesture(
            x: x, y: y, active: modifiers, facts: facts,
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
                committed = commit(
                    AutomationNodeResolver.deletions(
                        revision: facts.revision,
                        [
                            AutomationNodeResolver.LaneDeletes(
                                parameter: facts.parameter,
                                snapshot: facts.snapshot,
                                ticks: transaction.deleteTicks)
                        ]))
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
                committed = commit(
                    AutomationNodeResolver.moves([
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
                updateHover(
                    x: x, y: y, facts: live,
                    projection: makeProjection(facts: live, camera: liveCamera()))
            }
            publishInteractionState()
        }
        return committed
    }

    func releaseBand(_ live: AutomationRangeBand, x: Double, y: Double) {
        guard let session, live.revision == session.document.revision,
            live.parameter == activeParameter
        else { return }
        let first = min(live.anchorTick, live.currentTick)
        let last = max(live.anchorTick, live.currentTick)
        if live.active {
            if last > first {
                let stack = AutomationRowStack(
                    rows: rows, visibleRowCount: rows.count,
                    activeTickRange: nil)
                let payload = stack.laneSet(from: live.parameter, through: live.parameter)
                applyTimeSelection(
                    AutomationTimeSelection(
                        range: TimeRange(startTick: first, endTick: last), scope: .lanes,
                        lanes: Set(payload.lanes), tempo: payload.tempo))
            } else {
                applyTimeSelection(nil)
            }
            return
        }
        guard let facts = frozenFacts(modifiers: .init()) else { return }
        let projection = makeProjection(facts: facts, camera: liveCamera())
        guard let lane = laneProjection(facts: facts, projection: projection) else { return }
        if let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius) {
            openPointMenu(hit: hit, facts: facts, x: x, y: y)
            return
        }
        if live.insideSelection {
            if let onRequestTimeMenu, selection?.scope == .lanes {
                onRequestTimeMenu(live.anchorTick, live.pressY)
            } else {
                openRangeMenu(x: x, y: y)
            }
            return
        }
        // The hover ghost under a stationary right click: type the value it inserts.
        let ghost = AutomationHover.resolve(
            x: x, y: y, facts: facts, lane: lane, projection: projection,
            pointHitRadius: geometry.pointHitRadius, isPencilMode: isPencilMode)
        if !ghost.hasPoint, let value = ghost.value {
            openInsertionPrompt(tick: Int(ghost.tick), value: value)
        }
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
        if selectionContains(x: x, facts: facts, projection: projection) { return }
        if case .tracks = selection.scope, row(facts.parameter)?.coversNodes == true,
            x >= projection.x(selection.range.startTick),
            x < projection.x(selection.range.endTick)
        {
            return
        }
        applyTimeSelection(nil)
    }

    func selectionContains(
        x: Double, facts: AutomationFrozenFacts,
        projection: AutomationProjection
    ) -> Bool {
        guard let selection else { return false }
        let stack = AutomationRowStack(
            rows: rows, visibleRowCount: rows.count,
            activeTickRange: selection.range)
        return stack.hitTest(
            parameter: facts.parameter, x: x,
            projection: projection, selection: selection)
    }

    func update(
        sweep transaction: inout AutomationSweepTransaction, x: Double, y: Double,
        modifiers: AutomationModifiers, facts: AutomationFrozenFacts,
        projection: AutomationProjection, activate: Bool
    ) {
        if transaction.mode == .ramp {
            transaction.updateRamp(
                mapped: mappedPoint(
                    x: x, y: y, facts: facts,
                    modifiers: modifiers,
                    projection: projection))
            return
        }
        guard
            let effective = transaction.dragPosition(
                x: x, y: y, activate: activate,
                activationDistance: geometry.nodeDragActivationDistance),
            transaction.slopExceeded
        else { return }
        let rawTick = projection.rawTick(atX: effective.x)
        let first = projection.snapPolicy.snap(
            min(transaction.previousRawTick, rawTick),
            fine: modifiers.fine, camera: projection.camera)
        let last = projection.snapPolicy.snap(
            max(transaction.previousRawTick, rawTick),
            fine: modifiers.fine, camera: projection.camera)
        transaction.update(
            mapped: mappedPoint(
                x: effective.x, y: effective.y, facts: facts,
                modifiers: modifiers, projection: projection),
            first: first, last: last, rawTick: rawTick, fine: modifiers.fine,
            projection: projection)
    }

    func update(
        pencil transaction: inout AutomationPencilTransaction, x: Double, y: Double,
        facts: AutomationFrozenFacts, projection: AutomationProjection,
        modifiers: AutomationModifiers
    ) {
        let freehand = modifiers.snapValue
        let locking = modifiers.shift
        let continuous = transaction.sampleValue(
            logicalX: x, logicalY: y, locking: locking, freehand: freehand,
            verticalSlopDistance: geometry.nodeDragActivationDistance,
            plotHeight: max(1, plotHeight - 2 * geometry.valuePlotPadding),
            displaySpan: (projection.displayMaximum ?? facts.metadata.maximum) - facts.metadata.minimum)
        let sample = AutomationPencilTransaction.Sample(
            rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
            point: mappedPoint(
                x: x, y: y, facts: facts, modifiers: .init(),
                projection: projection),
            continuousValue: continuous)
        if freehand {
            _ = transaction.applyFreehandSegment(sample)
        } else {
            _ = transaction.applySnappedSegment(
                sample,
                cells: projection.cellsCrossed(
                    from: projection.rawTick(atX: transaction.previousLogicalX), to: sample.rawTick))
        }
    }

    func cancelGesture() {
        gesture = nil
        frozen = nil
        frozenCamera = nil
    }

    func commit(_ plan: AutomationDocumentPlan?) -> Bool {
        guard let session, let plan else { return false }
        return AutomationCommit.apply(plan, in: session.document)
    }

    /// The parameters the explicit selection covers and that still carry events:
    /// the lanes a range command or a shared-delta drag acts on.
    func coveredLanes()
        -> [(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot)]
    {
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

    func selectedNodesDrag(
        facts: AutomationFrozenFacts, hit: AutomationProjectedPoint,
        press: (x: Double, y: Double), deleteOnStationary: Bool
    )
        -> AutomationNodeDragTransaction?
    {
        guard let selection, selection.isActive,
            row(facts.parameter)?.coversNodes == true, selection.range.contains(hit.tick),
            let source = source(of: hit.identity, facts: facts)
        else { return nil }
        return AutomationNodeDragTransaction.selection(
            facts: facts, lanes: coveredLanes(), grabbed: (facts.parameter, source),
            range: selection.range, press: press, deleteOnStationary: deleteOnStationary)
    }

}
