import PorydawCore

// Automation scene-state vocabulary: the document-derived snapshot one static
// build produces, the gesture preview draft, the effective-context values, the
// sanitized body input, and the interaction-activity rollup. Primitive
// publication lives in the sibling publication files; the bridged records in
// AutomationHandles.swift.

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
