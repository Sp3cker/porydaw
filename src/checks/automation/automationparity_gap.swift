import Foundation
import PorydawApp
import PorydawCore
import PorydawProjectService

private let drawerAutomationParityGapID = "automation/AutomationEditingTest::hoverStationaryAndDoubleClick"

@MainActor
func drawerAutomationHoverStationaryAndDoubleClickParity(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let rows: [(name: String, parameter: AutomationParameter)] = [
        ("tempo", .tempo),
        ("cc", .controlChange(track: 0, controller: 10)),
    ]

    func make(_ row: (name: String, parameter: AutomationParameter))
        -> drawerAutomationAutomationFixture {
        if row.parameter == .tempo {
            return drawerAutomationAutomationFixture(
                suite: suite, service: service,
                tempo: [(0, TimeDefaults.microsecondsPerQuarterNote(forBPM: 80)),
                        (96, TimeDefaults.microsecondsPerQuarterNote(forBPM: 100)),
                        (288, TimeDefaults.microsecondsPerQuarterNote(forBPM: 64))])
        }
        return drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(0, 80), (96, 100), (288, 64)])
    }

    func values(_ fixture: drawerAutomationAutomationFixture,
                _ parameter: AutomationParameter) -> [String] {
        parameter == .tempo ? fixture.tempoValues : fixture.values(parameter)
    }

    for row in rows {
        let hover = make(row)
        let laneValid = AutomationCatalog.index(of: row.parameter, track: 0) != nil
        report.expect(laneValid, cppID: drawerAutomationParityGapID,
                      message: "A001-\(row.name): the production catalog resolves the lane")
        report.expect(hover.page.activeParameter == row.parameter
                          || hover.page.activateParameter(row.parameter),
                      cppID: drawerAutomationParityGapID,
                      message: "A002-\(row.name): the page activates the lane")
        let beforeHover = hover.snapshot
        _ = hover.page.pointerMove(x: hover.x(48), y: hover.y(row.parameter, 90), buttons: 0,
                                   modifiers: 0)
        report.expectEqual(beforeHover, hover.snapshot, cppID: drawerAutomationParityGapID,
                           what: "A005-\(row.name): hover publishes no document edit")

        let stationary = make(row)
        report.expect(AutomationCatalog.index(of: row.parameter, track: 0) != nil,
                      cppID: drawerAutomationParityGapID,
                      message: "A006-\(row.name): the stationary lane resolves")
        report.expect(stationary.page.activeParameter == row.parameter
                          || stationary.page.activateParameter(row.parameter),
                      cppID: drawerAutomationParityGapID,
                      message: "A007-\(row.name): the stationary lane activates")
        let beforeDelete = stationary.snapshot
        let nodeX = stationary.x(96)
        let nodeY = stationary.y(row.parameter, 100)
        _ = stationary.page.pointerPress(x: nodeX, y: nodeY,
                                         surface: AutomationInputSurface.plot.rawValue,
                                         button: 1, modifiers: 0)
        _ = stationary.page.pointerRelease(x: nodeX, y: nodeY, button: 1, modifiers: 0)
        report.expectEqual(beforeDelete.revision + 1, stationary.document.revision,
                           cppID: drawerAutomationParityGapID,
                           what: "A008-\(row.name): stationary release commits one revision")
        report.expectEqual(["0:80", "288:64"], values(stationary, row.parameter),
                           cppID: drawerAutomationParityGapID,
                           what: "A010-\(row.name): stationary release deletes only the node")
        report.expect(stationary.undo() && !stationary.document.history.canUndo,
                      cppID: drawerAutomationParityGapID,
                      message: "A009-\(row.name): exactly one undo entry restores the delete")

        let shifted = make(row)
        _ = shifted.page.activateParameter(row.parameter)
        let beforeShift = shifted.snapshot
        let shiftX = shifted.x(96)
        let shiftY = shifted.y(row.parameter, 100)
        _ = shifted.page.pointerPress(x: shiftX, y: shiftY,
                                      surface: AutomationInputSurface.plot.rawValue,
                                      button: 1, modifiers: DrawerModifiers.shiftBit)
        _ = shifted.page.pointerRelease(x: shiftX, y: shiftY,
                                        button: 1, modifiers: DrawerModifiers.shiftBit)
        report.expectEqual(beforeShift, shifted.snapshot, cppID: drawerAutomationParityGapID,
                           what: "A013-\(row.name): Shift stationary release publishes no edit")
        report.expectEqual(["0:80", "96:100", "288:64"], values(shifted, row.parameter),
                           cppID: drawerAutomationParityGapID,
                           what: "A014-\(row.name): Shift stationary release preserves every point")

        let doubleClick = make(row)
        report.expect(AutomationCatalog.index(of: row.parameter, track: 0) != nil,
                      cppID: drawerAutomationParityGapID,
                      message: "A015-\(row.name): the double-click lane resolves")
        report.expect(doubleClick.page.activeParameter == row.parameter
                          || doubleClick.page.activateParameter(row.parameter),
                      cppID: drawerAutomationParityGapID,
                      message: "A016-\(row.name): the double-click lane activates")
        let doubleBefore = doubleClick.snapshot
        let doubleX = doubleClick.x(96)
        let doubleY = doubleClick.y(row.parameter, 100)
        _ = doubleClick.page.pointerPress(x: doubleX, y: doubleY,
                                          surface: AutomationInputSurface.plot.rawValue,
                                          button: 1, modifiers: 0)
        _ = doubleClick.page.pointerRelease(x: doubleX, y: doubleY, button: 1, modifiers: 0)
        _ = doubleClick.page.pointerDoubleClick(x: doubleX, y: doubleY)
        report.expect(!doubleClick.page.hasPrompt, cppID: drawerAutomationParityGapID,
                      message: "A019-\(row.name): double-click leaves no value prompt")
        report.expectEqual(doubleBefore.revision + 1, doubleClick.document.revision,
                           cppID: drawerAutomationParityGapID,
                           what: "A020-A022-\(row.name): double-click publishes one revision")
        report.expectEqual(["0:80", "288:64"], values(doubleClick, row.parameter),
                           cppID: drawerAutomationParityGapID,
                           what: "A025-\(row.name): double-click deletes only the target node")
        report.expect(doubleClick.undo() && !doubleClick.document.history.canUndo,
                      cppID: drawerAutomationParityGapID,
                      message: "A023-A024-\(row.name): double-click records one undo entry")
    }
}
