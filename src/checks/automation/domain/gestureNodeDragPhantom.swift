import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
func drawerAutomationNodeDragAndPhantomOutcomes(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 60), (48, 80), (120, 40)])
    let facts = fixture.facts(fixture.panLane)
    let sources = facts.snapshot.sources
    report.expectEqual(
        expected: 3, actual: sources.count, cppID: drawerAutomationNodeDragID,
        what: "the fixture offers three draggable nodes")

    // An empty gesture finishes as a no-op.
    let empty = AutomationNodeDragTransaction(
        facts: facts, targets: [], grabbedPoint: 0,
        selectionDrag: false, press: (100, 100),
        deleteOnStationary: true)
    report.expectEqual(
        expected: AutomationPointRelease.noOp, actual: empty.finish().release, cppID: drawerAutomationNodeDragID,
        what: "a gesture with no target finishes as a no-op")
    report.expect(
        !empty.finish().changed, cppID: drawerAutomationNodeDragID,
        message: "an empty gesture reports no change")

    // A Shift-held stationary release is a no-op; a plain one deletes.
    let shiftPress = AutomationNodeDragTransaction.single(
        facts: facts, source: sources[0],
        press: (100, 100),
        deleteOnStationary: false)
    report.expectEqual(
        expected: AutomationPointRelease.noOp, actual: shiftPress.finish().release, cppID: drawerAutomationNodeDragID,
        what: "a Shift-held stationary release is a no-op")
    report.expect(
        !shiftPress.finish().changed, cppID: drawerAutomationNodeDragID,
        message: "a Shift-held stationary release changes nothing")
    var plainPress = AutomationNodeDragTransaction.single(
        facts: facts, source: sources[0],
        press: (100, 100),
        deleteOnStationary: true)
    report.expectEqual(
        expected: AutomationPointRelease.stationaryDelete, actual: plainPress.finish().release,
        cppID: drawerAutomationNodeDragID, what: "a stationary release without Shift deletes")
    report.expect(
        !plainPress.finish().changed, cppID: drawerAutomationNodeDragID,
        message: "the stationary delete reports no move")

    // Past the slop without moving: a move that changed nothing.
    _ = plainPress.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    report.expectEqual(
        expected: AutomationPointRelease.move, actual: plainPress.finish().release, cppID: drawerAutomationNodeDragID,
        what: "a released stroke past the slop is a move")
    report.expect(
        !plainPress.finish().changed, cppID: drawerAutomationNodeDragID,
        message: "a stroke that never moved the node changes nothing")

    // The same gesture with a moved node: one move with the grabbed delta.
    _ = plainPress.update(
        AutomationPointDrag.Update(
            phase: .dragging, effectiveX: 130,
            effectiveY: 100, axisLock: .none),
        mapped: AutomationLanePoint(tick: 30, value: 80))
    let moved = plainPress.finish()
    report.expectEqual(
        expected: AutomationPointRelease.move, actual: moved.release, cppID: drawerAutomationNodeDragID,
        what: "the moved gesture is still a move")
    report.expect(moved.changed, cppID: drawerAutomationNodeDragID, message: "the moved node reports a change")
    report.expectEqual(
        expected: 6, actual: moved.dTick, cppID: drawerAutomationNodeDragID,
        what: "the reported delta is the grabbed node's own tick delta")
    report.expectEqual(
        expected: AutomationLanePoint(tick: 30, value: 80), actual: plainPress.targets[0].current,
        cppID: drawerAutomationNodeDragID, what: "the target's preview is the mapped destination")

    // A selected set shares one delta and keeps its spacing.
    var group = AutomationNodeDragTransaction(
        facts: facts,
        targets: [
            AutomationNodeDragTarget(
                parameter: fixture.panLane, source: sources[0],
                minimum: 0, maximum: 127),
            AutomationNodeDragTarget(
                parameter: fixture.panLane, source: sources[1],
                minimum: 0, maximum: 127),
        ],
        grabbedPoint: 0, selectionDrag: true, press: (100, 100), deleteOnStationary: true)
    _ = group.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    _ = group.update(
        AutomationPointDrag.Update(
            phase: .dragging, effectiveX: 105,
            effectiveY: 100, axisLock: .none),
        mapped: AutomationLanePoint(tick: 30, value: 70))
    let groupFinish = group.finish()
    report.expectEqual(
        expected: AutomationPointRelease.move, actual: groupFinish.release,
        cppID: drawerAutomationNodeDragID, what: "the selection releases as a move")
    report.expect(
        groupFinish.changed, cppID: drawerAutomationNodeDragID,
        message: "the moved selection reports a change")
    report.expectEqual(
        expected: 6, actual: groupFinish.dTick, cppID: drawerAutomationNodeDragID,
        what: "the shared delta is the grabbed node's delta")
    report.expect(
        groupFinish.selectionDrag, cppID: drawerAutomationNodeDragID,
        message: "the finish reports that the whole selection moved")
    report.expectEqual(
        expected: ["30:70", "54:90"], actual: group.targets.map { "\($0.current.tick):\($0.current.value)" },
        cppID: drawerAutomationNodeDragID, what: "every selected node moves by the same delta")

    // The lower edge clamps the common delta, so the group keeps its spacing.
    var edge = AutomationNodeDragTransaction(
        facts: facts,
        targets: [
            AutomationNodeDragTarget(
                parameter: fixture.panLane, source: sources[0],
                minimum: 0, maximum: 127),
            AutomationNodeDragTarget(
                parameter: fixture.panLane, source: sources[1],
                minimum: 0, maximum: 127),
        ],
        grabbedPoint: 1, selectionDrag: false, press: (100, 100), deleteOnStationary: false)
    _ = edge.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    _ = edge.update(
        AutomationPointDrag.Update(
            phase: .dragging, effectiveX: 100,
            effectiveY: 100, axisLock: .none),
        mapped: AutomationLanePoint(tick: 0, value: 80))
    report.expectEqual(
        expected: ["0:60", "24:80"], actual: edge.targets.map { "\($0.current.tick):\($0.current.value)" },
        cppID: drawerAutomationNodeDragID,
        what: "a leftward drag clamps at tick zero without collapsing the group")
    report.expectEqual(
        expected: -24, actual: edge.finish().dTick, cppID: drawerAutomationNodeDragID,
        what: "the clamped delta is what the finish reports")
    report.expectEqual(
        expected: AutomationPointRelease.move, actual: edge.finish().release,
        cppID: drawerAutomationNodeDragID, what: "the clamped group releases as a move")
    report.expect(
        edge.finish().changed, cppID: drawerAutomationNodeDragID,
        message: "the clamped group reports a change")

    // The axis lock pins one axis.
    var locked = AutomationNodeDragTransaction.single(
        facts: facts, source: sources[1],
        press: (100, 100),
        deleteOnStationary: false)
    _ = locked.update(
        AutomationPointDrag.Update(
            phase: .dragging, effectiveX: 130,
            effectiveY: 60, axisLock: .time),
        mapped: AutomationLanePoint(tick: 60, value: 20))
    report.expectEqual(
        expected: 80, actual: locked.targets[0].current.value, cppID: drawerAutomationNodeDragID,
        what: "a time lock keeps the original value")
    report.expectEqual(
        expected: Tick(60), actual: locked.targets[0].current.tick, cppID: drawerAutomationNodeDragID,
        what: "a time lock keeps the mapped tick")

    // A phantom drag restores its source on reset and clamps into the domain.
    var phantom = AutomationPhantomDragTransaction(
        facts: facts, source: sources[0],
        press: (100, 100))
    report.expectEqual(
        expected: AutomationAxisLock.value,
        actual: phantom.update(
            AutomationPointDrag.Update(
                phase: .reset, effectiveX: 100,
                effectiveY: 100, axisLock: .none),
            mappedValue: 127),
        cppID: drawerAutomationNodeDragID, what: "a phantom drag only ever locks the value axis")
    report.expectEqual(
        expected: AutomationLanePoint(tick: 24, value: 60), actual: phantom.target.current,
        cppID: drawerAutomationNodeDragID, what: "a reset restores the phantom's source value")
    report.expect(
        phantom.finish() == nil, cppID: drawerAutomationNodeDragID,
        message: "a reset phantom finishes as no edit")
    _ = phantom.drag.update(x: 100, y: 110, shiftHeld: false, activationDistance: 5)
    _ = phantom.update(
        AutomationPointDrag.Update(
            phase: .dragging, effectiveX: 100,
            effectiveY: 110, axisLock: .value),
        mappedValue: 200)
    guard let phantomTarget = phantom.finish() else {
        report.fail(drawerAutomationNodeDragID, "the dragged phantom publishes no target")
        return
    }
    report.expectEqual(
        expected: phantomTarget.original.tick, actual: phantomTarget.current.tick, cppID: drawerAutomationNodeDragID,
        what: "a phantom drag never moves in time")
    report.expectEqual(
        expected: 127, actual: phantomTarget.current.value, cppID: drawerAutomationNodeDragID,
        what: "a phantom drag clamps into the lane's domain")
    report.expectEqual(
        expected: Tick(24), actual: phantom.move?.sourceTick ?? 0, cppID: drawerAutomationNodeDragID,
        what: "the phantom's write names its own source tick")

    var committed = AutomationNodeDragTransaction.single(
        facts: facts, source: sources[0],
        press: (100, 100),
        deleteOnStationary: true)
    _ = committed.drag.update(x: 120, y: 100, shiftHeld: false, activationDistance: 5)
    _ = committed.update(
        AutomationPointDrag.Update(
            phase: .dragging, effectiveX: 120,
            effectiveY: 100, axisLock: .none),
        mapped: AutomationLanePoint(tick: 48, value: 90))
    let beforeCommit = fixture.snapshot
    guard
        let plan = AutomationNodeResolver.moves([
            AutomationNodeResolver.LaneMoves(facts, committed.moves)
        ])
    else {
        report.fail(drawerAutomationNodeDragID, "the committed drag resolved no plan")
        return
    }
    report.expect(
        AutomationCommit.apply(plan, in: fixture.document), cppID: drawerAutomationNodeDragID,
        message: "the committed drag writes once")
    report.expectEqual(
        expected: ["48:90", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationNodeDragID,
        what: "the node lands on its destination and evicts the occupant there")
    report.expectEqual(
        expected: beforeCommit.revision + 1, actual: fixture.document.revision, cppID: drawerAutomationNodeDragID,
        what: "one drag is one revision")
    report.expect(fixture.undo(), cppID: drawerAutomationNodeDragID, message: "the drag is undoable")
    report.expectEqual(
        expected: ["24:60", "48:80", "120:40"], actual: fixture.values(fixture.panLane),
        cppID: drawerAutomationNodeDragID,
        what: "one undo restores the moved node and the evicted occupant")

    let promotion = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    let promotionFacts = promotion.facts(promotion.panLane)
    report.expectEqual(
        expected: ["0:64"], actual: promotion.laneValues(promotionFacts.displayPoints),
        cppID: drawerAutomationNodeDragID,
        what: "the empty lane displays its projected engine node")
    guard
        let promotionPlan = AutomationNodeResolver.moves([
            AutomationNodeResolver.LaneMoves(
                promotionFacts,
                [
                    AutomationNodeMove(parameter: promotion.panLane, sourceTick: 0, tick: 0, value: 20)
                ])
        ])
    else {
        report.fail(drawerAutomationNodeDragID, "the promotion resolved no plan")
        return
    }
    report.expect(
        !promotionPlan.isEmpty, cppID: drawerAutomationNodeDragID,
        message: "a write on the projected node resolves to a promotion")
    report.expect(
        AutomationCommit.apply(promotionPlan, in: promotion.document), cppID: drawerAutomationNodeDragID,
        message: "the promotion commits")
    report.expectEqual(
        expected: ["0:20"], actual: promotion.values(promotion.panLane), cppID: drawerAutomationNodeDragID,
        what: "the projected node becomes a written event at its own tick")
    report.expect(
        promotion.undo() && promotion.values(promotion.panLane).isEmpty, cppID: drawerAutomationNodeDragID,
        message: "one undo returns the lane to its projected node alone")
    let tickID = "automation/AutomationEditingTest::nodeDragCommits"
    for parameter in [AutomationParameter.tempo, fixture.panLane] {
        let tickMove = drawerAutomationAutomationFixture(
            suite: suite, service: service,
            pan: [(24, 60), (120, 40)],
            tempo: [(24, 600_000), (120, 500_000)])
        tickMove.activate(parameter)
        let value = parameter == .tempo ? 100 : 60
        let before = tickMove.snapshot
        let y = tickMove.y(parameter, value)
        let start = tickMove.x(24)
        let finish = tickMove.x(96) + 30
        report.expect(
            tickMove.page.pointerPress(
                x: start, y: y, surface: 1,
                button: AutomationQtButton.left),
            cppID: tickID, message: "the written node takes its drag")
        _ = tickMove.page.pointerMove(x: start + 30, y: y, buttons: AutomationQtButton.left)
        _ = tickMove.page.pointerMove(x: finish, y: y, buttons: AutomationQtButton.left)
        report.expectEqual(
            expected: before, actual: tickMove.snapshot, cppID: tickID,
            what: "a node drag preview writes nothing before release")
        _ = tickMove.page.pointerRelease(x: finish, y: y, button: AutomationQtButton.left)
        let actual = parameter == .tempo ? tickMove.tempoValues : tickMove.values(tickMove.panLane)
        let expected = parameter == .tempo ? ["96:100", "120:120"] : ["96:60", "120:40"]
        report.expectEqual(
            expected: expected, actual: actual, cppID: tickID,
            what: "a node drag commits the tick and count outcomes")
        report.expectEqual(
            expected: before.revision + 1, actual: tickMove.document.revision,
            cppID: tickID, what: "a node drag commits one revision")
        report.expect(tickMove.undo(), cppID: tickID, message: "the moved tick is undoable")
    }
    let phantomID = "automation/AutomationEditingTest::scrolledOriginPhantomCommits"
    for parameter in [AutomationParameter.tempo, fixture.panLane] {
        let scrolled = drawerAutomationAutomationFixture(
            suite: suite, service: service,
            pan: [(24, 60), (120, 40)],
            tempo: [(24, 600_000), (120, 500_000)])
        scrolled.activate(parameter)
        let independentHitRadius = max(1, (scrolled.page.baseFontPx * 7 / 12).rounded())
        let scroll = scrolled.x(24) + independentHitRadius * 2
        _ = scrolled.viewport.mutateCamera { $0.setHScroll(scroll) }
        guard let projected = scrolled.page.projection?.originPhantom,
            let handle = scrolled.page.publishedNodes.first(where: \.phantom)
        else {
            report.fail(phantomID, "scrolling leaves no origin phantom in the production plot")
            continue
        }
        let before = scrolled.snapshot
        let original = parameter == .tempo ? scrolled.tempoValues : scrolled.values(scrolled.panLane)
        report.expectEqual(
            expected: Tick(24), actual: projected.point.tick, cppID: phantomID,
            what: "a scrolled node becomes the origin phantom")
        report.expectEqual(
            expected: Double(projected.point.tick), actual: handle.tick,
            cppID: phantomID, what: "the phantom retains its source tick")
        let y = projected.point.y
        _ = scrolled.page.pointerMove(x: 0, y: y, buttons: 0)
        report.expectEqual(
            expected: AutomationCursorKind.arrow.rawValue,
            actual: scrolled.page.cursorKind, cppID: phantomID,
            what: "an origin phantom hover keeps the arrow cursor")
        report.expectEqual(
            expected: AutomationHintProfile.originPhantom,
            actual: scrolled.page.hoverHintProfile, cppID: phantomID,
            what: "an origin phantom hover advertises its own operation")
        let targetY = scrolled.y(parameter, 110)
        report.expect(
            scrolled.page.pointerPress(
                x: 0, y: y, surface: 1,
                button: AutomationQtButton.left),
            cppID: phantomID, message: "the origin phantom takes its press")
        _ = scrolled.page.pointerMove(x: 0, y: y - 30, buttons: AutomationQtButton.left)
        let firstPreview = AutomationDisplayProbe(scrolled.page)
        let firstCurve = firstPreview.preview.first {
            $0.argb == SceneRectPacking.argb(scrolled.page.palette.selectionEdge) && $0.h <= 2
        }
        report.expect(
            firstPreview.valid && firstCurve != nil
                && (firstCurve?.w ?? 0) > independentHitRadius * 2,
            cppID: phantomID,
            message: "an activated phantom paints a full held-value preview curve")
        _ = scrolled.page.pointerMove(x: 0, y: targetY - 30, buttons: AutomationQtButton.left)
        let movedPreview = AutomationDisplayProbe(scrolled.page)
        let movedCurve = movedPreview.preview.first {
            $0.argb == SceneRectPacking.argb(scrolled.page.palette.selectionEdge) && $0.h <= 2
        }
        report.expect(
            movedPreview.valid && movedCurve != nil
                && (movedCurve?.w ?? 0) > independentHitRadius * 2,
            cppID: phantomID,
            message: "a moved phantom retains its full preview curve")
        let curveDelta = (movedCurve?.y ?? -1) - (firstCurve?.y ?? -1)
        report.expect(
            abs(curveDelta) > 0.5 / scrolled.page.devicePixelRatio
                && curveDelta * (targetY - y) > 0,
            cppID: phantomID,
            message: "a moved phantom shifts the preview curve toward its target by a pixel")
        report.expectEqual(
            expected: before, actual: scrolled.snapshot, cppID: phantomID,
            what: "a scrolled-origin preview writes nothing")
        _ = scrolled.page.pointerRelease(
            x: 0, y: targetY - 30,
            button: AutomationQtButton.left)
        let written = parameter == .tempo ? scrolled.tempoValues : scrolled.values(scrolled.panLane)
        report.expectEqual(
            expected: ["24:110", "120:\(parameter == .tempo ? 120 : 40)"],
            actual: written, cppID: phantomID,
            what: "a scrolled-origin drag commits through its phantom")
        report.expectEqual(
            expected: before.revision + 1, actual: scrolled.document.revision,
            cppID: phantomID, what: "the phantom edit commits once")
        report.expect(scrolled.undo(), cppID: phantomID, message: "the phantom edit undoes")
        report.expectEqual(
            expected: original,
            actual: parameter == .tempo
                ? scrolled.tempoValues
                : scrolled.values(scrolled.panLane),
            cppID: phantomID, what: "undo restores the phantom source")
    }
    let rangeID = "automation/AutomationEditingTest::selectedRangeDragAndDelete"
    for parameter in [AutomationParameter.tempo, fixture.panLane] {
        let selected = drawerAutomationAutomationFixture(
            suite: suite, service: service,
            pan: [(0, 80), (96, 100), (192, 64), (384, 110)],
            tempo: [(0, 750_000), (96, 600_000), (192, 937_500), (384, 545_455)])
        selected.activate(parameter)
        selected.page.selectRange(from: 96, to: 288, lanes: [parameter])
        let sourceX = selected.x(96)
        let sourceY = selected.y(parameter, 100)
        let endX = selected.x(144) + 30
        let before = selected.snapshot
        let beforeIndex = selected.document.history.undoIndex
        let beforeCount = selected.document.history.undoCount
        let beforeBytes = try! selected.document.captureSave().bytes
        report.expect(
            selected.page.pointerPress(
                x: sourceX, y: sourceY, surface: 1,
                button: AutomationQtButton.left),
            cppID: rangeID, message: "the selected node takes the group drag")
        _ = selected.page.pointerMove(
            x: sourceX + 30, y: sourceY,
            buttons: AutomationQtButton.left)
        _ = selected.page.pointerMove(
            x: endX, y: sourceY,
            buttons: AutomationQtButton.left)
        report.expectEqual(
            expected: before, actual: selected.snapshot, cppID: rangeID,
            what: "the selected-range preview writes nothing")
        _ = selected.page.pointerRelease(x: endX, y: sourceY, button: AutomationQtButton.left)
        let movedValues = parameter == .tempo ? selected.tempoValues : selected.values(selected.panLane)
        report.expectEqual(
            expected: ["0:80", "144:100", "240:64", "384:110"],
            actual: movedValues, cppID: rangeID,
            what: "the selected-range drag moves both nodes and preserves outside points")
        report.expectEqual(
            expected: TimeRange(startTick: 144, endTick: 336),
            actual: selected.page.selection?.range, cppID: rangeID,
            what: "the selected-range band follows its drag")
        report.expectEqual(
            expected: before.revision + 1, actual: selected.document.revision,
            cppID: rangeID, what: "the selected-range drag commits once")
        let movedBytes = try! selected.document.captureSave().bytes
        report.expect(
            selected.document.history.undoIndex == beforeIndex + 1
                && selected.document.history.undoCount == beforeCount + 1
                && movedBytes != beforeBytes, cppID: rangeID,
            message: "the selected-range release changes full-song bytes in one history entry")
        report.expect(
            selected.undo()
                && selected.document.history.undoIndex == beforeIndex
                && (try! selected.document.captureSave().bytes) == beforeBytes,
            cppID: rangeID,
            message: "selected-range undo restores the original full-song bytes and history index")
        report.expect(
            (try? runBlocking { try await selected.session.redo() }) == true
                && selected.document.history.undoIndex == beforeIndex + 1
                && (try! selected.document.captureSave().bytes) == movedBytes,
            cppID: rangeID,
            message: "selected-range redo restores the moved full-song bytes and history index")
        selected.page.selectRange(from: 96, to: 288, lanes: [parameter])
        let beforeDelete = selected.snapshot
        report.expect(
            selected.page.consumeSelectionCommand(command: .delete), cppID: rangeID,
            message: "the moved selection consumes Delete")
        let retainedValues = parameter == .tempo ? selected.tempoValues : selected.values(selected.panLane)
        report.expectEqual(
            expected: ["0:80", "384:110"], actual: retainedValues,
            cppID: rangeID, what: "a selected-range drag deletes through the range")
        report.expectEqual(
            expected: beforeDelete.revision + 1, actual: selected.document.revision,
            cppID: rangeID, what: "the selected-range delete commits once")
    }
}
