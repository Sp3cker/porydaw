import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runTimemenuChecks(_ report: CheckReport, session: DocumentSession) {
    checkTimeMenuInsertTime(report, session: session)
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
