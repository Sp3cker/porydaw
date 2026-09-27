import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore

@MainActor
func checkCommandRouting(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::commandRouting"
    let setupGrid = makeCameraGrid(session: session)
    let snap = max(1, setupGrid.snapTicks)
    guard let pitch = session.camera.projection.pitch(
        atY: 160, keyHeight: session.camera.snapshot.keyHeight,
        scrollY: session.camera.snapshot.scrollY, dpr: setupGrid.devicePixelRatio),
        pitch <= 115,
        let added = try? session.document.addNotes([
            NewNote(track: setupGrid.trackIndex, tick: 24, pitch: UInt8(pitch),
                    duration: 7, velocity: 80),
            NewNote(track: setupGrid.trackIndex, tick: 96, pitch: UInt8(pitch),
                    duration: 13, velocity: 80),
            NewNote(track: setupGrid.trackIndex, tick: 9, pitch: UInt8(pitch),
                    duration: 6, velocity: 80)
        ]), added.count == 3 else {
        report.fail(id, "command-routing fixture could not seed notes")
        return
    }
    defer {
        session.document.deleteNotes(
            added.filter { session.document.note($0) != nil })
    }
    let grid = makeCameraGrid(session: session)
    let a = added[0], b = added[1], c = added[2]
    session.setSelectedNotes([a])
    grid.performCommand(command: EditCommand.nudgeRight.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.tick) == 24 + snap } == true,
        cppID: id, message: "nudge right advances the selected note one snap cell")
    grid.performCommand(command: EditCommand.nudgeLeft.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.tick) == 24 } == true,
        cppID: id, message: "nudge left returns the selected note one snap cell")
    session.setSelectedNotes([c])
    grid.performCommand(command: EditCommand.nudgeRight.rawValue)
    report.expect(
        session.document.note(c).map { Int($0.tick) == 12 } == true,
        cppID: id, message: "nudge right snaps an off-grid note forward to the lattice")
    grid.performCommand(command: EditCommand.nudgeLeft.rawValue)
    report.expect(
        session.document.note(c).map { Int($0.tick) == 6 } == true,
        cppID: id, message: "nudge left snaps an off-grid note back to the lattice")
    session.setSelectedNotes([a])
    grid.performCommand(command: EditCommand.transposeUpOctave.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.pitch) == pitch + 12 } == true,
        cppID: id, message: "octave transpose raises the selected note twelve keys")
    grid.performCommand(command: EditCommand.transposeDownOctave.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.pitch) == pitch } == true,
        cppID: id, message: "octave transpose down restores the selected note pitch")
    session.setSelectedNotes([a, b])
    grid.performCommand(command: EditCommand.shortenNote.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.duration) == 1 } == true
            && session.document.note(b).map { Int($0.duration) == 7 } == true,
        cppID: id, message: "shorten clamps the shorter note at one tick")
    grid.performCommand(command: EditCommand.shortenNote.rawValue)
    grid.performCommand(command: EditCommand.shortenNote.rawValue)
    report.expect(
        session.document.note(a).map { Int($0.duration) == 1 } == true
            && session.document.note(b).map { Int($0.duration) == 7 } == true,
        cppID: id, message: "repeated shorten at the floor is a no-op")
    _ = session.document.history.undoDocument()
    report.expect(
        session.document.note(a).map { Int($0.duration) == 7 } == true
            && session.document.note(b).map { Int($0.duration) == 13 } == true,
        cppID: id, message: "merged shorten presses undo in one step")
    let summaryBeforeCopy = grid.noteSummary
    let revisionBeforeCopy = session.document.revision
    grid.performCommand(command: EditCommand.copy.rawValue)
    report.expect(
        grid.noteSummary == summaryBeforeCopy
            && session.document.revision == revisionBeforeCopy,
        cppID: id, message: "copy leaves the document and published summary untouched")
    guard let aRect = firstRect(named: "gridNote_\(a.rawValue)", in: grid.scene.pianoNoteFills)
    else {
        report.fail(id, "command-routing fixture note is not projected")
        return
    }
    let dpr = grid.devicePixelRatio
    let pressX = aRect.x - floor(grid.cameraScrollX * dpr + 0.5) / dpr + aRect.width / 2
    let pressY = aRect.y - floor(grid.cameraScrollY * dpr + 0.5) / dpr + aRect.height / 2
    let revisionBeforePress = session.document.revision
    grid.beginPointer(x: pressX, y: pressY, modifiers: 0)
    let midGestureSummary = grid.noteSummary
    grid.performCommand(command: EditCommand.delete.rawValue)
    report.expect(
        grid.noteSummary == midGestureSummary && session.document.note(a) != nil,
        cppID: id, message: "delete is refused while a pointer gesture owns the grid")
    let pencilBefore = grid.pencilMode
    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    report.expect(
        grid.pencilMode == !pencilBefore && grid.noteSummary == midGestureSummary,
        cppID: id, message: "pencil mode still toggles mid-gesture without touching notes")
    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    report.expect(
        grid.pencilMode == pencilBefore && grid.noteSummary == midGestureSummary,
        cppID: id, message: "pencil mode toggles back mid-gesture without touching notes")
    grid.endPointer(x: pressX, y: pressY)
    report.expect(
        session.document.revision == revisionBeforePress && session.document.note(a) != nil,
        cppID: id, message: "releasing a zero-delta press commits nothing")
}
