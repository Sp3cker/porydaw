import Foundation
import PorydawApp
import PorydawCore

@MainActor
func voiceSubtitleFollowsProgramPosition(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::voiceSubtitleFollowsProgramPosition"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    fx.document.writeLane(track: 1, lane: .voice, from: 480, through: 480,
                          points: [LaneWrite(tick: 480, value: 5)])
    let baseline = HeaderDocumentBaseline(fx.document)
    let initial = h.rows[1].subtitle
    func program(at tick: Tick) -> Int {
        VoiceLanePolicy.slot(firstProgram: fx.session.timeline.tracks[1].firstProgram,
                             tick: tick, points: fx.document.lanePoints(track: 1, lane: .voice))
    }
    report.expectEqual(1, program(at: 0), cppID: id, what: "initial numeric program")
    let unaffected = h.rows[0]
    let rebuilds = h.rowRebuildCount
    fx.session.editCursor = 479
    h.refreshFromDocument()
    report.expectEqual(initial, h.rows[1].subtitle, cppID: id,
                       what: "cursor before change still shows first program")
    fx.session.editCursor = 480
    h.refreshFromDocument()
    report.expectEqual(5, program(at: fx.session.editCursor), cppID: id,
                       what: "edit cursor resolves the changed numeric program")
    let changed = h.rows[1].subtitle
    report.expect(changed != initial, cppID: id, message: "cursor at change publishes new subtitle")
    report.expect(h.rows[0] === unaffected, cppID: id, message: "program transition retains unrelated row")
    fx.session.editCursor = 0
    h.refreshFromDocument()
    report.expectEqual(initial, h.rows[1].subtitle, cppID: id, what: "stopped cursor restores first program")
    h.refreshPlayhead(tick: 480, playing: true)
    report.expectEqual(5, program(at: 480), cppID: id,
                       what: "playing position resolves the changed numeric program")
    report.expectEqual(changed, h.rows[1].subtitle, cppID: id, what: "playing follows playhead over edit cursor")
    let retained = h.rows[1]
    h.refreshPlayhead(tick: 481, playing: true)
    report.expect(h.rows[1] === retained, cppID: id, message: "unchanged program retains published row")
    h.refreshPlayhead(tick: 481, playing: false)
    report.expectEqual(1, program(at: fx.session.editCursor), cppID: id,
                       what: "stopped position resolves the original numeric program")
    report.expectEqual(initial, h.rows[1].subtitle, cppID: id, what: "stop immediately returns to edit cursor")
    report.expectEqual(rebuilds, h.rowRebuildCount, cppID: id, what: "subtitle transitions never rebuild rows")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "cursor and playhead changes")
}

/// Supplemental regression for the QML voice-edit/undo sequence. The original
/// raster check varies cursor/playhead position; it does not assert this undo.
@MainActor
func coreHeaderVoiceUndoRegression(_ report: CheckReport, suite: DocumentSession,
                                   service: ProjectService) async throws {
    let id = "swiftcore/TrackHeaders::supplementalAwaitedVoiceUndo"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let before = fx.document.state
    let subtitle = fx.headers.rows[0].subtitle
    fx.openMenu(report, track: 0, cppID: id)
    fx.headers.activateHeaderMenuAction(actionId: 1)
    fx.headers.completeVoiceRequest(program: 127)
    report.expectEqual(127, fx.document.lanePoints(track: 0, lane: .voice).first?.value,
                       cppID: id, what: "picker completion writes program127")
    let changed = fx.headers.rows[0].subtitle
    report.expect(changed != subtitle, cppID: id, message: "voice edit publishes the new subtitle")
    let undone = try await fx.session.undo()
    report.expect(undone, cppID: id, message: "awaited session undo completes")
    report.expectEqual(before, fx.document.state, cppID: id, what: "one undo restores the entire document")
    report.expectEqual(subtitle, fx.headers.rows[0].subtitle, cppID: id,
                       what: "one undo publishes the original subtitle")
    let redone = try await fx.session.redo()
    report.expect(redone, cppID: id, message: "awaited session redo completes")
    report.expectEqual(changed, fx.headers.rows[0].subtitle, cppID: id,
                       what: "one redo republishes the changed subtitle")
}
