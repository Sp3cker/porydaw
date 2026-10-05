import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

// Existing scenarios paired with painting.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationScaleLabelsAndLaneCounts(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(0, 127), (96, 64)], pan: [(24, 64)])
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual(
        expected: [AutomationScaleLabel.Role.maximum, .minimum, .neutral], actual: pan.scaleLabels.map(\.role),
        cppID: drawerAutomationLabelsID,
        what: "a centered parameter emits maximum, minimum and neutral labels")
    report.expectEqual(
        expected: ["c_v+63", "c_v-64", "c_v+0"], actual: pan.scaleLabels.map(\.text), cppID: drawerAutomationLabelsID,
        what: "the scale labels use the parameter's own formatting")
    report.expectEqual(
        expected: 64, actual: pan.scaleLabels[2].value, cppID: drawerAutomationLabelsID,
        what: "the neutral label names the neutral value")
    report.expect(
        pan.scaleLabels[0].y < pan.scaleLabels[2].y
            && pan.scaleLabels[2].y < pan.scaleLabels[1].y,
        cppID: drawerAutomationLabelsID,
        message: "maximum, neutral and minimum sit at their curve-true heights")

    let volume = fixture.projection(fixture.volumeLane)
    report.expectEqual(
        expected: [AutomationScaleLabel.Role.maximum, .minimum], actual: volume.scaleLabels.map(\.role),
        cppID: drawerAutomationLabelsID,
        what: "a parameter without a neutral emits only its extremes")
    report.expectEqual(
        expected: ["127", "0"], actual: volume.scaleLabels.map(\.text), cppID: drawerAutomationLabelsID,
        what: "Volume's scale labels are its raw values")
    report.expectEqual(
        expected: ["255", "20"], actual: fixture.projection(.tempo).scaleLabels.map(\.text),
        cppID: drawerAutomationLabelsID,
        what: "Tempo's scale labels are its BPM bounds with no neutral")
    report.expectEqual(
        expected: ["+8191", "-8192", "0"],
        actual: fixture.projection(fixture.bendLane)
            .scaleLabels.map(\.text), cppID: drawerAutomationLabelsID,
        what: "Bend's scale labels take the bend format path")

    let stack = AutomationRowStack.build(
        document: fixture.document, primaryTrack: 0,
        selection: nil, ready: true,
        songEndTick: fixture.songEndTick)
    report.expectEqual(
        expected: AutomationCatalog.count, actual: stack.rows.count, cppID: drawerAutomationLabelsID,
        what: "the row stack carries one row per catalog parameter")
    report.expectEqual(
        expected: AutomationParameter.tempo, actual: stack.rows[0].parameter, cppID: drawerAutomationLabelsID,
        what: "the Tempo row leads the stack")
    report.expectEqual(
        expected: 2, actual: stack.row(for: fixture.volumeLane)?.eventCount ?? 0, cppID: drawerAutomationLabelsID,
        what: "a row counts the lane's written events")
    report.expectEqual(
        expected: 0, actual: stack.row(for: fixture.modulationLane)?.eventCount ?? 0, cppID: drawerAutomationLabelsID,
        what: "a lane the document never wrote counts no event")
    report.expectEqual(
        expected: AutomationCatalog.count, actual: stack.visibleRowCount, cppID: drawerAutomationLabelsID,
        what: "a ready stack shows every row")
    report.expectEqual(
        expected: 4, actual: stack.laneCount, cppID: drawerAutomationLabelsID,
        what: "the lane count sums the written events, Tempo included")
    report.expectEqual(
        expected: [1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], actual: stack.eventCounts(track: 0),
        cppID: drawerAutomationLabelsID,
        what: "the selector's counts follow the catalog order, Tempo first")
    let hidden = AutomationRowStack.build(
        document: fixture.document, primaryTrack: nil,
        selection: nil, ready: true,
        songEndTick: fixture.songEndTick)
    report.expectEqual(
        expected: 1, actual: hidden.visibleRowCount, cppID: drawerAutomationLabelsID,
        what: "without a track only the Tempo row is visible")
    report.expectEqual(
        expected: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], actual: hidden.eventCounts(track: 0),
        cppID: drawerAutomationLabelsID,
        what: "without a track the selector counts only Tempo")
}

@MainActor
func drawerAutomationRowStackAndSelectionIndicators(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(0, 127), (96, 64)], pan: [(24, 64), (120, 40)],
        tempo: [(0, 500_000), (48, 400_000)])
    let range = TimeRange(startTick: 20, endTick: 140)
    let selection = AutomationTimeSelection(
        range: range, scope: .lanes,
        lanes: [fixture.panLane, .tempo], tempo: true)
    let stack = AutomationRowStack.build(
        document: fixture.document, primaryTrack: 0,
        selection: selection, ready: true,
        songEndTick: fixture.songEndTick)
    report.expectEqual(
        expected: range, actual: stack.activeTickRange, cppID: drawerAutomationRowsID,
        what: "an active selection publishes its tick range")
    let panRow = stack.row(for: fixture.panLane)
    report.expect(
        panRow?.coversNodes == true && panRow?.coversLane == true
            && panRow?.selectionHasEvents == true,
        cppID: drawerAutomationRowsID,
        message: "a covered lane with events inside the range carries both indicators")
    let volumeRow = stack.row(for: fixture.volumeLane)
    report.expect(
        volumeRow?.coversNodes == false && volumeRow?.selectionHasEvents == false,
        cppID: drawerAutomationRowsID, message: "an uncovered lane carries no scope indicator")
    report.expectEqual(
        expected: [fixture.panLane, .tempo], actual: stack.selectedParameters(track: 0), cppID: drawerAutomationRowsID,
        what: "the selected parameters are the covered lanes with events")

    // Coverage without events is not a selection.
    let empty = AutomationRowStack.build(
        document: fixture.document, primaryTrack: 0,
        selection: AutomationTimeSelection(
            range: TimeRange(startTick: 200, endTick: 260),
            scope: .lanes, lanes: [fixture.panLane]),
        ready: true, songEndTick: fixture.songEndTick)
    report.expect(
        empty.row(for: fixture.panLane)?.coversNodes == true
            && empty.row(for: fixture.panLane)?.selectionHasEvents == false,
        cppID: drawerAutomationRowsID, message: "scope coverage alone never marks a row selected")
    report.expectEqual(
        expected: [AutomationParameter](), actual: empty.selectedParameters(track: 0), cppID: drawerAutomationRowsID,
        what: "a covered but empty range selects no parameter")

    // A track-scoped selection covers the track's lanes and Tempo only when the
    // whole used track set is selected.
    let trackScoped = AutomationTimeSelection(range: range, scope: .tracks([0]))
    report.expect(
        trackScoped.covers(fixture.panLane, usedTracks: [0]), cppID: drawerAutomationRowsID,
        message: "a track-scoped selection covers the selected track's lanes")
    report.expect(
        !trackScoped.covers(
            .controlChange(track: 1, controller: TimeDefaults.ccPan),
            usedTracks: [0, 1]),
        cppID: drawerAutomationRowsID,
        message: "a track-scoped selection leaves another track's lanes alone")
    report.expect(
        trackScoped.coversTempo(usedTracks: [0]), cppID: drawerAutomationRowsID,
        message: "Tempo is covered when the whole used set is selected")
    report.expect(
        !trackScoped.coversTempo(usedTracks: [0, 1]), cppID: drawerAutomationRowsID,
        message: "Tempo is uncovered when part of the used set is selected")
    report.expect(
        !AutomationTimeSelection(
            range: TimeRange(startTick: 20, endTick: 20),
            scope: .lanes
        ).isActive,
        cppID: drawerAutomationRowsID, message: "a zero-width range is no selection")

    // The page's own indicators: the covered lanes are selected while the active
    // parameter stays whatever the user is editing.
    fixture.activate(fixture.volumeLane)
    fixture.page.applyTimeSelection(selection)
    report.expectEqual(
        expected: [fixture.panLane, .tempo], actual: fixture.page.selectedParameters, cppID: drawerAutomationRowsID,
        what: "the page publishes the selected inactive parameters")
    report.expectEqual(
        expected: fixture.volumeLane, actual: fixture.page.activeParameter, cppID: drawerAutomationRowsID,
        what: "the active parameter is not the selected one")
    let panIndex = AutomationCatalog.index(of: fixture.panLane, track: 0) ?? 0
    report.expect(
        fixture.page.toggleGhostParameter(index: panIndex), cppID: drawerAutomationRowsID,
        message: "a covered lane with events pins as a ghost")
    report.expectEqual(
        expected: ["Pan (PAN) · 2 Events"], actual: fixture.page.ghostLabels, cppID: drawerAutomationRowsID,
        what: "the ghost label names the curve and its event count")
    report.expect(
        fixture.page.toggleGhostParameter(index: panIndex), cppID: drawerAutomationRowsID,
        message: "the pin toggles off again")
    report.expectEqual(
        expected: [String](), actual: fixture.page.ghostLabels, cppID: drawerAutomationRowsID,
        what: "unpinning drops the ghost label")
}

let drawerAutomationPaintingModelID = "swiftcore/AutomationPage::presentationPaintingModel"

@MainActor
func drawerAutomationPresentationPaintingModel(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    for (mode, node, resting, outline) in [
        ("vanilla", "#EA3C3C", "#E7E1DB", "#8C857F"),
        ("dark-neutral-high", "#FF4D47", "#51555E", "#62666F"),
        ("immaterial", "#FF91C3", "#4A4E59", "#616571"),
    ] {
        let colors = GridPalette()
        ShellAppearance.apply(to: colors, mode: mode, contrast: 50)
        let expectedNode = PaletteMath.qmlColor(node)
        let expectedResting = PaletteMath.qmlColor(resting)
        let expectedOutline = PaletteMath.qmlColor(outline)
        report.expect(
            colors.automationNodeInk == expectedNode, cppID: drawerAutomationPaintingModelID,
            message: "\(mode) automation node ink matches the native preset")
        report.expect(
            colors.automationTabBackground == expectedResting,
            cppID: drawerAutomationPaintingModelID,
            message: "\(mode) resting automation tab matches the native preset")
        report.expect(
            colors.automationTabOutline == expectedOutline,
            cppID: drawerAutomationPaintingModelID,
            message: "\(mode) automation tab border matches the native preset")
        for (pair, text, background) in [
            (
                "checked label/count on pressed tab", colors.buttonPressedText,
                colors.tabPressedBackground
            ),
            (
                "hover label/count on hover tab", colors.windowText,
                colors.tabHoverBackground
            ),
            (
                "resting label/count on resting tab", colors.windowText,
                colors.automationTabBackground
            ),
            (
                "pinned ghost name on its opaque chrome card", colors.windowText,
                colors.chromeBackground
            ),
        ] {
            let ratio = PaletteMath.contrastRatio(text, background)
            report.expect(
                ratio >= 4.5, cppID: drawerAutomationPaintingModelID,
                message: "\(mode) \(pair) contrast \(ratio):1 meets 4.5:1")
        }
    }
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(0, 127), (96, 64)], pan: [(24, 64), (120, 40)],
        tempo: [(0, 500_000), (48, 400_000)])
    let page = fixture.page
    let catalog = AutomationCatalog.parameters(track: 0)
    report.expectEqual(
        expected: AutomationCatalog.count, actual: page.tabCount, cppID: drawerAutomationPaintingModelID,
        what: "the selector publishes one tab per catalog parameter")
    report.expectEqual(
        expected: catalog.count, actual: page.publishedTabs.count, cppID: drawerAutomationPaintingModelID,
        what: "every catalog parameter draws a selector tab")
    report.expectEqual(
        expected: true, actual: page.publishedTabs.last?.tempo ?? false, cppID: drawerAutomationPaintingModelID,
        what: "the Tempo row closes the selector")
    report.expectEqual(
        expected: catalog.map(AutomationCatalog.tabLabel), actual: page.publishedTabs.map(\.label),
        cppID: drawerAutomationPaintingModelID,
        what: "each tab carries its catalog label")
    report.expectEqual(
        expected: 2, actual: page.publishedTabs[page.catalogIndex(of: fixture.volumeLane)].eventCount,
        cppID: drawerAutomationPaintingModelID,
        what: "a tab counts its lane's written events")
    report.expectEqual(
        expected: 0, actual: page.publishedTabs[page.catalogIndex(of: fixture.modulationLane)].eventCount,
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
        report.expect(
            accepted || index == firstActive, cppID: drawerAutomationPaintingModelID,
            message: "activating a catalog row is accepted unless already active")
        report.expectEqual(
            expected: parameter, actual: page.activeParameter, cppID: drawerAutomationPaintingModelID,
            what: "the activated row becomes active")
    }
    report.expectEqual(
        expected: before, actual: fixture.snapshot, cppID: drawerAutomationPaintingModelID,
        what: "switching every parameter mutates nothing")
    fixture.activate(fixture.volumeLane)
    report.expectEqual(
        expected: fixture.projection(fixture.volumeLane).points.map(\.x),
        actual: page.projection?.points.map(\.x) ?? [], cppID: drawerAutomationPaintingModelID,
        what: "the active projection is the switched parameter's")
    report.expectEqual(
        expected: 2, actual: page.nodeCount, cppID: drawerAutomationPaintingModelID,
        what: "the active lane draws one marker per written event")
    report.expect(
        page.publishedNodes.allSatisfy { !$0.projected },
        cppID: drawerAutomationPaintingModelID,
        message: "a fully written lane shows no synthetic nodes")
    let curveInk = SceneRectPacking.argb(page.palette.automationNodeInk)
    let ghostInk = (curveInk & 0x00FF_FFFF) | 0x8000_0000
    let curveX = fixture.x(72)
    let volumeY = fixture.y(fixture.volumeLane, 127)
    let activeDrawing = AutomationDisplayProbe(page)
    report.expect(
        activeDrawing.hasHeldCurve(atX: curveX, y: volumeY, ink: curveInk),
        cppID: drawerAutomationPaintingModelID,
        message: "Volume draws its held value in lane ink at the projected height")
    report.expect(
        !activeDrawing.statics.contains { $0.argb == ghostInk },
        cppID: drawerAutomationPaintingModelID,
        message: "an unpinned lane draws no ghost ink")
    fixture.activate(fixture.modulationLane)
    report.expectEqual(
        expected: 0, actual: page.nodeCount, cppID: drawerAutomationPaintingModelID,
        what: "an empty lane draws no markers")
    let emptyDrawing = AutomationDisplayProbe(page)
    report.expect(
        emptyDrawing.valid
            && !emptyDrawing.statics.contains {
                $0.argb == curveInk || $0.argb == ghostInk
            }, cppID: drawerAutomationPaintingModelID,
        message: "an empty lane draws no active or ghost curve ink")
    fixture.activate(fixture.volumeLane)
    let tempoIndex = AutomationCatalog.index(of: .tempo, track: 0) ?? 0
    report.expect(
        page.toggleGhostParameter(index: tempoIndex), cppID: drawerAutomationPaintingModelID,
        message: "Tempo pins as a ghost under the active lane")
    report.expectEqual(
        expected: ["Tempo (BPM) · 2 Events"], actual: page.ghostLabels, cppID: drawerAutomationPaintingModelID,
        what: "the ghost label names the curve and its event count")
    report.expect(
        page.ghostNameLabels.count == 1
            && page.ghostNameLabels[0].labelText == "Tempo (BPM) · 2 Events",
        cppID: drawerAutomationPaintingModelID,
        message: "pinning Tempo publishes its drawn name and exact event count")
    if page.ghostNameLabels.count == 1 {
        let rect = page.ghostNameLabels[0]
        let x = rect.x
        let y = rect.y
        let width = rect.width
        let height = rect.height
        report.expect(
            x > page.plotWidth / 2 && x + width <= page.plotWidth,
            cppID: drawerAutomationPaintingModelID,
            message: "the pinned Tempo name stays within the plot's right half")
        report.expect(
            abs(y + height / 2 - fixture.y(.tempo, 150)) <= height,
            cppID: drawerAutomationPaintingModelID,
            message: "the pinned Tempo name follows its own held curve height")
        report.expect(
            (0..<page.valueLabels.count).allSatisfy {
                let label = page.valueLabels[$0]
                return x >= label.x + label.width
            }, cppID: drawerAutomationPaintingModelID,
            message: "the pinned Tempo name remains clear of left scale text")
    }
    let ghostHoverX = fixture.x(72)
    let ghostHoverY = fixture.y(.tempo, 150)
    _ = page.pointerMove(x: ghostHoverX, y: ghostHoverY, buttons: 0)
    let ghostHoverRect = page.hoverLabelRect
    report.expect(
        page.hoverText == "Tempo" && page.hoverVisible,
        cppID: drawerAutomationPaintingModelID,
        message: "hovering the pinned Tempo curve draws its exact name")
    report.expect(
        abs(ghostHoverRect.x + ghostHoverRect.width / 2 - ghostHoverX)
            <= ghostHoverRect.width,
        cppID: drawerAutomationPaintingModelID,
        message: "the pinned Tempo hover follows the pointer's plot column")
    report.expect(
        ghostHoverRect.y + ghostHoverRect.height <= ghostHoverY,
        cppID: drawerAutomationPaintingModelID,
        message: "the pinned Tempo hover sits above its own curve")
    for theme in themePresetRows {
        ShellAppearance.apply(to: page.palette, mode: theme.mode, contrast: 50)
        page.refreshFromDocument()
        let drawing = AutomationDisplayProbe(page)
        let ink = SceneRectPacking.argb(page.palette.automationNodeInk)
        let channels = PaletteMath.channels(page.palette.automationNodeInk)
        let ghost = SceneRectPacking.argb(
            PaletteMath.hex(r: channels.r, g: channels.g, b: channels.b, a: 128))
        let lastGhost = drawing.statics.lastIndex { $0.argb == ghost }
        let firstActive = drawing.statics.firstIndex { $0.argb == ink }
        guard drawing.valid, let lastGhost, let firstActive else {
            report.fail(
                drawerAutomationPaintingModelID,
                "\(theme.mode): pinned Tempo and active Volume must both draw")
            continue
        }
        report.expect(
            lastGhost < firstActive, cppID: drawerAutomationPaintingModelID,
            message: "\(theme.mode): all ghost ink paints before active curve ink")
        let ghostY = fixture.y(.tempo, 150)
        report.expect(
            drawing.hasHeldCurve(atX: curveX, y: ghostY, ink: ghost),
            cppID: "themelayout/ThemeLayoutTest::themeColorTables",
            message: "\(theme.mode): Tempo ghost uses its own height and node ink at alpha 128")
        report.expect(
            drawing.hasHeldCurve(atX: curveX, y: volumeY, ink: ink),
            cppID: drawerAutomationPaintingModelID,
            message: "\(theme.mode): pinning Tempo preserves the active Volume curve")
    }
    ShellAppearance.apply(to: page.palette, mode: "vanilla", contrast: 50)
    page.refreshFromDocument()
    report.expect(
        page.toggleGhostParameter(index: tempoIndex), cppID: drawerAutomationPaintingModelID,
        message: "the ghost unpins")
    report.expect(
        page.ghostNameLabels.count == 0,
        cppID: drawerAutomationPaintingModelID,
        message: "unpinning Tempo removes the drawn curve-name label")
    report.expect(
        page.hoverText != "Tempo",
        cppID: drawerAutomationPaintingModelID,
        message: "unpinning Tempo removes the hovered ghost name")
    let unpinnedDrawing = AutomationDisplayProbe(page)
    report.expect(
        !unpinnedDrawing.statics.contains { $0.argb == ghostInk }
            && unpinnedDrawing.hasHeldCurve(atX: curveX, y: volumeY, ink: curveInk),
        cppID: drawerAutomationPaintingModelID,
        message: "unpinning removes ghost ink and retains the active Volume curve")
    let tempoProjection = fixture.makeProjection(.tempo)
    let volumeProjection = fixture.makeProjection(fixture.volumeLane)
    report.expectEqual(
        expected: volumeProjection.points.first?.x ?? -1, actual: tempoProjection.points.first?.x ?? -2,
        cppID: drawerAutomationPaintingModelID,
        what: "Tempo shares the active lane's plot origin")
    report.expectEqual(
        expected: 2, actual: tempoProjection.eventCount, cppID: drawerAutomationPaintingModelID,
        what: "Tempo keeps its own event count on the shared body")
    let sharedMap = AutomationProjection(
        camera: fixture.viewport.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: page.geometry,
        snapPolicy: AutomationProjectionCache().snapPolicy(viewport: fixture.viewport, font: page.baseFontPx, dpr: 1),
        songEndTick: fixture.songEndTick)
    if let first = tempoProjection.points.first, let last = tempoProjection.points.last {
        report.expectEqual(
            expected: sharedMap.x(first.tick), actual: first.x, cppID: drawerAutomationPaintingModelID,
            what: "Tempo's first tick plots through the shared camera")
        report.expectEqual(
            expected: sharedMap.x(last.tick), actual: last.x, cppID: drawerAutomationPaintingModelID,
            what: "Tempo's last tick plots through the shared camera")
    } else {
        report.fail(drawerAutomationPaintingModelID, "Tempo projected no shared-body probe")
    }
    if let last = volumeProjection.points.last {
        report.expectEqual(
            expected: sharedMap.x(last.tick), actual: last.x, cppID: drawerAutomationPaintingModelID,
            what: "the active lane's last tick plots through the shared camera")
    } else {
        report.fail(drawerAutomationPaintingModelID, "the active lane projected no shared-body probe")
    }
    let volumeWidth = page.plotWidth
    let volumeHeight = page.plotHeight
    let volumeGrid = AutomationDisplayProbe(page).gridLines.map(\.x)
    fixture.activate(.tempo)
    let activeTempoDrawing = AutomationDisplayProbe(page)
    let tempoY = fixture.y(.tempo, 150)
    report.expect(
        activeTempoDrawing.hasHeldCurve(atX: curveX, y: tempoY, ink: curveInk),
        cppID: drawerAutomationPaintingModelID,
        message: "active Tempo draws its held value in independent lane ink")
    report.expectEqual(
        expected: volumeWidth, actual: page.plotWidth, cppID: drawerAutomationPaintingModelID,
        what: "Tempo shares the active lane's plot width")
    report.expectEqual(
        expected: volumeHeight, actual: page.plotHeight, cppID: drawerAutomationPaintingModelID,
        what: "Tempo shares the active lane's plot height")
    let tempoDrawing = AutomationDisplayProbe(page)
    let separator = SceneRectPacking.argb(page.palette.separator)
    report.expect(
        volumeWidth > 0 && volumeHeight > 0
            && page.plotWidth == volumeWidth && page.plotHeight == volumeHeight
            && tempoDrawing.valid
            && tempoDrawing.axis.contains {
                $0.y == 0 && $0.w == page.plotWidth && $0.argb == separator
            },
        cppID: drawerAutomationPaintingModelID,
        message: "Tempo and Volume share the complete plot body including its top edge")
    report.expect(
        !volumeGrid.isEmpty && volumeGrid == tempoDrawing.gridLines.map(\.x),
        cppID: drawerAutomationPaintingModelID,
        message: "Tempo shares the active lane's grid centers")
    fixture.activate(fixture.panLane)
    let shortY = page.projection?.points.first(where: { $0.tick == 24 })?.y ?? -1
    let shortGrid = AutomationDisplayProbe(page).gridLines.map(\.x)
    report.expect(
        !shortGrid.isEmpty, cppID: drawerAutomationPaintingModelID,
        message: "the plot draws its time grid")
    let beforeHeight = page.plotHeight
    page.configureBody(
        width: 480, height: 240, gutter: 0, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    report.expect(
        page.projection?.points.first(where: { $0.tick == 24 })?.y != shortY,
        cppID: drawerAutomationPaintingModelID,
        message: "drawer growth moves the value axis")
    report.expect(
        page.plotHeight > beforeHeight, cppID: drawerAutomationPaintingModelID,
        message: "drawer growth increases the lane body's own height")
    let tallDrawing = AutomationDisplayProbe(page)
    let tallGrid = tallDrawing.gridLines.map(\.x)
    report.expect(
        tallDrawing.valid && shortGrid == tallGrid,
        cppID: drawerAutomationPaintingModelID,
        message: "drawer growth keeps every grid line's horizontal center")
    // Thin axis records: frames, value rules and edge ticks. Grid lines are
    // full-height and filtered out, as the legacy axis section did.
    let drawnAxis = tallDrawing.axis.filter { $0.h != page.plotHeight }
    report.expect(
        tallDrawing.valid
            && drawnAxis.first.map {
                $0.x == 0 && $0.w == page.plotWidth && $0.y == 0
                    && $0.argb == separator
            } == true, cppID: drawerAutomationPaintingModelID,
        message: "the resized top frame spans the new body in separator ink")
    report.expect(
        drawnAxis.dropFirst().first.map {
            $0.x == 0 && $0.w == page.plotWidth
                && $0.y + $0.h == page.plotHeight
                && $0.argb == separator
        } == true, cppID: drawerAutomationPaintingModelID,
        message: "the resized bottom frame spans the new body in separator ink")
    let ruleColor = SceneRectPacking.argb(page.palette.gridLineSub2)
    report.expectEqual(
        expected: 3,
        actual: drawnAxis.filter {
            $0.argb == ruleColor && $0.x == 0 && $0.w == page.plotWidth
        }.count, cppID: drawerAutomationPaintingModelID,
        what: "the centered lane keeps its three value rules")
    report.expectEqual(
        expected: ["c_v+63", "c_v-64", "c_v+0"],
        actual: (0..<page.valueLabels.count).map { page.valueLabels[$0].labelText },
        cppID: drawerAutomationPaintingModelID,
        what: "the value axis labels the centered lane's extremes and neutral")
    let labelTop = (0..<page.valueLabels.count).map { page.valueLabels[$0].y }
    report.expect(
        labelTop[0] < labelTop[2] && labelTop[2] < labelTop[1],
        cppID: drawerAutomationPaintingModelID,
        message: "maximum, neutral and minimum stack top to bottom without overlap")
    report.expect(
        (0..<page.valueLabels.count).allSatisfy {
            page.valueLabels[$0].x < page.plotWidth / 4
        }, cppID: drawerAutomationPaintingModelID,
        message: "each drawn scale label hugs the left quarter of the plot")
    let ticks = drawnAxis.filter {
        $0.argb == separator && $0.w > 0 && $0.w < page.plotWidth / 4
    }
    let heights = page.projection?.scaleLabels.map(\.y) ?? []
    report.expect(
        ticks.count == 3 && heights.count == 3
            && ticks.allSatisfy {
                $0.w < page.plotWidth / 4
            }, cppID: drawerAutomationPaintingModelID,
        message: "exactly three short left-edge ticks mark maximum neutral and minimum")
    report.expect(
        heights.allSatisfy { y in
            ticks.filter { abs($0.y + $0.h / 2 - y) <= 2 }.count == 1
        }, cppID: drawerAutomationPaintingModelID,
        message: "every edge tick aligns with its own scale value after growth")
    let labelsBefore = (0..<page.valueLabels.count).map { page.valueLabels[$0].labelText }
    if let probe = fixture.projection(fixture.panLane).points.first {
        let hoverRevision = page.displayRevision
        _ = page.pointerMove(x: probe.x, y: probe.y, buttons: 0)
        report.expectEqual(
            expected: labelsBefore, actual: (0..<page.valueLabels.count).map { page.valueLabels[$0].labelText },
            cppID: drawerAutomationPaintingModelID,
            what: "a hover pass preserves the scale labels")
        let hoveredAxis = AutomationDisplayProbe(page).axis.filter { $0.h != page.plotHeight }
        report.expectEqual(
            expected: 3,
            actual: hoveredAxis.filter {
                $0.argb == ruleColor && $0.x == 0 && $0.w == page.plotWidth
            }.count, cppID: drawerAutomationPaintingModelID,
            what: "a hover pass appends no duplicate value rules")
        report.expect(
            page.displayRevision == hoverRevision
                && heights.allSatisfy { y in
                    hoveredAxis.filter {
                        $0.argb == separator
                            && $0.w > 0 && $0.w < page.plotWidth / 4
                            && abs($0.y + $0.h / 2 - y) <= 2
                    }.count == 1
                }, cppID: drawerAutomationPaintingModelID,
            message: "hovering preserves each left-edge tick at its label height")
        page.pointerLeave()
    } else {
        report.fail(drawerAutomationPaintingModelID, "the pan lane projected no hover probe")
    }
    fixture.activate(.tempo)
    if let node = page.projection?.points.first(where: { $0.tick == 48 }) {
        let revision = fixture.snapshot
        _ = page.pointerMove(x: node.x, y: node.y, buttons: 0)
        report.expect(
            page.hoverVisible, cppID: drawerAutomationPaintingModelID,
            message: "hovering a tempo node shows its readout")
        report.expectEqual(
            expected: page.hover?.text ?? "", actual: page.hoverText, cppID: drawerAutomationPaintingModelID,
            what: "the readout text is the hovered value's own text")
        report.expect(
            !page.hoverText.isEmpty, cppID: drawerAutomationPaintingModelID,
            message: "the tempo hover names its value")
        let rect = page.hoverLabelRect
        let inPlot =
            rect.x >= 0 && rect.y >= 0
            && rect.x + rect.width <= page.plotWidth + 1
            && rect.y + rect.height <= page.plotHeight + 1
        report.expect(
            inPlot, cppID: drawerAutomationPaintingModelID,
            message: "the hover label stays inside the plot")
        report.expectEqual(
            expected: revision, actual: fixture.snapshot, cppID: drawerAutomationPaintingModelID,
            what: "hovering a tempo node writes nothing")
        page.pointerLeave()
        report.expect(
            !page.hoverVisible, cppID: drawerAutomationPaintingModelID,
            message: "leaving the plot clears the tempo hover")
    } else {
        report.fail(drawerAutomationPaintingModelID, "the tempo lane projected no node at tick 48")
    }
    let emptyTempo = drawerAutomationAutomationFixture(suite: suite, service: service, tempo: [])
    let emptyComposition = emptyTempo.makeProjection(.tempo)
    report.expect(
        emptyTempo.document.state.tempo.isEmpty && emptyComposition.points.isEmpty
            && emptyComposition.segments.isEmpty,
        cppID: drawerAutomationPaintingModelID,
        message: "an empty tempo store composes no lead-in")
    emptyTempo.activate(.tempo)
    let emptyTempoDrawing = AutomationDisplayProbe(emptyTempo.page)
    report.expect(
        emptyTempoDrawing.valid
            && !emptyTempoDrawing.statics.contains {
                $0.argb == curveInk || $0.argb == ghostInk
            }, cppID: drawerAutomationPaintingModelID,
        message: "an empty Tempo lane draws no active or ghost curve ink")
    report.expect(
        emptyTempo.page.publishedNodes.isEmpty,
        cppID: drawerAutomationPaintingModelID,
        message: "an empty Tempo lane publishes no origin marker")
    let implicitTempo = drawerAutomationAutomationFixture(
        suite: suite, service: service, tempo: [(96, 400_000)])
    let implicitComposition = implicitTempo.makeProjection(.tempo)
    report.expectEqual(
        expected: AutomationCurveSegment(
            kind: .step, tickBegin: 0, tickEnd: 96, fromValue: 120,
            toValue: 120, isLeadIn: true, isSelected: false),
        actual: implicitComposition.segments.first,
        cppID: drawerAutomationPaintingModelID,
        what: "a first-nonzero tempo point composes its implicit lead-in")
    implicitTempo.activate(.tempo)
    let leadY = implicitTempo.y(.tempo, 120)
    let leadX = implicitTempo.x(48)
    let implicitDrawing = AutomationDisplayProbe(implicitTempo.page)
    report.expect(
        implicitDrawing.hasHeldCurve(atX: leadX, y: leadY, ink: curveInk),
        cppID: drawerAutomationPaintingModelID,
        message: "the first nonzero Tempo point draws 120 BPM lead-in ink")
    report.expect(
        !implicitTempo.page.publishedNodes.contains { $0.tick == 0 },
        cppID: drawerAutomationPaintingModelID,
        message: "the implicit Tempo lead-in publishes no origin marker")
    report.expect(
        implicitTempo.page.publishedNodes.contains {
            $0.tick == 96 && $0.outlineColor == implicitTempo.page.palette.automationNodeInk
        }, cppID: drawerAutomationPaintingModelID,
        message: "the first written Tempo marker carries lane ink")
    let explicitTempo = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(0, 375_000), (96, 400_000)])
    let explicitComposition = explicitTempo.makeProjection(.tempo)
    report.expect(
        explicitComposition.leadIn == nil
            && !explicitComposition.segments.contains(where: \.isLeadIn),
        cppID: drawerAutomationPaintingModelID,
        message: "an explicit tick-zero point suppresses the lead-in")
    explicitTempo.activate(.tempo)
    report.expect(
        explicitTempo.page.publishedNodes.contains {
            $0.tick == 0 && !$0.projected
                && $0.outlineColor == explicitTempo.page.palette.automationNodeInk
        }, cppID: drawerAutomationPaintingModelID,
        message: "the written tick-zero Tempo marker carries lane ink")
    let explicitDrawing = AutomationDisplayProbe(explicitTempo.page)
    let explicitX = explicitTempo.x(48)
    let defaultTempoY = explicitTempo.y(.tempo, 120)
    let writtenTempoY = explicitTempo.y(.tempo, 160)
    report.expect(
        !explicitDrawing.hasHeldCurve(atX: explicitX, y: defaultTempoY, ink: curveInk)
            && explicitDrawing.hasHeldCurve(atX: explicitX, y: writtenTempoY, ink: curveInk),
        cppID: drawerAutomationPaintingModelID,
        message: "a written tick-zero Tempo point replaces default lead-in ink")
    let stepComposition = fixture.makeProjection(fixture.panLane)
    report.expectEqual(
        expected: [Tick(0), 24, 120],
        actual: stepComposition.segments.map(\.tickBegin),
        cppID: drawerAutomationPaintingModelID,
        what: "step curves compose the projected origin and written nodes")
    report.expectEqual(
        expected: [.step, .step, .step],
        actual: stepComposition.segments.map(\.kind),
        cppID: drawerAutomationPaintingModelID,
        what: "step curves compose their nodes")
    fixture.activate(fixture.panLane)
    let stepDrawing = AutomationDisplayProbe(page)
    let stepX = fixture.x(72)
    let resizedPan = fixture.makeProjection(
        fixture.panLane, width: page.plotWidth, height: page.plotHeight)
    let stepPoint = resizedPan.points.first { $0.tick == 24 }
    report.expect(
        stepPoint.map { stepDrawing.hasHeldCurve(atX: stepX, y: $0.y, ink: curveInk) } == true,
        cppID: drawerAutomationPaintingModelID,
        message: "written CC steps draw their held value in lane ink")
    report.expect(
        page.publishedNodes.contains {
            $0.tick == 24 && $0.outlineColor == page.palette.automationNodeInk
        }, cppID: drawerAutomationPaintingModelID,
        message: "written CC step markers publish the same lane ink")
    let halfOpen = AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 120),
        scope: .lanes, lanes: [fixture.panLane])
    let selectedComposition = fixture.makeProjection(fixture.panLane, selection: halfOpen)
    report.expectEqual(
        expected: [Tick(24)],
        actual: selectedComposition.points
            .filter(\.selected).map(\.tick),
        cppID: drawerAutomationPaintingModelID,
        what: "a half-open time selection composes node rings")
    page.selectRange(from: 24, to: 120, lanes: [fixture.panLane])
    fixture.activate(fixture.panLane)
    let selectedNodes = page.publishedNodes.filter(\.selected)
    let selectionDrawing = AutomationDisplayProbe(page)
    let compositionFill = SceneRectPacking.argb(page.palette.selectionFill)
    let compositionEdge = SceneRectPacking.argb(page.palette.selectionEdge)
    let compositionEdges = selectionDrawing.statics.filter {
        $0.argb == compositionEdge && $0.w == 1
    }
    report.expect(
        selectedNodes.map(\.tick) == [24]
            && selectedNodes.allSatisfy {
                $0.ringRadius > $0.radius && $0.ringColor == page.palette.selectionRing
            }
            && selectionDrawing.valid
            && selectionDrawing.statics.contains {
                $0.argb == compositionFill && abs($0.x - page.xForTick(24)) <= 1
                    && abs($0.x + $0.w - page.xForTick(120)) <= 1.5
            }
            && compositionEdges.count == 2
            && compositionEdges.contains { abs($0.x - page.xForTick(24)) <= 1 }
            && compositionEdges.contains { abs($0.x + $0.w - page.xForTick(120)) <= 1.5 },
        cppID: drawerAutomationPaintingModelID,
        message: "selection rings and reticles compose")
    report.expect(
        selectedNodes.map(\.tick) == [24]
            && page.publishedNodes.first(where: { $0.tick == 120 })?.selected == false,
        cppID: drawerAutomationPaintingModelID,
        message: "the half-open selection excludes the endpoint marker")
    page.selectRange(from: 24, to: 121, lanes: [fixture.panLane])
    report.expect(
        page.publishedNodes.filter(\.selected).map(\.tick) == [24, 120],
        cppID: drawerAutomationPaintingModelID,
        message: "extending the endpoint includes the second marker")
}
