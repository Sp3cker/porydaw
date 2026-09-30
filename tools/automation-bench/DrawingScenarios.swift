import Foundation
import PorydawCore

@testable import PorydawApp

// Pencil and sweep stroke scenarios through real pointer press/move/release, plus the scenario entry.
// Expected documents come from the page's retained draft resolved exactly as release does.

/// Advances the retained draft through the release's own `update`, then resolves it as `releasePlot` does.
@MainActor
func drawingReleasedEdit(
    _ f: BenchFixture, _ box: DrawingBox
) throws
    -> (edit: AutomationLaneEdit, sweep: AutomationSweepTransaction?)
{
    guard let stroke = box.s.stroke, let gesture = box.s.gesture, let facts = box.s.frozen else {
        throw BenchFailure(description: "no live drawing gesture was retained before release")
    }
    let projection = f.page.makeProjection(facts: facts, camera: box.s.camera ?? f.page.liveCamera())
    let modifiers = AutomationQtModifier.automation(stroke.modifiers)
    let release = stroke.release
    switch gesture {
    case .pencil(var transaction):
        f.page.update(
            pencil: &transaction, x: release.x, y: release.y, facts: facts,
            projection: projection, modifiers: modifiers)
        return (transaction.completion(), nil)
    case .sweep(var transaction):
        f.page.update(
            sweep: &transaction, x: release.x, y: release.y, modifiers: modifiers,
            facts: facts, projection: projection, activate: false)
        guard transaction.mode == .ramp || transaction.slopExceeded,
            let edit = transaction.finish(fine: modifiers.fine, projection: projection)
        else {
            throw BenchFailure(description: "the sweep never left its activation slop")
        }
        return (edit, transaction)
    default:
        throw BenchFailure(description: "the press started a node gesture instead of a drawing")
    }
}

/// One edit; lane equals the resolved edit applied to the baseline; the held value at the
/// edit's end matches the baseline's, so playback past the stroke is unchanged.
@MainActor
func drawingValidateStroke(
    _ f: BenchFixture, _ box: DrawingBox, _ what: String,
    exactRevision: Bool = true
) throws
    -> (edit: AutomationLaneEdit, sweep: AutomationSweepTransaction?)
{
    try f.check(f.runResult, "\(what): the release did not commit")
    try f.check(!f.page.hasGesture, "\(what): a gesture is still live after release")
    let resolved = try drawingReleasedEdit(f, box)
    let edit = resolved.edit
    try f.check(!edit.unchanged && !edit.points.isEmpty, "\(what): the draft resolved to no change")
    try f.check(
        edit.revision == box.s.revision, "\(what): the draft froze revision \(edit.revision), not \(box.s.revision)")
    try drawingExpectOneEdit(f, box, what, exactRevision: exactRevision)
    try drawingExpectLane(f, drawingApplying(edit, to: box.s.before), what)
    let metadata = AutomationParameterMetadata(parameter: f.parameter)
    try f.check(
        edit.points.allSatisfy { $0.value >= metadata.minimum && $0.value <= metadata.maximum },
        "\(what): a drawn value left the parameter's domain")
    try f.check(
        edit.tickEnd < f.session.timeline.lengthTicks,
        "\(what): the stroke's span \(edit.tickEnd) reached the song end")
    let after = drawingSources(f, f.parameter)
    let restored = drawingHeld(after, at: edit.tickEnd)
    let original = drawingHeld(box.s.before, at: edit.tickEnd)
    try f.check(
        restored == original,
        "\(what): held value at the tail \(edit.tickEnd) is \(restored.map { "\($0)" } ?? "none"), baseline holds \(original.map { "\($0)" } ?? "none")"
    )
    return resolved
}

/// The stroke's own points, without the restored tail at `tickEnd`.
func drawingBody(_ edit: AutomationLaneEdit) -> [AutomationLanePoint] {
    edit.points.filter { $0.tick < edit.tickEnd }
}

// MARK: - Scenarios

@MainActor
func drawingScenarios() -> [BenchScenario] {
    // Strokes need a node pair after emptyTick and at least one pointer sample.
    let atLeastFour: @MainActor (BenchFixture) -> Bool = { $0.nodes >= 4 && $0.samples >= 1 }
    return drawingStrokeScenarios(atLeastFour)
        + drawingRangeScenarios(atLeastFour)
        + drawingLaneMenuScenarios(atLeastFour)
        + drawingHistoryScenarios(atLeastFour)
        + drawingCancelScenarios(atLeastFour)
}

@MainActor
func drawingStrokeScenarios(_ applies: @escaping @MainActor (BenchFixture) -> Bool) -> [BenchScenario] {
    func stroke(
        _ name: String, pencil: Bool, modifiers: Int,
        shape: @escaping @MainActor (BenchFixture, AutomationLaneEdit, AutomationSweepTransaction?) throws -> Void
    )
        -> BenchScenario
    {
        let box = DrawingBox()
        return BenchScenario(
            name: name, applies: applies,
            prepare: { f in try drawingPrepareStroke(f, box, pencil: pencil, modifiers: modifiers) },
            run: { f in
                guard let stroke = box.s.stroke else { return }
                f.runResult = drawingPerform(f, stroke, stash: box)
            },
            validate: { f in
                let resolved = try drawingValidateStroke(f, box, name)
                try shape(f, resolved.edit, resolved.sweep)
            })
    }
    return [
        stroke("draw.pencil.snapped", pencil: true, modifiers: 0) { f, edit, _ in
            let body = drawingBody(edit)
            try f.check(body.count >= 2, "draw.pencil.snapped: the stroke wrote \(body.count) cell points")
            try f.check(
                zip(body, body.dropFirst()).allSatisfy { $0.tick < $1.tick },
                "draw.pencil.snapped: cell points are not strictly tick-ordered")
        },
        stroke("draw.pencil.freehand", pencil: true, modifiers: AutomationQtModifier.control) { f, edit, _ in
            try f.check(drawingBody(edit).count >= 2, "draw.pencil.freehand: the freehand stroke wrote too few points")
        },
        stroke("draw.pencil.locked", pencil: true, modifiers: AutomationQtModifier.shift) { f, edit, _ in
            let values = Set(drawingBody(edit).map(\.value))
            try f.check(
                values.count == 1,
                "draw.pencil.locked: a Shift-locked stroke wrote \(values.count) distinct values")
        },
        stroke("draw.sweep.drag", pencil: false, modifiers: 0) { f, edit, sweep in
            try f.check(sweep?.mode == .drag, "draw.sweep.drag: the press did not start a drag sweep")
            let count = drawingBody(edit).count
            try f.check(
                f.samples == 1 ? count == 1 : count >= 2,
                "draw.sweep.drag: \(f.samples) pointer samples wrote \(count) steps")
        },
        stroke("draw.sweep.shiftRamp", pencil: false, modifiers: AutomationQtModifier.shift) { f, edit, sweep in
            guard let sweep, sweep.mode == .ramp else {
                throw BenchFailure(description: "draw.sweep.shiftRamp: the Shift press did not start a ramp")
            }
            let body = drawingBody(edit)
            // Canonicalization elides a ramp step equal to its predecessor, so the
            // release endpoint is asserted as the value the lane holds there.
            try f.check(
                drawingHeld(drawingSources(f, f.parameter), at: sweep.current.tick) == sweep.current.value,
                "draw.sweep.shiftRamp: the lane does not hold the release endpoint \(sweep.current.tick):\(sweep.current.value)"
            )
            let rising = sweep.current.value >= sweep.anchor.value
            try f.check(
                zip(body, body.dropFirst()).allSatisfy { rising ? $0.value <= $1.value : $0.value >= $1.value },
                "draw.sweep.shiftRamp: the ramp is not monotone between its endpoints")
        },
    ]
}
