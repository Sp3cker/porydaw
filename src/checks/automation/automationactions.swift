import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

// Existing scenarios paired with automationactions.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationQtModifierMapping(_ report: CheckReport, suite: DocumentSession,
                               service: ProjectService) {
    report.expectEqual(AutomationModifiers(), drawerAutomationDecodedModifiers(0), cppID: drawerAutomationModifierMappingID,
                       what: "no Qt bit arms no policy")
    report.expectEqual(AutomationModifiers(shift: true),
                       drawerAutomationDecodedModifiers(DrawerModifiers.shiftBit), cppID: drawerAutomationModifierMappingID,
                       what: "Qt's shift bit arms the ramp and axis-lock policy")
    report.expectEqual(AutomationModifiers(snapValue: true),
                       drawerAutomationDecodedModifiers(DrawerModifiers.controlBit),
                       cppID: drawerAutomationModifierMappingID,
                       what: "Qt's control bit arms the value snap")
    report.expectEqual(AutomationModifiers(fine: true),
                       drawerAutomationDecodedModifiers(DrawerModifiers.altBit), cppID: drawerAutomationModifierMappingID,
                       what: "Qt's alt bit arms the fine lattice")
    report.expectEqual(AutomationModifiers(),
                       drawerAutomationDecodedModifiers(DrawerModifiers.metaBit), cppID: drawerAutomationModifierMappingID,
                       what: "Qt's meta bit arms nothing")
    report.expectEqual(AutomationModifiers(fine: true, snapValue: true, shift: true),
                       drawerAutomationDecodedModifiers(DrawerModifiers.shiftBit
                                                       | DrawerModifiers.controlBit
                                                       | DrawerModifiers.altBit),
                       cppID: drawerAutomationModifierMappingID,
                       what: "the three policy bits compose through the same mapping")
    for policy in [AutomationModifiers(), AutomationModifiers(fine: true),
                   AutomationModifiers(snapValue: true), AutomationModifiers(shift: true),
                   AutomationModifiers(fine: true, snapValue: true),
                   AutomationModifiers(fine: true, shift: true),
                   AutomationModifiers(snapValue: true, shift: true),
                   AutomationModifiers(fine: true, snapValue: true, shift: true)] {
        report.expectEqual(policy, drawerAutomationDecodedModifiers(drawerAutomationQtModifiers(policy)),
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
                               modifiers: DrawerModifiers.controlBit),
                  cppID: drawerAutomationModifierMappingID,
                  message: "the pointer route took the drag carrying the Qt control bit")
    report.expectEqual(["24:64"], snapped.values(snapped.panLane), cppID: drawerAutomationModifierMappingID,
                       what: "the Qt control bit a QML event carries lands the drag on the neutral")
}

@MainActor
func drawerAutomationActionShortcutContracts(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service)
    let policy = editCommandPolicy(.pencilMode)
    report.expect(policy.command == .pencilMode && policy.standaloneOperation == .pencilToggle,
                  cppID: drawerAutomationModifierMappingID,
                  message: "the canonical action table contains the Pencil toggle command")
    report.expect(policy.keyRoute == .availabilityGated
                      && policy.autoRepeatRule == .consumeWhenEligible,
                  cppID: drawerAutomationModifierMappingID,
                  message: "Pencil has the canonical gated repeat policy")

    func decision(autoRepeat: Bool, command: EditCommand? = .pencilMode) -> EditKeyDecision {
        EditKeyArbiter.decide(
            command: command,
            surface: EditSurfaceState(pointerGestureActive: false,
                                      timeSelectionActive: false,
                                      noteSelectionEmpty: true,
                                      origin: .timeline,
                                      autoRepeat: autoRepeat,
                                      commandAvailable: true))
    }
    func execute(_ route: EditKeyDecision) {
        if route == .execute { fixture.page.isPencilMode.toggle() }
    }

    fixture.page.isPencilMode = false
    execute(decision(autoRepeat: false))
    report.expect(fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "the first shortcut press checks Pencil")
    report.expect(fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "shortcut release leaves the latched action checked")
    execute(decision(autoRepeat: false))
    report.expect(!fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "the second shortcut press unchecks Pencil")
    report.expect(!fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "second shortcut release leaves Pencil unchecked")

    execute(decision(autoRepeat: false))
    report.expect(fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "a real shortcut press checks Pencil before repeat delivery")
    report.expect(decision(autoRepeat: true) == .consume,
                  cppID: drawerAutomationModifierMappingID,
                  message: "an auto-repeat shortcut press is consumed without execution")
    execute(decision(autoRepeat: true))
    report.expect(fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "auto-repeat leaves the Pencil latch checked")
    report.expect(fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "repeat release leaves Pencil checked")
    fixture.page.isPencilMode = false
    report.expect(decision(autoRepeat: false, command: nil) == .decline,
                  cppID: drawerAutomationModifierMappingID,
                  message: "an unbound text key stays with its text owner")
    report.expect(!fixture.page.isPencilMode, cppID: drawerAutomationModifierMappingID,
                  message: "text input does not toggle Pencil")
}
