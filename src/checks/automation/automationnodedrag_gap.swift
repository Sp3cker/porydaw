import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

private let automationNodeDragGapID = "automation/AutomationEditingTest::nodeDragGapContracts"
private let automationOwnershipGapID = "automation/AutomationEditingTest::ownershipGapContracts"

@MainActor
private func automationGapMoveNode(
    _ fixture: drawerAutomationAutomationFixture,
    parameter: AutomationParameter,
    from source: (tick: Tick, value: Int),
    to target: (tick: Tick, value: Int),
    modifiers: Int = 0
) -> Bool {
    let pressX = fixture.x(source.tick)
    let pressY = fixture.y(parameter, source.value)
    let targetX = fixture.x(target.tick)
    let targetY = fixture.y(parameter, target.value)
    guard fixture.page.pointerPress(
        x: pressX, y: pressY, surface: AutomationInputSurface.plot.rawValue,
        button: 1, modifiers: modifiers
    ) else { return false }
    _ = fixture.page.pointerMove(
        x: pressX + 12, y: pressY, buttons: 1, modifiers: modifiers)
    _ = fixture.page.pointerMove(
        x: pressX + 12 + targetX - pressX,
        y: pressY + targetY - pressY,
        buttons: 1, modifiers: modifiers)
    return fixture.page.pointerRelease(
        x: pressX + 12 + targetX - pressX,
        y: pressY + targetY - pressY,
        button: 1, modifiers: modifiers)
}

@MainActor
func drawerAutomationNodeDragGapChecks(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let committed = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 10), (48, 64), (120, 40)],
        tempo: [(24, 500_000), (72, 400_000)])
    committed.activate(committed.panLane)
    let committedBefore = committed.snapshot
    report.expect(
        committed.page.activeParameter == committed.panLane,
        cppID: automationNodeDragGapID,
        message: "A001/A002 active Pan lane is the production drag target")
    report.expect(
        automationGapMoveNode(committed, parameter: committed.panLane,
                              from: (48, 64), to: (72, 96)),
        cppID: automationNodeDragGapID,
        message: "A003-A006 node drag commits through pointer release")
    report.expectEqual(
        committedBefore.revision + 1, committed.document.revision,
        cppID: automationNodeDragGapID,
        what: "A003 node drag publishes one document revision")
    report.expectEqual(
        ["24:10", "72:96", "120:40"], committed.values(committed.panLane),
        cppID: automationNodeDragGapID,
        what: "A005/A006 node drag moves only the grabbed occurrence")
    report.expect(
        committed.document.history.canUndo,
        cppID: automationNodeDragGapID,
        message: "A004 committed node drag creates one undoable entry")
    report.expect(
        committed.undo() && !committed.document.history.canUndo,
        cppID: automationNodeDragGapID,
        message: "A004 one undo exhausts the node-drag history")
    report.expectEqual(
        ["24:10", "48:64", "120:40"], committed.values(committed.panLane),
        cppID: automationNodeDragGapID,
        what: "A012/A013 undo restores source and evicted destination state")
    do {
        _ = try drawerAutomationRunBlocking { try await committed.session.redo() }
    } catch {
        report.fail(automationNodeDragGapID, "A012/A013 Pan node-drag redo failed: \(error)")
    }
    report.expectEqual(
        ["24:10", "72:96", "120:40"], committed.values(committed.panLane),
        cppID: automationNodeDragGapID,
        what: "A012/A013 redo reapplies the colliding Pan node drag atomically")

    committed.activate(.tempo)
    let tempoBefore = committed.snapshot
    report.expect(
        automationGapMoveNode(committed, parameter: .tempo,
                              from: (72, 150), to: (96, 150)),
        cppID: automationNodeDragGapID,
        message: "A007-A010 Tempo node drag uses the same pointer transaction")
    report.expectEqual(
        tempoBefore.revision + 1, committed.document.revision,
        cppID: automationNodeDragGapID,
        what: "A007 Tempo node drag publishes one revision")
    report.expectEqual(
        ["24:120", "96:150"], committed.tempoValues,
        cppID: automationNodeDragGapID,
        what: "A008-A010 Tempo drag preserves value while moving the tick")
    report.expect(
        committed.undo(), cppID: automationNodeDragGapID,
        message: "A007-A010 Tempo node drag is undoable as one transaction")
    report.expectEqual(
        ["24:120", "72:150"], committed.tempoValues,
        cppID: automationNodeDragGapID,
        what: "A007-A010 Tempo undo restores the source tick")
    do {
        _ = try drawerAutomationRunBlocking { try await committed.session.redo() }
    } catch {
        report.fail(automationNodeDragGapID, "A007-A010 Tempo node-drag redo failed: \(error)")
    }
    report.expectEqual(
        ["24:120", "96:150"], committed.tempoValues,
        cppID: automationNodeDragGapID,
        what: "A007-A010 Tempo redo restores the moved tick")

    for row in [
        (name: "A014-time", cursor: AutomationCursorKind.sizeHorizontal,
         tick: Tick(48), value: 64),
        (name: "A015-value", cursor: AutomationCursorKind.sizeVertical,
         tick: Tick(24), value: 106),
    ] {
        let fixture = drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(24, 64)])
        fixture.activate(fixture.panLane)
        let x = fixture.x(24)
        let y = fixture.y(fixture.panLane, 64)
        let shift = DrawerModifiers.shiftBit
        report.expect(
            fixture.page.pointerPress(x: x, y: y, surface: 1, button: 1,
                                      modifiers: shift),
            cppID: automationNodeDragGapID,
            message: "\(row.name) Shift press captures the node")
        _ = fixture.page.pointerMove(x: x + 12, y: y, buttons: 1, modifiers: shift)
        let finalX = row.cursor == .sizeHorizontal ? fixture.x(row.tick) : x + 12
        let finalY = row.cursor == .sizeHorizontal ? y + 12 : fixture.y(fixture.panLane, row.value)
        _ = fixture.page.pointerMove(
            x: finalX, y: finalY, buttons: 1, modifiers: shift)
        report.expectEqual(
            row.cursor, fixture.page.observation.cursorIntent,
            cppID: automationNodeDragGapID,
            what: "\(row.name) Shift chooses and publishes the dominant axis lock")
        report.expectEqual(
            ["\(row.tick):\(row.value)"], fixture.page.previewPoints.map { "\($0.tick):\($0.value)" },
            cppID: automationNodeDragGapID,
            what: "\(row.name) preview pins the locked dimension")
        let axisBefore = fixture.snapshot
        _ = fixture.page.pointerRelease(
            x: finalX, y: finalY, button: 1, modifiers: shift)
        report.expectEqual(
            axisBefore.revision + 1, fixture.document.revision,
            cppID: automationNodeDragGapID,
            what: "\(row.name) A016 axis-locked release commits one revision")
        report.expectEqual(
            ["\(row.tick):\(row.value)"], fixture.values(fixture.panLane),
            cppID: automationNodeDragGapID,
            what: "\(row.name) A017/A018 axis-locked commit pins the other dimension")
    }

    let phantom = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 64), (96, 20)])
    phantom.activate(phantom.panLane)
    _ = phantom.session.mutateCamera { $0.setHScroll(70) }
    report.expect(
        phantom.page.publishedNodes.first?.phantom == true,
        cppID: automationNodeDragGapID,
        message: "A019/A020 scrolled source is published as the origin phantom")
    let phantomBefore = phantom.snapshot
    let phantomY = phantom.y(phantom.panLane, 64)
    report.expect(
        phantom.page.pointerPress(x: 0, y: phantomY, surface: 1, button: 1),
        cppID: automationNodeDragGapID,
        message: "A021-A024 origin phantom captures through the production hit seam")
    report.expect(
        phantom.page.observation.pointerKind == .originPhantomDrag,
        cppID: automationNodeDragGapID,
        message: "A021 phantom press publishes semantic ownership")
    _ = phantom.page.pointerMove(x: 12, y: phantomY, buttons: 1)
    _ = phantom.page.pointerMove(x: 12, y: phantom.y(phantom.panLane, 90), buttons: 1)
    _ = phantom.page.pointerRelease(x: 12, y: phantom.y(phantom.panLane, 90), button: 1)
    report.expectEqual(
        phantomBefore.revision + 1, phantom.document.revision,
        cppID: automationNodeDragGapID,
        what: "A025/A026 phantom value drag commits once")
    report.expectEqual(
        ["0:90", "96:20"], phantom.values(phantom.panLane),
        cppID: automationNodeDragGapID,
        what: "A027/A028 phantom commit retains tick zero and changes its value")
    report.expect(
        phantom.undo(), cppID: automationNodeDragGapID,
        message: "A035-A038 scrolled phantom commit is undoable")
    report.expectEqual(
        ["0:64", "96:20"], phantom.values(phantom.panLane),
        cppID: automationNodeDragGapID,
        what: "A035-A039 phantom undo restores the exact original lane state")

    let selected = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(48, 32), (96, 64), (144, 96), (192, 80)])
    selected.activate(selected.panLane)
    selected.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 192), scope: .tracks([0])))
    let selectedBefore = selected.snapshot
    report.expect(
        automationGapMoveNode(selected, parameter: selected.panLane,
                              from: (96, 64), to: (120, 64)),
        cppID: automationNodeDragGapID,
        message: "A040-A043 selected-range drag commits through the grabbed node")
    report.expectEqual(
        ["72:32", "120:64", "168:96", "192:80"], selected.values(selected.panLane),
        cppID: automationNodeDragGapID,
        what: "A044 selected drag moves covered points and preserves the half-open endpoint")
    report.expectEqual(
        TimeRange(startTick: 48, endTick: 216), selected.page.selection?.range,
        cppID: automationNodeDragGapID,
        what: "A045/A046 selected drag shifts the range by the shared delta")
    report.expectEqual(
        selectedBefore.revision + 1, selected.document.revision,
        cppID: automationNodeDragGapID,
        what: "A047 selected drag is one document transaction")
    report.expect(
        selected.undo(), cppID: automationNodeDragGapID,
        message: "A048 selected drag is undoable as a group")
    report.expectEqual(
        ["48:32", "96:64", "144:96", "192:80"], selected.values(selected.panLane),
        cppID: automationNodeDragGapID,
        what: "A049 group undo restores all selected points")

    let cancelled = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(48, 64)])
    cancelled.activate(cancelled.panLane)
    let cancelBefore = cancelled.snapshot
    let cancelX = cancelled.x(48)
    let cancelY = cancelled.y(cancelled.panLane, 64)
    report.expect(
        cancelled.page.pointerPress(x: cancelX, y: cancelY, surface: 1, button: 1),
        cppID: automationNodeDragGapID,
        message: "A050-A054 cancellation fixture captures its node")
    _ = cancelled.page.pointerMove(x: cancelX + 12, y: cancelY, buttons: 1)
    _ = cancelled.page.pointerMove(x: cancelX + 40, y: cancelY - 20, buttons: 1)
    report.expect(
        cancelled.page.handleEscape(), cppID: automationNodeDragGapID,
        message: "A058 Escape aborts the armed node drag")
    report.expectEqual(
        cancelBefore, cancelled.snapshot,
        cppID: automationNodeDragGapID,
        what: "A058/A059 aborted node drag changes neither document nor history")

    report.expect(
        cancelled.page.pointerPress(x: cancelX, y: cancelY, surface: 1, button: 1),
        cppID: automationNodeDragGapID,
        message: "A061-A063 recovery drag captures the node again")
    _ = cancelled.page.pointerMove(x: cancelX + 12, y: cancelY, buttons: 1)
    _ = cancelled.page.pointerMove(x: cancelX + 36, y: cancelY - 24, buttons: 1)
    cancelled.page.refreshFromDocument()
    report.expect(
        !cancelled.page.hasGesture,
        cppID: automationNodeDragGapID,
        message: "A064-A067 content rebuild cancels the stale adapter gesture")
    let rebuilt = cancelled.snapshot
    _ = cancelled.page.pointerRelease(x: cancelX + 36, y: cancelY - 24, button: 1)
    report.expectEqual(
        rebuilt, cancelled.snapshot,
        cppID: automationNodeDragGapID,
        what: "A065-A067 release after rebuild cannot commit the cancelled draft")
    report.expect(
        automationGapMoveNode(cancelled, parameter: cancelled.panLane,
                              from: (48, 64), to: (72, 80)),
        cppID: automationNodeDragGapID,
        message: "A068-A071 page accepts a fresh drag after rebuild cancellation")
    report.expectEqual(
        ["72:80"], cancelled.values(cancelled.panLane),
        cppID: automationNodeDragGapID,
        what: "A069-A071 recovered drag commits its destination")
}

@MainActor
func drawerAutomationOwnershipGapChecks(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let rings = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(48, 32), (96, 64), (144, 96), (192, 80)])
    rings.activate(rings.panLane)
    rings.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 192), scope: .tracks([0])))
    report.expect(
        rings.page.publishedNodes.filter(\.selected).map { Tick($0.tick) } == [48, 96, 144],
        cppID: automationOwnershipGapID,
        message: "A001 selection rings are paint-model flags on exactly the half-open selected nodes")
    let ringBefore = rings.snapshot
    report.expect(
        automationGapMoveNode(rings, parameter: rings.panLane,
                              from: (96, 64), to: (120, 64)),
        cppID: automationOwnershipGapID,
        message: "A008-A013 track selection group drag releases as one commit")
    report.expectEqual(
        ["72:32", "120:64", "168:96", "192:80"], rings.values(rings.panLane),
        cppID: automationOwnershipGapID,
        what: "A014-A024 group drag moves all and only selected occurrences")
    report.expect(
        rings.page.selection?.scope == .tracks([0])
            && rings.page.selection?.range == TimeRange(startTick: 48, endTick: 216),
        cppID: automationOwnershipGapID,
        message: "A025-A029 group drag preserves track scope and shifts its range")
    report.expectEqual(
        ringBefore.revision + 1, rings.document.revision,
        cppID: automationOwnershipGapID,
        what: "A011-A013 group drag records one revision and history entry")
    report.expect(
        rings.undo(), cppID: automationOwnershipGapID,
        message: "A030-A038 one undo restores the entire selected group")
    report.expectEqual(
        ["48:32", "96:64", "144:96", "192:80"], rings.values(rings.panLane),
        cppID: automationOwnershipGapID,
        what: "A032-A038 undo restores original ticks and removes moved ticks")
    do {
        _ = try drawerAutomationRunBlocking { try await rings.session.redo() }
    } catch {
        report.fail(automationOwnershipGapID, "A039/A040 group redo failed: \(error)")
    }
    report.expectEqual(
        ["72:32", "120:64", "168:96", "192:80"], rings.values(rings.panLane),
        cppID: automationOwnershipGapID,
        what: "A039-A041 redo restores the grouped move")

    let retainedPencil = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 40)])
    retainedPencil.activate(retainedPencil.panLane)
    retainedPencil.page.isPencilMode = true
    let pencilY = retainedPencil.y(retainedPencil.panLane, 92)
    report.expect(
        retainedPencil.page.pointerPress(x: retainedPencil.x(48), y: pencilY,
                                         surface: 1, button: 1),
        cppID: automationOwnershipGapID,
        message: "A042-A046 pencil mode starts a pencil-owned gesture")
    retainedPencil.page.isPencilMode = false
    report.expect(
        retainedPencil.page.observation.pointerKind == .pencilStroke,
        cppID: automationOwnershipGapID,
        message: "A043-A046 tool toggle retains the captured pencil gesture")
    _ = retainedPencil.page.pointerMove(
        x: retainedPencil.x(96), y: pencilY, buttons: 1)
    _ = retainedPencil.page.pointerRelease(
        x: retainedPencil.x(96), y: pencilY, button: 1)
    report.expect(
        retainedPencil.values(retainedPencil.panLane).contains { $0.hasSuffix(":92") },
        cppID: automationOwnershipGapID,
        message: "A047-A049 retained pencil gesture commits its final value")

    let retainedNode = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(72, 40), (192, 20)])
    retainedNode.activate(retainedNode.panLane)
    let nodeX = retainedNode.x(72)
    let nodeY = retainedNode.y(retainedNode.panLane, 40)
    retainedNode.page.isPencilMode = false
    report.expect(
        retainedNode.page.pointerPress(x: nodeX, y: nodeY, surface: 1, button: 1),
        cppID: automationOwnershipGapID,
        message: "A050-A056 arrow mode captures a node gesture")
    retainedNode.page.isPencilMode = true
    report.expect(
        retainedNode.page.observation.pointerKind == .nodeDrag,
        cppID: automationOwnershipGapID,
        message: "A053-A056 tool toggle retains the captured node gesture")
    _ = retainedNode.page.pointerMove(x: nodeX + 12, y: nodeY, buttons: 1)
    _ = retainedNode.page.pointerMove(
        x: nodeX + 12 + retainedNode.x(168) - nodeX,
        y: retainedNode.y(retainedNode.panLane, 96), buttons: 1)
    _ = retainedNode.page.pointerRelease(
        x: nodeX + 12 + retainedNode.x(168) - nodeX,
        y: retainedNode.y(retainedNode.panLane, 96), button: 1)
    report.expectEqual(
        ["168:96", "192:20"], retainedNode.values(retainedNode.panLane),
        cppID: automationOwnershipGapID,
        what: "A051/A052/A057-A064 retained node gesture moves its source and preserves sibling")

    let outside = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 20)])
    outside.activate(outside.panLane)
    outside.page.selectRange(from: 0, to: 48, lanes: [outside.panLane])
    outside.page.isPencilMode = true
    _ = outside.page.pointerPress(
        x: outside.x(96), y: outside.y(outside.panLane, 70), surface: 1, button: 1)
    report.expect(
        outside.page.selection == nil,
        cppID: automationOwnershipGapID,
        message: "A065/A066 pencil press outside the active band clears selection")
    _ = outside.page.handleEscape()

    let precedence = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(72, 40)])
    precedence.activate(precedence.panLane)
    precedence.page.isPencilMode = true
    _ = precedence.session.mutateCamera { _ = $0.setTimeZoom(1) }
    report.expect(
        precedence.page.publishedNodes.isEmpty,
        cppID: automationOwnershipGapID,
        message: "A067-A077 below detail threshold the paint model publishes no node markers")
    let hiddenBefore = precedence.snapshot
    _ = precedence.page.pointerPress(
        x: precedence.x(72), y: precedence.y(precedence.panLane, 40), surface: 1, button: 1)
    report.expect(
        precedence.page.observation.pointerKind == .pencilStroke,
        cppID: automationOwnershipGapID,
        message: "A070-A077 hidden-node hit precedence starts a pencil stroke")
    _ = precedence.page.handleEscape()
    report.expectEqual(
        hiddenBefore, precedence.snapshot,
        cppID: automationOwnershipGapID,
        what: "A073-A077 cancelling hidden-node pencil ownership preserves its source")
    _ = precedence.session.mutateCamera { _ = $0.setTimeZoom(90) }
    report.expect(
        precedence.page.publishedNodes.contains { Tick($0.tick) == 72 },
        cppID: automationOwnershipGapID,
        message: "A078-A086 above detail threshold the written node marker is published")
    let visibleX = precedence.x(72)
    let visibleY = precedence.y(precedence.panLane, 40)
    _ = precedence.page.pointerPress(x: visibleX, y: visibleY, surface: 1, button: 1)
    report.expect(
        precedence.page.observation.pointerKind == .nodeDrag,
        cppID: automationOwnershipGapID,
        message: "A079-A087 visible-node hit precedence captures the node drag")
    _ = precedence.page.pointerMove(x: visibleX + 12, y: visibleY, buttons: 1)
    _ = precedence.page.pointerMove(
        x: visibleX + 12 + precedence.x(96) - visibleX,
        y: precedence.y(precedence.panLane, 80), buttons: 1)
    _ = precedence.page.pointerRelease(
        x: visibleX + 12 + precedence.x(96) - visibleX,
        y: precedence.y(precedence.panLane, 80), button: 1)
    report.expectEqual(
        ["96:80"], precedence.values(precedence.panLane),
        cppID: automationOwnershipGapID,
        what: "A081-A088 visible node moves rather than painting through it")

    let switched = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(72, 40), (144, 20)])
    switched.activate(switched.panLane)
    let switchBefore = switched.snapshot
    let switchX = switched.x(72)
    let switchY = switched.y(switched.panLane, 40)
    report.expect(
        switched.page.pointerPress(x: switchX, y: switchY, surface: 1, button: 1),
        cppID: automationOwnershipGapID,
        message: "A090-A095 parameter-switch fixture arms a node drag")
    _ = switched.page.pointerMove(x: switchX + 12, y: switchY, buttons: 1)
    _ = switched.page.pointerMove(x: switchX + 48, y: switchY - 20, buttons: 1)
    switched.activate(.tempo)
    report.expect(
        switched.page.activeParameter == .tempo
            && !switched.page.hasGesture
            && switched.page.observation.pointerKind == nil,
        cppID: automationOwnershipGapID,
        message: "A097-A102 parameter switch synchronously ungrabs the node")
    _ = switched.page.pointerRelease(x: switchX + 48, y: switchY - 20, button: 1)
    report.expectEqual(
        switchBefore, switched.snapshot,
        cppID: automationOwnershipGapID,
        what: "A094/A105-A112 release after parameter switch mutates no lane or history")
    switched.activate(switched.panLane)
    report.expect(
        automationGapMoveNode(switched, parameter: switched.panLane,
                              from: (72, 40), to: (96, 90)),
        cppID: automationOwnershipGapID,
        message: "A113-A123 switched-back lane accepts a fresh node drag")
    report.expectEqual(
        ["96:90", "144:20"], switched.values(switched.panLane),
        cppID: automationOwnershipGapID,
        what: "A124-A127 fresh drag commits target and preserves sibling")
}
