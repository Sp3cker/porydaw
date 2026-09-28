import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore
import QtBridge

@MainActor
func checkSelectionBandSweep(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionBandSweep"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(session: session)
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
    guard let a = selectionRect(added[0], grid: roll),
          let b = selectionRect(added[1], grid: roll) else {
        report.fail(id, "selection-band notes were not projected")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    session.clearSelectedNotes()
    roll.beginRightPointer(x: 1, y: 0)
    roll.updateRightPointer(x: max(a.x + a.width, b.x + b.width) + 4,
                            y: max(a.y + a.height, b.y + b.height) + 4)
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "band preview does not commit note selection before release")
    roll.endRightPointer(x: max(a.x + a.width, b.x + b.width) + 4,
                         y: max(a.y + a.height, b.y + b.height) + 4)
    report.expect(session.selectedNotes.isSuperset(of: Set(added)), cppID: id,
                  message: "band release selects both swept note identities")
    report.expect(session.document.revision == revision
        && session.document.history.currentIdentity == history, cppID: id,
        message: "selection sweep changes no document or undo command")
    let bx0 = b.x + 1
    let by0 = b.y + 1
    let bx1 = b.x + b.width - 1
    let by1 = b.y + b.height - 1
    session.setSelectedNotes([added[0]])
    roll.refreshNotes()
    roll.beginRightPointer(x: bx0, y: by0)
    roll.updateRightPointer(x: bx1, y: by1)
    let held = RollContentProbe(roll.scene)
    report.expect(
        session.selectedNotes == Set([added[0]])
            && roll.bandSelectionActive
            && held.note(added[0])?.selected == false
            && held.note(added[1])?.selected == false, cppID: id,
        message: "plain band hides the old selection ring while its new selection is provisional")
    roll.endRightPointer(x: bx1, y: by1)
    let replaced = RollContentProbe(roll.scene)
    report.expect(
        session.selectedNotes == Set([added[1]])
            && replaced.note(added[0])?.selected == false
            && replaced.note(added[1])?.selected == true, cppID: id,
        message: "plain band replaces the old selection and publishes only the new note ring")
    session.setSelectedNotes([added[0]])
    roll.refreshNotes()
    roll.beginRightPointer(x: bx0, y: by0)
    roll.updateRightPointer(x: bx1, y: by1, modifiers: 0x0400_0000)
    let additiveHeld = RollContentProbe(roll.scene)
    report.expect(
        additiveHeld.note(added[0])?.selected == true, cppID: id,
        message: "Ctrl-held band preserves the old note ring during preview")
    roll.endRightPointer(x: bx1, y: by1, modifiers: 0x0400_0000)
    let additive = RollContentProbe(roll.scene)
    report.expect(
        session.selectedNotes == Set(added)
            && additive.note(added[0])?.selected == true
            && additive.note(added[1])?.selected == true, cppID: id,
        message: "Ctrl-release band adds the swept note without clearing the old selection")
    checkDeferredModifierSelection(report, session: session, grid: roll,
                                   a: a, b: b, ids: added)
}

@MainActor
func checkSelectionNonScaleMove(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionNonScaleMove"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(session: session)
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
    let addedCount = session.document.history.undoCount
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
    guard let plantedBytes = try? session.document.captureSave().bytes else {
        report.fail(id, "could not capture planted move-note MIDI bytes")
        return
    }
    let roll = PianoGrid(session: session)
    roll.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let rect = selectionRect(noteID, grid: roll) else {
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
    report.expect(session.document.history.undoCount == addedCount + 1, cppID: id,
                  message: "non-Scale move release pushes exactly one command")
    let movedIdentity = session.document.history.currentIdentity
    roll.performCommand(command: EditCommand.nudgeRight.rawValue)
    report.expect(session.document.note(noteID).map {
        $0.tick == Tick(tick + 3 * snap) && Int($0.pitch) == pitch
    } == true, cppID: id, message: "right nudge moves the same NoteID without reselecting")
    report.expect(session.selectedNoteOrder == [noteID], cppID: id,
                  message: "right nudge retains the moved note as the selection")
    report.expect(session.document.history.currentIdentity != movedIdentity, cppID: id,
                  message: "right nudge commits an undoable edit")
    report.expect(session.document.history.undoCount == addedCount + 2, cppID: id,
                  message: "Right nudge after the move pushes exactly one command")
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
    report.expect((try? session.document.captureSave().bytes) == plantedBytes, cppID: id,
                  message: "undoing the non-Scale move and Right nudge restores exact MIDI bytes")
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
