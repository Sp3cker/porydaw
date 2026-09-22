import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

private let automationHoverGapID = "automation-hover/AutomationHoverTest::swiftPortableGaps"

@MainActor
func drawerAutomationHoverPortableGaps(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let before = fixture.snapshot

    let hoverRows: [(id: String, x: Double, y: Double)] = [
        ("A013-direct", fixture.x(24), fixture.y(fixture.panLane, 64)),
        ("A033-idle", fixture.x(80), fixture.y(fixture.panLane, 90)),
        ("A049-repeat", fixture.x(24), fixture.y(fixture.panLane, 64)),
    ]
    for row in hoverRows {
        _ = page.pointerMove(x: row.x, y: row.y, buttons: 0, modifiers: 0)
        _ = page.pointerMove(x: row.x, y: row.y, buttons: 0, modifiers: 0)
        report.expectEqual(before, fixture.snapshot, cppID: automationHoverGapID,
                           what: "\(row.id) hover preserves document state")
    }
    page.pointerLeave()
    report.expectEqual(before, fixture.snapshot, cppID: automationHoverGapID,
                       what: "A058 leave clears hover without mutating the document")

    report.expect(page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                                    surface: AutomationInputSurface.plot.rawValue, button: 1,
                                    modifiers: 0),
                  cppID: automationHoverGapID,
                  message: "A017 a node press establishes the cancellable grab")
    page.cancelSectionInteraction()
    report.expectEqual(before, fixture.snapshot, cppID: automationHoverGapID,
                       what: "A017 cancellation preserves document state")

    report.expect(page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64),
                                    surface: AutomationInputSurface.plot.rawValue, button: 1,
                                    modifiers: 0),
                  cppID: automationHoverGapID,
                  message: "A023 a second node press establishes the deactivation case")
    page.cancelSectionInteraction()
    report.expectEqual(before, fixture.snapshot, cppID: automationHoverGapID,
                       what: "A023 deactivation cancellation preserves document state")

    let fine = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    fine.activate(fine.panLane)
    let fineBefore = fine.snapshot
    let pressX = fine.x(24)
    let pressY = fine.y(fine.panLane, 64)
    let endX = fine.x(82)
    let endY = -40.0
    report.expect(fine.page.pointerPress(x: pressX, y: pressY,
                                         surface: AutomationInputSurface.plot.rawValue,
                                         button: 1, modifiers: 0),
                  cppID: automationHoverGapID,
                  message: "A133 fine sweep starts through the production plot seam")
    _ = fine.page.pointerMove(x: pressX + 20, y: pressY, buttons: 1, modifiers: 0)
    _ = fine.page.pointerMove(x: endX, y: endY, buttons: 1,
                              modifiers: DrawerModifiers.altBit)
    let fineEndpoint = fine.page.previewPoints.last
    report.expect(fineEndpoint != nil, cppID: automationHoverGapID,
                  message: "A133 fine sweep publishes an endpoint")
    report.expectEqual(127, fineEndpoint?.value ?? -1, cppID: automationHoverGapID,
                       what: "A137 endpoint value clamps to the lane maximum")
    _ = fine.page.pointerRelease(x: endX, y: endY, button: 1,
                                 modifiers: DrawerModifiers.altBit)
    let fineWritten = fineEndpoint.flatMap { endpoint in
        fine.lanePoints(fine.panLane).first { $0.tick == endpoint.tick }
    }
    report.expect(fineWritten != nil, cppID: automationHoverGapID,
                  message: "A136 released fine endpoint exists in the document")
    report.expectEqual(fineEndpoint?.value, fineWritten?.value, cppID: automationHoverGapID,
                       what: "A137 released fine endpoint keeps the clamped value")
    report.expect(fine.snapshot != fineBefore, cppID: automationHoverGapID,
                  message: "A138 released fine sweep changes the document")
    report.expect(fine.undo(), cppID: automationHoverGapID,
                  message: "A139 fine sweep undo is accepted")
    report.expectEqual(fineBefore, fine.snapshot, cppID: automationHoverGapID,
                       what: "A139 fine sweep undo restores document state")
    report.expect(fineEndpoint.map { endpoint in
        !fine.lanePoints(fine.panLane).contains { $0.tick == endpoint.tick }
    } ?? false, cppID: automationHoverGapID,
                  message: "A140 fine endpoint is absent after undo")

    let ramp = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    ramp.activate(ramp.panLane)
    let rampBefore = ramp.snapshot
    let rampStartX = ramp.x(24)
    let rampStartY = ramp.y(ramp.panLane, 32)
    let rampEndX = ramp.x(168)
    let rampEndY = ramp.y(ramp.panLane, 112)
    report.expect(ramp.page.pointerPress(x: rampStartX, y: rampStartY,
                                         surface: AutomationInputSurface.plot.rawValue,
                                         button: 1, modifiers: DrawerModifiers.shiftBit),
                  cppID: automationHoverGapID,
                  message: "A141 Shift press captures ramp mode")
    _ = ramp.page.pointerMove(x: ramp.x(96), y: ramp.y(ramp.panLane, 127),
                              buttons: 1, modifiers: 0)
    _ = ramp.page.pointerMove(x: rampEndX, y: rampEndY, buttons: 1, modifiers: 0)
    let rampPreview = ramp.page.previewPoints
    report.expect(rampPreview.count >= 3, cppID: automationHoverGapID,
                  message: "A141 ramp preview contains endpoints and an interior cell")
    guard let first = rampPreview.first, let last = rampPreview.last,
          let middle = rampPreview.dropFirst().dropLast().first else {
        ramp.page.cancelSectionInteraction()
        return
    }
    let span = max(1, last.tick - first.tick)
    let expectedMiddle = Int((Double(first.value) + Double(last.value - first.value)
        * Double(middle.tick - first.tick) / Double(span)).rounded())
    report.expect(middle.value != 127, cppID: automationHoverGapID,
                  message: "A143 captured ramp ignores the off-line dip value")
    _ = ramp.page.pointerRelease(x: rampEndX, y: rampEndY, button: 1, modifiers: 0)
    let written = ramp.lanePoints(ramp.panLane)
    report.expect(written.contains { $0.tick == first.tick && $0.value == first.value },
                  cppID: automationHoverGapID,
                  message: "A145-A146 ramp writes its captured start endpoint")
    report.expect(written.contains { $0.tick == last.tick && $0.value == last.value },
                  cppID: automationHoverGapID,
                  message: "A147-A148 ramp writes its release endpoint")
    report.expect(written.contains { $0.tick == middle.tick && $0.value == expectedMiddle },
                  cppID: automationHoverGapID,
                  message: "A149-A150 ramp writes a linearly interpolated interior point")
    report.expect(written.first { $0.tick == middle.tick }?.value != 127,
                  cppID: automationHoverGapID,
                  message: "A151 ramp interior differs from the dip")
    report.expect(ramp.undo(), cppID: automationHoverGapID,
                  message: "A152 ramp undo is accepted")
    report.expectEqual(rampBefore, ramp.snapshot, cppID: automationHoverGapID,
                       what: "A152 ramp undo restores document state")
    report.expect(!ramp.lanePoints(ramp.panLane).contains { $0.tick == middle.tick },
                  cppID: automationHoverGapID,
                  message: "A153 ramp interior is absent after undo")
}
