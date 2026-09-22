import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

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
    fixture.drag(fixture.panLane, from: (24, 60), to: 70, modifiers: DrawerModifiers.altBit)
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
    _ = page.pointerPress(x: x, y: y, surface: 1, button: 1)
    _ = page.pointerRelease(x: x, y: y, button: 1)
    report.expectEqual([String](), fixture.values(fixture.panLane), cppID: id,
                       what: "stationary selection click deletes grabbed node only")
    report.expectEqual(["48:70"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "stationary selection click preserves other lanes")
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: 2)
    _ = page.pointerRelease(x: 400, y: 90, button: 2)
    report.expect(page.selection == nil, cppID: id,
                  message: "outside right press clears selection before opening a menu")
    page.dismissMenu()
    page.selectRange(from: 0, to: fixture.songEndTick, lanes: [fixture.panLane])
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: 2)
    _ = page.pointerMove(x: 404, y: 86, buttons: 2)
    report.expect(!page.bandVisible && page.selection?.range == TimeRange(
        startTick: 0, endTick: fixture.songEndTick), cppID: id,
                  message: "a pending band preserves selection below the Manhattan threshold")
    _ = page.pointerMove(x: 405, y: 85, buttons: 2)
    report.expect(page.bandVisible, cppID: id,
                  message: "diagonal travel activates at Manhattan ten before Euclidean ten")
    _ = page.pointerMove(x: 400, y: 60, buttons: 2)
    _ = page.pointerRelease(x: 400, y: 60, button: 2)
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
                                        button: 2)
        _ = synthetic.page.pointerRelease(x: point.x, y: point.y, button: 2)
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
                                 surface: 1, button: 2)
    _ = hover.page.pointerRelease(x: hover.x(48), y: hover.y(hover.volumeLane, 70),
                                   button: 2)
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

@MainActor
func drawerAutomationBandSelectionIsolationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::bandSelectionIsolationGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(48, 36)],
        modulation: [(48, 72)],
        tempo: [(0, 500_000), (48, 400_000)]
    )
    let initialSnapshot = fixture.snapshot
    let initialState = fixture.document.state
    fixture.activate(.tempo)
    report.expect((try? fixture.document.state.file.encoded()) != nil,
                  cppID: id, message: "A001 mixed automation fixture has a serializable document")
    report.expect(fixture.projection(.tempo).points.isEmpty == false,
                  cppID: id, message: "A002-A004 Tempo lane and body are valid and populated")
    report.expect(fixture.projection(fixture.panLane).points.isEmpty == false,
                  cppID: id, message: "A003-A005 Pan lane and body are valid and populated")
    report.expect(fixture.page.trackAvailable && fixture.page.plotWidth > 0
                      && fixture.page.plotHeight > 0,
                  cppID: id, message: "A001-A006 automation plot and mixed fixture are available")

    let bandStartX = fixture.x(24)
    let bandEndX = fixture.x(96)
    report.expect(fixture.page.pointerPress(
        x: bandStartX,
        y: 104,
        surface: AutomationInputSurface.plot.rawValue,
        button: 2,
        modifiers: 0
    ), cppID: id, message: "A009 tempo right press starts a band")
    _ = fixture.page.pointerMove(x: bandEndX, y: 108, buttons: 2, modifiers: 0)
    report.expect(fixture.page.pointerRelease(
        x: bandEndX,
        y: 108,
        button: 2,
        modifiers: 0
    ), cppID: id, message: "A010 tempo right drag commits a band")
    report.expect(fixture.page.selection?.range == TimeRange(startTick: 24, endTick: 96),
                  cppID: id, message: "A009 tempo band publishes the dragged tick range")
    report.expect(fixture.page.selection?.tempo == true
                      && fixture.page.selection?.lanes.isEmpty == true,
                  cppID: id, message: "A011-A014 tempo band contains Tempo and excludes CC lanes")
    report.expect(fixture.page.selectedParameters == [.tempo],
                  cppID: id, message: "A015 selection membership is isolated to Tempo")
    report.expect(fixture.snapshot == initialSnapshot && fixture.document.state == initialState,
                  cppID: id, message: "A016 band creation writes no document or history")
    let beforeTempoDrag = fixture.snapshot

    let sourceX = fixture.x(48)
    let destinationX = fixture.x(96)
    let sourceY = fixture.y(.tempo, 150)
    report.expect(fixture.page.pointerPress(
        x: sourceX,
        y: sourceY,
        surface: AutomationInputSurface.plot.rawValue,
        button: 1,
        modifiers: DrawerModifiers.shiftBit
    ), cppID: id, message: "A017 selected tempo node press is handled")
    report.expect(fixture.snapshot == beforeTempoDrag,
                  cppID: id, message: "A015 tempo drag press writes no document or history")
    _ = fixture.page.pointerMove(
        x: sourceX,
        y: sourceY - 30,
        buttons: 1,
        modifiers: DrawerModifiers.shiftBit
    )
    _ = fixture.page.pointerMove(
        x: destinationX,
        y: sourceY,
        buttons: 1,
        modifiers: DrawerModifiers.shiftBit
    )
    report.expect(fixture.page.pointerRelease(
        x: destinationX,
        y: sourceY,
        button: 1,
        modifiers: DrawerModifiers.shiftBit
    ), cppID: id, message: "A018 selected tempo drag commits")
    report.expectEqual(["0:120", "96:150"], fixture.tempoValues, cppID: id,
                       what: "A019-A020 tempo point moves to the destination with its value")
    report.expectEqual(["48:36"], fixture.values(fixture.panLane), cppID: id,
                       what: "A021 pan lane remains unchanged by tempo selection drag")
    report.expectEqual(["48:72"], fixture.values(fixture.modulationLane), cppID: id,
                       what: "A021 modulation lane remains unchanged by tempo selection drag")
    report.expectEqual(initialSnapshot.revision + 1, fixture.document.revision, cppID: id,
                       what: "A022 selected tempo drag commits one revision")
    report.expect(fixture.snapshot.canUndo && fixture.snapshot.identity != initialSnapshot.identity,
                  cppID: id, message: "A021 selected tempo drag creates an undoable history entry")
    report.expect(fixture.undo(), cppID: id, message: "A022 selected tempo drag is undoable")
    report.expectEqual(["0:120", "48:150"], fixture.tempoValues, cppID: id,
                       what: "A023 undo restores the tempo point at the selection tick")
    report.expect(fixture.document.state == initialState && !fixture.document.history.canUndo,
                  cppID: id, message: "A024 undo restores the complete mixed document and history position")

    fixture.activate(fixture.panLane)
    report.expect(fixture.page.activeParameter == fixture.panLane,
                  cppID: id, message: "A024 Pan parameter activates for the second band")
    report.expect(fixture.page.pointerPress(
        x: bandStartX,
        y: 104,
        surface: AutomationInputSurface.plot.rawValue,
        button: 2,
        modifiers: 0
    ), cppID: id, message: "A025 pan right press starts a replacement band")
    _ = fixture.page.pointerMove(x: bandEndX, y: 108, buttons: 2, modifiers: 0)
    _ = fixture.page.pointerRelease(
        x: bandEndX,
        y: 108,
        button: 2,
        modifiers: 0
    )
    report.expect(fixture.page.selection?.range == TimeRange(startTick: 24, endTick: 96),
                  cppID: id, message: "A025 Pan band publishes the same dragged tick range")
    report.expect(fixture.page.selection?.tempo == false
                      && fixture.page.selection?.lanes == Set([fixture.panLane]),
                  cppID: id, message: "A026 replacement band contains only Pan")
    report.expect(fixture.page.selectedParameters == [fixture.panLane],
                  cppID: id, message: "A027 Pan is selected after the active-row switch")
    report.expect(!fixture.page.selectedParameters.contains(.tempo),
                  cppID: id, message: "A028 Tempo is not selected by the Pan-row band")
}

@MainActor
func drawerAutomationGhostToggleSkipsEventlessLaneGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::ghostToggleSkipsEventlessLaneGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: [(48, 70)],
        modulation: []
    )
    fixture.activate(fixture.volumeLane)
    let volumeIndex = fixture.page.catalogIndex(of: fixture.volumeLane)
    let eventlessIndex = fixture.page.catalogIndex(of: fixture.modulationLane)
    report.expect(fixture.page.trackAvailable, cppID: id,
                  message: "A166 automation page is attached to the fixture track")
    report.expect(fixture.page.activeParameter == fixture.volumeLane,
                  cppID: id, message: "A167 populated Volume lane is active")
    report.expect(volumeIndex >= 0,
                  cppID: id, message: "A168 populated Volume row has a catalog index")
    report.expect(eventlessIndex >= 0 && eventlessIndex < fixture.page.publishedTabs.count,
                  cppID: id, message: "A168 eventless Modulation row is published")
    report.expect(fixture.values(fixture.modulationLane).isEmpty,
                  cppID: id, message: "A169 Modulation lane has no written events")
    report.expect(!fixture.page.toggleGhostParameter(index: eventlessIndex),
                  cppID: id, message: "A170 eventless lane rejects ghost enablement")
    report.expect(fixture.page.activeParameter == fixture.volumeLane,
                  cppID: id, message: "A171 rejected ghost toggle keeps Volume active")
    report.expect(fixture.page.ghostParameters.isEmpty,
                  cppID: id, message: "A172 rejected toggle publishes no ghost lane")
    report.expect(fixture.page.publishedTabs[eventlessIndex].ghosted == false,
                  cppID: id, message: "A173 eventless row remains visibly unghosted")
}

@MainActor
func drawerAutomationPopulatedGhostToggleGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::populatedGhostToggleGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: [(48, 70)],
        pan: [(24, 60)]
    )
    fixture.activate(fixture.volumeLane)
    let volumeIndex = fixture.page.catalogIndex(of: fixture.volumeLane)
    let panIndex = fixture.page.catalogIndex(of: fixture.panLane)
    let selectionBefore = fixture.page.selectedParameters
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    let baselineBytes = try? fixture.document.state.file.encoded()
    report.expect(fixture.page.trackAvailable && volumeIndex >= 0 && panIndex >= 0,
                  cppID: id, message: "A144-A147 populated Volume and Pan rows are valid")

    report.expect(fixture.page.toggleGhostParameter(index: panIndex),
                  cppID: id, message: "A148 populated Pan accepts ghost enablement")
    report.expect(fixture.page.ghostParameters == [fixture.panLane]
                      && fixture.page.activeParameter == fixture.volumeLane
                      && fixture.page.selectedParameters == selectionBefore,
                  cppID: id, message: "A149-A151 ghost toggle preserves active row and selection")
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && (try? fixture.document.state.file.encoded()) == baselineBytes,
                  cppID: id, message: "A152-A155 ghost toggle is document and history neutral")

    fixture.activate(.tempo)
    fixture.activate(fixture.volumeLane)
    report.expect(fixture.page.activeParameter == fixture.volumeLane
                      && fixture.page.ghostParameters == [fixture.panLane],
                  cppID: id, message: "A156-A158 Pan ghost survives Tempo and Volume activation")
    fixture.activate(fixture.panLane)
    report.expect(fixture.page.activeParameter == fixture.panLane
                      && fixture.page.ghostParameters == [fixture.panLane],
                  cppID: id, message: "A159-A161 activating Pan retains its ghost publication")
    report.expect(fixture.page.toggleGhostParameter(index: panIndex),
                  cppID: id, message: "A162 active Pan consumes ghost disablement")
    report.expect(fixture.page.activeParameter == fixture.panLane
                      && fixture.page.ghostParameters.isEmpty,
                  cppID: id, message: "A163-A165 ghost disablement preserves active Pan and clears ghosts")
}

@MainActor
func drawerAutomationMultiLaneSelectionDragGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::multiLaneSelectionDragGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: [(24, 32)],
        pan: [(48, 10), (48, 20)],
        modulation: [(48, 96)],
        tempo: [(0, 500_000), (48, 400_000)]
    )
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(
        from: 48, to: 96,
        lanes: [fixture.panLane, fixture.modulationLane, .tempo]
    )
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    report.expect(fixture.page.activeParameter == fixture.panLane
                      && fixture.page.selection?.range == TimeRange(startTick: 48, endTick: 96)
                      && Set(fixture.page.selectedParameters)
                        == Set([fixture.panLane, fixture.modulationLane, .tempo]),
                  cppID: id, message: "A029-A036 mixed three-lane selection is valid and Pan is active")

    let sourceX = fixture.x(48)
    let destinationX = fixture.x(96)
    let sourceY = fixture.y(fixture.panLane, 20)
    _ = fixture.page.pointerPress(
        x: sourceX, y: sourceY, surface: AutomationInputSurface.plot.rawValue,
        button: 1, modifiers: DrawerModifiers.shiftBit
    )
    _ = fixture.page.pointerMove(
        x: sourceX, y: sourceY - 30, buttons: 1, modifiers: DrawerModifiers.shiftBit
    )
    _ = fixture.page.pointerMove(
        x: destinationX, y: sourceY, buttons: 1, modifiers: DrawerModifiers.shiftBit
    )
    report.expect(fixture.snapshot == baseline && fixture.document.state == baselineState,
                  cppID: id, message: "A037-A039 selected-drag preview writes no document or history")
    _ = fixture.page.pointerRelease(
        x: destinationX, y: sourceY,
        button: 1, modifiers: DrawerModifiers.shiftBit
    )
    report.expect(fixture.document.revision == baseline.revision + 1
                      && fixture.snapshot.canUndo
                      && fixture.snapshot.identity != baseline.identity,
                  cppID: id, message: "A040-A044 selected drag creates one revision and history entry")
    report.expectEqual(["96:10", "96:20"], fixture.values(fixture.panLane),
                       cppID: id, what: "A047-A048 Pan duplicates move together in source order")
    report.expectEqual(["96:96"], fixture.values(fixture.modulationLane),
                       cppID: id, what: "A049-A050 LFO point moves to the destination")
    report.expectEqual(["0:120", "96:150"], fixture.tempoValues,
                       cppID: id, what: "A045-A046 selected Tempo point moves to the destination")
    report.expectEqual(["24:32"], fixture.values(fixture.volumeLane),
                       cppID: id, what: "A051 unselected Volume remains unchanged")
    report.expect(fixture.page.selection?.range == TimeRange(startTick: 96, endTick: 144)
                      && Set(fixture.page.selectedParameters)
                        == Set([fixture.panLane, fixture.modulationLane, .tempo]),
                  cppID: id, message: "A052-A055 selection and projected streams move together")

    report.expect(fixture.snapshot.canUndo && fixture.undo(),
                  cppID: id, message: "A056-A057 mixed selected drag is undoable")
    report.expect(fixture.document.state == baselineState
                      && fixture.values(fixture.panLane) == ["48:10", "48:20"]
                      && fixture.values(fixture.modulationLane) == ["48:96"]
                      && fixture.tempoValues == ["0:120", "48:150"],
                  cppID: id, message: "A058-A061 undo restores all source occurrences")
    report.expect(fixture.document.history.canRedo,
                  cppID: id, message: "A062 selected drag undo publishes redo")
    do {
        _ = try drawerAutomationRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(id, "A063 selected drag redo failed: \(error)")
    }
    report.expect(fixture.values(fixture.panLane) == ["96:10", "96:20"]
                      && fixture.values(fixture.modulationLane) == ["96:96"]
                      && fixture.tempoValues == ["0:120", "96:150"],
                  cppID: id, message: "A063-A067 redo restores every destination occurrence")
}

@MainActor
func drawerAutomationMultiLaneSelectionDeleteGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::multiLaneSelectionDeleteGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: [(24, 32)],
        pan: [(48, 10), (48, 20)],
        modulation: [(48, 96)],
        tempo: [(0, 500_000), (48, 400_000)]
    )
    fixture.activate(.tempo)
    fixture.page.selectRange(
        from: 48, to: 96,
        lanes: [fixture.panLane, fixture.modulationLane, .tempo]
    )
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    report.expect(fixture.page.activeParameter == .tempo
                      && Set(fixture.page.selectedParameters)
                        == Set([fixture.panLane, fixture.modulationLane, .tempo])
                      && !fixture.page.selectedParameters.contains(fixture.volumeLane),
                  cppID: id, message: "A068-A077 mixed selection covers Tempo, Pan, and LFO but not Volume")
    report.expect(fixture.page.consumeSelectionCommand(command: .delete),
                  cppID: id, message: "mixed selection consumes Delete")
    report.expect(fixture.document.revision == baseline.revision + 1
                      && fixture.snapshot.canUndo
                      && fixture.snapshot.identity != baseline.identity,
                  cppID: id, message: "A078-A083 Delete creates one revision and history entry")
    report.expect(fixture.values(fixture.panLane).isEmpty
                      && fixture.values(fixture.modulationLane).isEmpty
                      && fixture.tempoValues == ["0:120"],
                  cppID: id, message: "A084-A089 Delete removes all and only selected events")
    report.expectEqual(["24:32"], fixture.values(fixture.volumeLane),
                       cppID: id, what: "A087 Delete preserves unselected Volume")

    report.expect(fixture.snapshot.canUndo && fixture.undo(),
                  cppID: id, message: "A090-A091 mixed selection Delete is undoable")
    report.expect(fixture.document.state == baselineState
                      && fixture.values(fixture.panLane) == ["48:10", "48:20"]
                      && fixture.values(fixture.modulationLane) == ["48:96"]
                      && fixture.tempoValues == ["0:120", "48:150"],
                  cppID: id, message: "A092-A095 undo restores every selected event")
    report.expect(fixture.document.history.canRedo,
                  cppID: id, message: "A096 Delete undo publishes redo")
    do {
        _ = try drawerAutomationRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(id, "A097 selection Delete redo failed: \(error)")
    }
    report.expect(fixture.values(fixture.panLane).isEmpty
                      && fixture.values(fixture.modulationLane).isEmpty
                      && fixture.tempoValues == ["0:120"],
                  cppID: id, message: "A097-A099 redo restores the mixed deletion")
    let beforeEmptyDelete = fixture.snapshot
    _ = fixture.page.consumeSelectionCommand(command: .delete)
    report.expect(fixture.snapshot == beforeEmptyDelete
                      && fixture.values(fixture.volumeLane) == ["24:32"],
                  cppID: id, message: "A100-A101 empty repeated Delete is a document no-op")
}

@MainActor
func drawerAutomationSelectionDragRebuildAbortGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::selectionDragRebuildAbortGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: [(24, 32)],
        pan: [(48, 10), (48, 20)],
        modulation: [(48, 96)],
        tempo: [(0, 500_000), (48, 400_000)]
    )
    fixture.activate(.tempo)
    fixture.page.selectRange(
        from: 48, to: 96,
        lanes: [fixture.panLane, fixture.modulationLane, .tempo]
    )
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    report.expect(fixture.page.activeParameter == .tempo
                      && fixture.projection(.tempo).points.isEmpty == false
                      && fixture.projection(fixture.panLane).points.isEmpty == false
                      && fixture.projection(fixture.modulationLane).points.isEmpty == false,
                  cppID: id, message: "A102-A106 mixed selection rebuild fixture is valid")

    let sourceX = fixture.x(48)
    let destinationX = fixture.x(96)
    let sourceY = fixture.y(.tempo, 150)
    _ = fixture.page.pointerPress(
        x: sourceX, y: sourceY, surface: AutomationInputSurface.plot.rawValue,
        button: 1, modifiers: DrawerModifiers.shiftBit
    )
    _ = fixture.page.pointerMove(
        x: sourceX, y: sourceY - 30, buttons: 1, modifiers: DrawerModifiers.shiftBit
    )
    _ = fixture.page.pointerMove(
        x: destinationX, y: sourceY, buttons: 1, modifiers: DrawerModifiers.shiftBit
    )
    fixture.page.refreshFromDocument()
    report.expect(!fixture.page.hasGesture
                      && fixture.snapshot == baseline
                      && fixture.document.state == baselineState,
                  cppID: id, message: "A107-A110 document rebuild aborts preview without an edit")
    _ = fixture.page.pointerRelease(
        x: destinationX, y: sourceY,
        button: 1, modifiers: DrawerModifiers.shiftBit
    )
    report.expect(fixture.tempoValues == ["0:120", "48:150"]
                      && fixture.values(fixture.panLane) == ["48:10", "48:20"]
                      && fixture.values(fixture.modulationLane) == ["48:96"]
                      && fixture.values(fixture.volumeLane) == ["24:32"]
                      && fixture.page.selection?.range == TimeRange(startTick: 48, endTick: 96),
                  cppID: id, message: "A111-A117 aborted release preserves every lane and selection")
}

@MainActor
func drawerAutomationMultiCCSelectionDragGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::multiCCSelectionDragGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: [(24, 32)],
        pan: [(48, 10), (48, 20)],
        modulation: [(48, 96)],
        tempo: [(0, 500_000), (48, 400_000)]
    )
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(
        from: 48, to: 96,
        lanes: [fixture.panLane, fixture.modulationLane]
    )
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    report.expect(fixture.page.activeParameter == fixture.panLane
                      && Set(fixture.page.selectedParameters)
                        == Set([fixture.panLane, fixture.modulationLane]),
                  cppID: id, message: "A118-A121 Pan and LFO lane-only selection is valid")

    let sourceX = fixture.x(48)
    let destinationX = fixture.x(96)
    let sourceY = fixture.y(fixture.panLane, 20)
    _ = fixture.page.pointerPress(
        x: sourceX, y: sourceY, surface: AutomationInputSurface.plot.rawValue,
        button: 1, modifiers: DrawerModifiers.shiftBit
    )
    _ = fixture.page.pointerMove(
        x: sourceX, y: sourceY - 30, buttons: 1, modifiers: DrawerModifiers.shiftBit
    )
    _ = fixture.page.pointerMove(
        x: destinationX, y: sourceY, buttons: 1, modifiers: DrawerModifiers.shiftBit
    )
    report.expect(fixture.snapshot == baseline && fixture.document.state == baselineState,
                  cppID: id, message: "A122-A124 multi-CC drag preview writes nothing")
    _ = fixture.page.pointerRelease(
        x: destinationX, y: sourceY,
        button: 1, modifiers: DrawerModifiers.shiftBit
    )
    report.expect(fixture.document.revision == baseline.revision + 1
                      && fixture.snapshot.canUndo,
                  cppID: id, message: "A125 multi-CC drag creates one undoable revision")
    report.expect(fixture.values(fixture.panLane) == ["96:10", "96:20"]
                      && fixture.values(fixture.modulationLane) == ["96:96"],
                  cppID: id, message: "A128-A129 and A132-A133 both selected CC lanes move")
    report.expect(fixture.tempoValues == ["0:120", "48:150"]
                      && fixture.values(fixture.volumeLane) == ["24:32"],
                  cppID: id, message: "A126-A127 and A130 drag excludes Tempo and Volume")
    report.expect(fixture.page.selection?.range == TimeRange(startTick: 96, endTick: 144)
                      && fixture.page.selection?.tempo == false
                      && Set(fixture.page.selectedParameters)
                        == Set([fixture.panLane, fixture.modulationLane]),
                  cppID: id, message: "A131 lane-only selection moves and still excludes Tempo")

    report.expect(fixture.snapshot.canUndo && fixture.undo(),
                  cppID: id, message: "A134-A135 multi-CC drag is undoable")
    report.expect(fixture.values(fixture.panLane) == ["48:10", "48:20"]
                      && fixture.values(fixture.modulationLane) == ["48:96"]
                      && fixture.tempoValues == ["0:120", "48:150"],
                  cppID: id, message: "A136-A138 undo restores CC lanes and preserves Tempo")
    report.expect(fixture.document.history.canRedo,
                  cppID: id, message: "A139 multi-CC undo publishes redo")
    do {
        _ = try drawerAutomationRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(id, "A140 multi-CC redo failed: \(error)")
    }
    report.expect(fixture.values(fixture.panLane) == ["96:10", "96:20"]
                      && fixture.values(fixture.modulationLane) == ["96:96"]
                      && fixture.tempoValues == ["0:120", "48:150"],
                  cppID: id, message: "A140-A143 redo restores CC destinations without Tempo")
}
