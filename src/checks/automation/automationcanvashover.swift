import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore

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
        report.expect(!page.interactionActive, cppID: drawerAutomationHoverModelID,
                      message: "a hover is not the page's interaction")
        if let second = lane.points.first(where: { $0.tick == 120 }) {
            _ = page.pointerMove(x: second.x, y: second.y, buttons: 0)
            report.expectEqual(expected: Tick(120), actual: page.hover?.tick,
                               cppID: drawerAutomationHoverModelID,
                               what: "hover move republishes without writing")
            report.expectEqual(expected: [120.0],
                               actual: page.publishedNodes.filter(\.hovered).map(\.tick),
                               cppID: drawerAutomationHoverModelID,
                               what: "hover enter publishes exactly one ring")
            report.expectEqual(expected: revision, actual: fixture.snapshot,
                               cppID: drawerAutomationHoverModelID,
                               what: "hover move republishes without writing")
        } else {
            report.fail(drawerAutomationHoverModelID, "the pan lane projected no second node")
        }
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
    report.expect(!page.hasGesture, cppID: drawerAutomationHoverModelID,
                  message: "a document rebuild aborts the drag")
    let rebuilt = fixture.snapshot
    let afterRebuild = fixture.values(fixture.panLane)
    _ = page.pointerRelease(x: pressX + 24, y: pressY - 12, button: AutomationQtButton.left)
    report.expectEqual(expected: afterRebuild, actual: fixture.values(fixture.panLane), cppID: drawerAutomationHoverModelID,
                       what: "a stale release after a mid-gesture rebuild commits nothing")
    report.expectEqual(expected: rebuilt, actual: fixture.snapshot,
                       cppID: drawerAutomationHoverModelID,
                       what: "a stale batch release writes nothing")
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
