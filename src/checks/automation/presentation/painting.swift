import Foundation
import PorydawApp
import PorydawCore

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

let drawerAutomationPaintingModelID = "swiftcore/AutomationPage::presentationPaintingModel"

@MainActor
func drawerAutomationPresentationPaintingModel(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)], pan: [(24, 64), (120, 40)],
                                    tempo: [(0, 500_000), (48, 400_000)])
    let page = fixture.page
    let catalog = AutomationCatalog.parameters(track: 0)
    report.expectEqual(AutomationCatalog.count, page.tabCount, cppID: drawerAutomationPaintingModelID,
                       what: "the selector publishes one tab per catalog parameter")
    report.expectEqual(catalog.count, page.publishedTabs.count, cppID: drawerAutomationPaintingModelID,
                       what: "every catalog parameter draws a selector tab")
    report.expectEqual(true, page.publishedTabs.last?.tempo ?? false, cppID: drawerAutomationPaintingModelID,
                       what: "the Tempo row closes the selector")
    report.expectEqual(catalog.map(AutomationCatalog.tabLabel),
                       page.publishedTabs.map(\.label), cppID: drawerAutomationPaintingModelID,
                       what: "each tab carries its catalog label")
    report.expectEqual(2, page.publishedTabs[page.catalogIndex(of: fixture.volumeLane)].eventCount,
                       cppID: drawerAutomationPaintingModelID,
                       what: "a tab counts its lane's written events")
    report.expectEqual(0, page.publishedTabs[page.catalogIndex(of: fixture.modulationLane)].eventCount,
                       cppID: drawerAutomationPaintingModelID,
                       what: "a lane the document never wrote counts no event")
    let before = fixture.snapshot
    let firstActive = page.activeParameterIndex
    for parameter in catalog {
        guard let index = AutomationCatalog.index(of: parameter, track: 0) else {
            report.fail(drawerAutomationPaintingModelID, "catalog parameter has no index")
            return
        }
        let accepted = page.activateParameter(index: index)
        report.expect(accepted || index == firstActive, cppID: drawerAutomationPaintingModelID,
                      message: "activating a catalog row is accepted unless already active")
        report.expectEqual(parameter, page.activeParameter, cppID: drawerAutomationPaintingModelID,
                           what: "the activated row becomes active")
    }
    report.expectEqual(before, fixture.snapshot, cppID: drawerAutomationPaintingModelID,
                       what: "switching every parameter mutates nothing")
    fixture.activate(fixture.volumeLane)
    report.expectEqual(fixture.projection(fixture.volumeLane).points.map(\.x),
                       page.projection?.points.map(\.x) ?? [], cppID: drawerAutomationPaintingModelID,
                       what: "the active projection is the switched parameter's")
    report.expectEqual(2, page.nodeCount, cppID: drawerAutomationPaintingModelID,
                       what: "the active lane draws one marker per written event")
    report.expect(page.publishedNodes.allSatisfy { !$0.projected },
                  cppID: drawerAutomationPaintingModelID,
                  message: "a fully written lane shows no synthetic nodes")
    report.expect(!page.publishedCurveRuns.isEmpty, cppID: drawerAutomationPaintingModelID,
                  message: "a lane with events draws its curve")
    report.expect(page.publishedCurveRuns.allSatisfy { $0.primitiveName == "automationCurve" },
                  cppID: drawerAutomationPaintingModelID,
                  message: "an unpinned lane draws no ghost curve")
    fixture.activate(fixture.modulationLane)
    report.expectEqual(0, page.nodeCount, cppID: drawerAutomationPaintingModelID,
                       what: "an empty lane draws no markers")
    report.expect(page.publishedCurveRuns.isEmpty, cppID: drawerAutomationPaintingModelID,
                  message: "an empty lane draws no curve")
    fixture.activate(fixture.volumeLane)
    let tempoIndex = AutomationCatalog.index(of: .tempo, track: 0) ?? 0
    let activeRuns = page.publishedCurveRuns.count
    report.expect(activeRuns > 0, cppID: drawerAutomationPaintingModelID,
                  message: "the active lane draws its own runs")
    report.expect(page.toggleGhostParameter(index: tempoIndex), cppID: drawerAutomationPaintingModelID,
                  message: "Tempo pins as a ghost under the active lane")
    report.expectEqual(["Tempo (BPM) · 2 Events"], page.ghostLabels, cppID: drawerAutomationPaintingModelID,
                       what: "the ghost label names the curve and its event count")
    report.expect(page.publishedCurveRuns.count > activeRuns, cppID: drawerAutomationPaintingModelID,
                  message: "pinning a ghost adds its curve under the active lane")
    report.expect(page.publishedCurveRuns.last?.primitiveName == "automationCurve",
                  cppID: drawerAutomationPaintingModelID,
                  message: "the active lane keeps the top curve run")
    report.expect(page.publishedCurveRuns.dropLast(activeRuns)
        .allSatisfy { $0.primitiveName == "automationGhostCurve" },
                  cppID: drawerAutomationPaintingModelID,
                  message: "every earlier run is the pinned ghost's curve")
    report.expect(page.publishedCurveRuns.suffix(activeRuns)
        .allSatisfy { $0.primitiveName == "automationCurve" },
                  cppID: drawerAutomationPaintingModelID,
                  message: "the active tail keeps its own runs on top")
    report.expect(page.toggleGhostParameter(index: tempoIndex), cppID: drawerAutomationPaintingModelID,
                  message: "the ghost unpins")
    report.expectEqual(activeRuns, page.publishedCurveRuns.count, cppID: drawerAutomationPaintingModelID,
                       what: "unpinning drops the ghost curve")
    let tempoProjection = fixture.makeProjection(.tempo)
    let volumeProjection = fixture.makeProjection(fixture.volumeLane)
    report.expectEqual(volumeProjection.points.first?.x ?? -1, tempoProjection.points.first?.x ?? -2,
                       cppID: drawerAutomationPaintingModelID,
                       what: "Tempo shares the active lane's plot origin")
    report.expectEqual(2, tempoProjection.eventCount, cppID: drawerAutomationPaintingModelID,
                       what: "Tempo keeps its own event count on the shared body")
    let sharedMap = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: page.baseFontPx, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    if let first = tempoProjection.points.first, let last = tempoProjection.points.last {
        report.expectEqual(sharedMap.x(first.tick), first.x, cppID: drawerAutomationPaintingModelID,
                           what: "Tempo's first tick plots through the shared camera")
        report.expectEqual(sharedMap.x(last.tick), last.x, cppID: drawerAutomationPaintingModelID,
                           what: "Tempo's last tick plots through the shared camera")
    } else {
        report.fail(drawerAutomationPaintingModelID, "Tempo projected no shared-body probe")
    }
    if let last = volumeProjection.points.last {
        report.expectEqual(sharedMap.x(last.tick), last.x, cppID: drawerAutomationPaintingModelID,
                           what: "the active lane's last tick plots through the shared camera")
    } else {
        report.fail(drawerAutomationPaintingModelID, "the active lane projected no shared-body probe")
    }
    let volumeWidth = page.plotWidth
    let volumeHeight = page.plotHeight
    let volumeGrid = (0..<page.gridLines.count).map { page.gridLines[$0].x }
    fixture.activate(.tempo)
    report.expectEqual(volumeWidth, page.plotWidth, cppID: drawerAutomationPaintingModelID,
                       what: "Tempo shares the active lane's plot width")
    report.expectEqual(volumeHeight, page.plotHeight, cppID: drawerAutomationPaintingModelID,
                       what: "Tempo shares the active lane's plot height")
    report.expectEqual(volumeGrid, (0..<page.gridLines.count).map { page.gridLines[$0].x },
                       cppID: drawerAutomationPaintingModelID,
                       what: "Tempo shares the active lane's grid centers")
    fixture.activate(fixture.panLane)
    let shortY = page.projection?.points.first(where: { $0.tick == 24 })?.y ?? -1
    let shortGrid = page.gridLines.count > 0 ? (0..<page.gridLines.count).map { page.gridLines[$0].x } : []
    report.expect(!shortGrid.isEmpty, cppID: drawerAutomationPaintingModelID,
                  message: "the plot draws its time grid")
    page.configureBody(width: 480, height: 240, gutter: 0, devicePixelRatio: 1,
                       baseFontPx: 13, dragDistance: 10)
    report.expect(page.projection?.points.first(where: { $0.tick == 24 })?.y != shortY,
                  cppID: drawerAutomationPaintingModelID,
                  message: "drawer growth moves the value axis")
    let tallGrid = (0..<page.gridLines.count).map { page.gridLines[$0].x }
    report.expectEqual(shortGrid, tallGrid, cppID: drawerAutomationPaintingModelID,
                       what: "drawer growth keeps every grid line's horizontal center")
    report.expectEqual(3, page.valueLines.count, cppID: drawerAutomationPaintingModelID,
                       what: "the centered lane keeps its three value rules")
    report.expectEqual(["c_v+63", "c_v-64", "c_v+0"],
                       (0..<page.valueLabels.count).map { page.valueLabels[$0].labelText },
                       cppID: drawerAutomationPaintingModelID,
                       what: "the value axis labels the centered lane's extremes and neutral")
    let labelTop = (0..<page.valueLabels.count).map { page.valueLabels[$0].labelRect["y"] as? Double ?? -1 }
    report.expect(labelTop[0] < labelTop[2] && labelTop[2] < labelTop[1],
                  cppID: drawerAutomationPaintingModelID,
                  message: "maximum, neutral and minimum stack top to bottom without overlap")
    let labelsBefore = (0..<page.valueLabels.count).map { page.valueLabels[$0].labelText }
    if let probe = fixture.projection(fixture.panLane).points.first {
        _ = page.pointerMove(x: probe.x, y: probe.y, buttons: 0)
        report.expectEqual(labelsBefore,
                           (0..<page.valueLabels.count).map { page.valueLabels[$0].labelText },
                           cppID: drawerAutomationPaintingModelID,
                           what: "a hover pass preserves the scale labels")
        report.expectEqual(3, page.valueLines.count, cppID: drawerAutomationPaintingModelID,
                           what: "a hover pass appends no duplicate value rules")
        page.pointerLeave()
    } else {
        report.fail(drawerAutomationPaintingModelID, "the pan lane projected no hover probe")
    }
    fixture.activate(.tempo)
    if let node = page.projection?.points.first(where: { $0.tick == 48 }) {
        let revision = fixture.snapshot
        _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
        report.expect(page.hoverVisible, cppID: drawerAutomationPaintingModelID,
                      message: "hovering a tempo node shows its readout")
        report.expectEqual(page.hover?.text ?? "", page.hoverText, cppID: drawerAutomationPaintingModelID,
                           what: "the readout text is the hovered value's own text")
        report.expect(!page.hoverText.isEmpty, cppID: drawerAutomationPaintingModelID,
                      message: "the tempo hover names its value")
        let rect = page.hoverLabelRect
        let inPlot = (rect["x"] as? Double ?? -1) >= 0 && (rect["y"] as? Double ?? -1) >= 0
            && ((rect["x"] as? Double ?? 0) + (rect["width"] as? Double ?? 0)) <= page.plotWidth + 1
            && ((rect["y"] as? Double ?? 0) + (rect["height"] as? Double ?? 0)) <= page.plotHeight + 1
        report.expect(inPlot, cppID: drawerAutomationPaintingModelID,
                      message: "the hover label stays inside the plot")
        report.expectEqual(revision, fixture.snapshot, cppID: drawerAutomationPaintingModelID,
                           what: "hovering a tempo node writes nothing")
        page.pointerLeave()
        report.expect(!page.hoverVisible, cppID: drawerAutomationPaintingModelID,
                      message: "leaving the plot clears the tempo hover")
    } else {
        report.fail(drawerAutomationPaintingModelID, "the tempo lane projected no node at tick 48")
    }
}
