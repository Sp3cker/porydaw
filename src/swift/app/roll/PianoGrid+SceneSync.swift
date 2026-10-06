import Foundation
import PorydawCore
import PorydawDocument
import QtBridge
import PorydawAppCommands

@MainActor
extension PianoGrid {
    @QtIgnored
    func updateTimeAxis() {
        metrics.timeAxis = viewport.syncTimeAxis()
    }

    @QtIgnored
    func sceneInput() -> GridSceneInput {
        let visibleNotes: [GridNote]
        if case .velocity(let state) = gesture, state.preview != nil {
            visibleNotes = notes.map { note in
                guard let velocity = previewVelocity(note.noteId) else { return note }
                return GridNote(
                    noteId: note.noteId, tick: note.tick, duration: note.duration,
                    pitch: note.pitch, track: note.track, velocity: velocity,
                    ghost: note.ghost)
            }
        } else {
            visibleNotes = notes
        }
        let showVelocityValues: Bool
        switch gesture {
        case .velocity:
            showVelocityValues = true
        case .draw, .pendingDraw:
            showVelocityValues = pointerModifiers & QtFact.controlModifier != 0
        default:
            showVelocityValues = false
        }
        let initial =
            session.timeline.tracks.indices.contains(trackIndex)
            ? session.timeline.tracks[trackIndex].firstProgram : -1
        let program = max(0, initial)
        let drumNames =
            session.bankSlots.indices.contains(program)
            ? session.bankSlots[program].drumPadNames : nil
        let selectedNotes: Set<NoteID> =
            selectionBand != nil
                && rightPointerModifiers & QtFact.controlModifier == 0
            ? [] : session.selectedNotes
        let displacesNotes: Bool
        switch gesture {
        case .move, .resize: displacesNotes = true
        default: displacesNotes = false
        }
        return GridSceneInput(
            metrics: metrics, grid: viewport.grid, palette: palette, camera: viewport.camera,
            scale: viewport.scale,
            typography: typography, fontSpec: { self.fontSpec($0) },
            fonts: measurementFonts, notes: visibleNotes,
            displayedNote: { self.displayedNote($0) },
            displacesNotes: displacesNotes,
            selectedNotes: selectedNotes,
            drawPreview: drawPreview, bandSelection: selectionBand,
            lastVelocity: lastVelocity, hoverKey: hoverKey,
            noteNameMode: noteNameMode,
            showVelocityValues: showVelocityValues,
            timeSelection: session.timeSelection,
            usedTrackCount: session.document.engineTracks.usedTrackCount,
            selectedTrack: trackIndex,
            keyboardNames: drumNames, keyboardBankIdentity: ObjectIdentifier(session.bankLease),
            keyboardProgram: program, rulerHeight: rulerHeight)
    }

    @QtIgnored
    func rebuildScene() {
        let input = sceneInput()
        scene.invalidatePaletteCache()
        staticSceneDirty = false
        scene.rebuildNotes(input)
        scene.rebuildStatic(input)
    }

    @QtIgnored
    func refreshNotes() {
        recomputeContentEndTick()
        let typographyChanged = updateTypography()
        if typographyChanged { staticSceneDirty = true }
        let input = sceneInput()
        if staticSceneDirty {
            scene.invalidatePaletteCache()
            staticSceneDirty = false
        }
        scene.rebuildNotes(input)
        scene.rebuildStatic(input)
        if typographyChanged {
            scene.rebuildHover(input)
        } else if hoverKey >= 0 {
            scene.refreshHoverChip(input)
        }
        publishVelocityPreview()
        publishOutputs()
    }

    @QtIgnored
    public func refreshCameraPresentation(_ change: EditorCamera.Change) {
        let fontsKept =
            typographyKey.map {
                $0.fontPx == metrics.baseFontPx && $0.dpr == metrics.dpr
            } ?? false
        guard fontsKept, !change.contains(.geometry) else {
            refreshCameraPresentationGeometry()
            return
        }
        let typographyChanged = updateTypography()
        let input = sceneInput()
        if typographyChanged || staticSceneDirty {
            scene.invalidatePaletteCache()
            staticSceneDirty = false
        }
        scene.rebuildDisplayLists(input)
        scene.rebuildStatic(input)
        if typographyChanged {
            scene.rebuildHover(input)
        } else if hoverKey >= 0 {
            scene.refreshHoverChip(input)
        }
        publishOutputs()
    }

    /// Geometry seam: refreshes axis/fonts, reuses cached records unless
    /// the projection changed; fonts/projection/cold take the content path.
    @QtIgnored
    private func refreshCameraPresentationGeometry() {
        updateTimeAxis()
        let typographyChanged = updateTypography()
        let input = sceneInput()
        if typographyChanged || staticSceneDirty {
            scene.invalidatePaletteCache()
            staticSceneDirty = false
        }
        guard !typographyChanged,
            scene.projectionCovers(input.camera.projection)
        else {
            refreshNotes()
            return
        }
        scene.rebuildDisplayLists(input)
        scene.rebuildStatic(input)
        if hoverKey >= 0 {
            scene.refreshHoverChip(input)
        }
        publishOutputs()
    }

    @QtIgnored
    private func recomputeContentEndTick() {
        let length = session.timeline.lengthTicks
        if notes == lastEndTickNotes, length == lastEndTickLength,
            drawPreview?.tick == lastEndTickPreview?.tick,
            drawPreview?.duration == lastEndTickPreview?.duration,
            drawPreview?.pitch == lastEndTickPreview?.pitch
        {
            return
        }
        lastEndTickNotes = notes
        lastEndTickPreview = drawPreview
        lastEndTickLength = length
        var end = max(Int(length), GridMetrics.songLengthTicks)
        for note in notes { end = max(end, note.tick + note.duration) }
        if let preview = drawPreview { end = max(end, preview.tick + preview.duration) }
        contentEndTick = end
    }

    @discardableResult
    @QtIgnored
    private func updateTypography() -> Bool {
        let cameraRowHeight = viewport.camera.snapshot.keyHeight
        let key = (
            fontPx: metrics.baseFontPx, dpr: metrics.dpr,
            rowHeight: cameraRowHeight
        )
        if let current = typographyKey,
            current.fontPx == key.fontPx && current.dpr == key.dpr
                && current.rowHeight == key.rowHeight
        {
            return false
        }
        measurementFonts = GridTypography.fonts(
            metrics: metrics, typography: roleTypography)
        let measured = GridTypography(
            fonts: measurementFonts, rowHeight: cameraRowHeight, pixel: metrics.pixel)
        typography = measured
        typographyKey = key
        let markerRowHeight = measured.boldHeight + 1
        publish(\.rulerMarkerRowHeight, markerRowHeight)
        publish(\.rulerHeight, markerRowHeight + measured.rulerHeight + 1)
        return true
    }

    @QtIgnored
    private func fontSpec(_ kind: GridFontKind) -> QmlFont {
        if let typography { return typography.font(kind) }
        guard let font = measurementFonts[kind] else {
            preconditionFailure("PianoGrid requires measured fonts before scene publication")
        }
        return font.qmlFont
    }

    @QtIgnored
    private func publishGeometry() {
        let snapshot = viewport.camera.snapshot
        publish(\.beatWidth, snapshot.pixelsPerBeat)
        publish(\.rowHeight, snapshot.keyHeight)
        publish(\.cameraScrollX, snapshot.scrollX)
        publish(\.scaleFold, viewport.scale.fold)
        let rowCount = viewport.camera.projection.visibleRowCount
        publish(\.visibleRowCount, rowCount)
        publish(\.cameraScrollY, snapshot.scrollY)
        publish(\.cameraMaxVScroll, snapshot.maxVScroll)
        publish(\.cameraMinHScroll, snapshot.minHScroll)
        publish(\.cameraMaxHScroll, snapshot.maxHScroll)
        publish(\.keyboardWidth, metrics.keyboardWidth)
        let headerWidth = fontPx(baseFontPx, 17.5)
        publish(\.trackHeaderWidth, headerWidth)
        let cursorExtent = Int(fontPx(baseFontPx, 2.0))
        publish(\.resizeCursorExtent, cursorExtent)
        let tpb = Int(max(1, session.document.ticksPerBeat))
        publish(\.ticksPerBeat, tpb)
        let snap = Int(viewport.grid.snapTicksAt(session.editCursor, camera: viewport.camera))
        publish(\.snapTicks, snap)
        let gridTicks = Int(viewport.grid.gridTicksAt(session.editCursor, camera: viewport.camera))
        publish(\.visibleGridTicks, gridTicks)
    }

    @QtIgnored
    func defaultVerticalScroll(camera: EditorCamera) -> Double {
        let pitches = notes.map(\.pitch)
        let middle = pitches.isEmpty ? 60 : (pitches.min()! + pitches.max()!) / 2
        guard let pitch = camera.projection.nearestVisiblePitch(to: middle) else { return 0 }
        let centerRow = camera.projection.row(forPitch: pitch)
        return max(
            0,
            Double(centerRow) * camera.snapshot.keyHeight
                - max(
                    fontPx(metrics.baseFontPx, 50.0 / 3.0),
                    camera.snapshot.rollHeight) / 2)
    }

    @QtIgnored
    func publishOutputs() {
        if renderedNoteCount != scene.noteRecordCount {
            renderedNoteCount = scene.noteRecordCount
        }
        let band = selectionBand
        if bandSelectionActive != (band != nil) { bandSelectionActive = band != nil }
        let bandX = band?.x ?? 0
        let bandY = band?.y ?? 0
        let bandW = band?.w ?? 0
        let bandH = band?.h ?? 0
        if bandSelectionX != bandX { bandSelectionX = bandX }
        if bandSelectionY != bandY { bandSelectionY = bandY }
        if bandSelectionWidth != bandW { bandSelectionWidth = bandW }
        if bandSelectionHeight != bandH { bandSelectionHeight = bandH }
        let status = currentStatusText()
        if statusText != status { statusText = status }
        let availability = EditCommand.allCases.map { commands.isAvailable($0) }
        if availability != lastCommandAvailability || interactionActive != lastCommandGestureActive {
            lastCommandAvailability = availability
            lastCommandGestureActive = interactionActive
            onCommandAvailabilityChanged?()
        }
        publishGeometry()
    }

    @QtIgnored
    func fetchNoteSummaryImpl() -> String {
        let selectedNotes = session.selectedNotes
        let parts = notes.map { note -> String in
            var json = "{\"id\":\(note.noteId.rawValue),\"tick\":\(note.tick)"
            json += ",\"duration\":\(note.duration),\"pitch\":\(note.pitch)"
            json += ",\"track\":\(note.track),\"velocity\":\(note.velocity)"
            json += ",\"ghost\":\(note.ghost)"
            json += ",\"selected\":\(selectedNotes.contains(note.noteId))}"
            return json
        }
        return "[" + parts.joined(separator: ",") + "]"
    }
}
