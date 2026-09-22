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

private let mappingID = "swiftcore/SharedPlayhead::sampleMappingAcrossTempo"
private let loopWrapID = "swiftcore/SharedPlayhead::loopWrapDiscontinuity"
private let transportID = "swiftcore/SharedPlayhead::transportFlags"
private let visibilityID = "swiftcore/SharedPlayhead::visibilityEdges"
private let followID = "swiftcore/SharedPlayhead::followPolicyAndThreshold"
private let aggregateID = "swiftcore/SharedPlayhead::aggregateSuspension"
let sharedPlayheadPublicationID = "swiftcore/SharedPlayhead::publicationAndRepeatedNoOp"
let sharedPlayheadReprojectionID = "swiftcore/SharedPlayhead::cameraReprojection"
private let staticContentID = "swiftcore/SharedPlayhead::staticContentInvariant"
private let lifecycleID = "swiftcore/SharedPlayhead::replacementTokenAndRetirement"
private let pollingID = "swiftcore/SharedPlayhead::pollingLifecycle"
private let compoundCommandID = "swiftcore/SharedPlayhead::compoundCommandPublication"

private let mappingTolerance = 1e-6

private func near(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

// MARK: - Synthetic tempo fixture

/// 500_000 µs/quarter (1000 samples/tick at 24 ticks per beat and 48 kHz) until
/// tick 48, then 250_000 µs/quarter (500 samples/tick), with a loop bracket.
/// Hand-derived: the mapping under check must resolve both segments.
private func sharedPlayheadFixture() -> MidiFile {
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

/// What the grid publishes as content. The Swift grid exposes scene models rather
/// than a content-build counter, so the playhead-only invariant is asserted over
/// the published content itself: a rebuild that changed anything would show here.
private struct GridContentSnapshot: Equatable {
    var renderedNoteCount: Int
    var noteSummary: String
    var appliedRevisionText: String
    var editCursorTick: Int
    var rulerChromeCount: Int
    var gridTimeCount: Int
    var noteFillCount: Int
    var noteBorderCount: Int
    var keyboardKeyCount: Int
    var keyboardTextCount: Int
    var gridTimeSignature: String
    var noteFillSignature: String
}

@MainActor
private func gridContentSnapshot(_ grid: PianoGrid) -> GridContentSnapshot {
    let scene = grid.scene
    var gridTime: [String] = []
    gridTime.reserveCapacity(min(64, scene.pianoGridTime.count))
    for index in 0..<min(64, scene.pianoGridTime.count) {
        let rect = scene.pianoGridTime[index]
        gridTime.append("\(rect.x),\(rect.width),\(rect.fillColor)")
    }
    var fills: [String] = []
    fills.reserveCapacity(min(64, scene.pianoNoteFills.count))
    for index in 0..<min(64, scene.pianoNoteFills.count) {
        let rect = scene.pianoNoteFills[index]
        fills.append("\(rect.x),\(rect.y),\(rect.width),\(rect.height),\(rect.fillColor)")
    }
    return GridContentSnapshot(
        renderedNoteCount: grid.renderedNoteCount,
        noteSummary: grid.noteSummary,
        appliedRevisionText: grid.appliedRevisionText,
        editCursorTick: grid.editCursorTick,
        rulerChromeCount: scene.rulerChrome.count,
        gridTimeCount: scene.pianoGridTime.count,
        noteFillCount: scene.pianoNoteFills.count,
        noteBorderCount: scene.pianoNoteBordersAndSelection.count,
        keyboardKeyCount: scene.pianoKeyboardKeys.count,
        keyboardTextCount: scene.pianoKeyboardTextModel.count,
        gridTimeSignature: gridTime.joined(separator: "|"),
        noteFillSignature: fills.joined(separator: "|"))
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
    let commands = EditorCommandRouter(session: session, grid: grid, automation: automation)
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
    report.expectEqual(1, publications.count, cppID: compoundCommandID,
                       what: "paste publishes one completed session change")
    report.expectEqual(
        [.document, .selection, .dirty, .history, .cursor],
        publications.first?.domains ?? [],
        cppID: compoundCommandID,
        what: "paste publication aggregates document, selection, and cursor domains")
    report.expectEqual([expectedCursor], observedCursors, cppID: compoundCommandID,
                       what: "the only observer sees the completed paste cursor")
    report.expectEqual([session.selectedNoteOrder], observedSelections, cppID: compoundCommandID,
                       what: "the only observer sees the completed pasted selection")
    report.expectEqual([1], observedPlaybackCounts, cppID: compoundCommandID,
                       what: "playback is published before the completed session state")
    report.expectEqual(Int(expectedCursor), grid.editCursorTick, cppID: compoundCommandID,
                       what: "cursor-domain routing updates the lightweight grid presentation")
    report.expectEqual(1, inserted.count, cppID: compoundCommandID,
                       what: "paste selects one inserted note")
    report.expect(inserted.first?.tick == 120 && inserted.first?.id != source.id,
                  cppID: compoundCommandID,
                  message: "the completed selection names the inserted destination note")
    report.expectEqual(revision + 1, session.document.revision, cppID: compoundCommandID,
                       what: "paste commits one document revision")
    report.expect(session.document.history.currentIdentity != history, cppID: compoundCommandID,
                  message: "paste commits one history state")
    report.expectEqual(1, playbackCount, cppID: compoundCommandID,
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

    report.expectEqual([.cursor], publications.map(\.domains), cppID: compoundCommandID,
                       what: "a cursor-only move publishes only the cursor domain")
    report.expectEqual(Int(movedCursor), grid.editCursorTick, cppID: compoundCommandID,
                       what: "cursor publication updates the grid without a content refresh")
    report.expect(session.document.revision == cursorRevision
                      && session.document.isDirty == cursorDirty,
                  cppID: compoundCommandID,
                  message: "cursor-only publication preserves revision and dirty state")
    report.expectEqual(cursorHistory, session.document.history.currentIdentity,
                       cppID: compoundCommandID,
                       what: "cursor-only publication creates no history entry")
    report.expectEqual(0, playbackCount, cppID: compoundCommandID,
                       what: "cursor-only publication rebuilds no playback timeline")
}

// MARK: - Pure policy

/// The authoritative tempo-map arithmetic the presenter's mapping must resolve.
@MainActor
private func checkPureMapping(_ report: CheckReport) {
    let timeline = PlaybackTimeline.build(file: sharedPlayheadFixture(), sampleRate: 48_000)
    report.expect(near(timeline.tick(for: 0), 0, tolerance: mappingTolerance),
                  cppID: mappingID, message: "sample zero maps to tick zero")
    report.expect(near(timeline.tick(for: 24_000), 24, tolerance: mappingTolerance),
                  cppID: mappingID, message: "pre-boundary samples map at the first tempo")
    report.expect(near(timeline.tick(for: 48_000), 48, tolerance: mappingTolerance),
                  cppID: mappingID,
                  message: "the tempo boundary begins at the sample its first segment reaches")
    report.expect(near(timeline.tick(for: 54_000), 60, tolerance: mappingTolerance),
                  cppID: mappingID, message: "post-boundary samples map at the second tempo")
    report.expect(near(Double(timeline.sample(for: 48)), 48_000, tolerance: mappingTolerance)
                      && near(Double(timeline.sample(for: 60)), 54_000, tolerance: mappingTolerance),
                  cppID: mappingID,
                  message: "the mapping round-trips across the boundary in both directions")
}

/// Visibility, transport flags, the follow rule, and loop wrap as an ordinary
/// backward observation. Synthetic camera: 24 ticks/beat, 32 px/beat, 320 px
/// viewport, scrolled to the plot origin.
@MainActor
private func checkPureVisibilityFollowAndWrap(_ report: CheckReport) {
    var camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 480, viewportWidth: 320,
                              rollHeight: 240, limits: EditorCamera.Limits(
                                  defaultPixelsPerBeat: 32, minPixelsPerBeat: 4,
                                  maxPixelsPerBeat: 640, defaultKeyHeight: 12,
                                  minKeyHeight: 4, maxKeyHeight: 32,
                                  revealViewportFraction: 1.0 / 3.0, minimumPlotWidth: 50))
    _ = camera.setHScroll(0)
    let width = camera.snapshot.viewportWidth

    let atZero = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(0), transport: 0, timelineAttached: true, camera: camera)
    let beforeZero = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(-5), transport: 0, timelineAttached: true, camera: camera)
    let insideRight = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(width - 1), transport: 0, timelineAttached: true, camera: camera)
    let pastRight = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(width + 1), transport: 0, timelineAttached: true, camera: camera)
    let detached = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(4), transport: 0, timelineAttached: false, camera: camera)

    report.expect(atZero.visible && near(atZero.contentX, 0), cppID: visibilityID,
                  message: "a projection at the plot origin renders")
    report.expect(!beforeZero.visible && beforeZero.contentX < 0, cppID: visibilityID,
                  message: "a negative projection is hidden, never moved")
    report.expect(insideRight.visible, cppID: visibilityID,
                  message: "a projection inside the viewport renders")
    report.expect(!pastRight.visible && pastRight.contentX > width, cppID: visibilityID,
                  message: "a projection past the viewport width is hidden")
    report.expect(!detached.visible && !detached.timelineAttached, cppID: visibilityID,
                  message: "no attached timeline renders nothing")

    let playing = SharedPlayheadPolicy.presentation(
        tick: 0, transport: SharedPlayheadPolicy.playingTransport,
        timelineAttached: true, camera: camera)
    let paused = SharedPlayheadPolicy.presentation(
        tick: 0, transport: 1, timelineAttached: true, camera: camera)
    let stopped = SharedPlayheadPolicy.presentation(
        tick: 0, transport: 0, timelineAttached: true, camera: camera)
    report.expect(playing.playing && !paused.playing && !stopped.playing, cppID: transportID,
                  message: "only transport 2 reports playing")
    report.expect(paused.timelineAttached && paused.visible && stopped.visible,
                  cppID: transportID,
                  message: "a paused or stopped position stays attached and visible in viewport")

    let open = SharedPlayheadInteractions()
    let followTick = camera.tickAtContentX(width + 4)
    let expectedTarget = followTick * camera.snapshot.pixelsPerTick - width / 10
    let target = SharedPlayheadPolicy.followTarget(
        tick: followTick, camera: camera, playing: true, followEnabled: true,
        interactions: open)
    report.expect(target.map { near($0, expectedTarget) } ?? false, cppID: followID,
                  message: "follow scrolls to tick * pixelsPerTick - viewportWidth / 10")
    report.expect(SharedPlayheadPolicy.followTarget(
        tick: camera.tickAtContentX(width * 0.85 - 1), camera: camera, playing: true,
        followEnabled: true, interactions: open) == nil, cppID: followID,
        message: "follow stays put below 85% of the viewport width")
    report.expect(SharedPlayheadPolicy.followTarget(
        tick: camera.tickAtContentX(width * 0.85 + 1), camera: camera, playing: true,
        followEnabled: true, interactions: open) != nil, cppID: followID,
        message: "follow re-enters past 85% of the viewport width")
    report.expect(SharedPlayheadPolicy.followTarget(
        tick: camera.tickAtContentX(-5), camera: camera, playing: true, followEnabled: true,
        interactions: open) != nil, cppID: followID,
        message: "a projection left of the plot re-enters follow")
    report.expect(SharedPlayheadPolicy.followTarget(
        tick: 0, camera: camera, playing: true, followEnabled: true, interactions: open) == nil,
        cppID: followID, message: "an in-viewport projection never moves the camera")

    let gated: [(String, Double?)] = [
        ("paused transport", SharedPlayheadPolicy.followTarget(
            tick: followTick, camera: camera, playing: false, followEnabled: true,
            interactions: open)),
        ("follow disabled", SharedPlayheadPolicy.followTarget(
            tick: followTick, camera: camera, playing: true, followEnabled: false,
            interactions: open)),
        ("grid gesture", SharedPlayheadPolicy.followTarget(
            tick: followTick, camera: camera, playing: true, followEnabled: true,
            interactions: SharedPlayheadInteractions(gridActive: true))),
        ("drawer resize", SharedPlayheadPolicy.followTarget(
            tick: followTick, camera: camera, playing: true, followEnabled: true,
            interactions: SharedPlayheadInteractions(drawerActive: true))),
        ("explicit suspension", SharedPlayheadPolicy.followTarget(
            tick: followTick, camera: camera, playing: true, followEnabled: true,
            interactions: SharedPlayheadInteractions(explicitSuspension: true))),
    ]
    for (name, gatedTarget) in gated {
        report.expect(gatedTarget == nil, cppID: followID, message: "\(name) suspends follow")
    }

    let late = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(width + 4), transport: SharedPlayheadPolicy.playingTransport,
        timelineAttached: true, camera: camera)
    let wrapped = SharedPlayheadPolicy.presentation(
        tick: camera.tickAtContentX(4), transport: SharedPlayheadPolicy.playingTransport,
        timelineAttached: true, camera: camera)
    report.expect(late.tick > wrapped.tick && late.contentX > wrapped.contentX, cppID: loopWrapID,
                  message: "a wrapped sample presents a backward tick and projection")
    report.expect(wrapped.timelineAttached && wrapped.playing && wrapped.visible,
                  cppID: loopWrapID,
                  message: "a wrapped sample keeps the same attached playing presentation")
}

// MARK: - Presenter against the real owners

@MainActor
private func checkPresenterAgainstSession(_ report: CheckReport, session: DocumentSession,
                                         service: ProjectService) {
    let grid = PianoGrid(session: session)
    let drawer = EditorDrawerPresenter()
    let page = SharedPlayheadStubPage()
    let presenter = SharedPlayheadPresenter()

    let priorCamera = session.onCameraChange
    let priorPlayback = session.onPlayback
    let priorChange = session.onChange
    defer {
        session.onCameraChange = priorCamera
        session.onPlayback = priorPlayback
        session.onChange = priorChange
        presenter.detach()
    }
    // The production wiring reduced to its playback owner: a camera publication
    // refreshes the grid and reprojects the retained authoritative tick.
    session.onCameraChange = { [weak grid, weak presenter] _ in
        grid?.refreshCamera()
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
                  message: "an attached document starts one polling task")
    presenter.startPolling()
    report.expect(presenter.isPolling, cppID: pollingID,
                  message: "a second start runs no second task")
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
