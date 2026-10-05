import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawDocument

@MainActor
func runTimemenuChecks(_ report: CheckReport, session: DocumentSession) {
    checkTimeMenuInsertTime(report, session: session)
    checkTimeSelectionMenuCommands(report, session: session)
    checkTimeMenuHalfOpenBoundary(report, session: session)
    checkTimeMenuClipboardRetirement(report, session: session)
    checkEmptyTimeSelectionNudge(report, session: session)
    checkRejectedTimeMenuPaste(report, session: session)
    checkAdmittedTimeMenuPaste(report, session: session)
    checkNoteDuplicateArming(report, session: session)
}

@MainActor
private func checkTimeMenuInsertTime(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeSelectionMenuInsertTimeAndStaleNoOp"
    // makeResizeSeed requests a free cell near tick 88 and draws velocity 100;
    // the synthetic song's six-tick cell starts at the snapped-down tick.
    let seedTick: Tick = 88 - (88 % 6)
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [], endTick: 200),
                MidiChunk(
                    events: [
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
    report.expect(
        seed.tick == seedTick && seed.pitch == 60 && seed.duration == 6,
        cppID: id, message: "the time insertion fixture seeds its shifted note")
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
    let undoCount = document.history.undoCount
    let range = TimeRange(startTick: insertStart, endTick: insertEnd)
    report.expect(
        document.insertBlankTime(range, scope: TimeScope(tracks: [0])), cppID: id,
        message: "the selected span inserts blank time")
    report.expect(
        document.notes(in: 0).contains {
            $0.tick == insertEnd && $0.pitch == seed.pitch && $0.velocity == seed.velocity
        } && document.history.currentIdentity != identity,
        cppID: id, message: "A084: the seed shifts from the selection start to its end in one transaction")
    report.expect(
        document.history.undoCount == undoCount + 1,
        cppID: id, message: "time insertion adds exactly one undo transaction")
    _ = document.history.undoDocument()
    report.expect(
        coreTimeBytes(document) == before, cppID: id,
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
    let previousClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { previousClipboard.restore() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }

    let start: Tick = 72
    let end: Tick = 96
    guard
        let added = try? session.document.addNotes([
            NewNote(
                track: session.selectedTrack ?? 0, tick: start + 6,
                pitch: 30, duration: 6, velocity: 100)
        ]), !added.isEmpty
    else {
        report.fail(id, "could not seed a note in the insertion range")
        return
    }
    report.expect(
        session.document.note(added[0]).map {
            $0.track == (session.selectedTrack ?? 0) && $0.tick == start + 6 && $0.pitch == 30
        } == true, cppID: id, message: "the time insertion fixture seeds its selected note")
    defer { _ = session.document.history.undoDocument() }
    let midpoint = session.camera.contentX(tick: Double((start + end) / 2))
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: start, endTick: end),
            scope: .tracks([session.selectedTrack ?? 0])))
    menu.openTimeSelection(contentX: midpoint)
    report.expect(
        menu.isOpen && menu.menuKind == 2
            && menu.rows.count == 9
            && menu.rows[3].actionId == 1 && menu.rows[3].enabled,
        cppID: id, message: "a selected interval opens an enabled Insert Time row")
    let copyBytes = coreTimeBytes(session.document)
    let copyIndex = session.document.history.undoIndex
    let copyCount = session.document.history.undoCount
    _ = menu.activate(actionId: 11)
    report.expect(
        GridClipboard().read()?.clip.span == end - start,
        cppID: id, message: "Copy decodes a clip spanning exactly the selected snap cells")
    report.expect(
        coreTimeBytes(session.document) == copyBytes
            && session.document.history.undoIndex == copyIndex
            && session.document.history.undoCount == copyCount,
        cppID: id, message: "Copy changes neither document bytes nor undo history")
    let copiedNote = GridClipboard().read()?.clip.tracks
        .first(where: { $0.track == (session.selectedTrack ?? 0) })?
        .notes.first(where: { $0.key == 30 })
    report.expect(
        copiedNote?.relTick == 6, cppID: id,
        message: "the copied time range stores the covered note relative to its start")
    report.expect(
        copiedNote?.key == 30, cppID: id,
        message: "the copied time range preserves the covered note pitch")
    menu.openTimeSelection(contentX: midpoint)
    let before = session.document.history.currentIdentity
    let bytes = coreTimeBytes(session.document)
    let insertCount = session.document.history.undoCount
    let selection = session.timeSelection
    _ = menu.activate(actionId: 1)
    report.expect(
        !menu.isOpen && session.document.history.currentIdentity != before,
        cppID: id, message: "the row applies one undoable range insertion")
    report.expect(
        session.editCursor == start && session.timeSelection == selection
            && session.document.note(added[0])?.tick == end + 6,
        cppID: id, message: "the Insert Time row commits at the seam and retains the blank selection")
    report.expect(
        session.document.history.undoCount == insertCount + 1,
        cppID: id, message: "the time-menu Insert Time row commits exactly one undo entry")
    if session.document.history.currentIdentity != before {
        _ = session.document.history.undoDocument()
    }
    report.expect(
        session.document.history.currentIdentity == before
            && coreTimeBytes(session.document) == bytes, cppID: id,
        message: "one undo restores the document before the menu insertion")

    menu.openTimeSelection(contentX: midpoint)
    automation.clearTimeSelection()
    let identity = session.document.history.currentIdentity
    let staleBytes = coreTimeBytes(session.document)
    let staleIndex = session.document.history.undoIndex
    let staleCount = session.document.history.undoCount
    let staleRevision = session.document.revision
    _ = menu.activate(actionId: 6)
    report.expect(
        !menu.isOpen && session.document.history.currentIdentity == identity,
        cppID: id, message: "a stale duplicate click cannot write after selection loss")
    report.expect(
        coreTimeBytes(session.document) == staleBytes
            && session.document.history.undoIndex == staleIndex
            && session.document.history.undoCount == staleCount
            && session.document.revision == staleRevision,
        cppID: id, message: "stale Duplicate preserves bytes, history depth and revision")
    let snapCell = Tick(grid.snapTicks)
    let cellStart = start + snapCell
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: cellStart, endTick: cellStart + snapCell),
            scope: .tracks([session.selectedTrack ?? 0])))
    menu.openTimeSelection(contentX: session.camera.contentX(tick: Double(cellStart + 1)))
    let cellBytes = coreTimeBytes(session.document)
    let cellIndex = session.document.history.undoIndex
    let cellCount = session.document.history.undoCount
    _ = menu.activate(actionId: 11)
    let copiedCell = GridClipboard().read()?.clip
    report.expect(
        copiedCell?.span == snapCell
            && copiedCell?.tracks.contains(where: {
                $0.notes.contains(where: { $0.key == 30 && $0.relTick == 0 })
            }) == true, cppID: id,
        message: "Copy decodes a note clip spanning exactly one snap cell")
    report.expect(
        coreTimeBytes(session.document) == cellBytes
            && session.document.history.undoIndex == cellIndex
            && session.document.history.undoCount == cellCount,
        cppID: id, message: "single-cell Copy leaves bytes, index and count unchanged")
    automation.clearTimeSelection()
}

@MainActor
private func checkTimeMenuClipboardRetirement(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeSelectionMenuClipboardRetirement"
    let saved = drawerAutomationPorydawSelectionClipboardState()
    defer { saved.restore() }
    let clipboard = GridClipboard()
    report.expect(
        clipboard.write(
            PorydawClip(),
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
    let band = AutomationTimeSelection(
        range: TimeRange(startTick: 72, endTick: 96),
        scope: .tracks([session.selectedTrack ?? 0]))
    session.applyTimeSelection(band)
    defer { session.clearTimeSelection() }
    let midpoint = session.camera.contentX(tick: 84)
    menu.openTimeSelection(contentX: midpoint)
    let identity = session.document.history.currentIdentity
    let disabledBytes = coreTimeBytes(session.document)
    let disabledIndex = session.document.history.undoIndex
    let disabledCount = session.document.history.undoCount
    report.expect(
        menu.isOpen && !menu.rows[6].enabled && menu.rows[0].enabled
            && menu.rows[8].enabled, cppID: id,
        message: "Paste starts disabled for an empty clip while Copy and Clear remain enabled")
    report.expect(
        !menu.activate(actionId: 13) && menu.isOpen
            && coreTimeBytes(session.document) == disabledBytes
            && session.document.history.undoIndex == disabledIndex
            && session.document.history.undoCount == disabledCount,
        cppID: id, message: "disabled Paste click keeps the menu open and writes nothing")
    let note = ClipNote(relTick: 0, key: 60, duration: 6, velocity: 100)
    report.expect(
        clipboard.write(
            PorydawClip(tracks: [
                ClipTrack(track: session.selectedTrack ?? 0, notes: [note])
            ]), ticksPerBeat: UInt32(session.document.ticksPerBeat)), cppID: id,
        message: "a non-empty note clip reaches the native clipboard")
    report.expect(
        !menu.isOpen && session.document.history.currentIdentity == identity,
        cppID: id, message: "the clipboard change retires the open time menu without a write")
    menu.openTimeSelection(contentX: midpoint)
    report.expect(
        menu.isOpen && menu.rows[6].enabled, cppID: id,
        message: "the rebuilt Paste row follows the decodable non-empty clipboard")
    report.expect(
        clipboard.write(
            PorydawClip(),
            ticksPerBeat: UInt32(session.document.ticksPerBeat)),
        cppID: id, message: "the native clipboard accepts the emptied clip")
    report.expect(
        !menu.isOpen && session.document.history.currentIdentity == identity,
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
    let grid = PianoGrid(session: session)
    let tick = Tick(grid.snapTickDown(Double(session.timeline.lengthTicks + 96)))
    let seedID =
        (try? session.document.addNotes([
            NewNote(track: 0, tick: tick, pitch: 60, duration: 6, velocity: 100)
        ]))?.first
    defer {
        if seedID != nil { _ = session.document.history.undoDocument() }
    }
    let seed = seedID.flatMap { session.document.note($0) }
    report.expect(
        seed.map {
            $0.track == 0 && $0.tick == tick && $0.pitch == 60
                && $0.duration == 6 && $0.velocity == 100
        } == true, cppID: id,
        message: "the sweep seed note is reachable for note-only Duplicate")
    guard let note = seed else { return }
    session.selectPrimaryTrack(0)
    session.clearTimeSelection()
    session.setSelectedNotes([note.id])
    report.expect(
        session.timeSelection == nil
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
        if let oldTime { session.applyTimeSelection(oldTime) } else { session.setSelectedNotes(oldNotes) }
        session.editCursor = oldCursor
    }
    if oldTrack == nil { session.selectPrimaryTrack(0) }
    let destination = Tick(grid.snapTickDown(Double(session.timeline.lengthTicks + 96)))
    let track = session.selectedTrack ?? 0
    guard
        let seeded = try? session.document.addNotes([
            NewNote(track: track, tick: destination, pitch: 30, duration: 6, velocity: 100)
        ]), let seedID = seeded.first
    else {
        report.fail(id, "could not seed the rejected-paste fixture note")
        return
    }
    report.expect(
        session.document.note(seedID).map {
            $0.track == track && $0.tick == destination && $0.pitch == 30
        } == true, cppID: id, message: "the rejected-paste fixture seeds its note at the track and tick")
    defer { _ = session.document.history.undoDocument() }
    let conflicting = [
        ClipNote(relTick: 0, key: 55, duration: 12, velocity: 91),
        ClipNote(relTick: 1, key: 55, duration: 12, velocity: 91),
    ]
    for span: Tick in [0, 24] {
        for selected in [false, true] {
            for fromMenu in [false, true] {
                let variant =
                    "\(span == 0 ? "notes" : "range"), "
                    + "\(selected ? "selected" : "unselected"), "
                    + "\(fromMenu ? "menu" : "key")"
                session.applyTimeSelection(
                    selected
                        ? AutomationTimeSelection(
                            range: TimeRange(
                                startTick: destination, endTick: destination + 24),
                            scope: .tracks([track])) : nil)
                session.editCursor = destination
                report.expect(
                    clipboard.write(
                        PorydawClip(
                            span: span,
                            tracks: [
                                ClipTrack(track: track, notes: conflicting)
                            ]), ticksPerBeat: UInt32(session.document.ticksPerBeat)),
                    cppID: id, message: "a conflicting \(variant) payload reaches the native clipboard")
                if fromMenu {
                    let contentX = session.camera.contentX(
                        tick: Double(destination + (selected ? 6 : 0)))
                    if selected {
                        menu.openTimeSelection(contentX: contentX)
                    } else {
                        openRejectedPasteRulerMenu(menu, at: contentX)
                    }
                    report.expect(
                        menu.isOpen && menu.rows[selected ? 6 : 1].enabled,
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
                let previousChange = session.onChange
                var cursorPublications = 0
                session.onChange = { change in
                    if change.domains.contains(.cursor) { cursorPublications += 1 }
                    previousChange?(change)
                }
                if fromMenu {
                    _ = menu.activate(actionId: 13)
                } else {
                    _ = automation.consumeSelectionCommand(command: .paste)
                }
                session.onChange = previousChange
                report.expect(
                    cursorPublications == 0, cppID: id,
                    message: "every rejected paste variant publishes zero cursor moves")
                report.expect(
                    grid.statusText == status, cppID: id,
                    message: "every rejected paste variant leaves status text unchanged")
                report.expect(
                    coreTimeBytes(session.document) == bytes
                        && session.document.revision == revision
                        && session.document.history.undoIndex == undoIndex
                        && session.document.history.undoCount == undoCount
                        && session.document.history.canRedo == canRedo,
                    cppID: id, message: "a conflicting \(variant) paste preserves song and history")
                report.expect(
                    session.selectedNoteOrder == notes && session.timeSelection == time
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
private func checkAdmittedTimeMenuPaste(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timeSelectionMenuPaste"
    let saved = drawerAutomationPorydawSelectionClipboardState()
    defer { saved.restore() }
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor; session.clearTimeSelection() }
    let grid = PianoGrid(session: session)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: grid.palette)
    defer { automation.detach() }
    let track = session.selectedTrack ?? 0
    let destination = Tick(grid.snapTickDown(Double(session.timeline.lengthTicks + 96)))
    let clipboard = GridClipboard()
    let note = ClipNote(relTick: 6, key: 55, duration: 6, velocity: 90)
    for span: Tick in [24, 0] {
        session.editCursor = destination
        if span > 0 {
            session.applyTimeSelection(
                AutomationTimeSelection(
                    range: TimeRange(startTick: destination, endTick: destination + span),
                    scope: .tracks([track])))
        } else {
            session.clearTimeSelection()
        }
        guard
            clipboard.write(
                PorydawClip(
                    span: span,
                    tracks: [
                        ClipTrack(track: track, notes: [note])
                    ]), ticksPerBeat: UInt32(session.document.ticksPerBeat))
        else {
            report.fail(id, "the admitted clip could not reach the clipboard")
            return
        }
        let before = coreTimeBytes(session.document)
        let index = session.document.history.undoIndex
        let previousChange = session.onChange
        var cursorPublications = 0
        session.onChange = { change in
            if change.domains.contains(.cursor) { cursorPublications += 1 }
            previousChange?(change)
        }
        let consumed = automation.consumeSelectionCommand(command: .paste)
        session.onChange = previousChange
        let after = coreTimeBytes(session.document)
        let nextCursor = destination + (span > 0 ? span : Tick(note.relTick + note.duration))
        report.expect(
            consumed && session.document.history.undoIndex == index + 1
                && after != before && cursorPublications == 1,
            cppID: id, message: "an admitted paste publishes exactly one cursor move")
        report.expect(
            session.document.notes(in: track).contains {
                $0.tick == destination + Tick(note.relTick) && $0.pitch == note.key
                    && $0.velocity == 90
            }, cppID: id, message: "the admitted clip lands its original note velocity at the snap base")
        report.expect(
            session.editCursor == nextCursor, cppID: id,
            message: span > 0
                ? "an admitted range paste advances the cursor by the clip span"
                : "an admitted note-clip paste advances the cursor past the pasted notes")
        if span > 0 {
            report.expect(
                session.timeSelection == nil, cppID: id,
                message: "an admitted range paste drops the time selection")
        } else {
            report.expect(
                !session.selectedNotes.isEmpty, cppID: id,
                message: "an admitted note-clip paste selects the inserted notes")
        }
        let undone = session.document.history.undoDocument()
        let restored = coreTimeBytes(session.document) == before
        let redone = session.document.history.redoDocument()
        let replayed = coreTimeBytes(session.document) == after
        report.expect(
            undone && restored && redone && replayed, cppID: id,
            message: "one undo and redo restore the exact song bytes after an admitted paste")
        _ = session.document.history.undoDocument()
    }
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
    let expectedStart = Tick(grid.snapTickDown(Double(start + Tick(max(1, grid.snapTicks)))))
    report.expect(
        automation.consumeSelectionCommand(command: .nudgeRight)
            && (session.timeSelection?.range.startTick ?? start) > start,
        cppID: id, message: "an empty-content nudge moves the band past the song end")
    report.expect(
        session.timeSelection?.range.startTick == expectedStart,
        cppID: id, message: "an empty-band nudge moves the start to the next snap tick")
    report.expect(
        session.timeSelection?.range.endTick == expectedStart + 24,
        cppID: id, message: "an empty-band nudge moves the end to start plus the band length")
    report.expect(
        coreTimeBytes(session.document) == bytes
            && session.document.revision == revision
            && session.document.history.undoIndex == undoIndex
            && session.document.history.undoCount == undoCount,
        cppID: id, message: "nudging an empty band publishes no document edit")
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    menu.openTimeSelection(tick: expectedStart + 1)
    report.expect(
        menu.isOpen && menu.menuKind == 2
            && menu.rows.contains(where: { $0.actionId == 8 && $0.enabled }),
        cppID: id, message: "the time menu offers Clear for the nudged empty band")
    _ = menu.activate(actionId: 8)
    report.expect(
        !menu.isOpen && session.timeSelection == nil,
        cppID: id, message: "the time menu Clear row closes and drops the empty band")
    report.expect(
        session.document.history.undoCount == undoCount
            && session.document.history.undoIndex == undoIndex,
        cppID: id, message: "the time menu Clear row leaves the undo stack untouched")
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
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: start, endTick: end),
            scope: .tracks([session.selectedTrack ?? 0])))
    menu.openTimeSelection(contentX: session.camera.contentX(tick: Double(end - 1)))
    report.expect(
        menu.isOpen && menu.menuKind == 2,
        cppID: id,
        message: "a press one tick inside the end stays inside the half-open interval")
    menu.close()
    menu.openTimeSelection(contentX: session.camera.contentX(tick: Double(end) + 0.5))
    report.expect(
        !menu.isOpen && menu.menuKind == 0,
        cppID: id,
        message: "a press at the interval end is outside the half-open selection")
}
