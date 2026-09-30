import Foundation
import PorydawCore

@MainActor
extension AutomationPage {
    /// Rebuilds the three viewport-space display lists together: axis grid
    /// plus sticky chrome, ghost/curve/selection statics, preview draft.
    func publishDrawingContent() {
        guard let session else {
            let empty = retainedEmptyDisplayList()
            let fresh = [empty, empty, empty]
            guard fresh != displayLists else { return }
            displayLists = fresh
            displayRevision &+= 1
            return
        }
        let grid = session.grid
        let axis = timeAxis(session)
        // One integer parse per palette slot per build; every record below
        // reuses these, and ghost ink is node ink at alpha 128 as integers.
        let separatorArgb = SceneRectPacking.argb(palette.separator)
        let gridSub2Argb = SceneRectPacking.argb(palette.gridLineSub2)
        let curveArgb = SceneRectPacking.argb(palette.automationNodeInk)
        let ghostArgb = (curveArgb & 0x00FF_FFFF) | 0x8000_0000
        let selectionFillArgb = SceneRectPacking.argb(palette.selectionFill)
        let selectionEdgeArgb = SceneRectPacking.argb(palette.selectionEdge)
        let gridPalette: [Int: String] = [
            3: palette.gridLineBar, 4: palette.gridLineBeat,
            5: palette.gridLineSub1, 6: palette.gridLineSub2,
            7: palette.gridLineSub3, 25: palette.gridLineBeatFine,
        ]
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
            let tickLength = Typography(baseFontPx: Int(baseFontPx.rounded())).space(.half) * 3
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
            let projectionFacts = facts(parameter: activeParameter, modifiers: .init(), session: session)
            let curveProjection = makeProjection(facts: projectionFacts, camera: session.camera)
            for ghost in ghostProjections(session) where !ghost.points.isEmpty {
                let ghostProjection = makeProjection(
                    facts: facts(parameter: ghost.parameter, modifiers: .init(), session: session),
                    camera: session.camera)
                appendDrawingCurve(
                    ghost.segments, metadata: ghost.metadata, projection: ghostProjection,
                    argb: ghostArgb, runs: &ghostRuns, edges: &ghostEdges)
            }
            if let edit = previewEdit, edit.parameter == lane.parameter {
                // A live draw paints the lane it would commit.
                appendDrawingCurve(
                    Self.previewCurve(lane, replacedBy: edit), metadata: lane.metadata,
                    projection: curveProjection, argb: curveArgb,
                    runs: &runs, edges: &curveEdges)
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
        var previewNodes: [DrawerAnchoredRect] = []
        if let facts = frozen, !previewPoints.isEmpty {
            let previewProjection = makeProjection(facts: facts, camera: gestureCamera)
            let extent = Float(nodePaint.nodeRadius)
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
            for point in previewPoints {
                previewNodes.append(
                    DrawerAnchoredRect(
                        tick: point.tick,
                        dx: phantomPreview ? -Float(previewProjection.x(point.tick)) - extent : -extent,
                        width: 2 * extent,
                        y: Float(
                            (previewProjection.y(point.value, metadata: facts.metadata)
                                - Double(extent)).rounded()),
                        height: 2 * extent, argb: ink, flags: 1))
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
                                metadata: facts.metadata) - 1).rounded()),
                        height: 2, argb: ink))
            }
        }
        // Viewport-space lists through the Task 6a builders; record order is
        // the paint order inside each list, matching the legacy layer order.
        let viewport = CGSize(width: plotWidth, height: plotHeight)
        let camera = session.camera
        let dpr = devicePixelRatio
        DrawerStaticsContent.buildGrid(
            into: &axisListWriter, axis: axis, grid: grid, camera: camera,
            viewport: viewport, paletteColors: gridPalette)
        DrawerStaticsContent.buildTickRects(
            into: &axisListWriter, rects: axisRects, camera: camera, dpr: dpr,
            viewport: viewport)
        let axisData = axisListWriter.finish()
        DrawerStaticsContent.buildTickRects(
            into: &staticsListWriter, rects: ghostRuns, camera: camera, dpr: dpr,
            viewport: viewport)
        DrawerStaticsContent.buildAnchored(
            into: &staticsListWriter, rects: ghostEdges, camera: camera, dpr: dpr,
            viewport: viewport)
        DrawerStaticsContent.buildTickRects(
            into: &staticsListWriter, rects: runs, camera: camera, dpr: dpr,
            viewport: viewport)
        DrawerStaticsContent.buildAnchored(
            into: &staticsListWriter, rects: curveEdges, camera: camera, dpr: dpr,
            viewport: viewport)
        DrawerStaticsContent.buildTickRects(
            into: &staticsListWriter, rects: selectionFill, camera: camera, dpr: dpr,
            viewport: viewport)
        DrawerStaticsContent.buildAnchored(
            into: &staticsListWriter, rects: selectionEdges, camera: camera, dpr: dpr,
            viewport: viewport)
        let staticsData = staticsListWriter.finish()
        DrawerStaticsContent.buildAnchored(
            into: &previewListWriter, rects: previewNodes, camera: camera, dpr: dpr,
            viewport: viewport)
        DrawerStaticsContent.buildTickRects(
            into: &previewListWriter, rects: previewRuns, camera: camera, dpr: dpr,
            viewport: viewport)
        let previewData = previewListWriter.finish()
        let fresh = [axisData, staticsData, previewData]
        guard fresh != displayLists else { return }
        displayLists = fresh
        displayRevision &+= 1
    }

    /// Valid empty list for unbuilt bands and out-of-range fetches.
    func retainedEmptyDisplayList() -> Data {
        if let cached = cachedEmptyDisplayList { return cached }
        var writer = DisplayListWriter()
        let empty = writer.finish()
        cachedEmptyDisplayList = empty
        return empty
    }

    private func appendDrawingCurve(
        _ segments: [AutomationCurveSegment], metadata: AutomationParameterMetadata,
        projection: AutomationProjection, argb: UInt32,
        runs: inout [DrawerStaticRect], edges: inout [DrawerAnchoredRect]
    ) {
        for (index, segment) in segments.enumerated() {
            let fromY = projection.y(segment.fromValue, metadata: metadata)
            runs.append(
                DrawerStaticRect(
                    tickStart: segment.tickBegin,
                    tickEnd: segment.tickEnd ?? TimeDefaults.maxTick,
                    y: Float((fromY - 1).rounded()), height: 2, argb: argb))
            let next = index + 1 < segments.count ? segments[index + 1] : nil
            if segment.kind == .step, let next, next.fromValue != segment.fromValue,
                let end = segment.tickEnd
            {
                let nextY = projection.y(next.fromValue, metadata: metadata)
                edges.append(
                    DrawerAnchoredRect(
                        tick: end, dx: -1, width: 2,
                        y: Float(min(fromY, nextY).rounded()),
                        height: Float(max(2, abs(nextY - fromY))), argb: argb, flags: 1))
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
        for point in lane.points[end...] {
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
