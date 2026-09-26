import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with tst_velocityediting.cpp.
// Entry order remains in VelocityPageChecks.swift.

@MainActor
func drawerVelocityGestureTransactions(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityTransactionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document

    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    let baseline = DocumentSnapshot(document)
    let dragDepth = document.history.undoCount
    let dragPublications = drawerVelocityPublicationCounter(session: fixture.session)
    let before = fixture.handle(notes[0])?.y ?? 0
    fixture.drag(notes[0], dy: -24)
    let committed = DocumentSnapshot(document)
    let committedVelocities = [notes[0], notes[1]].map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
    report.expectEqual(expected: [notes[0], notes[1]].map { Int(document.note($0.id)?.velocity ?? 0) },
                       actual: committedVelocities, cppID: drawerVelocityTransactionID,
                       what: "a released drag republishes the staged velocities into the timeline projection")
    report.expectEqual(expected: dragDepth + 1, actual: document.history.undoCount,
                       cppID: drawerVelocityTransactionID, what: "one release grows the undo depth by exactly one")
    report.expectEqual(expected: 1, actual: dragPublications.document, cppID: drawerVelocityTransactionID,
                       what: "one release publishes exactly one document change")
    report.expectEqual(expected: 1, actual: dragPublications.dirty, cppID: drawerVelocityTransactionID,
                       what: "one release publishes exactly one dirty change")
    report.expectEqual(expected: baseline.revision + 1, actual: committed.revision, cppID: drawerVelocityTransactionID,
                       what: "one released drag advances the document revision once")
    report.expect(committed.identity != baseline.identity, cppID: drawerVelocityTransactionID,
                  message: "one released drag makes exactly one history entry")
    report.expect(committed.canUndo && !baseline.canUndo, cppID: drawerVelocityTransactionID,
                  message: "the drag's entry becomes undoable")
    report.expect(document.note(notes[0].id)?.velocity != notes[0].velocity, cppID: drawerVelocityTransactionID,
                  message: "the drag's commit reached the document")
    report.expect(document.note(notes[1].id)?.velocity != notes[1].velocity, cppID: drawerVelocityTransactionID,
                  message: "every selected target moved with the gesture")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityTransactionID,
                  message: "a released gesture clears its preview")
    report.expect(fixture.handle(notes[0])?.y != before, cppID: drawerVelocityProjectionID,
                  message: "the published handle follows the committed value (before \(before) "
                      + "after \(fixture.handle(notes[0])?.y ?? -1) velocity "
                      + "\(document.note(notes[0].id)?.velocity ?? 0) level "
                      + "\(fixture.handle(notes[0])?.level ?? -99)")

    _ = try? runBlocking { try await fixture.session.undo() }
    report.expectEqual(expected: Int(notes[0].velocity), actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: drawerVelocityHistoryID, what: "Undo restores the captured velocity")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0),
                       cppID: drawerVelocityHistoryID, what: "Undo restores every target of the transaction")
    report.expectEqual(expected: [100, 64, 32], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityHistoryID, what: "undo restores the timeline projection")
    page.refreshFromDocument()
    report.expectEqual(expected: 3, actual: fixture.handles.count, cppID: drawerVelocityHistoryID,
                       what: "Undo rebuilds the page without losing its handles")
    _ = try? runBlocking { try await fixture.session.redo() }
    report.expectEqual(expected: committed.identity, actual: DocumentSnapshot(document).identity, cppID: drawerVelocityHistoryID,
                       what: "Redo restores the committed history identity")
    report.expectEqual(expected: committedVelocities,
                       actual: [notes[0], notes[1]].map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityHistoryID, what: "redo restores the committed timeline projection")
    _ = try? runBlocking { try await fixture.session.undo() }

    // A press that never leaves the activation distance is a selection, not an
    // edit: no preview, no history.
    let pointerBaseline = DocumentSnapshot(document)
    let pointerDepth = document.history.undoCount
    fixture.drag(notes[0], dy: 0)
    report.expectEqual(expected: pointerBaseline.revision, actual: DocumentSnapshot(document).revision,
                       cppID: drawerVelocityTransactionID, what: "a stationary click records no history")
    report.expectEqual(expected: pointerDepth, actual: document.history.undoCount,
                       cppID: drawerVelocityTransactionID, what: "a cancelled gesture leaves the undo depth unchanged")
    report.expect(fixture.session.selectedNotes == [notes[0].id], cppID: drawerVelocityTransactionID,
                  message: "a stationary click selects only its own note")

    // Escape cancels: preview clears, nothing is written, the press-time
    // selection returns.
    fixture.session.setSelectedNotes([notes[2].id, notes[0].id])
    page.refreshFromDocument()
    let cancelBaseline = DocumentSnapshot(document)
    let cancelDepth = document.history.undoCount
    let cancelProjection = notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
    let cancelPublications = drawerVelocityPublicationCounter(session: fixture.session)
    if let handle = fixture.handle(notes[0]) {
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        report.expect(!page.frozenPreview.isEmpty, cppID: drawerVelocityTransactionID,
                      message: "a live drag previews before release")
        report.expect(page.interactionActive, cppID: drawerVelocityTransactionID,
                      message: "a live drag reports an active interaction")
        report.expectEqual(expected: cancelProjection,
                           actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                           cppID: drawerVelocityCancellationID,
                           what: "a drag preview holds the timeline projection at the captured velocities")
        report.expectEqual(expected: 0, actual: cancelPublications.document,
                           cppID: drawerVelocityCancellationID, what: "a held drag publishes no document change")
        report.expectEqual(expected: 0, actual: cancelPublications.dirty,
                           cppID: drawerVelocityCancellationID, what: "a held drag publishes no dirty change")
        report.expect(page.handleEscape(), cppID: drawerVelocityCancellationID,
                      message: "Escape is claimed while a gesture is live")
    }
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityCancellationID,
                  message: "Escape clears the frozen preview")
    report.expect(DocumentSnapshot(document) == cancelBaseline, cppID: drawerVelocityCancellationID,
                  message: "Escape writes nothing at all")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: drawerVelocityCancellationID,
                  message: "Escape restores selection membership and insertion order")
    report.expectEqual(expected: cancelProjection, actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityCancellationID, what: "an escaped drag leaves the timeline projection untouched")
    report.expectEqual(expected: cancelDepth, actual: document.history.undoCount,
                       cppID: drawerVelocityCancellationID, what: "a cancelled gesture leaves the undo depth unchanged")

    // A stale revision cancels instead of retargeting the current selection.
    if let handle = fixture.handle(notes[0]) {
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        let foreignRevision = document.revision
        _ = document.setVelocities([NoteVelocity(noteID: notes[2].id, velocity: 12)],
                                   expectedRevision: foreignRevision)
        _ = page.pointerRelease(x: handle.x, y: handle.y - 30, button: 1)
        report.expectEqual(expected: foreignRevision + 1, actual: document.revision, cppID: drawerVelocityCancellationID,
                           what: "a release after a foreign change writes nothing")
        report.expect(!page.hasGesture && page.frozenPreview.isEmpty, cppID: drawerVelocityCancellationID,
                      message: "a stale release ends the gesture")
    }
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // The ruler click-sets the selected notes and commits once.
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    let rulerBaseline = DocumentSnapshot(document)
    let rulerY = (page.axisModel.top + page.axisModel.bottom) / 2
    report.expect(page.pointerPress(x: 10, y: rulerY, surface: 0, button: 1, modifiers: 0),
                  cppID: drawerVelocityTransactionID, message: "the ruler consumes its own press")
    _ = page.pointerRelease(x: 10, y: rulerY, button: 1)
    report.expectEqual(expected: rulerBaseline.revision + 1, actual: document.revision, cppID: drawerVelocityTransactionID,
                       what: "one ruler click makes one revision")
    report.expect(document.history.currentIdentity != rulerBaseline.identity, cppID: drawerVelocityTransactionID,
                  message: "one ruler click makes one history entry")
    report.expect(!page.pointerPress(x: 200, y: rulerY, surface: 0, button: 1, modifiers: 0),
                  cppID: drawerVelocityTransactionID, message: "a press inside the plot is not the ruler's")
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // Middle-drag pan asks the one shared camera for its own scroll and writes
    // no document state.
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    let panBaseline = DocumentSnapshot(document)
    let panScroll = fixture.session.camera.snapshot.scrollX
    _ = page.pointerPress(x: 200, y: 40, surface: 1, button: 4, modifiers: 0)
    _ = page.pointerMove(x: 170, y: 40, buttons: 4)
    _ = page.pointerMove(x: 150, y: 40, buttons: 4)
    report.expect(fixture.session.camera.snapshot.scrollX > panScroll, cppID: drawerVelocityTransactionID,
                  message: "a middle drag pans the shared camera")
    report.expect(page.interactionActive, cppID: drawerVelocityTransactionID,
                  message: "a live pan suspends follow through the page's own interaction")
    _ = page.pointerRelease(x: 150, y: 40, button: 4)
    report.expect(!page.hasGesture, cppID: drawerVelocityTransactionID, message: "the pan ends on release")
    report.expect(DocumentSnapshot(document) == panBaseline, cppID: drawerVelocityTransactionID,
                  message: "panning writes no document state")

    // The detent control: available for a PSG context, and turning it off puts
    // every context on the continuous domain and cancels what it interrupted.
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    report.expect(page.detentsAvailable && page.detentsEnabled, cppID: drawerVelocityTransactionID,
                  message: "a PSG context offers the detent control, enabled by default")
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode,
                       cppID: drawerVelocityTransactionID,
                       what: "the PSG context presents the intrinsic ruler")
    report.expect(page.axisGraduationsVisible, cppID: drawerVelocityTransactionID,
                  message: "an enabled detent set draws the level graduations")
    if let handle = fixture.handle(notes[0]) {
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        report.expect(!page.frozenPreview.isEmpty, cppID: drawerVelocityTransactionID,
                      message: "the detent case starts from a live preview")
        page.toggleDetents()
        report.expect(!page.detentsEnabled && page.frozenPreview.isEmpty, cppID: drawerVelocityTransactionID,
                      message: "toggling detents cancels the live interaction")
    }
    report.expect(page.axisGraduationsVisible == false, cppID: drawerVelocityTransactionID,
                  message: "disabled detents put the ruler on the continuous rendering")
    report.expect(page.axisModel.mode == .intrinsic, cppID: drawerVelocityTransactionID,
                  message: "the voice's own map stays intrinsic under the ruler switch")
    if let handle = fixture.handle(notes[0]) {
        let exactY = page.axisModel.velocityToY(handle.value)
        report.expect(abs(handle.y - exactY) < 0.001, cppID: drawerVelocityTransactionID,
                      message: "a disabled detent set places nodes at their exact velocity")
    }
    report.expect(DocumentSnapshot(document) == panBaseline, cppID: drawerVelocityTransactionID,
                  message: "the detent toggle writes no document state")
    page.setUseDetents(enabled: true)
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // A band gesture resolves a selection and commits nothing.
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    let bandBaseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: 0, y: 0, surface: 1, button: 2, modifiers: 0)
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    _ = page.pointerRelease(x: 400, y: 120, button: 2)
    report.expectEqual(expected: bandBaseline.revision, actual: document.revision, cppID: drawerVelocityTransactionID,
                       what: "a band selection writes nothing")
    report.expectEqual(expected: 3, actual: fixture.session.selectedNotes.count, cppID: drawerVelocityTransactionID,
                       what: "the band selected every note it covered")
}
