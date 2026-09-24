import PorydawApp
import PorydawCore

@MainActor
func drawerAutomationOriginalClearMenus(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    let id = "automation/AutomationEditingTest::contextMenuActionsApplyEffects"
    // automationmenus.cpp:228-232: tempo 120 BPM and CC10=64, both at tick 48.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(48, 64)], tempo: [(48, 500_000)])
    let page = fixture.page
    let parameters: [AutomationParameter] = [.tempo, fixture.panLane]
    for parameter in parameters {
        report.expect(page.openParameterMenu(index: page.catalogIndex(of: parameter), x: 0, y: 0),
                      cppID: id, message: "the original parameter opens its lane menu")
        report.expect(page.publishedMenuRows.contains {
            $0.actionId == AutomationMenuAction.clearLane.rawValue && $0.enabled
        }, cppID: id, message: "the lane menu publishes the enabled Clear row")
        report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.clearLane.rawValue),
                      cppID: id, message: "the published Clear action is consumed")
        report.expect(!page.menuOpen, cppID: id, message: "Clear closes the lane menu")
        if parameter == .tempo {
            report.expect(fixture.document.state.tempo.isEmpty, cppID: id,
                          message: "Clear removes the original tempo point")
        } else {
            report.expect(fixture.lanePoints(parameter).isEmpty, cppID: id,
                          message: "Clear removes the original CC10 point")
        }

        // Original 251-252 and 266-267 switch away and back after each clear.
        let other = parameter == .tempo ? fixture.panLane : .tempo
        report.expect(page.activateParameter(index: page.catalogIndex(of: other)),
                      cppID: id, message: "the other parameter remains selectable")
        report.expect(page.activateParameter(index: page.catalogIndex(of: parameter)),
                      cppID: id, message: "the cleared parameter remains selectable")
        report.expectEqual(parameter, page.activeParameter, cppID: id,
                           what: "switching back selects the cleared parameter")
    }
}

@MainActor
func drawerAutomationOriginalRangeMenu(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let id = "automation/AutomationEditingTest::laneMenuValueRangeSubmenuPickRescalesAndCloses"
    // automationmenus.cpp: controller 21, written value 96 at tick 48.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service)
    let lane = AutomationParameter.controlChange(track: 0, controller: 21)
    fixture.document.writeLane(track: 0, lane: .controller(21), from: 0,
                               through: TimeDefaults.maxTick,
                               points: [LaneWrite(tick: 48, value: 96)])
    fixture.activate(lane)
    let page = fixture.page
    let before = fixture.snapshot
    let state = fixture.document.state
    let canUndo = fixture.document.history.canUndo
    let canRedo = fixture.document.history.canRedo
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: lane), x: 0, y: 0),
                  cppID: id, message: "original LFO label opens its lane menu")
    report.expect(page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.valueRange.rawValue && $0.hasSubmenu
    }, cppID: id, message: "the lane menu publishes a real Value range submenu")
    report.expect(page.menuChildRows.asArray.contains {
        $0.actionId == AutomationMenuAction.range64.rawValue && $0.enabled
    }, cppID: id, message: "the submenu publishes the enabled 0-64 choice")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.range64.rawValue),
                  cppID: id, message: "the original range choice is accepted")
    report.expect(!page.menuOpen, cppID: id, message: "a normal range pick closes the menu")
    report.expectEqual(64, page.scaleLabels.first?.value, cppID: id,
                       what: "the selected range rescales the lane to 64")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "range selection preserves document revision and history identity")
    report.expect(fixture.document.state == state, cppID: id,
                  message: "range selection preserves all song content")
    report.expect(fixture.document.history.canUndo == canUndo &&
                  fixture.document.history.canRedo == canRedo,
                  cppID: id, message: "range selection preserves history availability")
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: lane), x: 0, y: 0),
                  cppID: id, message: "the same LFO menu reopens")
    report.expect(page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.valueRange.rawValue && $0.hasSubmenu
    }, cppID: id, message: "the reopened lane menu still publishes Value range")
    report.expect(page.menuChildRows.asArray.contains {
        $0.actionId == AutomationMenuAction.range64.rawValue && $0.checked
    }, cppID: id, message: "the reopened submenu advertises the applied range")
    page.dismissMenu()
    report.expect(!page.menuOpen, cppID: id, message: "dismissal closes the reopened menu")
    report.expect(fixture.undo(), cppID: id, message: "one undo still reaches the preceding lane write")
    report.expect(fixture.document.lanePoints(track: 0, lane: .controller(21)).isEmpty,
                  cppID: id, message: "range picks inserted no history entries before the lane write")
}
