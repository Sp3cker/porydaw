import Foundation
@testable import PorydawApp
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
    report.expectEqual(1, VelocityPromptPolicy.minimum, cppID: drawerVelocityPromptID,
                       what: "the prompt's minimum is 1")
    report.expectEqual(127, VelocityPromptPolicy.maximum, cppID: drawerVelocityPromptID,
                       what: "the prompt's maximum is 127")
    report.expect(VelocityPromptPolicy.value(draft: "1") == 1
                      && VelocityPromptPolicy.value(draft: "127") == 127, cppID: drawerVelocityPromptID,
                  message: "the domain endpoints are accepted")
    report.expect(VelocityPromptPolicy.value(draft: "0") == nil
                      && VelocityPromptPolicy.value(draft: "128") == nil, cppID: drawerVelocityPromptID,
                  message: "values outside the domain are refused")
    report.expect(VelocityPromptPolicy.value(draft: "") == nil
                      && VelocityPromptPolicy.value(draft: "12x") == nil
                      && VelocityPromptPolicy.value(draft: "-5") == nil, cppID: drawerVelocityPromptID,
                  message: "empty, non-decimal and signed drafts are refused")
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
    report.expectEqual("\(notes[0].velocity)", page.promptDraft, cppID: drawerVelocityPromptID,
                       what: "the prompt opens with the first captured value as its draft")
    report.expectEqual(Int(notes[0].velocity), page.promptInitialValue, cppID: drawerVelocityPromptID,
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
    report.expectEqual(95, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityPromptID,
                       what: "the accepted value reached the first target")
    report.expectEqual(95, Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityPromptID,
                       what: "the accepted value reached every captured target")
    report.expectEqual(acceptBaseline.revision + 1, document.revision, cppID: drawerVelocityPromptID,
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
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: drawerVelocityHistoryID, what: "Undo restores the prompt's before-values")

    // The first selected note seeds the prompt, even when selected later in the
    // song or another selected note is hovered before opening.
    let ordered = drawerVelocityVelocityFixture(session: session, service: service)
    ordered.session.addSelectedNote(ordered.notes[1].id)
    ordered.session.addSelectedNote(ordered.notes[0].id)
    ordered.page.refreshFromDocument()
    _ = ordered.page.openSelectedVelocityPrompt()
    report.expectEqual(Int(ordered.notes[1].velocity), ordered.page.promptInitialValue,
                       cppID: drawerVelocityPromptID, what: "selection insertion order seeds the prompt")
    ordered.page.cancelPrompt()
    if let pointed = ordered.handle(ordered.notes[0]) {
        _ = ordered.page.pointerMove(x: pointed.x, y: pointed.y, buttons: 0)
    }
    _ = ordered.page.openSelectedVelocityPrompt()
    report.expectEqual(Int(ordered.notes[1].velocity), ordered.page.promptInitialValue,
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
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: drawerVelocityCancellationID,
                       what: "the stale acceptance left its targets alone")
    report.expectEqual(staleBaseline.revision + 1, document.revision, cppID: drawerVelocityCancellationID,
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
    report.expectEqual(77, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityPromptID,
                       what: "the acceptance wrote the captured target, not the new selection")
    report.expectEqual(Int(notes[2].velocity), Int(document.note(notes[2].id)?.velocity ?? 0),
                       cppID: drawerVelocityPromptID,
                       what: "the note the prompt never captured keeps its own velocity")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
}
