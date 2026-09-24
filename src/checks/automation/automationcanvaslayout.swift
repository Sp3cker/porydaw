import Foundation
import PorydawApp
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
    report.expectEqual(200, policy.preferredBodyHeight(1000, metrics), cppID: drawerAutomationLayoutID,
                       what: "the requested height is a fifth of the host inside those bounds")
    report.expect(policy.maximumBodyHeight == nil, cppID: drawerAutomationLayoutID,
                  message: "automation declares no page maximum")

    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    report.expectEqual(8.0, fixture.page.geometry.pointHitRadius, cppID: drawerAutomationLayoutID,
                       what: "the hit radius is the font-relative production value")
    report.expectEqual(9.0, fixture.page.geometry.neutralSnapRadius, cppID: drawerAutomationLayoutID,
                       what: "the neutral snap radius is the font-relative production value")
    report.expectEqual(5.0, fixture.page.geometry.nodeDragActivationDistance, cppID: drawerAutomationLayoutID,
                       what: "the drag activation distance is the font-relative value")
    report.expectEqual(5.0, fixture.page.geometry.valuePlotPadding, cppID: drawerAutomationLayoutID,
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
    report.expectEqual(node.tick, lane.hitTest(x: node.x + 1, y: node.y,
                                               radius: fixture.page.geometry.pointHitRadius)?.tick
                           ?? 0,
                       cppID: drawerAutomationLayoutID, what: "the nearest node wins the hit")

    // The half-open cell rule: a tick on a boundary belongs to the cell starting
    // there, and the song's end never starts another cell.
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    let cell = projection.cell(atRawTick: 48)
    report.expect(cell.tickBegin < cell.tickEnd && cell.tickEnd <= fixture.songEndTick,
                  cppID: drawerAutomationLayoutID, message: "a cell is half-open and inside the song")
    report.expect(cell.contains(Double(cell.tickBegin)), cppID: drawerAutomationLayoutID,
                  message: "a cell contains its own begin")
    report.expect(!cell.contains(Double(cell.tickEnd)), cppID: drawerAutomationLayoutID,
                  message: "a cell excludes its own end")
    let endCell = projection.cell(atRawTick: Double(fixture.songEndTick))
    report.expectEqual(fixture.songEndTick, endCell.tickEnd, cppID: drawerAutomationLayoutID,
                       what: "the song's end belongs to the cell that ends there")
    let forward = projection.cellsCrossed(from: 0, to: 30)
    report.expect(forward.count >= 2 && forward.first?.contains(0) == true, cppID: drawerAutomationLayoutID,
                  message: "a forward walk starts at the origin's own cell")
    report.expectEqual(projection.cell(atRawTick: 30).tickBegin, forward.last?.tickBegin ?? 0,
                       cppID: drawerAutomationLayoutID, what: "a forward walk ends at the pointer's cell")
    let backward = projection.cellsCrossed(from: 30, to: 0)
    report.expectEqual(forward.last?.tickBegin, backward.first?.tickBegin, cppID: drawerAutomationLayoutID,
                       what: "a backward walk starts at the pointer's own cell")
    let degenerate = projection.cellsCrossed(from: 0, to: 0)
    report.expectEqual(1, degenerate.count, cppID: drawerAutomationLayoutID,
                       what: "a degenerate walk reports its own cell once")
    report.expectEqual(projection.cell(atRawTick: 0).tickBegin, degenerate[0].tickBegin,
                       cppID: drawerAutomationLayoutID, what: "a degenerate walk stays in the pointer's cell")
}
