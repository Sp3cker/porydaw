import Foundation
import PorydawApp
import PorydawCore

let drawerVelocityClickSelectionID = "swiftcore/VelocityClickSelection::clickSelection"
let drawerVelocityHitPriorityID = "swiftcore/VelocityHitPriority::hitPriority"

@MainActor
func drawerVelocityBlankClickDeselects(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let blankX = page.plotWidth - 1
    let blankY = page.axisModel.velocityToY(40)
    let consumed = page.pointerPress(x: blankX, y: blankY, surface: 1, button: 1, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityClickSelectionID, message: "a blank plot press is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a blank press holds a live gesture")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityClickSelectionID, message: "a blank press keeps the selection until release")
    report.expect(page.frozenPreview.isEmpty, cppID: drawerVelocityClickSelectionID, message: "a blank press previews nothing")
    _ = page.pointerRelease(x: blankX, y: blankY, button: 1)
    report.expect(fixture.session.selectedNoteOrder.isEmpty, cppID: drawerVelocityClickSelectionID, message: "a blank release clears the selection")
    report.expect(!page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a blank release ends the gesture")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityTransactionID, message: "deselecting on release writes nothing")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a blank click leaves every velocity captured")
    }
    for note in notes {
        report.expectEqual(Int(document.note(note.id)?.velocity ?? 0), fixture.handle(note)?.value ?? -1, cppID: drawerVelocityClickSelectionID, what: "a blank click republishes every captured value")
    }
}

@MainActor
func drawerVelocityGraduationClickEdits(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let maximum = page.axisModel.labels.first(where: { $0.velocity == 127 }) else {
        report.fail(drawerVelocityClickSelectionID, "the ruler published no 127 label")
        return
    }
    let expected = page.axisModel.rulerVelocityAt(y: maximum.y, labelHeight: page.axisModel.geometry.labelHeight)
    guard expected >= 1 else {
        report.fail(drawerVelocityClickSelectionID, "the 127 label row resolved no velocity")
        return
    }
    let baseline = drawerVelocityDocumentSnapshot(document)
    let untouched = document.note(notes[2].id)?.velocity
    let consumed = page.pointerPress(x: 10, y: maximum.y, surface: 0, button: 1, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityClickSelectionID, message: "a graduation press is consumed")
    report.expectEqual(expected, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityClickSelectionID, what: "a graduation click sets the first selected note")
    report.expectEqual(expected, Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityClickSelectionID, what: "a graduation click sets the second selected note")
    report.expectEqual(untouched, document.note(notes[2].id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a graduation click leaves the unselected note alone")
    report.expectEqual(baseline.revision + 1, document.revision, cppID: drawerVelocityTransactionID, what: "one graduation click makes one revision")
    report.expect(document.history.currentIdentity != baseline.identity, cppID: drawerVelocityTransactionID, message: "one graduation click makes one history entry")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityClickSelectionID, message: "a graduation click keeps the selection")
    let released = page.pointerRelease(x: 10, y: maximum.y, button: 1)
    report.expect(!released, cppID: drawerVelocityClickSelectionID, message: "the release after a graduation commit is inert")
    report.expectEqual(expected, fixture.handle(notes[0])?.value ?? -1, cppID: drawerVelocityClickSelectionID, what: "the first handle republishes the clicked graduation")
    report.expectEqual(expected, fixture.handle(notes[1])?.value ?? -1, cppID: drawerVelocityClickSelectionID, what: "the second handle republishes the clicked graduation")
}

@MainActor
func drawerVelocityClickBelowNodeCommits(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    let later = notes[2]
    fixture.session.setSelectedNotes([later.id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [later.id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let laterHandle = fixture.handle(later) else {
        report.fail(drawerVelocityClickSelectionID, "the fixture's later note has no published handle")
        return
    }
    let baseline = drawerVelocityDocumentSnapshot(document)
    let pressX = laterHandle.x
    var pressY = 0.0
    var pressPreview = 0
    var painted = false
    for velocity in [40, 80, 120, 20, 100, 60] {
        let y = page.axisModel.velocityToY(velocity)
        var clear = true
        for handle in fixture.handles {
            let dx = handle.x - pressX
            let dy = handle.y - y
            if dx * dx + dy * dy <= handle.hitRadius * handle.hitRadius {
                clear = false
            }
        }
        if !clear {
            continue
        }
        _ = page.pointerPress(x: pressX, y: y, surface: 1, button: 1, modifiers: 0)
        if let preview = page.frozenPreview[later.id], preview != later.velocity, fixture.session.selectedNoteOrder == [later.id] {
            pressY = y
            pressPreview = Int(preview)
            painted = true
            break
        }
        page.cancelSectionInteraction()
    }
    guard painted else {
        report.fail(drawerVelocityClickSelectionID, "no off-node press previewed without moving")
        return
    }
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "an off-node press holds a live gesture")
    report.expect(fixture.session.selectedNoteOrder == [later.id], cppID: drawerVelocityClickSelectionID, message: "an off-node press previews without changing the selection")
    _ = page.pointerRelease(x: pressX, y: pressY, button: 1)
    report.expectEqual(baseline.revision + 1, document.revision, cppID: drawerVelocityTransactionID, what: "one off-node click makes one revision")
    report.expect(document.history.currentIdentity != baseline.identity, cppID: drawerVelocityTransactionID, message: "one off-node click makes one history entry")
    report.expectEqual(pressPreview, Int(document.note(later.id)?.velocity ?? 0), cppID: drawerVelocityClickSelectionID, what: "the release commits the pressed preview")
    report.expectEqual(document.note(notes[0].id)?.velocity, notes[0].velocity, cppID: drawerVelocityClickSelectionID, what: "an off-node click leaves the first note alone")
    report.expectEqual(document.note(notes[1].id)?.velocity, notes[1].velocity, cppID: drawerVelocityClickSelectionID, what: "an off-node click leaves the second note alone")
    report.expect(fixture.session.selectedNoteOrder == [later.id], cppID: drawerVelocityClickSelectionID, message: "an off-node click keeps its own selection")
    report.expect(!page.hasGesture && page.frozenPreview.isEmpty, cppID: drawerVelocityClickSelectionID, message: "an off-node release ends the gesture")
}

@MainActor
func drawerVelocityBandExpandContract(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[2].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[2].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let first = fixture.handle(notes[0]), let second = fixture.handle(notes[1]), let third = fixture.handle(notes[2]) else {
        report.fail(drawerVelocityClickSelectionID, "the fixture's notes have no published handles")
        return
    }
    let contractedX = (second.x + third.x) / 2
    guard contractedX > second.x, contractedX < third.x, first.x < contractedX else {
        report.fail(drawerVelocityClickSelectionID, "the contracted band cannot split the published handles")
        return
    }
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let pressed = page.pointerPress(x: 0, y: 0, surface: 1, button: 2, modifiers: 0)
    report.expect(pressed, cppID: drawerVelocityClickSelectionID, message: "a band press is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a band press holds a live gesture")
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    _ = page.pointerMove(x: contractedX, y: 120, buttons: 2)
    _ = page.pointerRelease(x: contractedX, y: 120, button: 2)
    report.expect(fixture.session.selectedNotes == Set([notes[0].id, notes[1].id]), cppID: drawerVelocityClickSelectionID, message: "the contracted band keeps the covered pair and drops the later note")
    report.expect(!page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a band release ends the gesture")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityTransactionID, message: "a band selection writes nothing")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a band selection leaves every velocity captured")
    }
}

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
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    _ = page.pointerPress(x: target.x, y: target.y, surface: 1, button: 1, modifiers: 0)
    report.expect(fixture.session.selectedNoteOrder == [notes[1].id], cppID: drawerVelocityClickSelectionID, message: "pressing another node provisionally selects it")
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a provisional press holds a live gesture")
    page.cancelSectionInteraction()
    report.expect(!page.hasGesture && page.frozenPreview.isEmpty, cppID: drawerVelocityCancellationID, message: "cancelling clears the provisional gesture")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "cancelling restores selection membership and insertion order")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "cancelling writes nothing at all")
    let released = page.pointerRelease(x: target.x, y: target.y, button: 1)
    report.expect(!released, cppID: drawerVelocityClickSelectionID, message: "a release after cancellation is inert")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "a late release cannot revive the discarded selection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a cancelled press leaves every velocity captured")
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
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    _ = page.pointerPress(x: target.x, y: target.y, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a band press holds a live gesture")
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    page.cancelSectionInteraction()
    report.expect(!page.hasGesture, cppID: drawerVelocityCancellationID, message: "cancelling clears the live band")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "a cancelled band restores selection membership and insertion order")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "cancelling writes nothing at all")
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    let released = page.pointerRelease(x: 400, y: 120, button: 2)
    report.expect(!released, cppID: drawerVelocityClickSelectionID, message: "input after cancellation starts no band")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID, message: "input after cancellation cannot replace the restored selection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a cancelled band leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityPrimaryTrackSwitchCancels(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    guard fixture.document.addTrack(voice: 2) == 1 else {
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
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    _ = page.pointerPress(x: lead.x, y: lead.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: lead.x, y: lead.y - 30, buttons: 1)
    report.expect(page.frozenPreview[notes[0].id] != nil, cppID: drawerVelocityClickSelectionID, message: "a live drag previews the pressed note")
    report.expect(page.frozenPreview[notes[2].id] != nil, cppID: drawerVelocityClickSelectionID, message: "a live drag previews every selected target")
    report.expect(page.hasGesture && page.interactionActive, cppID: drawerVelocityClickSelectionID, message: "a live drag reports an active gesture")
    fixture.session.adjustTrackScope(track: 1, action: .plain)
    page.refreshFromDocument()
    report.expectEqual(2, page.contextSlot, cppID: drawerVelocityCancellationID,
                       what: "the new primary track presents its program")
    report.expect(!page.hasGesture, cppID: drawerVelocityCancellationID, message: "a primary-track switch ends the live gesture")
    report.expect(page.frozenPreview.isEmpty, cppID: drawerVelocityCancellationID, message: "a primary-track switch clears every preview")
    report.expect(fixture.session.selectedNoteOrder.isEmpty, cppID: drawerVelocityCancellationID, message: "a primary-track replacement clears rather than revives the old selection")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "a primary-track switch writes nothing at all")
    let released = page.pointerRelease(x: lead.x, y: lead.y - 30, button: 1)
    report.expect(!released, cppID: drawerVelocityClickSelectionID, message: "a release after the switch is inert")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityCancellationID, message: "a late release still writes nothing")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID, what: "a cancelled drag leaves every velocity captured")
    }
    report.expect(page.frozenPreview.isEmpty, cppID: drawerVelocityCancellationID, message: "a late release previews nothing")
}

@MainActor
func drawerVelocityLifecycleCancellation(_ report: CheckReport, session: DocumentSession,
                                         service: ProjectService) {
    let routes = ["page-switch", "drawer-hide", "pointer-ungrabbed", "focus-loss",
                  "window-deactivated", "hidden", "escape"]
    for route in routes {
        let fixture = drawerVelocityVelocityFixture(session: session, service: service)
        guard let note = fixture.notes.first, let handle = fixture.handle(note) else {
            report.fail(drawerVelocityCancellationID, "\(route): no draggable note handle")
            continue
        }
        let page = fixture.page
        let drawer = EditorDrawerPresenter()
        drawer.attachSection(page)
        drawer.restoreStoredPreferences(velocityVisible: 1, velocityHeight: 0,
                                        automationVisible: route == "page-switch" ? 1 : -1,
                                        automationHeight: 0,
                                        voiceChangesVisible: -1, voiceChangesHeight: 0,
                                        activePage: DrawerSectionKind.velocity.rawValue)
        if route == "page-switch" {
            drawer.attachSection(AutomationPage(baseFontPx: 13))
        }
        fixture.session.setSelectedNotes([note.id])
        page.refreshFromDocument()
        let baseline = drawerVelocityDocumentSnapshot(fixture.document)
        let bytes = coreTimeBytes(fixture.document)
        let undoCount = fixture.document.history.undoCount
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        guard page.hasGesture && page.interactionActive && page.frozenPreview[note.id] != nil else {
            report.fail(drawerVelocityCancellationID, "\(route): held drag did not preview")
            continue
        }
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
        report.expect(drawerVelocityDocumentSnapshot(fixture.document) == baseline
                      && fixture.document.history.undoCount == undoCount
                      && coreTimeBytes(fixture.document) == bytes,
                      cppID: drawerVelocityCancellationID,
                      message: "\(route): document bytes, revision and undo depth remain unchanged")
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
        callbacks: DocumentWorkspace.Callbacks(
            addTrackRequested: {}, changeTrackVoiceRequested: { _ in },
            revealTrackVoiceRequested: { _ in }, headerContextMenuRequested: { _, _ in },
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
        _ = try drawerVelocityRunBlocking {
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
}

@MainActor
func drawerVelocityStackedHitPriority(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    let overlapIDs = try? document.addNotes([NewNote(track: 0, tick: 12, pitch: 61, duration: 24, velocity: notes[0].velocity)])
    guard let overlapID = overlapIDs?.first else {
        report.fail(drawerVelocityHitPriorityID, "the overlap note was not inserted")
        return
    }
    page.refreshFromDocument()
    guard let overlap = document.notes(in: 0).first(where: { $0.id == overlapID }) else {
        report.fail(drawerVelocityHitPriorityID, "the overlap note did not resolve")
        return
    }
    guard let circles = fixture.handle(overlap), let stem = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityHitPriorityID, "the stacked notes have no published handles")
        return
    }
    guard abs(circles.y - stem.y) < 0.001 else {
        report.fail(drawerVelocityHitPriorityID, "the overlap published off the target level")
        return
    }
    let gapX = circles.x - stem.x
    let gapY = circles.y - stem.y
    guard gapX * gapX + gapY * gapY > circles.hitRadius * circles.hitRadius else {
        report.fail(drawerVelocityHitPriorityID, "the overlap circle covers the target node")
        return
    }
    guard circles.x > stem.x, circles.x < stem.endX else {
        report.fail(drawerVelocityHitPriorityID, "the overlap sits outside the target stem")
        return
    }
    report.expectEqual(Int(notes[0].velocity), Int(document.note(overlapID)?.velocity ?? 0), cppID: drawerVelocityHitPriorityID, what: "the overlap note carries the target velocity")
    let baseline = drawerVelocityDocumentSnapshot(document)
    let capturedOverlap = document.note(overlapID)?.velocity
    let captured = notes.map { document.note($0.id)?.velocity }
    fixture.session.setSelectedNotes([overlapID])
    page.refreshFromDocument()
    report.expect(fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID, message: "the overlap selection latches before the press")
    let selectedPress = page.pointerPress(x: circles.x, y: circles.y, surface: 1, button: 1, modifiers: 0)
    report.expect(selectedPress, cppID: drawerVelocityHitPriorityID, message: "pressing the selected circle is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "pressing the selected circle holds a live gesture")
    report.expect(fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID, message: "pressing the selected circle keeps it over the stem")
    _ = page.pointerRelease(x: circles.x, y: circles.y, button: 1)
    report.expect(fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID, message: "releasing the selected circle keeps it")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID, message: "a circle-over-stem click writes nothing")
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityHitPriorityID, message: "the stem selection latches before the press")
    let unselectedPress = page.pointerPress(x: circles.x, y: circles.y, surface: 1, button: 1, modifiers: 0)
    report.expect(unselectedPress, cppID: drawerVelocityHitPriorityID, message: "pressing the unselected circle is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "pressing the unselected circle holds a live gesture")
    report.expect(fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID, message: "an unselected circle wins over a selected stem")
    _ = page.pointerRelease(x: circles.x, y: circles.y, button: 1)
    report.expect(fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID, message: "releasing the winning circle keeps it")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID, message: "a circle-over-stem reselect writes nothing")
    report.expectEqual(capturedOverlap, document.note(overlapID)?.velocity, cppID: drawerVelocityHitPriorityID, what: "hit-priority clicks leave the overlap velocity captured")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID, what: "hit-priority clicks leave every velocity captured")
    }
}

@MainActor
func drawerVelocityStemPressKeepsSelection(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id] else {
        report.fail(drawerVelocityHitPriorityID, "the press-time selection did not latch")
        return
    }
    guard let stem = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityHitPriorityID, "the fixture's target note has no published handle")
        return
    }
    let stemX = stem.x + stem.hitRadius + 2
    guard stem.endX - stem.x >= stem.hitRadius + 3 else {
        report.fail(drawerVelocityHitPriorityID, "the target stem spans less than one hit diameter")
        return
    }
    for handle in fixture.handles where handle.noteIdText != stem.noteIdText {
        let dx = handle.x - stemX
        let dy = handle.y - stem.y
        if dx * dx + dy * dy <= handle.hitRadius * handle.hitRadius {
            report.fail(drawerVelocityHitPriorityID, "the stem point touches another node")
            return
        }
    }
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let consumed = page.pointerPress(x: stemX, y: stem.y, surface: 1, button: 1, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityHitPriorityID, message: "a stem-only press is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "a stem-only press holds a live gesture")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityHitPriorityID, message: "a stem-only press keeps the selected stem")
    _ = page.pointerRelease(x: stemX, y: stem.y, button: 1)
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityHitPriorityID, message: "releasing the stem keeps it")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID, message: "a stem-only click writes nothing")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID, what: "a stem-only click leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityMovedNodeNoClickThrough(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder.isEmpty else {
        report.fail(drawerVelocityHitPriorityID, "the selection did not clear")
        return
    }
    guard let near = fixture.handle(notes[1]), let far = fixture.handle(notes[2]) else {
        report.fail(drawerVelocityHitPriorityID, "the fixture's notes have no published handles")
        return
    }
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    _ = page.pointerPress(x: far.x, y: far.y, surface: 1, button: 1, modifiers: 0)
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id], cppID: drawerVelocityHitPriorityID, message: "pressing a node selects it")
    report.expect(page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "pressing a node holds a live gesture")
    var step = 0.0
    for candidate in [3.0, 4.0, 5.0, 2.0, -3.0, -4.0] {
        if page.axisModel.yToLevel(far.y + candidate) == page.axisModel.yToLevel(far.y), abs(candidate) > far.hitRadius / 6 {
            step = candidate
            break
        }
    }
    guard step != 0 else {
        report.fail(drawerVelocityHitPriorityID, "no same-level step leaves the activation distance")
        return
    }
    let endX = near.x
    let endY = far.y + step
    _ = page.pointerMove(x: endX, y: endY, buttons: 1)
    report.expectEqual(Int(notes[2].velocity), Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityHitPriorityID, what: "a same-level move previews the captured velocity")
    _ = page.pointerRelease(x: endX, y: endY, button: 1)
    report.expect(!page.hasGesture && page.frozenPreview.isEmpty, cppID: drawerVelocityHitPriorityID, message: "a same-value move ends the gesture with no preview left")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityTransactionID, message: "a same-value move writes nothing")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id], cppID: drawerVelocityHitPriorityID, message: "releasing over another column does not click through")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID, what: "a moved node leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityRightPressPreservesGroup(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id] else {
        report.fail(drawerVelocityHitPriorityID, "the press-time selection did not latch")
        return
    }
    guard let lead = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityHitPriorityID, "the fixture's lead note has no published handle")
        return
    }
    let baseline = drawerVelocityDocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let consumed = page.pointerPress(x: lead.x, y: lead.y, surface: 1, button: 2, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityHitPriorityID, message: "a secondary press on the group is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "a secondary press holds a live gesture")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityHitPriorityID, message: "a secondary press preserves the selected group")
    _ = page.pointerRelease(x: lead.x, y: lead.y, button: 2)
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityHitPriorityID, message: "a secondary release preserves the selected group")
    report.expect(!page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "a secondary release ends the gesture")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID, message: "a secondary click writes nothing")
    for (index, note) in notes.enumerated() {
        report.expectEqual(captured[index], document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID, what: "a secondary click leaves every velocity captured")
    }
}
