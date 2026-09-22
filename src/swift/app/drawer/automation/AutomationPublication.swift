import NativeGridTypography
import PorydawCore
import QtBridge

struct AutomationPublicationScope: OptionSet, Sendable {
    let rawValue: UInt16

    static let body = Self(rawValue: 1 << 0)
    static let typography = Self(rawValue: 1 << 1)
    static let content = Self(rawValue: 1 << 2)
    static let band = Self(rawValue: 1 << 3)
    static let hover = Self(rawValue: 1 << 4)
    static let preview = Self(rawValue: 1 << 5)
    static let context = Self(rawValue: 1 << 6)
    static let prompt = Self(rawValue: 1 << 7)
    static let menu = Self(rawValue: 1 << 8)
    static let tapTempo = Self(rawValue: 1 << 9)
    static let interaction = Self(rawValue: 1 << 10)
    static let hoverHint = Self(rawValue: 1 << 11)
    static let clear = Self(rawValue: 1 << 12)
}

/// The MainActor adapter owns revision-keyed document facts, projection policy
/// and native font handles. Only immutable values cross into AutomationScene.
@MainActor
final class AutomationSceneAdapter {
    private var sessionID: ObjectIdentifier?
    private var revision: UInt64?
    private var songEnd: Tick?
    private var lanes: [AutomationParameter: AutomationLaneSnapshot] = [:]
    private var rowFacts: AutomationRowStack?
    private var rowTrack: Int?
    private var rowSelection: AutomationTimeSelection?
    private var rowReady = false
    private var rowUsedTracks = -1
    private var snapping: AutomationSnapPolicy?
    private var snapFont = 0.0
    private var snapDpr = 0.0
    private var policies: [AutomationParameter: (
        revision: UInt64, range: Int?, font: Double, projection: AutomationProjection)] = [:]

    private var typographyPixelSize = 0
    private var caption: AutomationNativeCaption?
    private var title: AutomationNativeCaption?
    private var captionAdvances: [String: Double] = [:]
    private var titleAdvances: [String: Double] = [:]

    private func refresh(_ session: DocumentSession) {
        let id = ObjectIdentifier(session)
        guard sessionID != id || revision != session.document.revision
            || songEnd != session.timeline.lengthTicks else { return }
        sessionID = id
        revision = session.document.revision
        songEnd = session.timeline.lengthTicks
        lanes.removeAll(keepingCapacity: true)
        rowFacts = nil
        snapping = nil
        policies.removeAll(keepingCapacity: true)
    }

    func snapshot(_ parameter: AutomationParameter,
                  session: DocumentSession) -> AutomationLaneSnapshot {
        refresh(session)
        if let snapshot = lanes[parameter] { return snapshot }
        let points = parameter.lane.flatMap { lane in
            parameter.track.map { session.projectionCache.lanePoints(track: $0, lane: lane) }
        }
        let snapshot = AutomationLaneSnapshot(
            parameter: parameter, in: session.document,
            songEndTick: session.timeline.lengthTicks, lanePoints: points)
        lanes[parameter] = snapshot
        return snapshot
    }

    func rows(session: DocumentSession, track: Int?, selection: AutomationTimeSelection?,
              ready: Bool) -> AutomationRowStack {
        refresh(session)
        let used = session.document.engineTracks.usedTrackCount
        if let rowFacts, rowTrack == track, rowSelection == selection,
           rowReady == ready, rowUsedTracks == used { return rowFacts }
        let value = AutomationRowStack.build(
            document: session.document, primaryTrack: track, selection: selection,
            ready: ready, songEndTick: session.timeline.lengthTicks,
            snapshot: { self.snapshot($0, session: session) })
        rowTrack = track
        rowSelection = selection
        rowReady = ready
        rowUsedTracks = used
        rowFacts = value
        return value
    }

    func projection(snapshot: AutomationLaneSnapshot, session: DocumentSession,
                    camera: EditorCamera, bounds: AutomationPlotBounds,
                    geometry: AutomationPlotGeometry, font: Double,
                    range: Int?) -> AutomationProjection {
        refresh(session)
        if let cached = policies[snapshot.parameter], cached.revision == snapshot.revision,
           cached.range == range, cached.font == font,
           cached.projection.camera.snapshot == camera.snapshot,
           cached.projection.bounds == bounds, cached.projection.geometry == geometry,
           cached.projection.songEndTick == snapshot.songEndTick {
            return cached.projection
        }
        let value = AutomationProjection(
            camera: camera, bounds: bounds, geometry: geometry,
            snapPolicy: snapPolicy(session: session, font: font, dpr: bounds.devicePixelRatio),
            songEndTick: snapshot.songEndTick,
            displayMaximum: AutomationProjection.displayMaximum(snapshot: snapshot, range: range))
        policies[snapshot.parameter] = (snapshot.revision, range, font, value)
        return value
    }

    func snapPolicy(session: DocumentSession, font: Double, dpr: Double)
        -> AutomationSnapPolicy {
        refresh(session)
        if let snapping, snapFont == font, snapDpr == dpr { return snapping }
        let value = AutomationSnapPolicy(
            baseFontPx: font, devicePixelRatio: dpr,
            timeAxis: session.projectionCache.timeAxis,
            clockTicks: TimelineSnapPolicy.clockTicks(
                division: session.document.ticksPerBeat,
                extendedClocks: session.document.state.config.extendedClocks))
        snapping = value
        snapFont = font
        snapDpr = dpr
        return value
    }

    private func typographyHandles(baseFontPx: Double)
        -> (caption: AutomationNativeCaption, title: AutomationNativeCaption) {
        let pixelSize = max(1, Int(baseFontPx.rounded()))
        if typographyPixelSize != pixelSize || caption == nil || title == nil {
            typographyPixelSize = pixelSize
            caption = AutomationNativeCaption(pixelSize: pixelSize, weight: 400)
            title = AutomationNativeCaption(pixelSize: pixelSize, weight: 600)
            captionAdvances.removeAll(keepingCapacity: true)
            titleAdvances.removeAll(keepingCapacity: true)
        }
        return (caption!, title!)
    }

    private func typographyValues(
        _ handles: (caption: AutomationNativeCaption, title: AutomationNativeCaption)
    ) -> AutomationTypographyValues {
        AutomationTypographyValues(
            captionFont: handles.caption.spec, titleFont: handles.title.spec,
            captionHeight: handles.caption.height, titleHeight: handles.title.height,
            captionAdvances: captionAdvances, titleAdvances: titleAdvances)
    }

    func typography(baseFontPx: Double, captionLabels: [String],
                    titleLabels: [String]) -> AutomationTypographyValues {
        let handles = typographyHandles(baseFontPx: baseFontPx)
        for label in captionLabels where !label.isEmpty && captionAdvances[label] == nil {
            captionAdvances[label] = handles.caption.advance(label)
        }
        for label in titleLabels where !label.isEmpty && titleAdvances[label] == nil {
            titleAdvances[label] = handles.title.advance(label)
        }
        return typographyValues(handles)
    }

    func typography(baseFontPx: Double, captionLabel: String?,
                    titleLabel: String?) -> AutomationTypographyValues {
        let handles = typographyHandles(baseFontPx: baseFontPx)
        if let captionLabel, !captionLabel.isEmpty, captionAdvances[captionLabel] == nil {
            captionAdvances[captionLabel] = handles.caption.advance(captionLabel)
        }
        if let titleLabel, !titleLabel.isEmpty, titleAdvances[titleLabel] == nil {
            titleAdvances[titleLabel] = handles.title.advance(titleLabel)
        }
        return typographyValues(handles)
    }
}

@MainActor
private final class AutomationNativeCaption {
    let spec: GridFontSpec
    let height: Double
    private let session: OpaquePointer

    init(pixelSize: Int, weight: Int) {
        spec = GridFontSpec(
            family: AutomationPage.fontFamily, pixelSize: pixelSize,
            weight: weight, letterSpacing: 0)
        session = AutomationPage.fontFamily.withCString {
            sgf_create($0, Int32(pixelSize), Int32(weight), 0)!
        }
        height = sgf_extents(session).height
    }

    isolated deinit { sgf_destroy(session) }

    func advance(_ text: String) -> Double {
        text.withCString { sgf_advance(session, $0) }
    }
}

@MainActor
extension AutomationPage {
    // MARK: Document/input adapter

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
        return AutomationFrozenFacts(
            parameter: parameter, snapshot: snapshot, camera: session.camera.snapshot,
            selection: selection, modifiers: modifiers,
            songEndTick: session.timeline.lengthTicks)
    }

    var gestureCamera: EditorCamera { frozenCamera ?? liveCamera() }

    func liveCamera() -> EditorCamera {
        guard let session else {
            return EditorCamera(
                ticksPerBeat: 24, lengthTicks: nil, viewportWidth: 0, rollHeight: 0,
                limits: GridCameraPolicy.limits(baseFontPx: GridCameraPolicy.seedBaseFontPx))
        }
        return session.camera
    }

    func makeProjection(facts: AutomationFrozenFacts,
                        camera: EditorCamera) -> AutomationProjection {
        let bounds = plotBounds
        if let session {
            return projectionFacts.projection(
                snapshot: facts.snapshot, session: session, camera: camera,
                bounds: bounds, geometry: geometry, font: baseFontPx,
                range: laneRanges[facts.parameter])
        }
        return AutomationProjection(
            camera: camera, bounds: bounds, geometry: geometry,
            snapPolicy: AutomationSnapPolicy(
                baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                timeAxis: TimeAxis(), clockTicks: 1),
            songEndTick: facts.songEndTick,
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

    private var plotBounds: AutomationPlotBounds {
        AutomationPlotBounds(
            width: plotWidth, height: plotHeight, devicePixelRatio: devicePixelRatio)
    }

    private var scenePalette: AutomationScenePalette {
        AutomationScenePalette(
            primaryText: palette.primaryText, secondaryText: palette.secondaryText,
            gridLineSub1: palette.gridLineSub1, gridLineSub2: palette.gridLineSub2,
            gridLineSub3: palette.gridLineSub3, gridLineBar: palette.gridLineBar,
            gridLineBeat: palette.gridLineBeat, gridLineBeatFine: palette.gridLineBeatFine,
            outline: palette.outline, noteBorder: palette.noteBorder,
            selectionRing: palette.selectionRing, selectionFill: palette.selectionFill,
            selectionEdge: palette.selectionEdge)
    }
    private func gridSceneInput(session: DocumentSession,
                                bounds: AutomationPlotBounds) -> AutomationGridSceneInput {
        let camera = session.camera
        let metrics = GridMetrics(
            baseFontPx: baseFontPx, dpr: devicePixelRatio,
            width: plotWidth, height: plotHeight,
            timeAxis: session.projectionCache.timeAxis)
        guard bounds.height > 0, bounds.width > 0 else {
            return AutomationGridSceneInput(stroke: metrics.gridLineStroke, lines: [])
        }
        let physicalPixel = max(metrics.pixel, 0.0001)
        let margin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-margin)
        let endTick = camera.tickAtContentX(bounds.width - physicalPixel + margin) + 1
        guard endTick > beginTick else {
            return AutomationGridSceneInput(stroke: metrics.gridLineStroke, lines: [])
        }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        var lines: [AutomationGridLineFact] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) {
            tick, level in
            let kind: AutomationGridLineKind = level == 1 ? .subdivision1
                : level == 2 ? .subdivision2 : .subdivision3
            lines.append(AutomationGridLineFact(tick: tick, kind: kind))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) {
            tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            let kind: AutomationGridLineKind = isBar ? .bar : finest ? .fineBeat : .beat
            lines.append(AutomationGridLineFact(tick: tick, kind: kind))
        }
        return AutomationGridSceneInput(stroke: metrics.gridLineStroke, lines: lines)
    }


    private func contentSceneInput() -> AutomationContentSceneInput {
        guard let session else {
            return .detached(palette: scenePalette, baseFontPx: baseFontPx, bounds: plotBounds)
        }
        let track = activeTrack()
        let index = min(max(activeParameterIndex, 0), AutomationCatalog.count - 1)
        let parameter = AutomationCatalog.parameter(at: index, track: track ?? 0) ?? .tempo
        let trackAvailable = track != nil
        let message = track == nil && !parameter.isTempo
            ? AutomationPagePolicy.noTrackMessage : ""
        let catalog = AutomationCatalog.parameters(track: track ?? 0)
        let rows = projectionFacts.rows(
            session: session, track: track, selection: selection,
            ready: track != nil).visibleRows
        let bounds = plotBounds
        let used = usedTracks()
        func lane(_ parameter: AutomationParameter) -> AutomationLaneSceneInput {
            let snapshot = projectionFacts.snapshot(parameter, session: session)
            let projection = projectionFacts.projection(
                snapshot: snapshot, session: session, camera: session.camera,
                bounds: bounds, geometry: geometry, font: baseFontPx,
                range: laneRanges[parameter])
            return AutomationLaneSceneInput(
                lane: projection.project(snapshot, selection: selection, usedTracks: used),
                paint: AutomationPaintProjection(projection))
        }
        let activeLane = message.isEmpty ? lane(parameter) : nil
        let ghosts = activeLane == nil
            ? [] : catalog.filter { ghostPins.contains($0) }.map(lane)
        return AutomationContentSceneInput(
            active: AutomationActiveSceneValue(
                parameterIndex: index, parameter: parameter, selectedTrack: track,
                trackAvailable: trackAvailable, plotMessage: message),
            catalog: catalog, rows: rows, ghostPins: ghostPins,
            activeLane: activeLane, ghostLanes: ghosts, selection: selection,
            usedTracks: used,
            grid: activeLane == nil ? nil : gridSceneInput(session: session, bounds: bounds),
            bounds: bounds, baseFontPx: baseFontPx, hover: hover, palette: scenePalette)
    }

    private func paintProjection(parameter: AutomationParameter,
                                 camera: EditorCamera) -> AutomationPaintProjection? {
        guard let session else { return nil }
        let facts = facts(parameter: parameter, modifiers: .init(), session: session)
        return AutomationPaintProjection(makeProjection(facts: facts, camera: camera))
    }

    private func promptSceneInput() -> AutomationPromptSceneInput {
        if let prompt {
            return AutomationPromptSceneInput(
                kind: AutomationPromptKind.value.rawValue, title: prompt.prompt.title,
                label: prompt.prompt.label, message: "", minimum: prompt.prompt.minimum,
                maximum: prompt.prompt.maximum, draft: promptDraft,
                error: promptError, open: true)
        }
        if let laneDelete {
            return AutomationPromptSceneInput(
                kind: AutomationPromptKind.confirmLaneDelete.rawValue,
                title: laneDelete.title, label: "", message: laneDelete.message,
                minimum: 0, maximum: 0, draft: promptDraft,
                error: promptError, open: true)
        }
        return AutomationPromptSceneInput()
    }

    private func menuSceneInput() -> AutomationMenuSceneInput {
        guard let menu else { return AutomationMenuSceneInput() }
        let children: [AutomationMenuRowValue]
        if case .lane = menu.target {
            children = rangeMenuRows(facts: menu.facts).map(menuValue)
        } else {
            children = []
        }
        return AutomationMenuSceneInput(
            x: menu.anchorX, y: menu.anchorY, rows: menu.rows.map(menuValue),
            childRows: children, open: true)
    }

    private func menuValue(_ row: AutomationMenuRowHandle) -> AutomationMenuRowValue {
        AutomationMenuRowValue(
            actionId: row.actionId, text: row.text, enabled: row.enabled,
            separator: row.separator, checkable: row.checkable, checked: row.checked,
            hasSubmenu: row.hasSubmenu, shortcutText: row.shortcutText,
            primitiveName: row.primitiveName)
    }

    // MARK: Single publication pass

    func publish(_ scope: AutomationPublicationScope,
                 body configuration: AutomationBodySceneConfiguration? = nil) {
        if let configuration, scope.contains(.body) {
            setPublished(&plotWidth, configuration.plotWidth)
            setPublished(&plotHeight, configuration.plotHeight)
            setPublished(&devicePixelRatio, configuration.devicePixelRatio)
            setPublished(&plotOrigin, configuration.plotOrigin)
            setPublished(&dragDistance, configuration.dragDistance)
            setPublished(&baseFontPx, configuration.baseFontPx)
            lastBodyOrigin = configuration.plotOrigin
            lastBodyDragDistance = configuration.dragDistance
            if let nextGeometry = configuration.geometry { geometry = nextGeometry }
        }

        let clearing = scope.contains(.clear)
        var next = clearing ? AutomationScene.detached : sceneCache
        var typography: AutomationTypographyValues?
        let contentChanged = clearing || scope.contains(.content)
        let publishFonts = scope.contains(.typography) || scope.contains(.content)
            || scope.contains(.body)
        if scope.contains(.content) {
            let input = contentSceneInput()
            let measured = projectionFacts.typography(
                baseFontPx: baseFontPx,
                captionLabels: AutomationScene.measurementLabels(input), titleLabels: [])
            typography = measured
            next.content = AutomationScene.buildContent(input, typography: measured)
        }

        let rebuildBand = contentChanged || scope.contains(.band)
        if rebuildBand {
            let paint = clearing ? nil : band.flatMap {
                paintProjection(parameter: $0.parameter, camera: liveCamera())
            }
            next.overlay.band = clearing ? AutomationBandValue()
                : AutomationScene.bandValue(band, paint: paint)
        }

        let rebuildHover = contentChanged || scope.contains(.hover)
        if rebuildHover {
            let paint = clearing ? nil : hover.flatMap {
                paintProjection(parameter: $0.parameter, camera: liveCamera())
            }
            let measured = projectionFacts.typography(
                baseFontPx: baseFontPx,
                captionLabel: clearing ? nil : hover?.text, titleLabel: nil)
            let metadata = hover.flatMap { candidate in
                candidate.parameter == next.content.projection?.parameter
                    ? next.content.projection?.metadata
                    : session.map {
                        projectionFacts.snapshot(candidate.parameter, session: $0).metadata
                    }
            }
            next.overlay.hover = clearing ? AutomationHoverValue()
                : AutomationScene.hoverValue(
                    hover, pointerX: hoverX, isPencilMode: isPencilMode,
                    activeParameter: next.content.active?.parameter ?? activeParameter,
                    paint: paint, metadata: metadata, baseFontPx: baseFontPx,
                    typography: measured)
        }

        let rebuildPreview = contentChanged || scope.contains(.preview)
        if rebuildPreview {
            let draft = AutomationPreviewDraft.resolve(gesture: gesture, frozen: frozen)
            let measured = projectionFacts.typography(
                baseFontPx: baseFontPx,
                captionLabel: clearing || draft.text.isEmpty ? nil : draft.text,
                titleLabel: nil)
            let paint = clearing ? nil : frozen.map {
                AutomationPaintProjection(makeProjection(facts: $0, camera: gestureCamera))
            }
            next.overlay.preview = clearing ? AutomationPreviewValue()
                : AutomationScene.previewValue(
                    draft: draft, frozen: frozen,
                    activeParameter: next.content.active?.parameter ?? activeParameter,
                    paint: paint, baseFontPx: baseFontPx, palette: scenePalette,
                    typography: measured)
        }

        let rebuildContext = contentChanged || scope.contains(.context)
        if rebuildContext {
            let parameter = next.content.active?.parameter ?? activeParameter
            let text = clearing ? "" : AutomationContextPresentation.text(
                editCursor: session?.editCursor, playing: playing,
                presentedTick: presentedTick, projection: next.content.projection,
                activeParameter: parameter)
            let measured = projectionFacts.typography(
                baseFontPx: baseFontPx, captionLabel: nil,
                titleLabel: text.isEmpty ? nil : text)
            next.context = clearing ? AutomationContextPresentation()
                : AutomationContextPresentation.resolve(
                    editCursor: session?.editCursor, playing: playing,
                    presentedTick: presentedTick, projection: next.content.projection,
                    activeParameter: parameter, previousTick: contextTick,
                    previousValue: contextValue, bounds: plotBounds,
                    baseFontPx: baseFontPx, typography: measured)
        }

        if clearing || scope.contains(.prompt) {
            next.modal.prompt = clearing ? AutomationPromptSceneInput() : promptSceneInput()
        }
        if clearing || scope.contains(.menu) {
            next.modal.menu = clearing ? AutomationMenuSceneInput() : menuSceneInput()
        }
        if clearing || scope.contains(.tapTempo) {
            next.tapTempo = clearing ? AutomationTapTempoValue() : AutomationTapTempoValue(
                active: tapGuard != nil || tapSession.tapCount != 0,
                tapCount: tapSession.tapCount, draftBpm: tapSession.draftBpm,
                idleCommitMs: tapSession.idleCommitMs, ready: tapSession.readyToCommit)
        }
        if clearing || scope.contains(.interaction) {
            next.interaction.active = clearing ? false : AutomationInteractionActivity.resolve(
                hasGesture: gesture != nil, hasPrompt: prompt != nil,
                hasLaneDelete: laneDelete != nil, hasMenu: menu != nil,
                hasBand: band != nil, isPanning: panActive, hasTapSession: tapGuard != nil)
        }
        if clearing || scope.contains(.hoverHint) || scope.contains(.hover) {
            next.interaction.hoverHintProfile = clearing ? AutomationHintProfile.empty
                : AutomationInteractionActivity.hintProfile(
                    hover: hover, isPencilMode: isPencilMode)
        }
        if scope.contains(.typography), typography == nil {
            typography = projectionFacts.typography(
                baseFontPx: baseFontPx, captionLabels: [], titleLabels: [])
        }

        sceneCache = next
        if contentChanged { applyContentFacts(next.content) }
        if publishFonts, let typography { publishTypographyValues(typography) }
        if contentChanged { publishContentValues(next.content) }
        if rebuildBand { publishBandValue(next.overlay.band) }
        if rebuildHover {
            publishHoverValue(next.overlay.hover)
            if !contentChanged { publishNodeHover(next.overlay.hover.nodeTick) }
        }
        if rebuildPreview { publishPreviewValue(next.overlay.preview) }
        if rebuildContext { publishContextValue(next.context) }
        if clearing || scope.contains(.prompt) { publishPromptValue(next.modal.prompt) }
        if clearing || scope.contains(.menu) { publishMenuValue(next.modal.menu) }
        if clearing || scope.contains(.tapTempo) { publishTapTempoValue(next.tapTempo) }
        if clearing || scope.contains(.hoverHint) || scope.contains(.hover) {
            setPublished(&hoverHintProfile, next.interaction.hoverHintProfile)
        }
        if clearing || scope.contains(.interaction) {
            publishInteractionValue(next.interaction)
        }
    }

    // MARK: Scoped requests retained until the reducer migration

    func rebuildContent(selectionOnly: Bool = false) {
        publish(.content)
        if session != nil { contentBuildCount &+= 1 }
        if selectionOnly { selectionBuildCount &+= 1 }
    }

    func publishBand() { publish(.band) }
    func publishHover() { publish([.hover, .hoverHint]) }
    func publishPreview() { publish(.preview) }
    func publishContext() { publish(.context) }
    func publishPrompt() { publish(.prompt) }
    func publishMenuRows() { publish([.menu, .interaction]) }
    func publishTapTempo() { publish(.tapTempo) }
    func publishTypography() { publish(.typography) }
    func publishInteractionState() { publish(.interaction) }
    func publishHoverHintProfile() { publish(.hoverHint) }

    func applyPreviewDraft(_ draft: AutomationPreviewDraft) {
        previewPoints = draft.parameter == activeParameter ? draft.points : []
        previewText = draft.parameter == activeParameter ? draft.text : ""
    }

    @discardableResult
    func applyHover(_ next: AutomationHover?, countingPublication: Bool) -> Bool {
        guard next != hover else { return false }
        hover = next
        if countingPublication { hoverBuildCount &+= 1 }
        return true
    }

    func hoverHintTargetAtPointer() -> AutomationHoverHintTarget? {
        guard hover != nil, let projection else { return nil }
        return AutomationHover.hintTarget(
            x: hoverX, y: hoverY, lane: projection,
            pointHitRadius: geometry.pointHitRadius)
    }

    func applyPrompt(_ next: AutomationPromptTransaction?) { prompt = next }

    func shiftSelection(by delta: Int64) {
        guard let moved = shiftedAutomationSelection(selection, by: delta) else { return }
        selection = moved
    }

    func applyBodySceneConfiguration(_ configuration: AutomationBodySceneConfiguration) {
        guard configuration.changed else { return }
        publish([.body, .content], body: configuration)
        if session != nil { contentBuildCount &+= 1 }
    }

    // MARK: Qt reconciliation

    private func applyContentFacts(_ content: AutomationContentScene) {
        parameterLabels = content.parameterLabels
        rows = content.rows
        ghostParameters = content.ghostParameters
        ghostLabels = content.ghostLabels
        selectedParameters = content.selectedParameters
        projection = content.projection
        scaleLabels = content.scaleLabels
        if let active = content.active {
            activeParameterIndex = active.parameterIndex
            activeParameter = active.parameter
        }
    }

    private func publishContentValues(_ content: AutomationContentScene) {
        if let active = content.active {
            setPublished(&trackAvailable, active.trackAvailable)
            setPublished(&plotMessage, active.plotMessage)
        } else {
            setPublished(&trackAvailable, false)
            setPublished(&plotMessage, AutomationPagePolicy.noTrackMessage)
        }
        syncModel(tabs, previous: &tabSnapshots, content.tabs) { AutomationTabHandle($0) }
        setPublished(&tabCount, content.tabs.count)
        syncModel(gridLines, previous: &gridLineSnapshots, content.gridLines) { SceneRect($0) }
        syncModel(valueLines, previous: &valueLineSnapshots, content.valueLines) { SceneRect($0) }
        syncModel(valueLabels, previous: &valueLabelSnapshots, content.valueLabels) { SceneText($0) }
        syncModel(curveRuns, previous: &curveRunSnapshots, content.curveRuns) { SceneRect($0) }
        syncModel(ramps, previous: &rampSnapshots, content.ramps) { AutomationRampHandle($0) }
        syncModel(nodes, previous: &nodeSnapshots, content.nodes) { AutomationNodeHandle($0) }
        setPublished(&nodeCount, content.nodes.count)
        syncModel(selectionRects, previous: &selectionRectSnapshots, content.selectionRects) {
            SceneRect($0)
        }
    }

    private func publishNodeHover(_ nodeTick: Double?) {
        guard nodeSnapshots.count == nodes.count else { return }
        for index in nodeSnapshots.indices {
            let hovered = nodeSnapshots[index].tick == nodeTick
            guard nodeSnapshots[index].hovered != hovered else { continue }
            nodeSnapshots[index].hovered = hovered
            nodes[index] = AutomationNodeHandle(nodeSnapshots[index])
        }
    }

    private func publishBandValue(_ value: AutomationBandValue) {
        setRect(&bandRect, value.rect)
        setPublished(&bandVisible, value.visible)
    }

    private func publishHoverValue(_ value: AutomationHoverValue) {
        setPublished(&hoverText, value.text)
        setRect(&hoverLabelRect, value.rect)
        setPublished(&hoverTick, Double(value.tick))
        setPublished(&hoverVisible, value.visible)
    }

    private func publishPreviewValue(_ value: AutomationPreviewValue) {
        previewPoints = value.points
        previewText = value.text
        syncModel(previewRects, previous: &previewRectSnapshots, value.rects) { SceneRect($0) }
        setPublished(&previewLabelText, value.text)
        setRect(&previewLabelRect, value.labelRect)
        setPublished(&previewLabelVisible, value.labelVisible)
    }

    private func publishContextValue(_ value: AutomationContextPresentation) {
        contextTick = value.tick
        contextValue = value.value
        setPublished(&readoutText, value.readoutText)
        setRect(&readoutRect, value.readoutRect)
        setPublished(&accessibleDescription, value.accessibleDescription)
        setPublished(&readoutVisible, value.readoutVisible)
        if value.contextChanged { contextChangeCount &+= 1 }
    }

    private func publishPromptValue(_ value: AutomationPromptSceneInput) {
        setPublished(&promptKind, value.kind)
        setPublished(&promptTitle, value.title)
        setPublished(&promptLabel, value.label)
        setPublished(&promptMessage, value.message)
        setPublished(&promptMinimum, value.minimum)
        setPublished(&promptMaximum, value.maximum)
        setPublished(&promptDraft, value.draft)
        setPublished(&promptError, value.error)
        setPublished(&promptOpen, value.open)
    }

    private func publishMenuValue(_ value: AutomationMenuSceneInput) {
        syncModel(menuRows, previous: &menuRowSnapshots, value.rows) { AutomationMenuRowHandle($0) }
        syncModel(menuChildRows, previous: &menuChildRowSnapshots, value.childRows) {
            AutomationMenuRowHandle($0)
        }
        setPublished(&menuX, value.x)
        setPublished(&menuY, value.y)
        setPublished(&menuRowCount, value.rows.count)
        setPublished(&menuChildRowCount, value.childRows.count)
        setPublished(&menuOpen, value.open)
    }

    private func publishTapTempoValue(_ value: AutomationTapTempoValue) {
        setPublished(&tapTempoTapCount, value.tapCount)
        setPublished(&tapTempoDraftBpm, value.draftBpm)
        setPublished(&tapTempoIdleCommitMs, value.idleCommitMs)
        setPublished(&tapTempoReady, value.ready)
        setPublished(&tapTempoActive, value.active)
    }

    private func publishInteractionValue(_ value: AutomationInteractionValue) {
        let changed = interactionActive != value.active
            || publishedPointerGestureActive != pointerGestureActive
        setPublished(&interactionActive, value.active)
        publishedPointerGestureActive = pointerGestureActive
        if changed { onCommandAvailabilityChanged?() }
    }

    private func publishTypographyValues(_ value: AutomationTypographyValues) {
        if captionFontSnapshot != value.captionFont {
            captionFontSnapshot = value.captionFont
            captionFont = value.captionFont.map
        }
        if titleFontSnapshot != value.titleFont {
            titleFontSnapshot = value.titleFont
            titleFont = value.titleFont.map
        }
    }

    private func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }

    private func setRect(_ storage: inout [String: QVariantSettable],
                         _ value: DrawerRectValue) {
        guard !Self.rectMatches(storage, value) else { return }
        storage = Self.rect(value.x, value.y, value.width, value.height)
    }


    static func rect(_ x: Double, _ y: Double, _ width: Double,
                     _ height: Double) -> [String: QVariantSettable] {
        ["x": x, "y": y, "width": width, "height": height]
    }

    private static func rectMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: DrawerRectValue) -> Bool {
        guard let x = lhs["x"] as? Double, let y = lhs["y"] as? Double,
              let width = lhs["width"] as? Double, let height = lhs["height"] as? Double
        else { return false }
        return x == rhs.x && y == rhs.y && width == rhs.width && height == rhs.height
    }
}
