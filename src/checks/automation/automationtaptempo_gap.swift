import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerAutomationTapTempoGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::portableTapTempoGap"

    let staged = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)], tempo: []
    )
    staged.activate(.tempo)
    let stagedBefore = staged.snapshot
    let stagedState = staged.document.state
    report.expect(staged.page.activeParameter == .tempo && staged.page.trackAvailable,
                  cppID: id, message: "A001-A004 Tempo activates on an attached production page")
    staged.page.tapTempoTap(atMilliseconds: 1_000)
    report.expect(staged.page.tapTempoTapCount == 1 && staged.page.tapTempoDraftBpm == 0
                      && staged.page.tapTempoActive && !staged.page.tapTempoReady,
                  cppID: id, message: "A005-A010 first tap starts a session but cannot draft or commit")
    report.expect(staged.document.state == stagedState && staged.snapshot == stagedBefore,
                  cppID: id, message: "A007-A010 first tap freezes document revision and history")
    staged.page.tapTempoTap(atMilliseconds: 1_500)
    report.expect(staged.page.tapTempoTapCount == 2 && staged.page.tapTempoDraftBpm == 120
                      && staged.page.tapTempoReady,
                  cppID: id, message: "A011-A012 second tap drafts 120 BPM and makes the session ready")
    staged.page.tapTempoTap(atMilliseconds: 2_000)
    report.expect(staged.page.tapTempoTapCount == 3 && staged.page.tapTempoDraftBpm == 120,
                  cppID: id, message: "A013-A015 third tap updates the same frozen draft")
    report.expect(staged.document.state == stagedState && staged.snapshot == stagedBefore,
                  cppID: id, message: "A016-A019 all draft taps preserve song bytes, revision, and history")

    let stray = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)], tempo: []
    )
    stray.activate(.tempo)
    let strayBefore = stray.snapshot
    let strayState = stray.document.state
    stray.page.tapTempoTap(atMilliseconds: 1_000)
    report.expect(!stray.page.tapTempoIdleElapsed(), cppID: id,
                  message: "A020-A023 one stray tap reaches idle without committing")
    report.expect(stray.page.tapTempoTapCount == 0 && stray.page.tapTempoDraftBpm == 0
                      && !stray.page.tapTempoActive,
                  cppID: id, message: "A024-A025 idle clears the incomplete tap session")
    report.expect(stray.document.state == strayState && stray.snapshot == strayBefore,
                  cppID: id, message: "A026 incomplete idle preserves the complete document and history state")

    let inserted = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)], tempo: []
    )
    inserted.activate(.tempo)
    let insertedBefore = inserted.snapshot
    for tap in 0...3 {
        inserted.page.tapTempoTap(atMilliseconds: 10_000 + Int64(tap) * 400)
    }
    report.expect(inserted.page.tapTempoDraftBpm == 150
                      && inserted.page.tapTempoTapCount == 4
                      && inserted.page.tapTempoReady,
                  cppID: id, message: "A027-A033 four 400 ms taps draft one ready 150 BPM commit")
    report.expect(inserted.page.tapTempoIdleElapsed(), cppID: id,
                  message: "A034-A035 idle commits the ready draft once")
    report.expectEqual(["0:150"], inserted.tempoValues, cppID: id,
                       what: "A036-A040 the first tempo point is inserted at tick zero with the draft BPM")
    report.expect(inserted.document.revision == insertedBefore.revision + 1
                      && inserted.document.history.canUndo,
                  cppID: id, message: "A036-A041 the commit creates one revision and one undoable history entry")
    report.expect(inserted.page.tapTempoTapCount == 0 && inserted.page.tapTempoDraftBpm == 0,
                  cppID: id, message: "A041-A042 commit clears the tap session")
    report.expect(inserted.undo(), cppID: id, message: "A043-A044 the tick-zero tempo insertion is undoable")
    report.expect(inserted.tempoValues.isEmpty && !inserted.document.history.canUndo,
                  cppID: id, message: "A045-A047 undo removes the first tempo and consumes the sole history entry")

    let silent = drawerAutomationAutomationFixture(
        suite: suite, service: service, tempo: [(0, TimeDefaults.microsecondsPerQuarterNote(forBPM: 255))]
    )
    silent.activate(.tempo)
    let silentBefore = silent.snapshot
    let silentState = silent.document.state
    for tap in 0...3 {
        silent.page.tapTempoTap(atMilliseconds: 20_000 + Int64(tap) * 235)
    }
    report.expect(silent.page.tapTempoDraftBpm == 255 && silent.page.tapTempoReady,
                  cppID: id, message: "A048-A055 a clamped cadence drafts the existing 255 BPM tick-zero tempo")
    report.expect(!silent.page.tapTempoIdleElapsed(), cppID: id,
                  message: "A056-A057 an equal tick-zero tempo is a silent no-op")
    report.expect(silent.document.state == silentState && silent.snapshot == silentBefore,
                  cppID: id, message: "A058-A062 an equal draft preserves tempo, revision, and history")

    let replaced = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(0, TimeDefaults.microsecondsPerQuarterNote(forBPM: 100)),
                (96, TimeDefaults.microsecondsPerQuarterNote(forBPM: 120)),
                (192, TimeDefaults.microsecondsPerQuarterNote(forBPM: 80))]
    )
    replaced.activate(.tempo)
    let replacedBefore = replaced.snapshot
    for tap in 0...3 {
        replaced.page.tapTempoTap(atMilliseconds: 30_000 + Int64(tap) * 400)
    }
    report.expect(replaced.page.tapTempoIdleElapsed(), cppID: id,
                  message: "A063-A069 changed ready draft commits through the page idle route")
    report.expectEqual(["0:150", "96:120", "192:80"], replaced.tempoValues, cppID: id,
                       what: "A070-A075 commit replaces tick zero and preserves both later tempo points")
    report.expect(replaced.document.revision == replacedBefore.revision + 1
                      && replaced.document.history.canUndo,
                  cppID: id, message: "A071-A076 replacement is exactly one undoable revision")
    report.expect(replaced.undo(), cppID: id, message: "A077 replacement is undoable")
    report.expectEqual(["0:100", "96:120", "192:80"], replaced.tempoValues, cppID: id,
                       what: "A078-A080 undo restores the original tick-zero tempo and later points")

    let laterOnly = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(96, TimeDefaults.microsecondsPerQuarterNote(forBPM: 120))]
    )
    laterOnly.activate(.tempo)
    let laterBefore = laterOnly.snapshot
    for tap in 0...3 {
        laterOnly.page.tapTempoTap(atMilliseconds: 40_000 + Int64(tap) * 500)
    }
    report.expect(laterOnly.page.tapTempoIdleElapsed(), cppID: id,
                  message: "A081-A086 ready draft commits on a document whose first tempo is nonzero")
    report.expectEqual(["0:120", "96:120"], laterOnly.tempoValues, cppID: id,
                       what: "A087-A091 commit inserts tick zero and preserves the later tempo")
    report.expect(laterOnly.document.revision == laterBefore.revision + 1
                      && laterOnly.document.history.canUndo
                      && laterOnly.page.tapTempoTapCount == 0,
                  cppID: id, message: "A087-A093 insertion is one history entry and resets the session")
    report.expect(laterOnly.undo() && laterOnly.tempoValues == ["96:120"], cppID: id,
                  message: "A094-A095 undo removes only the inserted tick-zero tempo")

    let concurrent = drawerAutomationAutomationFixture(
        suite: suite, service: service, tempo: []
    )
    concurrent.activate(.tempo)
    concurrent.page.tapTempoTap(atMilliseconds: 50_000)
    concurrent.page.tapTempoTap(atMilliseconds: 50_500)
    report.expect(concurrent.page.tapTempoDraftBpm == 120,
                  cppID: id, message: "A096-A098 concurrent scenario begins with a live draft")
    _ = concurrent.page.openPrompt(tick: 0, value: 120)
    _ = concurrent.page.acceptPrompt(displayedValue: 150)
    let concurrentWritten = concurrent.snapshot
    report.expect(concurrent.page.tapTempoTapCount == 0 && concurrent.page.tapTempoDraftBpm == 0,
                  cppID: id, message: "A099-A105 a document publication synchronously clears the captured session")
    report.expect(!concurrent.page.tapTempoIdleElapsed() && concurrent.snapshot == concurrentWritten
                      && concurrent.tempoValues == ["0:150"],
                  cppID: id, message: "A100-A114 stale idle cannot overwrite the concurrent tempo edit")

    let detached = drawerAutomationAutomationFixture(
        suite: suite, service: service, tempo: []
    )
    detached.page.detach()
    let detachedBefore = detached.snapshot
    detached.page.tapTempoTap(atMilliseconds: 60_000)
    report.expect(detached.page.tapTempoTapCount == 0 && !detached.page.tapTempoActive,
                  cppID: id, message: "A115-A118 detached page ignores tap tempo input")
    report.expect(!detached.page.tapTempoIdleElapsed() && detached.snapshot == detachedBefore,
                  cppID: id, message: "A119-A121 detached idle performs no document transaction")

    var cadence = AutomationTapTempoSession()
    for tap in 0...9 {
        cadence.registerTap(nowMs: 70_000 + Int64(tap) * 500)
    }
    report.expect(cadence.tapCount == 10 && cadence.draftBpm == 120,
                  cppID: id, message: "A142-A151 mean cadence uses the newest bounded interval window")
    report.expect(AutomationTapTempoSession.bpm(forMeanIntervalMs: 1) == TimeDefaults.maximumTempoBPM
                      && AutomationTapTempoSession.bpm(forMeanIntervalMs: 10_000) == TimeDefaults.minimumTempoBPM,
                  cppID: id, message: "A152-A157 mean conversion clamps to the production tempo bounds")
    report.expect(cadence.idleCommitMs >= AutomationTapTempoSession.commitMinimumMs
                      && cadence.idleCommitMs <= AutomationTapTempoSession.commitMaximumMs,
                  cppID: id, message: "A158-A159 idle commit delay remains inside the production bounds")
}
