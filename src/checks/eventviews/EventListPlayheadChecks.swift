import Foundation
import PorydawApp
import PorydawAppEventList
import PorydawCore
import PorydawDocument

private let tintLastOfRunID = "eventviews/EventViewsPlayheadTest::tintLastOfRun"
internal let focusCommitsCursorID = "eventviews/EventViewsPlayheadTest::focusCommitsCursor"
internal let focusedSiblingWinsID = "eventviews/EventViewsPlayheadTest::focusedSiblingWins"
internal let samplePathAndProgrammaticRestoreID =
    "eventviews/EventViewsPlayheadTest::samplePathAndProgrammaticRestore"
internal let followScrollID = "eventviews/EventViewsPlayheadTest::followScroll"
internal let rowsAndEditContractID = "swiftcore/EventList::eventListRowsAndEditContract"
internal let remapAnchorAndProjectionID = "swiftcore/EventList::eventListRemapAnchorAndProjection"

internal enum EventListPlayheadShape {
    case basic
    case long
    case tempo
    case empty
    case eotCoincident
}

@MainActor
internal final class EventListPlayheadFixture {
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

internal func eventListPlayheadFile(_ shape: EventListPlayheadShape) -> MidiFile {
    if shape == .empty {
        return MidiFile(division: 24, chunks: [MidiChunk(events: [], endTick: 120)])
    }
    if shape == .eotCoincident {
        return MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .meta(tick: 120, type: 0x06, data: Array("at end".utf8))
                    ], endTick: 120)
            ])
    }
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
    case .basic, .tempo:
        endTick = 120
        if shape == .tempo {
            primary.insert(
                .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
                at: 0)
        }
    case .empty, .eotCoincident:
        preconditionFailure("single-chunk fixture returned above")
    case .long:
        endTick = 500
        for tick in 100..<500 {
            primary.append(
                .channel(
                    tick: Tick(tick), status: 0xB0, data0: 11,
                    data1: UInt8(tick % 127)))
        }
    }

    return MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: primary, endTick: endTick),
            MidiChunk(
                events: [
                    .meta(tick: 5, type: 0x06, data: Array("metadata only".utf8))
                ], endTick: 120),
            MidiChunk(
                events: [
                    .channel(status: 0xC1, data0: 1),
                    .channel(tick: 24, status: 0xB1, data0: 7, data1: 64),
                    .channel(tick: 48, status: 0x91, data0: 67, data1: 90),
                    .channel(tick: 72, status: 0x81, data0: 67),
                ], endTick: 120),
        ])
}

internal func playheadRowOracle(_ rows: [EventListRow], tick: Double) -> Int {
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

@MainActor internal func rowFor(
    _ presenter: EventListPresenter, tick: Tick,
    kind: EventListEventType
) -> Int? {
    presenter.model.rows.first { $0.tick == tick && $0.kind == kind }?.index
}

@MainActor internal func tintedRows(_ presenter: EventListPresenter) -> [Int] {
    presenter.model.rows.compactMap { row in
        presenter.isRowTinted(row: row.index) ? row.index : nil
    }
}

@MainActor internal func hasExactTintContract(_ presenter: EventListPresenter, expected: Int) -> Bool {
    presenter.model.rows.allSatisfy { row in
        let shouldTint = row.index == expected
        let actualTinted = presenter.isRowTinted(row: row.index)
        let actualColor = presenter.rowTint(row: row.index)
        return actualTinted == shouldTint
            && actualColor == (shouldTint ? EventListModel.playheadTint : "")
    }
}

@MainActor
public func runEventListPlayheadChecks(
    _ report: CheckReport, session suite: DocumentSession,
    service: ProjectService
) {
    tintLastOfRun(report, suite: suite, service: service)
    focusCommitsCursor(report, suite: suite, service: service)
    focusedSiblingWins(report, suite: suite, service: service)
    samplePathAndProgrammaticRestore(report, suite: suite, service: service)
    followScroll(report, suite: suite, service: service)
    eventListRowsAndEditContract(report)
    eventListRemapAnchorAndProjection(report, suite: suite, service: service)
    eventListFixtureProjection(report, suite: suite, service: service)
    eventListTempoShapeAtomic(report, suite: suite, service: service)
    runEventListPageChecks(report, session: suite, service: service)
}

@MainActor
private func eventListFixtureProjection(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "eventviews/EventViewsChromeTest::rowMirror"
    for shape in [EventListPlayheadShape.empty, .eotCoincident, .basic, .tempo] {
        let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: shape)
        let presenter = fixture.presenter
        let chunk = fixture.session.document.rawChunks[0]
        let tempos = fixture.session.document.state.tempo
        report.expectEqual(
            expected: chunk.events.count + tempos.count + 1,
            actual: presenter.rowCount, cppID: id,
            what: "the table mirrors the chunk's events plus tempo rows and one EOT")
        report.expect(
            presenter.model.rows.last?.isEndOfTrack == true
                && presenter.model.rows.last?.tick == chunk.endTick,
            cppID: id, message: "the sentinel follows the fixture's end tick")
    }
    let tempo = EventListPlayheadFixture(suite: suite, service: service, shape: .tempo)
    let presenter = tempo.presenter
    report.expect(
        presenter.model.rows.first?.tempo?.tick == 0,
        cppID: "eventviews/EventViewsRemapTest::tempoProjectionRows",
        message: "a tick-zero tempo point projects the first table row")
    presenter.setChunk(index: 1)
    report.expect(
        !presenter.model.rows.contains(where: { $0.tempo != nil }),
        cppID: "eventviews/EventViewsRemapTest::tempoProjectionRows",
        message: "the tempo row leads the conductor chunk and vanishes on a track switch")
    presenter.setVisible(visible: true)
    presenter.openChunkMenu(x: 0, y: 0)
    presenter.activateMenuAction(actionId: 2)
    report.expect(
        presenter.chunkIndex == 2 && presenter.chunk == 2,
        cppID: "eventviews/EventViewsRemapTest::metadataChunkTransition",
        message: "selecting a chunk through the menu model echoes the chunk")
    report.expect(
        presenter.model.rows.contains {
            $0.kind == .program && $0.tick == 0 && $0.eventIndex != nil
        }, cppID: "eventviews/EventViewsRemapTest::metadataChunkTransition",
        message: "the promoted program event resolves to a rendered row")
}

@MainActor
private func eventListTempoShapeAtomic(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .tempo)
    let document = fixture.session.document
    let presenter = fixture.presenter
    let original = document.rawChunks[0].events.filter { $0.tick == 0 && $0.isMeta }
    let tick: Tick = 121
    document.insertRawEvent(
        chunk: 0, event: .meta(tick: tick, type: 0x06, data: Array("convert".utf8)))
    let id = "eventviews/EventViewsEditsTest::rawTempoAtomic"
    report.expect(
        presenter.model.rows.first?.tempo?.tick == 0, cppID: id,
        message: "a tick-zero tempo point projects the first table row")
    report.expect(
        presenter.model.rows.contains(where: { $0.tick == tick && $0.event?.isMeta == true }), cppID: id,
        message: "the Tempo journey re-establishes its own fixture rows")
    guard
        let raw = presenter.model.rows.firstIndex(where: {
            $0.tick == tick && $0.event?.isMeta == true
        })
    else {
        return
    }
    let beforeTempo = document.history.undoIndex
    let converted = presenter.commitCellEdit(row: raw, column: 1, text: "9")
    report.expect(
        converted && document.history.undoIndex == beforeTempo + 1,
        cppID: id, message: "each conversion is one undo step through the presenter")
    report.expect(
        presenter.model.rows.contains(where: { $0.tick == tick && $0.tempo != nil })
            && !presenter.model.rows.contains(where: {
                $0.tick == tick && $0.event?.isMeta == true
            })
            && document.rawChunks[0].events.filter({
                $0.tick == 0 && $0.isMeta
            }) == original, cppID: id,
        message: "tempo and raw conversions preserve the tick-zero meta set")
    let convertedCount = document.history.undoCount
    let conversionUndone = document.history.undoDocument()
    report.expect(
        conversionUndone && document.history.undoIndex == beforeTempo
            && document.history.undoCount == convertedCount
            && rowFor(presenter, tick: tick, kind: .meta) != nil
            && !presenter.model.rows.contains(where: { $0.tick == tick && $0.tempo != nil })
            && document.rawChunks[0].events.filter({ $0.tick == 0 && $0.isMeta }) == original,
        cppID: id, message: "undo restores the raw meta without changing tick-zero metas")
    let conversionRedone = document.history.redoDocument()
    report.expect(
        conversionRedone && document.history.undoIndex == beforeTempo + 1
            && document.history.undoCount == convertedCount
            && presenter.model.rows.contains(where: { $0.tick == tick && $0.tempo != nil })
            && rowFor(presenter, tick: tick, kind: .meta) == nil
            && document.rawChunks[0].events.filter({ $0.tick == 0 && $0.isMeta }) == original,
        cppID: id, message: "redo restores the tempo without changing tick-zero metas")
    report.expect(
        presenter.model.rows.contains(where: { $0.tick == tick && $0.tempo != nil }), cppID: id,
        message: "the converted tempo row is available")
    guard
        let tempo = presenter.model.rows.firstIndex(where: {
            $0.tick == tick && $0.tempo != nil
        })
    else {
        return
    }
    let beforeRaw = document.history.undoIndex
    let restored = presenter.commitCellEdit(row: tempo, column: 1, text: "10")
    report.expect(
        restored && document.history.undoIndex == beforeRaw + 1,
        cppID: id, message: "the reverse conversion is one undo step through the presenter")
    report.expect(
        presenter.model.rows.contains(where: {
            $0.tick == tick && $0.event?.isMeta == true
        })
            && !presenter.model.rows.contains(where: {
                $0.tick == tick && $0.tempo != nil
            })
            && document.rawChunks[0].events.filter({
                $0.tick == 0 && $0.isMeta
            }) == original, cppID: id,
        message: "the reverse conversion preserves the tick-zero meta set")
    let reverseCount = document.history.undoCount
    let reverseUndone = document.history.undoDocument()
    report.expect(
        reverseUndone && document.history.undoIndex == beforeRaw
            && document.history.undoCount == reverseCount
            && presenter.model.rows.contains(where: { $0.tick == tick && $0.tempo != nil })
            && rowFor(presenter, tick: tick, kind: .meta) == nil
            && document.rawChunks[0].events.filter({ $0.tick == 0 && $0.isMeta }) == original,
        cppID: id, message: "undoing the reverse conversion restores the tempo")
    let reverseRedone = document.history.redoDocument()
    report.expect(
        reverseRedone && document.history.undoIndex == beforeRaw + 1
            && document.history.undoCount == reverseCount
            && rowFor(presenter, tick: tick, kind: .meta) != nil
            && !presenter.model.rows.contains(where: { $0.tick == tick && $0.tempo != nil })
            && document.rawChunks[0].events.filter({ $0.tick == 0 && $0.isMeta }) == original,
        cppID: id, message: "redoing the reverse conversion restores the raw meta")
}

@MainActor
private func tintLastOfRun(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A001: the Swift value fixture is constructed directly, so the native open-rig failure
    // path is represented by the attached source invariant below.
    report.expect(
        fixture.session.document.rawChunks.indices.contains(0), cppID: tintLastOfRunID,
        message: "A001 basic fixture has a primary chunk")
    // A002: presenter attachment is the Swift equivalent of locating EventWidgets.
    report.expect(
        fixture.presenter.attached && fixture.presenter.rowCount > 0,
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
        report.expectEqual(
            expected: expected, actual: fixture.presenter.playRow, cppID: tintLastOfRunID,
            what: "A003 \(explanation) at tick \(tick)")
        // A004: only one complete row has the playhead tint, with the stable bridge color.
        report.expect(
            tintedRows(fixture.presenter) == (expected >= 0 ? [expected] : [])
                && hasExactTintContract(fixture.presenter, expected: expected),
            cppID: tintLastOfRunID,
            message: "A004 whole-row tint matches the oracle at tick \(tick)")
    }

    fixture.presenter.setPlayheadTick(tick: -1, playing: false)
    // A005: a negative transport tick clears the published play row.
    report.expectEqual(
        expected: -1, actual: fixture.presenter.playRow, cppID: tintLastOfRunID,
        what: "A005 negative tick clears playRow")
    // A006: clearing playRow clears every presenter/model tint.
    report.expect(
        tintedRows(fixture.presenter).isEmpty
            && hasExactTintContract(fixture.presenter, expected: -1),
        cppID: tintLastOfRunID, message: "A006 negative tick leaves no tinted row")
}
