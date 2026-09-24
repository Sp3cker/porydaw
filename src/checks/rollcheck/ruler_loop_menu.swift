import Foundation
import PorydawApp
import PorydawCore

// The original resize seed requests a free cell near tick 88. The synthetic
// document has no competing notes, so its six-tick grid cell starts at 84.
private let rulerSeedTick: Tick = 88 - (88 % 6)

@MainActor
func runRulerLoopMenuChecks(_ report: CheckReport, session: DocumentSession) {
    checkRulerLoopSetAndUndo(report, session: session)
    checkRulerSignatureRemoval(report, session: session)
    checkRulerInsertTime(report, session: session)
}

@MainActor
private func rulerMenuDocument(_ session: DocumentSession) -> SongDocument {
    // As in makeResizeSeed, the requested cell has velocity 100. The loop
    // endpoints are its right edge and one snap cell beyond that edge.
    return SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 200),
        MidiChunk(events: [
            .channel(tick: 0, status: 0xC0, data0: 0),
            .channel(tick: rulerSeedTick, status: 0x90, data0: 60, data1: 100),
            .channel(tick: rulerSeedTick + 6, status: 0x80, data0: 60),
        ], endTick: 200),
    ]), config: session.document.state.config, source: session.document.source,
        trackBudget: session.document.trackBudget)
}

@MainActor
private func checkRulerLoopSetAndUndo(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuSetAndTwoStepUndo"
    let document = rulerMenuDocument(session)
    guard let note = document.notes(in: 0).first else {
        report.fail(id, "resize fixture note is absent")
        return
    }
    let snapCell: Tick = 6
    let startTick = note.tick + note.duration
    let endTick = startTick + snapCell
    // The legacy fixture begins with both loop markers removed.
    document.setLoop(end: false, tick: nil)
    document.setLoop(end: true, tick: nil)
    let before = coreTimeBytes(document)
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(timeline.loopStartTick == TimeDefaults.noTick &&
                  timeline.loopEndTick == TimeDefaults.noTick,
                  cppID: id, message: "A004: both markers begin absent")

    document.setLoop(end: false, tick: Int64(startTick))
    report.expect(PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopStartTick == startTick,
                  cppID: id, message: "A009: setting loop start moves its marker to the cell edge")
    let afterStart = document.history.currentIdentity
    document.setLoop(end: true, tick: Int64(endTick))
    let afterSets = coreTimeBytes(document)
    report.expect(PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopEndTick == endTick &&
                  document.history.currentIdentity != afterStart && afterSets != before,
                  cppID: id, message: "A015/A017: the end marker is one snap cell later and changes the song")

    // Production removal performs two commands: start first, end second.
    document.setLoop(end: false, tick: nil)
    document.setLoop(end: true, tick: nil)
    let afterRemoval = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(afterRemoval.loopStartTick == TimeDefaults.noTick &&
                  afterRemoval.loopEndTick == TimeDefaults.noTick,
                  cppID: id, message: "A022: removal clears both markers")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "removing the end marker is undoable")
    let firstUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(firstUndo.loopStartTick == TimeDefaults.noTick && firstUndo.loopEndTick == endTick,
                  cppID: id, message: "A024: first undo restores only the end marker")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "removing the start marker is separately undoable")
    let secondUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(secondUndo.loopStartTick == startTick && secondUndo.loopEndTick == endTick &&
                  coreTimeBytes(document) == afterSets,
                  cppID: id, message: "A025/A026: second undo restores both markers and song bytes")

    let selectionStart = startTick - snapCell
    document.setLoop(end: false, tick: Int64(selectionStart))
    document.setLoop(end: true, tick: Int64(startTick))
    let selected = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(selected.loopStartTick == selectionStart && selected.loopEndTick == startTick,
                  cppID: id, message: "A030: the selection bounds become the loop markers")
    _ = document.history.undoDocument()
    let selectionUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(selectionUndo.loopStartTick == selectionStart && selectionUndo.loopEndTick == endTick,
                  cppID: id, message: "A032: first selection undo restores only the old end")
    _ = document.history.undoDocument()
    report.expect(coreTimeBytes(document) == afterSets, cppID: id,
                  message: "A033: second selection undo restores the manual markers")
}

@MainActor
private func checkRulerSignatureRemoval(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuEnablementSelectionContext"
    let document = rulerMenuDocument(session)
    let snapCell: Tick = 6
    let chipTick = rulerSeedTick + snapCell
    document.setTimeSignature(tick: chipTick, numerator: 5, denominatorPower: 2)
    report.expect(PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
        .timeSignatures.contains { $0.tick == chipTick }, cppID: id,
                  message: "A037: the explicit 5/4 signature exists at the snap cell")
    let before = coreTimeBytes(document)
    document.deleteTimeSignature(at: chipTick)
    report.expect(!PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
        .timeSignatures.contains { $0.tick == chipTick }, cppID: id,
                  message: "A050: removing the chip deletes the exact event")
    _ = document.history.undoDocument()
    report.expect(coreTimeBytes(document) == before, cppID: id,
                  message: "one undo restores the explicit signature")
}

@MainActor
private func checkRulerInsertTime(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuInsertTimeAndStaleNoOp"
    let document = rulerMenuDocument(session)
    let snapCell: Tick = 6
    let insertStart = rulerSeedTick + snapCell
    let insertEnd = insertStart + snapCell
    guard let note = document.notes(in: 0).first else {
        report.fail(id, "resize fixture note is absent")
        return
    }
    document.nudgeNotes([note.id], byTicks: Int64(snapCell), byKeys: 0)
    guard document.notes(in: 0).contains(where: { $0.tick == insertStart && $0.pitch == note.pitch }) else {
        report.fail(id, "the moved fixture note did not land at the selected seam")
        return
    }
    let before = coreTimeBytes(document)
    let identity = document.history.currentIdentity
    let range = TimeRange(startTick: insertStart, endTick: insertEnd)
    report.expect(document.insertBlankTime(range, scope: TimeScope(tracks: [0])),
                  cppID: id, message: "the selected span inserts blank time")
    report.expect(document.notes(in: 0).contains {
        $0.tick == insertEnd && $0.pitch == note.pitch && $0.velocity == note.velocity
    } && document.history.currentIdentity != identity && coreTimeBytes(document) != before,
    cppID: id, message: "A104/A108: the note shifts by exactly one span and the song bytes change")
    _ = document.history.undoDocument()
    report.expect(coreTimeBytes(document) == before, cppID: id,
                  message: "A109: one undo restores the song before ruler insertion")
}
