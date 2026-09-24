import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runPencilChecks(_ report: CheckReport, session: DocumentSession) {
    checkPencilFractionalPlacement(report, session: session)
    checkPencilPlacement(report, session: session)
    checkPencilAbuttingNotes(report, session: session)
    checkVelocityDoubleClickDelete(report, session: session)
    checkPointerDrawCancellation(report, session: session)
}

private struct PencilCell {
    let tick: Int
    let duration: Int
    let pitch: Int
    let x: Double
    let y: Double
}

@MainActor
private func pencilGrid(session: DocumentSession, zoom: Double = 35) -> PianoGrid {
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(zoom) }
    grid.refreshCamera()
    return grid
}

@MainActor
private func pencilFreeCell(
    session: DocumentSession, grid: PianoGrid, firstProbe: Int = 40,
    fractional: Bool = false
) -> PencilCell? {
    let camera = session.camera
    let snapshot = camera.snapshot
    let step = max(1, grid.snapTicks)
    let occupiedNotes = (0..<session.document.engineTracks.usedTrackCount)
        .flatMap { session.document.notes(in: $0) }
    for pitch in stride(from: 115, through: 24, by: -1) {
        let row = camera.projection.row(forPitch: pitch)
        guard let top = camera.projection.rowTop(
            row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
            let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
            top >= 0, bottom <= snapshot.rollHeight else { continue }
        for probe in stride(from: firstProbe, to: Int(snapshot.viewportWidth) - 40, by: 24) {
            let tick = grid.snapTickDown(camera.tickAtContentX(Double(probe)))
            let cell = grid.gridCell(at: tick)
            let duration = fractional ? step : cell.duration
            guard fractional || (tick - cell.start) % duration == 0 else { continue }
            let left = camera.displayX(tick: Double(tick), origin: 0, dpr: grid.devicePixelRatio)
            let right = camera.displayX(tick: Double(tick + duration), origin: 0,
                                        dpr: grid.devicePixelRatio)
            let snapRight = camera.displayX(tick: Double(tick + step), origin: 0,
                                            dpr: grid.devicePixelRatio)
            let center = (left + snapRight) / 2
            guard left >= 4, right <= snapshot.viewportWidth - 4,
                  right - left >= (fractional ? 4 : 12),
                  snapRight - left >= (fractional ? 4 : 8),
                  !fractional || (abs(center - center.rounded()) >= 1e-12
                      && grid.snapTickDown(camera.tickAtContentX(center)) == tick)
            else { continue }
            let occupied = occupiedNotes.contains { note in
                Int(note.pitch) == pitch && Int(note.tick) < tick + 2 * duration
                    && (note.isUnterminated || Int(note.tick) + Int(note.duration) + duration > tick)
            }
            if !occupied {
                return PencilCell(tick: tick, duration: duration, pitch: pitch,
                                  x: center, y: (top + bottom) / 2)
            }
        }
    }
    return nil
}

@MainActor
private func pencilDraw(_ cell: PencilCell, grid: PianoGrid) {
    grid.beginPointer(x: cell.x, y: cell.y, modifiers: 0)
    grid.endPointer(x: cell.x, y: cell.y)
}

@MainActor
private func pencilRestore(
    _ report: CheckReport, id: String, session: DocumentSession,
    baseline: SaveSnapshot
) {
    let document = session.document
    while document.history.currentIdentity != baseline.identity && document.history.canUndo {
        guard document.history.undoDocument() else {
            report.fail(id, "a non-document history entry interrupted the gesture undo drain")
            return
        }
    }
    do {
        let restored = try document.captureSave()
        report.expect(document.history.currentIdentity == baseline.identity
                          && restored.bytes == baseline.bytes,
                      cppID: id, message: "undo restores the original SMF bytes and history position")
    } catch {
        report.fail(id, "could not encode the restored MIDI document: \(error)")
    }
}

@MainActor
private func checkPencilFractionalPlacement(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::pencilFractionalPlacement"
    let grid = pencilGrid(session: session, zoom: 31.375)
    _ = session.mutateCamera { _ = $0.setHScroll(0.625) }
    grid.refreshCamera()
    let snapshot = session.camera.snapshot
    report.expect(abs(snapshot.pixelsPerBeat - 31.375) <= 1e-12
                      && abs(snapshot.scrollX - 0.625) <= 1e-12,
                  cppID: id, message: "fractional edit camera applies exactly")
    guard let cell = pencilFreeCell(session: session, grid: grid, fractional: true) else {
        report.fail(id, "no empty fractional displayed cell for edit regression")
        return
    }
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-draw SMF bytes")
        return
    }
    pencilDraw(cell, grid: grid)
    let atTick = session.document.notes(in: grid.trackIndex).filter {
        Int($0.tick) == cell.tick && Int($0.pitch) == cell.pitch
    }
    report.expect(atTick.count == 1, cppID: id,
                  message: "a fractional-center press saves in the displayed tick cell")
    let adjacent = session.document.notes(in: grid.trackIndex).contains {
        Int($0.pitch) == cell.pitch
            && (Int($0.tick) == cell.tick - cell.duration
                || Int($0.tick) == cell.tick + cell.duration)
    }
    report.expect(!adjacent, cppID: id,
                  message: "the fractional-center press does not create a neighboring note")
    report.expect(session.document.history.currentIdentity != baseline.identity,
                  cppID: id, message: "a fractional-center draw records a history entry")
    pencilRestore(report, id: id, session: session, baseline: baseline)
    report.expect(session.document.notes(in: grid.trackIndex).allSatisfy {
        Int($0.pitch) != cell.pitch || Int($0.tick) != cell.tick
    }, cppID: id, message: "undo removes the fractional-cell probe")
}

@MainActor
private func checkPencilPlacement(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::pencilPlacement"
    let grid = pencilGrid(session: session)
    guard let cell = pencilFreeCell(session: session, grid: grid),
          let baseline = try? session.document.captureSave() else {
        report.fail(id, "no free grid cell or pre-draw SMF snapshot")
        return
    }
    grid.setEditCursorTick(tick: cell.tick + 3 * cell.duration)
    pencilDraw(cell, grid: grid)
    let note = session.document.notes(in: grid.trackIndex).first {
        Int($0.tick) == cell.tick && Int($0.pitch) == cell.pitch
    }
    report.expect(note != nil, cppID: id, message: "pointer draw creates a note at the selected cell")
    report.expect(note.map { Int($0.velocity) == 100 } == true, cppID: id,
                  message: "the newly drawn note has default velocity 100")
    pencilRestore(report, id: id, session: session, baseline: baseline)
}

@MainActor
private func checkPencilAbuttingNotes(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::pencilAbuttingRaster"
    let grid = pencilGrid(session: session)
    guard let cell = pencilFreeCell(session: session, grid: grid),
          let baseline = try? session.document.captureSave() else {
        report.fail(id, "no free grid cell or pre-draw SMF snapshot")
        return
    }
    grid.setEditCursorTick(tick: cell.tick + 3 * cell.duration)
    pencilDraw(cell, grid: grid)
    let note = session.document.notes(in: grid.trackIndex).first {
        Int($0.tick) == cell.tick && Int($0.pitch) == cell.pitch
    }
    report.expect(note != nil, cppID: id,
                  message: "pencil draw produces the note before the abutting fixture")
    guard let note else {
        pencilRestore(report, id: id, session: session, baseline: baseline)
        return
    }
    let nextTick = note.tick + note.duration
    guard let added = try? session.document.addNotes([
        NewNote(track: grid.trackIndex, tick: nextTick, pitch: note.pitch,
                duration: note.duration, velocity: 100)
    ]), added.count == 1 else {
        report.fail(id, "could not seed a note at the drawn note's end tick")
        pencilRestore(report, id: id, session: session, baseline: baseline)
        return
    }
    grid.refreshFromSession()
    let left = (0..<grid.scene.pianoNoteFills.count)
        .map { grid.scene.pianoNoteFills[$0] }
        .first { $0.primitiveName == "gridNote_\(note.id.rawValue)" }
    let right = (0..<grid.scene.pianoNoteFills.count)
        .map { grid.scene.pianoNoteFills[$0] }
        .first { $0.primitiveName == "gridNote_\(added[0].rawValue)" }
    report.expect(left != nil && right != nil
                      && session.document.notes(in: grid.trackIndex).contains {
                          $0.id == added[0] && $0.tick == nextTick && $0.pitch == note.pitch
                      }, cppID: id,
                  message: "both abutting notes appear on the projected row")
    pencilRestore(report, id: id, session: session, baseline: baseline)
}

@MainActor
private func checkVelocityDoubleClickDelete(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::velocityDoubleClickDelete"
    let grid = pencilGrid(session: session)
    guard let a = pencilFreeCell(session: session, grid: grid, firstProbe: 40),
          let baseline = try? session.document.captureSave(),
          let first = try? session.document.addNotes([
              NewNote(track: grid.trackIndex, tick: Tick(a.tick), pitch: UInt8(a.pitch),
                      duration: Tick(a.duration), velocity: 100)
          ]), first.count == 1 else {
        report.fail(id, "could not seed the first velocity fixture note")
        return
    }
    grid.refreshFromSession()
    guard let b = pencilFreeCell(session: session, grid: grid, firstProbe: 64),
          let second = try? session.document.addNotes([
              NewNote(track: grid.trackIndex, tick: Tick(b.tick), pitch: UInt8(b.pitch),
                      duration: Tick(b.duration), velocity: 73)
          ]), second.count == 1,
          let c = pencilFreeCell(session: session, grid: grid) else {
        report.fail(id, "could not seed the second velocity note or locate a free delete cell")
        pencilRestore(report, id: id, session: session, baseline: baseline)
        return
    }
    grid.refreshFromSession()
    report.expect(session.document.note(first[0])?.velocity == 100
                      && session.document.note(second[0])?.velocity == 73,
                  cppID: id, message: "the two velocity fixture notes retain their seeded values")
    pencilDraw(c, grid: grid)
    let drawn = session.document.notes(in: grid.trackIndex).first {
        Int($0.tick) == c.tick && Int($0.pitch) == c.pitch
    }
    report.expect(drawn != nil, cppID: id, message: "a free cell accepts the note to delete")
    grid.doublePointer(x: c.x, y: c.y)
    report.expect(drawn.map { session.document.note($0.id) == nil } == true,
                  cppID: id, message: "double press deletes the note under the pointer")
    pencilRestore(report, id: id, session: session, baseline: baseline)
}

@MainActor
private func checkPointerDrawCancellation(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::quickLifecycle"
    let grid = pencilGrid(session: session)
    guard let cell = pencilFreeCell(session: session, grid: grid),
          let baseline = try? session.document.captureSave() else {
        report.fail(id, "no free grid cell for the pointer lifecycle")
        return
    }
    for reason in [GridCancelReason.pointerUngrabbed, .windowDeactivated, .focusLost] {
        let revision = session.document.revision
        grid.beginPointer(x: cell.x, y: cell.y, modifiers: 0)
        grid.updatePointer(x: cell.x + 20, y: cell.y)
        let preview = grid.scene.pianoDrawPreviewFill.count > 0
        grid.inputCancelled(reason: reason.rawValue)
        grid.endPointer(x: cell.x + 20, y: cell.y)
        report.expect(preview && grid.scene.pianoDrawPreviewFill.count == 0
                          && !grid.interactionActive && grid.lastCancelReason == reason.rawValue
                          && session.document.revision == revision,
                      cppID: id,
                      message: "\(reason) discards the staged draw without a document write")
    }
    pencilRestore(report, id: id, session: session, baseline: baseline)
}
