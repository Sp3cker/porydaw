import NativeGridTypography
import PorydawCore
import QtBridge

// Automation overlay publication: the pointer-, band- and gesture-dependent
// primitives, the label/readout geometry, the prompt, menu and tap-tempo
// publications, the typography metrics, and the shared metrics and model
// synchronisation every publication routes through.

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
        // Hover is an overlay-only update: refresh the changed node roles
        // without rebuilding lane geometry or replacing unaffected delegates.
        let hoveredTick = hover.flatMap {
            $0.hasPoint && $0.parameter == activeParameter ? Double($0.tick) : nil
        }
        for (index, node) in nodeSnapshots.enumerated() {
            let hovered = hoveredTick == node.tick
            if node.hovered != hovered {
                node.hovered = hovered
                nodes[index] = node
            }
        }
        guard let session, let hover else {
            let wasVisible = hoverVisible
            hoverVisible = false
            hoverText = ""
            hoverTick = 0
            hoverLabelRect = Self.rect(0, 0, 0, 0)
            if wasVisible {
                hoverDisplay = [
                    "visible": false, "text": "", "hasNode": false, "nodeTick": 0.0,
                    "x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0,
                ]
            }
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
        hoverDisplay = [
            "visible": true, "text": hover.text, "hasNode": hoveredTick != nil,
            "nodeTick": hoveredTick ?? 0.0,
            "x": hoverLabelRect["x"] ?? 0.0, "y": hoverLabelRect["y"] ?? 0.0,
            "width": hoverLabelRect["width"] ?? 0.0,
            "height": hoverLabelRect["height"] ?? 0.0,
        ]
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
        let height = noteNameMetrics?.height ?? fontPx(baseFontPx, 1)
        let width = max(fontPx(baseFontPx, 2), (noteNameMetrics?.advance(text) ?? 0).rounded())
        let gap = fontPx(baseFontPx, 1)
        let anchor = isPencilMode ? x + gap : xForTick(tick) + gap
        let originX = min(max(0, anchor), max(0, plotWidth - width))
        let centerY = valueY ?? plotHeight / 2
        let originY = min(max(0, centerY - height / 2), max(0, plotHeight - height))
        return Self.rect(originX.rounded(), originY.rounded(), width, height)
    }

    /// The readout's own rectangle: the parameter title's width at the plot's
    /// top-right corner.
    func publishReadoutGeometry() {
        let height = titleMetrics?.height ?? fontPx(baseFontPx, 1)
        let pad = fontPx(baseFontPx, 0.5)
        let width = min(max(0, plotWidth - 2 * pad),
                        max(fontPx(baseFontPx, 4), (titleMetrics?.advance(readoutText) ?? 0).rounded()))
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
        let typography = Typography(baseFontPx: Int(baseFontPx.rounded()))
        captionMetrics = AutomationCaption(font: typography.caption)
        titleMetrics = AutomationCaption(font: typography.captionBold)
        noteNameMetrics = AutomationCaption(font: typography.noteName)
        setFont(&captionFont, typography.caption.map)
        setFont(&titleFont, typography.captionBold.map)
        setFont(&noteNameFont, typography.noteName.map)
        setFont(&minimumFont, typography.captionMinimum.map)
        promptAppearance = PromptAppearance.metrics(base: baseFontPx)
        setFont(&promptFont, PromptAppearance.font(typography: typography))
        promptInputWidth = typography.fontPx(16)
        pipExtent = Double(typography.fontPx(0.5))
        minimumCellHeight = typography.fontPxF(4.0 / 3.0)
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
