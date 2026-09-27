import PorydawCore

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
        hoverY = y
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
        cancelGesture()
        applyPreviewDraft(.empty)
        publishPreview()
        if let facts = frozenFacts(modifiers: .init()) {
            let projection = makeProjection(facts: facts, camera: liveCamera())
            if let lane = laneProjection(facts: facts, projection: projection),
               (!isPencilMode || projection.markersVisible()),
               let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius),
               (!isPencilMode || projection.cell(atRawTick: projection.rawTick(atX: x))
                   .contains(Double(hit.tick))),
               let source = source(of: hit.identity, facts: facts),
               commit(AutomationNodeResolver.deletions(
                   revision: facts.revision,
                   [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                       snapshot: facts.snapshot,
                                                       ticks: [source.tick])])) {
                refreshFromDocument()
                return true
            }
        }
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
        if selection != nil {
            applyTimeSelection(nil)
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
