import Foundation
import PorydawCore

@testable import PorydawApp

// --edits prompt-accepted node value changes, undos and redos on one retained document per sample,
// after --history-depth untimed seeded edits. Each operation is one real mutation or history call.

/// One prompt edit: the node at `tick` goes from `current` to `value`.
private struct SustainedStep {
    let tick: Tick
    let current: Int
    let value: Int
    let draft: String
}

@MainActor
private final class SustainedBox {
    var steps: [SustainedStep] = []
    var model: [Tick: Int] = [:]
    /// Facts after seeding, before any batch edit: the state undo must restore.
    var baseline: NodeBenchBaseline?
    /// The lane after every batch step has applied.
    var expected: [NodeBenchPoint] = []
    var tipBytes: [UInt8]?
    var startRevision: UInt64 = 0
    var succeeded = 0

    func reset() {
        steps = []
        model = [:]
        baseline = nil
        expected = []
        tipBytes = nil
        startRevision = 0
        succeeded = 0
    }
}

/// low → mid → high → low: every step differs from the value it replaces.
@MainActor
private func sustainedNext(_ f: BenchFixture, _ value: Int) -> Int {
    value == f.lowValue ? midValue(f) : value == midValue(f) ? f.highValue : f.lowValue
}

/// Steps `first..<first+count` over nodes round-robin; `advance` false plans every
/// step against the unchanged model, as when each edit is undone before the next.
@MainActor
private func sustainedPlan(
    _ f: BenchFixture, _ box: SustainedBox, first: Int, count: Int, advance: Bool
) throws -> [SustainedStep] {
    try (first..<first + count).map { index in
        let tick = Tick((index % f.nodes + 1) * 24)
        guard let current = box.model[tick] else {
            throw BenchFailure(description: "node tick \(tick) has no single occurrence")
        }
        let value = sustainedNext(f, current)
        if advance { box.model[tick] = value }
        let displayed = AutomationParameterMetadata(parameter: f.parameter).prompt(storedValue: value).initialValue
        return SustainedStep(tick: tick, current: current, value: value, draft: String(displayed))
    }
}

/// The real form route: open the node prompt, type the stored value's display text, accept.
@MainActor
private func sustainedCommit(_ f: BenchFixture, _ step: SustainedStep) -> Bool {
    guard f.page.openPrompt(tick: step.tick, value: step.current) else { return false }
    f.page.updatePromptDraft(draft: step.draft)
    return f.page.acceptPromptDraft()
}

/// Commits every step untimed, requiring one revision and one history entry per step.
@MainActor
private func sustainedCommitAll(_ f: BenchFixture, _ steps: [SustainedStep], _ what: String) throws {
    let revision = f.document.revision
    let index = f.document.history.undoIndex
    let count = f.document.history.undoCount
    for (offset, step) in steps.enumerated() {
        try f.check(sustainedCommit(f, step), "\(what): edit \(offset) at tick \(step.tick) was refused")
    }
    try f.check(
        f.document.revision == revision + UInt64(steps.count)
            && f.document.history.undoIndex == index + steps.count
            && f.document.history.undoCount == count + steps.count && !f.document.history.canRedo,
        "\(what): \(steps.count) edits left revision \(f.document.revision), history \(f.document.history.undoIndex)/\(f.document.history.undoCount)"
    )
}

/// The lane with every modelled node tick at its model value.
@MainActor
private func sustainedLane(_ box: SustainedBox, _ base: [NodeBenchPoint]) -> [NodeBenchPoint] {
    base.map { NodeBenchPoint(tick: $0.tick, value: box.model[$0.tick] ?? $0.value) }.sorted()
}

/// Models the node ticks, seeds --history-depth edits, then plans --edits steps.
@MainActor
private func sustainedStage(_ f: BenchFixture, _ box: SustainedBox, advance: Bool) throws {
    box.reset()
    let depth = f.workload.historyDepth
    let edits = f.workload.editCount
    try f.check(depth >= 0 && edits >= 1, "history depth \(depth) and edit count \(edits)")
    let occupants = Dictionary(grouping: writtenPoints(f), by: \.tick)
    for node in 0..<min(f.nodes, depth + edits) {
        let tick = Tick((node + 1) * 24)
        guard let points = occupants[tick], points.count == 1 else {
            throw BenchFailure(description: "node tick \(tick) must hold exactly one occurrence")
        }
        box.model[tick] = points[0].value
    }
    let original = writtenPoints(f)
    let seeds = try sustainedPlan(f, box, first: 0, count: depth, advance: true)
    try sustainedCommitAll(f, seeds, "history seed")
    try f.check(writtenPoints(f) == sustainedLane(box, original), "the seeded lane differs from its model")
    let base = captureBaseline(f)
    try f.check(base.songBytes != nil, "the seeded song cannot be saved")
    box.baseline = base
    box.steps = try sustainedPlan(f, box, first: depth, count: edits, advance: advance)
    box.expected = sustainedLane(box, base.points)
}

/// Commits the planned batch untimed, then records the tip bytes.
@MainActor
private func sustainedStageTip(_ f: BenchFixture, _ box: SustainedBox) throws {
    try sustainedStage(f, box, advance: true)
    try sustainedCommitAll(f, box.steps, "prepared batch")
    try f.check(writtenPoints(f) == box.expected, "the prepared batch lane differs from its model")
    box.tipBytes = try f.document.captureSave().bytes
}

/// Exact outcome of `operations` timed calls ending at history `index`/`count`.
@MainActor
private func sustainedExpect(
    _ f: BenchFixture, _ box: SustainedBox, _ what: String,
    operations: Int, index: Int, count: Int, redoable: Bool,
    lane: [NodeBenchPoint], bytes: [UInt8]?
) throws {
    let history = f.document.history
    try f.check(box.succeeded == operations, "\(what): \(box.succeeded) of \(operations) operations succeeded")
    try f.check(
        f.document.revision == box.startRevision + UInt64(operations),
        "\(what): revision \(f.document.revision), expected \(box.startRevision) + \(operations)")
    try f.check(
        history.undoIndex == index && history.undoCount == count && history.canRedo == redoable,
        "\(what): history is \(history.undoIndex)/\(history.undoCount), expected \(index)/\(count)")
    let actual = writtenPoints(f)
    try f.check(actual == lane, "\(what): lane differs from its model (\(actual.count) vs \(lane.count) points)")
    if let bytes {
        try f.check(try f.document.captureSave().bytes == bytes, "\(what): song bytes differ from the capture")
    }
    try expectSettled(f)
}

@MainActor
func sustainedHistoryScenarios() -> [BenchScenario] {
    let commit = SustainedBox()
    let editUndoRedo = SustainedBox()
    let editUndo = SustainedBox()
    let undo = SustainedBox()
    let redo = SustainedBox()
    func start(_ f: BenchFixture, _ box: SustainedBox) { box.startRevision = f.document.revision }
    func base(_ box: SustainedBox) throws -> NodeBenchBaseline {
        guard let base = box.baseline else { throw BenchFailure(description: "no seeded baseline") }
        return base
    }
    return [
        BenchScenario(
            name: "sustained.prompt.commit",
            prepare: { f in
                try sustainedStage(f, commit, advance: true)
                start(f, commit)
            },
            run: { f in
                for step in commit.steps {
                    if sustainedCommit(f, step) { commit.succeeded += 1 }
                    drainNotifications()
                }
            },
            validate: { f in
                let b = try base(commit)
                try sustainedExpect(
                    f, commit, "sustained.prompt.commit", operations: commit.steps.count,
                    index: b.undoIndex + commit.steps.count, count: b.undoCount + commit.steps.count,
                    redoable: false, lane: commit.expected, bytes: nil)
            },
            operations: { f in f.workload.editCount }),
        BenchScenario(
            name: "sustained.cycle.editUndoRedo",
            prepare: { f in
                try sustainedStage(f, editUndoRedo, advance: true)
                start(f, editUndoRedo)
            },
            run: { f in
                for step in editUndoRedo.steps {
                    if sustainedCommit(f, step) { editUndoRedo.succeeded += 1 }
                    drainNotifications()
                    if try await f.session.undo() { editUndoRedo.succeeded += 1 }
                    drainNotifications()
                    if try await f.session.redo() { editUndoRedo.succeeded += 1 }
                    drainNotifications()
                }
            },
            validate: { f in
                let b = try base(editUndoRedo)
                let edits = editUndoRedo.steps.count
                try sustainedExpect(
                    f, editUndoRedo, "sustained.cycle.editUndoRedo", operations: 3 * edits,
                    index: b.undoIndex + edits, count: b.undoCount + edits,
                    redoable: false, lane: editUndoRedo.expected, bytes: nil)
            },
            operations: { f in 3 * f.workload.editCount }),
        BenchScenario(
            name: "sustained.cycle.editUndo",
            prepare: { f in
                try sustainedStage(f, editUndo, advance: false)
                start(f, editUndo)
            },
            run: { f in
                for step in editUndo.steps {
                    if sustainedCommit(f, step) { editUndo.succeeded += 1 }
                    drainNotifications()
                    if try await f.session.undo() { editUndo.succeeded += 1 }
                    drainNotifications()
                }
            },
            validate: { f in
                // Each edit discards the previous redo entry, leaving only the last one redoable.
                let b = try base(editUndo)
                try sustainedExpect(
                    f, editUndo, "sustained.cycle.editUndo", operations: 2 * editUndo.steps.count,
                    index: b.undoIndex, count: b.undoCount + 1,
                    redoable: true, lane: b.points, bytes: b.songBytes)
            },
            operations: { f in 2 * f.workload.editCount }),
        BenchScenario(
            name: "sustained.undo.retained",
            prepare: { f in
                try sustainedStageTip(f, undo)
                start(f, undo)
            },
            run: { f in
                for _ in undo.steps {
                    if try await f.session.undo() { undo.succeeded += 1 }
                    drainNotifications()
                }
            },
            validate: { f in
                let b = try base(undo)
                try sustainedExpect(
                    f, undo, "sustained.undo.retained", operations: undo.steps.count,
                    index: b.undoIndex, count: b.undoCount + undo.steps.count,
                    redoable: true, lane: b.points, bytes: b.songBytes)
                try f.check(
                    f.document.history.canUndo == (b.undoIndex > 0),
                    "sustained.undo.retained: seeded history is not undoable")
            },
            operations: { f in f.workload.editCount }),
        BenchScenario(
            name: "sustained.redo.retained",
            prepare: { f in
                try sustainedStageTip(f, redo)
                let b = try base(redo)
                for offset in redo.steps.indices {
                    try f.check(try await f.session.undo(), "prepared undo \(offset) reported no step")
                }
                try f.check(
                    writtenPoints(f) == b.points && (try f.document.captureSave().bytes) == b.songBytes,
                    "the prepared undos did not restore the seeded song")
                start(f, redo)
            },
            run: { f in
                for _ in redo.steps {
                    if try await f.session.redo() { redo.succeeded += 1 }
                    drainNotifications()
                }
            },
            validate: { f in
                let b = try base(redo)
                try sustainedExpect(
                    f, redo, "sustained.redo.retained", operations: redo.steps.count,
                    index: b.undoIndex + redo.steps.count, count: b.undoCount + redo.steps.count,
                    redoable: false, lane: redo.expected, bytes: redo.tipBytes)
            },
            operations: { f in f.workload.editCount }),
    ]
}
