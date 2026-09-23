import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerOriginalNumericPromptTransaction(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "selectionkey/SelectionLocalInputTierTest::numericPromptOwnsKeys"
    let labelID = "selectionkey/SelectionWindowTierTest::parameterLabelActivationAndSharedCommands"
    let lifetimeID = "selectionkey/SelectionWindowTierTest::tabsDocumentsAndPrimaryTrackLifetime"
    // localinputtier_text.cpp: track0 CC10 at48=32 and96=64; insert at144.
    // These predicates exercise the production Swift transaction. Original
    // keyboard delivery and focus assertions remain deferred, not simulated.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(48, 32), (96, 64)],
                                                     tailTick: 6000)
    fixture.activate(fixture.panLane)
    var insertedNotes: [NoteID] = []
    do {
        let notes = try fixture.document.addNotes([
            NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100)
        ])
        report.expectEqual(1, notes.count, cppID: id, what: "the original selected fixture note exists")
        insertedNotes = notes
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

    // Model facts the original read through the QML canvas: the CC10 lane is
    // one row of the page's published row stack, and the inserted fixture
    // note resolves by ID. The QML surfaces themselves stay deferred.
    report.expect(page.rows.contains { $0.parameter == fixture.panLane }, cppID: id,
                  message: "the original CC10 lane is present in the page's row stack")
    report.expect(insertedNotes.first.flatMap { fixture.document.note($0) } != nil, cppID: id,
                  message: "the original fixture note resolves by its inserted ID")

    // windowtier_keyboard.cpp parameterLabelActivationAndSharedCommands opens
    // the volume lane's insertion prompt at tick 5808 value 48 through the
    // same production entry point.
    fixture.activate(fixture.volumeLane)
    report.expect(page.rows.contains { $0.parameter == fixture.volumeLane }, cppID: labelID,
                  message: "the original volume lane is present in the page's row stack")
    report.expect(page.openPrompt(tick: 5808, value: 48), cppID: labelID,
                  message: "the original volume-lane insertion prompt opens")
    report.expectEqual("48", page.promptDraft, cppID: labelID,
                       what: "the volume prompt opens with the plotted value as its draft")
    page.cancelPrompt()

    // windowtier_lifetime.cpp tabsDocumentsAndPrimaryTrackLifetime opens the
    // pan lane's insertion prompt at tick 5760 value 64; a document switch
    // routes through cancelSectionInteraction, and a late acceptance writes
    // nothing.
    fixture.activate(fixture.panLane)
    report.expect(page.openPrompt(tick: 5760, value: 64), cppID: lifetimeID,
                  message: "the original pan-lane insertion prompt opens")
    page.cancelSectionInteraction()
    report.expect(!page.promptOpen, cppID: lifetimeID,
                  message: "the document-switch cancellation closes the prompt")
    report.expect(!page.acceptPrompt(displayedValue: 96), cppID: lifetimeID,
                  message: "accepting a closed prompt commits nothing")
    report.expectEqual(before, fixture.snapshot, cppID: lifetimeID,
                       what: "the closed prompt's late acceptance leaves the document unchanged")

}
