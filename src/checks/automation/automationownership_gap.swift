import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

private let automationPaintingGapID = "automation/AutomationEditingTest::paintingGapContracts"
private let automationPreviewGapID = "automation/AutomationEditingTest::previewGapContracts"

@MainActor
func drawerAutomationPaintingGapChecks(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let emptyTempo = drawerAutomationAutomationFixture(
        suite: suite, service: service, tempo: [])
    emptyTempo.activate(.tempo)
    let emptyBefore = emptyTempo.snapshot
    report.expect(
        emptyTempo.page.activeParameter == .tempo && emptyTempo.page.projection != nil,
        cppID: automationPaintingGapID,
        message: "A001/A002 empty Tempo storage still publishes an active lane projection")
    report.expect(
        emptyTempo.document.state.tempo.isEmpty,
        cppID: automationPaintingGapID,
        message: "A004 empty Tempo projection does not synthesize document storage")
    report.expect(
        emptyTempo.page.projection?.leadIn?.tick == 0
            && emptyTempo.page.projection?.segments.isEmpty == true,
        cppID: automationPaintingGapID,
        message: "A002 empty Tempo storage carries only its implicit lead-in value and no curve")
    report.expectEqual(
        emptyBefore, emptyTempo.snapshot,
        cppID: automationPaintingGapID,
        what: "A005/A006/A009 composing empty Tempo changes no document or history state")

    let implicit = drawerAutomationAutomationFixture(
        suite: suite, service: service, tempo: [(48, 400_000)])
    implicit.activate(.tempo)
    let implicitBefore = implicit.snapshot
    report.expect(
        implicit.page.activeParameter == .tempo && implicit.page.projection != nil,
        cppID: automationPaintingGapID,
        message: "A010/A011 nonzero Tempo point publishes the Tempo projection")
    report.expect(
        implicit.page.projection?.segments.first?.isLeadIn == true
            && implicit.page.projection?.segments.first?.tickBegin == 0
            && implicit.page.projection?.segments.first?.tickEnd == 48,
        cppID: automationPaintingGapID,
        message: "A011 first nonzero Tempo point composes an implicit tick-zero lead-in curve")
    report.expectEqual(
        implicitBefore, implicit.snapshot,
        cppID: automationPaintingGapID,
        what: "A014/A015/A019 implicit lead-in composition is paint-only")

    let explicit = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(0, 500_000), (48, 400_000)])
    explicit.activate(.tempo)
    let explicitBefore = explicit.snapshot
    report.expect(
        explicit.page.activeParameter == .tempo && explicit.page.projection != nil,
        cppID: automationPaintingGapID,
        message: "A020/A021 explicit tick-zero Tempo publishes the Tempo projection")
    report.expect(
        explicit.page.projection?.leadIn == nil
            && explicit.page.projection?.segments.allSatisfy { !$0.isLeadIn } == true,
        cppID: automationPaintingGapID,
        message: "A021 explicit tick-zero Tempo suppresses the implicit lead-in curve")
    report.expectEqual(
        explicitBefore, explicit.snapshot,
        cppID: automationPaintingGapID,
        what: "A024/A025/A028 zero-tick suppression is paint-only")

    let curveRows: [(name: String, parameter: AutomationParameter,
                     fixture: drawerAutomationAutomationFixture, ramp: Bool,
                     ticks: [Tick])] = [
        ("A029-pan", .controlChange(track: 0, controller: TimeDefaults.ccPan),
         drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(24, 30), (72, 90)]), false, [24, 72]),
        ("A029-tempo", .tempo,
         drawerAutomationAutomationFixture(
            suite: suite, service: service, tempo: [(0, 500_000), (72, 400_000)]), true,
         [0, 72]),
    ]
    for row in curveRows {
        row.fixture.activate(row.parameter)
        let before = row.fixture.snapshot
        report.expect(
            row.fixture.page.activeParameter == row.parameter
                && row.ticks.allSatisfy { tick in
                    row.fixture.page.publishedNodes.contains { Tick($0.tick) == tick }
                },
            cppID: automationPaintingGapID,
            message: "\(row.name) active lane publishes its two written node paint records")
        report.expect(
            row.ramp ? !row.fixture.page.rampSnapshots.isEmpty
                     : !row.fixture.page.publishedCurveRuns.isEmpty,
            cppID: automationPaintingGapID,
            message: "\(row.name) interpolation publishes the matching curve primitive")
        report.expectEqual(
            before, row.fixture.snapshot,
            cppID: automationPaintingGapID,
            what: "\(row.name) A033-A039 curve composition mutates nothing")
    }

    let selected = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 30), (72, 90), (120, 50)])
    selected.activate(selected.panLane)
    let selectedBefore = selected.snapshot
    selected.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 120), scope: .lanes,
        lanes: [selected.panLane]))
    let paintNodes = selected.page.publishedNodes
    report.expect(
        paintNodes.filter(\.selected).map { Tick($0.tick) } == [24, 72],
        cppID: automationPaintingGapID,
        message: "A040-A049 selection ring flags cover nodes inside the half-open range")
    report.expect(
        (paintNodes.first(where: { Tick($0.tick) == 24 })?.ringRadius ?? 0)
            > (paintNodes.first(where: { Tick($0.tick) == 24 })?.radius ?? 0),
        cppID: automationPaintingGapID,
        message: "A044 selected node paint model carries a ring larger than its node")
    _ = selected.page.pointerMove(
        x: selected.x(72), y: selected.y(selected.panLane, 90), buttons: 0)
    report.expect(
        selected.page.publishedNodes.first(where: { Tick($0.tick) == 72 })?.hovered == true,
        cppID: automationPaintingGapID,
        message: "A044 selection reticle paint model marks the hovered selected node")
    report.expect(
        selected.page.publishedNodes.first(where: { Tick($0.tick) == 120 })?.selected == false,
        cppID: automationPaintingGapID,
        message: "A051-A053/A062 half-open end node carries no selection ring")
    report.expectEqual(
        selectedBefore, selected.snapshot,
        cppID: automationPaintingGapID,
        what: "A042/A043/A049/A051/A052/A062 node-ring composition is paint-only")
}

@MainActor
func drawerAutomationPreviewGapChecks(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let singleRows: [(name: String, parameter: AutomationParameter,
                      fixture: drawerAutomationAutomationFixture,
                      source: (Tick, Int), target: (Tick, Int))] = [
        ("A001-pan", .controlChange(track: 0, controller: TimeDefaults.ccPan),
         drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(48, 40)]),
         (48, 40), (72, 90)),
        ("A001-tempo", .tempo,
         drawerAutomationAutomationFixture(
            suite: suite, service: service, tempo: [(48, 500_000)]),
         (48, 120), (72, 150)),
    ]
    for row in singleRows {
        row.fixture.activate(row.parameter)
        let before = row.fixture.snapshot
        let x = row.fixture.x(row.source.0)
        let y = row.fixture.y(row.parameter, row.source.1)
        report.expect(
            row.fixture.page.pointerPress(x: x, y: y, surface: 1, button: 1),
            cppID: automationPreviewGapID,
            message: "\(row.name) A001-A007 single-node preview captures the source")
        _ = row.fixture.page.pointerMove(x: x + 12, y: y, buttons: 1)
        _ = row.fixture.page.pointerMove(
            x: row.fixture.x(row.target.0),
            y: row.fixture.y(row.parameter, row.target.1), buttons: 1)
        report.expectEqual(
            ["\(row.target.0):\(row.target.1)"],
            row.fixture.page.previewPoints.map { "\($0.tick):\($0.value)" },
            cppID: automationPreviewGapID,
            what: "\(row.name) A008/A009 single-node paint preview publishes its destination")
        report.expect(
            row.fixture.page.previewLabelVisible
                && row.fixture.page.previewRectSnapshots.count == 1,
            cppID: automationPreviewGapID,
            message: "\(row.name) A008/A009 preview publishes one node primitive and value label")
        report.expectEqual(
            before, row.fixture.snapshot,
            cppID: automationPreviewGapID,
            what: "\(row.name) A010 single-node preview mutates nothing before release")
        _ = row.fixture.page.handleEscape()
    }

    let multipleRows: [(name: String, points: [(Tick, Int)], range: TimeRange,
                        source: (Tick, Int), target: (Tick, Int),
                        expected: [String])] = [
        ("A011-two-nodes", [(48, 30), (96, 60), (144, 90)],
         TimeRange(startTick: 24, endTick: 120), (48, 30), (72, 50),
         ["72:50", "120:80"]),
        ("A011-three-nodes", [(24, 20), (48, 40), (72, 60), (144, 90)],
         TimeRange(startTick: 0, endTick: 96), (24, 20), (48, 40),
         ["48:40", "72:60", "96:80"]),
    ]
    for row in multipleRows {
        let multiple = drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: row.points)
        multiple.activate(multiple.panLane)
        multiple.page.selectRange(
            from: row.range.startTick, to: row.range.endTick, lanes: [multiple.panLane])
        let before = multiple.snapshot
        let x = multiple.x(row.source.0)
        let y = multiple.y(multiple.panLane, row.source.1)
        report.expect(
            multiple.page.pointerPress(x: x, y: y, surface: 1, button: 1),
            cppID: automationPreviewGapID,
            message: "\(row.name) A011-A015 selected-node preview captures its group")
        _ = multiple.page.pointerMove(x: x + 12, y: y, buttons: 1)
        _ = multiple.page.pointerMove(
            x: multiple.x(row.target.0),
            y: multiple.y(multiple.panLane, row.target.1), buttons: 1)
        report.expectEqual(
            row.expected,
            multiple.page.previewPoints.map { "\($0.tick):\($0.value)" },
            cppID: automationPreviewGapID,
            what: "\(row.name) A016-A018 preview publishes every moved selected target")
        report.expectEqual(
            row.expected.count, multiple.page.previewRectSnapshots.count,
            cppID: automationPreviewGapID,
            what: "\(row.name) A016-A018 paint model publishes every preview primitive")
        report.expectEqual(
            before, multiple.snapshot,
            cppID: automationPreviewGapID,
            what: "\(row.name) A019 multi-node preview mutates nothing before release")
        _ = multiple.page.handleEscape()
    }

    let sweepRows = [
        (name: "A020-forward-sweep", source: (Tick(24), 40), target: (Tick(96), 100)),
        (name: "A020-backward-sweep", source: (Tick(120), 100), target: (Tick(48), 40)),
    ]
    for row in sweepRows {
        let sweep = drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(0, 20), (144, 80)])
        sweep.activate(sweep.panLane)
        let before = sweep.snapshot
        let x = sweep.x(row.source.0)
        let y = sweep.y(sweep.panLane, row.source.1)
        report.expect(
            sweep.page.pointerPress(x: x, y: y, surface: 1, button: 1),
            cppID: automationPreviewGapID,
            message: "\(row.name) A020-A023 background press starts production sweep preview")
        let direction = row.target.0 > row.source.0 ? 12.0 : -12.0
        _ = sweep.page.pointerMove(x: x + direction, y: y, buttons: 1)
        _ = sweep.page.pointerMove(
            x: sweep.x(row.target.0), y: sweep.y(sweep.panLane, row.target.1), buttons: 1)
        report.expect(
            sweep.page.observation.pointerKind == .sweep
                && !sweep.page.previewPoints.isEmpty
                && sweep.page.previewRectSnapshots.count == sweep.page.previewPoints.count,
            cppID: automationPreviewGapID,
            message: "\(row.name) A024/A025 sweep paint preview publishes every stepped point")
        report.expectEqual(
            before, sweep.snapshot,
            cppID: automationPreviewGapID,
            what: "\(row.name) A026 sweep preview mutates nothing before release")
        _ = sweep.page.handleEscape()
    }

    let rampRows = [
        (name: "A027-ramp-up", source: (Tick(24), 40), target: (Tick(96), 100)),
        (name: "A027-ramp-down", source: (Tick(24), 100), target: (Tick(96), 40)),
    ]
    for row in rampRows {
        let ramp = drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(0, 20), (144, 80)])
        ramp.activate(ramp.panLane)
        let before = ramp.snapshot
        report.expect(
            ramp.page.pointerPress(
                x: ramp.x(row.source.0), y: ramp.y(ramp.panLane, row.source.1),
                surface: 1, button: 1, modifiers: DrawerModifiers.shiftBit),
            cppID: automationPreviewGapID,
            message: "\(row.name) A027-A030 Shift background press starts the ramp gesture")
        _ = ramp.page.pointerMove(
            x: ramp.x(row.target.0), y: ramp.y(ramp.panLane, row.target.1),
            buttons: 1, modifiers: DrawerModifiers.shiftBit)
        report.expect(
            ramp.page.observation.pointerKind == .ramp,
            cppID: automationPreviewGapID,
            message: "\(row.name) A031/A032 Shift preview retains semantic ramp ownership")
        report.expectEqual(
            before, ramp.snapshot,
            cppID: automationPreviewGapID,
            what: "\(row.name) A033 ramp preview mutates nothing before release")
        _ = ramp.page.handleEscape()
    }

    let pencil = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20)])
    pencil.activate(pencil.panLane)
    pencil.page.isPencilMode = true
    let pencilBefore = pencil.snapshot
    let pencilY = pencil.y(pencil.panLane, 40)
    report.expect(
        pencil.page.pointerPress(x: pencil.x(24), y: pencilY, surface: 1, button: 1),
        cppID: automationPreviewGapID,
        message: "A034-A037 pencil press starts the preview transaction")
    _ = pencil.page.pointerMove(
        x: pencil.x(96), y: pencil.y(pencil.panLane, 90), buttons: 1)
    report.expect(
        !pencil.page.previewPoints.isEmpty
            && pencil.page.previewRectSnapshots.count == pencil.page.previewPoints.count,
        cppID: automationPreviewGapID,
        message: "A038/A039 pencil preview publishes its held-span point primitives")
    report.expect(
        pencil.page.previewLabelVisible && !pencil.page.previewLabelText.isEmpty,
        cppID: automationPreviewGapID,
        message: "A040 pencil preview publishes the final value label")
    report.expectEqual(
        pencilBefore, pencil.snapshot,
        cppID: automationPreviewGapID,
        what: "A041 pencil preview changes no document or history state")
    _ = pencil.page.handleEscape()

    let cursor = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (144, 80)])
    cursor.activate(cursor.panLane)
    let cursorBefore = cursor.snapshot
    let firstX = cursor.session.camera.contentX(tick: 24)
    cursor.session.editCursor = 24
    report.expect(
        cursor.page.readoutVisible && cursor.page.contextTick == 24,
        cppID: automationPreviewGapID,
        message: "A042-A046 published edit cursor is visible in the page context")
    cursor.session.editCursor = 96
    let secondX = cursor.session.camera.contentX(tick: 96)
    report.expect(
        cursor.page.readoutVisible && cursor.page.contextTick == 96 && firstX != secondX,
        cppID: automationPreviewGapID,
        message: "A046/A047 moved edit cursor republishes at a distinct quick-view x")
    report.expect(
        abs((secondX - firstX) - Double(96 - 24)
            * cursor.session.camera.snapshot.pixelsPerTick) < 0.5,
        cppID: automationPreviewGapID,
        message: "A048 cursor movement uses the shared camera projection")
    report.expectEqual(
        cursorBefore, cursor.snapshot,
        cppID: automationPreviewGapID,
        what: "A043/A044/A049 cursor synchronization mutates no document or history state")
}
