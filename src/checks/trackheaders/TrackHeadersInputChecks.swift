import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawDocument

@MainActor
public func runTrackHeadersInputChecks(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    selectionAndVoiceRouteThroughHeaders(report, suite: session, service: service)
    headerSelectionTargetsResolve(report, suite: session, service: service)
    trackHeaderScopeTransitions(report, suite: session, service: service)
    muteAndSoloHonorCancellationAndButtons(report, suite: session, service: service)
    scrollClampsAndRoutesKeyboardAndWheelInput(report, suite: session, service: service)
    emptyTrackHeadersRejectInputWithoutMutation(report, suite: session, service: service)
    rulerScopeHeaderRecordsGuard(report, suite: session, service: service)
    renameTargetRowAndScrolledTitleResolve(report, suite: session, service: service)
    renameMenuTargetsAndBegins(report, suite: session, service: service)
    renameCommitsAndRebuildsHeader(report, suite: session, service: service)
    reorderCommitsAndRebuildsHeader(report, suite: session, service: service)
    addTrackOpensPickerAndRebuildsHeader(report, suite: session, service: service)
    firstTickDuplicateVoiceAcceptsLastDuplicate(report, suite: session, service: service)
    voiceAcceptInsertsWhenNoTarget(report, suite: session, service: service)
    headerMenuOpensWithTypedRowsAndDismissesWithoutWrite(report, suite: session, service: service)
    headerMenuTargetRowResolvesByTrack(report, suite: session, service: service)
    headerMenuChangeVoiceOpensPickerAfterMenuCloses(report, suite: session, service: service)
    headerMenuRenameBeginsAfterCloseAndFocusesEditor(report, suite: session, service: service)
    headerMenuRowsDispatchRevealDuplicateDelete(report, suite: session, service: service)
    headerMenuStaleStructuralChangeCancelsWithoutWrite(report, suite: session, service: service)
    headerMenuQueuedDestructiveMutationsDropAfterRemap(report, suite: session, service: service)
    headerMenuOutsidePressDismissesWithoutClickThrough(report, suite: session, service: service)
    voiceSubtitleFollowsProgramPosition(report, suite: session, service: service)
    activityRemainsSilentAndRebuiltTracksRetainIdentity(report, suite: session, service: service)
    trackActivityPhysicalPixelPredicates(report, suite: session, service: service)
    independentEffectsControlsHonorCancellation(report, suite: session, service: service)
}

@MainActor
func rulerScopeHeaderRecordsGuard(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    guard let seed = fx.document.notes(in: 0).first else {
        report.fail(id, "timeline scope seed note was not found")
        return
    }
    fx.document.moveNotes([seed.id], byTicks: 24, byKeys: -11)
    report.expect(
        fx.rowForTrack(0) != nil, cppID: id, message: "the Quick track-header model resolves for the ruler scope")
    guard fx.rowForTrack(0) != nil else {
        return
    }
    let document = fx.document
    let trackCount = document.engineTracks.usedTrackCount
    let rows = (0..<fx.headers.rows.count).map { fx.headers.rows[$0] }
    report.expect(
        rows.filter { !$0.isAddTrack }.map(\.track) == Array(0..<trackCount)
            && rows.count == trackCount + (document.canAddTrack ? 1 : 0)
            && rows.last?.isAddTrack == document.canAddTrack,
        cppID: id, message: "header records follow used timeline tracks with one conditional trailing add row")
}

@MainActor
private func independentEffectsControlsHonorCancellation(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::independentEffectsControlsHonorCancellation"
    let fixture = TrackHeadersFixture(suite: suite, service: service)
    let headers = fixture.headers
    let document = fixture.document
    do {
        let effect = try document.addEffect(
            TrackEffectConfig(
                track: 0,
                plugin: PluginEffectConfig(
                    modulePath: "/missing/header-controls.vst3", classUID: Array(repeating: 0, count: 16),
                    name: "A long plug-in name that must never widen Effects",
                    input: .none, pacing: .offline, prerollBars: 0)))
        let row = headers.rows[0]
        let rack = (x: row.effectRect.x + row.effectRect.width / 2, y: row.effectRect.y + row.effectRect.height / 2)
        let live = (x: row.liveRect.x + row.liveRect.width / 2, y: row.liveRect.y + row.liveRect.height / 2)
        report.expect(
            row.hasEffect && !row.liveArmed
                && headers.hitTarget(row: 0, x: rack.x, y: rack.y) == .effects
                && headers.hitTarget(row: 0, x: live.x, y: live.y) == .live,
            cppID: id, message: "a configured, off effect exposes separate rack and Live hit targets")
        headers.updateHover(x: live.x, y: live.y)
        report.expect(
            !row.liveEnabled && !row.liveHovered && !row.effectHovered,
            cppID: id, message: "disabled Live has no hover highlight and does not highlight the rack")
        headers.updateHover(x: rack.x, y: rack.y)
        report.expect(
            row.effectHovered && !row.liveHovered,
            cppID: id, message: "rack hover does not highlight Live")
        var rackRequests: [Int] = []
        headers.onMidiEffectsRequested = { (track: Int) in rackRequests.append(track) }
        let baseline = HeaderDocumentBaseline(document)
        let selection = fixture.session.selectedTracks
        for reason in [0, 1, 2] {
            _ = headers.beginPointer(x: live.x, y: live.y, button: 1, modifiers: 0)
            _ = headers.updatePointer(x: rack.x, y: rack.y, modifiers: 0)
            report.expect(
                !headers.pointer.dragArmed && !headers.pointer.dragging && !headers.reorderIndicatorVisible,
                cppID: id, message: "dragging from Live never arms track reorder")
            headers.inputCancelled(reason: reason)
            _ = headers.endPointer(x: live.x, y: live.y, button: 1, modifiers: 0)
        }
        _ = headers.beginPointer(x: live.x, y: live.y, button: 1, modifiers: 0)
        _ = headers.endPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        _ = headers.beginPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        _ = headers.endPointer(x: live.x, y: live.y, button: 1, modifiers: 0)
        report.expect(
            rackRequests.isEmpty && fixture.session.selectedTracks == selection,
            cppID: id, message: "cross-control releases neither open the rack nor change track scope")
        baseline.expectUnchanged(report, document, cppID: id, phase: "canceled independent controls")
        _ = headers.beginPointer(x: live.x, y: live.y, button: 2, modifiers: 0)
        report.expect(
            headers.menuOpen && rackRequests.isEmpty,
            cppID: id, message: "right-clicking Live opens the header menu without toggling or opening Effects")
        headers.dismissHeaderMenu()

        _ = headers.beginPointer(x: live.x, y: live.y, button: 1, modifiers: 0)
        try document.removeEffect(effect)
        let removed = HeaderDocumentBaseline(document)
        _ = headers.endPointer(x: live.x, y: live.y, button: 1, modifiers: 0)
        report.expect(
            rackRequests.isEmpty && !headers.rows[0].hasEffect && headers.rows[0].liveRect.width == 0,
            cppID: id, message: "removing a pressed effect retires its Live target instead of hitting Effects")
        removed.expectUnchanged(report, document, cppID: id, phase: "stale effect release")

        _ = headers.beginPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        _ = document.moveTrack(0, to: 1)
        let reordered = HeaderDocumentBaseline(document)
        _ = headers.endPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        report.expect(
            rackRequests.isEmpty, cppID: id, message: "a reorder invalidates the pressed track target")
        reordered.expectUnchanged(report, document, cppID: id, phase: "stale reordered target")

        _ = headers.beginPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        fixture.rebuild()
        headers.onMidiEffectsRequested = { (track: Int) in rackRequests.append(track) }
        _ = headers.endPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        report.expect(
            rackRequests.isEmpty, cppID: id, message: "detach and reattach discard the old pressed target")
        reordered.expectUnchanged(report, document, cppID: id, phase: "detached target")

        _ = headers.beginPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        _ = headers.endPointer(x: rack.x, y: rack.y, button: 1, modifiers: 0)
        report.expect(
            rackRequests == [0], cppID: id, message: "empty-track Effects still opens the rack exactly once")
    } catch {
        report.fail(id, "header effect fixture failed: \(error)")
    }
}
