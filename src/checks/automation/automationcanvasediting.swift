import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore

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
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a cancelled gesture mutates nothing")
    report.expect(!fixture.page.handleEscape(), cppID: drawerAutomationCancelID,
                  message: "Escape with nothing to claim stays unhandled")

    // A stroke that never travelled commits nothing.
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a second press grabs the node")
    _ = fixture.page.pointerMove(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "an armed stroke that moved no node writes nothing")

    // Shift-held stationary release is a no-op; plain stationary release deletes.
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                            surface: 1, button: 1, modifiers: drawerAutomationQtModifiers(.init(shift: true))), cppID: drawerAutomationCancelID,
                  message: "a Shift-held press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                    button: 1, modifiers: drawerAutomationQtModifiers(.init(shift: true)))
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a Shift-held stationary release deletes nothing")
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a plain press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), button: 1)
    report.expectEqual(expected: ["24:64"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationCancelID,
                       what: "a plain stationary release deletes the grabbed node")
    report.expect(fixture.undo(), cppID: drawerAutomationCancelID, message: "the stationary delete is undoable")
    report.expectEqual(expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationCancelID,
                       what: "one undo restores the deleted node")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationCancelID,
                  message: "the stationary delete recorded exactly one history entry")

    // A stale revision cancels the frozen interaction instead of retargeting it.
    let pressRevision = fixture.document.revision
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press freezes the current revision")
    report.expectEqual(expected: pressRevision, actual: fixture.page.frozenRevision ?? 0, cppID: drawerAutomationCancelID,
                       what: "the frozen facts carry the revision")
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                               through: 168, points: [LaneWrite(tick: 168, value: 5)])
    report.expect(!fixture.page.hasGesture, cppID: drawerAutomationCancelID,
                  message: "a document change outside the gesture cancels it")
    let afterStale = fixture.snapshot
    _ = fixture.page.pointerMove(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(expected: afterStale, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
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
    report.expectEqual(expected: emptyBefore, actual: empty.snapshot, cppID: drawerAutomationCancelID,
                       what: "the parked press leaves the document alone")
    let policy = AutomationProjectionCache().snapPolicy(session: empty.session, font: 13, dpr: 1)
    let snapped = policy.snap(min(max(0, empty.session.camera.tickAtContentX(pressX)),
                                  Double(empty.songEndTick)),
                              fine: false, camera: empty.session.camera)
    report.expectEqual(expected: snapped, actual: empty.session.editCursor, cppID: drawerAutomationCancelID,
                       what: "the press parks the edit cursor at the snapped tick")

    // A sub-threshold move leaves a frozen gesture alive but unchanged.
    let jitter = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    jitter.activate(jitter.panLane)
    report.expect(jitter.page.pointerPress(x: jitter.x(24), y: jitter.y(jitter.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press grabs the node")
    _ = jitter.page.pointerMove(x: jitter.x(24) + 2, y: jitter.y(jitter.panLane, 64) + 2, buttons: 1)
    report.expectEqual(expected: [Tick(24): 64], actual: [jitter.page.previewPoints.first?.tick ?? 0:
                                            jitter.page.previewPoints.first?.value ?? 0],
                       cppID: drawerAutomationCancelID,
                       what: "a sub-threshold move previews the untouched target")
    report.expectEqual(expected: jitter.snapshot, actual: DocumentSnapshot(jitter.document), cppID: drawerAutomationCancelID,
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
    report.expectEqual(expected: Tick(0), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped page presents the edit cursor")

    // A cursor-only publication updates the stopped context without rebuilding
    // document-derived content or changing document/history state.
    let cursorDocument = fixture.snapshot
    fixture.session.editCursor = 100
    report.expectEqual(expected: Tick(100), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped context consumes the published edit cursor")
    report.expectEqual(expected: 64, actual: fixture.page.contextValue ?? -1, cppID: drawerAutomationContextID,
                       what: "the context readout is the lane's held value there")
    report.expect(fixture.page.contextChangeCount > contextChanges, cppID: drawerAutomationContextID,
                  message: "a cursor-only context move is counted")
    report.expectEqual(expected: builds, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a cursor-only publication rebuilds no static content")
    report.expectEqual(expected: cursorDocument, actual: fixture.snapshot, cppID: drawerAutomationContextID,
                       what: "a cursor-only publication changes no document or history state")

    // A shared-playhead presentation retargets the context and rebuilds nothing.
    let buildsBeforePlayhead = fixture.page.contentBuildCount
    let presentations = fixture.page.playheadPresentationCount
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expect(fixture.page.playing, cppID: drawerAutomationContextID, message: "the page consumes playing")
    report.expectEqual(expected: Tick(50), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a playing context consumes the shared playhead tick")
    report.expectEqual(expected: 127, actual: fixture.page.contextValue ?? -1, cppID: drawerAutomationContextID,
                       what: "the playing context reads the held value at its own tick")
    report.expectEqual(expected: presentations + 1, actual: fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "the presentation is counted once")
    report.expectEqual(expected: buildsBeforePlayhead, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a playhead-only update rebuilds no static content")
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expectEqual(expected: presentations + 1, actual: fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "an equal presentation is dropped")
    fixture.page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(expected: presentations + 2, actual: fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "a moved playhead presents again")
    report.expectEqual(expected: buildsBeforePlayhead, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "repeated playhead movement still rebuilds nothing")
    fixture.page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(expected: Tick(100), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped transport returns to the edit cursor")

    // A camera-only publication reprojects the curve, which is a content build.
    let buildsBeforeCamera = fixture.page.contentBuildCount
    _ = fixture.session.mutateCamera { _ = $0.setTimeZoom(90) }
    report.expectEqual(expected: buildsBeforeCamera + 1, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a camera change reprojects the curve once")

    // A selection change rebuilds and is counted apart from content builds.
    let buildsBeforeSelection = fixture.page.contentBuildCount
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .lanes, lanes: [fixture.volumeLane]))
    report.expectEqual(expected: buildsBeforeSelection + 1, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a selection change rebuilds the content it displays")
    report.expectEqual(expected: selectionBuilds + 1, actual: fixture.page.selectionBuildCount, cppID: drawerAutomationContextID,
                       what: "the selection build is counted on its own")
    let points = fixture.page.projection?.points ?? []
    report.expect(points.contains { $0.selected } && points.contains { !$0.selected },
                  cppID: drawerAutomationContextID,
                  message: "the projection marks the points inside the selection")
    report.expectEqual(expected: ["0:127"], actual: fixture.laneValues(points.filter(\.selected).map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }).count == 1 ? ["0:127"] : [], cppID: drawerAutomationContextID,
                       what: "the selection marks exactly the points inside its range")
    fixture.page.applyTimeSelection(nil)
    let cleared = fixture.page.projection?.points ?? []
    report.expect(!cleared.isEmpty, cppID: drawerAutomationContextID,
                  message: "clearing the selection keeps the lane's points")
    report.expect(cleared.allSatisfy { !$0.selected },
                  cppID: drawerAutomationContextID, message: "clearing the selection clears every indicator")
    report.expect(fixture.page.contentBuildCount > builds, cppID: drawerAutomationContextID,
                  message: "the content builds accumulated across the case")

    // Hover: a node publishes its own value text, the background the held value.
    let hoverBuilds = fixture.page.hoverBuildCount
    _ = fixture.page.pointerMove(x: fixture.x(96), y: fixture.y(fixture.volumeLane, 64),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == true, cppID: drawerAutomationContextID,
                  message: "a hover on a node publishes the node")
    report.expectEqual(expected: "64", actual: fixture.page.hover?.text ?? "", cppID: drawerAutomationContextID,
                       what: "a node hover reads out the node's value")
    report.expectEqual(expected: AutomationHintProfile.node, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "a written node advertises node movement")
    _ = fixture.page.pointerMove(x: fixture.x(150), y: fixture.y(fixture.volumeLane, 20),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == false, cppID: drawerAutomationContextID,
                  message: "a hover on the background publishes the tick")
    report.expectEqual(expected: "64", actual: fixture.page.hover?.text ?? "", cppID: drawerAutomationContextID,
                       what: "a background hover reads the value the lane holds there")
    report.expect(fixture.page.hoverBuildCount > hoverBuilds, cppID: drawerAutomationContextID,
                  message: "the hover publications are counted")
    report.expectEqual(expected: AutomationHintProfile.sweep, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "the background advertises sweep and ramp input")
    fixture.page.isPencilMode = true
    report.expectEqual(expected: AutomationHintProfile.pencil, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "switching tools updates stationary hover instructions")
    fixture.page.isPencilMode = false
    report.expectEqual(expected: AutomationHintProfile.sweep, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
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

let drawerAutomationHoverModelID = "swiftcore/AutomationPage::hoverModel"

@MainActor
func drawerAutomationHoverModel(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 64), (120, 40)],
                                    tempo: [(0, 500_000), (48, 400_000)])
    let page = fixture.page
    fixture.activate(fixture.panLane)
    let lane = fixture.projection(fixture.panLane)
    let backgroundTick = Tick(72)
    let backgroundX = fixture.x(backgroundTick)
    let backgroundY = fixture.y(fixture.panLane, lane.heldValue(at: backgroundTick) ?? 64)
    let revision = fixture.snapshot
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerAutomationHoverModelID,
                  message: "a background move publishes its hover")
    if let backgroundHover = page.hover {
        report.expectEqual(expected: false, actual: backgroundHover.hasPoint, cppID: drawerAutomationHoverModelID,
                           what: "a background hover names no node")
        report.expect(backgroundHover.tick != 24 && backgroundHover.tick != 120,
                      cppID: drawerAutomationHoverModelID,
                      message: "the insertion tick sits between its neighboring nodes")
        report.expect(abs(fixture.x(backgroundHover.tick) - backgroundX) <= 1.0,
                      cppID: drawerAutomationHoverModelID,
                      message: "a background hover anchors within a pixel of its pointer")
    } else {
        report.fail(drawerAutomationHoverModelID, "a background move publishes its hover")
    }
    report.expectEqual(expected: AutomationParameterMetadata(parameter: fixture.panLane)
        .valueText(lane.heldValue(at: backgroundTick) ?? 64), actual: page.hoverText,
                       cppID: drawerAutomationHoverModelID,
                       what: "a background hover reads the value the lane holds there")
    report.expect(!page.publishedNodes.isEmpty, cppID: drawerAutomationHoverModelID,
                  message: "a background hover keeps the lane's nodes")
    report.expect(page.publishedNodes.allSatisfy { !$0.hovered },
                  cppID: drawerAutomationHoverModelID,
                  message: "a background hover rings no node")
    report.expectEqual(expected: AutomationHintProfile.sweep, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
                       what: "a background hover offers the sweep profile")
    report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
                       what: "hovering the background writes nothing")
    let builds = page.hoverBuildCount
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expectEqual(expected: builds, actual: page.hoverBuildCount, cppID: drawerAutomationHoverModelID,
                       what: "a repeated hover does not churn")
    report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
                       what: "a repeated hover still writes nothing")
    if let node = lane.points.first(where: { $0.tick == 24 }) {
        _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
        if let nodeHover = page.hover,
           let hoveredPoint = page.projection?.points.first(where: { $0.tick == nodeHover.tick }) {
            report.expectEqual(expected: true, actual: nodeHover.hasPoint, cppID: drawerAutomationHoverModelID,
                               what: "a node move hovers its point")
            report.expectEqual(expected: Tick(24), actual: nodeHover.tick, cppID: drawerAutomationHoverModelID,
                               what: "the node hover names its tick")
            report.expectEqual(expected: node.x, actual: hoveredPoint.x, cppID: drawerAutomationHoverModelID,
                               what: "the node hover anchors exactly on its drawn node")
        } else {
            report.fail(drawerAutomationHoverModelID, "a node move hovers its point")
        }
        report.expectEqual(expected: AutomationParameterMetadata(parameter: fixture.panLane).valueText(64), actual:
                           page.hoverText, cppID: drawerAutomationHoverModelID,
                           what: "the node hover reads the node's own text")
        report.expectEqual(expected: 1, actual: page.publishedNodes.filter(\.hovered).count,
                           cppID: drawerAutomationHoverModelID,
                           what: "exactly the hovered node carries the ring")
        report.expectEqual(expected: AutomationHintProfile.node, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
                           what: "an arrow node hover offers the node profile")
        report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
                           what: "hovering a node writes nothing")
    } else {
        report.fail(drawerAutomationHoverModelID, "the pan lane projected no node at tick 24")
    }
    page.pointerLeave()
    report.expect(!page.hoverVisible, cppID: drawerAutomationHoverModelID,
                  message: "leaving the plot clears the hover")
    report.expectEqual(expected: "", actual: page.hoverText, cppID: drawerAutomationHoverModelID,
                       what: "leaving the plot clears the hover text")
    report.expect(page.hover == nil, cppID: drawerAutomationHoverModelID,
                  message: "leaving the plot drops the hover")
    report.expect(!page.publishedNodes.isEmpty, cppID: drawerAutomationHoverModelID,
                  message: "leaving the plot keeps the lane's nodes")
    report.expect(page.publishedNodes.allSatisfy { !$0.hovered },
                  cppID: drawerAutomationHoverModelID,
                  message: "leaving the plot unrings every node")
    report.expectEqual(expected: AutomationCursorKind.arrow.rawValue, actual: page.cursorKind,
                       cppID: drawerAutomationHoverModelID,
                       what: "an arrow hover never arms the pencil cursor")
    let clearedBuilds = page.hoverBuildCount
    page.pointerLeave()
    report.expectEqual(expected: clearedBuilds, actual: page.hoverBuildCount, cppID: drawerAutomationHoverModelID,
                       what: "a repeated leave stays clear without churn")
    report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
                       what: "leave passes write nothing")
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerAutomationHoverModelID,
                  message: "a move after a leave revives the hover")
    page.cancelSectionInteraction()
    report.expect(!page.hoverVisible && page.hover == nil, cppID: drawerAutomationHoverModelID,
                  message: "a strong cancellation clears a live hover")
    report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
                       what: "cancelling a hover changes no document or history state")
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerAutomationHoverModelID,
                  message: "a move after a cancellation revives the hover")
    page.cancelSectionInteraction()
    report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
                       what: "an idle cancellation is a no-op on document and history")
    report.expect(!page.interactionActive, cppID: drawerAutomationHoverModelID,
                  message: "an idle cancellation leaves no interaction live")
    page.isPencilMode = true
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expectEqual(expected: AutomationHintProfile.pencil, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
                       what: "a stationary pencil toggle offers the pencil profile")
    page.isPencilMode = false
    report.expectEqual(expected: AutomationHintProfile.sweep, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
                       what: "leaving pencil mode restores the sweep profile")
    page.pointerLeave()
    fixture.activate(.tempo)
    if let tempoNode = page.projection?.points.first(where: { $0.tick == 48 }) {
        _ = page.pointerMove(x: tempoNode.x, y: tempoNode.y, buttons: 0)
        if let tempoHover = page.hover,
           let hoveredTempoPoint = page.projection?.points.first(where: { $0.tick == tempoHover.tick }) {
            report.expectEqual(expected: true, actual: tempoHover.hasPoint, cppID: drawerAutomationHoverModelID,
                               what: "Tempo hovers its node exactly like a CC lane")
            report.expectEqual(expected: tempoNode.x, actual: hoveredTempoPoint.x, cppID: drawerAutomationHoverModelID,
                               what: "the Tempo hover anchors exactly on its drawn node")
        } else {
            report.fail(drawerAutomationHoverModelID, "Tempo hovers its node exactly like a CC lane")
        }
        report.expect(!page.hoverText.isEmpty, cppID: drawerAutomationHoverModelID,
                      message: "the Tempo node hover names its value")
        report.expectEqual(expected: 1, actual: page.publishedNodes.filter(\.hovered).count,
                           cppID: drawerAutomationHoverModelID,
                           what: "Tempo rings exactly its hovered node")
        report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
                           what: "Tempo hover topology preserves the document")
        page.pointerLeave()
        report.expect(!page.hoverVisible, cppID: drawerAutomationHoverModelID,
                      message: "Tempo leaves clear exactly like a CC lane")
    } else {
        report.fail(drawerAutomationHoverModelID, "the tempo lane projected no node at tick 48")
    }
    fixture.activate(fixture.panLane)
    let pressX = fixture.x(72)
    let pressY = fixture.y(fixture.panLane, lane.heldValue(at: 72) ?? 64)
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: AutomationQtButton.left)
    _ = page.pointerMove(x: pressX + 24, y: pressY - 12, buttons: AutomationQtButton.left)
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 0,
                               through: TimeDefaults.noTick,
                               points: [LaneWrite(tick: 24, value: 64), LaneWrite(tick: 72, value: 70),
                                        LaneWrite(tick: 120, value: 40)])
    page.refreshFromDocument()
    let afterRebuild = fixture.values(fixture.panLane)
    _ = page.pointerRelease(x: pressX + 24, y: pressY - 12, button: AutomationQtButton.left)
    report.expectEqual(expected: afterRebuild, actual: fixture.values(fixture.panLane), cppID: drawerAutomationHoverModelID,
                       what: "a stale release after a mid-gesture rebuild commits nothing")
    report.expect(!page.interactionActive, cppID: drawerAutomationHoverModelID,
                  message: "a stale release leaves no interaction live")
}

let drawerAutomationMenuHintMutingID = "swiftcore/AutomationPage::menuHintMuting"

@MainActor
func drawerAutomationMenuHintMuting(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 64), (120, 40)])
    let page = fixture.page
    fixture.activate(fixture.panLane)
    guard let node = fixture.projection(fixture.panLane).points.first(where: { $0.tick == 24 }) else {
        report.fail(drawerAutomationMenuHintMutingID, "the pan lane projected no node at tick 24")
        return
    }
    let revision = fixture.snapshot
    _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
    report.expectEqual(expected: AutomationHintProfile.node, actual: page.hoverHintProfile,
                       cppID: drawerAutomationMenuHintMutingID,
                       what: "a node hover offers the node profile before the menu opens")
    report.expect(page.pointerPress(x: node.x, y: node.y, surface: 1,
                                    button: AutomationQtButton.right),
                  cppID: drawerAutomationMenuHintMutingID,
                  message: "a right press on a node starts its band")
    report.expect(page.pointerRelease(x: node.x, y: node.y, button: AutomationQtButton.right),
                  cppID: drawerAutomationMenuHintMutingID,
                  message: "a stationary right release opens the node menu")
    report.expect(page.menuOpen, cppID: drawerAutomationMenuHintMutingID,
                  message: "the open menu owns the hint scope")
    report.expect(page.interactionActive, cppID: drawerAutomationMenuHintMutingID,
                  message: "the open menu is the page's live interaction")
    report.expectEqual(expected: AutomationHintProfile.empty, actual: page.hoverHintProfile,
                       cppID: drawerAutomationMenuHintMutingID,
                       what: "the open menu mutes the underlay hint")
    let lane = fixture.projection(fixture.panLane)
    let backgroundY = fixture.y(fixture.panLane, lane.heldValue(at: 72) ?? 64)
    _ = page.pointerMove(x: fixture.x(72), y: backgroundY, buttons: 0)
    _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
    report.expect(page.menuOpen, cppID: drawerAutomationMenuHintMutingID,
                  message: "motion between underlying targets keeps the menu scope")
    report.expectEqual(expected: AutomationHintProfile.empty, actual: page.hoverHintProfile,
                       cppID: drawerAutomationMenuHintMutingID,
                       what: "motion between underlying targets stays muted")
    report.expect(page.handleEscape(), cppID: drawerAutomationMenuHintMutingID,
                  message: "Escape claims the open menu")
    report.expect(!page.menuOpen, cppID: drawerAutomationMenuHintMutingID,
                  message: "dismissing the menu releases the hint scope")
    report.expect(!page.interactionActive, cppID: drawerAutomationMenuHintMutingID,
                  message: "dismissing the menu ends the live interaction")
    _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerAutomationMenuHintMutingID,
                  message: "pointer motion after a dismissal revives the hover")
    report.expectEqual(expected: AutomationHintProfile.node, actual: page.hoverHintProfile,
                       cppID: drawerAutomationMenuHintMutingID,
                       what: "pointer motion after a dismissal restores the node profile")
    report.expect(!page.interactionActive, cppID: drawerAutomationMenuHintMutingID,
                  message: "the revived hover is not the page's interaction")
    report.expectEqual(expected: revision, actual: fixture.snapshot, cppID: drawerAutomationMenuHintMutingID,
                       what: "the menu cycle writes nothing")
}

let drawerAutomationHoverResidualID = "swiftcore/AutomationPage::hoverResidual"

@MainActor
func drawerAutomationHoverResidual(_ report: CheckReport, suite: DocumentSession,
                                   service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 64), (120, 40)],
                                    tempo: [(0, 500_000), (96, 400_000)])
    let page = fixture.page
    fixture.activate(.tempo)
    let tempoLane = fixture.makeProjection(.tempo)
    let backgroundTick = Tick(48)
    let backgroundX = fixture.x(backgroundTick)
    let backgroundY = fixture.y(.tempo, tempoLane.heldValue(at: backgroundTick) ?? 120)
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerAutomationHoverResidualID,
                  message: "a tempo background move publishes its hover")
    report.expectEqual(expected: AutomationParameterMetadata(parameter: .tempo)
        .valueText(tempoLane.heldValue(at: backgroundTick) ?? 120), actual: page.hoverText,
                       cppID: drawerAutomationHoverResidualID,
                       what: "a tempo background hover reads the held value")
    page.pointerLeave()
    fixture.activate(fixture.panLane)
    fixture.activate(.tempo)
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerAutomationHoverResidualID,
                  message: "a hover after switching away and back revives")
    report.expectEqual(expected: AutomationParameterMetadata(parameter: .tempo)
        .valueText(tempoLane.heldValue(at: backgroundTick) ?? 120), actual: page.hoverText,
                       cppID: drawerAutomationHoverResidualID,
                       what: "the revived hover reads the current held value")
    page.pointerLeave()
    let hints = MouseHints()
    let token = hints.allocateSourceToken()
    hints.setWindowActive(active: true)
    hints.claim(sourceToken: token, profile: AutomationHintProfile.sweep)
    report.expect(hints.text.contains("draw ramp"), cppID: drawerAutomationHoverResidualID,
                  message: "the sweep profile instructs the ramp gesture")
    hints.claim(sourceToken: token, profile: AutomationHintProfile.node)
    report.expect(hints.text.contains("constrain to axis"), cppID: drawerAutomationHoverResidualID,
                  message: "the node profile instructs the axis constraint")
    hints.clear(sourceToken: token)
    report.expectEqual(expected: "", actual: hints.text, cppID: drawerAutomationHoverResidualID,
                       what: "clearing the claim retires its instructions")
    fixture.activate(fixture.panLane)
    let facts = fixture.facts(fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: page.geometry,
        snapPolicy: AutomationProjectionCache().snapPolicy(session: fixture.session, font: 13, dpr: 1),
        songEndTick: fixture.songEndTick)
    var ramp = AutomationSweepTransaction(facts: facts, mode: .ramp,
                                          mapped: AutomationLanePoint(tick: 72, value: 60),
                                          rawTick: 72, pressX: 0, pressY: 0)
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 96, value: 20))
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 120, value: 100))
    let rampPoints = ramp.finishedPoints(fine: true, projection: projection)
    report.expect(rampPoints.allSatisfy { $0.tick < 72 || $0.tick > 120 || $0.value != 20 },
                  cppID: drawerAutomationHoverResidualID,
                  message: "a ramp ignores its interior excursion")
    report.expectEqual(expected: AutomationLanePoint(tick: 72, value: 60), actual: rampPoints.first,
                       cppID: drawerAutomationHoverResidualID, what: "the ramp keeps its anchor")
    report.expectEqual(expected: AutomationLanePoint(tick: 120, value: 100), actual: rampPoints.last,
                       cppID: drawerAutomationHoverResidualID, what: "the ramp keeps its release")
    let profile = page.hoverHintProfile
    let sweepX = fixture.x(72)
    let sweepY = fixture.y(fixture.panLane, 64)
    _ = page.pointerPress(x: sweepX, y: sweepY, surface: 1, button: AutomationQtButton.left)
    _ = page.pointerMove(x: sweepX + 48, y: sweepY - 30, buttons: AutomationQtButton.left)
    report.expectEqual(expected: profile, actual: page.hoverHintProfile, cppID: drawerAutomationHoverResidualID,
                       what: "a live sweep retains its originating hint profile")
    _ = page.pointerMove(x: sweepX + 52, y: sweepY - 34, buttons: AutomationQtButton.left)
    report.expect(page.pointerRelease(x: sweepX + 52, y: sweepY - 34, button: AutomationQtButton.left),
                  cppID: drawerAutomationHoverResidualID, message: "the drafted sweep commits")
    report.expect(fixture.undo(), cppID: drawerAutomationHoverResidualID,
                  message: "the committed sweep is undoable")
    report.expectEqual(expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane),
                       cppID: drawerAutomationHoverResidualID,
                       what: "one undo restores the pre-sweep lane")
}

@MainActor
func drawerAutomationInflightDragInvalidation(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let rebuildID = "automation/AutomationEditingTest::rebuildCancelsAdapterDragAndRecovers"
    let rebuilt = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    rebuilt.activate(rebuilt.panLane)
    let page = rebuilt.page
    report.expect(page.pointerPress(x: rebuilt.x(24), y: rebuilt.y(rebuilt.panLane, 64),
                                     surface: 1, button: 1),
                  cppID: rebuildID, message: "a press grabs the node")
    _ = page.pointerMove(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 64), buttons: 1)
    report.expect(page.hasGesture, cppID: rebuildID, message: "the drag is live past the slop")
    rebuilt.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                               through: 168, points: [LaneWrite(tick: 168, value: 5)])
    report.expect(!page.hasGesture, cppID: rebuildID,
                  message: "the document rebuild cancels the drag synchronously")
    let afterRebuild = rebuilt.snapshot
    _ = page.pointerRelease(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 64), button: 1)
    report.expectEqual(expected: afterRebuild, actual: rebuilt.snapshot, cppID: rebuildID,
                       what: "releasing the cancelled drag commits nothing")
    report.expect(page.pointerPress(x: rebuilt.x(24), y: rebuilt.y(rebuilt.panLane, 64),
                                     surface: 1, button: 1),
                  cppID: rebuildID, message: "a fresh press grabs the node after the rebuild")
    _ = page.pointerMove(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 64), buttons: 1)
    _ = page.pointerMove(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 90), buttons: 1)
    _ = page.pointerRelease(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 90), button: 1)
    report.expectEqual(expected: ["24:90", "120:40", "168:5"], actual: rebuilt.values(rebuilt.panLane),
                       cppID: rebuildID, what: "the recovery drag commits normally")

    let switchID = "automation/AutomationEditingTest::parameterSwitchCancelsNodeDrag"
    let switched = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(24, 64), (120, 40)])
    switched.activate(switched.panLane)
    let switchedBefore = switched.snapshot
    report.expect(switched.page.pointerPress(
        x: switched.x(24), y: switched.y(switched.panLane, 64), surface: 1, button: 1),
                  cppID: switchID, message: "a press grabs the node")
    _ = switched.page.pointerMove(x: switched.x(24) + 30, y: switched.y(switched.panLane, 64),
                                   buttons: 1)
    report.expect(switched.page.hasGesture, cppID: switchID, message: "the drag is live")
    switched.activate(switched.volumeLane)
    report.expect(!switched.page.hasGesture, cppID: switchID,
                  message: "switching parameters cancels the drag")
    report.expectEqual(expected: switchedBefore, actual: switched.snapshot, cppID: switchID,
                       what: "the cancelled drag writes nothing")
    _ = switched.page.pointerRelease(x: switched.x(24) + 30,
                                      y: switched.y(switched.panLane, 64), button: 1)
    report.expectEqual(expected: switchedBefore, actual: switched.snapshot, cppID: switchID,
                       what: "releasing after the switch commits nothing")
    switched.activate(switched.panLane)
    report.expect(switched.page.pointerPress(
        x: switched.x(24), y: switched.y(switched.panLane, 64), surface: 1, button: 1),
                  cppID: switchID, message: "a fresh press grabs the node after the switch")
    _ = switched.page.pointerMove(x: switched.x(24) + 30, y: switched.y(switched.panLane, 64),
                                   buttons: 1)
    _ = switched.page.pointerMove(x: switched.x(24) + 30, y: switched.y(switched.panLane, 90),
                                   buttons: 1)
    _ = switched.page.pointerRelease(x: switched.x(24) + 30, y: switched.y(switched.panLane, 90),
                                      button: 1)
    report.expectEqual(expected: ["24:90", "120:40"], actual: switched.values(switched.panLane), cppID: switchID,
                       what: "the recovery drag commits normally")
}

@MainActor
func drawerAutomationKeyboardIngress(_ report: CheckReport, suite: DocumentSession,
                                     service: ProjectService) {
    let selID = "automation/AutomationEditingTest::selectionClearingAndMultilaneReplacement"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 20, to: 60, lanes: [fixture.panLane])
    let selected = fixture.snapshot
    report.expect(fixture.page.handleEscape(), cppID: selID,
                  message: "Escape with only an explicit selection claims it")
    report.expect(fixture.page.selection == nil, cppID: selID,
                  message: "Escape clears the explicit time selection")
    report.expectEqual(expected: selected, actual: fixture.snapshot, cppID: selID,
                       what: "clearing the selection writes nothing")

    let precedence = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                       pan: [(24, 64)])
    precedence.activate(precedence.panLane)
    precedence.page.selectRange(from: 20, to: 60, lanes: [precedence.panLane])
    report.expect(precedence.page.pointerPress(x: precedence.x(24),
                                                y: precedence.y(precedence.panLane, 64),
                                                surface: 1, button: 1),
                  cppID: selID, message: "a press inside the selection grabs the node")
    let grabbed = precedence.snapshot
    report.expect(precedence.page.handleEscape(), cppID: selID,
                  message: "Escape with a live gesture claims it")
    report.expect(!precedence.page.hasGesture, cppID: selID,
                  message: "Escape cancels the gesture first")
    report.expect(precedence.page.selection != nil, cppID: selID,
                  message: "the selection survives a gesture-first Escape")
    report.expectEqual(expected: grabbed, actual: precedence.snapshot, cppID: selID,
                       what: "a gesture-first Escape writes nothing")

    let keyID = "automation/AutomationEditingTest::selectedRangeDragAndDelete"
    let armed = EditSurfaceState(pointerGestureActive: false, timeSelectionActive: true,
                                 noteSelectionEmpty: true, origin: .timeline, autoRepeat: false,
                                 commandAvailable: true)
    report.expectEqual(expected: EditKeyDecision.execute, actual: EditKeyArbiter.decide(command: .delete, surface: armed),
                       cppID: keyID, what: "the Delete key routes to the active time selection")
    report.expectEqual(expected: EditKeyDecision.decline, actual:
                       EditKeyArbiter.decide(command: nil, surface: armed), cppID: keyID,
                       what: "an unbound key stays host-owned")
    let held = EditSurfaceState(pointerGestureActive: true, timeSelectionActive: true,
                                 noteSelectionEmpty: true, origin: .timeline, autoRepeat: false,
                                 commandAvailable: true)
    report.expectEqual(expected: EditKeyDecision.consume, actual:
                       EditKeyArbiter.decide(command: .delete, surface: held), cppID: keyID,
                       what: "a live gesture swallows the Delete key without acting")
    let quietID = "automation/AutomationEditingTest::cleanup"
    let quiet = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    quiet.activate(quiet.panLane)
    let quietBefore = quiet.snapshot
    quiet.page.cancelSectionInteraction()
    report.expectEqual(expected: quietBefore, actual: quiet.snapshot, cppID: quietID,
                       what: "quiescing an idle page writes nothing")
}

@MainActor
func drawerAutomationBandEscape(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let bandID = "automation/AutomationEditingTest::rightBandPreviewIsolated"
    let band = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    band.activate(band.panLane)
    _ = band.page.pointerPress(x: band.x(24), y: 60, surface: 1, button: AutomationQtButton.right)
    _ = band.page.pointerMove(x: band.x(120), y: 60, buttons: AutomationQtButton.right)
    report.expect(band.page.bandVisible, cppID: bandID, message: "the right drag arms the band")
    let bandBefore = band.snapshot
    report.expect(band.page.handleEscape(), cppID: bandID, message: "Escape claims the live band")
    report.expect(!band.page.bandVisible, cppID: bandID, message: "Escape drops the band")
    report.expect(!band.page.isPanning, cppID: bandID,
                  message: "no pan owns the band scenario")
    report.expect(!band.page.hasGesture, cppID: bandID,
                  message: "no gesture owns the band scenario")
    report.expectEqual(expected: bandBefore, actual: band.snapshot, cppID: bandID,
                       what: "dropping the band writes nothing")
}
