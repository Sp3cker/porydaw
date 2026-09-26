import Foundation
import PorydawApp
import PorydawCore

@MainActor
internal func runTrackHeadersInputChecks(_ report: CheckReport, session: DocumentSession,
                                        service: ProjectService) {
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
}

@MainActor
func rulerScopeHeaderRecordsGuard(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService) {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    guard let seed = fx.document.notes(in: 0).first else {
        report.fail(id, "timeline scope seed note was not found")
        return
    }
    fx.document.moveNotes([seed.id], byTicks: 24, byKeys: -11)
    guard fx.rowForTrack(0) != nil else {
        report.fail(id, "could not find the Quick track-header model")
        return
    }
    let document = fx.document
    let trackCount = document.engineTracks.usedTrackCount
    let rows = (0..<fx.headers.rows.count).map { fx.headers.rows[$0] }
    report.expect(rows.filter { !$0.isAddTrack }.map(\.track) == Array(0..<trackCount)
                  && rows.count == trackCount + (document.canAddTrack ? 1 : 0)
                  && rows.last?.isAddTrack == document.canAddTrack,
                  cppID: id, message: "header records follow used timeline tracks with one conditional trailing add row")
}
