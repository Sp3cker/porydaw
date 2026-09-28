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
    checkRulerLoopBuildTotality(report, session: session)
    checkRulerSignatureRemoval(report, session: session)
    checkRulerInsertTime(report, session: session)
    checkRenderedRulerMenuCommands(report, session: session)
    checkRulerInsertTimePrompt(report, session: session)
    checkRulerMenuRetirement(report, session: session)
    checkRulerSweepScopeTapAndChip(report, session: session)
    checkRulerSelectedKeyboardScope(report, session: session)
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

@MainActor
private func checkRulerSelectedKeyboardScope(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    withKeyboardSeed(report, session: session, id: id) { grid, seed in
        let document = session.document
        let postSeedBytes = coreTimeBytes(document)
        let postSeedIdentity = document.history.currentIdentity
        let palette = GridPalette()
        let automation = AutomationPage(baseFontPx: grid.baseFontPx)
        automation.attach(session: session, palette: palette)
        defer { automation.detach(); session.clearTimeSelection() }
        session.setSelectedNotes([seed.id])
        grid.performCommand(command: EditCommand.transposeDownOctave.rawValue)
        grid.performCommand(command: EditCommand.nudgeRight.rawValue)
        let firstTick = seed.tick
        let lastTick = firstTick + 4 * seed.snap
        guard document.canAddTrack, let other = document.addTrack(voice: 0),
              let ghost = try? document.addNotes([NewNote(
                  track: other, tick: firstTick + seed.snap, pitch: UInt8(seed.pitch),
                  duration: seed.snap, velocity: 90)]).first else {
            report.fail(id, "cannot add the overlapping ruler-scope note")
            return
        }
        var expectedScope: Set<Int> = [seed.track]
        for track in 0..<document.engineTracks.usedTrackCount where track != seed.track {
            if document.notes(in: track).contains(where: {
                $0.tick < lastTick && firstTick < $0.tick + $0.duration
            }) {
                expectedScope.insert(track)
            }
        }
        let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
        menu.beginSweep(contentX: session.camera.contentX(tick: Double(firstTick)),
                        pointerY: 0, modifiers: 0x0400_0000)
        menu.updateSweep(contentX: session.camera.contentX(tick: Double(lastTick)))
        menu.endSweep(contentX: session.camera.contentX(tick: Double(lastTick)))
        report.expect(automation.selection?.range == TimeRange(startTick: firstTick, endTick: lastTick)
                      && automation.selection?.scope == .tracks(expectedScope)
                      && expectedScope.contains(other) && document.note(ghost) != nil,
                      cppID: id,
                      message: "A026 modified ruler sweep selects exactly every overlapping note track and span")
        session.clearTimeSelection()
        while document.history.currentIdentity != postSeedIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        report.expect(coreTimeBytes(document) == postSeedBytes
                      && document.history.currentIdentity == postSeedIdentity,
                      cppID: id, message: "A039 ruler transpose and sweep unwind to post-seed bytes")
    }
}

@MainActor
func checkRulerLoopBuildTotality(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuBuildTotality"
    let document = rulerMenuDocument(session)
    // The fork's :500 guard holds a nullable build; Swift's build is total,
    // so the clause's law is that the marked document builds a looped timeline.
    document.setLoop(end: false, tick: 6)
    document.setLoop(end: true, tick: 18)
    let marked = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(marked.hasLoop, cppID: id,
                  message: "A137: the loop-marked document always builds a looped timeline")
}
