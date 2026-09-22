import PorydawCore

// Plain automation scene values and construction. Document/session sampling,
// native measurement and Qt reconciliation stay at the adapter boundary.

struct AutomationScenePalette: Equatable, Sendable {
    var primaryText: String
    var secondaryText: String
    var gridLineSub1: String
    var gridLineSub2: String
    var gridLineSub3: String
    var gridLineBar: String
    var gridLineBeat: String
    var gridLineBeatFine: String
    var outline: String
    var noteBorder: String
    var selectionRing: String
    var selectionFill: String
    var selectionEdge: String
}

struct AutomationTypographyValues: Equatable, Sendable {
    var captionFont: GridFontSpec
    var titleFont: GridFontSpec
    var captionHeight: Double
    var titleHeight: Double
    var captionAdvances: [String: Double]
    var titleAdvances: [String: Double]

    static let empty = Self(
        captionFont: GridFontSpec(family: "", pixelSize: 0, weight: 400, letterSpacing: 0),
        titleFont: GridFontSpec(family: "", pixelSize: 0, weight: 600, letterSpacing: 0),
        captionHeight: 0, titleHeight: 0, captionAdvances: [:], titleAdvances: [:])

    func captionAdvance(_ text: String) -> Double {
        text.isEmpty ? 0 : captionAdvances[text]!
    }

    func titleAdvance(_ text: String) -> Double {
        text.isEmpty ? 0 : titleAdvances[text]!
    }
}

/// Projection facts needed by painting. The snapping policy stays in the input
/// adapter because a scene never snaps pointer input.
struct AutomationPaintProjection: Equatable, Sendable {
    var camera: EditorCamera.Snapshot
    var bounds: AutomationPlotBounds
    var geometry: AutomationPlotGeometry
    var displayMaximum: Int?

    init(_ projection: AutomationProjection) {
        camera = projection.camera.snapshot
        bounds = projection.bounds
        geometry = projection.geometry
        displayMaximum = projection.displayMaximum
    }

    func x(_ tick: Tick) -> Double {
        let value = Double(tick) * camera.pixelsPerTick - camera.scrollX
        let scale = bounds.devicePixelRatio
        return scale > 0 ? (value * scale).rounded() / scale : value
    }

    func y(_ value: Int, metadata: AutomationParameterMetadata) -> Double {
        let top = geometry.valuePlotPadding
        let bottom = max(top, bounds.height - geometry.valuePlotPadding)
        let clamped = Double(metadata.clamp(value))
        let span = max(1, (displayMaximum ?? metadata.maximum) - metadata.minimum)
        return bottom - (clamped - Double(metadata.minimum))
            * (bottom - top) / Double(span)
    }

    var markersVisible: Bool {
        camera.pixelsPerBeat >= geometry.pointDetailThreshold
    }
}

struct AutomationActiveSceneValue: Equatable, Sendable {
    var parameterIndex: Int
    var parameter: AutomationParameter
    var selectedTrack: Int?
    var trackAvailable: Bool
    var plotMessage: String
}

struct AutomationLaneSceneInput: Equatable, Sendable {
    var lane: AutomationLaneProjection
    var paint: AutomationPaintProjection
}

enum AutomationGridLineKind: Equatable, Sendable {
    case subdivision1
    case subdivision2
    case subdivision3
    case bar
    case beat
    case fineBeat
}

struct AutomationGridLineFact: Equatable, Sendable {
    var tick: Tick
    var kind: AutomationGridLineKind
}

struct AutomationGridSceneInput: Equatable, Sendable {
    var stroke: Double
    var lines: [AutomationGridLineFact]
}

/// Values sampled by the adapter before pure content construction.
struct AutomationContentSceneInput: Equatable, Sendable {
    var active: AutomationActiveSceneValue?
    var catalog: [AutomationParameter]
    var rows: [AutomationRow]
    var ghostPins: Set<AutomationParameter>
    var activeLane: AutomationLaneSceneInput?
    var ghostLanes: [AutomationLaneSceneInput]
    var selection: AutomationTimeSelection?
    var usedTracks: Set<Int>
    var grid: AutomationGridSceneInput?
    var bounds: AutomationPlotBounds
    var baseFontPx: Double
    var hover: AutomationHover?
    var palette: AutomationScenePalette

    static func detached(palette: AutomationScenePalette, baseFontPx: Double,
                         bounds: AutomationPlotBounds) -> Self {
        Self(active: nil, catalog: [], rows: [], ghostPins: [], activeLane: nil,
             ghostLanes: [], selection: nil, usedTracks: [], grid: nil,
             bounds: bounds, baseFontPx: baseFontPx, hover: nil, palette: palette)
    }
}

struct AutomationTabValue: Equatable, Sendable {
    var index: Int
    var label: String
    var tempo: Bool
    var active: Bool
    var ghosted: Bool
    var included: Bool
    var available: Bool
    var eventCount: Int
    var primitiveName = "automationParameterTab"
}

struct AutomationNodeValue: Equatable, Sendable {
    var x: Double
    var y: Double
    var tick: Double
    var value: Int
    var radius: Double
    var ringRadius: Double
    var outlineWidth: Double
    var fillColor: String
    var outlineColor: String
    var ringColor: String
    var selected: Bool
    var hovered: Bool
    var projected: Bool
    var phantom: Bool
    var identity: String
    var primitiveName = "automationNode"
}

struct AutomationRampValue: Equatable, Sendable {
    var x0: Double
    var y0: Double
    var dx: Double
    var dy: Double
    var color: String
    var primitiveName: String
}

struct AutomationMenuRowValue: Equatable, Sendable {
    var actionId: Int
    var text: String
    var enabled: Bool
    var separator: Bool
    var checkable: Bool
    var checked: Bool
    var hasSubmenu: Bool
    var shortcutText: String
    var primitiveName: String
}

struct AutomationContentScene: Equatable, Sendable {
    var active: AutomationActiveSceneValue?
    var parameterLabels: [String]
    var rows: [AutomationRow]
    var ghostParameters: [AutomationParameter]
    var ghostLabels: [String]
    var selectedParameters: [AutomationParameter]
    var projection: AutomationLaneProjection?
    var scaleLabels: [AutomationScaleLabel]
    var tabs: [AutomationTabValue]
    var gridLines: [DrawerRectValue]
    var valueLines: [DrawerRectValue]
    var valueLabels: [DrawerTextValue]
    var curveRuns: [DrawerRectValue]
    var ramps: [AutomationRampValue]
    var nodes: [AutomationNodeValue]
    var selectionRects: [DrawerRectValue]

    static let detached = Self(
        active: nil, parameterLabels: [], rows: [], ghostParameters: [],
        ghostLabels: [], selectedParameters: [], projection: nil, scaleLabels: [],
        tabs: [], gridLines: [], valueLines: [], valueLabels: [], curveRuns: [],
        ramps: [], nodes: [], selectionRects: [])
}

struct AutomationBandValue: Equatable, Sendable {
    var visible = false
    var rect = DrawerRectValue()
}

struct AutomationHoverValue: Equatable, Sendable {
    var visible = false
    var text = ""
    var rect = DrawerRectValue()
    var tick: Tick = 0
    var nodeTick: Double?
}

struct AutomationPreviewValue: Equatable, Sendable {
    var points: [AutomationLanePoint] = []
    var text = ""
    var rects: [DrawerRectValue] = []
    var labelVisible = false
    var labelRect = DrawerRectValue()
}

struct AutomationOverlayScene: Equatable, Sendable {
    var band = AutomationBandValue()
    var hover = AutomationHoverValue()
    var preview = AutomationPreviewValue()
}

struct AutomationContextPresentation: Equatable, Sendable {
    var tick: Tick = 0
    var value: Int?
    var readoutVisible = false
    var readoutText = ""
    var readoutRect = DrawerRectValue()
    var accessibleDescription = AutomationPagePolicy.accessibleName
    var contextChanged = false

    static func text(editCursor: Tick?, playing: Bool, presentedTick: Tick,
                     projection: AutomationLaneProjection?,
                     activeParameter: AutomationParameter) -> String {
        guard let editCursor else { return "" }
        let tick = playing ? presentedTick : editCursor
        guard let value = projection?.heldValue(at: tick) else { return "" }
        return "\(AutomationCatalog.title(activeParameter)) \(projection!.metadata.valueText(value))"
    }

    static func resolve(editCursor: Tick?, playing: Bool, presentedTick: Tick,
                        projection: AutomationLaneProjection?,
                        activeParameter: AutomationParameter, previousTick: Tick,
                        previousValue: Int?, bounds: AutomationPlotBounds,
                        baseFontPx: Double,
                        typography: AutomationTypographyValues) -> Self {
        guard let editCursor else { return Self() }
        let tick = playing ? presentedTick : editCursor
        let value = projection?.heldValue(at: tick)
        let title = AutomationCatalog.title(activeParameter)
        let valueText = value.map { projection?.metadata.valueText($0) ?? "" }
        let text = valueText.map { "\(title) \($0)" } ?? ""
        let visible = value != nil
        let pad = fontPx(baseFontPx, 0.5)
        let width = min(max(0, bounds.width - 2 * pad),
                        max(fontPx(baseFontPx, 4), typography.titleAdvance(text).rounded()))
        return Self(
            tick: tick, value: value, readoutVisible: visible, readoutText: text,
            readoutRect: DrawerRectValue(
                x: max(0, bounds.width - width - pad).rounded(), y: pad.rounded(),
                width: width, height: typography.titleHeight),
            accessibleDescription: visible ? "\(title). \(text)" : title,
            contextChanged: tick != previousTick || value != previousValue)
    }
}

struct AutomationPromptSceneInput: Sendable {
    var kind = AutomationPromptKind.value.rawValue
    var title = ""
    var label = ""
    var message = ""
    var minimum = 0
    var maximum = 0
    var draft = ""
    var error = ""
    var open = false
}

struct AutomationMenuSceneInput: Sendable {
    var x: Double = 0
    var y: Double = 0
    var rows: [AutomationMenuRowValue] = []
    var childRows: [AutomationMenuRowValue] = []
    var open = false
}

struct AutomationModalScene: Equatable, Sendable {
    var prompt = AutomationPromptSceneInput()
    var menu = AutomationMenuSceneInput()
}

extension AutomationPromptSceneInput: Equatable {}
extension AutomationMenuSceneInput: Equatable {}

struct AutomationTapTempoValue: Equatable, Sendable {
    var active = false
    var tapCount = 0
    var draftBpm = 0
    var idleCommitMs = AutomationTapTempoSession.gapMs
    var ready = false
}

struct AutomationInteractionValue: Equatable, Sendable {
    var active = false
    var hoverHintProfile = AutomationHintProfile.empty
}

struct AutomationScene: Equatable, Sendable {
    var content = AutomationContentScene.detached
    var overlay = AutomationOverlayScene()
    var context = AutomationContextPresentation()
    var modal = AutomationModalScene()
    var tapTempo = AutomationTapTempoValue()
    var interaction = AutomationInteractionValue()

    static let detached = Self()

    static func measurementLabels(_ input: AutomationContentSceneInput) -> [String] {
        input.activeLane?.lane.scaleLabels.map(\.text) ?? []
    }

    static func buildContent(_ input: AutomationContentSceneInput,
                             typography: AutomationTypographyValues)
        -> AutomationContentScene {
        guard let active = input.active else { return .detached }
        func row(_ parameter: AutomationParameter) -> AutomationRow? {
            input.rows.first { $0.parameter == parameter }
        }
        let ghostLanes = input.catalog.compactMap { parameter in
            input.ghostLanes.first {
                $0.lane.parameter == parameter && input.ghostPins.contains(parameter)
                    && $0.lane.eventCount != 0
            }
        }
        let ghostParameters = ghostLanes.map(\.lane.parameter)
        let ghostLabels = ghostLanes.map {
            let count = $0.lane.eventCount
            return AutomationCatalog.title($0.lane.parameter)
                + AutomationPagePolicy.ghostSeparator
                + (count == 1 ? "1 Event" : "\(count) Events")
        }
        let selectedParameters = active.selectedTrack.map { _ in
            input.catalog.filter { row($0)?.selectionHasEvents ?? false }
        } ?? []
        let tabs = input.catalog.enumerated().map { index, parameter in
            AutomationTabValue(
                index: index, label: AutomationCatalog.tabLabel(parameter),
                tempo: parameter.isTempo, active: index == active.parameterIndex,
                ghosted: ghostParameters.contains(parameter),
                included: selectedParameters.contains(parameter),
                available: active.trackAvailable || parameter.isTempo,
                eventCount: row(parameter)?.eventCount ?? 0)
        }
        guard let lane = input.activeLane else {
            return AutomationContentScene(
                active: active, parameterLabels: input.catalog.map(AutomationCatalog.tabLabel),
                rows: input.rows, ghostParameters: ghostParameters, ghostLabels: ghostLabels,
                selectedParameters: selectedParameters, projection: nil, scaleLabels: [],
                tabs: tabs, gridLines: [], valueLines: [], valueLabels: [], curveRuns: [],
                ramps: [], nodes: [], selectionRects: [])
        }
        let axis = valueAxis(lane.lane, input: input, typography: typography)
        var runs: [DrawerRectValue] = []
        var ramps: [AutomationRampValue] = []
        for ghost in ghostLanes {
            appendCurve(ghost.lane, paint: lane.paint, isGhost: true,
                        palette: input.palette, into: &runs, ramps: &ramps)
        }
        appendCurve(lane.lane, paint: lane.paint, isGhost: false,
                    palette: input.palette, into: &runs, ramps: &ramps)
        return AutomationContentScene(
            active: active, parameterLabels: input.catalog.map(AutomationCatalog.tabLabel),
            rows: input.rows, ghostParameters: ghostParameters, ghostLabels: ghostLabels,
            selectedParameters: selectedParameters, projection: lane.lane,
            scaleLabels: lane.lane.scaleLabels, tabs: tabs,
            gridLines: gridValues(input, paint: lane.paint), valueLines: axis.lines,
            valueLabels: axis.labels, curveRuns: runs, ramps: ramps,
            nodes: nodeValues(lane.lane, paint: lane.paint, input: input),
            selectionRects: selectionValues(lane.lane, paint: lane.paint, input: input))
    }


    static func bandValue(_ band: AutomationRangeBand?, paint: AutomationPaintProjection?)
        -> AutomationBandValue {
        guard let band, band.active, let paint else { return AutomationBandValue() }
        let limit = max(0, paint.bounds.width)
        let x0 = min(max(0, paint.x(min(band.anchorTick, band.currentTick))), limit)
        let x1 = min(max(0, paint.x(max(band.anchorTick, band.currentTick))), limit)
        return AutomationBandValue(
            visible: true,
            rect: DrawerRectValue(x: x0, y: 0, width: max(0, x1 - x0),
                                  height: paint.bounds.height))
    }

    static func hoverValue(_ hover: AutomationHover?, pointerX: Double,
                           isPencilMode: Bool, activeParameter: AutomationParameter,
                           paint: AutomationPaintProjection?,
                           metadata: AutomationParameterMetadata?, baseFontPx: Double,
                           typography: AutomationTypographyValues)
        -> AutomationHoverValue {
        guard let hover, let paint, let metadata else { return AutomationHoverValue() }
        let rect = labelRect(
            text: hover.text, tick: hover.tick, x: pointerX,
            valueY: hover.value.map { paint.y($0, metadata: metadata) },
            isPencilMode: isPencilMode, paint: paint, baseFontPx: baseFontPx,
            typography: typography)
        let nodeTick = hover.hasPoint && hover.parameter == activeParameter
            ? Double(hover.tick) : nil
        return AutomationHoverValue(
            visible: true, text: hover.text, rect: rect, tick: hover.tick, nodeTick: nodeTick)
    }

    static func previewValue(draft: AutomationPreviewDraft,
                             frozen: AutomationFrozenFacts?,
                             activeParameter: AutomationParameter,
                             paint: AutomationPaintProjection?, baseFontPx: Double,
                             palette: AutomationScenePalette,
                             typography: AutomationTypographyValues)
        -> AutomationPreviewValue {
        let points = draft.parameter == activeParameter ? draft.points : []
        let text = draft.parameter == activeParameter ? draft.text : ""
        guard let frozen, let paint, !points.isEmpty else {
            return AutomationPreviewValue(points: points, text: text)
        }
        let extent = fontPxF(baseFontPx, 3.0 / 16.0)
        let limit = max(0, paint.bounds.width)
        let rects = points.map { point in
            DrawerRectValue(
                x: (min(max(0, paint.x(point.tick)), limit) - extent).rounded(),
                y: (paint.y(point.value, metadata: frozen.metadata) - extent).rounded(),
                width: 2 * extent, height: 2 * extent,
                fillColor: palette.selectionEdge, primitiveName: "automationPreviewNode")
        }
        guard let last = draft.labelPoint, !text.isEmpty else {
            return AutomationPreviewValue(points: points, text: text, rects: rects)
        }
        return AutomationPreviewValue(
            points: points, text: text, rects: rects, labelVisible: true,
            labelRect: labelRect(
                text: text, tick: last.tick, x: paint.x(last.tick),
                valueY: paint.y(last.value, metadata: frozen.metadata),
                isPencilMode: false, paint: paint, baseFontPx: baseFontPx,
                typography: typography))
    }

    private static func gridValues(_ input: AutomationContentSceneInput,
                                   paint: AutomationPaintProjection)
        -> [DrawerRectValue] {
        guard input.bounds.height > 0, input.bounds.width > 0,
              let grid = input.grid else { return [] }
        return grid.lines.map { line in
            let color: String
            switch line.kind {
            case .subdivision1: color = input.palette.gridLineSub1
            case .subdivision2: color = input.palette.gridLineSub2
            case .subdivision3: color = input.palette.gridLineSub3
            case .bar: color = input.palette.gridLineBar
            case .beat: color = input.palette.gridLineBeat
            case .fineBeat: color = input.palette.gridLineBeatFine
            }
            return DrawerRectValue(
                x: paint.x(line.tick) - grid.stroke / 2, y: 0, width: grid.stroke,
                height: input.bounds.height, fillColor: color,
                primitiveName: "automationGrid")
        }
    }

    private static func valueAxis(_ lane: AutomationLaneProjection,
                                  input: AutomationContentSceneInput,
                                  typography: AutomationTypographyValues)
        -> (lines: [DrawerRectValue], labels: [DrawerTextValue]) {
        let stroke = max(1, fontPxF(input.baseFontPx, 1.0 / 12.0))
        let pad = max(1, (input.baseFontPx / 4).rounded())
        var lines: [DrawerRectValue] = []
        var labels: [DrawerTextValue] = []
        for label in lane.scaleLabels {
            lines.append(DrawerRectValue(
                x: 0, y: (label.y - stroke / 2).rounded(), width: input.bounds.width,
                height: stroke, fillColor: input.palette.gridLineSub2,
                primitiveName: "automationValueRule"))
            let width = max(fontPx(input.baseFontPx, 2),
                            typography.captionAdvance(label.text).rounded())
            let y = min(max(0, label.y - typography.captionHeight / 2),
                        max(0, input.bounds.height - typography.captionHeight))
            labels.append(DrawerTextValue(
                rect: DrawerRectValue(x: Double(pad), y: y.rounded(), width: width,
                                      height: typography.captionHeight),
                text: label.text, color: input.palette.secondaryText,
                font: typography.captionFont))
        }
        return (lines, labels)
    }

    private static func appendCurve(_ lane: AutomationLaneProjection,
                                    paint: AutomationPaintProjection,
                                    isGhost: Bool, palette: AutomationScenePalette,
                                    into runs: inout [DrawerRectValue],
                                    ramps: inout [AutomationRampValue]) {
        guard !lane.points.isEmpty else { return }
        let stroke = 2.0
        let color = isGhost ? palette.outline : palette.primaryText
        let name = isGhost ? "automationGhostCurve" : "automationCurve"
        let limit = max(0, paint.bounds.width)
        for (index, segment) in lane.segments.enumerated() {
            let x0 = min(max(0, paint.x(segment.tickBegin)), limit)
            let x1 = min(max(0, segment.tickEnd.map(paint.x) ?? limit), limit)
            guard x1 >= x0 else { continue }
            let fromY = paint.y(segment.fromValue, metadata: lane.metadata)
            switch segment.kind {
            case .step:
                if x1 > x0 {
                    runs.append(DrawerRectValue(
                        x: x0, y: (fromY - stroke / 2).rounded(), width: x1 - x0,
                        height: stroke, fillColor: color, primitiveName: name))
                }
            case .ramp:
                if x1 > x0 {
                    ramps.append(AutomationRampValue(
                        x0: x0, y0: (fromY - stroke / 2).rounded(), dx: x1 - x0,
                        dy: paint.y(segment.toValue, metadata: lane.metadata) - fromY,
                        color: color, primitiveName: name))
                }
            }
            let next = index + 1 < lane.segments.count ? lane.segments[index + 1] : nil
            if segment.kind == .step, let next, next.fromValue != segment.fromValue,
               let end = segment.tickEnd, paint.x(end) >= -stroke / 2,
               paint.x(end) <= limit + stroke / 2 {
                let nextY = paint.y(next.fromValue, metadata: lane.metadata)
                runs.append(DrawerRectValue(
                    x: (x1 - stroke / 2).rounded(), y: min(fromY, nextY).rounded(),
                    width: stroke, height: max(stroke, abs(nextY - fromY)),
                    fillColor: color, primitiveName: name))
            }
        }
    }

    private static func nodeValues(_ lane: AutomationLaneProjection,
                                   paint: AutomationPaintProjection,
                                   input: AutomationContentSceneInput)
        -> [AutomationNodeValue] {
        guard paint.markersVisible else { return [] }
        let nodeRadius = fontPxF(input.baseFontPx, 3.0 / 16.0)
        let ringRadius = fontPxF(input.baseFontPx, 9.0 / 32.0)
        let outlineWidth = fontPxF(input.baseFontPx, 1.0 / 12.0)
        func value(_ point: AutomationProjectedPoint, phantom: Bool) -> AutomationNodeValue {
            AutomationNodeValue(
                x: phantom ? 0 : paint.x(point.tick), y: point.y, tick: Double(point.tick),
                value: point.value, radius: nodeRadius, ringRadius: ringRadius,
                outlineWidth: outlineWidth,
                fillColor: point.projected ? input.palette.secondaryText : input.palette.primaryText,
                outlineColor: input.palette.noteBorder, ringColor: input.palette.selectionRing,
                selected: point.selected,
                hovered: input.hover?.hasPoint == true
                    && input.hover?.parameter == lane.parameter && input.hover?.tick == point.tick,
                projected: point.projected, phantom: phantom,
                identity: identityText(point.identity))
        }
        var values: [AutomationNodeValue] = []
        if let phantom = lane.originPhantom { values.append(value(phantom.point, phantom: true)) }
        let radius = max(nodeRadius, ringRadius) + outlineWidth
        let begin = automationPartitionIndex(lane.points) { $0.x < -radius }
        let end = automationPartitionIndex(lane.points) { $0.x <= input.bounds.width + radius }
        for point in lane.points[begin..<end] { values.append(value(point, phantom: false)) }
        return values
    }

    private static func selectionValues(_ lane: AutomationLaneProjection,
                                        paint: AutomationPaintProjection,
                                        input: AutomationContentSceneInput)
        -> [DrawerRectValue] {
        guard let selection = input.selection, selection.isActive,
              selection.covers(lane.parameter, usedTracks: input.usedTracks) else { return [] }
        let limit = max(0, input.bounds.width)
        let x0 = min(max(0, paint.x(selection.range.startTick)), limit)
        let x1 = min(max(0, paint.x(selection.range.endTick)), limit)
        guard x1 > x0 else { return [] }
        let stroke = 1.0
        return [
            DrawerRectValue(x: x0, y: 0, width: x1 - x0, height: input.bounds.height,
                            fillColor: input.palette.selectionFill,
                            primitiveName: "automationSelectionFill"),
            DrawerRectValue(x: x0, y: 0, width: stroke, height: input.bounds.height,
                            fillColor: input.palette.selectionEdge,
                            primitiveName: "automationSelectionEdge"),
            DrawerRectValue(x: (x1 - stroke).rounded(), y: 0, width: stroke,
                            height: input.bounds.height,
                            fillColor: input.palette.selectionEdge,
                            primitiveName: "automationSelectionEdge"),
        ]
    }

    private static func labelRect(text: String, tick: Tick, x: Double, valueY: Double?,
                                  isPencilMode: Bool,
                                  paint: AutomationPaintProjection,
                                  baseFontPx: Double,
                                  typography: AutomationTypographyValues)
        -> DrawerRectValue {
        let width = max(fontPx(baseFontPx, 2), typography.captionAdvance(text).rounded())
        let gap = fontPx(baseFontPx, 1)
        let anchor = isPencilMode ? x + gap : paint.x(tick) + gap
        let originX = min(max(0, anchor), max(0, paint.bounds.width - width))
        let centerY = valueY ?? paint.bounds.height / 2
        let originY = min(max(0, centerY - typography.captionHeight / 2),
                          max(0, paint.bounds.height - typography.captionHeight))
        return DrawerRectValue(x: originX.rounded(), y: originY.rounded(), width: width,
                               height: typography.captionHeight)
    }

    private static func identityText(_ identity: AutomationPointIdentity) -> String {
        "\(identity.parameter)/\(identity.tick)/\(identity.occurrence)/\(identity.value)"
    }
}

/// The plain gesture draft one preview derives from frozen input.
struct AutomationPreviewDraft: Equatable, Sendable {
    let parameter: AutomationParameter?
    let points: [AutomationLanePoint]
    let labelPoint: AutomationLanePoint?
    let text: String

    static let empty = Self(parameter: nil, points: [], labelPoint: nil, text: "")

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
        return Self(
            parameter: frozen?.parameter, points: points, labelPoint: labelPoint, text: text)
    }
}

/// Sanitized body input plus the exact invalidation decisions it produces.
struct AutomationBodySceneConfiguration: Equatable, Sendable {
    let plotWidth: Double
    let plotHeight: Double
    let devicePixelRatio: Double
    let plotOrigin: Double
    let dragDistance: Double
    let baseFontPx: Double
    let geometry: AutomationPlotGeometry?
    let fontChanged: Bool
    let changed: Bool

    static func resolve(width: Double, height: Double, gutter: Double,
                        devicePixelRatio: Double, baseFontPx: Double,
                        dragDistance: Double, currentWidth: Double,
                        currentHeight: Double, currentDevicePixelRatio: Double,
                        currentOrigin: Double, currentDragDistance: Double,
                        currentBaseFontPx: Double) -> Self {
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
            plotWidth: nextWidth, plotHeight: nextHeight, devicePixelRatio: nextDpr,
            plotOrigin: nextOrigin, dragDistance: nextDrag, baseFontPx: nextFont,
            geometry: fontChanged ? AutomationPlotGeometry(baseFontPx: nextFont) : nil,
            fontChanged: fontChanged, changed: changed)
    }
}

enum AutomationHintProfile {
    static let empty = 0
    static let node = 15
    static let originPhantom = 16
    static let sweep = 17
    static let pencil = 18
}

enum AutomationInteractionActivity {
    static func resolve(hasGesture: Bool, hasPrompt: Bool, hasLaneDelete: Bool,
                        hasMenu: Bool, hasBand: Bool, isPanning: Bool,
                        hasTapSession: Bool) -> Bool {
        hasGesture || hasPrompt || hasLaneDelete || hasMenu || hasBand
            || isPanning || hasTapSession
    }

    static func hintProfile(hover: AutomationHover?, isPencilMode: Bool) -> Int {
        guard let hover else { return AutomationHintProfile.empty }
        switch (!isPencilMode || hover.nodeMarkersVisible, hover.hintTarget) {
        case (true, .originPhantom): return AutomationHintProfile.originPhantom
        case (true, .node): return AutomationHintProfile.node
        default: return isPencilMode ? AutomationHintProfile.pencil : AutomationHintProfile.sweep
        }
    }
}
