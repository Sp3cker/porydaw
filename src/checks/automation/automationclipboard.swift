import Foundation
import PorydawApp
import PorydawCore
import PorydawBankLease

// Existing scenarios paired with automationclipboard.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationRangeEditAndClipboard(_ report: CheckReport, suite: DocumentSession,
                                   service: ProjectService) {
    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    _ = pd_clipboard_write(nil, 0)
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 30), (120, 40)],
                                    tempo: [(0, 500_000), (48, 400_000)])
    fixture.activate(fixture.panLane)
    func pasteRowEnabled() -> Bool? {
        let x = fixture.x(80)
        let y = fixture.y(fixture.panLane, 80)
        _ = fixture.page.pointerPress(x: x, y: y, surface: AutomationInputSurface.plot.rawValue,
                                      button: AutomationQtButton.right, modifiers: 0)
        _ = fixture.page.pointerRelease(x: x, y: y, button: AutomationQtButton.right, modifiers: 0)
        defer { fixture.page.dismissMenu() }
        return fixture.page.publishedMenuRows.first {
            $0.actionId == AutomationMenuAction.rangePaste.rawValue
        }?.enabled
    }
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 130), scope: .lanes,
        lanes: [fixture.panLane], tempo: true))
    report.expect(pasteRowEnabled() == false, cppID: drawerAutomationRangeID,
                  message: "the range menu refuses Paste when the system clipboard is empty")
    report.expect(!fixture.page.selectionCommandAvailable(command: .paste), cppID: drawerAutomationRangeID,
                  message: "the window Paste command is unavailable for an empty clipboard")
    report.expect(fixture.page.copyTimeSelection(), cppID: drawerAutomationRangeID,
                  message: "the selection copies into the semantic clipboard")
    report.expect(fixture.page.hasClipboard, cppID: drawerAutomationRangeID,
                  message: "the clipboard publishes its semantic payload")
    report.expect(pasteRowEnabled() == true, cppID: drawerAutomationRangeID,
                  message: "the range menu enables Paste for a copied system selection")
    report.expect(fixture.page.selectionCommandAvailable(command: .paste), cppID: drawerAutomationRangeID,
                  message: "the window Paste command becomes available for the copied selection")
    let beforePaste = fixture.snapshot
    report.expectEqual(expected: 310, actual: fixture.page.pasteTimeSelection(at: 200).map(Int.init) ?? -1,
                       cppID: drawerAutomationRangeID,
                       what: "the paste cursor lands one span after the destination")
    report.expectEqual(expected: ["24:30", "120:40", "204:30", "300:40"], actual: fixture.values(fixture.panLane),
                       cppID: drawerAutomationRangeID,
                       what: "the pasted lane writes its relative points at the destination")
    report.expectEqual(expected: ["0:120", "48:150", "228:150"], actual: fixture.tempoValues, cppID: drawerAutomationRangeID,
                       what: "the pasted tempo point merges at its destination tick")
    report.expectEqual(expected: beforePaste.revision + 1, actual: fixture.document.revision, cppID: drawerAutomationRangeID,
                       what: "one paste is one document revision")
    report.expect(fixture.undo(), cppID: drawerAutomationRangeID, message: "the paste is undoable")
    report.expectEqual(expected: ["24:30", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationRangeID,
                       what: "one undo removes the pasted lane points")
    report.expectEqual(expected: ["0:120", "48:150"], actual: fixture.tempoValues, cppID: drawerAutomationRangeID,
                       what: "one undo removes the pasted tempo point")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationRangeID,
                  message: "one undo consumes the paste's single history entry")

    let cut = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 30), (120, 40)])
    cut.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 100), scope: .lanes, lanes: [cut.panLane]))
    let cutBefore = cut.snapshot
    report.expect(cut.page.cutTimeSelection(), cppID: drawerAutomationRangeID,
                  message: "the cut copies and deletes in one document write")
    report.expectEqual(expected: ["120:40"], actual: cut.values(cut.panLane), cppID: drawerAutomationRangeID,
                       what: "the cut removes only the covered span")
    report.expectEqual(expected: cutBefore.revision + 1, actual: cut.document.revision, cppID: drawerAutomationRangeID,
                       what: "the cut is one revision")
    report.expect(cut.page.hasClipboard && cut.undo(), cppID: drawerAutomationRangeID,
                  message: "the cut keeps its payload and is undoable")
    report.expectEqual(expected: ["24:30", "120:40"], actual: cut.values(cut.panLane), cppID: drawerAutomationRangeID,
                       what: "one undo restores the cut span")
    report.expect(!cut.document.history.canUndo, cppID: drawerAutomationRangeID,
                  message: "one undo consumes the cut's single history entry")

    // Lane copy is cross-parameter but must not overwrite the system range clip.
    cut.activate(cut.panLane)
    _ = cut.page.openParameterMenu(index: cut.page.catalogIndex(of: cut.panLane), x: 0, y: 0)
    report.expect(cut.page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                  cppID: drawerAutomationRangeID, message: "lane menu copies its absolute points")
    cut.activate(cut.volumeLane)
    _ = cut.page.openParameterMenu(index: cut.page.catalogIndex(of: cut.volumeLane), x: 0, y: 0)
    report.expect(cut.page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue),
                  cppID: drawerAutomationRangeID, message: "lane menu pastes into another parameter")
    report.expectEqual(expected: ["24:30", "120:40"], actual: cut.values(cut.volumeLane), cppID: drawerAutomationRangeID,
                       what: "lane paste preserves absolute ticks across parameters")
    cut.page.detach()
    let otherDocument = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    report.expectEqual(expected: 280, actual: otherDocument.page.pasteTimeSelection(at: 200).map(Int.init) ?? -1,
                       cppID: drawerAutomationRangeID, what: "the native range clip survives lane copy and detach")
    report.expectEqual(expected: ["204:30"], actual: otherDocument.values(otherDocument.panLane), cppID: drawerAutomationRangeID,
                       what: "another document pastes the shared range clip, not the lane buffer")

    // A whole-lane replacement keeps the lane's own point rules.
    let replace = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 30)])
    replace.activate(replace.panLane)
    let edit = AutomationRangeEditor.replaceLane(
        replace.facts(replace.panLane),
        points: [AutomationLanePoint(tick: 48, value: 200),
                 AutomationLanePoint(tick: 48, value: 20),
                 AutomationLanePoint(tick: 96, value: -5)])
    report.expect(!edit.unchanged, cppID: drawerAutomationRangeID,
                  message: "a replacement that differs from the lane is a change")
    report.expectEqual(expected: Tick(0), actual: edit.tickBegin, cppID: drawerAutomationRangeID,
                       what: "a whole-lane replacement starts at tick zero")
    report.expectEqual(expected: TimeDefaults.noTick, actual: edit.tickEnd, cppID: drawerAutomationRangeID,
                       what: "a whole-lane replacement covers the whole lane")
    report.expect(AutomationCommit.apply(edit, in: replace.document), cppID: drawerAutomationRangeID,
                  message: "the replacement commits through one lane write")
    report.expectEqual(expected: ["48:20", "96:0"], actual: replace.values(replace.panLane), cppID: drawerAutomationRangeID,
                       what: "the replacement deduplicates by tick and clamps into the domain")
    let clear = AutomationRangeEditor.replaceLane(replace.facts(replace.panLane), points: [])
    report.expect(AutomationCommit.apply(clear, in: replace.document), cppID: drawerAutomationRangeID,
                  message: "clearing the lane writes once")
    report.expectEqual(expected: 0, actual: replace.lanePoints(replace.panLane).count, cppID: drawerAutomationRangeID,
                       what: "clearing removes every written point")
    report.expect(AutomationRangeEditor.replaceLane(replace.facts(replace.panLane),
                                                    points: []).unchanged,
                  cppID: drawerAutomationRangeID, message: "clearing an empty lane is unchanged")
}

@MainActor
func drawerAutomationCrossLanePasteClamps(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    let id = "automation/AutomationEditingTest::clipboardCrossLanePasteClamps"
    let lfo = AutomationParameter.controlChange(track: 0, controller: 21)
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(96, TimeDefaults.microsecondsPerQuarterNote(forBPM: 300))])
    fixture.document.writeLane(track: 0, lane: .controller(21), from: 0,
                               through: TimeDefaults.maxTick,
                               points: [LaneWrite(tick: 96, value: 96)])
    let page = fixture.page
    fixture.activate(.tempo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: .tempo), x: 0, y: 0),
                  cppID: id, message: "the tempo label opens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                  cppID: id, message: "the tempo Copy row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Copy tempo pick closes the menu")
    fixture.activate(lfo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: lfo), x: 0, y: 0),
                  cppID: id, message: "the CC label opens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue),
                  cppID: id, message: "the Paste CC row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Paste CC pick closes the menu")
    report.expectEqual(expected: ["96:127"], actual: fixture.values(lfo), cppID: id,
                       what: "the pasted tempo point clamps into the CC domain at its tick")
    fixture.document.writeLane(track: 0, lane: .controller(21), from: 0,
                               through: TimeDefaults.maxTick,
                               points: [LaneWrite(tick: 144, value: 0)])
    fixture.activate(lfo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: lfo), x: 0, y: 0),
                  cppID: id, message: "the CC label reopens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                  cppID: id, message: "the Copy CC row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Copy CC pick closes the menu")
    fixture.activate(.tempo)
    report.expect(page.openParameterMenu(index: page.catalogIndex(of: .tempo), x: 0, y: 0),
                  cppID: id, message: "the tempo label reopens its lane menu")
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue),
                  cppID: id, message: "the Paste tempo row is consumed")
    report.expect(!page.menuOpen, cppID: id, message: "the Paste tempo pick closes the menu")
    let pasted = fixture.document.state.tempo
    report.expectEqual(expected: 1, actual: pasted.count, cppID: id,
                       what: "the pasted CC point replaces the tempo stream")
    report.expectEqual(expected: Tick(144), actual: pasted.first?.tick ?? Tick.max, cppID: id,
                       what: "the pasted tempo point keeps the CC tick")
    report.expectEqual(expected: TimeDefaults.microsecondsPerQuarterNote(forBPM: TimeDefaults.minimumTempoBPM), actual:
                       pasted.first?.microsecondsPerQuarterNote ?? 0, cppID: id,
                       what: "the pasted tempo point clamps to the slowest tempo")
}
