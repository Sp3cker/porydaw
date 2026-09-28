import PorydawCore
import QtBridge

// Publication machinery for the drawer's Velocity section: the content rebuild
// that resolves the presented context and republishes every static projection,
// the scene-input assembly a build reads, and the per-row apply paths that sync
// the published primitives and item models, plus the readout, the transient
// gesture rendering and the typography/metrics/handle reuse caches.
//
// Ownership: an extension of the page, never a separate object. Published
// state and the caches stay declared on `VelocityPage` — `@QtBridgeable`
// registers class-body members only and stored properties cannot move to an
// extension — so this file reads and writes the page's own state and publishes
// through `setPublished` and `syncModel`: it holds no session, no cache and no
// bridge type of its own.

@MainActor
extension VelocityPage {
    // MARK: Content rebuild

    /// Rebuilds every static projection: the ruler, the grid, the PSG bands and
    /// the note handles.
    @QtIgnored func rebuildContent() {
        guard session != nil, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        geometry = VelocityNodeGeometry(baseFontPx: baseFontPx,
                                        devicePixelRatio: devicePixelRatio)
        let presented = VelocityScene.presentation(session, playing: playing,
                                                   contextTick: contextTick)
        resolvedContextValue = presented
        lastContextKey = VelocityContextKey(context: presented, playing: playing)
        contextUnsupported = !presented.editable
        contextDiagnostic = presented.diagnostic
        contextSlot = presented.slot
        contextVoiceName = presented.map.voiceName
        setPublished(&detentsAvailable, presented.status == .resolved && presented.map.isPSG)
        let snapshot = buildScene()
        refreshAxisAndHandles(snapshot)
        publishTransient(updateDrawing: false)
        publishDrawingContent()
    }

    /// Hover and detent changes republish the ruler and handle rows: a content
    /// rebuild hands its own build in, the hover-only paths derive the scoped
    /// axis, handle and ruler values those interactions actually change.
    @QtIgnored func refreshAxisAndHandles(_ snapshot: VelocitySceneSnapshot? = nil) {
        let built = snapshot.map { VelocityAxisAndHandles($0) }
            ?? VelocitySceneSnapshot.buildAxisAndHandles(
                sceneInput(reuseGeometry: handleReuseGeometry()),
                previousHandles: handlesByID)
        rebuildAxis(built.axis)
        publishHandles(built.handles)
        publishAxis(built.rows)
        publishReadout()
        if snapshot == nil { publishDrawingContent() }
    }

    /// Applies one build's value axis to the page's published axis values.
    private func rebuildAxis(_ axis: VelocityAxisModel) {
        self.axis = axis
        setPublished(&axisMode, axis.mode.rawValue)
        setPublished(&axisGraduationsVisible, axis.mode == .intrinsic && detentsEnabled)
        setPublished(&axisAccessibleDescription, axis.accessibleDescription)
    }

    // MARK: Scene input

    /// The page's one static scene build, from the live session and the page's
    /// own state. The cached label typography and the published handle lookup are
    /// the page's `@MainActor` objects, so they travel as build parameters.
    func buildScene() -> VelocitySceneSnapshot {
        VelocitySceneSnapshot.build(sceneInput(reuseGeometry: handleReuseGeometry()),
                                    previousHandles: handlesByID)
    }

    /// The primary track's note rows, projected against the published axis: the
    /// scoped build a live gesture uses, so motion never rebuilds static content.
    @QtIgnored func projectHandles() -> [VelocityHandle] {
        VelocitySceneSnapshot.buildHandleRows(sceneInput(reuseGeometry: handleReuseGeometry()),
                                              axis: axis, previousHandles: handlesByID)
    }

    /// The handle-reuse decision: geometry, track, DPR and axis mode form one
    /// key, and an unchanged key reuses the previous handle objects in place.
    private func handleReuseGeometry() -> Bool {
        let key = HandleGeometryKey(geometry: geometry, track: session?.selectedTrack ?? 0,
                                    dpr: devicePixelRatio, intrinsic: axis.mode == .intrinsic)
        let reuse = handleGeometryKey == key
        handleGeometryKey = key
        return reuse
    }

    /// Everything one scene build reads, as values: the session's document facts,
    /// the page's live interaction snapshot and its cached grid metrics.
    func sceneInput(reuseGeometry: Bool) -> VelocitySceneInput {
        let session = self.session
        return VelocitySceneInput(
            camera: session?.camera,
            context: resolvedContextValue,
            notes: VelocityScene.trackNotes(session),
            selectedNotes: VelocityScene.selectedTrackNotes(session),
            selectedNoteIDs: session?.selectedNotes ?? [],
            track: session?.selectedTrack ?? 0,
            source: VelocityScene.contextSource(session),
            interaction: interactionSnapshot(),
            geometry: geometry,
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            rulerWidth: rulerWidth,
            devicePixelRatio: devicePixelRatio,
            baseFontPx: baseFontPx,
            metrics: session.map { gridMetrics($0) },
            grid: session?.grid,
            palette: scenePalette(),
            reuseGeometry: reuseGeometry)
    }

    /// The page's live gesture and hover facts, frozen for one build.
    private func interactionSnapshot() -> VelocityInteractionSnapshot {
        VelocityInteractionSnapshot(
            frozenNotes: gesture?.notes ?? [],
            preview: gesture?.preview ?? [:],
            detentUnlock: gesture?.detentUnlock ?? false,
            relativeActivated: gesture?.relativeActivated ?? false,
            hovered: hovered,
            detentsEnabled: detentsEnabled)
    }

    /// The palette colours a scene build draws with, as values.
    private func scenePalette() -> VelocityScenePalette {
        VelocityScenePalette(
            gridLineSub1: palette.gridLineSub1,
            gridLineSub2: palette.gridLineSub2,
            gridLineSub3: palette.gridLineSub3,
            gridLineBar: palette.gridLineBar,
            gridLineBeat: palette.gridLineBeat,
            gridLineBeatFine: palette.gridLineBeatFine,
            separator: palette.separator,
            primaryText: palette.primaryText,
            selectionRing: palette.selectionRing,
            outline: palette.outline,
            noteBorder: palette.noteBorder)
    }

    /// The page's own projection for hit tests and gesture maths: the shared
    /// camera at the page's DPR against the published value axis.
    @QtIgnored var projection: VelocityProjection {
        VelocityProjection(camera: session?.camera, geometry: geometry,
                           devicePixelRatio: devicePixelRatio, axis: axis)
    }

    // MARK: Publication

    /// Publishes one handle projection. The page's own array is the authoritative
    /// copy the hit tests and the checks read, so it moves with the model.
    @QtIgnored func publishHandles(_ values: [VelocityHandle]) {
        publishedHandles = values
        handlesByID = Dictionary(uniqueKeysWithValues: values.map { ($0.noteID, $0) })
        syncModel(handles, values, matches: { $0.matches($1) })
    }

    private func syncRects(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        syncModel(model, rects, matches: { $0.matches($1) })
    }

    private func syncTexts(_ model: QListModel<SceneText>, _ texts: [SceneText]) {
        syncModel(model, texts, matches: matchesText)
    }

    /// `SceneText` publishes no comparison of its own; an equal record leaves
    /// its row untouched. The font map is compared through its published
    /// spelling, because its values are variant-typed.
    private func matchesText(_ lhs: SceneText, _ rhs: SceneText) -> Bool {
        lhs.labelText == rhs.labelText && lhs.labelColor == rhs.labelColor
            && lhs.labelBackground == rhs.labelBackground
            && lhs.labelHorizontalAlignment == rhs.labelHorizontalAlignment
            && lhs.labelVerticalAlignment == rhs.labelVerticalAlignment
            && Self.rectMatches(lhs.labelRect, rhs.labelRect)
            && Self.fontMatches(lhs.labelFont, rhs.labelFont)
    }

    private static func rectMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right
            else { return false }
        }
        return true
    }

    private static func fontMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, value) in lhs {
            guard let other = rhs[key], String(describing: value) == String(describing: other)
            else { return false }
        }
        return true
    }

    /// Publishes one build's ruler rows: the ticks, graduations, markers and
    /// labels `VelocityScene` derived for the presented axis.
    private func publishAxis(_ rows: VelocityAxisRows) {
        syncRects(axisTicks, rows.ticks)
        syncRects(axisGraduations, rows.graduations)
        syncRects(axisMarkers, rows.markers)
        syncTexts(axisLabels, rows.labels)
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        let key = MetricsKey(revision: session.document.revision, font: baseFontPx,
                             dpr: devicePixelRatio, width: plotWidth, height: plotHeight)
        if let metricsCache, metricsCache.key == key { return metricsCache.value }
        let value = VelocityScene.gridMetrics(baseFontPx: baseFontPx,
                                              devicePixelRatio: devicePixelRatio,
                                              width: plotWidth, height: plotHeight,
                                              timeAxis: VelocityScene.timeAxis(session))
        metricsCache = (key, value)
        return value
    }

    @QtIgnored func publishDrawingContent(rebuildBands: Bool = true) {
        guard session != nil else { return }
        let input = sceneInput(reuseGeometry: true)
        guard let metrics = input.metrics, let grid = input.grid else { return }
        if rebuildBands { drawingBands = VelocityScene.modelBands(input, axis: axis) }
        let data = DrawerStaticsContent.pack(
            axis: metrics.timeAxis, grid: grid, metrics: metrics,
            palette: input.palette, bands: drawingBands,
            transient: drawingTransientRects())
        guard drawingContentData != data else { return }
        drawingContentData = data
        contentRevision &+= 1
    }

    private func drawingTransientRects()
        -> (fill: DrawerStaticRect, frame: DrawerStaticRect)?
    {
        guard let gesture, gesture.kind == .band || gesture.kind == .pendingBand,
            let camera = session?.camera
        else { return nil }
        let minX = min(gesture.pressX, gesture.bandX)
        let maxX = max(gesture.pressX, gesture.bandX)
        let left = TimeDefaults.tick(from: (minX / camera.snapshot.pixelsPerTick).rounded())
        let right = TimeDefaults.tick(from: (maxX / camera.snapshot.pixelsPerTick).rounded())
        let y = Float(min(gesture.pressY, gesture.bandY))
        let height = Float(abs(gesture.bandY - gesture.pressY))
        let fill = DrawerStaticRect(
            tickStart: left, tickEnd: right, y: y, height: height,
            argb: SceneRectPacking.argb(palette.selectionFill))
        let frame = DrawerStaticRect(
            tickStart: left, tickEnd: right, y: y, height: height,
            argb: SceneRectPacking.argb(palette.selectionEdge), flags: 4)
        return (fill, frame)
    }

    @QtIgnored func publishTransient(updateDrawing: Bool = true) {
        setPublished(&rampVisible, false)
        setPublished(&rampLength, 0)
        setPublished(&rampSlopeY, 0)
        if let gesture {
            switch gesture.kind {
            case .ramp:
                let dx = gesture.previousX - gesture.pressX
                let dy = gesture.previousY - gesture.pressY
                // Gestures live in scroll-stable x; the transient draws in
                // untranslated plot space, so it restores the origin here.
                setPublished(&rampX0, gesture.pressX - projection.scrollOffsetX)
                setPublished(&rampY0, gesture.pressY)
                setPublished(&rampLength, (dx * dx + dy * dy).squareRoot())
                setPublished(&rampSlopeY, dy)
                setPublished(&rampColor, palette.primaryText)
                setPublished(&rampVisible, rampLength > 0)
            case .band, .pendingBand:
                break
            case .relative, .paint, .pan:
                break
            }
        }
        publishReadout()
        if updateDrawing { publishDrawingContent(rebuildBands: false) }
    }

    /// The readout: the hovered or dragged value plus the selection count. An
    /// unchanged publication writes nothing.
    func publishReadout() {
        var text = ""
        var visible = false
        var x = 0.0
        var y = 0.0
        if let hovered, let handle = handlesByID[hovered] {
            text = handle.label
            visible = true
            x = handle.x
            y = handle.y
        } else if let gesture, let first = gesture.notes.first {
            let handle = handlesByID[first.noteID]
            let preview = gesture.preview[first.noteID].map(Int.init) ?? Int(first.velocity)
            text = handle?.label ?? "\(preview)"
            visible = true
            x = handle?.x ?? 0
            y = handle?.y ?? 0
        }
        setPublished(&readoutText, text)
        setPublished(&readoutVisible, visible)
        setPublished(&readoutX, x)
        setPublished(&readoutY, y)
        setPublished(&selectedCount, publishedHandles.filter(\.selected).count)
        setPublished(&hoveredNoteText, hovered.map(velocityNoteText) ?? "")
    }

    /// Writes one published primitive only when it really changed, so a
    /// repeated equal publication emits nothing.
    @QtIgnored func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }
}
