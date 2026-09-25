import Foundation
import PorydawApp
import PorydawAppEventList
import PorydawCore

private let tintLastOfRunID = "eventviews/EventViewsPlayheadTest::tintLastOfRun"
private let focusCommitsCursorID = "eventviews/EventViewsPlayheadTest::focusCommitsCursor"
private let focusedSiblingWinsID = "eventviews/EventViewsPlayheadTest::focusedSiblingWins"
private let samplePathAndProgrammaticRestoreID =
    "eventviews/EventViewsPlayheadTest::samplePathAndProgrammaticRestore"
private let followScrollID = "eventviews/EventViewsPlayheadTest::followScroll"
private let rowsAndEditContractID = "swiftcore/EventList::eventListRowsAndEditContract"
private let remapAnchorAndProjectionID = "swiftcore/EventList::eventListRemapAnchorAndProjection"

private enum EventListPlayheadShape {
    case basic
    case long
}

@MainActor
private final class EventListPlayheadFixture {
    let session: DocumentSession
    let presenter: EventListPresenter

    init(suite: DocumentSession, service: ProjectService, shape: EventListPlayheadShape) {
        let document = SongDocument(
            file: eventListPlayheadFile(shape),
            config: suite.document.state.config,
            source: suite.document.source,
            trackBudget: suite.document.trackBudget)
        let presenter = EventListPresenter()
        let session = DocumentSession(
            document: document,
            service: service,
            lease: suite.bankLease,
            slots: suite.bankSlots,
            dirty: false,
            loadName: suite.bankLoadName,
            sampleRate: 48_000)
        self.session = session
        self.presenter = presenter

        // The production workspace routes document publications to the event-list presenter.
        // Keep that observable contract in this presenter-only fixture as well.
        session.onChange = { [weak presenter] change in
            presenter?.documentDidChange(change)
        }
        presenter.attach(session: session, chunkIndex: 0)
    }
}

private func eventListPlayheadFile(_ shape: EventListPlayheadShape) -> MidiFile {
    var primary: [MidiEvent] = [
        .meta(tick: 0, type: 0x58, data: [4, 2, 0x18, 8]),
        .meta(tick: 0, type: 0x06, data: Array("fixture marker".utf8)),
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 8, status: 0xB0, data0: 7, data1: 80),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 30, status: 0x80, data0: 60),
        .meta(tick: 50, type: 0x58, data: [3, 2, 0x18, 8]),
        .channel(tick: 60, status: 0xB0, data0: 7, data1: 20),
        .channel(tick: 60, status: 0xB0, data0: 10, data1: 30),
        .channel(tick: 70, status: 0x90, data0: 64, data1: 70),
        .channel(tick: 90, status: 0x80, data0: 64),
    ]
    let endTick: Tick
    switch shape {
    case .basic:
        endTick = 120
    case .long:
        endTick = 500
        for tick in 100..<500 {
            primary.append(.channel(tick: Tick(tick), status: 0xB0, data0: 11,
                                    data1: UInt8(tick % 127)))
        }
    }

    return MidiFile(division: 24, chunks: [
        MidiChunk(events: primary, endTick: endTick),
        MidiChunk(events: [
            .meta(tick: 5, type: 0x06, data: Array("metadata only".utf8)),
        ], endTick: 120),
        MidiChunk(events: [
            .channel(status: 0xC1, data0: 1),
            .channel(tick: 24, status: 0xB1, data0: 7, data1: 64),
            .channel(tick: 48, status: 0x91, data0: 67, data1: 90),
            .channel(tick: 72, status: 0x81, data0: 67),
        ], endTick: 120),
    ])
}

private func playheadRowOracle(_ rows: [EventListRow], tick: Double) -> Int {
    guard let eot = rows.last, eot.isEndOfTrack else { return -1 }
    if tick < 0 { return -1 }
    if tick >= Double(eot.tick) { return eot.index }

    var row = -1
    for item in rows.dropLast() {
        if Double(item.tick) > tick { break }
        row = item.index
    }
    return row
}

@MainActor private func rowFor(_ presenter: EventListPresenter, tick: Tick,
                   kind: EventListEventType) -> Int? {
    presenter.model.rows.first { $0.tick == tick && $0.kind == kind }?.index
}

@MainActor private func tintedRows(_ presenter: EventListPresenter) -> [Int] {
    presenter.model.rows.compactMap { row in
        presenter.isRowTinted(row: row.index) ? row.index : nil
    }
}

@MainActor private func hasExactTintContract(_ presenter: EventListPresenter, expected: Int) -> Bool {
    presenter.model.rows.allSatisfy { row in
        let shouldTint = row.index == expected
        let actualTinted = presenter.isRowTinted(row: row.index)
        let actualColor = presenter.rowTint(row: row.index)
        return actualTinted == shouldTint
            && actualColor == (shouldTint ? EventListModel.playheadTint : "")
    }
}

@MainActor
internal func runEventListPlayheadChecks(_ report: CheckReport, session suite: DocumentSession,
                                         service: ProjectService) {
    tintLastOfRun(report, suite: suite, service: service)
    focusCommitsCursor(report, suite: suite, service: service)
    focusedSiblingWins(report, suite: suite, service: service)
    samplePathAndProgrammaticRestore(report, suite: suite, service: service)
    followScroll(report, suite: suite, service: service)
    eventListRowsAndEditContract(report)
    eventListRemapAnchorAndProjection(report, suite: suite, service: service)
    runEventListPageChecks(report, session: suite, service: service)
}

@MainActor
private func tintLastOfRun(_ report: CheckReport, suite: DocumentSession,
                           service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A001: the Swift value fixture is constructed directly, so the native open-rig failure
    // path is represented by the attached source invariant below.
    report.expect(fixture.session.document.rawChunks.indices.contains(0), cppID: tintLastOfRunID,
                  message: "A001 basic fixture has a primary chunk")
    // A002: presenter attachment is the Swift equivalent of locating EventWidgets.
    report.expect(fixture.presenter.attached && fixture.presenter.rowCount > 0,
                  cppID: tintLastOfRunID, message: "A002 event-list presenter is attached")

    let rows = fixture.presenter.model.rows
    let cases: [(Double, String)] = [
        (1, "before first event uses the last row at or before the tick"),
        (60, "same-tick run uses the last row in the run"),
        (130, "past end uses the end-of-track row"),
    ]
    for (tick, explanation) in cases {
        let expected = playheadRowOracle(rows, tick: tick)
        fixture.presenter.setPlayheadTick(tick: tick, playing: true)
        // A003: controller playRow follows the independent row oracle.
        report.expectEqual(expected: expected, actual: fixture.presenter.playRow, cppID: tintLastOfRunID,
                           what: "A003 \(explanation) at tick \(tick)")
        // A004: only one complete row has the playhead tint, with the stable bridge color.
        report.expect(tintedRows(fixture.presenter) == (expected >= 0 ? [expected] : [])
            && hasExactTintContract(fixture.presenter, expected: expected),
            cppID: tintLastOfRunID,
            message: "A004 whole-row tint matches the oracle at tick \(tick)")
    }

    fixture.presenter.setPlayheadTick(tick: -1, playing: false)
    // A005: a negative transport tick clears the published play row.
    report.expectEqual(expected: -1, actual: fixture.presenter.playRow, cppID: tintLastOfRunID,
                       what: "A005 negative tick clears playRow")
    // A006: clearing playRow clears every presenter/model tint.
    report.expect(tintedRows(fixture.presenter).isEmpty
        && hasExactTintContract(fixture.presenter, expected: -1),
        cppID: tintLastOfRunID, message: "A006 negative tick leaves no tinted row")
}

@MainActor
private func focusCommitsCursor(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A007: direct fixture construction replaces the native rig-open guard.
    report.expect(fixture.session.document.rawChunks.indices.contains(0), cppID: focusCommitsCursorID,
                  message: "A007 basic fixture has a primary chunk")
    // A008: attachment replaces the native EventWidgets lookup guard.
    report.expect(fixture.presenter.attached, cppID: focusCommitsCursorID,
                  message: "A008 event-list presenter is attached")

    let eventRow = rowFor(fixture.presenter, tick: 70, kind: .noteOn)
    // A009: the NoteOn row lookup succeeds in the fixture.
    report.expect(eventRow != nil, cppID: focusCommitsCursorID,
                  message: "A009 NoteOn row at tick 70 exists")
    guard let eventRow else { return }

    fixture.presenter.focusRow(row: eventRow)
    // A010: focusing an event commits its tick to the session edit cursor.
    report.expectEqual(expected: Tick(70), actual: fixture.session.editCursor, cppID: focusCommitsCursorID,
                       what: "A010 focusing NoteOn commits tick 70")

    fixture.presenter.focusRow(row: fixture.presenter.rowCount - 1)
    // A011: focusing the sentinel commits the chunk end tick.
    report.expectEqual(expected: Tick(120), actual: fixture.session.editCursor, cppID: focusCommitsCursorID,
                       what: "A011 focusing EOT commits end tick 120")
}

@MainActor
private func focusedSiblingWins(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A012: direct fixture construction replaces the native rig-open guard.
    report.expect(fixture.session.document.rawChunks.indices.contains(0), cppID: focusedSiblingWinsID,
                  message: "A012 basic fixture has a primary chunk")
    // A013: attachment replaces the native EventWidgets lookup guard.
    report.expect(fixture.presenter.attached && fixture.presenter.rowCount > 0,
                  cppID: focusedSiblingWinsID, message: "A013 event-list presenter is attached")

    let first = rowFor(fixture.presenter, tick: 60, kind: .cc)
    // A014: the first CC row at the duplicate tick exists.
    report.expect(first != nil, cppID: focusedSiblingWinsID,
                  message: "A014 first CC row at tick 60 exists")
    guard let first else { return }

    let sibling = first + 1
    // A015: the immediately following row is the same-tick sibling.
    report.expect(sibling < fixture.presenter.rowCount
        && fixture.presenter.rowTick(row: sibling) == 60,
        cppID: focusedSiblingWinsID, message: "A015 adjacent sibling retains tick 60")
    guard sibling < fixture.presenter.rowCount else { return }

    fixture.presenter.setPlayheadTick(tick: -1, playing: false)
    fixture.presenter.focusRow(row: first)
    fixture.presenter.setPlayheadTick(tick: 60, playing: false)
    // A016: the focused first sibling wins exact-tick snapping.
    report.expectEqual(expected: first, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A016 focused first sibling wins at tick 60")
    // A017: tint follows the focused first sibling.
    report.expect(tintedRows(fixture.presenter) == [first]
        && hasExactTintContract(fixture.presenter, expected: first),
        cppID: focusedSiblingWinsID, message: "A017 first sibling is the only tinted row")

    fixture.presenter.setPlayheadTick(tick: 59.999, playing: false)
    // A018: the same focused sibling wins within the half-tick tolerance.
    report.expectEqual(expected: first, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A018 focused first sibling wins within 0.5 tick")

    fixture.presenter.focusRow(row: sibling)
    // A019: moving focus to the sibling moves the play row immediately.
    report.expectEqual(expected: sibling, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A019 focusing sibling moves playRow")
    // A020: tint follows the newly focused sibling.
    report.expect(tintedRows(fixture.presenter) == [sibling]
        && hasExactTintContract(fixture.presenter, expected: sibling),
        cppID: focusedSiblingWinsID, message: "A020 sibling is the only tinted row")

    let other = rowFor(fixture.presenter, tick: 70, kind: .noteOn)
    // A021: an unrelated event row exists for the no-snap phase.
    report.expect(other != nil, cppID: focusedSiblingWinsID,
                  message: "A021 unrelated NoteOn row at tick 70 exists")
    guard let other else { return }

    fixture.presenter.focusRow(row: other)
    fixture.presenter.setPlayheadTick(tick: 60, playing: false)
    let expected = playheadRowOracle(fixture.presenter.model.rows, tick: 60)
    // A022: once an unrelated row is focused, the ordinary oracle wins.
    report.expectEqual(expected: expected, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A022 unrelated focus restores ordinary row oracle")
    // A023: the ordinary oracle row is the only tinted row.
    report.expect(tintedRows(fixture.presenter) == [expected]
        && hasExactTintContract(fixture.presenter, expected: expected),
        cppID: focusedSiblingWinsID, message: "A023 oracle row is the only tinted row")
}

@MainActor
private func samplePathAndProgrammaticRestore(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A024: direct fixture construction replaces the native tab-open guard.
    report.expect(fixture.session.document.rawChunks.indices.contains(0),
                  cppID: samplePathAndProgrammaticRestoreID,
                  message: "A024 basic tab fixture has a primary chunk")
    // A025: attachment replaces the native EventWidgets lookup guard.
    report.expect(fixture.presenter.attached && fixture.presenter.rowCount > 0,
                  cppID: samplePathAndProgrammaticRestoreID,
                  message: "A025 event-list presenter is attached")
    // A026: the session timeline is the Swift equivalent of the native timeline lookup.
    report.expect(!fixture.session.timeline.events.isEmpty,
                  cppID: samplePathAndProgrammaticRestoreID,
                  message: "A026 playback timeline exists")

    let rows = fixture.presenter.model.rows
    let endTick = rows.last?.tick ?? 0
    // A027: a fresh list starts without an edit-focused row.
    report.expectEqual(expected: -1, actual: fixture.presenter.currentRow,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A027 fresh list has no focused row")

    fixture.presenter.setPlayheadTick(tick: Double(endTick + 1), playing: false)
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    let tickZero = playheadRowOracle(rows, tick: 0)
    // A028: direct programmatic tick updates use the row oracle without focus.
    report.expectEqual(expected: tickZero, actual: fixture.presenter.playRow,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A028 programmatic tick zero uses the oracle row")
    // A029: programmatic restoration updates whole-row tint with the same oracle row.
    report.expect(tintedRows(fixture.presenter) == [tickZero]
        && hasExactTintContract(fixture.presenter, expected: tickZero),
        cppID: samplePathAndProgrammaticRestoreID,
        message: "A029 programmatic tick zero tints only the oracle row")

    let focused = rowFor(fixture.presenter, tick: 70, kind: .noteOn)
    // A030: the focused NoteOn lookup succeeds.
    report.expect(focused != nil, cppID: samplePathAndProgrammaticRestoreID,
                  message: "A030 NoteOn row at tick 70 exists")
    guard let focused else { return }

    fixture.presenter.focusRow(row: focused)
    // A031: focus commits the edit cursor before the document mutation.
    report.expectEqual(expected: Tick(70), actual: fixture.session.editCursor,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A031 focused row commits edit cursor tick 70")
    let cursorBefore = fixture.session.editCursor
    fixture.session.document.insertRawEvent(
        chunk: 0,
        event: .channel(tick: endTick + 50, status: 0xB0, data0: 7, data1: 64))
    // A032: the document publication/rebuild leaves the cursor untouched.
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A032 insert preserves edit cursor")

    _ = fixture.session.document.history.undoDocument()
    // A033: undo publication also leaves the cursor untouched.
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A033 undo preserves edit cursor")
}

@MainActor
private func followScroll(_ report: CheckReport, suite: DocumentSession,
                          service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .long)
    // A034: direct fixture construction replaces the native long-rig open guard.
    report.expect(fixture.session.document.rawChunks.indices.contains(0), cppID: followScrollID,
                  message: "A034 long fixture has a primary chunk")
    // A035: attachment replaces the native EventWidgets lookup guard.
    report.expect(fixture.presenter.attached && fixture.presenter.rowCount > 100,
                  cppID: followScrollID, message: "A035 long event-list presenter is attached")

    var callbacks: [Int] = []
    fixture.presenter.onScrollToRow = { callbacks.append($0) }
    // A036: the installed callback is the Swift equivalent of a valid scroll spy.
    report.expect(fixture.presenter.onScrollToRow != nil, cppID: followScrollID,
                  message: "A036 scroll-to-row observer is valid")

    let eot = fixture.presenter.rowCount - 1
    let pastEnd = Double(fixture.presenter.model.rows[eot].tick + 10)
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    fixture.presenter.setFollowPlayhead(enabled: true)
    callbacks.removeAll()
    let requestsBeforeFollow = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A037: free follow emits a request targeting the playing EOT row.
    report.expect(!callbacks.isEmpty && callbacks.last == eot
        && fixture.presenter.lastScrollToRow == eot
        && fixture.presenter.scrollToRowRequested > requestsBeforeFollow,
        cppID: followScrollID, message: "A037 free follow scrolls to the playing row")

    callbacks.removeAll()
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    fixture.presenter.setPointerDown(down: true)
    let requestsBeforePointer = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A038: pointer-held state suppresses auto-scroll.
    report.expect(callbacks.isEmpty
        && fixture.presenter.scrollToRowRequested == requestsBeforePointer,
        cppID: followScrollID, message: "A038 pointer-held state suppresses scroll")
    // A039: pointer suppression does not suppress transport tint.
    report.expect(tintedRows(fixture.presenter) == [eot]
        && hasExactTintContract(fixture.presenter, expected: eot),
        cppID: followScrollID, message: "A039 pointer-held state retains EOT tint")
    fixture.presenter.setPointerDown(down: false)

    callbacks.removeAll()
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    let editing = fixture.presenter.beginEditing(row: eot, column: 0)
    // A040: the sentinel tick cell opens a real presenter editing session.
    report.expect(editing, cppID: followScrollID,
                  message: "A040 EOT tick cell begins editing")
    let requestsBeforeEditing = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A041: in-cell editing suppresses auto-scroll.
    report.expect(callbacks.isEmpty
        && fixture.presenter.scrollToRowRequested == requestsBeforeEditing,
        cppID: followScrollID, message: "A041 editing state suppresses scroll")
    // A042: editing suppression does not suppress transport tint.
    report.expect(tintedRows(fixture.presenter) == [eot]
        && hasExactTintContract(fixture.presenter, expected: eot),
        cppID: followScrollID, message: "A042 editing state retains EOT tint")
    _ = fixture.presenter.finishEditing(text: "", commit: false)

    callbacks.removeAll()
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    fixture.presenter.setFollowPlayhead(enabled: false)
    let requestsBeforeDisabledFollow = fixture.presenter.scrollToRowRequested
    fixture.presenter.setPlayheadTick(tick: pastEnd, playing: true)
    // A043: disabling follow prevents any scroll request.
    report.expect(callbacks.isEmpty
        && fixture.presenter.scrollToRowRequested == requestsBeforeDisabledFollow,
        cppID: followScrollID, message: "A043 follow-off state suppresses scroll")
    // A044: follow-off still updates the transport tint.
    report.expect(tintedRows(fixture.presenter) == [eot]
        && hasExactTintContract(fixture.presenter, expected: eot),
        cppID: followScrollID, message: "A044 follow-off state retains EOT tint")
    fixture.presenter.setFollowPlayhead(enabled: true)
}

@MainActor
private func eventListRowsAndEditContract(_ report: CheckReport) {
    let empty = MidiChunk(events: [], endTick: 24)
    let coincident = MidiChunk(events: [
        .channel(tick: 48, status: 0x90, data0: 60, data1: 100),
    ], endTick: 48)
    let multiple = MidiChunk(events: [
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
    report.expectEqual(expected: 0, actual: model.rowCount, cppID: rowsAndEditContractID,
                       what: "detached model has no EOT row")
    for (index, chunk) in file.chunks.enumerated() {
        model.setSource(chunk)
        report.expectEqual(expected: chunk.events.count + 1, actual: model.rowCount,
                           cppID: rowsAndEditContractID,
                           what: "shape \(index) has one EOT row after its events")
        report.expectEqual(expected: chunk.endTick, actual: model.rowTick(row: chunk.events.count),
                           cppID: rowsAndEditContractID,
                           what: "shape \(index) EOT tick mirrors the chunk end")
        report.expectEqual(expected: expectedTypes[index] + [EventListEventType.endOfTrack.rawValue],
                           actual: model.rows.map(\.typeKind), cppID: rowsAndEditContractID,
                           what: "shape \(index) projects each event type and EOT")
        report.expect(model.rows.last?.isEndOfTrack == true
            && model.rows.dropLast().allSatisfy { !$0.isEndOfTrack },
            cppID: rowsAndEditContractID,
            message: "shape \(index) has exactly one EOT sentinel")
    }

    let eot = model.rowCount - 1
    report.expect(model.isCellEditable(row: eot, column: 0)
        && !(1..<EventListModel.columnCount).contains { model.isCellEditable(row: eot, column: $0) }
        && !model.isCellEditable(row: -1, column: 0),
        cppID: rowsAndEditContractID, message: "only the EOT tick cell is editable")
    report.expect(model.isCellEditable(row: 1, column: 2)
        && !model.isCellEditable(row: 2, column: 2)
        && !model.isCellEditable(row: 3, column: 2)
        && model.isCellEditable(row: 2, column: 5)
        && model.isCellEditable(row: 3, column: 5)
        && model.isCellEditable(row: 4, column: 5)
        && !model.isCellEditable(row: 1, column: 5),
        cppID: rowsAndEditContractID, message: "channel and blob cells follow event kind")
    report.expect(model.validatesEdit(row: eot, column: 0, text: String(TimeDefaults.maxTick))
        && !model.validatesEdit(row: eot, column: 0, text: String(TimeDefaults.maxTick + 1))
        && !model.validatesEdit(row: eot, column: 0, text: "-1"),
        cppID: rowsAndEditContractID, message: "tick editing honors maxTick")
    report.expect(model.validatesEdit(row: 1, column: 1, text: "10")
        && !model.validatesEdit(row: 1, column: 1, text: "9")
        && model.validatesEdit(row: 1, column: 2, text: "1")
        && model.validatesEdit(row: 1, column: 2, text: "16")
        && !model.validatesEdit(row: 1, column: 2, text: "0")
        && !model.validatesEdit(row: 1, column: 2, text: "17"),
        cppID: rowsAndEditContractID, message: "type IDs and channel bounds are validated")
    report.expect(model.validatesEdit(row: 1, column: 3, text: "0")
        && model.validatesEdit(row: 1, column: 4, text: "127")
        && !model.validatesEdit(row: 1, column: 3, text: "-1")
        && !model.validatesEdit(row: 1, column: 4, text: "128")
        && model.validatesEdit(row: 2, column: 5, text: "AA")
        && model.validatesEdit(row: 3, column: 5, text: "7D")
        && !model.validatesEdit(row: 2, column: 5, text: "  ")
        && !model.validatesEdit(row: 3, column: 5, text: ""),
        cppID: rowsAndEditContractID, message: "data bytes and blob contents are validated")
    model.setPlayheadTick(36)
    report.expectEqual(expected: 3, actual: model.playRow, cppID: rowsAndEditContractID,
                       what: "transport chooses the SysEx row")
    report.expect(model.rows.filter { model.rowTint(row: $0.index) != nil }.map(\.index) == [model.playRow]
        && model.rowTint(row: model.playRow) == EventListModel.playheadTint,
        cppID: rowsAndEditContractID, message: "exactly the playing row is tinted")
    model.detach()
    report.expectEqual(expected: 0, actual: model.rowCount, cppID: rowsAndEditContractID,
                       what: "detaching clears all rows")
}

@MainActor
private func eventListRemapAnchorAndProjection(_ report: CheckReport, suite: DocumentSession,
                                               service: ProjectService) {
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
    report.expectEqual(expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
                       what: "initial chunk holds the focused event row")

    let moved = session.document.moveTrack(1, to: 0)
    report.expect(moved && remaps.last?.chunkMap[2] == 0,
                  cppID: remapAnchorAndProjectionID,
                  message: "moving the second track publishes its chunk remap")
    report.expectEqual(expected: 0, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
                       what: "chunk anchor follows the move")
    report.expectEqual(expected: session.document.rawChunks[0].events.count + 1, actual: presenter.rowCount,
                       cppID: remapAnchorAndProjectionID,
                       what: "moved chunk projects its current event count and EOT")
    report.expectEqual(expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
                       what: "document remap preserves in-range row focus")

    _ = session.document.history.undoDocument()
    report.expectEqual(expected: 2, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
                       what: "undo restores the chunk anchor")
    report.expectEqual(expected: initialCount, actual: presenter.rowCount, cppID: remapAnchorAndProjectionID,
                       what: "undo restores the initial projection")
    report.expectEqual(expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
                       what: "undo retains in-range row focus")
    _ = session.document.history.redoDocument()
    report.expectEqual(expected: 0, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
                       what: "redo follows the moved chunk again")
    report.expectEqual(expected: session.document.rawChunks[0].events.count + 1, actual: presenter.rowCount,
                       cppID: remapAnchorAndProjectionID,
                       what: "redo rebuilds the moved chunk projection")
    report.expectEqual(expected: 2, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
                       what: "redo retains in-range row focus")

    presenter.setChunk(index: 1)
    report.expectEqual(expected: -1, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
                       what: "explicit chunk switch resets row focus")
    presenter.focusRow(row: 2)
    session.document.deleteTrack(1)
    report.expect(remaps.last?.chunkMap[1] == .some(nil),
                  cppID: remapAnchorAndProjectionID,
                  message: "deletion publishes an unmapped original chunk")
    report.expectEqual(expected: -1, actual: presenter.chunkIndex, cppID: remapAnchorAndProjectionID,
                       what: "deleting the selected chunk clears its anchor")
    report.expectEqual(expected: 0, actual: presenter.rowCount, cppID: remapAnchorAndProjectionID,
                       what: "deleted chunk has no projected rows")
    report.expectEqual(expected: -1, actual: presenter.currentRow, cppID: remapAnchorAndProjectionID,
                       what: "deleting the selected chunk clears row focus")
    _ = session.document.history.undoDocument()
    report.expect(presenter.chunkIndex == -1 && presenter.rowCount == 0
        && presenter.currentRow == -1,
        cppID: remapAnchorAndProjectionID,
        message: "undoing deletion leaves the unselected anchor empty")
    _ = session.document.history.redoDocument()
    report.expect(presenter.chunkIndex == -1 && presenter.rowCount == 0
        && presenter.currentRow == -1,
        cppID: remapAnchorAndProjectionID,
        message: "redoing deletion leaves the unselected anchor empty")
}
