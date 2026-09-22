import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerAutomationEditingGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::portableEditingGap"

    let drag = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (120, 40)]
    )
    drag.activate(drag.panLane)
    let dragBefore = drag.snapshot
    let dragState = drag.document.state
    let dragged = (tick: Tick(24), value: 64)
    let targetValue = 90
    report.expect(drag.page.activeParameter == drag.panLane && drag.page.projection != nil,
                  cppID: id, message: "A001-A004 Pan and its production projection are active")
    report.expect(drag.page.drag(drag.panLane, from: dragged, to: targetValue, armPixels: 30),
                  cppID: id, message: "A005-A006 the typed pointer route previews and releases the node drag")
    report.expectEqual(["24:90", "120:40"], drag.values(drag.panLane), cppID: id,
                       what: "A008-A011 and A016-A019 release changes only the grabbed CC occurrence")
    report.expect(drag.document.state != dragState && drag.document.revision == dragBefore.revision + 1,
                  cppID: id, message: "A010-A015 the release publishes exactly one document revision")
    report.expect(drag.document.history.canUndo && drag.snapshot.identity != dragBefore.identity,
                  cppID: id, message: "A012-A015 the release records one undoable history identity")
    report.expect(drag.undo(), cppID: id, message: "A020-A021 the committed drag is undoable")
    report.expectEqual(["24:64", "120:40"], drag.values(drag.panLane), cppID: id,
                       what: "A022-A025 undo restores both target and independent CC occurrences")
    do {
        _ = try drawerAutomationRunBlocking { try await drag.session.redo() }
    } catch {
        report.fail(id, "A026-A027 redo failed: \(error)")
        return
    }
    report.expectEqual(["24:90", "120:40"], drag.values(drag.panLane), cppID: id,
                       what: "A028-A031 redo restores the committed target and preserves the independent occurrence")

    let cancel = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (120, 40)]
    )
    cancel.activate(cancel.panLane)
    let cancelBefore = cancel.snapshot
    let cancelState = cancel.document.state
    let sourceX = cancel.x(24)
    let sourceY = cancel.y(cancel.panLane, 64)
    report.expect(cancel.page.pointerPress(x: sourceX, y: sourceY, surface: AutomationInputSurface.plot.rawValue,
                                           button: 1, modifiers: 0),
                  cppID: id, message: "A032-A035 the production pointer route arms the written node")
    _ = cancel.page.pointerMove(x: sourceX + 40, y: cancel.y(cancel.panLane, 90), buttons: 1)
    report.expect(cancel.page.hasGesture && !cancel.page.previewPoints.isEmpty,
                  cppID: id, message: "A036-A040 motion publishes an automation preview while the document remains frozen")
    report.expect(cancel.document.state == cancelState && cancel.snapshot == cancelBefore,
                  cppID: id, message: "A038-A040 preview motion writes no document or history state")
    report.expect(cancel.page.handleEscape(), cppID: id,
                  message: "A041-A043 Escape is consumed by the live production gesture")
    report.expect(!cancel.page.hasGesture && cancel.page.previewPoints.isEmpty && !cancel.page.interactionActive,
                  cppID: id, message: "A041-A047 Escape synchronously clears preview and interaction state")
    _ = cancel.page.pointerRelease(x: sourceX + 40, y: cancel.y(cancel.panLane, 90), button: 1)
    report.expect(cancel.document.state == cancelState && cancel.snapshot == cancelBefore
                      && cancel.values(cancel.panLane) == ["24:64", "120:40"],
                  cppID: id, message: "A043-A050 release after cancellation cannot commit and preserves both occurrences")

    let idle = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (120, 40)]
    )
    idle.activate(idle.panLane)
    let idleBefore = idle.snapshot
    let idleState = idle.document.state
    let blankX = idle.x(72)
    report.expect(blankX >= 0 && blankX <= idle.page.plotWidth
                      && !idle.values(idle.panLane).contains(where: { $0.hasPrefix("72:") }),
                  cppID: id, message: "A051-A052 the blank target is inside the production plot and has no CC event")
    report.expect(idle.page.pointerPress(x: blankX, y: 60, surface: AutomationInputSurface.plot.rawValue,
                                         button: 1, modifiers: 0),
                  cppID: id, message: "A053-A055 the blank press is routed and parks the shared edit cursor")
    report.expect(!idle.page.pointerRelease(x: blankX, y: 60, button: 1, modifiers: 0),
                  cppID: id, message: "A055 release without activation reports no edit")
    report.expect(idle.document.state == idleState && idle.snapshot == idleBefore,
                  cppID: id, message: "A056-A061 release without activation preserves bytes, revision, and history")
    report.expectEqual(["24:64", "120:40"], idle.values(idle.panLane), cppID: id,
                       what: "A062-A064 release without activation preserves both CC events and leaves the blank tick empty")

    let tabs = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)]
    )
    let selection = AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 120), scope: .lanes,
        lanes: [tabs.panLane, tabs.bendLane]
    )
    tabs.page.applyTimeSelection(selection)
    let tabBefore = tabs.snapshot
    let tabState = tabs.document.state
    report.expect(tabs.page.selection == selection && tabs.page.publishedTabs.count > 1,
                  cppID: id, message: "A065-A068 an active noncontiguous selection and multiple parameter tabs are published")
    let parameters: [AutomationParameter] = [tabs.volumeLane, tabs.panLane, tabs.modulationLane,
                                              tabs.bendLane, .tempo]
    for parameter in parameters {
        let row = "A069-A071-\(parameter)"
        let index = tabs.page.catalogIndex(of: parameter)
        report.expect(index >= 0 && tabs.page.activateParameter(index: index)
                          && tabs.page.activeParameter == parameter,
                      cppID: id, message: "\(row) each catalog row activates through the production page")
        report.expect(tabs.page.selection == selection,
                      cppID: id, message: "A072-A076-\(parameter) tab activation preserves scope, range, tempo flag, and lane set")
    }
    report.expect(tabs.document.state == tabState && tabs.snapshot == tabBefore,
                  cppID: id, message: "A077 all tab activations preserve document revision and history")

    let previewOnly = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (120, 40)]
    )
    previewOnly.activate(previewOnly.panLane)
    let previewOnlyBefore = previewOnly.snapshot
    let previewOnlyState = previewOnly.document.state
    let previewX = previewOnly.x(24)
    let previewY = previewOnly.y(previewOnly.panLane, 64)
    _ = previewOnly.page.pointerPress(
        x: previewX, y: previewY, surface: AutomationInputSurface.plot.rawValue,
        button: 1, modifiers: 0
    )
    _ = previewOnly.page.pointerMove(
        x: previewX + 40, y: previewOnly.y(previewOnly.panLane, 90), buttons: 1
    )
    report.expect(previewOnly.page.hasGesture && !previewOnly.page.previewPoints.isEmpty
                      && previewOnly.document.state == previewOnlyState
                      && previewOnly.snapshot == previewOnlyBefore,
                  cppID: id, message: "A007 drag preview is visible while document and history remain frozen")
    previewOnly.page.cancelSectionInteraction()

    let redo = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (120, 40)]
    )
    redo.activate(redo.panLane)
    _ = redo.page.drag(redo.panLane, from: (tick: Tick(24), value: 64), to: 90,
                       armPixels: 30)
    _ = redo.undo()
    report.expect(redo.document.history.canRedo,
                  cppID: id, message: "A026 undo publishes the committed drag as redoable")
    do {
        _ = try drawerAutomationRunBlocking { try await redo.session.redo() }
    } catch {
        report.fail(id, "A027 redo failed: \(error)")
        return
    }
    report.expect(redo.values(redo.panLane) == ["24:90", "120:40"]
                      && redo.document.history.canUndo && !redo.document.history.canRedo,
                  cppID: id, message: "A027 redo applies the same single transaction")

    for parameter in parameters {
        let index = tabs.page.catalogIndex(of: parameter)
        report.expect(index >= 0 && tabs.page.activateParameter(index: index)
                          && tabs.page.activeParameter == parameter,
                      cppID: id,
                      message: "A069-A071-\(parameter) every catalog row resolves and activates")
    }
}
