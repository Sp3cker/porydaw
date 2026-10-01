import Foundation
@testable import PorydawApp
import PorydawCore

// Direct coverage for the shared playhead. The pure policy layer is checked with
// synthetic timelines and cameras; the presenter is checked against the real
// `DocumentSession`, `PianoGrid` and `EditorDrawerPresenter` owners the suite
// already has open. Translated legacy intent:
//
// - `drawerpresentation/VelocityPageTest::textRetentionAndPlayheadPerformance`:
//   playhead-only updates advance presentation diagnostics and rebuild no
//   content, and the presented tick is the authoritative one;
// - `nativegraphics/RenderingPlayheadTest::quickPolarityAndEdges`: an attached
//   band renders the position, paused included, and an out-of-viewport
//   projection renders nothing;
// - `nativegraphics/RenderingPlayheadTest::positionOnlyDoesNotRebuild`: a
//   position change publishes a position and nothing else;
// - `songview.cpp` `setPlayheadSample`: the 85%/10% follow rule, suspended while
//   a gesture is live.

let sharedPlayheadMappingID = "swiftcore/SharedPlayhead::sampleMappingAcrossTempo"
let loopWrapID = "swiftcore/SharedPlayhead::loopWrapDiscontinuity"
let transportID = "swiftcore/SharedPlayhead::transportFlags"
let visibilityID = "swiftcore/SharedPlayhead::visibilityEdges"
let followID = "swiftcore/SharedPlayhead::followPolicyAndThreshold"
private let aggregateID = "swiftcore/SharedPlayhead::aggregateSuspension"
let sharedPlayheadPublicationID = "swiftcore/SharedPlayhead::publicationAndRepeatedNoOp"
let sharedPlayheadReprojectionID = "swiftcore/SharedPlayhead::cameraReprojection"
private let staticContentID = "swiftcore/SharedPlayhead::staticContentInvariant"
private let lifecycleID = "swiftcore/SharedPlayhead::replacementTokenAndRetirement"
private let pollingID = "swiftcore/SharedPlayhead::pollingLifecycle"
private let compoundCommandID = "swiftcore/SharedPlayhead::compoundCommandPublication"

let mappingTolerance = 1e-6

func near(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

// MARK: - Synthetic tempo fixture

/// 500_000 µs/quarter (1000 samples/tick at 24 ticks per beat and 48 kHz) until
/// tick 48, then 250_000 µs/quarter (500 samples/tick), with a loop bracket.
/// Hand-derived: the mapping under check must resolve both segments.
func sharedPlayheadFixture() -> MidiFile {
    let tempo = { (tick: Tick, microseconds: UInt32) -> MidiEvent in
        .meta(tick: tick, type: 0x51, data: [
            UInt8((microseconds >> 16) & 0xFF),
            UInt8((microseconds >> 8) & 0xFF),
            UInt8(microseconds & 0xFF),
        ])
    }
    let conductor: [MidiEvent] = [
        tempo(0, 500_000),
        tempo(48, 250_000),
        .meta(tick: 48, type: 0x01, data: Array("[".utf8)),
        .meta(tick: 144, type: 0x01, data: Array("]".utf8)),
    ]
    let notes: [MidiEvent] = [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
        .channel(tick: 72, status: 0x90, data0: 67, data1: 100),
        .channel(tick: 96, status: 0x80, data0: 67),
    ]
    return MidiFile(division: 24, chunks: [
        MidiChunk(events: conductor, endTick: 192),
        MidiChunk(events: notes, endTick: 192),
    ])
}

// MARK: - Check-side owners

/// A page that owns interaction state and clears it exactly the way a production
/// page does when the container cancels it.
@MainActor
private final class SharedPlayheadStubPage: EditorDrawerPage {
    let sectionKind: DrawerSectionKind = .velocity
    let contentUrl = "file:///shared-playhead/velocity.qml"
    let bodyPolicy = EditorDrawerBodyPolicy { hostHeight, metrics in
        min(max(hostHeight / 5, metrics.minimumBody),
            metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
    }
    private(set) var interactionActive = false
    private(set) var cancelCount = 0

    func setInteractionActive(_ active: Bool) { interactionActive = active }

    func cancelSectionInteraction() {
        cancelCount += 1
        interactionActive = false
    }
}

/// A second document session over the synthetic tempo fixture. It shares the
/// suite's service and bank lease (and is deliberately never closed, because
/// closing would close the suite's service) and exists to prove that the shared
/// playhead maps through whichever timeline its document owns.
@MainActor
private func sharedPlayheadReplacementSession(_ session: DocumentSession,
                                              service: ProjectService) -> DocumentSession {
    let document = SongDocument(file: sharedPlayheadFixture(),
                                config: session.document.state.config,
                                source: session.document.source,
                                trackBudget: session.document.trackBudget)
    return DocumentSession(document: document, service: service,
                           lease: session.bankLease, slots: session.bankSlots,
                           dirty: false, loadName: session.bankLoadName, sampleRate: 48_000)
}

/// What the grid publishes as content: the content key, display revision and
/// the probe-decoded counts, so a rebuild that changed anything shows here.
private struct GridContentSnapshot: Equatable {
    var renderedNoteCount: Int
    var noteSummary: String
    var appliedRevisionText: String
    var editCursorTick: Int
    var contentKey: RollDrawingContentKey?
    var displayRevision: Int
    var noteCount: Int
    var rowCount: Int
    var keyboardNameCount: Int
}

@MainActor
private func gridContentSnapshot(_ grid: PianoGrid) -> GridContentSnapshot {
    let probe = RollContentProbe(grid)
    return GridContentSnapshot(
        renderedNoteCount: grid.renderedNoteCount,
        noteSummary: grid.fetchNoteSummary(),
        appliedRevisionText: grid.appliedRevisionText,
        editCursorTick: grid.editCursorTick,
        contentKey: probe.contentKey,
        displayRevision: probe.displayRevision,
        noteCount: probe.notes.count,
        rowCount: probe.rows.count,
        keyboardNameCount: probe.keyboardNames.count)
}

/// Pumps the main run loop so a main-actor task can run, exactly as the suite's
/// own bounded waits do.
@MainActor
private func pumpSharedPlayheadRunLoop(_ seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
    }
}

@MainActor
func runSharedPlayheadChecks(_ report: CheckReport, session: DocumentSession,
                             service: ProjectService) {
    checkPureMapping(report)
    checkPureVisibilityFollowAndWrap(report)
    checkPresenterAgainstSession(report, session: session, service: service)
    checkCompoundCommandPublication(report, session: session, service: service)
}

@MainActor
private func checkCompoundCommandPublication(
    _ report: CheckReport, session suite: DocumentSession, service: ProjectService
) {
    let session = sharedPlayheadReplacementSession(suite, service: service)
    let grid = PianoGrid(session: session)
    let automation = AutomationPage()
    automation.attach(session: session, palette: GridPalette())
    defer { automation.detach() }
    let ruler = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let commands = EditorCommandRouter(session: session, grid: grid, automation: automation,
                                       rulerMenu: ruler)
    guard let source = session.document.notes(in: 0).first else {
        report.fail(compoundCommandID, "compound command fixture has no source note")
        return
    }
    session.setSelectedNotes([source.id])
    commands.perform(.copy)
    grid.setEditCursorTick(tick: 120)

    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    var playbackCount = 0
    var publications: [SessionChange] = []
    var observedCursors: [Tick] = []
    var observedSelections: [[NoteID]] = []
    var observedPlaybackCounts: [Int] = []
    session.onPlayback = { _ in playbackCount += 1 }
    session.onChange = { [weak grid] change in
        if change.domains.contains(.cursor) {
            grid?.refreshCursorPresentation()
        }
        publications.append(change)
        observedCursors.append(session.editCursor)
        observedSelections.append(session.selectedNoteOrder)
        observedPlaybackCounts.append(playbackCount)
    }

    commands.perform(.paste)

    let expectedCursor = Tick(120) + max(1, source.duration)
    let inserted = session.selectedNoteOrder.compactMap(session.document.note)
    report.expectEqual(expected: 1, actual: publications.count, cppID: compoundCommandID,
                       what: "paste publishes one completed session change")
    report.expectEqual(expected:
        [.document, .selection, .dirty, .history, .cursor],
        actual: publications.first?.domains ?? [],
        cppID: compoundCommandID,
        what: "paste publication aggregates document, selection, and cursor domains")
    report.expectEqual(expected: [expectedCursor], actual: observedCursors, cppID: compoundCommandID,
                       what: "the only observer sees the completed paste cursor")
    report.expectEqual(expected: [session.selectedNoteOrder], actual: observedSelections, cppID: compoundCommandID,
                       what: "the only observer sees the completed pasted selection")
    report.expectEqual(expected: [1], actual: observedPlaybackCounts, cppID: compoundCommandID,
                       what: "playback is published before the completed session state")
    report.expectEqual(expected: Int(expectedCursor), actual: grid.editCursorTick, cppID: compoundCommandID,
                       what: "cursor-domain routing updates the lightweight grid presentation")
    report.expectEqual(expected: 1, actual: inserted.count, cppID: compoundCommandID,
                       what: "paste selects one inserted note")
    report.expect(inserted.first?.tick == 120 && inserted.first?.id != source.id,
                  cppID: compoundCommandID,
                  message: "the completed selection names the inserted destination note")
    report.expectEqual(expected: revision + 1, actual: session.document.revision, cppID: compoundCommandID,
                       what: "paste commits one document revision")
    report.expect(session.document.history.currentIdentity != history, cppID: compoundCommandID,
                  message: "paste commits one history state")
    report.expectEqual(expected: 1, actual: playbackCount, cppID: compoundCommandID,
                       what: "paste rebuilds and publishes playback exactly once")

    publications.removeAll()
    observedCursors.removeAll()
    observedSelections.removeAll()
    observedPlaybackCounts.removeAll()
    playbackCount = 0
    let cursorRevision = session.document.revision
    let cursorDirty = session.document.isDirty
    let cursorHistory = session.document.history.currentIdentity
    let movedCursor = expectedCursor + 12

    session.editCursor = movedCursor

    report.expectEqual(expected: [.cursor], actual: publications.map(\.domains), cppID: compoundCommandID,
                       what: "a cursor-only move publishes only the cursor domain")
    report.expectEqual(expected: Int(movedCursor), actual: grid.editCursorTick, cppID: compoundCommandID,
                       what: "cursor publication updates the grid without a content refresh")
    report.expect(session.document.revision == cursorRevision
                      && session.document.isDirty == cursorDirty,
                  cppID: compoundCommandID,
                  message: "cursor-only publication preserves revision and dirty state")
    report.expectEqual(expected: cursorHistory, actual: session.document.history.currentIdentity,
                       cppID: compoundCommandID,
                       what: "cursor-only publication creates no history entry")
    report.expectEqual(expected: 0, actual: playbackCount, cppID: compoundCommandID,
                       what: "cursor-only publication rebuilds no playback timeline")
}

// MARK: - Presenter against the real owners

@MainActor
private func checkPresenterAgainstSession(_ report: CheckReport, session: DocumentSession,
                                         service: ProjectService) {
    let grid = PianoGrid(session: session)
    let drawer = EditorDrawerPresenter()
    let page = SharedPlayheadStubPage()
    let presenter = SharedPlayheadPresenter()

    let priorCamera = session.onCameraChangeDetailed
    let priorPlayback = session.onPlayback
    let priorChange = session.onChange
    defer {
        session.onCameraChangeDetailed = priorCamera
        session.onPlayback = priorPlayback
        session.onChange = priorChange
        presenter.detach()
    }
    // The production wiring reduced to its playback owner: a camera publication
    // refreshes the grid and reprojects the retained authoritative tick.
    session.onCameraChangeDetailed = { [weak grid, weak presenter] _, change in
        grid?.refreshCameraPresentation(change)
        presenter?.refreshProjection()
    }

    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    presenter.attach(session: session, audio: nil, grid: grid, drawer: drawer)
    presenter.setFollowEnabled(false)

    checkPublicationAndReprojection(report, session: session, presenter: presenter)
    checkAggregateSuspension(report, session: session, grid: grid, drawer: drawer,
                             page: page, presenter: presenter)
    checkStaticContentInvariant(report, session: session, grid: grid, presenter: presenter)
    checkReplacementAndPolling(report, session: session, service: service, grid: grid,
                               drawer: drawer, presenter: presenter)
}



@MainActor
private func checkAggregateSuspension(_ report: CheckReport, session: DocumentSession,
                                      grid: PianoGrid, drawer: EditorDrawerPresenter,
                                      page: SharedPlayheadStubPage,
                                      presenter: SharedPlayheadPresenter) {
    presenter.setFollowEnabled(true)
    let playing = SharedPlayheadPolicy.playingTransport
    let farSample = session.timeline.sample(for: 2_000)
    report.expect(grid.interactionActive == false && drawer.interactionActive == false,
                  cppID: aggregateID, message: "idle owners report no interaction")

    _ = session.mutateCamera { _ = $0.setHScroll(0) }
    let parked = session.camera.snapshot
    _ = presenter.observe(sample: farSample, transport: playing)
    let following = session.camera.snapshot
    report.expect(following.scrollX != parked.scrollX, cppID: aggregateID,
                  message: "an idle aggregate lets follow scroll the camera")

    _ = session.mutateCamera { _ = $0.setHScroll(parked.scrollX) }
    grid.beginPointer(x: 200, y: 40, modifiers: 0)
    report.expect(grid.interactionActive, cppID: aggregateID,
                  message: "a live roll gesture reports interaction")
    _ = presenter.observe(sample: farSample, transport: playing)
    report.expect(session.camera.snapshot == parked, cppID: aggregateID,
                  message: "a live roll gesture suspends follow")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expect(grid.interactionActive == false, cppID: aggregateID,
                  message: "cancelling the gesture clears the grid's interaction")
    _ = presenter.observe(sample: farSample, transport: playing)
    report.expect(session.camera.snapshot == following, cppID: aggregateID,
                  message: "ending the gesture lets the next observation follow")

    drawer.attachSection(page)
    drawer.setSectionVisible(kind: DrawerSectionKind.velocity.rawValue, visible: true,
                             drawerOwnsFocus: false)
    drawer.beginResize(kind: DrawerSectionKind.velocity.rawValue)
    report.expect(drawer.interactionActive, cppID: aggregateID,
                  message: "a live drawer resize reports interaction")
    _ = session.mutateCamera { _ = $0.setHScroll(parked.scrollX) }
    _ = presenter.observe(sample: farSample, transport: playing)
    report.expect(session.camera.snapshot == parked, cppID: aggregateID,
                  message: "a drawer resize suspends follow")
    drawer.endResize(kind: DrawerSectionKind.velocity.rawValue)
    report.expect(drawer.interactionActive == false, cppID: aggregateID,
                  message: "ending the resize clears the aggregate")

    page.setInteractionActive(true)
    report.expect(drawer.interactionActive, cppID: aggregateID,
                  message: "an attached page's interaction joins the aggregate")
    _ = session.mutateCamera { _ = $0.setHScroll(parked.scrollX) }
    _ = presenter.observe(sample: farSample, transport: playing)
    report.expect(session.camera.snapshot == parked, cppID: aggregateID,
                  message: "a page interaction suspends follow")

    presenter.setExplicitSuspension(true)
    page.setInteractionActive(false)
    _ = presenter.observe(sample: farSample, transport: playing)
    report.expect(session.camera.snapshot == parked, cppID: aggregateID,
                  message: "an explicit suspension suspends follow with no owner gesture")

    presenter.setExplicitSuspension(false)
    drawer.detachSection(page)
    report.expect(page.cancelCount == 1 && page.interactionActive == false, cppID: aggregateID,
                  message: "detach cancels the page's interaction synchronously")
    _ = presenter.observe(sample: farSample, transport: playing)
    report.expect(session.camera.snapshot == following, cppID: aggregateID,
                  message: "clearing every suspension restores the same follow target")
}

/// 128 distinct authoritative positions publish 128 presentations and leave the
/// grid, the document, the history, the camera and the edit cursor untouched.
@MainActor
private func checkStaticContentInvariant(_ report: CheckReport, session: DocumentSession,
                                        grid: PianoGrid, presenter: SharedPlayheadPresenter) {
    presenter.setFollowEnabled(false)
    _ = session.mutateCamera { _ = $0.setHScroll(0) }
    let camera = session.camera.snapshot
    let content = gridContentSnapshot(grid)
    let revision = session.document.revision
    let dirty = session.document.isDirty
    let canUndo = session.document.history.canUndo
    let canRedo = session.document.history.canRedo
    let editCursor = session.editCursor
    let count = presenter.presentationCount

    for step in 0..<128 {
        _ = presenter.observe(sample: session.timeline.sample(for: Tick(step)), transport: 0)
    }
    report.expect(presenter.presentationCount == count + 128, cppID: staticContentID,
                  message: "128 distinct authoritative samples present 128 positions")
    report.expect(near(presenter.tick, 127, tolerance: 0.5), cppID: staticContentID,
                  message: "the last presented position is the last authoritative sample")
    report.expect(gridContentSnapshot(grid) == content, cppID: staticContentID,
                  message: "playhead-only updates rebuild no grid scene content")
    report.expect(session.camera.snapshot == camera, cppID: staticContentID,
                  message: "playhead-only updates move no camera")
    report.expect(session.document.revision == revision && session.document.isDirty == dirty,
                  cppID: staticContentID,
                  message: "playhead-only updates leave the document revision and dirty state")
    report.expect(session.document.history.canUndo == canUndo
                      && session.document.history.canRedo == canRedo,
                  cppID: staticContentID,
                  message: "playhead-only updates consume no history")
    report.expect(session.editCursor == editCursor, cppID: staticContentID,
                  message: "the edit cursor stays a separate document-session value")
}

/// A replacement document maps the same samples through its own timeline, and a
/// cancelled generation can never publish into it. Polling is one task per
/// attached document, cancelled with the attached presentation.
@MainActor
private func checkReplacementAndPolling(_ report: CheckReport, session: DocumentSession,
                                        service: ProjectService, grid: PianoGrid,
                                        drawer: EditorDrawerPresenter,
                                        presenter: SharedPlayheadPresenter) {
    // The sample is built through the replacement document's own timeline: its
    // tempo map resolves 60 (48 ticks at 1000 samples/tick up to the boundary at
    // tick 48, then 12 at 500) to 54000 samples. The retired document maps that
    // same sample elsewhere, so the published tick can only match one of them.
    let replacement = sharedPlayheadReplacementSession(session, service: service)
    let sample = replacement.timeline.sample(for: 60)
    let retiredTick = session.timeline.tick(for: sample)
    let beforeToken = presenter.lifecycleToken

    presenter.attach(session: replacement, audio: nil, grid: grid, drawer: drawer)
    presenter.setFollowEnabled(false)
    let replacementToken = presenter.lifecycleToken
    report.expect(replacementToken != beforeToken, cppID: lifecycleID,
                  message: "installing a replacement document starts a new generation")
    report.expect(presenter.observe(SharedPlayheadObservation(sample: sample, transport: 0),
                                    token: beforeToken) == false,
                  cppID: lifecycleID,
                  message: "an observation from the retired generation publishes nothing")
    _ = presenter.observe(sample: sample, transport: 0)
    report.expect(!near(presenter.tick, retiredTick, tolerance: mappingTolerance)
                      && near(presenter.tick, 60, tolerance: mappingTolerance),
                  cppID: lifecycleID,
                  message: "the same sample maps through the replacement document's timeline"
                      + " (sample \(sample), retired tick \(retiredTick),"
                      + " replacement tick \(presenter.tick))")

    presenter.detach()
    report.expect(!presenter.timelineAttached && !presenter.visible && presenter.tick == 0
                      && presenter.playing == false,
                  cppID: lifecycleID,
                  message: "retirement clears the attached presentation synchronously")
    report.expect(presenter.lifecycleToken != replacementToken, cppID: lifecycleID,
                  message: "retirement advances the generation")
    report.expect(presenter.observe(sample: sample, transport: 0) == false, cppID: lifecycleID,
                  message: "with no document attached nothing publishes")

    presenter.attach(session: session, audio: nil, grid: grid, drawer: drawer)
    presenter.startPolling()
    report.expect(presenter.isPolling, cppID: pollingID,
        message: "an attached document starts polling")
    presenter.startPolling()
    report.expect(presenter.isPolling, cppID: pollingID,
        message: "repeated start keeps polling active")
    presenter.stopPolling()
    report.expect(!presenter.isPolling && presenter.timelineAttached, cppID: pollingID,
                  message: "stopping polling keeps the attached presentation")
    presenter.startPolling()
    presenter.detach()
    let settled = presenter.presentationCount
    pumpSharedPlayheadRunLoop(0.05)
    report.expect(!presenter.isPolling && !presenter.timelineAttached, cppID: pollingID,
                  message: "cancellation stops polling and clears the attachment before release")
    report.expect(presenter.presentationCount == settled, cppID: pollingID,
                  message: "a cancelled task publishes no late presentation")
}
