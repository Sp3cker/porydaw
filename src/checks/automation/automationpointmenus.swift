import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

// Existing scenarios paired with automationpointmenus.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationPromptTransactions(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: drawerAutomationPromptID,
                  message: "a prompt opens on a written node")
    report.expect(fixture.page.hasPrompt && fixture.page.interactionActive, cppID: drawerAutomationPromptID,
                  message: "an open prompt marks the page interacting")
    report.expectEqual(before, fixture.snapshot, cppID: drawerAutomationPromptID,
                       what: "opening a prompt writes nothing")
    report.expectEqual(1, fixture.lanePoints(fixture.panLane).count(where: { $0.tick == 24 }),
                       cppID: drawerAutomationPromptID, what: "opening a prompt leaves the lane alone")
    report.expect(!fixture.page.acceptPrompt(displayedValue: 0), cppID: drawerAutomationPromptID,
                  message: "accepting the unchanged value commits nothing")
    report.expectEqual(before, fixture.snapshot, cppID: drawerAutomationPromptID,
                       what: "a no-op acceptance writes nothing")
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: drawerAutomationPromptID,
                  message: "the prompt reopens")
    report.expect(fixture.page.acceptPrompt(displayedValue: 10), cppID: drawerAutomationPromptID,
                  message: "accepting a changed value commits once")
    report.expectEqual(["24:74", "120:40"], fixture.values(fixture.panLane), cppID: drawerAutomationPromptID,
                       what: "the displayed value maps back through the prompt's offset")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: drawerAutomationPromptID,
                       what: "one acceptance is one document revision")
    report.expectEqual(1, fixture.lanePoints(fixture.panLane).count(where: { $0.tick == 24 }),
                       cppID: drawerAutomationPromptID, what: "a value replacement keeps one occurrence at the tick")
    report.expect(fixture.undo(), cppID: drawerAutomationPromptID, message: "the acceptance is undoable")
    report.expectEqual(["24:64", "120:40"], fixture.values(fixture.panLane), cppID: drawerAutomationPromptID,
                       what: "one undo restores the lane's values")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationPromptID,
                  message: "one undo consumes the acceptance's single history entry")

    // Insertion at an empty tick: one span write, and a duplicate is a no-op.
    report.expect(fixture.page.openPrompt(tick: 48, value: 40), cppID: drawerAutomationPromptID,
                  message: "a prompt opens on an empty tick")
    report.expect(fixture.page.acceptPrompt(displayedValue: -24), cppID: drawerAutomationPromptID,
                  message: "the empty-tick prompt commits its insertion")
    report.expectEqual(["24:64", "48:40", "120:40"], fixture.values(fixture.panLane),
                       cppID: drawerAutomationPromptID, what: "the insertion lands at the captured tick")
    let revisionAfterInsert = fixture.document.revision
    report.expect(fixture.page.openPrompt(tick: 48, value: 40), cppID: drawerAutomationPromptID,
                  message: "a prompt reopens on the inserted tick")
    report.expect(!fixture.page.acceptPrompt(displayedValue: -24), cppID: drawerAutomationPromptID,
                  message: "re-inserting an existing point changes nothing")
    report.expectEqual(revisionAfterInsert, fixture.document.revision, cppID: drawerAutomationPromptID,
                       what: "a duplicate insertion writes no revision")

    // Cancellation writes nothing and ends the interaction.
    let beforeCancel = fixture.snapshot
    _ = fixture.page.openPrompt(tick: 24, value: 64)
    fixture.page.cancelSectionInteraction()
    report.expectEqual(beforeCancel, fixture.snapshot, cppID: drawerAutomationPromptID,
                       what: "cancelling a prompt commits nothing")
    report.expect(!fixture.page.hasPrompt && !fixture.page.interactionActive, cppID: drawerAutomationPromptID,
                  message: "cancelling drops the prompt and the interaction")

    // Tempo parity: the same prompt path writes BPM through the tempo edit.
    let tempoFixture = drawerAutomationAutomationFixture(suite: suite, service: service)
    tempoFixture.activate(.tempo)
    let tempoBefore = tempoFixture.snapshot
    report.expect(tempoFixture.page.openPrompt(tick: 0, value: 120), cppID: drawerAutomationPromptID,
                  message: "Tempo opens the same prompt on its written point")
    report.expect(tempoFixture.page.acceptPrompt(displayedValue: 150), cppID: drawerAutomationPromptID,
                  message: "Tempo commits its prompt")
    report.expectEqual(["0:150"], tempoFixture.tempoValues, cppID: drawerAutomationPromptID,
                       what: "the tempo point stores the prompted BPM")
    report.expectEqual(tempoBefore.revision + 1, tempoFixture.document.revision, cppID: drawerAutomationPromptID,
                       what: "Tempo's acceptance is one revision")
    report.expect(tempoFixture.undo() && tempoFixture.tempoValues == ["0:120"], cppID: drawerAutomationPromptID,
                  message: "one undo restores Tempo's stored microseconds")
}
