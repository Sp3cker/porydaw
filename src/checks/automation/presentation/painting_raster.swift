import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
func drawerAutomationRasterScrolledPhantom(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/raster/AutomationRasterTest::hoverGhostRingAndLeaveClear"
    let tempo = [
        (Tick(0), TimeDefaults.microsecondsPerQuarterNote(forBPM: 79)),
        (Tick(144), TimeDefaults.microsecondsPerQuarterNote(forBPM: 196)),
    ]
    for isTempo in [false, true] {
        let fixture = drawerAutomationAutomationFixture(
            suite: suite, service: service,
            pan: [(0, 32), (144, 95)], tempo: tempo)
        let parameter = isTempo ? AutomationParameter.tempo : fixture.panLane
        let heldValue = isTempo ? 79 : 32
        let nodeValue = isTempo ? 196 : 95
        let cursorValue = isTempo ? 138 : 64
        fixture.activate(parameter)
        let radius = max(1, (fixture.page.baseFontPx * 7 / 12).rounded())
        let scroll = fixture.x(144) + 2 * radius
        _ = fixture.session.mutateCamera { $0.setHScroll(scroll) }
        let page = fixture.page
        let sourceY = fixture.y(parameter, nodeValue)
        let targetY = fixture.y(parameter, cursorValue)
        report.expect(
            abs(targetY - sourceY) > page.geometry.nodeDragActivationDistance,
            cppID: id,
            message: "the scrolled phantom drag target exceeds the production activation distance")
        guard let source = page.projection?.originPhantom,
            let phantom = page.publishedNodes.first(where: \.phantom)
        else {
            report.fail(id, "the fork tick-144 source is not drawn as a scrolled origin phantom")
            continue
        }
        report.expect(
            source.point.tick == 144 && source.point.value == nodeValue
                && phantom.tick == 144 && phantom.value == nodeValue,
            cppID: id,
            message: "the fork scrolled origin retains the original tick-144 value")
        let original = fixture.snapshot
        let originalIndex = fixture.document.history.undoIndex
        let originalBytes = try? fixture.document.captureSave().bytes
        _ = page.pointerMove(x: 0, y: sourceY, buttons: 0)
        report.expectEqual(
            expected: AutomationParameterMetadata(parameter: parameter).valueText(nodeValue),
            actual: page.hoverText, cppID: id,
            what: "the fork phantom hover has exactly its original source-value text")
        report.expect(
            page.hoverVisible && page.publishedNodes.filter(\.hovered).count == 1,
            cppID: id, message: "exactly one scrolled phantom shows the hover ring")
        _ = page.pointerMove(x: 0, y: sourceY, buttons: 0)
        report.expect(
            fixture.snapshot == original
                && originalBytes != nil
                && originalBytes == (try? fixture.document.captureSave().bytes)
                && fixture.document.history.undoIndex == originalIndex,
            cppID: id,
            message: "repeated scrolled phantom hover retains the original snapshot, serialized bytes and history index"
        )
        page.pointerLeave()
        page.pointerLeave()
        report.expect(
            !page.hoverVisible && page.hoverText.isEmpty
                && !page.publishedNodes.contains(where: \.hovered),
            cppID: id, message: "a repeated plot leave keeps the phantom hover state clear")
        report.expect(
            fixture.snapshot == original
                && originalBytes != nil
                && originalBytes == (try? fixture.document.captureSave().bytes)
                && fixture.document.history.undoIndex == originalIndex,
            cppID: id,
            message:
                "double scrolled phantom pointer leave retains the original snapshot, serialized bytes and history index"
        )
        _ = page.pointerMove(x: 0, y: sourceY, buttons: 0)
        let pressed = page.pointerPress(
            x: 0, y: sourceY, surface: 1,
            button: AutomationQtButton.left)
        report.expect(
            pressed && page.hasGesture,
            cppID: id, message: "a real plot press captures the scrolled source phantom")
        _ = page.pointerMove(x: 0, y: targetY, buttons: AutomationQtButton.left)
        let dragAnchor = 2 * targetY - sourceY
        _ = page.pointerMove(x: 0, y: dragAnchor, buttons: AutomationQtButton.left)
        report.expectEqual(
            expected: original, actual: fixture.snapshot, cppID: id,
            what: "the scrolled phantom hover and drag do not commit")
        report.expect(
            originalBytes != nil
                && originalBytes == (try? fixture.document.captureSave().bytes),
            cppID: id, message: "the held scrolled phantom retains exact document bytes")
        fixture.activate(isTempo ? fixture.panLane : .tempo)
        let cancelledPreview = AutomationDisplayProbe(page)
        report.expect(
            !page.hasGesture && cancelledPreview.valid
                && cancelledPreview.preview.isEmpty
                && !page.hoverVisible,
            cppID: id, message: "switching lanes clears the phantom ring and transient draft")
        report.expectEqual(
            expected: original, actual: fixture.snapshot, cppID: id,
            what: "lane switching cancels without touching document or history")
        report.expect(
            originalBytes != nil
                && originalBytes == (try? fixture.document.captureSave().bytes),
            cppID: id, message: "the cancelled phantom retains exact document bytes")
        fixture.activate(parameter)
        page.pointerLeave()
        report.expect(
            fixture.snapshot == original
                && originalBytes != nil
                && originalBytes == (try? fixture.document.captureSave().bytes)
                && fixture.document.history.undoIndex == originalIndex,
            cppID: id,
            message:
                "the reactivated phantom leave retains the complete scrolled snapshot, serialized bytes and history index"
        )
        _ = page.pointerMove(x: 0, y: sourceY, buttons: 0)
        let rearmed = page.pointerPress(
            x: 0, y: sourceY, surface: 1,
            button: AutomationQtButton.left)
        _ = page.pointerMove(x: 0, y: targetY, buttons: AutomationQtButton.left)
        _ = page.pointerMove(x: 0, y: dragAnchor, buttons: AutomationQtButton.left)
        let committed = page.pointerRelease(x: 0, y: dragAnchor, button: AutomationQtButton.left)
        report.expect(
            !page.hoverVisible && page.hoverText.isEmpty
                && !page.publishedNodes.contains(where: \.hovered),
            cppID: id, message: "the committed phantom drag clears hover before any plot leave")
        page.pointerLeave()
        report.expect(
            !page.hoverVisible && page.hoverText.isEmpty
                && !page.publishedNodes.contains(where: \.hovered),
            cppID: id, message: "leaving the plot after the phantom commit keeps hover clear")
        let values = isTempo ? fixture.tempoValues : fixture.values(fixture.panLane)
        report.expect(
            rearmed && committed
                && values == ["0:\(heldValue)", "144:\(cursorValue)"]
                && fixture.document.revision == original.revision + 1
                && fixture.document.history.undoIndex == originalIndex + 1,
            cppID: id,
            message:
                "the fork phantom release changes the original tick-144 cursor value once without an edge duplicate")
        report.expect(
            page.publishedNodes.first(where: \.phantom)?.value == cursorValue,
            cppID: id, message: "the committed phantom publishes the exact staged cursor value")
        report.expect(
            originalBytes != nil
                && originalBytes != (try? fixture.document.captureSave().bytes),
            cppID: id, message: "the committed fork phantom changes exact document bytes")
    }
}

@MainActor
func drawerAutomationRasterHalfOpenGeometry(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/raster/AutomationRasterTest::halfOpenTrackSelectionRendersOnlyIncludedNodes"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(48, 40), (72, 80), (120, 55)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let normal = page.publishedNodes
    let nodes = [(Tick(48), 40), (Tick(72), 80), (Tick(120), 55)]
    for (tick, value) in nodes {
        let expectedX = fixture.x(tick)
        let expectedY = fixture.y(fixture.panLane, value)
        report.expect(
            normal.contains {
                $0.tick == Double(tick) && $0.value == value && abs($0.x - expectedX) <= 1
                    && abs($0.y - expectedY) <= 1
                    && !$0.selected && $0.outlineColor == page.palette.automationNodeInk
            }, cppID: id, message: "each fork Pan group paints its unselected value at the independent projected point")
    }
    let bytes = try? fixture.document.captureSave().bytes
    for endTick in [Tick(72), Tick(73)] {
        page.applyTimeSelection(
            AutomationTimeSelection(
                range: TimeRange(startTick: 48, endTick: endTick),
                scope: .tracks([0])))
        let expected = endTick == 72 ? [Tick(48)] : [Tick(48), Tick(72)]
        report.expectEqual(
            expected: expected, actual: page.publishedNodes.filter(\.selected).map { Tick($0.tick) },
            cppID: id,
            what: "the half-open track range includes exactly the fork Pan groups before its endpoint")
        report.expect(
            page.publishedNodes.filter(\.selected).allSatisfy {
                $0.ringRadius > $0.radius
                    && $0.ringColor == page.palette.selectionRing
            }, cppID: id, message: "each selected fork Pan group publishes an outer selection annulus")
        let selection = AutomationDisplayProbe(page)
        let fillColor = SceneRectPacking.argb(page.palette.selectionFill)
        let reticleEdge = SceneRectPacking.argb(page.palette.selectionEdge)
        let endX = min(page.plotWidth, page.xForTick(endTick))
        report.expect(
            selection.valid
                && selection.statics.filter({ $0.argb == fillColor }).count == 1
                && selection.statics.filter({ $0.argb == reticleEdge }).count == 2
                && selection.statics.contains {
                    $0.argb == fillColor && abs($0.x - page.xForTick(48)) <= 1
                        && abs($0.x + $0.w - endX) <= 1.5
                }
                && selection.statics.contains {
                    $0.argb == reticleEdge && $0.w == 1 && abs($0.x + $0.w - endX) <= 1.5
                }
                && page.publishedNodes.count == normal.count,
            cppID: id,
            message: "the selection reticle's drawn edge follows the fork half-open endpoint without dropping nodes")
        report.expect(
            bytes != nil && bytes == (try? fixture.document.captureSave().bytes),
            cppID: id, message: "changing track range preserves exact serialized song bytes")
    }
    report.expectEqual(
        expected: AutomationTimeSelection(
            range: TimeRange(startTick: 48, endTick: 73),
            scope: .tracks([0])),
        actual: fixture.session.timeSelection, cppID: id,
        what: "the retained fork selection has exact endpoints, track scope, empty lane list and false Tempo flag")
    fixture.activate(.tempo)
    report.expect(
        fixture.page.publishedTabs.first(where: { $0.tempo })?.active == true
            && fixture.session.timeSelection
                == AutomationTimeSelection(
                    range: TimeRange(startTick: 48, endTick: 73),
                    scope: .tracks([0])),
        cppID: id,
        message: "switching to the away Tempo lane retains the exact fork half-open selection")
}
