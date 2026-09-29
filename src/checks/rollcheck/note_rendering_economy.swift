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
          let box = decodedNoteBox(grid, noteID) else {
        report.fail(id, "projection economy fixture has no projected box")
        return
    }
    let scene = grid.scene
    func fills() -> [UInt64: UInt32] {
        Dictionary(
            RollContentProbe(grid).notes.map { ($0.id, $0.fillArgb) },
            uniquingKeysWith: { first, _ in first })
    }
    func frame() -> (display: Int, bytes: Data) {
        (scene.displayRevision, scene.displayList(list: 0))
    }
    func untouched(since revision: Int, content: Data) -> Bool {
        scene.contentRevision == revision && scene.drawingContent() == content
    }
    session.clearSelectedNotes()
    grid.refreshCamera()
    let fillsBefore = fills()
    let revisionBefore = scene.contentRevision
    let frameBefore = frame()
    let summaryBefore = grid.fetchNoteSummary()
    session.setSelectedNotes([noteID])
    grid.refreshCamera()
    report.expect(
        fills() == fillsBefore && scene.contentRevision == revisionBefore + 1
            && frame().display == frameBefore.display + 1,
                  cppID: id,
        message: "a selection-only refresh repacks the content once with unchanged fills and one new plot frame")
    report.expect(
        session.selectedNotes.contains(noteID)
            && !RollContentProbe(grid).ringRects(noteID).isEmpty,
                  cppID: id,
                  message: "a selection-only refresh still republishes the selection ring")
    report.expect(grid.fetchNoteSummary() != summaryBefore,
                  cppID: id,
                  message: "a selection-content change is visible in the pulled note summary")
    let revisionSelected = scene.contentRevision
    let contentSelected = scene.drawingContent()
    let frameSelected = frame()
    let keyboardBefore = scene.displayList(list: 1)
    let summarySelected = grid.fetchNoteSummary()
    grid.updateHover(x: 4, y: box.y + box.h / 2)
    grid.refreshCamera()
    report.expect(
        untouched(since: revisionSelected, content: contentSelected)
            && frame().bytes == frameSelected.bytes,
                  cppID: id,
        message: "a hover-only refresh republishes no content boxes or fills and leaves the plot frame byte-identical")
    report.expect(
        frame().display == frameSelected.display + 1
            && scene.displayList(list: 1) != keyboardBefore,
                  cppID: id,
        message: "a hover-only refresh rebuilds only the keyboard frame for the highlight")
    report.expect(grid.fetchNoteSummary() == summarySelected,
                  cppID: id,
                  message: "a hover-only refresh leaves the pulled note summary byte-identical")
    grid.clearKeyboardHover()
    session.clearSelectedNotes()
    grid.refreshCamera()
    let fillsPlain = fills()
    let revisionPlain = scene.contentRevision
    let framePlain = frame()
    let summaryPlain = grid.fetchNoteSummary()
    let startTick = Tick(max(0, Int(note.tick) - 2))
    let endTick = Tick(Int(note.tick) + Int(note.duration) + 2)
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: startTick, endTick: endTick),
        scope: .tracks([grid.trackIndex])))
    grid.refreshCamera()
    report.expect(
        fills() == fillsPlain && scene.contentRevision == revisionPlain + 1
            && frame().display == framePlain.display + 1,
                  cppID: id,
        message: "a highlight-only refresh repacks the content once with unchanged fills and one new plot frame")
    report.expect(grid.fetchNoteSummary() == summaryPlain,
                  cppID: id,
                  message: "a highlight-only refresh leaves the pulled note summary byte-identical")
    report.expect(
        !RollContentProbe(grid).ringRects(noteID).isEmpty,
                  cppID: id,
                  message: "a highlight-only refresh still rings the time-covered note")
    session.clearTimeSelection()
    grid.refreshCamera()
    let revisionBeforeScroll = scene.contentRevision
    let contentBeforeScroll = scene.drawingContent()
    let frameBeforeScroll = frame()
    let fillsBeforeScroll = fills()
    let summaryBeforeScroll = grid.fetchNoteSummary()
    let scrolledX = session.camera.snapshot.scrollX
    session.mutateCamera { _ = $0.scrollByPx(10) }
    guard session.camera.snapshot.scrollX != scrolledX else {
        report.fail(id, "projection economy fixture could not scroll the camera")
        return
    }
    grid.refreshCamera()
    let scrolledCamera = session.camera
    let scrolledX0 = scrolledCamera.viewX(
        tick: Double(note.tick), dpr: grid.devicePixelRatio)
    let scrolledX1 = scrolledCamera.viewX(
        tick: Double(note.tick + note.duration), dpr: grid.devicePixelRatio)
    let scrolledExpected = grid.metrics.noteBox(
        camera: scrolledCamera, x0: scrolledX0, x1: scrolledX1,
        pitch: Int(note.pitch))
    let scrolledFace = decodedNoteBox(grid, noteID)
    let scrolledSnap = scrolledCamera.snapshot
    let clipX = max(0, scrolledExpected.x)
    let clipY = max(0, scrolledExpected.y)
    let clipW = min(
        scrolledExpected.x + scrolledExpected.w, scrolledSnap.viewportWidth) - clipX
    let clipH = min(
        scrolledExpected.y + scrolledExpected.h, scrolledSnap.rollHeight) - clipY
    report.expect(
        scrolledFace.map {
            renderingNear($0.x, clipX) && renderingNear($0.y, clipY)
                && renderingNear($0.w, clipW) && renderingNear($0.h, clipH)
        } == true, cppID: id,
        message: "the camera-translated note position matches the projected viewport position")
    report.expect(
        untouched(since: revisionBeforeScroll, content: contentBeforeScroll)
            && fills() == fillsBeforeScroll,
        cppID: id,
        message: "an in-window camera scroll republishes no content boxes or fills")
    report.expect(
        frame().display != frameBeforeScroll.display
            && frame().bytes != frameBeforeScroll.bytes,
        cppID: id,
        message: "an in-window camera scroll rebuilds the display frames with fresh list bytes")
    report.expect(grid.fetchNoteSummary() == summaryBeforeScroll,
                  cppID: id,
                  message: "a camera-only refresh leaves the pulled note summary byte-identical")
    _ = session.mutateCamera { _ = $0.setTimeZoom(70) }
    grid.refreshCamera()
    report.expect(
        untouched(since: revisionBeforeScroll, content: contentBeforeScroll)
            && frame().display != frameBeforeScroll.display,
        cppID: id,
        message: "a camera zoom leaves the content revision and blob untouched while the plot frame moves")
    session.mutateCamera { _ = $0.setKeyHeight(20) }
    grid.refreshCamera()
    report.expect(
        untouched(since: revisionBeforeScroll, content: contentBeforeScroll)
            && frame().display != frameBeforeScroll.display,
        cppID: id,
        message: "a key-height change leaves the content revision and blob untouched while the plot frame moves")
}

/// The plot frame culls off-screen notes in O(visible): thousands of far
/// notes decode to no fill rects, and doubling them changes nothing.
@MainActor
func checkRollPlotCullBound(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::plotCullBound"
    let oldCamera = session.camera
    let grid = PianoGrid(session: session)
    defer { session.mutateCamera { $0 = oldCamera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let visibleID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    var stagedIDs: [NoteID] = [visibleID]
    defer { session.document.deleteNotes(stagedIDs) }
    func stageOffscreen(count: Int, base: Int) -> Bool {
        var staged: [NewNote] = []
        staged.reserveCapacity(count)
        for i in 0..<count {
            staged.append(NewNote(
                track: grid.trackIndex, tick: Tick(base + i * 48),
                pitch: UInt8(24 + (i % 80)), duration: Tick(24), velocity: 100))
        }
        guard let added = try? session.document.addNotes(staged) else { return false }
        stagedIDs.append(contentsOf: added)
        grid.refreshFromSession()
        return true
    }
    guard stageOffscreen(count: 2000, base: 500_000) else {
        report.fail(id, "cull fixture could not stage its off-screen notes")
        return
    }
    func projectedBox(tick: Int, duration: Int, pitch: Int)
        -> (x: Double, y: Double, w: Double, h: Double)?
    {
        let camera = session.camera
        guard camera.projection.row(forPitch: pitch) != PitchProjection.hiddenRow else { return nil }
        let row = camera.projection.row(forPitch: pitch)
        let snapshot = camera.snapshot
        guard let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio),
              let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio),
              bottom > 0 && top < snapshot.rollHeight
        else { return nil }
        let x0 = camera.viewX(tick: Double(tick), dpr: grid.devicePixelRatio)
        let x1 = camera.viewX(tick: Double(tick + duration), dpr: grid.devicePixelRatio)
        return grid.metrics.noteBox(camera: camera, x0: x0, x1: x1, pitch: pitch)
    }
    func audit() -> (plotted: Set<UInt64>, expected: Set<UInt64>, fills: Int, rects: Int)? {
        let probe = RollContentProbe(grid)
        guard !probe.plotRects.isEmpty else { return nil }
        var plotted = Set<UInt64>()
        var fills = 0
        var seen = Set<UInt64>()
        for rect in probe.plotRects where rect.id != 0 && rect.id < RollContentProbe.loopStartId {
            plotted.insert(rect.id)
            if seen.insert(rect.id).inserted { fills += 1 }
        }
        let snapshot = session.camera.snapshot
        var expected = Set<UInt64>()
        for track in 0..<session.document.engineTracks.usedTrackCount {
            for note in session.document.notes(in: track) {
                guard let box = projectedBox(
                    tick: Int(note.tick), duration: Int(note.duration),
                    pitch: Int(note.pitch)),
                      box.x + box.w > 0 && box.x < snapshot.viewportWidth
                else { continue }
                expected.insert(note.id.rawValue)
            }
        }
        return (plotted, expected, fills, probe.plotRects.count)
    }
    guard let first = audit() else {
        report.fail(id, "cull fixture decoded no plot rects")
        return
    }
    report.expect(
        !first.expected.isEmpty && first.expected == first.plotted, cppID: id,
        message: "the plotted fill set equals the viewport-visible notes")
    report.expect(
        first.fills == first.expected.count, cppID: id,
        message: "the plotted fill count matches the visible note count")
    report.expect(
        RollContentProbe(grid).plotRects.contains { $0.id == 0 }, cppID: id,
        message: "the culled frame still plots its grid lines")
    guard stageOffscreen(count: 2000, base: 700_000) else {
        report.fail(id, "cull fixture could not double its off-screen notes")
        return
    }
    guard let second = audit() else {
        report.fail(id, "cull fixture decoded no plot rects after doubling")
        return
    }
    report.expect(
        second.fills == first.fills && second.plotted == first.plotted
            && second.rects == first.rects, cppID: id,
        message: "doubling the off-screen notes leaves the plotted frame unchanged")
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
