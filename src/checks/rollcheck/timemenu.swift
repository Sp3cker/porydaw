import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runTimemenuChecks(_ report: CheckReport, session: DocumentSession) {
    checkTimeMenuInsertTime(report, session: session)
    checkTimeSelectionMenuCommands(report, session: session)
    checkTimeMenuHalfOpenBoundary(report, session: session)
}

@MainActor
private func checkTimeMenuInsertTime(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeSelectionMenuInsertTimeAndStaleNoOp"
    // makeResizeSeed requests a free cell near tick 88 and draws velocity 100;
    // the synthetic song's six-tick cell starts at the snapped-down tick.
    let seedTick: Tick = 88 - (88 % 6)
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 200),
        MidiChunk(events: [
            .channel(tick: 0, status: 0xC0, data0: 0),
            .channel(tick: seedTick, status: 0x90, data0: 60, data1: 100),
            .channel(tick: seedTick + 6, status: 0x80, data0: 60),
        ], endTick: 200),
    ]), config: session.document.state.config, source: session.document.source,
        trackBudget: session.document.trackBudget)
    guard let seed = document.notes(in: 0).first else {
        report.fail(id, "the resize seed note was not found")
        return
    }
    let snapCell: Tick = 6
    document.nudgeNotes([seed.id], byTicks: Int64(snapCell), byKeys: 0)
    let insertStart = seed.tick + snapCell
    let insertEnd = insertStart + snapCell
    guard document.notes(in: 0).contains(where: { $0.tick == insertStart && $0.pitch == seed.pitch }) else {
        report.fail(id, "the moved seed note did not reach the insertion seam")
        return
    }
    let before = coreTimeBytes(document)
    let identity = document.history.currentIdentity
    let range = TimeRange(startTick: insertStart, endTick: insertEnd)
    report.expect(document.insertBlankTime(range, scope: TimeScope(tracks: [0])), cppID: id,
                  message: "the selected span inserts blank time")
    report.expect(document.notes(in: 0).contains {
        $0.tick == insertEnd && $0.pitch == seed.pitch && $0.velocity == seed.velocity
    } && document.history.currentIdentity != identity,
    cppID: id, message: "A084: the seed shifts from the selection start to its end in one transaction")
    _ = document.history.undoDocument()
    report.expect(coreTimeBytes(document) == before, cppID: id,
                  message: "A088: one undo restores the bytes before time insertion")
}

@MainActor
private func checkTimeSelectionMenuCommands(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeSelectionSwiftMenuInsertAndStale"
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }

    let start: Tick = 72
    let end: Tick = 96
    guard let added = try? session.document.addNotes([
        NewNote(track: session.selectedTrack ?? 0, tick: start + 6,
                pitch: 30, duration: 6, velocity: 100)
    ]), !added.isEmpty else {
        report.fail(id, "could not seed a note in the insertion range")
        return
    }
    defer { _ = session.document.history.undoDocument() }
    let midpoint = session.camera.contentX(tick: Double((start + end) / 2))
    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: start, endTick: end),
        scope: .tracks([session.selectedTrack ?? 0])))
    menu.openTimeSelection(contentX: midpoint)
    report.expect(menu.isOpen && menu.menuKind == 2
                  && menu.rows.count == 9
                  && menu.rows[3].actionId == 1 && menu.rows[3].enabled,
                  cppID: id, message: "a selected interval opens an enabled Insert Time row")
    let before = session.document.history.currentIdentity
    _ = menu.activate(actionId: 1)
    report.expect(!menu.isOpen && session.document.history.currentIdentity != before,
                  cppID: id, message: "the row applies one undoable range insertion")
    if session.document.history.currentIdentity != before {
        _ = session.document.history.undoDocument()
    }
    report.expect(session.document.history.currentIdentity == before, cppID: id,
                  message: "one undo restores the document before the menu insertion")

    menu.openTimeSelection(contentX: midpoint)
    automation.clearTimeSelection()
    let identity = session.document.history.currentIdentity
    _ = menu.activate(actionId: 6)
    report.expect(!menu.isOpen && session.document.history.currentIdentity == identity,
                  cppID: id, message: "a stale duplicate click cannot write after selection loss")
}

@MainActor
private func checkTimeMenuHalfOpenBoundary(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeSelectionMenuHalfOpenBoundary"
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    defer { automation.clearTimeSelection(); menu.close() }
    let start: Tick = 72
    let end: Tick = 96
    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: start, endTick: end),
        scope: .tracks([session.selectedTrack ?? 0])))
    menu.openTimeSelection(contentX: session.camera.contentX(tick: Double(end - 1)))
    report.expect(menu.isOpen && menu.menuKind == 2,
                  cppID: id,
                  message: "a press one tick inside the end stays inside the half-open interval")
    menu.close()
    menu.openTimeSelection(contentX: session.camera.contentX(tick: Double(end) + 0.5))
    report.expect(!menu.isOpen && menu.menuKind == 0,
                  cppID: id,
                  message: "a press at the interval end is outside the half-open selection")
}
