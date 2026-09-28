import Foundation
import PorydawCore
import QtBridge
import PorydawAppCommands

@MainActor
extension PianoGrid {

    @QtIgnored
    func applyPressSelection(_ id: NoteID, modifiers: Int) {
        if modifiers & QtFact.controlModifier != 0 {
            if !session.selectedNotes.contains(id) {
                addSelectedNoteFromLeftPointer(id)
            }
        } else if modifiers & QtFact.shiftModifier != 0 {
            addSelectedNoteFromLeftPointer(id)
        } else if !session.selectedNotes.contains(id) {
            session.setSelectedNotes([id])
        }
    }

    @QtIgnored
    func addSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.addSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted,
           !selectionAtRightPress.contains(id) {
            selectionAtRightPress.append(id)
        }
    }

    @QtIgnored
    func removeSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.removeSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted {
            selectionAtRightPress.removeAll { $0 == id }
        }
    }

    @QtIgnored
    func commitGesture() {
        guard let gesture else { return }
        let ids = session.selectedNoteOrder
        switch gesture {
        case .pendingDraw:
            break
        case .draw(let state):
            addNote(tick: state.tick, duration: state.duration, pitch: state.key)
        case .velocity(let state):
            if state.delta != 0 {
                var changes: [NoteVelocity] = []
                for id in session.selectedNoteOrder {
                    guard let current = session.document.note(id) else { continue }
                    changes.append(NoteVelocity(
                        noteID: id, velocity: Int(current.velocity) + state.delta))
                }
                if changes.isEmpty {
                    changes.append(NoteVelocity(
                        noteID: state.noteId, velocity: state.original + state.delta))
                }
                if session.document.setVelocities(
                    changes, expectedRevision: session.document.revision) != nil {
                    lastVelocity = min(127, max(1, state.original + state.delta))
                }
            }
        case .move(let state):
            if session.scaleProjection.fold && state.dKey != 0 {
                let selected = ids.compactMap { session.document.note($0) }
                if let pitches = session.scaleProjection.destinations(for: selected, steps: state.dKey) {
                    _ = session.document.moveNotes(
                        selected.map(\.id), toPitches: pitches, byTicks: Int64(state.dTick))
                }
            } else {
                session.document.moveNotes(ids, byTicks: Int64(state.dTick), byKeys: state.dKey)
            }
        case .resize(let state):
            session.document.resizeNotes(ids, edge: state.leading ? .leading : .trailing,
                                         byTicks: Int64(state.delta))
        case .pendingMenu, .band, .pan:
            break
        }
    }

    @QtIgnored
    private func addNote(tick: Int, duration: Int, pitch: Int) {
        guard session.selectedTrack != nil, tick >= 0, duration > 0,
              (0...127).contains(pitch), tick < Int(TimeDefaults.maxTick),
              Int64(tick) + Int64(duration) <= Int64(TimeDefaults.maxTick)
        else { return }
        guard let ids = try? session.document.addNotes([
            NewNote(track: trackIndex, tick: Tick(tick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: UInt8(min(127, max(1, lastVelocity))))
        ]), let id = ids.first else { return }
        session.setSelectedNotes([id])
        activeNoteId = id.rawValue
    }

    @QtIgnored
    func bandCoveredNotes() -> [GridNote] {
        guard let band = selectionBand else { return [] }
        return notes.filter { note in
            guard !note.ghost else { return false }
            let displayed = displayedNote(note)
            let rect = metrics.noteRect(
                camera: session.camera,
                x0: session.camera.displayX(tick: Double(displayed.tick), origin: 0, dpr: metrics.dpr),
                x1: session.camera.displayX(tick: Double(displayed.end), origin: 0, dpr: metrics.dpr),
                pitch: displayed.pitch)
            return rect.x < band.x + band.w && rect.x + rect.w > band.x
                && rect.y < band.y + band.h && rect.y + rect.h > band.y
        }
    }

    @QtIgnored
    func applyBandSelection() {
        guard selectionBand != nil else { return }
        let previous =
            rightPointerModifiers & QtFact.controlModifier != 0
            ? selectionAtRightPress : []
        session.setSelectedNotes(previous + bandCoveredNotes().map(\.noteId))
    }

    @QtIgnored
    func auditionBandEntrants() {
        guard selectionBand != nil else { return }
        var covered: [NoteID: (track: Int, pitch: Int)] = [:]
        for note in bandCoveredNotes() {
            guard let source = session.document.note(note.noteId), source.duration > 0 else {
                continue
            }
            covered[note.noteId] = (note.track, note.pitch)
            if bandAuditioned[note.noteId] == nil {
                onAudition?(note.track, note.pitch, note.velocity)
            }
        }
        for (id, entry) in bandAuditioned where covered[id] == nil {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned = covered
    }

    @QtIgnored
    func releaseBandAudition() {
        for (_, entry) in bandAuditioned {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned.removeAll()
    }

    func beginPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard gesture == nil else { return }
        suppressedLeftRelease = false
        pointerModifiers = modifiers
        stopAudition()
        pendingVelocityReanchor = nil
        let pressTick = session.camera.tickAtContentX(x)
        let pressKey = pitch(atY: y)
        guard pressKey >= 0 else { return }
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            let control = modifiers & QtFact.controlModifier != 0
            pendingControlToggle = control && session.selectedNotes.contains(note.noteId)
                ? note.noteId : nil
            activeNoteId = note.noteId.rawValue
            lastVelocity = note.velocity
            keyboardAuditionKey = note.pitch
            keyboardAuditionTrack = trackIndex
            onAudition?(trackIndex, note.pitch, note.velocity)
            if control && hit.zone == .body {
                gesture = .velocity(GridGesture.Velocity(
                    noteId: note.noteId, pressY: y, original: note.velocity))
                pendingVelocityReanchor =
                    session.selectedNotes.contains(note.noteId) ? nil : note.noteId
                if hoverKey != note.pitch {
                    hoverKey = note.pitch
                    scene.rebuildHover(sceneInput())
                }
            } else {
                applyPressSelection(note.noteId, modifiers: modifiers)
                switch hit.zone {
                case .leftEdge:
                    gesture = .resize(pressTick: pressTick, gripTick: note.tick,
                                      oppositeTick: note.tick + note.duration, leading: true)
                case .rightEdge:
                    gesture = .resize(pressTick: pressTick, gripTick: note.tick + note.duration,
                                      oppositeTick: note.tick, leading: false)
                default:
                    gesture = .move(pressTick: pressTick, pressKey: pressKey)
                }
            }
            if case .band(let band) = rightGesture, !control {
                rightBandDemoted = true
                rightGesture = .pendingMenu(GridGesture.PendingMenu(
                    pressX: band.pressX, pressY: band.pressY,
                    threshold: .infinity, hitNoteId: NoteID()))
                releaseBandAudition()
            }
        } else {
            guard !session.scaleProjection.fold || session.scaleProjection.contains(pressKey)
            else { return }
            session.clearSelectedNotes()
            gesture = .pendingDraw(GridGesture.PendingDraw(
                pressX: x, pressY: y, pressTick: pressTick, pressKey: pressKey))
            keyboardAuditionKey = pressKey
            keyboardAuditionTrack = trackIndex
            onAudition?(trackIndex, pressKey, min(127, max(1, lastVelocity)))
        }
        refreshNotes()
    }

    func beginPanImpl(x: Double, y: Double) {
        guard !interactionActive else { return }
        gesture = .pan(GridGesture.Pan(pressX: x, pressY: y))
        if cursorKind != GridCursorKind.closedHand.rawValue {
            cursorKind = GridCursorKind.closedHand.rawValue
        }
        publishOutputs()
    }

    func updatePanImpl(x: Double, y: Double) {
        guard let gesture, case .pan = gesture else { return }
        let updated = gesture.updated(
            x: x, y: y, metrics: metrics, grid: session.grid,
            camera: session.camera, scale: session.scaleProjection)
        guard case .pan(let state) = updated else { return }
        if state.deltaX != 0 || state.deltaY != 0 {
            session.mutateCamera { camera in
                _ = camera.scrollByPx(-state.deltaX)
                _ = camera.scrollRollBy(-state.deltaY)
            }
        }
        self.gesture = updated
    }

    func endPanImpl() {
        guard case .pan = gesture else { return }
        gesture = nil
        if cursorKind != GridCursorKind.arrow.rawValue {
            cursorKind = GridCursorKind.arrow.rawValue
        }
        publishOutputs()
    }

    func updatePointerImpl(x: Double, y: Double, modifiers: Int = 0) {
        pointerModifiers = modifiers
        guard let gesture, !gesture.isRight else { return }
        if case .velocity(let state) = gesture, state.preview == nil,
           abs(y - state.pressY) < dragDistance { return }
        if case .pendingDraw = gesture {
            let key = pitch(atY: y)
            if key >= 0, (!session.scaleProjection.fold || session.scaleProjection.contains(key)),
               key != keyboardAuditionKey {
                stopAudition()
                keyboardAuditionKey = key
                keyboardAuditionTrack = trackIndex
                onAudition?(trackIndex, key, min(127, max(1, lastVelocity)))
            }
        }
        self.gesture = gesture.updated(
            x: x, y: y, metrics: metrics, grid: session.grid,
            camera: session.camera, scale: session.scaleProjection)
        if case .velocity(let state) = self.gesture {
            if let reanchor = pendingVelocityReanchor {
                pendingVelocityReanchor = nil
                session.setSelectedNotes([reanchor])
            } else if !session.selectedNotes.contains(state.noteId) {
                session.setSelectedNotes([state.noteId])
            }
            pendingControlToggle = nil
        }
        refreshNotes()
    }

    func endPointerImpl(x: Double, y: Double) {
        defer { suppressedLeftRelease = false }
        guard let gesture, !gesture.isRight else { return }
        if case .pendingDraw(let state) = gesture {
            if abs(x - state.pressX) >= drawThreshold {
                self.gesture = gesture.updated(
                    x: x, y: y, metrics: metrics, grid: session.grid,
                    camera: session.camera, scale: session.scaleProjection)
                if !suppressedLeftRelease { commitGesture() }
                stopAudition()
            } else {
                if case .band = rightGesture {
                    stopAudition()
                } else {
                    if let selection = session.timeSelection, selection.isActive,
                       session.timeSelectionCoversTrack(trackIndex),
                       selection.contains(Tick(max(0, Int(session.camera.tickAtContentX(x))))) {
                        session.clearTimeSelection()
                    }
                    let tick = session.grid.snapTick(state.pressTick, camera: session.camera)
                    session.editCursor = Tick(tick)
                    editCursorTick = Int(tick)
                    stopAudition()
                }
            }
        } else if case .velocity(let state) = gesture, state.preview == nil {
            // A stationary modifier press is a deferred selection click.
        } else {
            self.gesture = gesture.updated(
                x: x, y: y, metrics: metrics, grid: session.grid,
                camera: session.camera, scale: session.scaleProjection)
            if !suppressedLeftRelease { commitGesture() }
        }
        if let pendingControlToggle, !suppressedLeftRelease {
            switch self.gesture {
            case .move(let state) where state.dTick == 0 && state.dKey == 0:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            case .resize(let state) where state.delta == 0:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            case .velocity(let state) where state.preview == nil:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            default:
                break
            }
        } else if case .velocity(let state) = self.gesture, state.preview == nil,
                  !suppressedLeftRelease {
            addSelectedNoteFromLeftPointer(state.noteId)
        }
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        pointerModifiers = 0
        self.gesture = nil
        stopAudition()
        activeNoteId = 0
        refreshFromSession()
    }

    func beginRightPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard rightGesture == nil else { return }
        if case .pan = gesture { return }
        rightPointerModifiers = modifiers
        selectionAtRightPress = session.selectedNoteOrder
        rightBandDemoted = false
        releaseBandAudition()
        let hit = hitNote(x: x, y: y)
        let blockedByLeft: Bool
        switch gesture {
        case nil, .pendingDraw: blockedByLeft = false
        case .velocity(let state): blockedByLeft = state.preview != nil
        default: blockedByLeft = true
        }
        rightGesture = .pendingMenu(GridGesture.PendingMenu(
            pressX: x, pressY: y, threshold: blockedByLeft ? .infinity : dragDistance,
            hitNoteId: hit.map { notes[$0.index].noteId } ?? NoteID()))
        publishOutputs()
    }

    func updateRightPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard let rightGesture else { return }
        rightPointerModifiers = modifiers
        if !rightBandDemoted {
            let leftAllowsBand: Bool
            switch gesture {
            case nil, .pendingDraw: leftAllowsBand = true
            case .velocity(let state): leftAllowsBand = state.preview == nil
            default: leftAllowsBand = false
            }
            if leftAllowsBand {
                self.rightGesture = rightGesture.updated(
                    x: x, y: y, metrics: metrics, grid: session.grid,
                    camera: session.camera, scale: session.scaleProjection)
            }
        }
        if case .band = self.rightGesture { auditionBandEntrants() }
        refreshNotes()
    }

    func endRightPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard let rightGesture else { return }
        rightPointerModifiers = modifiers
        if case .pendingDraw = gesture {
            // PendingDraw remains parked until its own release.
        } else if gesture != nil {
            pointerModifiers = 0
            gesture = nil
            suppressedLeftRelease = true
            pendingVelocityReanchor = nil
        }
        let updated = rightBandDemoted ? rightGesture : rightGesture.updated(
            x: x, y: y, metrics: metrics, grid: session.grid,
            camera: session.camera, scale: session.scaleProjection)
        self.rightGesture = updated
        if case .band = updated, !rightBandDemoted {
            applyBandSelection()
        } else if case .pendingMenu(let state) = updated {
            if state.hitNoteId.isAssigned {
                if !session.selectedNotes.contains(state.hitNoteId) {
                    session.setSelectedNotes([state.hitNoteId])
                    refreshNotes()
                }
                contextMenuRequested(x: x, y: y)
            } else {
                session.clearSelectedNotes()
                session.clearTimeSelection()
            }
        }
        self.rightGesture = nil
        if gesture == nil { activeNoteId = 0 }
        releaseBandAudition()
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        publishOutputs()
        refreshNotes()
    }

    func doublePointerImpl(x: Double, y: Double) {
        stopAudition()
        if let hit = hitNote(x: x, y: y) {
            gesture = nil
            let id = notes[hit.index].noteId
            let ids = session.selectedNotes.contains(id) ? session.selectedNoteOrder : [id]
            session.document.deleteNotes(ids)
            session.clearSelectedNotes()
            refreshFromSession()
            return
        }
        let key = pitch(atY: y)
        guard key >= 0, !session.scaleProjection.fold || session.scaleProjection.contains(key)
        else { return }
        session.clearSelectedNotes()
        let tick = session.grid.snapTickDown(session.camera.tickAtContentX(x),
                                             camera: session.camera)
        gesture = .draw(GridGesture.Draw(
            anchorTick: Int(tick), tick: Int(tick),
            duration: Int(session.grid.snapTicksAt(tick, camera: session.camera)), key: key))
        refreshNotes()
    }

    func beginKeyboardPointerImpl(y: Double) {
        let key = pitch(atY: y)
        guard (0...127).contains(key) else { return }
        session.setSelectedNotes(notes.filter { !$0.ghost && $0.pitch == key }.map(\.noteId))
        refreshNotes()
        updateKeyboardPointer(y: y)
    }

    func updateKeyboardPointerImpl(y: Double) {
        let key = pitch(atY: y)
        guard key >= 0, key <= 127, key != keyboardAuditionKey else { return }
        stopAudition()
        let track = trackIndex
        keyboardAuditionKey = key
        keyboardAuditionTrack = track
        onAudition?(track, key, 100)
        hoverKey = key
        scene.rebuildHover(sceneInput())
    }

    func endKeyboardPointerImpl() {
        stopAudition()
    }

    func inputCancelledImpl(reason: Int) {
        guard let reason = GridCancelReason(rawValue: reason) else { return }
        lastCancelReason = reason.rawValue
        cancelInput()
    }

    func finishKeyboardTransposeAuditionImpl() -> Bool {
        guard keyboardTransposeAuditionActive, keyboardAuditionKey != nil,
              keyboardAuditionTrack != nil else { return false }
        stopAudition()
        return true
    }
}
