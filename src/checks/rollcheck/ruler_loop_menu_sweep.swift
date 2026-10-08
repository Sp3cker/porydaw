import Foundation
import PorydawApp
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import PorydawAppCommands

@MainActor
private struct RulerCheckFixture {
    let viewport: DocumentViewport
    var session: DocumentSession { viewport.session }
    let grid: PianoGrid
    let automation: AutomationPage
    let menu: RulerMenuPresenter
    let primary: Int
    let cell: Int
    let anchor: Tick
    let farTick: Tick
    let atAnchor: Double
    let atFar: Double
}

@MainActor
func checkRulerSweepScopeTapAndChip(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let palette = GridPalette()
    let grid = PianoGrid(viewport: viewport, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(viewport: viewport, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(viewport: viewport, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }
    defer { automation.clearTimeSelection(); menu.close(); menu.cancelSweep() }
    automation.clearTimeSelection()
    menu.close()

    let cell = max(1, grid.snapTicks)
    let anchor = Tick(grid.snapTickDown(Double(72)))
    var farTick = anchor + Tick(cell * 4)
    var alignSteps = 0
    while Tick(grid.snapTickDown(Double(farTick))) != farTick && alignSteps < 1024 {
        farTick = farTick + 1
        alignSteps += 1
    }
    let fixture = RulerCheckFixture(
        viewport: viewport, grid: grid, automation: automation, menu: menu,
        primary: session.selectedTrack ?? 0, cell: cell, anchor: anchor, farTick: farTick,
        atAnchor: viewport.camera.contentX(tick: Double(anchor)),
        atFar: viewport.camera.contentX(tick: Double(farTick)))
    guard let endTick = checkRulerSweepScope(report, fixture: fixture) else { return }
    guard checkRulerTapAndCancel(report, fixture: fixture, endTick: endTick) else { return }
    checkRulerPressPolicy(report, fixture: fixture, endTick: endTick)
    checkRulerChip(report, fixture: fixture, endTick: endTick)
}

@MainActor
private func checkRulerSweepScope(_ report: CheckReport, fixture: RulerCheckFixture) -> Tick? {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let session = fixture.session
    let menu = fixture.menu
    let automation = fixture.automation
    menu.beginSweep(contentX: fixture.atAnchor, pointerY: 0)
    menu.updateSweep(contentX: fixture.atFar)
    guard let swept = automation.selection, swept.isActive else {
        report.fail(id, "a plain ruler sweep published no time selection")
        return nil
    }
    report.expect(
        swept.range == TimeRange(startTick: fixture.anchor, endTick: fixture.farTick)
            && swept.scope == .tracks([fixture.primary]),
        cppID: id,
        message: "A025: a plain ruler drag sweeps the exact range with primary-only scope")
    menu.endSweep(contentX: fixture.atFar)
    report.expect(
        automation.selection?.isActive == true
            && automation.selection?.range == swept.range,
        cppID: id,
        message: "releasing a swept range retains the time selection")

    let docBytes = coreTimeBytes(session.document)
    guard session.document.canAddTrack, let other = session.document.addTrack(voice: 0),
        other != fixture.primary
    else {
        report.fail(id, "the fixture cannot provision a second engine track")
        return nil
    }
    guard
        let overlapIDs = try? session.document.addNotes([
            NewNote(
                track: other, tick: fixture.anchor, pitch: 60,
                duration: Tick(fixture.cell * 4), velocity: 90)
        ]), !overlapIDs.isEmpty
    else {
        report.fail(id, "the fixture cannot seed the intersecting track note")
        return nil
    }
    automation.clearTimeSelection()
    menu.beginSweep(contentX: fixture.atAnchor, pointerY: 0, modifiers: 0x0400_0000)
    menu.updateSweep(contentX: fixture.atFar)
    guard let modified = automation.selection, modified.isActive else {
        report.fail(id, "a modified ruler sweep published no time selection")
        return nil
    }
    guard case let .tracks(scope) = modified.scope else {
        report.fail(id, "a modified ruler sweep published a non-track scope")
        return nil
    }
    report.expect(
        modified.range == TimeRange(startTick: fixture.anchor, endTick: fixture.farTick)
            && scope.contains(fixture.primary) && scope.contains(other),
        cppID: id,
        message: "A026: a Control ruler drag sweeps the exact range with intersecting-track scope")
    menu.endSweep(contentX: fixture.atFar)
    checkDuplicateUndoRehighlightsSource(report, fixture: fixture, swept: modified)
    report.expect(
        session.document.history.undoDocument(), cppID: id,
        message: "the intersecting note insertion is undoable")
    report.expect(
        session.document.history.undoDocument()
            && coreTimeBytes(session.document) == docBytes, cppID: id,
        message: "undoing the note and track restores the fixture bytes")
    return modified.range.endTick
}

/// Undoing a time duplication re-highlights the range it copied; redo re-highlights the copy.
@MainActor
private func checkDuplicateUndoRehighlightsSource(
    _ report: CheckReport, fixture: RulerCheckFixture, swept: AutomationTimeSelection
) {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let session = fixture.session
    let document = session.document
    let automation = fixture.automation
    let router = EditorCommandRouter(
        session: session, grid: fixture.grid, automation: automation, rulerMenu: fixture.menu)
    let span = swept.range.span
    func shifted(_ copies: Tick) -> TimeRange {
        TimeRange(startTick: swept.range.startTick + copies * span, endTick: swept.range.endTick + copies * span)
    }
    func step(_ direction: BankHistoryDirection) -> Bool {
        (try? runBlocking { direction == .undo ? try await session.undo() : try await session.redo() }) == true
    }
    let original = coreTimeBytes(document)
    router.perform(.duplicate)
    let once = coreTimeBytes(document)
    router.perform(.duplicate)
    report.expect(
        automation.selection?.range == shifted(2) && once != original,
        cppID: id, message: "each duplicate highlights its copy")
    report.expect(
        step(.undo) && coreTimeBytes(document) == once && automation.selection?.range == shifted(1)
            && automation.selection?.scope == swept.scope,
        cppID: id, message: "undoing a duplicate re-highlights the range it copied")
    report.expect(
        step(.undo) && coreTimeBytes(document) == original && automation.selection == swept,
        cppID: id, message: "undoing the first duplicate re-highlights the swept range")
    report.expect(
        step(.redo) && coreTimeBytes(document) == once && automation.selection?.range == shifted(1),
        cppID: id, message: "redoing a duplicate re-highlights its copy")
    report.expect(
        step(.undo) && automation.selection == swept,
        cppID: id, message: "undo after redo re-highlights the swept range again")
    router.perform(.duplicate)
    report.expect(
        coreTimeBytes(document) == once,
        cppID: id, message: "duplicating after undo copies the re-highlighted range")
    report.expect(
        step(.undo) && coreTimeBytes(document) == original && automation.selection == swept,
        cppID: id, message: "the repeated duplicate undoes to the swept range")
}

@MainActor
private func checkRulerTapAndCancel(
    _ report: CheckReport, fixture: RulerCheckFixture, endTick: Tick
) -> Bool {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let viewport = fixture.viewport
    let session = viewport.session
    let menu = fixture.menu
    let automation = fixture.automation
    var outside = endTick + Tick(fixture.cell)
    var steps = 0
    while Tick(fixture.grid.snapTickDown(Double(outside))) != outside && steps < 1024 {
        outside = outside + 1
        steps += 1
    }
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: fixture.anchor, endTick: endTick),
            scope: .tracks([fixture.primary])))
    let priorTapChange = session.onChange
    var tapPublications: [SessionChangeDomains] = []
    session.onChange = { change in
        tapPublications.append(change.domains)
        priorTapChange?(change)
    }
    session.editCursor = fixture.anchor
    let atOutside = viewport.camera.contentX(tick: Double(outside))
    menu.beginSweep(contentX: atOutside, pointerY: 0)
    menu.endSweep(contentX: atOutside)
    session.onChange = priorTapChange
    report.expect(
        automation.selection
            == AutomationTimeSelection(
                range: TimeRange(startTick: fixture.anchor, endTick: endTick),
                scope: .tracks([fixture.primary]))
            && session.editCursor == outside,
        cppID: id,
        message: "A035: tapping the ruler outside the selection commits the cursor without clearing it")
    report.expect(
        tapPublications.contains(where: { $0.contains(.cursor) }), cppID: id,
        message: "A035: the tap commit publishes the cursor through the session observer")

    menu.beginSweep(contentX: fixture.atAnchor, pointerY: 0)
    menu.updateSweep(contentX: fixture.atFar)
    guard let live = automation.selection, live.isActive else {
        report.fail(id, "the cancellation fixture published no time selection")
        return false
    }
    let cursorBeforeCancel = session.editCursor
    menu.cancelSweep()
    report.expect(
        automation.selection == live && session.editCursor == cursorBeforeCancel,
        cppID: id,
        message: "cancelling a sweep keeps the selection and cursor without committing")
    menu.updateSweep(contentX: fixture.atAnchor)
    report.expect(
        automation.selection == live,
        cppID: id,
        message: "a cancelled sweep ignores further movement")
    return true
}

@MainActor
private func checkRulerPressPolicy(
    _ report: CheckReport, fixture: RulerCheckFixture, endTick: Tick
) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuInsertTimeAndStaleNoOp"
    let viewport = fixture.viewport
    let session = viewport.session
    let menu = fixture.menu
    let automation = fixture.automation
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: fixture.anchor, endTick: endTick),
            scope: .tracks([fixture.primary])))
    session.editCursor = fixture.anchor
    openRulerMenu(menu, at: viewport.camera.contentX(tick: Double(endTick - 1)))
    report.expect(
        menu.isOpen && menu.menuKind == 1
            && automation.selection?.range.startTick == fixture.anchor
            && automation.selection?.range.endTick == endTick
            && session.editCursor == fixture.anchor
            && (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 5 }),
        cppID: id,
        message: "A098/A099: a press inside the interval keeps the selection and cursor")
    menu.close()

    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: fixture.anchor, endTick: endTick),
            scope: .tracks([fixture.primary])))
    let priorEndChange = session.onChange
    var endPublications: [SessionChangeDomains] = []
    session.onChange = { change in
        endPublications.append(change.domains)
        priorEndChange?(change)
    }
    openRulerMenu(menu, at: viewport.camera.contentX(tick: Double(endTick) + 0.5))
    session.onChange = priorEndChange
    report.expect(
        menu.isOpen && menu.menuKind == 1,
        cppID: id,
        message: "A110-A113: the exact-end press clears, commits the end tick, opens cursor rows")
    report.expect(
        automation.selection?.isActive != true,
        cppID: id, message: "A111: the exact-end press clears the time selection")
    report.expect(
        session.editCursor == endTick,
        cppID: id, message: "A112: the exact-end press commits the snapped end tick")
    report.expect(
        !(0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 5 })
            && (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 2 }),
        cppID: id, message: "A113: the exact-end press opens the cursor rows")
    report.expect(
        endPublications.contains(where: { $0.contains(.cursor) }), cppID: id,
        message: "A112: the outside press publishes the committed cursor through the session observer")
    menu.close()
}

@MainActor
private func checkRulerChip(
    _ report: CheckReport, fixture: RulerCheckFixture, endTick: Tick
) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuEnablementSelectionContext"
    let viewport = fixture.viewport
    let session = viewport.session
    let menu = fixture.menu
    let chipOff = endTick + 1
    let preSigBytes = coreTimeBytes(session.document)
    session.document.setTimeSignature(tick: chipOff, numerator: 7, denominatorPower: 2)
    fixture.automation.clearTimeSelection()
    openRulerMenu(menu, at: viewport.camera.contentX(tick: Double(chipOff)))
    report.expect(
        session.editCursor == chipOff && menu.isOpen && menu.menuKind == 1,
        cppID: id,
        message: "A059: an off-grid chip press commits the chip's exact event tick")
    let tickRowY = fixture.grid.rulerMarkerRowHeight
    menu.captureRulerPress(
        contentX: viewport.camera.contentX(tick: Double(chipOff)),
        pointerY: tickRowY)
    menu.openRulerAtRelease()
    report.expect(
        menu.isOpen
            && !menu.rows.contains(where: {
                $0.actionId == 10 && $0.enabled
            }), cppID: id, message: "a tick-row ruler press ignores the signature chip")
    menu.close()
    report.expect(
        session.document.history.undoDocument()
            && coreTimeBytes(session.document) == preSigBytes, cppID: id,
        message: "one undo restores the bytes before the chip signature")

    session.document.setTimeSignature(tick: endTick, numerator: 5, denominatorPower: 2)
    session.editCursor = fixture.anchor
    openRulerMenu(menu, at: viewport.camera.contentX(tick: Double(endTick)))
    report.expect(
        session.editCursor == endTick && menu.isOpen && menu.menuKind == 1
            && (0..<menu.rows.count).contains(where: {
                menu.rows[$0].actionId == 10 && menu.rows[$0].enabled
            }),
        cppID: id,
        message: "A039: a snap-aligned chip press commits the chip tick and enables Remove Time Signature")
    menu.captureRulerPress(
        contentX: viewport.camera.contentX(tick: Double(endTick)),
        pointerY: fixture.grid.rulerMarkerRowHeight / 2)
    menu.openRulerAtRelease()
    report.expect(
        menu.targetTick() == Double(endTick)
            && menu.rows.contains(where: {
                $0.actionId == 10 && $0.enabled
            }), cppID: id, message: "a marker-row press commits the chip's exact tick")
    menu.close()
    report.expect(
        session.document.history.undoDocument()
            && coreTimeBytes(session.document) == preSigBytes, cppID: id,
        message: "one undo restores the bytes before the snap-aligned chip signature")
}
