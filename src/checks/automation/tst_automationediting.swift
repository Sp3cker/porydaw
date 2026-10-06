import Foundation
import PorydawApp
import PorydawAppPresentation
import PorydawCore
import PorydawDocument

// Shared fixture and suite entry order live in AutomationPageChecks.swift.

@MainActor
func drawerAutomationHistoryUndoRedo(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(
        fixture.page.openPrompt(tick: 24, value: 64), cppID: drawerAutomationHistoryID,
        message: "the prompt opens")
    report.expect(
        fixture.page.acceptPrompt(displayedValue: 20), cppID: drawerAutomationHistoryID,
        message: "the prompt commits")
    report.expectEqual(
        expected: ["24:84", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationHistoryID,
        what: "the committed lane holds the new value")
    report.expect(
        fixture.document.history.canUndo, cppID: drawerAutomationHistoryID,
        message: "the transaction is on the undo stack")
    report.expect(fixture.undo(), cppID: drawerAutomationHistoryID, message: "the transaction undoes")
    report.expectEqual(
        expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationHistoryID,
        what: "undo restores the curve from the document")
    report.expect(
        !fixture.document.history.canUndo, cppID: drawerAutomationHistoryID,
        message: "the transaction recorded exactly one history entry")
    report.expectEqual(
        expected: ["0:64", "24:64", "120:40"],
        actual:
            fixture.page.projection?.points.map { "\($0.tick):\($0.value)" } ?? [],
        cppID: drawerAutomationHistoryID, what: "the page rebuilds the restored curve")
    report.expect(
        fixture.document.history.canRedo, cppID: drawerAutomationHistoryID,
        message: "the undone transaction is redoable")
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerAutomationHistoryID, "redo failed: \(error)")
        return
    }
    report.expectEqual(
        expected: ["24:84", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationHistoryID,
        what: "redo restores the committed lane")
    report.expect(
        fixture.document.history.canUndo && !fixture.document.history.canRedo,
        cppID: drawerAutomationHistoryID,
        message: "one undo and one redo stand on the same single entry")
    report.expectEqual(
        expected: before.revision + 3, actual: fixture.document.revision, cppID: drawerAutomationHistoryID,
        what: "a commit, an undo and a redo each publish one revision")

    // Two transactions undo one at a time.
    let two = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    two.activate(two.panLane)
    _ = two.page.openPrompt(tick: 24, value: 64)
    _ = two.page.acceptPrompt(displayedValue: 10)
    _ = two.page.openPrompt(tick: 48, value: 64)
    _ = two.page.acceptPrompt(displayedValue: -10)
    report.expectEqual(
        expected: ["24:74", "48:54"], actual: two.values(two.panLane), cppID: drawerAutomationHistoryID,
        what: "two transactions leave both writes")
    report.expect(
        two.undo() && two.values(two.panLane) == ["24:74"], cppID: drawerAutomationHistoryID,
        message: "the first undo removes only the second transaction")
    report.expect(
        two.undo() && two.values(two.panLane) == ["24:64"], cppID: drawerAutomationHistoryID,
        message: "the second undo removes the first transaction")
    report.expect(
        !two.undo(), cppID: drawerAutomationHistoryID,
        message: "a third undo finds nothing and reports nothing")
    let blank = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    blank.activate(blank.panLane)
    let unwrittenTick: Tick = 72
    let beforeBlank = blank.lanePoints(blank.panLane).contains { $0.tick == unwrittenTick }
    let blankX = blank.x(unwrittenTick)
    _ = blank.page.pointerPress(
        x: blankX, y: 60, surface: AutomationInputSurface.plot.rawValue,
        button: DrawerQtButton.left)
    _ = blank.page.pointerRelease(x: blankX, y: 60, button: DrawerQtButton.left)
    report.expect(
        !beforeBlank && !blank.lanePoints(blank.panLane).contains { $0.tick == unwrittenTick },
        cppID: drawerAutomationHistoryID, message: "an unwritten tick holds no point")
}

@MainActor
func drawerAutomationCcPointerDragPlayback(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::ccDragCommitsOnce"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(48, 40), (96, 100)])
    fixture.activate(fixture.panLane)
    let sourceX = fixture.x(48)
    let sourceY = fixture.y(fixture.panLane, 40)
    let activationY = sourceY - fixture.page.geometry.nodeDragActivationDistance - 2
    let endY = activationY + fixture.y(fixture.panLane, 84) - sourceY
    let before = fixture.snapshot
    let history = fixture.document.history.undoCount
    _ = fixture.page.pointerPress(
        x: sourceX, y: sourceY, surface: 1,
        button: DrawerQtButton.left)
    _ = fixture.page.pointerMove(x: sourceX, y: activationY, buttons: DrawerQtButton.left)
    _ = fixture.page.pointerMove(x: sourceX, y: endY, buttons: DrawerQtButton.left)
    report.expect(
        fixture.snapshot == before
            && fixture.playbackValues(fixture.panLane, at: 48) == [40]
            && fixture.playbackValues(fixture.panLane, at: 96) == [100], cppID: id,
        message: "held CC pointer drag keeps both playback events unchanged")
    let committed = fixture.page.pointerRelease(
        x: sourceX, y: endY,
        button: DrawerQtButton.left)
    report.expect(
        committed && fixture.values(fixture.panLane) == ["48:84", "96:100"]
            && fixture.document.history.undoCount == history + 1, cppID: id,
        message: "the CC pointer drag commits 84 once without replacing the independent point")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 48) == [84], cppID: id,
        message: "dragged CC playback commits value 84 at tick 48")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96) == [100], cppID: id,
        message: "independent CC playback stays 100 at tick 96 after drag")
    let undid = fixture.undo()
    report.expect(
        undid && fixture.playbackValues(fixture.panLane, at: 48) == [40], cppID: id,
        message: "undo restores dragged CC playback value 40 at tick 48")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96) == [100], cppID: id,
        message: "undo preserves independent CC playback value 100 at tick 96")
    let redid = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(
        redid && fixture.playbackValues(fixture.panLane, at: 48) == [84], cppID: id,
        message: "redo restores dragged CC playback value 84 at tick 48")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96) == [100], cppID: id,
        message: "redo preserves independent CC playback value 100 at tick 96")
}
