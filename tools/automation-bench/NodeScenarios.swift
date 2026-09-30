import Foundation
import PorydawCore

@testable import PorydawApp

// Node drag, cancel and projected-origin scenarios over the real AutomationPage
// pointer route; prompt scenarios live in PromptScenarios.swift.

// MARK: - Scenarios

@MainActor
func nodeScenarios() -> [BenchScenario] {
    nodeDragScenarios() + nodeNoOpScenarios() + promptScenarios() + originScenarios()
}

@MainActor
private func nodeDragScenarios() -> [BenchScenario] {
    var scenarios: [BenchScenario] = []

    // A plain drag of one node to a new value at its own tick.
    let valueDrag = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.valueDrag",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireTick(f, f.sourceTick, fine: false)
                try requireValue(f, f.highValue)
                let base = captureBaseline(f)
                valueDrag.baseline = base
                valueDrag.expected = edited(
                    base.points, removing: [f.sourceTick],
                    adding: [NodeBenchPoint(tick: f.sourceTick, value: f.highValue)])
            },
            run: { f in
                f.drag(from: f.sourceTick, value: f.lowValue, to: f.sourceTick, targetValue: f.highValue)
            },
            validate: { f in try expectCommitted(f, valueDrag) }))

    // Alt (fine) drag to the in-between value at the node's own tick.
    let fine = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.fineValueDrag",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireTick(f, f.sourceTick, fine: true)
                try requireValue(f, midValue(f))
                let base = captureBaseline(f)
                fine.baseline = base
                fine.expected = edited(
                    base.points, removing: [f.sourceTick],
                    adding: [NodeBenchPoint(tick: f.sourceTick, value: midValue(f))])
            },
            run: { f in
                f.drag(
                    from: f.sourceTick, value: f.lowValue, to: f.sourceTick,
                    targetValue: midValue(f), modifiers: AutomationQtModifier.alt)
            },
            validate: { f in try expectCommitted(f, fine) }))

    // A single node moved in time onto the empty in-between tick.
    let time = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.timeMoveToEmptyTick",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireEmpty(f, f.emptyTick)
                try requireTick(f, f.emptyTick, fine: true)
                try requireValue(f, f.lowValue)
                let base = captureBaseline(f)
                time.baseline = base
                time.expected = edited(
                    base.points, removing: [f.sourceTick],
                    adding: [NodeBenchPoint(tick: f.emptyTick, value: f.lowValue)])
            },
            run: { f in
                f.drag(
                    from: f.sourceTick, value: f.lowValue, to: f.emptyTick,
                    targetValue: f.lowValue, modifiers: AutomationQtModifier.alt)
            },
            validate: { f in try expectCommitted(f, time) }))

    // A single node moved onto its occupied neighbour: the occupant is evicted.
    let overwrite = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.moveOverwritesOccupied",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireNode(f, f.targetTick, f.highValue)
                try requireTick(f, f.targetTick, fine: false)
                let base = captureBaseline(f)
                overwrite.baseline = base
                overwrite.expected = edited(
                    base.points, removing: [f.sourceTick, f.targetTick],
                    adding: [NodeBenchPoint(tick: f.targetTick, value: f.lowValue)])
            },
            run: { f in
                f.drag(from: f.sourceTick, value: f.lowValue, to: f.targetTick, targetValue: f.lowValue)
            },
            validate: { f in try expectCommitted(f, overwrite) }))

    // A selected pair moved one step later: each keeps its value, the unselected
    // occupant of the last destination is evicted, and the selection follows.
    let selected = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.selectionDragCollision",
            prepare: { f in
                let step = f.targetTick - f.sourceTick
                let evicted = f.targetTick + step
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireNode(f, f.targetTick, f.highValue)
                try requireNode(f, evicted, f.lowValue)
                try requireTick(f, f.targetTick, fine: false)
                f.page.selectRange(from: f.sourceTick, to: f.targetTick + 1, lanes: [f.parameter])
                try f.check(f.page.coveredEventCount() == 2, "the selection covers exactly two nodes")
                let base = captureBaseline(f)
                selected.baseline = base
                selected.expected = edited(
                    base.points, removing: [f.sourceTick, f.targetTick, evicted],
                    adding: [
                        NodeBenchPoint(tick: f.targetTick, value: f.lowValue),
                        NodeBenchPoint(tick: evicted, value: f.highValue),
                    ])
            },
            run: { f in
                f.drag(from: f.sourceTick, value: f.lowValue, to: f.targetTick, targetValue: f.lowValue)
            },
            validate: { f in
                try expectCommitted(f, selected)
                let step = f.targetTick - f.sourceTick
                try f.check(
                    f.page.selection?.range
                        == TimeRange(startTick: f.sourceTick + step, endTick: f.targetTick + 1 + step),
                    "the selection shifted with the dragged set")
            }))

    // A selected pair dragged past tick zero: the shared delta clamps so the
    // earliest node lands on zero and the pair keeps its spacing.
    let clamp = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.selectionDragClampsAtZero",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireNode(f, f.targetTick, f.highValue)
                try requireTick(f, 0, fine: false)
                f.page.selectRange(from: f.sourceTick, to: f.targetTick + 1, lanes: [f.parameter])
                try f.check(f.page.coveredEventCount() == 2, "the selection covers exactly two nodes")
                let base = captureBaseline(f)
                clamp.baseline = base
                let step = f.targetTick - f.sourceTick
                clamp.expected = edited(
                    base.points, removing: [0, f.sourceTick, f.targetTick],
                    adding: [
                        NodeBenchPoint(tick: 0, value: f.lowValue),
                        NodeBenchPoint(tick: step, value: f.highValue),
                    ])
            },
            run: { f in
                // Grab the later node and pull it to zero: requested -targetTick,
                // clamped to -sourceTick by the earliest participant.
                f.drag(from: f.targetTick, value: f.highValue, to: 0, targetValue: f.highValue)
            },
            validate: { f in
                try expectCommitted(f, clamp)
                try f.check(
                    f.page.selection?.range
                        == TimeRange(startTick: 0, endTick: f.targetTick + 1 - f.sourceTick),
                    "the selection shifted by the clamped delta")
            }))

    // Control-held value drag next to the neutral: lanes with a neutral land on
    // it exactly; lanes without one keep the dragged value.
    let snap = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.snapValueDrag",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireTick(f, f.sourceTick, fine: false)
                let metadata = f.facts().metadata
                let target = (metadata.neutral ?? midValue(f)) + 1
                try requireValue(f, target)
                let landed: Int
                if let neutral = metadata.neutral {
                    try f.check(
                        metadata.snappedValue(
                            target, snapValue: true,
                            plotHeight: f.page.plotHeight,
                            neutralSnapRadius: f.page.geometry.neutralSnapRadius)
                            == neutral,
                        "the plot's neutral snap radius covers one value step")
                    landed = neutral
                } else {
                    landed = target
                }
                snap.targetValue = target
                let base = captureBaseline(f)
                snap.baseline = base
                snap.expected = edited(
                    base.points, removing: [f.sourceTick],
                    adding: [NodeBenchPoint(tick: f.sourceTick, value: landed)])
            },
            run: { f in
                f.drag(
                    from: f.sourceTick, value: f.lowValue, to: f.sourceTick,
                    targetValue: snap.targetValue, modifiers: AutomationQtModifier.control)
            },
            validate: { f in try expectCommitted(f, snap) }))

    // A release that never passed the slop deletes the node it pressed.
    let delete = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.stationaryDelete",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                let base = captureBaseline(f)
                delete.baseline = base
                delete.expected = edited(base.points, removing: [f.sourceTick], adding: [])
            },
            run: { f in f.click(tick: f.sourceTick, value: f.lowValue) },
            validate: { f in try expectCommitted(f, delete) }))

    // A stale drag: the gesture armed at press, then the document moved on
    // underneath it; the release must write nothing.
    let stale = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.staleReleaseRejected",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                let x = f.x(f.sourceTick)
                let y = f.y(f.lowValue)
                try f.check(
                    f.page.pointerPress(
                        x: x, y: y, surface: AutomationInputSurface.plot.rawValue,
                        button: AutomationQtButton.left),
                    "the press grabs the node")
                _ = f.page.pointerMove(x: x, y: y - 30, buttons: AutomationQtButton.left)
                stale.releaseX = x
                stale.releaseY = y - 30 + (f.y(f.highValue) - y)
                _ = f.page.pointerMove(x: x, y: stale.releaseY, buttons: AutomationQtButton.left)
                try mutateBehindPage(f)
                stale.baseline = captureBaseline(f)
            },
            run: { f in
                f.runResult = f.page.pointerRelease(
                    x: stale.releaseX, y: stale.releaseY,
                    button: AutomationQtButton.left)
            },
            validate: { f in
                try expectUnchanged(f, stale)
                try expectSettled(f)
            }))

    return scenarios
}

@MainActor
private func nodeNoOpScenarios() -> [BenchScenario] {
    var scenarios: [BenchScenario] = []

    // Shift-held stationary release: no delete, no write.
    let shift = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.shiftStationaryNoOp",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                shift.baseline = captureBaseline(f)
            },
            run: { f in
                f.click(tick: f.sourceTick, value: f.lowValue, modifiers: AutomationQtModifier.shift)
            },
            validate: { f in
                try expectUnchanged(f, shift)
                try expectSettled(f)
            }))

    // A drag that armed and returned to its own value changes nothing.
    let back = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.dragReturnNoOp",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireTick(f, f.sourceTick, fine: false)
                try requireValue(f, f.lowValue)
                back.baseline = captureBaseline(f)
            },
            run: { f in
                f.drag(from: f.sourceTick, value: f.lowValue, to: f.sourceTick, targetValue: f.lowValue)
            },
            validate: { f in
                try expectUnchanged(f, back)
                try expectSettled(f)
            }))

    // A press that moved less than the activation distance, then Escape.
    let slop = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.belowSlopCancel",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                slop.pressX = f.x(f.sourceTick)
                slop.pressY = f.y(f.lowValue)
                slop.releaseX = slop.pressX + f.page.geometry.nodeDragActivationDistance * 0.25
                slop.baseline = captureBaseline(f)
            },
            run: { f in
                let pressed = f.page.pointerPress(
                    x: slop.pressX, y: slop.pressY,
                    surface: AutomationInputSurface.plot.rawValue,
                    button: AutomationQtButton.left)
                _ = f.page.pointerMove(x: slop.releaseX, y: slop.pressY, buttons: AutomationQtButton.left)
                let live = f.page.gesture != nil
                // Escape is the cancellation; nothing reports a commit.
                slop.previewed = pressed && live && f.page.handleEscape()
                f.runResult = false
            },
            validate: { f in
                try f.check(slop.previewed, "the press held a live node gesture that Escape cancelled")
                try expectUnchanged(f, slop)
                try expectSettled(f)
            }))

    // A drag past the slop with a live preview, then Escape.
    let dragged = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "node.draggedCancel",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                dragged.pressX = f.x(f.sourceTick)
                dragged.pressY = f.y(f.lowValue)
                dragged.releaseY = dragged.pressY - 30 + (f.y(f.highValue) - dragged.pressY)
                dragged.baseline = captureBaseline(f)
            },
            run: { f in
                let pressed = f.page.pointerPress(
                    x: dragged.pressX, y: dragged.pressY,
                    surface: AutomationInputSurface.plot.rawValue,
                    button: AutomationQtButton.left)
                _ = f.page.pointerMove(
                    x: dragged.pressX, y: dragged.pressY - 30,
                    buttons: AutomationQtButton.left)
                _ = f.page.pointerMove(
                    x: dragged.pressX, y: dragged.releaseY,
                    buttons: AutomationQtButton.left)
                let previewed = f.page.previewPoints.contains {
                    $0.tick == f.sourceTick && $0.value == f.highValue
                }
                dragged.previewed = pressed && previewed && f.page.handleEscape()
                f.runResult = false
            },
            validate: { f in
                try f.check(dragged.previewed, "the drag previewed its target and Escape cancelled it")
                try expectUnchanged(f, dragged)
                try expectSettled(f)
            }))

    return scenarios
}
/// Lanes whose tick-zero node is projected from the engine default, not written.
@MainActor
private func projectsOrigin(_ f: BenchFixture) -> Bool {
    f.facts().snapshot.projectedTickZero
}

@MainActor
private func originValue(_ f: BenchFixture) throws -> Int {
    let facts = f.facts()
    try f.check(facts.snapshot.projectedTickZero, "the lane projects its tick-zero node")
    guard let origin = facts.displayPoints.first(where: { $0.tick == 0 }) else {
        throw BenchFailure(description: "the projected tick-zero node is not displayed")
    }
    return origin.value
}

@MainActor
private func originScenarios() -> [BenchScenario] {
    var scenarios: [BenchScenario] = []

    // Dragging the projected origin node promotes it into a written event.
    let promote = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "origin.promotionDrag",
            applies: { f in projectsOrigin(f) },
            prepare: { f in
                promote.targetValue = try originValue(f)
                try f.check(promote.targetValue != f.lowValue, "the origin differs from the drag target")
                try requireTick(f, 0, fine: false)
                try requireValue(f, f.lowValue)
                let base = captureBaseline(f)
                try f.check(!base.points.contains { $0.tick == 0 }, "tick zero holds no written occurrence")
                promote.baseline = base
                promote.expected = edited(
                    base.points, removing: [],
                    adding: [NodeBenchPoint(tick: 0, value: f.lowValue)])
            },
            run: { f in
                f.drag(from: 0, value: promote.targetValue, to: 0, targetValue: f.lowValue)
            },
            validate: { f in
                try expectCommitted(f, promote)
                try f.check(!f.facts().snapshot.projectedTickZero, "the origin is written, no longer projected")
            }))

    // A stationary release on the projected origin deletes nothing.
    let origin = NodeBenchScratch()
    scenarios.append(
        BenchScenario(
            name: "origin.stationaryDeleteNoOp",
            applies: { f in projectsOrigin(f) },
            prepare: { f in
                origin.targetValue = try originValue(f)
                origin.baseline = captureBaseline(f)
            },
            run: { f in f.click(tick: 0, value: origin.targetValue) },
            validate: { f in
                try expectUnchanged(f, origin)
                try f.check(f.facts().snapshot.projectedTickZero, "the origin stays projected")
                try expectSettled(f)
            }))

    return scenarios
}
