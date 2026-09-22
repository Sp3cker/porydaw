import Foundation
@testable import PorydawApp
import PorydawCore

// Existing scenarios paired with voice.cpp.
// Entry order remains in VoiceChangesPageChecks.swift.

@MainActor
func drawerVoiceUndoRedoRefresh(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let builds = page.contentBuildCount
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    _ = page.acceptPicker()
    report.expectEqual(builds + 1, page.contentBuildCount, cppID: drawerVoiceHistoryID,
                       what: "one committed edit rebuilds the projection exactly once")
    let editedBuilds = page.contentBuildCount
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceHistoryID, "undo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > editedBuilds, cppID: drawerVoiceHistoryID,
                  message: "undo rebuilds every affected page")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceHistoryID,
                       what: "undo removes the inserted marker")
    report.expectEqual(VoiceLanePolicy.label(slot: programs[0],
                                             view: fixture.session.bankSlots[programs[0]]),
                       page.contextLabel(at: page.contextSlot), cppID: drawerVoiceHistoryID,
                       what: "undo restores the context the readout resolves")
    let undoneBuilds = page.contentBuildCount
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceHistoryID, "redo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > undoneBuilds, cppID: drawerVoiceHistoryID,
                  message: "redo rebuilds the projection again")
    report.expectEqual([0, 48, 96, 120], page.markerTicks, cppID: drawerVoiceHistoryID,
                       what: "redo republishes the full marker set")

    // An equal refresh leaves every marker exactly as it was: the rebuild runs,
    // and no published row is replaced.
    let identities = page.markerIdentities
    let publishedMarkers = page.markers.asArray
    page.refreshFromDocument()
    report.expectEqual(identities, page.markerIdentities, cppID: drawerVoiceHistoryID,
                       what: "an equal refresh leaves every marker identity in place")
    report.expectEqual(publishedMarkers.count, page.markers.count, cppID: drawerVoiceHistoryID,
                       what: "an equal refresh publishes the same marker count")
    report.expect(zip(publishedMarkers, page.markers.asArray).allSatisfy { $0 === $1 },
                  cppID: drawerVoiceHistoryID,
                  message: "an equal refresh replaces no published marker row")
}

@MainActor
func drawerVoicePlayheadDiagnostics(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let documentFacts = fixture.snapshot
    page.refreshPlayhead(tick: 0, playing: true)
    let builds = page.contentBuildCount
    let presentations = page.playheadPresentationCount
    let contextChanges = page.contextChangeCount
    let readout = page.readoutText
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the playing context opens on the first program span")

    // Every other distinct shared tick inside the same span: the page consumes
    // each of them and rebuilds no static content.
    var ticks: [Double] = []
    for step in 1..<48 { ticks.append(Double(step)) }
    for tick in ticks {
        page.refreshPlayhead(tick: tick, playing: true)
    }
    report.expectEqual(presentations + UInt64(ticks.count), page.playheadPresentationCount,
                       cppID: drawerVoiceDiagnosticsID,
                       what: "every distinct shared presentation is consumed once")
    // A shared position that rounds to a tick the page already presented is not
    // a presentation of its own, and neither is an equal one.
    let roundingBase = page.playheadPresentationCount
    page.refreshPlayhead(tick: 47.4, playing: true)
    report.expectEqual(roundingBase, page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "a position rounding to an already presented tick presents nothing")
    page.refreshPlayhead(tick: 47, playing: true)
    report.expectEqual(roundingBase, page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "an equal presentation is not consumed twice")
    report.expectEqual(builds, page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "playhead-only movement inside one span rebuilds no content")
    report.expectEqual(contextChanges, page.contextChangeCount, cppID: drawerVoiceDiagnosticsID,
                       what: "no span was crossed inside the span itself")
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the presented context stayed in its own span")
    report.expectEqual(readout, page.readoutText, cppID: drawerVoiceDiagnosticsID,
                       what: "the readout names the same program throughout the span")
    report.expectEqual(documentFacts, fixture.snapshot, cppID: drawerVoiceDiagnosticsID,
                       what: "playhead movement mutates no document and consumes no redo")

    // An equal presentation publishes nothing.
    let settled = page.playheadPresentationCount
    page.refreshPlayhead(tick: ticks.last ?? 0, playing: true)
    report.expectEqual(settled, page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "an equal presentation is not consumed twice")

    // Crossing into the next span updates the readout and rebuilds once.
    page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(programs[1], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "crossing a span updates the context indicator")
    report.expectEqual(builds + 1, page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "crossing a span rebuilds the projection exactly once")
    report.expectEqual(contextChanges + 1, page.contextChangeCount, cppID: drawerVoiceDiagnosticsID,
                       what: "one context change is counted")
    report.expect(page.readoutText.hasPrefix(String(format: "%03d", programs[1])),
                  cppID: drawerVoiceDiagnosticsID, message: "the readout names the new span's program")

    // Stopping returns the context to the edit cursor.
    fixture.session.editCursor = 200
    page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(programs[2], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the stopped context follows the edit cursor")
    report.expectEqual(builds + 2, page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "the playing-to-stopped transition rebuilds once")
}

@MainActor
func drawerVoiceAuditionCapability(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    var calls: [[UInt8]] = []
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    let baseline = fixture.snapshot
    let first = UInt8(programs[0])
    let second = UInt8(programs[1])

    func hold(_ program: Int) {
        guard let row = page.pickerRowPrograms.firstIndex(of: program) else {
            report.fail(drawerVoiceAuditionID, "the audition program is absent from the picker")
            return
        }
        page.pressAndHoldPickerRow(index: row)
    }
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    hold(programs[0])
    hold(programs[0])
    hold(programs[1])
    page.releasePickerAudition()
    page.releasePickerAudition()
    report.expectEqual([[first, 60, 112], [first, 60, 0],
                        [first, 60, 112], [first, 60, 0],
                        [second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "held program replacement releases once before the next note")

    calls.removeAll()
    hold(programs[0])
    page.setPickerFilter(text: "__no_voice_can_match__")
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "filter invalidation releases the sounding program")
    page.cancelPicker()

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    _ = page.acceptPicker()
    report.expectEqual([[second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "same-value acceptance releases without a musical edit")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceAuditionID,
                       what: "audition, filtering and same-value acceptance leave document/history unchanged")

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    hold(programs[0])
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    page.onAuditionVoice = nil
    report.expectEqual([[first, 60, 112], [first, 60, 0],
                        [second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "picker and callback replacement release through the old owner")
    report.expect(!page.auditionAvailable, cppID: drawerVoiceAuditionID,
                  message: "removing the real callback removes audition availability")

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    fixture.session.selectedTrack = 1
    page.releasePickerAudition()
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "stale track cancellation releases without a duplicate note-off")
    fixture.session.selectedTrack = 0
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    calls.removeAll()
    hold(programs[1])
    page.cancelSectionInteraction()
    report.expectEqual([[second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "workspace cancellation releases its held voice")
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    page.detach()
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "document teardown releases the final held program")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceAuditionID,
                       what: "picker replacement and teardown write no musical state")
}
