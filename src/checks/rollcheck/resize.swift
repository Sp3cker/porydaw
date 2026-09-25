import Foundation
@testable import PorydawApp
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
    checkEdgeResize(report, session: session)
}

private struct ResizeCell {
    let tick: Int
    let duration: Int
    let pitch: Int
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
    let grid = makeCameraGrid(session: session)
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
    let grid = makeCameraGrid(session: session)
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
    let grid = makeCameraGrid(session: session)
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
    let grid = makeCameraGrid(session: session)
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
    let grid = makeCameraGrid(session: session)
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

@MainActor
private func checkEdgeResize(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/EditorGridCamera::edgeResize"
    let setupGrid = makeCameraGrid(session: session)
    let snap = max(1, setupGrid.snapTicks)
    let track = setupGrid.trackIndex
    var freePitch = -1
    pitchScan: for candidateY in stride(from: 300.0, through: 20.0, by: -20) {
        guard let candidate = session.camera.projection.pitch(
            atY: candidateY, keyHeight: session.camera.snapshot.keyHeight,
            scrollY: session.camera.snapshot.scrollY, dpr: setupGrid.devicePixelRatio)
        else { continue }
        let occupied = session.document.notes(in: track).contains { note in
            Int(note.pitch) == candidate
                && Int(note.tick) < 280 && Int(note.tick) + Int(note.duration) > 0
        }
        if !occupied {
            freePitch = candidate
            break pitchScan
        }
    }
    guard freePitch >= 0,
        let added = try? session.document.addNotes([
            NewNote(track: track, tick: 24, pitch: UInt8(freePitch),
                    duration: Tick(12 + snap / 4), velocity: 80),
            NewNote(track: track, tick: 96, pitch: UInt8(freePitch),
                    duration: 12, velocity: 80)
        ]), added.count == 2 else {
        report.fail(id, "edge-resize fixture could not seed a free row")
        return
    }
    defer {
        session.document.deleteNotes(
            added.filter { session.document.note($0) != nil })
    }
    let grid = makeCameraGrid(session: session)
    let a = added[0], b = added[1]
    func rect(_ id: NoteID) -> SceneRect? {
        firstRect(named: "gridNote_\(id.rawValue)", in: grid.scene.pianoNoteFills)
    }
    guard let aRect = rect(a) else {
        report.fail(id, "edge-resize fixture note is not projected")
        return
    }
    let rowY = aRect.y + aRect.height / 2
    // The native case starts at 1.25 cells and releases at 1.9 cells,
    // which must snap the right edge to the second lattice line.
    let pullX = session.camera.displayX(
        tick: 24 + 1.9 * Double(snap), origin: 0, dpr: grid.devicePixelRatio)
    grid.beginPointer(x: aRect.x + aRect.width - 1, y: rowY, modifiers: 0)
    grid.updatePointer(x: pullX, y: rowY)
    grid.endPointer(x: pullX, y: rowY)
    report.expect(
        session.document.note(a).map { Int($0.duration) == 2 * snap } == true,
        cppID: id, message: "off-grid right-edge drag snaps the end to the ruler grid")
    let quarterPx = Double(snap) * session.camera.snapshot.pixelsPerTick / 4
    // Overshoot trailing drag: pull the right edge before the note start; the
    // commit clamps the duration at one snap cell.
    guard let aRect2 = rect(a) else {
        report.fail(id, "resized fixture note is not projected")
        return
    }
    let overshootX = session.camera.displayX(
        tick: 0, origin: 0, dpr: grid.devicePixelRatio)
    grid.beginPointer(x: aRect2.x + aRect2.width - 1, y: rowY, modifiers: 0)
    grid.updatePointer(x: overshootX, y: rowY)
    grid.endPointer(x: overshootX, y: rowY)
    report.expect(
        session.document.note(a).map { Int($0.duration) == snap } == true,
        cppID: id, message: "overshot right-edge drag stops at one snap cell")
    // Leading-edge drag: pull the left edge three quarters of a cell backward;
    // the commit snaps the start to the lattice and preserves the end tick.
    guard let aRect3 = rect(a) else {
        report.fail(id, "collapsed fixture note is not projected")
        return
    }
    grid.beginPointer(x: aRect3.x + 1, y: rowY, modifiers: 0)
    grid.updatePointer(x: aRect3.x + 1 - 3 * quarterPx, y: rowY)
    grid.endPointer(x: aRect3.x + 1 - 3 * quarterPx, y: rowY)
    report.expect(
        session.document.note(a).map {
            Int($0.tick) == 24 - snap && Int($0.duration) == 2 * snap
        } == true,
        cppID: id, message: "leading-edge drag snaps the start back one cell and keeps the end")
    // Ctrl+edge: a stationary Ctrl press joins the note to the selection
    // without resizing; the drag then resizes every selected note.
    session.setSelectedNotes([a])
    guard let bRect = rect(b) else {
        report.fail(id, "second fixture note is not projected")
        return
    }
    let bEdgeX = bRect.x + bRect.width - 1
    let bRowY = bRect.y + bRect.height / 2
    grid.beginPointer(x: bEdgeX, y: bRowY, modifiers: 0x0400_0000)
    grid.endPointer(x: bEdgeX, y: bRowY)
    report.expect(
        session.selectedNotes == Set([a, b])
            && session.document.note(b).map { Int($0.duration) == 12 } == true,
        cppID: id, message: "stationary Ctrl+edge click joins the note without resizing")
    grid.beginPointer(x: bEdgeX, y: bRowY, modifiers: 0x0400_0000)
    grid.updatePointer(x: bEdgeX + Double(snap) * session.camera.snapshot.pixelsPerTick,
                       y: bRowY)
    grid.endPointer(x: bEdgeX + Double(snap) * session.camera.snapshot.pixelsPerTick,
                    y: bRowY)
    report.expect(
        session.document.note(b).map { Int($0.duration) == 12 + snap } == true
            && session.document.note(a).map {
                Int($0.tick) + Int($0.duration) == 24 + 2 * snap
            } == true,
        cppID: id, message: "Ctrl+edge drag resizes the grabbed note and the joined selection")
    // Abutting boundary: a press just left of the shared boundary grips the
    // left note's trailing edge; just right grips the right note's leading edge.
    guard let cPair = try? session.document.addNotes([
        NewNote(track: track, tick: 240, pitch: UInt8(freePitch),
                duration: 12, velocity: 80),
        NewNote(track: track, tick: 252, pitch: UInt8(freePitch),
                duration: 12, velocity: 80)
    ]), cPair.count == 2 else {
        report.fail(id, "abutting fixture could not seed the pair")
        return
    }
    defer {
        session.document.deleteNotes(
            cPair.filter { session.document.note($0) != nil })
    }
    let abuttingGrid = PianoGrid(session: session)
    abuttingGrid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let leftRect = firstRect(
        named: "gridNote_\(cPair[0].rawValue)", in: abuttingGrid.scene.pianoNoteFills)
    else {
        report.fail(id, "abutting fixture notes are not projected")
        return
    }
    let boundary = session.camera.displayX(
        tick: 252, origin: 0, dpr: grid.devicePixelRatio)
    let boundaryY = leftRect.y + leftRect.height / 2
    abuttingGrid.beginPointer(x: boundary - 1.6, y: boundaryY, modifiers: 0)
    abuttingGrid.updatePointer(
        x: boundary - 1.6 - Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    abuttingGrid.endPointer(
        x: boundary - 1.6 - Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    report.expect(
        session.document.note(cPair[0]).map { Int($0.duration) == 12 - snap } == true
            && session.document.note(cPair[1]).map {
                Int($0.tick) == 252 && Int($0.duration) == 12
            } == true,
        cppID: id, message: "boundary-left drag resizes the left note's end only")
    abuttingGrid.beginPointer(x: boundary + 1.6, y: boundaryY, modifiers: 0)
    abuttingGrid.updatePointer(
        x: boundary + 1.6 + Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    abuttingGrid.endPointer(
        x: boundary + 1.6 + Double(snap) * session.camera.snapshot.pixelsPerTick,
        y: boundaryY)
    report.expect(
        session.document.note(cPair[1]).map {
            Int($0.tick) == 252 + snap && Int($0.duration) == 12 - snap
        } == true
            && session.document.note(cPair[0]).map {
                Int($0.tick) == 240 && Int($0.duration) == 12 - snap
            } == true,
        cppID: id, message: "boundary-right drag resizes the right note's start only")
}
