import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerOriginalNumericPromptTransaction(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "selectionkey/SelectionLocalInputTierTest::numericPromptOwnsKeys"
    // localinputtier_text.cpp: track0 CC10 at48=32 and96=64; insert at144.
    // These predicates exercise the production Swift transaction. Original
    // keyboard delivery and focus assertions remain deferred, not simulated.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(48, 32), (96, 64)])
    fixture.activate(fixture.panLane)
    do {
        let notes = try fixture.document.addNotes([
            NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100)
        ])
        report.expectEqual(1, notes.count, cppID: id, what: "the original selected fixture note exists")
        fixture.session.setSelectedNotes(notes)
    } catch {
        report.fail(id, "original fixture note creation failed: \(error)")
        return
    }
    let before = fixture.snapshot
    let state = fixture.document.state
    let selection = fixture.session.selectedNotes
    let page = fixture.page
    report.expect(page.openPrompt(tick: 144, value: 64), cppID: id,
                  message: "the original empty-tick numeric prompt opens")
    page.updatePromptDraft(draft: "12")
    report.expectEqual("12", page.promptDraft, cppID: id,
                       what: "the production prompt retains the supplied numeric draft")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "draft editing does not mutate the song")
    report.expectEqual(selection, fixture.session.selectedNotes, cppID: id,
                       what: "draft editing preserves note selection")
    page.cancelPrompt()
    report.expect(!page.promptOpen, cppID: id, message: "cancellation closes the prompt")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "cancellation leaves the original document unchanged")
    report.expect(fixture.document.state == state, cppID: id,
                  message: "draft and cancellation preserve the full song contents")
}
