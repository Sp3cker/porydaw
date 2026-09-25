import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with tst_automationpresentation.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationParameterSwitchAndGhosts(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)], pan: [(24, 64), (120, 40)])
    let before = fixture.snapshot
    let selection = AutomationTimeSelection(range: TimeRange(startTick: 20, endTick: 140),
                                            scope: .lanes, lanes: [fixture.panLane])
    fixture.page.applyTimeSelection(selection)
    let panIndex = AutomationCatalog.index(of: fixture.panLane, track: 0) ?? 0
    report.expect(fixture.page.activateParameter(index: panIndex), cppID: drawerAutomationSwitchID,
                  message: "a parameter switch is accepted")
    report.expectEqual(expected: fixture.panLane, actual: fixture.page.activeParameter, cppID: drawerAutomationSwitchID,
                       what: "the switched parameter becomes active")
    report.expectEqual(expected: panIndex, actual: fixture.page.activeParameterIndex, cppID: drawerAutomationSwitchID,
                       what: "the catalog index follows the switch")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationSwitchID,
                       what: "switching a parameter mutates nothing")
    report.expectEqual(expected: selection, actual: fixture.page.selection, cppID: drawerAutomationSwitchID,
                       what: "switching a parameter keeps the explicit selection")
    report.expectEqual(expected: [fixture.panLane], actual: fixture.page.selectedParameters, cppID: drawerAutomationSwitchID,
                       what: "the inactive parameter's selection indicator survives the switch")
    report.expectEqual(expected: "Pan (PAN)", actual: AutomationCatalog.title(fixture.page.activeParameter),
                       cppID: drawerAutomationSwitchID, what: "the active lane title is the switched parameter's")
    report.expectEqual(expected: 2, actual: fixture.page.laneCount, cppID: drawerAutomationSwitchID,
                       what: "the active lane publishes its written-event count")
    report.expectEqual(expected: fixture.projection(fixture.panLane).points.map(\.x), actual: fixture.page.projection?.points.map(\.x) ?? [], cppID: drawerAutomationSwitchID,
                       what: "the active projection is the switched parameter's")
    report.expect(!fixture.page.activateParameter(index: panIndex), cppID: drawerAutomationSwitchID,
                  message: "re-activating the active parameter is not a switch")
    report.expect(!fixture.page.activateParameter(index: AutomationCatalog.count), cppID: drawerAutomationSwitchID,
                  message: "an index outside the catalog is rejected")

    // Ghosts keep their pins while they carry events.
    let volumeIndex = AutomationCatalog.index(of: fixture.volumeLane, track: 0) ?? 0
    report.expect(fixture.page.toggleGhostParameter(index: volumeIndex), cppID: drawerAutomationSwitchID,
                  message: "a parameter with events can be pinned as a ghost")
    report.expectEqual(expected: ["Volume (VOL) · 2 Events"], actual: fixture.page.ghostLabels, cppID: drawerAutomationSwitchID,
                       what: "the ghost label counts the lane's written events")
    report.expect(fixture.page.toggleGhostParameter(index: volumeIndex), cppID: drawerAutomationSwitchID,
                  message: "the same parameter unpins")
    report.expectEqual(expected: [String](), actual: fixture.page.ghostLabels, cppID: drawerAutomationSwitchID,
                       what: "unpinning drops the label")
    report.expect(fixture.page.toggleGhostParameter(index: volumeIndex), cppID: drawerAutomationSwitchID,
                  message: "the ghost pins again")
    report.expect(fixture.page.toggleGhostParameter(index: panIndex), cppID: drawerAutomationSwitchID,
                  message: "toggling the active parameter clears its ghosts")
    report.expectEqual(expected: [String](), actual: fixture.page.ghostLabels, cppID: drawerAutomationSwitchID,
                       what: "the active parameter owns every pin")
    let emptyIndex = AutomationCatalog.index(of: fixture.echoLane, track: 0) ?? 0
    report.expect(!fixture.page.toggleGhostParameter(index: emptyIndex), cppID: drawerAutomationSwitchID,
                  message: "a parameter with no events cannot be pinned")

    // Tempo is always addressable, even without a selected track.
    fixture.session.selectedTrack = nil
    fixture.page.refreshFromDocument()
    report.expectEqual(expected: AutomationPagePolicy.noTrackMessage, actual: fixture.page.plotMessage,
                       cppID: drawerAutomationSwitchID,
                       what: "no selected track publishes the missing-track message")
    report.expect(fixture.page.activateParameter(index: AutomationCatalog.count - 1), cppID: drawerAutomationSwitchID,
                  message: "Tempo stays selectable without a track")
    report.expectEqual(expected: AutomationParameter.tempo, actual: fixture.page.activeParameter, cppID: drawerAutomationSwitchID,
                       what: "Tempo becomes the active parameter")
    report.expectEqual(expected: "", actual: fixture.page.plotMessage, cppID: drawerAutomationSwitchID,
                       what: "Tempo's plot presents without a selected track")
    report.expectEqual(expected: 1, actual: fixture.page.laneCount, cppID: drawerAutomationSwitchID,
                       what: "Tempo publishes its own event count")
    fixture.session.selectedTrack = 0
    fixture.page.refreshFromDocument()
    report.expectEqual(expected: "", actual: fixture.page.plotMessage, cppID: drawerAutomationSwitchID,
                       what: "a selected track presents again")
}

let drawerAutomationCursorKindID = "swiftcore/AutomationPage::pencilCursorKind"

@MainActor
func drawerAutomationPencilCursorKind(_ report: CheckReport, suite: DocumentSession,
                                     service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    report.expectEqual(expected: AutomationCursorKind.arrow.rawValue, actual: page.cursorKind,
                       cppID: drawerAutomationCursorKindID, what: "the plot starts with the arrow")
    page.isPencilMode = true
    let pressX = fixture.x(72)
    let pressY = fixture.y(fixture.panLane, 64)
    let pencilBefore = fixture.snapshot
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: AutomationQtButton.left)
    _ = page.pointerRelease(x: pressX, y: pressY, button: AutomationQtButton.left)
    report.expectEqual(expected: AutomationCursorKind.pencil.rawValue, actual: page.cursorKind,
                       cppID: drawerAutomationCursorKindID,
                       what: "a pencil release arms the pencil cursor")
    report.expectEqual(expected: pencilBefore.revision + 1, actual: fixture.document.revision,
                       cppID: drawerAutomationCursorKindID, what: "the pencil stroke is one revision")
    page.isPencilMode = false
    page.cancelSectionInteraction()
    if let node = fixture.projection(fixture.panLane).points.first(where: { $0.tick == 24 }) {
        _ = page.pointerPress(x: node.x, y: node.y, surface: 1,
                              button: AutomationQtButton.left, modifiers: AutomationQtModifier.shift)
        _ = page.pointerMove(x: node.x + 30, y: node.y, buttons: AutomationQtButton.left,
                             modifiers: AutomationQtModifier.shift)
        _ = page.pointerMove(x: node.x + 34, y: node.y, buttons: AutomationQtButton.left,
                             modifiers: AutomationQtModifier.shift)
        report.expectEqual(expected: AutomationCursorKind.sizeHorizontal.rawValue, actual: page.cursorKind,
                           cppID: drawerAutomationCursorKindID,
                           what: "a Shift node drag locks the time axis")
        _ = page.pointerRelease(x: node.x + 34, y: node.y, button: AutomationQtButton.left,
                                modifiers: AutomationQtModifier.shift)
        report.expectEqual(expected: AutomationCursorKind.arrow.rawValue, actual: page.cursorKind,
                           cppID: drawerAutomationCursorKindID,
                           what: "releasing the drag reverts to the arrow")
    } else {
        report.fail(drawerAutomationCursorKindID, "the pan lane projected no node at tick 24")
    }
}
