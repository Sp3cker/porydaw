import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore

@MainActor
func runKeyboardParityChecks(_ report: CheckReport, session: DocumentSession) {
    checkBandKeyCancelReasons(report, session: session)
    checkBandKeyAutoRepeat(report, session: session)
    checkBandKeyDeleteEligibility(report, session: session)
}

@MainActor
private func withBandKeyFixture(
    _ report: CheckReport, session: DocumentSession, id: String,
    _ body: (PianoGrid, NoteID) -> Void
) {
    let document = session.document
    let before = document.state
    let identity = document.history.currentIdentity
    let originalSelection = session.selectedNoteOrder
    let originalTrack = session.selectedTrack
    let originalCamera = session.camera.snapshot
    defer {
        while document.history.currentIdentity != identity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        session.selectedTrack = originalTrack
        session.setSelectedNotes(originalSelection)
        _ = session.mutateCamera {
            $0.updateViewport(width: originalCamera.viewportWidth,
                              rollHeight: originalCamera.rollHeight)
            $0.restore(pixelsPerBeat: originalCamera.pixelsPerBeat,
                       keyHeight: originalCamera.keyHeight, scrollX: originalCamera.scrollX,
                       scrollY: originalCamera.scrollY)
        }
        report.expect(document.state == before && document.history.currentIdentity == identity
            && session.camera.snapshot == originalCamera,
            cppID: id, message: "band key fixture restores document, history, and camera")
    }
    guard let track = (0..<document.engineTracks.usedTrackCount).first(where: {
        !document.notes(in: $0).isEmpty
    }), let noteID = document.notes(in: track).first?.id else {
        report.fail(id, "no existing note available for the band key fixture")
        return
    }
    session.selectedTrack = track
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    body(grid, noteID)
}

@MainActor
private func checkBandKeyDeleteEligibility(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::bandKeyDeleteEligibility"
    withBandKeyFixture(report, session: session, id: id) { grid, noteID in
        let document = session.document
        session.clearSelectedNotes()
        let emptyState = document.state
        let emptyRevision = document.revision
        let emptyIdentity = document.history.currentIdentity
        let emptySurface = EditSurfaceState(
            pointerGestureActive: grid.interactionActive, timeSelectionActive: false,
            noteSelectionEmpty: session.selectedNotes.isEmpty, origin: .timeline,
            autoRepeat: false, commandAvailable: grid.commandAvailable(command: EditCommand.delete.rawValue))
        report.expect(!emptySurface.commandAvailable
            && EditKeyArbiter.decide(command: .delete, surface: emptySurface) == .decline,
            cppID: id, message: "empty note and time selection declines Delete")
        grid.performCommand(command: EditCommand.delete.rawValue)
        report.expect(document.state == emptyState && document.revision == emptyRevision
            && document.history.currentIdentity == emptyIdentity,
            cppID: id, message: "empty Delete cannot mutate the document")
        session.setSelectedNotes([noteID])
        let selectedSurface = EditSurfaceState(
            pointerGestureActive: grid.interactionActive, timeSelectionActive: false,
            noteSelectionEmpty: session.selectedNotes.isEmpty, origin: .timeline,
            autoRepeat: false, commandAvailable: grid.commandAvailable(command: EditCommand.delete.rawValue))
        report.expect(selectedSurface.commandAvailable
            && EditKeyArbiter.decide(command: .delete, surface: selectedSurface) == .execute,
            cppID: id, message: "selected note executes Delete")
        let selectedRevision = document.revision
        grid.performCommand(command: EditCommand.delete.rawValue)
        report.expect(document.note(noteID) == nil && document.revision == selectedRevision + 1,
                      cppID: id, message: "selected Delete removes the note in one revision")
    }
}

@MainActor
private func checkBandKeyAutoRepeat(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::bandKeyAutoRepeat"
    withBandKeyFixture(report, session: session, id: id) { grid, _ in
        let initialPencilMode = grid.pencilMode
        let eligible = grid.commandAvailable(command: EditCommand.pencilMode.rawValue)
        let repeatSurface = EditSurfaceState(
            pointerGestureActive: grid.interactionActive, timeSelectionActive: false,
            noteSelectionEmpty: session.selectedNotes.isEmpty, origin: .timeline,
            autoRepeat: true, commandAvailable: eligible)
        report.expect(eligible
            && EditKeyArbiter.decide(command: .pencilMode, surface: repeatSurface) == .consume,
            cppID: id, message: "repeated eligible pencil key is consumed")
        var firstSurface = repeatSurface
        firstSurface.autoRepeat = false
        report.expect(grid.pencilMode == initialPencilMode
            && EditKeyArbiter.decide(command: .pencilMode, surface: firstSurface) == .execute,
            cppID: id, message: "first pencil key executes without a repeat toggle")
        grid.performCommand(command: EditCommand.pencilMode.rawValue)
        report.expect(grid.pencilMode != initialPencilMode, cppID: id,
                      message: "the executing first press toggles pencil mode")
    }
}

@MainActor
private func checkBandKeyCancelReasons(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::bandKeyCancelReasons"
    withBandKeyFixture(report, session: session, id: id) { grid, _ in
        guard let y = (24...115).lazy.compactMap({ pitch -> Double? in
            guard let box = grid.projectedNoteBox(tick: 96, end: 108, pitch: pitch),
                  box.y >= 0, box.y + box.h <= 320 else { return nil }
            return box.y + box.h / 2
        }).first else {
            report.fail(id, "no visible grid row available for cancellation")
            return
        }
        let originalState = session.document.state
        let originalRevision = session.document.revision
        for reason in [GridCancelReason.focusLost, .pointerUngrabbed, .hidden,
                       .windowDeactivated] {
            grid.beginPointer(x: 88, y: y, modifiers: 0)
            report.expect(grid.interactionActive, cppID: id,
                          message: "pointer gesture opens before \(reason) cancellation")
            grid.inputCancelled(reason: reason.rawValue)
            report.expect(!grid.interactionActive && grid.lastCancelReason == reason.rawValue
                && session.document.state == originalState
                && session.document.revision == originalRevision,
                cppID: id, message: "\(reason) resets gesture and records its reason")
        }
    }
}
