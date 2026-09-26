import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with automationpointmenus.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationPromptTransactions(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    let fileBytes = try? fixture.document.state.file.encoded()
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: drawerAutomationPromptID,
                  message: "a prompt opens on a written node")
    report.expect(fixture.page.hasPrompt && fixture.page.interactionActive, cppID: drawerAutomationPromptID,
                  message: "an open prompt marks the page interacting")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationPromptID,
                       what: "opening a prompt writes nothing")
    report.expectEqual(expected: 1, actual: fixture.lanePoints(fixture.panLane).count(where: { $0.tick == 24 }),
                       cppID: drawerAutomationPromptID, what: "opening a prompt leaves the lane alone")
    report.expect(!fixture.page.acceptPrompt(displayedValue: 0), cppID: drawerAutomationPromptID,
                  message: "accepting the unchanged value commits nothing")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationPromptID,
                       what: "a no-op acceptance writes nothing")
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: drawerAutomationPromptID,
                  message: "the prompt reopens")
    report.expect(fixture.page.acceptPrompt(displayedValue: 10), cppID: drawerAutomationPromptID,
                  message: "accepting a changed value commits once")
    report.expectEqual(expected: ["24:74", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationPromptID,
                       what: "the displayed value maps back through the prompt's offset")
    report.expectEqual(expected: before.revision + 1, actual: fixture.document.revision, cppID: drawerAutomationPromptID,
                       what: "one acceptance is one document revision")
    report.expectEqual(expected: 1, actual: fixture.lanePoints(fixture.panLane).count(where: { $0.tick == 24 }),
                       cppID: drawerAutomationPromptID, what: "a value replacement keeps one occurrence at the tick")
    report.expect(fixture.undo(), cppID: drawerAutomationPromptID, message: "the acceptance is undoable")
    report.expectEqual(expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationPromptID,
                       what: "one undo restores the lane's values")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationPromptID,
                  message: "one undo consumes the acceptance's single history entry")

    // Insertion at an empty tick: one span write, and a duplicate is a no-op.
    report.expect(fixture.page.openPrompt(tick: 48, value: 40), cppID: drawerAutomationPromptID,
                  message: "a prompt opens on an empty tick")
    report.expect(fixture.page.acceptPrompt(displayedValue: -24), cppID: drawerAutomationPromptID,
                  message: "the empty-tick prompt commits its insertion")
    report.expectEqual(expected: ["24:64", "48:40", "120:40"], actual: fixture.values(fixture.panLane),
                       cppID: drawerAutomationPromptID, what: "the insertion lands at the captured tick")
    let revisionAfterInsert = fixture.document.revision
    report.expect(fixture.page.openPrompt(tick: 48, value: 40), cppID: drawerAutomationPromptID,
                  message: "a prompt reopens on the inserted tick")
    report.expect(!fixture.page.acceptPrompt(displayedValue: -24), cppID: drawerAutomationPromptID,
                  message: "re-inserting an existing point changes nothing")
    report.expectEqual(expected: revisionAfterInsert, actual: fixture.document.revision, cppID: drawerAutomationPromptID,
                       what: "a duplicate insertion writes no revision")
    report.expect(fixture.undo(), cppID: drawerAutomationPromptID,
                  message: "the insertion is undoable")
    report.expectEqual(expected: fileBytes, actual: try? fixture.document.state.file.encoded(), cppID: drawerAutomationPromptID,
                       what: "the insertion's undo restores the document's exact bytes")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationPromptID,
                  message: "the insertion's undo consumes the committed edit's single history entry")

    // Cancellation writes nothing and ends the interaction.
    let beforeCancel = fixture.snapshot
    _ = fixture.page.openPrompt(tick: 24, value: 64)
    fixture.page.cancelSectionInteraction()
    report.expectEqual(expected: beforeCancel, actual: fixture.snapshot, cppID: drawerAutomationPromptID,
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
    report.expectEqual(expected: ["0:150"], actual: tempoFixture.tempoValues, cppID: drawerAutomationPromptID,
                       what: "the tempo point stores the prompted BPM")
    report.expectEqual(expected: tempoBefore.revision + 1, actual: tempoFixture.document.revision, cppID: drawerAutomationPromptID,
                       what: "Tempo's acceptance is one revision")
    report.expect(tempoFixture.undo() && tempoFixture.tempoValues == ["0:120"], cppID: drawerAutomationPromptID,
                  message: "one undo restores Tempo's stored microseconds")
    let escapeBefore = fixture.snapshot
    _ = fixture.page.openPrompt(tick: 24, value: 64)
    report.expect(fixture.page.hasPrompt && fixture.page.interactionActive, cppID: drawerAutomationPromptID, message: "the prompt reopens for the Escape route")
    report.expect(fixture.page.handleEscape(), cppID: drawerAutomationPromptID, message: "Escape claims the open prompt")
    report.expect(!fixture.page.hasPrompt && !fixture.page.interactionActive, cppID: drawerAutomationPromptID, message: "Escape drops the prompt and the interaction")
    report.expectEqual(expected: escapeBefore, actual: fixture.snapshot, cppID: drawerAutomationPromptID, what: "Escape cancellation writes nothing")
}

@MainActor
func drawerAutomationPointMenuDeleteAndStale(_ report: CheckReport, suite: DocumentSession,
                                             service: ProjectService) {
    let id = "automation/AutomationEditingTest::pointMenuDeleteCommitsEdit"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let before = fixture.snapshot
    _ = page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                           surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                             button: AutomationQtButton.right)
    report.expect(page.menuTargetIsPoint, cppID: id,
                  message: "the written point owns its captured menu target")
    report.expect(page.publishedMenuRows.first {
        $0.actionId == AutomationMenuAction.deleteNode.rawValue
    }?.enabled == true, cppID: id, message: "the point menu enables Delete on a written node")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue),
                  cppID: id, message: "the Delete row is consumed")
    report.expectEqual(expected: ["120:40"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "Delete removes the targeted node and keeps the other")
    report.expectEqual(expected: before.revision + 1, actual: fixture.document.revision, cppID: id,
                       what: "one Delete is one revision")
    report.expect(fixture.undo(), cppID: id, message: "the Delete undoes")
    report.expectEqual(expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "undo restores the deleted node")
    report.expect(!fixture.document.history.canUndo, cppID: id,
                  message: "the Delete recorded exactly one history entry")

    let staleID = "automation/AutomationEditingTest::pointMenuStaleDocumentCannotDeleteTarget"
    let stale = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  pan: [(24, 64), (120, 40)])
    stale.activate(stale.panLane)
    _ = stale.page.pointerPress(x: stale.x(24), y: stale.y(stale.panLane, 64),
                                 surface: 1, button: AutomationQtButton.right)
    _ = stale.page.pointerRelease(x: stale.x(24), y: stale.y(stale.panLane, 64),
                                   button: AutomationQtButton.right)
    report.expect(stale.page.menuTargetIsPoint, cppID: staleID,
                  message: "the stale target opens its point menu")
    stale.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                             through: 168, points: [LaneWrite(tick: 168, value: 5)])
    let rewritten = stale.snapshot
    report.expect(!stale.page.consumeMenuAction(
        actionId: AutomationMenuAction.deleteNode.rawValue), cppID: staleID,
                  message: "a stale point menu cannot delete its target")
    report.expect(!stale.page.menuOpen, cppID: staleID,
                  message: "the rejected row activation dismisses the stale point menu")
    report.expect(!stale.page.hasPrompt, cppID: staleID,
                  message: "the rejected row activation opens no prompt")
    report.expectEqual(expected: rewritten, actual: stale.snapshot, cppID: staleID,
                       what: "the rejected Delete leaves the rewritten lane intact")
    report.expectEqual(expected: ["24:64", "120:40", "168:5"], actual: stale.values(stale.panLane), cppID: staleID,
                       what: "the rejected Delete preserves the rewritten points")
}

@MainActor
func drawerAutomationDuplicatePromptAndParameterSwitch(_ report: CheckReport, suite: DocumentSession,
                                                       service: ProjectService) {
    let id = "automation/AutomationEditingTest::pointMenuValuePromptUpdatesOneDuplicateOccurrence"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 30), (24, 90)])
    fixture.activate(fixture.panLane)
    report.expectEqual(expected: ["24:30", "24:90"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "both duplicate occurrences stage")
    let before = fixture.snapshot
    report.expect(fixture.page.openPrompt(tick: 24, value: 30), cppID: id,
                  message: "a prompt opens on the duplicate tick")
    report.expect(fixture.page.acceptPrompt(displayedValue: -14), cppID: id,
                  message: "the duplicate value commits")
    report.expectEqual(expected: ["24:30", "24:50"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "only the targeted duplicate occurrence moves")
    report.expectEqual(expected: before.revision + 1, actual: fixture.document.revision, cppID: id,
                       what: "one duplicate acceptance is one revision")
    report.expect(fixture.undo(), cppID: id, message: "the duplicate acceptance undoes")
    report.expectEqual(expected: ["24:30", "24:90"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "undo restores both duplicate occurrences")

    let switchID = "automation/AutomationEditingTest::parameterSwitchInvalidatesValuePrompt"
    let switched = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    switched.activate(switched.panLane)
    report.expect(switched.page.openPrompt(tick: 24, value: 64), cppID: switchID,
                  message: "a prompt opens on the CC lane")
    switched.activate(.tempo)
    report.expect(!switched.page.hasPrompt, cppID: switchID,
                  message: "switching parameters closes the CC prompt")
    let tempoBefore = switched.snapshot
    report.expect(switched.page.openPrompt(tick: 0, value: 120), cppID: switchID,
                  message: "Tempo opens its own prompt")
    report.expect(switched.page.acceptPrompt(displayedValue: 150), cppID: switchID,
                  message: "Tempo commits its prompt")
    report.expectEqual(expected: ["0:150"], actual: switched.tempoValues, cppID: switchID,
                       what: "the tempo point stores the prompted BPM")
    let ccPoints = switched.lanePoints(switched.panLane)
    report.expectEqual(expected: ["24:64", "120:40"], actual: switched.values(switched.panLane),
                       cppID: switchID, what: "the CC lane stays untouched")
    report.expect(ccPoints.count == 2, cppID: switchID,
                  message: "the switch journey leaves two CC points")
    report.expect(ccPoints.count > 1 && ccPoints[1].tick == 120, cppID: switchID,
                  message: "the second CC point keeps its tick")
    report.expect(ccPoints.count > 1 && ccPoints[1].value == 40, cppID: switchID,
                  message: "the second CC point keeps its value")
    report.expectEqual(expected: tempoBefore.revision + 1, actual: switched.document.revision, cppID: switchID,
                       what: "Tempo's acceptance is one revision")
    let routed = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    routed.activate(routed.panLane)
    _ = routed.page.pointerPress(x: routed.x(24), y: routed.y(routed.panLane, 64), surface: 1, button: AutomationQtButton.right)
    _ = routed.page.pointerRelease(x: routed.x(24), y: routed.y(routed.panLane, 64), button: AutomationQtButton.right)
    report.expect(routed.page.menuTargetIsPoint, cppID: id, message: "the written point owns its Set Value menu target")
    report.expect(routed.page.menuOpen, cppID: id, message: "the point menu opens for the Set Value route")
    report.expect(routed.page.publishedMenuRows.first { $0.actionId == AutomationMenuAction.setValue.rawValue }?.enabled == true, cppID: id, message: "the point menu enables Set Value on a written node")
    report.expect(routed.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue), cppID: id, message: "the Set Value row is consumed")
    report.expect(routed.page.promptOpen, cppID: id, message: "the Set Value pick opens the value prompt")
    report.expectEqual(expected: AutomationPromptKind.value.rawValue, actual: routed.page.promptKind, cppID: id, what: "the Set Value pick opens the value form")
    report.expect(routed.page.interactionActive, cppID: id, message: "the open value prompt marks the page interacting")
    report.expect(!routed.page.promptDraft.isEmpty, cppID: id, message: "the value prompt carries its initial draft")
    routed.page.cancelPrompt()
    report.expect(!routed.page.hasPrompt && !routed.page.interactionActive, cppID: id, message: "cancelling the routed prompt drops the prompt and the interaction")
}

@MainActor
func drawerAutomationLaneDeleteConfirmation(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "automation/AutomationEditingTest::ccDeletePromptAcceptDeletesOnlyTargetLaneAndUndoRestores"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    volume: [(48, 70)],
                                                    pan: [(24, 60), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let before = fixture.snapshot
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0),
                  cppID: id, message: "the lane menu opens")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.deleteLaneEvents.rawValue),
                  cppID: id, message: "the Delete events row is consumed")
    report.expectEqual(expected: AutomationPromptKind.confirmLaneDelete.rawValue, actual: page.promptKind, cppID: id,
                       what: "the row opens the delete confirmation")
    report.expect(page.promptMessage.contains("2 written events"), cppID: id,
                  message: "the confirmation names the written count")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "opening the confirmation writes nothing")
    report.expect(page.acceptPromptDraft(), cppID: id, message: "the confirmation accepts")
    report.expectEqual(expected: [String](), actual: fixture.values(fixture.panLane), cppID: id,
                       what: "accept removes only the target lane")
    report.expectEqual(expected: ["48:70"], actual: fixture.values(fixture.volumeLane), cppID: id,
                       what: "the volume lane is preserved")
    report.expectEqual(expected: before.revision + 1, actual: fixture.document.revision, cppID: id,
                       what: "one acceptance is one revision")
    report.expect(fixture.undo(), cppID: id, message: "the acceptance undoes")
    report.expectEqual(expected: ["24:60", "120:40"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "undo restores the target lane")
    report.expect(!fixture.document.history.canUndo, cppID: id,
                  message: "the acceptance recorded exactly one history entry")

    let cancelID = "automation/AutomationEditingTest::ccDeletePromptCancelButtonLeavesDocumentUntouched"
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0)
    _ = page.consumeMenuAction(actionId: AutomationMenuAction.deleteLaneEvents.rawValue)
    let cancelBefore = fixture.snapshot
    page.cancelPrompt()
    report.expect(!page.hasPrompt, cppID: cancelID, message: "cancelling drops the confirmation")
    report.expectEqual(expected: cancelBefore, actual: fixture.snapshot, cppID: cancelID,
                       what: "cancelling leaves document and history untouched")

    let staleID = "automation/AutomationEditingTest::ccDeletePromptStaleDocumentCannotDeleteTarget"
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0)
    _ = page.consumeMenuAction(actionId: AutomationMenuAction.deleteLaneEvents.rawValue)
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                               through: 168, points: [LaneWrite(tick: 168, value: 5)])
    let rewritten = fixture.snapshot
    report.expect(!page.acceptPromptDraft(), cppID: staleID,
                  message: "a stale confirmation cannot delete its target")
    report.expectEqual(expected: rewritten, actual: fixture.snapshot, cppID: staleID,
                       what: "the rejected confirmation leaves the rewritten lane intact")
    report.expectEqual(expected: ["24:60", "120:40", "168:5"], actual: fixture.values(fixture.panLane),
                       cppID: staleID,
                       what: "the rejected confirmation preserves the rewritten points")

    let syntheticID = "automation/AutomationEditingTest::ccDeletePromptSyntheticOnlyVolumeSkipsConfirmation"
    let synthetic = drawerAutomationAutomationFixture(suite: suite, service: service)
    synthetic.activate(synthetic.volumeLane)
    let syntheticBefore = synthetic.snapshot
    _ = synthetic.page.openParameterMenu(
        index: synthetic.page.catalogIndex(of: synthetic.volumeLane), x: 0, y: 0)
    report.expect(synthetic.page.publishedMenuRows.first {
        $0.actionId == AutomationMenuAction.deleteLaneEvents.rawValue
    }?.enabled == false, cppID: syntheticID,
                  message: "the eventless lane disables Delete events")
    report.expect(!synthetic.page.consumeMenuAction(
        actionId: AutomationMenuAction.deleteLaneEvents.rawValue), cppID: syntheticID,
                  message: "the disabled row is refused")
    report.expect(!synthetic.page.hasPrompt, cppID: syntheticID,
                  message: "no confirmation opens for the eventless lane")
    report.expectEqual(expected: syntheticBefore, actual: synthetic.snapshot, cppID: syntheticID,
                       what: "the refused row writes nothing")

    let countID = "automation/AutomationEditingTest::ccDeletePromptDefaultLaneWrittenCountExcludesSynthetic"
    let single = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                   volume: [(48, 70)])
    single.activate(single.volumeLane)
    _ = single.page.openParameterMenu(
        index: single.page.catalogIndex(of: single.volumeLane), x: 0, y: 0)
    report.expect(single.page.consumeMenuAction(
        actionId: AutomationMenuAction.deleteLaneEvents.rawValue), cppID: countID,
                  message: "the Delete events row is consumed")
    report.expect(single.page.promptMessage.contains("1 written events"), cppID: countID,
                  message: "the confirmation counts written events only")
    report.expect(single.page.acceptPromptDraft(), cppID: countID,
                  message: "the confirmation accepts")
    report.expectEqual(expected: [String](), actual: single.values(single.volumeLane), cppID: countID,
                       what: "accept removes the written event")
    report.expect(single.page.catalogIndex(of: single.volumeLane) >= 0, cppID: countID,
                  message: "the volume parameter remains in the catalog")
    report.expect(single.undo(), cppID: countID, message: "the acceptance undoes")
    report.expectEqual(expected: ["48:70"], actual: single.values(single.volumeLane), cppID: countID,
                       what: "undo restores the written event")
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0)
    _ = page.consumeMenuAction(actionId: AutomationMenuAction.deleteLaneEvents.rawValue)
    report.expectEqual(expected: AutomationPromptKind.confirmLaneDelete.rawValue, actual: page.promptKind, cppID: id, what: "the reopened row owns the delete confirmation")
    report.expect(page.promptOpen, cppID: id, message: "the delete confirmation is open")
    report.expect(page.interactionActive, cppID: id, message: "the open confirmation marks the page interacting")
    let escapeID = "automation/AutomationEditingTest::ccDeletePromptEscapeLeavesDocumentUntouched"
    let confirmationEscapeBefore = fixture.snapshot
    report.expect(page.handleEscape(), cppID: escapeID, message: "Escape claims the open confirmation")
    report.expect(!page.promptOpen && !page.interactionActive, cppID: escapeID, message: "Escape drops the confirmation and the interaction")
    report.expectEqual(expected: confirmationEscapeBefore, actual: fixture.snapshot, cppID: escapeID, what: "Escape cancellation writes nothing")
}

@MainActor
func drawerAutomationOutsidePressRetarget(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    let id = "automation/AutomationEditingTest::outsideRightClickDismissesPointMenu"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    _ = page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                           surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                             button: AutomationQtButton.right)
    report.expect(page.menuTargetIsPoint, cppID: id,
                  message: "the first point owns its captured menu target")
    page.outsideMenuPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                          button: AutomationQtButton.right)
    report.expect(page.menuTargetIsPoint, cppID: id,
                  message: "an outside right press on another node retargets the menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue),
                  cppID: id, message: "the retargeted Delete row is consumed")
    report.expectEqual(expected: ["24:64"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "the retargeted Delete removes the second node only")
    report.expect(fixture.undo(), cppID: id, message: "the retargeted Delete undoes")

    _ = page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                           surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                             button: AutomationQtButton.right)
    report.expect(page.menuTargetIsPoint, cppID: id,
                  message: "the point menu reopens")
    let missBefore = fixture.snapshot
    page.outsideMenuPress(x: fixture.x(168), y: 60, button: AutomationQtButton.right)
    report.expect(!page.menuOpen, cppID: id, message: "the miss closes the shared menu")
    report.expect(!page.pointerRelease(x: fixture.x(168), y: 60, button: AutomationQtButton.right),
                  cppID: id, message: "the paired release claims no band")
    report.expectEqual(expected: missBefore, actual: fixture.snapshot, cppID: id,
                       what: "the dismissed menu writes nothing")
    let foreignID = "automation/AutomationEditingTest::pointMenuForeignPopupPublishedDuringOpenSurvives"
    _ = page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), button: AutomationQtButton.right)
    report.expect(page.menuTargetIsPoint, cppID: foreignID, message: "the point menu reopens for the Escape route")
    report.expect(page.menuOpen, cppID: foreignID, message: "the reopened point menu is open")
    let menuEscapeBefore = fixture.snapshot
    report.expect(page.handleEscape(), cppID: foreignID, message: "Escape claims the open point menu")
    report.expect(!page.menuOpen, cppID: foreignID, message: "Escape closes the open point menu")
    report.expectEqual(expected: menuEscapeBefore, actual: fixture.snapshot, cppID: foreignID, what: "Escape dismissal writes nothing")
}

@MainActor
func drawerAutomationSelectionInvalidation(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "automation/AutomationEditingTest::outsideRightClickDismissesPointMenu"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let before = fixture.snapshot
    let selection = { (start: Tick, end: Tick) in
        AutomationTimeSelection(range: TimeRange(startTick: start, endTick: end),
                                scope: .lanes, lanes: [fixture.panLane], tempo: false)
    }

    _ = page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                          surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                            button: AutomationQtButton.right)
    report.expect(page.menuOpen, cppID: id, message: "the point menu opens before selection changes")
    fixture.session.applyTimeSelection(selection(20, 100))
    report.expect(!page.menuOpen, cppID: id,
                  message: "a selection change dismisses the owned point menu")
    report.expect(!page.menuOpen && !page.hasPrompt, cppID: id,
                  message: "the selection-dismissed menu leaves no prompt open")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "dismissing the point menu for a selection writes nothing")

    report.expect(page.openPrompt(tick: 24, value: 64), cppID: id,
                  message: "the value prompt opens before selection changes")
    fixture.session.applyTimeSelection(selection(30, 110))
    report.expect(page.hasPrompt, cppID: id,
                  message: "a selection change spares the open value prompt")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "sparing the value prompt during selection writes nothing")
    page.cancelPrompt()

    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0)
    _ = page.consumeMenuAction(actionId: AutomationMenuAction.deleteLaneEvents.rawValue)
    report.expect(page.promptOpen, cppID: id,
                  message: "the lane-delete confirmation opens before selection changes")
    fixture.session.applyTimeSelection(selection(40, 130))
    report.expect(page.promptOpen, cppID: id,
                  message: "a selection change spares the lane-delete confirmation")
    report.expect(page.promptKind == AutomationPromptKind.confirmLaneDelete.rawValue,
                  cppID: id, message: "the spared confirmation keeps its delete content")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "sparing the lane-delete confirmation during selection writes nothing")
    page.cancelPrompt()
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "cancelling the spared confirmation writes nothing")
}

@MainActor
func drawerAutomationTrackSwitchInvalidation(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let id = "automation/AutomationEditingTest::consumedValuePromptCannotFollowTrackSwitch"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64)])
    let addedTrack = fixture.document.addTrack(voice: 0)
    let otherPan: AutomationParameter = .controlChange(track: 1, controller: TimeDefaults.ccPan)
    if addedTrack == 1 {
        fixture.document.writeLane(track: 1, lane: .controller(TimeDefaults.ccPan), from: 120,
                                   through: 120, points: [LaneWrite(tick: 120, value: 40)])
    }
    report.expect(addedTrack == 1 && fixture.values(otherPan) == ["120:40"], cppID: id,
                  message: "the second track stages its own lane point")
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: id,
                  message: "a prompt opens on the first track's node")
    fixture.session.selectedTrack = 1
    report.expect(!fixture.page.hasPrompt, cppID: id,
                  message: "switching tracks closes the open CC prompt")
    report.expect(fixture.page.catalogIndex(of: otherPan) >= 0, cppID: id,
                  message: "the switched page lists the second track's pan lane")
    report.expect(fixture.page.catalogIndex(of: fixture.panLane) == -1, cppID: id,
                  message: "the switched page drops the first track's pan lane")
    report.expect(!fixture.page.acceptPrompt(displayedValue: 10), cppID: id,
                  message: "the dropped prompt's late acceptance writes nothing")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "the switched prompt leaves both tracks and history untouched")
}

@MainActor
func drawerAutomationSharedPopupArbitration(_ report: CheckReport, suite: DocumentSession,
                                           service: ProjectService) {
    let id = "automation/AutomationEditingTest::sharedPopupArbitration"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    let audio: NativeAudio
    do {
        audio = try NativeAudio()
    } catch {
        report.fail(id, "the shared-popup fixture cannot create audio: \(error)")
        return
    }
    let playhead = SharedPlayheadPresenter()
    let guides = PlayheadGuidesPresenter()
    let eventList = EventListPresenter()
    let workspace = DocumentWorkspace(
        session: fixture.session, audio: audio, playhead: playhead,
        playheadGuides: guides, eventList: eventList, palette: GridPalette(),
        typography: Typography(baseFontPx: 13), callbacks: DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { _ in },
            revealTrackVoiceRequested: { _ in },
            gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
            publicationFailed: { _ in }, timeSignaturePromptInvalidated: { _, _ in }))
    defer {
        workspace.teardown()
        withExtendedLifetime((audio, playhead, guides, eventList)) {}
    }
    workspace.activate()
    let page = workspace.automationPage
    page.configureBody(width: 480, height: 120, gutter: workspace.grid.trackHeaderWidth
                       + workspace.grid.keyboardWidth, devicePixelRatio: 1,
                       baseFontPx: 13, dragDistance: 10)
    _ = page.activateParameter(index: page.catalogIndex(of: fixture.panLane))
    let before = fixture.snapshot
    let undoCount = fixture.document.history.undoCount
    let bytes = try? fixture.document.state.file.encoded()
    let selection = AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 100), scope: .lanes,
        lanes: [fixture.panLane], tempo: false)
    fixture.session.applyTimeSelection(selection)
    let missX = fixture.x(48)
    let missY = fixture.y(fixture.panLane, 20)
    _ = page.pointerPress(x: missX, y: missY, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: missX, y: missY, button: AutomationQtButton.right)
    report.expect(workspace.rulerMenu.isOpen && workspace.rulerMenu.menuKind == 2,
                  cppID: id, message: "a miss press inside the selection opens the time menu")
    report.expect(page.plotOrigin > 0 && workspace.rulerMenu.targetTick() == 48,
                  cppID: id, message: "the fallback time menu targets the band press tick")
    workspace.rulerMenu.close()
    report.expect(!workspace.rulerMenu.isOpen, cppID: id,
                  message: "Escape dismisses the fallback menu")
    _ = page.pointerPress(x: missX, y: missY, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: missX, y: missY, button: AutomationQtButton.right)
    _ = workspace.rulerMenu.activate(actionId: 8)
    report.expect(fixture.session.timeSelection == nil && !workspace.rulerMenu.isOpen,
                  cppID: id, message: "the fallback menu offers the time-selection rows")

    let pointX = fixture.x(24)
    let pointY = fixture.y(fixture.panLane, 64)
    _ = page.pointerPress(x: pointX, y: pointY, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: pointX, y: pointY, button: AutomationQtButton.right)
    workspace.grid.openGridMenu(kind: 1)
    report.expect(workspace.grid.gridMenuKind == 1 && !page.hasMenu,
                  cppID: id, message: "the division menu publishes over the open point menu")
    report.expect(!page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue)
                  && !page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue),
                  cppID: id, message: "the displaced point menu never returns")
    workspace.grid.activateGridMenuRow(actionId: 8)
    report.expect(workspace.grid.gridSelectionMenuId == 8 && workspace.grid.gridMenuKind == 0,
                  cppID: id, message: "the division pick changes the grid selection")
    report.expect(DocumentSnapshot(fixture.document) == before
                  && fixture.document.history.undoCount == undoCount
                  && (try? fixture.document.state.file.encoded()) == bytes,
                  cppID: id, message: "the takeover writes nothing")
    report.expect(!page.hasPrompt, cppID: id,
                  message: "no prompt surfaces after the takeover")

    _ = page.pointerPress(x: pointX, y: pointY, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: pointX, y: pointY, button: AutomationQtButton.right)
    workspace.rulerMenu.captureRulerPress(contentX: fixture.x(120), pointerY: 0)
    workspace.rulerMenu.openRulerAtRelease()
    report.expect(workspace.rulerMenu.isOpen && !page.hasMenu,
                  cppID: id, message: "the ruler menu replaces the open point menu")
    workspace.grid.openGridMenu(kind: 1)
    report.expect(!workspace.rulerMenu.isOpen && workspace.grid.gridMenuKind == 1,
                  cppID: id, message: "the division menu replaces the open ruler menu")
    workspace.grid.dismissGridMenu()

    let dismissForAutomation = page.onMenuOpened
    page.onMenuOpened = { [weak workspace] in
        dismissForAutomation?()
        workspace?.grid.openGridMenu(kind: 1)
    }
    _ = page.pointerPress(x: pointX, y: pointY, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: pointX, y: pointY, button: AutomationQtButton.right)
    page.onMenuOpened = dismissForAutomation
    report.expect(workspace.grid.gridMenuKind == 1 && !page.hasMenu,
                  cppID: id, message: "a menu published during another's open displaces it")
    workspace.grid.activateGridMenuRow(actionId: 16)
    report.expect(workspace.grid.gridSelectionMenuId == 16 && workspace.grid.gridMenuKind == 0,
                  cppID: id, message: "the surviving menu still picks a denominator")
    report.expect(page.openPrompt(tick: 24, value: 64), cppID: id,
                  message: "the value prompt opens beside a foreign menu")
    workspace.grid.openGridMenu(kind: 1)
    report.expect(page.hasPrompt && page.promptKind == AutomationPromptKind.value.rawValue,
                  cppID: id, message: "the foreign menu spares the open value prompt")
    _ = page.activateParameter(index: page.catalogIndex(of: .tempo))
    report.expect(!page.hasPrompt && !page.acceptPrompt(displayedValue: 100),
                  cppID: id, message: "the parameter switch invalidates the prompt beside a foreign menu")
    report.expect(workspace.grid.gridMenuKind == 1,
                  cppID: id, message: "the foreign menu survives the parameter switch")
    workspace.grid.activateGridMenuRow(actionId: 8)
    report.expect(workspace.grid.gridSelectionMenuId == 8 && workspace.grid.gridMenuKind == 0
                  && DocumentSnapshot(fixture.document) == before
                  && fixture.document.history.undoCount == undoCount
                  && (try? fixture.document.state.file.encoded()) == bytes,
                  cppID: id, message: "the post-switch pick still changes the grid selection")
}
