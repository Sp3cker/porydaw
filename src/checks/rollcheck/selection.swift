import Foundation
import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func runSelectionChecks(_ report: CheckReport, session: DocumentSession) {
    checkSelectionBandSweep(report, session: session)
    checkSelectionNonScaleMove(report, session: session)
}

@MainActor
private func checkSelectionBandSweep(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionBandSweep"
    let initialSelection = session.selectedNoteOrder
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let pitch = [160.0, 200, 120, 240, 80].compactMap { y in
        session.camera.projection.pitch(
            atY: y, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
    }.first { candidate in
        !session.document.notes(in: grid.trackIndex).contains {
            Int($0.pitch) == candidate
                && (($0.tick < 48 && $0.tick + $0.duration > 24)
                    || ($0.tick < 120 && $0.tick + $0.duration > 96))
        }
    }
    guard let pitch,
        let added = try? session.document.addNotes([
            NewNote(track: grid.trackIndex, tick: 24, pitch: UInt8(pitch),
                    duration: 24, velocity: 100),
            NewNote(track: grid.trackIndex, tick: 96, pitch: UInt8(pitch),
                    duration: 24, velocity: 73)
        ]), added.count == 2 else {
        report.fail(id, "could not seed the two selection-band notes")
        return
    }
    defer {
        session.clearSelectedNotes()
        _ = session.document.history.undoDocument()
        session.setSelectedNotes(initialSelection)
    }
    let roll = PianoGrid(session: session)
    roll.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let a = selectionRect(added[0], in: roll.scene.pianoNoteFills),
          let b = selectionRect(added[1], in: roll.scene.pianoNoteFills) else {
        report.fail(id, "selection-band notes were not projected")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    session.clearSelectedNotes()
    roll.beginRightPointer(x: 1, y: 0)
    roll.updateRightPointer(x: max(a.x + a.width, b.x + b.width) + 4,
                            y: max(a.y + a.height, b.y + b.height) + 4)
    roll.endRightPointer(x: max(a.x + a.width, b.x + b.width) + 4,
                         y: max(a.y + a.height, b.y + b.height) + 4)
    report.expect(session.selectedNotes.isSuperset(of: Set(added)), cppID: id,
                  message: "band release selects both swept note identities")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history, cppID: id,
        message: "selection sweep changes no document or undo command")
    checkDeferredModifierSelection(report, session: session, grid: roll,
                                   a: a, b: b, ids: added)
}

@MainActor
private func checkSelectionNonScaleMove(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionNonScaleMove"
    let initialSelection = session.selectedNoteOrder
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let snap = max(1, grid.snapTicks)
    let tick = 240
    let duration = 4 * snap
    let pitch = [160.0, 200, 120, 240, 80].compactMap { y in
        session.camera.projection.pitch(
            atY: y, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
    }.first { candidate in
        !session.document.notes(in: grid.trackIndex).contains {
            Int($0.pitch) == candidate
                && Int($0.tick) < tick + duration + 3 * snap
                && Int($0.tick + $0.duration) > tick
        }
    }
    guard let pitch,
        let added = try? session.document.addNotes([
            NewNote(track: grid.trackIndex, tick: Tick(tick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: 93)
        ]), let noteID = added.first else {
        report.fail(id, "could not seed the wide move note")
        return
    }
    let addedIdentity = session.document.history.currentIdentity
    defer {
        session.clearSelectedNotes()
        if session.document.history.currentIdentity != addedIdentity {
            _ = session.document.history.undoDocument()
        }
        if session.document.history.currentIdentity != addedIdentity {
            _ = session.document.history.undoDocument()
        }
        _ = session.document.history.undoDocument()
        session.setSelectedNotes(initialSelection)
    }
    let roll = PianoGrid(session: session)
    roll.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let rect = selectionRect(noteID, in: roll.scene.pianoNoteFills) else {
        report.fail(id, "wide move note was not projected")
        return
    }
    let x = rect.x + rect.width / 2
    let y = rect.y + rect.height / 2
    let targetX = x + Double(2 * snap) * session.camera.snapshot.pixelsPerTick
    roll.beginPointer(x: x, y: y, modifiers: 0)
    report.expect(session.selectedNoteOrder == [noteID], cppID: id,
                  message: "body press selects exactly the grabbed note")
    let previewHistory = session.document.history.currentIdentity
    roll.updatePointer(x: targetX, y: y)
    report.expect(session.document.history.currentIdentity == previewHistory
        && session.document.note(noteID)?.tick == Tick(tick), cppID: id,
        message: "move preview does not commit before release")
    roll.endPointer(x: targetX, y: y)
    report.expect(session.document.note(noteID).map {
        $0.tick == Tick(tick + 2 * snap) && Int($0.pitch) == pitch
            && $0.duration == Tick(duration)
    } == true, cppID: id, message: "move release keeps the same NoteID at the target")
    report.expect(!session.document.notes(in: roll.trackIndex).contains {
        $0.tick == Tick(tick) && Int($0.pitch) == pitch
    }, cppID: id, message: "move release vacates the original cell")
    report.expect(session.selectedNoteOrder == [noteID], cppID: id,
                  message: "move release retains the moved note as the selection")
    report.expect(session.document.history.currentIdentity != previewHistory, cppID: id,
                  message: "move release commits one undoable edit")
    let movedIdentity = session.document.history.currentIdentity
    roll.performCommand(command: EditCommand.nudgeRight.rawValue)
    report.expect(session.document.note(noteID).map {
        $0.tick == Tick(tick + 3 * snap) && Int($0.pitch) == pitch
    } == true, cppID: id, message: "right nudge moves the same NoteID without reselecting")
    report.expect(session.selectedNoteOrder == [noteID], cppID: id,
                  message: "right nudge retains the moved note as the selection")
    report.expect(session.document.history.currentIdentity != movedIdentity, cppID: id,
                  message: "right nudge commits an undoable edit")
    if session.document.history.currentIdentity != movedIdentity {
        _ = session.document.history.undoDocument()
    }
    if session.document.history.currentIdentity != addedIdentity {
        _ = session.document.history.undoDocument()
        report.expect(session.document.history.currentIdentity == addedIdentity
            && session.document.note(noteID).map {
                $0.tick == Tick(tick) && Int($0.pitch) == pitch
                    && $0.duration == Tick(duration)
            } == true, cppID: id,
            message: "undo restores the original note identity and position")
    }
}

@MainActor
private func checkDeferredModifierSelection(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid,
    a: SceneRect, b: SceneRect, ids: [NoteID]
) {
    let id = "swiftcore/PianoRoll::selectionModifierVelocity"
    let ax = a.x + a.width / 2
    let ay = a.y + a.height / 2
    let bx = b.x + b.width / 2
    let by = b.y + b.height / 2
    session.setSelectedNotes([ids[0]])
    grid.beginPointer(x: bx, y: by, modifiers: 0x0200_0000)
    report.expect(session.selectedNoteOrder == ids, cppID: id,
                  message: "Shift press extends selection without replacing its first note")
    grid.endPointer(x: bx, y: by)
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    grid.beginPointer(x: ax, y: ay, modifiers: 0x0400_0000)
    report.expect(session.selectedNoteOrder == ids, cppID: id,
                  message: "Ctrl press defers removal of an already-selected note")
    grid.endPointer(x: ax, y: ay)
    report.expect(session.selectedNoteOrder == [ids[1]], cppID: id,
                  message: "Ctrl release toggles the pressed note without changing the other")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history, cppID: id,
        message: "modifier selection clicks push no document edit")
}

@MainActor
private func selectionRect(_ id: NoteID, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == "gridNote_\(id.rawValue)" {
        return model[index]
    }
    return nil
}
