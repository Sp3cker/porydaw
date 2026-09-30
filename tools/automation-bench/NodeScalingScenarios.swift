import Foundation
import PorydawCore

@testable import PorydawApp

// Workload-scaled node scenarios: live pointer cadence over an armed gesture,
// release-only commits, and dense same-tick CC destination overwrites.

/// Scratch for one sample: untimed pointer path, modifiers and expected draft.
@MainActor
private final class NodeScalingScratch {
    let node = NodeBenchScratch()
    var modifiers = 0
    var path: [(x: Double, y: Double)] = []
    var preview: [AutomationLanePoint] = []
    var targets = 0
    var selectionDrag = false
}

/// Pointer y rises this far on the arming move, so the effective drag point sits
/// this far below the pointer for the rest of the gesture.
private let armLift = 30.0

private let left = AutomationQtButton.left

/// Production modifiers under which every `ticks` x maps back to its tick:
/// snapped first, Alt (fine) when the camera's snap policy is too coarse.
@MainActor
private func pointerModifiers(_ f: BenchFixture, ticks: [Tick]) throws -> Int {
    let projection = f.page.makeProjection(facts: f.facts(), camera: f.page.liveCamera())
    for (modifiers, fine) in [(0, false), (AutomationQtModifier.alt, true)]
    where ticks.allSatisfy({ projection.tick(atX: f.x($0), fine: fine) == $0 }) {
        return modifiers
    }
    let spacing = f.x(f.sourceTick + 24) - f.x(f.sourceTick)
    throw BenchFailure(
        description: "camera (\(spacing) px per node slot) cannot address ticks \(ticks) even with Alt")
}

/// Untimed press on the node at `tick` plus the arming move past the slop; the
/// live gesture must be a node drag that grabbed exactly that occurrence.
@MainActor
private func pressAndArm(
    _ f: BenchFixture, _ scratch: NodeScalingScratch, tick: Tick, value: Int
) throws -> AutomationNodeDragTransaction {
    try requireValue(f, value)
    let projection = f.page.makeProjection(facts: f.facts(), camera: f.page.liveCamera())
    let x = projection.x(tick)
    let y = f.y(value)
    try f.check(
        f.page.pointerPress(
            x: x, y: y, surface: AutomationInputSurface.plot.rawValue, button: left,
            modifiers: scratch.modifiers),
        "the press at tick \(tick) is consumed")
    try f.check(
        f.page.pointerMove(x: x, y: y - armLift, buttons: left, modifiers: scratch.modifiers),
        "the arming move is consumed")
    guard case .node(let transaction)? = f.page.gesture else {
        throw BenchFailure(
            description:
                "press at tick \(tick) is not pickable as a node: gesture \(String(describing: f.page.gesture))")
    }
    try f.check(transaction.drag.exceeded, "the arming move passed the activation distance")
    try f.check(
        transaction.grabbed?.original == AutomationLanePoint(tick: tick, value: value),
        "the press grabbed \(tick):\(value), found \(String(describing: transaction.grabbed?.original))")
    return transaction
}

/// Pointer coordinates whose effective drag point is `tick`/`value`.
@MainActor
private func pointer(_ f: BenchFixture, _ tick: Tick, _ value: Int) -> (x: Double, y: Double) {
    (f.x(tick), f.y(value) - armLift)
}

/// `samples` evenly spaced pointer positions from the armed pointer to `end`.
@MainActor
private func linearPath(
    _ f: BenchFixture, from start: (x: Double, y: Double), to end: (x: Double, y: Double)
) -> [(x: Double, y: Double)] {
    (1...f.samples).map { sample in
        let fraction = Double(sample) / Double(f.samples)
        return sample == f.samples
            ? end : (start.x + (end.x - start.x) * fraction, start.y + (end.y - start.y) * fraction)
    }
}

@MainActor
private func movePath(_ f: BenchFixture, _ scratch: NodeScalingScratch) {
    for point in scratch.path {
        _ = f.page.pointerMove(x: point.x, y: point.y, buttons: left, modifiers: scratch.modifiers)
        drainNotifications()
    }
}

/// The armed gesture still owns the page, previews exactly the expected draft,
/// and wrote nothing; Escape then retires it without a write.
@MainActor
private func expectLiveDraftThenCancel(_ f: BenchFixture, _ scratch: NodeScalingScratch) throws {
    guard let before = scratch.node.baseline else { throw BenchFailure(description: "no prepared baseline") }
    guard case .node(let transaction)? = f.page.gesture else {
        throw BenchFailure(description: "the node gesture is still live")
    }
    try f.check(f.page.frozen?.revision == before.revision, "the gesture keeps its press-time revision")
    try f.check(f.page.interactionActive, "the page publishes the live interaction")
    try f.check(
        transaction.targets.count == scratch.targets && transaction.selectionDrag == scratch.selectionDrag,
        "gesture drags \(transaction.targets.count) targets (selection \(transaction.selectionDrag)), "
            + "expected \(scratch.targets) (selection \(scratch.selectionDrag))")
    let preview = f.page.previewPoints.sorted { ($0.tick, $0.value) < ($1.tick, $1.value) }
    try f.check(preview == scratch.preview, "preview is \(preview), expected \(scratch.preview)")
    try expectUnchanged(f, scratch.node)
    try f.check(f.page.handleEscape(), "Escape cancels the live drag")
    try expectSettled(f)
    try expectUnchanged(f, scratch.node)
}

// MARK: - Scenarios

@MainActor
func nodeScalingScenarios() -> [BenchScenario] {
    pointerCadenceScenarios() + repeatedPointerScenarios() + overwriteScenarios()
}

@MainActor
private func pointerCadenceScenarios() -> [BenchScenario] {
    var scenarios: [BenchScenario] = []

    // One grabbed node dragged across the lane onto its occupied neighbour.
    let occupied = NodeScalingScratch()
    scenarios.append(
        BenchScenario(
            name: "nodeScaling.pointerCadenceOccupied",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireNode(f, f.targetTick, f.highValue)
                occupied.modifiers = try pointerModifiers(f, ticks: [f.sourceTick, f.targetTick])
                occupied.node.baseline = captureBaseline(f)
                _ = try pressAndArm(f, occupied, tick: f.sourceTick, value: f.lowValue)
                occupied.path = linearPath(
                    f, from: pointer(f, f.sourceTick, f.lowValue),
                    to: pointer(f, f.targetTick, f.lowValue))
                occupied.preview = [AutomationLanePoint(tick: f.targetTick, value: f.lowValue)]
                occupied.targets = 1
                occupied.selectionDrag = false
            },
            run: { f in movePath(f, occupied) },
            validate: { f in try expectLiveDraftThenCancel(f, occupied) },
            operations: { f in f.samples }))

    // Anchor on a coarse-snap tick so press arbitration preserves the selected block.
    let group = NodeScalingScratch()
    scenarios.append(
        BenchScenario(
            name: "nodeScaling.pointerCadenceSelectedGroup",
            prepare: { f in
                let count = min(f.workload.selectedNodes, f.nodes)
                let step = f.targetTick - f.sourceTick
                let projection = f.page.makeProjection(facts: f.facts(), camera: f.page.liveCamera())
                guard
                    let grabbed = writtenPoints(f).first(where: {
                        $0.tick > 0 && projection.tick(atX: f.x($0.tick), fine: false) == $0.tick
                    })
                else { throw BenchFailure(description: "No written node on a coarse-snap tick at this zoom") }
                group.modifiers = try pointerModifiers(f, ticks: [grabbed.tick, grabbed.tick + step])
                let last = max(grabbed.tick, f.sourceTick + Tick(count - 1) * step)
                let first = last - Tick(count - 1) * step
                f.page.selectRange(from: first, to: last + 1, lanes: [f.parameter])
                try f.check(
                    f.page.coveredEventCount() == count,
                    "selection covers \(count) nodes, found \(f.page.coveredEventCount())")
                let base = captureBaseline(f)
                group.node.baseline = base
                let selected = base.points.filter { (first...last).contains($0.tick) }
                try f.check(selected.count == count, "baseline holds \(count) selected occurrences")
                let transaction = try pressAndArm(f, group, tick: grabbed.tick, value: grabbed.value)
                try f.check(
                    transaction.selectionDrag && transaction.targets.count == count,
                    "Press must preserve all \(count) selected targets")
                group.path = linearPath(
                    f, from: pointer(f, grabbed.tick, grabbed.value),
                    to: pointer(f, grabbed.tick + step, grabbed.value))
                group.preview = selected.map { AutomationLanePoint(tick: $0.tick + step, value: $0.value) }
                    .sorted { ($0.tick, $0.value) < ($1.tick, $1.value) }
                group.targets = count
                group.selectionDrag = true
            },
            run: { f in movePath(f, group) },
            validate: { f in try expectLiveDraftThenCancel(f, group) },
            operations: { f in f.samples }))

    return scenarios
}

@MainActor
private func repeatedPointerScenarios() -> [BenchScenario] {
    var scenarios: [BenchScenario] = []
    for jitter in [false, true] {
        // Pointer already resting on the occupied destination; timed moves repeat
        // its exact position, or jitter within the same tick/value cell.
        let scratch = NodeScalingScratch()
        scenarios.append(
            BenchScenario(
                name: jitter ? "nodeScaling.pointerRepeatSameCell" : "nodeScaling.pointerRepeatSamePosition",
                prepare: { f in
                    try requireNode(f, f.sourceTick, f.lowValue)
                    try requireNode(f, f.targetTick, f.highValue)
                    scratch.modifiers = try pointerModifiers(f, ticks: [f.sourceTick, f.targetTick])
                    scratch.node.baseline = captureBaseline(f)
                    _ = try pressAndArm(f, scratch, tick: f.sourceTick, value: f.lowValue)
                    let rest = pointer(f, f.targetTick, f.lowValue)
                    _ = f.page.pointerMove(x: rest.x, y: rest.y, buttons: left, modifiers: scratch.modifiers)
                    let destination = AutomationLanePoint(tick: f.targetTick, value: f.lowValue)
                    try f.check(
                        f.page.previewPoints == [destination],
                        "resting pointer previews \(destination), found \(f.page.previewPoints)")
                    scratch.path = try repeatedPath(f, scratch, rest: rest, jitter: jitter, expected: destination)
                    scratch.preview = [destination]
                    scratch.targets = 1
                    scratch.selectionDrag = false
                },
                run: { f in movePath(f, scratch) },
                validate: { f in try expectLiveDraftThenCancel(f, scratch) },
                operations: { f in f.samples }))
    }
    return scenarios
}

/// `samples` pointer positions at `rest`, or alternating sub-cell offsets around
/// it; every jittered position is checked to map onto `expected`.
@MainActor
private func repeatedPath(
    _ f: BenchFixture, _ scratch: NodeScalingScratch, rest: (x: Double, y: Double),
    jitter: Bool, expected: AutomationLanePoint
) throws -> [(x: Double, y: Double)] {
    guard jitter else { return Array(repeating: rest, count: f.samples) }
    guard let facts = f.page.frozen else { throw BenchFailure(description: "no frozen gesture facts") }
    let projection = f.page.makeProjection(facts: facts, camera: f.page.gestureCamera)
    let dx = min(0.25, abs(f.x(expected.tick + 1) - f.x(expected.tick)) * 0.25)
    let dy = min(0.25, abs(f.y(expected.value + 1) - f.y(expected.value)) * 0.25)
    let modifiers = AutomationQtModifier.automation(scratch.modifiers)
    let path = (0..<f.samples).map { sample -> (x: Double, y: Double) in
        let sign = sample.isMultiple(of: 2) ? 1.0 : -1.0
        return (rest.x + sign * dx, rest.y - sign * dy)
    }
    for point in path {
        let mapped = f.page.mappedPoint(
            x: point.x, y: point.y + armLift, facts: facts, modifiers: modifiers, projection: projection)
        try f.check(mapped == expected, "jittered pointer \(point) maps to \(mapped), not \(expected)")
    }
    return path
}

@MainActor
private func overwriteScenarios() -> [BenchScenario] {
    var scenarios: [BenchScenario] = []

    // Press and moves onto the occupied neighbour are untimed; only the release
    // that resolves and commits the overwrite is measured.
    let release = NodeScalingScratch()
    scenarios.append(
        BenchScenario(
            name: "nodeScaling.releaseOverwriteOccupied",
            prepare: { f in
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireNode(f, f.targetTick, f.highValue)
                release.modifiers = try pointerModifiers(f, ticks: [f.sourceTick, f.targetTick])
                let base = captureBaseline(f)
                release.node.baseline = base
                release.node.expected = edited(
                    base.points, removing: [f.sourceTick, f.targetTick],
                    adding: [NodeBenchPoint(tick: f.targetTick, value: f.lowValue)])
                _ = try pressAndArm(f, release, tick: f.sourceTick, value: f.lowValue)
                let end = pointer(f, f.targetTick, f.lowValue)
                release.path = linearPath(f, from: pointer(f, f.sourceTick, f.lowValue), to: end)
                movePath(f, release)
                let destination = AutomationLanePoint(tick: f.targetTick, value: f.lowValue)
                try f.check(
                    f.page.previewPoints == [destination],
                    "pre-release preview is \(destination), found \(f.page.previewPoints)")
                release.node.releaseX = end.x
                release.node.releaseY = end.y
            },
            run: { f in
                f.runResult = f.page.pointerRelease(
                    x: release.node.releaseX, y: release.node.releaseY, button: left,
                    modifiers: release.modifiers)
            },
            validate: { f in try expectCommitted(f, release.node) }))

    // `duplicateOccupants` same-tick CC occurrences staged at the destination;
    // moves and release are timed, and every staged occupant must be evicted.
    let dense = NodeScalingScratch()
    scenarios.append(
        BenchScenario(
            name: "nodeScaling.denseDuplicateDestinationOverwrite",
            applies: { f in
                guard case .controlChange(_, let controller) = f.parameter else { return false }
                return controller == TimeDefaults.ccPan || controller == TimeDefaults.ccVolume
            },
            prepare: { f in
                guard case .controlChange(_, let controller) = f.parameter else {
                    throw BenchFailure(description: "dense overwrite needs a CC lane")
                }
                let occupants = f.workload.duplicateOccupants
                try f.check(occupants >= 1, "--duplicate-occupants is at least 1")
                try requireNode(f, f.sourceTick, f.lowValue)
                try requireNode(f, f.targetTick, f.highValue)
                guard let chunk = f.facts().occupants(at: f.targetTick).first?.lanePoint?.chunk else {
                    throw BenchFailure(description: "destination occurrence has no raw lane point")
                }
                for extra in 1..<occupants {
                    f.document.insertRawEvent(
                        chunk: chunk,
                        event: .channel(
                            tick: f.targetTick, status: 0xB0, data0: controller,
                            data1: UInt8(f.highValue + 1 + extra % 8)))
                }
                let staged = f.facts().occupants(at: f.targetTick).count
                try f.check(staged == occupants, "\(occupants) same-tick occupants staged, found \(staged)")
                dense.modifiers = try pointerModifiers(f, ticks: [f.sourceTick, f.targetTick])
                let base = captureBaseline(f)
                dense.node.baseline = base
                dense.node.expected = edited(
                    base.points, removing: [f.sourceTick, f.targetTick],
                    adding: [NodeBenchPoint(tick: f.targetTick, value: f.lowValue)])
                _ = try pressAndArm(f, dense, tick: f.sourceTick, value: f.lowValue)
                let end = pointer(f, f.targetTick, f.lowValue)
                dense.path = linearPath(f, from: pointer(f, f.sourceTick, f.lowValue), to: end)
                dense.node.releaseX = end.x
                dense.node.releaseY = end.y
            },
            run: { f in
                movePath(f, dense)
                f.runResult = f.page.pointerRelease(
                    x: dense.node.releaseX, y: dense.node.releaseY, button: left,
                    modifiers: dense.modifiers)
            },
            validate: { f in
                try expectCommitted(f, dense.node)
                try f.check(
                    f.facts().occupants(at: f.targetTick).count == 1,
                    "one occurrence remains at the dense destination")
            }))

    return scenarios
}
