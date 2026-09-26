import Foundation
@testable import PorydawApp
import PorydawCore

// Node-drag scenarios paired with gestures.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationPanNeutralSnap(_ report: CheckReport, suite: DocumentSession,
                            service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 72)])
    let metadata = AutomationParameterMetadata(parameter: fixture.panLane)
    report.expectEqual(expected: 64, actual: metadata.neutral, cppID: drawerAutomationNeutralSnapID,
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
        snapPolicy: AutomationProjectionCache().snapPolicy(session: fixture.session, font: 13, dpr: 1),
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
    report.expectEqual(expected: Tick(100), actual: plain.tick, cppID: drawerAutomationNeutralSnapID,
                       what: "the unsnapped value mapping preserves tick 100")
    report.expectEqual(expected: valueNear, actual: plain.value, cppID: drawerAutomationNeutralSnapID,
                       what: "the unsnapped value mapping keeps the near-neutral pixel value")
    let snapped = fixture.page.mappedPoint(x: projection.x(100), y: Double(yNear), facts: facts,
                                           modifiers: AutomationModifiers(fine: true, snapValue: true),
                                           projection: projection)
    report.expectEqual(expected: Tick(100), actual: snapped.tick, cppID: drawerAutomationNeutralSnapID,
                       what: "neutral snapping preserves tick 100")
    report.expectEqual(expected: 64, actual: snapped.value, cppID: drawerAutomationNeutralSnapID,
                       what: "the near-neutral pixel snaps to 64")
    let exact = fixture.page.mappedPoint(x: projection.x(200), y: projection.y(64, metadata: metadata),
                                         facts: facts,
                                         modifiers: AutomationModifiers(fine: true, snapValue: true),
                                         projection: projection)
    report.expectEqual(expected: AutomationLanePoint(tick: 200, value: 64), actual: exact,
                       cppID: drawerAutomationNeutralSnapID,
                       what: "the exact neutral maps to the original tick-200 point")
    report.expectEqual(expected: near, actual: metadata.snappedValue(near, snapValue: false, plotHeight: height,
                                                   neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID,
                       what: "an unsnapped drag keeps the value under the pointer")
    report.expectEqual(expected: 64, actual: metadata.snappedValue(near, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID, what: "a snapped drag lands exactly on the neutral")
    report.expectEqual(expected: 64, actual: metadata.snappedValue(64, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID, what: "a pointer on the neutral stays neutral")
    let outside = 64 + threshold + 5
    report.expectEqual(expected: outside, actual: metadata.snappedValue(outside, snapValue: true, plotHeight: height,
                                                      neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID,
                       what: "a value outside the radius keeps its own value")
    report.expectEqual(expected: 19, actual: metadata.snappedValue(19, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: drawerAutomationNeutralSnapID,
                       what: "a snap only ever moves a value onto the neutral")
    let volume = AutomationParameterMetadata(parameter: fixture.volumeLane)
    report.expectEqual(expected: 60, actual: volume.snappedValue(60, snapValue: true, plotHeight: height,
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
    report.expectEqual(expected: Tick(24), actual: fixture.page.previewPoints.first?.tick ?? 0, cppID: drawerAutomationNeutralSnapID,
                       what: "the armed preview keeps the node's own tick")
    _ = fixture.page.pointerMove(x: nodeX + 12, y: nodeY, buttons: 1, modifiers: drawerAutomationQtModifiers(modifiers))
    report.expectEqual(expected: 64, actual: fixture.page.previewPoints.first?.value ?? 0, cppID: drawerAutomationNeutralSnapID,
                       what: "the preview publishes the snapped neutral")
    _ = fixture.page.pointerRelease(x: nodeX + 12, y: nodeY, button: 1, modifiers: drawerAutomationQtModifiers(modifiers))
    report.expectEqual(expected: ["24:64"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationNeutralSnapID,
                       what: "the snapped release writes the neutral at the node's own tick")
}

@MainActor
func drawerAutomationNodeDragAndPhantomOutcomes(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 60), (48, 80), (120, 40)])
    let facts = fixture.facts(fixture.panLane)
    let sources = facts.snapshot.sources
    report.expectEqual(expected: 3, actual: sources.count, cppID: drawerAutomationNodeDragID,
                       what: "the fixture offers three draggable nodes")

    // An empty gesture finishes as a no-op.
    let empty = AutomationNodeDragTransaction(facts: facts, targets: [], grabbedPoint: 0,
                                              selectionDrag: false, press: (100, 100),
                                              deleteOnStationary: true)
    report.expectEqual(expected: AutomationPointRelease.noOp, actual: empty.finish().release, cppID: drawerAutomationNodeDragID,
                       what: "a gesture with no target finishes as a no-op")
    report.expect(!empty.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "an empty gesture reports no change")

    // A Shift-held stationary release is a no-op; a plain one deletes.
    let shiftPress = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                          press: (100, 100),
                                                          deleteOnStationary: false)
    report.expectEqual(expected: AutomationPointRelease.noOp, actual: shiftPress.finish().release, cppID: drawerAutomationNodeDragID,
                       what: "a Shift-held stationary release is a no-op")
    report.expect(!shiftPress.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "a Shift-held stationary release changes nothing")
    var plainPress = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                          press: (100, 100),
                                                          deleteOnStationary: true)
    report.expectEqual(expected: AutomationPointRelease.stationaryDelete, actual: plainPress.finish().release,
                       cppID: drawerAutomationNodeDragID, what: "a stationary release without Shift deletes")
    report.expect(!plainPress.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "the stationary delete reports no move")

    // Past the slop without moving: a move that changed nothing.
    _ = plainPress.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    report.expectEqual(expected: AutomationPointRelease.move, actual: plainPress.finish().release, cppID: drawerAutomationNodeDragID,
                       what: "a released stroke past the slop is a move")
    report.expect(!plainPress.finish().changed, cppID: drawerAutomationNodeDragID,
                  message: "a stroke that never moved the node changes nothing")

    // The same gesture with a moved node: one move with the grabbed delta.
    _ = plainPress.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 130,
                                                     effectiveY: 100, axisLock: .none),
                          mapped: AutomationLanePoint(tick: 30, value: 80))
    let moved = plainPress.finish()
    report.expectEqual(expected: AutomationPointRelease.move, actual: moved.release, cppID: drawerAutomationNodeDragID,
                       what: "the moved gesture is still a move")
    report.expect(moved.changed, cppID: drawerAutomationNodeDragID, message: "the moved node reports a change")
    report.expectEqual(expected: 6, actual: moved.dTick, cppID: drawerAutomationNodeDragID,
                       what: "the reported delta is the grabbed node's own tick delta")
    report.expectEqual(expected: AutomationLanePoint(tick: 30, value: 80), actual: plainPress.targets[0].current,
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
    report.expectEqual(expected: AutomationPointRelease.move, actual: groupFinish.release,
                       cppID: drawerAutomationNodeDragID, what: "the selection releases as a move")
    report.expect(groupFinish.changed, cppID: drawerAutomationNodeDragID,
                  message: "the moved selection reports a change")
    report.expectEqual(expected: 6, actual: groupFinish.dTick, cppID: drawerAutomationNodeDragID,
                       what: "the shared delta is the grabbed node's delta")
    report.expect(groupFinish.selectionDrag, cppID: drawerAutomationNodeDragID,
                  message: "the finish reports that the whole selection moved")
    report.expectEqual(expected: ["30:70", "54:90"], actual: group.targets.map { "\($0.current.tick):\($0.current.value)" },
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
    report.expectEqual(expected: ["0:60", "24:80"], actual: edge.targets.map { "\($0.current.tick):\($0.current.value)" },
                       cppID: drawerAutomationNodeDragID,
                       what: "a leftward drag clamps at tick zero without collapsing the group")
    report.expectEqual(expected: -24, actual: edge.finish().dTick, cppID: drawerAutomationNodeDragID,
                       what: "the clamped delta is what the finish reports")
    report.expectEqual(expected: AutomationPointRelease.move, actual: edge.finish().release,
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
    report.expectEqual(expected: 80, actual: locked.targets[0].current.value, cppID: drawerAutomationNodeDragID,
                       what: "a time lock keeps the original value")
    report.expectEqual(expected: Tick(60), actual: locked.targets[0].current.tick, cppID: drawerAutomationNodeDragID,
                       what: "a time lock keeps the mapped tick")

    // A phantom drag restores its source on reset and clamps into the domain.
    var phantom = AutomationPhantomDragTransaction(facts: facts, source: sources[0],
                                                   press: (100, 100))
    report.expectEqual(expected: AutomationAxisLock.value, actual: phantom.update(AutomationPointDrag.Update(phase: .reset, effectiveX: 100,
                                                                 effectiveY: 100, axisLock: .none),
                                      mappedValue: 127),
                       cppID: drawerAutomationNodeDragID, what: "a phantom drag only ever locks the value axis")
    report.expectEqual(expected: AutomationLanePoint(tick: 24, value: 60), actual: phantom.target.current,
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
    report.expectEqual(expected: phantomTarget.original.tick, actual: phantomTarget.current.tick, cppID: drawerAutomationNodeDragID,
                       what: "a phantom drag never moves in time")
    report.expectEqual(expected: 127, actual: phantomTarget.current.value, cppID: drawerAutomationNodeDragID,
                       what: "a phantom drag clamps into the lane's domain")
    report.expectEqual(expected: Tick(24), actual: phantom.move?.sourceTick ?? 0, cppID: drawerAutomationNodeDragID,
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
    report.expectEqual(expected: ["48:90", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationNodeDragID,
                       what: "the node lands on its destination and evicts the occupant there")
    report.expectEqual(expected: beforeCommit.revision + 1, actual: fixture.document.revision, cppID: drawerAutomationNodeDragID,
                       what: "one drag is one revision")
    report.expect(fixture.undo(), cppID: drawerAutomationNodeDragID, message: "the drag is undoable")
    report.expectEqual(expected: ["24:60", "48:80", "120:40"], actual: fixture.values(fixture.panLane),
                       cppID: drawerAutomationNodeDragID,
                       what: "one undo restores the moved node and the evicted occupant")

    // A write on the projected engine node promotes it into a written event.
    let promotion = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    let promotionFacts = promotion.facts(promotion.panLane)
    report.expectEqual(expected: ["0:64"], actual: promotion.laneValues(promotionFacts.displayPoints), cppID: drawerAutomationNodeDragID,
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
    report.expectEqual(expected: ["0:20"], actual: promotion.values(promotion.panLane), cppID: drawerAutomationNodeDragID,
                       what: "the projected node becomes a written event at its own tick")
    report.expect(promotion.undo() && promotion.values(promotion.panLane).isEmpty, cppID: drawerAutomationNodeDragID,
                  message: "one undo returns the lane to its projected node alone")
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
    report.expectEqual(expected: beforeMove, actual: fx.document.state, cppID: id,
                       what: "one undo restores all four written Pan occurrences")
    let redone = try await fx.session.redo()
    report.expect(redone, cppID: id, message: "awaited redo completes")
    report.expectEqual(expected: moved, actual: fx.document.state, cppID: id, what: "redo restores the node value move")
    _ = try await fx.session.undo()
    _ = try await fx.session.undo()
    report.expectEqual(expected: firstWrite, actual: fx.document.state, cppID: id,
                       what: "only a second undo removes the preceding Pan sweep")
}

let drawerAutomationContractParityID = "swiftcore/AutomationPage::gestureContractParity"

@MainActor
func drawerAutomationGestureContractParity(_ report: CheckReport, suite: DocumentSession,
                                           service: ProjectService) {
    let emptyLane = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    let emptyFacts = emptyLane.facts(emptyLane.panLane)
    report.expectEqual(expected: ["0:64"], actual: emptyLane.laneValues(emptyFacts.displayPoints),
                       cppID: drawerAutomationContractParityID,
                       what: "an empty lane displays its projected engine node")
    report.expect(emptyFacts.snapshot.leadInValue == nil, cppID: drawerAutomationContractParityID,
                  message: "an empty lane carries no written lead-in")
    let emptyModulationFacts = emptyLane.facts(emptyLane.modulationLane)
    report.expectEqual(expected: 0, actual: emptyModulationFacts.snapshot.leadInValue ?? -1,
                       cppID: drawerAutomationContractParityID,
                       what: "an unwritten Modulation lane leads in on its engine default")
    let metadata = AutomationParameterMetadata(parameter: emptyLane.panLane)
    report.expectEqual(expected: "Pan (PAN)", actual: AutomationCatalog.title(emptyLane.panLane),
                       cppID: drawerAutomationContractParityID, what: "the catalog titles a CC lane")
    report.expectEqual(expected: "Tempo (BPM)", actual: AutomationCatalog.title(.tempo),
                       cppID: drawerAutomationContractParityID, what: "the catalog titles Tempo")
    report.expectEqual(expected: "Pitch bend (BEND)", actual: AutomationCatalog.title(emptyLane.bendLane),
                       cppID: drawerAutomationContractParityID, what: "the catalog titles bend")
    report.expectEqual(expected: 0, actual: metadata.minimum, cppID: drawerAutomationContractParityID,
                       what: "a CC lane bottoms at zero")
    report.expectEqual(expected: 127, actual: metadata.maximum, cppID: drawerAutomationContractParityID,
                       what: "a CC lane tops at 127")
    report.expectEqual(expected: "150", actual: AutomationParameterMetadata(parameter: .tempo).valueText(150),
                       cppID: drawerAutomationContractParityID, what: "Tempo formats raw BPM")
    report.expectEqual(expected: "c_v+0", actual: metadata.valueText(64), cppID: drawerAutomationContractParityID,
                       what: "the neutral value formats through its own metadata")
    let band = AutomationTimeSelection(range: TimeRange(startTick: 50, endTick: 100), scope: .lanes,
                                       lanes: [emptyLane.panLane])
    report.expectEqual(expected: Tick(50), actual: band.range.startTick, cppID: drawerAutomationContractParityID,
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
    report.expectEqual(expected: ["96:10", "96:20"], actual: sameTick.values(sameTick.panLane),
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
    report.expectEqual(expected: ["48:80", "96:60"], actual: moved.values(moved.panLane),
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
    report.expectEqual(expected: ["96:80"], actual: moved.values(moved.panLane),
                       cppID: drawerAutomationContractParityID,
                       what: "a move onto an occupied tick evicts its occupant")
    report.expectEqual(expected: moveBefore.revision + 2, actual: moved.document.revision,
                       cppID: drawerAutomationContractParityID, what: "two hops are two revisions")
    report.expect(moved.undo(), cppID: drawerAutomationContractParityID, message: "the hops are undoable")
    report.expectEqual(expected: ["48:80", "96:60"], actual: moved.values(moved.panLane),
                       cppID: drawerAutomationContractParityID, what: "one undo restores the evicted occupant")
    let unknownFacts = moved.facts(moved.panLane)
    report.expect(AutomationNodeResolver.moves([.init(unknownFacts, [
        AutomationNodeMove(parameter: moved.panLane, sourceTick: 9999, tick: 100, value: 60),
    ])]) == nil, cppID: drawerAutomationContractParityID,
                  message: "a move from an unknown tick resolves to nothing")
    report.expectEqual(expected: moved.snapshot, actual: DocumentSnapshot(moved.document),
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
    report.expectEqual(expected: preservedUs, actual: tempo.document.state.tempo.first(where: { $0.tick == 48 })?
        .microsecondsPerQuarterNote ?? 0, cppID: drawerAutomationContractParityID,
                       what: "an unchanged-value tempo move preserves its microseconds")
    report.expectEqual(expected: tempoBefore.revision + 1, actual: tempo.document.revision,
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
    report.expectEqual(expected: fractionalBefore.revision + 1, actual: fractional.document.revision,
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
    report.expectEqual(expected: Tick(24), actual: verticalDrag.targets[0].current.tick,
                       cppID: drawerAutomationContractParityID,
                       what: "a value lock keeps the original tick")
    let lanes = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                  pan: [(24, 60)], modulation: [(48, 10)],
                                                  tempo: [(0, 500_000)])
    lanes.activate(lanes.panLane)
    lanes.page.selectRange(from: 0, to: 96, lanes: [lanes.panLane, lanes.modulationLane])
    let lanesBefore = lanes.snapshot
    report.expectEqual(expected: TimeRange(startTick: 0, endTick: 96), actual: lanes.page.selection?.range,
                       cppID: drawerAutomationContractParityID,
                       what: "a right-drag band publishes its shared time selection")
    report.expect(lanes.page.consumeSelectionCommand(command: .delete),
                  cppID: drawerAutomationContractParityID, message: "the mixed delete consumes its selection")
    report.expect(lanes.values(lanes.panLane).isEmpty && lanes.values(lanes.modulationLane).isEmpty,
                  cppID: drawerAutomationContractParityID,
                  message: "a mixed delete clears every covered lane")
    report.expectEqual(expected: ["0:120"], actual: lanes.tempoValues, cppID: drawerAutomationContractParityID,
                       what: "a CC range edit preserves Tempo")
    report.expectEqual(expected: lanesBefore.revision + 1, actual: lanes.document.revision,
                       cppID: drawerAutomationContractParityID, what: "one mixed delete is one revision")
    report.expect(lanes.undo(), cppID: drawerAutomationContractParityID, message: "the mixed delete is undoable")
    report.expectEqual(expected: ["24:60"], actual: lanes.values(lanes.panLane), cppID: drawerAutomationContractParityID,
                       what: "one undo restores the mixed delete's lanes")
    report.expectEqual(expected: ["48:10"], actual: lanes.values(lanes.modulationLane), cppID: drawerAutomationContractParityID,
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
    report.expectEqual(expected: cancelRevision, actual: cancel.snapshot, cppID: drawerAutomationContractParityID,
                       what: "an escape writes nothing")
    report.expect(cancel.drag(cancel.panLane, from: (24, 60), to: 70,
                              modifiers: AutomationQtModifier.alt),
                  cppID: drawerAutomationContractParityID, message: "input recovers after a cancellation")
    report.expectEqual(expected: ["24:70"], actual: cancel.values(cancel.panLane), cppID: drawerAutomationContractParityID,
                       what: "the recovered drag commits its move")
}
