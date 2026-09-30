import PorydawCore
import QtBridge

// Automation content publication: the page's session reads and projection
// assembly, plus the tab, grid, value-axis, curve, node and selection-band
// primitives one build publishes. Overlay, prompt, menu and typography
// publication lives in AutomationOverlayPublication.swift.

@MainActor
extension AutomationPage {
    func activeTrack() -> Int? {
        guard let session, let track = session.selectedTrack, track >= 0 else { return nil }
        return track
    }

    func row(_ parameter: AutomationParameter) -> AutomationRow? {
        rows.first { $0.parameter == parameter }
    }

    func eventCount(of parameter: AutomationParameter) -> Int {
        row(parameter)?.eventCount ?? 0
    }

    func frozenFacts(modifiers: AutomationModifiers) -> AutomationFrozenFacts? {
        guard let session else { return nil }
        return facts(parameter: activeParameter, modifiers: modifiers, session: session)
    }

    func facts(parameter: AutomationParameter, modifiers: AutomationModifiers,
                       session: DocumentSession) -> AutomationFrozenFacts {
        let snapshot = projectionFacts.snapshot(parameter, session: session)
        return AutomationFrozenFacts(parameter: parameter, snapshot: snapshot,
                                     camera: session.camera.snapshot, selection: selection,
                                     modifiers: modifiers,
                                     songEndTick: session.timeline.lengthTicks)
    }

    /// The projection a live gesture maps through: the camera it froze at press.
    var gestureCamera: EditorCamera { frozenCamera ?? liveCamera() }

    func liveCamera() -> EditorCamera {
        guard let session else {
            return EditorCamera(ticksPerBeat: 24, lengthTicks: nil, viewportWidth: 0, rollHeight: 0,
                                limits: GridCameraPolicy.limits(
                                    baseFontPx: GridCameraPolicy.seedBaseFontPx))
        }
        return session.camera
    }

    func makeProjection(facts: AutomationFrozenFacts,
                                camera: EditorCamera) -> AutomationProjection {
        let bounds = AutomationPlotBounds(width: plotWidth, height: plotHeight,
                                          devicePixelRatio: devicePixelRatio)
        if let session {
            return projectionFacts.projection(snapshot: facts.snapshot, session: session,
                camera: camera, bounds: bounds, geometry: geometry, font: baseFontPx,
                range: laneRanges[facts.parameter])
        }
        let snapPolicy = AutomationSnapPolicy(grid: RollGrid(), clockTicks: 1)
        return AutomationProjection(
            camera: camera,
            bounds: bounds,
            geometry: geometry, snapPolicy: snapPolicy, songEndTick: facts.songEndTick,
            displayMaximum: AutomationProjection.displayMaximum(
                snapshot: facts.snapshot, range: laneRanges[facts.parameter]))
    }

    func laneProjection(facts: AutomationFrozenFacts,
                                projection: AutomationProjection) -> AutomationLaneProjection? {
        guard session != nil else { return nil }
        return projection.project(facts.snapshot, selection: selection, usedTracks: usedTracks())
    }

    func usedTracks() -> Set<Int> {
        guard let session else { return [] }
        return Set(0..<session.document.engineTracks.usedTrackCount)
    }

    func xForTick(_ tick: Tick) -> Double {
        guard let session else { return 0 }
        return session.camera.viewX(tick: Double(tick), dpr: devicePixelRatio)
    }
    // MARK: Internals: publication


    /// The selector's published tabs: one entry per catalog parameter, with the
    /// active, ghost, shared-selection and event-count facts the strip renders.
    func publishTabs(_ parameters: [AutomationParameter]) {
        let values = parameters.enumerated().map { index, parameter -> AutomationTabHandle in
            let tab = AutomationTabHandle()
            tab.index = index
            tab.label = AutomationCatalog.tabLabel(parameter)
            tab.tempo = parameter.isTempo
            tab.active = index == activeParameterIndex
            tab.ghosted = ghostParameters.contains(parameter)
            tab.included = selectedParameters.contains(parameter)
            tab.eventCount = eventCount(of: parameter)
            tab.available = trackAvailable || parameter.isTempo
            return tab
        }
        tabSnapshots = values
        if tabCount != values.count { tabCount = values.count }
        syncTabs(values)
    }

    /// Every drawn primitive of one build.
    func publishContent(_ session: DocumentSession?) {
        guard let session, let lane = projection else {
            syncTexts(ghostNameLabels, [])
            syncTexts(valueLabels, [])
            curveRunSnapshots = []
            syncNodes([])
            return
        }
        let projection = makeProjection(
            facts: facts(parameter: lane.parameter, modifiers: .init(), session: session),
            camera: session.camera)
        publishValueAxis(lane)
        publishGhostNames(session)
        var runs: [SceneRect] = []
        for ghost in ghostProjections(session) {
            appendCurve(ghost, projection: projection, isGhost: true, into: &runs)
        }
        appendCurve(lane, projection: projection, isGhost: false, into: &runs)
        curveRunSnapshots = runs
        syncNodes(nodeHandles(lane, projection: projection))
    }

    /// Reprojects the active and pinned lanes for a horizontal camera scroll
    /// without rebuilding the value axis or document-derived selector state.
    @QtIgnored
    public func refreshHorizontalProjection() {
        guard let session, projection != nil else { return }
        let facts = facts(parameter: activeParameter, modifiers: .init(), session: session)
        let cameraProjection = makeProjection(facts: facts, camera: session.camera)
        guard let lane = laneProjection(facts: facts, projection: cameraProjection) else {
            return
        }
        projection = lane
        publishGhostNames(session)
        var runs: [SceneRect] = []
        for ghost in ghostProjections(session) {
            appendCurve(ghost, projection: cameraProjection, isGhost: true,
                        into: &runs)
        }
        appendCurve(lane, projection: cameraProjection, isGhost: false,
                    into: &runs)
        curveRunSnapshots = runs
        syncNodes(nodeHandles(lane, projection: cameraProjection))
        publishOverlays()
    }

    /// The value axis: one rule at each scale value, with its label at the plot's
    /// left edge and curve-true height.
    func publishValueAxis(_ lane: AutomationLaneProjection) {
        let height = captionMetrics?.height ?? fontPx(baseFontPx, 1)
        let pad = Typography(baseFontPx: Int(baseFontPx.rounded())).space(.one)
        var labels: [SceneText] = []
        for label in lane.scaleLabels {
            let width = max(fontPx(baseFontPx, 2),
                            (captionMetrics?.advance(label.text) ?? 0).rounded())
            let y = min(max(0, label.y - height / 2), max(0, plotHeight - height))
            labels.append(SceneText(rect: (Double(pad), y.rounded(), width, height),
                                    text: label.text, color: palette.primaryText,
                                    font: captionFont))
        }
        syncTexts(valueLabels, labels)
    }

    // Ghost curve ink per ThemePreset.rawValue: automationNodeInk at alpha
    // 128, precomputed; verified by themeColorTableChecks.
    static let ghostCurveInk = ["#80EA3C3C", "#80FF4D47", "#80FF91C3"]

    func appendCurve(_ lane: AutomationLaneProjection, projection: AutomationProjection,
                     isGhost: Bool, into runs: inout [SceneRect]) {
        guard !lane.points.isEmpty else { return }
        let stroke = 2.0
        // Theme-only lookup: the ghost ink is automationNodeInk at alpha 128.
        let color = isGhost ? Self.ghostCurveInk[palette.theme.rawValue] : palette.automationNodeInk
        let name = isGhost ? "automationGhostCurve" : "automationCurve"
        let limit = max(0, plotWidth)
        func x(_ tick: Tick) -> Double { projection.x(tick) }
        func y(_ value: Int) -> Double { projection.y(value, metadata: lane.metadata) }
        for (index, segment) in lane.segments.enumerated() {
            let x0 = min(max(0, x(segment.tickBegin)), limit)
            let x1 = min(max(0, segment.tickEnd.map(x) ?? limit), limit)
            guard x1 >= x0 else { continue }
            let fromY = y(segment.fromValue)
            if x1 > x0 {
                runs.append(SceneRect(x: x0, y: (fromY - stroke / 2).rounded(), width: x1 - x0,
                                      height: stroke, fillColor: color, primitiveName: name))
            }
            let next = index + 1 < lane.segments.count ? lane.segments[index + 1] : nil
            if segment.kind == .step, let next, next.fromValue != segment.fromValue,
               let end = segment.tickEnd, x(end) >= -stroke / 2, x(end) <= limit + stroke / 2 {
                let nextY = y(next.fromValue)
                runs.append(SceneRect(x: (x1 - stroke / 2).rounded(),
                                      y: min(fromY, nextY).rounded(), width: stroke,
                                      height: max(stroke, abs(nextY - fromY)), fillColor: color,
                                      primitiveName: name))
            }
        }
    }

    /// The active parameter's nodes and its projected origin phantom, minus the
    /// ones a live draw replaces. Node markers are drawn only at a zoom that can
    /// show them, exactly as production's `nodeMarkersVisible` decides.
    func nodeHandles(_ lane: AutomationLaneProjection,
                             projection: AutomationProjection) -> [AutomationNodeHandle] {
        guard projection.markersVisible() else { return [] }
        let paint = nodePaint
        let replaced = previewEdit.flatMap { edit in
            edit.parameter == lane.parameter ? edit.tickBegin...edit.tickEnd : nil
        }
        var values: [AutomationNodeHandle] = []
        if let phantom = lane.originPhantom, replaced?.contains(phantom.point.tick) != true {
            values.append(nodeHandle(phantom.point, paint: paint, parameter: lane.parameter,
                                     projection: projection, phantom: true))
        }
        let radius = max(paint.nodeRadius, paint.ringRadius) + paint.outlineWidth
        let begin = automationPartitionIndex(lane.points) { $0.x < -radius }
        let end = automationPartitionIndex(lane.points) { $0.x <= plotWidth + radius }
        for point in lane.points[begin..<end] where replaced?.contains(point.tick) != true {
            values.append(nodeHandle(point, paint: paint, parameter: lane.parameter,
                                     projection: projection, phantom: false))
        }
        return values
    }

    /// Republishes only the active node handles, for a live draw's coverage change.
    func syncActiveNodes() {
        guard let session, let lane = projection else { return }
        let projection = makeProjection(
            facts: facts(parameter: lane.parameter, modifiers: .init(), session: session),
            camera: session.camera)
        syncNodes(nodeHandles(lane, projection: projection))
    }

    func nodeHandle(_ point: AutomationProjectedPoint, paint: AutomationNodePaint,
                            parameter: AutomationParameter,
                            projection: AutomationProjection,
                            phantom: Bool) -> AutomationNodeHandle {
        let node = AutomationNodeHandle()
        // Plot-relative x rides the row, so a zoom's x and scroll land in one frame.
        node.x = phantom ? 0 : point.x
        node.y = point.y
        node.tick = Double(point.tick)
        node.value = point.value
        node.radius = paint.nodeRadius
        node.ringRadius = paint.ringRadius
        node.outlineWidth = paint.outlineWidth
        node.outlineColor = palette.automationNodeInk
        node.ringColor = palette.selectionRing
        node.selected = point.selected
        node.hovered = hover?.hasPoint == true && hover?.parameter == parameter
            && hover?.tick == point.tick
        node.projected = point.projected
        node.phantom = phantom
        node.identity = Self.identityText(point.identity)
        node.refreshSpec()
        return node
    }

    /// The explicit selection's band: a fill over the covered range with the two
    /// edge rules, clamped to the plot.
    func selectionBand(_ lane: AutomationLaneProjection,
                               projection: AutomationProjection) -> [SceneRect] {
        guard let selection, selection.isActive,
              selection.covers(lane.parameter, usedTracks: usedTracks()) else { return [] }
        let limit = max(0, plotWidth)
        let x0 = min(max(0, projection.x(selection.range.startTick)), limit)
        let x1 = min(max(0, projection.x(selection.range.endTick)), limit)
        guard x1 > x0 else { return [] }
        let stroke = 1.0
        return [
            SceneRect(x: x0, y: 0, width: x1 - x0, height: plotHeight,
                      fillColor: palette.selectionFill, primitiveName: "automationSelectionFill"),
            SceneRect(x: x0, y: 0, width: stroke, height: plotHeight,
                      fillColor: palette.selectionEdge, primitiveName: "automationSelectionEdge"),
            SceneRect(x: (x1 - stroke).rounded(), y: 0, width: stroke, height: plotHeight,
                      fillColor: palette.selectionEdge, primitiveName: "automationSelectionEdge"),
        ]
    }

    func ghostProjections(_ session: DocumentSession) -> [AutomationLaneProjection] {
        ghostParameters.compactMap { ghost in
            let facts = facts(parameter: ghost, modifiers: .init(), session: session)
            return makeProjection(facts: facts, camera: session.camera)
                .project(facts.snapshot, selection: selection, usedTracks: usedTracks())
        }
    }
}

/// The page's own paint geometry: the production node radii at the same
/// font-relative factors the interaction geometry resolves.
struct AutomationNodePaint: Equatable, Sendable {
    var nodeRadius: Double
    var ringRadius: Double
    var outlineWidth: Double
}
