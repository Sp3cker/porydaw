import Foundation
import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func runResizeChecks(_ report: CheckReport, session: DocumentSession) {
    let originalCamera = session.camera.snapshot
    let originalSelection = session.selectedNoteOrder
    defer {
        session.mutateCamera {
            $0.updateViewport(width: originalCamera.viewportWidth,
                              rollHeight: originalCamera.rollHeight)
            $0.restore(pixelsPerBeat: originalCamera.pixelsPerBeat,
                       keyHeight: originalCamera.keyHeight,
                       scrollX: originalCamera.scrollX, scrollY: originalCamera.scrollY)
        }
        session.setSelectedNotes(originalSelection)
    }
    checkResizeOffGrid(report, session: session)
    checkResizeSelection(report, session: session)
    checkResizeMinimum(report, session: session)
    checkResizeAbutting(report, session: session)
    checkResizeHoverCursor(report, session: session)
}

private struct ResizeCell {
    let tick: Int
    let duration: Int
    let pitch: Int
}

@MainActor
private func resizeGrid(_ session: DocumentSession) -> PianoGrid {
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    return grid
}

@MainActor
private func resizeFreeCell(_ grid: PianoGrid, session: DocumentSession,
                            firstProbe: Int = 8) -> ResizeCell? {
    let camera = session.camera
    let snapshot = camera.snapshot
    for pitch in (24...115).reversed() {
        let row = camera.projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow,
              let top = camera.projection.rowTop(row, keyHeight: snapshot.keyHeight,
                                                  scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
              let bottom = camera.projection.rowBottom(row, keyHeight: snapshot.keyHeight,
                                                        scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
              top >= 0, bottom <= 320 else { continue }
        for probe in stride(from: firstProbe, to: 600, by: 24) {
            let tick = grid.snapTickDown(camera.tickAtContentX(Double(probe)))
            let cell = grid.gridCell(at: tick)
            let duration = cell.duration
            guard (tick - cell.start) % max(1, duration) == 0 else { continue }
            let x0 = camera.displayX(tick: Double(tick), origin: 0, dpr: grid.devicePixelRatio)
            let x1 = camera.displayX(tick: Double(tick + duration), origin: 0, dpr: grid.devicePixelRatio)
            let snapX = camera.displayX(tick: Double(tick + grid.snapTicks), origin: 0,
                                        dpr: grid.devicePixelRatio)
            guard x0 >= 0, x1 - x0 >= 12, snapX - x0 >= 8, x1 < 640 else { continue }
            let occupied = (0..<session.document.engineTracks.usedTrackCount).contains { track in
                session.document.notes(in: track).contains { note in
                    Int(note.pitch) == pitch && Int(note.tick) < tick + 2 * duration
                        && (note.isUnterminated || Int(note.tick) + Int(note.duration) + duration > tick)
                }
            }
            if !occupied { return ResizeCell(tick: tick, duration: duration, pitch: pitch) }
        }
    }
    return nil
}

@MainActor
private func resizeHandle(_ id: NoteID, grid: PianoGrid) -> SceneRect? {
    let name = "gridNote_\(id.rawValue)"
    for index in 0..<grid.scene.pianoNoteFills.count
    where grid.scene.pianoNoteFills[index].primitiveName == name {
        return grid.scene.pianoNoteFills[index]
    }
    return nil
}

@MainActor
private func resizeUndoTo(_ identity: DocumentIdentity, session: DocumentSession) -> Bool {
    let history = session.document.history
    while history.currentIdentity != identity && history.canUndo {
        guard history.undoDocument() else { return false }
    }
    return history.currentIdentity == identity
}

@MainActor
private func checkResizeOffGrid(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::resizeOffGrid"
    let document = session.document
    let start = document.history.currentIdentity
    defer { _ = resizeUndoTo(start, session: session); session.clearSelectedNotes() }
    let grid = resizeGrid(session)
    guard let d = resizeFreeCell(grid, session: session, firstProbe: 88) else {
        report.fail(id, "no free grid cell for the off-grid resize")
        return
    }
    let offDuration = d.duration + d.duration / 4
    guard let noteID = try? document.addNotes([
        NewNote(track: grid.trackIndex, tick: Tick(d.tick), pitch: UInt8(d.pitch),
                duration: Tick(offDuration), velocity: 100)
    ]).first, let before = try? document.captureSave().bytes else {
        report.fail(id, "off-grid note fixture could not be serialized")
        return
    }
    let planted = document.history.currentIdentity
    grid.refreshFromSession()
    guard let rect = resizeHandle(noteID, grid: grid) else {
        report.fail(id, "off-grid note is not projected")
        return
    }
    let y = rect.y + rect.height / 2
    let right = session.camera.displayX(tick: Double(d.tick + offDuration), origin: 0,
                                        dpr: grid.devicePixelRatio)
    let inset = grid.edgeGripReach / 2
    grid.beginPointer(x: right - inset, y: y, modifiers: 0)
    report.expect(grid.activeNoteId == noteID.rawValue && grid.statusText.contains("Resizing"),
                  cppID: id, message: "right edge grips the off-grid note")
    let pull = session.camera.displayX(tick: Double(d.tick) + 1.9 * Double(d.duration),
                                       origin: 0, dpr: grid.devicePixelRatio)
    grid.updatePointer(x: pull, y: y)
    grid.endPointer(x: pull, y: y)
    report.expect(document.note(noteID).map {
        Int($0.tick) == d.tick && Int($0.duration) == 2 * d.duration
    } == true, cppID: id, message: "off-grid right edge ends exactly two ruler cells after start")
    report.expect(resizeUndoTo(planted, session: session)
                      && (try? document.captureSave().bytes) == before,
                  cppID: id, message: "Undo restores the planted off-grid MIDI bytes")
}

@MainActor
private func checkResizeSelection(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::resizeSelection"
    let document = session.document
    let start = document.history.currentIdentity
    defer { _ = resizeUndoTo(start, session: session); session.clearSelectedNotes() }
    let grid = resizeGrid(session)
    guard let a = resizeFreeCell(grid, session: session, firstProbe: 40),
          let aID = try? document.addNotes([
              NewNote(track: grid.trackIndex, tick: Tick(a.tick), pitch: UInt8(a.pitch),
                      duration: Tick(a.duration), velocity: 100)
          ]).first,
          let b = resizeFreeCell(grid, session: session, firstProbe: 64),
          let bID = try? document.addNotes([
              NewNote(track: grid.trackIndex, tick: Tick(b.tick), pitch: UInt8(b.pitch),
                      duration: Tick(b.duration), velocity: 73)
          ]).first else {
        report.fail(id, "velocity-pair seed could not find two free cells")
        return
    }
    let firstProbe = Int(ceil(session.camera.displayX(
        tick: Double(b.tick + 2 * b.duration), origin: 0, dpr: grid.devicePixelRatio)))
    guard let d = resizeFreeCell(grid, session: session, firstProbe: firstProbe),
          let dID = try? document.addNotes([
              NewNote(track: grid.trackIndex, tick: Tick(d.tick), pitch: UInt8(d.pitch),
                      duration: Tick(2 * d.duration), velocity: 100)
          ]).first,
          let before = try? document.captureSave().bytes,
          let bBefore = document.note(bID), document.note(aID) != nil,
          document.note(dID) != nil else {
        report.fail(id, "selection resize could not seed its grabbed note")
        return
    }
    let planted = document.history.currentIdentity
    grid.refreshFromSession()
    guard let bRect = resizeHandle(bID, grid: grid),
          let dRect = resizeHandle(dID, grid: grid) else {
        report.fail(id, "selection resize notes are not projected")
        return
    }
    let bX = bRect.x + bRect.width / 2, bY = bRect.y + bRect.height / 2
    grid.beginPointer(x: bX, y: bY, modifiers: 0)
    grid.endPointer(x: bX, y: bY)
    let selected = document.history.currentIdentity
    let revision = document.revision
    let edge = session.camera.displayX(tick: Double(d.tick + 2 * d.duration), origin: 0,
                                       dpr: grid.devicePixelRatio) - grid.edgeGripReach / 2
    let y = dRect.y + dRect.height / 2
    grid.beginPointer(x: edge, y: y, modifiers: 0x0400_0000)
    grid.endPointer(x: edge, y: y)
    report.expect(session.selectedNotes == Set([bID, dID]), cppID: id,
                  message: "stationary Ctrl+edge joins grabbed note to selection")
    report.expect(document.note(dID).map { Int($0.duration) == 2 * d.duration } == true,
                  cppID: id, message: "stationary Ctrl+edge does not resize grabbed note")
    report.expect(document.history.currentIdentity == selected && document.revision == revision,
                  cppID: id, message: "stationary Ctrl+edge creates no history entry")
    let cellWidth = session.camera.displayX(tick: Double(d.tick + 3 * d.duration), origin: 0,
                                            dpr: grid.devicePixelRatio)
        - session.camera.displayX(tick: Double(d.tick + 2 * d.duration), origin: 0,
                                  dpr: grid.devicePixelRatio)
    grid.beginPointer(x: edge, y: y, modifiers: 0x0400_0000)
    grid.updatePointer(x: edge + cellWidth, y: y)
    grid.endPointer(x: edge + cellWidth, y: y)
    report.expect(document.note(dID).map { Int($0.duration) == 3 * d.duration } == true,
                  cppID: id, message: "Ctrl+edge drag grows grabbed note by exactly one cell")
    report.expect(document.note(bID).map {
        Int($0.duration) == Int(bBefore.duration) + d.duration
    } == true, cppID: id, message: "Ctrl+edge drag grows the rest of selection by one cell")
    report.expect(document.revision == revision + 1
                      && document.history.currentIdentity != selected,
                  cppID: id, message: "one selection resize gesture commits one transaction")
    report.expect(document.history.undoDocument()
                      && document.history.currentIdentity == planted
                      && (try? document.captureSave().bytes) == before,
                  cppID: id, message: "Undo restores the planted selection MIDI bytes")
}

@MainActor
private func checkResizeMinimum(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::resizeMinimum"
    let document = session.document
    let start = document.history.currentIdentity
    defer { _ = resizeUndoTo(start, session: session); session.clearSelectedNotes() }
    let grid = resizeGrid(session)
    guard let d = resizeFreeCell(grid, session: session, firstProbe: 88),
          let noteID = try? document.addNotes([
              NewNote(track: grid.trackIndex, tick: Tick(d.tick), pitch: UInt8(d.pitch),
                      duration: Tick(2 * d.duration), velocity: 100)
          ]).first,
          let before = try? document.captureSave().bytes else {
        report.fail(id, "no free grid cell for the minimum resize")
        return
    }
    let planted = document.history.currentIdentity
    grid.refreshFromSession()
    guard let rect = resizeHandle(noteID, grid: grid) else {
        report.fail(id, "minimum-resize fixture is not projected")
        return
    }
    let snap = grid.snapTicks
    let edge = session.camera.displayX(tick: Double(d.tick + 2 * d.duration), origin: 0,
                                       dpr: grid.devicePixelRatio) - grid.edgeGripReach / 2
    let y = rect.y + rect.height / 2
    let overshoot = session.camera.displayX(tick: Double(d.tick) - 0.5 * Double(d.duration),
                                            origin: 0, dpr: grid.devicePixelRatio)
    grid.beginPointer(x: edge, y: y, modifiers: 0)
    grid.updatePointer(x: overshoot, y: y)
    grid.endPointer(x: overshoot, y: y)
    report.expect(document.note(noteID).map {
        Int($0.tick) == d.tick && Int($0.duration) == snap
    } == true, cppID: id, message: "overshot edge clamps at one snap cell")
    let originalZoom = session.camera.snapshot.pixelsPerBeat
    let originalScroll = session.camera.snapshot.scrollX
    session.mutateCamera {
        _ = $0.setTimeZoom(4.0)
        _ = $0.setHScroll(max(0, Double(d.tick) * 4.0
                                / Double(document.ticksPerBeat) - 100.0))
    }
    grid.refreshCamera()
    let narrowLeft = session.camera.displayX(tick: Double(d.tick), origin: 0,
                                              dpr: grid.devicePixelRatio)
    let narrowRight = session.camera.displayX(tick: Double(d.tick + snap), origin: 0,
                                               dpr: grid.devicePixelRatio)
    report.expect(narrowRight - narrowLeft <= 3, cppID: id,
                  message: "minimum-duration note spans at most three pixels at narrow zoom")
    session.mutateCamera {
        _ = $0.setTimeZoom(originalZoom)
        _ = $0.setHScroll(originalScroll)
    }
    grid.refreshCamera()
    report.expect(resizeUndoTo(planted, session: session)
                      && (try? document.captureSave().bytes) == before,
                  cppID: id, message: "Undo restores the planted minimum-resize MIDI bytes")
}

@MainActor
private func checkResizeAbutting(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::resizeAbutting"
    let document = session.document
    let start = document.history.currentIdentity
    defer { _ = resizeUndoTo(start, session: session); session.clearSelectedNotes() }
    let grid = resizeGrid(session)
    guard let g = resizeFreeCell(grid, session: session),
          let ids = try? document.addNotes([
              NewNote(track: grid.trackIndex, tick: Tick(g.tick), pitch: UInt8(g.pitch),
                      duration: Tick(g.duration), velocity: 100),
              NewNote(track: grid.trackIndex, tick: Tick(g.tick + g.duration),
                      pitch: UInt8(g.pitch), duration: Tick(g.duration), velocity: 100)
          ]), ids.count == 2,
          let before = try? document.captureSave().bytes else {
        report.fail(id, "no free grid cell for the abutting-notes resize")
        return
    }
    let planted = document.history.currentIdentity
    grid.refreshFromSession()
    guard let rect = resizeHandle(ids[0], grid: grid) else {
        report.fail(id, "abutting note pair is not projected")
        return
    }
    let snap = grid.snapTicks
    let boundary = session.camera.displayX(tick: Double(g.tick + g.duration), origin: 0,
                                           dpr: grid.devicePixelRatio)
    let inset = grid.edgeGripReach / 2
    let y = rect.y + rect.height / 2
    let pullLeft = session.camera.displayX(tick: Double(g.tick + g.duration - snap), origin: 0,
                                           dpr: grid.devicePixelRatio)
    grid.beginPointer(x: boundary - inset, y: y, modifiers: 0)
    report.expect(grid.activeNoteId == ids[0].rawValue && grid.statusText.contains("Resizing"),
                  cppID: id, message: "boundary-left grip targets the first note")
    grid.updatePointer(x: pullLeft, y: y)
    grid.endPointer(x: pullLeft, y: y)
    report.expect(document.note(ids[0]).map {
        Int($0.tick) == g.tick && Int($0.duration) == g.duration - snap
    } == true, cppID: id, message: "boundary-left drag shortens first note by one snap cell")
    report.expect(document.note(ids[1]).map {
        Int($0.tick) == g.tick + g.duration && Int($0.duration) == g.duration
    } == true, cppID: id, message: "boundary-left drag leaves second note unchanged")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "Undo reverses the first boundary gesture")
    grid.refreshFromSession()
    session.clearSelectedNotes()
    let pullRight = session.camera.displayX(tick: Double(g.tick + g.duration + snap), origin: 0,
                                            dpr: grid.devicePixelRatio)
    grid.beginPointer(x: boundary + inset, y: y, modifiers: 0)
    report.expect(grid.activeNoteId == ids[1].rawValue && grid.statusText.contains("Resizing"),
                  cppID: id, message: "boundary-right grip targets the second note")
    grid.updatePointer(x: pullRight, y: y)
    grid.endPointer(x: pullRight, y: y)
    report.expect(document.note(ids[1]).map {
        Int($0.tick) == g.tick + g.duration + snap && Int($0.duration) == g.duration - snap
    } == true, cppID: id, message: "boundary-right drag advances second start one snap cell")
    report.expect(document.note(ids[0]).map {
        Int($0.tick) == g.tick && Int($0.duration) == g.duration
    } == true, cppID: id, message: "boundary-right drag leaves first note unchanged")
    report.expect(resizeUndoTo(planted, session: session)
                      && (try? document.captureSave().bytes) == before,
                  cppID: id, message: "Undo restores the planted abutting pair MIDI bytes")
}
@MainActor
private func checkResizeHoverCursor(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::resizeOffGrid"
    let document = session.document
    let start = document.history.currentIdentity
    defer { _ = resizeUndoTo(start, session: session); session.clearSelectedNotes() }
    let grid = resizeGrid(session)
    guard let d = resizeFreeCell(grid, session: session, firstProbe: 88) else {
        report.fail(id, "no free grid cell for the hover cursor")
        return
    }
    let span = 4 * d.duration
    let clash = session.document.notes(in: grid.trackIndex).contains {
        Int($0.pitch) == d.pitch && Int($0.tick) < d.tick + span
            && Int($0.tick) + Int($0.duration) > d.tick
    }
    guard !clash else {
        report.fail(id, "no free four-cell span for the hover cursor")
        return
    }
    guard let noteID = try? document.addNotes([
        NewNote(track: grid.trackIndex, tick: Tick(d.tick), pitch: UInt8(d.pitch),
                duration: Tick(span), velocity: 100)
    ]).first else {
        report.fail(id, "hover-cursor note could not be planted")
        return
    }
    grid.refreshFromSession()
    guard let rect = resizeHandle(noteID, grid: grid), rect.width >= 16 else {
        report.fail(id, "hover-cursor note is not projected wide enough")
        return
    }
    let y = rect.y + rect.height / 2
    grid.updateHover(x: rect.x + rect.width - 1, y: y)
    report.expect(grid.cursorKind == 3, cppID: id,
                  message: "the right edge grip publishes the horizontal resize cursor")
    grid.updateHover(x: rect.x, y: y)
    report.expect(grid.cursorKind == 3, cppID: id,
                  message: "the left edge grip publishes the horizontal resize cursor")
    grid.updateHover(x: rect.x + rect.width / 2, y: y)
    report.expect(grid.cursorKind == 0, cppID: id,
                  message: "the note body publishes the arrow cursor")
}
