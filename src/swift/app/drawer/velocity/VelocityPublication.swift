import Foundation
import PorydawCore
import PorydawDocument
import QtBridge

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

// Publication for `VelocityPage`: published state stays in the class body because
// QtBridge registers class-body members only; this extension holds no state.

@MainActor
extension VelocityPage {
    /// Valid empty list for out-of-range fetches before the first publish.
    /// Built once and retained.
    @QtIgnored func retainedEmptyDisplayList() -> Data {
        if let cached = cachedEmptyDisplayList { return cached }
        var writer = DisplayListWriter()
        let empty = writer.finish()
        cachedEmptyDisplayList = empty
        return empty
    }

    @QtIgnored func rebuildContent() {
        guard session != nil, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        geometry = VelocityNodeGeometry(
            baseFontPx: baseFontPx,
            devicePixelRatio: devicePixelRatio)
        let presented = VelocityScene.presentation(
            session, playing: playing,
            contextTick: contextTick)
        resolvedContextValue = presented
        lastContextKey = VelocityContextKey(context: presented, playing: playing)
        contextUnsupported = !presented.editable
        contextDiagnostic = presented.diagnostic
        contextSlot = presented.slot
        contextVoiceName = presented.map.voiceName
        publish(\.detentsAvailable, presented.status == .resolved && presented.map.isPSG)
        refreshAxisAndHandles(republishDisplayLists: false)
        publishTransient(updateDrawing: false)
        publishDisplayLists()
    }

    /// Republishes the axis, handle and ruler rows; a content rebuild passes
    /// `false` because it publishes its display lists after the transient.
    @QtIgnored func refreshAxisAndHandles(republishDisplayLists: Bool = true) {
        let built = VelocityScene.axisAndHandles(
            sceneInput(reuseGeometry: handleReuseGeometry()),
            previousHandles: handlesByID)
        rebuildAxis(built.axis)
        publishHandles(built.handles)
        publishAxis(built.rows)
        publishReadout()
        if republishDisplayLists { publishDisplayLists() }
    }

    /// Applies one build's value axis to the page's published axis values.
    private func rebuildAxis(_ axis: VelocityAxisModel) {
        self.axis = axis
        publish(\.axisMode, axis.mode.rawValue)
        publish(\.axisGraduationsVisible, axis.mode == .intrinsic && detentsEnabled)
        publish(\.axisAccessibleDescription, axis.accessibleDescription)
    }

    // MARK: Scene input

    /// The primary track's note rows, projected against the published axis: the
    /// scoped build a live gesture uses, so motion never rebuilds static content.
    @QtIgnored func projectHandles(window: ClosedRange<Double>? = nil) -> [VelocityHandle] {
        VelocityScene.handleRows(
            sceneInput(reuseGeometry: handleReuseGeometry(), window: window),
            axis: axis, previousHandles: handlesByID)
    }

    /// Camera movement keeps retained rows stable until the viewport leaves
    /// their overscan window, then republishes handles without rebuilding axes.
    @QtIgnored
    public func refreshCamera() {
        guard viewport != nil else { return }
        let window = handleWindowForCamera()
        if window != publishedHandleWindow {
            publishHandles(projectHandles(window: window), window: window)
        }
        let projection = self.projection
        for handle in publishedHandles {
            let x = projection.stableXForTick(handle.tick)
            let endX = projection.stableXForTick(handle.endTick)
            handle.publish(\.x, x)
            handle.publish(\.endX, endX)
        }
        publishTransient(updateDrawing: false)
        // Viewport-space lists: every camera move rebuilds both lists together.
        publishDisplayLists(rebuildBands: false)
    }

    /// The handle-reuse decision: geometry, track, DPR and axis mode form one
    /// key, and an unchanged key reuses the previous handle objects in place.
    private func handleReuseGeometry() -> Bool {
        let key = HandleGeometryKey(
            geometry: geometry, track: session?.selectedTrack ?? 0,
            dpr: devicePixelRatio, intrinsic: axis.mode == .intrinsic)
        let reuse = handleGeometryKey == key
        handleGeometryKey = key
        return reuse
    }

    /// Keep the current overscan until the visible ticks escape it.
    private func handleWindowForCamera() -> ClosedRange<Double>? {
        guard let camera = viewport?.camera else { return nil }
        let width = plotWidth > 0 ? plotWidth : camera.snapshot.viewportWidth
        let start = projection.scrollOffsetX / camera.pixelsPerTick
        let end = start + width / camera.pixelsPerTick
        if let publishedHandleWindow,
            start >= publishedHandleWindow.lowerBound,
            end <= publishedHandleWindow.upperBound
        {
            return publishedHandleWindow
        }
        let margin = width / camera.pixelsPerTick * VelocityPagePolicy.handleMarginViewportWidths
        return (start - margin)...(end + margin)
    }

    /// Everything one scene build reads, as values: the session's document facts,
    /// the page's live interaction snapshot and its cached grid metrics.
    func sceneInput(reuseGeometry: Bool, window: ClosedRange<Double>? = nil) -> VelocitySceneInput {
        let session = self.session
        return VelocitySceneInput(
            camera: viewport?.camera,
            handleTickWindow: window ?? handleWindowForCamera(),
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
            typography: typography,
            metrics: session.map { gridMetrics($0) },
            grid: viewport?.grid,
            palette: scenePalette(),
            reuseGeometry: reuseGeometry)
    }

    /// The page's live gesture and hover facts, frozen for one build.
    private func interactionSnapshot() -> VelocityInteractionSnapshot {
        VelocityInteractionSnapshot(
            frozenNotes: gesture?.notes ?? [],
            preview: gesture?.preview ?? rollPreview,
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
        VelocityProjection(
            camera: viewport?.camera, geometry: geometry,
            devicePixelRatio: devicePixelRatio, axis: axis)
    }

    // MARK: Publication

    /// Publishes one handle projection. The page's own array is the authoritative
    /// copy the hit tests and the checks read, so it moves with the model.
    @QtIgnored func publishHandles(_ values: [VelocityHandle], window: ClosedRange<Double>? = nil) {
        let nextByID = Dictionary(uniqueKeysWithValues: values.map { ($0.noteID, $0) })
        publishedHandles = values
        handlesByID = nextByID
        publishedHandleWindow = window ?? handleWindowForCamera()
        let selected = session?.selectedNotes ?? []
        let count = VelocityScene.trackNotes(session).reduce(0) {
            $0 + (selected.contains($1.id) ? 1 : 0)
        }
        publish(\.selectedCount, count)
        syncModel(handles, values, matches: { $0.matches($1) })
    }

    /// Publishes one build's ruler rows: the ticks, graduations, markers and
    /// labels `VelocityScene` derived for the presented axis.
    private func publishAxis(_ rows: VelocityAxisRows) {
        syncRetained(axisTicks, rows.ticks, make: SceneRect.init, update: { $0.update($1) })
        syncRetained(axisGraduations, rows.graduations, make: SceneRect.init, update: { $0.update($1) })
        syncRetained(axisMarkers, rows.markers, make: SceneRect.init, update: { $0.update($1) })
        syncRetained(axisLabels, rows.labels, make: SceneText.init, update: { $0.update($1) })
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        let key = MetricsKey(
            revision: session.document.revision, font: baseFontPx,
            dpr: devicePixelRatio, width: plotWidth, height: plotHeight)
        if let metricsCache, metricsCache.key == key { return metricsCache.value }
        let value = VelocityScene.gridMetrics(
            baseFontPx: baseFontPx,
            devicePixelRatio: devicePixelRatio,
            width: plotWidth, height: plotHeight,
            timeAxis: VelocityScene.timeAxis(session))
        metricsCache = (key, value)
        return value
    }

    @QtIgnored func publishDisplayLists(rebuildBands: Bool = true) {
        guard viewport != nil else { return }
        let input = sceneInput(reuseGeometry: true)
        guard let metrics = input.metrics, let grid = input.grid,
            let camera = input.camera
        else { return }
        if rebuildBands { drawingBands = VelocityScene.modelBands(input, axis: axis) }
        let viewport = CGSize(width: plotWidth, height: plotHeight)
        let dpr = devicePixelRatio
        let colors = [
            3: input.palette.gridLineBar, 4: input.palette.gridLineBeat,
            5: input.palette.gridLineSub1, 6: input.palette.gridLineSub2,
            7: input.palette.gridLineSub3, 25: input.palette.gridLineBeatFine,
        ]
        // Release the previous buffers before the retained writer reuses its
        // own: otherwise finish()'s shared output copies on write each frame.
        var writer = listWriter
        DrawerStaticsContent.buildGrid(
            into: &writer, axis: metrics.timeAxis, grid: grid,
            camera: camera, viewport: viewport, paletteColors: colors)
        DrawerStaticsContent.buildTickRects(
            into: &writer, rects: drawingBands,
            camera: camera, dpr: dpr, viewport: viewport)
        let list0 = writer.finish()
        if let transient = drawingTransientRects() {
            DrawerStaticsContent.buildTickRects(
                into: &writer, rects: [transient.fill],
                camera: camera, dpr: dpr, viewport: viewport)
            let x0 = camera.viewX(tick: Double(transient.frame.tickStart), dpr: dpr)
            let x1 = camera.viewX(tick: Double(transient.frame.tickEnd), dpr: dpr)
            let box = CGRect(
                x: x0, y: Double(transient.frame.y),
                width: x1 - x0, height: Double(transient.frame.height))
            DrawerStaticsContent.buildDashedFrame(
                into: &writer, box: box, argb: transient.frame.argb,
                dashDevicePx: 4, gapDevicePx: 2, dpr: dpr, viewport: viewport)
        }
        let list1 = writer.finish()
        listWriter = writer
        let next = [list0, list1]
        guard next != displayLists else { return }
        displayLists = next
        displayRevision &+= 1
    }

    private func drawingTransientRects()
        -> (fill: DrawerStaticRect, frame: DrawerStaticRect)?
    {
        guard let gesture, gesture.kind == .band || gesture.kind == .pendingBand,
            let camera = viewport?.camera
        else { return nil }
        let minX = min(gesture.pressX, gesture.bandX)
        let maxX = max(gesture.pressX, gesture.bandX)
        let left = TimeDefaults.tick(from: (minX / camera.snapshot.pixelsPerTick).rounded())
        let right = TimeDefaults.tick(from: (maxX / camera.snapshot.pixelsPerTick).rounded())
        let y = Float(min(gesture.pressY, gesture.bandY))
        let height = Float(abs(gesture.bandY - gesture.pressY))
        let fill = DrawerStaticRect(
            tickStart: left, tickEnd: right, y: y, height: height,
            argb: PaletteMath.argb(palette.selectionFill))
        let frame = DrawerStaticRect(
            tickStart: left, tickEnd: right, y: y, height: height,
            argb: PaletteMath.argb(palette.selectionEdge), flags: 4)
        return (fill, frame)
    }

    @QtIgnored func publishTransient(updateDrawing: Bool = true) {
        publish(\.rampVisible, false)
        publish(\.rampLength, 0)
        publish(\.rampSlopeY, 0)
        if let gesture {
            switch gesture.kind {
            case .ramp:
                let dx = gesture.previousX - gesture.pressX
                let dy = gesture.previousY - gesture.pressY
                // Gestures live in scroll-stable x; the transient draws in
                // untranslated plot space, so it restores the origin here.
                publish(\.rampX0, gesture.pressX - projection.scrollOffsetX)
                publish(\.rampY0, gesture.pressY)
                publish(\.rampLength, (dx * dx + dy * dy).squareRoot())
                publish(\.rampSlopeY, dy)
                publish(\.rampColor, palette.primaryText)
                publish(\.rampVisible, rampLength > 0)
            case .band, .pendingBand:
                break
            case .relative, .paint, .pan:
                break
            }
        }
        publishReadout()
        if updateDrawing { publishDisplayLists(rebuildBands: false) }
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
        publish(\.readoutText, text)
        publish(\.readoutVisible, visible)
        publish(\.readoutX, x)
        publish(\.readoutY, y)
        publish(\.hoveredNoteText, hovered.map(velocityNoteText) ?? "")
    }

}
