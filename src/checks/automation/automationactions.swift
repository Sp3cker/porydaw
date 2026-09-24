import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with automationactions.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationQtModifierMapping(_ report: CheckReport, suite: DocumentSession,
                               service: ProjectService) {
    report.expectEqual(AutomationModifiers(), AutomationQtModifier.automation(0), cppID: drawerAutomationModifierMappingID,
                       what: "no Qt bit arms no policy")
    report.expectEqual(AutomationModifiers(shift: true),
                       AutomationQtModifier.automation(AutomationQtModifier.shift), cppID: drawerAutomationModifierMappingID,
                       what: "Qt's shift bit arms the ramp and axis-lock policy")
    report.expectEqual(AutomationModifiers(snapValue: true),
                       AutomationQtModifier.automation(AutomationQtModifier.control),
                       cppID: drawerAutomationModifierMappingID,
                       what: "Qt's control bit arms the value snap")
    report.expectEqual(AutomationModifiers(fine: true),
                       AutomationQtModifier.automation(AutomationQtModifier.alt), cppID: drawerAutomationModifierMappingID,
                       what: "Qt's alt bit arms the fine lattice")
    report.expectEqual(AutomationModifiers(),
                       AutomationQtModifier.automation(AutomationQtModifier.meta), cppID: drawerAutomationModifierMappingID,
                       what: "Qt's meta bit arms nothing")
    report.expectEqual(AutomationModifiers(fine: true, snapValue: true, shift: true),
                       AutomationQtModifier.automation(AutomationQtModifier.shift
                                                       | AutomationQtModifier.control
                                                       | AutomationQtModifier.alt),
                       cppID: drawerAutomationModifierMappingID,
                       what: "the three policy bits compose through the same mapping")
    for policy in [AutomationModifiers(), AutomationModifiers(fine: true),
                   AutomationModifiers(snapValue: true), AutomationModifiers(shift: true),
                   AutomationModifiers(fine: true, snapValue: true),
                   AutomationModifiers(fine: true, shift: true),
                   AutomationModifiers(snapValue: true, shift: true),
                   AutomationModifiers(fine: true, snapValue: true, shift: true)] {
        report.expectEqual(policy, AutomationQtModifier.automation(drawerAutomationQtModifiers(policy)),
                           cppID: drawerAutomationModifierMappingID,
                           what: "the Qt bits that policy composes to map back to it")
    }

    // The same mapping is the press route's own input: one pan drag inside the
    // neutral radius lands on 64 only when the Qt control bit is carried.
    let plain = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 80)])
    plain.activate(plain.panLane)
    let metadata = AutomationParameterMetadata(parameter: plain.panLane)
    let height = 120.0
    let radius = plain.page.geometry.neutralSnapRadius
    let threshold = Int(Double(metadata.maximum - metadata.minimum) * radius / height)
    report.expect(threshold > 1, cppID: drawerAutomationModifierMappingID,
                  message: "the neutral radius covers more than one value step")
    let near = (metadata.neutral ?? (metadata.maximum + metadata.minimum) / 2)
        + max(1, threshold - 1)
    report.expect(plain.drag(plain.panLane, from: (24, 80), to: near, modifiers: 0),
                  cppID: drawerAutomationModifierMappingID,
                  message: "the pointer route took the drag without a Qt modifier bit")
    report.expectEqual(["24:\(near)"], plain.values(plain.panLane), cppID: drawerAutomationModifierMappingID,
                       what: "a drag without the Qt control bit keeps the dragged value")

    let snapped = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 80)])
    snapped.activate(snapped.panLane)
    report.expect(snapped.drag(snapped.panLane, from: (24, 80), to: near,
                               modifiers: AutomationQtModifier.control),
                  cppID: drawerAutomationModifierMappingID,
                  message: "the pointer route took the drag carrying the Qt control bit")
    report.expectEqual(["24:64"], snapped.values(snapped.panLane), cppID: drawerAutomationModifierMappingID,
                       what: "the Qt control bit a QML event carries lands the drag on the neutral")
}

@MainActor
func drawerAutomationProjectionValueBounds(_ report: CheckReport, suite: DocumentSession,
                                                         service: ProjectService) {
    let id = "automation/AutomationEditingTest::projectionValueBounds"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    let metadata = AutomationParameterMetadata(parameter: fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    let yMin = projection.y(0, metadata: metadata)
    let yMax = projection.y(127, metadata: metadata)
    report.expectEqual(0, projection.value(atY: yMin, metadata: metadata), cppID: id,
                       what: "the value axis minimum maps back to zero")
    report.expectEqual(127, projection.value(atY: yMax, metadata: metadata), cppID: id,
                       what: "the value axis maximum maps back to full scale")
    report.expect(abs(projection.y(64, metadata: metadata) - 60) < 1.0, cppID: id,
                  message: "the neutral value maps within a pixel of the lane midpoint")
    drawerAutomationProjectionInsertionAndPencilClick(report, suite: suite, service: service)
}

@MainActor
func drawerAutomationProjectionInsertionAndPencilClick(_ report: CheckReport, suite: DocumentSession,
                                                        service: ProjectService) {
    let timingID = "automation/AutomationEditingTest::projectionInsertionTiming"
    let clickID = "automation/AutomationEditingTest::pencilClickHalfOpenQuantization"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    fixture.activate(fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: fixture.page.baseFontPx, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    let cell = projection.cell(atRawTick: 24.0)
    let intermediateTick = Double(cell.tickBegin) + 0.4 * Double(projection.snapPolicy.clockTicks)
    let x = fixture.session.camera.contentX(tick: intermediateTick)
    let rawTick = projection.rawTick(atX: x)
    let mappedCell = projection.cell(atRawTick: rawTick)
    let caretTick = projection.tick(atX: x, fine: true)
    report.expect(rawTick != Double(mappedCell.tickBegin) && rawTick != Double(caretTick),
                  cppID: timingID, message: "the intermediate position is neither the cell begin nor caret")
    report.expectEqual(mappedCell.tickBegin, projection.insertionTick(atX: x, pencil: true),
                       cppID: timingID, what: "pencil insertion floors to the half-open cell begin")
    report.expectEqual(caretTick, projection.insertionTick(atX: x, pencil: false),
                       cppID: timingID, what: "non-pencil insertion uses the fine-grid caret")

    fixture.page.isPencilMode = true
    let y = fixture.y(fixture.panLane, 72)
    report.expect(fixture.page.pointerPress(x: x, y: y, surface: AutomationInputSurface.plot.rawValue,
                                            button: AutomationQtButton.left),
                  cppID: clickID, message: "the page starts the pencil click at an intermediate tick")
    report.expect(fixture.page.pointerRelease(x: x, y: y, button: AutomationQtButton.left),
                  cppID: clickID, message: "the page commits the pencil click")
    report.expectEqual([72], fixture.lanePoints(fixture.panLane)
        .filter { $0.tick == mappedCell.tickBegin }.map(\.value),
        cppID: clickID, what: "the first half-open cell holds the clicked value")

    let following = projection.cell(atRawTick: Double(mappedCell.tickEnd))
    report.expect(following.tickBegin < following.tickEnd, cppID: clickID,
                  message: "the following cell is a nonempty half-open interval")
    let nextX = fixture.x(following.tickBegin)
    let nextY = fixture.y(fixture.panLane, 96)
    report.expect(fixture.page.pointerPress(x: nextX, y: nextY,
                                            surface: AutomationInputSurface.plot.rawValue,
                                            button: AutomationQtButton.left),
                  cppID: clickID, message: "the page starts the following cell click")
    report.expect(fixture.page.pointerRelease(x: nextX, y: nextY, button: AutomationQtButton.left),
                  cppID: clickID, message: "the page commits the following cell click")
    report.expectEqual([72], fixture.lanePoints(fixture.panLane)
        .filter { $0.tick == mappedCell.tickBegin }.map(\.value),
        cppID: clickID, what: "the first cell survives the following click")
    report.expectEqual([96], fixture.lanePoints(fixture.panLane)
        .filter { $0.tick == following.tickBegin }.map(\.value),
        cppID: clickID, what: "the following half-open cell holds the second clicked value")
    let biased = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    biased.activate(biased.panLane)
    biased.page.isPencilMode = true
    let biasedRawTick = Double(cell.tickBegin) + 0.75 * Double(cell.tickEnd - cell.tickBegin)
    let biasedX = biased.session.camera.contentX(tick: biasedRawTick)
    report.expect(projection.tick(atX: biasedX, fine: false) != cell.tickBegin,
                  cppID: clickID, message: "a late-cell click differs from the nearest grid tick")
    report.expect(biased.page.pointerPress(x: biasedX, y: biased.y(biased.panLane, 72),
                                           surface: AutomationInputSurface.plot.rawValue,
                                           button: AutomationQtButton.left),
                  cppID: clickID, message: "the page starts a late-cell pencil click")
    report.expect(biased.page.pointerRelease(x: biasedX, y: biased.y(biased.panLane, 72),
                                             button: AutomationQtButton.left),
                  cppID: clickID, message: "the page commits the late-cell click")
    report.expectEqual([72], biased.lanePoints(biased.panLane)
        .filter { $0.tick == cell.tickBegin }.map(\.value),
        cppID: clickID, what: "a late-cell click still writes at the half-open cell begin")
}