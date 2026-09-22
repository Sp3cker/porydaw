import Foundation
import PorydawApp
import PorydawCore
import PorydawProjectService

// Existing scenarios paired with painting.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationScaleLabelsAndLaneCounts(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)], pan: [(24, 64)])
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual([AutomationScaleLabel.Role.maximum, .minimum, .neutral],
                       pan.scaleLabels.map(\.role), cppID: drawerAutomationLabelsID,
                       what: "a centered parameter emits maximum, minimum and neutral labels")
    report.expectEqual(["c_v+63", "c_v-64", "c_v+0"], pan.scaleLabels.map(\.text), cppID: drawerAutomationLabelsID,
                       what: "the scale labels use the parameter's own formatting")
    report.expectEqual(64, pan.scaleLabels[2].value, cppID: drawerAutomationLabelsID,
                       what: "the neutral label names the neutral value")
    report.expect(pan.scaleLabels[0].y < pan.scaleLabels[2].y
                      && pan.scaleLabels[2].y < pan.scaleLabels[1].y,
                  cppID: drawerAutomationLabelsID,
                  message: "maximum, neutral and minimum sit at their curve-true heights")

    let volume = fixture.projection(fixture.volumeLane)
    report.expectEqual([AutomationScaleLabel.Role.maximum, .minimum],
                       volume.scaleLabels.map(\.role), cppID: drawerAutomationLabelsID,
                       what: "a parameter without a neutral emits only its extremes")
    report.expectEqual(["127", "0"], volume.scaleLabels.map(\.text), cppID: drawerAutomationLabelsID,
                       what: "Volume's scale labels are its raw values")
    report.expectEqual(["255", "20"], fixture.projection(.tempo).scaleLabels.map(\.text),
                       cppID: drawerAutomationLabelsID,
                       what: "Tempo's scale labels are its BPM bounds with no neutral")
    report.expectEqual(["+8191", "-8192", "0"], fixture.projection(fixture.bendLane)
        .scaleLabels.map(\.text), cppID: drawerAutomationLabelsID,
                       what: "Bend's scale labels take the bend format path")

    let stack = AutomationRowStack.build(document: fixture.document, primaryTrack: 0,
                                         selection: nil, ready: true,
                                         songEndTick: fixture.songEndTick)
    report.expectEqual(AutomationCatalog.count, stack.rows.count, cppID: drawerAutomationLabelsID,
                       what: "the row stack carries one row per catalog parameter")
    report.expectEqual(AutomationParameter.tempo, stack.rows[0].parameter, cppID: drawerAutomationLabelsID,
                       what: "the Tempo row leads the stack")
    report.expectEqual(2, stack.row(for: fixture.volumeLane)?.eventCount ?? 0, cppID: drawerAutomationLabelsID,
                       what: "a row counts the lane's written events")
    report.expectEqual(0, stack.row(for: fixture.modulationLane)?.eventCount ?? 0, cppID: drawerAutomationLabelsID,
                       what: "a lane the document never wrote counts no event")
    report.expectEqual(AutomationCatalog.count, stack.visibleRowCount, cppID: drawerAutomationLabelsID,
                       what: "a ready stack shows every row")
    report.expectEqual(4, stack.laneCount, cppID: drawerAutomationLabelsID,
                       what: "the lane count sums the written events, Tempo included")
    report.expectEqual([1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], stack.eventCounts(track: 0),
                       cppID: drawerAutomationLabelsID,
                       what: "the selector's counts follow the catalog order, Tempo first")
    let hidden = AutomationRowStack.build(document: fixture.document, primaryTrack: nil,
                                          selection: nil, ready: true,
                                          songEndTick: fixture.songEndTick)
    report.expectEqual(1, hidden.visibleRowCount, cppID: drawerAutomationLabelsID,
                       what: "without a track only the Tempo row is visible")
    report.expectEqual([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], hidden.eventCounts(track: 0),
                       cppID: drawerAutomationLabelsID,
                       what: "without a track the selector counts only Tempo")
}

@MainActor
func drawerAutomationRowStackAndSelectionIndicators(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)], pan: [(24, 64), (120, 40)],
                                    tempo: [(0, 500_000), (48, 400_000)])
    let range = TimeRange(startTick: 20, endTick: 140)
    let selection = AutomationTimeSelection(range: range, scope: .lanes,
                                            lanes: [fixture.panLane, .tempo], tempo: true)
    let stack = AutomationRowStack.build(document: fixture.document, primaryTrack: 0,
                                         selection: selection, ready: true,
                                         songEndTick: fixture.songEndTick)
    report.expectEqual(range, stack.activeTickRange, cppID: drawerAutomationRowsID,
                       what: "an active selection publishes its tick range")
    let panRow = stack.row(for: fixture.panLane)
    report.expect(panRow?.coversNodes == true && panRow?.coversLane == true
                      && panRow?.selectionHasEvents == true,
                  cppID: drawerAutomationRowsID,
                  message: "a covered lane with events inside the range carries both indicators")
    let volumeRow = stack.row(for: fixture.volumeLane)
    report.expect(volumeRow?.coversNodes == false && volumeRow?.selectionHasEvents == false,
                  cppID: drawerAutomationRowsID, message: "an uncovered lane carries no scope indicator")
    report.expectEqual([fixture.panLane, .tempo], stack.selectedParameters(track: 0), cppID: drawerAutomationRowsID,
                       what: "the selected parameters are the covered lanes with events")

    // Coverage without events is not a selection.
    let empty = AutomationRowStack.build(
        document: fixture.document, primaryTrack: 0,
        selection: AutomationTimeSelection(range: TimeRange(startTick: 200, endTick: 260),
                                           scope: .lanes, lanes: [fixture.panLane]),
        ready: true, songEndTick: fixture.songEndTick)
    report.expect(empty.row(for: fixture.panLane)?.coversNodes == true
                      && empty.row(for: fixture.panLane)?.selectionHasEvents == false,
                  cppID: drawerAutomationRowsID, message: "scope coverage alone never marks a row selected")
    report.expectEqual([AutomationParameter](), empty.selectedParameters(track: 0), cppID: drawerAutomationRowsID,
                       what: "a covered but empty range selects no parameter")

    // A track-scoped selection covers the track's lanes and Tempo only when the
    // whole used track set is selected.
    let trackScoped = AutomationTimeSelection(range: range, scope: .tracks([0]))
    report.expect(trackScoped.covers(fixture.panLane, usedTracks: [0]), cppID: drawerAutomationRowsID,
                  message: "a track-scoped selection covers the selected track's lanes")
    report.expect(!trackScoped.covers(.controlChange(track: 1, controller: TimeDefaults.ccPan),
                                      usedTracks: [0, 1]),
                  cppID: drawerAutomationRowsID,
                  message: "a track-scoped selection leaves another track's lanes alone")
    report.expect(trackScoped.coversTempo(usedTracks: [0]), cppID: drawerAutomationRowsID,
                  message: "Tempo is covered when the whole used set is selected")
    report.expect(!trackScoped.coversTempo(usedTracks: [0, 1]), cppID: drawerAutomationRowsID,
                  message: "Tempo is uncovered when part of the used set is selected")
    report.expect(!AutomationTimeSelection(range: TimeRange(startTick: 20, endTick: 20),
                                           scope: .lanes).isActive,
                  cppID: drawerAutomationRowsID, message: "a zero-width range is no selection")

    // The page's own indicators: the covered lanes are selected while the active
    // parameter stays whatever the user is editing.
    fixture.activate(fixture.volumeLane)
    fixture.page.applyTimeSelection(selection)
    report.expectEqual([fixture.panLane, .tempo], fixture.page.selectedParameters, cppID: drawerAutomationRowsID,
                       what: "the page publishes the selected inactive parameters")
    report.expectEqual(fixture.volumeLane, fixture.page.activeParameter, cppID: drawerAutomationRowsID,
                       what: "the active parameter is not the selected one")
    let panIndex = AutomationCatalog.index(of: fixture.panLane, track: 0) ?? 0
    report.expect(fixture.page.toggleGhostParameter(index: panIndex), cppID: drawerAutomationRowsID,
                  message: "a covered lane with events pins as a ghost")
    report.expectEqual(["Pan (PAN) · 2 Events"], fixture.page.ghostLabels, cppID: drawerAutomationRowsID,
                       what: "the ghost label names the curve and its event count")
    report.expect(fixture.page.toggleGhostParameter(index: panIndex), cppID: drawerAutomationRowsID,
                  message: "the pin toggles off again")
    report.expectEqual([String](), fixture.page.ghostLabels, cppID: drawerAutomationRowsID,
                       what: "unpinning drops the ghost label")
}
