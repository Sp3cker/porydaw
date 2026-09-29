import Foundation
import PorydawCore
import QtBridge
import PorydawAppCommands

@MainActor
extension PianoGrid {
    @QtIgnored
    func updateTimeAxis() {
        metrics.timeAxis = session.projectionCache.timeAxis
        session.grid.axis = metrics.timeAxis
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
        let initial = session.timeline.tracks.indices.contains(trackIndex)
            ? session.timeline.tracks[trackIndex].firstProgram : -1
        let program = max(0, initial)
        let drumNames = session.bankSlots.indices.contains(program)
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
            metrics: metrics, grid: session.grid, palette: palette, camera: session.camera,
            scale: session.scaleProjection,
            typography: typography, fontSpec: { self.fontSpec($0) },
            fonts: measurementFonts, notes: visibleNotes,
            displayedNote: { self.displayedNote($0) },
            displacesNotes: displacesNotes,
            selectedNotes: selectedNotes,
            drawPreview: drawPreview, lastVelocity: lastVelocity,
            hoverKey: hoverKey,
            noteNameMode: noteNameMode,
            showVelocityValues: showVelocityValues,
            timeSelection: session.timeSelection,
            usedTrackCount: session.document.engineTracks.usedTrackCount,
            selectedTrack: trackIndex,
            keyboardNames: drumNames, keyboardBankIdentity: ObjectIdentifier(session.bankLease),
            keyboardProgram: program)
    }

    @QtIgnored
    func rebuildScene() {
        let input = sceneInput()
        scene.invalidateStatic()
        scene.rebuildStatic(input)
        staticSceneDirty = false
        scene.rebuildNotes(input)
    }

    @QtIgnored
    func refreshNotes() {
        recomputeContentEndTick()
        let typographyChanged = updateTypography()
        if typographyChanged { staticSceneDirty = true }
        let input = sceneInput()
        if staticSceneDirty {
            scene.invalidateStatic()
            staticSceneDirty = false
        }
        scene.rebuildStatic(input)
        scene.rebuildNotes(input)
        if typographyChanged {
            scene.rebuildHover(input)
        } else if hoverKey >= 0 {
            scene.refreshHoverChip(input)
        }
        publishOutputs()
    }

    @QtIgnored
    public func refreshCameraPresentation(_ change: EditorCamera.Change) {
        let fontsKept =
            typographyKey.map {
                $0.fontPx == metrics.baseFontPx && $0.dpr == metrics.dpr
            } ?? false
        guard fontsKept, !change.contains(.geometry) else {
            refreshCamera()
            return
        }
        let typographyChanged = updateTypography()
        let input = sceneInput()
        if typographyChanged || staticSceneDirty {
            scene.invalidateStatic()
            staticSceneDirty = false
        }
        scene.rebuildStatic(input)
        if typographyChanged {
            scene.rebuildHover(input)
        } else if hoverKey >= 0 {
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
            drawPreview?.pitch == lastEndTickPreview?.pitch { return }
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
        let cameraRowHeight = session.camera.snapshot.keyHeight
        let key = (fontPx: metrics.baseFontPx, dpr: metrics.dpr,
                   rowHeight: cameraRowHeight)
        if let current = typographyKey,
           current.fontPx == key.fontPx && current.dpr == key.dpr
            && current.rowHeight == key.rowHeight { return false }
        measurementFonts = GridTypography.fonts(
            metrics: metrics, typography: roleTypography)
        let measured = GridTypography(
            fonts: measurementFonts, rowHeight: cameraRowHeight, pixel: metrics.pixel)
        typography = measured
        typographyKey = key
        let markerRowHeight = measured.boldHeight + 1
        if rulerMarkerRowHeight != markerRowHeight {
            rulerMarkerRowHeight = markerRowHeight
        }
        if rulerHeight != markerRowHeight + measured.rulerHeight + 1 {
            rulerHeight = markerRowHeight + measured.rulerHeight + 1
        }
        return true
    }

    @QtIgnored
    private func fontSpec(_ kind: GridFontKind) -> [String: QVariantSettable] {
        typography?.fontMap(kind) ?? measurementFonts[kind]!.map
    }

    @QtIgnored
    private func publishGeometry() {
        let snapshot = session.camera.snapshot
        if beatWidth != snapshot.pixelsPerBeat { beatWidth = snapshot.pixelsPerBeat }
        if pixelsPerTick != snapshot.pixelsPerTick { pixelsPerTick = snapshot.pixelsPerTick }
        if rowHeight != snapshot.keyHeight { rowHeight = snapshot.keyHeight }
        if cameraScrollX != snapshot.scrollX { cameraScrollX = snapshot.scrollX }
        if scaleFold != session.scaleProjection.fold { scaleFold = session.scaleProjection.fold }
        let rowCount = session.camera.projection.visibleRowCount
        if visibleRowCount != rowCount { visibleRowCount = rowCount }
        if cameraScrollY != snapshot.scrollY { cameraScrollY = snapshot.scrollY }
        if cameraMaxVScroll != snapshot.maxVScroll { cameraMaxVScroll = snapshot.maxVScroll }
        if cameraMinHScroll != snapshot.minHScroll { cameraMinHScroll = snapshot.minHScroll }
        if cameraMaxHScroll != snapshot.maxHScroll { cameraMaxHScroll = snapshot.maxHScroll }
        if keyboardWidth != metrics.keyboardWidth { keyboardWidth = metrics.keyboardWidth }
        let headerWidth = fontPx(baseFontPx, 17.5)
        if trackHeaderWidth != headerWidth { trackHeaderWidth = headerWidth }
        let cursorExtent = Int(fontPx(baseFontPx, 2.0))
        if resizeCursorExtent != cursorExtent { resizeCursorExtent = cursorExtent }
        let tpb = Int(max(1, session.document.ticksPerBeat))
        if ticksPerBeat != tpb { ticksPerBeat = tpb }
        let snap = Int(session.grid.snapTicksAt(session.editCursor, camera: session.camera))
        if snapTicks != snap { snapTicks = snap }
        let gridTicks = Int(session.grid.gridTicksAt(session.editCursor, camera: session.camera))
        if visibleGridTicks != gridTicks { visibleGridTicks = gridTicks }
    }

    @QtIgnored
    func defaultVerticalScroll(camera: EditorCamera) -> Double {
        let pitches = notes.map(\.pitch)
        let middle = pitches.isEmpty ? 60 : (pitches.min()! + pitches.max()!) / 2
        guard let pitch = camera.projection.nearestVisiblePitch(to: middle) else { return 0 }
        let centerRow = camera.projection.row(forPitch: pitch)
        return max(
            0, Double(centerRow) * camera.snapshot.keyHeight
                - max(fontPx(metrics.baseFontPx, 50.0 / 3.0),
                      camera.snapshot.rollHeight) / 2)
    }

    @QtIgnored
    func pitch(atY y: Double) -> Int {
        let snapshot = session.camera.snapshot
        return session.camera.projection.pitch(
            atY: y, keyHeight: snapshot.keyHeight,
            scrollY: snapshot.scrollY, dpr: metrics.dpr) ?? -1
    }

    @QtIgnored
    func displayedNote(_ note: GridNote) -> (tick: Int, end: Int, pitch: Int) {
        var tick = note.tick
        var end = note.tick + note.duration
        var pitch = note.pitch
        guard let gesture, !note.ghost, session.selectedNotes.contains(note.noteId) else {
            return (tick, end, pitch)
        }
        switch gesture {
        case .resize(let state) where state.leading:
            tick = min(max(0, tick + state.delta), end - 1)
        case .move(let state):
            tick = max(0, tick + state.dTick)
            end = max(tick + 1, end + state.dTick)
            if session.scaleProjection.fold && state.dKey != 0 {
                let destination = session.scaleProjection.scale.pitch(
                    pitch, steps: state.dKey, root: session.scaleProjection.root)
                if destination >= 0 { pitch = destination }
            } else {
                pitch = min(127, max(0, pitch + state.dKey))
            }
        case .resize(let state):
            end = max(tick + 1, end + state.delta)
        default:
            break
        }
        return (tick, end, pitch)
    }

    enum HitZone { case none, body, leftEdge, rightEdge }

    @QtIgnored
    private func hitZone(x: Double, y: Double, note: GridNote) -> (HitZone, Bool) {
        let reach = metrics.edgeGripReach
        let rect = metrics.noteRect(
            camera: session.camera,
            x0: session.camera.displayX(tick: Double(note.tick), origin: 0, dpr: metrics.dpr),
            x1: session.camera.displayX(
                tick: Double(note.tick + note.duration), origin: 0, dpr: metrics.dpr),
            pitch: note.pitch)
        guard y >= rect.y, y < rect.y + rect.h else { return (.none, false) }
        let right = rect.x + rect.w
        let inside = x >= rect.x && x < right
        guard inside || (x >= rect.x - reach && x < right + reach) else {
            return (.none, false)
        }
        let inner = metrics.edgeGripInnerReach(rectWidth: rect.w)
        if x >= right - inner && x <= right + reach { return (.rightEdge, inside) }
        if x >= rect.x - reach && x <= rect.x + inner { return (.leftEdge, inside) }
        return (.body, inside)
    }

    @QtIgnored
    func hitNote(x: Double, y: Double) -> (index: Int, zone: HitZone)? {
        var hit: (index: Int, zone: HitZone)?
        var hitInside = false
        var grip: (index: Int, zone: HitZone)?
        for index in notes.indices {
            if notes[index].ghost { continue }
            let (zone, inside) = hitZone(x: x, y: y, note: notes[index])
            if zone == .none { continue }
            hit = (index, zone)
            hitInside = inside
            if inside && (zone == .leftEdge || zone == .rightEdge) {
                grip = (index, zone)
            }
        }
        if let grip, !hitInside { return grip }
        return hit
    }

    @QtIgnored
    private func currentStatusText() -> String {
        if let gesture {
            switch gesture {
            case .pendingDraw(let state):
                return "Pending draw at tick \(session.grid.snapTick(state.pressTick, camera: session.camera))"
            case .draw(let state):
                return "Drawing — tick \(state.tick), duration \(state.duration), pitch \(state.key)"
            case .velocity:
                return "Changing velocity"
            case .move(let state):
                return "Moving \(session.selectedNotes.count) note(s) — dTick \(state.dTick), dKey \(state.dKey)"
            case .resize:
                return "Resizing \(session.selectedNotes.count) note(s)"
            case .pendingMenu:
                return "\(notes.count) notes, \(session.selectedNotes.count) selected"
            case .band:
                return "Selecting \(session.selectedNotes.count) note(s)"
            case .pan:
                return "Panning"
            }
        }
        if case .band = rightGesture {
            return "Selecting \(session.selectedNotes.count) note(s)"
        }
        return "\(notes.count) notes, \(session.selectedNotes.count) selected"
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
