import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runTimeSignaturePromptChecks(_ report: CheckReport, session: DocumentSession) {
    checkTimeSignatureAcceptUndo(report, session: session)
    checkTimeSignatureCursorEntry(report, session: session, onEvent: true)
    checkTimeSignatureCursorEntry(report, session: session, onEvent: false)
}

@MainActor
private func timeSignatureDocument(_ session: DocumentSession) -> SongDocument {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 240),
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 240),
    ]), config: session.document.state.config, source: session.document.source,
        trackBudget: session.document.trackBudget)
    // The original fixture seeds 3/4 at four quarter-note beats.
    document.setTimeSignature(tick: Tick(document.ticksPerBeat * 4), numerator: 3,
                              denominatorPower: 2)
    return document
}

@MainActor
private func checkTimeSignatureAcceptUndo(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRollTest::timeSignaturePromptAcceptUndoGrid"
    let document = timeSignatureDocument(session)
    let signatureTick = Tick(document.ticksPerBeat * 4)
    let before = coreTimeBytes(document)
    let revision = document.revision
    let undoIndex = document.history.undoIndex
    let undoCount = document.history.undoCount
    // Accepting the 7/8 draft is one document command, not a draft-time write.
    document.setTimeSignature(tick: signatureTick, numerator: 7, denominatorPower: 3)
    report.expect(document.timeSignatures.contains {
        $0.tick == signatureTick && $0.numerator == 7 && $0.denominatorPower == 3
    } && document.revision == revision + 1
        && document.history.undoIndex == undoIndex + 1
        && document.history.undoCount == undoCount + 1,
        cppID: id, message: "A007: 7/8 replaces the seeded signature in one undoable edit")

    let rebuilt = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(rebuilt.ticksPerBeat == UInt32(document.ticksPerBeat) &&
        rebuilt.timeSignatures.contains {
            $0.tick == signatureTick && $0.numerator == 7 && $0.denominatorPowerOfTwo == 3
        }, cppID: id, message: "A008: the accepted signature rebuilds into the playback timeline")
    let axis = TimeAxis(map: TimeMap(
        ticksPerBeat: rebuilt.ticksPerBeat,
        timeSigs: rebuilt.timeSignatures.map {
            TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                         denomPow2: $0.denominatorPowerOfTwo)
        }))
    let segment = axis.segmentAt(signatureTick)
    report.expect(segment.start == signatureTick && segment.beatsPerBar == 7
                  && segment.beatTicks == rebuilt.ticksPerBeat / 2,
                  cppID: id, message: "A009: 7/8 creates a denominator-scaled grid segment")
    report.expect(document.history.undoDocument() && coreTimeBytes(document) == before,
                  cppID: id, message: "A011: one undo restores the pre-acceptance song bytes")
}

@MainActor
private func checkTimeSignatureCursorEntry(_ report: CheckReport, session: DocumentSession,
                                           onEvent: Bool) {
    let id = "swiftcore/PianoRollTest::timeSignaturePromptCursorEntry"
    let document = timeSignatureDocument(session)
    let signatureTick = Tick(document.ticksPerBeat * 4)
    let cursorTick = onEvent ? signatureTick : signatureTick + 7
    let revision = document.revision
    let undoIndex = document.history.undoIndex
    let undoCount = document.history.undoCount
    document.setTimeSignature(tick: cursorTick, numerator: 5, denominatorPower: 3)
    report.expect(document.timeSignatures.contains {
        $0.tick == cursorTick && $0.numerator == 5 && $0.denominatorPower == 3
    } && document.revision == revision + 1
        && document.history.undoIndex == undoIndex + 1
        && document.history.undoCount == undoCount + 1,
        cppID: id, message: "A039: 5/8 commits at the exact \(onEvent ? "event" : "off-grid cursor") tick")
    if !onEvent {
        report.expect(document.timeSignatures.contains {
            $0.tick == signatureTick && $0.numerator == 3 && $0.denominatorPower == 2
        }, cppID: id, message: "A040: off-grid insertion retains the original 3/4 event")
    }
}
