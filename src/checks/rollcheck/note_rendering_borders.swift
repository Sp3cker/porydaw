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
        report.expect(
            (try? document.state.file.encoded()) == originalBytes,
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
    guard let box = decodedNoteBox(grid, noteID),
        let record = RollContentProbe(grid).note(noteID)
    else {
        report.fail(id, "fractional-height note has no published scene box")
        return
    }
    report.expect(
        record.tick == Int(note.tick) && record.duration == Int(note.duration)
            && record.pitch == Int(note.pitch) && box.w > 0 && box.h > 0,
        cppID: id,
        message: "the fractional 16.375-key-height note publishes its document span and a non-empty projected box")
    session.setSelectedNotes([noteID])
    grid.refreshCamera()
    let selectedProbe = RollContentProbe(grid)
    report.expect(
        session.selectedNotes.contains(noteID)
            && grid.notes.first(where: { $0.noteId == noteID })?.ghost == false,
        cppID: id,
        message:
            "A007-A012 the selected real note publishes the selected, non-ghost flags that drive its ring and inner frame"
    )
    report.expect(
        !selectedProbe.ringRects(noteID).isEmpty, cppID: id,
        message: "A007-A012 the selected real note plots its selection ring rects")
    session.clearSelectedNotes()
    grid.refreshCamera()
    let plainProbe = RollContentProbe(grid)
    report.expect(
        !session.selectedNotes.contains(noteID)
            && grid.notes.first(where: { $0.noteId == noteID })?.ghost == false,
        cppID: id, message: "A013/A014 the deselected note publishes no selection, time-cover, or ghost flag")
    report.expect(
        plainProbe.ringRects(noteID).isEmpty, cppID: id,
        message: "A013/A014 the deselected note plots no selection ring")

    let seededIdentity = document.history.currentIdentity
    guard let seededBytes = try? document.state.file.encoded(),
        let tinyIDNote = try? document.addNotes([
            NewNote(
                track: grid.trackIndex, tick: note.tick + note.duration,
                pitch: note.pitch, duration: note.duration, velocity: 100)
        ]).first,
        document.note(tinyIDNote) != nil
    else {
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
    guard let tiny = decodedNoteBox(grid, tinyIDNote),
        RollContentProbe(grid).note(tinyIDNote) != nil
    else {
        report.fail(tinyID, "5.0-key-height note has no published scene box")
        return
    }
    let tinyProbe = RollContentProbe(grid)
    let tinyBorders = tinyProbe.borderRects(tinyIDNote)
    report.expect(
        !tinyBorders.isEmpty, cppID: tinyID,
        message: "A002 5.0-key-height note plots its frame border rects")
    report.expect(
        grid.notes.first(where: { $0.noteId == tinyIDNote })?.ghost == false
            && !session.selectedNotes.contains(tinyIDNote),
        cppID: tinyID,
        message: "A003 the tiny note publishes as a plain real note with no ghost, selection, or time-cover flag")
    report.expect(
        probeFill(grid, tinyIDNote)
            == RollContentProbe.argb(
                grid.palette.noteFill(track: grid.trackIndex, velocity: 100))
            && tinyBorders.allSatisfy({
                $0.x >= tiny.x && $0.y >= tiny.y
                    && $0.x + $0.w <= tiny.x + tiny.w && $0.y + $0.h <= tiny.y + tiny.h
            }),
        cppID: tinyID,
        message: "A004 the tiny note publishes its track fill inside its plotted border")
    while document.history.currentIdentity != seededIdentity && document.history.canUndo {
        guard document.history.undoDocument() else { break }
    }
    report.expect(
        (try? document.state.file.encoded()) == seededBytes,
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
    var colors: [Int: UInt32] = [:]
    for velocity in [1, 64, 127] {
        guard
            session.document.setVelocities(
                [NoteVelocity(noteID: noteID, velocity: velocity)],
                expectedRevision: session.document.revision) != nil
        else {
            report.fail(id, "could not set fixture velocity \(velocity)")
            return
        }
        grid.refreshFromSession()
        guard let fill = probeFill(grid, noteID) else {
            report.fail(id, "velocity \(velocity) has no published note fill")
            return
        }
        colors[velocity] = fill
    }
    let palette = grid.palette
    // MIDI note-on velocity zero is a note-off, so the document clamps edits
    // to 1...127. Exercise the neutral endpoint through the color API itself.
    let zero = palette.noteFill(track: track, velocity: 0)
    let minimum = colors[1] ?? 0
    let maximum = colors[127] ?? 0
    let midpoint = colors[64] ?? 0
    report.expect(
        zero == palette.noteVelocityZero, cppID: id,
        message: "A020 velocity zero uses the neutral palette fill")
    report.expect(
        publishedOpaque(zero), cppID: id,
        message: "A021 velocity zero palette fill is opaque")
    report.expect(
        minimum == RollContentProbe.argb(palette.noteFill(track: track, velocity: 1))
            && argbOpaque(minimum), cppID: id,
        message: "the minimum MIDI note velocity publishes its opaque palette fill")
    report.expect(
        maximum == RollContentProbe.argb(palette.noteFill(track: track, velocity: 127)),
        cppID: id, message: "A022 published full velocity uses the track identity fill")
    report.expect(
        argbOpaque(maximum), cppID: id,
        message: "A023 published full velocity is opaque")
    report.expect(
        argbOpaque(midpoint), cppID: id,
        message: "A024 published middle velocity is opaque")
    report.expect(
        midpoint != RollContentProbe.argb(zero) && midpoint != minimum
            && midpoint != maximum, cppID: id,
        message: "A025 published middle velocity differs from both endpoints")
    let immaterial = GridPalette()
    ShellAppearance.apply(to: immaterial, mode: "immaterial", contrast: 50)
    report.expectEqual(
        expected: "#7DC36B", actual: immaterial.noteFill(track: 6, velocity: 100),
        cppID: id, what: "immaterial track-six velocity-100 native note color")
}
