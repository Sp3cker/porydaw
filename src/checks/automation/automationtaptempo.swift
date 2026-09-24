import Foundation
import PorydawApp
import PorydawCore
import PorydawProjectService

// Existing scenarios paired with automationtaptempo.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationTapTempoCadenceAndCommit(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    var cadence = AutomationTapTempoSession()
    report.expectEqual(0, cadence.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "a fresh session holds no draft")
    report.expect(!cadence.readyToCommit && cadence.idleCommitMs == AutomationTapTempoSession.gapMs,
                  cppID: drawerAutomationTapTempoID,
                  message: "a draft-less session cannot commit and publishes the gap as its window")

    cadence.registerTap(nowMs: 1000)
    report.expect(cadence.tapCount == 1 && cadence.draftBpm == 0 && !cadence.readyToCommit,
                  cppID: drawerAutomationTapTempoID,
                  message: "the first tap starts a session and names no tempo")

    for step in 1...5 { cadence.registerTap(nowMs: 1000 + Int64(step) * 500) }
    report.expectEqual(6, cadence.tapCount, cppID: drawerAutomationTapTempoID,
                       what: "six taps stand in the session")
    report.expectEqual(120, cadence.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "a steady 500 ms cadence drafts 120 BPM")
    report.expectEqual(750, cadence.idleCommitMs, cppID: drawerAutomationTapTempoID,
                       what: "1.5 tapped beats at 120 BPM is a 750 ms idle window")

    // The mean clips to the newest window: four 600 ms taps after five 500 ms
    // intervals average the newest eight intervals, and the oldest 500 ms
    // interval no longer counts.
    for step in 1...4 { cadence.registerTap(nowMs: 3500 + Int64(step) * 600) }
    report.expectEqual(10, cadence.tapCount, cppID: drawerAutomationTapTempoID,
                       what: "ten taps stand in the session")
    report.expectEqual(109, cadence.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "the draft is the clipped mean of the newest eight intervals")
    report.expectEqual(826, cadence.idleCommitMs, cppID: drawerAutomationTapTempoID,
                       what: "1.5 tapped beats at 109 BPM is an 826 ms idle window")

    // A tap past the gap distance is a new session, not a dropped interval.
    cadence.registerTap(nowMs: 5900 + Int64(AutomationTapTempoSession.gapMs) + 1)
    report.expect(cadence.tapCount == 1 && cadence.draftBpm == 0, cppID: drawerAutomationTapTempoID,
                  message: "a tap past the production idle gap starts a fresh session")
    cadence.registerTap(nowMs: 8401)
    report.expectEqual(120, cadence.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "the fresh session drafts from its own single interval")
    cadence.reset()
    report.expectEqual(AutomationTapTempoSession(), cadence, cppID: drawerAutomationTapTempoID,
                       what: "reset returns the session to its seed state")
    var burst = AutomationTapTempoSession()
    for tap in 0...3 { burst.registerTap(nowMs: 50_000 + Int64(tap) * 150) }
    report.expectEqual(TimeDefaults.maximumTempoBPM, burst.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "a 150 ms cadence clamps to the published maximum tempo")
    report.expect(burst.idleCommitMs == AutomationTapTempoSession.commitMinimumMs,
                  cppID: drawerAutomationTapTempoID,
                  message: "the clamped draft's idle window sits at the commit floor")

    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    fixture.activate(fixture.panLane)
    report.expectEqual(["0:120"], fixture.tempoValues, cppID: drawerAutomationTapTempoID,
                       what: "the staged document names 120 BPM at tick zero")
    let before = fixture.snapshot

    // A ready draft that already names the tick-zero tempo writes nothing.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 10 + Int64(tap) * 500) }
    report.expectEqual(120, fixture.page.tapTempoSession.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "the tapped cadence named the tempo already in place")
    report.expectEqual(4, fixture.page.tapTempoSession.tapCount, cppID: drawerAutomationTapTempoID,
                       what: "the taps stand in the page's own session")
    report.expect(fixture.page.tapTempoActive, cppID: drawerAutomationTapTempoID,
                  message: "a live session is the page's interaction fact")
    report.expect(!fixture.page.tapTempoIdleElapsed(), cppID: drawerAutomationTapTempoID,
                  message: "a draft that changes nothing commits nothing")
    report.expectEqual(["0:120"], fixture.tempoValues, cppID: drawerAutomationTapTempoID,
                       what: "the no-op idle window left the stream alone")
    report.expectEqual(before.revision, fixture.document.revision, cppID: drawerAutomationTapTempoID,
                       what: "the no-op idle window published no revision")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationTapTempoID,
                  message: "the no-op idle window recorded no history entry")
    report.expect(fixture.page.tapTempoSession.tapCount == 0 && !fixture.page.tapTempoActive,
                  cppID: drawerAutomationTapTempoID,
                  message: "the idle window closed the session either way")

    // A ready draft that changes the tempo is one edit and one history entry.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 20_000 + Int64(tap) * 400) }
    report.expectEqual(150, fixture.page.tapTempoSession.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "a 400 ms cadence drafts 150 BPM")
    report.expect(fixture.page.tapTempoIdleElapsed(), cppID: drawerAutomationTapTempoID,
                  message: "the idle window commits the ready draft")
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: drawerAutomationTapTempoID,
                       what: "the commit replaced the tick-zero tempo point")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: drawerAutomationTapTempoID,
                       what: "the tempo edit published one revision")
    report.expect(fixture.document.history.canUndo, cppID: drawerAutomationTapTempoID,
                  message: "the tempo edit recorded one history entry")
    report.expect(fixture.undo(), cppID: drawerAutomationTapTempoID, message: "the tempo edit undoes")
    report.expectEqual(["0:120"], fixture.tempoValues, cppID: drawerAutomationTapTempoID,
                       what: "undo restored the previous tick-zero tempo")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationTapTempoID,
                  message: "one tempo edit is exactly one history entry")
    do {
        _ = try drawerAutomationRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerAutomationTapTempoID, "redo failed: \(error)")
        return
    }
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: drawerAutomationTapTempoID,
                       what: "redo put the committed tempo back on the stream")

    // A capture whose own document moved on writes nothing.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 30_000 + Int64(tap) * 500) }
    report.expectEqual(120, fixture.page.tapTempoSession.draftBpm, cppID: drawerAutomationTapTempoID,
                       what: "the stale session drafts a tempo the stream does not hold")
    report.expect(fixture.page.openPrompt(tick: 48, value: 64), cppID: drawerAutomationTapTempoID,
                  message: "the intervening write opened its own prompt")
    report.expect(fixture.page.acceptPrompt(displayedValue: 96), cppID: drawerAutomationTapTempoID,
                  message: "the intervening write committed")
    let stale = fixture.document.revision
    report.expect(!fixture.page.tapTempoIdleElapsed(), cppID: drawerAutomationTapTempoID,
                  message: "a capture whose document moved on commits nothing")
    report.expectEqual(stale, fixture.document.revision, cppID: drawerAutomationTapTempoID,
                       what: "the stale idle window published no revision")
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: drawerAutomationTapTempoID,
                       what: "the stale draft never reached the tempo stream")
    report.expect(fixture.page.tapTempoSession.tapCount == 0, cppID: drawerAutomationTapTempoID,
                  message: "the stale idle window closed the session")

    // A session named its own parameter: switching it ends without a write.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 40_000 + Int64(tap) * 400) }
    report.expect(fixture.page.tapTempoSession.tapCount > 0, cppID: drawerAutomationTapTempoID,
                  message: "the session started on the lane the taps named")
    fixture.activate(fixture.volumeLane)
    report.expect(!fixture.page.tapTempoIdleElapsed(), cppID: drawerAutomationTapTempoID,
                  message: "a session whose parameter moved on commits nothing")
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: drawerAutomationTapTempoID,
                       what: "the switched parameter left the tempo stream alone")
    fixture.activate(.tempo)
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 60_000 + Int64(tap) * 150) }
    report.expectEqual(TimeDefaults.maximumTempoBPM, fixture.page.tapTempoSession.draftBpm,
                       cppID: drawerAutomationTapTempoID,
                       what: "the page session clamps the 150 ms burst to the maximum tempo")
    report.expect(fixture.page.tapTempoIdleElapsed(), cppID: drawerAutomationTapTempoID,
                  message: "the idle window commits the clamped draft")
    report.expectEqual(["0:\(TimeDefaults.maximumTempoBPM)"], fixture.tempoValues,
                       cppID: drawerAutomationTapTempoID,
                       what: "the clamped commit lands the maximum tempo at tick zero")
}

@MainActor
func drawerAutomationTapTempoStrayAndEmptyStream(_ report: CheckReport, suite: DocumentSession,
                                                 service: ProjectService) {
    let id = "swiftcore/AutomationPage::tapTempoStrayAndEmptyStream"
    report.expectEqual(TimeDefaults.maximumTempoBPM,
                       AutomationTapTempoSession.bpm(forMeanIntervalMs: 150), cppID: id,
                       what: "a 150 ms mean clamps to the published maximum tempo")
    report.expectEqual(TimeDefaults.minimumTempoBPM,
                       AutomationTapTempoSession.bpm(forMeanIntervalMs: 3000), cppID: id,
                       what: "a 3000 ms mean clamps to the published minimum tempo")

    let stray = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    stray.activate(stray.panLane)
    let strayBefore = stray.snapshot
    stray.page.tapTempoTap(atMilliseconds: 1000)
    report.expect(!stray.page.tapTempoIdleElapsed(), cppID: id,
                  message: "a single stray tap commits nothing")
    report.expect(stray.page.tapTempoSession.tapCount == 0, cppID: id,
                  message: "the stray idle window closes the session")
    report.expectEqual(strayBefore, stray.snapshot, cppID: id,
                       what: "the stray tap leaves document and history untouched")

    let later = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  tempo: [(0, 500_000), (384, 428_571)])
    later.activate(.tempo)
    for tap in 0...3 { later.page.tapTempoTap(atMilliseconds: 70_000 + Int64(tap) * 400) }
    report.expect(later.page.tapTempoIdleElapsed(), cppID: id,
                  message: "the idle window commits the ready draft")
    report.expectEqual(["0:150", "384:140"], later.tempoValues, cppID: id,
                       what: "the commit replaces tick zero and preserves the later point")
    report.expect(later.undo(), cppID: id, message: "the replacement undoes")
    report.expectEqual(["0:120", "384:140"], later.tempoValues, cppID: id,
                       what: "undo restores tick zero and preserves the later point")

    let empty = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  pan: [(24, 64)], tempo: [])
    empty.activate(.tempo)
    for tap in 0...3 { empty.page.tapTempoTap(atMilliseconds: 80_000 + Int64(tap) * 400) }
    report.expect(empty.page.tapTempoIdleElapsed(), cppID: id,
                  message: "the idle window commits the first tempo point")
    report.expectEqual(["0:150"], empty.tempoValues, cppID: id,
                       what: "the commit inserts tick zero on the empty stream")
    report.expect(empty.undo(), cppID: id, message: "the insertion undoes")
    report.expect(empty.tempoValues.isEmpty, cppID: id,
                  message: "undo restores the empty tempo stream")

    let seam = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    seam.activate(seam.panLane)
    for tap in 0...1 { seam.page.tapTempoTap(atMilliseconds: 90_000 + Int64(tap) * 500) }
    report.expect(seam.page.tapTempoSession.tapCount == 2, cppID: id,
                  message: "two taps stand in the session")
    seam.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                            through: 168, points: [LaneWrite(tick: 168, value: 5)])
    report.expect(seam.page.tapTempoSession.tapCount == 0 && !seam.page.tapTempoActive, cppID: id,
                  message: "the document seam clears the session synchronously")
}
