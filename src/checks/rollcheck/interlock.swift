import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func runInterlockChecks(_ report: CheckReport, session: DocumentSession) {
    checkGestureInterlock(report, session: session)
}

@MainActor
private func checkGestureInterlock(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRollTest::gestureInterlock"
    let initialSelection = session.selectedNoteOrder
    let setup = PianoGrid(session: session)
    setup.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    setup.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    let camera = session.camera
    let aTick = setup.snapTickDown(camera.tickAtContentX(40))
    let duration = setup.gridCell(at: aTick).duration
    let bTick = stride(from: 64.0, through: 560.0, by: 24.0).lazy
        .map { setup.snapTickDown(camera.tickAtContentX($0)) }
        .first { $0 >= aTick + 2 * duration } ?? -1
    let pitch = [160.0, 200, 120, 240, 80].compactMap { y in
        camera.projection.pitch(atY: y, keyHeight: camera.snapshot.keyHeight,
                                scrollY: camera.snapshot.scrollY, dpr: setup.devicePixelRatio)
    }.first { candidate in
        !session.document.notes(in: setup.trackIndex).contains { note in
            Int(note.pitch) == candidate &&
                ((Int(note.tick) < aTick + duration && Int(note.tick + note.duration) > aTick) ||
                 (Int(note.tick) < bTick + duration && Int(note.tick + note.duration) > bTick))
        }
    }
    let seeded: [NoteID]?
    if let pitch, bTick >= aTick + duration {
        seeded = try? session.document.addNotes([
            NewNote(track: setup.trackIndex, tick: Tick(aTick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: 100),
            NewNote(track: setup.trackIndex, tick: Tick(bTick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: 73)
        ])
    } else {
        seeded = nil
    }
    report.expect(seeded?.count == 2, cppID: id,
                  message: "A001 velocity fixture seeds notes A and B")
    guard let seeded, seeded.count == 2 else { return }
    defer {
        session.clearSelectedNotes()
        _ = session.document.history.undoDocument()
        session.setSelectedNotes(initialSelection)
    }
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    guard let a = interlockRect(seeded[0], in: grid.scene.pianoNoteFills),
          let b = interlockRect(seeded[1], in: grid.scene.pianoNoteFills),
          let beforeSlot = try? session.document.captureSave().bytes else {
        report.fail(id, "gesture-interlock notes were not projected or serialized")
        return
    }
    let ax = a.x + a.width / 2, ay = a.y + a.height / 2
    let bx = b.x + b.width / 2, by = b.y + b.height / 2
    let bandX = max(ax, bx) + 4, bandY = max(ay, by) + 4
    let beyondBX = bx + (bx < ax ? -4.0 : 4.0)
    let beyondAX = ax + (ax < bx ? -4.0 : 4.0)
    let freeX = [400.0, 500, 550, 600].first { x in
        !(0..<grid.scene.pianoNoteFills.count).contains { index in
            let rect = grid.scene.pianoNoteFills[index]
            return rect.x <= x && x < rect.x + rect.width &&
                rect.y <= ay && ay < rect.y + rect.height
        }
    }
    report.expect(freeX != nil, cppID: id, message: "A002 free draw cell exists")
    guard let freeX else { return }

    let undoSlot = session.document.history.undoIndex
    func snapshot() -> (bytes: [UInt8]?, index: Int, count: Int) {
        (try? session.document.captureSave().bytes,
         session.document.history.undoIndex, session.document.history.undoCount)
    }
    func unchanged(_ before: (bytes: [UInt8]?, index: Int, count: Int)) -> Bool {
        before.bytes != nil && (try? session.document.captureSave().bytes) == before.bytes &&
            session.document.history.undoIndex == before.index &&
            session.document.history.undoCount == before.count
    }
    func containsAB() -> Bool {
        session.selectedNotes.contains(seeded[0]) && session.selectedNotes.contains(seeded[1])
    }
    var timeSelection: AutomationTimeSelection?
    grid.timeSelectionSource = { timeSelection }
    grid.onClearTimeSelection = { timeSelection = nil }
    var committedTicks: [Tick] = []
    grid.onCommitCursor = { committedTicks.append($0) }
    func clearSelection() {
        session.clearSelectedNotes()
    }

    clearSelection()
    timeSelection = AutomationTimeSelection(
        range: TimeRange(startTick: Tick(aTick), endTick: Tick(aTick + duration)),
        scope: .tracks([grid.trackIndex]))
    do {
        let before = snapshot()
        grid.beginPointer(x: ax, y: ay, modifiers: 0)
        grid.updatePointer(x: ax, y: ay - grid.rowHeight)
        grid.beginRightPointer(x: 1, y: 0)
        grid.updateRightPointer(x: bandX, y: bandY)
        grid.endRightPointer(x: bandX, y: bandY)
        report.expect(session.selectedNoteOrder.isEmpty && !grid.interactionActive
                      && timeSelection == nil,
                      cppID: id, message: "A003 blocked right click clears notes and time selection")
        grid.endPointer(x: bandX, y: bandY)
        report.expect(unchanged(before), cppID: id,
                      message: "A004 aborted left Move preserves MIDI bytes and undo history")
    }

    clearSelection()
    timeSelection = AutomationTimeSelection(
        range: TimeRange(startTick: Tick(aTick), endTick: Tick(aTick + duration)),
        scope: .tracks([grid.trackIndex]))
    do {
        let before = snapshot()
        grid.beginRightPointer(x: 1, y: 0)
        grid.updateRightPointer(x: grid.dragDistance + 2, y: 0)
        grid.beginPointer(x: ax, y: ay, modifiers: 0)
        grid.updatePointer(x: beyondBX, y: by + 4)
        grid.endRightPointer(x: beyondBX, y: by + 4)
        report.expect(session.selectedNoteOrder.isEmpty && !grid.interactionActive
                      && timeSelection == nil,
                      cppID: id, message: "A005 demoted right Band clears notes and time selection")
        grid.endPointer(x: beyondBX, y: by + 4)
        report.expect(unchanged(before), cppID: id,
                      message: "A006 demoted Band preserves MIDI bytes and undo history")
    }

    clearSelection()
    do {
        let before = snapshot()
        grid.beginPointer(x: freeX, y: ay, modifiers: 0)
        grid.beginRightPointer(x: 1, y: 0)
        grid.updateRightPointer(x: bandX, y: bandY)
        grid.endRightPointer(x: bandX, y: bandY)
        report.expect(containsAB(), cppID: id,
                      message: "A007 Band selects A and B from PendingDraw")
        grid.endPointer(x: freeX, y: ay)
        report.expect(containsAB(), cppID: id,
                      message: "A008 parked PendingDraw release retains A and B")
        report.expect(committedTicks.last == session.grid.snapTick(
            camera.tickAtContentX(freeX), camera: camera)
            && committedTicks.last == session.editCursor,
            cppID: id, message: "A008 PendingDraw parks the cursor after the right band ends")
        report.expect(unchanged(before), cppID: id,
                      message: "A009 PendingDraw interlock preserves MIDI bytes and undo history")
    }

    clearSelection()
    do {
        let before = snapshot()
        grid.beginRightPointer(x: 1, y: 0)
        grid.updateRightPointer(x: grid.dragDistance + 2, y: 0)
        grid.beginPointer(x: bx, y: by, modifiers: 0x0400_0000)
        grid.endPointer(x: bx, y: by)
        report.expect(session.selectedNoteOrder == [seeded[1]], cppID: id,
                      message: "A010 deferred Ctrl click selects exactly B")
        var bAuditioned = false
        grid.onAudition = { _, key, velocity in
            if key == Int(session.document.note(seeded[1])?.pitch ?? 0), velocity > 0 {
                bAuditioned = true
            }
        }
        grid.updateRightPointer(x: bx + 1, y: by + 1)
        grid.onAudition = nil
        report.expect(bAuditioned, cppID: id,
                      message: "A011 live right Band auditions B above zero velocity")
        grid.updateRightPointer(x: beyondAX, y: ay + 4)
        grid.endRightPointer(x: beyondAX, y: ay + 4)
        report.expect(containsAB(), cppID: id,
                      message: "A012 deferred Ctrl click retains Band token through release")
        report.expect(unchanged(before), cppID: id,
                      message: "A013 deferred modifier interlock preserves bytes and history")
    }

    clearSelection()
    do {
        let before = snapshot()
        for attempt in 0..<2 {
            grid.beginPointer(x: bx, y: by, modifiers: 0x0400_0000)
            grid.updatePointer(x: bx, y: by - grid.dragDistance - 1)
            report.expect(grid.previewVelocity(seeded[1]) != nil, cppID: id,
                          message: attempt == 0 ? "A014 Ctrl velocity drag stages a preview" :
                              "A016 later Ctrl velocity drag stages a preview")
            grid.beginRightPointer(x: 1, y: 0)
            grid.endRightPointer(x: 1, y: 0)
            report.expect(grid.previewVelocity(seeded[1]) == nil, cppID: id,
                          message: attempt == 0 ? "A015 right release aborts velocity preview" :
                              "A017 second right release aborts velocity preview")
            grid.endPointer(x: 1, y: 0)
        }
        report.expect(unchanged(before), cppID: id,
                      message: "A018 velocity aborts preserve MIDI bytes and undo history")
    }
    report.expect(session.document.history.undoIndex == undoSlot, cppID: id,
                  message: "A019 all five interlocks preserve the slot undo index")
    report.expect((try? session.document.captureSave().bytes) == beforeSlot, cppID: id,
                  message: "A020 all five interlocks preserve slot MIDI bytes")
}

@MainActor
private func interlockRect(_ id: NoteID, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == "gridNote_\(id.rawValue)" {
        return model[index]
    }
    return nil
}
