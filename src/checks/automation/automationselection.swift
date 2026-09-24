import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with automationselection.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationRestoredInteractionContracts(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    let id = "swiftcore/AutomationPage::restoredInteractionContracts"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(48, 70)], pan: [(24, 60)],
                                    tempo: [(0, 500_000), (36, 400_000)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 20, to: 60,
                             lanes: [fixture.panLane, fixture.volumeLane, .tempo])
    let before = fixture.snapshot
    fixture.drag(fixture.panLane, from: (24, 60), to: 70, modifiers: AutomationQtModifier.alt)
    report.expectEqual(["24:70"], fixture.values(fixture.panLane), cppID: id,
                       what: "selected drag moves the grabbed lane")
    report.expectEqual(["48:80"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "selected drag resolves a disjoint CC snapshot")
    report.expectEqual(["0:120", "36:160"], fixture.tempoValues, cppID: id,
                       what: "selected drag resolves Tempo through its own stream")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: id,
                       what: "heterogeneous selected drag is one revision")
    report.expect(fixture.undo(), cppID: id, message: "one undo restores all selected lanes")
    report.expectEqual(["48:70"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "undo restores secondary CC lane")
    report.expectEqual(["0:120", "36:150"], fixture.tempoValues, cppID: id,
                       what: "undo restores secondary Tempo lane")
    report.expect(!fixture.document.history.canUndo, cppID: id,
                  message: "the drag records exactly one history entry")

    let page = fixture.page
    let x = fixture.x(24)
    let y = fixture.y(fixture.panLane, 60)
    _ = page.pointerPress(x: x, y: y, surface: 1, button: AutomationQtButton.left)
    _ = page.pointerRelease(x: x, y: y, button: AutomationQtButton.left)
    report.expectEqual([String](), fixture.values(fixture.panLane), cppID: id,
                       what: "stationary selection click deletes grabbed node only")
    report.expectEqual(["48:70"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "stationary selection click preserves other lanes")
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: 400, y: 90, button: AutomationQtButton.right)
    report.expect(page.selection == nil, cppID: id,
                  message: "outside right press clears selection before opening a menu")
    page.dismissMenu()
    page.selectRange(from: 0, to: fixture.songEndTick, lanes: [fixture.panLane])
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerMove(x: 404, y: 86, buttons: AutomationQtButton.right)
    report.expect(!page.bandVisible && page.selection?.range == TimeRange(
        startTick: 0, endTick: fixture.songEndTick), cppID: id,
                  message: "a pending band preserves selection below the Manhattan threshold")
    _ = page.pointerMove(x: 405, y: 85, buttons: AutomationQtButton.right)
    report.expect(page.bandVisible, cppID: id,
                  message: "diagonal travel activates at Manhattan ten before Euclidean ten")
    _ = page.pointerMove(x: 400, y: 60, buttons: AutomationQtButton.right)
    _ = page.pointerRelease(x: 400, y: 60, button: AutomationQtButton.right)
    report.expect(page.selection == nil, cppID: id,
                  message: "activated zero-width band clears selection")

    fixture.activate(fixture.volumeLane)
    let rangeBefore = fixture.snapshot
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.volumeLane), x: 0, y: 0)
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.range64.rawValue),
                  cppID: id, message: "zoomable lane consumes range choice")
    report.expectEqual(64, page.scaleLabels.first?.value, cppID: id,
                       what: "range choice changes displayed maximum")
    report.expectEqual(rangeBefore, fixture.snapshot, cppID: id,
                       what: "range choice changes neither document nor history")
    fixture.activate(fixture.panLane)
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0)
    report.expect(!page.menuRowActions.contains(AutomationMenuAction.valueRange.rawValue),
                  cppID: id, message: "centered lane has no value range submenu")
    page.dismissMenu()
    fixture.activate(fixture.volumeLane)
    report.expectEqual(64, page.scaleLabels.first?.value, cppID: id,
                       what: "range persists independently across parameter switches")
    let synthetic = drawerAutomationAutomationFixture(suite: suite, service: service)
    synthetic.activate(synthetic.volumeLane)
    if let point = synthetic.page.projection?.points.first {
        _ = synthetic.page.pointerPress(x: point.x, y: point.y, surface: 1,
                                        button: AutomationQtButton.right)
        _ = synthetic.page.pointerRelease(x: point.x, y: point.y, button: AutomationQtButton.right)
        report.expect(synthetic.page.publishedMenuRows.first {
            $0.actionId == AutomationMenuAction.deleteNode.rawValue
        }?.enabled == false, cppID: id, message: "synthetic engine default cannot be deleted")
        _ = synthetic.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue)
        report.expect(synthetic.page.acceptPrompt(displayedValue: 80), cppID: id,
                      message: "Set Value promotes the synthetic default")
        report.expectEqual(["0:80"], synthetic.values(synthetic.volumeLane), cppID: id,
                           what: "promoted value is a written tick-zero event")
        _ = synthetic.page.openPrompt(tick: 0, value: 80)
        synthetic.session.selectedTrack = nil
        let stale = synthetic.snapshot
        report.expect(!synthetic.page.acceptPrompt(displayedValue: 70), cppID: id,
                      message: "a prompt cannot follow a primary-track change")
        report.expectEqual(stale, synthetic.snapshot, cppID: id,
                           what: "stale prompt leaves document and history untouched")
    } else {
        report.fail(id, "synthetic default projection missing")
    }

    let hover = drawerAutomationAutomationFixture(suite: suite, service: service, volume: [(48, 70)])
    hover.activate(hover.volumeLane)
    hover.page.plotFocused = true
    hover.page.isPencilMode = true
    _ = hover.page.pointerMove(x: 400, y: 70, buttons: 0)
    let hoverBefore = hover.snapshot
    report.expect(hover.page.consumeHoverDelete(), cppID: id,
                  message: "pencil blank hover consumes deletion without falling through")
    report.expectEqual(hoverBefore, hover.snapshot, cppID: id,
                       what: "blank hover deletion changes nothing")
    hover.page.selectRange(from: 0, to: 100, lanes: [hover.volumeLane])
    report.expect(!hover.page.consumeHoverDelete(), cppID: id,
                  message: "time selection retains semantic delete priority")
    hover.page.clearTimeSelection()
    hover.page.isPencilMode = false
    report.expect(!hover.page.consumeHoverDelete(), cppID: id,
                  message: "arrow hover cannot claim pencil deletion")
    hover.page.isPencilMode = true
    _ = hover.page.pointerMove(x: hover.x(48), y: hover.y(hover.volumeLane, 70), buttons: 0)
    report.expect(hover.page.consumeHoverDelete(), cppID: id,
                  message: "pencil hover deletion consumes the written point")
    report.expectEqual([String](), hover.values(hover.volumeLane), cppID: id,
                       what: "hover deletion removes the actual written point")
    report.expectEqual(hoverBefore.revision + 1, hover.document.revision, cppID: id,
                       what: "hover deletion publishes one revision")
    report.expect(hover.undo() && !hover.document.history.canUndo, cppID: id,
                  message: "hover deletion is exactly one undo entry")
    report.expectEqual(["48:70"], hover.values(hover.volumeLane), cppID: id,
                       what: "undo restores the hover-deleted point")

    _ = hover.page.pointerPress(x: hover.x(48), y: hover.y(hover.volumeLane, 70),
                                 surface: 1, button: AutomationQtButton.right)
    _ = hover.page.pointerRelease(x: hover.x(48), y: hover.y(hover.volumeLane, 70),
                                   button: AutomationQtButton.right)
    report.expect(hover.page.menuTargetIsPoint, cppID: id,
                  message: "the written point owns its captured menu target")
    _ = hover.page.openParameterMenu(index: hover.page.catalogIndex(of: hover.volumeLane),
                                     x: 0, y: 0)
    let superseded = hover.snapshot
    report.expect(!hover.page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue),
                  cppID: id, message: "a replacement lane menu invalidates the old point action")
    report.expectEqual(superseded, hover.snapshot, cppID: id,
                       what: "a superseded point command cannot edit the lane")

    let emptyRange = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    emptyRange.page.selectRange(from: 48, to: 96, lanes: [emptyRange.panLane])
    let emptyBefore = emptyRange.snapshot
    report.expect(emptyRange.page.consumeSelectionCommand(command: .nudgeRight), cppID: id,
                  message: "an empty range owns its nudge command")
    report.expect((emptyRange.page.selection?.range.startTick ?? 0) > 48
                      && emptyRange.page.selection?.range.span == 48, cppID: id,
                  message: "an empty range advances on the camera grid without changing its span")
    report.expectEqual(emptyBefore, emptyRange.snapshot, cppID: id,
                       what: "empty-band movement creates no document edit or history")

    let duplicate = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 30)])
    duplicate.page.selectRange(from: 0, to: 48, lanes: [duplicate.panLane])
    report.expect(duplicate.page.consumeSelectionCommand(command: .duplicate), cppID: id,
                  message: "range duplicate is consumed through the canonical command seam")
    report.expectEqual(TimeRange(startTick: 48, endTick: 96), duplicate.page.selection?.range,
                       cppID: id, what: "duplicate moves the band onto the inserted span")
    report.expectEqual(Tick(96), duplicate.session.editCursor, cppID: id,
                       what: "duplicate advances the edit cursor to the new span end")
    report.expect(duplicate.undo() && !duplicate.document.history.canUndo, cppID: id,
                  message: "duplicate remains one undo entry")
    report.expectEqual(["24:30"], duplicate.values(duplicate.panLane), cppID: id,
                       what: "undo restores the original range contents")
}
