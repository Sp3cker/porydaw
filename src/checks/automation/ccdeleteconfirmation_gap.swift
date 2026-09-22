import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
private func drawerAutomationOpenLaneDeleteConfirmation(
    _ fixture: drawerAutomationAutomationFixture,
    parameter: AutomationParameter
) -> Bool {
    fixture.activate(parameter)
    let page = fixture.page
    guard page.openParameterMenu(index: page.catalogIndex(of: parameter), x: 0, y: 0),
          page.publishedMenuRows.contains(where: {
              $0.actionId == AutomationMenuAction.deleteLaneEvents.rawValue && $0.enabled
          }) else { return false }
    return page.consumeMenuAction(actionId: AutomationMenuAction.deleteLaneEvents.rawValue)
        && page.hasPrompt
        && page.promptKind == AutomationPromptKind.confirmLaneDelete.rawValue
}

@MainActor
func drawerAutomationCcDeleteConfirmationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::portableCcDeleteConfirmationGap"

    let accepted = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(192, 90)], pan: [(48, 40), (96, 100)]
    )
    let before = accepted.snapshot
    let beforeState = accepted.document.state
    let beforeBytes = try? accepted.document.state.file.encoded()
    report.expect(accepted.page.catalogIndex(of: accepted.panLane) >= 0
                      && accepted.page.catalogIndex(of: accepted.volumeLane) >= 0,
                  cppID: id, message: "A001-A003 target and foreign CC rows exist in the production catalog")
    report.expect(drawerAutomationOpenLaneDeleteConfirmation(accepted, parameter: accepted.panLane),
                  cppID: id, message: "A004-A008 the typed lane menu action opens a CC delete confirmation")
    report.expect(accepted.page.promptOpen && accepted.page.promptKind == AutomationPromptKind.confirmLaneDelete.rawValue
                      && accepted.page.promptMessage.contains("2")
                      && accepted.page.promptTitle == "Delete automation events",
                  cppID: id, message: "A009-A013 confirmation publishes the captured lane and its two written events")
    report.expect(accepted.page.acceptPromptDraft(), cppID: id,
                  message: "A014-A016 accepting the published confirmation commits through the prompt route")
    report.expect(accepted.values(accepted.panLane).isEmpty
                      && accepted.values(accepted.volumeLane) == ["192:90"],
                  cppID: id, message: "A017-A021 acceptance deletes only the target lane's written events")
    report.expect(accepted.document.revision == before.revision + 1
                      && accepted.document.history.canUndo
                      && accepted.snapshot.identity != before.identity,
                  cppID: id, message: "A022-A026 acceptance creates exactly one undoable document revision")
    report.expect(accepted.undo(), cppID: id, message: "A027 acceptance is undoable")
    report.expect(accepted.document.state == beforeState && !accepted.document.history.canUndo
                      && (try? accepted.document.state.file.encoded()) == beforeBytes,
                  cppID: id, message: "A028-A033 undo restores exact song bytes, both lanes, and history position")

    for route in ["cancel-button", "escape"] {
        let fixture = drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(48, 40), (96, 100)]
        )
        let frozen = fixture.snapshot
        let state = fixture.document.state
        report.expect(drawerAutomationOpenLaneDeleteConfirmation(fixture, parameter: fixture.panLane),
                      cppID: id, message: "A034-A050-\(route) confirmation opens for the cancellation route")
        if route == "escape" {
            report.expect(fixture.page.handleEscape(), cppID: id,
                          message: "A043-A046-escape the page consumes Escape while confirmation is open")
        } else {
            fixture.page.cancelPrompt()
        }
        report.expect(!fixture.page.hasPrompt && !fixture.page.interactionActive,
                      cppID: id, message: "A037-A050-\(route) cancellation closes the confirmation synchronously")
        report.expect(fixture.snapshot == frozen && fixture.document.state == state
                          && fixture.values(fixture.panLane) == ["48:40", "96:100"],
                      cppID: id, message: "A038-A050-\(route) cancellation preserves content, revision, and history")
    }

    let stale = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(48, 40), (96, 100)]
    )
    report.expect(drawerAutomationOpenLaneDeleteConfirmation(stale, parameter: stale.panLane),
                  cppID: id, message: "A074-A079 stale scenario captures the original lane revision")
    stale.document.writeLane(
        track: 0, lane: .controller(TimeDefaults.ccPan), from: 0, through: TimeDefaults.noTick,
        points: [LaneWrite(tick: 288, value: 77)]
    )
    let rewritten = stale.snapshot
    let rewrittenState = stale.document.state
    let rewrittenBytes = try? stale.document.state.file.encoded()
    report.expect(!stale.page.acceptPromptDraft(), cppID: id,
                  message: "A080-A083 a confirmation captured before another document write cannot commit")
    report.expectEqual(["288:77"], stale.values(stale.panLane), cppID: id,
                       what: "A084-A085 stale acceptance preserves the concurrent replacement lane")
    report.expect(stale.snapshot == rewritten && stale.document.state == rewrittenState
                      && (try? stale.document.state.file.encoded()) == rewrittenBytes,
                  cppID: id, message: "A086-A089 stale acceptance adds no revision or history entry")

    let synthetic = drawerAutomationAutomationFixture(
        suite: suite, service: service, volume: []
    )
    synthetic.activate(synthetic.volumeLane)
    let syntheticBefore = synthetic.snapshot
    report.expect(synthetic.page.projection?.eventCount == 0
                      && synthetic.page.projection?.points.count == 1
                      && synthetic.page.projection?.points.first?.projected == true,
                  cppID: id, message: "A120-A124 empty Volume publishes one synthetic node but zero written events")
    report.expect(synthetic.page.openParameterMenu(
        index: synthetic.page.catalogIndex(of: synthetic.volumeLane), x: 0, y: 0),
                  cppID: id, message: "A125-A127 the synthetic-only Volume lane menu opens")
    report.expect(synthetic.page.publishedMenuRows.contains(where: {
        $0.actionId == AutomationMenuAction.deleteLaneEvents.rawValue && !$0.enabled
    }), cppID: id, message: "A128-A130 synthetic-only Volume disables Delete automation events")
    report.expect(!synthetic.page.consumeMenuAction(
        actionId: AutomationMenuAction.deleteLaneEvents.rawValue),
                  cppID: id, message: "A131-A132 a disabled delete row opens no confirmation and commits nothing")
    report.expect(synthetic.snapshot == syntheticBefore && !synthetic.page.hasPrompt,
                  cppID: id, message: "A133-A134 synthetic-only deletion preserves document and history")

    let writtenDefault = drawerAutomationAutomationFixture(
        suite: suite, service: service, volume: [(96, 64)]
    )
    writtenDefault.activate(writtenDefault.volumeLane)
    let writtenBefore = writtenDefault.snapshot
    report.expect(writtenDefault.page.projection?.eventCount == 1
                      && writtenDefault.page.projection?.points.count == 2,
                  cppID: id, message: "A135-A140 one written default-lane event excludes the synthetic node from its count")
    report.expect(drawerAutomationOpenLaneDeleteConfirmation(writtenDefault,
                                                              parameter: writtenDefault.volumeLane),
                  cppID: id, message: "A141-A146 the written default lane opens confirmation through its menu")
    report.expect(writtenDefault.page.promptMessage.contains("1")
                      && !writtenDefault.page.promptMessage.contains("2 written"),
                  cppID: id, message: "A147-A150 confirmation advertises one written event, not two projected nodes")
    report.expect(writtenDefault.page.acceptPromptDraft(), cppID: id,
                  message: "A151-A153 default-lane confirmation accepts through the typed prompt route")
    report.expect(writtenDefault.values(writtenDefault.volumeLane).isEmpty
                      && writtenDefault.page.projection?.eventCount == 0,
                  cppID: id, message: "A154-A155 acceptance removes the sole written event and retains synthetic projection policy")
    report.expect(writtenDefault.document.revision == writtenBefore.revision + 1
                      && writtenDefault.document.history.canUndo,
                  cppID: id, message: "A156-A157 default-lane deletion is one undoable revision")
}
