import Foundation
import PorydawApp
import PorydawAppEventList
import PorydawCore
import PorydawDocument

@MainActor
internal func followScroll(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .long)
    // A034: direct fixture construction replaces the native long-rig open guard.
    report.expect(
        fixture.session.document.rawChunks.indices.contains(0), cppID: followScrollID,
        message: "A034 long fixture has a primary chunk")
    // A035: attachment replaces the native EventWidgets lookup guard.
    report.expect(
        fixture.presenter.attached && fixture.presenter.rowCount > 100,
        cppID: followScrollID, message: "A035 long event-list presenter is attached")

    var callbacks: [Int] = []
    fixture.presenter.onScrollToRow = { callbacks.append($0) }
    // A036: the installed callback is the Swift equivalent of a valid scroll spy.
    report.expect(
        fixture.presenter.onScrollToRow != nil, cppID: followScrollID,
        message: "A036 scroll-to-row observer is valid")

    let eot = fixture.presenter.rowCount - 1
    let pastEnd = Double(fixture.presenter.model.rows[eot].tick + 10)
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    fixture.presenter.setFollowPlayhead(enabled: true)
    callbacks.removeAll()
    let requestsBeforeFollow = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A037: free follow emits a request targeting the playing EOT row.
    report.expect(
        !callbacks.isEmpty && callbacks.last == eot
            && fixture.presenter.lastScrollToRow == eot
            && fixture.presenter.scrollToRowRequested > requestsBeforeFollow,
        cppID: followScrollID, message: "A037 free follow scrolls to the playing row")

    callbacks.removeAll()
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    fixture.presenter.setPointerDown(down: true)
    let requestsBeforePointer = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A038: pointer-held state suppresses auto-scroll.
    report.expect(
        callbacks.isEmpty
            && fixture.presenter.scrollToRowRequested == requestsBeforePointer,
        cppID: followScrollID, message: "A038 pointer-held state suppresses scroll")
    // A039: pointer suppression does not suppress transport tint.
    report.expect(
        tintedRows(fixture.presenter) == [eot]
            && hasExactTintContract(fixture.presenter, expected: eot),
        cppID: followScrollID, message: "A039 pointer-held state retains EOT tint")
    fixture.presenter.setPointerDown(down: false)

    callbacks.removeAll()
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    let editing = fixture.presenter.beginEditing(row: eot, column: 0)
    // A040: the sentinel tick cell opens a real presenter editing session.
    report.expect(
        editing, cppID: followScrollID,
        message: "A040 EOT tick cell begins editing")
    let requestsBeforeEditing = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A041: in-cell editing suppresses auto-scroll.
    report.expect(
        callbacks.isEmpty
            && fixture.presenter.scrollToRowRequested == requestsBeforeEditing,
        cppID: followScrollID, message: "A041 editing state suppresses scroll")
    // A042: editing suppression does not suppress transport tint.
    report.expect(
        tintedRows(fixture.presenter) == [eot]
            && hasExactTintContract(fixture.presenter, expected: eot),
        cppID: followScrollID, message: "A042 editing state retains EOT tint")
    _ = fixture.presenter.finishEditing(text: "", commit: false)

    callbacks.removeAll()
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    fixture.presenter.setFollowPlayhead(enabled: false)
    let requestsBeforeDisabledFollow = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A043: disabling follow prevents any scroll request.
    report.expect(
        callbacks.isEmpty
            && fixture.presenter.scrollToRowRequested == requestsBeforeDisabledFollow,
        cppID: followScrollID, message: "A043 follow-off state suppresses scroll")
    // A044: follow-off still updates the transport tint.
    report.expect(
        tintedRows(fixture.presenter) == [eot]
            && hasExactTintContract(fixture.presenter, expected: eot),
        cppID: followScrollID, message: "A044 follow-off state retains EOT tint")
    fixture.presenter.setFollowPlayhead(enabled: true)
}

@MainActor
internal func eventListRowsAndEditContract(_ report: CheckReport) {
    let empty = MidiChunk(events: [], endTick: 24)
    let coincident = MidiChunk(
        events: [
            .channel(tick: 48, status: 0x90, data0: 60, data1: 100)
        ], endTick: 48)
    let multiple = MidiChunk(
        events: [
            .channel(status: 0xC0, data0: 1),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 100),
            .meta(tick: 24, type: 0x06, data: [0x61]),
            .systemExclusive(tick: 36, status: 0xF0, data: [0x7D]),
            .systemExclusive(tick: 40, status: 0xF7, data: [0x7E]),
        ], endTick: 60)
    let file = MidiFile(division: 24, chunks: [empty, coincident, multiple])
    let expectedTypes: [[Int]] = [
        [],
        [EventListEventType.noteOn.rawValue],
        [
            EventListEventType.program.rawValue, EventListEventType.noteOn.rawValue,
            EventListEventType.meta.rawValue, EventListEventType.sysEx0.rawValue,
            EventListEventType.sysEx7.rawValue,
        ],
    ]
    var model = EventListModel()
    report.expectEqual(
        expected: 0, actual: model.rowCount, cppID: rowsAndEditContractID,
        what: "detached model has no EOT row")
    for (index, chunk) in file.chunks.enumerated() {
        model.setSource(chunk)
        report.expectEqual(
            expected: chunk.events.count + 1, actual: model.rowCount,
            cppID: rowsAndEditContractID,
            what: "shape \(index) has one EOT row after its events")
        report.expectEqual(
            expected: chunk.endTick, actual: model.rowTick(row: chunk.events.count),
            cppID: rowsAndEditContractID,
            what: "shape \(index) EOT tick mirrors the chunk end")
        report.expectEqual(
            expected: expectedTypes[index] + [EventListEventType.endOfTrack.rawValue],
            actual: model.rows.map(\.typeKind), cppID: rowsAndEditContractID,
            what: "shape \(index) projects each event type and EOT")
        report.expect(
            model.rows.last?.isEndOfTrack == true
                && model.rows.dropLast().allSatisfy { !$0.isEndOfTrack },
            cppID: rowsAndEditContractID,
            message: "shape \(index) has exactly one EOT sentinel")
    }

    let eot = model.rowCount - 1
    report.expect(
        model.isCellEditable(row: eot, column: 0)
            && !(1..<EventListModel.columnCount).contains { model.isCellEditable(row: eot, column: $0) }
            && !model.isCellEditable(row: -1, column: 0),
        cppID: rowsAndEditContractID, message: "only the EOT tick cell is editable")
    report.expect(
        model.isCellEditable(row: 1, column: 2)
            && !model.isCellEditable(row: 2, column: 2)
            && !model.isCellEditable(row: 3, column: 2)
            && model.isCellEditable(row: 2, column: 5)
            && model.isCellEditable(row: 3, column: 5)
            && model.isCellEditable(row: 4, column: 5)
            && !model.isCellEditable(row: 1, column: 5),
        cppID: rowsAndEditContractID, message: "channel and blob cells follow event kind")
    report.expect(
        model.validatesEdit(row: eot, column: 0, text: String(TimeDefaults.maxTick))
            && !model.validatesEdit(row: eot, column: 0, text: String(TimeDefaults.maxTick + 1))
            && !model.validatesEdit(row: eot, column: 0, text: "-1"),
        cppID: rowsAndEditContractID, message: "tick editing honors maxTick")
    report.expect(
        model.validatesEdit(row: 1, column: 1, text: "10")
            && !model.validatesEdit(row: 1, column: 1, text: "9")
            && model.validatesEdit(row: 1, column: 2, text: "1")
            && model.validatesEdit(row: 1, column: 2, text: "16")
            && !model.validatesEdit(row: 1, column: 2, text: "0")
            && !model.validatesEdit(row: 1, column: 2, text: "17"),
        cppID: rowsAndEditContractID, message: "type IDs and channel bounds are validated")
    report.expect(
        model.validatesEdit(row: 1, column: 3, text: "0")
            && model.validatesEdit(row: 1, column: 4, text: "127")
            && !model.validatesEdit(row: 1, column: 3, text: "-1")
            && !model.validatesEdit(row: 1, column: 4, text: "128")
            && model.validatesEdit(row: 2, column: 5, text: "AA")
            && model.validatesEdit(row: 3, column: 5, text: "7D")
            && !model.validatesEdit(row: 2, column: 5, text: "  ")
            && !model.validatesEdit(row: 3, column: 5, text: ""),
        cppID: rowsAndEditContractID, message: "data bytes and blob contents are validated")
    model.setPlayheadTick(36)
    report.expectEqual(
        expected: 3, actual: model.playRow, cppID: rowsAndEditContractID,
        what: "transport chooses the SysEx row")
    report.expect(
        model.rows.filter { model.rowTint(row: $0.index) != nil }.map(\.index) == [model.playRow]
            && model.rowTint(row: model.playRow) == EventListModel.playheadTint,
        cppID: rowsAndEditContractID, message: "exactly the playing row is tinted")
    model.detach()
    report.expectEqual(
        expected: 0, actual: model.rowCount, cppID: rowsAndEditContractID,
        what: "detaching clears all rows")
}

@MainActor
internal func eventListRemapAnchorAndProjection(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    let session = fixture.session
    let presenter = fixture.presenter
    var remaps: [TrackRemap] = []
    session.onChange = { [weak presenter] change in
        if let remap = change.trackRemap { remaps.append(remap) }
        presenter?.documentDidChange(change)
    }
    presenter.setChunk(index: 2)
    presenter.focusRow(row: 2)
    let initialCount = presenter.rowCount
    report.expectEqual(
        expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
        what: "initial chunk holds the focused event row")

    let moved = session.document.moveTrack(1, to: 0)
    report.expect(
        moved && remaps.last?.chunkMap[2] == 0,
        cppID: remapAnchorAndProjectionID,
        message: "moving the second track publishes its chunk remap")
    report.expectEqual(
        expected: 0, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
        what: "chunk anchor follows the move")
    report.expectEqual(
        expected: session.document.rawChunks[0].events.count + 1, actual: presenter.rowCount,
        cppID: remapAnchorAndProjectionID,
        what: "moved chunk projects its current event count and EOT")
    report.expectEqual(
        expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
        what: "document remap preserves in-range row focus")

    _ = session.document.history.undoDocument()
    report.expectEqual(
        expected: 2, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
        what: "undo restores the chunk anchor")
    report.expectEqual(
        expected: initialCount, actual: presenter.rowCount, cppID: remapAnchorAndProjectionID,
        what: "undo restores the initial projection")
    report.expectEqual(
        expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
        what: "undo retains in-range row focus")
    _ = session.document.history.redoDocument()
    report.expectEqual(
        expected: 0, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
        what: "redo follows the moved chunk again")
    report.expectEqual(
        expected: session.document.rawChunks[0].events.count + 1, actual: presenter.rowCount,
        cppID: remapAnchorAndProjectionID,
        what: "redo rebuilds the moved chunk projection")
    report.expectEqual(
        expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
        what: "redo retains in-range row focus")

    presenter.setChunk(index: 1)
    report.expectEqual(
        expected: -1, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
        what: "explicit chunk switch resets row focus")
    presenter.focusRow(row: 2)
    session.document.deleteTrack(1)
    report.expect(
        remaps.last?.chunkMap[1] == .some(nil),
        cppID: remapAnchorAndProjectionID,
        message: "deletion publishes an unmapped original chunk")
    report.expectEqual(
        expected: -1, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
        what: "deleting the selected chunk clears its anchor")
    report.expectEqual(
        expected: 0, actual: presenter.rowCount, cppID: remapAnchorAndProjectionID,
        what: "deleted chunk has no projected rows")
    report.expectEqual(
        expected: -1, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
        what: "deleting the selected chunk clears row focus")
    _ = session.document.history.undoDocument()
    report.expect(
        presenter.chunkIndex == -1 && presenter.rowCount == 0
            && presenter.currentRow == -1,
        cppID: remapAnchorAndProjectionID,
        message: "undoing deletion leaves the unselected anchor empty")
    _ = session.document.history.redoDocument()
    report.expect(
        presenter.chunkIndex == -1 && presenter.rowCount == 0
            && presenter.currentRow == -1,
        cppID: remapAnchorAndProjectionID,
        message: "redoing deletion leaves the unselected anchor empty")
}
