import Foundation
import PorydawApp
import PorydawCore

@MainActor
internal func runTrackHeadersChecks(_ report: CheckReport, session: DocumentSession,
                                   service: ProjectService) {
    runTrackActivityChecks(report)
    unattachedModelPublishesSafeZeroGeometry(report, suite: session, service: service)
    reorderSlotsResolveInsertionTargetsAndUndoRestores(report, suite: session, service: service)
    headerReconciliationUnchanged(report, suite: session, service: service)
    headerReconciliationStructural(report, suite: session, service: service)
    commandMixStatePublishesImmediately(report, suite: session, service: service)
    do {
        try trackHeadersRunBlocking {
            try await coreHeaderVoiceUndoRegression(report, suite: session, service: service)
        }
    } catch {
        report.fail("swiftcore/TrackHeaders::supplementalAwaitedVoiceUndo", "history regression failed: \(error)")
    }
}

@MainActor
private func trackHeadersRunBlocking<T>(
    _ operation: @escaping @MainActor () async throws -> T
) throws -> T {
    var outcome: Result<T, Error>?
    Task { @MainActor in
        do { outcome = .success(try await operation()) }
        catch { outcome = .failure(error) }
    }
    let deadline = Date().addingTimeInterval(20)
    while outcome == nil {
        if Date() > deadline { throw TrackHeadersCheckTimeout.timeout }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return try outcome!.get()
}

private enum TrackHeadersCheckTimeout: Error {
    case timeout
}

@MainActor
private func commandMixStatePublishesImmediately(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = TrackHeadersFixture(suite: suite, service: service)
    let session = fixture.session
    let headers = fixture.headers
    let grid = PianoGrid(session: session)
    let document = fixture.document
    let revision = document.revision
    let history = document.history.currentIdentity
    let dirty = document.isDirty
    let unaffected = headers.rows[1]
    var publications: [SessionChangeDomains] = []
    var playbackPublications = 0
    session.onPlayback = { _ in playbackPublications += 1 }
    session.onChange = { [weak headers] change in
        publications.append(change.domains)
        headers?.documentDidChange(change)
    }

    grid.performCommand(command: EditCommand.muteTracks.rawValue)
    report.expectEqual(expected: Set([0]), actual: session.mutedTracks, cppID: trackHeadersMixPublicationID,
                       what: "mute command changes session mix state")
    report.expect(headers.rows[0].muteChecked, cppID: trackHeadersMixPublicationID,
                  message: "mute command updates header in the same publication")
    report.expect(headers.rows[1] === unaffected, cppID: trackHeadersMixPublicationID,
                  message: "mute publication retains the unrelated row")

    grid.performCommand(command: EditCommand.soloTracks.rawValue)
    report.expectEqual(expected: Set([0]), actual: session.soloedTracks, cppID: trackHeadersMixPublicationID,
                       what: "solo command changes session mix state")
    report.expect(headers.rows[0].soloChecked, cppID: trackHeadersMixPublicationID,
                  message: "solo command updates header in the same publication")
    report.expectEqual(expected: 2, actual: publications.count, cppID: trackHeadersMixPublicationID,
                       what: "each command publishes once without a playhead poll")
    report.expect(publications.allSatisfy { $0 == [.mixState] }, cppID: trackHeadersMixPublicationID,
                  message: "command publications contain only the mix-state domain")
    report.expectEqual(expected: revision, actual: document.revision, cppID: trackHeadersMixPublicationID,
                       what: "mix commands do not revise the document")
    report.expectEqual(expected: history, actual: document.history.currentIdentity, cppID: trackHeadersMixPublicationID,
                       what: "mix commands create no history")
    report.expectEqual(expected: dirty, actual: document.isDirty, cppID: trackHeadersMixPublicationID,
                       what: "mix commands do not dirty the document")
    report.expectEqual(expected: 0, actual: playbackPublications, cppID: trackHeadersMixPublicationID,
                       what: "mix commands do not publish a playback timeline")
}
