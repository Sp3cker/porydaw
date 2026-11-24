import Foundation
import PorydawCore
import SwiftCoreCheckLogic

@testable import PorydawApp
@testable import PorydawAppPresentation
@testable import PorydawDocument

// Discrete Pan: PSG voices render only Left/Center/Right, so Pan lanes are
// three-stop inside the tick spans where the track's voice is a PSG voice.

let drawerAutomationDiscretePanID = "swiftcore/AutomationPage::discretePanSpans"

@MainActor
func drawerAutomationDiscretePanSpans(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    // Span resolution follows program spans; Direct Sound and keysplit
    // programs stay continuous, and adjacent PSG spans merge.
    let slots = [
        BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(macro: BankVoiceMacro.square1)),
        BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(macro: BankVoiceMacro.directSound)),
        BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(macro: BankVoiceMacro.keysplit)),
        BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(macro: BankVoiceMacro.noise)),
    ]
    let changes = [
        LanePoint(chunk: 1, eventIndex: 0, tick: 192, value: 1),
        LanePoint(chunk: 1, eventIndex: 1, tick: 384, value: 3),
    ]
    report.expectEqual(
        expected: [TimeRange(startTick: 0, endTick: 192), TimeRange(startTick: 384, endTick: 576)],
        actual: DiscretePan.spans(
            firstProgram: 0, voiceChanges: changes, slots: slots, songEndTick: 576),
        cppID: drawerAutomationDiscretePanID,
        what: "PSG program spans are discrete, Direct Sound spans are not")
    report.expectEqual(
        expected: [TimeRange](),
        actual: DiscretePan.spans(
            firstProgram: 2, voiceChanges: [], slots: slots, songEndTick: 576),
        cppID: drawerAutomationDiscretePanID,
        what: "a keysplit program never resolves to a discrete span without a key")
    report.expectEqual(
        expected: 64, actual: DiscretePan.nearestStop(32, minimum: 0, neutral: 64, maximum: 127),
        cppID: drawerAutomationDiscretePanID, what: "a tie settles toward center")
    report.expectEqual(
        expected: 0, actual: DiscretePan.nearestStop(30, minimum: 0, neutral: 64, maximum: 127),
        cppID: drawerAutomationDiscretePanID, what: "30 is nearer Left than Center")

    // A spanned snapshot snaps display and edits inside the span only; the
    // stored points themselves are untouched until an edit lands.
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 30), (240, 90)])
    let spanned = AutomationLaneSnapshot(
        parameter: fixture.panLane, in: fixture.document, songEndTick: fixture.songEndTick,
        discretePanSpans: [TimeRange(startTick: 0, endTick: 192)])
    report.expectEqual(
        expected: 0, actual: spanned.displayValue(30, at: 24),
        cppID: drawerAutomationDiscretePanID,
        what: "an in-between point displays on the Left stop inside the span")
    report.expectEqual(
        expected: 90, actual: spanned.displayValue(90, at: 240),
        cppID: drawerAutomationDiscretePanID,
        what: "the same value displays stored outside the span")
    report.expectEqual(
        expected: "Left", actual: spanned.valueText(30, at: 24),
        cppID: drawerAutomationDiscretePanID, what: "the readout names the stop inside the span")
    report.expectEqual(
        expected: ["24:30", "240:90"], actual: fixture.values(fixture.panLane),
        cppID: drawerAutomationDiscretePanID,
        what: "display snapping alone rewrites no stored point")

    // The projection draws the snapped height and labels the stops.
    let projection = AutomationProjection(
        camera: fixture.viewport.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationProjectionCache().snapPolicy(
            viewport: fixture.viewport, font: 13, dpr: 1),
        songEndTick: fixture.songEndTick)
    let lane = projection.project(spanned)
    let inside = lane.points.first { $0.tick == 24 }
    report.expectEqual(
        expected: projection.y(0, metadata: spanned.metadata), actual: inside?.y,
        cppID: drawerAutomationDiscretePanID,
        what: "the projected node sits on the Left stop's height")
    report.expectEqual(
        expected: 30, actual: inside?.value,
        cppID: drawerAutomationDiscretePanID,
        what: "the projected node keeps its stored value")
    report.expectEqual(
        expected: ["Right", "Left", "Center"],
        actual: lane.scaleLabels.map(\.text),
        cppID: drawerAutomationDiscretePanID,
        what: "the scale labels name the three stops")

    // A node drag inside the span writes the stop; outside it writes raw.
    let facts = AutomationFrozenFacts(
        parameter: fixture.panLane, snapshot: spanned,
        camera: fixture.viewport.camera.snapshot, selection: nil,
        modifiers: .init(), songEndTick: fixture.songEndTick)
    var drag = AutomationNodeDragTransaction.single(
        facts: facts, source: spanned.sources[0], press: (0, 0), deleteOnStationary: false)
    _ = drag.update(
        AutomationPointDrag.Update(phase: .dragging, effectiveX: 0, effectiveY: 0, axisLock: .none),
        mapped: AutomationLanePoint(tick: 24, value: 100))
    report.expectEqual(
        expected: 127, actual: drag.targets[0].current.value,
        cppID: drawerAutomationDiscretePanID,
        what: "dragging to 100 inside the span writes Right (127)")
    var outsideDrag = AutomationNodeDragTransaction.single(
        facts: facts, source: spanned.sources[1], press: (0, 0), deleteOnStationary: false)
    _ = outsideDrag.update(
        AutomationPointDrag.Update(phase: .dragging, effectiveX: 0, effectiveY: 0, axisLock: .none),
        mapped: AutomationLanePoint(tick: 240, value: 100))
    report.expectEqual(
        expected: 100, actual: outsideDrag.targets[0].current.value,
        cppID: drawerAutomationDiscretePanID,
        what: "dragging to 100 outside the span writes 100")

    // The value prompt quantizes its result inside the span.
    let prompt = AutomationPromptTransaction(
        facts: facts, anchor: AutomationLanePoint(tick: 24, value: 30),
        source: spanned.sources[0], forExistingNode: true, metadata: spanned.metadata)
    report.expectEqual(
        expected: 127, actual: prompt?.storedValue(displayed: 36),
        cppID: drawerAutomationDiscretePanID,
        what: "a prompted 100 inside the span stores Right (127)")
    report.expectEqual(
        expected: -64, actual: prompt?.prompt.initialValue,
        cppID: drawerAutomationDiscretePanID,
        what: "a prompt on an in-between 30 inside the span opens on Left")
    report.expectEqual(
        expected: AutomationPromptOutcome.none,
        actual: prompt.map { $0.outcome(displayed: $0.prompt.initialValue) },
        cppID: drawerAutomationDiscretePanID,
        what: "accepting the unchanged prompt on an in-between point writes nothing")

    // A pencil stroke's first point lands on the stop.
    let cell = AutomationGridCell(tickBegin: 0, tickEnd: 24)
    let sample = AutomationPencilTransaction.Sample(
        rawTick: 0, logicalX: 0, logicalY: 0,
        point: AutomationLanePoint(tick: 0, value: 100), continuousValue: 100)
    let pencil = AutomationPencilTransaction(
        facts: facts, firstSample: sample, firstCell: cell, clockTicks: 24)
    report.expectEqual(
        expected: [AutomationLanePoint(tick: 0, value: 127)], actual: pencil?.strokePoints,
        cppID: drawerAutomationDiscretePanID,
        what: "a pencil stroke inside the span starts on Right (127)")
}
