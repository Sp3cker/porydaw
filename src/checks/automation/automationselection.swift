import Foundation
import PorydawApp
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

@MainActor
func drawerAutomationBandIsolatesTempoAndCc(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "automation/AutomationEditingTest::bandSelectionIsolatesTempoAndControlChangeRows"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(48, 60)],
                                                    tempo: [(48, 600_000)])
    fixture.activate(.tempo)
    let page = fixture.page
    let before = fixture.snapshot
    _ = page.pointerPress(x: fixture.x(24), y: 60, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerMove(x: fixture.x(120), y: 60, buttons: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(120), y: 60, button: AutomationQtButton.right)
    report.expect(page.selection?.tempo == true
                      && page.selection?.lanes == Set([AutomationParameter.tempo]),
                  cppID: id, message: "a band on Tempo selects Tempo alone")
    report.expect(page.selection?.scope == .lanes, cppID: id,
                  message: "the band publishes a lane-scoped range")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "banding writes nothing")
    report.expect(fixture.drag(.tempo, from: (48, 100), to: 120, modifiers: 0),
                  cppID: id, message: "the pointer route takes the tempo drag")
    report.expectEqual(["48:120"], fixture.tempoValues, cppID: id,
                       what: "the tempo drag moves the tempo point")
    report.expectEqual(["48:60"], fixture.values(fixture.panLane), cppID: id,
                       what: "the tempo drag leaves the CC lane alone")
    report.expect(fixture.undo(), cppID: id, message: "the tempo drag undoes")

    fixture.activate(fixture.panLane)
    _ = page.pointerPress(x: fixture.x(24), y: 60, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerMove(x: fixture.x(120), y: 60, buttons: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(120), y: 60, button: AutomationQtButton.right)
    report.expect(page.selection?.tempo == false
                      && page.selection?.lanes == Set([fixture.panLane]),
                  cppID: id, message: "a band on Pan selects the Pan lane alone")
}

@MainActor
func drawerAutomationMultiCcDragExcludesOthers(_ report: CheckReport, suite: DocumentSession,
                                               service: ProjectService) {
    let id = "automation/AutomationEditingTest::multiCcLaneSelectionDragExcludesTempoAndVolume"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    volume: [(48, 70)],
                                                    pan: [(24, 60)],
                                                    modulation: [(48, 70)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 0, to: 96, lanes: [fixture.panLane, fixture.modulationLane])
    let before = fixture.snapshot
    fixture.drag(fixture.panLane, from: (24, 60), to: 70, modifiers: 0)
    report.expectEqual(["24:70"], fixture.values(fixture.panLane), cppID: id,
                       what: "the grabbed lane moves with the selection")
    report.expectEqual(["48:80"], fixture.values(fixture.modulationLane), cppID: id,
                       what: "the second selected lane shares the delta")
    report.expectEqual(["48:70"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "the unselected volume lane is excluded")
    report.expectEqual(["0:120"], fixture.tempoValues, cppID: id,
                       what: "tempo is excluded from the CC drag")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: id,
                       what: "the multi-lane drag is one revision")
    report.expect(fixture.undo(), cppID: id, message: "one undo restores all selected lanes")
    report.expectEqual(["24:60"], fixture.values(fixture.panLane), cppID: id,
                       what: "undo restores the grabbed lane")
    report.expectEqual(["48:70"], fixture.values(fixture.modulationLane), cppID: id,
                       what: "undo restores the second selected lane")
    report.expect(!fixture.document.history.canUndo, cppID: id,
                  message: "the drag recorded exactly one history entry")
}

@MainActor
func drawerAutomationGhostViewOnlyAndSurvives(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let id = "automation/AutomationEditingTest::ghostToggleIsViewOnlyAndSurvivesActivation"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    volume: [(48, 70)],
                                                    pan: [(24, 60)])
    fixture.activate(fixture.volumeLane)
    let page = fixture.page
    let before = fixture.snapshot
    let panIndex = page.catalogIndex(of: fixture.panLane)
    report.expect(page.toggleGhostParameter(index: panIndex), cppID: id,
                  message: "a lane with events pins as a ghost")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "pinning a ghost writes nothing")
    report.expect(page.ghostParameters.contains(fixture.panLane), cppID: id,
                  message: "the page publishes the pinned ghost")
    report.expectEqual(fixture.volumeLane, page.activeParameter, cppID: id,
                       what: "pinning keeps the active parameter")
    fixture.activate(fixture.panLane)
    fixture.activate(fixture.volumeLane)
    report.expect(page.ghostParameters.contains(fixture.panLane), cppID: id,
                  message: "the ghost survives parameter activation")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "activation around a ghost writes nothing")
    report.expect(page.toggleGhostParameter(index: panIndex), cppID: id,
                  message: "the pin toggles off again")
    report.expect(!page.ghostParameters.contains(fixture.panLane), cppID: id,
                  message: "unpinning drops the ghost")
}

@MainActor
func drawerAutomationPencilOwnershipAndShift(_ report: CheckReport, suite: DocumentSession,
                                             service: ProjectService) {
    let id = "automation/AutomationEditingTest::pencilStrokeOutsideSelectionClearsSelection"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 20, to: 60, lanes: [fixture.panLane])
    fixture.page.isPencilMode = true
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: 60, surface: 1,
                                             button: AutomationQtButton.left),
                  cppID: id, message: "a pencil press outside the selection starts")
    report.expect(fixture.page.selection == nil, cppID: id,
                  message: "starting a pencil stroke outside clears the selection")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: 60, button: AutomationQtButton.left)

    let lockID = "automation/AutomationEditingTest::nodeDragShiftAxisLocks"
    let horizontal = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                       pan: [(24, 64), (120, 40)])
    horizontal.activate(horizontal.panLane)
    let shift = drawerAutomationQtModifiers(AutomationModifiers(shift: true))
    _ = horizontal.page.pointerPress(x: horizontal.x(24), y: horizontal.y(horizontal.panLane, 64),
                                      surface: 1, button: 1, modifiers: shift)
    _ = horizontal.page.pointerMove(x: horizontal.x(24) + 30, y: horizontal.y(horizontal.panLane, 64),
                                     buttons: 1, modifiers: shift)
    _ = horizontal.page.pointerMove(x: horizontal.x(24) + 60, y: horizontal.y(horizontal.panLane, 64),
                                     buttons: 1, modifiers: shift)
    _ = horizontal.page.pointerRelease(x: horizontal.x(24) + 60,
                                        y: horizontal.y(horizontal.panLane, 64),
                                        button: 1, modifiers: shift)
    let moved = horizontal.lanePoints(horizontal.panLane)
    report.expect(moved.count == 2 && moved[0].value == 64 && moved[0].tick > 24, cppID: lockID,
                  message: "a horizontal Shift drag locks the value and moves the tick")
    let vertical = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(24, 64), (120, 40)])
    vertical.activate(vertical.panLane)
    _ = vertical.page.pointerPress(x: vertical.x(24), y: vertical.y(vertical.panLane, 64),
                                    surface: 1, button: 1, modifiers: shift)
    _ = vertical.page.pointerMove(x: vertical.x(24), y: vertical.y(vertical.panLane, 64) - 20,
                                   buttons: 1, modifiers: shift)
    _ = vertical.page.pointerMove(x: vertical.x(24), y: vertical.y(vertical.panLane, 64) - 40,
                                   buttons: 1, modifiers: shift)
    _ = vertical.page.pointerRelease(x: vertical.x(24), y: vertical.y(vertical.panLane, 64) - 40,
                                      button: 1, modifiers: shift)
    let shifted = vertical.lanePoints(vertical.panLane)
    report.expect(shifted.count == 2 && shifted[0].tick == 24 && shifted[0].value != 64,
                  cppID: lockID,
                  message: "a vertical Shift drag locks the tick and moves the value")

    let doubleID = "automation/AutomationEditingTest::doubleClickDeletesOnceWithoutValuePrompt"
    for parameter in [AutomationParameter.tempo,
                      .controlChange(track: 0, controller: TimeDefaults.ccPan)] {
        let twice = drawerAutomationAutomationFixture(
            suite: suite, service: service,
            pan: [(0, 80), (96, 100), (288, 64)],
            tempo: [(0, 750_000), (96, 600_000), (288, 937_500)])
        twice.activate(parameter)
        let before = twice.snapshot
        let nodeX = twice.x(96)
        let nodeY = twice.y(parameter, 100)
        report.expect(twice.page.pointerDoubleClick(x: nodeX, y: nodeY),
                      cppID: doubleID, message: "a double-click on the node is handled")
        report.expect(!twice.page.hasPrompt, cppID: doubleID,
                      message: "a double-click never opens the value prompt")
        report.expectEqual(before.revision + 1, twice.document.revision, cppID: doubleID,
                           what: "the double-click publishes exactly one revision")
        let expected = ["0:80", "288:64"]
        let actual = parameter == .tempo ? twice.tempoValues : twice.values(twice.panLane)
        report.expectEqual(expected, actual, cppID: doubleID,
                           what: "only the clicked node is deleted from the active adapter")
        report.expect(twice.document.history.canUndo, cppID: doubleID,
                      message: "the deletion records an undo entry")
        report.expect(twice.undo(), cppID: doubleID,
                      message: "the double-click deletion can be undone")
        report.expect(!twice.document.history.canUndo, cppID: doubleID,
                      message: "one undo consumes the double-click's single history entry")
        let restored = parameter == .tempo ? twice.tempoValues : twice.values(twice.panLane)
        report.expectEqual(["0:80", "96:100", "288:64"], restored, cppID: doubleID,
                           what: "one undo restores the deleted node and its two neighbours")
    }
}

@MainActor
func drawerAutomationDetailThresholdPrecedence(_ report: CheckReport, suite: DocumentSession,
                                               service: ProjectService) {
    let id = "automation/AutomationEditingTest::detailThresholdHiddenVisibleNodePrecedence"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    fixture.page.isPencilMode = true
    func markersVisible() -> Bool {
        AutomationProjection(
            camera: fixture.session.camera,
            bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
            geometry: fixture.page.geometry,
            snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                             timeline: fixture.session.timeline,
                                             baseFontPx: 13, devicePixelRatio: 1),
            songEndTick: fixture.songEndTick).markersVisible()
    }
    report.expect(markersVisible(), cppID: id, message: "markers are visible at default zoom")
    let zoomAnchor = fixture.x(24)
    _ = fixture.session.mutateCamera {
        $0.zoomAroundContentX(factor: 0.02, anchorContentX: zoomAnchor)
    }
    report.expect(!markersVisible(), cppID: id,
                  message: "markers hide below the detail threshold")
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 70),
                                             surface: 1, button: 1),
                  cppID: id, message: "the pencil press through hidden markers starts a stroke")
    report.expect(fixture.page.pointerRelease(x: fixture.x(24), y: fixture.y(fixture.panLane, 70),
                                               button: 1),
                  cppID: id, message: "the stroke through hidden markers commits")
    let hidden = fixture.lanePoints(fixture.panLane)
    report.expect(hidden.count == 3 && hidden.contains(where: { $0.tick == 24 && $0.value == 70 }),
                  cppID: id,
                  message: "the hidden-marker stroke inserts instead of grabbing the node")
    let zoomBack = fixture.x(120)
    _ = fixture.session.mutateCamera {
        $0.zoomAroundContentX(factor: 50, anchorContentX: zoomBack)
    }
    report.expect(markersVisible(), cppID: id, message: "markers return above the threshold")

    let shownFixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                         pan: [(24, 64), (120, 40)])
    shownFixture.activate(shownFixture.panLane)
    shownFixture.page.isPencilMode = true
    report.expect(shownFixture.page.pointerPress(
        x: shownFixture.x(24), y: shownFixture.y(shownFixture.panLane, 64),
        surface: 1, button: 1),
                  cppID: id, message: "the pencil press on a visible node grabs it")
    _ = shownFixture.page.pointerRelease(x: shownFixture.x(24),
                                          y: shownFixture.y(shownFixture.panLane, 64), button: 1)
    report.expectEqual(["120:40"], shownFixture.values(shownFixture.panLane), cppID: id,
                       what: "a stationary release on the grabbed node deletes exactly it")
}

@MainActor
func drawerAutomationTempoBendClickRestore(_ report: CheckReport, suite: DocumentSession,
                                           service: ProjectService) {
    let tempoID = "automation/AutomationEditingTest::pencilSingleClickOnTempoLaneRestoresDefaultTempoAtCellEnd"
    let tempo = drawerAutomationAutomationFixture(suite: suite, service: service, tempo: [])
    tempo.activate(.tempo)
    tempo.page.isPencilMode = true
    report.expect(tempo.page.pointerPress(x: tempo.x(48), y: tempo.y(.tempo, 150),
                                           surface: 1, button: 1),
                  cppID: tempoID, message: "the pencil press on the empty tempo lane starts")
    report.expect(tempo.page.pointerRelease(x: tempo.x(48), y: tempo.y(.tempo, 150), button: 1),
                  cppID: tempoID, message: "the tempo click commits")
    report.expectEqual(["48:150", "120:120"], tempo.tempoValues, cppID: tempoID,
                       what: "the click writes its BPM at the cell start and restores default at the end")

    let bendID = "automation/AutomationEditingTest::pencilSingleClickOnPitchBendLaneRestoresCenterAtCellEnd"
    let bend = drawerAutomationAutomationFixture(suite: suite, service: service)
    bend.activate(bend.bendLane)
    bend.page.isPencilMode = true
    report.expect(bend.page.pointerPress(x: bend.x(48), y: bend.y(bend.bendLane, 100),
                                          surface: 1, button: 1),
                  cppID: bendID, message: "the pencil press on the empty bend lane starts")
    report.expect(bend.page.pointerRelease(x: bend.x(48), y: bend.y(bend.bendLane, 100), button: 1),
                  cppID: bendID, message: "the bend click commits")
    report.expectEqual(["48:100", "120:0"], bend.values(bend.bendLane), cppID: bendID,
                       what: "the click writes its value at the cell start and restores center at the end")

    let excursionID = "automation/AutomationEditingTest::pencilClickOnExcursionNodeDeletesExcursion"
    let excursion = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                      pan: [(0, 60), (48, 90), (96, 60)])
    excursion.activate(excursion.panLane)
    excursion.page.isPencilMode = true
    report.expect(excursion.page.pointerPress(x: excursion.x(48), y: excursion.y(excursion.panLane, 60),
                                               surface: 1, button: 1),
                  cppID: excursionID, message: "the pencil press at baseline over the excursion starts")
    report.expect(excursion.page.pointerRelease(x: excursion.x(48),
                                                 y: excursion.y(excursion.panLane, 60), button: 1),
                  cppID: excursionID, message: "the baseline click commits")
    report.expectEqual(["0:60"], excursion.values(excursion.panLane), cppID: excursionID,
                       what: "collapsing the excursion leaves the baseline alone")
}

@MainActor
func drawerAutomationSelectionDeleteCommand(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "automation/AutomationEditingTest::multiLaneSelectionDeleteAndEmptyDeleteNoop"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 60), (120, 40)],
                                                    tempo: [(48, 600_000)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 0, to: 96, lanes: [fixture.panLane, .tempo])
    let before = fixture.snapshot
    report.expect(fixture.page.consumeSelectionCommand(command: .delete), cppID: id,
                  message: "the Delete command removes the covered span")
    report.expectEqual(["120:40"], fixture.values(fixture.panLane), cppID: id,
                       what: "Delete keeps CC points outside the span")
    report.expect(fixture.tempoValues.isEmpty, cppID: id,
                  message: "Delete removes the covered tempo point")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: id,
                       what: "one Delete is one revision")
    report.expect(fixture.undo(), cppID: id, message: "the Delete undoes")
    report.expectEqual(["24:60", "120:40"], fixture.values(fixture.panLane), cppID: id,
                       what: "undo restores the covered CC point")
    report.expectEqual(["48:100"], fixture.tempoValues, cppID: id,
                       what: "undo restores the covered tempo point")
    fixture.page.clearTimeSelection()
    let emptyBefore = fixture.snapshot
    report.expect(!fixture.page.consumeSelectionCommand(command: .delete), cppID: id,
                  message: "Delete with no selection commits nothing")
    report.expectEqual(emptyBefore, fixture.snapshot, cppID: id,
                       what: "an empty Delete writes nothing")
}
