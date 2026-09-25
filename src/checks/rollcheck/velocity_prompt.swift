import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with velocity_prompt.cpp.
// Entry order remains in VelocityPageChecks.swift.

@MainActor
func drawerVelocityPromptTransaction(_ report: CheckReport, session: DocumentSession,
                               service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    let document = fixture.document
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityPromptID, "the synthetic fixture published fewer than three notes")
        return
    }
    var acceptedValues: [UInt8] = []
    page.onVelocityAccepted = { acceptedValues.append($0) }
    report.expectEqual(expected: 1, actual: VelocityPromptPolicy.minimum, cppID: drawerVelocityPromptID,
                       what: "the prompt's minimum is 1")
    report.expectEqual(expected: 127, actual: VelocityPromptPolicy.maximum, cppID: drawerVelocityPromptID,
                       what: "the prompt's maximum is 127")
    report.expect(VelocityPromptPolicy.value(draft: "1") == 1
                      && VelocityPromptPolicy.value(draft: "127") == 127, cppID: drawerVelocityPromptID,
                  message: "the domain endpoints are accepted")
    report.expect(VelocityPromptPolicy.value(draft: "0") == nil
                      && VelocityPromptPolicy.value(draft: "128") == nil, cppID: drawerVelocityPromptID,
                  message: "values outside the domain are refused")
    report.expect(VelocityPromptPolicy.value(draft: "") == nil
                      && VelocityPromptPolicy.value(draft: "12x") == nil
                      && VelocityPromptPolicy.value(draft: "-5") == nil
                      && VelocityPromptPolicy.value(draft: " 95") == nil
                      && VelocityPromptPolicy.value(draft: "95 ") == nil
                      && VelocityPromptPolicy.value(draft: "²") == nil,
                  cppID: drawerVelocityPromptID,
                  message: "empty, non-ASCII, spaced and signed drafts are refused")
    report.expect(VelocityPromptPolicy.error(draft: "64").isEmpty, cppID: drawerVelocityPromptID,
                  message: "a valid draft publishes no error")

    // No selection: the entry point refuses and writes nothing.
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    let emptyBaseline = drawerVelocityDocumentSnapshot(document)
    report.expect(!page.openSelectedVelocityPrompt(), cppID: drawerVelocityPromptID,
                  message: "the selectionless entry point does not open a prompt")
    report.expect(drawerVelocityDocumentSnapshot(document) == emptyBaseline, cppID: drawerVelocityPromptID,
                  message: "the selectionless entry point writes nothing")

    // Capture, draft typing, cancellation.
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expect(page.openSelectedVelocityPrompt(), cppID: drawerVelocityPromptID,
                  message: "the selected-note entry point opens the prompt")
    report.expectEqual(expected: "\(notes[0].velocity)", actual: page.promptDraft, cppID: drawerVelocityPromptID,
                       what: "the prompt opens with the first captured value as its draft")
    report.expectEqual(expected: Int(notes[0].velocity), actual: page.promptInitialValue, cppID: drawerVelocityPromptID,
                       what: "the prompt publishes its initial value")
    report.expect(page.promptTargets == [notes[0].id, notes[1].id], cppID: drawerVelocityPromptID,
                  message: "the prompt captured the stable target IDs")
    report.expect(page.promptBeforeValues == [notes[0].velocity, notes[1].velocity], cppID: drawerVelocityPromptID,
                  message: "the prompt captured every before-value")
    report.expect(page.interactionActive, cppID: drawerVelocityPromptID,
                  message: "an open prompt reports an active interaction")
    page.updatePromptDraft(draft: "95")
    report.expect(page.promptDraft == "95" && page.promptError.isEmpty, cppID: drawerVelocityPromptID,
                  message: "typing replaces the draft without an error")
    report.expect(drawerVelocityDocumentSnapshot(document) == emptyBaseline, cppID: drawerVelocityPromptID,
                  message: "typing into the prompt never mutates the document")
    page.cancelPrompt()
    report.expect(!page.promptOpen, cppID: drawerVelocityCancellationID, message: "cancelling closes the prompt")
    report.expect(drawerVelocityDocumentSnapshot(document) == emptyBaseline, cppID: drawerVelocityCancellationID,
                  message: "cancelling writes nothing")
    report.expect(acceptedValues.isEmpty, cppID: drawerVelocityPromptID,
                  message: "drafting and cancellation do not latch a drawing velocity")

    // Acceptance: one transaction for every captured target.
    let acceptBaseline = drawerVelocityDocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    page.updatePromptDraft(draft: "95")
    report.expect(page.acceptPrompt(), cppID: drawerVelocityPromptID, message: "acceptance commits")
    report.expectEqual(expected: 95, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityPromptID,
                       what: "the accepted value reached the first target")
    report.expectEqual(expected: 95, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityPromptID,
                       what: "the accepted value reached every captured target")
    report.expectEqual(expected: acceptBaseline.revision + 1, actual: document.revision, cppID: drawerVelocityPromptID,
                       what: "acceptance makes one revision")
    report.expect(document.history.currentIdentity != acceptBaseline.identity, cppID: drawerVelocityPromptID,
                  message: "acceptance makes exactly one history entry")
    report.expect(!page.promptOpen, cppID: drawerVelocityPromptID, message: "acceptance closes the prompt")
    report.expect(fixture.session.selectedNotes == [notes[0].id, notes[1].id], cppID: drawerVelocityPromptID,
                  message: "acceptance preserves the selection")
    report.expect(acceptedValues == [95], cppID: drawerVelocityPromptID,
                  message: "valid acceptance latches the drawing velocity")
    let noOpBaseline = drawerVelocityDocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    page.updatePromptDraft(draft: "95")
    report.expect(page.acceptPrompt(), cppID: drawerVelocityPromptID,
                  message: "an identical valid value is still accepted")
    report.expect(drawerVelocityDocumentSnapshot(document) == noOpBaseline && acceptedValues == [95, 95],
                  cppID: drawerVelocityPromptID,
                  message: "no-op acceptance relatches the drawing velocity without history")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
    report.expectEqual(expected: Int(notes[0].velocity), actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: drawerVelocityHistoryID, what: "Undo restores the prompt's before-values")

    // The first selected note seeds the prompt, even when selected later in the
    // song or another selected note is hovered before opening.
    let ordered = drawerVelocityVelocityFixture(session: session, service: service)
    ordered.session.addSelectedNote(ordered.notes[1].id)
    ordered.session.addSelectedNote(ordered.notes[0].id)
    ordered.page.refreshFromDocument()
    _ = ordered.page.openSelectedVelocityPrompt()
    report.expectEqual(expected: Int(ordered.notes[1].velocity), actual: ordered.page.promptInitialValue,
                       cppID: drawerVelocityPromptID, what: "selection insertion order seeds the prompt")
    ordered.page.cancelPrompt()
    if let pointed = ordered.handle(ordered.notes[0]) {
        _ = ordered.page.pointerMove(x: pointed.x, y: pointed.y, buttons: 0)
    }
    _ = ordered.page.openSelectedVelocityPrompt()
    report.expectEqual(expected: Int(ordered.notes[1].velocity), actual: ordered.page.promptInitialValue,
                       cppID: drawerVelocityPromptID, what: "hover cannot reseed the ordered prompt")
    ordered.page.cancelPrompt()

    // An invalid draft stays open, publishes its error and writes nothing.
    let invalidBaseline = drawerVelocityDocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    page.updatePromptDraft(draft: "0")
    report.expect(!page.promptError.isEmpty, cppID: drawerVelocityPromptID,
                  message: "an out-of-domain draft publishes an error")
    report.expect(!page.acceptPrompt(), cppID: drawerVelocityPromptID,
                  message: "an invalid draft does not accept")
    report.expect(page.promptOpen, cppID: drawerVelocityPromptID,
                  message: "the invalid prompt stays open for correction")
    report.expect(drawerVelocityDocumentSnapshot(document) == invalidBaseline, cppID: drawerVelocityPromptID,
                  message: "an invalid draft adds no history entry")
    page.cancelPrompt()
    report.expect(drawerVelocityDocumentSnapshot(document) == invalidBaseline, cppID: drawerVelocityCancellationID,
                  message: "cancelling the invalid prompt writes nothing")

    // A stale prompt commits nothing: the captured revision moved.
    let staleBaseline = drawerVelocityDocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    _ = document.setVelocities([NoteVelocity(noteID: notes[2].id, velocity: 33)],
                               expectedRevision: document.revision)
    page.updatePromptDraft(draft: "40")
    report.expect(!page.acceptPrompt(), cppID: drawerVelocityCancellationID,
                  message: "a stale acceptance commits nothing")
    report.expect(acceptedValues == [95, 95], cppID: drawerVelocityCancellationID,
                  message: "invalid, cancelled and stale prompts never relatch drawing velocity")
    report.expectEqual(expected: Int(notes[0].velocity), actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: drawerVelocityCancellationID,
                       what: "the stale acceptance left its targets alone")
    report.expectEqual(expected: staleBaseline.revision + 1, actual: document.revision, cppID: drawerVelocityCancellationID,
                       what: "the only write is the foreign document change")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // A prompt cannot follow a later selection: the capture stays frozen.
    _ = page.openSelectedVelocityPrompt()
    fixture.session.setSelectedNotes([notes[2].id])
    page.updatePromptDraft(draft: "77")
    report.expect(page.promptTargets == [notes[0].id, notes[1].id], cppID: drawerVelocityPromptID,
                  message: "the capture never follows a later selection")
    report.expect(page.acceptPrompt(), cppID: drawerVelocityPromptID,
                  message: "the captured transaction still completes after a selection change")
    report.expectEqual(expected: 77, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityPromptID,
                       what: "the acceptance wrote the captured target, not the new selection")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0),
                       cppID: drawerVelocityPromptID,
                       what: "the note the prompt never captured keeps its own velocity")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
    checkVelocityPromptAcceptUndoLatch(report, session: session, service: service)
    checkVelocityPromptCancelStale(report, session: session, service: service)
    checkVelocityPromptBounds(report, session: session, service: service)
}

@MainActor
private func checkVelocityPromptAcceptUndoLatch(_ report: CheckReport, session: DocumentSession,
                                                service: ProjectService) {
    let id = "swiftcore/PianoRoll::velocityPromptAcceptUndoLatch"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard fixture.notes.count >= 2 else {
        report.fail(id, "the 73-velocity target note was not found")
        return
    }
    let noteID = fixture.notes[1].id
    _ = fixture.document.setVelocities([NoteVelocity(noteID: noteID, velocity: 73)],
                                       expectedRevision: fixture.document.revision)
    fixture.session.setSelectedNotes([noteID])
    fixture.page.refreshFromDocument()
    var acceptedValues: [UInt8] = []
    fixture.page.onVelocityAccepted = { acceptedValues.append($0) }
    let before = coreTimeBytes(fixture.document)
    let revision = fixture.document.revision
    let identity = fixture.document.history.currentIdentity
    let undoIndex = fixture.document.history.undoIndex
    let undoCount = fixture.document.history.undoCount
    report.expect(fixture.page.openSelectedVelocityPrompt() &&
                  fixture.page.promptInitialValue == 73 && fixture.page.promptDraft == "73",
                  cppID: id, message: "A004: the selected note seeds the prompt with velocity 73")
    fixture.page.updatePromptDraft(draft: "95")
    report.expect(coreTimeBytes(fixture.document) == before &&
                  fixture.document.revision == revision &&
                  fixture.document.history.currentIdentity == identity &&
                  fixture.document.history.undoIndex == undoIndex &&
                  fixture.document.history.undoCount == undoCount,
                  cppID: id, message: "A007: drafting 95 does not write song bytes or history")
    report.expect(fixture.page.acceptPrompt() &&
                  fixture.document.note(noteID)?.velocity == 95 &&
                  fixture.document.revision == revision + 1 &&
                  fixture.document.history.currentIdentity != identity &&
                  fixture.document.history.undoIndex == undoIndex + 1 &&
                  fixture.document.history.undoCount == undoCount + 1,
                  cppID: id, message: "A010: accepting 95 changes the captured note in one edit")
    report.expect(acceptedValues == [95], cppID: id,
                  message: "accepting 95 latches the velocity for subsequent drawing")
    let undone = (try? drawerVelocityRunBlocking { try await fixture.session.undo() }) == true
    report.expect(undone &&
                  fixture.document.note(noteID)?.velocity == 73 &&
                  coreTimeBytes(fixture.document) == before &&
                  fixture.document.history.undoIndex == undoIndex &&
                  fixture.document.history.undoCount == undoCount + 1,
                  cppID: id, message: "A012: one undo restores the original 73-velocity song bytes")
    fixture.page.refreshFromDocument()
    let afterUndo = drawerVelocityDocumentSnapshot(fixture.document)
    report.expect(fixture.page.openSelectedVelocityPrompt() && fixture.page.acceptPrompt() &&
                  drawerVelocityDocumentSnapshot(fixture.document) == afterUndo &&
                  coreTimeBytes(fixture.document) == before &&
                  fixture.document.history.undoIndex == undoIndex &&
                  fixture.document.history.undoCount == undoCount + 1 &&
                  acceptedValues == [95, 73],
                  cppID: id, message: "A018: accepting unchanged 73 relatches without a document edit")
}

@MainActor
private func checkVelocityPromptCancelStale(_ report: CheckReport, session: DocumentSession,
                                            service: ProjectService) {
    let id = "swiftcore/PianoRoll::velocityPromptCancelStale"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard fixture.notes.count >= 2 else {
        report.fail(id, "the selected-note fixture is incomplete")
        return
    }
    let noteID = fixture.notes[1].id
    fixture.session.clearSelectedNotes()
    fixture.page.refreshFromDocument()
    let before = drawerVelocityDocumentSnapshot(fixture.document)
    let bytes = coreTimeBytes(fixture.document)
    let undoIndex = fixture.document.history.undoIndex
    let undoCount = fixture.document.history.undoCount
    report.expect(!fixture.page.openSelectedVelocityPrompt() &&
                  drawerVelocityDocumentSnapshot(fixture.document) == before &&
                  coreTimeBytes(fixture.document) == bytes &&
                  fixture.document.history.undoIndex == undoIndex &&
                  fixture.document.history.undoCount == undoCount,
                  cppID: id, message: "A024: opening without a selected note writes nothing")
    fixture.session.setSelectedNotes([noteID])
    fixture.page.refreshFromDocument()
    _ = fixture.page.openSelectedVelocityPrompt()
    fixture.page.updatePromptDraft(draft: "20")
    fixture.page.cancelPrompt()
    report.expect(!fixture.page.promptOpen &&
                  drawerVelocityDocumentSnapshot(fixture.document) == before &&
                  coreTimeBytes(fixture.document) == bytes &&
                  fixture.document.history.undoIndex == undoIndex &&
                  fixture.document.history.undoCount == undoCount,
                  cppID: id, message: "A029: cancelling a 20 draft leaves history and notes untouched")
    _ = fixture.page.openSelectedVelocityPrompt()
    fixture.page.updatePromptDraft(draft: "30")
    let revision = fixture.document.revision
    _ = fixture.document.setVelocities([NoteVelocity(noteID: noteID, velocity: 40)],
                                       expectedRevision: revision)
    let afterForeignWrite = drawerVelocityDocumentSnapshot(fixture.document)
    let afterForeignBytes = coreTimeBytes(fixture.document)
    report.expect(!fixture.page.acceptPrompt() && !fixture.page.promptOpen &&
                  fixture.document.note(noteID)?.velocity == 40 &&
                  fixture.document.revision == revision + 1 &&
                  drawerVelocityDocumentSnapshot(fixture.document) == afterForeignWrite &&
                  coreTimeBytes(fixture.document) == afterForeignBytes &&
                  fixture.document.history.undoIndex == undoIndex + 1 &&
                  fixture.document.history.undoCount == undoCount + 1,
                  cppID: id, message: "A039: a stale 30 draft never overwrites the foreign 40 edit")
}

@MainActor
private func checkVelocityPromptBounds(_ report: CheckReport, session: DocumentSession,
                                       service: ProjectService) {
    let id = "swiftcore/PianoRoll::velocityPromptBounds"
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    guard fixture.notes.count >= 2 else {
        report.fail(id, "the selected-note fixture is incomplete")
        return
    }
    let noteID = fixture.notes[1].id
    fixture.session.setSelectedNotes([noteID])
    fixture.page.refreshFromDocument()
    let before = drawerVelocityDocumentSnapshot(fixture.document)
    let beforeBytes = coreTimeBytes(fixture.document)
    let undoIndex = fixture.document.history.undoIndex
    let undoCount = fixture.document.history.undoCount
    _ = fixture.page.openSelectedVelocityPrompt()
    fixture.page.updatePromptDraft(draft: "999")
    report.expect(!fixture.page.acceptPrompt() && fixture.page.promptOpen &&
                  drawerVelocityDocumentSnapshot(fixture.document) == before &&
                  coreTimeBytes(fixture.document) == beforeBytes &&
                  fixture.document.history.undoIndex == undoIndex &&
                  fixture.document.history.undoCount == undoCount,
                  cppID: id, message: "invalid 999 leaves the prompt open and the song unchanged")
    fixture.page.updatePromptDraft(draft: "1")
    report.expect(fixture.page.acceptPrompt() && fixture.document.note(noteID)?.velocity == 1 &&
                  fixture.document.history.undoIndex == undoIndex + 1 &&
                  fixture.document.history.undoCount == undoCount + 1,
                  cppID: id, message: "valid lower-bound velocity 1 commits")
    _ = fixture.page.openSelectedVelocityPrompt()
    fixture.page.updatePromptDraft(draft: "127")
    report.expect(fixture.page.acceptPrompt() && fixture.document.note(noteID)?.velocity == 127 &&
                  fixture.document.history.undoIndex == undoIndex + 2 &&
                  fixture.document.history.undoCount == undoCount + 2,
                  cppID: id, message: "valid upper-bound velocity 127 commits")
}
