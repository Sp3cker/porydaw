import Foundation
import NativeGridTypography
import PorydawCore
import QtBridge

// Automation scene construction and primitive publication. Document and lifecycle
// ownership remain on AutomationPage; this file contains the presentation adapter.

/// The document-derived values produced by one static automation scene build.
/// Applying them remains the page owner's responsibility.
struct AutomationSceneSnapshot {
    struct Active {
        let parameterIndex: Int
        let parameter: AutomationParameter
        let trackAvailable: Bool
        let plotMessage: String
    }

    let active: Active?
    let catalog: [AutomationParameter]
    let parameterLabels: [String]
    let rows: [AutomationRow]
    let ghostParameters: [AutomationParameter]
    let ghostLabels: [String]
    let selectedParameters: [AutomationParameter]
    let projection: AutomationLaneProjection?
    let scaleLabels: [AutomationScaleLabel]

    static let detached = Self(
        active: nil, catalog: [], parameterLabels: [], rows: [],
        ghostParameters: [], ghostLabels: [], selectedParameters: [],
        projection: nil, scaleLabels: [])

    @MainActor
    static func build(
        session: DocumentSession,
        cache: AutomationProjectionCache,
        selectedTrack: Int?,
        camera: EditorCamera,
        activeParameterIndex: Int,
        ghostPins: Set<AutomationParameter>,
        selection: AutomationTimeSelection?,
        plotWidth: Double,
        plotHeight: Double,
        devicePixelRatio: Double,
        baseFontPx: Double,
        geometry: AutomationPlotGeometry,
        laneRanges: [AutomationParameter: Int] = [:]
    ) -> Self {
        let document = session.document
        let track = selectedTrack.flatMap { $0 >= 0 ? $0 : nil }
        let parameterIndex = min(max(activeParameterIndex, 0), AutomationCatalog.count - 1)
        let parameter = AutomationCatalog.parameter(at: parameterIndex, track: track ?? 0) ?? .tempo
        let trackAvailable = track != nil
        let plotMessage = track == nil && !parameter.isTempo
            ? AutomationPagePolicy.noTrackMessage : ""
        let catalog = AutomationCatalog.parameters(track: track ?? 0)
        let rows = cache.rows(session: session, track: track, selection: selection,
                              ready: track != nil).visibleRows
        func row(_ parameter: AutomationParameter) -> AutomationRow? {
            rows.first { $0.parameter == parameter }
        }
        func eventCount(of parameter: AutomationParameter) -> Int {
            row(parameter)?.eventCount ?? 0
        }
        let ghostParameters = catalog.filter {
            ghostPins.contains($0) && eventCount(of: $0) != 0
        }
        let ghostLabels = ghostParameters.map { ghost in
            let count = eventCount(of: ghost)
            return AutomationCatalog.title(ghost) + AutomationPagePolicy.ghostSeparator
                + (count == 1 ? "1 Event" : "\(count) Events")
        }
        let selectedParameters = track.map { selected in
            AutomationCatalog.parameters(track: selected).filter {
                row($0)?.selectionHasEvents ?? false
            }
        } ?? []

        let laneProjection: AutomationLaneProjection?
        if plotMessage.isEmpty {
            let snapshot = cache.snapshot(parameter, session: session)
            let projection = cache.projection(snapshot: snapshot, session: session, camera: camera,
                bounds: AutomationPlotBounds(width: plotWidth, height: plotHeight,
                                             devicePixelRatio: devicePixelRatio),
                geometry: geometry, font: baseFontPx, range: laneRanges[parameter])
            laneProjection = projection.project(
                snapshot, selection: selection,
                usedTracks: Set(0..<document.engineTracks.usedTrackCount))
        } else {
            laneProjection = nil
        }

        return Self(
            active: Active(
                parameterIndex: parameterIndex, parameter: parameter,
                trackAvailable: trackAvailable, plotMessage: plotMessage),
            catalog: catalog,
            parameterLabels: catalog.map(AutomationCatalog.tabLabel),
            rows: rows,
            ghostParameters: ghostParameters,
            ghostLabels: ghostLabels,
            selectedParameters: selectedParameters,
            projection: laneProjection,
            scaleLabels: laneProjection?.scaleLabels ?? [])
    }
}

/// The plain gesture draft one preview publication derives from frozen input.
struct AutomationPreviewDraft: Sendable {
    let parameter: AutomationParameter?
    let points: [AutomationLanePoint]
    let text: String

    static let empty = Self(parameter: nil, points: [], text: "")

    static func resolve(gesture: AutomationGesture?, frozen: AutomationFrozenFacts?) -> Self {
        let points: [AutomationLanePoint]
        switch gesture {
        case let .sweep(transaction): points = transaction.preview
        case let .pencil(transaction): points = transaction.preview.points
        case let .node(transaction):
            points = transaction.targets.filter { $0.parameter == frozen?.parameter }.map(\.current)
        case let .phantom(transaction): points = [transaction.target.current]
        case nil: points = []
        }
        let labelPoint: AutomationLanePoint?
        if case let .node(transaction) = gesture {
            labelPoint = transaction.grabbed.flatMap {
                $0.parameter == frozen?.parameter ? $0.current : nil
            }
        } else {
            labelPoint = points.last
        }
        let text = labelPoint.map { frozen?.metadata.valueText($0.value) ?? "" } ?? ""
        return Self(parameter: frozen?.parameter, points: points, text: text)
    }
}

/// The effective-context values produced without writing page-owned state.
struct AutomationContextPresentation: Sendable {
    let tick: Tick
    let value: Int?
    let readoutVisible: Bool
    let readoutText: String
    let accessibleDescription: String
    let contextChanged: Bool

    static func resolve(
        editCursor: Tick?,
        playing: Bool,
        presentedTick: Tick,
        projection: AutomationLaneProjection?,
        activeParameter: AutomationParameter,
        previousTick: Tick,
        previousValue: Int?
    ) -> Self {
        guard let editCursor else {
            return Self(
                tick: 0, value: nil, readoutVisible: false, readoutText: "",
                accessibleDescription: AutomationPagePolicy.accessibleName,
                contextChanged: false)
        }
        let tick = playing ? presentedTick : editCursor
        let value = projection?.heldValue(at: tick)
        let title = AutomationCatalog.title(activeParameter)
        let valueText = value.map { projection?.metadata.valueText($0) ?? "" }
        let text = valueText.map { "\(title) \($0)" } ?? ""
        let visible = value != nil
        return Self(
            tick: tick,
            value: value,
            readoutVisible: visible,
            readoutText: text,
            accessibleDescription: visible ? "\(title). \(text)" : title,
            contextChanged: tick != previousTick || value != previousValue)
    }
}

/// Sanitized body input plus the exact invalidation decisions it produces.
struct AutomationBodySceneConfiguration: Sendable {
    let plotWidth: Double
    let plotHeight: Double
    let devicePixelRatio: Double
    let plotOrigin: Double
    let dragDistance: Double
    let baseFontPx: Double
    let geometry: AutomationPlotGeometry?
    let fontChanged: Bool
    let changed: Bool

    static func resolve(
        width: Double,
        height: Double,
        gutter: Double,
        devicePixelRatio: Double,
        baseFontPx: Double,
        dragDistance: Double,
        currentWidth: Double,
        currentHeight: Double,
        currentDevicePixelRatio: Double,
        currentOrigin: Double,
        currentDragDistance: Double,
        currentBaseFontPx: Double
    ) -> Self {
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : AutomationPagePolicy.seedBaseFontPx
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextOrigin = max(0, gutter.isFinite ? gutter : 0)
        let nextDrag = dragDistance.isFinite && dragDistance > 0
            ? dragDistance : AutomationPagePolicy.dragDistance
        let fontChanged = nextFont != currentBaseFontPx
        let changed = fontChanged || nextWidth != currentWidth || nextHeight != currentHeight
            || nextDpr != currentDevicePixelRatio || nextOrigin != currentOrigin
            || nextDrag != currentDragDistance
        return Self(
            plotWidth: nextWidth,
            plotHeight: nextHeight,
            devicePixelRatio: nextDpr,
            plotOrigin: nextOrigin,
            dragDistance: nextDrag,
            baseFontPx: nextFont,
            geometry: fontChanged ? AutomationPlotGeometry(baseFontPx: nextFont) : nil,
            fontChanged: fontChanged,
            changed: changed)
    }
}

enum AutomationInteractionActivity {
    static func resolve(
        hasGesture: Bool,
        hasPrompt: Bool,
        hasLaneDelete: Bool,
        hasMenu: Bool,
        hasBand: Bool,
        isPanning: Bool,
        hasTapSession: Bool
    ) -> Bool {
        return hasGesture || hasPrompt || hasLaneDelete || hasMenu || hasBand
            || isPanning || hasTapSession
    }
}

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
            syncRamps([])
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
        var segments: [AutomationRampHandle] = []
        for ghost in ghostProjections(session) {
            appendCurve(ghost, projection: projection, isGhost: true, into: &runs, ramps: &segments)
        }
        appendCurve(lane, projection: projection, isGhost: false, into: &runs, ramps: &segments)
        syncRects(curveRuns, runs)
        syncRamps(segments)
        syncNodes(nodeHandles(lane, projection: projection))
        syncRects(selectionRects, selectionBand(lane, projection: projection))
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
        let height = captionMetrics?.height ?? fontPx(1)
        let pad = max(1, (baseFontPx / 4).rounded())
        var lines: [SceneRect] = []
        var labels: [SceneText] = []
        for label in lane.scaleLabels {
            lines.append(SceneRect(x: 0, y: (label.y - stroke / 2).rounded(), width: plotWidth,
                                   height: stroke, fillColor: palette.gridLineSub2,
                                   primitiveName: "automationValueRule"))
            let width = max(fontPx(2), (captionMetrics?.advance(label.text) ?? 0).rounded())
            let y = min(max(0, label.y - height / 2), max(0, plotHeight - height))
            labels.append(SceneText(rect: (Double(pad), y.rounded(), width, height),
                                    text: label.text, color: palette.secondaryText,
                                    font: captionFont))
        }
        syncRects(valueLines, lines)
        syncTexts(valueLabels, labels)
    }

    /// One lane's step curve and ramps as drawn primitives: a horizontal run per
    /// segment with the vertical connector the next value needs, and the sloped
    /// line a ramp interpolates. `stroke` is production's two-single-pixel curve
    /// width.
    func appendCurve(_ lane: AutomationLaneProjection, projection: AutomationProjection,
                             isGhost: Bool, into runs: inout [SceneRect],
                             ramps: inout [AutomationRampHandle]) {
        guard !lane.points.isEmpty else { return }
        let stroke = 2.0
        let color = isGhost ? palette.outline : palette.primaryText
        let name = isGhost ? "automationGhostCurve" : "automationCurve"
        let limit = max(0, plotWidth)
        func x(_ tick: Tick) -> Double { projection.x(tick) }
        func y(_ value: Int) -> Double { projection.y(value, metadata: lane.metadata) }
        for (index, segment) in lane.segments.enumerated() {
            let x0 = min(max(0, x(segment.tickBegin)), limit)
            let x1 = min(max(0, segment.tickEnd.map(x) ?? limit), limit)
            guard x1 >= x0 else { continue }
            let fromY = y(segment.fromValue)
            switch segment.kind {
            case .step:
                if x1 > x0 {
                    runs.append(SceneRect(x: x0, y: (fromY - stroke / 2).rounded(), width: x1 - x0,
                                          height: stroke, fillColor: color, primitiveName: name))
                }
            case .ramp:
                if x1 > x0 {
                    ramps.append(AutomationRampHandle(
                        x0: x0, y0: (fromY - stroke / 2).rounded(), dx: x1 - x0,
                        dy: y(segment.toValue) - fromY, color: color, primitiveName: name))
                }
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

    /// Every drawn fact that depends on the pointer, the range band or a frozen
    /// gesture. The context readout's text is its own publication, so a
    /// playhead-only update never reaches here.
    func publishOverlays() {
        publishBand()
        publishHover()
        publishPreview()
    }

    /// The range press's own band, in plot coordinates.
    func publishBand() {
        guard let session, let band, band.active else {
            if bandVisible { bandVisible = false }
            bandRect = Self.rect(0, 0, 0, 0)
            return
        }
        let projection = makeProjection(
            facts: facts(parameter: band.parameter, modifiers: .init(), session: session),
            camera: session.camera)
        let limit = max(0, plotWidth)
        let x0 = min(max(0, projection.x(min(band.anchorTick, band.currentTick))), limit)
        let x1 = min(max(0, projection.x(max(band.anchorTick, band.currentTick))), limit)
        bandVisible = true
        bandRect = Self.rect(x0, 0, max(0, x1 - x0), plotHeight)
    }

    /// The hover label: the value the lane holds under the pointer, at
    /// curve-true height and the pointer's own column.
    func publishHover() {
        guard let session, let hover else {
            hoverVisible = false
            hoverText = ""
            hoverTick = 0
            hoverLabelRect = Self.rect(0, 0, 0, 0)
            return
        }
        let facts = facts(parameter: hover.parameter, modifiers: .init(), session: session)
        let projection = makeProjection(facts: facts, camera: session.camera)
        let metadata = facts.metadata
        hoverVisible = true
        hoverText = hover.text
        hoverTick = Double(hover.tick)
        hoverLabelRect = labelRect(
            text: hover.text, tick: hover.tick, x: hoverX,
            valueY: hover.value.map { projection.y($0, metadata: metadata) })
    }

    /// The frozen gesture's draft: one marker per draft point and the value
    /// readout at the last of them.
    func publishPreview() {
        applyPreviewDraft(AutomationPreviewDraft.resolve(gesture: gesture, frozen: frozen))
        guard let facts = frozen, !previewPoints.isEmpty else {
            syncRects(previewRects, [])
            previewLabelVisible = false
            previewLabelText = ""
            previewLabelRect = Self.rect(0, 0, 0, 0)
            return
        }
        let projection = makeProjection(facts: facts, camera: gestureCamera)
        let extent = nodePaint.nodeRadius
        let limit = max(0, plotWidth)
        let rects = previewPoints.map { point in
            SceneRect(x: (min(max(0, projection.x(point.tick)), limit) - extent).rounded(),
                      y: (projection.y(point.value, metadata: facts.metadata) - extent).rounded(),
                      width: 2 * extent, height: 2 * extent, fillColor: palette.selectionEdge,
                      primitiveName: "automationPreviewNode")
        }
        syncRects(previewRects, rects)
        previewLabelText = previewText
        let labelPoint: AutomationLanePoint?
        if case let .node(transaction) = gesture { labelPoint = transaction.grabbed?.current }
        else { labelPoint = previewPoints.last }
        guard let last = labelPoint, !previewText.isEmpty else {
            previewLabelVisible = false
            previewLabelRect = Self.rect(0, 0, 0, 0)
            return
        }
        previewLabelVisible = true
        previewLabelRect = labelRect(
            text: previewText, tick: last.tick,
            x: projection.x(last.tick),
            valueY: projection.y(last.value, metadata: facts.metadata))
    }


    /// A value label's own rectangle: font-sized, at the column the interaction
    /// works in, and clamped into the plot.
    func labelRect(text: String, tick: Tick, x: Double,
                           valueY: Double?) -> [String: QVariantSettable] {
        let height = captionMetrics?.height ?? fontPx(1)
        let width = max(fontPx(2), (captionMetrics?.advance(text) ?? 0).rounded())
        let gap = fontPx(1)
        let anchor = isPencilMode ? x + gap : xForTick(tick) + gap
        let originX = min(max(0, anchor), max(0, plotWidth - width))
        let centerY = valueY ?? plotHeight / 2
        let originY = min(max(0, centerY - height / 2), max(0, plotHeight - height))
        return Self.rect(originX.rounded(), originY.rounded(), width, height)
    }

    /// The readout's own rectangle: the parameter title's width at the plot's
    /// top-right corner.
    func publishReadoutGeometry() {
        let height = titleMetrics?.height ?? fontPx(1)
        let pad = fontPx(0.5)
        let width = min(max(0, plotWidth - 2 * pad),
                        max(fontPx(4), (titleMetrics?.advance(readoutText) ?? 0).rounded()))
        readoutRect = Self.rect(max(0, plotWidth - width - pad).rounded(), pad.rounded(),
                                width, height)
    }


    /// The open prompt's published form: the captured value form or the captured
    /// lane-delete confirmation.
    func publishPrompt() {
        if let prompt {
            promptKind = AutomationPromptKind.value.rawValue
            promptTitle = prompt.prompt.title
            promptLabel = prompt.prompt.label
            promptMessage = ""
            promptMinimum = prompt.prompt.minimum
            promptMaximum = prompt.prompt.maximum
            promptOpen = true
            return
        }
        if let laneDelete {
            promptKind = AutomationPromptKind.confirmLaneDelete.rawValue
            promptTitle = laneDelete.title
            promptLabel = ""
            promptMessage = laneDelete.message
            promptMinimum = 0
            promptMaximum = 0
            promptOpen = true
            return
        }
        promptOpen = false
        promptDraft = ""
        promptError = ""
        promptKind = AutomationPromptKind.value.rawValue
        promptTitle = ""
        promptLabel = ""
        promptMessage = ""
        promptMinimum = 0
        promptMaximum = 0
    }

    func publishMenuRows() {
        let values = menu?.rows ?? []
        menuRowSnapshots = values
        syncMenuRows(values)
        menuRowCount = values.count
        let children: [AutomationMenuRowHandle] = menu.flatMap { state in
            if case .lane = state.target { return rangeMenuRows(facts: state.facts) }
            return nil
        } ?? []
        menuChildRows.replaceSubrange(0..<menuChildRows.count, with: children)
        menuChildRowCount = children.count
        let open = menu != nil
        if menuOpen != open { menuOpen = open }
        publishInteractionState()
    }

    func publishTapTempo() {
        tapTempoActive = tapGuard != nil || tapSession.tapCount != 0
        tapTempoTapCount = tapSession.tapCount
        tapTempoDraftBpm = tapSession.draftBpm
        tapTempoIdleCommitMs = tapSession.idleCommitMs
        tapTempoReady = tapSession.readyToCommit
    }


    func publishTypography() {
        let pixelSize = max(1, Int(baseFontPx.rounded()))
        let caption = AutomationCaption(pixelSize: pixelSize, weight: 400)
        let title = AutomationCaption(pixelSize: pixelSize, weight: 600)
        captionMetrics = caption
        titleMetrics = title
        setFont(&captionFont, caption.fontMap)
        setFont(&titleFont, title.fontMap)
    }

    func setFont(_ storage: inout [String: QVariantSettable],
                         _ value: [String: QVariantSettable]) {
        guard !Self.fontMatches(storage, value) else { return }
        storage = value
    }

    static func fontMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy {
            String(describing: $1) == String(describing: rhs[$0])
        }
    }

    // MARK: Internals: shared metrics

    func fontPx(_ multiplier: Double) -> Double {
        multiplier == 0 ? 0 : max(1, (baseFontPx * multiplier).rounded())
    }

    func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: plotWidth,
                    height: plotHeight, timeAxis: timeAxis(session))
    }

    /// The roll's own time axis, built from the same document facts the grid
    /// uses, so the automation grid is the roll's grid.
    func timeAxis(_ session: DocumentSession) -> TimeAxis {
        session.projectionCache.timeAxis
    }

    /// The production paint geometry, at the same font-relative factors
    /// `AutomationPlotGeometry` resolves its interaction radii with.
    var nodePaint: AutomationNodePaint {
        AutomationNodePaint(
            nodeRadius: fontPxF(baseFontPx, 3.0 / 16.0),
            ringRadius: fontPxF(baseFontPx, 9.0 / 32.0),
            outlineWidth: fontPxF(baseFontPx, 1.0 / 12.0))
    }

    static func rect(_ x: Double, _ y: Double, _ width: Double,
                             _ height: Double) -> [String: QVariantSettable] {
        ["x": x, "y": y, "width": width, "height": height]
    }

    static func rectMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right else { return false }
        }
        return true
    }

    static func identityText(_ identity: AutomationPointIdentity) -> String {
        "\(identity.parameter)/\(identity.tick)/\(identity.occurrence)/\(identity.value)"
    }

    // MARK: Internals: model synchronisation

    func syncRects(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        let common = min(model.count, rects.count)
        for index in 0..<common where !model[index].matches(rects[index]) {
            model[index] = rects[index]
        }
        if model.count != rects.count {
            model.replaceSubrange(common..<model.count, with: rects[common...])
        }
    }

    func syncTexts(_ model: QListModel<SceneText>, _ texts: [SceneText]) {
        let common = min(model.count, texts.count)
        for index in 0..<common where !Self.textMatches(model[index], texts[index]) {
            model[index] = texts[index]
        }
        if model.count != texts.count {
            model.replaceSubrange(common..<model.count, with: texts[common...])
        }
    }

    func syncTabs(_ values: [AutomationTabHandle]) {
        let common = min(tabs.count, values.count)
        for index in 0..<common where !tabs[index].matches(values[index]) {
            tabs[index] = values[index]
        }
        if tabs.count != values.count {
            tabs.replaceSubrange(common..<tabs.count, with: values[common...])
        }
    }

    func syncNodes(_ values: [AutomationNodeHandle]) {
        nodeSnapshots = values
        if nodeCount != values.count { nodeCount = values.count }
        let common = min(nodes.count, values.count)
        for index in 0..<common where !nodes[index].matches(values[index]) {
            nodes[index] = values[index]
        }
        if nodes.count != values.count {
            nodes.replaceSubrange(common..<nodes.count, with: values[common...])
        }
    }

    func syncRamps(_ values: [AutomationRampHandle]) {
        let common = min(ramps.count, values.count)
        for index in 0..<common where !ramps[index].matches(values[index]) {
            ramps[index] = values[index]
        }
        if ramps.count != values.count {
            ramps.replaceSubrange(common..<ramps.count, with: values[common...])
        }
    }

    func syncMenuRows(_ values: [AutomationMenuRowHandle]) {
        let common = min(menuRows.count, values.count)
        for index in 0..<common where !menuRows[index].matches(values[index]) {
            menuRows[index] = values[index]
        }
        if menuRows.count != values.count {
            menuRows.replaceSubrange(common..<menuRows.count, with: values[common...])
        }
    }

    static func textMatches(_ lhs: SceneText, _ rhs: SceneText) -> Bool {
        lhs.labelText == rhs.labelText && lhs.labelColor == rhs.labelColor
            && lhs.labelBackground == rhs.labelBackground
            && lhs.labelHorizontalAlignment == rhs.labelHorizontalAlignment
            && lhs.labelVerticalAlignment == rhs.labelVerticalAlignment
            && fontMatches(lhs.labelFont, rhs.labelFont)
            && rectMatches(lhs.labelRect, rhs.labelRect)
            && rectMatches(lhs.labelBackgroundRect, rhs.labelBackgroundRect)
            && rectMatches(lhs.labelClipRect, rhs.labelClipRect)
    }
}

// MARK: - Published records

/// One published selector tab: the parameter's label, whether it is the active
/// one, whether its curve is pinned as a ghost, whether the shared selection
/// covers it, and its own event count.
@MainActor
@QtBridgeable
public final class AutomationTabHandle {
    public var index: Int = 0
    public var label: String = ""
    public var tempo: Bool = false
    public var active: Bool = false
    public var ghosted: Bool = false
    public var included: Bool = false
    public var available: Bool = true
    public var eventCount: Int = 0
    public var primitiveName: String = "automationParameterTab"

    public init() {}

    @QtIgnored
    func matches(_ other: AutomationTabHandle) -> Bool {
        index == other.index && label == other.label && tempo == other.tempo
            && active == other.active && ghosted == other.ghosted && included == other.included
            && available == other.available && eventCount == other.eventCount
            && primitiveName == other.primitiveName
    }
}

/// One published node: its projected position, its paint radii, its interaction
/// state and the identity a capture can revalidate.
@MainActor
@QtBridgeable
public final class AutomationNodeHandle {
    public var x: Double = 0
    public var y: Double = 0
    public var tick: Double = 0
    public var value: Int = 0
    public var radius: Double = 0
    public var ringRadius: Double = 0
    public var outlineWidth: Double = 0
    public var fillColor: String = ""
    public var outlineColor: String = ""
    public var ringColor: String = ""
    public var selected: Bool = false
    public var hovered: Bool = false
    /// The synthetic engine-default node rather than a written occurrence.
    public var projected: Bool = false
    /// The origin phantom: the rightmost node left of the plot, drawn at the edge.
    public var phantom: Bool = false
    public var identity: String = ""
    public var primitiveName: String = "automationNode"

    public init() {}

    @QtIgnored
    func matches(_ other: AutomationNodeHandle) -> Bool {
        x == other.x && y == other.y && tick == other.tick && value == other.value
            && radius == other.radius && ringRadius == other.ringRadius
            && outlineWidth == other.outlineWidth && fillColor == other.fillColor
            && outlineColor == other.outlineColor && ringColor == other.ringColor
            && selected == other.selected && hovered == other.hovered
            && projected == other.projected && phantom == other.phantom
            && identity == other.identity && primitiveName == other.primitiveName
    }
}

/// One published ramp segment: the drawn span from its start to the next value.
@MainActor
@QtBridgeable
public final class AutomationRampHandle {
    public var x0: Double = 0
    public var y0: Double = 0
    public var dx: Double = 0
    public var dy: Double = 0
    public var color: String = ""
    public var primitiveName = "automationRamp"

    public init() {}

    init(x0: Double, y0: Double, dx: Double, dy: Double, color: String,
         primitiveName: String) {
        self.x0 = x0
        self.y0 = y0
        self.dx = dx
        self.dy = dy
        self.color = color
        self.primitiveName = primitiveName
    }

    @QtIgnored
    func matches(_ other: AutomationRampHandle) -> Bool {
        x0 == other.x0 && y0 == other.y0 && dx == other.dx && dy == other.dy
            && color == other.color && primitiveName == other.primitiveName
    }
}

/// One published menu row: the captured action, its label and its availability.
/// A separator carries no action and is never activatable.
@MainActor
@QtBridgeable
public final class AutomationMenuRowHandle {
    public var actionId: Int = 0
    public var text: String = ""
    public var enabled: Bool = true
    public var separator: Bool = false
    public var checkable: Bool = false
    public var checked: Bool = false
    public var hasSubmenu: Bool = false
    public var shortcutText: String = ""
    public var primitiveName: String = "automationMenuRow"

    public init() {}

    init(actionId: Int, text: String, enabled: Bool) {
        self.actionId = actionId
        self.text = text
        self.enabled = enabled
    }

    init(separator: Bool) {
        self.separator = separator
        actionId = -1
        enabled = false
        primitiveName = "automationMenuSeparator"
    }

    @QtIgnored
    func matches(_ other: AutomationMenuRowHandle) -> Bool {
        actionId == other.actionId && text == other.text && enabled == other.enabled
            && separator == other.separator && primitiveName == other.primitiveName
            && checkable == other.checkable && checked == other.checked
            && hasSubmenu == other.hasSubmenu && shortcutText == other.shortcutText
    }
}

/// The page's own paint geometry: the production node radii at the same
/// font-relative factors the interaction geometry resolves.
struct AutomationNodePaint: Equatable, Sendable {
    var nodeRadius: Double
    var ringRadius: Double
    var outlineWidth: Double
}

/// Caption and title metrics for the page's own labels, measured through the same
/// native font-metrics seam the grid and the sibling pages use.
@MainActor
final class AutomationCaption {
    let fontMap: [String: QVariantSettable]
    let height: Double
    private let session: OpaquePointer

    init(pixelSize: Int, weight: Int) {
        let family = AutomationPage.fontFamily
        fontMap = ["family": family, "pixelSize": pixelSize, "weight": weight,
                   "letterSpacing": 0.0]
        session = family.withCString { sgf_create($0, Int32(pixelSize), Int32(weight), 0)! }
        height = sgf_extents(session).height
    }

    isolated deinit { sgf_destroy(session) }

    func advance(_ text: String) -> Double {
        text.withCString { sgf_advance(session, $0) }
    }
}

