import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore

@MainActor
func runTimemenuChecks(_ report: CheckReport, session: DocumentSession) {
    checkTimeMenuInsertTime(report, session: session)
    checkTimeSelectionMenuCommands(report, session: session)
    checkTimeMenuHalfOpenBoundary(report, session: session)
    checkTimeMenuClipboardRetirement(report, session: session)
    checkEmptyTimeSelectionNudge(report, session: session)
    checkRejectedTimeMenuPaste(report, session: session)
    checkNoteDuplicateArming(report, session: session)
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
    let bytes = coreTimeBytes(session.document)
    let selection = session.timeSelection
    _ = menu.activate(actionId: 1)
    report.expect(!menu.isOpen && session.document.history.currentIdentity != before,
                  cppID: id, message: "the row applies one undoable range insertion")
    report.expect(session.editCursor == start && session.timeSelection == selection
                  && session.document.note(added[0])?.tick == end + 6,
                  cppID: id, message: "the Insert Time row commits at the seam and retains the blank selection")
    if session.document.history.currentIdentity != before {
        _ = session.document.history.undoDocument()
    }
    report.expect(session.document.history.currentIdentity == before
                  && coreTimeBytes(session.document) == bytes, cppID: id,
                  message: "one undo restores the document before the menu insertion")

    menu.openTimeSelection(contentX: midpoint)
    automation.clearTimeSelection()
    let identity = session.document.history.currentIdentity
    _ = menu.activate(actionId: 6)
    report.expect(!menu.isOpen && session.document.history.currentIdentity == identity,
                  cppID: id, message: "a stale duplicate click cannot write after selection loss")
}

@MainActor
private func checkTimeMenuClipboardRetirement(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeSelectionMenuClipboardRetirement"
    let saved = drawerAutomationPorydawSelectionClipboardState()
    defer { saved.restore() }
    let clipboard = GridClipboard()
    report.expect(clipboard.write(PorydawClip(),
                                  ticksPerBeat: UInt32(session.document.ticksPerBeat)),
                  cppID: id, message: "an empty clip reaches the native clipboard")
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let band = AutomationTimeSelection(range: TimeRange(startTick: 72, endTick: 96),
                                       scope: .tracks([session.selectedTrack ?? 0]))
    session.applyTimeSelection(band)
    defer { session.clearTimeSelection() }
    let midpoint = session.camera.contentX(tick: 84)
    menu.openTimeSelection(contentX: midpoint)
    let identity = session.document.history.currentIdentity
    report.expect(menu.isOpen && !menu.rows[6].enabled && menu.rows[0].enabled
                  && menu.rows[8].enabled, cppID: id,
                  message: "Paste starts disabled for an empty clip while Copy and Clear remain enabled")
    let note = ClipNote(relTick: 0, key: 60, duration: 6, velocity: 100)
    report.expect(clipboard.write(PorydawClip(tracks: [
        ClipTrack(track: session.selectedTrack ?? 0, notes: [note])
    ]), ticksPerBeat: UInt32(session.document.ticksPerBeat)), cppID: id,
                  message: "a non-empty note clip reaches the native clipboard")
    report.expect(!menu.isOpen && session.document.history.currentIdentity == identity,
                  cppID: id, message: "the clipboard change retires the open time menu without a write")
    menu.openTimeSelection(contentX: midpoint)
    report.expect(menu.isOpen && menu.rows[6].enabled, cppID: id,
                  message: "the rebuilt Paste row follows the decodable non-empty clipboard")
    report.expect(clipboard.write(PorydawClip(),
                                  ticksPerBeat: UInt32(session.document.ticksPerBeat)),
                  cppID: id, message: "the native clipboard accepts the emptied clip")
    report.expect(!menu.isOpen && session.document.history.currentIdentity == identity,
                  cppID: id, message: "emptying the clipboard retires the enabled Paste menu without a write")
}

@MainActor
private func checkNoteDuplicateArming(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeMenuNoteDuplicateAvailability"
    let oldTrack = session.selectedTrack
    let oldNotes = session.selectedNoteOrder
    defer {
        session.selectedTrack = oldTrack
        session.setSelectedNotes(oldNotes)
    }
    guard let note = session.document.notes(in: 0).first else {
        report.fail(id, "the availability fixture has no source note")
        return
    }
    session.selectPrimaryTrack(0)
    session.clearTimeSelection()
    session.setSelectedNotes([note.id])
    let grid = PianoGrid(session: session)
    report.expect(session.timeSelection == nil
                  && grid.commandAvailable(command: EditCommand.duplicate.rawValue),
                  cppID: id, message: "Duplicate stays enabled for a note-only selection")
}

@MainActor
private func checkRejectedTimeMenuPaste(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rejectedNotePastePreservesViewState"
    let saved = drawerAutomationPorydawSelectionClipboardState()
    defer { saved.restore() }
    let clipboard = GridClipboard()
    let grid = PianoGrid(session: session)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: GridPalette())
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let oldTrack = session.selectedTrack
    let oldNotes = session.selectedNoteOrder
    let oldTime = session.timeSelection
    let oldCursor = session.editCursor
    defer {
        session.clearTimeSelection()
        session.selectedTrack = oldTrack
        if let oldTime { session.applyTimeSelection(oldTime) }
        else { session.setSelectedNotes(oldNotes) }
        session.editCursor = oldCursor
    }
    if oldTrack == nil { session.selectPrimaryTrack(0) }
    let destination = Tick(grid.snapTickDown(Double(session.timeline.lengthTicks + 96)))
    let track = session.selectedTrack ?? 0
    let conflicting = [
        ClipNote(relTick: 0, key: 55, duration: 12, velocity: 91),
        ClipNote(relTick: 1, key: 55, duration: 12, velocity: 91)
    ]
    for span: Tick in [0, 24] {
        for selected in [false, true] {
            for fromMenu in [false, true] {
                let variant = "\(span == 0 ? "notes" : "range"), "
                    + "\(selected ? "selected" : "unselected"), "
                    + "\(fromMenu ? "menu" : "key")"
                session.applyTimeSelection(selected
                    ? AutomationTimeSelection(range: TimeRange(
                        startTick: destination, endTick: destination + 24),
                        scope: .tracks([track])) : nil)
                session.editCursor = destination
                report.expect(clipboard.write(PorydawClip(span: span, tracks: [
                    ClipTrack(track: track, notes: conflicting)
                ]), ticksPerBeat: UInt32(session.document.ticksPerBeat)),
                cppID: id, message: "a conflicting \(variant) payload reaches the native clipboard")
                if fromMenu {
                    let contentX = session.camera.contentX(
                        tick: Double(destination + (selected ? 6 : 0)))
                    if selected { menu.openTimeSelection(contentX: contentX) }
                    else { openRejectedPasteRulerMenu(menu, at: contentX) }
                    report.expect(menu.isOpen && menu.rows[selected ? 6 : 1].enabled,
                                  cppID: id, message: "Paste remains eligible for the \(variant) payload")
                }
                let bytes = coreTimeBytes(session.document)
                let revision = session.document.revision
                let undoIndex = session.document.history.undoIndex
                let undoCount = session.document.history.undoCount
                let canRedo = session.document.history.canRedo
                let notes = session.selectedNoteOrder
                let time = session.timeSelection
                let scope = session.selectedTracks
                let cursor = session.editCursor
                let camera = session.camera.snapshot
                let status = grid.statusText
                if fromMenu { _ = menu.activate(actionId: 13) }
                else { _ = automation.consumeSelectionCommand(command: .paste) }
                report.expect(coreTimeBytes(session.document) == bytes
                              && session.document.revision == revision
                              && session.document.history.undoIndex == undoIndex
                              && session.document.history.undoCount == undoCount
                              && session.document.history.canRedo == canRedo,
                              cppID: id, message: "a conflicting \(variant) paste preserves song and history")
                report.expect(session.selectedNoteOrder == notes && session.timeSelection == time
                              && session.selectedTracks == scope && session.editCursor == cursor
                              && session.camera.snapshot == camera && grid.statusText == status,
                              cppID: id, message: "a conflicting \(variant) paste preserves selection and view")
            }
        }
    }
    session.clearTimeSelection()
}

@MainActor
private func openRejectedPasteRulerMenu(_ menu: RulerMenuPresenter, at contentX: Double) {
    menu.captureRulerPress(contentX: contentX, pointerY: 0)
    menu.openRulerAtRelease()
}

@MainActor
private func checkEmptyTimeSelectionNudge(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::emptyTimeSelectionNudge"
    let grid = PianoGrid(session: session)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: GridPalette())
    defer { automation.detach() }
    let oldTrack = session.selectedTrack
    if oldTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = oldTrack }
    let start = Tick(grid.snapTickDown(Double(session.timeline.lengthTicks + 96)))
    let selection = AutomationTimeSelection(
        range: TimeRange(startTick: start, endTick: start + 24),
        scope: .tracks([session.selectedTrack ?? 0]))
    session.applyTimeSelection(selection)
    defer { session.clearTimeSelection() }
    let bytes = coreTimeBytes(session.document)
    let revision = session.document.revision
    let undoIndex = session.document.history.undoIndex
    let undoCount = session.document.history.undoCount
    report.expect(automation.consumeSelectionCommand(command: .nudgeRight)
                  && (session.timeSelection?.range.startTick ?? start) > start,
                  cppID: id, message: "an empty-content nudge moves the band past the song end")
    report.expect(coreTimeBytes(session.document) == bytes
                  && session.document.revision == revision
                  && session.document.history.undoIndex == undoIndex
                  && session.document.history.undoCount == undoCount,
                  cppID: id, message: "nudging an empty band publishes no document edit")
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
