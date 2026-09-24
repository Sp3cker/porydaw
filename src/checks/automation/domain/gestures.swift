import Foundation
@testable import PorydawApp
import PorydawCore

// Existing scenarios paired with gestures.cpp.
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
    report.expectEqual(Tick(1), projection.snapPolicy.clockTicks, cppID: drawerAutomationSweepStepsID,
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
    report.expectEqual((0...10).map { "\($0):\($0 * 10)" },
                       fixture.laneValues(sweep.points), cppID: drawerAutomationSweepStepsID,
                       what: "each stepped tick interpolates its value across the stroke")
    report.expectEqual(11, sweep.points.count, cppID: drawerAutomationSweepStepsID,
                       what: "the sweep steps every lattice tick of the stroke")

    var update = AutomationSweepTransaction(facts: facts, mode: .drag,
                                            mapped: AutomationLanePoint(tick: 0, value: 0),
                                            rawTick: 0, pressX: 0, pressY: 0)
    update.update(mapped: AutomationLanePoint(tick: 5, value: 50), first: 0, last: 5,
                  rawTick: 5, fine: true, projection: projection)
    report.expectEqual("5:50", "\(update.current.tick):\(update.current.value)", cppID: drawerAutomationSweepStepsID,
                       what: "the stroke's current point is its mapped one")
    report.expectEqual((0...5).map { "\($0):\($0 * 10)" },
                       fixture.laneValues(update.points), cppID: drawerAutomationSweepStepsID,
                       what: "the second stroke interpolates across its own span")
    report.expectEqual(6, update.points.count, cppID: drawerAutomationSweepStepsID,
                       what: "the second stroke has all six lattice points")

    var ramp = AutomationSweepTransaction(facts: facts, mode: .ramp,
                                          mapped: AutomationLanePoint(tick: 0, value: 0),
                                          rawTick: 0, pressX: 0, pressY: 0)
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 10, value: 100))
    let rampPoints = ramp.finishedPoints(fine: true, projection: projection)
    report.expectEqual(11, rampPoints.count, cppID: drawerAutomationSweepStepsID,
                       what: "a ramp sweep fills every lattice tick between its endpoints")
    report.expectEqual(["0:0", "10:100"],
                       fixture.laneValues([rampPoints[0], rampPoints[10]]), cppID: drawerAutomationSweepStepsID,
                       what: "the ramp runs from its anchor value to its release value")
    report.expectEqual(50, rampPoints[5].value, cppID: drawerAutomationSweepStepsID,
                       what: "the ramp's midpoint interpolates linearly")
    let edit = ramp.finish(fine: true, projection: projection)
    report.expect(edit != nil && !edit!.unchanged, cppID: drawerAutomationSweepStepsID,
                  message: "the completed ramp is a changed span replacement")
    report.expectEqual(Tick(0), edit?.tickBegin ?? 99, cppID: drawerAutomationSweepStepsID,
                       what: "the ramp replacement starts at its anchor")
    report.expectEqual(Tick(11), edit?.tickEnd ?? 0, cppID: drawerAutomationSweepStepsID,
                       what: "the ramp replacement closes one lattice step past its release")
    report.expectEqual("0:0", "\(edit?.points.first?.tick ?? 0):\(edit?.points.first?.value ?? 0)",
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
    report.expectEqual(11, emptyCompletion.points.count, cppID: drawerAutomationSweepStepsID,
                       what: "the completion itself contains eleven points")
    report.expectEqual(AutomationLanePoint(tick: 0, value: 0), emptyCompletion.points.first,
                       cppID: drawerAutomationSweepStepsID, what: "the completion starts at the anchor")
    report.expectEqual(AutomationLanePoint(tick: 10, value: 100), emptyCompletion.points.last,
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
    report.expectEqual(Tick(24), projection.snapPolicy.clockTicks, cppID: drawerAutomationSweepTailID,
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
    report.expectEqual("168:85",
                       "\(dragEdit?.points.last?.tick ?? 0):\(dragEdit?.points.last?.value ?? 0)",
                       cppID: drawerAutomationSweepTailID,
                       what: "the tail re-anchors the original held value one step past the release")
    report.expectEqual(Tick(168), dragEdit?.tickEnd ?? 0, cppID: drawerAutomationSweepTailID,
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
    report.expectEqual("168:85",
                       "\(rampEdit?.points.last?.tick ?? 0):\(rampEdit?.points.last?.value ?? 0)",
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
    report.expectEqual(endTick, endSweep.points.last?.tick ?? 0, cppID: drawerAutomationSweepTailID,
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
    report.expectEqual(["48:85", "72:70", "96:55", "120:40", "144:25"],
                       committed.laneValues(live.preview), cppID: drawerAutomationSweepTailID,
                       what: "the sweep preview is the stepped draft alone")
    report.expectEqual(beforeRelease, committed.snapshot, cppID: drawerAutomationSweepTailID,
                       what: "the draft writes nothing before the release")
    guard let committedEdit = live.finish(fine: true, projection: committedProjection) else {
        report.fail(drawerAutomationSweepTailID, "the released sweep produced no edit")
        return
    }
    report.expect(AutomationCommit.apply(committedEdit, in: committed.document), cppID: drawerAutomationSweepTailID,
                  message: "the released sweep commits once")
    report.expectEqual(["0:85", "72:70", "96:55", "120:40", "144:25", "168:85"],
                       committed.values(committed.modulationLane), cppID: drawerAutomationSweepTailID,
                       what: "the committed lane holds the stroke and its restored tail")
    report.expectEqual(beforeRelease.revision + 1, committed.document.revision, cppID: drawerAutomationSweepTailID,
                       what: "one released sweep is one revision")
    report.expect(committed.undo(), cppID: drawerAutomationSweepTailID, message: "the sweep is undoable")
    report.expectEqual(["0:85"], committed.values(committed.modulationLane), cppID: drawerAutomationSweepTailID,
                       what: "one undo restores the flat lane")
    report.expect(!committed.document.history.canUndo, cppID: drawerAutomationSweepTailID,
                  message: "the released sweep recorded exactly one history entry")
}

@MainActor
func drawerAutomationPanNeutralSnap(_ report: CheckReport, suite: DocumentSession,
                            service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 72)])
    let metadata = AutomationParameterMetadata(parameter: fixture.panLane)
    report.expectEqual(64, metadata.neutral, cppID: drawerAutomationNeutralSnapID,
                       what: "Pan's neutral is 64, the centered domain's midpoint")
    let radius = fixture.page.geometry.neutralSnapRadius
    let height = 120.0
    let threshold = Int(Double(metadata.maximum - metadata.minimum) * radius / height)
    report.expect(threshold > 0, cppID: drawerAutomationNeutralSnapID,
                  message: "the neutral snap radius covers more than one value step")
    let near = 64 + max(1, threshold - 1)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: height, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    let yNear = (0..<Int(height)).first { y in
        let value = projection.value(atY: Double(y), metadata: metadata)
        return value != 64 && abs(value - 64) <= threshold
    }
    guard let yNear else {
        report.fail(drawerAutomationNeutralSnapID, "the plot contains no pixel inside the neutral snap radius")
        return
    }
    let valueNear = projection.value(atY: Double(yNear), metadata: metadata)
    let facts = fixture.facts(fixture.panLane)
    let plain = fixture.page.mappedPoint(x: projection.x(100), y: Double(yNear), facts: facts,
                                         modifiers: AutomationModifiers(fine: true), projection: projection)
    report.expectEqual(Tick(100), plain.tick, cppID: drawerAutomationNeutralSnapID,
                       what: "the unsnapped value mapping preserves tick 100")
    report.expectEqual(valueNear, plain.value, cppID: drawerAutomationNeutralSnapID,
                       what: "the unsnapped value mapping keeps the near-neutral pixel value")
    let snapped = fixture.page.mappedPoint(x: projection.x(100), y: Double(yNear), facts: facts,
                                           modifiers: AutomationModifiers(fine: true, snapValue: true),
                                           projection: projection)
    report.expectEqual(Tick(100), snapped.tick, cppID: drawerAutomationNeutralSnapID,
                       what: "neutral snapping preserves tick 100")
    report.expectEqual(64, snapped.value, cppID: drawerAutomationNeutralSnapID,
                       what: "the near-neutral pixel snaps to 64")
    let exact = fixture.page.mappedPoint(x: projection.x(200), y: projection.y(64, metadata: metadata),
                                         facts: facts,
                                         modifiers: AutomationModifiers(fine: true, snapValue: true),
                                         projection: projection)
    report.expectEqual(AutomationLanePoint(tick: 200, value: 64), exact,
                       cppID: drawerAutomationNeutralSnapID,
                       what: "the exact neutral maps to the original tick-200 point")
    report.expectEqual(near, metadata.snappedValue(near, snapValue: false, plotHeight: height,
                                                   neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID,
                       what: "an unsnapped drag keeps the value under the pointer")
    report.expectEqual(64, metadata.snappedValue(near, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID, what: "a snapped drag lands exactly on the neutral")
    report.expectEqual(64, metadata.snappedValue(64, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID, what: "a pointer on the neutral stays neutral")
    let outside = 64 + threshold + 5
    report.expectEqual(outside, metadata.snappedValue(outside, snapValue: true, plotHeight: height,
                                                      neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID,
                       what: "a value outside the radius keeps its own value")
    report.expectEqual(19, metadata.snappedValue(19, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID,
                       what: "a snap only ever moves a value onto the neutral")
    let volume = AutomationParameterMetadata(parameter: fixture.volumeLane)
    report.expectEqual(60, volume.snappedValue(60, snapValue: true, plotHeight: height,
                                               neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID,
                       what: "a parameter with no neutral keeps the dragged value")

    // Through the page's own pointer mapping: a snapped drag on a node holding
    // 72 writes 64 at the node's own tick, and the preview never moved the tick.
    fixture.activate(fixture.panLane)
    let nodeX = fixture.x(24)
    let nodeY = fixture.y(fixture.panLane, 72)
    let modifiers = AutomationModifiers(snapValue: true)
    report.expect(fixture.page.pointerPress(x: nodeX, y: nodeY, surface: 1, button: 1, modifiers: drawerAutomationQtModifiers(modifiers)),
                  cppID: drawerAutomationNeutralSnapID, message: "a snapped press grabs the node under the pointer")
    _ = fixture.page.pointerMove(x: nodeX + 12, y: nodeY, buttons: 1, modifiers: drawerAutomationQtModifiers(modifiers))
    report.expectEqual(Tick(24), fixture.page.previewPoints.first?.tick ?? 0, cppID: drawerAutomationNeutralSnapID,
                       what: "the armed preview keeps the node's own tick")
    _ = fixture.page.pointerMove(x: nodeX + 12, y: nodeY, buttons: 1, modifiers: drawerAutomationQtModifiers(modifiers))
    report.expectEqual(64, fixture.page.previewPoints.first?.value ?? 0, cppID: drawerAutomationNeutralSnapID,
                       what: "the preview publishes the snapped neutral")
    _ = fixture.page.pointerRelease(x: nodeX + 12, y: nodeY, button: 1, modifiers: drawerAutomationQtModifiers(modifiers))
    report.expectEqual(["24:64"], fixture.values(fixture.panLane), cppID: drawerAutomationNeutralSnapID,
                       what: "the snapped release writes the neutral at the node's own tick")
}

@MainActor
func drawerAutomationNodeDragAndPhantomOutcomes(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 60), (48, 80), (120, 40)])
    let facts = fixture.facts(fixture.panLane)
    let sources = facts.snapshot.sources
    report.expectEqual(3, sources.count, cppID: drawerAutomationNodeDragID,
                       what: "the fixture offers three draggable nodes")

    // An empty gesture finishes as a no-op.
    let empty = AutomationNodeDragTransaction(facts: facts, targets: [], grabbedPoint: 0,
                                              selectionDrag: false, press: (100, 100),
                                              deleteOnStationary: true)
    report.expectEqual(AutomationPointRelease.noOp, empty.finish().release, cppID: drawerAutomationNodeDragID,
                       what: "a gesture with no target finishes as a no-op")
    report.expect(!empty.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "an empty gesture reports no change")

    // A Shift-held stationary release is a no-op; a plain one deletes.
    let shiftPress = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                          press: (100, 100),
                                                          deleteOnStationary: false)
    report.expectEqual(AutomationPointRelease.noOp, shiftPress.finish().release, cppID: drawerAutomationNodeDragID,
                       what: "a Shift-held stationary release is a no-op")
    report.expect(!shiftPress.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "a Shift-held stationary release changes nothing")
    var plainPress = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                          press: (100, 100),
                                                          deleteOnStationary: true)
    report.expectEqual(AutomationPointRelease.stationaryDelete, plainPress.finish().release,
                       cppID: drawerAutomationNodeDragID, what: "a stationary release without Shift deletes")
    report.expect(!plainPress.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "the stationary delete reports no move")

    // Past the slop without moving: a move that changed nothing.
    _ = plainPress.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    report.expectEqual(AutomationPointRelease.move, plainPress.finish().release, cppID: drawerAutomationNodeDragID,
                       what: "a released stroke past the slop is a move")
    report.expect(!plainPress.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "a stroke that never moved the node changes nothing")

    // The same gesture with a moved node: one move with the grabbed delta.
    _ = plainPress.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 130,
                                                     effectiveY: 100, axisLock: .none),
                          mapped: AutomationLanePoint(tick: 30, value: 80))
    let moved = plainPress.finish()
    report.expectEqual(AutomationPointRelease.move, moved.release, cppID: drawerAutomationNodeDragID,
                       what: "the moved gesture is still a move")
    report.expect(moved.changed, cppID: drawerAutomationNodeDragID, message: "the moved node reports a change")
    report.expectEqual(6, moved.dTick, cppID: drawerAutomationNodeDragID,
                       what: "the reported delta is the grabbed node's own tick delta")
    report.expectEqual(AutomationLanePoint(tick: 30, value: 80), plainPress.targets[0].current,
                       cppID: drawerAutomationNodeDragID, what: "the target's preview is the mapped destination")

    // A selected set shares one delta and keeps its spacing.
    var group = AutomationNodeDragTransaction(
        facts: facts,
        targets: [AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[0],
                                           minimum: 0, maximum: 127),
                  AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[1],
                                           minimum: 0, maximum: 127)],
        grabbedPoint: 0, selectionDrag: true, press: (100, 100), deleteOnStationary: true)
    _ = group.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    _ = group.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 105,
                                                effectiveY: 100, axisLock: .none),
                     mapped: AutomationLanePoint(tick: 30, value: 70))
    let groupFinish = group.finish()
    report.expectEqual(AutomationPointRelease.move, groupFinish.release,
                       cppID: drawerAutomationNodeDragID, what: "the selection releases as a move")
    report.expect(groupFinish.changed, cppID: drawerAutomationNodeDragID,
                  message: "the moved selection reports a change")
    report.expectEqual(6, groupFinish.dTick, cppID: drawerAutomationNodeDragID,
                       what: "the shared delta is the grabbed node's delta")
    report.expect(groupFinish.selectionDrag, cppID: drawerAutomationNodeDragID,
                  message: "the finish reports that the whole selection moved")
    report.expectEqual(["30:70", "54:90"], group.targets.map { "\($0.current.tick):\($0.current.value)" },
                       cppID: drawerAutomationNodeDragID, what: "every selected node moves by the same delta")

    // The lower edge clamps the common delta, so the group keeps its spacing.
    var edge = AutomationNodeDragTransaction(
        facts: facts,
        targets: [AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[0],
                                           minimum: 0, maximum: 127),
                  AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[1],
                                           minimum: 0, maximum: 127)],
        grabbedPoint: 1, selectionDrag: false, press: (100, 100), deleteOnStationary: false)
    _ = edge.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    _ = edge.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 100,
                                               effectiveY: 100, axisLock: .none),
                    mapped: AutomationLanePoint(tick: 0, value: 80))
    report.expectEqual(["0:60", "24:80"], edge.targets.map { "\($0.current.tick):\($0.current.value)" },
                       cppID: drawerAutomationNodeDragID,
                       what: "a leftward drag clamps at tick zero without collapsing the group")
    report.expectEqual(-24, edge.finish().dTick, cppID: drawerAutomationNodeDragID,
                       what: "the clamped delta is what the finish reports")
    report.expectEqual(AutomationPointRelease.move, edge.finish().release,
                       cppID: drawerAutomationNodeDragID, what: "the clamped group releases as a move")
    report.expect(edge.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "the clamped group reports a change")

    // The axis lock pins one axis.
    var locked = AutomationNodeDragTransaction.single(facts: facts, source: sources[1],
                                                      press: (100, 100),
                                                      deleteOnStationary: false)
    _ = locked.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 130,
                                                 effectiveY: 60, axisLock: .time),
                      mapped: AutomationLanePoint(tick: 60, value: 20))
    report.expectEqual(80, locked.targets[0].current.value, cppID: drawerAutomationNodeDragID,
                       what: "a time lock keeps the original value")
    report.expectEqual(Tick(60), locked.targets[0].current.tick, cppID: drawerAutomationNodeDragID,
                       what: "a time lock keeps the mapped tick")

    // A phantom drag restores its source on reset and clamps into the domain.
    var phantom = AutomationPhantomDragTransaction(facts: facts, source: sources[0],
                                                   press: (100, 100))
    report.expectEqual(AutomationAxisLock.value,
                       phantom.update(AutomationPointDrag.Update(phase: .reset, effectiveX: 100,
                                                                 effectiveY: 100, axisLock: .none),
                                      mappedValue: 127),
                       cppID: drawerAutomationNodeDragID, what: "a phantom drag only ever locks the value axis")
    report.expectEqual(AutomationLanePoint(tick: 24, value: 60), phantom.target.current,
                       cppID: drawerAutomationNodeDragID, what: "a reset restores the phantom's source value")
    report.expect(phantom.finish() == nil, cppID: drawerAutomationNodeDragID,
                  message: "a reset phantom finishes as no edit")
    _ = phantom.drag.update(x: 100, y: 110, shiftHeld: false, activationDistance: 5)
    _ = phantom.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 100,
                                                  effectiveY: 110, axisLock: .value),
                       mappedValue: 200)
    guard let phantomTarget = phantom.finish() else {
        report.fail(drawerAutomationNodeDragID, "the dragged phantom publishes no target")
        return
    }
    report.expectEqual(phantomTarget.original.tick, phantomTarget.current.tick, cppID: drawerAutomationNodeDragID,
                       what: "a phantom drag never moves in time")
    report.expectEqual(127, phantomTarget.current.value, cppID: drawerAutomationNodeDragID,
                       what: "a phantom drag clamps into the lane's domain")
    report.expectEqual(Tick(24), phantom.move?.sourceTick ?? 0, cppID: drawerAutomationNodeDragID,
                       what: "the phantom's write names its own source tick")

    // The committed drag writes once, moves the node and evicts the occupant of
    // the destination tick.
    var committed = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                         press: (100, 100),
                                                         deleteOnStationary: true)
    _ = committed.drag.update(x: 120, y: 100, shiftHeld: false, activationDistance: 5)
    _ = committed.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 120,
                                                    effectiveY: 100, axisLock: .none),
                         mapped: AutomationLanePoint(tick: 48, value: 90))
    let beforeCommit = fixture.snapshot
    guard let plan = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(facts, committed.moves)
    ]) else {
        report.fail(drawerAutomationNodeDragID, "the committed drag resolved no plan")
        return
    }
    report.expect(AutomationCommit.apply(plan, in: fixture.document), cppID: drawerAutomationNodeDragID,
                  message: "the committed drag writes once")
    report.expectEqual(["48:90", "120:40"], fixture.values(fixture.panLane), cppID: drawerAutomationNodeDragID,
                       what: "the node lands on its destination and evicts the occupant there")
    report.expectEqual(beforeCommit.revision + 1, fixture.document.revision, cppID: drawerAutomationNodeDragID,
                       what: "one drag is one revision")
    report.expect(fixture.undo(), cppID: drawerAutomationNodeDragID, message: "the drag is undoable")
    report.expectEqual(["24:60", "48:80", "120:40"], fixture.values(fixture.panLane),
                       cppID: drawerAutomationNodeDragID,
                       what: "one undo restores the moved node and the evicted occupant")

    // A write on the projected engine node promotes it into a written event.
    let promotion = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    let promotionFacts = promotion.facts(promotion.panLane)
    report.expectEqual(["0:64"], promotion.laneValues(promotionFacts.displayPoints), cppID: drawerAutomationNodeDragID,
                       what: "the empty lane displays its projected engine node")
    guard let promotionPlan = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(promotionFacts, [
            AutomationNodeMove(parameter: promotion.panLane, sourceTick: 0, tick: 0, value: 20)
        ])
    ]) else {
        report.fail(drawerAutomationNodeDragID, "the promotion resolved no plan")
        return
    }
    report.expect(!promotionPlan.isEmpty, cppID: drawerAutomationNodeDragID,
                  message: "a write on the projected node resolves to a promotion")
    report.expect(AutomationCommit.apply(promotionPlan, in: promotion.document), cppID: drawerAutomationNodeDragID,
                  message: "the promotion commits")
    report.expectEqual(["0:20"], promotion.values(promotion.panLane), cppID: drawerAutomationNodeDragID,
                       what: "the projected node becomes a written event at its own tick")
    report.expect(promotion.undo() && promotion.values(promotion.panLane).isEmpty, cppID: drawerAutomationNodeDragID,
                  message: "one undo returns the lane to its projected node alone")
}

@MainActor
func drawerAutomationPointRangeAndPencilReplacements(_ report: CheckReport, suite: DocumentSession,
                                             service: ProjectService) {
    let metadata = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    let freeze = AutomationLaneFreeze(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan), revision: 7,
        metadata: metadata, songEndTick: 96,
        original: [AutomationLanePoint(tick: 0, value: 20),
                   AutomationLanePoint(tick: 24, value: 60),
                   AutomationLanePoint(tick: 72, value: 90)])
    report.expectEqual(7, freeze.revision, cppID: drawerAutomationPointRangeID,
                       what: "the frozen lane carries the revision it was read at")
    let originalPointRange = AutomationLaneFreeze(
        parameter: freeze.parameter, revision: freeze.revision, metadata: metadata,
        songEndTick: 96, original: [AutomationLanePoint(tick: 24, value: 64),
                                   AutomationLanePoint(tick: 48, value: 64)])
    report.expect(AutomationLaneReplacement.pointRange(
        originalPointRange, begin: 24, end: 48,
        points: [AutomationLanePoint(tick: 24, value: 64),
                 AutomationLanePoint(tick: 48, value: 64)]).unchanged,
        cppID: drawerAutomationPointRangeID, message: "the original two-point range is unchanged")
    report.expect(!AutomationLaneReplacement.pointRange(
        originalPointRange, begin: 24, end: 48,
        points: [AutomationLanePoint(tick: 24, value: 64)]).unchanged,
        cppID: drawerAutomationPointRangeID, message: "dropping the original range endpoint changes it")

    // Swift freezes an implicit lead-in into the held series before replacement.
    // This is the original arbitrary value 20; the page pencil case below also
    // exercises the actual Modulation engine default through production setup.
    let leadIn = AutomationLaneFreeze(parameter: freeze.parameter, revision: freeze.revision,
                                      metadata: metadata, songEndTick: 96,
                                      original: [AutomationLanePoint(tick: 0, value: 20)])
    let leadInCompletion = AutomationLaneReplacement.heldSpan(
        leadIn, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 80)])
    report.expect(!leadInCompletion.unchanged, cppID: drawerAutomationPointRangeID,
                  message: "the original implicit lead-in replacement changes the lane")
    report.expectEqual([AutomationLanePoint(tick: 24, value: 80),
                        AutomationLanePoint(tick: 48, value: 20)], leadInCompletion.points,
                       cppID: drawerAutomationPointRangeID,
                       what: "the original implicit lead-in is restored at the two-point span end")

    // An identical point range is unchanged.
    let identical = AutomationLaneReplacement.pointRange(
        freeze, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 60)])
    report.expect(identical.unchanged, cppID: drawerAutomationPointRangeID,
                  message: "an identical point range is unchanged")
    let shortened = AutomationLaneReplacement.pointRange(
        freeze, begin: 24, end: 48,
        points: [AutomationLanePoint(tick: 24, value: 64),
                 AutomationLanePoint(tick: 48, value: 64)])
    report.expect(!shortened.unchanged, cppID: drawerAutomationPointRangeID,
                  message: "a range the lane does not hold is a change")

    // A held-span replacement restores the boundary endpoint.
    let restored = AutomationLaneReplacement.heldSpan(
        freeze, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 80)])
    report.expect(!restored.unchanged, cppID: drawerAutomationPointRangeID,
                  message: "a held-span replacement that differs is a change")
    report.expectEqual(["24:80", "48:60"], restored.points.map { "\($0.tick):\($0.value)" },
                       cppID: drawerAutomationPointRangeID,
                       what: "the held span closes on the original endpoint's value")
    report.expectEqual(Tick(48), restored.tickEnd, cppID: drawerAutomationPointRangeID,
                       what: "the replacement names the last tick it covers")

    // A flat replacement is unchanged; an empty one deletes the span.
    let flat = AutomationLaneReplacement.heldSpan(
        freeze, begin: 36, end: 48, points: [AutomationLanePoint(tick: 36, value: 60)])
    report.expect(flat.unchanged, cppID: drawerAutomationPointRangeID,
                  message: "a replacement the lane already holds is unchanged")
    report.expectEqual(0, flat.points.count, cppID: drawerAutomationPointRangeID,
                       what: "an unchanged replacement carries no point")
    let deletion = AutomationLaneReplacement.heldSpan(freeze, begin: 24, end: 96, points: [])
    report.expect(!deletion.unchanged, cppID: drawerAutomationPointRangeID,
                  message: "an empty replacement over a covered span deletes it")
    report.expectEqual(0, deletion.points.count, cppID: drawerAutomationPointRangeID,
                       what: "the deleting replacement carries no point")

    // The canonicalization and held-value rules.
    report.expectEqual(["8:20", "24:40"],
                       AutomationLaneReplacement.canonical(
                           [AutomationLanePoint(tick: 24, value: 30),
                            AutomationLanePoint(tick: 8, value: 20),
                            AutomationLanePoint(tick: 32, value: 30),
                            AutomationLanePoint(tick: 24, value: 40)],
                           begin: 0, end: 30, minimum: 0, maximum: 127, priorValue: nil)
                           .map { "\($0.tick):\($0.value)" },
                       cppID: drawerAutomationPointRangeID,
                       what: "canonicalization sorts, drops the far tick and keeps the last occupant")
    report.expectEqual(["0:0", "24:9"],
                       AutomationLaneReplacement.canonical(
                           [AutomationLanePoint(tick: 0, value: -4),
                            AutomationLanePoint(tick: 9, value: -4),
                            AutomationLanePoint(tick: 24, value: 9)],
                           begin: 0, end: 96, minimum: 0, maximum: 9, priorValue: nil)
                           .map { "\($0.tick):\($0.value)" },
                       cppID: drawerAutomationPointRangeID,
                       what: "canonicalization clamps into the domain and drops repeated values")
    let held = [AutomationLanePoint(tick: 8, value: 20), AutomationLanePoint(tick: 24, value: 30)]
    report.expect(AutomationLaneReplacement.held(held, at: 8, inclusive: false) == nil,
                  cppID: drawerAutomationPointRangeID,
                  message: "the exclusive held lookup skips a point on the tick")
    report.expectEqual(20, AutomationLaneReplacement.held(held, at: 8, inclusive: true) ?? -1,
                       cppID: drawerAutomationPointRangeID,
                       what: "the inclusive held lookup takes a point on the tick")
    report.expectEqual(30, AutomationLaneReplacement.held(held, at: 40, inclusive: true) ?? -1,
                       cppID: drawerAutomationPointRangeID,
                       what: "the held lookup walks to the last point before the tick")
    report.expect(AutomationLaneReplacement.held(held, at: 4, inclusive: true) == nil,
                  cppID: drawerAutomationPointRangeID, message: "the held lookup reports nothing before the first")

    // The pencil stroke on an empty lane with a lead-in.
    let emptyLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let emptyFacts = emptyLane.facts(emptyLane.modulationLane)
    report.expectEqual(0, emptyFacts.snapshot.leadInValue ?? -1, cppID: drawerAutomationPointRangeID,
                       what: "an unwritten Modulation lane leads in on its engine default")
    guard let stroke = AutomationPencilTransaction(
        facts: emptyFacts,
        firstSample: AutomationPencilTransaction.Sample(
            rawTick: 24, logicalX: 24, logicalY: 40,
            point: AutomationLanePoint(tick: 24, value: 80), continuousValue: 80),
        firstCell: AutomationGridCell(tickBegin: 24, tickEnd: 48), clockTicks: 24) else {
        report.fail(drawerAutomationPointRangeID, "the pencil stroke did not start on an empty lane")
        return
    }
    report.expectEqual(["24:80", "48:0"], emptyLane.laneValues(stroke.completion().points),
                       cppID: drawerAutomationPointRangeID,
                       what: "the stroke writes its point and restores the lane's held value")
    report.expectEqual(["24:80", "48:0"], emptyLane.laneValues(stroke.preview.points),
                       cppID: drawerAutomationPointRangeID, what: "the stroke's preview matches its completion")
    report.expect(!stroke.completion().unchanged, cppID: drawerAutomationPointRangeID,
                  message: "an empty lane's first stroke is a change")

    // A stroke past the last point re-anchors that point's value.
    let pastLast = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [(0, 20)])
    let pastLastFacts = pastLast.facts(pastLast.modulationLane)
    guard let pastLastStroke = AutomationPencilTransaction(
        facts: pastLastFacts,
        firstSample: AutomationPencilTransaction.Sample(
            rawTick: 24, logicalX: 24, logicalY: 40,
            point: AutomationLanePoint(tick: 24, value: 80), continuousValue: 80),
        firstCell: AutomationGridCell(tickBegin: 24, tickEnd: 48), clockTicks: 24) else {
        report.fail(drawerAutomationPointRangeID, "the pencil stroke did not start past the last point")
        return
    }
    report.expectEqual(["24:80", "48:20"], pastLast.laneValues(pastLastStroke.completion().points),
                       cppID: drawerAutomationPointRangeID,
                       what: "a stroke past the last point re-anchors that point's value")
    report.expect(!pastLastStroke.completion().unchanged, cppID: drawerAutomationPointRangeID,
                  message: "a stroke past the last point reports a change")

    // Committed through the page's own press and release: one write, one entry.
    let committed = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [(0, 20)])
    let committedBefore = committed.snapshot
    committed.activate(committed.modulationLane)
    // Historical CCLanes defaults Modulation to Auto: this fixture's maximum
    // 20 displays 0–32. Request the full range before targeting value 60.
    _ = committed.page.openParameterMenu(
        index: committed.page.catalogIndex(of: committed.modulationLane), x: 0, y: 0)
    report.expect(committed.page.consumeMenuAction(actionId: AutomationMenuAction.range127.rawValue),
                  cppID: drawerAutomationPointRangeID, message: "the stroke fixture selects its intended value range")
    report.expectEqual(committedBefore, committed.snapshot, cppID: drawerAutomationPointRangeID,
                       what: "preparing the display range leaves document and history unchanged")
    committed.page.isPencilMode = true
    let strokeY = committed.y(committed.modulationLane, 60)
    report.expect(committed.page.pointerPress(x: committed.x(24), y: strokeY, surface: 1, button: 1), cppID: drawerAutomationPointRangeID,
                  message: "the pencil press starts a stroke")
    report.expect(committed.page.isPainting, cppID: drawerAutomationPointRangeID,
                  message: "the page publishes the painting gesture")
    report.expect(committed.page.pointerRelease(x: committed.x(24), y: strokeY, button: 1), cppID: drawerAutomationPointRangeID,
                  message: "the pencil release commits")
    report.expectEqual(committedBefore.revision + 1, committed.document.revision, cppID: drawerAutomationPointRangeID,
                       what: "one pencil press and release is one revision")
    report.expect(committed.values(committed.modulationLane).contains { $0.hasSuffix(":60") },
                  cppID: drawerAutomationPointRangeID,
                  message: "the released stroke writes the value under the pointer")
    report.expect(committed.undo(), cppID: drawerAutomationPointRangeID, message: "the stroke is undoable")
    report.expectEqual(["0:20"], committed.values(committed.modulationLane), cppID: drawerAutomationPointRangeID,
                       what: "one undo restores the pre-stroke lane")
    report.expect(!committed.document.history.canUndo, cppID: drawerAutomationPointRangeID,
                  message: "the released stroke recorded exactly one history entry")
}

@MainActor
func coreEventAutomationGestureCoreSeams(_ report: CheckReport) {
    let replacement = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 1),
        .channel(tick: 0, status: 0xB0, data0: 7, data1: 20),
        .channel(tick: 24, status: 0xB0, data0: 7, data1: 60),
        .channel(tick: 72, status: 0xB0, data0: 7, data1: 90),
    ])]))
    replacement.writeLane(track: 0, lane: .controller(7), from: 24, through: 48,
                          points: [
                              LaneWrite(tick: 24, value: 80),
                              LaneWrite(tick: 48, value: 60),
                          ])
    report.expectEqual(
        ["0:20", "24:80", "48:60", "72:90"],
        replacement.lanePoints(track: 0, lane: .controller(7))
            .map { "\($0.tick):\($0.value)" },
        cppID: "automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements",
        what: "core held-span replacement including the trailing held-value seam")

    let emptyLane = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)]),
    ]))
    emptyLane.writeLane(track: 0, lane: .controller(7), from: 24, through: 48,
                        points: [
                            LaneWrite(tick: 24, value: 80),
                            LaneWrite(tick: 48, value: 20),
                        ])
    report.expectEqual(
        ["24:80", "48:20"],
        emptyLane.lanePoints(track: 0, lane: .controller(7))
            .map { "\($0.tick):\($0.value)" },
        cppID: "automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements",
        what: "core empty-lane replacement stores the pencil value and restored tail")

    let trailingHold = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 1),
        .channel(tick: 0, status: 0xB0, data0: 7, data1: 85),
    ])]))
    trailingHold.writeLane(track: 0, lane: .controller(7), from: 48, through: 168,
                           points: [
                               LaneWrite(tick: 144, value: 25),
                               LaneWrite(tick: 168, value: 85),
                           ])
    report.expectEqual(
        ["0:85", "144:25", "168:85"],
        trailingHold.lanePoints(track: 0, lane: .controller(7))
            .map { "\($0.tick):\($0.value)" },
        cppID: "automation-domain/AutomationDomainTest::sweepFinishRestoresTrailingHeldValue",
        what: "core lane write retains the explicit post-sweep held-value seam")
}

/// Supplemental history regression from the production QML Pan sequence.
/// The original panNeutralSnap asserts mapping, not this asynchronous undo.
@MainActor
func coreAutomationPanUndoRegression(_ report: CheckReport, suite: DocumentSession,
                                     service: ProjectService) async throws {
    let id = "swiftcore/Automation::supplementalAwaitedPanUndo"
    let fx = drawerAutomationAutomationFixture(suite: suite, service: service)
    fx.document.writeLane(track: 0, lane: .controller(10), from: 0, through: 12,
        points: [LaneWrite(tick: 0, value: 112), LaneWrite(tick: 12, value: 64)])
    let firstWrite = fx.document.state
    fx.document.writeLane(track: 0, lane: .controller(10), from: 72, through: 108,
        points: [LaneWrite(tick: 72, value: 15), LaneWrite(tick: 108, value: 64)])
    let beforeMove = fx.document.state
    let facts = fx.facts(fx.panLane)
    guard let plan = AutomationNodeResolver.moves([.init(facts, [
        AutomationNodeMove(parameter: fx.panLane, sourceTick: 0, tick: 0, value: 63),
    ])]) else { report.fail(id, "Pan node move resolves"); return }
    report.expect(AutomationCommit.apply(plan, in: fx.document), cppID: id,
                  message: "node value move records its own transaction")
    let moved = fx.document.state
    report.expect(moved != beforeMove, cppID: id, message: "the move actually changes document state")
    let undone = try await fx.session.undo()
    report.expect(undone, cppID: id, message: "awaited undo completes")
    report.expectEqual(beforeMove, fx.document.state, cppID: id,
                       what: "one undo restores all four written Pan occurrences")
    let redone = try await fx.session.redo()
    report.expect(redone, cppID: id, message: "awaited redo completes")
    report.expectEqual(moved, fx.document.state, cppID: id, what: "redo restores the node value move")
    _ = try await fx.session.undo()
    _ = try await fx.session.undo()
    report.expectEqual(firstWrite, fx.document.state, cppID: id,
                       what: "only a second undo removes the preceding Pan sweep")
}

let drawerAutomationContractParityID = "swiftcore/AutomationPage::gestureContractParity"

@MainActor
func drawerAutomationGestureContractParity(_ report: CheckReport, suite: DocumentSession,
                                           service: ProjectService) {
    let emptyLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    let emptyFacts = emptyLane.facts(emptyLane.panLane)
    report.expectEqual(["0:64"], emptyLane.laneValues(emptyFacts.displayPoints),
                       cppID: drawerAutomationContractParityID,
                       what: "an empty lane displays its projected engine node")
    report.expect(emptyFacts.snapshot.leadInValue == nil, cppID: drawerAutomationContractParityID,
                  message: "an empty lane carries no written lead-in")
    let emptyModulationFacts = emptyLane.facts(emptyLane.modulationLane)
    report.expectEqual(0, emptyModulationFacts.snapshot.leadInValue ?? -1,
                       cppID: drawerAutomationContractParityID,
                       what: "an unwritten Modulation lane leads in on its engine default")
    let metadata = AutomationParameterMetadata(parameter: emptyLane.panLane)
    report.expectEqual("Pan (PAN)", AutomationCatalog.title(emptyLane.panLane),
                       cppID: drawerAutomationContractParityID, what: "the catalog titles a CC lane")
    report.expectEqual("Tempo (BPM)", AutomationCatalog.title(.tempo),
                       cppID: drawerAutomationContractParityID, what: "the catalog titles Tempo")
    report.expectEqual("Pitch bend (BEND)", AutomationCatalog.title(emptyLane.bendLane),
                       cppID: drawerAutomationContractParityID, what: "the catalog titles bend")
    report.expectEqual(0, metadata.minimum, cppID: drawerAutomationContractParityID,
                       what: "a CC lane bottoms at zero")
    report.expectEqual(127, metadata.maximum, cppID: drawerAutomationContractParityID,
                       what: "a CC lane tops at 127")
    report.expectEqual("150", AutomationParameterMetadata(parameter: .tempo).valueText(150),
                       cppID: drawerAutomationContractParityID, what: "Tempo formats raw BPM")
    report.expectEqual("c_v+0", metadata.valueText(64), cppID: drawerAutomationContractParityID,
                       what: "the neutral value formats through its own metadata")
    let band = AutomationTimeSelection(range: TimeRange(startTick: 50, endTick: 100), scope: .lanes,
                                       lanes: [emptyLane.panLane])
    report.expectEqual(Tick(50), band.range.startTick, cppID: drawerAutomationContractParityID,
                       what: "a band publishes its active tick range")
    report.expect(band.covers(emptyLane.panLane, usedTracks: [0]), cppID: drawerAutomationContractParityID,
                  message: "a band covers its own lane")
    report.expect(!band.covers(.tempo, usedTracks: [0]), cppID: drawerAutomationContractParityID,
                  message: "a CC band excludes Tempo")
    let tempoBand = AutomationTimeSelection(range: TimeRange(startTick: 50, endTick: 100),
                                            scope: .lanes, lanes: [.tempo], tempo: true)
    report.expect(tempoBand.coversTempo(usedTracks: [0]), cppID: drawerAutomationContractParityID,
                  message: "a Tempo band covers Tempo")
    report.expect(!tempoBand.covers(emptyLane.panLane, usedTracks: [0]),
                  cppID: drawerAutomationContractParityID,
                  message: "a Tempo band excludes CC lanes")
    let sameTick = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(96, 10), (96, 20)])
    report.expectEqual(["96:10", "96:20"], sameTick.values(sameTick.panLane),
                       cppID: drawerAutomationContractParityID,
                       what: "same-tick CC writes keep their order")
    let moved = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  pan: [(24, 60), (48, 80)])
    var moveFacts = moved.facts(moved.panLane)
    guard let firstHop = AutomationNodeResolver.moves([.init(moveFacts, [
        AutomationNodeMove(parameter: moved.panLane, sourceTick: 24, tick: 96, value: 60),
    ])]) else {
        report.fail(drawerAutomationContractParityID, "the first hop resolved no plan")
        return
    }
    let moveBefore = moved.snapshot
    report.expect(AutomationCommit.apply(firstHop, in: moved.document),
                  cppID: drawerAutomationContractParityID, message: "the first hop commits")
    report.expectEqual(["48:80", "96:60"], moved.values(moved.panLane),
                       cppID: drawerAutomationContractParityID,
                       what: "a move onto a free tick keeps every occupant in order")
    moveFacts = moved.facts(moved.panLane)
    guard let secondHop = AutomationNodeResolver.moves([.init(moveFacts, [
        AutomationNodeMove(parameter: moved.panLane, sourceTick: 48, tick: 96, value: 80),
    ])]) else {
        report.fail(drawerAutomationContractParityID, "the second hop resolved no plan")
        return
    }
    report.expect(AutomationCommit.apply(secondHop, in: moved.document),
                  cppID: drawerAutomationContractParityID, message: "the second hop commits")
    report.expectEqual(["96:80"], moved.values(moved.panLane),
                       cppID: drawerAutomationContractParityID,
                       what: "a move onto an occupied tick evicts its occupant")
    report.expectEqual(moveBefore.revision + 2, moved.document.revision,
                       cppID: drawerAutomationContractParityID, what: "two hops are two revisions")
    report.expect(moved.undo(), cppID: drawerAutomationContractParityID, message: "the hops are undoable")
    report.expectEqual(["48:80", "96:60"], moved.values(moved.panLane),
                       cppID: drawerAutomationContractParityID, what: "one undo restores the evicted occupant")
    let unknownFacts = moved.facts(moved.panLane)
    report.expect(AutomationNodeResolver.moves([.init(unknownFacts, [
        AutomationNodeMove(parameter: moved.panLane, sourceTick: 9999, tick: 100, value: 60),
    ])]) == nil, cppID: drawerAutomationContractParityID,
                  message: "a move from an unknown tick resolves to nothing")
    report.expectEqual(moved.snapshot, drawerAutomationAutomationDocumentSnapshot(moved.document),
                       cppID: drawerAutomationContractParityID,
                       what: "an unresolvable move leaves document and history untouched")
    let deleteFacts = moved.facts(moved.panLane)
    guard let deletePlan = AutomationNodeResolver.deletions(revision: deleteFacts.revision, [.init(
        parameter: moved.panLane, snapshot: deleteFacts.snapshot, ticks: [48, 48, 96])]) else {
        report.fail(drawerAutomationContractParityID, "the batch delete resolved no plan")
        return
    }
    report.expect(!deletePlan.isEmpty, cppID: drawerAutomationContractParityID,
                  message: "a batch delete over repeated ticks resolves its removals")
    report.expect(AutomationCommit.apply(deletePlan, in: moved.document),
                  cppID: drawerAutomationContractParityID, message: "the batch delete commits")
    report.expect(moved.values(moved.panLane).isEmpty, cppID: drawerAutomationContractParityID,
                  message: "a batch delete empties the lane's raw events")
    let unknownDeleteFacts = moved.facts(moved.panLane)
    report.expect(AutomationNodeResolver.deletions(revision: unknownDeleteFacts.revision, [.init(
        parameter: moved.panLane, snapshot: unknownDeleteFacts.snapshot, ticks: [9999])]) == nil,
                  cppID: drawerAutomationContractParityID,
                  message: "a delete of an unknown tick resolves to nothing")
    let tempo = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  tempo: [(0, 500_000), (96, 400_000)])
    let tempoFacts = tempo.facts(.tempo)
    let preservedUs = tempo.document.state.tempo.first(where: { $0.tick == 0 })?
        .microsecondsPerQuarterNote ?? 0
    guard let tempoPlan = AutomationNodeResolver.moves([.init(tempoFacts, [
        AutomationNodeMove(parameter: .tempo, sourceTick: 0, tick: 48, value: 120),
    ])]) else {
        report.fail(drawerAutomationContractParityID, "the tempo move resolved no plan")
        return
    }
    let tempoBefore = tempo.snapshot
    report.expect(AutomationCommit.apply(tempoPlan, in: tempo.document),
                  cppID: drawerAutomationContractParityID, message: "the tempo move commits")
    report.expectEqual(preservedUs, tempo.document.state.tempo.first(where: { $0.tick == 48 })?
        .microsecondsPerQuarterNote ?? 0, cppID: drawerAutomationContractParityID,
                       what: "an unchanged-value tempo move preserves its microseconds")
    report.expectEqual(tempoBefore.revision + 1, tempo.document.revision,
                       cppID: drawerAutomationContractParityID, what: "one tempo move is one revision")
    report.expect(tempo.undo(), cppID: drawerAutomationContractParityID, message: "the tempo move is undoable")
    let fractional = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                       tempo: [(0, 499_999)])
    let fractionalFacts = fractional.facts(.tempo)
    guard let fractionalPlan = AutomationNodeResolver.moves([.init(fractionalFacts, [
        AutomationNodeMove(parameter: .tempo, sourceTick: 0, tick: 96, value: 120),
    ])]) else {
        report.fail(drawerAutomationContractParityID, "the fractional tempo drag resolved no plan")
        return
    }
    let fractionalBefore = fractional.snapshot
    report.expect(AutomationCommit.apply(fractionalPlan, in: fractional.document),
                  cppID: drawerAutomationContractParityID, message: "a fractional tempo drag commits one edit")
    report.expectEqual(fractionalBefore.revision + 1, fractional.document.revision,
                       cppID: drawerAutomationContractParityID, what: "one fractional drag is one revision")
    report.expect(fractional.undo(), cppID: drawerAutomationContractParityID,
                  message: "the fractional drag is undoable")
    let vertical = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(24, 60), (48, 80)])
    let verticalFacts = vertical.facts(vertical.panLane)
    var verticalDrag = AutomationNodeDragTransaction.single(
        facts: verticalFacts, source: verticalFacts.snapshot.sources[0], press: (100, 100),
        deleteOnStationary: false)
    _ = verticalDrag.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 100,
                                                       effectiveY: 160, axisLock: .value),
                            mapped: AutomationLanePoint(tick: 60, value: 20))
    report.expectEqual(Tick(24), verticalDrag.targets[0].current.tick,
                       cppID: drawerAutomationContractParityID,
                       what: "a value lock keeps the original tick")
    let lanes = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  pan: [(24, 60)], modulation: [(48, 10)],
                                                  tempo: [(0, 500_000)])
    lanes.activate(lanes.panLane)
    lanes.page.selectRange(from: 0, to: 96, lanes: [lanes.panLane, lanes.modulationLane])
    let lanesBefore = lanes.snapshot
    report.expectEqual(TimeRange(startTick: 0, endTick: 96), lanes.page.selection?.range,
                       cppID: drawerAutomationContractParityID,
                       what: "a right-drag band publishes its shared time selection")
    report.expect(lanes.page.consumeSelectionCommand(command: .delete),
                  cppID: drawerAutomationContractParityID, message: "the mixed delete consumes its selection")
    report.expect(lanes.values(lanes.panLane).isEmpty && lanes.values(lanes.modulationLane).isEmpty,
                  cppID: drawerAutomationContractParityID,
                  message: "a mixed delete clears every covered lane")
    report.expectEqual(["0:120"], lanes.tempoValues, cppID: drawerAutomationContractParityID,
                       what: "a CC range edit preserves Tempo")
    report.expectEqual(lanesBefore.revision + 1, lanes.document.revision,
                       cppID: drawerAutomationContractParityID, what: "one mixed delete is one revision")
    report.expect(lanes.undo(), cppID: drawerAutomationContractParityID, message: "the mixed delete is undoable")
    report.expectEqual(["24:60"], lanes.values(lanes.panLane), cppID: drawerAutomationContractParityID,
                       what: "one undo restores the mixed delete's lanes")
    report.expectEqual(["48:10"], lanes.values(lanes.modulationLane), cppID: drawerAutomationContractParityID,
                       what: "one undo restores the covered modulation lane")
    let cancel = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 60)])
    cancel.activate(cancel.panLane)
    let cancelRevision = cancel.snapshot
    _ = cancel.page.pointerPress(x: cancel.x(24), y: cancel.y(cancel.panLane, 60), surface: 1,
                                 button: AutomationQtButton.left)
    _ = cancel.page.pointerMove(x: cancel.x(24) + 24, y: cancel.y(cancel.panLane, 60) - 12,
                                buttons: AutomationQtButton.left)
    cancel.page.cancelSectionInteraction()
    report.expect(!cancel.page.interactionActive, cppID: drawerAutomationContractParityID,
                  message: "an escape leaves no interaction live")
    report.expectEqual(cancelRevision, cancel.snapshot, cppID: drawerAutomationContractParityID,
                       what: "an escape writes nothing")
    report.expect(cancel.drag(cancel.panLane, from: (24, 60), to: 70,
                              modifiers: AutomationQtModifier.alt),
                  cppID: drawerAutomationContractParityID, message: "input recovers after a cancellation")
    report.expectEqual(["24:70"], cancel.values(cancel.panLane), cppID: drawerAutomationContractParityID,
                       what: "the recovered drag commits its move")
}

@MainActor
func drawerAutomationPencilStrokeFilters(_ report: CheckReport, suite: DocumentSession,
                                         service: ProjectService) {
    func pencilSample(_ rawTick: Double, _ value: Double) -> AutomationPencilTransaction.Sample {
        AutomationPencilTransaction.Sample(
            rawTick: rawTick, logicalX: rawTick, logicalY: 60,
            point: AutomationLanePoint(tick: Tick(rawTick.rounded(.down)), value: Int(value)),
            continuousValue: value)
    }
    func pencilCell(_ begin: Tick) -> AutomationGridCell {
        AutomationGridCell(tickBegin: begin, tickEnd: begin + 24)
    }
    let jitterID = "automation/AutomationEditingTest::pencilSubCellHorizontalJitterDoesNotAlterStroke"
    let jitterLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let jitterFacts = jitterLane.facts(jitterLane.modulationLane)
    let jitterCells = [pencilCell(24), pencilCell(48), pencilCell(72)]
    guard var jitter = AutomationPencilTransaction(
        facts: jitterFacts, firstSample: pencilSample(36, 48),
        firstCell: jitterCells[0], clockTicks: 24) else {
        report.fail(jitterID, "the jitter stroke did not start")
        return
    }
    let slop = jitterLane.page.geometry.nodeDragActivationDistance
    let jittered = jitter.sampleValue(logicalX: 38, logicalY: 60, locking: false, freehand: false,
                                      verticalSlopDistance: slop, plotHeight: 120)
    report.expectEqual(48.0, jittered, cppID: jitterID,
                       what: "pure horizontal jitter keeps the stroke's continuous value")
    jitter.applySnappedSegment(pencilSample(38, jittered), cells: [jitterCells[0]])
    report.expectEqual(1, jitter.strokePoints.count, cppID: jitterID,
                       what: "a same-cell revisit keeps one point for the cell")
    jitter.applySnappedSegment(pencilSample(60, 48), cells: [jitterCells[1]])
    jitter.applySnappedSegment(pencilSample(84, 48), cells: [jitterCells[2]])
    report.expectEqual(["24:48", "48:48", "72:48"], jitterLane.laneValues(jitter.strokePoints),
                       cppID: jitterID, what: "one point per crossed cell holds the jittered value")
    let zigzagID = "automation/AutomationEditingTest::pencilZigzagStrokePreservesDirectionalExtrema"
    let zigzagLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let zigzagFacts = zigzagLane.facts(zigzagLane.modulationLane)
    let zigzagValues = [32, 100, 28, 92, 44, 84]
    let zigzagCells = (0..<6).map { pencilCell(Tick(24 + $0 * 24)) }
    guard var zigzag = AutomationPencilTransaction(
        facts: zigzagFacts, firstSample: pencilSample(36, Double(zigzagValues[0])),
        firstCell: zigzagCells[0], clockTicks: 24) else {
        report.fail(zigzagID, "the zigzag stroke did not start")
        return
    }
    for index in 1..<6 {
        zigzag.applySnappedSegment(
            pencilSample(Double(36 + index * 24), Double(zigzagValues[index])),
            cells: [zigzagCells[index]])
    }
    report.expectEqual((0..<6).map { Tick(24 + $0 * 24) }, zigzag.strokePoints.map(\.tick),
                       cppID: zigzagID, what: "the zigzag keeps one point per crossed cell")
    report.expectEqual(zigzagValues, zigzag.strokePoints.map(\.value), cppID: zigzagID,
                       what: "each zigzag cell holds its own extremum")
    let extrema = zigzag.strokePoints.map(\.value)
    report.expect(extrema[0] < extrema[1] && extrema[1] > extrema[2] && extrema[2] < extrema[3]
                      && extrema[3] > extrema[4] && extrema[4] < extrema[5],
                  cppID: zigzagID, message: "the zigzag preserves every directional extremum")
    let verticalID = "automation/AutomationEditingTest::pencilVerticalMotionInSingleCellRetainsFinalValue"
    let verticalLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let verticalFacts = verticalLane.facts(verticalLane.modulationLane)
    let verticalCell = pencilCell(24)
    guard var vertical = AutomationPencilTransaction(
        facts: verticalFacts, firstSample: pencilSample(36, 32),
        firstCell: verticalCell, clockTicks: 24) else {
        report.fail(verticalID, "the vertical stroke did not start")
        return
    }
    vertical.applySnappedSegment(pencilSample(36, 96), cells: [verticalCell])
    report.expectEqual([AutomationLanePoint(tick: 24, value: 96)], vertical.strokePoints,
                       cppID: verticalID,
                       what: "vertical motion in one cell keeps only the final value")
    let densityID = "automation/AutomationEditingTest::pencilDiagonalStrokeEventDensityInvariance"
    let densityLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let densityFacts = densityLane.facts(densityLane.modulationLane)
    let densityCells = (0..<6).map { pencilCell(Tick(24 + $0 * 24)) }
    func densityStroke(intermediates: Int) -> [AutomationLanePoint]? {
        guard var stroke = AutomationPencilTransaction(
            facts: densityFacts, firstSample: pencilSample(36, 8),
            firstCell: densityCells[0], clockTicks: 24) else { return nil }
        for step in 1...intermediates {
            let rawTick = 36 + 120 * Double(step) / Double(intermediates + 1)
            stroke.applySnappedSegment(pencilSample(rawTick, 8 + 112 * (rawTick - 36) / 120),
                                       cells: densityCells)
        }
        stroke.applySnappedSegment(pencilSample(156, 120), cells: densityCells)
        return stroke.completion().points
    }
    guard let sparse = densityStroke(intermediates: 10),
          let dense = densityStroke(intermediates: 50) else {
        report.fail(densityID, "the density strokes did not start")
        return
    }
    report.expect(!sparse.isEmpty, cppID: densityID,
                  message: "the sparse diagonal stroke writes points")
    report.expectEqual(sparse, dense, cppID: densityID,
                       what: "10 vs 50 intermediate samples give identical completion points")
    let backtrackID = "automation/AutomationEditingTest::pencilBacktrackingStrokeRetainsExtremaAndLatestRevisit"
    let backtrackLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let backtrackFacts = backtrackLane.facts(backtrackLane.modulationLane)
    let outward = [pencilCell(24), pencilCell(48), pencilCell(72)]
    guard var backtrack = AutomationPencilTransaction(
        facts: backtrackFacts, firstSample: pencilSample(36, 28),
        firstCell: outward[0], clockTicks: 24) else {
        report.fail(backtrackID, "the backtracking stroke did not start")
        return
    }
    backtrack.applySnappedSegment(pencilSample(84, 100), cells: outward)
    backtrack.applySnappedSegment(pencilSample(36, 68), cells: Array(outward.reversed()))
    report.expectEqual(["24:68", "48:84", "72:100"],
                       backtrackLane.laneValues(backtrack.strokePoints),
                       cppID: backtrackID,
                       what: "revisited cells hold the leftward values while the far extremum stands")
    report.expectEqual([Tick(24), Tick(48), Tick(72)], backtrack.strokePoints.map(\.tick),
                       cppID: backtrackID, what: "the backtracking stroke stays sorted by tick")
}

@MainActor
func drawerAutomationPencilStrokeModifiers(_ report: CheckReport, suite: DocumentSession,
                                           service: ProjectService) {
    func pencilSample(_ rawTick: Double, _ value: Double) -> AutomationPencilTransaction.Sample {
        AutomationPencilTransaction.Sample(
            rawTick: rawTick, logicalX: rawTick, logicalY: 60,
            point: AutomationLanePoint(tick: Tick(rawTick.rounded(.down)), value: Int(value)),
            continuousValue: value)
    }
    func pencilCell(_ begin: Tick) -> AutomationGridCell {
        AutomationGridCell(tickBegin: begin, tickEnd: begin + 24)
    }
    let shiftID = "automation/AutomationEditingTest::pencilShiftModifierLocksValueDimension"
    let lockedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let lockedFacts = lockedLane.facts(lockedLane.modulationLane)
    let lockedCells = [pencilCell(24), pencilCell(48), pencilCell(72)]
    guard var locked = AutomationPencilTransaction(
        facts: lockedFacts, firstSample: pencilSample(36, 64),
        firstCell: lockedCells[0], clockTicks: 24) else {
        report.fail(shiftID, "the locked stroke did not start")
        return
    }
    let slop = lockedLane.page.geometry.nodeDragActivationDistance
    let firstLocked = locked.sampleValue(logicalX: 60, logicalY: 10, locking: true, freehand: false,
                                         verticalSlopDistance: slop, plotHeight: 120)
    let secondLocked = locked.sampleValue(logicalX: 84, logicalY: 110, locking: true,
                                          freehand: false, verticalSlopDistance: slop,
                                          plotHeight: 120)
    report.expectEqual(64.0, firstLocked, cppID: shiftID,
                       what: "a locked run keeps the initial value")
    report.expectEqual(64.0, secondLocked, cppID: shiftID,
                       what: "a locked run ignores later vertical travel")
    locked.applySnappedSegment(pencilSample(60, firstLocked), cells: [lockedCells[1]])
    locked.applySnappedSegment(pencilSample(84, secondLocked), cells: [lockedCells[2]])
    report.expectEqual(["24:64", "48:64", "72:64"], lockedLane.laneValues(locked.strokePoints),
                       cppID: shiftID, what: "the locked stroke writes its constant initial value")
    let unlockedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard var unlocked = AutomationPencilTransaction(
        facts: unlockedLane.facts(unlockedLane.modulationLane),
        firstSample: pencilSample(36, 64), firstCell: lockedCells[0], clockTicks: 24) else {
        report.fail(shiftID, "the unlocked stroke did not start")
        return
    }
    let unlockedValue = unlocked.sampleValue(logicalX: 60, logicalY: 10, locking: false,
                                             freehand: false, verticalSlopDistance: slop,
                                             plotHeight: 120)
    report.expect(unlockedValue != 64, cppID: shiftID,
                  message: "the same travel unlocked moves the value")
    let controlID = "automation/AutomationEditingTest::pencilControlModifierDrawsUnsnappedClockQuantizedPoints"
    let freehandLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard var freehand = AutomationPencilTransaction(
        facts: freehandLane.facts(freehandLane.modulationLane),
        firstSample: pencilSample(24, 30), firstCell: pencilCell(24), clockTicks: 6) else {
        report.fail(controlID, "the freehand stroke did not start")
        return
    }
    freehand.applyFreehandSegment(pencilSample(31.5, 90))
    report.expectEqual([Tick(24), Tick(30)], freehand.strokePoints.map(\.tick), cppID: controlID,
                       what: "a freehand run lands on clock ticks off the snapped grid")
    report.expect(freehand.strokePoints.allSatisfy { $0.tick % 6 == 0 }, cppID: controlID,
                  message: "every freehand point is clock-quantized")
    report.expect(freehand.strokePoints.contains { $0.tick % 24 != 0 }, cppID: controlID,
                  message: "the freehand run escapes the snapped cell lattice")
    let mixedID = "automation/AutomationEditingTest::pencilMixedModifierComposesFreehandAndSnappedSegments"
    let mixedLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    guard var mixed = AutomationPencilTransaction(
        facts: mixedLane.facts(mixedLane.modulationLane),
        firstSample: pencilSample(36, 36), firstCell: pencilCell(24), clockTicks: 6) else {
        report.fail(mixedID, "the mixed stroke did not start")
        return
    }
    mixed.applySnappedSegment(pencilSample(60, 76), cells: [pencilCell(24), pencilCell(48)])
    mixed.applyFreehandSegment(pencilSample(70.5, 104))
    report.expectEqual([Tick(24), Tick(48), Tick(60), Tick(66)], mixed.strokePoints.map(\.tick),
                       cppID: mixedID,
                       what: "snapped then freehand segments compose contiguously")
    report.expectEqual(36, mixed.strokePoints.first?.value ?? -1, cppID: mixedID,
                       what: "the snapped head keeps its cell value")
    report.expectEqual(Tick(24), mixed.tickBegin, cppID: mixedID,
                       what: "the mixed stroke spans from its first cell")
    let altID = "automation/AutomationEditingTest::pencilAltModifierIsIgnoredDuringStroke"
    let plainLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    plainLane.activate(plainLane.panLane)
    plainLane.page.isPencilMode = true
    let plainBits = drawerAutomationQtModifiers(AutomationModifiers())
    guard plainLane.page.pointerPress(x: plainLane.x(48), y: plainLane.y(plainLane.panLane, 36),
                                      surface: 1, button: 1, modifiers: plainBits) else {
        report.fail(altID, "the plain stroke did not start")
        return
    }
    plainLane.page.pointerMove(x: plainLane.x(120), y: plainLane.y(plainLane.panLane, 96),
                               buttons: 1, modifiers: plainBits)
    guard plainLane.page.pointerRelease(x: plainLane.x(120), y: plainLane.y(plainLane.panLane, 96),
                                        button: 1, modifiers: plainBits) else {
        report.fail(altID, "the plain stroke did not commit")
        return
    }
    let altLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    altLane.activate(altLane.panLane)
    altLane.page.isPencilMode = true
    let altBits = drawerAutomationQtModifiers(AutomationModifiers(fine: true))
    guard altLane.page.pointerPress(x: altLane.x(48), y: altLane.y(altLane.panLane, 36),
                                    surface: 1, button: 1, modifiers: altBits) else {
        report.fail(altID, "the fine stroke did not start")
        return
    }
    altLane.page.pointerMove(x: altLane.x(120), y: altLane.y(altLane.panLane, 96),
                             buttons: 1, modifiers: altBits)
    guard altLane.page.pointerRelease(x: altLane.x(120), y: altLane.y(altLane.panLane, 96),
                                      button: 1, modifiers: altBits) else {
        report.fail(altID, "the fine stroke did not commit")
        return
    }
    let plain = plainLane.values(plainLane.panLane)
    report.expect(!plain.isEmpty, cppID: altID, message: "the plain stroke writes the empty lane")
    report.expectEqual(plain, altLane.values(altLane.panLane), cppID: altID,
                       what: "the fine modifier leaves the stroke unchanged")
}
