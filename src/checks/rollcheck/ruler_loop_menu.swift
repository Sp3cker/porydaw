import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawAppCommands

// The original resize seed requests a free cell near tick 88. The synthetic
// document has no competing notes, so its six-tick grid cell starts at 84.
let rulerSeedTick: Tick = 88 - (88 % 6)

@MainActor
func runRulerLoopMenuChecks(_ report: CheckReport, session: DocumentSession) {
    checkRulerLoopSetAndUndo(report, session: session)
    checkRulerSignatureRemoval(report, session: session)
    checkRulerInsertTime(report, session: session)
    checkRenderedRulerMenuCommands(report, session: session)
    checkRulerInsertTimePrompt(report, session: session)
    checkRulerMenuRetirement(report, session: session)
    checkRulerSweepScopeTapAndChip(report, session: session)
    checkRulerSeekEmission(report, session: session)
    checkRulerDeferredTiming(report, session: session)
    checkGridLoopCommandArms(report, session: session)
}

@MainActor
func openRulerMenu(_ menu: RulerMenuPresenter, at contentX: Double) {
    menu.captureRulerPress(contentX: contentX, pointerY: 0)
    menu.openRulerAtRelease()
}

@MainActor
func rulerMenuDocument(_ session: DocumentSession) -> SongDocument {
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
