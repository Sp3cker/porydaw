import Foundation
@testable import PorydawApp
import PorydawAppAudio
import PorydawCore
@testable import PorydawDocument
import PorydawPlayback

@MainActor
internal func runHostBehaviorChecks(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService, fixtureRoot: String
) {
    let route = hostNoteDiscovery(report, fixtureRoot: fixtureRoot, suite: session, service: service)
    hostVelocityMarker(report, route: route)
    hostSeededTrackDiscovery(report, route: route)
    hostSteadyVoiceContext(report, route: route)
    hostTwoTabActiveSelection(report)
    hostVelocityGestureContracts(report, session: session, service: service)
    hostDocumentMutationUndoRedo(report, session: session, service: service)
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
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [], endTick: 48),
            MidiChunk(events: events, endTick: 48),
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    return DocumentSession(
        document: document, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
}

@MainActor
private func hostNoteDiscovery(
    _ report: CheckReport, fixtureRoot: String,
    suite: DocumentSession, service: ProjectService
) -> DocumentSession? {
    let id = "swiftcore/HostBehaviorChecks::noteDiscovery"
    let twoNotes = hostTwoNoteSession(suite: suite, service: service)
    report.expect(
        twoNotes.document.notes(in: 0).count == 2
            && twoNotes.timeline.events.filter { $0.type == 0x9 }.count == 2,
        cppID: id, message: "track zero projects two seeded notes")
    twoNotes.setSelectedNotes(twoNotes.document.notes(in: 0).prefix(2).map(\.id))
    report.expect(
        twoNotes.selectedNotes.count == 2, cppID: id,
        message: "A004: the ready two-note seed selects exactly two notes")
    let routeService = ProjectService()
    do {
        try runBlocking { try await routeService.open(root: fixtureRoot) }
        let session = try runBlocking {
            try await DocumentSession.open(
                service: routeService, label: "mus_route101",
                sampleRate: 48_000)
        }
        let note = (0..<session.document.engineTracks.usedTrackCount)
            .lazy.flatMap { session.document.notes(in: $0) }.first
        report.expect(
            note != nil
                && session.timeline.events.contains {
                    $0.type == 0x9 && $0.noteID == note?.id
                }, cppID: id,
            message: "route101 fixture notes resolve from the loaded document with timeline note-on events")
        report.expect(
            session.document.source.label == "mus_route101", cppID: id,
            message: "A013: the opened route101 document retains the mus_route101 label")
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
private func hostTwoTabActiveSelection(_ report: CheckReport) {
    let id = "swiftcore/HostBehaviorChecks::noteDiscovery"
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(id, "project-session fixture root is unavailable for the two-tab selection")
        return
    }
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-host-two-tab-selection")
    let shell = ShellPresenter()
    let app = shell.session
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    var deadline = Date().addingTimeInterval(25)
    while !app.songOpen && app.lastSaveError.isEmpty && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    guard app.songOpen, app.lastSaveError.isEmpty else {
        report.fail(id, "first staged song did not open for the two-tab selection: \(app.lastSaveError)")
        return
    }
    app.openSong(label: "mus_session_test2")
    deadline = Date().addingTimeInterval(25)
    while app.songTabs.tabCount < 2 && app.lastSaveError.isEmpty && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    // The fork's ready two-tab route fixture: the second open owns the
    // active tab, and the selected document is that tab's own session.
    guard app.songTabs.tabCount == 2, app.lastSaveError.isEmpty,
        let first = app.songTabs.tab(label: "mus_session_test"),
        let active = app.songTabs.selectedPage, first !== active,
        let activeSession = app.selectedDocument,
        activeSession === active.workspace.session
    else {
        report.fail(id, "ready two-tab session did not land on the second song")
        return
    }
    guard
        let track = (0..<activeSession.document.engineTracks.usedTrackCount).first(
            where: { activeSession.document.notes(in: $0).count >= 2 })
    else {
        report.fail(id, "active tab song exposes no track holding two notes")
        return
    }
    activeSession.setSelectedNotes(activeSession.document.notes(in: track).prefix(2).map(\.id))
    report.expect(
        activeSession.selectedNotes.count == 2, cppID: id,
        message: "A004: the active tab of the ready two-tab session selects exactly two notes")
}

@MainActor
private func hostVelocityMarker(_ report: CheckReport, route: DocumentSession?) {
    let id = "swiftcore/HostBehaviorChecks::velocityMarker"
    guard let route,
        let track = (0..<route.document.engineTracks.usedTrackCount).first(where: {
            !route.document.notes(in: $0).isEmpty
        }), let note = route.document.notes(in: track).first
    else {
        report.fail(id, "route101 fixture did not expose an editable note")
        return
    }
    route.selectedTrack = track
    route.setSelectedNotes([note.id])
    let page = VelocityPage(baseFontPx: GridCameraPolicy.seedBaseFontPx)
    page.attach(session: route, palette: GridPalette())
    let font = GridCameraPolicy.seedBaseFontPx
    page.configureBody(
        width: fontPx(font, 30), height: fontPx(font, 9),
        rulerWidth: fontPx(font, 4), devicePixelRatio: 1,
        baseFontPx: font, dragDistance: page.dragDistance)
    guard route.selectedTrack == track && route.selectedNotes == [note.id] else {
        report.fail(id, "fixture note selection could not attach to the primary track")
        return
    }
    report.expect(
        route.selectedTrack == 0, cppID: id,
        message: "A015: the first note-bearing route101 engine track is track zero")
    report.expect(
        route.selectedNotes == [NoteID(1)], cppID: id,
        message: "A016: the front note on route101 track zero has note id one")
    let markers = page.axisModel.markers
    report.expect(
        markers.count == 1, cppID: id,
        message: "the selected note publishes one axis marker")
    report.expect(
        markers.first?.velocity == Int(note.velocity), cppID: id,
        message: "the marker value equals the fixture velocity")
}

@MainActor
private func hostVelocityGestureContracts(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/HostBehaviorChecks::velocityGestureContracts"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard let note = fixture.notes.first,
        fixture.document.setVelocities(
            [NoteVelocity(noteID: note.id, velocity: 127)],
            expectedRevision: fixture.document.revision) != nil
    else {
        report.fail(id, "fixture first note could not be seeded to velocity 127")
        return
    }
    fixture.page.refreshFromDocument()
    guard let handle = fixture.handle(note) else {
        report.fail(id, "seeded fixture note has no velocity node")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([note.id])
    page.refreshFromDocument()
    let before = DocumentSnapshot(document)
    let depth = document.history.undoCount
    let originalBytes = try? document.state.file.encoded()
    let pressY = page.axisModel.velocityToY(127)
    let targetY = page.axisModel.velocityToY(1)
    let pressed = page.pointerPress(
        x: handle.x, y: pressY, surface: 1, button: 1,
        modifiers: VelocityModifier.control)
    _ = page.pointerMove(x: handle.x, y: targetY, buttons: 1)
    report.expect(
        pressed && !page.frozenPreview.isEmpty && DocumentSnapshot(document) == before
            && document.history.undoCount == depth && (try? document.state.file.encoded()) == originalBytes,
        cppID: id, message: "a drag move stages a preview without advancing revision or history")
    _ = page.pointerRelease(x: handle.x, y: targetY, button: 1)
    report.expect(
        document.revision == before.revision + 1
            && document.history.undoCount == depth + 1
            && document.note(note.id)?.velocity != note.velocity
            && page.frozenPreview.isEmpty && fixture.handle(note)?.y != handle.y,
        cppID: id, message: "committing advances revision once and invalidates")
    report.expect(
        document.note(note.id)?.velocity == 1
            && document.revision == before.revision + 1, cppID: id,
        message: "A028: the first pointer gesture commits velocity one in one revision")
    let after = DocumentSnapshot(document)
    let afterBytes = try? document.state.file.encoded()
    guard let moved = fixture.handle(note) else {
        report.fail(id, "committed first note has no clickable velocity handle")
        return
    }
    _ = page.pointerPress(x: moved.x, y: moved.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerRelease(x: moved.x, y: moved.y, button: 1)
    report.expect(
        fixture.session.selectedNotes == [note.id] && DocumentSnapshot(document) == after
            && document.history.undoCount == depth + 1
            && (try? document.state.file.encoded()) == afterBytes,
        cppID: id, message: "a click press selects one note without touching song bytes")
    hostVelocityExactGestures(report, session: session, service: service)
}

@MainActor
private func hostVelocityExactGestures(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/HostBehaviorChecks::velocityGestureContracts"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard fixture.notes.count >= 2 else {
        report.fail(id, "the exact gesture fixture lacks two notes")
        return
    }
    let document = fixture.document
    let firstID = fixture.notes[0].id
    let secondID = fixture.notes[1].id
    guard
        document.setVelocities(
            [
                NoteVelocity(noteID: firstID, velocity: 127),
                NoteVelocity(noteID: secondID, velocity: 64),
            ],
            expectedRevision: document.revision) != nil,
        let first = document.note(firstID), let second = document.note(secondID),
        first.velocity == 127, second.velocity == 64
    else {
        report.fail(id, "the exact 127 and 64 gesture seed did not land")
        return
    }
    let selected = [firstID, secondID]
    fixture.session.setSelectedNotes(selected)
    fixture.page.refreshFromDocument()
    let baseline = DocumentSnapshot(document)
    let undoIndex = document.history.undoIndex
    let baselineBytes = try? document.state.file.encoded()
    guard baselineBytes != nil else {
        report.fail(id, "the gesture seed could not encode its song bytes")
        return
    }
    let map = VelocityMap(voiceKind: .unresolved)
    let axis = VelocityAxisModel(map: map, geometry: VelocityAxisGeometry())
    let frozen = [
        VelocityFrozenNote(
            noteID: firstID, tick: first.tick, duration: first.duration,
            pitch: first.pitch, velocity: 127, map: map, exactOrigin: 127),
        VelocityFrozenNote(
            noteID: secondID, tick: second.tick, duration: second.duration,
            pitch: second.pitch, velocity: 64, map: map, exactOrigin: 64),
    ]
    func begin(_ notes: [VelocityFrozenNote]) -> VelocityGestureState? {
        VelocityGestureState(
            kind: .relative, revision: document.revision, track: 0,
            notes: notes, axis: axis, detentUnlock: true,
            activationDistance: 0, pressX: 0, pressY: 0)
    }
    guard var noop = begin(frozen),
        noop.updatePreview([
            NoteVelocity(noteID: firstID, velocity: 127),
            NoteVelocity(noteID: secondID, velocity: 64),
        ])
    else {
        report.fail(id, "the unchanged two-note gesture could not stage its preview")
        return
    }
    let noopResult = document.setVelocities(
        VelocityGesturePolicy.updates(noop),
        expectedRevision: noop.revision)
    report.expect(
        noopResult == baseline.revision && DocumentSnapshot(document) == baseline
            && fixture.session.selectedNotes == Set(selected)
            && (try? document.state.file.encoded()) == baselineBytes
            && noop.previewVelocity(firstID) == 127
            && noop.previewVelocity(secondID) == 64,
        cppID: id, message: "A044: an unchanged gesture leaves revision, notes, selection and previews intact")
    report.expect(
        document.history.undoIndex == undoIndex, cppID: id,
        message: "A045: an unchanged gesture does not advance the history index")
    guard let handle = fixture.handle(first) else {
        report.fail(id, "the seeded first note has no clickable velocity handle")
        return
    }
    let pressed = fixture.page.pointerPress(
        x: handle.x, y: handle.y, surface: 1,
        button: 1, modifiers: 0)
    let released = fixture.page.pointerRelease(x: handle.x, y: handle.y, button: 1)
    report.expect(
        pressed && released && fixture.session.selectedNotes == Set([firstID])
            && DocumentSnapshot(document) == baseline
            && document.history.undoIndex == undoIndex
            && (try? document.state.file.encoded()) == baselineBytes,
        cppID: id, message: "clicking the first node selects it without editing song bytes or history")
    fixture.session.setSelectedNotes(selected)
    fixture.page.refreshFromDocument()
    guard var gesture = begin(frozen),
        gesture.updatePreview([
            NoteVelocity(noteID: firstID, velocity: 1),
            NoteVelocity(noteID: secondID, velocity: 65),
        ])
    else {
        report.fail(id, "the exact two-note gesture could not stage its targets")
        return
    }
    report.expect(
        gesture.previewVelocity(firstID) == 1, cppID: id,
        message: "A053: the first frozen preview has exact velocity one")
    report.expect(
        gesture.previewVelocity(secondID) == 65, cppID: id,
        message: "A054: the second frozen preview has exact velocity sixty-five")
    report.expect(
        document.note(firstID)?.velocity == 127
            && document.revision == baseline.revision
            && document.history.undoIndex == undoIndex, cppID: id,
        message: "the two exact previews leave the seeded first velocity and history held")
    let committed = document.setVelocities(
        VelocityGesturePolicy.updates(gesture),
        expectedRevision: gesture.revision)
    fixture.page.refreshFromDocument()
    report.expect(
        committed == baseline.revision + 1, cppID: id,
        message: "the exact two-note commit advances the document revision once")
    report.expect(
        document.note(firstID)?.velocity == 1, cppID: id,
        message: "A063: the held first note lands at exact velocity one")
    report.expect(
        document.note(secondID)?.velocity == 65, cppID: id,
        message: "the second committed target lands at exact velocity sixty-five")
    report.expect(
        document.history.undoIndex == undoIndex + 1
            && fixture.session.selectedNotes == Set(selected), cppID: id,
        message: "A065: the exact commit retains both selected notes at the next history index")
    do {
        guard try runBlocking({ try await fixture.session.undo() }) else {
            report.fail(id, "the exact velocity commit was not undoable")
            return
        }
    } catch {
        report.fail(id, "the exact velocity undo failed")
        return
    }
    report.expect(
        fixture.session.selectedNotes == Set(selected)
            && document.note(firstID)?.velocity == 127
            && document.note(secondID)?.velocity == 64, cppID: id,
        message: "A066: undo restores both selected notes and their seeded velocities")
    do {
        guard try runBlocking({ try await fixture.session.redo() }) else {
            report.fail(id, "the exact velocity commit was not redoable")
            return
        }
    } catch {
        report.fail(id, "the exact velocity redo failed")
        return
    }
    guard let staleFirst = document.note(firstID), let staleSecond = document.note(secondID),
        var stale = begin([
            VelocityFrozenNote(
                noteID: firstID, tick: staleFirst.tick,
                duration: staleFirst.duration, pitch: staleFirst.pitch,
                velocity: 1, map: map, exactOrigin: 1),
            VelocityFrozenNote(
                noteID: secondID, tick: staleSecond.tick,
                duration: staleSecond.duration, pitch: staleSecond.pitch,
                velocity: 65, map: map, exactOrigin: 65),
        ]), stale.updatePreview([NoteVelocity(noteID: firstID, velocity: 2)])
    else {
        report.fail(id, "the stale velocity fixture could not stage its preview")
        return
    }
    guard let staleHandle = fixture.handle(staleFirst),
        fixture.page.pointerPress(
            x: staleHandle.x, y: staleHandle.y, surface: 1,
            button: 1, modifiers: 0),
        fixture.page.pointerMove(
            x: staleHandle.x,
            y: staleHandle.y - fixture.page.dragDistance * 2,
            buttons: 1),
        fixture.page.frozenPreview[firstID] != nil,
        fixture.page.frozenPreview[secondID] != nil
    else {
        report.fail(id, "the stale pointer drag did not preview both selected notes")
        return
    }
    let staleRevision = document.revision
    guard
        document.setVelocities(
            [NoteVelocity(noteID: secondID, velocity: 66)],
            expectedRevision: staleRevision) == staleRevision + 1
    else {
        report.fail(id, "the external velocity edit did not land")
        return
    }
    let rejected = document.setVelocities(
        VelocityGesturePolicy.updates(stale),
        expectedRevision: stale.revision)
    fixture.page.refreshFromDocument()
    report.expect(
        rejected == nil, cppID: id,
        message: "the stale model payload rejects the captured revision")
    report.expect(
        document.revision == staleRevision + 1, cppID: id,
        message: "A070: only the external edit advances the stale revision")
    report.expect(
        document.history.undoIndex == undoIndex + 2, cppID: id,
        message: "A071: the stale rejection adds no history entry after the external edit")
    report.expect(
        document.note(firstID)?.velocity == 1, cppID: id,
        message: "A074: stale rejection leaves the first note at velocity one")
    report.expect(
        document.note(secondID)?.velocity == 66, cppID: id,
        message: "A075: the external edit lands velocity sixty-six on the second note")
    report.expect(
        fixture.page.frozenPreview[firstID] == nil, cppID: id,
        message: "A076: rejection clears the first stale preview")
    report.expect(
        fixture.page.frozenPreview[secondID] == nil, cppID: id,
        message: "A077: rejection clears the second stale preview")
    report.expect(
        fixture.session.selectedNotes == Set(selected), cppID: id,
        message: "A078: rejection preserves the restored two-note selection")
}

@MainActor
private func hostDocumentMutationUndoRedo(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/HostBehaviorChecks::documentMutationUndoRedo"
    enum Branch: CaseIterable, Equatable {
        case mutation, undo, redo
    }
    for branch in Branch.allCases {
        let fixture = drawerVelocityVelocityFixture(session: session, service: service)
        let document = fixture.document
        guard let note = fixture.notes.first, note.velocity == 100 else {
            report.fail(id, "the document-history fixture lacks its first velocity-100 note")
            continue
        }
        fixture.session.setSelectedNotes([note.id])
        let page = fixture.page
        func beginPreview() -> Bool {
            page.refreshFromDocument()
            guard let current = document.note(note.id), let handle = fixture.handle(current) else {
                return false
            }
            return page.pointerPress(
                x: handle.x, y: handle.y, surface: 1,
                button: 1, modifiers: 0)
                && page.pointerMove(x: handle.x, y: handle.y - page.dragDistance * 2, buttons: 1)
                && page.hasGesture && page.frozenPreview[note.id] != nil
        }
        guard beginPreview() else {
            report.fail(id, "the document-history fixture could not stage a live velocity preview")
            continue
        }
        let revision = document.revision
        let undoIndex = document.history.undoIndex
        let undoCount = document.history.undoCount
        let originalIdentity = document.history.currentIdentity
        let target = branch == .mutation ? 101 : 95
        let mutation = document.setVelocities(
            [NoteVelocity(noteID: note.id, velocity: target)],
            expectedRevision: revision)
        guard mutation != nil else {
            report.fail(id, "the document-history velocity mutation was rejected")
            continue
        }
        if branch == .mutation {
            report.expect(
                document.revision == revision + 1, cppID: id,
                message: "A127: live-preview document mutation advances the revision by one")
            report.expect(
                document.history.undoIndex == undoIndex + 1, cppID: id,
                message: "A128: live-preview document mutation advances the undo index by one")
            report.expect(
                document.history.undoCount == undoCount + 1, cppID: id,
                message: "A129: live-preview document mutation appends one undo entry")
            continue
        }
        guard mutation == revision + 1,
            document.history.undoIndex == undoIndex + 1,
            document.history.currentIdentity != originalIdentity
        else {
            report.fail(id, "the history branch could not stage its independent velocity mutation")
            continue
        }
        guard beginPreview() else {
            report.fail(id, "the history branch could not stage its undo preview")
            continue
        }
        if branch == .undo {
            let beforeUndoRevision = document.revision
            let beforeUndoIndex = document.history.undoIndex
            let undone = document.history.undoDocument()
            report.expect(
                undone && document.revision == beforeUndoRevision + 1, cppID: id,
                message: "A130: undo during a live velocity preview advances the revision by one")
            report.expect(
                undone && document.history.undoIndex == beforeUndoIndex - 1, cppID: id,
                message: "A131: undo during a live velocity preview moves the index back by one")
            continue
        }
        guard document.history.undoDocument(),
            document.history.currentIdentity == originalIdentity
        else {
            report.fail(id, "the redo branch could not return to its pre-mutation identity")
            continue
        }
        guard beginPreview() else {
            report.fail(id, "the redo branch could not stage its live velocity preview")
            continue
        }
        let beforeRedoRevision = document.revision
        let beforeRedoIndex = document.history.undoIndex
        let redone = document.history.redoDocument()
        report.expect(
            redone && document.revision == beforeRedoRevision + 1, cppID: id,
            message: "A132: redo during a live velocity preview advances the revision by one")
        report.expect(
            redone && document.history.undoIndex == beforeRedoIndex + 1, cppID: id,
            message: "A133: redo during a live velocity preview moves the index forward by one")
    }
}

@MainActor
private func hostLifecycleTermination(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
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
    report.expect(
        !fixture.page.hasGesture && fixture.page.frozenPreview.isEmpty
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
        _ = outgoing.page.pointerPress(
            x: handle.x, y: handle.y, surface: 1,
            button: 1, modifiers: 0)
        _ = outgoing.page.pointerMove(
            x: handle.x,
            y: handle.y - outgoing.page.dragDistance * 2, buttons: 1)
        let held = outgoing.page.hasGesture && !outgoing.page.frozenPreview.isEmpty
        outgoing.page.detach()
        if replacing {
            outgoing.page.attach(
                session: hostTwoNoteSession(suite: session, service: service),
                palette: GridPalette())
        }
        let released = outgoing.page.pointerRelease(
            x: handle.x,
            y: handle.y - outgoing.page.dragDistance * 2,
            button: 1)
        let preserved =
            held && !released && !outgoing.page.hasGesture
            && outgoing.page.frozenPreview.isEmpty
            && DocumentSnapshot(outgoing.document) == snapshot
            && outgoing.document.history.undoCount == depth
            && (try? outgoing.document.state.file.encoded()) == originalBytes
        report.expect(
            outgoing.session.selectedNotes.isEmpty, cppID: id,
            message: "song teardown clears the outgoing note selection")
        if replacing {
            report.expect(
                preserved, cppID: id,
                message: "song replacement ends the outgoing preview without mutating its song")
        } else {
            report.expect(
                preserved, cppID: id,
                message: "song null ends the held preview without mutating its song")
        }
    }
}

@MainActor
private func hostPlayheadFollowing(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/HostBehaviorChecks::playheadFollowing"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    fixture.session.clearSelectedNotes()
    fixture.session.editCursor = 0
    fixture.page.refreshEditCursor()
    let bankSlot = fixture.page.context.slot
    let tick: Tick = 96
    let sample = fixture.session.timeline.sample(for: tick)
    fixture.page.refreshPlayhead(tick: fixture.session.timeline.tick(for: sample), playing: true)
    report.expect(
        velocityContextTick(fixture.session.timeline.tick(for: sample)) == tick
            && fixture.page.contextTick == tick, cppID: id,
        message: "the playhead tick follows the played sample")
    report.expect(
        fixture.page.context.slot != bankSlot, cppID: id,
        message: "steady context resolves through presentation voice, not the bank")
    hostVelocityAxisVoice(report, session: session)
}

@MainActor
private func hostVelocityAxisVoice(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/HostBehaviorChecks::playheadFollowing"
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [], endTick: 48),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0xC0, data0: 0),
                    .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
                    .channel(tick: 24, status: 0xC0, data0: 1),
                    .channel(tick: 48, status: 0x80, data0: 60),
                ], endTick: 48),
        ])
    let document = SongDocument(
        file: file, config: session.document.state.config,
        source: session.document.source,
        trackBudget: session.document.trackBudget)
    let slots = [
        BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(macro: BankVoiceMacro.square1)),
        BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(macro: BankVoiceMacro.noise)),
    ]
    let played = DocumentSession(
        document: document, service: ProjectService(),
        lease: session.bankLease, slots: slots, dirty: false,
        loadName: session.bankLoadName, sampleRate: 48_000)
    played.selectedTrack = 0
    played.clearSelectedNotes()
    played.editCursor = 0
    let page = VelocityPage(baseFontPx: GridCameraPolicy.seedBaseFontPx)
    page.attach(session: played, palette: GridPalette())
    let font = GridCameraPolicy.seedBaseFontPx
    page.configureBody(
        width: fontPx(font, 30), height: fontPx(font, 9),
        rulerWidth: fontPx(font, 4), devicePixelRatio: 1,
        baseFontPx: font, dragDistance: page.dragDistance)
    page.refreshEditCursor()
    report.expect(
        page.axisModel.map.voiceName == "Square 1", cppID: id,
        message: "A164: the stopped axis names Square 1 at the steady cursor")
    let at24 = played.timeline.sample(for: 24)
    page.refreshPlayhead(tick: played.timeline.tick(for: at24), playing: true)
    report.expect(
        page.axisModel.map.voiceName == "Noise", cppID: id,
        message: "A165: the followed sample at tick twenty-four names Noise")
    let at25 = played.timeline.sample(for: 25)
    let at26 = played.timeline.sample(for: 26)
    page.refreshPlayhead(tick: played.timeline.tick(for: at25), playing: true)
    page.refreshPlayhead(tick: played.timeline.tick(for: at26), playing: true)
    page.refreshPlayhead(tick: played.timeline.tick(for: at26), playing: false)
    report.expect(
        page.axisModel.map.voiceName == "Square 1", cppID: id,
        message: "A168: the non-following sample at tick twenty-six restores Square 1")
}

@MainActor
private func hostBandGeometry(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/HostBehaviorChecks::bandGeometry"
    let fixture = drawerAutomationAutomationFixture(suite: session, service: service)
    let font = GridCameraPolicy.seedBaseFontPx
    let width = Int(fontPx(font, 70))
    let height = Int(fontPx(font, 40))
    let gutter = Int(fontPx(font, 8))
    let drawer = EditorDrawerPresenter()
    drawer.configureLayout(
        hostWidth: width, hostHeight: height, gutterWidth: gutter,
        fontPx: font, appFontLineSpacing: fontPx(font, 1))
    fixture.page.configureBody(
        width: Double(drawer.plotWidth),
        height: fontPx(font, 9), gutter: Double(drawer.plotOrigin),
        devicePixelRatio: 1, baseFontPx: font,
        dragDistance: fixture.page.dragDistance)
    report.expect(
        drawer.plotOrigin == gutter && drawer.plotOrigin + drawer.plotWidth == width
            && fixture.page.plotOrigin == Double(gutter)
            && fixture.page.plotWidth == Double(width - gutter),
        cppID: id, message: "plot origins sit at the split and right edges meet band edges")
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(id, "project-session fixture root is unavailable for band geometry")
        return
    }
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-host-band-geometry")
    let shell = ShellPresenter()
    let app = shell.session
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    let deadline = Date().addingTimeInterval(25)
    while !app.songOpen && app.lastSaveError.isEmpty && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    guard app.songOpen, let page = app.songTabs.selectedPage,
        let audio = app.transportAudio
    else {
        report.fail(id, "copied project did not open with audio and an automation band: \(app.lastSaveError)")
        return
    }
    let liveDrawer = page.drawerPresenter()
    liveDrawer.configureLayout(
        hostWidth: width, hostHeight: height, gutterWidth: gutter,
        fontPx: font, appFontLineSpacing: fontPx(font, 1))
    liveDrawer.setSectionVisible(
        kind: DrawerSectionKind.automation.rawValue,
        visible: true, drawerOwnsFocus: false)
    let band = liveDrawer.automationSection
    let settings = PreferencesStore()
    let previousMode = settings.string(key: "theme.mode", fallback: "")
    let hadMode = settings.hasValue(key: "theme.mode")
    defer {
        if hadMode {
            settings.setString(key: "theme.mode", value: previousMode)
        } else {
            settings.remove(key: "theme.mode")
        }
        settings.synchronize()
        shell.restoreAppearance()
    }
    shell.restoreAppearance()
    let originalColor = app.palette.windowBackground
    let nextMode = shell.themeMode == "dark-neutral-high" ? "vanilla" : "dark-neutral-high"
    let firstSample = audio.playheadSamples
    app.play()
    let playbackDeadline = Date().addingTimeInterval(5)
    while (audio.transport != AudioTransportState.playing.rawValue
        || audio.playheadSamples <= firstSample + UInt64(audio.sampleRate / 20))
        && Date() < playbackDeadline
    {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    guard audio.transport == AudioTransportState.playing.rawValue,
        audio.playheadSamples > firstSample + UInt64(audio.sampleRate / 20)
    else {
        report.fail(id, "copied song did not reach steady null-backend playback")
        return
    }
    defer { app.stop() }
    let metrics = EditorDrawerMetrics.resolve(
        baseFontPx: font,
        appFontLineSpacing: fontPx(font, 1))
    report.expect(
        band.available && band.visible && !band.contentUrl.isEmpty
            && band.bodyX == 0 && band.bodyWidth == width
            && band.bodyHeight >= metrics.minimumBody
            && band.handleHeight == metrics.handleHeight,
        cppID: id,
        message: "A008: the automation band publishes measured body and handle geometry during steady playback")
    let beforeValues = [
        band.bodyX, band.bodyY, band.bodyWidth, band.bodyHeight,
        band.handleY, band.handleHeight, band.toggleX, band.toggleY,
        band.toggleSize, liveDrawer.plotOrigin, liveDrawer.plotWidth,
    ]
    let beforeAvailable = band.available
    let beforeVisible = band.visible
    let beforeUrl = band.contentUrl
    settings.setString(key: "theme.mode", value: nextMode)
    settings.synchronize()
    shell.restoreAppearance()
    guard shell.themeMode == nextMode, app.palette.windowBackground != originalColor else {
        report.fail(id, "production appearance restore did not apply a different palette")
        return
    }
    report.expect(
        band.available == beforeAvailable && band.visible == beforeVisible
            && band.contentUrl == beforeUrl
            && [
                band.bodyX, band.bodyY, band.bodyWidth, band.bodyHeight,
                band.handleY, band.handleHeight, band.toggleX, band.toggleY,
                band.toggleSize, liveDrawer.plotOrigin, liveDrawer.plotWidth,
            ] == beforeValues,
        cppID: id,
        message: "A142: restoring a different appearance preserves every measured automation band geometry field")
}

@MainActor
private func hostCameraEndpoints(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
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
    report.expect(
        camera.scrollX == 96 && camera.pixelsPerBeat == zoom, cppID: id,
        message: "scroll 96 and the zoom law publish through the camera")
    report.expect(
        session.grid.gridTicksAt(12, camera: session.camera) > 0
            && session.grid.snapTicksAt(12, camera: session.camera) > 0,
        cppID: id, message: "grid and snap ticks stay positive")
    session.editCursor = 0
    fixture.page.refreshEditCursor()
    report.expect(
        fixture.page.context.slot == 0, cppID: id,
        message: "voice context resolves slot zero")
    report.expect(
        velocityContextTick(-1) == 0 && velocityContextTick(0.49) == 0
            && velocityContextTick(0.5) == 1 && velocityContextTick(0.51) == 1,
        cppID: id, message: "context-tick rounding splits at the half tick")
}

@MainActor
private func hostCosmeticOnly(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/HostBehaviorChecks::cosmeticOnly"
    let fixture = drawerAutomationAutomationFixture(suite: session, service: service)
    let before = DocumentSnapshot(fixture.document)
    let count = fixture.document.history.undoCount
    let bytes = try? fixture.document.state.file.encoded()
    var lanes = EditorLaneState()
    lanes.laneHeight = Int(fontPx(fixture.page.baseFontPx, 8))
    lanes.hiddenLanes = [.init(track: 0, controller: 7)]
    let encoded = EditorViewStatePreferences.encodeLanes(lanes)
    let restored = encoded.map(EditorViewStatePreferences.decodeLanes)
    fixture.page.configureBody(
        width: fontPx(fixture.page.baseFontPx, 30),
        height: fontPx(fixture.page.baseFontPx, 9),
        gutter: 0, devicePixelRatio: 1,
        baseFontPx: fixture.page.baseFontPx,
        dragDistance: fixture.page.dragDistance)
    report.expect(
        restored == lanes && DocumentSnapshot(fixture.document) == before
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
    report.expect(
        pressed && panning && moved && released && !fixture.page.isPanning,
        cppID: id, message: "middle-button pan completes its gesture lifecycle")
    report.expect(
        fixture.session.camera.snapshot.scrollX != cameraBefore.scrollX,
        cppID: id, message: "middle-button pan moves the shared camera")
    report.expect(
        DocumentSnapshot(fixture.document) == before
            && fixture.document.history.undoCount == count
            && (try? fixture.document.state.file.encoded()) == bytes,
        cppID: id, message: "pan attempts leave song bytes, revision and undo depth untouched")
}

@MainActor
private func hostAutomationTempo(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/HostBehaviorChecks::automationTempo"
    let fixture = drawerAutomationAutomationFixture(suite: session, service: service)
    let index = fixture.page.catalogIndex(of: .tempo)
    report.expect(
        index >= 0 && fixture.page.activateParameter(index: index)
            && fixture.page.activeParameter == .tempo, cppID: id,
        message: "the tempo parameter index resolves")
}

@MainActor
private func hostSeededTrackDiscovery(_ report: CheckReport, route: DocumentSession?) {
    let id = "swiftcore/HostBehaviorChecks::seededContext"
    guard let route else {
        report.fail(id, "the route101 host session did not open for the two-note discovery")
        return
    }
    let discovered =
        (0..<route.document.engineTracks.usedTrackCount).first {
            route.document.notes(in: $0).count >= 2
        } ?? -1
    report.expect(
        discovered >= 0, cppID: id,
        message: "A003: the route101 host session exposes a track holding two notes")
}

@MainActor
private func hostSteadyVoiceContext(_ report: CheckReport, route: DocumentSession?) {
    let id = "swiftcore/HostBehaviorChecks::seededContext"
    guard let route else {
        report.fail(id, "the route101 host session did not open for the steadiness search")
        return
    }
    let page = VelocityPage(baseFontPx: GridCameraPolicy.seedBaseFontPx)
    page.attach(session: route, palette: GridPalette())
    let font = GridCameraPolicy.seedBaseFontPx
    page.configureBody(
        width: fontPx(font, 30), height: fontPx(font, 9),
        rulerWidth: fontPx(font, 4), devicePixelRatio: 1,
        baseFontPx: font, dragDistance: page.dragDistance)
    // Mirror of the fork's candidate search: the first tick whose 120-tick
    // window holds its voice slot and name with strictly rising samples.
    var first: Tick? = nil
    var candidate: Tick = 0
    while candidate < 4096 && first == nil {
        page.refreshPlayhead(tick: Double(candidate), playing: true)
        let slot = page.context.slot
        let voice = page.context.map.voiceName
        var previousSample = route.timeline.sample(for: candidate)
        var steady = true
        var offset: Tick = 1
        while offset <= 120 {
            let tick = candidate + offset
            page.refreshPlayhead(tick: Double(tick), playing: true)
            let sample = route.timeline.sample(for: tick)
            if page.context.slot != slot || page.context.map.voiceName != voice
                || sample <= previousSample
            {
                steady = false
                break
            }
            previousSample = sample
            offset += 1
        }
        if steady {
            first = candidate
        }
        candidate += 1
    }
    report.expect(
        first != nil, cppID: id,
        message: "A007: the route101 host session holds a steady 120-tick voice context")
}
