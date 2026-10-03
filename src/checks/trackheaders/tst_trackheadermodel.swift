import Foundation
import PorydawApp
import PorydawCore

@MainActor
func unattachedModelPublishesSafeZeroGeometry(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = TrackHeadersFixture(suite: suite, service: service, configured: false)
    let headers = fixture.headers
    report.expectEqual(expected: 0, actual: headers.rows[headers.rows.count - 1].activityLeftHeight,
                       cppID: trackHeadersUnattachedID, what: "add row left activity is dark")
    report.expectEqual(expected: 0, actual: headers.rows[headers.rows.count - 1].activityRightHeight,
                       cppID: trackHeadersUnattachedID, what: "add row right activity is dark")
    report.expectEqual(expected: 0.0, actual: headers.viewportHeight, cppID: trackHeadersUnattachedID,
                       what: "unconfigured viewport has zero height")
    report.expectEqual(expected: 0.0, actual: headers.maximumScrollY, cppID: trackHeadersUnattachedID,
                       what: "unconfigured viewport has no scroll range")
    report.expectEqual(expected: 3, actual: headers.rows.count, cppID: trackHeadersUnattachedID,
                       what: "unconfigured model has two track rows and the add-track row")
    report.expectEqual(expected: [0, 1], actual: fixture.trackRows.map(\.track), cppID: trackHeadersUnattachedID,
                       what: "track rows exist before viewport attachment")
    for row in fixture.trackRows {
        report.expectEqual(expected: 0.0, actual: row.activityLeftHeight, cppID: trackHeadersUnattachedID,
                           what: "track \(row.track): unattached left activity height")
        report.expectEqual(expected: 0.0, actual: row.activityRightHeight, cppID: trackHeadersUnattachedID,
                           what: "track \(row.track): unattached right activity height")
    }
}

@MainActor
func reorderSlotsResolveInsertionTargetsAndUndoRestores(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    // Distinct source/target directions exercise insertion slots, not a direct
    // move-to-row shortcut. The third row is a real duplicated track.
    let probes: [(label: String, from: Int, target: Int, fraction: Double,
                  muted: Int, order: [Int], mutedAfter: Int, changes: Bool)] = [
        ("top quarter inserts above", 2, 0, 0.125, 2, [2, 0, 1], 0, true),
        ("bottom three quarters insert below", 0, 2, 0.75, 0, [1, 2, 0], 2, true),
        ("adjacent insertion slot is unchanged", 1, 1, 0.75, 1, [0, 1, 2], 1, false),
    ]
    for probe in probes {
        let fixture = TrackHeadersFixture(suite: suite, service: service)
        let document = fixture.document
        guard let duplicated = document.duplicateTrack(0), duplicated == 2 else {
            report.fail(trackHeadersReorderID, "\(probe.label): cannot create third track")
            continue
        }
        let original = fixture.channelOrder
        report.expectEqual(expected: 3, actual: document.engineTracks.usedTrackCount,
                           cppID: trackHeadersReorderID, what: "duplicate adds exactly one track")
        report.expectEqual(expected: 3, actual: Set(original).count, cppID: trackHeadersReorderID,
                           what: "\(probe.label): channels distinguish all three track identities")
        fixture.session.mutedTracks = [probe.muted]
        fixture.headers.refreshFromDocument()
        let revision = document.revision
        let baseline = document.history.currentIdentity
        let couldUndo = document.history.canUndo
        let couldRedo = document.history.canRedo
        fixture.drag(report, from: probe.from, target: probe.target,
                     fraction: probe.fraction, label: probe.label)
        report.expectEqual(expected: probe.order.map { original[$0] }, actual: fixture.channelOrder,
                           cppID: trackHeadersReorderID, what: "\(probe.label): committed track order")
        report.expectEqual(expected: Set([probe.mutedAfter]), actual: fixture.session.mutedTracks,
                           cppID: trackHeadersReorderID, what: "\(probe.label): mute follows the moved identity")
        report.expectEqual(expected: [probe.mutedAfter], actual: 
                           fixture.trackRows.filter(\.muteChecked).map(\.track),
                           cppID: trackHeadersReorderID, what: "\(probe.label): visible mute follows the track")
        report.expectEqual(expected: revision + (probe.changes ? 1 : 0), actual: document.revision,
                           cppID: trackHeadersReorderID, what: "\(probe.label): one revision only for a real move")
        if !probe.changes {
            report.expectEqual(expected: baseline, actual: document.history.currentIdentity, cppID: trackHeadersReorderID,
                               what: "\(probe.label): no history entry")
            report.expectEqual(expected: couldUndo, actual: document.history.canUndo, cppID: trackHeadersReorderID,
                               what: "\(probe.label): undo reachability unchanged")
            report.expectEqual(expected: couldRedo, actual: document.history.canRedo, cppID: trackHeadersReorderID,
                               what: "\(probe.label): redo reachability unchanged")
            report.expect(document.history.undoDocument(), cppID: trackHeadersReorderID,
                          message: "no-op move leaves duplicate as the next undo")
            report.expectEqual(expected: 2, actual: document.engineTracks.usedTrackCount,
                               cppID: trackHeadersReorderID, what: "undo duplicate restores original track count")
            continue
        }
        let moved = document.history.currentIdentity
        report.expect(moved != baseline, cppID: trackHeadersReorderID,
                      message: "\(probe.label): move enters document history")
        report.expect(document.history.undoDocument(), cppID: trackHeadersReorderID,
                      message: "\(probe.label): undo succeeds")
        report.expectEqual(expected: baseline, actual: document.history.currentIdentity, cppID: trackHeadersReorderID,
                           what: "\(probe.label): one undo returns to duplicated baseline")
        report.expectEqual(expected: original, actual: fixture.channelOrder, cppID: trackHeadersReorderID,
                           what: "\(probe.label): undo restores order")
        report.expectEqual(expected: Set([probe.muted]), actual: fixture.session.mutedTracks, cppID: trackHeadersReorderID,
                           what: "\(probe.label): undo restores mute identity")
        report.expectEqual(expected: [probe.muted], actual: fixture.trackRows.filter(\.muteChecked).map(\.track),
                           cppID: trackHeadersReorderID, what: "\(probe.label): undo restores visible mute")
        report.expect(document.history.redoDocument(), cppID: trackHeadersReorderID,
                      message: "\(probe.label): redo succeeds")
        report.expectEqual(expected: moved, actual: document.history.currentIdentity, cppID: trackHeadersReorderID,
                           what: "\(probe.label): redo restores the move history entry")
        report.expectEqual(expected: probe.order.map { original[$0] }, actual: fixture.channelOrder,
                           cppID: trackHeadersReorderID, what: "\(probe.label): redo restores order")
        report.expectEqual(expected: Set([probe.mutedAfter]), actual: fixture.session.mutedTracks,
                           cppID: trackHeadersReorderID, what: "\(probe.label): redo restores mute identity")
        report.expectEqual(expected: [probe.mutedAfter], actual: 
                           fixture.trackRows.filter(\.muteChecked).map(\.track),
                           cppID: trackHeadersReorderID, what: "\(probe.label): redo restores visible mute")
        report.expect(document.history.undoDocument(), cppID: trackHeadersReorderID,
                      message: "return to duplicated baseline")
        report.expect(document.history.undoDocument(), cppID: trackHeadersReorderID,
                      message: "undo duplicate")
        report.expectEqual(expected: 2, actual: document.engineTracks.usedTrackCount,
                           cppID: trackHeadersReorderID, what: "undo duplicate restores original track count")
    }
}

@MainActor
func headerReconciliationUnchanged(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = TrackHeadersFixture(suite: suite, service: service)
    let resets = fixture.headers.rowRebuildCount
    let original = fixture.channelOrder
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: trackHeadersUnchangedID,
                       phase: "before unchanged reconciliation")
    fixture.headers.refreshFromDocument()
    report.expectEqual(expected: resets, actual: fixture.headers.rowRebuildCount, cppID: trackHeadersUnchangedID,
                       what: "unchanged document refresh emits zero row-model resets")
    report.expectEqual(expected: original, actual: fixture.channelOrder, cppID: trackHeadersUnchangedID,
                       what: "unchanged refresh preserves document track order")
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: trackHeadersUnchangedID,
                       phase: "unchanged refresh")
}

@MainActor
func headerReconciliationStructural(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = TrackHeadersFixture(suite: suite, service: service)
    let document = fixture.document
    let headers = fixture.headers
    let original = fixture.channelOrder
    let baseline = document.history.currentIdentity
    let resets = headers.rowRebuildCount
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: trackHeadersStructuralID,
                       phase: "before structural reconciliation")
    document.deleteTrack(1)
    report.expectEqual(expected: resets + 1, actual: headers.rowRebuildCount, cppID: trackHeadersStructuralID,
                       what: "delete rebuilds rows exactly once")
    fixture.expectRows(report, names: ["Lead"], cppID: trackHeadersStructuralID, phase: "after delete")
    report.expectEqual(expected: Array(original.prefix(1)), actual: fixture.channelOrder, cppID: trackHeadersStructuralID,
                       what: "delete removes exactly the last track")
    report.expect(document.history.undoDocument(), cppID: trackHeadersStructuralID,
                  message: "undo restores deleted track")
    report.expectEqual(expected: baseline, actual: document.history.currentIdentity, cppID: trackHeadersStructuralID,
                       what: "restore returns to original history identity")
    report.expectEqual(expected: resets + 2, actual: headers.rowRebuildCount, cppID: trackHeadersStructuralID,
                       what: "restore rebuilds rows exactly once")
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: trackHeadersStructuralID, phase: "after restore")
    report.expectEqual(expected: original, actual: fixture.channelOrder, cppID: trackHeadersStructuralID,
                       what: "restore recovers original track order")

    headers.beginRename(track: 0)
    report.expectEqual(expected: 0, actual: headers.renamingTrack, cppID: trackHeadersStructuralID,
                       what: "rename opens on a live row")
    headers.renameDraft = "zzz"
    let revision = document.revision
    document.deleteTrack(1)
    report.expectEqual(expected: resets + 3, actual: headers.rowRebuildCount, cppID: trackHeadersStructuralID,
                       what: "structural change during rename rebuilds rows exactly once")
    report.expectEqual(expected: -1, actual: headers.renamingTrack, cppID: trackHeadersStructuralID,
                       what: "structural change cancels an open rename")
    report.expectEqual(expected: "Lead", actual: document.trackName(0), cppID: trackHeadersStructuralID,
                       what: "structural cancellation does not commit the draft")
    report.expectEqual(expected: revision + 1, actual: document.revision, cppID: trackHeadersStructuralID,
                       what: "only deletion commits during rename cancellation")
    // A late editor completion must not resurrect the cancelled draft.
    headers.finishRename(commit: true, restoreRollFocus: false)
    report.expectEqual(expected: "Lead", actual: document.trackName(0), cppID: trackHeadersStructuralID,
                       what: "late rename completion cannot commit cancelled text")
    report.expect(document.history.undoDocument(), cppID: trackHeadersStructuralID,
                  message: "single undo after cancellation restores the deleted track")
    report.expectEqual(expected: baseline, actual: document.history.currentIdentity, cppID: trackHeadersStructuralID,
                       what: "cancelled rename leaves no extra history entry")
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: trackHeadersStructuralID,
                       phase: "after cancelled rename undo")
}
