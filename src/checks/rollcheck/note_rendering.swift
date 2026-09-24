import Foundation
import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func runNoteRenderingChecks(_ report: CheckReport, session: DocumentSession) {
    checkNoteBorders(report, session: session)
    checkIdentityNoteColors(report, session: session)
}

@MainActor
private func firstNoteRect(named name: String, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == name {
        return model[index]
    }
    return nil
}

@MainActor
private func renderingSeed(_ report: CheckReport, id: String,
                           session: DocumentSession, grid: PianoGrid) -> NoteID? {
    let camera = session.camera
    let projection = camera.projection
    let snapshot = camera.snapshot
    let track = grid.trackIndex
    let occupied = (0..<session.document.engineTracks.usedTrackCount).flatMap {
        session.document.notes(in: $0)
    }
    for pitch in (24...115).reversed() {
        let row = projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow,
              let top = projection.rowTop(row, keyHeight: snapshot.keyHeight,
                                          scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
              let bottom = projection.rowBottom(row, keyHeight: snapshot.keyHeight,
                                                scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
              top >= 0, bottom <= snapshot.rollHeight else { continue }
        for probe in stride(from: 40, to: Int(snapshot.viewportWidth) - 40, by: 24) {
            let tick = grid.snapTickDown(camera.tickAtContentX(Double(probe)))
            let cell = grid.gridCell(at: tick)
            let duration = cell.duration
            guard (tick - cell.start) % duration == 0 else { continue }
            let left = camera.contentX(tick: Double(tick))
            let right = camera.contentX(tick: Double(tick + duration))
            let snap = camera.contentX(tick: Double(tick + grid.snapTicks))
            guard left >= 0, right - left >= 12, snap - left >= 8,
                  right < snapshot.viewportWidth,
                  !occupied.contains(where: { note in
                      Int(note.pitch) == pitch && Int(note.tick) < tick + duration
                          && Int(note.tick) + Int(note.duration) > tick
                  }) else { continue }
            guard let added = try? session.document.addNotes([
                NewNote(track: track, tick: Tick(tick), pitch: UInt8(pitch),
                        duration: Tick(duration), velocity: 100)
            ]), let id = added.first else {
                report.fail(id, "note rendering fixture could not insert the free cell")
                return nil
            }
            grid.refreshFromSession()
            return id
        }
    }
    report.fail(id, "note rendering fixture has no visible free cell (40px initial probe)")
    return nil
}

@MainActor
private func noteBox(_ grid: PianoGrid, session: DocumentSession, note: Note)
    -> (x: Double, y: Double, w: Double, h: Double)? {
    grid.projectedNoteBox(tick: Int(note.tick), end: Int(note.tick + note.duration),
                          pitch: Int(note.pitch))
}

private func renderingNear(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 1e-6
}
private func publishedOpaque(_ color: String) -> Bool {
    color.count == 7 && color.hasPrefix("#")
}


@MainActor
private func hasFrame(_ model: QListModel<SceneRect>,
                      box: (x: Double, y: Double, w: Double, h: Double),
                      inset: Double, thickness: Double, color: String) -> Bool {
    let x = box.x + inset, y = box.y + inset
    let w = box.w - 2 * inset, h = box.h - 2 * inset
    guard w > 0, h > 2 * thickness else { return false }
    let sides = [(x, y, w, thickness), (x, y + h - thickness, w, thickness),
                 (x, y + thickness, thickness, h - 2 * thickness),
                 (x + w - thickness, y + thickness, thickness, h - 2 * thickness)]
    return sides.allSatisfy { side in
        (0..<model.count).contains { index in
            let rect = model[index]
            return rect.fillColor == color && renderingNear(rect.x, side.0)
                && renderingNear(rect.y, side.1) && renderingNear(rect.width, side.2)
                && renderingNear(rect.height, side.3)
        }
    }
}

@MainActor
private func checkNoteBorders(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectedNoteFrameRaster"
    let tinyID = "swiftcore/PianoRoll::tinyNoteBorderRaster"
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
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
    defer { session.document.deleteNotes([noteID]) }
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

    grid.configureViewport(width: 640, height: 320, fontPx: 5, dpr: 1)
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(5.0)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 5.0 - 160))
    }
    grid.refreshCamera()
    guard let tiny = noteBox(grid, session: session, note: note),
          let tinyFill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
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
}

@MainActor
private func checkIdentityNoteColors(_ report: CheckReport, session: DocumentSession) {
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
}
