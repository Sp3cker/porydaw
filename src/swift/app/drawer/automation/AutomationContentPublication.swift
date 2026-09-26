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
        let snapPolicy = AutomationSnapPolicy(baseFontPx: baseFontPx,
            devicePixelRatio: devicePixelRatio, timeAxis: TimeAxis(), clockTicks: 1)
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
        return session.camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
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
            syncRects(gridLines, [])
            syncRects(valueLines, [])
            syncTexts(valueLabels, [])
            syncRects(curveRuns, [])
            curveRunSnapshots = []
            syncNodes([])
            syncRects(selectionRects, [])
            return
        }
        let projection = makeProjection(
            facts: facts(parameter: lane.parameter, modifiers: .init(), session: session),
            camera: session.camera)
        publishGrid(session)
        publishValueAxis(lane)
        var runs: [SceneRect] = []
        for ghost in ghostProjections(session) {
            appendCurve(ghost, projection: projection, isGhost: true, into: &runs)
        }
        appendCurve(lane, projection: projection, isGhost: false, into: &runs)
        syncRects(curveRuns, runs)
        curveRunSnapshots = runs
        syncNodes(nodeHandles(lane, projection: projection))
        syncRects(selectionRects, selectionBand(lane, projection: projection))
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
        publishGrid(session)
        var runs: [SceneRect] = []
        for ghost in ghostProjections(session) {
            appendCurve(ghost, projection: cameraProjection, isGhost: true,
                        into: &runs)
        }
        appendCurve(lane, projection: cameraProjection, isGhost: false,
                    into: &runs)
        syncRects(curveRuns, runs)
        curveRunSnapshots = runs
        syncNodes(nodeHandles(lane, projection: cameraProjection))
        syncRects(selectionRects, selectionBand(lane, projection: cameraProjection))
        publishOverlays()
    }

    /// The shared time grid: the roll's own subdivision, beat, fine-beat and bar
    /// lines, through the same grid metrics the roll and the sibling pages use.
    func publishGrid(_ session: DocumentSession) {
        guard plotHeight > 0, plotWidth > 0, projection != nil else {
            syncRects(gridLines, [])
            return
        }
        let camera = session.camera
        let metrics = gridMetrics(session)
        let physicalPixel = max(metrics.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else {
            syncRects(gridLines, [])
            return
        }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [SceneRect] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let color = level == 1 ? palette.gridLineSub1
                : level == 2 ? palette.gridLineSub2 : palette.gridLineSub3
            rects.append(SceneRect(x: xForTick(tick) - stroke / 2, y: 0, width: stroke,
                                   height: plotHeight, fillColor: color,
                                   primitiveName: "automationGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            rects.append(SceneRect(
                x: xForTick(tick) - stroke / 2, y: 0, width: stroke, height: plotHeight,
                fillColor: isBar ? palette.gridLineBar
                    : finest ? palette.gridLineBeatFine : palette.gridLineBeat,
                primitiveName: "automationGrid"))
        }
        syncRects(gridLines, rects)
    }

    /// The value axis: one rule at each scale value, with its label at the plot's
    /// left edge and curve-true height.
    func publishValueAxis(_ lane: AutomationLaneProjection) {
        let stroke = max(1, fontPxF(baseFontPx, 1.0 / 12.0))
        let height = captionMetrics?.height ?? fontPx(baseFontPx, 1)
        let pad = Typography(baseFontPx: Int(baseFontPx.rounded())).space(.one)
        var lines: [SceneRect] = []
        var labels: [SceneText] = []
        for label in lane.scaleLabels {
            lines.append(SceneRect(x: 0, y: (label.y - stroke / 2).rounded(), width: plotWidth,
                                   height: stroke, fillColor: palette.gridLineSub2,
                                   primitiveName: "automationValueRule"))
            let width = max(fontPx(baseFontPx, 2),
                            (captionMetrics?.advance(label.text) ?? 0).rounded())
            let y = min(max(0, label.y - height / 2), max(0, plotHeight - height))
            labels.append(SceneText(rect: (Double(pad), y.rounded(), width, height),
                                    text: label.text, color: palette.primaryText,
                                    font: captionFont))
        }
        syncRects(valueLines, lines)
        syncTexts(valueLabels, labels)
    }

    func appendCurve(_ lane: AutomationLaneProjection, projection: AutomationProjection,
                     isGhost: Bool, into runs: inout [SceneRect]) {
        guard !lane.points.isEmpty else { return }
        let stroke = 2.0
        let ink = palette.automationNodeInk
        let color: String
        if isGhost {
            let channels = PaletteMath.channels(ink)
            color = PaletteMath.hex(r: channels.r, g: channels.g, b: channels.b, a: 128)
        } else {
            color = ink
        }
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

    /// The active parameter's nodes and its projected origin phantom. Node markers
    /// are drawn only at a zoom that can show them, exactly as production's
    /// `nodeMarkersVisible` decides.
    func nodeHandles(_ lane: AutomationLaneProjection,
                             projection: AutomationProjection) -> [AutomationNodeHandle] {
        guard projection.markersVisible() else { return [] }
        let paint = nodePaint
        var values: [AutomationNodeHandle] = []
        if let phantom = lane.originPhantom {
            values.append(nodeHandle(phantom.point, paint: paint, parameter: lane.parameter,
                                     projection: projection, phantom: true))
        }
        let radius = max(paint.nodeRadius, paint.ringRadius) + paint.outlineWidth
        let begin = automationPartitionIndex(lane.points) { $0.x < -radius }
        let end = automationPartitionIndex(lane.points) { $0.x <= plotWidth + radius }
        for point in lane.points[begin..<end] {
            values.append(nodeHandle(point, paint: paint, parameter: lane.parameter,
                                     projection: projection, phantom: false))
        }
        return values
    }

    func nodeHandle(_ point: AutomationProjectedPoint, paint: AutomationNodePaint,
                            parameter: AutomationParameter,
                            projection: AutomationProjection,
                            phantom: Bool) -> AutomationNodeHandle {
        let node = AutomationNodeHandle()
        node.x = phantom ? 0 : projection.x(point.tick)
        node.y = point.y
        node.tick = Double(point.tick)
        node.value = point.value
        node.radius = paint.nodeRadius
        node.ringRadius = paint.ringRadius
        node.outlineWidth = paint.outlineWidth
        node.fillColor = point.projected ? palette.secondaryText : palette.primaryText
        node.outlineColor = palette.noteBorder
        node.ringColor = palette.selectionRing
        node.selected = point.selected
        node.hovered = hover?.hasPoint == true && hover?.parameter == parameter
            && hover?.tick == point.tick
        node.projected = point.projected
        node.phantom = phantom
        node.identity = Self.identityText(point.identity)
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
