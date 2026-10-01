import Foundation
import NativeDisplayList
import PorydawCore

@testable import PorydawApp

/// Viewport-space rects decoded from one AutomationPage display list, through
/// the same C decoder the DisplayList item paints with.
@MainActor struct AutomationDisplayProbe {
    struct Rect {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let argb: UInt32
    }

    let valid: Bool
    let revision: Int
    let axis: [Rect]
    let statics: [Rect]
    let preview: [Rect]
    let plotWidth: Double
    let plotHeight: Double

    init(_ page: AutomationPage) {
        revision = page.displayRevision
        plotWidth = page.plotWidth
        plotHeight = page.plotHeight
        let (axisValid, axisRects) = Self.decode(page.displayList(list: 0))
        let (staticsValid, staticsRects) = Self.decode(page.displayList(list: 1))
        let (previewValid, previewRects) = Self.decode(page.displayList(list: 2))
        valid = axisValid && staticsValid && previewValid
        axis = axisRects
        statics = staticsRects
        preview = previewRects
    }

    /// Full-height axis records: the time-grid lines.
    var gridLines: [Rect] { axis.filter { $0.h == plotHeight } }

    private static func decode(_ data: Data) -> (Bool, [Rect]) {
        data.withUnsafeBytes { raw -> (Bool, [Rect]) in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let header = view.header, let rectBase = view.rects
            else { return (false, []) }
            let count = Int(header.pointee.rectCount)
            var rects: [Rect] = []
            rects.reserveCapacity(count)
            for i in 0..<count {
                let r = rectBase[i]
                rects.append(Rect(x: r.x, y: r.y, w: r.w, h: r.h, argb: r.argb))
            }
            return (true, rects)
        }
    }
}

@MainActor
func drawerAutomationDrawingContentChecks(
    _ report: CheckReport,
    suite: DocumentSession, service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(0, 30), (24, 100)])
    let page = fixture.page
    _ = page.activateParameter(index: 0)
    let revision = page.displayRevision
    let probe = AutomationDisplayProbe(page)
    let ink = SceneRectPacking.argb(page.palette.automationNodeInk)
    let separator = SceneRectPacking.argb(page.palette.separator)
    report.expect(
        probe.valid && probe.revision == revision && !probe.gridLines.isEmpty
            && probe.axis.contains {
                $0.y == 0 && $0.w == page.plotWidth && $0.argb == separator
            }
            && probe.statics.contains { $0.argb == ink }
            && probe.statics.contains { $0.w == 2 && $0.h >= 2 && $0.argb == ink },
        cppID: drawerAutomationProjectionID,
        message: "automation lists carry grid lines, sticky axis chrome and anchored curve")
    let axisBytes = page.displayList(list: 0)
    let staticsBytes = page.displayList(list: 1)
    fixture.session.mutateCamera { _ = $0.setHScroll(17) }
    page.refreshCamera()
    report.expect(
        page.displayRevision == revision + 1 && page.displayList(list: 0) != axisBytes
            && page.displayList(list: 1) != staticsBytes,
        cppID: drawerAutomationProjectionID,
        message: "automation scroll rebuilds viewport lists and bumps revision")
    let scrolledRevision = page.displayRevision
    let scrolledAxis = page.displayList(list: 0)
    fixture.session.mutateCamera { $0.setTimeZoom($0.snapshot.pixelsPerBeat * 2) }
    page.refreshCamera()
    report.expect(
        page.displayRevision == scrolledRevision + 1 && page.displayList(list: 0) != scrolledAxis,
        cppID: drawerAutomationProjectionID,
        message: "automation zoom rebuilds viewport lists and bumps revision")
    let zoomedStatics = page.displayList(list: 1)
    page.palette.gridLineBar = "#FF214365"
    page.refreshFromDocument()
    let changed = AutomationDisplayProbe(page)
    report.expect(
        changed.valid && page.displayRevision == scrolledRevision + 2
            && page.displayList(list: 0) != scrolledAxis
            && page.displayList(list: 1) == zoomedStatics,
        cppID: drawerAutomationProjectionID,
        message: "automation palette edit republishes the axis list once")
    let paletteRevision = page.displayRevision
    page.selectRange(from: 12, to: 48)
    page.refreshFromDocument()
    let selected = AutomationDisplayProbe(page)
    let fill = SceneRectPacking.argb(page.palette.selectionFill)
    let edge = SceneRectPacking.argb(page.palette.selectionEdge)
    let x0 = max(0, page.xForTick(12))
    let x1 = min(page.plotWidth, page.xForTick(48))
    report.expect(
        selected.valid && page.displayRevision == paletteRevision + 1
            && selected.statics.contains {
                $0.argb == fill && abs($0.x - x0) <= 1 && abs($0.x + $0.w - x1) <= 1.5
            }
            && selected.statics.filter({ $0.argb == edge && $0.w == 1 }).count == 2
            && selected.statics.contains {
                $0.argb == edge && $0.w == 1 && abs($0.x - x0) <= 1
            }
            && selected.statics.contains {
                $0.argb == edge && $0.w == 1 && abs($0.x + $0.w - x1) <= 1.5
            },
        cppID: drawerAutomationProjectionID,
        message: "automation selection emits tick span and anchored pixel-width edges")
    let armAxis = page.displayList(list: 0)
    let armStatics = page.displayList(list: 1)
    let armRevision = page.displayRevision
    let armCamera = fixture.session.camera.snapshot
    let armTarget =
        armCamera.scrollX + 24 <= armCamera.maxHScroll
        ? armCamera.scrollX + 24 : armCamera.scrollX - 24
    fixture.session.mutateCamera { _ = $0.setHScroll(armTarget) }
    page.refreshHorizontalProjection()
    report.expect(
        page.displayRevision == armRevision + 1 && page.displayList(list: 0) != armAxis
            && page.displayList(list: 1) != armStatics,
        cppID: drawerAutomationProjectionID,
        message: "automation scroll-only arm republishes viewport lists once")

    page.detach()
}

/// A live sweep paints the lane it would commit in lane ink, its covered nodes
/// hidden, and Escape restores the lane untouched.
@MainActor
func drawerAutomationDrawPreviewChecks(
    _ report: CheckReport,
    suite: DocumentSession, service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64), (72, 100), (120, 40)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let ink = SceneRectPacking.argb(page.palette.automationNodeInk)
    let coveredY = fixture.y(fixture.panLane, 100)
    func heldRun(atY y: Double, fromTick tick: Tick, _ probe: AutomationDisplayProbe) -> Bool {
        probe.statics.contains {
            $0.argb == ink && $0.h == 2 && abs($0.y - (y - 1)) <= 1
                && abs($0.x - fixture.x(tick)) <= 1
        }
    }
    func heldRunAtCoveredValue(_ probe: AutomationDisplayProbe) -> Bool {
        heldRun(atY: coveredY, fromTick: 72, probe)
    }
    func nodeTicks() -> [Double] { page.publishedNodes.map(\.tick) }
    report.expect(
        heldRunAtCoveredValue(AutomationDisplayProbe(page)) && nodeTicks().contains(72),
        cppID: drawerAutomationProjectionID,
        message: "the resting lane draws the 72 node and its held run")
    let before = fixture.snapshot
    let pressY = fixture.y(fixture.panLane, 20)
    let button = AutomationQtButton.left
    _ = page.pointerPress(x: fixture.x(48), y: pressY, surface: 1, button: button)
    _ = page.pointerMove(x: fixture.x(48), y: pressY - 30, buttons: button)
    _ = page.pointerMove(x: fixture.x(88), y: pressY - 30, buttons: button)
    let drawing = AutomationDisplayProbe(page)
    report.expect(
        !heldRunAtCoveredValue(drawing), cppID: drawerAutomationProjectionID,
        message: "a live sweep drops the held run it replaces")
    report.expect(
        !nodeTicks().contains(72) && nodeTicks().contains(24)
            && nodeTicks().contains(120),
        cppID: drawerAutomationProjectionID,
        message: "a live sweep hides only the nodes it replaces")
    report.expect(
        page.handleEscape(), cppID: drawerAutomationProjectionID,
        message: "Escape cancels the live sweep")
    let restored = AutomationDisplayProbe(page)
    report.expect(
        !heldRun(atY: pressY, fromTick: 48, restored)
            && heldRunAtCoveredValue(restored) && nodeTicks().contains(72),
        cppID: drawerAutomationProjectionID,
        message: "a cancelled sweep restores the resting lane")
    report.expectEqual(
        expected: before, actual: fixture.snapshot,
        cppID: drawerAutomationProjectionID,
        what: "a previewed and cancelled sweep writes nothing")
    _ = page.pointerPress(x: fixture.x(48), y: pressY, surface: 1, button: button)
    _ = page.pointerMove(x: fixture.x(48), y: pressY - 30, buttons: button)
    _ = page.pointerMove(x: fixture.x(88), y: pressY - 30, buttons: button)
    let drafted = page.previewPoints.map { "\($0.tick):\($0.value)" }
    let draftTicks = (page.previewPoints.first?.tick ?? 0)...(page.previewPoints.last?.tick ?? 0)
    _ = page.pointerRelease(x: fixture.x(88), y: pressY - 30, button: button)
    let committed = fixture.lanePoints(fixture.panLane)
        .filter { draftTicks.contains(Tick($0.tick)) }.map { "\($0.tick):\($0.value)" }
    report.expectEqual(
        expected: drafted, actual: committed, cppID: drawerAutomationProjectionID,
        what: "a sweep's draft markers are exactly the points its release writes")
    page.detach()
}
