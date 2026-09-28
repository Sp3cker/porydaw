import Foundation
import PorydawCore

@MainActor
extension AutomationPage {
    func publishDrawingContent() {
        guard let session, !drawingCameraOnly else { return }
        let grid = session.grid
        let axis = timeAxis(session)
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
                        y: y, height: frame, argb: SceneRectPacking.argb(palette.separator), flags: 3))
            }
        }
        let rule = Float(max(1, fontPxF(baseFontPx, 1.0 / 12.0)))
        if let lane = projection {
            for label in lane.scaleLabels {
                let y = Float((label.y - Double(rule) / 2).rounded())
                axisRects.append(
                    DrawerStaticRect(
                        tickStart: 0, tickEnd: UInt32(max(0, plotWidth)),
                        y: y, height: rule, argb: SceneRectPacking.argb(palette.gridLineSub2), flags: 3))
            }
            let tickLength = Typography(baseFontPx: Int(baseFontPx.rounded())).space(.half) * 3
            for label in lane.scaleLabels {
                axisRects.append(
                    DrawerStaticRect(
                        tickStart: 0, tickEnd: UInt32(tickLength),
                        y: Float((label.y - Double(rule) / 2).rounded()), height: rule,
                        argb: SceneRectPacking.argb(palette.separator), flags: 3))
            }
        }
        var ghostRuns: [DrawerStaticRect] = []
        var ghostEdges: [DrawerAnchoredRect] = []
        var runs: [DrawerStaticRect] = []
        var curveEdges: [DrawerAnchoredRect] = []
        if let lane = projection {
            let projectionFacts = facts(parameter: activeParameter, modifiers: .init(), session: session)
            let curveProjection = makeProjection(facts: projectionFacts, camera: session.camera)
            for ghost in ghostProjections(session) {
                let ghostProjection = makeProjection(
                    facts: facts(parameter: ghost.parameter, modifiers: .init(), session: session),
                    camera: session.camera)
                appendDrawingCurve(
                    ghost, projection: ghostProjection, ghost: true,
                    runs: &ghostRuns, edges: &ghostEdges)
            }
            appendDrawingCurve(
                lane, projection: curveProjection, ghost: false,
                runs: &runs, edges: &curveEdges)
        }
        var selectionFill: [DrawerStaticRect] = []
        var selectionEdges: [DrawerAnchoredRect] = []
        if let lane = projection, let selection, selection.isActive,
            selection.covers(lane.parameter, usedTracks: usedTracks())
        {
            selectionFill.append(
                DrawerStaticRect(
                    tickStart: selection.range.startTick, tickEnd: selection.range.endTick,
                    y: 0, height: Float(plotHeight), argb: SceneRectPacking.argb(palette.selectionFill)))
            let edgeColor = SceneRectPacking.argb(palette.selectionEdge)
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
            let ink = SceneRectPacking.argb(palette.selectionEdge)
            let phantomPreview: Bool
            if case .phantom = gesture { phantomPreview = true } else { phantomPreview = false }
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
        let layers: [DrawerLayer] = [
            .statics(axisRects), .layerBreak, .statics(ghostRuns), .anchored(ghostEdges),
            .statics(runs), .anchored(curveEdges), .statics(selectionFill),
            .anchored(selectionEdges), .layerBreak, .anchored(previewNodes),
            .statics(previewRuns),
        ]
        let data = DrawerStaticsContent.pack(
            axis: axis, grid: grid, metrics: gridMetrics(session),
            paletteColors: gridPalette, layers: layers)
        guard data != drawingContentData else { return }
        drawingContentData = data
        contentRevision &+= 1
    }

    private func appendDrawingCurve(
        _ lane: AutomationLaneProjection,
        projection: AutomationProjection, ghost: Bool,
        runs: inout [DrawerStaticRect], edges: inout [DrawerAnchoredRect]
    ) {
        guard !lane.points.isEmpty else { return }
        let ink = palette.automationNodeInk
        let color: String
        if ghost {
            let channels = PaletteMath.channels(ink)
            color = PaletteMath.hex(r: channels.r, g: channels.g, b: channels.b, a: 128)
        } else {
            color = ink
        }
        let argb = SceneRectPacking.argb(color)
        for (index, segment) in lane.segments.enumerated() {
            let fromY = projection.y(segment.fromValue, metadata: lane.metadata)
            runs.append(
                DrawerStaticRect(
                    tickStart: segment.tickBegin,
                    tickEnd: segment.tickEnd ?? TimeDefaults.maxTick,
                    y: Float((fromY - 1).rounded()), height: 2, argb: argb))
            let next = index + 1 < lane.segments.count ? lane.segments[index + 1] : nil
            if segment.kind == .step, let next, next.fromValue != segment.fromValue,
                let end = segment.tickEnd
            {
                let nextY = projection.y(next.fromValue, metadata: lane.metadata)
                edges.append(
                    DrawerAnchoredRect(
                        tick: end, dx: -1, width: 2,
                        y: Float(min(fromY, nextY).rounded()),
                        height: Float(max(2, abs(nextY - fromY))), argb: argb, flags: 1))
            }
        }
    }
}
