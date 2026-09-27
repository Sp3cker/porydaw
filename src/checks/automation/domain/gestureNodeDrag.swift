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
                                                       tempo: [(96, 499_999), (288, 545_455)])
    let fractionalFacts = fractional.facts(.tempo)
    guard let fractionalPlan = AutomationNodeResolver.moves([.init(fractionalFacts, [
        AutomationNodeMove(parameter: .tempo, sourceTick: 96, tick: 192, value: 120),
    ])]) else {
        report.fail(drawerAutomationContractParityID, "the fractional tempo drag resolved no plan")
        return
    }
    let fractionalBefore = fractional.snapshot
    let fractionalBytes = try! fractional.document.captureSave().bytes
    let fractionalIndex = fractional.document.history.undoIndex
    let fractionalCount = fractional.document.history.undoCount
    report.expect(AutomationCommit.apply(fractionalPlan, in: fractional.document),
                  cppID: drawerAutomationContractParityID, message: "a fractional tempo drag commits one edit")
    report.expectEqual(expected: fractionalBefore.revision + 1, actual: fractional.document.revision,
                       cppID: drawerAutomationContractParityID, what: "one fractional drag is one revision")
    report.expect(fractional.document.state.tempo.map { ($0.tick, $0.microsecondsPerQuarterNote) }
                  .elementsEqual([(Tick(192), UInt32(499_999)), (Tick(288), UInt32(545_455))],
                                 by: { $0 == $1 }),
                  cppID: drawerAutomationContractParityID,
                  message: "the free-tick Tempo drag preserves raw fractional microseconds and its sibling")
    report.expect(fractional.document.history.undoIndex == fractionalIndex + 1,
                  cppID: drawerAutomationContractParityID,
                  message: "the fractional Tempo release advances the history index once")
    report.expect(fractional.document.history.undoCount == fractionalCount + 1,
                  cppID: drawerAutomationContractParityID,
                  message: "the fractional Tempo release appends one history entry")
    report.expect((try! fractional.document.captureSave().bytes) != fractionalBytes,
                  cppID: drawerAutomationContractParityID,
                  message: "the fractional Tempo release changes serialized full-song bytes")
    report.expect(fractional.undo(), cppID: drawerAutomationContractParityID,
                  message: "the fractional drag is undoable")
    report.expect(fractional.document.history.undoIndex == fractionalIndex
                  && (try! fractional.document.captureSave().bytes) == fractionalBytes,
                  cppID: drawerAutomationContractParityID,
                  message: "undo of fractional Tempo restores the captured full-song bytes and history index")
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
    for parameter in [AutomationParameter.tempo, vertical.panLane] {
        let bandFixture = drawerAutomationAutomationFixture(suite: suite, service: service,
            pan: [(96, 60), (288, 40)], tempo: [(96, 600_000), (288, 500_000)])
        bandFixture.activate(parameter)
        let bandBefore = bandFixture.snapshot
        let bandIndex = bandFixture.document.history.undoIndex
        let bandCount = bandFixture.document.history.undoCount
        let bandBytes = try! bandFixture.document.captureSave().bytes
        let from = bandFixture.x(96)
        let to = bandFixture.x(288)
        let y = bandFixture.y(parameter, parameter == .tempo ? 100 : 60)
        report.expect(bandFixture.page.pointerPress(x: from, y: y, surface: 1,
                            button: AutomationQtButton.right), cppID: drawerAutomationContractParityID,
                      message: "a real right press stages the active parameter's time band")
        _ = bandFixture.page.pointerMove(x: to, y: y, buttons: AutomationQtButton.right)
        report.expect(bandFixture.page.bandVisible && bandFixture.page.interactionActive,
                      cppID: drawerAutomationContractParityID,
                      message: "the held right drag visibly stages its time band before release")
        _ = bandFixture.page.pointerRelease(x: to, y: y, button: AutomationQtButton.right)
        let selected = bandFixture.page.selection
        report.expect(selected?.isActive == true && selected?.scope == .lanes
                      && selected?.tempo == parameter.isTempo
                      && selected?.lanes == (parameter.isTempo ? [] : [parameter])
                      && selected?.range == TimeRange(startTick: 96, endTick: 288),
                      cppID: drawerAutomationContractParityID,
                      message: "right-band release selects the snapped range in only its active lane or Tempo")
        report.expect(!bandFixture.page.bandVisible && !bandFixture.page.interactionActive
                      && bandFixture.snapshot == bandBefore
                      && bandFixture.document.history.undoIndex == bandIndex
                      && bandFixture.document.history.undoCount == bandCount
                      && (try! bandFixture.document.captureSave().bytes) == bandBytes,
                      cppID: drawerAutomationContractParityID,
                      message: "right-band selection retires its preview without editing the full song or history")
    }
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
    drawerAutomationExactNodeContract(report, suite: suite, service: service)
}

@MainActor
func drawerAutomationExactNodeContract(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let id = drawerAutomationContractParityID
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
        pan: [(0, 64), (96, 10), (96, 20), (192, 70), (192, 80), (288, 40)],
        tempo: [(96, 499_999), (288, 545_455)])
    let document = fixture.document
    let tempoMetadata = AutomationParameterMetadata(parameter: .tempo)
    let ccMetadata = AutomationParameterMetadata(parameter: fixture.panLane)
    let bendMetadata = AutomationParameterMetadata(parameter: fixture.bendLane)
    report.expect(tempoMetadata.minimum == TimeDefaults.minimumTempoBPM
                  && tempoMetadata.maximum == TimeDefaults.maximumTempoBPM, cppID: id,
                  message: "Tempo bounds expose the exact supported BPM interval")
    report.expectEqual(expected: "120", actual: tempoMetadata.valueText(120), cppID: id,
                       what: "Tempo formats a whole BPM without losing digits")
    report.expectEqual(expected: ["96:120", "288:110"], actual: fixture.tempoValues, cppID: id,
                       what: "fractional Tempo projects its displayed node value")
    report.expect(ccMetadata.valueText(64) == "c_v+0" && ccMetadata.valueText(0) == "c_v-64",
                  cppID: id, message: "CC text formats both neutral and zero")
    report.expect(bendMetadata.minimum == TimeDefaults.minimumBendValue
                  && bendMetadata.maximum == TimeDefaults.maximumBendValue
                  && bendMetadata.valueText(0) == "0"
                  && bendMetadata.valueText(100) == "+100", cppID: id,
                  message: "bend bounds and zero and hundred text retain their domain")
    let covered = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .lanes,
        lanes: [fixture.panLane])
    let uncovered = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .lanes,
        lanes: [.tempo], tempo: true)
    report.expect(covered.isActive && covered.range == uncovered.range
                  && covered.covers(fixture.panLane, usedTracks: [0]), cppID: id,
                  message: "covered lane reports the complete 50 to 150 interval")
    report.expect(uncovered.isActive && !uncovered.covers(fixture.panLane, usedTracks: [0]),
                  cppID: id, message: "uncovered lane keeps the interval without coverage")
    let allTracks = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .tracks([0, 1]))
    let oneTrack = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .tracks([0]))
    report.expect(allTracks.covers(.tempo, usedTracks: [0, 1])
                  && allTracks.coversTempo(usedTracks: [0, 1]), cppID: id,
                  message: "all-used-track ruler range covers its Tempo lane")
    report.expect(!oneTrack.covers(.tempo, usedTracks: [0, 1])
                  && oneTrack.covers(fixture.panLane, usedTracks: [0]), cppID: id,
                  message: "partial-track ruler range excludes Tempo but covers its own Pan")
    fixture.page.selectRange(from: 50, to: 150, lanes: [fixture.panLane])
    fixture.page.clearTimeSelection()
    report.expect(fixture.page.selection?.isActive != true
                  && fixture.page.selection?.covers(fixture.panLane, usedTracks: [0]) != true,
                  cppID: id, message: "cleared range is inactive and cannot cover its former lane")
    let emptyTempo = drawerAutomationAutomationFixture(suite: suite, service: service, tempo: [])
    report.expect(emptyTempo.laneSnapshot(.tempo).displaySeries.isEmpty, cppID: id,
                  message: "empty Tempo lane displays no written nodes")
    report.expect(fixture.laneSnapshot(fixture.modulationLane).displaySeries.isEmpty
                  && fixture.laneSnapshot(fixture.modulationLane).leadInValue == 0, cppID: id,
                  message: "empty modulation lane has no displayed nodes but retains its lead-in")

    let before = fixture.snapshot
    let bytes = try! document.captureSave().bytes
    let index = document.history.undoIndex
    let emptyMoves = AutomationNodeResolver.moves([.init(fixture.facts(.tempo), [])])
    report.expect(emptyMoves?.isEmpty == true
                  && !(emptyMoves.map { AutomationCommit.apply($0, in: document) } ?? false)
                  && fixture.snapshot == before && document.history.undoIndex == index
                  && (try! document.captureSave().bytes) == bytes, cppID: id,
                  message: "empty Tempo move leaves bytes revision and undo index intact")
    let unknownTempo = AutomationNodeResolver.moves([.init(fixture.facts(.tempo), [
        AutomationNodeMove(parameter: .tempo, sourceTick: 99999, tick: 192, value: 120),
    ])])
    report.expect(unknownTempo == nil && fixture.snapshot == before
                  && document.history.undoIndex == index
                  && (try! document.captureSave().bytes) == bytes, cppID: id,
                  message: "unknown Tempo move leaves bytes revision and undo index intact")
    let emptyDelete = AutomationNodeResolver.deletions(revision: document.revision, [])
    report.expect(emptyDelete?.isEmpty == true
                  && !(emptyDelete.map { AutomationCommit.apply($0, in: document) } ?? false)
                  && fixture.snapshot == before && document.history.undoIndex == index
                  && (try! document.captureSave().bytes) == bytes, cppID: id,
                  message: "empty Delete leaves bytes revision and undo index intact")
    report.expect(AutomationNodeResolver.deletions(revision: document.revision, [.init(
        parameter: .tempo, snapshot: fixture.laneSnapshot(.tempo), ticks: [99999])]) == nil
                  && fixture.snapshot == before && document.history.undoIndex == index
                  && (try! document.captureSave().bytes) == bytes, cppID: id,
                  message: "unknown Tempo Delete leaves bytes revision and undo index intact")

    let ccBefore = fixture.snapshot
    let ccBytes = try! document.captureSave().bytes
    let ccIndex = document.history.undoIndex
    let emptyCc = AutomationNodeResolver.moves([.init(fixture.facts(fixture.panLane), [])])
    report.expect(emptyCc?.isEmpty == true
                  && !(emptyCc.map { AutomationCommit.apply($0, in: document) } ?? false)
                  && fixture.snapshot == ccBefore && document.history.undoIndex == ccIndex
                  && (try! document.captureSave().bytes) == ccBytes, cppID: id,
                  message: "empty CC move preserves the complete document snapshot")
    report.expect(AutomationNodeResolver.moves([.init(fixture.facts(fixture.panLane), [
        AutomationNodeMove(parameter: fixture.panLane, sourceTick: 99999, tick: 192, value: 20),
    ])]) == nil && fixture.snapshot == ccBefore && document.history.undoIndex == ccIndex
                  && (try! document.captureSave().bytes) == ccBytes, cppID: id,
                  message: "unknown CC move preserves bytes and history")
    report.expect(AutomationNodeResolver.deletions(revision: document.revision, [.init(
        parameter: fixture.panLane, snapshot: fixture.laneSnapshot(fixture.panLane),
        ticks: [99999])]) == nil && fixture.snapshot == ccBefore
                  && document.history.undoIndex == ccIndex
                  && (try! document.captureSave().bytes) == ccBytes, cppID: id,
                  message: "unknown CC Delete preserves bytes and history")

    guard let ccMove = AutomationNodeResolver.moves([.init(fixture.facts(fixture.panLane), [
        AutomationNodeMove(parameter: fixture.panLane, sourceTick: 96, tick: 192, value: 20),
    ])]) else { report.fail(id, "same-tick collision needs a resolved CC move"); return }
    report.expect(AutomationCommit.apply(ccMove, in: document)
                  && document.revision == ccBefore.revision + 1
                  && document.history.undoIndex == ccIndex + 1, cppID: id,
                  message: "same-tick collision commits exactly one CC edit")
    report.expect(fixture.values(fixture.panLane) == ["0:64", "192:10", "192:20", "288:40"],
                  cppID: id, message: "collision evicts the destination group without reordering surviving CC events")
    report.expect(fixture.playbackValues(fixture.panLane, at: 96).isEmpty
                  && fixture.playbackValues(fixture.panLane, at: 192) == [10, 20], cppID: id,
                  message: "collision vacates source and writes both raw Pan occupants in order")
    let committedBytes = try! document.captureSave().bytes
    report.expect(fixture.undo() && document.history.undoIndex == ccIndex
                  && (try! document.captureSave().bytes) == ccBytes
                  && fixture.values(fixture.panLane) ==
                      ["0:64", "96:10", "96:20", "192:70", "192:80", "288:40"],
                  cppID: id, message: "CC collision undo restores index bytes and every original point")
    let ccRedo = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(ccRedo && document.history.undoIndex == ccIndex + 1
                  && (try! document.captureSave().bytes) == committedBytes
                  && fixture.values(fixture.panLane) == ["0:64", "192:10", "192:20", "288:40"],
                  cppID: id, message: "CC collision redo restores committed index bytes and points")

    let tempoBefore = fixture.snapshot
    let tempoBytes = try! document.captureSave().bytes
    let tempoIndex = document.history.undoIndex
    guard let tempoMove = AutomationNodeResolver.moves([.init(fixture.facts(.tempo), [
        AutomationNodeMove(parameter: .tempo, sourceTick: 96, tick: 288, value: 120),
    ])]) else { report.fail(id, "fractional Tempo collision needs a resolved move"); return }
    report.expect(AutomationCommit.apply(tempoMove, in: document)
                  && document.revision == tempoBefore.revision + 1
                  && document.history.undoIndex == tempoIndex + 1, cppID: id,
                  message: "fractional Tempo collision commits exactly one edit")
    report.expect(document.state.tempo.count == 1
                  && document.state.tempo[0].tick == 288
                  && document.state.tempo[0].microsecondsPerQuarterNote == 499_999, cppID: id,
                  message: "fractional Tempo collision evicts occupant but preserves 499999 microseconds")
    let tempoCommitted = try! document.captureSave().bytes
    report.expect(fixture.undo() && document.history.undoIndex == tempoIndex
                  && (try! document.captureSave().bytes) == tempoBytes
                  && fixture.tempoValues == ["96:120", "288:110"], cppID: id,
                  message: "Tempo collision undo restores index bytes and both source points")
    let tempoRedo = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(tempoRedo && document.history.undoIndex == tempoIndex + 1
                  && (try! document.captureSave().bytes) == tempoCommitted
                  && fixture.tempoValues == ["288:120"], cppID: id,
                  message: "Tempo collision redo restores index bytes and sole destination")
    let fractional = drawerAutomationAutomationFixture(suite: suite, service: service,
        tempo: [(0, 500_000), (96, 398_406)])
    report.expect(fractional.document.state.tempo.first(where: { $0.tick == 96 })?
                      .microsecondsPerQuarterNote == 398_406, cppID: id,
                  message: "398406-us Tempo node retains exact fractional raw timing")
    let tempoNodes = fractional.laneSnapshot(.tempo).displaySeries
    report.expect(tempoNodes.map { "\($0.tick):\($0.value)" } == ["0:120", "96:151"]
                  && tempoNodes.allSatisfy { !$0.projected }, cppID: id,
                  message: "398406-us Tempo lane displays both actual nodes including rounded 151 BPM")
    let displayedFraction = tempoNodes.first(where: { $0.tick == 96 && !$0.projected })?.value
    report.expect(displayedFraction.map(tempoMetadata.valueText) == "151", cppID: id,
                  message: "fractional Tempo lane value formats its full 151 BPM text")
    let changedDocument = fractional.document
    let changedBefore = fractional.snapshot
    let changedBytes = try! changedDocument.captureSave().bytes
    let changedIndex = changedDocument.history.undoIndex
    guard let changedMove = AutomationNodeResolver.moves([.init(fractional.facts(.tempo), [
        AutomationNodeMove(parameter: .tempo, sourceTick: 96, tick: 192, value: 140),
    ])]) else { report.fail(id, "changed fractional Tempo needs a resolved move"); return }
    report.expect(AutomationCommit.apply(changedMove, in: changedDocument)
                  && changedDocument.revision == changedBefore.revision + 1
                  && changedDocument.history.undoIndex == changedIndex + 1, cppID: id,
                  message: "changing fractional Tempo tick and value commits exactly one edit")
    report.expect(changedDocument.state.tempo.first(where: { $0.tick == 96 }) == nil
                  && changedDocument.state.tempo.first(where: { $0.tick == 192 })?
                      .microsecondsPerQuarterNote ==
                      TimeDefaults.microsecondsPerQuarterNote(forBPM: 140)
                  && fractional.tempoValues == ["0:120", "192:140"], cppID: id,
                  message: "changing fractional Tempo to 140 vacates source and recomputes destination")
    let changedCommitted = try! changedDocument.captureSave().bytes
    report.expect(fractional.undo() && changedDocument.history.undoIndex == changedIndex
                  && (try! changedDocument.captureSave().bytes) == changedBytes
                  && fractional.tempoValues == ["0:120", "96:151"], cppID: id,
                  message: "changed Tempo move undo restores original index bytes and fractional point")
    let changedRedo = (try? runBlocking { try await fractional.session.redo() }) ?? false
    report.expect(changedRedo && changedDocument.history.undoIndex == changedIndex + 1
                  && (try! changedDocument.captureSave().bytes) == changedCommitted
                  && fractional.tempoValues == ["0:120", "192:140"], cppID: id,
                  message: "changed Tempo move redo restores committed index bytes and destination")

    let deleting = drawerAutomationAutomationFixture(suite: suite, service: service,
        pan: [(0, 64), (96, 10), (96, 20), (288, 40)],
        tempo: [(0, 500_000), (96, 499_999), (288, 545_455)])
    let deleteDocument = deleting.document
    let deleteBefore = deleting.snapshot
    let deleteBytes = try! deleteDocument.captureSave().bytes
    let deleteIndex = deleteDocument.history.undoIndex
    guard let deletion = AutomationNodeResolver.deletions(
        revision: deleteDocument.revision, [
            .init(parameter: .tempo, snapshot: deleting.laneSnapshot(.tempo), ticks: [96]),
            .init(parameter: deleting.panLane, snapshot: deleting.laneSnapshot(deleting.panLane),
                  ticks: [96]),
        ]) else { report.fail(id, "mixed node Delete needs a resolved plan"); return }
    report.expect(AutomationCommit.apply(deletion, in: deleteDocument)
                  && deleteDocument.revision == deleteBefore.revision + 1
                  && deleteDocument.history.undoIndex == deleteIndex + 1, cppID: id,
                  message: "mixed node Delete commits one revision and one applied undo entry")
    report.expect(deleting.values(deleting.panLane) == ["0:64", "288:40"]
                  && deleting.playbackValues(deleting.panLane, at: 96).isEmpty, cppID: id,
                  message: "CC node Delete removes its entire same-tick raw group without touching siblings")
    report.expect(deleting.tempoValues == ["0:120", "288:110"], cppID: id,
                  message: "mixed node Delete removes only the named Tempo occurrence")
    let deletedBytes = try! deleteDocument.captureSave().bytes
    report.expect(deleting.undo() && deleteDocument.history.undoIndex == deleteIndex
                  && (try! deleteDocument.captureSave().bytes) == deleteBytes
                  && deleting.values(deleting.panLane) == ["0:64", "96:10", "96:20", "288:40"]
                  && deleting.tempoValues == ["0:120", "96:120", "288:110"], cppID: id,
                  message: "mixed node Delete undo restores prior index bytes Tempo and CC points")
    let deleteRedo = (try? runBlocking { try await deleting.session.redo() }) ?? false
    report.expect(deleteRedo && deleteDocument.history.undoIndex == deleteIndex + 1
                  && (try! deleteDocument.captureSave().bytes) == deletedBytes
                  && deleting.values(deleting.panLane) == ["0:64", "288:40"]
                  && deleting.tempoValues == ["0:120", "288:110"], cppID: id,
                  message: "mixed node Delete redo restores committed index bytes and points")
}
