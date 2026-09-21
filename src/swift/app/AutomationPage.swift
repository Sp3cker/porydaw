import Foundation
import PorydawCore

// The Automation drawer page owner: document-bound parameter selection, the
// explicit per-parameter time selection, hover/preview/prompt state, the frozen
// gesture dispatch, and the publication diagnostics the drawer seam reads.
//
// It is deliberately not attached by `ApplicationSession` yet: task 6b owns
// production attachment, QML input delivery and rendering. Everything the QML
// bridge will read is published here as plain Swift values.
//
// Context rule: a stopped transport consumes the session's edit cursor and a
// playing one consumes the shared playhead sample the owner is handed. This page
// owns no clock, no camera and no playhead line.

/// Published constants, mirroring the production automation pane.
public enum AutomationPagePolicy {
    /// The base font seed of the grid, which is internal to this module.
    public static let seedBaseFontPx: Double = 13
    /// The pointer travel that turns a press into a drag.
    public static let dragDistance: Double = 10
    /// The ghost label's separator between the curve name and its event count.
    public static let ghostSeparator = " · "
    public static let noTrackMessage = "No track selected"
}

/// One hover over the plot: the node under the pointer, or the background tick
/// with the value the lane holds there.
public struct AutomationHover: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let tick: Tick
    public let value: Int?
    public let text: String
    public let hasPoint: Bool
}

@MainActor
public final class AutomationPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = "qrc:/porydaw/drawer/AutomationPage.qml"

    public let sectionKind: DrawerSectionKind = .automation
    public var contentUrl: String { Self.contentUrl }
    /// Production's `defaultAutomationHeight`: a fifth of the host, clamped by
    /// the section minimum and the piano-roll reserve.
    public private(set) var bodyPolicy: EditorDrawerBodyPolicy
    /// The container's follow-scroll gate: a stroke, drag, hover or prompt is an
    /// active interaction.
    public var interactionActive: Bool { gesture != nil || prompt != nil || hover != nil }

    // MARK: Published body facts

    public private(set) var plotWidth: Double = 0
    public private(set) var plotHeight: Double = 0
    public private(set) var devicePixelRatio: Double = 1
    public private(set) var baseFontPx: Double = AutomationPagePolicy.seedBaseFontPx
    public private(set) var geometry = AutomationPlotGeometry(
        baseFontPx: AutomationPagePolicy.seedBaseFontPx)
    /// The catalog's selector labels, Tempo last.
    public private(set) var parameterLabels: [String] = []
    public private(set) var activeParameterIndex = 0
    /// The active parameter: Tempo always, another catalog parameter only while a
    /// track is selected.
    public private(set) var activeParameter: AutomationParameter = .tempo
    public private(set) var rows: [AutomationRow] = []
    public private(set) var projection: AutomationLaneProjection?
    public private(set) var scaleLabels: [AutomationScaleLabel] = []
    /// Empty while a parameter is presented; the missing-track message otherwise.
    public private(set) var plotMessage = AutomationPagePolicy.noTrackMessage
    /// Every catalog parameter whose explicit selection covers written events.
    public private(set) var selectedParameters: [AutomationParameter] = []
    /// The explicit ghost pins that still carry events.
    public private(set) var ghostParameters: [AutomationParameter] = []
    public private(set) var ghostLabels: [String] = []
    public private(set) var selection: AutomationTimeSelection?
    public private(set) var hover: AutomationHover?
    /// The live gesture draft: points only, never a document write.
    public private(set) var previewPoints: [AutomationLanePoint] = []
    public private(set) var previewText = ""
    public private(set) var prompt: AutomationPromptTransaction?
    /// The effective editing context: the shared playhead while playing, the
    /// session's edit cursor while stopped.
    public private(set) var contextTick: Tick = 0
    public private(set) var contextValue: Int?
    public private(set) var playing = false
    /// The shared pencil tool's state, owned by the window's edit commands.
    public var isPencilMode = false

    // MARK: Diagnostics

    /// Distinct static-content rebuilds: rows, active curve, labels.
    public private(set) var contentBuildCount: UInt64 = 0
    /// Rebuilds a selection change alone caused.
    public private(set) var selectionBuildCount: UInt64 = 0
    /// Hover publications.
    public private(set) var hoverBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    public private(set) var playheadPresentationCount: UInt64 = 0
    /// Presentations that moved the effective context.
    public private(set) var contextChangeCount: UInt64 = 0
    /// The playing tick the last presentation carried.
    public private(set) var presentedTick: Tick = 0

    // MARK: Check-facing state

    public var hasGesture: Bool { gesture != nil }
    public var hasPrompt: Bool { prompt != nil }
    public var isDraggingNodes: Bool { if case .node = gesture { return true }; return false }
    public var isSweeping: Bool { if case .sweep = gesture { return true }; return false }
    public var isPainting: Bool { if case .pencil = gesture { return true }; return false }
    public var laneCount: Int { projection?.eventCount ?? 0 }
    public var hasClipboard: Bool { clipboard.clip != nil }
    public var frozenRevision: UInt64? { frozen?.revision }

    private enum Gesture {
        case pencil(AutomationPencilTransaction)
        case sweep(AutomationSweepTransaction)
        case node(AutomationNodeDragTransaction)
        case phantom(AutomationPhantomDragTransaction)
    }

    private weak var session: DocumentSession?
    private var gesture: Gesture?
    private var frozen: AutomationFrozenFacts?
    private var ghostPins: Set<AutomationParameter> = []
    private var clipboard = AutomationClipboardTransaction()
    private var lastPresentation: (tick: Tick, playing: Bool)?

    public init(baseFontPx: Double = AutomationPagePolicy.seedBaseFontPx) {
        bodyPolicy = EditorDrawerBodyPolicy { hostHeight, metrics in
            let minimum = min(hostHeight, metrics.minimumBody)
            let maximum = max(minimum, metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
            return min(max(hostHeight / 5, minimum), maximum)
        }
        self.baseFontPx = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : AutomationPagePolicy.seedBaseFontPx
        geometry = AutomationPlotGeometry(baseFontPx: self.baseFontPx)
    }

    /// Installs the document owner. Called before the container attaches the
    /// page, so no publication precedes the session it reads.
    public func attach(session: DocumentSession) {
        self.session = session
        rebuildContent()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    public func detach() {
        cancelSectionInteraction()
        session = nil
        projection = nil
        rows = []
        selection = nil
        selectedParameters = []
        ghostPins = []
        ghostParameters = []
        ghostLabels = []
        clipboard.clear()
    }

    /// The page body's own facts, pushed by the production QML as it lays out.
    public func configureBody(width: Double, height: Double, devicePixelRatio: Double,
                              baseFontPx: Double) {
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : AutomationPagePolicy.seedBaseFontPx
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let fontChanged = nextFont != self.baseFontPx
        let changed = fontChanged || nextWidth != plotWidth || nextHeight != plotHeight
            || nextDpr != self.devicePixelRatio
        plotWidth = nextWidth
        plotHeight = nextHeight
        self.devicePixelRatio = nextDpr
        if fontChanged {
            self.baseFontPx = nextFont
            geometry = AutomationPlotGeometry(baseFontPx: nextFont)
        }
        if changed { rebuildContent() }
    }

    // MARK: Refresh

    /// Document, Undo/Redo, track or history publication: a frozen interaction
    /// whose revision no longer holds cancels, then content rebuilds.
    public func refreshFromDocument() {
        guard let session else { return }
        if let frozen, frozen.revision != session.document.revision {
            cancelSectionInteraction()
        }
        rebuildContent()
    }

    /// Camera-only publication: the same points at new plot positions.
    public func refreshCamera() {
        guard session != nil else { return }
        rebuildContent()
    }

    /// One shared-playhead presentation, delivered by the shared owner's fan-out.
    /// Movement re-publishes the effective context and rebuilds nothing: the
    /// automation pane draws no playhead overlay.
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard session != nil else { return }
        let resolved = Tick(max(0, tick).rounded())
        guard lastPresentation?.tick != resolved || lastPresentation?.playing != playing else {
            return
        }
        lastPresentation = (resolved, playing)
        playheadPresentationCount &+= 1
        self.playing = playing
        if playing { presentedTick = resolved }
        publishContext()
    }

    // MARK: Parameter and selection state

    /// View-only parameter switch: the document, revision, history, edit cursor,
    /// track and explicit selection are untouched, and an open interaction ends
    /// synchronously first.
    @discardableResult
    public func activateParameter(index: Int) -> Bool {
        guard session != nil, index != activeParameterIndex,
              index >= 0, index < AutomationCatalog.count else { return false }
        cancelSectionInteraction()
        activeParameterIndex = index
        rebuildContent()
        return true
    }

    @discardableResult
    public func activateParameter(_ parameter: AutomationParameter) -> Bool {
        guard let index = AutomationCatalog.index(of: parameter, track: activeTrack() ?? 0) else {
            return false
        }
        return activateParameter(index: index)
    }

    /// Explicit ghost pins: a pinned parameter's curve paints behind the active
    /// one while it still carries events.
    @discardableResult
    public func toggleGhostParameter(index: Int) -> Bool {
        guard session != nil, index >= 0, index < AutomationCatalog.count,
              let parameter = AutomationCatalog.parameter(at: index, track: activeTrack() ?? 0)
        else { return false }
        if index == activeParameterIndex {
            // The active parameter owns every pin: toggling it clears them all,
            // and does nothing while nothing is pinned.
            guard !ghostPins.isEmpty else { return false }
            ghostPins = []
        } else if parameter.isTempo || eventCount(of: parameter) != 0 {
            if !ghostPins.insert(parameter).inserted { ghostPins.remove(parameter) }
        } else {
            return false
        }
        rebuildContent()
        return true
    }

    /// The explicit time selection. Setting it clears nothing else, and a
    /// parameter switch never discards it.
    public func applyTimeSelection(_ selection: AutomationTimeSelection?) {
        guard self.selection != selection else { return }
        self.selection = selection
        rebuildContent(selectionOnly: true)
    }

    public func clearTimeSelection() { applyTimeSelection(nil) }

    /// The selection a band over `[first, last)` publishes for the parameters it
    /// covered, defaulting to the active one.
    public func selectRange(from first: Tick, to last: Tick,
                            lanes: Set<AutomationParameter>? = nil) {
        guard last > first else {
            clearTimeSelection()
            return
        }
        let covered = lanes ?? Set([activeParameter])
        applyTimeSelection(AutomationTimeSelection(
            range: TimeRange(startTick: first, endTick: last), scope: .lanes,
            lanes: covered, tempo: covered.contains(.tempo)))
    }

    // MARK: Frozen gestures

    /// One press: the hover clears, then the pointer grabs a node, grabs the
    /// projected origin node, paints with the pencil, or starts a sweep.
    @discardableResult
    public func pointerPress(x: Double, y: Double,
                             modifiers: AutomationModifiers = .init()) -> Bool {
        pointerLeave()
        guard let facts = frozenFacts(modifiers: modifiers),
              let lane = laneProjection(facts: facts) else { return false }
        cancelGesture()
        // The gesture's inputs are frozen for its whole life: motion, release
        // and cancellation all read this one revision.
        frozen = facts
        let projection = makeProjection(facts: facts)
        if let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius),
           let source = source(of: hit.identity, facts: facts) {
            let deleteOnStationary = !modifiers.shift
            gesture = .node(selectedNodesDrag(facts: facts, hit: hit, press: (x, y),
                                              deleteOnStationary: deleteOnStationary)
                ?? AutomationNodeDragTransaction.single(
                    facts: facts, source: source, press: (x, y),
                    deleteOnStationary: deleteOnStationary))
            publishPreview()
            return true
        }
        if !isPencilMode, let phantom = phantomHit(lane: lane, x: x, y: y),
           let source = source(of: phantom.point.identity, facts: facts) {
            gesture = .phantom(AutomationPhantomDragTransaction(facts: facts, source: source,
                                                               press: (x, y)))
            publishPreview()
            return true
        }
        if isPencilMode {
            let continuous = Double(projection.value(atY: y, metadata: facts.metadata))
            let first = AutomationPencilTransaction.Sample(
                rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
                point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init()),
                continuousValue: continuous)
            guard let stroke = AutomationPencilTransaction(
                facts: facts, firstSample: first,
                firstCell: projection.cell(atRawTick: projection.rawTick(atX: x)),
                clockTicks: projection.snapPolicy.clockTicks) else { return false }
            gesture = .pencil(stroke)
        } else {
            gesture = .sweep(AutomationSweepTransaction(
                facts: facts, mode: modifiers.shift ? .ramp : .drag,
                mapped: mappedPoint(x: x, y: y, facts: facts, modifiers: modifiers),
                rawTick: projection.rawTick(atX: x), pressX: x, pressY: y))
        }
        publishPreview()
        return true
    }

    /// One move: with no gesture this republishes the hover; with a gesture it
    /// updates the draft and never touches the document.
    @discardableResult
    public func pointerMove(x: Double, y: Double, modifiers: AutomationModifiers = .init(),
                            pressed: Bool = true) -> Bool {
        guard session != nil, let facts = frozen ?? frozenFacts(modifiers: modifiers) else {
            return false
        }
        let projection = makeProjection(facts: facts)
        guard let gesture else {
            guard !pressed else { return false }
            updateHover(x: x, y: y, facts: facts)
            return true
        }
        switch gesture {
        case let .node(transaction):
            var transaction = transaction
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: modifiers.shift,
                activationDistance: geometry.nodeDragActivationDistance)
            if update.phase != .pending {
                _ = transaction.update(update, mapped: mappedPoint(
                    x: update.effectiveX, y: update.effectiveY, facts: facts,
                    modifiers: modifiers))
            }
            self.gesture = .node(transaction)
        case let .phantom(transaction):
            var transaction = transaction
            let update = transaction.drag.update(
                x: x, y: y, shiftHeld: modifiers.shift,
                activationDistance: geometry.nodeDragActivationDistance)
            _ = transaction.update(update, mappedValue: projection.value(
                atY: update.effectiveY, metadata: facts.metadata))
            self.gesture = .phantom(transaction)
        case let .sweep(transaction):
            var transaction = transaction
            update(sweep: &transaction, x: x, y: y, modifiers: modifiers, facts: facts,
                   projection: projection, activate: pressed)
            self.gesture = .sweep(transaction)
        case let .pencil(transaction):
            var transaction = transaction
            update(pencil: &transaction, x: x, y: y, modifiers: modifiers, facts: facts,
                   projection: projection)
            self.gesture = .pencil(transaction)
        }
        publishPreview()
        return true
    }

    /// One release: the frozen draft resolves into at most one commit.
    @discardableResult
    public func pointerRelease(x: Double, y: Double,
                               modifiers: AutomationModifiers = .init()) -> Bool {
        guard let session, let facts = frozen, let gesture else { return false }
        self.gesture = nil
        self.frozen = nil
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
                committed = commit(AutomationNodeResolver.moves([
                    AutomationNodeResolver.LaneMoves(facts, transaction.moves)
                ]))
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
            let projection = makeProjection(facts: facts)
            if transaction.mode == .drag, !transaction.slopExceeded {
                // A press that never travelled parks the edit cursor instead.
                session.editCursor = projection.tick(atX: transaction.pressX, fine: false)
            } else if let edit = transaction.finish(fine: modifiers.fine, projection: projection) {
                committed = AutomationCommit.apply(edit, in: session.document)
            }
        }
        previewPoints = []
        previewText = ""
        if committed { refreshFromDocument() } else { publishContext() }
        return committed
    }

    public func pointerLeave() {
        guard hover != nil else { return }
        hover = nil
        hoverBuildCount &+= 1
    }

    /// The page's local Escape: a prompt, a frozen gesture or a hover claims it.
    public func handleEscape() -> Bool {
        if prompt != nil || gesture != nil {
            cancelSectionInteraction()
            return true
        }
        guard hover != nil else { return false }
        pointerLeave()
        return true
    }

    /// Ends every interaction the page owns without committing anything.
    public func cancelSectionInteraction() {
        cancelGesture()
        prompt = nil
        previewPoints = []
        previewText = ""
        pointerLeave()
    }

    // MARK: Prompt and commands

    /// `Set Value` on a node, or the empty-lane insertion prompt. Opening it
    /// writes nothing.
    @discardableResult
    public func openPrompt(tick: Tick, value: Int) -> Bool {
        guard let facts = frozenFacts(modifiers: .init()) else { return false }
        let occupants = facts.occupants(at: tick)
        prompt = AutomationPromptTransaction(facts: facts,
                                             anchor: AutomationLanePoint(tick: tick, value: value),
                                             source: occupants.last,
                                             forExistingNode: !occupants.isEmpty,
                                             metadata: facts.metadata)
        guard prompt != nil else { return false }
        frozen = facts
        return true
    }

    /// The prompt's acceptance: one commit, or nothing when it changes nothing.
    @discardableResult
    public func acceptPrompt(displayedValue: Int) -> Bool {
        guard let session, let prompt else { return false }
        self.prompt = nil
        frozen = nil
        var committed = false
        switch prompt.outcome(displayed: displayedValue) {
        case .none:
            break
        case let .move(move):
            committed = commit(AutomationNodeResolver.moves([
                AutomationNodeResolver.LaneMoves(prompt.facts, [move])
            ]))
        case let .insert(edit):
            committed = AutomationCommit.apply(edit, in: session.document)
        }
        if committed { refreshFromDocument() } else { publishContext() }
        return committed
    }

    public func cancelPrompt() { prompt = nil }

    /// Delete every occurrence at the given ticks of the active parameter.
    @discardableResult
    public func deletePoints(at ticks: [Tick]) -> Bool {
        guard !ticks.isEmpty, let facts = frozenFacts(modifiers: .init()),
              commit(AutomationNodeResolver.deletions(
                  revision: facts.revision,
                  [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                      snapshot: facts.snapshot, ticks: ticks)]))
        else { return false }
        refreshFromDocument()
        return true
    }

    /// Delete every node the explicit selection covers.
    @discardableResult
    public func deleteSelectedNodes() -> Bool {
        guard let selection, selection.isActive,
              let plan = AutomationRangeEditor.deletion(range: selection.range,
                                                        lanes: coveredLanes()),
              commit(plan) else { return false }
        refreshFromDocument()
        return true
    }

    /// The selection's semantic clipboard: copy, cut and paste through the
    /// existing Swift payload. The native pasteboard is never touched, and an
    /// automation scope gathers no notes, so the duration argument is inert.
    @discardableResult
    public func copyTimeSelection() -> Bool {
        guard let session, let selection, selection.isActive else { return false }
        return clipboard.copy(range: selection.range, scope: selectionScope(selection),
                              from: session.document, unterminatedDuration: 1)
    }

    @discardableResult
    public func cutTimeSelection() -> Bool {
        guard let session, let selection, selection.isActive,
              clipboard.cut(range: selection.range, scope: selectionScope(selection),
                            from: session.document, unterminatedDuration: 1) else { return false }
        refreshFromDocument()
        return true
    }

    @discardableResult
    public func pasteTimeSelection(at cursor: Tick) -> Tick? {
        guard let session, let track = activeTrack() else { return nil }
        let next = clipboard.paste(at: cursor, selectedTrack: track, into: session.document)
        if next != nil { refreshFromDocument() }
        return next
    }

    // MARK: Internals

    private func commit(_ plan: AutomationDocumentPlan?) -> Bool {
        guard let session, let plan else { return false }
        return AutomationCommit.apply(plan, in: session.document)
    }

    private func shiftSelection(by delta: Int64) {
        guard var moved = selection else { return }
        let start = TimeDefaults.shiftTickClamped(moved.range.startTick, by: delta)
        let end = TimeDefaults.shiftTickClamped(moved.range.endTick, by: delta)
        guard end > start else { return }
        moved.range = TimeRange(startTick: start, endTick: end)
        selection = moved
    }

    private func selectionScope(_ selection: AutomationTimeSelection) -> TimeScope {
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
    private func coveredLanes()
        -> [(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot)] {
        guard let session else { return [] }
        return rows.compactMap { row in
            guard row.coversNodes, row.selectionHasEvents else { return nil }
            return (row.parameter, AutomationLaneSnapshot(parameter: row.parameter,
                                                          in: session.document,
                                                          songEndTick: session.timeline.lengthTicks))
        }
    }

    private func selectedNodesDrag(facts: AutomationFrozenFacts, hit: AutomationProjectedPoint,
                                   press: (x: Double, y: Double), deleteOnStationary: Bool)
        -> AutomationNodeDragTransaction? {
        guard let selection, selection.isActive,
              row(facts.parameter)?.coversNodes == true, selection.range.contains(hit.tick),
              let source = source(of: hit.identity, facts: facts) else { return nil }
        return AutomationNodeDragTransaction.selection(
            facts: facts, lanes: coveredLanes(), grabbed: (facts.parameter, source),
            range: selection.range, press: press, deleteOnStationary: deleteOnStationary)
    }

    private func updateHover(x: Double, y: Double, facts: AutomationFrozenFacts) {
        guard let lane = laneProjection(facts: facts) else { return }
        let next: AutomationHover
        if let hit = lane.hitTest(x: x, y: y, radius: geometry.pointHitRadius) {
            next = AutomationHover(parameter: facts.parameter, tick: hit.tick, value: hit.value,
                                   text: facts.metadata.valueText(hit.value), hasPoint: true)
        } else {
            // The background tick is the fine lattice, or the insert cell while
            // the pencil is armed; the readout is the value the lane holds there.
            let projection = makeProjection(facts: facts)
            let tick = isPencilMode
                ? projection.cell(atRawTick: projection.rawTick(atX: x)).tickBegin
                : projection.tick(atX: x, fine: true)
            let held = lane.heldValue(at: tick)
            next = AutomationHover(parameter: facts.parameter, tick: tick, value: held,
                                   text: held.map(facts.metadata.valueText) ?? "", hasPoint: false)
        }
        guard next != hover else { return }
        hover = next
        hoverBuildCount &+= 1
    }

    private func update(sweep transaction: inout AutomationSweepTransaction, x: Double, y: Double,
                        modifiers: AutomationModifiers, facts: AutomationFrozenFacts,
                        projection: AutomationProjection, activate: Bool) {
        if transaction.mode == .ramp {
            transaction.updateRamp(mapped: mappedPoint(x: x, y: y, facts: facts,
                                                       modifiers: modifiers))
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
                                               modifiers: modifiers),
                           first: first, last: last, rawTick: rawTick, fine: modifiers.fine,
                           projection: projection)
    }

    private func update(pencil transaction: inout AutomationPencilTransaction, x: Double, y: Double,
                        modifiers: AutomationModifiers, facts: AutomationFrozenFacts,
                        projection: AutomationProjection) {
        let freehand = modifiers.snapValue && !modifiers.shift
        let locking = modifiers.shift && !modifiers.snapValue
        let continuous = transaction.sampleValue(
            logicalX: x, logicalY: y, locking: locking, freehand: freehand,
            verticalSlopDistance: geometry.nodeDragActivationDistance, plotHeight: plotHeight)
        let sample = AutomationPencilTransaction.Sample(
            rawTick: projection.rawTick(atX: x), logicalX: x, logicalY: y,
            point: mappedPoint(x: x, y: y, facts: facts, modifiers: .init()),
            continuousValue: continuous)
        if freehand {
            _ = transaction.applyFreehandSegment(sample)
        } else {
            _ = transaction.applySnappedSegment(
                sample, cells: projection.cellsCrossed(from: transaction.previousLogicalX, to: x))
        }
    }

    private func mappedPoint(x: Double, y: Double, facts: AutomationFrozenFacts,
                             modifiers: AutomationModifiers) -> AutomationLanePoint {
        let projection = makeProjection(facts: facts)
        return AutomationLanePoint(
            tick: projection.tick(atX: x, fine: modifiers.fine),
            value: facts.metadata.snappedValue(
                projection.value(atY: y, metadata: facts.metadata), snapValue: modifiers.snapValue,
                plotHeight: plotHeight, neutralSnapRadius: geometry.neutralSnapRadius))
    }

    private func phantomHit(lane: AutomationLaneProjection, x: Double,
                            y: Double) -> AutomationOriginPhantom? {
        guard let phantom = lane.originPhantom else { return nil }
        let dy = phantom.point.y - y
        return x * x + dy * dy <= geometry.pointHitRadius * geometry.pointHitRadius
            ? phantom : nil
    }

    private func cancelGesture() {
        gesture = nil
        frozen = nil
    }

    private func publishPreview() {
        switch gesture {
        case let .sweep(transaction): previewPoints = transaction.preview
        case let .pencil(transaction): previewPoints = transaction.preview.points
        case let .node(transaction): previewPoints = transaction.targets.map(\.current)
        case let .phantom(transaction): previewPoints = [transaction.target.current]
        case nil: previewPoints = []
        }
        previewText = previewPoints.last.map { frozen?.metadata.valueText($0.value) ?? "" } ?? ""
    }

    private func activeTrack() -> Int? {
        guard let session, let track = session.selectedTrack, track >= 0 else { return nil }
        return track
    }

    private func row(_ parameter: AutomationParameter) -> AutomationRow? {
        rows.first { $0.parameter == parameter }
    }

    private func eventCount(of parameter: AutomationParameter) -> Int {
        row(parameter)?.eventCount ?? 0
    }

    private func frozenFacts(modifiers: AutomationModifiers) -> AutomationFrozenFacts? {
        guard let session else { return nil }
        let snapshot = AutomationLaneSnapshot(parameter: activeParameter, in: session.document,
                                              songEndTick: session.timeline.lengthTicks)
        return AutomationFrozenFacts(parameter: activeParameter, snapshot: snapshot,
                                     camera: session.camera.snapshot, selection: selection,
                                     modifiers: modifiers,
                                     songEndTick: session.timeline.lengthTicks)
    }

    private func makeProjection(facts: AutomationFrozenFacts) -> AutomationProjection {
        let session = self.session
        let camera = session?.camera ?? EditorCamera(
            ticksPerBeat: 24, lengthTicks: UInt64(facts.songEndTick), viewportWidth: 0,
            rollHeight: 0,
            limits: GridCameraPolicy.limits(baseFontPx: GridCameraPolicy.seedBaseFontPx))
        let snapPolicy = session.map {
            AutomationSnapPolicy(document: $0.document, timeline: $0.timeline,
                                 baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio)
        } ?? AutomationSnapPolicy(baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                                  timeAxis: TimeAxis(), clockTicks: 1)
        return AutomationProjection(
            camera: camera,
            bounds: AutomationPlotBounds(width: plotWidth, height: plotHeight,
                                         devicePixelRatio: devicePixelRatio),
            geometry: geometry, snapPolicy: snapPolicy, songEndTick: facts.songEndTick)
    }

    private func laneProjection(facts: AutomationFrozenFacts) -> AutomationLaneProjection? {
        guard session != nil else { return nil }
        return makeProjection(facts: facts).project(facts.snapshot, selection: selection,
                                                    usedTracks: usedTracks())
    }

    private func usedTracks() -> Set<Int> {
        guard let session else { return [] }
        return Set(0..<session.document.engineTracks.usedTrackCount)
    }

    /// Rebuild the static content: rows, the active curve, labels and ghosts.
    /// `selectionOnly` marks a rebuild a selection change alone caused.
    private func rebuildContent(selectionOnly: Bool = false) {
        guard let session else { return }
        let track = activeTrack()
        activeParameterIndex = min(max(activeParameterIndex, 0), AutomationCatalog.count - 1)
        activeParameter = AutomationCatalog.parameter(at: activeParameterIndex,
                                                      track: track ?? 0) ?? .tempo
        plotMessage = track == nil && !activeParameter.isTempo
            ? AutomationPagePolicy.noTrackMessage : ""
        parameterLabels = AutomationCatalog.parameters(track: track ?? 0)
            .map(AutomationCatalog.tabLabel)
        rows = AutomationRowStack.build(document: session.document, primaryTrack: track,
                                        selection: selection, ready: track != nil,
                                        songEndTick: session.timeline.lengthTicks).visibleRows
        ghostParameters = AutomationCatalog.parameters(track: track ?? 0).filter {
            ghostPins.contains($0) && eventCount(of: $0) != 0
        }
        ghostLabels = ghostParameters.map { ghost in
            let count = eventCount(of: ghost)
            return AutomationCatalog.title(ghost) + AutomationPagePolicy.ghostSeparator
                + (count == 1 ? "1 Event" : "\(count) Events")
        }
        selectedParameters = track.map { selected in
            AutomationCatalog.parameters(track: selected).filter {
                row($0)?.selectionHasEvents ?? false
            }
        } ?? []
        if plotMessage.isEmpty {
            let facts = AutomationFrozenFacts(
                parameter: activeParameter,
                snapshot: AutomationLaneSnapshot(parameter: activeParameter,
                                                 in: session.document,
                                                 songEndTick: session.timeline.lengthTicks),
                camera: session.camera.snapshot, selection: selection,
                modifiers: AutomationModifiers(),
                songEndTick: session.timeline.lengthTicks)
            projection = laneProjection(facts: facts)
        } else {
            projection = nil
        }
        scaleLabels = projection?.scaleLabels ?? []
        contentBuildCount &+= 1
        if selectionOnly { selectionBuildCount &+= 1 }
        publishContext()
    }

    private func publishContext() {
        guard let session else { return }
        let tick = playing ? presentedTick : session.editCursor
        let value = projection?.heldValue(at: tick)
        guard tick != contextTick || value != contextValue else { return }
        contextTick = tick
        contextValue = value
        contextChangeCount &+= 1
    }
}

// MARK: - Source resolution

private func source(of identity: AutomationPointIdentity,
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
