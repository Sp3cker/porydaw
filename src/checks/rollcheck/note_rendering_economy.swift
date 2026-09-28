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
    let scene = grid.scene
    func fills() -> [UInt64: UInt32] {
        Dictionary(
            RollContentProbe(scene).notes.map { ($0.id, $0.fillArgb) },
            uniquingKeysWith: { first, _ in first })
    }
    func untouched(since revision: Int, content: Data) -> Bool {
        scene.contentRevision == revision && scene.drawingContent() == content
    }
    session.clearSelectedNotes()
    grid.refreshCamera()
    let fillsBefore = fills()
    let revisionBefore = scene.contentRevision
    let summaryBefore = grid.fetchNoteSummary()
    session.setSelectedNotes([noteID])
    grid.refreshCamera()
    report.expect(
        fills() == fillsBefore && scene.contentRevision == revisionBefore + 1,
                  cppID: id,
        message: "a selection-only refresh repacks the content once with unchanged fills")
    report.expect(
        RollContentProbe(scene).note(noteID)?.selected == true,
                  cppID: id,
                  message: "a selection-only refresh still republishes the selection ring")
    report.expect(grid.fetchNoteSummary() != summaryBefore,
                  cppID: id,
                  message: "a selection-content change is visible in the pulled note summary")
    let revisionSelected = scene.contentRevision
    let contentSelected = scene.drawingContent()
    let summarySelected = grid.fetchNoteSummary()
    let hoverPoint = viewportPoint(grid, x: box.x, y: box.y + box.h / 2)
    grid.updateHover(x: 4, y: hoverPoint.y)
    grid.refreshCamera()
    report.expect(
        untouched(since: revisionSelected, content: contentSelected),
                  cppID: id,
                  message: "a hover-only refresh reuses the published fills with no box or fill work")
    report.expect(grid.fetchNoteSummary() == summarySelected,
                  cppID: id,
                  message: "a hover-only refresh leaves the pulled note summary byte-identical")
    grid.clearKeyboardHover()
    session.clearSelectedNotes()
    grid.refreshCamera()
    let fillsPlain = fills()
    let revisionPlain = scene.contentRevision
    let summaryPlain = grid.fetchNoteSummary()
    let startTick = Tick(max(0, Int(note.tick) - 2))
    let endTick = Tick(Int(note.tick) + Int(note.duration) + 2)
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: startTick, endTick: endTick),
        scope: .tracks([grid.trackIndex])))
    grid.refreshCamera()
    report.expect(
        fills() == fillsPlain && scene.contentRevision == revisionPlain + 1,
                  cppID: id,
        message: "a highlight-only refresh repacks the content once with unchanged fills")
    report.expect(grid.fetchNoteSummary() == summaryPlain,
                  cppID: id,
                  message: "a highlight-only refresh leaves the pulled note summary byte-identical")
    report.expect(
        RollContentProbe(scene).note(noteID)?.timeCovered == true,
                  cppID: id,
                  message: "a highlight-only refresh still rings the time-covered note")
    session.clearTimeSelection()
    grid.refreshCamera()
    let revisionBeforeScroll = scene.contentRevision
    let contentBeforeScroll = scene.drawingContent()
    let summaryBeforeScroll = grid.fetchNoteSummary()
    let scrolledX = session.camera.snapshot.scrollX
    session.mutateCamera { _ = $0.scrollByPx(10) }
    guard session.camera.snapshot.scrollX != scrolledX else {
        report.fail(id, "projection economy fixture could not scroll the camera")
        return
    }
    grid.refreshCamera()
    let record = RollContentProbe(scene).note(noteID)
    let contentBox = record.flatMap {
        contentNoteBox(
            grid, session: session, tick: $0.tick, end: $0.tick + $0.duration,
            pitch: $0.pitch)
    }
    let cameraBox = grid.projectedNoteBox(
        tick: Int(note.tick), end: Int(note.tick + note.duration),
        pitch: Int(note.pitch))
    let matchesCamera: Bool
    if let contentBox, let cameraBox, grid.cameraScrollX == session.camera.snapshot.scrollX {
        let viewport = viewportPoint(grid, x: contentBox.x, y: contentBox.y)
        matchesCamera = renderingNear(viewport.x, cameraBox.x)
            && renderingNear(viewport.y, cameraBox.y)
    } else {
        matchesCamera = false
    }
    report.expect(matchesCamera, cppID: id,
                  message: "the camera-translated note position matches the projected viewport position")
    report.expect(
        untouched(since: revisionBeforeScroll, content: contentBeforeScroll),
                  cppID: id,
                  message: "an in-window camera scroll republishes no note boxes or fills")
    report.expect(grid.fetchNoteSummary() == summaryBeforeScroll,
                  cppID: id,
                  message: "a camera-only refresh leaves the pulled note summary byte-identical")
    _ = session.mutateCamera { _ = $0.setTimeZoom(70) }
    grid.refreshCamera()
    report.expect(
        untouched(since: revisionBeforeScroll, content: contentBeforeScroll),
        cppID: id,
        message: "a camera zoom leaves the content revision and blob untouched")
    session.mutateCamera { _ = $0.setKeyHeight(20) }
    grid.refreshCamera()
    report.expect(
        untouched(since: revisionBeforeScroll, content: contentBeforeScroll),
        cppID: id,
        message: "a key-height change leaves the content revision and blob untouched")
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
