import Foundation
import PorydawCore
import PorydawDocument
import QtBridge
import PorydawAppCommands

@MainActor
extension PianoGrid {
    enum QtFact {
        static let shiftModifier = 0x0200_0000
        static let controlModifier = 0x0400_0000
    }

    enum GridCursorKind: Int {
        case arrow = 0
        case openHand = 1
        case leftEdge = 2
        case rightEdge = 3
        case closedHand = 4
        case velocity = 5
        case pencil = 6
    }

    /// True while a pointer gesture owns the roll. Swift-only: the shared
    /// playhead suspends follow while a gesture is live, and no gesture state is
    /// published or duplicated to QML.
    @QtIgnored
    public var interactionActive: Bool { gesture != nil || rightGesture != nil }

    @QtIgnored
    var velocityPreviewPresentation: RollVelocityPreview? {
        guard case .velocity(let state) = gesture, let pressed = state.preview else { return nil }
        return RollVelocityPreview(
            revision: session.document.revision, noteId: state.noteId,
            pressed: pressed, delta: state.delta, selection: session.selectedNotes)
    }

    @QtIgnored
    public func previewVelocity(_ id: NoteID) -> Optional<Int> {
        guard let preview = velocityPreviewPresentation else { return nil }
        if preview.noteId == id { return preview.pressed }
        guard preview.selection.contains(id), let note = session.document.note(id) else { return nil }
        return preview.adjusted(Int(note.velocity))
    }

    /// Publish a plain drawer snapshot only when its values actually change.
    @QtIgnored
    func publishVelocityPreview(_ preview: RollVelocityPreview?) {
        guard preview != publishedVelocityPresentation else { return }
        publishedVelocityPresentation = preview
        var values: [NoteID: UInt8] = [:]
        if let preview {
            values.reserveCapacity(preview.selection.count + 1)
            for id in preview.selection where id != preview.noteId {
                guard let note = session.document.note(id) else { continue }
                values[id] = UInt8(preview.adjusted(Int(note.velocity)))
            }
            values[preview.noteId] = UInt8(preview.pressed)
        }
        guard values != publishedVelocityPreview else { return }
        publishedVelocityPreview = values
        onVelocityPreviewChanged?(values)
    }

    @QtIgnored
    func detach() {
        inputCancelled(reason: GridCancelReason.hidden.rawValue)
        onAudition = nil
        onBandAudition = nil
    }

    @QtIgnored
    public func refreshFromSession() {
        let count = session.document.engineTracks.usedTrackCount
        if count == 0 {
            session.selectedTrack = nil
            if trackIndex != 0 { trackIndex = 0 }
        } else {
            let valid = min(max(0, session.selectedTrack ?? trackIndex), count - 1)
            session.selectedTrack = valid
            if trackIndex != valid { trackIndex = valid }
        }
        notes.selectedTrack = trackIndex
        let revisionText = String(session.document.revision)
        if appliedRevisionText != revisionText { appliedRevisionText = revisionText }
        let cursorTick = Int(session.editCursor)
        if editCursorTick != cursorTick { editCursorTick = cursorTick }
        updateTimeAxis()
        refreshGridMenuPresentation()
        refreshNotes()
    }

    /// Updates selected-track style without reconstructing retained document content.
    @QtIgnored
    public func refreshSelectionPresentation() {
        let primaryTrack: Int? = session.document.engineTracks.usedTrackCount == 0 ? nil : trackIndex
        guard session.selectedTrack == primaryTrack else {
            refreshFromSession()
            return
        }
        refreshCursorPresentation()
        refreshNotes()
    }

    @QtIgnored
    public func snapTickDown(_ tick: Double) -> Int {
        Int(viewport.grid.snapTickDown(tick, camera: viewport.camera))
    }

    @QtIgnored
    public func gridCell(at tick: Int) -> (start: Int, duration: Int) {
        let cell = viewport.grid.visibleGridCellContaining(
            Tick(max(0, tick)), camera: viewport.camera)
        return (Int(cell.start), Int(cell.end - cell.start))
    }

    /// Applies the session-owned edit cursor without rebuilding document content.
    @QtIgnored
    public func refreshCursorPresentation() {
        let cursorTick = Int(session.editCursor)
        if editCursorTick != cursorTick { editCursorTick = cursorTick }
    }

    @QtIgnored
    public func refreshCamera() {
        updateTimeAxis()
        refreshNotes()
    }

    @QtIgnored
    public func refreshTimeSelectionHighlight() {
        refreshNotes()
    }

    @QtIgnored
    public func handleEscape() -> Bool {
        if scrollbarGrabActive {
            cancelScrollbarGrab()
            return true
        }
        guard interactionActive else {
            session.clearSelectedNotes()
            refreshNotes()
            return true
        }
        cancelInput()
        return true
    }

    private func cancelScrollbarGrab() {
        guard scrollbarGrabActive else { return }
        setScrollbarGrabActive(active: false)
        scrollbarGrabCancelRequested()
    }

    @QtIgnored
    func cancelInput() {
        if cursorKind != GridCursorKind.arrow.rawValue {
            cursorKind = GridCursorKind.arrow.rawValue
        }
        if case .band = rightGesture {
            session.setSelectedNotes(selectionAtRightPress)
        }
        stopAudition()
        releaseBandAudition()
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        cancelScrollbarGrab()
        pointerModifiers = 0
        gesture = nil
        rightGesture = nil
        suppressedLeftRelease = false
        activeNoteId = 0
        clearKeyboardHover()
        refreshNotes()
    }

    @QtIgnored
    func stopAudition() {
        velocityAuditionTask?.cancel()
        velocityAuditionTask = nil
        guard let key = keyboardAuditionKey, let track = keyboardAuditionTrack else { return }
        onAudition?(track, key, 0)
        keyboardAuditionKey = nil
        keyboardAuditionTrack = nil
        keyboardTransposeAuditionActive = false
    }

    /// Intentional user-requested feature: velocity drags replay the held note at most once per 120 ms
    /// (per-step replays stutter; the engine fixes velocity at note-on). Release cancels a pending replay.
    @QtIgnored
    func scheduleVelocityAudition() {
        guard velocityAuditionTask == nil else { return }
        velocityAuditionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }  // Cancelled by stopAudition.
            guard let self, !Task.isCancelled else { return }
            self.velocityAuditionTask = nil
            guard case .velocity(let state) = self.gesture, let velocity = state.preview,
                velocity != self.velocityAuditionHeard,
                let key = self.keyboardAuditionKey, let track = self.keyboardAuditionTrack
            else { return }
            self.velocityAuditionHeard = velocity
            self.onAudition?(track, key, velocity)
        }
    }
}
