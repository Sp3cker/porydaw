import Foundation
import PorydawApp
import PorydawCore
import PorydawProjectService

private let drawerAutomationLayoutGapID = "automation/AutomationEditingTest::publishedLayoutAndZoom"

@MainActor
func drawerAutomationPublishedLayoutAndZoom(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.page.configureBody(width: 640, height: 160, gutter: 56,
                               devicePixelRatio: 1, baseFontPx: 13, dragDistance: 10)
    report.expect(fixture.page.projection != nil, cppID: drawerAutomationLayoutGapID,
                  message: "the active automation plot publishes a projection")
    report.expectEqual(160.0, fixture.page.plotHeight, cppID: drawerAutomationLayoutGapID,
                       what: "the plot body height equals the configured viewport height")
    report.expectEqual(584.0, fixture.page.plotWidth, cppID: drawerAutomationLayoutGapID,
                       what: "the plot body width excludes exactly the gutter")
    report.expectEqual(56.0, fixture.page.plotOrigin, cppID: drawerAutomationLayoutGapID,
                       what: "the automation plot begins at the timeline split")
    report.expect(fixture.page.plotWidth > 0 && fixture.page.plotHeight > 0,
                  cppID: drawerAutomationLayoutGapID,
                  message: "the published automation band is nonempty")
    report.expect(!fixture.page.parameterLabels.isEmpty, cppID: drawerAutomationLayoutGapID,
                  message: "the published gutter exposes parameter labels")

    let splitBefore = fixture.page.plotOrigin
    fixture.page.configureBody(width: 640, height: 80, gutter: 56,
                               devicePixelRatio: 1, baseFontPx: 13, dragDistance: 10)
    report.expectEqual(80.0, fixture.page.plotHeight, cppID: drawerAutomationLayoutGapID,
                       what: "section resize republishes the requested viewport height")
    report.expectEqual(splitBefore, fixture.page.plotOrigin, cppID: drawerAutomationLayoutGapID,
                       what: "section resize preserves the timeline split")
    report.expect(fixture.page.plotWidth > 0 && fixture.page.plotHeight > 0,
                  cppID: drawerAutomationLayoutGapID,
                  message: "the resized plot remains nonempty")

    report.expect(fixture.page.activeParameter == fixture.panLane
                      || fixture.page.activateParameter(fixture.panLane),
                  cppID: drawerAutomationLayoutGapID,
                  message: "wheel-zoom scenario activates Pan")
    let parameterBefore = fixture.page.activeParameter
    let selectionBefore = fixture.page.selection
    let documentBefore = fixture.snapshot
    let cursorBefore = fixture.session.editCursor
    let anchorX = fixture.x(72)
    let tickBefore = fixture.session.camera.tickAtContentX(anchorX)
    let zoomBefore = fixture.session.camera.snapshot.pixelsPerBeat
    _ = fixture.session.mutateCamera {
        _ = $0.zoomAroundContentX(factor: 2, anchorContentX: anchorX)
    }
    report.expect(fixture.session.camera.snapshot.pixelsPerBeat > zoomBefore,
                  cppID: drawerAutomationLayoutGapID,
                  message: "wheel-equivalent camera zoom increases pixels per beat")
    report.expect(abs(fixture.session.camera.tickAtContentX(anchorX) - tickBefore) < 0.001,
                  cppID: drawerAutomationLayoutGapID,
                  message: "anchored zoom preserves the tick under the pointer")
    report.expectEqual(parameterBefore, fixture.page.activeParameter,
                       cppID: drawerAutomationLayoutGapID,
                       what: "camera zoom preserves the active automation parameter")
    report.expectEqual(selectionBefore, fixture.page.selection,
                       cppID: drawerAutomationLayoutGapID,
                       what: "camera zoom preserves automation selection state")

    let heightBefore = fixture.page.plotHeight
    fixture.page.configureBody(width: 640, height: 140, gutter: 56,
                               devicePixelRatio: 1, baseFontPx: 13, dragDistance: 10)
    report.expect(fixture.page.plotHeight != heightBefore, cppID: drawerAutomationLayoutGapID,
                  message: "the resize target differs from the original height")
    report.expectEqual(140.0, fixture.page.plotHeight, cppID: drawerAutomationLayoutGapID,
                       what: "the page publishes the target height")
    report.expectEqual(splitBefore, fixture.page.plotOrigin, cppID: drawerAutomationLayoutGapID,
                       what: "zoom and resize preserve the timeline split")
    report.expectEqual(documentBefore, fixture.snapshot, cppID: drawerAutomationLayoutGapID,
                       what: "zoom and resize preserve document and history state")
    report.expectEqual(cursorBefore, fixture.session.editCursor, cppID: drawerAutomationLayoutGapID,
                       what: "zoom and resize preserve the edit cursor")
}
