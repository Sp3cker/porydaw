import PorydawAppPresentation
import PorydawCore
import PorydawDocument
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
        guard let viewport else { return nil }
        return facts(parameter: activeParameter, modifiers: modifiers, viewport: viewport)
    }

    func facts(
        parameter: AutomationParameter, modifiers: AutomationModifiers,
        viewport: DocumentViewport
    ) -> AutomationFrozenFacts {
        let snapshot = projectionFacts.snapshot(parameter, session: viewport.session)
        return AutomationFrozenFacts(
            parameter: parameter, snapshot: snapshot,
            camera: viewport.camera.snapshot, selection: selection,
            modifiers: modifiers,
            songEndTick: viewport.session.timeline.lengthTicks)
    }

    /// The projection a live gesture maps through: the camera it froze at press.
    var gestureCamera: EditorCamera { frozenCamera ?? liveCamera() }

    func liveCamera() -> EditorCamera {
        guard let viewport else {
            return EditorCamera(
                ticksPerBeat: 24, lengthTicks: nil, viewportWidth: 0, rollHeight: 0,
                limits: GridCameraPolicy.limits(
                    baseFontPx: GridCameraPolicy.seedBaseFontPx))
        }
        return viewport.camera
    }

    func makeProjection(
        facts: AutomationFrozenFacts,
        camera: EditorCamera
    ) -> AutomationProjection {
        let bounds = AutomationPlotBounds(
            width: plotWidth, height: plotHeight,
            devicePixelRatio: devicePixelRatio)
        if let viewport {
            return projectionFacts.projection(
                snapshot: facts.snapshot, viewport: viewport,
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

    func laneProjection(
        facts: AutomationFrozenFacts,
        projection: AutomationProjection
    ) -> AutomationLaneProjection? {
        guard session != nil else { return nil }
        return projection.project(facts.snapshot, selection: selection, usedTracks: usedTracks())
    }

    func usedTracks() -> Set<Int> {
        guard let session else { return [] }
        return Set(0..<session.document.engineTracks.usedTrackCount)
    }

    func xForTick(_ tick: Tick) -> Double {
        guard let viewport else { return 0 }
        return viewport.camera.viewX(tick: Double(tick), dpr: devicePixelRatio)
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
        syncModel(tabs, values, matches: { $0.matches($1) })
    }

    /// Publishes the value labels, ghost names and active node handles.
    func publishContent(_ viewport: DocumentViewport?) {
        guard let viewport, let lane = projection else {
            syncRetained(ghostNameLabels, [SceneTextValue](), make: SceneText.init, update: { $0.update($1) })
            syncRetained(valueLabels, [SceneTextValue](), make: SceneText.init, update: { $0.update($1) })
            syncNodes([])
            return
        }
        let projection = makeProjection(
            facts: facts(parameter: lane.parameter, modifiers: .init(), viewport: viewport),
            camera: viewport.camera)
        publishValueAxis(lane)
        publishGhostNames(viewport)
        syncNodes(nodeHandles(lane, projection: projection))
    }

    /// Reprojects the active and pinned lanes for a horizontal camera scroll
    /// without rebuilding the value axis or document-derived selector state.
    @QtIgnored
    public func refreshHorizontalProjection() {
        guard let viewport, projection != nil else { return }
        let facts = facts(parameter: activeParameter, modifiers: .init(), viewport: viewport)
        let cameraProjection = makeProjection(facts: facts, camera: viewport.camera)
        guard let lane = laneProjection(facts: facts, projection: cameraProjection) else {
            return
        }
        projection = lane
        publishGhostNames(viewport)
        syncNodes(nodeHandles(lane, projection: cameraProjection))
        publishOverlays()
    }

    /// The value axis: one rule at each scale value, with its label at the plot's
    /// left edge and curve-true height.
    func publishValueAxis(_ lane: AutomationLaneProjection) {
        let height = captionMetrics?.height ?? fontPx(baseFontPx, 1)
        let pad = typography.space(.one)
        let font = typography.caption.qmlFont
        var labels: [SceneTextValue] = []
        for label in lane.scaleLabels {
            let width = max(
                fontPx(baseFontPx, 2),
                (captionMetrics?.advance(label.text) ?? 0).rounded())
            let y = min(max(0, label.y - height / 2), max(0, plotHeight - height))
            labels.append(
                SceneTextValue(
                    rect: (Double(pad), y.rounded(), width, height),
                    text: label.text, color: palette.primaryText,
                    font: font))
        }
        syncRetained(valueLabels, labels, make: SceneText.init, update: { $0.update($1) })
    }

    /// The active parameter's nodes and origin phantom, minus those a live draw
    /// replaces; markers draw only at a zoom that can show them.
    func nodeHandles(
        _ lane: AutomationLaneProjection,
        projection: AutomationProjection
    ) -> [AutomationNodeValue] {
        guard projection.markersVisible() else { return [] }
        let paint = nodePaint
        let replaced = previewEdit.flatMap { edit in
            edit.parameter == lane.parameter ? edit.tickBegin...edit.tickEnd : nil
        }
        var values: [AutomationNodeValue] = []
        if let phantom = lane.originPhantom, !(replaced?.contains(phantom.point.tick) ?? false) {
            values.append(
                nodeHandle(
                    phantom.point, paint: paint, parameter: lane.parameter,
                    projection: projection, phantom: true))
        }
        let radius = max(paint.nodeRadius, paint.ringRadius) + paint.outlineWidth
        let begin = automationPartitionIndex(lane.points) { $0.x < -radius }
        let end = automationPartitionIndex(lane.points) { $0.x <= plotWidth + radius }
        for point in lane.points[begin..<end] where !(replaced?.contains(point.tick) ?? false) {
            values.append(
                nodeHandle(
                    point, paint: paint, parameter: lane.parameter,
                    projection: projection, phantom: false))
        }
        return values
    }

    /// Republishes only the active node handles, for a live draw's coverage change.
    func syncActiveNodes() {
        guard let viewport, let lane = projection else { return }
        let cameraProjection = makeProjection(
            facts: facts(parameter: lane.parameter, modifiers: .init(), viewport: viewport),
            camera: viewport.camera)
        syncNodes(nodeHandles(lane, projection: cameraProjection))
    }

    func nodeHandle(
        _ point: AutomationProjectedPoint, paint: AutomationNodePaint,
        parameter: AutomationParameter,
        projection: AutomationProjection,
        phantom: Bool
    ) -> AutomationNodeValue {
        var node = AutomationNodeValue()
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
        node.hovered =
            hover?.hasPoint == true && hover?.parameter == parameter
            && hover?.tick == point.tick
        node.projected = point.projected
        node.phantom = phantom
        node.identity = point.identity
        return node
    }

    func ghostProjections(_ viewport: DocumentViewport) -> [AutomationLaneProjection] {
        ghostParameters.compactMap { ghost in
            let facts = facts(parameter: ghost, modifiers: .init(), viewport: viewport)
            return makeProjection(facts: facts, camera: viewport.camera)
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
