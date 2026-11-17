import Foundation
import PorydawCore
import PorydawDocument
import QtBridge
import PorydawAppCommands
import PorydawAppPresentation

@MainActor
extension PianoGrid {
    private static let availabilityCommands = EditCommand.allCases

    @QtIgnored
    func updateTimeAxis() {
        metrics.timeAxis = viewport.syncTimeAxis()
    }

    @QtIgnored
    func sceneInput() -> GridSceneInput {
        let snap = Int(max(1, viewport.grid.snapTicksAt(session.editCursor, camera: viewport.camera)))
        notes.refresh(session: session, snap: snap)
        notes.selectedTrack = trackIndex
        recomputeContentEndTick()
        let velocityPreview = velocityPreviewPresentation
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
        let displacement = noteDisplacement()
        let displacedNotes: Set<NoteID> = displacement == .none ? [] : session.selectedNotes
        return GridSceneInput(
            metrics: metrics, grid: viewport.grid, palette: palette, camera: viewport.camera,
            scale: viewport.scale,
            typography: typography, fontSpec: { self.fontSpec($0) },
            fonts: measurementFonts, notes: notes,
            displacement: displacement, displacedNotes: displacedNotes,
            selectedNotes: selectedNotes,
            velocityPreview: velocityPreview,
            drawPreview: drawPreview, paintPreview: paintPreview, bandSelection: selectionBand,
            lastVelocity: lastVelocity, hoverKey: hoverKey,
            noteNameMode: noteNameMode,
            showVelocityValues: showVelocityValues,
            timeSelection: session.timeSelection,
            usedTrackCount: session.document.engineTracks.usedTrackCount,
            keyboardNames: drumNames, keyboardBankIdentity: ObjectIdentifier(session.bankLease),
            keyboardProgram: program, rulerHeight: rulerHeight)
    }

    @QtIgnored
    func rebuildScene() {
        let input = sceneInput()
        scene.rebuildNotes(input)
        scene.rebuildStatic(input)
    }

    @QtIgnored
    func refreshNotes() {
        updateTypography()
        let input = sceneInput()
        scene.rebuildNotes(input)
        scene.rebuildStatic(input)
        publishVelocityPreview(input.velocityPreview)
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
        updateTypography()
        let input = sceneInput()
        scene.rebuildNotes(input)
        scene.rebuildStatic(input)
        publishOutputs()
    }

    /// Geometry changes reuse neutral track content and invalidate each list
    /// through its own actual camera/typography dependencies.
    @QtIgnored
    private func refreshCameraPresentationGeometry() {
        updateTimeAxis()
        updateTypography()
        let input = sceneInput()
        scene.rebuildNotes(input)
        scene.rebuildStatic(input)
        publishOutputs()
    }

    @QtIgnored
    private func recomputeContentEndTick() {
        var end = max(Int(session.timeline.lengthTicks), GridMetrics.songLengthTicks)
        end = max(end, notes.endTick)
        if let preview = drawPreview { end = max(end, preview.tick + preview.duration) }
        for preview in paintPreview { end = max(end, preview.tick + preview.duration) }
        contentEndTick = end
    }

    @QtIgnored
    private func updateTypography() {
        let cameraRowHeight = viewport.camera.snapshot.keyHeight
        let key = (
            fontPx: metrics.baseFontPx, dpr: metrics.dpr,
            rowHeight: cameraRowHeight
        )
        if let current = typographyKey,
            current.fontPx == key.fontPx && current.dpr == key.dpr
                && current.rowHeight == key.rowHeight
        {
            return
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
        let middle: Int
        if let low = notes.minPitch, let high = notes.maxPitch {
            middle = (low + high) / 2
        } else {
            middle = 60
        }
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
        let status = currentStatusPresentation()
        if status != lastStatusPresentation {
            lastStatusPresentation = status
            let text = status.text
            if statusText != text { statusText = text }
        }
        var availabilityChanged = interactionActive != lastCommandGestureActive
        for (index, command) in Self.availabilityCommands.enumerated() {
            let available = commands.isAvailable(command)
            if index == lastCommandAvailability.count {
                lastCommandAvailability.append(available)
                availabilityChanged = true
            } else if lastCommandAvailability[index] != available {
                lastCommandAvailability[index] = available
                availabilityChanged = true
            }
        }
        lastCommandGestureActive = interactionActive
        if availabilityChanged {
            onCommandAvailabilityChanged?()
        }
        publishGeometry()
    }

    @QtIgnored
    func fetchNoteSummaryImpl() -> String {
        let selectedNotes = session.selectedNotes
        var parts: [String] = []
        parts.reserveCapacity(notes.count)
        for pass in 0..<2 {
            for track in notes.tracks.indices where (track == notes.selectedTrack) == (pass == 0) {
                for note in notes.tracks[track].notes {
                    var json = "{\"id\":\(note.noteId.rawValue),\"tick\":\(note.tick)"
                    json += ",\"duration\":\(note.duration),\"pitch\":\(note.pitch)"
                    json += ",\"track\":\(note.track),\"velocity\":\(note.velocity)"
                    json += ",\"ghost\":\(track != notes.selectedTrack)"
                    json += ",\"selected\":\(selectedNotes.contains(note.noteId))}"
                    parts.append(json)
                }
            }
        }
        return "[" + parts.joined(separator: ",") + "]"
    }
}
