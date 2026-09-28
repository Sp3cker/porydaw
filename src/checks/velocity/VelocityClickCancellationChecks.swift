import Foundation
import PorydawApp
import PorydawCore

@MainActor
func drawerVelocityPressCancelRestores(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[2].id, notes[0].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let target = fixture.handle(notes[1]) else {
        report.fail(drawerVelocityClickSelectionID, "the fixture's target note has no published handle")
        return
    }
    let baseline = DocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let depth = document.history.undoCount
    _ = page.pointerPress(x: target.x, y: target.y, surface: 1, button: 1, modifiers: 0)
    report.expect(fixture.session.selectedNoteOrder == [notes[1].id], cppID: drawerVelocityClickSelectionID, message: "pressing another node provisionally selects it")
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a provisional press holds a live gesture")
    page.cancelSectionInteraction()
    report.expect(!page.hasGesture && page.frozenPreview.isEmpty, cppID: drawerVelocityCancellationID, message: "cancelling clears the provisional gesture")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "cancelling restores selection membership and insertion order")
    report.expect(DocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "cancelling writes nothing at all")
    report.expectEqual(expected: depth, actual: document.history.undoCount, cppID: drawerVelocityCancellationID,
                       what: "a cancelled gesture leaves the undo depth unchanged")
    report.expectEqual(expected: [100, 64, 32], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityCancellationID, what: "an escaped drag leaves the timeline projection untouched")
    let released = page.pointerRelease(x: target.x, y: target.y, button: 1)
    report.expect(!released, cppID: drawerVelocityClickSelectionID, message: "a release after cancellation is inert")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "a late release cannot revive the discarded selection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a cancelled press leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityBandCancelRestores(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[2].id, notes[0].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let target = fixture.handle(notes[1]) else {
        report.fail(drawerVelocityClickSelectionID, "the fixture's target note has no published handle")
        return
    }
    let baseline = DocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let depth = document.history.undoCount
    _ = page.pointerPress(x: target.x, y: target.y, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a band press holds a live gesture")
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    page.cancelSectionInteraction()
    report.expect(!page.hasGesture, cppID: drawerVelocityCancellationID, message: "cancelling clears the live band")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "a cancelled band restores selection membership and insertion order")
    report.expect(DocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "cancelling writes nothing at all")
    report.expectEqual(expected: depth, actual: document.history.undoCount, cppID: drawerVelocityCancellationID,
                       what: "a cancelled gesture leaves the undo depth unchanged")
    report.expectEqual(expected: [100, 64, 32], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityCancellationID, what: "an escaped drag leaves the timeline projection untouched")
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    let released = page.pointerRelease(x: 400, y: 120, button: 2)
    report.expect(!released, cppID: drawerVelocityClickSelectionID, message: "input after cancellation starts no band")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "input after cancellation cannot replace the restored selection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a cancelled band leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityPrimaryTrackSwitchCancels(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(drawerVelocityCancellationID, "the staged wave bank fixture is unavailable")
        return
    }
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftcore-velocity-switch-\(UUID().uuidString)", isDirectory: true)
    let waveService = ProjectService()
    defer {
        do {
            try runBlocking { await waveService.close() }
        } catch {
            report.fail(drawerVelocityCancellationID, "could not close the wave bank fixture: \(error)")
        }
        // Scratch removal is best-effort after the isolated service closes.
        try? FileManager.default.removeItem(at: scratch)
    }
    let waveSession: DocumentSession
    do {
        try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: scratch)
        try runBlocking { try await waveService.open(root: scratch.path) }
        let loaded = try runBlocking { try await waveService.openSong(label: "mus_gym") }
        let waveDocument = SongDocument(file: drawerVelocityVelocityPageFixture(),
                                        config: loaded.config, source: loaded.source,
                                        trackBudget: loaded.trackBudget)
        waveSession = DocumentSession(document: waveDocument, service: waveService,
                                      lease: loaded.bank, slots: loaded.bankSlots,
                                      dirty: loaded.bankDirty, loadName: loaded.bankLoadName)
    } catch {
        report.fail(drawerVelocityCancellationID, "could not load the staged wave bank fixture: \(error)")
        return
    }
    let fixture = drawerVelocityVelocityFixture(session: waveSession, service: waveService)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    guard fixture.document.addTrack(voice: 6) == 1 else {
        report.fail(drawerVelocityCancellationID, "the primary-track replacement needs a second track")
        return
    }
    fixture.session.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let lead = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityClickSelectionID, "the fixture's lead note has no published handle")
        return
    }
    let baseline = DocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let depth = document.history.undoCount
    let before = notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
    _ = page.pointerPress(x: lead.x, y: lead.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: lead.x, y: lead.y - 30, buttons: 1)
    report.expect(page.frozenPreview[notes[0].id] != nil, cppID: drawerVelocityClickSelectionID, message: "a live drag previews the pressed note")
    report.expect(page.frozenPreview[notes[2].id] != nil, cppID: drawerVelocityClickSelectionID, message: "a live drag previews every selected target")
    report.expect(page.hasGesture && page.interactionActive, cppID: drawerVelocityClickSelectionID, message: "a live drag reports an active gesture")
    report.expectEqual(expected: before, actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityCancellationID, what: "a drag preview holds the timeline projection at the captured velocities")
    fixture.session.adjustTrackScope(track: 1, action: .plain)
    page.refreshFromDocument()
    report.expectEqual(expected: 6, actual: page.contextSlot, cppID: drawerVelocityCancellationID,
                       what: "the new primary track presents its program")
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode,
                       cppID: drawerVelocityCancellationID,
                       what: "the replacement PSG track presents its intrinsic axis")
    report.expectEqual(expected: 5, actual: page.axisModel.graduations.count,
                       cppID: drawerVelocityCancellationID,
                       what: "the replacement PSG axis presents exactly five graduations")
    report.expect(!page.hasGesture, cppID: drawerVelocityCancellationID, message: "a primary-track switch ends the live gesture")
    report.expect(page.frozenPreview.isEmpty, cppID: drawerVelocityCancellationID, message: "a primary-track switch clears every preview")
    report.expect(fixture.session.selectedNoteOrder.isEmpty, cppID: drawerVelocityCancellationID, message: "a primary-track replacement clears rather than revives the old selection")
    report.expect(DocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "a primary-track switch writes nothing at all")
    report.expectEqual(expected: depth, actual: document.history.undoCount, cppID: drawerVelocityCancellationID,
                       what: "a cancelled gesture leaves the undo depth unchanged")
    report.expectEqual(expected: before, actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityCancellationID, what: "an escaped drag leaves the timeline projection untouched")
    let released = page.pointerRelease(x: lead.x, y: lead.y - 30, button: 1)
    report.expect(!released, cppID: drawerVelocityClickSelectionID, message: "a release after the switch is inert")
    report.expect(DocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "a late release still writes nothing")
    for (index, note) in notes.enumerated() {
        report.expectEqual(expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a cancelled drag leaves every velocity captured")
    }
    report.expect(page.frozenPreview.isEmpty, cppID: drawerVelocityCancellationID, message: "a late release previews nothing")
}

@MainActor
func drawerVelocityLifecycleCancellation(_ report: CheckReport, session: DocumentSession,
                                         service: ProjectService) {
    let routes = ["page-switch", "drawer-hide", "pointer-ungrabbed", "focus-loss",
                  "window-deactivated", "hidden", "escape"]
    let preferences = PreferencesStore()
    for route in routes {
        let fixture = drawerVelocityVelocityFixture(session: session, service: service)
        guard let note = fixture.notes.first, let handle = fixture.handle(note) else {
            report.fail(drawerVelocityCancellationID, "\(route): no draggable note handle")
            continue
        }
        _ = preferences.resetPreferences()
        preferences.setBool(key: "editorDrawer.velocityVisible", value: true)
        preferences.setInt(key: "editorDrawer.velocityHeight", value: 0)
        if route == "page-switch" {
            preferences.setBool(key: "editorDrawer.automationVisible", value: true)
        }
        preferences.setInt(key: "editorDrawer.automationHeight", value: 0)
        preferences.setInt(key: "editorDrawer.voiceChangesHeight", value: 0)
        preferences.setString(key: "editorDrawer.activePage", value: "velocity")
        let page = fixture.page
        let drawer = EditorDrawerPresenter()
        drawer.attachSection(page)
        drawer.applyChrome(EditorViewStateCodec.loadChrome(store: preferences))
        if route == "page-switch" {
            drawer.attachSection(AutomationPage(baseFontPx: 13))
        }
        fixture.session.setSelectedNotes([note.id])
        page.refreshFromDocument()
        let baseline = DocumentSnapshot(fixture.document)
        let bytes = coreTimeBytes(fixture.document)
        let undoCount = fixture.document.history.undoCount
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        guard page.hasGesture && page.interactionActive && page.frozenPreview[note.id] != nil else {
            report.fail(drawerVelocityCancellationID, "\(route): held drag did not preview")
            continue
        }
        report.expectEqual(expected: Int(note.velocity),
                           actual: drawerVelocityTimelineVelocity(fixture.session, note.id),
                           cppID: drawerVelocityCancellationID,
                           what: "\(route): a held drag preserves the timeline projection")
        switch route {
        case "page-switch":
            drawer.toggleSection(kind: DrawerSectionKind.automation.rawValue,
                                 drawerOwnsFocus: true)
        case "drawer-hide":
            drawer.setSectionVisible(kind: DrawerSectionKind.velocity.rawValue,
                                     visible: false, drawerOwnsFocus: true)
        case "pointer-ungrabbed":
            drawer.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
        case "focus-loss":
            drawer.inputCancelled(reason: GridCancelReason.focusLost.rawValue)
        case "window-deactivated":
            drawer.inputCancelled(reason: GridCancelReason.windowDeactivated.rawValue)
        case "hidden":
            drawer.inputCancelled(reason: GridCancelReason.hidden.rawValue)
        case "escape":
            report.expect(page.handleEscape(), cppID: drawerVelocityCancellationID,
                          message: "escape claims the live velocity drag")
        default:
            break
        }
        report.expect(!page.hasGesture && !page.interactionActive && page.frozenPreview.isEmpty,
                      cppID: drawerVelocityCancellationID,
                      message: "\(route): cancellation clears the active preview")
        report.expect(fixture.session.selectedNoteOrder == [note.id],
                      cppID: drawerVelocityCancellationID,
                      message: "\(route): cancellation preserves the note selection")
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        report.expect(!page.pointerRelease(x: handle.x, y: handle.y - 30, button: 1),
                      cppID: drawerVelocityCancellationID,
                      message: "\(route): held release cannot commit the cancelled gesture")
        report.expect(DocumentSnapshot(fixture.document) == baseline
                      && fixture.document.history.undoCount == undoCount
                      && coreTimeBytes(fixture.document) == bytes,
                      cppID: drawerVelocityCancellationID,
                      message: "\(route): document bytes, revision and undo depth remain unchanged")
        report.expectEqual(expected: Int(note.velocity),
                           actual: drawerVelocityTimelineVelocity(fixture.session, note.id),
                           cppID: drawerVelocityCancellationID,
                           what: "\(route): cancellation leaves the timeline projection untouched")
    }
    let bankFixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard let note = bankFixture.notes.first,
          let originalVoice = bankFixture.session.bankSlots.first?.voice else {
        report.fail(drawerVelocityCancellationID, "bank transition fixture lacks its note or editable voice")
        return
    }
    let audio: NativeAudio
    do {
        audio = try NativeAudio()
    } catch {
        report.fail(drawerVelocityCancellationID, "bank transition cannot create audio: \(error)")
        return
    }
    let playhead = SharedPlayheadPresenter()
    let guides = PlayheadGuidesPresenter()
    let eventList = EventListPresenter()
    let workspace = DocumentWorkspace(
        session: bankFixture.session, audio: audio, playhead: playhead,
        playheadGuides: guides, eventList: eventList, palette: GridPalette(),
        typography: Typography(baseFontPx: 13), callbacks: DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { _ in },
            revealTrackVoiceRequested: { _ in },
            gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
            publicationFailed: { _ in }, timeSignaturePromptInvalidated: { _, _ in }))
    defer {
        workspace.teardown()
        withExtendedLifetime((audio, playhead, guides, eventList)) {}
    }
    workspace.activate()
    let page = workspace.velocityPage
    page.configureBody(width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1,
                       baseFontPx: 13, dragDistance: 10)
    bankFixture.session.setSelectedNotes([note.id])
    guard let handle = page.publishedHandlesSnapshot.first(where: {
        $0.noteIdText == "\(note.id.rawValue)"
    }) else {
        report.fail(drawerVelocityCancellationID, "bank transition fixture lacks a drawn handle")
        return
    }
    let baselineRevision = bankFixture.document.revision
    let bytes = coreTimeBytes(bankFixture.document)
    let velocity = bankFixture.document.note(note.id)?.velocity
    _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
    guard page.hasGesture && page.frozenPreview[note.id] != nil else {
        report.fail(drawerVelocityCancellationID, "bank transition drag did not preview")
        return
    }
    var editedVoice = originalVoice
    editedVoice.pan = editedVoice.pan == 15 ? 14 : 15
    do {
        _ = try runBlocking {
            try await bankFixture.session.applyBankEdit(slot: 0, value: editedVoice,
                                                        expected: originalVoice)
        }
    } catch {
        report.fail(drawerVelocityCancellationID, "bank transition rejected the edit: \(error)")
        return
    }
    report.expect(bankFixture.session.bankDirty
                  && bankFixture.session.bankSlots[0].voice == editedVoice,
                  cppID: drawerVelocityCancellationID,
                  message: "the genuine bank edit advances bank state")
    report.expect(!page.hasGesture && !page.interactionActive && page.frozenPreview.isEmpty,
                  cppID: drawerVelocityCancellationID,
                  message: "a bank edit cancels the held velocity preview through its workspace")
    report.expect(bankFixture.session.selectedNoteOrder == [note.id],
                  cppID: drawerVelocityCancellationID,
                  message: "a bank edit preserves the held note selection")
    report.expect(!page.pointerRelease(x: handle.x, y: handle.y - 30, button: 1),
                  cppID: drawerVelocityCancellationID,
                  message: "the bank edit makes the late release inert")
    report.expect(bankFixture.document.revision == baselineRevision
                  && coreTimeBytes(bankFixture.document) == bytes
                  && bankFixture.document.note(note.id)?.velocity == velocity,
                  cppID: drawerVelocityCancellationID,
                  message: "the bank edit leaves song revision, note velocity and MIDI bytes unchanged")

    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(drawerVelocityCancellationID, "voicegroup switch fixture root is unavailable")
        return
    }
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftcore-velocity-voicegroup-\(UUID().uuidString)", isDirectory: true)
    let switchService = ProjectService()
    defer {
        do {
            try runBlocking { await switchService.close() }
        } catch {
            report.fail(drawerVelocityCancellationID, "could not close the voicegroup switch service: \(error)")
        }
        // Scratch removal is best-effort after the isolated service closes.
        try? FileManager.default.removeItem(at: scratch)
    }
    let switchSession: DocumentSession
    do {
        try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: scratch)
        try runBlocking { try await switchService.open(root: scratch.path) }
        let loaded = try runBlocking { try await switchService.openSong(label: "mus_gym") }
        let switchDocument = SongDocument(file: drawerVelocityVelocityPageFixture(),
                                          config: loaded.config, source: loaded.source,
                                          trackBudget: loaded.trackBudget)
        switchSession = DocumentSession(document: switchDocument, service: switchService,
                                        lease: loaded.bank, slots: loaded.bankSlots,
                                        dirty: loaded.bankDirty, loadName: loaded.bankLoadName)
    } catch {
        report.fail(drawerVelocityCancellationID, "could not stage the alternate voicegroup: \(error)")
        return
    }
    let switchFixture = drawerVelocityVelocityFixture(session: switchSession, service: switchService)
    guard let switchNote = switchFixture.notes.first else {
        report.fail(drawerVelocityCancellationID, "voicegroup switch has no note")
        return
    }
    let switchAudio: NativeAudio
    do {
        switchAudio = try NativeAudio()
    } catch {
        report.fail(drawerVelocityCancellationID, "voicegroup switch cannot create audio: \(error)")
        return
    }
    let switchPlayhead = SharedPlayheadPresenter()
    let switchGuides = PlayheadGuidesPresenter()
    let switchEventList = EventListPresenter()
    let switchWorkspace = DocumentWorkspace(
        session: switchFixture.session, audio: switchAudio, playhead: switchPlayhead,
        playheadGuides: switchGuides, eventList: switchEventList, palette: GridPalette(),
        typography: Typography(baseFontPx: 13), callbacks: DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { _ in },
            revealTrackVoiceRequested: { _ in },
            gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
            publicationFailed: { _ in }, timeSignaturePromptInvalidated: { _, _ in }))
    defer {
        switchWorkspace.teardown()
        withExtendedLifetime((switchAudio, switchPlayhead, switchGuides, switchEventList)) {}
    }
    switchWorkspace.activate()
    let switchPage = switchWorkspace.velocityPage
    switchPage.configureBody(width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1,
                             baseFontPx: 13, dragDistance: 10)
    switchFixture.session.setSelectedNotes([switchNote.id])
    guard let switchHandle = switchPage.publishedHandlesSnapshot.first(where: {
        $0.noteIdText == "\(switchNote.id.rawValue)"
    }), switchFixture.document.state.config.voicegroupArgument == "_fixture_rich" else {
        report.fail(drawerVelocityCancellationID, "voicegroup switch needs the original bank and a drawn note")
        return
    }
    let switchRevision = switchFixture.document.revision
    let switchUndoCount = switchFixture.document.history.undoCount
    let switchBytes = coreTimeBytes(switchFixture.document)
    _ = switchPage.pointerPress(x: switchHandle.x, y: switchHandle.y,
                                surface: 1, button: 1, modifiers: 0)
    _ = switchPage.pointerMove(x: switchHandle.x, y: switchHandle.y - 30, buttons: 1)
    guard switchPage.hasGesture && switchPage.interactionActive
        && switchPage.frozenPreview[switchNote.id] != nil else {
        report.fail(drawerVelocityCancellationID, "voicegroup switch drag did not stage a preview")
        return
    }
    do {
        try runBlocking { try await switchFixture.session.selectVoicegroup("_fixture_alt") }
    } catch {
        report.fail(drawerVelocityCancellationID, "voicegroup switch failed to load its alternate bank: \(error)")
        return
    }
    report.expect(switchFixture.session.bankLoadName == "fixture_alt",
                  cppID: drawerVelocityCancellationID,
                  message: "the dock switch adopts the alternate voicegroup")
    report.expect(!switchPage.hasGesture && !switchPage.interactionActive,
                  cppID: drawerVelocityCancellationID,
                  message: "A114 voicegroup replacement ends the held velocity gesture")
    report.expect(coreTimeBytes(switchFixture.document) == switchBytes,
                  cppID: drawerVelocityCancellationID,
                  message: "A115 voicegroup replacement leaves the MIDI bytes unchanged")
    report.expect(switchFixture.document.revision == switchRevision + 1,
                  cppID: drawerVelocityCancellationID,
                  message: "A116 voicegroup replacement advances revision only for its config edit")
    report.expect(switchFixture.document.history.undoCount == switchUndoCount + 1,
                  cppID: drawerVelocityCancellationID,
                  message: "A117 voicegroup replacement adds only its config undo entry")
    report.expect(switchPage.frozenPreview.isEmpty,
                  cppID: drawerVelocityCancellationID,
                  message: "A118 voicegroup replacement clears the held velocity preview")
    report.expect(switchFixture.session.selectedNoteOrder == [switchNote.id],
                  cppID: drawerVelocityCancellationID,
                  message: "A120 voicegroup replacement preserves the selected note")
    report.expect(!switchPage.pointerRelease(x: switchHandle.x, y: switchHandle.y - 30, button: 1),
                  cppID: drawerVelocityCancellationID,
                  message: "the late release after voicegroup replacement is inert")
    report.expect(switchFixture.document.notes(in: 0).map(\.velocity) == [100, 64, 32],
                  cppID: drawerVelocityCancellationID,
                  message: "voicegroup replacement cannot commit any staged note velocity")
    do {
        let undone = try runBlocking { try await switchFixture.session.undo() }
        report.expect(undone && switchFixture.document.state.config.voicegroupArgument == "_fixture_rich"
                      && switchFixture.document.notes(in: 0).map(\.velocity) == [100, 64, 32],
                      cppID: drawerVelocityCancellationID,
                      message: "undoing the switch reverts its config without undoing a velocity edit")
    } catch {
        report.fail(drawerVelocityCancellationID, "could not undo the voicegroup switch: \(error)")
    }
}
