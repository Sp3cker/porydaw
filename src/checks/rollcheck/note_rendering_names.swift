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
        _ = camera.setHScroll(max(camera.snapshot.minHScroll,
                                  camera.contentX(tick: Double(tick)) - 160))
    }
    grid.refreshCamera()
    grid.setNoteNameMode(enabled: true)
    func matchingRecords() -> [SceneText] {
        grid.scene.pianoNoteTextModel.asArray.filter { $0.labelText == GridScene.keyName(pitch) }
    }
    guard let box = noteBox(grid, session: session, note: note) else {
        report.fail(id, "wide note has no projected box")
        return
    }
    let half = grid.metrics.spaceHalf
    let expectedRect = (x: box.x + half, y: box.y + half,
                        w: box.w - 2 * half, h: box.h - 2 * half)
    func rectMatches(_ record: SceneText) -> Bool {
        guard let x = record.labelRect["x"] as? Double,
              let y = record.labelRect["y"] as? Double,
              let width = record.labelRect["width"] as? Double,
              let height = record.labelRect["height"] as? Double
        else { return false }
        return renderingNear(x, expectedRect.x) && renderingNear(y, expectedRect.y)
            && renderingNear(width, expectedRect.w) && renderingNear(height, expectedRect.h)
    }
    let wide = matchingRecords()
    report.expect(wide.count == 1, cppID: id,
                  message: "a wide selected-track note gets exactly one name label")
    if let record = wide.first(where: rectMatches) {
        let fill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                 in: grid.scene.pianoNoteFills)?.fillColor ?? ""
        let light = grid.palette.keyboardNatural
        let dark = grid.palette.keyboardBlack
        let expectedInk = PaletteMath.aaContrastInk(
            fill: fill, light: light, dark: dark,
            fallbackLight: grid.palette.noteLabelAaLight,
            fallbackDark: grid.palette.noteLabelAaDark)
        report.expect(record.labelColor == expectedInk
                          && PaletteMath.contrastRatio(fill, record.labelColor) >= 4.5,
                      cppID: id,
                      message: "the name label uses the contrasting keyboard ink")
        report.expect(record.labelHorizontalAlignment == 0x1
                          && record.labelVerticalAlignment == 0x80, cppID: id,
                      message: "the name label is left-aligned and vertically centred")
        report.expect((record.labelFont["pixelSize"] as? Int) == 11, cppID: id,
                      message: "the name label uses the fixed reduced caption face")
    } else {
        report.fail(id, "the wide note label rect misses the half-space inset box")
    }
    // Too narrow: the same note at minimum time zoom earns no label.
    _ = session.mutateCamera { _ = $0.setTimeZoom(4) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(camera.snapshot.minHScroll)
    }
    grid.refreshCamera()
    report.expect(matchingRecords().isEmpty, cppID: id,
                  message: "a too-narrow note gets no name label")
    // Below the key-height threshold: wide again, but rows too short.
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(max(camera.snapshot.minHScroll,
                                  camera.contentX(tick: Double(tick)) - 160))
        _ = camera.setKeyHeight(8)
        _ = camera.setVScroll(max(0, (127.5 - Double(pitch)) * 8 - 160))
    }
    grid.refreshCamera()
    report.expect(matchingRecords().isEmpty, cppID: id,
                  message: "no name labels below the key-height threshold")
    // Ghost exclusion through the exact layout entry the scene calls:
    // PianoGrid only presents the selected track, so exercise the pure
    // function with a synthetic ghost face.
    let faces = [
        NoteNameFace(pitch: pitch, box: (0, 0, 200, 24), velocity: 100,
                     fillColor: grid.palette.noteVelocityZero, ghost: true),
        NoteNameFace(pitch: pitch, box: (0, 0, 200, 24), velocity: 100,
                     fillColor: grid.palette.noteVelocityZero, ghost: false),
    ]
    let ghostLabels = NoteNameLabels.labels(
        faces: faces, keyHeight: 32, occupiedHeight: 0, pixel: 1,
        spaceHalf: 2, spaceTwo: 7, advance: { _ in 10 },
        font: [:], palette: grid.palette)
    report.expect(ghostLabels.count == 1 && ghostLabels[0].labelText == GridScene.keyName(pitch),
                  cppID: id, message: "ghost notes are never labeled")
    let hardFill = PaletteMath.velocityNoteColor(
        velocity: 121, zeroColor: grid.palette.noteVelocityZero)
    report.expect(PaletteMath.contrastRatio(
        hardFill, NoteNameLabels.textColor(fillColor: hardFill, palette: grid.palette)) >= 4.5,
        cppID: id, message: "the low-contrast velocity hue gets AA-clearing label ink")
    // Mode off empties the model unconditionally.
    grid.setNoteNameMode(enabled: false)
    report.expect(grid.scene.pianoNoteTextModel.count == 0, cppID: id,
                  message: "disabling the mode empties the name model")
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
                  && session.document.history.canUndo {
            guard session.document.history.undoDocument() else { break }
        }
        report.expect(session.document.state == beforeState
                          && session.document.history.currentIdentity == beforeIdentity,
                      cppID: id, message: "note-name fixture undo restores the document")
    }
    guard let short = ghostSeed(report, id: id, session: session, grid: grid,
                                track: grid.trackIndex, spanCells: 1,
                                nearPitch: pitch, excluding: [pitch]),
          let wide = ghostSeed(report, id: id, session: session, grid: grid,
                               track: grid.trackIndex, spanCells: 12,
                               nearPitch: pitch, excluding: [pitch, short.pitch]) else { return }
    let nextTick = short.tick + short.duration
    guard !session.document.notes(in: grid.trackIndex).contains(where: {
        Int($0.pitch) == short.pitch && Int($0.tick) < nextTick + short.duration
            && Int($0.tick) + Int($0.duration) > nextTick
    }), let adjacent = try? session.document.addNotes([
        NewNote(track: grid.trackIndex, tick: Tick(nextTick), pitch: UInt8(short.pitch),
                duration: Tick(short.duration), velocity: 1)
    ]).first else {
        report.fail(id, "adjacent short name-note fixture could not be seeded")
        return
    }
    grid.refreshFromSession()
    grid.setNoteNameMode(enabled: true)
    func hasLabel(_ noteID: NoteID) -> Bool {
        guard let note = session.document.note(noteID),
              let box = noteBox(grid, session: session, note: note) else { return false }
        return grid.scene.pianoNoteTextModel.asArray.contains {
            $0.labelText == GridScene.keyName(Int(note.pitch))
                && renderingNear(($0.labelRect["x"] as? Double) ?? -.infinity,
                                 box.x + grid.metrics.spaceHalf)
        }
    }
    report.expect(!hasLabel(short.id), cppID: id,
                  message: "an abutting short same-pitch note carries no label (first)")
    report.expect(!hasLabel(adjacent), cppID: id,
                  message: "an abutting short same-pitch note carries no label (second)")
    report.expect(hasLabel(wide.id), cppID: id,
                  message: "a distant wide note keeps its label")
    let noteFonts = GridTypography.fonts(
        metrics: grid.metrics, typography: Typography(baseFontPx: 13))
    let measured = GridTypography(fonts: noteFonts, rowHeight: 32, pixel: grid.metrics.pixel)
    let fitHeight = measured.noteNameOccupiedHeight.rounded(.up)
        + 2 * grid.metrics.spaceHalf + grid.metrics.pixel
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(fitHeight)
        _ = camera.setVScroll(max(0, (127.5 - Double(wide.pitch)) * fitHeight - 160))
    }
    grid.refreshCamera()
    report.expect(hasLabel(wide.id), cppID: id,
                  message: "a row at the exact padded fit still labels")
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(fitHeight - grid.metrics.pixel)
        _ = camera.setVScroll(max(0, (127.5 - Double(wide.pitch))
                                 * (fitHeight - grid.metrics.pixel) - 160))
    }
    grid.refreshCamera()
    report.expect(!hasLabel(wide.id), cppID: id,
                  message: "one pixel shorter the label hides instead of shrinking")
    for (velocity, label) in [
        (100, "label ink is chosen against the bright velocity fill"),
        (1, "label ink is chosen against the dark velocity fill"),
    ] {
        let fill = PaletteMath.velocityNoteColor(
            velocity: velocity, zeroColor: grid.palette.noteVelocityZero)
        report.expect(PaletteMath.contrastRatio(
            fill, NoteNameLabels.textColor(fillColor: fill, palette: grid.palette)) >= 4.5,
            cppID: id, message: label)
    }
    grid.setNoteNameMode(enabled: false)
}
