import Foundation
@testable import PorydawApp
import PorydawCore

@MainActor
func drawerAutomationBandIsolatesTempoAndCc(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::bandSelectionIsolatesTempoAndControlChangeRows"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(48, 60)],
        tempo: [(48, 600_000)])
    fixture.activate(.tempo)
    let page = fixture.page
    let before = fixture.snapshot
    let pendingRevision = page.documentRevision
    let pendingCursor = fixture.session.editCursor
    _ = page.pointerPress(x: fixture.x(24), y: 60, surface: 1, button: AutomationQtButton.right)
    report.expect(
        page.hasBand && page.activeParameter == .tempo,
        cppID: id, message: "a pending band belongs to the active Tempo lane")
    report.expect(
        page.documentRevision == pendingRevision
            && fixture.session.editCursor == pendingCursor,
        cppID: id, message: "a pending band leaves the document revision and edit cursor untouched")
    _ = page.pointerMove(x: fixture.x(120), y: 60, buttons: AutomationQtButton.right)
    report.expect(
        page.documentRevision == pendingRevision
            && fixture.session.editCursor == pendingCursor,
        cppID: id, message: "a travelled band leaves the document revision and edit cursor untouched")
    _ = page.pointerRelease(x: fixture.x(120), y: 60, button: AutomationQtButton.right)
    report.expect(
        page.selection?.tempo == true
            && page.selection?.lanes.isEmpty == true,
        cppID: id, message: "a band on Tempo selects Tempo alone")
    report.expect(
        page.selection?.scope == .lanes, cppID: id,
        message: "the band publishes a lane-scoped range")
    report.expectEqual(
        expected: before, actual: fixture.snapshot, cppID: id,
        what: "banding writes nothing")
    report.expect(
        fixture.drag(.tempo, from: (48, 100), to: 120, modifiers: 0),
        cppID: id, message: "the pointer route takes the tempo drag")
    report.expectEqual(
        expected: ["48:120"], actual: fixture.tempoValues, cppID: id,
        what: "the tempo drag moves the tempo point")
    report.expectEqual(
        expected: ["48:60"], actual: fixture.values(fixture.panLane), cppID: id,
        what: "the tempo drag leaves the CC lane alone")
    report.expect(fixture.undo(), cppID: id, message: "the tempo drag undoes")

    fixture.activate(fixture.panLane)
    _ = page.pointerPress(x: fixture.x(24), y: 60, surface: 1, button: AutomationQtButton.right)
    report.expect(
        page.hasBand && page.activeParameter == fixture.panLane,
        cppID: id, message: "a pending band belongs to the active Pan lane")
    _ = page.pointerMove(x: fixture.x(120), y: 60, buttons: AutomationQtButton.right)
    _ = page.pointerRelease(x: fixture.x(120), y: 60, button: AutomationQtButton.right)
    report.expect(
        page.selection?.tempo == false
            && page.selection?.lanes == Set([fixture.panLane]),
        cppID: id, message: "a band on Pan selects the Pan lane alone")
    _ = page.pointerPress(
        x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
        surface: AutomationInputSurface.plot.rawValue,
        button: AutomationQtButton.middle)
    report.expect(
        page.isPanning && !page.hasBand, cppID: id,
        message: "a pan press publishes its pan and no band")
    _ = page.pointerRelease(
        x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
        button: AutomationQtButton.middle)
    let bodyX = fixture.x(144)
    let bodyY = fixture.y(fixture.panLane, 64)
    report.expect(
        page.pointerPress(
            x: bodyX, y: bodyY,
            surface: AutomationInputSurface.plot.rawValue,
            button: AutomationQtButton.left)
            && !page.isPanning && !page.hasBand,
        cppID: id, message: "a body press starts no pan and no band")
    _ = page.pointerRelease(x: bodyX, y: bodyY, button: AutomationQtButton.left)
}

@MainActor
func drawerAutomationMultiCcDragExcludesOthers(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::multiCcLaneSelectionDragExcludesTempoAndVolume"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(48, 70), (144, 20)],
        pan: [(24, 60)],
        modulation: [(48, 70)],
        tempo: [(0, 500_000), (144, 400_000)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 0, to: 96, lanes: [fixture.panLane, fixture.modulationLane])
    let before = fixture.snapshot
    fixture.drag(fixture.panLane, from: (24, 60), to: 70, modifiers: 0)
    report.expectEqual(
        expected: ["24:70"], actual: fixture.values(fixture.panLane), cppID: id,
        what: "the grabbed lane moves with the selection")
    report.expectEqual(
        expected: ["48:80"], actual: fixture.values(fixture.modulationLane), cppID: id,
        what: "the second selected lane shares the delta")
    report.expectEqual(
        expected: ["48:70", "144:20"], actual: fixture.values(fixture.volumeLane),
        cppID: id, what: "the unselected volume lane is excluded")
    report.expectEqual(
        expected: ["0:120", "144:150"], actual: fixture.tempoValues, cppID: id,
        what: "tempo is excluded from the CC drag")
    let horizontal = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(48, 70), (144, 20)],
        pan: [(24, 60)], modulation: [(48, 70)],
        tempo: [(0, 500_000), (144, 400_000)])
    horizontal.activate(horizontal.panLane)
    horizontal.page.selectRange(
        from: 0, to: 96,
        lanes: [horizontal.panLane, horizontal.modulationLane])
    let held = horizontal.snapshot
    let heldIndex = horizontal.document.history.undoIndex
    let volumeBeforeShift = horizontal.values(horizontal.volumeLane)
    let tempoBeforeShift = horizontal.tempoValues
    var publishedDocumentEdits = 0
    let priorChange = horizontal.session.onChange
    horizontal.session.onChange = { change in
        if change.domains.contains(.document) { publishedDocumentEdits += 1 }
        priorChange?(change)
    }
    let sourceX = horizontal.x(24)
    let sourceY = horizontal.y(horizontal.panLane, 60)
    let activationX = sourceX + horizontal.page.geometry.nodeDragActivationDistance + 2
    let endX = activationX + horizontal.x(72) - sourceX
    _ = horizontal.page.pointerPress(
        x: sourceX, y: sourceY, surface: 1,
        button: AutomationQtButton.left,
        modifiers: AutomationQtModifier.shift)
    _ = horizontal.page.pointerMove(
        x: activationX, y: sourceY,
        buttons: AutomationQtButton.left,
        modifiers: AutomationQtModifier.shift)
    _ = horizontal.page.pointerMove(
        x: endX, y: sourceY, buttons: AutomationQtButton.left,
        modifiers: AutomationQtModifier.shift)
    report.expect(
        horizontal.snapshot == held
            && horizontal.document.history.undoIndex == heldIndex
            && horizontal.values(horizontal.panLane) == ["24:60"]
            && horizontal.values(horizontal.modulationLane) == ["48:70"],
        cppID: id, message: "held multi-CC preview freezes revision history and both selected lanes")
    report.expectEqual(
        expected: 0, actual: publishedDocumentEdits, cppID: id,
        what: "held multi-CC preview emits no document publication")
    _ = horizontal.page.pointerRelease(
        x: endX, y: sourceY, button: AutomationQtButton.left,
        modifiers: AutomationQtModifier.shift)
    report.expectEqual(
        expected: TimeRange(startTick: 48, endTick: 144),
        actual: horizontal.page.selection?.range, cppID: id,
        what: "horizontal multi-CC drag moves its half-open interval by 48")
    report.expect(
        horizontal.page.selection?.scope == .lanes
            && horizontal.page.selection?.tempo == false
            && horizontal.page.selection?.lanes
                == Set([
                    horizontal.panLane,
                    horizontal.modulationLane,
                ]),
        cppID: id, message: "shifted CC selection retains only Pan and Modulation scope")
    report.expectEqual(
        expected: [60], actual: horizontal.playbackValues(horizontal.panLane, at: 72),
        cppID: id, what: "shifted Pan reaches playback at tick 72")
    report.expectEqual(
        expected: [70], actual: horizontal.playbackValues(horizontal.modulationLane, at: 96),
        cppID: id, what: "shifted Modulation reaches playback at tick 96")
    report.expect(
        horizontal.values(horizontal.volumeLane) == volumeBeforeShift
            && horizontal.tempoValues == tempoBeforeShift, cppID: id,
        message: "horizontal multi-CC release preserves excluded Volume and Tempo points")
    report.expectEqual(
        expected: 1, actual: publishedDocumentEdits, cppID: id,
        what: "horizontal multi-CC release emits one document publication")
    report.expectEqual(
        expected: before.revision + 1, actual: fixture.document.revision, cppID: id,
        what: "the multi-lane drag is one revision")
    report.expect(fixture.undo(), cppID: id, message: "one undo restores all selected lanes")
    report.expectEqual(
        expected: ["24:60"], actual: fixture.values(fixture.panLane), cppID: id,
        what: "undo restores the grabbed lane")
    report.expectEqual(
        expected: ["48:70"], actual: fixture.values(fixture.modulationLane), cppID: id,
        what: "undo restores the second selected lane")
    report.expect(
        fixture.values(fixture.volumeLane) == ["48:70", "144:20"]
            && fixture.tempoValues == ["0:120", "144:150"],
        cppID: id, message: "a multi-lane drag preserves tempo and CC order")
    report.expect(
        !fixture.document.history.canUndo, cppID: id,
        message: "the drag recorded exactly one history entry")
}

@MainActor
func drawerAutomationGhostViewOnlyAndSurvives(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::ghostToggleIsViewOnlyAndSurvivesActivation"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(48, 70)],
        pan: [(24, 60)])
    fixture.activate(fixture.volumeLane)
    let page = fixture.page
    let before = fixture.snapshot
    report.expect(
        !page.toggleGhostParameter(index: -1)
            && !page.toggleGhostParameter(index: page.tabCount)
            && page.ghostParameters.isEmpty, cppID: id,
        message: "negative and upper-bound ghost indices leave every pin empty")
    let panIndex = page.catalogIndex(of: fixture.panLane)
    report.expect(
        page.toggleGhostParameter(index: panIndex), cppID: id,
        message: "a lane with events pins as a ghost")
    report.expectEqual(
        expected: before, actual: fixture.snapshot, cppID: id,
        what: "pinning a ghost writes nothing")
    report.expect(
        page.ghostParameters.contains(fixture.panLane), cppID: id,
        message: "the page publishes the pinned ghost")
    report.expectEqual(
        expected: fixture.volumeLane, actual: page.activeParameter, cppID: id,
        what: "pinning keeps the active parameter")
    fixture.activate(fixture.panLane)
    fixture.activate(fixture.volumeLane)
    report.expect(
        page.ghostParameters.contains(fixture.panLane), cppID: id,
        message: "the ghost survives parameter activation")
    report.expectEqual(
        expected: before, actual: fixture.snapshot, cppID: id,
        what: "activation around a ghost writes nothing")
    report.expect(
        page.toggleGhostParameter(index: panIndex), cppID: id,
        message: "the pin toggles off again")
    report.expect(
        !page.ghostParameters.contains(fixture.panLane), cppID: id,
        message: "unpinning drops the ghost")
    let eventless = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(48, 70)])
    eventless.activate(eventless.volumeLane)
    report.expect(
        eventless.values(eventless.modulationLane).isEmpty, cppID: id,
        message: "unwritten Modulation has no document lane events")
    report.expect(
        !eventless.page.toggleGhostParameter(
            index: eventless.page.catalogIndex(of: eventless.modulationLane)), cppID: id,
        message: "eventless Modulation refuses a ghost pin")
    report.expectEqual(
        expected: eventless.volumeLane, actual: eventless.page.activeParameter,
        cppID: id, what: "rejected Modulation pin preserves active Volume")
}

@MainActor
func drawerAutomationSelectionDeleteCommand(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::multiLaneSelectionDeleteAndEmptyDeleteNoop"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 60), (120, 40)],
        tempo: [(48, 600_000)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 0, to: 96, lanes: [fixture.panLane, .tempo])
    let before = fixture.snapshot
    report.expect(
        fixture.page.consumeSelectionCommand(command: .delete), cppID: id,
        message: "the Delete command removes the covered span")
    report.expectEqual(
        expected: ["120:40"], actual: fixture.values(fixture.panLane), cppID: id,
        what: "Delete keeps CC points outside the span")
    report.expect(
        fixture.tempoValues.isEmpty, cppID: id,
        message: "Delete removes the covered tempo point")
    report.expectEqual(
        expected: before.revision + 1, actual: fixture.document.revision, cppID: id,
        what: "one Delete is one revision")
    report.expect(fixture.undo(), cppID: id, message: "the Delete undoes")
    report.expectEqual(
        expected: ["24:60", "120:40"], actual: fixture.values(fixture.panLane), cppID: id,
        what: "undo restores the covered CC point")
    report.expectEqual(
        expected: ["48:100"], actual: fixture.tempoValues, cppID: id,
        what: "undo restores the covered tempo point")
    fixture.page.clearTimeSelection()
    let emptyBefore = fixture.snapshot
    report.expect(
        !fixture.page.consumeSelectionCommand(command: .delete), cppID: id,
        message: "Delete with no selection commits nothing")
    report.expectEqual(
        expected: emptyBefore, actual: fixture.snapshot, cppID: id,
        what: "an empty Delete writes nothing")
}
