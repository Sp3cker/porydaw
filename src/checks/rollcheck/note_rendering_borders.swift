import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func checkNoteBorders(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectedNoteFrameRaster"
    let tinyID = "swiftcore/PianoRoll::tinyNoteBorderRaster"
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let document = session.document
    let initialIdentity = document.history.currentIdentity
    guard let originalBytes = try? document.state.file.encoded() else {
        report.fail(id, "note rendering fixture cannot encode the original song")
        return
    }
    let grid = PianoGrid(session: session)
    defer {
        session.clearSelectedNotes()
        session.setSelectedNotes(priorSelection)
        session.mutateCamera { $0 = oldCamera }
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer {
        while document.history.currentIdentity != initialIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        report.expect((try? document.state.file.encoded()) == originalBytes,
                      cppID: id, message: "A015 undoing the selected frame fixture restores original song bytes")
    }
    guard let note = session.document.note(noteID) else {
        report.fail(id, "note rendering seed disappeared")
        return
    }
    session.clearSelectedNotes()
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(16.375)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 16.375 - 160))
    }
    grid.refreshCamera()
    guard let box = noteBox(grid, session: session, note: note),
          let fill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                   in: grid.scene.pianoNoteFills) else {
        report.fail(id, "fractional-height note has no published scene box")
        return
    }
    report.expect(renderingNear(fill.x, box.x) && renderingNear(fill.y, box.y)
                      && renderingNear(fill.width, box.w) && renderingNear(fill.height, box.h),
                  cppID: id, message: "fractional 16.375-key-height note keeps projected box")
    session.setSelectedNotes([noteID])
    grid.refreshCamera()
    let borders = grid.scene.pianoNoteBordersAndSelection
    let ring = 3.0 / grid.devicePixelRatio
    let border = 2.0 / grid.devicePixelRatio
    report.expect(hasFrame(borders, box: box, inset: 0, thickness: ring,
                           color: grid.palette.selectionRing),
                  cppID: id, message: "A007/A012 3px contiguous selection ring stops at inset")
    report.expect(hasFrame(borders, box: box, inset: ring, thickness: border,
                           color: grid.palette.noteBorder),
                  cppID: id, message: "A008-A011 2px black frame lies inside every selected edge")
    session.clearSelectedNotes()
    grid.refreshCamera()
    report.expect(hasFrame(borders, box: box, inset: 0, thickness: border,
                           color: grid.palette.noteBorder),
                  cppID: id, message: "A013/A014 unselected bottom border bounds the face")

    let seededIdentity = document.history.currentIdentity
    guard let seededBytes = try? document.state.file.encoded(),
          let tinyIDNote = try? document.addNotes([
              NewNote(track: grid.trackIndex, tick: note.tick + note.duration,
                      pitch: note.pitch, duration: note.duration, velocity: 100)
          ]).first,
          let tinyNote = document.note(tinyIDNote) else {
        report.fail(tinyID, "tiny note fixture cannot seed the adjacent face")
        return
    }
    grid.refreshFromSession()

    grid.configureViewport(width: 640, height: 320, fontPx: 5, dpr: 1)
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(5.0)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 5.0 - 160))
    }
    grid.refreshCamera()
    guard let tiny = noteBox(grid, session: session, note: tinyNote),
          let tinyFill = firstNoteRect(named: "gridNote_\(tinyIDNote.rawValue)",
                                       in: grid.scene.pianoNoteFills) else {
        report.fail(tinyID, "5.0-key-height note has no published scene box")
        return
    }
    let fitted = max(0, min(1, (Int(min(tiny.w, tiny.h).rounded()) - 1) / 2))
    report.expect(fitted == 1, cppID: tinyID,
                  message: "A002 5.0-key-height note has room for a 1px border")
    report.expect(hasFrame(borders, box: tiny, inset: 0, thickness: Double(fitted),
                           color: grid.palette.noteBorder),
                  cppID: tinyID, message: "A003 tiny note retains its 1px black border")
    report.expect(tinyFill.fillColor == grid.palette.noteFill(track: grid.trackIndex, velocity: 100)
                      && tiny.w > 2 * Double(fitted) && tiny.h > 2 * Double(fitted),
                  cppID: tinyID, message: "A004 tiny note face survives inside its border")
    while document.history.currentIdentity != seededIdentity && document.history.canUndo {
        guard document.history.undoDocument() else { break }
    }
    report.expect((try? document.state.file.encoded()) == seededBytes,
                  cppID: tinyID, message: "A005 undoing the tiny frame fixture restores seeded song bytes")
}

@MainActor
func checkIdentityNoteColors(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::velocityColorRaster"
    let oldCamera = session.camera
    let grid = PianoGrid(session: session)
    defer { session.mutateCamera { $0 = oldCamera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer { session.document.deleteNotes([noteID]) }
    let track = grid.trackIndex
    var colors: [Int: String] = [:]
    for velocity in [1, 64, 127] {
        guard session.document.setVelocities([NoteVelocity(noteID: noteID, velocity: velocity)],
                                              expectedRevision: session.document.revision) != nil
        else {
            report.fail(id, "could not set fixture velocity \(velocity)")
            return
        }
        grid.refreshFromSession()
        guard let fill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                       in: grid.scene.pianoNoteFills) else {
            report.fail(id, "velocity \(velocity) has no published note fill")
            return
        }
        colors[velocity] = fill.fillColor
    }
    let palette = grid.palette
    // MIDI note-on velocity zero is a note-off, so the document clamps edits
    // to 1...127. Exercise the neutral endpoint through the color API itself.
    let zero = palette.noteFill(track: track, velocity: 0)
    let minimum = colors[1] ?? ""
    let maximum = colors[127] ?? ""
    let midpoint = colors[64] ?? ""
    report.expect(zero == palette.noteVelocityZero, cppID: id,
                  message: "A020 velocity zero uses the neutral palette fill")
    report.expect(publishedOpaque(zero), cppID: id,
                  message: "A021 velocity zero palette fill is opaque")
    report.expect(minimum == palette.noteFill(track: track, velocity: 1)
                      && publishedOpaque(minimum), cppID: id,
                  message: "the minimum MIDI note velocity publishes its opaque palette fill")
    report.expect(maximum == palette.noteFill(track: track, velocity: 127),
                  cppID: id, message: "A022 published full velocity uses the track identity fill")
    report.expect(publishedOpaque(maximum), cppID: id,
                  message: "A023 published full velocity is opaque")
    report.expect(publishedOpaque(midpoint), cppID: id,
                  message: "A024 published middle velocity is opaque")
    report.expect(midpoint != zero && midpoint != minimum && midpoint != maximum, cppID: id,
                  message: "A025 published middle velocity differs from both endpoints")
    let immaterial = GridPalette()
    ShellAppearance.apply(to: immaterial, mode: "immaterial", contrast: 50)
    report.expectEqual(expected: "#7DC36B", actual: immaterial.noteFill(track: 6, velocity: 100),
                       cppID: id, what: "immaterial track-six velocity-100 native note color")
}
