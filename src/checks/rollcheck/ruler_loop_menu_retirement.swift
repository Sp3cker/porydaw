import Foundation
import PorydawApp
import PorydawCore
import PorydawDocument
import PorydawAppCommands

@MainActor
func checkRulerMenuRetirement(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::rulerMenuLiveRetirement"
    let palette = GridPalette()
    let grid = PianoGrid(viewport: viewport, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(viewport: viewport, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(viewport: viewport, grid: grid, automation: automation)
    let oldChange = session.onChange
    session.onChange = { change in
        menu.sessionDidChange(change)
        oldChange?(change)
    }
    defer { session.onChange = oldChange }
    let oldCursor = session.editCursor
    defer { session.editCursor = oldCursor }
    let entryIdentity = session.document.history.currentIdentity
    defer {
        while session.document.history.currentIdentity != entryIdentity
            && session.document.history.canUndo
        {
            guard session.document.history.undoDocument() else { break }
        }
    }
    let track = session.selectedTrack ?? 0
    let seed = try? session.document.addNotes([
        NewNote(track: track, tick: rulerSeedTick, pitch: 60, duration: 6, velocity: 100)
    ])
    report.expect(
        seed?.first.flatMap { session.document.note($0) }.map {
            $0.track == track && $0.tick == rulerSeedTick && $0.pitch == 60
                && $0.duration == 6 && $0.velocity == 100
        } == true, cppID: id, message: "the stale ruler fixture seeds its resize note")
    guard seed?.first != nil else { return }
    session.document.setLoop(end: false, tick: nil)
    session.document.setLoop(end: true, tick: nil)
    let at = viewport.camera.contentX(tick: 48)
    report.expect(
        [Tick(48), 72, 96].allSatisfy {
            Tick(grid.snapTickDown(Double($0))) == $0
        }, cppID: id, message: "the stale ruler press ticks lie on the snap lattice")
    openRulerMenu(menu, at: at)
    let revision = session.document.revision
    let identity = session.document.history.currentIdentity
    let disabledBytes = coreTimeBytes(session.document)
    let disabledIndex = session.document.history.undoIndex
    let disabledCount = session.document.history.undoCount
    report.expect(
        menu.isOpen && !menu.rows[5].enabled && menu.rows[0].enabled,
        cppID: id, message: "an unmarked ruler enables Insert Time but not Remove Loop")
    report.expect(
        !menu.activate(actionId: 4) && menu.isOpen
            && session.document.history.currentIdentity == identity,
        cppID: id, message: "a disabled Remove Loop click keeps the ruler menu open without a write")
    report.expect(
        coreTimeBytes(session.document) == disabledBytes
            && session.document.history.undoIndex == disabledIndex,
        cppID: id, message: "disabled Remove Loop changes neither bytes nor undo index")
    report.expect(
        menu.rows.contains(where: { $0.actionId == 10 && !$0.enabled })
            && !menu.activate(actionId: 10) && menu.isOpen
            && coreTimeBytes(session.document) == disabledBytes
            && session.document.history.undoIndex == disabledIndex,
        cppID: id, message: "disabled Remove Time Signature click preserves bytes and undo index")
    session.document.setLoop(end: false, tick: 48)
    report.expect(
        !menu.isOpen && session.document.revision != revision,
        cppID: id, message: "a document edit retires the open ruler menu")
    report.expect(
        session.timeline.loopStartTick == 48
            && session.timeline.loopEndTick == TimeDefaults.noTick,
        cppID: id, message: "a document-edit dismissal writes no loop marker beyond the edit")
    report.expect(
        coreTimeBytes(session.document) != disabledBytes
            && session.document.history.undoIndex == disabledIndex + 1
            && session.document.history.undoCount == disabledCount + 1
            && session.document.revision == revision + 1,
        cppID: id, message: "document edit closes the menu without an extra history or revision step")
    _ = session.document.history.undoDocument()
    let selectionBytes = coreTimeBytes(session.document)
    let selectionIndex = session.document.history.undoIndex
    let selectionRevision = session.document.revision
    let selectionMarkers = (session.timeline.loopStartTick, session.timeline.loopEndTick)
    openRulerMenu(menu, at: at)
    let selection = AutomationTimeSelection(
        range: TimeRange(startTick: 48, endTick: 72),
        scope: .tracks([session.selectedTrack ?? 0]))
    session.applyTimeSelection(selection)
    report.expect(
        !menu.isOpen && session.timeSelection == selection,
        cppID: id, message: "a selection change retires the open ruler menu")
    report.expect(
        coreTimeBytes(session.document) == selectionBytes,
        cppID: id, message: "a selection-change dismissal writes no markers")
    report.expect(
        coreTimeBytes(session.document) == selectionBytes
            && session.document.history.undoIndex == selectionIndex
            && session.document.revision == selectionRevision
            && session.timeline.loopStartTick == selectionMarkers.0
            && session.timeline.loopEndTick == selectionMarkers.1,
        cppID: id, message: "selection-change dismissal preserves post-edit bytes, history, revision and markers")
    session.clearTimeSelection()
}

@MainActor
func checkRulerDeferredTiming(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let palette = GridPalette()
    let grid = PianoGrid(viewport: viewport, palette: palette)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(viewport: viewport, palette: palette)
    let priorTrack = session.selectedTrack
    if priorTrack == nil { session.selectPrimaryTrack(0) }
    let priorCursor = session.editCursor
    defer {
        automation.detach()
        session.clearTimeSelection()
        session.editCursor = priorCursor
        session.selectedTrack = priorTrack
    }
    let menu = RulerMenuPresenter(viewport: viewport, grid: grid, automation: automation)
    let start = viewport.camera.contentX(tick: 24)
    let end = viewport.camera.contentX(tick: 72)
    let cursor = session.editCursor
    menu.captureRulerPress(contentX: end, pointerY: 0)
    report.expect(
        !menu.isOpen, cppID: id,
        message: "the ruler right press does not open the menu")
    report.expect(
        session.editCursor == cursor, cppID: id,
        message: "the ruler right press leaves the cursor untouched until release")
    menu.openRulerAtRelease()
    report.expect(
        menu.isOpen, cppID: id,
        message: "the ruler menu opens on right release")
    report.expect(
        menu.targetTick() == Double(Tick(grid.snapTickDown(72))), cppID: id,
        message: "ruler release uses the captured press tick for the menu target")
    menu.close()
    let band = AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 72),
        scope: .tracks([session.selectedTrack ?? 0]))
    session.applyTimeSelection(band)
    session.editCursor = 0
    menu.captureRulerPress(contentX: start + (end - start) / 2, pointerY: 0)
    report.expect(
        session.timeSelection == band, cppID: id,
        message: "a right press inside the interval keeps the selection")
    report.expect(
        session.editCursor == 0, cppID: id,
        message: "a right press inside the interval keeps the cursor")
    menu.openRulerAtRelease()
    report.expect(
        session.timeSelection == band, cppID: id,
        message: "right release inside the interval preserves the selection")
    report.expect(
        session.editCursor == 0, cppID: id,
        message: "right release inside the interval does not seek")
    menu.close()
    menu.captureRulerPress(contentX: end, pointerY: 0)
    report.expect(
        session.timeSelection == band, cppID: id,
        message: "a right press outside keeps the band until release")
    menu.openRulerAtRelease()
    report.expect(
        session.timeSelection == nil, cppID: id,
        message: "a press outside clears the selection on release")
    report.expect(
        session.editCursor == Tick(grid.snapTickDown(72)), cppID: id,
        message: "a press outside commits the cursor on release")
    menu.close()
    menu.beginSweep(contentX: start, pointerY: 0)
    menu.updateSweep(contentX: start + grid.dragDistance / 2, pointerY: 0)
    report.expect(
        session.timeSelection == nil, cppID: id,
        message: "the ruler sweep stays unarmed below the drag distance")
    menu.updateSweep(contentX: end, pointerY: 0)
    report.expect(
        session.timeSelection?.isActive == true, cppID: id,
        message: "the ruler sweep arms at the drag distance")
    menu.endSweep(contentX: end, pointerY: 0)
    session.clearTimeSelection()
    menu.beginSweep(contentX: start, pointerY: 0)
    menu.endSweep(contentX: start + grid.dragDistance / 2, pointerY: 0)
    report.expect(
        session.editCursor == Tick(grid.snapTickDown(24)), cppID: id,
        message: "a below-slop ruler release commits the snapped anchor")
    session.applyTimeSelection(band)
    menu.beginSweep(contentX: end, pointerY: 20)
    menu.endSweep(contentX: end + grid.dragDistance / 2, pointerY: 20)
    report.expect(
        session.timeSelection == band, cppID: id,
        message: "a below-slop ruler tap preserves the prior time-selection band")
}
