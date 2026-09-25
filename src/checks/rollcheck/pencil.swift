import Foundation
@testable import PorydawApp
import PorydawCore

@MainActor
func runPencilChecks(_ report: CheckReport, session: DocumentSession) {
    checkPencilFractionalPlacement(report, session: session)
    checkPencilPlacement(report, session: session)
    checkPencilAbuttingNotes(report, session: session)
    checkVelocityDoubleClickDelete(report, session: session)
    checkPointerDrawCancellation(report, session: session)
    checkDrawLatchAndCancel(report, session: session)
}

private struct PencilCell {
    let tick: Int
    let duration: Int
    let pitch: Int
    let x: Double
    let y: Double
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
    let grid = makeCameraGrid(session: session, zoom: 31.375)
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
    let grid = makeCameraGrid(session: session)
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
    let grid = makeCameraGrid(session: session)
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
    let grid = makeCameraGrid(session: session)
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
    let grid = makeCameraGrid(session: session)
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

@MainActor
private func checkDrawLatchAndCancel(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::drawLatchAndCancel"
    let grid = makeCameraGrid(session: session)
    let snap = max(1, grid.snapTicks)
    func emptyCell() -> (x: Double, y: Double, tick: Int, pitch: Int)? {
        for candidateY in [250.0, 200.0, 150.0, 100.0, 50.0] {
            guard let pitch = session.camera.projection.pitch(
                atY: candidateY, keyHeight: session.camera.snapshot.keyHeight,
                scrollY: session.camera.snapshot.scrollY, dpr: grid.devicePixelRatio)
            else { continue }
            for candidateX in [500.0, 550.0, 450.0, 600.0, 400.0] {
                let tick = Int(session.camera.tickAtContentX(candidateX)) / snap * snap
                let x = session.camera.displayX(
                    tick: Double(tick), origin: 0, dpr: grid.devicePixelRatio)
                let occupied = (0..<grid.scene.pianoNoteFills.count).contains { index in
                    let rect = grid.scene.pianoNoteFills[index]
                    return rect.x < x + 20 && rect.x + rect.width > x
                        && rect.y <= candidateY && rect.y + rect.height >= candidateY
                }
                if !occupied { return (x, candidateY, tick, pitch) }
            }
        }
        return nil
    }
    guard let first = emptyCell() else {
        report.fail(id, "no free draw cell resolves through the camera")
        return
    }
    let beforeIDs = Set(session.document.notes(in: grid.trackIndex).map(\.id))
    let revision = session.document.revision
    grid.beginPointer(x: first.x, y: first.y, modifiers: 0)
    grid.updatePointer(x: first.x + 20, y: first.y)
    grid.endPointer(x: first.x + 20, y: first.y)
    let created = session.document.notes(in: grid.trackIndex)
        .first { !beforeIDs.contains($0.id) }
    report.expect(
        session.document.revision == revision + 1
            && created.map { Int($0.velocity) == 100 } == true,
        cppID: id, message: "draw commits one note at the default latched velocity")
    grid.lastVelocity = 77
    guard let second = emptyCell() else {
        report.fail(id, "no second free draw cell resolves through the camera")
        return
    }
    let beforeSecond = Set(session.document.notes(in: grid.trackIndex).map(\.id))
    grid.beginPointer(x: second.x, y: second.y, modifiers: 0)
    grid.updatePointer(x: second.x + 20, y: second.y)
    grid.endPointer(x: second.x + 20, y: second.y)
    let latched = session.document.notes(in: grid.trackIndex)
        .first { !beforeSecond.contains($0.id) }
    report.expect(
        latched.map { Int($0.velocity) == 77 } == true,
        cppID: id, message: "draw commits at the latched last-used velocity")
    if let latchedID = latched?.id {
        grid.doublePointer(x: second.x + 10, y: second.y)
        report.expect(
            session.document.note(latchedID) == nil,
            cppID: id, message: "double press deletes the note under the pointer")
    }
    // Cancel reasons: a live move gesture cancelled by ungrab, focus loss,
    // window deactivation, or hiding commits nothing and records the reason.
    guard let target = session.document.notes(in: grid.trackIndex).first,
          let targetRect = firstRect(
              named: "gridNote_\(target.id.rawValue)", in: grid.scene.pianoNoteFills)
    else {
        report.fail(id, "cancel fixture exposes no projected note")
        return
    }
    let pressX = targetRect.x + targetRect.width / 2
    let pressY = targetRect.y + targetRect.height / 2
    let dragX = Double(snap) * session.camera.snapshot.pixelsPerTick
    for reason in [GridCancelReason.pointerUngrabbed, .focusLost,
                   .windowDeactivated, .hidden] {
        let cancelRevision = session.document.revision
        let cancelCount = session.document.notes(in: grid.trackIndex).count
        grid.beginPointer(x: pressX, y: pressY, modifiers: 0)
        let pressedSummary = grid.noteSummary
        grid.updatePointer(x: pressX + dragX, y: pressY)
        grid.inputCancelled(reason: reason.rawValue)
        report.expect(
            session.document.revision == cancelRevision
                && session.document.notes(in: grid.trackIndex).count == cancelCount
                && grid.lastCancelReason == reason.rawValue
                && !grid.interactionActive
                && grid.noteSummary == pressedSummary,
            cppID: id,
            message: "\(reason) cancel discards the gesture, records the reason, and keeps the summary")
    }
    // Idle Escape clears the ephemeral selection without a document mutation
    // and is never reported as a host cancel reason.
    let escapeRevision = session.document.revision
    session.setSelectedNotes([target.id])
    _ = grid.handleEscape()
    report.expect(
        session.selectedNotes.isEmpty && session.document.revision == escapeRevision
            && grid.lastCancelReason == GridCancelReason.hidden.rawValue,
        cppID: id, message: "idle Escape clears selection without a cancel reason or mutation")
}
