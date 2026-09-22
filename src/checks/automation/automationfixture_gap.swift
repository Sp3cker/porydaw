import Foundation
import PorydawApp
import PorydawCore
import PorydawProjectService

private let drawerAutomationFixtureGapID = "automation/AutomationEditingTest::fixturePreconditions"

@MainActor
func drawerAutomationFixturePreconditions(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(48, 40), (96, 100)], tailTick: 192)

    report.expect(fixture.document.state.tracks.count > 0 && fixture.songEndTick >= 192,
                  cppID: drawerAutomationFixtureGapID,
                  message: "the staged pilot has an editable track and timeline extent")
    report.expect(fixture.page.plotWidth > 0 && fixture.page.plotHeight > 0,
                  cppID: drawerAutomationFixtureGapID,
                  message: "the production page publishes a nonempty plot")
    report.expect(fixture.page.activeParameter == fixture.panLane
                      || fixture.page.activateParameter(fixture.panLane),
                  cppID: drawerAutomationFixtureGapID,
                  message: "the page activates the pilot controller")
    report.expect(AutomationCatalog.index(of: fixture.panLane, track: 0) != nil,
                  cppID: drawerAutomationFixtureGapID,
                  message: "the production catalog resolves the pilot controller")
    report.expect(fixture.page.projection != nil && fixture.page.plotWidth > 0,
                  cppID: drawerAutomationFixtureGapID,
                  message: "the active lane publishes a nonempty input body")
    let point = (x: fixture.x(48), y: fixture.y(fixture.panLane, 40))
    report.expect(point.x >= 0 && point.x <= fixture.page.plotWidth
                      && point.y >= 0 && point.y <= fixture.page.plotHeight,
                  cppID: drawerAutomationFixtureGapID,
                  message: "the staged pilot point lies inside the plot bounds")
    report.expectEqual(40, fixture.lanePoints(fixture.panLane).first { $0.tick == 48 }?.value ?? 0,
                       cppID: drawerAutomationFixtureGapID,
                       what: "the pilot dragged point has its staged value")
    report.expectEqual(100, fixture.lanePoints(fixture.panLane).first { $0.tick == 96 }?.value ?? 0,
                       cppID: drawerAutomationFixtureGapID,
                       what: "the pilot independent point has its staged value")
    fixture.page.plotFocused = true
    report.expect(fixture.page.plotFocused, cppID: drawerAutomationFixtureGapID,
                  message: "the automation plot accepts focus publication")
}
