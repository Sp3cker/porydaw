import Foundation
@testable import PorydawApp
import PorydawCore

// Existing scenarios paired with automationcanvaslayout.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationHitGeometry(_ report: CheckReport, suite: DocumentSession,
                         service: ProjectService) {
    let policy = AutomationPage().bodyPolicy
    let metrics = EditorDrawerMetrics.resolve(baseFontPx: 13, appFontLineSpacing: 15)
    report.expect(policy.preferredBodyHeight(200, metrics) >= metrics.minimumBody, cppID: drawerAutomationLayoutID,
                  message: "the requested automation height never falls under the minimum")
    report.expect(policy.preferredBodyHeight(1000, metrics)
                      <= metrics.maximumDefaultBodyHeight(hostHeight: 1000),
                  cppID: drawerAutomationLayoutID,
                  message: "the requested automation height keeps the piano-roll reserve")
    report.expectEqual(expected: 200, actual: policy.preferredBodyHeight(1000, metrics), cppID: drawerAutomationLayoutID,
                       what: "the requested height is a fifth of the host inside those bounds")
    report.expect(policy.maximumBodyHeight == nil, cppID: drawerAutomationLayoutID,
                  message: "automation declares no page maximum")

    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    report.expectEqual(expected: 8.0, actual: fixture.page.geometry.pointHitRadius, cppID: drawerAutomationLayoutID,
                       what: "the hit radius is the font-relative production value")
    report.expectEqual(expected: 9.0, actual: fixture.page.geometry.neutralSnapRadius, cppID: drawerAutomationLayoutID,
                       what: "the neutral snap radius is the font-relative production value")
    report.expectEqual(expected: 5.0, actual: fixture.page.geometry.nodeDragActivationDistance, cppID: drawerAutomationLayoutID,
                       what: "the drag activation distance is the font-relative value")
    report.expectEqual(expected: 5.0, actual: fixture.page.geometry.valuePlotPadding, cppID: drawerAutomationLayoutID,
                       what: "the value axis is padded by the marker's painted extent")

    // The hit radius decides what a press takes: inside it the node, beyond it
    // the lane.
    let lane = fixture.projection(fixture.panLane)
    let node = lane.points[0]
    report.expect(lane.hitTest(x: node.x + 4, y: node.y + 4,
                               radius: fixture.page.geometry.pointHitRadius) != nil,
                  cppID: drawerAutomationLayoutID, message: "a press inside the hit radius takes the node")
    report.expect(lane.hitTest(x: node.x + 9, y: node.y + 9,
                               radius: fixture.page.geometry.pointHitRadius) == nil,
                  cppID: drawerAutomationLayoutID, message: "a press beyond the hit radius takes no node")
    report.expectEqual(expected: node.tick, actual: lane.hitTest(x: node.x + 1, y: node.y,
                                               radius: fixture.page.geometry.pointHitRadius)?.tick
                           ?? 0,
                       cppID: drawerAutomationLayoutID, what: "the nearest node wins the hit")

    // The half-open cell rule: a tick on a boundary belongs to the cell starting
    // there, and the song's end never starts another cell.
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationProjectionCache().snapPolicy(session: fixture.session, font: 13, dpr: 1),
        songEndTick: fixture.songEndTick)
    let cell = projection.cell(atRawTick: 48)
    report.expect(cell.tickBegin < cell.tickEnd && cell.tickEnd <= fixture.songEndTick,
                  cppID: drawerAutomationLayoutID, message: "a cell is half-open and inside the song")
    report.expect(cell.contains(Double(cell.tickBegin)), cppID: drawerAutomationLayoutID,
                  message: "a cell contains its own begin")
    report.expect(!cell.contains(Double(cell.tickEnd)), cppID: drawerAutomationLayoutID,
                  message: "a cell excludes its own end")
    let endCell = projection.cell(atRawTick: Double(fixture.songEndTick))
    report.expectEqual(expected: fixture.songEndTick, actual: endCell.tickEnd, cppID: drawerAutomationLayoutID,
                       what: "the song's end belongs to the cell that ends there")
    let forward = projection.cellsCrossed(from: 0, to: 30)
    report.expect(forward.count >= 2 && forward.first?.contains(0) == true, cppID: drawerAutomationLayoutID,
                  message: "a forward walk starts at the origin's own cell")
    report.expectEqual(expected: projection.cell(atRawTick: 30).tickBegin, actual: forward.last?.tickBegin ?? 0,
                       cppID: drawerAutomationLayoutID, what: "a forward walk ends at the pointer's cell")
    let backward = projection.cellsCrossed(from: 30, to: 0)
    report.expectEqual(expected: forward.last?.tickBegin, actual: backward.first?.tickBegin, cppID: drawerAutomationLayoutID,
                       what: "a backward walk starts at the pointer's own cell")
    let degenerate = projection.cellsCrossed(from: 0, to: 0)
    report.expectEqual(expected: 1, actual: degenerate.count, cppID: drawerAutomationLayoutID,
                       what: "a degenerate walk reports its own cell once")
    report.expectEqual(expected: projection.cell(atRawTick: 0).tickBegin, actual: degenerate[0].tickBegin,
                       cppID: drawerAutomationLayoutID, what: "a degenerate walk stays in the pointer's cell")
}

@MainActor
func drawerAutomationMiddlePanIsolation(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    let id = "automation/AutomationEditingTest::middlePanIsolated"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let before = fixture.snapshot
    let cursorBefore = fixture.session.editCursor
    let scrollBefore = fixture.session.camera.snapshot.scrollX
    report.expect(page.pointerPress(x: 100, y: 60, surface: 1, button: AutomationQtButton.middle),
                  cppID: id, message: "a middle press starts the pan")
    report.expect(page.isPanning, cppID: id, message: "the page publishes the live pan")
    report.expectEqual(expected: AutomationCursorKind.closedHand.rawValue, actual: page.cursorKind, cppID: id,
                       what: "the pan publishes the closed hand")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "starting a pan mutates nothing")
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor, cppID: id,
                       what: "starting a pan parks no cursor")
    _ = page.pointerMove(x: 52, y: 60, buttons: AutomationQtButton.middle)
    report.expectEqual(expected: scrollBefore + 48, actual: fixture.session.camera.snapshot.scrollX, cppID: id,
                       what: "the pan scrolls the shared camera by the travel")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "panning mutates nothing")
    _ = page.pointerRelease(x: 52, y: 60, button: AutomationQtButton.middle)
    report.expect(!page.isPanning, cppID: id, message: "releasing ends the pan")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "the released pan leaves document and history untouched")
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor, cppID: id,
                       what: "the released pan leaves the cursor where it was")

    let switchID = "automation/AutomationEditingTest::primaryTrackSwitchRebuildsRowsDuringPan"
    _ = page.pointerPress(x: 100, y: 60, surface: 1, button: AutomationQtButton.middle)
    report.expect(page.isPanning, cppID: switchID, message: "a second pan starts")
    fixture.activate(fixture.volumeLane)
    report.expect(!page.isPanning, cppID: switchID,
                  message: "switching parameters ends the pan")
    report.expectEqual(expected: fixture.volumeLane, actual: page.activeParameter, cppID: switchID,
                       what: "the switch rebuilds the active parameter")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: switchID,
                       what: "switching mid-pan writes nothing")
    _ = page.pointerRelease(x: 100, y: 60, button: AutomationQtButton.middle)
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: switchID,
                       what: "releasing after the switch commits nothing")
}

@MainActor
func drawerAutomationViewStatePreservation(_ report: CheckReport, suite: DocumentSession,
                                           service: ProjectService) {
    let id = "automation/AutomationEditingTest::viewStateSwitchPreservesAutomationState"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    volume: [(24, 70)],
                                                    tempo: [(0, 500_000), (384, 428_571)])
    fixture.activate(fixture.volumeLane)
    let page = fixture.page
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.volumeLane), x: 0, y: 0)
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.range64.rawValue),
                  cppID: id, message: "the lane takes the 0-64 range")
    let before = fixture.snapshot
    let cursorBefore = fixture.session.editCursor
    page.detach()
    page.attach(session: fixture.session, palette: GridPalette())
    report.expectEqual(expected: fixture.volumeLane, actual: page.activeParameter, cppID: id,
                       what: "the active parameter survives a page switch")
    report.expectEqual(expected: 64, actual: page.scaleLabels.first?.value, cppID: id,
                       what: "the lane range survives a page switch")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "a page switch writes nothing")
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor, cppID: id,
                       what: "a page switch moves no cursor")
    report.expectEqual(expected: ["0:120", "384:140"], actual: fixture.tempoValues, cppID: id,
                       what: "the untouched stream survives a page switch")

    let resizeID = "automation/AutomationEditingTest::wheelZoomAndSectionResizePreserveDrawerState"
    let drawer = EditorDrawerPresenter()
    drawer.configureLayout(hostWidth: 1200, hostHeight: 800, gutterWidth: 160,
                           fontPx: 13, appFontLineSpacing: 15)
    let resizeBefore = fixture.snapshot
    drawer.setSectionBodyHeight(kind: 0, height: 300)
    drawer.applyResize(kind: 0, delta: 40)
    drawer.endResize(kind: 0)
    report.expectEqual(expected: resizeBefore, actual: fixture.snapshot, cppID: resizeID,
                       what: "a section resize writes nothing")
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor, cppID: resizeID,
                       what: "a section resize moves no cursor")
    report.expectEqual(expected: ["0:120", "384:140"], actual: fixture.tempoValues, cppID: resizeID,
                       what: "a section resize leaves the streams alone")
}
