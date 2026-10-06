import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
@testable import PorydawAppCommands
import PorydawCore
@testable import PorydawDocument

let drawerAutomationHoverModelID = "swiftcore/AutomationPage::hoverModel"

@MainActor
func drawerAutomationHoverModel(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    for mode in ["vanilla", "dark-neutral-high", "immaterial"] {
        let colors = GridPalette()
        ShellAppearance.apply(to: colors, mode: mode, contrast: 50)
        let ratio = PaletteMath.contrastRatio(colors.windowText, colors.rollBackground)
        report.expect(
            ratio >= 3, cppID: drawerAutomationHoverModelID,
            message: "\(mode) mounted insertion guide and ghost ink clear 3:1 on the roll background")
    }
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
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
    report.expect(
        page.hoverVisible, cppID: drawerAutomationHoverModelID,
        message: "a background move publishes its hover")
    if let backgroundHover = page.hover {
        report.expectEqual(
            expected: false, actual: backgroundHover.hasPoint, cppID: drawerAutomationHoverModelID,
            what: "a background hover names no node")
        report.expect(
            backgroundHover.tick != 24 && backgroundHover.tick != 120,
            cppID: drawerAutomationHoverModelID,
            message: "the insertion tick sits between its neighboring nodes")
        report.expect(
            abs(fixture.x(backgroundHover.tick) - backgroundX) <= 1.0,
            cppID: drawerAutomationHoverModelID,
            message: "a background hover anchors within a pixel of its pointer")
    } else {
        report.fail(drawerAutomationHoverModelID, "a background move publishes its hover")
    }
    report.expectEqual(
        expected: AutomationParameterMetadata(parameter: fixture.panLane)
            .valueText(lane.heldValue(at: backgroundTick) ?? 64), actual: page.hoverText,
        cppID: drawerAutomationHoverModelID,
        what: "a background hover reads the value the lane holds there")
    report.expectEqual(
        expected: true, actual: page.hoverDisplay.hasGhost,
        cppID: drawerAutomationHoverModelID,
        what: "inter-node CC hover publishes a held-value ghost")
    report.expect(
        abs(page.hoverDisplay.guideX - fixture.x(page.hover?.tick ?? 0)) <= 1,
        cppID: drawerAutomationHoverModelID,
        message: "inter-node CC hover aligns its insertion guide within one pixel")
    report.expect(
        abs(
            page.hoverDisplay.ghostY
                - fixture.y(fixture.panLane, lane.heldValue(at: backgroundTick) ?? 64)) <= 1,
        cppID: drawerAutomationHoverModelID,
        message: "inter-node CC hover paints its ghost at the held-value row")
    report.expect(
        !page.publishedNodes.isEmpty, cppID: drawerAutomationHoverModelID,
        message: "a background hover keeps the lane's nodes")
    report.expect(
        page.publishedNodes.allSatisfy { !$0.hovered },
        cppID: drawerAutomationHoverModelID,
        message: "a background hover rings no node")
    report.expectEqual(
        expected: AutomationHintProfile.sweep, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
        what: "a background hover offers the sweep profile")
    report.expectEqual(
        expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
        what: "hovering the background writes nothing")
    let builds = page.hoverBuildCount
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expectEqual(
        expected: builds, actual: page.hoverBuildCount, cppID: drawerAutomationHoverModelID,
        what: "a repeated hover does not churn")
    report.expectEqual(
        expected: true, actual: page.hoverDisplay.hasGhost,
        cppID: drawerAutomationHoverModelID,
        what: "a repeated CC hover retains its published ghost")
    report.expectEqual(
        expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
        what: "a repeated hover still writes nothing")
    if let node = lane.points.first(where: { $0.tick == 24 }) {
        _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
        if let nodeHover = page.hover,
            let hoveredPoint = page.projection?.points.first(where: { $0.tick == nodeHover.tick })
        {
            report.expectEqual(
                expected: true, actual: nodeHover.hasPoint, cppID: drawerAutomationHoverModelID,
                what: "a node move hovers its point")
            report.expectEqual(
                expected: Tick(24), actual: nodeHover.tick, cppID: drawerAutomationHoverModelID,
                what: "the node hover names its tick")
            report.expectEqual(
                expected: node.x, actual: hoveredPoint.x, cppID: drawerAutomationHoverModelID,
                what: "the node hover anchors exactly on its drawn node")
        } else {
            report.fail(drawerAutomationHoverModelID, "a node move hovers its point")
        }
        report.expectEqual(
            expected: AutomationParameterMetadata(parameter: fixture.panLane).valueText(64),
            actual:
                page.hoverText, cppID: drawerAutomationHoverModelID,
            what: "the node hover reads the node's own text")
        report.expectEqual(
            expected: 1, actual: page.publishedNodes.filter(\.hovered).count,
            cppID: drawerAutomationHoverModelID,
            what: "exactly the hovered node carries the ring")
        report.expectEqual(
            expected: false, actual: page.hoverDisplay.hasGhost,
            cppID: drawerAutomationHoverModelID,
            what: "an existing-node hover suppresses the insertion ghost")
        report.expectEqual(
            expected: AutomationHintProfile.node, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
            what: "an arrow node hover offers the node profile")
        report.expectEqual(
            expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
            what: "hovering a node writes nothing")
        report.expect(
            !page.interactionActive, cppID: drawerAutomationHoverModelID,
            message: "a hover is not the page's interaction")
        if let second = lane.points.first(where: { $0.tick == 120 }) {
            _ = page.pointerMove(x: second.x, y: second.y, buttons: 0)
            report.expectEqual(
                expected: Tick(120), actual: page.hover?.tick,
                cppID: drawerAutomationHoverModelID,
                what: "hover move republishes without writing")
            report.expectEqual(
                expected: [120.0],
                actual: page.publishedNodes.filter(\.hovered).map(\.tick),
                cppID: drawerAutomationHoverModelID,
                what: "hover enter publishes exactly one ring")
            report.expectEqual(
                expected: revision, actual: fixture.snapshot,
                cppID: drawerAutomationHoverModelID,
                what: "hover move republishes without writing")
        } else {
            report.fail(drawerAutomationHoverModelID, "the pan lane projected no second node")
        }
    } else {
        report.fail(drawerAutomationHoverModelID, "the pan lane projected no node at tick 24")
    }
    page.pointerLeave()
    report.expect(
        !page.hoverVisible, cppID: drawerAutomationHoverModelID,
        message: "leaving the plot clears the hover")
    report.expectEqual(
        expected: "", actual: page.hoverText, cppID: drawerAutomationHoverModelID,
        what: "leaving the plot clears the hover text")
    report.expect(
        page.hover == nil, cppID: drawerAutomationHoverModelID,
        message: "leaving the plot drops the hover")
    report.expect(
        !page.publishedNodes.isEmpty, cppID: drawerAutomationHoverModelID,
        message: "leaving the plot keeps the lane's nodes")
    report.expect(
        page.publishedNodes.allSatisfy { !$0.hovered },
        cppID: drawerAutomationHoverModelID,
        message: "leaving the plot unrings every node")
    report.expectEqual(
        expected: false, actual: page.hoverDisplay.visible,
        cppID: drawerAutomationHoverModelID,
        what: "leaving clears the guide ghost ring and label together")
    report.expectEqual(
        expected: AutomationCursorKind.arrow.rawValue, actual: page.cursorKind,
        cppID: drawerAutomationHoverModelID,
        what: "an arrow hover never arms the pencil cursor")
    let clearedBuilds = page.hoverBuildCount
    page.pointerLeave()
    report.expectEqual(
        expected: clearedBuilds, actual: page.hoverBuildCount, cppID: drawerAutomationHoverModelID,
        what: "a repeated leave stays clear without churn")
    report.expectEqual(
        expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
        what: "leave passes write nothing")
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(
        page.hoverVisible, cppID: drawerAutomationHoverModelID,
        message: "a move after a leave revives the hover")
    page.cancelSectionInteraction()
    report.expect(
        !page.hoverVisible && page.hover == nil, cppID: drawerAutomationHoverModelID,
        message: "a strong cancellation clears a live hover")
    report.expectEqual(
        expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
        what: "cancelling a hover changes no document or history state")
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(
        page.hoverVisible, cppID: drawerAutomationHoverModelID,
        message: "a move after a cancellation revives the hover")
    page.cancelSectionInteraction()
    report.expectEqual(
        expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
        what: "an idle cancellation is a no-op on document and history")
    report.expect(
        !page.interactionActive, cppID: drawerAutomationHoverModelID,
        message: "an idle cancellation leaves no interaction live")
    page.isPencilMode = true
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expectEqual(
        expected: AutomationHintProfile.pencil, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
        what: "a stationary pencil toggle offers the pencil profile")
    page.isPencilMode = false
    report.expectEqual(
        expected: AutomationHintProfile.sweep, actual: page.hoverHintProfile, cppID: drawerAutomationHoverModelID,
        what: "leaving pencil mode restores the sweep profile")
    page.pointerLeave()
    fixture.activate(.tempo)
    let tempoBackgroundTick = Tick(24)
    let tempoProjection = fixture.projection(.tempo)
    let tempoY = fixture.y(.tempo, tempoProjection.heldValue(at: tempoBackgroundTick) ?? 120)
    _ = page.pointerMove(x: fixture.x(tempoBackgroundTick), y: tempoY, buttons: 0)
    report.expectEqual(
        expected: true, actual: page.hoverDisplay.hasGhost,
        cppID: drawerAutomationHoverModelID,
        what: "inter-node Tempo hover publishes a held-value ghost")
    report.expect(
        !page.hoverText.isEmpty, cppID: drawerAutomationHoverModelID,
        message: "inter-node Tempo hover labels the held value")
    if let tempoNode = page.projection?.points.first(where: { $0.tick == 48 }) {
        _ = page.pointerMove(x: tempoNode.x, y: tempoNode.y, buttons: 0)
        if let tempoHover = page.hover,
            let hoveredTempoPoint = page.projection?.points.first(where: { $0.tick == tempoHover.tick })
        {
            report.expectEqual(
                expected: true, actual: tempoHover.hasPoint, cppID: drawerAutomationHoverModelID,
                what: "Tempo hovers its node exactly like a CC lane")
            report.expectEqual(
                expected: tempoNode.x, actual: hoveredTempoPoint.x, cppID: drawerAutomationHoverModelID,
                what: "the Tempo hover anchors exactly on its drawn node")
        } else {
            report.fail(drawerAutomationHoverModelID, "Tempo hovers its node exactly like a CC lane")
        }
        report.expect(
            !page.hoverText.isEmpty, cppID: drawerAutomationHoverModelID,
            message: "the Tempo node hover names its value")
        report.expectEqual(
            expected: 1, actual: page.publishedNodes.filter(\.hovered).count,
            cppID: drawerAutomationHoverModelID,
            what: "Tempo rings exactly its hovered node")
        report.expectEqual(
            expected: false, actual: page.hoverDisplay.hasGhost,
            cppID: drawerAutomationHoverModelID,
            what: "an existing Tempo node suppresses the insertion ghost")
        report.expectEqual(
            expected: revision, actual: fixture.snapshot, cppID: drawerAutomationHoverModelID,
            what: "Tempo hover topology preserves the document")
        page.pointerLeave()
        report.expect(
            !page.hoverVisible, cppID: drawerAutomationHoverModelID,
            message: "Tempo leaves clear exactly like a CC lane")
    } else {
        report.fail(drawerAutomationHoverModelID, "the tempo lane projected no node at tick 48")
    }
    fixture.activate(fixture.panLane)
    let pressX = fixture.x(72)
    let pressY = fixture.y(fixture.panLane, lane.heldValue(at: 72) ?? 64)
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: DrawerQtButton.left)
    _ = page.pointerMove(x: pressX + 24, y: pressY - 12, buttons: DrawerQtButton.left)
    fixture.document.writeLane(
        track: 0, lane: .controller(TimeDefaults.ccPan), from: 0,
        through: TimeDefaults.noTick,
        points: [
            LaneWrite(tick: 24, value: 64), LaneWrite(tick: 72, value: 70),
            LaneWrite(tick: 120, value: 40),
        ])
    page.refreshFromDocument()
    report.expect(
        !page.hasGesture, cppID: drawerAutomationHoverModelID,
        message: "a document rebuild aborts the drag")
    let rebuilt = fixture.snapshot
    let afterRebuild = fixture.values(fixture.panLane)
    _ = page.pointerRelease(x: pressX + 24, y: pressY - 12, button: DrawerQtButton.left)
    report.expectEqual(
        expected: afterRebuild, actual: fixture.values(fixture.panLane), cppID: drawerAutomationHoverModelID,
        what: "a stale release after a mid-gesture rebuild commits nothing")
    report.expectEqual(
        expected: rebuilt, actual: fixture.snapshot,
        cppID: drawerAutomationHoverModelID,
        what: "a stale batch release writes nothing")
    report.expect(
        !page.interactionActive, cppID: drawerAutomationHoverModelID,
        message: "a stale release leaves no interaction live")
}

let drawerAutomationMenuHintMutingID = "swiftcore/AutomationPage::menuHintMuting"

@MainActor
func drawerAutomationMenuHintMuting(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    let page = fixture.page
    fixture.activate(fixture.panLane)
    guard let node = fixture.projection(fixture.panLane).points.first(where: { $0.tick == 24 }) else {
        report.fail(drawerAutomationMenuHintMutingID, "the pan lane projected no node at tick 24")
        return
    }
    let revision = fixture.snapshot
    _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
    report.expectEqual(
        expected: AutomationHintProfile.node, actual: page.hoverHintProfile,
        cppID: drawerAutomationMenuHintMutingID,
        what: "a node hover offers the node profile before the menu opens")
    report.expect(
        page.pointerPress(
            x: node.x, y: node.y, surface: 1,
            button: DrawerQtButton.right),
        cppID: drawerAutomationMenuHintMutingID,
        message: "a right press on a node starts its band")
    report.expect(
        page.pointerRelease(x: node.x, y: node.y, button: DrawerQtButton.right),
        cppID: drawerAutomationMenuHintMutingID,
        message: "a stationary right release opens the node menu")
    report.expect(
        page.menuOpen, cppID: drawerAutomationMenuHintMutingID,
        message: "the open menu owns the hint scope")
    report.expect(
        page.interactionActive, cppID: drawerAutomationMenuHintMutingID,
        message: "the open menu is the page's live interaction")
    report.expectEqual(
        expected: AutomationHintProfile.empty, actual: page.hoverHintProfile,
        cppID: drawerAutomationMenuHintMutingID,
        what: "the open menu mutes the underlay hint")
    let lane = fixture.projection(fixture.panLane)
    let backgroundY = fixture.y(fixture.panLane, lane.heldValue(at: 72) ?? 64)
    _ = page.pointerMove(x: fixture.x(72), y: backgroundY, buttons: 0)
    _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
    report.expect(
        page.menuOpen, cppID: drawerAutomationMenuHintMutingID,
        message: "motion between underlying targets keeps the menu scope")
    report.expectEqual(
        expected: AutomationHintProfile.empty, actual: page.hoverHintProfile,
        cppID: drawerAutomationMenuHintMutingID,
        what: "motion between underlying targets stays muted")
    report.expect(
        page.handleEscape(), cppID: drawerAutomationMenuHintMutingID,
        message: "Escape claims the open menu")
    report.expect(
        !page.menuOpen, cppID: drawerAutomationMenuHintMutingID,
        message: "dismissing the menu releases the hint scope")
    report.expect(
        !page.interactionActive, cppID: drawerAutomationMenuHintMutingID,
        message: "dismissing the menu ends the live interaction")
    _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
    report.expect(
        page.hoverVisible, cppID: drawerAutomationMenuHintMutingID,
        message: "pointer motion after a dismissal revives the hover")
    report.expectEqual(
        expected: AutomationHintProfile.node, actual: page.hoverHintProfile,
        cppID: drawerAutomationMenuHintMutingID,
        what: "pointer motion after a dismissal restores the node profile")
    report.expect(
        !page.interactionActive, cppID: drawerAutomationMenuHintMutingID,
        message: "the revived hover is not the page's interaction")
    report.expectEqual(
        expected: revision, actual: fixture.snapshot, cppID: drawerAutomationMenuHintMutingID,
        what: "the menu cycle writes nothing")
}

let drawerAutomationHoverResidualID = "swiftcore/AutomationPage::hoverResidual"

@MainActor
func drawerAutomationHoverResidual(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)],
        tempo: [(0, 500_000), (96, 400_000)])
    let page = fixture.page
    fixture.activate(.tempo)
    let tempoLane = fixture.makeProjection(.tempo)
    let backgroundTick = Tick(48)
    let backgroundX = fixture.x(backgroundTick)
    let backgroundY = fixture.y(.tempo, tempoLane.heldValue(at: backgroundTick) ?? 120)
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(
        page.hoverVisible, cppID: drawerAutomationHoverResidualID,
        message: "a tempo background move publishes its hover")
    report.expectEqual(
        expected: AutomationParameterMetadata(parameter: .tempo)
            .valueText(tempoLane.heldValue(at: backgroundTick) ?? 120), actual: page.hoverText,
        cppID: drawerAutomationHoverResidualID,
        what: "a tempo background hover reads the held value")
    page.pointerLeave()
    fixture.activate(fixture.panLane)
    fixture.activate(.tempo)
    _ = page.pointerMove(x: backgroundX, y: backgroundY, buttons: 0)
    report.expect(
        page.hoverVisible, cppID: drawerAutomationHoverResidualID,
        message: "a hover after switching away and back revives")
    report.expectEqual(
        expected: AutomationParameterMetadata(parameter: .tempo)
            .valueText(tempoLane.heldValue(at: backgroundTick) ?? 120), actual: page.hoverText,
        cppID: drawerAutomationHoverResidualID,
        what: "the revived hover reads the current held value")
    page.pointerLeave()
    let hints = MouseHints()
    let token = hints.allocateSourceToken()
    hints.setWindowActive(active: true)
    hints.claim(sourceToken: token, profile: AutomationHintProfile.sweep)
    report.expect(
        hints.text.contains("draw ramp"), cppID: drawerAutomationHoverResidualID,
        message: "the sweep profile instructs the ramp gesture")
    hints.claim(sourceToken: token, profile: AutomationHintProfile.node)
    report.expect(
        hints.text.contains("constrain to axis"), cppID: drawerAutomationHoverResidualID,
        message: "the node profile instructs the axis constraint")
    hints.clear(sourceToken: token)
    report.expectEqual(
        expected: "", actual: hints.text, cppID: drawerAutomationHoverResidualID,
        what: "clearing the claim retires its instructions")
    fixture.activate(fixture.panLane)
    let facts = fixture.facts(fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.viewport.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: page.geometry,
        snapPolicy: AutomationProjectionCache().snapPolicy(viewport: fixture.viewport, font: 13, dpr: 1),
        songEndTick: fixture.songEndTick)
    var ramp = AutomationSweepTransaction(
        facts: facts, mode: .ramp,
        mapped: AutomationLanePoint(tick: 72, value: 60),
        rawTick: 72, pressX: 0, pressY: 0)
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 96, value: 20))
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 120, value: 100))
    let rampPoints = ramp.finishedPoints(fine: true, projection: projection)
    report.expect(
        rampPoints.allSatisfy { $0.tick < 72 || $0.tick > 120 || $0.value != 20 },
        cppID: drawerAutomationHoverResidualID,
        message: "a ramp ignores its interior excursion")
    report.expectEqual(
        expected: AutomationLanePoint(tick: 72, value: 60), actual: rampPoints.first,
        cppID: drawerAutomationHoverResidualID, what: "the ramp keeps its anchor")
    report.expectEqual(
        expected: AutomationLanePoint(tick: 120, value: 100), actual: rampPoints.last,
        cppID: drawerAutomationHoverResidualID, what: "the ramp keeps its release")
    let profile = page.hoverHintProfile
    let sweepX = fixture.x(72)
    let sweepY = fixture.y(fixture.panLane, 64)
    _ = page.pointerPress(x: sweepX, y: sweepY, surface: 1, button: DrawerQtButton.left)
    _ = page.pointerMove(x: sweepX + 48, y: sweepY - 30, buttons: DrawerQtButton.left)
    report.expectEqual(
        expected: profile, actual: page.hoverHintProfile, cppID: drawerAutomationHoverResidualID,
        what: "a live sweep retains its originating hint profile")
    _ = page.pointerMove(x: sweepX + 52, y: sweepY - 34, buttons: DrawerQtButton.left)
    report.expect(
        page.pointerRelease(x: sweepX + 52, y: sweepY - 34, button: DrawerQtButton.left),
        cppID: drawerAutomationHoverResidualID, message: "the drafted sweep commits")
    report.expect(
        fixture.undo(), cppID: drawerAutomationHoverResidualID,
        message: "the committed sweep is undoable")
    report.expectEqual(
        expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane),
        cppID: drawerAutomationHoverResidualID,
        what: "one undo restores the pre-sweep lane")
}
let drawerAutomationFocusLossID = "swiftcore/AutomationPage::focusLossRetainsGesture"
let drawerAutomationFocusPressID = "swiftcore/AutomationPage::focusLossKeepsPress"

// Focus loss mid-drag freezes the full snapshot at the held point while the
// focus publication flips under the live grab.
@MainActor
func drawerAutomationFocusLossRetainsGesture(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let staged = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    staged.activate(staged.panLane)
    staged.page.plotFocused = true
    let prePress = DrawerAutomationStagedSnapshot(staged.document)
    guard
        staged.page.pointerPress(
            x: staged.x(24), y: staged.y(staged.panLane, 64), surface: 1,
            button: DrawerQtButton.left)
    else {
        report.fail(drawerAutomationFocusLossID, "a press grabs the node before focus moves away")
        return
    }
    let dragTravel = staged.page.geometry.nodeDragActivationDistance + 2
    _ = staged.page.pointerMove(
        x: staged.x(24) + dragTravel, y: staged.y(staged.panLane, 64),
        buttons: DrawerQtButton.left)
    guard staged.page.hasGesture else {
        report.fail(drawerAutomationFocusLossID, "the node drag is live while focus moves away")
        return
    }
    staged.page.plotFocused = false
    guard staged.page.hasGesture && staged.page.interactionActive else {
        report.fail(drawerAutomationFocusLossID, "focus loss while held retains the live node drag")
        return
    }
    report.expectEqual(
        expected: prePress, actual: DrawerAutomationStagedSnapshot(staged.document),
        cppID: drawerAutomationFocusLossID,
        what: "focus loss while held freezes song bytes revision and undo")
}

// A stationary background press keeps its pointer grab across focus loss with
// the document frozen at the held point.
@MainActor
func drawerAutomationFocusLossKeepsPress(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let held = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    held.activate(held.panLane)
    held.page.plotFocused = true
    let frozen = DrawerAutomationStagedSnapshot(held.document)
    let pressX = held.x(72)
    let pressY = held.y(held.panLane, 64)
    guard
        held.page.pointerPress(
            x: pressX, y: pressY, surface: 1,
            button: DrawerQtButton.left)
    else {
        report.fail(drawerAutomationFocusPressID, "a background press captures the pointer grab")
        return
    }
    held.page.plotFocused = false
    guard held.page.hasGesture else {
        report.fail(drawerAutomationFocusPressID, "focus loss while held keeps the captured pointer grab")
        return
    }
    report.expectEqual(
        expected: frozen, actual: DrawerAutomationStagedSnapshot(held.document),
        cppID: drawerAutomationFocusPressID,
        what: "focus loss while still held freezes song bytes revision and undo")
}

// A stationary right click on the hover ghost types the value it inserts there.
@MainActor
func drawerAutomationGhostRightClickPrompt(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = drawerAutomationHoverModelID
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let x = fixture.x(72)
    let y = fixture.y(fixture.panLane, 20)
    _ = page.pointerMove(x: x, y: y, buttons: 0)
    guard let ghost = page.hover, !ghost.hasPoint,
        page.hoverDisplay.hasGhost
    else {
        report.fail(id, "the inter-node background shows its insertion ghost")
        return
    }
    let before = fixture.snapshot
    _ = page.pointerPress(x: x, y: y, surface: 1, button: DrawerQtButton.right)
    _ = page.pointerRelease(x: x, y: y, button: DrawerQtButton.right)
    report.expect(
        page.hasPrompt && !page.menuOpen, cppID: id,
        message: "a right click on the ghost opens its value prompt, not a menu")
    report.expectEqual(
        expected: "0", actual: page.promptDraft, cppID: id,
        what: "the ghost prompt starts at the held value it previews")
    report.expectEqual(
        expected: before, actual: fixture.snapshot, cppID: id,
        what: "opening the ghost prompt writes nothing")
    report.expect(
        page.acceptPrompt(displayedValue: 10), cppID: id,
        message: "accepting the ghost prompt commits once")
    report.expectEqual(
        expected: ["24:64", "\(ghost.tick):74", "120:40"],
        actual: fixture.values(fixture.panLane), cppID: id,
        what: "the typed value lands at the ghost's tick")
    report.expect(
        fixture.undo() && fixture.values(fixture.panLane) == ["24:64", "120:40"],
        cppID: id, message: "one undo removes the ghost insertion")

    let selected = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    selected.activate(selected.panLane)
    selected.page.selectRange(from: 48, to: 96)
    _ = selected.page.pointerPress(x: x, y: y, surface: 1, button: DrawerQtButton.right)
    _ = selected.page.pointerRelease(x: x, y: y, button: DrawerQtButton.right)
    report.expect(
        selected.page.menuOpen && !selected.page.hasPrompt, cppID: id,
        message: "a right click inside the time selection keeps its range menu")
}
