import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func checkProjectionEconomy(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectedNoteFrameRaster"
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let grid = PianoGrid(session: session)
    defer {
        session.clearTimeSelection()
        grid.clearKeyboardHover()
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
    guard let note = session.document.note(noteID),
          let box = noteBox(grid, session: session, note: note) else {
        report.fail(id, "projection economy fixture has no projected box")
        return
    }
    func fillSnapshot() -> [String] {
        (0..<grid.scene.pianoNoteFills.count).map { index in
            let rect = grid.scene.pianoNoteFills[index]
            return "\(rect.primitiveName)|\(rect.x)|\(rect.y)"
                + "|\(rect.width)|\(rect.height)|\(rect.fillColor)"
        }
    }
    let ring = 3.0 / grid.devicePixelRatio
    session.clearSelectedNotes()
    grid.refreshCamera()
    grid.scene.boxesProjected = 0
    grid.scene.fillWrites = 0
    grid.noteSummaryRebuilds = 0
    let fillsBefore = fillSnapshot()
    let summaryBefore = grid.noteSummary
    session.setSelectedNotes([noteID])
    grid.refreshCamera()
    report.expect(fillSnapshot() == fillsBefore
                      && grid.scene.boxesProjected == 0 && grid.scene.fillWrites == 0,
                  cppID: id,
                  message: "a selection-only refresh reuses the published fills with no box or fill work")
    report.expect(hasFrame(grid.scene.pianoNoteBordersAndSelection, box: box, inset: 0,
                           thickness: ring, color: grid.palette.selectionRing),
                  cppID: id,
                  message: "a selection-only refresh still republishes the selection ring")
    report.expect(grid.noteSummaryRebuilds > 0 && grid.noteSummary != summaryBefore,
                  cppID: id,
                  message: "a selection-content change still rebuilds the note summary")
    grid.scene.boxesProjected = 0
    grid.scene.fillWrites = 0
    grid.noteSummaryRebuilds = 0
    let fillsSelected = fillSnapshot()
    let summarySelected = grid.noteSummary
    let hoverPoint = viewportPoint(grid, x: box.x, y: box.y + box.h / 2)
    grid.updateHover(x: 4, y: hoverPoint.y)
    grid.refreshCamera()
    report.expect(fillSnapshot() == fillsSelected
                      && grid.scene.boxesProjected == 0 && grid.scene.fillWrites == 0,
                  cppID: id,
                  message: "a hover-only refresh reuses the published fills with no box or fill work")
    report.expect(grid.noteSummary == summarySelected && grid.noteSummaryRebuilds == 0,
                  cppID: id,
                  message: "a hover-only refresh leaves the note summary byte-identical with no rebuild")
    grid.clearKeyboardHover()
    session.clearSelectedNotes()
    grid.refreshCamera()
    grid.scene.boxesProjected = 0
    grid.scene.fillWrites = 0
    grid.noteSummaryRebuilds = 0
    let fillsPlain = fillSnapshot()
    let summaryPlain = grid.noteSummary
    let startTick = Tick(max(0, Int(note.tick) - 2))
    let endTick = Tick(Int(note.tick) + Int(note.duration) + 2)
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: startTick, endTick: endTick),
        scope: .tracks([grid.trackIndex])))
    grid.refreshCamera()
    report.expect(fillSnapshot() == fillsPlain
                      && grid.scene.boxesProjected == 0 && grid.scene.fillWrites == 0,
                  cppID: id,
                  message: "a highlight-only refresh reuses the published fills with no box or fill work")
    report.expect(grid.noteSummary == summaryPlain && grid.noteSummaryRebuilds == 0,
                  cppID: id,
                  message: "a highlight-only refresh leaves the note summary byte-identical with no rebuild")
    report.expect(hasFrame(grid.scene.pianoNoteBordersAndSelection, box: box, inset: 0,
                           thickness: ring, color: grid.palette.selectionRing),
                  cppID: id,
                  message: "a highlight-only refresh still rings the time-covered note")
    session.clearTimeSelection()
    grid.scene.boxesProjected = 0
    grid.scene.fillWrites = 0
    grid.noteSummaryRebuilds = 0
    let fillsBeforeScroll = fillSnapshot()
    let summaryBeforeScroll = grid.noteSummary
    let scrolledX = session.camera.snapshot.scrollX
    session.mutateCamera { _ = $0.scrollByPx(10) }
    guard session.camera.snapshot.scrollX != scrolledX else {
        report.fail(id, "projection economy fixture could not scroll the camera")
        return
    }
    grid.refreshCamera()
    let publishedNote = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                      in: grid.scene.pianoNoteFills)
    let cameraBox = grid.projectedNoteBox(
        tick: Int(note.tick), end: Int(note.tick + note.duration),
        pitch: Int(note.pitch))
    let matchesCamera: Bool
    if let publishedNote, let cameraBox {
        let viewport = viewportPoint(grid, x: publishedNote.x, y: publishedNote.y)
        matchesCamera = renderingNear(viewport.x, cameraBox.x)
            && renderingNear(viewport.y, cameraBox.y)
    } else {
        matchesCamera = false
    }
    report.expect(matchesCamera, cppID: id,
                  message: "the camera-translated note position matches the projected viewport position")
    report.expect(fillSnapshot() == fillsBeforeScroll
                      && grid.scene.boxesProjected == 0 && grid.scene.fillWrites == 0,
                  cppID: id,
                  message: "an in-window camera scroll republishes no note boxes or fills")
    report.expect(grid.noteSummary == summaryBeforeScroll && grid.noteSummaryRebuilds == 0,
                  cppID: id,
                  message: "a camera-only refresh leaves the note summary byte-identical with no rebuild")
}

@MainActor
func checkRulerSweepSingleTrackScope(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let priorTrack = session.selectedTrack
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer {
        automation.clearTimeSelection()
        automation.detach()
        session.clearSelectedNotes()
        session.setSelectedNotes(priorSelection)
        session.selectedTrack = priorTrack
        session.mutateCamera { $0 = oldCamera }
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    if session.selectedTrack == nil { session.selectPrimaryTrack(0) }
    grid.refreshFromSession()
    let primary = session.selectedTrack ?? grid.trackIndex
    let cell = max(1, grid.snapTicks)
    let anchor = Tick(grid.snapTickDown(Double(72)))
    var farTick = anchor + Tick(cell * 4)
    var alignSteps = 0
    while Tick(grid.snapTickDown(Double(farTick))) != farTick && alignSteps < 1024 {
        farTick = farTick + 1
        alignSteps += 1
    }
    let document = session.document
    report.expect(document.canAddTrack, cppID: id, message: "the sweep fixture can provision the intersecting other-track note")
    guard document.canAddTrack, let other = document.addTrack(voice: 0), other != primary,
          let overlapIDs = try? document.addNotes([NewNote(
              track: other, tick: anchor, pitch: 60,
              duration: Tick(cell * 4), velocity: 90)]), !overlapIDs.isEmpty else {
        return
    }
    defer {
        _ = document.history.undoDocument()
        _ = document.history.undoDocument()
    }
    let revision = document.revision
    automation.clearTimeSelection()
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    defer { menu.cancelSweep(); menu.close() }
    menu.beginSweep(contentX: session.camera.contentX(tick: Double(anchor)), pointerY: 0)
    menu.updateSweep(contentX: session.camera.contentX(tick: Double(farTick)))
    guard let swept = automation.selection, swept.isActive else {
        report.fail(id, "a plain ruler sweep published no time selection")
        return
    }
    report.expect(swept.range == TimeRange(startTick: anchor, endTick: farTick)
                      && swept.scope == .tracks([primary]),
                  cppID: id,
                  message: "a plain sweep keeps the primary-only scope with an intersecting other-track note")
    report.expect(document.revision == revision,
                  cppID: id,
                  message: "a plain sweep publishes its range without a document write")
}
