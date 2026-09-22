import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

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
