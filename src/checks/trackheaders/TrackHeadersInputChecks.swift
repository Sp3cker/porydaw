import Foundation
import PorydawApp
import PorydawCore

@MainActor
internal func runTrackHeadersInputChecks(_ report: CheckReport, session: DocumentSession,
                                        service: ProjectService) {
    selectionAndVoiceRouteThroughHeaders(report, suite: session, service: service)
    trackHeaderScopeTransitions(report, suite: session, service: service)
    muteAndSoloHonorCancellationAndButtons(report, suite: session, service: service)
    scrollClampsAndRoutesKeyboardAndWheelInput(report, suite: session, service: service)
    emptyTrackHeadersRejectInputWithoutMutation(report, suite: session, service: service)
    renameCommitsAndRebuildsHeader(report, suite: session, service: service)
    reorderCommitsAndRebuildsHeader(report, suite: session, service: service)
    addTrackOpensPickerAndRebuildsHeader(report, suite: session, service: service)
    headerMenuOpensWithTypedRowsAndDismissesWithoutWrite(report, suite: session, service: service)
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
