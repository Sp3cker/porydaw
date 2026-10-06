import Foundation
@testable import PorydawApp
import QtBridge
import PorydawCore
@testable import PorydawDocument
import PorydawAppEventList
import PorydawAppCommands

internal let pageID = "swiftcore/EventList::pageInteraction"
internal let cellCommitContractID = "swiftcore/EventList::cellCommitContract"

@MainActor
internal func runEventListPageChecks(
    _ report: CheckReport, session suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .meta(tick: 0, type: 6, data: Array("mark".utf8)),
                    .channel(tick: 12, status: 0xB0, data0: 7, data1: 80),
                    .channel(tick: 12, status: 0xB0, data0: 10, data1: 40),
                    .channel(tick: 24, status: 0x90, data0: 60, data1: 80),
                    .channel(tick: 48, status: 0x80, data0: 60, data1: 0),
                ], endTick: 96),
            MidiChunk(events: [.meta(tick: 0, type: 6, data: [3])], endTick: 96),
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let presenter = EventListPresenter()
    session.onChange = { [weak presenter] change in presenter?.documentDidChange(change) }
    presenter.attach(session: session)
    presenter.setVisible(visible: true)

    let firstCC = presenter.model.rows.firstIndex { $0.eventIndex == 1 }
    let secondCC = presenter.model.rows.firstIndex { $0.eventIndex == 2 }
    let note = presenter.model.rows.firstIndex { $0.eventIndex == 3 }
    guard let firstCC, let secondCC, let note else {
        report.expect(false, cppID: pageID, message: "the sample exposes its two controls and note")
        return
    }

    presenter.selectRow(row: firstCC, modifiers: 0)
    presenter.selectRow(row: secondCC, modifiers: 0x0400_0000)
    report.expect(
        presenter.selectedRows == [firstCC, secondCC], cppID: pageID,
        message: "Control-click adds the second control without dropping the first")
    presenter.selectRow(row: note, modifiers: 0x0200_0000)
    report.expect(
        presenter.selectedRows == Array(firstCC...note), cppID: pageID,
        message: "Shift-click extends a contiguous range from the anchor")

    report.expect(
        presenter.isLegalDrop(fromRow: firstCC, gap: secondCC + 1),
        cppID: pageID, message: "a same-tick insertion gap permits reordering")
    report.expect(
        !presenter.isLegalDrop(fromRow: firstCC, gap: note + 1),
        cppID: pageID, message: "a cross-tick insertion gap rejects reordering")
    let entireDocumentBeforeMove = document.rawChunks.reduce(0) { $0 + $1.events.count }
    presenter.commitDrop(fromRow: firstCC, gap: secondCC + 1)
    report.expect(
        document.rawChunks[0].events[1].payload
            == .channel(status: 0xB0, data0: 10, data1: 40)
            && document.rawChunks[0].events[2].payload
                == .channel(status: 0xB0, data0: 7, data1: 80),
        cppID: pageID, message: "legal row drag swaps the two same-tick events")
    report.expect(
        document.rawChunks.reduce(0) { $0 + $1.events.count }
            == entireDocumentBeforeMove,
        cppID: pageID,
        message: "same-tick reorder preserves the entire document raw-event population")
    let control = presenter.model.rows.firstIndex { $0.eventIndex == 2 }
    guard let control else { return }
    report.expect(
        presenter.beginEditing(row: control, column: 3), cppID: pageID,
        message: "a controller number enters cell editing")
    report.expect(
        !presenter.finishEditing(text: "500", commit: true) && presenter.editing,
        cppID: pageID, message: "out-of-range input keeps the cell editor active")
    report.expect(
        presenter.finishEditing(text: "65", commit: true)
            && document.rawChunks[0].events[2].payload
                == .channel(status: 0xB0, data0: 65, data1: 80),
        cppID: pageID, message: "valid input commits a controller number to the song")
    report.expect(
        document.history.undoDocument()
            && document.rawChunks[0].events[2].payload
                == .channel(status: 0xB0, data0: 7, data1: 80),
        cppID: pageID, message: "cell edit is a reversible document transaction")

    document.editTempo(
        TempoEdit(add: [
            TempoPoint(
                tick: 36, microsecondsPerQuarterNote: 600_000)
        ]))
    report.expect(
        presenter.model.rows.contains(where: { $0.tempo?.tick == 36 }),
        cppID: pageID, message: "tempo changes appear as editable rows")
    presenter.openFilterMenu(x: 0, y: 0)
    presenter.activateMenuAction(actionId: 64)
    report.expect(
        !presenter.model.rows.contains(where: { $0.tempo != nil || $0.event?.isMeta == true })
            && presenter.model.rows.last?.isEndOfTrack == true,
        cppID: pageID, message: "meta filter hides tempo/meta but retains the end row")
    presenter.activateMenuAction(actionId: 64)
    report.expect(
        presenter.model.rows.contains(where: { $0.tempo?.tick == 36 }),
        cppID: pageID, message: "re-enabled meta filter restores tempo rows")
    presenter.dismissMenu()

    presenter.selectAll()
    report.expect(
        presenter.selectedRows.count == presenter.rowCount, cppID: pageID,
        message: "Select All includes every visible row")
    guard let protectedID = document.rawChunks[0].events.first(where: { $0.isNoteOn })?.noteID,
        let originalNote = document.note(protectedID),
        let firstVictim = presenter.model.rows.firstIndex(where: { $0.eventIndex == 1 }),
        let secondVictim = presenter.model.rows.firstIndex(where: { $0.eventIndex == 2 })
    else {
        return
    }
    session.setSelectedNotes([protectedID])
    presenter.selectRow(row: firstVictim, modifiers: 0)
    presenter.selectRow(row: secondVictim, modifiers: 0x0400_0000)
    report.expect(
        presenter.selectedRows == [firstVictim, secondVictim], cppID: pageID,
        message: "the two intended victim rows, not the note, are selected")
    let beforeDeletion = document.rawChunks[0].events.count
    let entireDocumentBeforeDelete = document.rawChunks.reduce(0) { $0 + $1.events.count }
    let beforeRows = presenter.rowCount
    presenter.deleteSelected()
    report.expect(
        document.rawChunks[0].events.count == beforeDeletion - 2
            && !document.rawChunks[0].events.contains(where: {
                $0.isChannel && $0.typeNibble == 0xB
            }),
        cppID: pageID, message: "Delete removes exactly the two selected raw rows")
    report.expect(
        document.rawChunks.reduce(0) { $0 + $1.events.count }
            == entireDocumentBeforeDelete - 2,
        cppID: pageID,
        message: "two selected raw-event deletions reduce the entire document population by two")
    report.expect(
        presenter.rowCount == beforeRows - 2, cppID: pageID,
        message: "Delete removes two visible rows without dropping EOT")
    let survivingNote = document.note(protectedID)
    report.expect(
        session.selectedNotes.contains(protectedID)
            && survivingNote?.tick == originalNote.tick
            && survivingNote?.pitch == originalNote.pitch
            && survivingNote?.duration == originalNote.duration
            && survivingNote?.isUnterminated == false,
        cppID: pageID, message: "Delete leaves the unrelated selected note intact")

    eventListAppearanceParity(report, suite: suite, service: service)
    eventListTypographyParity(report)
    eventListSummaryParity(report, suite: suite, service: service)
    eventListCellCommitContract(report, suite: suite, service: service)
    eventListChunkLabelParity(report, suite: suite, service: service)
    eventListTempoContract(report, suite: suite, service: service)
    eventListDeleteMatrix(report, suite: suite, service: service)
    eventListRowMenuContract(report, suite: suite, service: service)
    eventListFilterMatrix(report, suite: suite, service: service)
    eventListMenuInvalidation(report, suite: suite, service: service)
    eventListScopedSnapshots(report, suite: suite, service: service)
}

@MainActor
internal func eventListTempoContract(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .meta(tick: 0, type: 6, data: [1]),
                    .meta(tick: 48, type: 6, data: [2]),
                ], endTick: 96)
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let presenter = EventListPresenter()
    session.onChange = { [weak presenter] change in presenter?.documentDidChange(change) }
    presenter.attach(session: session)
    presenter.setVisible(visible: true)
    let id = "swiftcore/EventList::tempoContract"
    guard let marker = presenter.model.rows.firstIndex(where: { $0.tick == 48 }) else {
        report.expect(false, cppID: id, message: "the marker row exists for atomic conversion")
        return
    }
    let before = document.history.undoIndex
    let beganMarkerEdit = presenter.beginEditing(row: marker, column: 1)
    let committedMarkerEdit = beganMarkerEdit && presenter.finishEditing(text: "9", commit: true)
    report.expect(
        committedMarkerEdit, cppID: id,
        message: "marker-to-tempo type commit is accepted")
    report.expect(
        document.history.undoIndex == before + 1, cppID: id,
        message: "marker-to-tempo commit pushes one undo step")
    report.expect(
        presenter.model.rows.contains(where: { $0.tempo?.tick == 48 }),
        cppID: id, message: "marker-to-tempo commit projects a tempo row at tick 48")
    report.expect(
        !document.rawChunks[0].events.contains(where: { $0.tick == 48 }),
        cppID: id, message: "marker-to-tempo commit removes the tick-48 raw event")
    report.expect(
        !presenter.model.rows.contains(where: {
            $0.tick == 48 && $0.event?.isMeta == true
        }), cppID: id, message: "marker-to-tempo commit removes the tick-48 meta row")
    report.expect(
        document.rawChunks[0].events.contains(where: { $0.tick == 0 }),
        cppID: id, message: "marker-to-tempo commit is one step preserving tick-zero metas")
    let markerUndo = document.history.undoDocument()
    report.expect(markerUndo, cppID: id, message: "marker-to-tempo undo succeeds")
    report.expect(
        document.rawChunks[0].events.contains(where: { $0.tick == 48 }),
        cppID: id, message: "marker-to-tempo undo restores the raw tick-48 event")
    report.expect(
        presenter.model.rows.contains(where: {
            $0.tick == 48 && $0.event?.isMeta == true
        }), cppID: id, message: "marker-to-tempo undo restores the tick-48 meta row")
    report.expect(
        !presenter.model.rows.contains(where: { $0.tempo?.tick == 48 }),
        cppID: id, message: "marker-to-tempo undo removes the tick-48 tempo row")
    let markerRedo = document.history.redoDocument()
    report.expect(markerRedo, cppID: id, message: "marker-to-tempo undo and redo round trip")
    report.expect(
        presenter.model.rows.contains(where: { $0.tempo?.tick == 48 }),
        cppID: id, message: "marker-to-tempo redo restores the tick-48 tempo row")
    report.expect(
        !presenter.model.rows.contains(where: {
            $0.tick == 48 && $0.event?.isMeta == true
        }), cppID: id, message: "marker-to-tempo redo removes the tick-48 meta row")
    guard let tempo = presenter.model.rows.firstIndex(where: { $0.tempo?.tick == 48 }) else {
        report.expect(false, cppID: id, message: "the converted tempo row is editable")
        return
    }
    let beforeBPM = document.history.undoIndex
    report.expect(
        presenter.beginEditing(row: tempo, column: 5)
            && !presenter.finishEditing(text: "19", commit: true)
            && presenter.editing && !presenter.finishEditing(text: "256", commit: true)
            && document.history.undoIndex == beforeBPM
            && presenter.finishEditing(text: "140", commit: true)
            && document.state.tempo.contains(where: {
                $0.tick == 48 && $0.microsecondsPerQuarterNote == 428_571
            })
            && document.history.undoIndex == beforeBPM + 1,
        cppID: id, message: "tempo BPM refuses outside 20 to 255 and commits 140 atomically")
    let beforeTick = document.history.undoIndex
    report.expect(
        presenter.beginEditing(row: tempo, column: 0)
            && presenter.finishEditing(text: "60", commit: true)
            && presenter.model.rows.contains(where: {
                $0.tempo?.tick == 60
                    && $0.tempo?.microsecondsPerQuarterNote == 428_571
            })
            && document.history.undoIndex == beforeTick + 1,
        cppID: id, message: "tempo tick commit relocates the same microseconds in one step")
    guard let moved = presenter.model.rows.firstIndex(where: { $0.tempo?.tick == 60 }) else {
        report.expect(false, cppID: id, message: "the moved tempo row is editable")
        return
    }
    let beforeRaw = document.history.undoIndex
    let beganRawEdit = presenter.beginEditing(row: moved, column: 1)
    let committedRawEdit = beganRawEdit && presenter.finishEditing(text: "10", commit: true)
    report.expect(
        committedRawEdit, cppID: id,
        message: "tempo-to-meta type commit is accepted")
    report.expect(
        document.history.undoIndex == beforeRaw + 1, cppID: id,
        message: "tempo-to-meta commit is one reversible undo step")
    report.expect(
        !document.state.tempo.contains(where: { $0.tick == 60 }),
        cppID: id, message: "tempo-to-meta commit removes the tick-60 tempo point")
    report.expect(
        !presenter.model.rows.contains(where: { $0.tempo?.tick == 60 }),
        cppID: id, message: "tempo-to-meta commit removes the tick-60 tempo row")
    report.expect(
        document.rawChunks[0].events.contains(where: { $0.tick == 60 && $0.isMeta }),
        cppID: id, message: "tempo-to-meta commit restores the tick-60 meta row")
    let rawUndo = document.history.undoDocument()
    report.expect(rawUndo, cppID: id, message: "tempo-to-meta undo succeeds")
    report.expect(
        document.state.tempo.contains(where: { $0.tick == 60 }),
        cppID: id, message: "tempo-to-meta undo restores the tick-60 tempo point")
    report.expect(
        presenter.model.rows.contains(where: { $0.tempo?.tick == 60 }),
        cppID: id, message: "tempo-to-meta undo restores the tick-60 tempo row")
    report.expect(
        !presenter.model.rows.contains(where: {
            $0.tick == 60 && $0.event?.isMeta == true
        }), cppID: id, message: "tempo-to-meta undo removes the tick-60 meta row")
    let rawRedo = document.history.redoDocument()
    report.expect(rawRedo, cppID: id, message: "tempo-to-meta redo succeeds")
    report.expect(
        presenter.model.rows.contains(where: {
            $0.tick == 60 && $0.event?.isMeta == true
        }), cppID: id, message: "tempo-to-meta redo restores the tick-60 meta row")
    report.expect(
        !presenter.model.rows.contains(where: { $0.tempo?.tick == 60 }),
        cppID: id, message: "tempo-to-meta redo removes the tick-60 tempo row")
}

@MainActor
internal func eventListDeleteMatrix(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .meta(tick: 0, type: 6, data: [1]),
                    .channel(tick: 12, status: 0xB0, data0: 7, data1: 80),
                    .channel(tick: 24, status: 0xB0, data0: 10, data1: 40),
                    .channel(tick: 36, status: 0xB0, data0: 1, data1: 20),
                ], endTick: 96)
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let presenter = EventListPresenter()
    session.onChange = { [weak presenter] change in presenter?.documentDidChange(change) }
    presenter.attach(session: session)
    presenter.setVisible(visible: true)
    let id = "swiftcore/EventList::deleteMatrix"
    report.expect(
        presenter.model.rows.contains(where: { $0.tick == 12 })
            && presenter.model.rows.contains(where: { $0.tick == 24 }), cppID: id,
        message: "the two deletion targets exist")
    guard let first = presenter.model.rows.firstIndex(where: { $0.tick == 12 }),
        let second = presenter.model.rows.firstIndex(where: { $0.tick == 24 })
    else {
        return
    }
    presenter.selectRow(row: first, modifiers: 0)
    presenter.selectRow(row: second, modifiers: 0x0400_0000)
    let before = document.history.undoIndex
    presenter.deleteSelected()
    report.expect(
        document.history.undoIndex == before + 1,
        cppID: id, message: "multi delete is one undo step")
    report.expect(
        !document.rawChunks[0].events.contains(where: { $0.tick == 12 || $0.tick == 24 }),
        cppID: id, message: "multi delete removes both raw events")
    report.expect(
        presenter.selectedRows.isEmpty, cppID: id,
        message: "multi delete clears selection and cursor in one step")
    report.expect(
        presenter.currentRow == -1, cppID: id,
        message: "multi delete clears the current row")
    report.expect(
        presenter.model.rows.contains(where: { $0.tick == 36 }), cppID: id,
        message: "the single deletion target survives")
    guard let single = presenter.model.rows.firstIndex(where: { $0.tick == 36 }) else {
        return
    }
    presenter.selectRow(row: single, modifiers: 0)
    presenter.deleteSelected()
    report.expect(
        !document.rawChunks[0].events.contains(where: { $0.tick == 36 }),
        cppID: id, message: "single delete removes the selected raw event")
    report.expect(
        (0..<presenter.rowCount).contains(presenter.currentRow),
        cppID: id, message: "single delete keeps the cursor on a valid row")
    presenter.selectRow(row: presenter.rowCount - 1, modifiers: 0)
    let beforeEOT = document.history.undoIndex
    presenter.deleteSelected()
    report.expect(
        document.history.undoIndex == beforeEOT
            && presenter.currentRow == presenter.rowCount - 1,
        cppID: id, message: "end-of-track-only delete leaves document and cursor unchanged")
}

@MainActor
internal func eventListRowMenuContract(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0xC0, data0: 5),
                    .channel(tick: 0, status: 0xB0, data0: 7, data1: 80),
                    .channel(tick: 0, status: 0xB0, data0: 10, data1: 40),
                ], endTick: 96)
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let presenter = EventListPresenter()
    session.onChange = { [weak presenter] change in presenter?.documentDidChange(change) }
    presenter.attach(session: session)
    presenter.setVisible(visible: true)
    let id = "swiftcore/EventList::rowMenuContract"
    var revealed = -1
    presenter.onRevealVoiceRequested = { revealed = $0 }
    presenter.selectRow(row: 0, modifiers: 0)
    presenter.openRowMenu(x: 0, y: 0)
    report.expect(
        presenter.menuItems.asArray.map(\.actionId) == [1, 2, 0, 3, 4, 0, 5],
        cppID: id, message: "program row menu exposes Insert Show voice separators Move and Delete")
    let programItems = presenter.menuItems.asArray
    let bindings = KeybindingRegistry()
    let up = bindings.sequences("eventlist.move_up").first
    let down = bindings.sequences("eventlist.move_down").first
    report.expect(
        down?.strokes.count == 1 && down?.nativeText.isEmpty == false,
        cppID: id, message: "A165 eventlist.move_down resolves to one native keybinding sequence")
    report.expect(
        programItems.map(\.text)
            == [
                "Insert event", "Show voice in voicegroup", "",
                "Move Event Up (Same Tick)", "Move Event Down (Same Tick)",
                "", "Delete 1 event(s)",
            ]
            && programItems[2].separator && programItems[5].separator
            && !programItems[3].enabled && programItems[4].enabled
            && programItems[3].shortcutText == up?.nativeText
            && programItems[4].shortcutText == down?.nativeText,
        cppID: id, message: "program menu paints canonical move labels bindings separators and availability")
    let source = document.rawChunks[0].events[0]
    let originals = document.rawChunks[0].events.filter { $0 == source }.count
    let beforeInsert = document.history.undoIndex
    let revisionBeforeInsert = document.revision
    session.editCursor = 72
    presenter.activateMenuAction(actionId: 1)
    report.expect(
        document.rawChunks[0].events.filter { $0 == source }.count == originals + 1
            && document.history.undoIndex == beforeInsert + 1
            && !document.rawChunks[0].events.contains(where: {
                $0.tick == 72 && $0.payload == source.payload
            }),
        cppID: id, message: "row-menu Insert copies the source at its own tick in one step")
    report.expect(
        document.revision == revisionBeforeInsert + 1, cppID: id,
        message: "rendered row-menu raw Insert advances the document revision exactly once")
    _ = document.history.undoDocument()
    presenter.selectRow(row: 0, modifiers: 0)
    presenter.openRowMenu(x: 0, y: 0)
    presenter.activateMenuAction(actionId: 2)
    report.expect(
        revealed == 5, cppID: id,
        message: "Show voice requests the program slot from the selected row")
    var routed: [Int] = []
    presenter.onPerformEventListCommand = { routed.append($0) }
    presenter.selectRow(row: 1, modifiers: 0)
    presenter.openRowMenu(x: 0, y: 0)
    presenter.activateMenuAction(actionId: 4)
    report.expect(
        routed == [EditCommand.moveEventDown.rawValue], cppID: id,
        message: "menu Move row routes the canonical command exactly once")
    presenter.selectRow(row: 1, modifiers: 0)
    presenter.selectRow(row: 2, modifiers: 0x0400_0000)
    presenter.openRowMenu(x: 0, y: 0)
    report.expect(
        presenter.menuItems.asArray.map(\.text)
            .contains("Delete 2 event(s)")
            && !presenter.menuItems.asArray.contains(where: { $0.actionId == 2 }),
        cppID: id, message: "control row menu hides Show voice and counts two deletable rows")
    presenter.dismissMenu()
    presenter.selectRow(row: presenter.rowCount - 1, modifiers: 0)
    presenter.openRowMenu(x: 0, y: 0)
    report.expect(
        presenter.menuItems.asArray.map(\.actionId) == [1, 0, 5]
            && presenter.menuItems.asArray[1].separator
            && !presenter.menuItems.asArray[2].enabled,
        cppID: id, message: "end row menu has Insert and disabled Delete without Move")
}

@MainActor
private func eventListFilterMatrix(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let events: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
        .meta(tick: 0, type: 0x58, data: [4, 2, 24, 8]),
        .meta(tick: 0, type: 0x06, data: Array("marker".utf8)),
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 8, status: 0xB0, data0: 7, data1: 80),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 30, status: 0x80, data0: 60),
        .channel(tick: 60, status: 0xB0, data0: 7, data1: 20),
        .channel(tick: 60, status: 0xB0, data0: 10, data1: 30),
        .channel(tick: 70, status: 0x90, data0: 64, data1: 70),
        .channel(tick: 90, status: 0x80, data0: 64),
    ]
    let document = SongDocument(
        file: MidiFile(division: 24, chunks: [MidiChunk(events: events, endTick: 120)]),
        config: suite.document.state.config, source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let presenter = EventListPresenter()
    presenter.attach(session: session)
    presenter.setVisible(visible: true)
    let id = "eventviews/EventViewsChromeTest::filterMatrix"
    report.expect(
        presenter.rowCount == 12, cppID: id,
        message: "all categories expose eleven events and the end row")
    presenter.openFilterMenu(x: 0, y: 0)
    for (bit, remaining, category) in [
        (64, 9, "meta"), (1, 5, "notes"),
        (2, 2, "controls"), (4, 1, "program"),
        (8, 1, "bend"), (16, 1, "aftertouch"),
        (32, 1, "SysEx"),
    ] {
        presenter.activateMenuAction(actionId: bit)
        report.expect(
            presenter.rowCount == remaining, cppID: id,
            message: "hiding \(category) leaves its ledger row count")
    }
    report.expect(
        presenter.model.rows.count == 1
            && presenter.model.rows[0].isEndOfTrack, cppID: id,
        message: "an empty mask leaves only the EOT row")
    for bit in [64, 1, 2, 4, 8, 16, 32] {
        presenter.activateMenuAction(actionId: bit)
    }
    report.expect(
        presenter.rowCount == 12, cppID: id,
        message: "restoring every category restores eleven event rows")
}

@MainActor
private func eventListMenuInvalidation(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xB0, data0: 7, data1: 80),
                        .channel(tick: 12, status: 0xB0, data0: 10, data1: 40),
                    ], endTick: 96),
                MidiChunk(events: [.meta(tick: 12, type: 6, data: [1])], endTick: 96),
            ]), config: suite.document.state.config, source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let presenter = EventListPresenter()
    session.onChange = { [weak presenter] change in presenter?.documentDidChange(change) }
    presenter.attach(session: session)
    presenter.setVisible(visible: true)
    let id = "eventviews/EventViewsChromeTest::rowMenu"
    presenter.selectRow(row: 0, modifiers: 0)
    presenter.openRowMenu(x: 0, y: 0)
    presenter.focusRow(row: 1)
    report.expect(
        !presenter.menuOpen && presenter.currentRow == 1, cppID: id,
        message: "a moved row context retires the row menu")
    presenter.openRowMenu(x: 0, y: 0)
    presenter.selectRow(row: 0, modifiers: 0x0400_0000)
    report.expect(
        !presenter.menuOpen, cppID: id,
        message: "a selection change retires the row menu")
    presenter.openRowMenu(x: 0, y: 0)
    presenter.setChunk(index: 1)
    report.expect(
        !presenter.menuOpen && presenter.chunkIndex == 1, cppID: id,
        message: "a chunk switch retires the row menu")
    presenter.setChunk(index: 0)
    presenter.selectRow(row: 0, modifiers: 0)
    presenter.openRowMenu(x: 0, y: 0)
    let revisionBeforeRawInsert = document.revision
    let undoBeforeRawInsert = document.history.undoIndex
    document.insertRawEvent(
        chunk: 0,
        event: .channel(
            tick: 118, status: 0xB0, data0: 7, data1: 64))
    report.expect(
        !presenter.menuOpen, cppID: id,
        message: "a document edit retires the row menu")
    report.expect(
        document.revision == revisionBeforeRawInsert + 1
            && document.history.undoIndex == undoBeforeRawInsert + 1,
        cppID: id, message: "a raw insertion under an open row menu advances revision and undo once")
    presenter.openFilterMenu(x: 0, y: 0)
    presenter.focusRow(row: 1)
    report.expect(
        presenter.menuOpen && presenter.currentRow == 1,
        cppID: id, message: "row changes leave the filter menu open")
}

@MainActor
private func eventListScopedSnapshots(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(tick: 0, type: 6, data: [1])], endTick: 192),
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xC0, data0: 0),
                        .channel(tick: 0, status: 0x90, data0: 60, data1: 80),
                        .channel(tick: 12, status: 0x80, data0: 60),
                        .channel(tick: 24, status: 0xB0, data0: 7, data1: 64),
                    ], endTick: 192),
                MidiChunk(
                    events: [
                        .channel(tick: 48, status: 0x91, data0: 67, data1: 90),
                        .channel(tick: 72, status: 0x81, data0: 67),
                    ], endTick: 192),
            ]), config: suite.document.state.config, source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    session.selectedTrack = 0
    let presenter = EventListPresenter()
    var observedDocumentEffects = DocumentEditEffects()
    session.onChange = { [weak presenter] change in
        if change.domains.contains(.document) { observedDocumentEffects = change.editEffects }
        presenter?.documentDidChange(change)
    }
    presenter.attach(session: session, chunkIndex: 1)
    presenter.setVisible(visible: true)
    presenter.selectRow(row: 1, modifiers: 0)
    let retainedModel = presenter.model
    let retainedRow = presenter.rowHandle(row: 1)
    let retainedSecondary = document.rawChunks[2]
    guard let secondary = document.notes(in: 1).first,
        let primary = session.projectionCache.notes(in: 0).first,
        let oldLanePoint = session.projectionCache.lanePoints(track: 0, lane: .controller(7)).first
    else {
        report.fail(pageID, "the scoped source fixture exposes both notes and its controller")
        return
    }
    document.moveNotes([secondary.id], byTicks: 12, byKeys: 1)
    report.expect(
        presenter.model.chunk == retainedModel.chunk && presenter.currentRow == 1
            && presenter.selectedRows == [1] && presenter.rowHandle(row: 1) === retainedRow,
        cppID: pageID, message: "editing another chunk retains the visible rows, focus and selection")
    presenter.setChunk(index: 2)
    report.expect(
        presenter.model.chunk.events.contains { $0.noteID == secondary.id && $0.tick == 60 }
            && retainedSecondary.events.contains { $0.noteID == secondary.id && $0.tick == 48 },
        cppID: pageID, message: "switching into the edited chunk reads new data without mutating its old snapshot")
    presenter.setChunk(index: 1)
    document.moveNotes([primary.id], byTicks: 36, byKeys: 0)
    guard let freshLanePoint = session.projectionCache.lanePoints(track: 0, lane: .controller(7)).first
    else {
        report.fail(pageID, "the controller survives the note crossing")
        return
    }
    report.expect(
        freshLanePoint.eventIndex != oldLanePoint.eventIndex
            && document.rawChunks[freshLanePoint.chunk].events[freshLanePoint.eventIndex].payload
                == .channel(status: 0xB0, data0: 7, data1: 64)
            && session.projectionCache.note(primary.id, in: 0)?.tick == 36
            && primary.tick == 0 && retainedModel.chunk.events[1].tick == 0,
        cppID: pageID,
        message: "a note crossing refreshes event offsets and notes while retained sources stay unchanged")
    report.expect(
        presenter.model.chunk.events.contains { $0.noteID == primary.id && $0.tick == 36 },
        cppID: pageID, message: "the affected event-list source displays the moved note")
    report.expect(document.history.undoDocument(), cppID: pageID, message: "the crossing undoes")
    report.expect(
        session.projectionCache.note(primary.id, in: 0)?.tick == 0
            && presenter.model.chunk.events.contains { $0.noteID == primary.id && $0.tick == 0 },
        cppID: pageID, message: "undo restores both projected notes and visible raw-event data")
    report.expect(document.history.redoDocument(), cppID: pageID, message: "the crossing redoes")
    guard let editablePoint = session.projectionCache.lanePoints(track: 0, lane: .controller(7)).first
    else {
        report.fail(pageID, "redo restores the editable controller occurrence")
        return
    }
    document.moveLanePoints(
        track: 0, lane: .controller(7),
        moves: [LanePointMove(point: editablePoint, tick: editablePoint.tick, value: 91)])
    report.expect(
        document.lanePoints(track: 0, lane: .controller(7)).first?.value == 91
            && document.note(primary.id)?.tick == 36 && document.note(primary.id)?.velocity == 80
            && presenter.model.chunk.events.contains { $0.payload == .channel(status: 0xB0, data0: 7, data1: 91) },
        cppID: pageID, message: "a lane edit after redo targets the controller, not the shifted note event")
    session.setSelectedNotes([primary.id])
    guard let beforeControllerInsert = session.projectionCache.note(primary.id, in: 0),
        let previousEndIndex = beforeControllerInsert.endIndex
    else {
        report.fail(pageID, "the selected note exposes both cached raw-event offsets")
        return
    }
    let retainedChunk = document.rawChunks[beforeControllerInsert.chunk]
    let unaffectedNotes = session.projectionCache.notes(in: 1)
    document.writeLane(
        track: 0, lane: .controller(10), from: 12, through: 12,
        points: [LaneWrite(tick: 12, value: 45)])
    guard let freshNote = session.projectionCache.note(primary.id, in: 0),
        let freshEndIndex = freshNote.endIndex
    else {
        report.fail(pageID, "controller insertion retains the selected note and its ending")
        return
    }
    let events = document.rawChunks[freshNote.chunk].events
    report.expect(
        observedDocumentEffects.flags.contains(.lanes) && !observedDocumentEffects.flags.contains(.notes)
            && freshNote.onIndex == beforeControllerInsert.onIndex + 1
            && freshEndIndex == previousEndIndex + 1
            && events[freshNote.onIndex].noteID == primary.id
            && events[freshEndIndex].tick == 48
            && events[freshEndIndex].payload == .channel(status: 0x80, data0: primary.pitch, data1: 0)
            && retainedChunk.events[beforeControllerInsert.onIndex].noteID == primary.id
            && retainedChunk.events[previousEndIndex].tick == 48
            && session.projectionCache.notes(in: 1) == unaffectedNotes,
        cppID: pageID,
        message:
            "inserting a controller before a cached note refreshes both raw offsets and retains old and unaffected sources"
    )
    let selectedNotes = session.selectedNoteOrder.compactMap {
        session.projectionCache.note($0, in: 0)
    }
    report.expect(
        selectedNotes.count == 1 && document.moveRange(notes: selectedNotes, points: [], by: 12),
        cppID: pageID, message: "selected range movement accepts the fresh cached offsets after controller insertion")
    report.expect(
        document.note(primary.id)?.tick == 48 && document.note(primary.id)?.endTick == 60
            && document.note(primary.id)?.pitch == primary.pitch
            && document.note(primary.id)?.velocity == primary.velocity
            && document.lanePoints(track: 0, lane: .controller(10)).first?.tick == 12
            && document.lanePoints(track: 0, lane: .controller(10)).first?.value == 45
            && document.lanePoints(track: 0, lane: .controller(7)).first?.value == 91
            && presenter.model.chunk.events.contains { $0.noteID == primary.id && $0.tick == 48 },
        cppID: pageID,
        message:
            "the selected range edit moves the intended note pair, preserves both controllers and publishes current event rows"
    )
}
