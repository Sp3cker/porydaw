import Foundation
@testable import PorydawApp
import PorydawCore

// Sweep-transaction scenarios paired with gestures.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationSweepSteppingAndRampFinish(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    // Division 24 makes one mid2agb clock a single tick: the legacy lattice of a
    // one-tick step per sample.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    let facts = fixture.facts(fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    report.expectEqual(expected: Tick(1), actual: projection.snapPolicy.clockTicks, cppID: drawerAutomationSweepStepsID,
                       what: "a 24-tick document's clock lattice steps one tick")

    var sweep = AutomationSweepTransaction(facts: facts, mode: .drag,
                                           mapped: AutomationLanePoint(tick: 0, value: 0),
                                           rawTick: 0, pressX: 0, pressY: 0)
    report.expect(!sweep.slopExceeded, cppID: drawerAutomationSweepStepsID,
                  message: "a drag sweep waits for the activation distance")
    _ = sweep.dragPosition(x: 12, y: 60, activate: true, activationDistance: 5)
    report.expect(sweep.slopExceeded, cppID: drawerAutomationSweepStepsID,
                  message: "a move past the activation distance arms the sweep")
    sweep.update(mapped: AutomationLanePoint(tick: 10, value: 100), first: 0, last: 10,
                 rawTick: 10, fine: true, projection: projection)
    report.expectEqual(expected: (0...10).map { "\($0):\($0 * 10)" }, actual: fixture.laneValues(sweep.points), cppID: drawerAutomationSweepStepsID,
                       what: "each stepped tick interpolates its value across the stroke")
    report.expectEqual(expected: 11, actual: sweep.points.count, cppID: drawerAutomationSweepStepsID,
                       what: "the sweep steps every lattice tick of the stroke")

    var update = AutomationSweepTransaction(facts: facts, mode: .drag,
                                            mapped: AutomationLanePoint(tick: 0, value: 0),
                                            rawTick: 0, pressX: 0, pressY: 0)
    update.update(mapped: AutomationLanePoint(tick: 5, value: 50), first: 0, last: 5,
                  rawTick: 5, fine: true, projection: projection)
    report.expectEqual(expected: "5:50", actual: "\(update.current.tick):\(update.current.value)", cppID: drawerAutomationSweepStepsID,
                       what: "the stroke's current point is its mapped one")
    report.expectEqual(expected: (0...5).map { "\($0):\($0 * 10)" }, actual: fixture.laneValues(update.points), cppID: drawerAutomationSweepStepsID,
                       what: "the second stroke interpolates across its own span")
    report.expectEqual(expected: 6, actual: update.points.count, cppID: drawerAutomationSweepStepsID,
                       what: "the second stroke has all six lattice points")

    var ramp = AutomationSweepTransaction(facts: facts, mode: .ramp,
                                          mapped: AutomationLanePoint(tick: 0, value: 0),
                                          rawTick: 0, pressX: 0, pressY: 0)
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 10, value: 100))
    let rampPoints = ramp.finishedPoints(fine: true, projection: projection)
    report.expectEqual(expected: 11, actual: rampPoints.count, cppID: drawerAutomationSweepStepsID,
                       what: "a ramp sweep fills every lattice tick between its endpoints")
    report.expectEqual(expected: ["0:0", "10:100"], actual: fixture.laneValues([rampPoints[0], rampPoints[10]]), cppID: drawerAutomationSweepStepsID,
                       what: "the ramp runs from its anchor value to its release value")
    report.expectEqual(expected: 50, actual: rampPoints[5].value, cppID: drawerAutomationSweepStepsID,
                       what: "the ramp's midpoint interpolates linearly")
    let edit = ramp.finish(fine: true, projection: projection)
    report.expect(edit != nil && !edit!.unchanged, cppID: drawerAutomationSweepStepsID,
                  message: "the completed ramp is a changed span replacement")
    report.expectEqual(expected: Tick(0), actual: edit?.tickBegin ?? 99, cppID: drawerAutomationSweepStepsID,
                       what: "the ramp replacement starts at its anchor")
    report.expectEqual(expected: Tick(11), actual: edit?.tickEnd ?? 0, cppID: drawerAutomationSweepStepsID,
                       what: "the ramp replacement closes one lattice step past its release")
    report.expectEqual(expected: "0:0", actual: "\(edit?.points.first?.tick ?? 0):\(edit?.points.first?.value ?? 0)",
                       cppID: drawerAutomationSweepStepsID, what: "the replacement keeps the ramp's first point")

    // The original completion case starts with no held point or engine default.
    let emptyParameter = AutomationParameter.controlChange(track: 0, controller: 11)
    let emptyFacts = fixture.facts(emptyParameter)
    report.expect(emptyFacts.displayPoints.isEmpty && emptyFacts.snapshot.leadInValue == nil,
                  cppID: drawerAutomationSweepStepsID, message: "the completion fixture is an empty lane")
    var emptyRamp = AutomationSweepTransaction(facts: emptyFacts, mode: .ramp,
                                               mapped: AutomationLanePoint(tick: 0, value: 0),
                                               rawTick: 0, pressX: 0, pressY: 0)
    emptyRamp.updateRamp(mapped: AutomationLanePoint(tick: 10, value: 100))
    guard let emptyCompletion = emptyRamp.finish(fine: true, projection: projection) else {
        report.fail(drawerAutomationSweepStepsID, "the empty-lane ramp produced no completion")
        return
    }
    report.expect(!emptyCompletion.unchanged, cppID: drawerAutomationSweepStepsID,
                  message: "the empty-lane completion changes the lane")
    report.expectEqual(expected: 11, actual: emptyCompletion.points.count, cppID: drawerAutomationSweepStepsID,
                       what: "the completion itself contains eleven points")
    report.expectEqual(expected: AutomationLanePoint(tick: 0, value: 0), actual: emptyCompletion.points.first,
                       cppID: drawerAutomationSweepStepsID, what: "the completion starts at the anchor")
    report.expectEqual(expected: AutomationLanePoint(tick: 10, value: 100), actual: emptyCompletion.points.last,
                       cppID: drawerAutomationSweepStepsID, what: "the empty lane adds no trailing held point")
}

@MainActor
func drawerAutomationSweepFinishRestoresTrailingHeldValue(_ report: CheckReport, suite: DocumentSession,
                                                  service: ProjectService) {
    // A flat 85 lane whose stroke releases at 25: the tail must re-anchor at 85
    // one lattice step past the release. Division 576 makes one clock 24 ticks,
    // which is this row's legacy lattice.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, division: 576,
                                    pan: [(0, 85)], config: SongConfig(), tailTick: 960)
    let facts = fixture.facts(fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    report.expectEqual(expected: Tick(24), actual: projection.snapPolicy.clockTicks, cppID: drawerAutomationSweepTailID,
                       what: "the lattice step of this document is 24 ticks")
    guard fixture.songEndTick > 168 else {
        report.fail(drawerAutomationSweepTailID,
                    "the fixture song ends at \(fixture.songEndTick), shorter than the seam")
        return
    }

    var drag = AutomationSweepTransaction(facts: facts, mode: .drag,
                                          mapped: AutomationLanePoint(tick: 48, value: 85),
                                          rawTick: 48, pressX: 0, pressY: 0)
    drag.update(mapped: AutomationLanePoint(tick: 144, value: 25), first: 48, last: 144,
                rawTick: 144, fine: true, projection: projection)
    let dragEdit = drag.finish(fine: true, projection: projection)
    report.expect(dragEdit != nil && !dragEdit!.unchanged, cppID: drawerAutomationSweepTailID,
                  message: "the drag over a flat lane is a changed span")
    report.expect(dragEdit?.points.contains { $0.tick == 144 && $0.value == 25 } == true,
                  cppID: drawerAutomationSweepTailID, message: "the stroke's release point is written")
    report.expectEqual(expected: "168:85", actual: "\(dragEdit?.points.last?.tick ?? 0):\(dragEdit?.points.last?.value ?? 0)",
                       cppID: drawerAutomationSweepTailID,
                       what: "the tail re-anchors the original held value one step past the release")
    report.expectEqual(expected: Tick(168), actual: dragEdit?.tickEnd ?? 0, cppID: drawerAutomationSweepTailID,
                       what: "the replacement's span covers the restored tail")

    var ramp = AutomationSweepTransaction(facts: facts, mode: .ramp,
                                          mapped: AutomationLanePoint(tick: 48, value: 85),
                                          rawTick: 48, pressX: 0, pressY: 0)
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 144, value: 25))
    let rampEdit = ramp.finish(fine: true, projection: projection)
    report.expect(rampEdit != nil && !rampEdit!.unchanged, cppID: drawerAutomationSweepTailID,
                  message: "the ramp over a flat lane is a changed span")
    report.expect(rampEdit?.points.contains { $0.tick == 144 && $0.value == 25 } == true,
                  cppID: drawerAutomationSweepTailID, message: "the ramp's release point is written")
    report.expectEqual(expected: "168:85", actual: "\(rampEdit?.points.last?.tick ?? 0):\(rampEdit?.points.last?.value ?? 0)",
                       cppID: drawerAutomationSweepTailID,
                       what: "the ramp's tail re-anchors the original held value too")

    // A stroke that ends at the song's end has no tail to restore.
    let endFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(0, 85)],
                                       tailTick: 384)
    let endProjection = AutomationProjection(
        camera: endFixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: endFixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: endFixture.document,
                                         timeline: endFixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: endFixture.songEndTick)
    var endSweep = AutomationSweepTransaction(
        facts: endFixture.facts(endFixture.panLane), mode: .drag,
        mapped: AutomationLanePoint(tick: 0, value: 85), rawTick: 0, pressX: 0, pressY: 0)
    let endTick = endFixture.songEndTick
    endSweep.update(mapped: AutomationLanePoint(tick: endTick, value: 25), first: 0,
                    last: endTick, rawTick: Double(endTick), fine: true, projection: endProjection)
    report.expectEqual(expected: endTick, actual: endSweep.points.last?.tick ?? 0, cppID: drawerAutomationSweepTailID,
                       what: "a stroke that ends at the song's end steps to the song's end")
    let endEdit = endSweep.finish(fine: true, projection: endProjection)
    report.expect(endEdit?.points.allSatisfy { $0.tick <= endTick } == true, cppID: drawerAutomationSweepTailID,
                  message: "a stroke that ends at the song's end restores no tail")

    // The released sweep lands in the document exactly once, with its tail, and
    // the draft never wrote anything before the release.
    let committed = drawerAutomationAutomationFixture(suite: suite, service: service, division: 576,
                                      modulation: [(0, 85)], config: SongConfig(), tailTick: 960)
    let committedFacts = committed.facts(committed.modulationLane)
    let committedProjection = AutomationProjection(
        camera: committed.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: committed.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: committed.document,
                                         timeline: committed.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: committed.songEndTick)
    var live = AutomationSweepTransaction(facts: committedFacts, mode: .drag,
                                          mapped: AutomationLanePoint(tick: 48, value: 85),
                                          rawTick: 48, pressX: 0, pressY: 0)
    live.update(mapped: AutomationLanePoint(tick: 144, value: 25), first: 48, last: 144,
                rawTick: 144, fine: true, projection: committedProjection)
    let beforeRelease = committed.snapshot
    report.expectEqual(expected: ["48:85", "72:70", "96:55", "120:40", "144:25"], actual: committed.laneValues(live.preview), cppID: drawerAutomationSweepTailID,
                       what: "the sweep preview is the stepped draft alone")
    report.expectEqual(expected: beforeRelease, actual: committed.snapshot, cppID: drawerAutomationSweepTailID,
                       what: "the draft writes nothing before the release")
    guard let committedEdit = live.finish(fine: true, projection: committedProjection) else {
        report.fail(drawerAutomationSweepTailID, "the released sweep produced no edit")
        return
    }
    report.expect(AutomationCommit.apply(committedEdit, in: committed.document), cppID: drawerAutomationSweepTailID,
                  message: "the released sweep commits once")
    report.expectEqual(expected: ["0:85", "72:70", "96:55", "120:40", "144:25", "168:85"], actual: committed.values(committed.modulationLane), cppID: drawerAutomationSweepTailID,
                       what: "the committed lane holds the stroke and its restored tail")
    report.expectEqual(expected: beforeRelease.revision + 1, actual: committed.document.revision, cppID: drawerAutomationSweepTailID,
                       what: "one released sweep is one revision")
    report.expect(committed.undo(), cppID: drawerAutomationSweepTailID, message: "the sweep is undoable")
    report.expectEqual(expected: ["0:85"], actual: committed.values(committed.modulationLane), cppID: drawerAutomationSweepTailID,
                       what: "one undo restores the flat lane")
    report.expect(!committed.document.history.canUndo, cppID: drawerAutomationSweepTailID,
                  message: "the released sweep recorded exactly one history entry")
}
