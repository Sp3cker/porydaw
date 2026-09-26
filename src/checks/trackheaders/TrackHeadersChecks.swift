import Foundation
@testable import PorydawApp
import PorydawAppCommands
import PorydawCore
import QtBridge

@MainActor
internal func runTrackHeadersChecks(_ report: CheckReport, session: DocumentSession,
                                   service: ProjectService) {
    runTrackActivityChecks(report)
    let fontFixture = TrackHeadersFixture(suite: session, service: service)
    let roles = Typography(baseFontPx: 13)
    let headers = fontFixture.headers
    let roleID = "swiftcore/TrackHeaders::publishedTypographyRoles"
    func matches(_ map: [String: QVariantSettable], _ role: GridFontSpec) -> Bool {
        map["family"] as? String == role.family &&
            map["pixelSize"] as? Int == role.pixelSize &&
            map["weight"] as? Int == role.weight
    }
    report.expect(matches(headers.controlFont, roles.body) &&
                  matches(headers.normalTitleFont, roles.body) &&
                  matches(headers.boldTitleFont, roles.bodyBold) &&
                  matches(headers.subtitleFont, roles.caption),
                  cppID: roleID,
                  message: "header controls, regular and selected titles, and subtitles publish body, bold body, and caption roles")
    report.expect(fontFixture.trackRows.contains {
        $0.titleBold && matches($0.titleFont, roles.bodyBold) &&
            matches($0.subtitleFont, roles.caption)
    }, cppID: roleID,
    message: "the selected header row paints a bold body title and caption subtitle")
    headers.configureViewport(width: 440, height: 240, fontPx: 26, dpr: 1)
    let resized = Typography(baseFontPx: 26)
    report.expect(matches(headers.controlFont, resized.body) &&
                  matches(headers.boldTitleFont, resized.bodyBold) &&
                  matches(headers.subtitleFont, resized.caption) &&
                  fontFixture.trackRows.contains {
                      $0.titleBold && matches($0.titleFont, resized.bodyBold) &&
                          matches($0.subtitleFont, resized.caption)
                  },
                  cppID: roleID,
                  message: "resizing the header repaints its controls and selected row with the new published roles")
    headers.configureViewport(width: 228, height: 240, fontPx: 13, dpr: 1)
    report.expect(matches(headers.controlFont, roles.body) &&
                  matches(headers.boldTitleFont, roles.bodyBold) &&
                  matches(headers.subtitleFont, roles.caption),
                  cppID: roleID,
                  message: "restoring the captured base restores the header font roles")
    let geometryID = "swiftcore/TrackHeaders::visibleHeaderColumn"
    for base in [12, 13, 16] {
        let geometry = TrackHeadersGeometry(base: Double(base))
        let contentWidth = geometry.bandWidth - Double(geometry.scrollbarWidth)
        let mute = geometry.muteRect(width: contentWidth)
        let solo = geometry.soloRect(width: contentWidth)
        let text = geometry.textRects(width: contentWidth,
                                     metrics: HeaderTextMetrics(title: base, bold: base,
                                                                subtitle: base))
        report.expect(mute.x + mute.width <= contentWidth - Double(geometry.spaceOne) &&
                      solo.x + solo.width <= contentWidth - Double(geometry.spaceOne) &&
                      mute.width == Double(geometry.buttonExtent) &&
                      solo.width == Double(geometry.buttonExtent) &&
                      text.0.x + text.0.width <= mute.x &&
                      text.1.x + text.1.width <= solo.x,
                      cppID: geometryID,
                      message: "at base \(base), both toggle borders and text fit within the header content column")
    }
    unattachedModelPublishesSafeZeroGeometry(report, suite: session, service: service)
    reorderSlotsResolveInsertionTargetsAndUndoRestores(report, suite: session, service: service)
    headerReconciliationUnchanged(report, suite: session, service: service)
    headerReconciliationStructural(report, suite: session, service: service)
    commandMixStatePublishesImmediately(report, suite: session, service: service)
    do {
        try runBlocking {
            try await coreHeaderVoiceUndoRegression(report, suite: session, service: service)
        }
    } catch {
        report.fail("swiftcore/TrackHeaders::supplementalAwaitedVoiceUndo", "history regression failed: \(error)")
    }
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
