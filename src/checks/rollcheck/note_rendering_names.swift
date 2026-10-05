import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func checkNoteNameMode(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::noteNameMode"
    let oldCamera = session.camera
    let grid = PianoGrid(session: session)
    defer { session.mutateCamera { $0 = oldCamera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer { session.document.deleteNotes([noteID]) }
    guard let note = session.document.note(noteID) else {
        report.fail(id, "note name seed disappeared")
        return
    }
    let pitch = Int(note.pitch)
    let tick = Int(note.tick)
    // Row heights that surely fit the fixed face: the oracle hides the
    // reduced caption face below its padded height, so use a tall row for the
    // positive case and a sub-threshold one for the gate case.
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(pitch)) * 32 - 160))
    }
    grid.refreshCamera()
    // Widen the seeded cell well past name width, keeping it on screen.
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(
            max(
                camera.snapshot.minHScroll,
                camera.contentX(tick: Double(tick)) - 160))
    }
    grid.refreshCamera()
    grid.setNoteNameMode(enabled: true)
    func labeledNotes() -> [RollContentProbe.Note] {
        RollContentProbe(grid).notes.filter { record in
            record.pitch == pitch
                && noteNameLabeled(grid, session: session, id: NoteID(record.id))
        }
    }
    let content = RollContentProbe(grid)
    guard let record = content.note(noteID) else {
        report.fail(id, "wide note has no projected box")
        return
    }
    let wide = labeledNotes()
    report.expect(
        content.noteNameMode && content.selectedTrack == record.track
            && wide.count == 1 && wide.first?.id == noteID.rawValue, cppID: id,
        message: "a wide selected-track note gets exactly one name label")
    func slot(_ kind: RollPaletteSlot) -> UInt32? {
        content.slot(kind)
    }
    let fill = grid.palette.noteFill(track: record.track, velocity: record.velocity)
    let expectedInk = PaletteMath.aaContrastInk(
        fill: fill, light: PaletteMath.hex(grid.palette.keyboardNatural),
        dark: PaletteMath.hex(grid.palette.keyboardBlack),
        fallbackLight: PaletteMath.hex(grid.palette.noteLabelAaLight),
        fallbackDark: PaletteMath.hex(grid.palette.noteLabelAaDark))
    report.expect(
        record.fillArgb == RollContentProbe.argb(fill)
            && slot(.noteLabelLight) == RollContentProbe.argb(grid.palette.keyboardNatural)
            && slot(.noteLabelDark) == RollContentProbe.argb(grid.palette.keyboardBlack)
            && PaletteMath.contrastRatio(fill, expectedInk) >= 4.5,
        cppID: id,
        message: "the name label uses the contrasting keyboard ink")
    report.expect(
        grid.measurementFonts[.noteName]?.pixelSize == 11, cppID: id,
        message: "the name label uses the fixed reduced caption face")
    // Too narrow: the same note at minimum time zoom earns no label.
    _ = session.mutateCamera { _ = $0.setTimeZoom(4) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(camera.snapshot.minHScroll)
    }
    grid.refreshCamera()
    report.expect(
        labeledNotes().isEmpty, cppID: id,
        message: "a too-narrow note gets no name label")
    // Below the key-height threshold: wide again, but rows too short.
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(
            max(
                camera.snapshot.minHScroll,
                camera.contentX(tick: Double(tick)) - 160))
        _ = camera.setKeyHeight(8)
        _ = camera.setVScroll(max(0, (127.5 - Double(pitch)) * 8 - 160))
    }
    grid.refreshCamera()
    report.expect(
        labeledNotes().isEmpty, cppID: id,
        message: "no name labels below the key-height threshold")
    // Ghost exclusion from the real plotted list: an adjacent-row
    // other-track note decodes no name label while the mode is on.
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(pitch)) * 32 - 160))
        _ = camera.setTimeZoom(280)
    }
    grid.refreshCamera()
    let ghostIdentity = session.document.history.currentIdentity
    let neighborPitches = [
        pitch - 1, pitch + 1, pitch - 2, pitch + 2, pitch - 3, pitch + 3,
        pitch - 4, pitch + 4, pitch - 5, pitch + 5, pitch - 6, pitch + 6,
    ]
    func pitchFree(_ candidate: Int) -> Bool {
        candidate != pitch && (24...115).contains(candidate)
            && session.camera.projection.row(forPitch: candidate) != PitchProjection.hiddenRow
            && !session.document.notes(in: grid.trackIndex).contains { existing in
                Int(existing.pitch) == candidate
                    && Int(existing.tick) < Int(note.tick) + Int(note.duration)
                    && Int(existing.tick) + Int(existing.duration) > Int(note.tick)
            }
    }
    let ghostPitch = neighborPitches.first(where: pitchFree)
    if session.document.canAddTrack, let ghostPitch,
        let other = session.document.addTrack(voice: 0), other != grid.trackIndex,
        let ghostID = try? session.document.addNotes([
            NewNote(
                track: other, tick: note.tick, pitch: UInt8(ghostPitch),
                duration: note.duration, velocity: 100)
        ]).first
    {
        // Center between the seed and ghost rows so both faces decode.
        let snapshot = session.camera.snapshot
        let seedRow = session.camera.projection.row(forPitch: pitch)
        let ghostRow = session.camera.projection.row(forPitch: ghostPitch)
        if let seedTop = session.camera.projection.contentRowTop(
            seedRow, keyHeight: snapshot.keyHeight, dpr: grid.devicePixelRatio),
            let ghostTop = session.camera.projection.contentRowTop(
                ghostRow, keyHeight: snapshot.keyHeight, dpr: grid.devicePixelRatio)
        {
            session.mutateCamera { camera in
                _ = camera.setVScroll(
                    max(
                        0, min(seedTop, ghostTop) + snapshot.keyHeight / 2 - snapshot.rollHeight / 2))
            }
        }
        grid.refreshFromSession()
        let seedFace = decodedNoteBox(grid, noteID)
        let ghostFace = decodedNoteBox(grid, ghostID)
        report.expect(
            seedFace != nil && noteNameLabeled(grid, session: session, id: noteID),
            cppID: id, message: "the wide selected-track note keeps its label beside the ghost")
        report.expect(
            ghostFace.map { $0.w == seedFace?.w } == true
                && RollContentProbe(grid).note(ghostID)?.ghost == true
                && !noteNameLabeled(grid, session: session, id: ghostID),
            cppID: id, message: "ghost notes are never labeled")
    } else {
        report.fail(id, "ghost label fixture could not seed a same-span other-track note")
    }
    // Undo the fixture track and note: later suites provision their own
    // second track from a single-track song.
    while session.document.history.currentIdentity != ghostIdentity
        && session.document.history.canUndo
    {
        guard session.document.history.undoDocument() else { break }
    }
    grid.refreshFromSession()
    grid.setNoteNameMode(enabled: false)
    report.expect(
        !RollContentProbe(grid).noteNameMode, cppID: id,
        message: "disabling the mode publishes no name labels")
    let beforeState = session.document.state
    let beforeIdentity = session.document.history.currentIdentity
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setTimeZoom(20)
        _ = camera.setHScroll(camera.snapshot.minHScroll)
        _ = camera.setVScroll(max(0, (127.5 - Double(pitch)) * 32 - 160))
    }
    grid.refreshCamera()
    defer {
        while session.document.history.currentIdentity != beforeIdentity
            && session.document.history.canUndo
        {
            guard session.document.history.undoDocument() else { break }
        }
        report.expect(
            session.document.state == beforeState
                && session.document.history.currentIdentity == beforeIdentity,
            cppID: id, message: "note-name fixture undo restores the document")
    }
    guard
        let short = ghostSeed(
            report, id: id, session: session, grid: grid,
            track: grid.trackIndex, spanCells: 1,
            nearPitch: pitch, excluding: [pitch]),
        let wide = ghostSeed(
            report, id: id, session: session, grid: grid,
            track: grid.trackIndex, spanCells: 12,
            nearPitch: pitch, excluding: [pitch, short.pitch])
    else { return }
    let nextTick = short.tick + short.duration
    guard
        !session.document.notes(in: grid.trackIndex).contains(where: {
            Int($0.pitch) == short.pitch && Int($0.tick) < nextTick + short.duration
                && Int($0.tick) + Int($0.duration) > nextTick
        }),
        let adjacent = try? session.document.addNotes([
            NewNote(
                track: grid.trackIndex, tick: Tick(nextTick), pitch: UInt8(short.pitch),
                duration: Tick(short.duration), velocity: 1)
        ]).first
    else {
        report.fail(id, "adjacent short name-note fixture could not be seeded")
        return
    }
    grid.refreshFromSession()
    grid.setNoteNameMode(enabled: true)
    func hasLabel(_ noteID: NoteID) -> Bool {
        noteNameLabeled(grid, session: session, id: noteID)
    }
    report.expect(
        !hasLabel(short.id), cppID: id,
        message: "an abutting short same-pitch note carries no label (first)")
    report.expect(
        !hasLabel(adjacent), cppID: id,
        message: "an abutting short same-pitch note carries no label (second)")
    report.expect(
        hasLabel(wide.id), cppID: id,
        message: "a distant wide note keeps its label")
    let noteFonts = GridTypography.fonts(
        metrics: grid.metrics, typography: Typography(baseFontPx: 13))
    let measured = GridTypography(fonts: noteFonts, rowHeight: 32, pixel: grid.metrics.pixel)
    let fitHeight =
        measured.noteNameOccupiedHeight.rounded(.up)
        + 2 * grid.metrics.spaceHalf + grid.metrics.pixel
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(fitHeight)
        _ = camera.setVScroll(max(0, (127.5 - Double(wide.pitch)) * fitHeight - 160))
    }
    grid.refreshCamera()
    report.expect(
        hasLabel(wide.id), cppID: id,
        message: "a row at the exact padded fit still labels")
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(fitHeight - grid.metrics.pixel)
        _ = camera.setVScroll(
            max(
                0,
                (127.5 - Double(wide.pitch))
                    * (fitHeight - grid.metrics.pixel) - 160))
    }
    grid.refreshCamera()
    report.expect(
        !hasLabel(wide.id), cppID: id,
        message: "one pixel shorter the label hides instead of shrinking")
    grid.setNoteNameMode(enabled: false)
}
