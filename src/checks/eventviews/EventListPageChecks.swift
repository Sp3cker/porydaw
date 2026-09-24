import Foundation
import PorydawApp
import PorydawCore

private let pageID = "swiftcore/EventList::pageInteraction"

@MainActor
internal func runEventListPageChecks(_ report: CheckReport, session suite: DocumentSession,
                                     service: ProjectService) {
    let file = MidiFile(division: 24, chunks: [MidiChunk(events: [
        .meta(tick: 0, type: 6, data: Array("mark".utf8)),
        .channel(tick: 12, status: 0xB0, data0: 7, data1: 80),
        .channel(tick: 12, status: 0xB0, data0: 10, data1: 40),
        .channel(tick: 24, status: 0x90, data0: 60, data1: 80),
        .channel(tick: 48, status: 0x80, data0: 60, data1: 0),
    ], endTick: 96)])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source,
                                trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
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
    report.expect(presenter.selectedRows == [firstCC, secondCC], cppID: pageID,
                  message: "Control-click adds the second control without dropping the first")
    presenter.selectRow(row: note, modifiers: 0x0200_0000)
    report.expect(presenter.selectedRows == Array(firstCC...note), cppID: pageID,
                  message: "Shift-click extends a contiguous range from the anchor")

    report.expect(presenter.isLegalDrop(fromRow: firstCC, gap: secondCC + 1),
                  cppID: pageID, message: "a same-tick insertion gap permits reordering")
    report.expect(!presenter.isLegalDrop(fromRow: firstCC, gap: note + 1),
                  cppID: pageID, message: "a cross-tick insertion gap rejects reordering")
    presenter.commitDrop(fromRow: firstCC, gap: secondCC + 1)
    report.expect(document.rawChunks[0].events[1].payload
                  == .channel(status: 0xB0, data0: 10, data1: 40)
                  && document.rawChunks[0].events[2].payload
                     == .channel(status: 0xB0, data0: 7, data1: 80),
                  cppID: pageID, message: "legal row drag swaps the two same-tick events")
    let control = presenter.model.rows.firstIndex { $0.eventIndex == 2 }
    guard let control else { return }
    report.expect(presenter.beginEditing(row: control, column: 3), cppID: pageID,
                  message: "a controller number enters cell editing")
    report.expect(!presenter.finishEditing(text: "500", commit: true) && presenter.editing,
                  cppID: pageID, message: "out-of-range input keeps the cell editor active")
    report.expect(presenter.finishEditing(text: "65", commit: true)
                  && document.rawChunks[0].events[2].payload
                     == .channel(status: 0xB0, data0: 65, data1: 80),
                  cppID: pageID, message: "valid input commits a controller number to the song")
    report.expect(document.history.undoDocument()
                  && document.rawChunks[0].events[2].payload
                     == .channel(status: 0xB0, data0: 7, data1: 80),
                  cppID: pageID, message: "cell edit is a reversible document transaction")

    document.editTempo(TempoEdit(add: [TempoPoint(
        tick: 36, microsecondsPerQuarterNote: 600_000)]))
    report.expect(presenter.model.rows.contains(where: { $0.tempo?.tick == 36 }),
                  cppID: pageID, message: "tempo changes appear as editable rows")
    presenter.openFilterMenu(x: 0, y: 0)
    presenter.activateMenuAction(actionId: 64)
    report.expect(!presenter.model.rows.contains(where: { $0.tempo != nil || $0.event?.isMeta == true })
                  && presenter.model.rows.last?.isEndOfTrack == true,
                  cppID: pageID, message: "meta filter hides tempo/meta but retains the end row")
    presenter.activateMenuAction(actionId: 64)
    report.expect(presenter.model.rows.contains(where: { $0.tempo?.tick == 36 }),
                  cppID: pageID, message: "re-enabled meta filter restores tempo rows")
    presenter.dismissMenu()

    presenter.selectAll()
    report.expect(presenter.selectedRows.count == presenter.rowCount, cppID: pageID,
                  message: "Select All includes every visible row")
    guard let protectedID = document.rawChunks[0].events.first(where: { $0.isNoteOn })?.noteID,
          let originalNote = document.note(protectedID),
          let firstVictim = presenter.model.rows.firstIndex(where: { $0.eventIndex == 1 }),
          let secondVictim = presenter.model.rows.firstIndex(where: { $0.eventIndex == 2 }) else {
        return
    }
    session.setSelectedNotes([protectedID])
    presenter.selectRow(row: firstVictim, modifiers: 0)
    presenter.selectRow(row: secondVictim, modifiers: 0x0400_0000)
    report.expect(presenter.selectedRows == [firstVictim, secondVictim], cppID: pageID,
                  message: "the two intended victim rows, not the note, are selected")
    let beforeDeletion = document.rawChunks[0].events.count
    let beforeRows = presenter.rowCount
    presenter.deleteSelected()
    report.expect(document.rawChunks[0].events.count == beforeDeletion - 2
                  && !document.rawChunks[0].events.contains(where: {
                      $0.isChannel && $0.typeNibble == 0xB
                  }),
                  cppID: pageID, message: "Delete removes exactly the two selected raw rows")
    report.expect(presenter.rowCount == beforeRows - 2, cppID: pageID,
                  message: "Delete removes two visible rows without dropping EOT")
    let survivingNote = document.note(protectedID)
    report.expect(session.selectedNotes.contains(protectedID)
                  && survivingNote?.tick == originalNote.tick
                  && survivingNote?.pitch == originalNote.pitch
                  && survivingNote?.duration == originalNote.duration
                  && survivingNote?.isUnterminated == false,
                  cppID: pageID, message: "Delete leaves the unrelated selected note intact")
}
