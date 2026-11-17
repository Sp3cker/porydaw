import Foundation
import NativeDisplayList
import PorydawAppPresentation
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
        DrawerStaticsContent.retainedEmptyDisplayList(cached: &cachedEmptyDisplayList)
    }

    @QtIgnored func rebuildContent(facts: SemanticFacts? = nil) {
        guard session != nil else { return }
        let facts = facts ?? resolveSemanticFacts()
        publishPresentationContext(facts)
        guard contentVisible else {
            contentRefreshPending = true
            publishReadout(facts: facts)
            return
        }
        guard plotHeight > 0 || plotWidth > 0 else {
            contentRefreshPending = true
            return
        }
        contentRefreshPending = false
        contentBuildCount &+= 1
        geometry = VelocityNodeGeometry(
            baseFontPx: baseFontPx,
            devicePixelRatio: devicePixelRatio)
        let input = refreshAxisAndHandles(facts: facts, republishDisplayLists: false)
        publishTransient(updateDrawing: false)
        publishDisplayLists(bandsInput: input)
    }
    /// Resolves one refresh's semantic snapshot; consumers share these facts.
    func resolveSemanticFacts() -> SemanticFacts? {
        guard let session else { return nil }
        let source = VelocityScene.contextSource(session)
        let selected = VelocityScene.selectedTrackNotes(session)
        let selectionContext: VelocityVoiceContext?
        if selected.isEmpty {
            selectionContext = nil
        } else {
            selectionContext = VelocityContextPolicy.presentation(
                selectedNotes: selected, effectiveTick: 0, resolve: source.resolver())
        }
        return SemanticFacts(
            source: source, selectionContext: selectionContext, selectedNotes: selected)
    }

    /// Republishes the axis, handle and ruler rows; a content rebuild passes
    /// `false` because it publishes its display lists after the transient.
    @discardableResult
    @QtIgnored func refreshAxisAndHandles(
        facts: SemanticFacts? = nil, republishDisplayLists: Bool = true
    ) -> VelocitySceneInput? {
        let facts = facts ?? resolveSemanticFacts()
        let input = sceneInput(facts: facts)
        let nextAxis = VelocityScene.axisModel(input)
        VelocityScene.handleRows(input, axis: nextAxis, into: &handleBuffer)
        rebuildAxis(nextAxis)
        publishHandles()
        publish(\.selectedCount, facts?.selectedNotes.count ?? 0)
        guard contentVisible else {
            contentRefreshPending = true
            publishReadout(facts: facts)
            return nil
        }
        let relativeGesture =
            input.interaction.relativeActivated
            || input.selectedNotes.count > 1 || input.interaction.hovered != nil
        let rows = VelocityScene.axisRows(input, axis: nextAxis, relativeGesture: relativeGesture)
        publishAxis(rows)
        publishReadout()
        if republishDisplayLists { publishDisplayLists(bandsInput: input) }
        return input
    }

    /// Applies one build's value axis to the page's published axis values.
    private func rebuildAxis(_ axis: VelocityAxisModel) {
        self.axis = axis
        publish(\.axisMode, axis.mode.rawValue)
        publish(\.axisGraduationsVisible, axis.mode == .intrinsic && detentsEnabled)
        publish(\.axisAccessibleDescription, axis.accessibleDescription)
    }

    // MARK: Scene input

    /// Reprojects live geometry without rebuilding the retained axes and bands.
    @QtIgnored func refreshHandles(window: ClosedRange<Double>? = nil, updateDrawing: Bool = true) {
        VelocityScene.handleRows(
            sceneInput(window: window), axis: axis, into: &handleBuffer)
        publishHandles(window: window)
        guard contentVisible else {
            contentRefreshPending = true
            return
        }
        if updateDrawing { publishDisplayLists() }
    }

    /// Camera movement keeps retained rows stable until the viewport leaves
    /// their overscan window, then republishes handles without rebuilding axes.
    @QtIgnored
    public func refreshCamera() {
        guard viewport != nil else { return }
        guard contentVisible else {
            contentRefreshPending = true
            return
        }
        if contentRefreshPending {
            rebuildContent()
            return
        }
        let window = handleWindowForCamera()
        if window != publishedHandleWindow {
            refreshHandles(window: window, updateDrawing: false)
        }
        let projection = self.projection
        for index in publishedHandles.indices {
            publishedHandles[index].x = projection.stableXForTick(publishedHandles[index].tick)
            publishedHandles[index].endX = projection.stableXForTick(publishedHandles[index].endTick)
        }
        publishTransient(updateDrawing: false)
        // Viewport-space lists: every camera move rebuilds both lists together.
        publishDisplayLists()
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
    /// the page's live interaction snapshot and drawn geometry.
    func sceneInput(
        facts: SemanticFacts? = nil, window: ClosedRange<Double>? = nil
    ) -> VelocitySceneInput {
        let session = self.session
        return VelocitySceneInput(
            camera: viewport?.camera,
            handleTickWindow: window ?? handleWindowForCamera(),
            context: resolvedContextValue,
            notes: VelocityScene.trackNotes(session),
            selectedNotes: facts?.selectedNotes ?? VelocityScene.selectedTrackNotes(session),
            selectedNoteIDs: session?.selectedNotes ?? [],
            source: facts?.source ?? VelocityScene.contextSource(session),
            interaction: interactionSnapshot(),
            geometry: geometry,
            plotHeight: plotHeight,
            rulerWidth: rulerWidth,
            devicePixelRatio: devicePixelRatio,
            baseFontPx: baseFontPx,
            typography: typography,
            palette: scenePalette())
    }

    /// The page's live gesture and hover facts, frozen for one build.
    private func interactionSnapshot() -> VelocityInteractionSnapshot {
        VelocityInteractionSnapshot(
            frozen: gesture?.frozen ?? VelocityFrozenNotes(),
            preview: gesture?.preview ?? rollPreview,
            detentUnlock: gesture?.detentUnlock ?? false,
            relativeActivated: gesture?.relativeActivated ?? false,
            hovered: hovered,
            detentsEnabled: detentsEnabled)
    }

    /// The palette colours a scene build draws with, as values.
    private func scenePalette() -> VelocityScenePalette {
        VelocityScenePalette(
            separator: palette.separator,
            primaryText: palette.primaryText,
            selectionRing: palette.selectionRing)
    }

    /// The page's own projection for hit tests and gesture maths: the shared
    /// camera at the page's DPR against the published value axis.
    @QtIgnored var projection: VelocityProjection {
        VelocityProjection(
            camera: viewport?.camera, geometry: geometry,
            devicePixelRatio: devicePixelRatio, axis: axis)
    }

    // MARK: Publication

    /// Swaps retained value buffers; no per-note bridge objects are published.
    @QtIgnored func publishHandles(window: ClosedRange<Double>? = nil) {
        swap(&publishedHandles, &handleBuffer)
        handleBuffer.removeAll(keepingCapacity: true)
        handleIndicesByID.removeAll(keepingCapacity: true)
        for (index, handle) in publishedHandles.enumerated() {
            handleIndicesByID[handle.noteID] = index
        }
        // Coverage changes ink only; axis and editing context keep session selection.
        if let gesture, gesture.kind == .band {
            for index in publishedHandles.indices {
                publishedHandles[index].selected = false
                publishedHandles[index].dimmed = selectedCount > 1
            }
            for id in gesture.bandPreview {
                guard let index = handleIndicesByID[id] else { continue }
                publishedHandles[index].selected = true
                publishedHandles[index].dimmed = false
            }
            if gesture.controlPress {
                for id in selectionBeforePress {
                    guard let index = handleIndicesByID[id] else { continue }
                    publishedHandles[index].selected = true
                    publishedHandles[index].dimmed = false
                }
            }
        }
        publishedHandleWindow = window ?? handleWindowForCamera()
        let track = PaletteMath.trackIdentityIndex(session?.selectedTrack ?? 0)
        handleDrawing = HandleDrawing(
            stemWidth: geometry.stemDipWidth / devicePixelRatio,
            selectedStemWidth: geometry.selectedStemDipWidth / devicePixelRatio,
            nodeRadius: geometry.nodePaintRadius,
            outlineRadius: geometry.nodePaintRadius + geometry.nodeOutlineDipWidth / 2,
            outlineWidth: Float(geometry.nodeOutlineDipWidth / devicePixelRatio),
            ringRadius: geometry.selectedNodeRingRadius + geometry.selectedNodeRingDipWidth / 2,
            ringWidth: Float(geometry.selectedNodeRingDipWidth / devicePixelRatio),
            fill: PaletteMath.argb(PaletteMath.trackIdentityColors[track]),
            dimFill: PaletteMath.argb(palette.outline),
            stem: PaletteMath.argb(PaletteMath.velocityStemColors[track]),
            selection: PaletteMath.argb(palette.selectionRing),
            border: PaletteMath.argb(palette.noteBorder))
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

    /// Records stay in note paint order: stem, selection ring, fill, outline, hover ring.
    private func appendHandleDrawing() {
        guard let drawing = handleDrawing else { return }
        let scroll = projection.scrollOffsetX
        let fringe = 0.5 / devicePixelRatio
        let viewport = CGRect(x: 0, y: 0, width: plotWidth, height: plotHeight)
        let markerViewport = viewport.insetBy(dx: -fringe, dy: -fringe)
        for handle in publishedHandles {
            let x = handle.x - scroll
            let endX = handle.endX - scroll
            let id = handle.noteID.rawValue
            let stemWidth = handle.selected ? drawing.selectedStemWidth : drawing.stemWidth
            let stem = CGRect(
                x: min(x, endX), y: handle.y - stemWidth / 2,
                width: max(1, abs(endX - x)), height: stemWidth)
            if viewport.intersects(stem) {
                listWriter.rect(
                    PdDlRect(
                        x: stem.minX, y: stem.minY, w: stem.width, h: stem.height,
                        id: id, argb: handle.selected ? drawing.selection : drawing.stem, flags: 0))
            }
            if handle.selected {
                let ring = drawing.ringRadius
                let bounds = CGRect(x: x - ring, y: handle.y - ring, width: 2 * ring, height: 2 * ring)
                if markerViewport.intersects(bounds) {
                    listWriter.rect(
                        PdDlRect(
                            ellipseX: bounds.minX, y: bounds.minY, w: bounds.width, h: bounds.height,
                            id: id, argb: drawing.selection, strokeWidth: drawing.ringWidth))
                }
            }
            let radius = drawing.nodeRadius
            let node = CGRect(x: x - radius, y: handle.y - radius, width: 2 * radius, height: 2 * radius)
            if markerViewport.intersects(node) {
                listWriter.rect(
                    PdDlRect(
                        ellipseX: node.minX, y: node.minY, w: node.width, h: node.height,
                        id: id, argb: handle.dimmed ? drawing.dimFill : drawing.fill))
                if handle.selected || !handle.dimmed {
                    listWriter.rect(
                        PdDlRect(
                            ellipseX: node.minX, y: node.minY, w: node.width, h: node.height,
                            id: id, argb: drawing.border, strokeWidth: drawing.outlineWidth))
                }
            }
            if handle.hovered && !handle.selected {
                let ring = drawing.outlineRadius
                let bounds = CGRect(x: x - ring, y: handle.y - ring, width: 2 * ring, height: 2 * ring)
                if markerViewport.intersects(bounds) {
                    listWriter.rect(
                        PdDlRect(
                            ellipseX: bounds.minX, y: bounds.minY, w: bounds.width, h: bounds.height,
                            id: id, argb: drawing.selection, strokeWidth: drawing.ringWidth))
                }
            }
        }
    }

    @QtIgnored func publishDisplayLists(bandsInput: VelocitySceneInput? = nil) {
        guard contentVisible, let session, let owner = viewport else { return }
        let camera = owner.camera
        let grid = owner.grid
        let metrics = gridMetrics(session)
        if let bandsInput { drawingBands = VelocityScene.modelBands(bandsInput, axis: axis) }
        let viewport = CGSize(width: plotWidth, height: plotHeight)
        let dpr = devicePixelRatio
        let colors = DrawerStaticsContent.gridPaletteColors(palette)
        DrawerStaticsContent.buildGrid(
            into: &listWriter, axis: metrics.timeAxis, grid: grid,
            camera: camera, viewport: viewport, paletteColors: colors)
        DrawerStaticsContent.buildTickRects(
            into: &listWriter, rects: drawingBands,
            camera: camera, dpr: dpr, viewport: viewport)
        appendHandleDrawing()
        if let transient = drawingTransientRects() {
            DrawerStaticsContent.buildTickRects(
                into: &transientWriter, rects: [transient.fill],
                camera: camera, dpr: dpr, viewport: viewport)
            let x0 = camera.viewX(tick: Double(transient.frame.tickStart), dpr: dpr)
            let x1 = camera.viewX(tick: Double(transient.frame.tickEnd), dpr: dpr)
            let box = CGRect(
                x: x0, y: Double(transient.frame.y),
                width: x1 - x0, height: Double(transient.frame.height))
            DrawerStaticsContent.buildDashedFrame(
                into: &transientWriter, box: box, argb: transient.frame.argb,
                dashDevicePx: 4, gapDevicePx: 2, dpr: dpr, viewport: viewport)
        }
        if displayLists.isEmpty { displayLists = [Data(), Data()] }
        let contentChanged = listWriter.replaceIfChanged(into: &displayLists[0])
        let transientChanged = transientWriter.replaceIfChanged(into: &displayLists[1])
        guard contentChanged || transientChanged else { return }
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
        if updateDrawing { publishDisplayLists() }
    }

    /// Hidden pages resolve hovered readout semantics without stale drawing rows.
    func publishReadout(facts: SemanticFacts? = nil) {
        let readout: (text: String, visible: Bool, x: Double, y: Double)
        if !contentVisible {
            if let hovered, let session, let track = session.selectedTrack,
                let note = session.projectionCache.note(hovered, in: track)
            {
                let value = Int(rollPreview[hovered] ?? note.velocity)
                let source = facts?.source ?? VelocityScene.contextSource(session)
                let map = source.map(at: note.tick, key: Int(note.pitch))
                let level = map.level(of: value) ?? -1
                let text = map.levelCount > 0 && level >= 0 ? "Vol \(level + 1)" : "\(value)"
                let projection = self.projection
                readout = (
                    text, true, projection.stableXForTick(Double(note.tick)),
                    projection.yForNote(map: map, velocity: value, detentUnlock: !detentsEnabled)
                )
            } else {
                readout = ("", false, 0, 0)
            }
        } else if let hovered, let index = handleIndicesByID[hovered] {
            let handle = publishedHandles[index]
            let text =
                axis.mode == .intrinsic && handle.level >= 0
                ? "Vol \(handle.level + 1)" : "\(handle.value)"
            readout = (text, true, handle.x, handle.y)
        } else if let gesture, let first = gesture.notes.first {
            let handle = handleIndicesByID[first.noteID].map { publishedHandles[$0] }
            let preview = gesture.preview[first.noteID].map(Int.init) ?? Int(first.velocity)
            let text: String =
                if let handle {
                    axis.mode == .intrinsic && handle.level >= 0
                        ? "Vol \(handle.level + 1)" : "\(handle.value)"
                } else {
                    "\(preview)"
                }
            readout = (text, true, handle?.x ?? 0, handle?.y ?? 0)
        } else {
            readout = ("", false, 0, 0)
        }
        publish(\.readoutText, readout.text)
        publish(\.readoutVisible, readout.visible)
        publish(\.readoutX, readout.x)
        publish(\.readoutY, readout.y)
        publish(\.hoveredNoteText, hovered.map(velocityNoteText) ?? "")
    }

}
