import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
private func drawerAutomationOpenPointMenu(
    _ fixture: drawerAutomationAutomationFixture,
    parameter: AutomationParameter,
    tick: Tick,
    value: Int
) -> Bool {
    fixture.activate(parameter)
    guard let point = fixture.page.projection?.points.first(where: {
        $0.tick == tick && $0.value == value
    }) else { return false }
    let pressed = fixture.page.pointerPress(
        x: point.x,
        y: point.y,
        surface: AutomationInputSurface.plot.rawValue,
        button: 2,
        modifiers: 0
    )
    let released = fixture.page.pointerRelease(
        x: point.x,
        y: point.y,
        surface: AutomationInputSurface.plot.rawValue,
        button: 2,
        modifiers: 0
    )
    return pressed && released && fixture.page.menuOpen
}

@MainActor
func drawerAutomationPointMenuDeleteGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointMenuDeleteGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(24, 32), (120, 64)]
    )
    let beforeSnapshot = fixture.snapshot
    let beforeState = fixture.document.state
    let beforeBytes = try? fixture.document.state.file.encoded()
    report.expect(drawerAutomationOpenPointMenu(fixture, parameter: fixture.panLane, tick: 24, value: 32), cppID: id, message: "A001-A003 right click opens the written point menu")
    report.expect(fixture.page.observation.menuTarget == .point(tick: 24, value: 32), cppID: id, message: "A004-A006 point menu captures the clicked tick and value")
    report.expect(fixture.page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.deleteNode.rawValue && $0.enabled
    }, cppID: id, message: "A006 point menu publishes enabled Delete")
    report.expect(fixture.page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue), cppID: id, message: "A007 Delete action is consumed")
    report.expect(!fixture.page.menuOpen && !fixture.page.interactionActive, cppID: id, message: "A008 Delete closes the menu interaction")
    report.expectEqual(["120:64"], fixture.values(fixture.panLane), cppID: id, what: "A009-A010 Delete removes only the captured point")
    report.expectEqual(beforeSnapshot.revision + 1, fixture.document.revision, cppID: id, what: "A011 Delete commits one revision")
    report.expect(fixture.snapshot.identity != beforeSnapshot.identity && fixture.snapshot.canUndo, cppID: id, message: "A012 Delete creates one undoable history entry")
    report.expect(fixture.undo(), cppID: id, message: "A013 Delete is undoable")
    report.expectEqual(["24:32", "120:64"], fixture.values(fixture.panLane), cppID: id, what: "A014 undo restores the deleted point")
    report.expect(fixture.document.state == beforeState && !fixture.document.history.canUndo
                      && (try? fixture.document.state.file.encoded()) == beforeBytes,
                  cppID: id, message: "A015 undo restores the exact serialized document and history state")
}

@MainActor
func drawerAutomationPointMenuSetValueGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointMenuSetValueGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        modulation: [(24, 32), (24, 32)]
    )
    let beforeSnapshot = fixture.snapshot
    report.expectEqual(2, fixture.lanePoints(fixture.modulationLane).count(where: { $0.tick == 24 }), cppID: id, what: "A016 fixture contains two independent occurrences at the target tick")
    report.expect(drawerAutomationOpenPointMenu(fixture, parameter: fixture.modulationLane, tick: 24, value: 32), cppID: id, message: "duplicate point menu opens")
    report.expect(fixture.page.observation.menuTarget == .point(tick: 24, value: 32), cppID: id, message: "menu captures the selected duplicate value")
    report.expect(fixture.page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.setValue.rawValue && $0.enabled
    }, cppID: id, message: "menu publishes enabled Set Value")
    report.expect(fixture.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue), cppID: id, message: "Set Value action is consumed")
    report.expect(fixture.page.hasPrompt && fixture.page.promptDraft == "32", cppID: id, message: "A022 prompt selects the captured duplicate value")
    report.expect(fixture.page.acceptPrompt(displayedValue: 64), cppID: id, message: "changed prompt value is accepted")
    report.expectEqual(["24:32", "24:64"], fixture.values(fixture.modulationLane), cppID: id, what: "A024-A028 Set Value replaces one duplicate and preserves its sibling")
    report.expectEqual(2, fixture.lanePoints(fixture.modulationLane).count(where: { $0.tick == 24 }), cppID: id, what: "A024 replacement preserves duplicate occurrence count")
    report.expectEqual(beforeSnapshot.revision + 1, fixture.document.revision, cppID: id, what: "A029 prompt acceptance commits one revision")
    report.expect(fixture.snapshot.identity != beforeSnapshot.identity && fixture.snapshot.canUndo, cppID: id, message: "A030 prompt acceptance creates one undoable entry")
}

@MainActor
func drawerAutomationPointMenuDismissGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointMenuDismissGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        modulation: [(24, 32)]
    )
    let before = fixture.snapshot
    let beforeState = fixture.document.state
    report.expect(drawerAutomationOpenPointMenu(fixture, parameter: fixture.modulationLane, tick: 24, value: 32), cppID: id, message: "A032 written point menu opens for prompt cancellation")
    report.expect(fixture.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue), cppID: id, message: "Set Value opens the prompt")
    report.expect(fixture.page.hasPrompt && fixture.page.promptDraft == "32", cppID: id, message: "prompt captures the point value")
    fixture.page.cancelPrompt()
    report.expect(!fixture.page.hasPrompt && !fixture.page.interactionActive, cppID: id, message: "cancel closes the value prompt")
    report.expectEqual(["24:32"], fixture.values(fixture.modulationLane), cppID: id, what: "A039 prompt cancellation preserves the single lane point")
    report.expect(fixture.document.state == beforeState && fixture.snapshot == before, cppID: id, message: "A037-A038 prompt cancellation writes no revision or history")

    report.expect(drawerAutomationOpenPointMenu(fixture, parameter: fixture.modulationLane, tick: 24, value: 32), cppID: id, message: "A054 original point menu reopens")
    fixture.page.outsideMenuPress(x: 470, y: 112, button: 2)
    report.expect(!fixture.page.menuOpen && fixture.page.observation.menuTarget == nil, cppID: id, message: "A055-A058 outside right click with no point dismisses instead of retargeting")
    report.expect(fixture.document.state == beforeState && fixture.snapshot == before, cppID: id, message: "A059-A060 outside dismissal writes nothing")
}

@MainActor
func drawerAutomationPointMenuRetargetGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointMenuRetargetGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(24, 32), (120, 64)]
    )
    let before = fixture.snapshot
    let beforeBytes = try? fixture.document.state.file.encoded()
    report.expect(drawerAutomationOpenPointMenu(fixture, parameter: fixture.panLane, tick: 24, value: 32), cppID: id, message: "A061-A063 original point menu opens")
    guard let destination = fixture.page.projection?.points.first(where: {
        $0.tick == 120 && $0.value == 64
    }) else {
        report.fail(id, "A064 destination point projects")
        return
    }
    fixture.page.outsideMenuPress(x: destination.x, y: destination.y, button: 2)
    report.expect(fixture.page.menuOpen && fixture.page.observation.menuTarget == .point(tick: 120, value: 64), cppID: id, message: "A064-A070 outside right click retargets to the destination point")
    report.expect(fixture.page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.deleteNode.rawValue && $0.enabled
    }, cppID: id, message: "A071 retargeted point publishes enabled Delete")
    report.expect(fixture.page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue), cppID: id, message: "A072 retargeted Delete is consumed")
    report.expectEqual(["24:32"], fixture.values(fixture.panLane), cppID: id, what: "A073-A076 retargeted Delete removes only the destination point")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: id, what: "A077 retargeted Delete commits once")
    report.expect(fixture.undo() && !fixture.document.history.canUndo
                      && (try? fixture.document.state.file.encoded()) == beforeBytes,
                  cppID: id, message: "A067-A079 one undo restores retargeted Delete and exact bytes")
}

@MainActor
func drawerAutomationPointMenuStaleTargetGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointMenuStaleTargetGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(24, 32), (120, 64)]
    )
    report.expect(drawerAutomationOpenPointMenu(fixture, parameter: fixture.panLane, tick: 24, value: 32), cppID: id, message: "A129-A134 point menu captures the original document revision")
    fixture.document.writeLane(
        track: 0,
        lane: .controller(TimeDefaults.ccPan),
        from: 0,
        through: TimeDefaults.noTick,
        points: [LaneWrite(tick: 72, value: 77)]
    )
    let rewritten = fixture.snapshot
    let rewrittenState = fixture.document.state
    let rewrittenBytes = try? fixture.document.state.file.encoded()
    report.expect(!fixture.page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue), cppID: id, message: "A135-A137 stale Delete action is rejected")
    report.expectEqual(["72:77"], fixture.values(fixture.panLane), cppID: id, what: "A138-A139 stale action preserves the replacement lane")
    report.expect(fixture.document.state == rewrittenState && fixture.snapshot == rewritten
                      && (try? fixture.document.state.file.encoded()) == rewrittenBytes,
                  cppID: id, message: "A135-A142 stale action preserves rewritten bytes, revision, and history")
}

@MainActor
func drawerAutomationPointPromptParameterSwitchGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointPromptParameterSwitchGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(24, 32), (120, 64)],
        tempo: []
    )
    let before = fixture.snapshot
    let beforeState = fixture.document.state
    let beforeBytes = try? fixture.document.state.file.encoded()
    report.expect(drawerAutomationOpenPointMenu(fixture, parameter: fixture.panLane, tick: 24, value: 32), cppID: id, message: "A182-A183 pan point menu opens")
    report.expect(fixture.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue), cppID: id, message: "pan Set Value opens its prompt")
    report.expect(fixture.page.hasPrompt && fixture.page.promptDraft == "-32", cppID: id, message: "prompt captures the pan value")
    fixture.activate(.tempo)
    report.expect(fixture.page.activeParameter == .tempo && !fixture.page.hasPrompt
                      && !fixture.page.interactionActive,
                  cppID: id, message: "A195-A196 parameter switch activates Tempo and invalidates the old prompt")
    report.expect(!fixture.page.acceptPrompt(displayedValue: 10), cppID: id, message: "invalidated prompt cannot commit")
    report.expect(fixture.document.state == beforeState && fixture.snapshot == before, cppID: id, message: "A200 invalidated prompt writes nothing")

    report.expect(fixture.page.openPrompt(tick: 120, value: 120), cppID: id, message: "A205-A207 fresh tempo insertion prompt opens after the switch")
    report.expect(fixture.page.hasPrompt && fixture.page.promptDraft == "120", cppID: id, message: "A210 fresh prompt selects the default tempo value")
    report.expect(fixture.page.acceptPrompt(displayedValue: 180), cppID: id, message: "fresh prompt accepts the insertion")
    report.expectEqual(["120:180"], fixture.tempoValues, cppID: id, what: "A214-A215 fresh prompt inserts one tempo point with the requested value")
    report.expectEqual(["24:32", "120:64"], fixture.values(fixture.panLane), cppID: id, what: "A216-A220 tempo insertion preserves both controller points")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: id, what: "A212 fresh prompt commits one revision")
    report.expect(fixture.snapshot.canUndo && fixture.snapshot.identity != before.identity,
                  cppID: id, message: "A213-A221 fresh prompt creates one undoable history entry")
    report.expect(fixture.undo(), cppID: id, message: "A222 fresh prompt is undoable")
    report.expect(fixture.tempoValues.isEmpty, cppID: id, message: "A223 undo removes the inserted tempo point")
    report.expect(fixture.document.state == beforeState && !fixture.document.history.canUndo
                      && (try? fixture.document.state.file.encoded()) == beforeBytes,
                  cppID: id, message: "A224 undo restores exact serialized document and history state")
}

@MainActor
func drawerAutomationPointMenuSelectionInvalidationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointMenuSelectionInvalidationGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        modulation: [(24, 32)]
    )
    fixture.activate(fixture.modulationLane)
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    let baselineBytes = try? fixture.document.state.file.encoded()
    let firstSelection = AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96),
        scope: .lanes,
        lanes: [fixture.modulationLane]
    )
    fixture.page.applyTimeSelection(firstSelection)
    report.expect(fixture.page.selection == firstSelection,
                  cppID: id, message: "A054 automation band owns the explicit time selection")

    let rangeX = fixture.x(72)
    _ = fixture.page.pointerPress(
        x: rangeX,
        y: 100,
        surface: AutomationInputSurface.plot.rawValue,
        button: 2,
        modifiers: 0
    )
    _ = fixture.page.pointerRelease(
        x: rangeX,
        y: 100,
        surface: AutomationInputSurface.plot.rawValue,
        button: 2,
        modifiers: 0
    )
    report.expect(fixture.page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.rangeClear.rawValue && $0.enabled
    }, cppID: id, message: "A070 fallback range menu publishes enabled Clear")
    fixture.page.dismissMenu()

    _ = drawerAutomationOpenPointMenu(
        fixture,
        parameter: fixture.modulationLane,
        tick: 24,
        value: 32
    )
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 48, endTick: 120),
        scope: .lanes,
        lanes: [fixture.modulationLane]
    ))
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && (try? fixture.document.state.file.encoded()) == baselineBytes,
                  cppID: id, message: "A075-A077 point-menu selection invalidation writes nothing")
    fixture.page.dismissMenu()

    _ = drawerAutomationOpenPointMenu(
        fixture,
        parameter: fixture.modulationLane,
        tick: 24,
        value: 32
    )
    _ = fixture.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue)
    fixture.page.applyTimeSelection(firstSelection)
    fixture.page.cancelPrompt()
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && (try? fixture.document.state.file.encoded()) == baselineBytes,
                  cppID: id, message: "A083-A085 value-prompt selection change and cancel write nothing")

    _ = fixture.page.openParameterMenu(
        index: fixture.page.catalogIndex(of: fixture.modulationLane),
        x: 0,
        y: 0
    )
    _ = fixture.page.consumeMenuAction(actionId: AutomationMenuAction.deleteLaneEvents.rawValue)
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 144),
        scope: .lanes,
        lanes: [fixture.modulationLane]
    ))
    fixture.page.cancelPrompt()
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && (try? fixture.document.state.file.encoded()) == baselineBytes,
                  cppID: id, message: "A091-A093 lane-delete selection change and cancel write nothing")
}

@MainActor
func drawerAutomationPointPromptTrackSwitchGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pointPromptTrackSwitchGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        modulation: [(24, 32)]
    )
    report.expect(fixture.document.addTrack(voice: 0) == 1,
                  cppID: id, message: "A041 fixture adds the secondary engine track")
    let trackA = fixture.modulationLane
    let trackB = AutomationParameter.controlChange(
        track: 1,
        controller: TimeDefaults.ccModulation
    )
    fixture.activate(trackA)
    report.expect(fixture.page.activeParameter == trackA,
                  cppID: id, message: "A042 source-track modulation row activates")
    _ = drawerAutomationOpenPointMenu(
        fixture,
        parameter: trackA,
        tick: 24,
        value: 32
    )
    _ = fixture.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue)
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    let baselineBytes = try? fixture.document.state.file.encoded()

    fixture.session.selectedTrack = 1
    fixture.page.refreshFromDocument()
    report.expect(fixture.session.selectedTrack == 1
                      && fixture.page.activeParameter == trackB
                      && fixture.page.catalogIndex(of: trackB) >= 0,
                  cppID: id, message: "A047-A048 switch publishes the destination-track row")
    report.expect(fixture.page.catalogIndex(of: trackA) == -1,
                  cppID: id, message: "A049 source-track row is absent after the switch")
    report.expect(!fixture.page.acceptPrompt(displayedValue: 64),
                  cppID: id, message: "consumed source prompt cannot commit after track switch")
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && (try? fixture.document.state.file.encoded()) == baselineBytes,
                  cppID: id, message: "A051-A053 stale prompt attempt preserves bytes, revision, and undo state")
}

@MainActor
func drawerAutomationSyntheticPointMenuGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::syntheticPointMenuGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: []
    )
    fixture.activate(fixture.volumeLane)
    let volumeIndex = fixture.page.catalogIndex(of: fixture.volumeLane)
    let synthetic = fixture.page.projection?.points.first
    report.expect(fixture.page.trackAvailable && volumeIndex >= 0
                      && fixture.page.activeParameter == fixture.volumeLane,
                  cppID: id, message: "A094-A095 empty Volume row is valid and active")
    report.expect(synthetic != nil && fixture.page.projection?.points.isEmpty == false
                      && fixture.values(fixture.volumeLane).isEmpty,
                  cppID: id, message: "A096-A097 empty lane publishes only its synthetic default")
    report.expect(fixture.page.publishedTabs.count == fixture.page.parameterLabels.count
                      && fixture.page.publishedTabs[volumeIndex].eventCount == 0,
                  cppID: id, message: "A098-A100 selector counts align and Volume reports no events")

    guard let synthetic else {
        report.expect(false, cppID: id, message: "synthetic Volume point is required")
        return
    }
    _ = drawerAutomationOpenPointMenu(
        fixture,
        parameter: fixture.volumeLane,
        tick: synthetic.tick,
        value: synthetic.value
    )
    report.expect(fixture.page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.deleteNode.rawValue && !$0.enabled
    }, cppID: id, message: "A102 synthetic default publishes disabled Delete")
    report.expect(fixture.page.publishedMenuRows.contains {
        $0.actionId == AutomationMenuAction.setValue.rawValue && $0.enabled
    }, cppID: id, message: "A103 synthetic default publishes enabled Set Value")
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    let baselineBytes = try? fixture.document.state.file.encoded()
    report.expect(!fixture.page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue)
                      && fixture.document.state == baselineState && fixture.snapshot == baseline
                      && (try? fixture.document.state.file.encoded()) == baselineBytes,
                  cppID: id, message: "A108-A111 disabled Delete preserves document and history")

    _ = fixture.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue)
    report.expect(fixture.page.promptDraft == String(synthetic.value),
                  cppID: id, message: "A116 Set Value selects the engine default")
    report.expect(fixture.page.acceptPrompt(displayedValue: 3),
                  cppID: id, message: "synthetic Set Value commits the requested value")
    report.expectEqual(["0:3"], fixture.values(fixture.volumeLane),
                       cppID: id, what: "A118-A120 synthetic default promotes to one written point")
    report.expect(fixture.document.revision == baseline.revision + 1
                      && fixture.snapshot.canUndo
                      && fixture.snapshot.identity != baseline.identity,
                  cppID: id, message: "A121-A123 promotion creates one revision and one undo entry")
    report.expect(fixture.snapshot.canUndo,
                  cppID: id, message: "A124 promoted point is undoable")
    report.expect(fixture.undo(), cppID: id, message: "A125 promoted point undo applies")
    report.expect(fixture.values(fixture.volumeLane).isEmpty
                      && fixture.document.state == baselineState
                      && (try? fixture.document.state.file.encoded()) == baselineBytes,
                  cppID: id, message: "A126-A127 undo restores empty lane and exact bytes")
}
