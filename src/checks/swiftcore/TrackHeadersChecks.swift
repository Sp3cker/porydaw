import Foundation
import PorydawApp
import PorydawCore

// Native equivalents of the four cases in trackheaders/tst_trackheadermodel.cpp.
// Every edit and history transition goes through a real document/session; input
// probes drive the same presenter methods used by the production header band.
private let unattachedID = "swiftcore/TrackHeaders::unattachedModelPublishesSafeZeroGeometry"
private let reorderID = "swiftcore/TrackHeaders::reorderSlotsResolveInsertionTargetsAndUndoRestores"
private let unchangedID = "swiftcore/TrackHeaders::headerReconciliationUnchanged"
private let structuralID = "swiftcore/TrackHeaders::headerReconciliationStructural"
private let mixPublicationID = "swiftcore/TrackHeaders::commandMixStatePublishesImmediately"

@MainActor
struct TrackHeadersFixture {
    let session: DocumentSession
    let headers: TrackHeadersPresenter
    var document: SongDocument { session.document }
    var trackRows: [TrackHeaderRowHandle] {
        (0..<headers.rows.count).map { headers.rows[$0] }.filter { !$0.isAddTrack }
    }
    var channelOrder: [UInt8] {
        let map = document.engineTracks
        return map.tracks.prefix(map.usedTrackCount).map(\.channel)
    }

    init(suite: DocumentSession, service: ProjectService, configured: Bool = true) {
        let file = MidiFile(division: 24, chunks: [
            MidiChunk(events: [.meta(type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 96),
            MidiChunk(events: [
                .meta(type: 0x03, data: Array("Lead".utf8)),
                .channel(status: 0xC0, data0: 0),
                .channel(status: 0x90, data0: 60, data1: 100),
                .channel(tick: 24, status: 0x80, data0: 60),
            ], endTick: 96),
            MidiChunk(events: [
                .meta(type: 0x03, data: Array("Bass".utf8)),
                .channel(status: 0xC1, data0: 1),
                .channel(status: 0x91, data0: 48, data1: 80),
                .channel(tick: 48, status: 0x81, data0: 48),
            ], endTick: 96),
        ])
        let document = SongDocument(file: file, config: suite.document.state.config,
                                    source: suite.document.source, trackBudget: 16)
        session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName,
                                  sampleRate: 48_000)
        session.selectedTrack = 0
        let headers = TrackHeadersPresenter(baseFontPx: 13)
        self.headers = headers
        headers.attach(session: session, palette: GridPalette())
        session.onChange = { [weak headers] change in headers?.documentDidChange(change) }
        if configured {
            headers.configureViewport(width: 228, height: 240, fontPx: 13, dpr: 1)
            headers.configureTextMetrics(titleLineSpacing: 18, boldLineSpacing: 18,
                                         subtitleLineSpacing: 16)
        }
    }

    func drag(_ report: CheckReport, from: Int, target: Int, fraction: Double,
              label: String) {
        let x = headers.trackHeaderWidth / 2
        let height = Double(headers.rowHeight)
        let startY = (Double(from) + 0.25) * height
        let dropY = (Double(target) + fraction) * height
        report.expect(headers.beginPointer(x: x, y: startY, button: 1, modifiers: 0),
                      cppID: reorderID, message: "\(label): header accepts press")
        report.expect(headers.updatePointer(x: x, y: dropY, modifiers: 0),
                      cppID: reorderID, message: "\(label): header accepts drag")
        report.expect(headers.endPointer(x: x, y: dropY, button: 1, modifiers: 0),
                      cppID: reorderID, message: "\(label): header accepts release")
    }

    func expectRows(_ report: CheckReport, names: [String], cppID: String, phase: String) {
        report.expectEqual(Array(names.indices), trackRows.map(\.track), cppID: cppID,
                           what: "\(phase): rows follow engine track order")
        let titles = names.enumerated().map { "\($0.offset + 1) · \($0.element)" }
        report.expectEqual(titles, trackRows.map(\.title), cppID: cppID,
                           what: "\(phase): rows display ordered numbered track names")
        report.expectEqual(names.count + 1, headers.rows.count, cppID: cppID,
                           what: "\(phase): one row per track plus add-track row")
        let addRows = (0..<headers.rows.count).filter { headers.rows[$0].isAddTrack }
        report.expectEqual([names.count], addRows, cppID: cppID,
                           what: "\(phase): add-track row remains last")
    }
}

@MainActor
internal func runTrackHeadersChecks(_ report: CheckReport, session: DocumentSession,
                                   service: ProjectService) {
    unattachedModelPublishesSafeZeroGeometry(report, suite: session, service: service)
    reorderSlotsResolveInsertionTargetsAndUndoRestores(report, suite: session, service: service)
    headerReconciliationUnchanged(report, suite: session, service: service)
    headerReconciliationStructural(report, suite: session, service: service)
    commandMixStatePublishesImmediately(report, suite: session, service: service)
}

@MainActor
private func unattachedModelPublishesSafeZeroGeometry(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = TrackHeadersFixture(suite: suite, service: service, configured: false)
    let headers = fixture.headers
    report.expectEqual(0.0, headers.viewportHeight, cppID: unattachedID,
                       what: "unconfigured viewport has zero height")
    report.expectEqual(0.0, headers.maximumScrollY, cppID: unattachedID,
                       what: "unconfigured viewport has no scroll range")
    report.expectEqual(3, headers.rows.count, cppID: unattachedID,
                       what: "unconfigured model has two track rows and the add-track row")
    report.expectEqual([0, 1], fixture.trackRows.map(\.track), cppID: unattachedID,
                       what: "track rows exist before viewport attachment")
    for row in fixture.trackRows {
        report.expectEqual(0.0, row.activityLeftHeight, cppID: unattachedID,
                           what: "track \(row.track): unattached left activity height")
        report.expectEqual(0.0, row.activityRightHeight, cppID: unattachedID,
                           what: "track \(row.track): unattached right activity height")
    }
}

@MainActor
private func reorderSlotsResolveInsertionTargetsAndUndoRestores(
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
            report.fail(reorderID, "\(probe.label): cannot create third track")
            continue
        }
        let original = fixture.channelOrder
        report.expectEqual(3, Set(original).count, cppID: reorderID,
                           what: "\(probe.label): channels distinguish all three track identities")
        fixture.session.mutedTracks = [probe.muted]
        fixture.headers.refreshFromDocument()
        let revision = document.revision
        let baseline = document.history.currentIdentity
        let couldUndo = document.history.canUndo
        let couldRedo = document.history.canRedo
        fixture.drag(report, from: probe.from, target: probe.target,
                     fraction: probe.fraction, label: probe.label)
        report.expectEqual(probe.order.map { original[$0] }, fixture.channelOrder,
                           cppID: reorderID, what: "\(probe.label): committed track order")
        report.expectEqual(Set([probe.mutedAfter]), fixture.session.mutedTracks,
                           cppID: reorderID, what: "\(probe.label): mute follows the moved identity")
        report.expectEqual([probe.mutedAfter],
                           fixture.trackRows.filter(\.muteChecked).map(\.track),
                           cppID: reorderID, what: "\(probe.label): visible mute follows the track")
        report.expectEqual(revision + (probe.changes ? 1 : 0), document.revision,
                           cppID: reorderID, what: "\(probe.label): one revision only for a real move")
        if !probe.changes {
            report.expectEqual(baseline, document.history.currentIdentity, cppID: reorderID,
                               what: "\(probe.label): no history entry")
            report.expectEqual(couldUndo, document.history.canUndo, cppID: reorderID,
                               what: "\(probe.label): undo reachability unchanged")
            report.expectEqual(couldRedo, document.history.canRedo, cppID: reorderID,
                               what: "\(probe.label): redo reachability unchanged")
            continue
        }
        let moved = document.history.currentIdentity
        report.expect(moved != baseline, cppID: reorderID,
                      message: "\(probe.label): move enters document history")
        report.expect(document.history.undoDocument(), cppID: reorderID,
                      message: "\(probe.label): undo succeeds")
        report.expectEqual(baseline, document.history.currentIdentity, cppID: reorderID,
                           what: "\(probe.label): one undo returns to duplicated baseline")
        report.expectEqual(original, fixture.channelOrder, cppID: reorderID,
                           what: "\(probe.label): undo restores order")
        report.expectEqual(Set([probe.muted]), fixture.session.mutedTracks, cppID: reorderID,
                           what: "\(probe.label): undo restores mute identity")
        report.expectEqual([probe.muted], fixture.trackRows.filter(\.muteChecked).map(\.track),
                           cppID: reorderID, what: "\(probe.label): undo restores visible mute")
        report.expect(document.history.redoDocument(), cppID: reorderID,
                      message: "\(probe.label): redo succeeds")
        report.expectEqual(moved, document.history.currentIdentity, cppID: reorderID,
                           what: "\(probe.label): redo restores the move history entry")
        report.expectEqual(probe.order.map { original[$0] }, fixture.channelOrder,
                           cppID: reorderID, what: "\(probe.label): redo restores order")
        report.expectEqual(Set([probe.mutedAfter]), fixture.session.mutedTracks,
                           cppID: reorderID, what: "\(probe.label): redo restores mute identity")
        report.expectEqual([probe.mutedAfter],
                           fixture.trackRows.filter(\.muteChecked).map(\.track),
                           cppID: reorderID, what: "\(probe.label): redo restores visible mute")
    }
}

@MainActor
private func headerReconciliationUnchanged(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = TrackHeadersFixture(suite: suite, service: service)
    let resets = fixture.headers.rowRebuildCount
    let original = fixture.channelOrder
    fixture.headers.refreshFromDocument()
    report.expectEqual(resets, fixture.headers.rowRebuildCount, cppID: unchangedID,
                       what: "unchanged document refresh emits zero row-model resets")
    report.expectEqual(original, fixture.channelOrder, cppID: unchangedID,
                       what: "unchanged refresh preserves document track order")
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: unchangedID,
                       phase: "unchanged refresh")
}

@MainActor
private func headerReconciliationStructural(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = TrackHeadersFixture(suite: suite, service: service)
    let document = fixture.document
    let headers = fixture.headers
    let original = fixture.channelOrder
    let baseline = document.history.currentIdentity
    let resets = headers.rowRebuildCount
    document.deleteTrack(1)
    report.expectEqual(resets + 1, headers.rowRebuildCount, cppID: structuralID,
                       what: "delete rebuilds rows exactly once")
    fixture.expectRows(report, names: ["Lead"], cppID: structuralID, phase: "after delete")
    report.expectEqual(Array(original.prefix(1)), fixture.channelOrder, cppID: structuralID,
                       what: "delete removes exactly the last track")
    report.expect(document.history.undoDocument(), cppID: structuralID,
                  message: "undo restores deleted track")
    report.expectEqual(baseline, document.history.currentIdentity, cppID: structuralID,
                       what: "restore returns to original history identity")
    report.expectEqual(resets + 2, headers.rowRebuildCount, cppID: structuralID,
                       what: "restore rebuilds rows exactly once")
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: structuralID, phase: "after restore")
    report.expectEqual(original, fixture.channelOrder, cppID: structuralID,
                       what: "restore recovers original track order")

    headers.beginRename(track: 0)
    report.expectEqual(0, headers.renamingTrack, cppID: structuralID,
                       what: "rename opens on a live row")
    headers.renameDraft = "zzz"
    let revision = document.revision
    document.deleteTrack(1)
    report.expectEqual(resets + 3, headers.rowRebuildCount, cppID: structuralID,
                       what: "structural change during rename rebuilds rows exactly once")
    report.expectEqual(-1, headers.renamingTrack, cppID: structuralID,
                       what: "structural change cancels an open rename")
    report.expectEqual("Lead", document.trackName(0), cppID: structuralID,
                       what: "structural cancellation does not commit the draft")
    report.expectEqual(revision + 1, document.revision, cppID: structuralID,
                       what: "only deletion commits during rename cancellation")
    // A late editor completion must not resurrect the cancelled draft.
    headers.finishRename(commit: true, restoreRollFocus: false)
    report.expectEqual("Lead", document.trackName(0), cppID: structuralID,
                       what: "late rename completion cannot commit cancelled text")
    report.expect(document.history.undoDocument(), cppID: structuralID,
                  message: "single undo after cancellation restores the deleted track")
    report.expectEqual(baseline, document.history.currentIdentity, cppID: structuralID,
                       what: "cancelled rename leaves no extra history entry")
    fixture.expectRows(report, names: ["Lead", "Bass"], cppID: structuralID,
                       phase: "after cancelled rename undo")
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
    report.expectEqual(Set([0]), session.mutedTracks, cppID: mixPublicationID,
                       what: "mute command changes session mix state")
    report.expect(headers.rows[0].muteChecked, cppID: mixPublicationID,
                  message: "mute command updates header in the same publication")
    report.expect(headers.rows[1] === unaffected, cppID: mixPublicationID,
                  message: "mute publication retains the unrelated row")

    grid.performCommand(command: EditCommand.soloTracks.rawValue)
    report.expectEqual(Set([0]), session.soloedTracks, cppID: mixPublicationID,
                       what: "solo command changes session mix state")
    report.expect(headers.rows[0].soloChecked, cppID: mixPublicationID,
                  message: "solo command updates header in the same publication")
    report.expectEqual(2, publications.count, cppID: mixPublicationID,
                       what: "each command publishes once without a playhead poll")
    report.expect(publications.allSatisfy { $0 == [.mixState] }, cppID: mixPublicationID,
                  message: "command publications contain only the mix-state domain")
    report.expectEqual(revision, document.revision, cppID: mixPublicationID,
                       what: "mix commands do not revise the document")
    report.expectEqual(history, document.history.currentIdentity, cppID: mixPublicationID,
                       what: "mix commands create no history")
    report.expectEqual(dirty, document.isDirty, cppID: mixPublicationID,
                       what: "mix commands do not dirty the document")
    report.expectEqual(0, playbackPublications, cppID: mixPublicationID,
                       what: "mix commands do not publish a playback timeline")
}
