import Foundation
import PorydawApp
import PorydawCore

// Shared fixture and suite entry order live in AutomationPageChecks.swift.

@MainActor
func drawerAutomationHistoryUndoRedo(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: drawerAutomationHistoryID,
                  message: "the prompt opens")
    report.expect(fixture.page.acceptPrompt(displayedValue: 20), cppID: drawerAutomationHistoryID,
                  message: "the prompt commits")
    report.expectEqual(expected: ["24:84", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationHistoryID,
                       what: "the committed lane holds the new value")
    report.expect(fixture.document.history.canUndo, cppID: drawerAutomationHistoryID,
                  message: "the transaction is on the undo stack")
    report.expect(fixture.undo(), cppID: drawerAutomationHistoryID, message: "the transaction undoes")
    report.expectEqual(expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationHistoryID,
                       what: "undo restores the curve from the document")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationHistoryID,
                  message: "the transaction recorded exactly one history entry")
    report.expectEqual(expected: ["0:64", "24:64", "120:40"], actual:
                       fixture.page.projection?.points.map { "\($0.tick):\($0.value)" } ?? [],
                       cppID: drawerAutomationHistoryID, what: "the page rebuilds the restored curve")
    report.expect(fixture.document.history.canRedo, cppID: drawerAutomationHistoryID,
                  message: "the undone transaction is redoable")
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerAutomationHistoryID, "redo failed: \(error)")
        return
    }
    report.expectEqual(expected: ["24:84", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationHistoryID,
                       what: "redo restores the committed lane")
    report.expect(fixture.document.history.canUndo && !fixture.document.history.canRedo,
                  cppID: drawerAutomationHistoryID,
                  message: "one undo and one redo stand on the same single entry")
    report.expectEqual(expected: before.revision + 3, actual: fixture.document.revision, cppID: drawerAutomationHistoryID,
                       what: "a commit, an undo and a redo each publish one revision")

    // Two transactions undo one at a time.
    let two = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    two.activate(two.panLane)
    _ = two.page.openPrompt(tick: 24, value: 64)
    _ = two.page.acceptPrompt(displayedValue: 10)
    _ = two.page.openPrompt(tick: 48, value: 64)
    _ = two.page.acceptPrompt(displayedValue: -10)
    report.expectEqual(expected: ["24:74", "48:54"], actual: two.values(two.panLane), cppID: drawerAutomationHistoryID,
                       what: "two transactions leave both writes")
    report.expect(two.undo() && two.values(two.panLane) == ["24:74"], cppID: drawerAutomationHistoryID,
                  message: "the first undo removes only the second transaction")
    report.expect(two.undo() && two.values(two.panLane) == ["24:64"], cppID: drawerAutomationHistoryID,
                  message: "the second undo removes the first transaction")
    report.expect(!two.undo(), cppID: drawerAutomationHistoryID,
                  message: "a third undo finds nothing and reports nothing")
}
