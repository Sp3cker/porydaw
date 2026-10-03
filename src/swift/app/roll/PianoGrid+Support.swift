import Foundation
import PorydawCore
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
}

    /// True while a pointer gesture owns the roll. Swift-only: the shared
    /// playhead suspends follow while a gesture is live, and no gesture state is
    /// published or duplicated to QML.
    @QtIgnored
    public var interactionActive: Bool { gesture != nil || rightGesture != nil }

    @QtIgnored
    public func previewVelocity(_ id: NoteID) -> Optional<Int> {
        guard case .velocity(let state) = gesture, let preview = state.preview else { return nil }
        if state.noteId == id { return preview }
        guard session.selectedNotes.contains(id), let note = session.document.note(id) else { return nil }
        return min(127, max(1, Int(note.velocity) + state.delta))
    }

    @QtIgnored
    func detach() {
        inputCancelled(reason: GridCancelReason.hidden.rawValue)
        onAudition = nil
    }

    @QtIgnored
    public func refreshFromSession() {
        let count = session.document.engineTracks.usedTrackCount
        if count == 0 {
            session.selectedTrack = nil
            if trackIndex != 0 { trackIndex = 0 }
            notes = []
        } else {
            let valid = min(max(0, session.selectedTrack ?? trackIndex), count - 1)
            session.selectedTrack = valid
            if trackIndex != valid { trackIndex = valid }
            let snap = session.grid.snapTicksAt(session.editCursor, camera: session.camera)
            var projected: [GridNote] = []
            var noteCount = 0
            for track in 0..<count { noteCount += session.document.notes(in: track).count }
            projected.reserveCapacity(noteCount)
            func emit(track: Int) {
                for note in session.document.notes(in: track) {
                    projected.append(GridNote(noteId: note.id, tick: Int(note.tick),
                        duration: Int(note.isUnterminated ? max(1, snap) : max(1, note.duration)),
                        pitch: Int(note.pitch), track: note.track,
                        velocity: Int(note.velocity), ghost: track != valid))
                }
            }
            emit(track: valid)
            for track in 0..<count where track != valid { emit(track: track) }
            notes = projected
        }
        let revisionText = String(session.document.revision)
        if appliedRevisionText != revisionText { appliedRevisionText = revisionText }
        let cursorTick = Int(session.editCursor)
        if editCursorTick != cursorTick { editCursorTick = cursorTick }
        updateTimeAxis()
        refreshGridMenuPresentation()
        staticSceneDirty = true
        refreshNotes()
    }

    @QtIgnored
    public func snapTickDown(_ tick: Double) -> Int {
        Int(session.grid.snapTickDown(tick, camera: session.camera))
    }

    @QtIgnored
    public func gridCell(at tick: Int) -> (start: Int, duration: Int) {
        let cell = session.grid.visibleGridCellContaining(
            Tick(max(0, tick)), camera: session.camera)
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
        guard let key = keyboardAuditionKey, let track = keyboardAuditionTrack else { return }
        onAudition?(track, key, 0)
        keyboardAuditionKey = nil
        keyboardAuditionTrack = nil
        keyboardTransposeAuditionActive = false
    }
}
