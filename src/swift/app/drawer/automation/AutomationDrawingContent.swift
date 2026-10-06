import Foundation
import PorydawCore
import PorydawDocument
import QtBridge

@MainActor
extension AutomationPage {
    /// Rebuilds the three viewport-space display lists together: axis grid
    /// plus sticky chrome, ghost/curve/selection statics, preview draft.
    func publishDrawingContent() {
        guard let viewport else {
            previewNodes.replaceSubrange(0..<previewNodes.count, with: [])
            let empty = retainedEmptyDisplayList()
            let fresh = [empty, empty, empty]
            guard fresh != displayLists else { return }
            displayLists = fresh
            displayRevision &+= 1
            return
        }
        let session = viewport.session
        let grid = viewport.grid
        let axis = timeAxis(session)
        // Resolve each typed palette slot once; ghost ink uses alpha 128.
        let separatorArgb = SceneRectPacking.argb(palette.separator)
        let gridSub2Argb = SceneRectPacking.argb(palette.gridLineSub2)
        let curveArgb = SceneRectPacking.argb(palette.automationNodeInk)
        let ghostArgb = (curveArgb & 0x00FF_FFFF) | 0x8000_0000
        let selectionFillArgb = SceneRectPacking.argb(palette.selectionFill)
        let selectionEdgeArgb = SceneRectPacking.argb(palette.selectionEdge)
        let gridPalette = DrawerStaticsContent.gridPaletteColors(palette)
        var axisRects: [DrawerStaticRect] = []
        let frame = Float(max(1 / devicePixelRatio, fontPxF(baseFontPx, 1.0 / 12.0)))
        if plotWidth > 0, plotHeight > 0 {
            for y in [Float(0), Float(plotHeight) - frame] {
                axisRects.append(
                    DrawerStaticRect(
                        tickStart: 0, tickEnd: UInt32(plotWidth),
                        y: y, height: frame, argb: separatorArgb, flags: 3))
            }
        }
        let rule = Float(max(1, fontPxF(baseFontPx, 1.0 / 12.0)))
        if let lane = projection {
            for label in lane.scaleLabels {
                let y = Float((label.y - Double(rule) / 2).rounded())
                axisRects.append(
                    DrawerStaticRect(
                        tickStart: 0, tickEnd: UInt32(max(0, plotWidth)),
                        y: y, height: rule, argb: gridSub2Argb, flags: 3))
            }
            let tickLength = typography.space(.half) * 3
            for label in lane.scaleLabels {
                axisRects.append(
                    DrawerStaticRect(
                        tickStart: 0, tickEnd: UInt32(tickLength),
                        y: Float((label.y - Double(rule) / 2).rounded()), height: rule,
                        argb: separatorArgb, flags: 3))
            }
        }
        var ghostRuns: [DrawerStaticRect] = []
        var ghostEdges: [DrawerAnchoredRect] = []
        var runs: [DrawerStaticRect] = []
        var curveEdges: [DrawerAnchoredRect] = []
        if let lane = projection {
            let projectionFacts = facts(parameter: activeParameter, modifiers: .init(), viewport: viewport)
            let curveProjection = makeProjection(facts: projectionFacts, camera: viewport.camera)
            for ghost in ghostProjections(viewport) where !ghost.points.isEmpty {
                let ghostProjection = makeProjection(
                    facts: facts(parameter: ghost.parameter, modifiers: .init(), viewport: viewport),
                    camera: viewport.camera)
                appendDrawingCurve(
                    ghost.segments, metadata: ghost.metadata, projection: ghostProjection,
                    argb: ghostArgb, runs: &ghostRuns, edges: &ghostEdges)
            }
            if let edit = previewEdit, edit.parameter == lane.parameter {
                // A live draw paints the lane it would commit.
                let stroke: Double
                if case .pencil = gesture { stroke = 2 } else { stroke = 1 }
                appendDrawingCurve(
                    Self.previewCurve(lane, replacedBy: edit), metadata: lane.metadata,
                    projection: curveProjection, argb: curveArgb,
                    stroke: stroke, edgeStroke: 1, runs: &runs, edges: &curveEdges)
            } else if !lane.points.isEmpty {
                appendDrawingCurve(
                    lane.segments, metadata: lane.metadata, projection: curveProjection,
                    argb: curveArgb, runs: &runs, edges: &curveEdges)
            }
        }
        var selectionFill: [DrawerStaticRect] = []
        var selectionEdges: [DrawerAnchoredRect] = []
        if let lane = projection, let selection, selection.isActive,
            selection.covers(lane.parameter, usedTracks: usedTracks())
        {
            selectionFill.append(
                DrawerStaticRect(
                    tickStart: selection.range.startTick, tickEnd: selection.range.endTick,
                    y: 0, height: Float(plotHeight), argb: selectionFillArgb))
            let edgeColor = selectionEdgeArgb
            selectionEdges.append(
                DrawerAnchoredRect(
                    tick: selection.range.startTick,
                    dx: 0, width: 1, y: 0, height: Float(plotHeight), argb: edgeColor, flags: 1))
            selectionEdges.append(
                DrawerAnchoredRect(
                    tick: selection.range.endTick,
                    dx: -1, width: 1, y: 0, height: Float(plotHeight), argb: edgeColor, flags: 1))
        }
        var previewRuns: [DrawerStaticRect] = []
        var draftNodes: [AutomationNodeValue] = []
        if let facts = frozen, !previewPoints.isEmpty {
            let previewProjection = makeProjection(facts: facts, camera: gestureCamera)
            let paint = nodePaint
            let phantomPreview: Bool
            let ink: UInt32
            switch gesture {
            case .phantom:
                phantomPreview = true
                ink = selectionEdgeArgb
            case .node:
                phantomPreview = false
                ink = selectionEdgeArgb
            default:
                // Pencil and sweep drafts share the lane ink of the curve they draw.
                phantomPreview = false
                ink = curveArgb
            }
            let showMarkers: Bool
            if case .pencil = gesture {
                showMarkers = previewProjection.markersVisible()
            } else {
                showMarkers = true
            }
            for point in previewPoints where showMarkers {
                var node = AutomationNodeValue()
                node.x = phantomPreview ? 0 : previewProjection.x(point.tick)
                node.y = previewProjection.y(point.value, metadata: facts.metadata)
                node.tick = Double(point.tick)
                node.value = point.value
                node.radius = paint.nodeRadius
                node.ringRadius = paint.ringRadius
                node.outlineWidth = paint.outlineWidth
                node.outlineColor = ink == curveArgb ? palette.automationNodeInk : palette.selectionEdge
                node.ringColor = palette.selectionRing
                node.primitiveName = "automationPreviewNode"
                draftNodes.append(node)
            }
            if case .phantom(let transaction) = gesture, transaction.drag.exceeded {
                let next = facts.snapshot.displaySeries.first { $0.tick > transaction.target.original.tick }
                previewRuns.append(
                    DrawerStaticRect(
                        tickStart: 0,
                        tickEnd: next?.tick ?? TimeDefaults.maxTick,
                        y: Float(
                            (previewProjection.y(
                                transaction.target.current.value,
                                metadata: facts.metadata) - 0.5).rounded()),
                        height: 1, argb: ink))
            }
        }
        syncRetained(previewNodes, draftNodes, make: AutomationNodeHandle.init, update: { $0.update($1) })
        // Viewport-space lists through the Task 6a builders; record order is
        // the paint order inside each list, matching the legacy layer order.
        let viewportSize = CGSize(width: plotWidth, height: plotHeight)
        let camera = viewport.camera
        let dpr = devicePixelRatio
        DrawerStaticsContent.buildGrid(
            into: &axisListWriter, axis: axis, grid: grid, camera: camera,
            viewport: viewportSize, paletteColors: gridPalette)
        DrawerStaticsContent.buildTickRects(
            into: &axisListWriter, rects: axisRects, camera: camera, dpr: dpr,
            viewport: viewportSize)
        let axisData = axisListWriter.finish()
        DrawerStaticsContent.buildTickRects(
            into: &staticsListWriter, rects: ghostRuns, camera: camera, dpr: dpr,
            viewport: viewportSize)
        DrawerStaticsContent.buildAnchored(
            into: &staticsListWriter, rects: ghostEdges, camera: camera, dpr: dpr,
            viewport: viewportSize)
        DrawerStaticsContent.buildTickRects(
            into: &staticsListWriter, rects: runs, camera: camera, dpr: dpr,
            viewport: viewportSize)
        DrawerStaticsContent.buildAnchored(
            into: &staticsListWriter, rects: curveEdges, camera: camera, dpr: dpr,
            viewport: viewportSize)
        DrawerStaticsContent.buildTickRects(
            into: &staticsListWriter, rects: selectionFill, camera: camera, dpr: dpr,
            viewport: viewportSize)
        DrawerStaticsContent.buildAnchored(
            into: &staticsListWriter, rects: selectionEdges, camera: camera, dpr: dpr,
            viewport: viewportSize)
        let staticsData = staticsListWriter.finish()
        DrawerStaticsContent.buildTickRects(
            into: &previewListWriter, rects: previewRuns, camera: camera, dpr: dpr,
            viewport: viewportSize)
        let previewData = previewListWriter.finish()
        let fresh = [axisData, staticsData, previewData]
        guard fresh != displayLists else { return }
        displayLists = fresh
        displayRevision &+= 1
    }

    /// Valid empty list for unbuilt bands and out-of-range fetches.
    func retainedEmptyDisplayList() -> Data {
        DrawerStaticsContent.retainedEmptyDisplayList(cached: &cachedEmptyDisplayList)
    }

    private func appendDrawingCurve(
        _ segments: [AutomationCurveSegment], metadata: AutomationParameterMetadata,
        projection: AutomationProjection, argb: UInt32,
        stroke: Double = 2, edgeStroke: Double = 2,
        runs: inout [DrawerStaticRect], edges: inout [DrawerAnchoredRect]
    ) {
        for (index, segment) in segments.enumerated() {
            let fromY = projection.y(segment.fromValue, metadata: metadata)
            runs.append(
                DrawerStaticRect(
                    tickStart: segment.tickBegin,
                    tickEnd: segment.tickEnd ?? TimeDefaults.maxTick,
                    y: Float((fromY - stroke / 2).rounded()), height: Float(stroke), argb: argb))
            let next = index + 1 < segments.count ? segments[index + 1] : nil
            if segment.kind == .step, let next, next.fromValue != segment.fromValue,
                let end = segment.tickEnd
            {
                let nextY = projection.y(next.fromValue, metadata: metadata)
                edges.append(
                    DrawerAnchoredRect(
                        tick: end, dx: -Float(edgeStroke / 2), width: Float(edgeStroke),
                        y: Float(min(fromY, nextY).rounded()),
                        height: Float(max(edgeStroke, abs(nextY - fromY))), argb: argb, flags: 1))
            }
        }
    }

    /// The lane's curve as `edit` would leave it: the written points outside the
    /// replaced span plus the replacement, with the snapshot's tick-zero rules.
    static func previewCurve(
        _ lane: AutomationLaneProjection,
        replacedBy edit: AutomationLaneEdit
    ) -> [AutomationCurveSegment] {
        let metadata = lane.metadata
        let begin = automationPartitionIndex(lane.points) { $0.tick < edit.tickBegin }
        let end = automationPartitionIndex(lane.points) { $0.tick <= edit.tickEnd }
        var points: [AutomationLanePoint] = []
        points.reserveCapacity(begin + edit.points.count + lane.points.count - end + 1)
        for point in lane.points[..<begin] where !point.projected {
            points.append(AutomationLanePoint(tick: point.tick, value: point.value))
        }
        points.append(contentsOf: edit.points)
        for point in lane.points[end...] where !point.projected {
            points.append(AutomationLanePoint(tick: point.tick, value: point.value))
        }
        var leadIn: Int?
        if points.first?.tick != 0, let value = metadata.defaultValue {
            if metadata.projectsTickZero {
                points.insert(AutomationLanePoint(tick: 0, value: metadata.clamp(value)), at: 0)
            } else {
                leadIn = metadata.clamp(value)
            }
        }
        return AutomationCurveSegment.curve(
            through: points, leadIn: leadIn, selection: nil,
            interpolation: metadata.interpolation)
    }
}
