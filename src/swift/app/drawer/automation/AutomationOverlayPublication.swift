import NativeGridTypography
import PorydawCore
import QtBridge


@MainActor
extension AutomationPage {
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
            updateRect(bandRect, (0, 0, 0, 0))
            return
        }
        let projection = makeProjection(
            facts: facts(parameter: band.parameter, modifiers: .init(), session: session),
            camera: session.camera)
        let limit = max(0, plotWidth)
        let x0 = min(max(0, projection.x(min(band.anchorTick, band.currentTick))), limit)
        let x1 = min(max(0, projection.x(max(band.anchorTick, band.currentTick))), limit)
        bandVisible = true
        updateRect(bandRect, (x0, 0, max(0, x1 - x0), plotHeight))
    }

    /// The hover label: the value the lane holds under the pointer, at
    /// curve-true height and the pointer's own column.
    func publishHover() {
        // Hover is an overlay-only update: refresh the changed node roles
        // without rebuilding lane geometry or replacing unaffected delegates.
        let hoveredTick = hover.flatMap {
            $0.hasPoint && $0.parameter == activeParameter ? Double($0.tick) : nil
        }
        for (index, node) in nodeSnapshots.enumerated() {
            let hovered = hoveredTick == node.tick
            if node.hovered != hovered {
                var value = node.current
                value.hovered = hovered
                _ = node.update(value)
                nodes[index] = node
            }
        }
        guard let session, let hover else {
            let wasVisible = hoverVisible
            hoverVisible = false
            if wasVisible {
                hoverDisplay.update(visible: false)
            }
            hoverText = ""
            hoverTick = 0
            updateRect(hoverLabelRect, (0, 0, 0, 0))
            return
        }
        if !hover.hasPoint && !ghostParameters.isEmpty {
            let tracks = usedTracks()
            for parameter in ghostParameters {
                let facts = facts(parameter: parameter, modifiers: .init(), session: session)
                let cameraProjection = makeProjection(facts: facts, camera: session.camera)
                let lane = cameraProjection.project(
                    facts.snapshot, selection: selection, usedTracks: tracks)
                guard let value = lane.heldValue(at: hover.tick) else { continue }
                let curveY = cameraProjection.y(value, metadata: lane.metadata)
                guard abs(curveY - hoverY) <= geometry.pointHitRadius else { continue }
                let label = parameter.isTempo ? "Tempo" : AutomationCatalog.tabLabel(parameter)
                let rect = hoverGhostRect(text: label, x: hoverX, curveY: curveY)
                hoverVisible = true
                hoverText = label
                hoverTick = Double(hover.tick)
                updateRect(hoverLabelRect, rect)
                hoverDisplay.update(visible: true, text: label, rect: rect)
                return
            }
        }
        let facts = facts(parameter: hover.parameter, modifiers: .init(), session: session)
        let projection = makeProjection(facts: facts, camera: session.camera)
        let metadata = facts.metadata
        hoverVisible = true
        hoverText = hover.text
        hoverTick = Double(hover.tick)
        let rect = labelRect(
            text: hover.text, tick: hover.tick, x: hoverX,
            valueY: hover.value.map { projection.y($0, metadata: metadata) })
        updateRect(hoverLabelRect, rect)
        hoverDisplay.update(
            visible: true, text: hover.text, hasNode: hoveredTick != nil,
            nodeTick: hoveredTick ?? 0,
            guideX: projection.x(hover.tick),
            ghostY: hover.value.map { projection.y($0, metadata: metadata) } ?? 0,
            hasGhost: !hover.hasPoint && hover.value != nil, rect: rect)
    }

    /// The frozen gesture's draft: one marker per point it would commit, the lane
    /// drawn through that replacement, and the value readout at the release point.
    func publishPreview() {
        let gestureProjection = frozen.map { makeProjection(facts: $0, camera: gestureCamera) }
        var draft = AutomationPreviewDraft.resolve(gesture: gesture, frozen: frozen)
        var edit: AutomationLaneEdit?
        var sweepRelease: AutomationLanePoint?
        if case let .pencil(transaction) = gesture { edit = transaction.preview }
        if case let .sweep(transaction) = gesture, let facts = frozen,
            let projection = gestureProjection
        {
            let finished = transaction.finishedPoints(fine: facts.modifiers.fine, projection: projection)
            edit = transaction.finish(fine: facts.modifiers.fine, projection: projection)
            sweepRelease = finished.last
            draft = AutomationPreviewDraft(
                parameter: facts.parameter, points: edit?.points ?? finished,
                text: sweepRelease.map { facts.metadata.valueText($0.value) } ?? "")
        }
        applyPreviewDraft(draft)
        applyPreviewEdit(edit)
        guard let facts = frozen, let projection = gestureProjection, !previewPoints.isEmpty else {
            publishDrawingContent()
            previewLabelVisible = false
            previewLabelText = ""
            updateRect(previewLabelRect, (0, 0, 0, 0))
            return
        }
        publishDrawingContent()
        let labelPoint: AutomationLanePoint?
        if case let .node(transaction) = gesture {
            labelPoint = transaction.grabbed?.current
        } else {
            labelPoint = sweepRelease ?? previewPoints.last
        }
        guard let last = labelPoint, !previewText.isEmpty else {
            previewLabelVisible = false
            previewLabelText = ""
            updateRect(previewLabelRect, (0, 0, 0, 0))
            return
        }
        previewLabelText = previewText
        previewLabelVisible = true
        updateRect(
            previewLabelRect,
            labelRect(
            text: previewText, tick: last.tick,
            x: projection.x(last.tick),
                valueY: projection.y(last.value, metadata: facts.metadata)))
    }

    func publishGhostNames(_ session: DocumentSession) {
        let height = captionMetrics?.height ?? fontPx(baseFontPx, 1)
        let pad = fontPx(baseFontPx, 0.5)
        let projected = ghostProjections(session)
        let font = typography.caption.qmlFont
        var labels: [SceneTextValue] = []
        for (index, lane) in projected.enumerated() {
            guard let value = lane.heldValue(at: lane.points.last?.tick ?? 0),
                index < ghostLabels.count
            else { continue }
            let text = ghostLabels[index]
            let width = min(
                max(0, plotWidth - 2 * pad),
                max(
                    fontPx(baseFontPx, 2),
                    (captionMetrics?.advance(text) ?? 0).rounded()))
            let projection = makeProjection(
                facts: facts(parameter: lane.parameter, modifiers: .init(), session: session),
                camera: session.camera)
            let curveY = projection.y(value, metadata: lane.metadata)
            let y = min(max(0, curveY - height / 2), max(0, plotHeight - height))
            labels.append(
                SceneTextValue(
                    rect: (max(0, plotWidth - width - pad), y, width, height),
                    text: text, color: palette.primaryText, font: font))
        }
        syncRetained(ghostNameLabels, labels, make: SceneText.init, update: { $0.update($1) })
    }

    func hoverGhostRect(
        text: String, x: Double, curveY: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let height = noteNameMetrics?.height ?? fontPx(baseFontPx, 1)
        let pad = fontPx(baseFontPx, 0.5)
        let width = min(
            max(0, plotWidth - 2 * pad),
            max(
                fontPx(baseFontPx, 2),
                (noteNameMetrics?.advance(text) ?? 0).rounded()))
        return (
            min(max(0, x - width / 2), max(0, plotWidth - width)),
            min(max(0, curveY - height - pad), max(0, plotHeight - height)),
            width, height)
    }

    /// A value label's own rectangle: font-sized, at the column the interaction
    /// works in, and clamped into the plot.
    func labelRect(
        text: String, tick: Tick, x: Double,
        valueY: Double?
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let height = noteNameMetrics?.height ?? fontPx(baseFontPx, 1)
        let width = max(fontPx(baseFontPx, 2), (noteNameMetrics?.advance(text) ?? 0).rounded())
        let gap = fontPx(baseFontPx, 1)
        let anchor = isPencilMode ? x + gap : xForTick(tick) + gap
        let originX = min(max(0, anchor), max(0, plotWidth - width))
        let centerY = valueY ?? plotHeight / 2
        let originY = min(max(0, centerY - height / 2), max(0, plotHeight - height))
        return (originX.rounded(), originY.rounded(), width, height)
    }

    /// The readout's own rectangle: the parameter title's width at the plot's
    /// top-right corner.
    func publishReadoutGeometry() {
        let height = titleMetrics?.height ?? fontPx(baseFontPx, 1)
        let pad = fontPx(baseFontPx, 0.5)
        let width = min(
            max(0, plotWidth - 2 * pad),
            max(fontPx(baseFontPx, 4), (titleMetrics?.advance(readoutText) ?? 0).rounded()))
        updateRect(
            readoutRect,
            (
            max(0, plotWidth - width - pad).rounded(), pad.rounded(),
                width, height
            ))
    }

    /// The open prompt's published form: the captured value form or the captured
    /// lane-delete confirmation.
    func publishPrompt() {
        refreshPromptStyles()
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
        syncModel(menuRows, values, matches: { $0.matches($1) })
        menuRowCount = values.count
        let children: [AutomationMenuRowHandle] =
            menu.flatMap { state in
                if case .lane = state.target { return rangeMenuRows(facts: state.facts) }
                return nil
            } ?? []
        menuChildRows.replaceSubrange(0..<menuChildRows.count, with: children)
        menuChildRowCount = children.count
        let open = menu != nil
        if menuOpen != open { menuOpen = open }
        publishHoverHintProfile()
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
        typography = Typography(baseFontPx: Int(baseFontPx.rounded()))
        captionMetrics = AutomationCaption(font: typography.caption)
        titleMetrics = AutomationCaption(font: typography.captionBold)
        noteNameMetrics = AutomationCaption(font: typography.noteName)
        publish(\.captionFont, typography.caption.qmlFont)
        publish(\.titleFont, typography.captionBold.qmlFont)
        publish(\.noteNameFont, typography.noteName.qmlFont)
        publish(\.minimumFont, typography.captionMinimum.qmlFont)
        publish(\.selectorInset, Double(typography.space(.one)))
        refreshPromptStyles()
        promptInputWidth = typography.fontPx(16)
        pipExtent = Double(typography.fontPx(0.5))
        minimumCellHeight = typography.fontPxF(4.0 / 3.0)
    }

    func refreshPromptStyles() {
        let metrics = PromptAppearance.Layout(base: baseFontPx)
        promptStyle.update(
            metrics: metrics, palette: palette, font: typography.body.qmlFont,
            surface: .automation)
        promptInputStyle.update(
            metrics: metrics, palette: palette, font: typography.body.qmlFont,
            surface: .input)
    }

    // MARK: Internals: shared metrics

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

    func updateRect(
        _ rect: SceneRect,
        _ value: (x: Double, y: Double, width: Double, height: Double)
    ) {
        _ = rect.update(
            SceneRectValue(
                x: value.x, y: value.y, width: value.width, height: value.height,
                fillColor: rect.fillColor, primitiveName: rect.primitiveName))
    }

    static func identityText(_ identity: AutomationPointIdentity) -> String {
        "\(identity.parameter)/\(identity.tick)/\(identity.occurrence)/\(identity.value)"
    }

    // MARK: Internals: model synchronisation

    func syncNodes(_ values: [AutomationNodeValue]) {
        syncRetained(nodes, values, make: AutomationNodeHandle.init, update: { $0.update($1) })
        if nodeCount != values.count { nodeCount = values.count }
        if nodeSnapshots.count > values.count {
            nodeSnapshots.removeSubrange(values.count..<nodeSnapshots.count)
        } else {
            for index in nodeSnapshots.count..<values.count {
                nodeSnapshots.append(nodes[index])
            }
        }
    }

}

/// Caption and title metrics for the page's own labels, measured through the same
/// native font-metrics seam the grid and the sibling pages use.
@MainActor
final class AutomationCaption {
    let height: Double
    private let metrics: NativeFontMetrics

    init(font: GridFontSpec) {
        metrics = NativeFontMetrics(font)
        height = metrics.extents.height
    }

    func advance(_ text: String) -> Double { metrics.advance(text) }
}
