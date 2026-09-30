import Foundation
import PorydawAppCommands
import PorydawCore

@testable import PorydawApp

// Undo/redo of prepared strokes and range deletes, a timed edit+undo+redo cycle, Escape
// cancellation of live drawings, and stale-revision rejection of releases and frozen commits.

@MainActor
func drawingHistoryScenarios(_ applies: @escaping @MainActor (BenchFixture) -> Bool) -> [BenchScenario] {
    /// Commits one snapped pencil stroke untimed and records the lane it left.
    func preparePencil(_ f: BenchFixture, _ box: DrawingBox) throws {
        try drawingPrepareStroke(f, box, pencil: true, modifiers: 0)
        guard let stroke = box.s.stroke else { return }
        try f.check(drawingPerform(f, stroke, stash: nil), "the prepared pencil stroke did not commit")
        try drawingExpectOneEdit(f, box, "prepared pencil stroke")
        box.s.after = drawingSources(f, f.parameter)
        try f.check(box.s.after != box.s.before, "the prepared pencil stroke changed nothing")
    }
    /// Commits one multi-lane range delete untimed through the window command.
    func prepareDelete(_ f: BenchFixture, _ box: DrawingBox) throws {
        box.reset()
        try drawingSeedCompanion(f, box)
        guard let companion = box.s.companion else { throw BenchFailure(description: "no companion lane") }
        f.page.selectRange(from: f.targetTick, to: Tick(f.nodes * 24), lanes: [f.parameter, companion])
        drawingCapture(f, box)
        try f.check(f.page.consumeSelectionCommand(command: .delete), "the prepared range delete was refused")
        try drawingExpectOneEdit(f, box, "prepared range delete")
        box.s.after = drawingSources(f, f.parameter)
        box.s.companionAfter = drawingSources(f, companion)
        try f.check(
            box.s.after != box.s.before && box.s.companionAfter != box.s.companionBefore,
            "the prepared range delete left a lane unchanged")
    }
    func expectUndone(_ f: BenchFixture, _ box: DrawingBox, _ what: String) throws {
        try f.check(f.runResult, "\(what): undo reported no step")
        try f.check(
            f.document.history.undoIndex == box.s.undoIndex
                && f.document.history.undoCount == box.s.undoCount + 1
                && f.document.history.canRedo,
            "\(what): history is \(f.document.history.undoIndex)/\(f.document.history.undoCount)")
        try drawingExpectLane(f, box.s.before, what)
        try drawingExpectCompanion(f, box, box.s.companionBefore, what)
    }
    func expectRedone(_ f: BenchFixture, _ box: DrawingBox, _ what: String) throws {
        try f.check(f.runResult, "\(what): redo reported no step")
        try f.check(
            f.document.history.undoIndex == box.s.undoIndex + 1
                && f.document.history.undoCount == box.s.undoCount + 1
                && !f.document.history.canRedo,
            "\(what): history is \(f.document.history.undoIndex)/\(f.document.history.undoCount)")
        try drawingExpectLane(f, box.s.after, what)
        try drawingExpectCompanion(f, box, box.s.companionAfter, what)
    }
    func undoPrepared(_ f: BenchFixture, _ box: DrawingBox) async throws {
        let undone = try await f.session.undo()
        try f.check(undone, "the prepared undo reported no step")
        try f.check(
            drawingOrdered(drawingSources(f, f.parameter)) == drawingOrdered(box.s.before),
            "the prepared undo did not restore the lane")
    }

    let undoPencil = DrawingBox()
    let redoPencil = DrawingBox()
    let undoDelete = DrawingBox()
    let redoDelete = DrawingBox()
    let cycle = DrawingBox()
    return [
        BenchScenario(
            name: "history.undo.pencil", applies: applies,
            prepare: { f in try preparePencil(f, undoPencil) },
            run: { f in f.runResult = try await f.session.undo() },
            validate: { f in try expectUndone(f, undoPencil, "history.undo.pencil") }),
        BenchScenario(
            name: "history.redo.pencil", applies: applies,
            prepare: { f in
                try preparePencil(f, redoPencil)
                try await undoPrepared(f, redoPencil)
            },
            run: { f in f.runResult = try await f.session.redo() },
            validate: { f in try expectRedone(f, redoPencil, "history.redo.pencil") }),
        BenchScenario(
            name: "history.undo.rangeDelete.multiLane", applies: applies,
            prepare: { f in try prepareDelete(f, undoDelete) },
            run: { f in f.runResult = try await f.session.undo() },
            validate: { f in try expectUndone(f, undoDelete, "history.undo.rangeDelete.multiLane") }),
        BenchScenario(
            name: "history.redo.rangeDelete.multiLane", applies: applies,
            prepare: { f in
                try prepareDelete(f, redoDelete)
                try await undoPrepared(f, redoDelete)
                try drawingExpectCompanion(f, redoDelete, redoDelete.s.companionBefore, "prepared undo")
            },
            run: { f in f.runResult = try await f.session.redo() },
            validate: { f in try expectRedone(f, redoDelete, "history.redo.rangeDelete.multiLane") }),
        BenchScenario(
            name: "history.cycle.pencil", applies: applies,
            prepare: { f in try drawingPrepareStroke(f, cycle, pencil: true, modifiers: 0) },
            run: { f in
                guard let stroke = cycle.s.stroke else { return }
                let committed = drawingPerform(f, stroke, stash: cycle)
                let undone = try await f.session.undo()
                let redone = try await f.session.redo()
                f.runResult = committed && undone && redone
            },
            validate: { f in
                _ = try drawingValidateStroke(f, cycle, "history.cycle.pencil", exactRevision: false)
            }),
    ]
}

@MainActor
func drawingCancelScenarios(_ applies: @escaping @MainActor (BenchFixture) -> Bool) -> [BenchScenario] {
    /// A full sampled stroke across the node span, left live and unreleased.
    func prepareLive(_ f: BenchFixture, _ box: DrawingBox, pencil: Bool) throws {
        try drawingPrepareStroke(f, box, pencil: pencil, modifiers: 0)
        guard let stroke = box.s.stroke else { return }
        try f.check(drawingPress(f, stroke), "the drawing press was refused")
        try f.check(
            pencil ? f.page.isPainting : f.page.isSweeping,
            "the press did not start a \(pencil ? "pencil stroke" : "sweep")")
        try drawingExpectUntouched(f, box, "live drawing preview")
    }
    func cancel(_ name: String, pencil: Bool) -> BenchScenario {
        let box = DrawingBox()
        return BenchScenario(
            name: name, applies: applies,
            prepare: { f in try prepareLive(f, box, pencil: pencil) },
            run: { f in f.runResult = f.page.handleEscape() },
            validate: { f in
                try f.check(f.runResult, "\(name): Escape was not consumed")
                try f.check(
                    !f.page.hasGesture && !f.page.pointerGestureActive,
                    "\(name): the drawing survived Escape")
                try drawingExpectUntouched(f, box, name)
            })
    }

    let staleRelease = DrawingBox()
    let staleCommit = DrawingBox()
    /// The out-of-gesture write: one companion-lane point, which moves the
    /// document revision without touching the tested lane.
    func writeBehind(_ f: BenchFixture, _ box: DrawingBox) throws {
        let companion = drawingCompanion(of: f.parameter)
        guard let track = companion.track, let lane = companion.lane else {
            throw BenchFailure(description: "the companion lane has no document lane")
        }
        let revision = f.document.revision
        f.document.writeLane(
            track: track, lane: lane, from: 12, through: 12,
            points: [LaneWrite(tick: 12, value: 64)])
        try f.check(f.document.revision != revision, "the out-of-gesture write changed no revision")
        box.s.companion = companion
        drawingCapture(f, box)
    }
    return [
        cancel("cancel.pencil", pencil: true),
        cancel("cancel.sweep", pencil: false),
        BenchScenario(
            name: "stale.gestureRelease", applies: applies,
            prepare: { f in
                try drawingPrepareStroke(f, staleRelease, pencil: true, modifiers: 0)
                guard let stroke = staleRelease.s.stroke else { return }
                try f.check(drawingPress(f, stroke) && f.page.isPainting, "the pencil stroke did not start")
                try writeBehind(f, staleRelease)
            },
            run: { f in
                guard let stroke = staleRelease.s.stroke else { return }
                f.runResult = drawingRelease(f, stroke)
            },
            validate: { f in
                try f.check(!f.runResult, "stale.gestureRelease: a stale stroke committed")
                try f.check(!f.page.hasGesture, "stale.gestureRelease: the stale stroke is still live")
                try drawingExpectUntouched(f, staleRelease, "stale.gestureRelease")
            }),
        BenchScenario(
            name: "stale.frozenCommit", applies: applies,
            prepare: { f in
                staleCommit.reset()
                let facts = f.facts()
                // Any in-domain value distinct from both dataset values makes the replacement a change.
                let value = AutomationParameterMetadata(parameter: f.parameter).clamp(max(f.lowValue, f.highValue) + 1)
                let points = (1..<f.nodes).map { AutomationLanePoint(tick: Tick($0 * 24 + 12), value: value) }
                let edit = AutomationLaneReplacement.heldSpan(
                    facts.freeze(), begin: f.emptyTick,
                    end: Tick(f.nodes * 24), points: points)
                try f.check(
                    !edit.unchanged && edit.revision == f.document.revision,
                    "the frozen replacement is not a live change")
                staleCommit.s.edit = edit
                try writeBehind(f, staleCommit)
            },
            run: { f in
                guard let edit = staleCommit.s.edit else { return }
                f.runResult = AutomationCommit.apply(edit, in: f.document)
            },
            validate: { f in
                try f.check(!f.runResult, "stale.frozenCommit: a stale frozen edit committed")
                try drawingExpectUntouched(f, staleCommit, "stale.frozenCommit")
            }),
    ]
}

@MainActor
func nodeHistoryScenarios() -> [BenchScenario] {
    func stage(_ f: BenchFixture, _ scratch: NodeBenchScratch) {
        let base = captureBaseline(f)
        scratch.baseline = base
        scratch.expected = edited(
            base.points, removing: [f.sourceTick, f.targetTick],
            adding: [NodeBenchPoint(tick: f.targetTick, value: f.lowValue)])
    }
    func overwrite(_ f: BenchFixture) {
        f.drag(from: f.sourceTick, value: f.lowValue, to: f.targetTick, targetValue: f.lowValue)
    }
    func expectHistory(_ f: BenchFixture, _ scratch: NodeBenchScratch, undone: Bool) throws {
        guard let base = scratch.baseline else { throw BenchFailure(description: "Missing history baseline") }
        try f.check(f.runResult, "History operation completed")
        try f.check(writtenPoints(f) == (undone ? base.points : scratch.expected), "Exact node overwrite/history lane")
        try f.check(
            f.document.history.undoCount == base.undoCount + 1
                && f.document.history.undoIndex == base.undoIndex + (undone ? 0 : 1)
                && f.document.history.canRedo == undone, "One reversible node edit")
        if undone {
            guard let bytes = base.songBytes else { throw BenchFailure(description: "Missing saved baseline") }
            try f.check(try f.document.captureSave().bytes == bytes, "Undo restores complete song bytes")
        }
    }
    let undo = NodeBenchScratch()
    let redo = NodeBenchScratch()
    let cycle = NodeBenchScratch()
    return [
        BenchScenario(
            name: "history.undo.nodeOverwrite",
            prepare: { f in
                stage(f, undo)
                overwrite(f)
                try expectCommitted(f, undo)
            }, run: { f in f.runResult = try await f.session.undo() },
            validate: { f in try expectHistory(f, undo, undone: true) }),
        BenchScenario(
            name: "history.redo.nodeOverwrite",
            prepare: { f in
                stage(f, redo)
                overwrite(f)
                try expectCommitted(f, redo)
                f.runResult = try await f.session.undo()
                try expectHistory(f, redo, undone: true)
            }, run: { f in f.runResult = try await f.session.redo() },
            validate: { f in try expectHistory(f, redo, undone: false) }),
        BenchScenario(
            name: "history.cycle.nodeOverwrite", prepare: { f in stage(f, cycle) },
            run: { f in
                overwrite(f)
                let committed = f.runResult
                let undone = try await f.session.undo()
                let redone = try await f.session.redo()
                f.runResult = committed && undone && redone
            }, validate: { f in try expectHistory(f, cycle, undone: false) }),
    ]
}
