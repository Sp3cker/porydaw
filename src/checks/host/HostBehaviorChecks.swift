import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawPlayback

@MainActor
internal func runHostBehaviorChecks(_ report: CheckReport, session: DocumentSession,
                                    service: ProjectService, fixtureRoot: String) {
    let route = hostNoteDiscovery(report, fixtureRoot: fixtureRoot, suite: session, service: service)
    hostVelocityMarker(report, route: route)
    hostVelocityGestureContracts(report, session: session, service: service)
    hostLifecycleTermination(report, session: session, service: service)
    hostPlayheadFollowing(report, session: session, service: service)
    hostBandGeometry(report, session: session, service: service)
    hostCameraEndpoints(report, session: session, service: service)
    hostCosmeticOnly(report, session: session, service: service)
    hostAutomationTempo(report, session: session, service: service)
}

@MainActor
private func hostTwoNoteSession(suite: DocumentSession, service: ProjectService) -> DocumentSession {
    let events: [MidiEvent] = [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
        .channel(tick: 24, status: 0x90, data0: 67, data1: 64),
        .channel(tick: 48, status: 0x80, data0: 67),
    ]
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 48),
        MidiChunk(events: events, endTick: 48),
    ])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source,
                                trackBudget: suite.document.trackBudget)
    return DocumentSession(document: document, service: service, lease: suite.bankLease,
                           slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName,
                           sampleRate: 48_000)
}

@MainActor
private func hostNoteDiscovery(_ report: CheckReport, fixtureRoot: String,
                               suite: DocumentSession, service: ProjectService) -> DocumentSession? {
    let id = "swiftcore/HostBehaviorChecks::noteDiscovery"
    let twoNotes = hostTwoNoteSession(suite: suite, service: service)
    report.expect(twoNotes.document.notes(in: 0).count == 2
                  && twoNotes.timeline.events.filter { $0.type == 0x9 }.count == 2,
                  cppID: id, message: "track zero projects two seeded notes")
    let routeService = ProjectService()
    do {
        try runBlocking { try await routeService.open(root: fixtureRoot) }
        let session = try runBlocking {
            try await DocumentSession.open(service: routeService, label: "mus_route101",
                                           sampleRate: 48_000)
        }
        let note = (0..<session.document.engineTracks.usedTrackCount)
            .lazy.flatMap { session.document.notes(in: $0) }.first
        report.expect(note != nil && session.timeline.events.contains {
            $0.type == 0x9 && $0.noteID == note?.id
        }, cppID: id,
        message: "route101 fixture notes resolve from the loaded document with timeline note-on events")
        guard session.document.source.label == "mus_route101" else {
            report.fail(id, "opened fixture did not retain its route101 label")
            return nil
        }
        return session
    } catch {
        report.fail(id, "route101 fixture could not open: \(error)")
        return nil
    }
}

@MainActor
private func hostVelocityMarker(_ report: CheckReport, route: DocumentSession?) {
    let id = "swiftcore/HostBehaviorChecks::velocityMarker"
    guard let route, let track = (0..<route.document.engineTracks.usedTrackCount).first(where: {
        !route.document.notes(in: $0).isEmpty
    }), let note = route.document.notes(in: track).first else {
        report.fail(id, "route101 fixture did not expose an editable note")
        return
    }
    route.selectedTrack = track
    route.setSelectedNotes([note.id])
    let page = VelocityPage(baseFontPx: GridCameraPolicy.seedBaseFontPx)
    page.attach(session: route, palette: GridPalette())
    let font = GridCameraPolicy.seedBaseFontPx
    page.configureBody(width: fontPx(font, 30), height: fontPx(font, 9),
                       rulerWidth: fontPx(font, 4), devicePixelRatio: 1,
                       baseFontPx: font, dragDistance: page.dragDistance)
    guard route.selectedTrack == track && route.selectedNotes == [note.id] else {
        report.fail(id, "fixture note selection could not attach to the primary track")
        return
    }
    let markers = page.axisModel.markers
    report.expect(markers.count == 1, cppID: id,
                  message: "the selected note publishes one axis marker")
    report.expect(markers.first?.velocity == Int(note.velocity), cppID: id,
                  message: "the marker value equals the fixture velocity")
}

@MainActor
private func hostVelocityGestureContracts(_ report: CheckReport, session: DocumentSession,
                                          service: ProjectService) {
    let id = "swiftcore/HostBehaviorChecks::velocityGestureContracts"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard let note = fixture.notes.first, let handle = fixture.handle(note) else {
        report.fail(id, "fixture note has no velocity node")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([note.id])
    page.refreshFromDocument()
    let before = DocumentSnapshot(document)
    let depth = document.history.undoCount
    let originalBytes = try? document.state.file.encoded()
    let pressed = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1,
                                    modifiers: 0)
    _ = page.pointerMove(x: handle.x, y: handle.y - page.dragDistance * 2, buttons: 1)
    report.expect(pressed && !page.frozenPreview.isEmpty && DocumentSnapshot(document) == before
                  && document.history.undoCount == depth && (try? document.state.file.encoded()) == originalBytes,
                  cppID: id, message: "a drag move stages a preview without advancing revision or history")
    _ = page.pointerRelease(x: handle.x, y: handle.y - page.dragDistance * 2, button: 1)
    report.expect(document.revision == before.revision + 1
                  && document.history.undoCount == depth + 1
                  && document.note(note.id)?.velocity != note.velocity
                  && page.frozenPreview.isEmpty && fixture.handle(note)?.y != handle.y,
                  cppID: id, message: "committing advances revision once and invalidates")
    let after = DocumentSnapshot(document)
    let afterBytes = try? document.state.file.encoded()
    guard let moved = fixture.handle(note) else { return }
    _ = page.pointerPress(x: moved.x, y: moved.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerRelease(x: moved.x, y: moved.y, button: 1)
    report.expect(fixture.session.selectedNotes == [note.id] && DocumentSnapshot(document) == after
                  && document.history.undoCount == depth + 1
                  && (try? document.state.file.encoded()) == afterBytes,
                  cppID: id, message: "a click press selects one note without touching song bytes")
}

@MainActor
private func hostLifecycleTermination(_ report: CheckReport, session: DocumentSession,
                                      service: ProjectService) {
    let id = "swiftcore/HostBehaviorChecks::lifecycleTermination"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard let note = fixture.notes.first, let handle = fixture.handle(note) else {
        report.fail(id, "fixture note has no velocity node")
        return
    }
    fixture.session.setSelectedNotes([note.id])
    fixture.page.refreshFromDocument()
    let before = DocumentSnapshot(fixture.document)
    let bytes = try? fixture.document.state.file.encoded()
    _ = fixture.page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
    _ = fixture.page.pointerMove(x: handle.x, y: handle.y - fixture.page.dragDistance * 2, buttons: 1)
    fixture.session.selectedTrack = 1
    fixture.page.refreshFromDocument()
    report.expect(!fixture.page.hasGesture && fixture.page.frozenPreview.isEmpty
                  && fixture.session.selectedNotes.isEmpty && DocumentSnapshot(fixture.document) == before
                  && (try? fixture.document.state.file.encoded()) == bytes,
                  cppID: id, message: "track-replace teardown clears the selection")
    for replacing in [false, true] {
        let outgoing = drawerVelocityVelocityFixture(session: session, service: service)
        guard let note = outgoing.notes.first, let handle = outgoing.handle(note) else {
            report.fail(id, "outgoing document lacks a velocity node")
            continue
        }
        outgoing.session.setSelectedNotes([note.id])
        outgoing.page.refreshFromDocument()
        let snapshot = DocumentSnapshot(outgoing.document)
        let depth = outgoing.document.history.undoCount
        let originalBytes = try? outgoing.document.state.file.encoded()
        _ = outgoing.page.pointerPress(x: handle.x, y: handle.y, surface: 1,
                                       button: 1, modifiers: 0)
        _ = outgoing.page.pointerMove(x: handle.x,
                                      y: handle.y - outgoing.page.dragDistance * 2, buttons: 1)
        let held = outgoing.page.hasGesture && !outgoing.page.frozenPreview.isEmpty
        outgoing.page.detach()
        if replacing {
            outgoing.page.attach(session: hostTwoNoteSession(suite: session, service: service),
                                 palette: GridPalette())
        }
        let released = outgoing.page.pointerRelease(x: handle.x,
                                                    y: handle.y - outgoing.page.dragDistance * 2,
                                                    button: 1)
        let preserved = held && !released && !outgoing.page.hasGesture
            && outgoing.page.frozenPreview.isEmpty
            && DocumentSnapshot(outgoing.document) == snapshot
            && outgoing.document.history.undoCount == depth
            && (try? outgoing.document.state.file.encoded()) == originalBytes
        if replacing {
            report.expect(preserved, cppID: id,
                          message: "song replacement ends the outgoing preview without mutating its song")
        } else {
            report.expect(preserved, cppID: id,
                          message: "song null ends the held preview without mutating its song")
        }
    }
}

@MainActor
private func hostPlayheadFollowing(_ report: CheckReport, session: DocumentSession,
                                   service: ProjectService) {
    let id = "swiftcore/HostBehaviorChecks::playheadFollowing"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    fixture.session.clearSelectedNotes()
    fixture.session.editCursor = 0
    fixture.page.refreshEditCursor()
    let bankSlot = fixture.page.context.slot
    let tick: Tick = 96
    let sample = fixture.session.timeline.sample(for: tick)
    fixture.page.refreshPlayhead(tick: fixture.session.timeline.tick(for: sample), playing: true)
    report.expect(velocityContextTick(fixture.session.timeline.tick(for: sample)) == tick
                  && fixture.page.contextTick == tick, cppID: id,
                  message: "the playhead tick follows the played sample")
    report.expect(fixture.page.context.slot != bankSlot, cppID: id,
                  message: "steady context resolves through presentation voice, not the bank")
}

@MainActor
private func hostBandGeometry(_ report: CheckReport, session: DocumentSession,
                              service: ProjectService) {
    let id = "swiftcore/HostBehaviorChecks::bandGeometry"
    let fixture = drawerAutomationAutomationFixture(suite: session, service: service)
    let font = GridCameraPolicy.seedBaseFontPx
    let width = Int(fontPx(font, 70))
    let height = Int(fontPx(font, 40))
    let gutter = Int(fontPx(font, 8))
    let drawer = EditorDrawerPresenter()
    drawer.configureLayout(hostWidth: width, hostHeight: height, gutterWidth: gutter,
                           fontPx: font, appFontLineSpacing: fontPx(font, 1))
    fixture.page.configureBody(width: Double(drawer.plotWidth),
                               height: fontPx(font, 9), gutter: Double(drawer.plotOrigin),
                               devicePixelRatio: 1, baseFontPx: font,
                               dragDistance: fixture.page.dragDistance)
    report.expect(drawer.plotOrigin == gutter && drawer.plotOrigin + drawer.plotWidth == width
                  && fixture.page.plotOrigin == Double(gutter)
                  && fixture.page.plotWidth == Double(width - gutter),
                  cppID: id, message: "plot origins sit at the split and right edges meet band edges")
}

@MainActor
private func hostCameraEndpoints(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let id = "swiftcore/HostBehaviorChecks::cameraEndpoints"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let session = fixture.session
    let font = GridCameraPolicy.seedBaseFontPx
    let zoom = 1.75 * fontPx(font, 8.0 / 3.0)
    _ = session.mutateCamera { camera in
        _ = camera.setTimeZoom(zoom)
        _ = camera.setHScroll(96)
    }
    let camera = session.camera.snapshot
    report.expect(camera.scrollX == 96 && camera.pixelsPerBeat == zoom, cppID: id,
                  message: "scroll 96 and the zoom law publish through the camera")
    report.expect(session.grid.gridTicksAt(12, camera: session.camera) > 0
                  && session.grid.snapTicksAt(12, camera: session.camera) > 0,
                  cppID: id, message: "grid and snap ticks stay positive")
    session.editCursor = 0
    fixture.page.refreshEditCursor()
    report.expect(fixture.page.context.slot == 0, cppID: id,
                  message: "voice context resolves slot zero")
    report.expect(velocityContextTick(-1) == 0 && velocityContextTick(0.49) == 0
                  && velocityContextTick(0.5) == 1 && velocityContextTick(0.51) == 1,
                  cppID: id, message: "context-tick rounding splits at the half tick")
}

@MainActor
private func hostCosmeticOnly(_ report: CheckReport, session: DocumentSession,
                              service: ProjectService) {
    let id = "swiftcore/HostBehaviorChecks::cosmeticOnly"
    let fixture = drawerAutomationAutomationFixture(suite: session, service: service)
    let before = DocumentSnapshot(fixture.document)
    let count = fixture.document.history.undoCount
    let bytes = try? fixture.document.state.file.encoded()
    var lanes = EditorLaneState()
    lanes.laneHeight = Int(fontPx(fixture.page.baseFontPx, 8))
    lanes.hiddenLanes = [.init(track: 0, controller: 7)]
    let encoded = EditorViewStateCodec.encodeLanes(lanes)
    let restored = encoded.map(EditorViewStateCodec.decodeLanes)
    fixture.page.configureBody(width: fontPx(fixture.page.baseFontPx, 30),
                               height: fontPx(fixture.page.baseFontPx, 9),
                               gutter: 0, devicePixelRatio: 1,
                               baseFontPx: fixture.page.baseFontPx,
                               dragDistance: fixture.page.dragDistance)
    report.expect(restored == lanes && DocumentSnapshot(fixture.document) == before
                  && fixture.document.history.undoCount == count
                  && (try? fixture.document.state.file.encoded()) == bytes,
                  cppID: id, message: "editor view-state round-trips without advancing revision or history")
    let x = fixture.page.plotWidth / 2
    let y = fixture.page.plotHeight / 2
    let cameraBefore = fixture.session.camera.snapshot
    let pressed = fixture.page.pointerPress(x: x, y: y, surface: 1, button: 4)
    let panning = fixture.page.isPanning
    let moved = fixture.page.pointerMove(x: x - fixture.page.baseFontPx, y: y, buttons: 4)
    let released = fixture.page.pointerRelease(x: x - fixture.page.baseFontPx, y: y, button: 4)
    report.expect(pressed && panning && moved && released && !fixture.page.isPanning,
                  cppID: id, message: "middle-button pan completes its gesture lifecycle")
    report.expect(fixture.session.camera.snapshot.scrollX != cameraBefore.scrollX,
                  cppID: id, message: "middle-button pan moves the shared camera")
    report.expect(DocumentSnapshot(fixture.document) == before
                  && fixture.document.history.undoCount == count
                  && (try? fixture.document.state.file.encoded()) == bytes,
                  cppID: id, message: "pan attempts leave song bytes, revision and undo depth untouched")
}

@MainActor
private func hostAutomationTempo(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let id = "swiftcore/HostBehaviorChecks::automationTempo"
    let fixture = drawerAutomationAutomationFixture(suite: session, service: service)
    let index = fixture.page.catalogIndex(of: .tempo)
    report.expect(index >= 0 && fixture.page.activateParameter(index: index)
                  && fixture.page.activeParameter == .tempo, cppID: id,
                  message: "the tempo parameter index resolves")
}
