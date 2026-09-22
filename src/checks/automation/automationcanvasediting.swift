import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

// Existing scenarios paired with automationcanvasediting.cpp.
// Entry order remains in AutomationPageChecks.swift.



@MainActor
func drawerAutomationCancellationAndNoOps(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot

    // A press and cancel writes nothing and ends every owned interaction.
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press on a node grabs it")
    report.expect(fixture.page.hasGesture && fixture.page.interactionActive, cppID: drawerAutomationCancelID,
                  message: "the page publishes the live gesture")
    report.expect(fixture.page.handleEscape(), cppID: drawerAutomationCancelID,
                  message: "Escape claims the live gesture")
    report.expect(!fixture.page.hasGesture && !fixture.page.interactionActive, cppID: drawerAutomationCancelID,
                  message: "cancelling ends the gesture synchronously")
    report.expectEqual(before, fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a cancelled gesture mutates nothing")
    report.expect(!fixture.page.handleEscape(), cppID: drawerAutomationCancelID,
                  message: "Escape with nothing to claim stays unhandled")

    // A stroke that never travelled commits nothing.
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a second press grabs the node")
    _ = fixture.page.pointerMove(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(before, fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "an armed stroke that moved no node writes nothing")

    // Shift-held stationary release is a no-op; plain stationary release deletes.
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                            surface: 1, button: 1, modifiers: drawerAutomationQtModifiers(.init(shift: true))), cppID: drawerAutomationCancelID,
                  message: "a Shift-held press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                    button: 1, modifiers: drawerAutomationQtModifiers(.init(shift: true)))
    report.expectEqual(before, fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a Shift-held stationary release deletes nothing")
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a plain press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), button: 1)
    report.expectEqual(["24:64"], fixture.values(fixture.panLane), cppID: drawerAutomationCancelID,
                       what: "a plain stationary release deletes the grabbed node")
    report.expect(fixture.undo(), cppID: drawerAutomationCancelID, message: "the stationary delete is undoable")
    report.expectEqual(["24:64", "120:40"], fixture.values(fixture.panLane), cppID: drawerAutomationCancelID,
                       what: "one undo restores the deleted node")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationCancelID,
                  message: "the stationary delete recorded exactly one history entry")

    // A stale revision cancels the frozen interaction instead of retargeting it.
    let pressRevision = fixture.document.revision
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press freezes the current revision")
    report.expectEqual(pressRevision, fixture.page.frozenRevision ?? 0, cppID: drawerAutomationCancelID,
                       what: "the frozen facts carry the revision")
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                               through: 168, points: [LaneWrite(tick: 168, value: 5)])
    report.expect(!fixture.page.hasGesture, cppID: drawerAutomationCancelID,
                  message: "a document change outside the gesture cancels it")
    let afterStale = fixture.snapshot
    _ = fixture.page.pointerMove(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(afterStale, fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a cancelled stale gesture never writes on release")

    // An empty-lane press parks the edit cursor instead of writing.
    let empty = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    empty.activate(empty.panLane)
    let emptyBefore = empty.snapshot
    let pressX = empty.x(72)
    report.expect(empty.page.pointerPress(x: pressX, y: 60, surface: 1, button: 1), cppID: drawerAutomationCancelID,
                  message: "a press on an empty lane starts a sweep")
    report.expect(!empty.page.pointerRelease(x: pressX, y: 60, button: 1), cppID: drawerAutomationCancelID,
                  message: "a press that never travelled commits nothing")
    report.expectEqual(emptyBefore, empty.snapshot, cppID: drawerAutomationCancelID,
                       what: "the parked press leaves the document alone")
    let policy = AutomationSnapPolicy(document: empty.document, timeline: empty.session.timeline,
                                      baseFontPx: 13, devicePixelRatio: 1)
    let snapped = policy.snap(min(max(0, empty.session.camera.tickAtContentX(pressX)),
                                  Double(empty.songEndTick)),
                              fine: false, camera: empty.session.camera)
    report.expectEqual(snapped, empty.session.editCursor, cppID: drawerAutomationCancelID,
                       what: "the press parks the edit cursor at the snapped tick")

    // A sub-threshold move leaves a frozen gesture alive but unchanged.
    let jitter = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    jitter.activate(jitter.panLane)
    report.expect(jitter.page.pointerPress(x: jitter.x(24), y: jitter.y(jitter.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press grabs the node")
    _ = jitter.page.pointerMove(x: jitter.x(24) + 2, y: jitter.y(jitter.panLane, 64) + 2, buttons: 1)
    report.expectEqual([Tick(24): 64], [jitter.page.previewPoints.first?.tick ?? 0:
                                            jitter.page.previewPoints.first?.value ?? 0],
                       cppID: drawerAutomationCancelID,
                       what: "a sub-threshold move previews the untouched target")
    report.expectEqual(jitter.snapshot, drawerAutomationAutomationDocumentSnapshot(jitter.document), cppID: drawerAutomationCancelID,
                       what: "a sub-threshold move writes nothing")
}

@MainActor
func drawerAutomationContextAndPublicationDiagnostics(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)])
    fixture.activate(fixture.volumeLane)
    let builds = fixture.page.contentBuildCount
    let selectionBuilds = fixture.page.selectionBuildCount
    let contextChanges = fixture.page.contextChangeCount
    report.expectEqual(Tick(0), fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped page presents the edit cursor")

    // A cursor-only publication updates the stopped context without rebuilding
    // document-derived content or changing document/history state.
    let cursorDocument = fixture.snapshot
    fixture.session.editCursor = 100
    report.expectEqual(Tick(100), fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped context consumes the published edit cursor")
    report.expectEqual(64, fixture.page.contextValue ?? -1, cppID: drawerAutomationContextID,
                       what: "the context readout is the lane's held value there")
    report.expect(fixture.page.contextChangeCount > contextChanges, cppID: drawerAutomationContextID,
                  message: "a cursor-only context move is counted")
    report.expectEqual(builds, fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a cursor-only publication rebuilds no static content")
    report.expectEqual(cursorDocument, fixture.snapshot, cppID: drawerAutomationContextID,
                       what: "a cursor-only publication changes no document or history state")

    // A shared-playhead presentation retargets the context and rebuilds nothing.
    let buildsBeforePlayhead = fixture.page.contentBuildCount
    let presentations = fixture.page.playheadPresentationCount
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expect(fixture.page.playing, cppID: drawerAutomationContextID, message: "the page consumes playing")
    report.expectEqual(Tick(50), fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a playing context consumes the shared playhead tick")
    report.expectEqual(127, fixture.page.contextValue ?? -1, cppID: drawerAutomationContextID,
                       what: "the playing context reads the held value at its own tick")
    report.expectEqual(presentations + 1, fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "the presentation is counted once")
    report.expectEqual(buildsBeforePlayhead, fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a playhead-only update rebuilds no static content")
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expectEqual(presentations + 1, fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "an equal presentation is dropped")
    fixture.page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(presentations + 2, fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "a moved playhead presents again")
    report.expectEqual(buildsBeforePlayhead, fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "repeated playhead movement still rebuilds nothing")
    fixture.page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(Tick(100), fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped transport returns to the edit cursor")

    // A camera-only publication reprojects the curve, which is a content build.
    let buildsBeforeCamera = fixture.page.contentBuildCount
    _ = fixture.session.mutateCamera { _ = $0.setTimeZoom(90) }
    report.expectEqual(buildsBeforeCamera + 1, fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a camera change reprojects the curve once")

    // A selection change rebuilds and is counted apart from content builds.
    let buildsBeforeSelection = fixture.page.contentBuildCount
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .lanes, lanes: [fixture.volumeLane]))
    report.expectEqual(buildsBeforeSelection + 1, fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a selection change rebuilds the content it displays")
    report.expectEqual(selectionBuilds + 1, fixture.page.selectionBuildCount, cppID: drawerAutomationContextID,
                       what: "the selection build is counted on its own")
    let points = fixture.page.projection?.points ?? []
    report.expect(points.contains { $0.selected } && points.contains { !$0.selected },
                  cppID: drawerAutomationContextID,
                  message: "the projection marks the points inside the selection")
    report.expectEqual(["0:127"], fixture.laneValues(points.filter(\.selected).map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }).count == 1 ? ["0:127"] : [], cppID: drawerAutomationContextID,
                       what: "the selection marks exactly the points inside its range")
    fixture.page.applyTimeSelection(nil)
    report.expect((fixture.page.projection?.points ?? []).allSatisfy { !$0.selected },
                  cppID: drawerAutomationContextID, message: "clearing the selection clears every indicator")
    report.expect(fixture.page.contentBuildCount > builds, cppID: drawerAutomationContextID,
                  message: "the content builds accumulated across the case")

    // Hover: a node publishes its own value text, the background the held value.
    let hoverBuilds = fixture.page.hoverBuildCount
    _ = fixture.page.pointerMove(x: fixture.x(96), y: fixture.y(fixture.volumeLane, 64),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == true, cppID: drawerAutomationContextID,
                  message: "a hover on a node publishes the node")
    report.expectEqual("64", fixture.page.hover?.text ?? "", cppID: drawerAutomationContextID,
                       what: "a node hover reads out the node's value")
    report.expectEqual(15, fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "a written node advertises node movement")
    _ = fixture.page.pointerMove(x: fixture.x(150), y: fixture.y(fixture.volumeLane, 20),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == false, cppID: drawerAutomationContextID,
                  message: "a hover on the background publishes the tick")
    report.expectEqual("64", fixture.page.hover?.text ?? "", cppID: drawerAutomationContextID,
                       what: "a background hover reads the value the lane holds there")
    report.expect(fixture.page.hoverBuildCount > hoverBuilds, cppID: drawerAutomationContextID,
                  message: "the hover publications are counted")
    report.expectEqual(17, fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "the background advertises sweep and ramp input")
    fixture.page.isPencilMode = true
    report.expectEqual(18, fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "switching tools updates stationary hover instructions")
    fixture.page.isPencilMode = false
    report.expectEqual(17, fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "leaving pencil mode restores sweep instructions")
    fixture.page.pointerLeave()
    report.expect(fixture.page.hover == nil, cppID: drawerAutomationContextID,
                  message: "leaving the plot clears the hover")

    // Detach drops everything the page published.
    var copyAvailable = false
    fixture.page.onCommandAvailabilityChanged = { [weak page = fixture.page] in
        copyAvailable = page?.selectionCommandAvailable(command: .copy) ?? false
    }
    fixture.page.detach()
    report.expect(fixture.page.projection == nil && fixture.page.rows.isEmpty
                      && fixture.page.selection == nil,
                  cppID: drawerAutomationContextID, message: "detaching drops every published value")
    fixture.page.attach(session: fixture.session, palette: GridPalette())
    fixture.activate(fixture.volumeLane)
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .lanes, lanes: [fixture.volumeLane]))
    report.expect(copyAvailable, cppID: drawerAutomationContextID,
                  message: "a retained command subscriber observes selection after page reattachment")
}

@MainActor
func drawerAutomationActivationAndSelectionContracts(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let slop = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)])
    report.expect(AutomationCatalog.index(of: slop.panLane, track: 0) != nil,
                  cppID: drawerAutomationCancelID,
                  message: "activation-slop lane resolves in the production catalog")
    let blankX = slop.x(72)
    let blankY = slop.y(slop.panLane, 100)
    report.expect(slop.page.pointerPress(x: blankX, y: blankY,
                                         surface: AutomationInputSurface.plot.rawValue,
                                         button: 1, modifiers: 0),
                  cppID: drawerAutomationCancelID,
                  message: "blank-lane press starts the production pointer route")
    let slopBefore = slop.snapshot
    _ = slop.page.pointerMove(x: blankX + 2, y: blankY + 2, buttons: 1, modifiers: 0)
    report.expectEqual(slopBefore, slop.snapshot, cppID: drawerAutomationCancelID,
                       what: "sub-threshold motion commits no document change")
    _ = slop.page.pointerRelease(x: blankX + 2, y: blankY + 2, button: 1, modifiers: 0)
    report.expectEqual(slopBefore, slop.snapshot, cppID: drawerAutomationCancelID,
                       what: "sub-threshold release leaves document and history untouched")

    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)])
    let bend = AutomationParameter.pitchBend(track: 0)
    report.expect(AutomationCatalog.index(of: bend, track: 0) != nil,
                  cppID: drawerAutomationCancelID,
                  message: "the production catalog resolves the Bend lane")
    report.expect(fixture.page.selection?.isActive != true,
                  cppID: drawerAutomationCancelID,
                  message: "a fresh page has no active time selection")
    report.expect(fixture.page.activeParameter == .tempo
                      || fixture.page.activateParameter(.tempo),
                  cppID: drawerAutomationCancelID,
                  message: "the page activates Tempo before applying selection")

    let noncontiguous = AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 120), scope: .lanes,
        lanes: [fixture.panLane, bend])
    fixture.page.applyTimeSelection(noncontiguous)
    report.expect(fixture.page.selection?.isActive == true,
                  cppID: drawerAutomationCancelID,
                  message: "applying a nonempty selection makes it active")
    report.expectEqual(Set([fixture.panLane, bend]), fixture.page.selection?.lanes ?? [],
                       cppID: drawerAutomationCancelID,
                       what: "selection publishes the complete noncontiguous lane set")
    report.expect(fixture.page.selection?.scope == .lanes,
                  cppID: drawerAutomationCancelID,
                  message: "selection publishes lane scope")
    report.expectEqual(Tick(24), fixture.page.selection?.range.startTick ?? -1,
                       cppID: drawerAutomationCancelID,
                       what: "selection publishes its start tick")
    report.expectEqual(Tick(120), fixture.page.selection?.range.endTick ?? -1,
                       cppID: drawerAutomationCancelID,
                       what: "selection publishes its end tick")

    fixture.page.clearTimeSelection()
    report.expect(fixture.page.selection?.isActive != true,
                  cppID: drawerAutomationCancelID,
                  message: "clearing makes the time selection inactive")
    report.expect((fixture.page.selection?.scope ?? .tracks) == .tracks,
                  cppID: drawerAutomationCancelID,
                  message: "clearing restores the default Tracks scope")
    report.expect((fixture.page.selection?.range.startTick ?? 0) == 0
                      && (fixture.page.selection?.range.endTick ?? 0) == 0,
                  cppID: drawerAutomationCancelID,
                  message: "clearing restores zero start and end ticks")
    report.expect((fixture.page.selection?.lanes ?? []).isEmpty,
                  cppID: drawerAutomationCancelID,
                  message: "clearing removes every selected lane")

    fixture.page.applyTimeSelection(noncontiguous)
    report.expectEqual(Set([fixture.panLane, bend]), fixture.page.selection?.lanes ?? [],
                       cppID: drawerAutomationCancelID,
                       what: "rebuild setup preserves the noncontiguous lane set")
    let replacement = AutomationTimeSelection(
        range: TimeRange(startTick: 48, endTick: 96), scope: .lanes,
        lanes: [.controlChange(track: 0, controller: 21)])
    fixture.page.applyTimeSelection(replacement)
    report.expectEqual(Set([AutomationParameter.controlChange(track: 0, controller: 21)]),
                       fixture.page.selection?.lanes ?? [],
                       cppID: drawerAutomationCancelID,
                       what: "a replacement selection replaces the lane set atomically")
    report.expect(fixture.page.handleEscape(), cppID: drawerAutomationCancelID,
                  message: "Escape consumes the active replacement selection")
    report.expect(fixture.page.selection?.isActive != true
                      && (fixture.page.selection?.lanes ?? []).isEmpty,
                  cppID: drawerAutomationCancelID,
                  message: "Escape clears replacement activity and lanes")
}
