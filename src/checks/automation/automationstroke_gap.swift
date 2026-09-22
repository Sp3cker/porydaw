import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

private let automationStrokeGapID = "automation/AutomationEditingTest::strokeGapContracts"
private let automationPencilGapID = "automation/AutomationEditingTest::pencilGapContracts"

@MainActor
private func automationGapBeginPencil(
    _ fixture: drawerAutomationAutomationFixture,
    parameter: AutomationParameter,
    tick: Tick,
    value: Int,
    modifiers: Int = 0
) -> Bool {
    fixture.activate(parameter)
    fixture.page.isPencilMode = true
    return fixture.page.pointerPress(
        x: fixture.x(tick), y: fixture.y(parameter, value),
        surface: AutomationInputSurface.plot.rawValue, button: 1, modifiers: modifiers)
}

@MainActor
private func automationGapFinishPencil(
    _ fixture: drawerAutomationAutomationFixture,
    parameter: AutomationParameter,
    tick: Tick,
    value: Int,
    modifiers: Int = 0
) -> Bool {
    fixture.page.pointerRelease(
        x: fixture.x(tick), y: fixture.y(parameter, value),
        button: 1, modifiers: modifiers)
}

@MainActor
func drawerAutomationStrokeGapChecks(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let jitter = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 64), (144, 20)])
    let jitterBefore = jitter.snapshot
    report.expect(
        automationGapBeginPencil(jitter, parameter: jitter.panLane, tick: 24, value: 80),
        cppID: automationStrokeGapID,
        message: "A001-A005 sub-cell jitter captures the active Pan pencil lane")
    let initialJitter = jitter.page.previewPoints
    _ = jitter.page.pointerMove(
        x: jitter.x(24) + 2, y: jitter.y(jitter.panLane, 80), buttons: 1)
    _ = jitter.page.pointerMove(
        x: jitter.x(24) + 4, y: jitter.y(jitter.panLane, 80), buttons: 1)
    report.expectEqual(
        initialJitter.map(\.value), jitter.page.previewPoints.map(\.value),
        cppID: automationStrokeGapID,
        what: "A006-A011 horizontal sub-cell jitter retains the stroke value")
    _ = automationGapFinishPencil(jitter, parameter: jitter.panLane, tick: 24, value: 80)
    report.expectEqual(
        jitterBefore.revision + 1, jitter.document.revision,
        cppID: automationStrokeGapID,
        what: "A006-A011 jitter stroke commits one transaction")

    let zigzag = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 64), (192, 64)])
    let freehand = DrawerModifiers.controlBit
    report.expect(
        automationGapBeginPencil(zigzag, parameter: zigzag.panLane,
                                 tick: 24, value: 64, modifiers: freehand),
        cppID: automationStrokeGapID,
        message: "A012-A016 zigzag freehand stroke starts on Pan")
    for sample in [(Tick(48), 110), (Tick(72), 20), (Tick(96), 100), (Tick(120), 30)] {
        _ = zigzag.page.pointerMove(
            x: zigzag.x(sample.0), y: zigzag.y(zigzag.panLane, sample.1),
            buttons: 1, modifiers: freehand)
    }
    let zigzagValues = zigzag.page.previewPoints.map(\.value)
    report.expect(
        (zigzagValues.max() ?? 0) >= 95 && (zigzagValues.min() ?? 127) <= 35,
        cppID: automationStrokeGapID,
        message: "A017-A021 zigzag preview preserves both directional extrema")
    _ = automationGapFinishPencil(
        zigzag, parameter: zigzag.panLane, tick: 120, value: 30, modifiers: freehand)

    let vertical = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (144, 20)])
    report.expect(
        automationGapBeginPencil(vertical, parameter: vertical.panLane,
                                 tick: 48, value: 30),
        cppID: automationStrokeGapID,
        message: "A022-A024 vertical single-cell stroke starts")
    _ = vertical.page.pointerMove(
        x: vertical.x(48), y: vertical.y(vertical.panLane, 100), buttons: 1)
    _ = vertical.page.pointerMove(
        x: vertical.x(48), y: vertical.y(vertical.panLane, 75), buttons: 1)
    report.expect(
        abs((vertical.page.previewPoints.first(where: { $0.tick == 48 })?.value ?? 0) - 75) <= 1,
        cppID: automationStrokeGapID,
        message: "A025-A027 vertical motion in one cell retains the final value")
    _ = automationGapFinishPencil(vertical, parameter: vertical.panLane, tick: 48, value: 75)

    let sparse = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    let dense = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    report.expect(
        automationGapBeginPencil(sparse, parameter: sparse.panLane, tick: 24, value: 30)
            && automationGapBeginPencil(dense, parameter: dense.panLane, tick: 24, value: 30),
        cppID: automationStrokeGapID,
        message: "A028-A032 density fixtures start equivalent strokes")
    _ = sparse.page.pointerMove(
        x: sparse.x(120), y: sparse.y(sparse.panLane, 100), buttons: 1)
    for tick in stride(from: Tick(48), through: Tick(120), by: 24) {
        let value = 30 + Int((tick - 24) * 70 / 96)
        _ = dense.page.pointerMove(
            x: dense.x(tick), y: dense.y(dense.panLane, value), buttons: 1)
    }
    report.expectEqual(
        sparse.page.previewPoints, dense.page.previewPoints,
        cppID: automationStrokeGapID,
        what: "A033-A037 diagonal snapped stroke is invariant to pointer sample density")
    _ = sparse.page.handleEscape()
    _ = dense.page.handleEscape()

    let backtrack = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    report.expect(
        automationGapBeginPencil(backtrack, parameter: backtrack.panLane,
                                 tick: 24, value: 30),
        cppID: automationStrokeGapID,
        message: "A038-A040 backtracking stroke starts")
    _ = backtrack.page.pointerMove(
        x: backtrack.x(120), y: backtrack.y(backtrack.panLane, 100), buttons: 1)
    _ = backtrack.page.pointerMove(
        x: backtrack.x(48), y: backtrack.y(backtrack.panLane, 50), buttons: 1)
    _ = backtrack.page.pointerMove(
        x: backtrack.x(96), y: backtrack.y(backtrack.panLane, 80), buttons: 1)
    let backtrackPoints = backtrack.page.previewPoints
    report.expect(
        backtrackPoints.map(\.tick) == Array(Set(backtrackPoints.map(\.tick))).sorted()
            && (backtrackPoints.max(by: { $0.value < $1.value })?.value ?? 0) >= 80,
        cppID: automationStrokeGapID,
        message: "A041-A045 backtracking retains extrema with the latest value per revisited tick")
    _ = backtrack.page.handleEscape()

    let plain = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    let locked = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    report.expect(
        automationGapBeginPencil(plain, parameter: plain.panLane, tick: 24, value: 40)
            && automationGapBeginPencil(locked, parameter: locked.panLane,
                                        tick: 24, value: 40,
                                        modifiers: DrawerModifiers.shiftBit),
        cppID: automationStrokeGapID,
        message: "A046-A048 plain and Shift pencil strokes start")
    _ = plain.page.pointerMove(
        x: plain.x(120), y: plain.y(plain.panLane, 100), buttons: 1)
    _ = locked.page.pointerMove(
        x: locked.x(120), y: locked.y(locked.panLane, 100), buttons: 1,
        modifiers: DrawerModifiers.shiftBit)
    report.expect(
        Set(plain.page.previewPoints.filter { $0.tick >= 24 && $0.tick <= 120 }.map(\.value)).count > 1,
        cppID: automationStrokeGapID,
        message: "A049-A055 unlocked pencil follows the value dimension")
    report.expect(
        Set(locked.page.previewPoints.filter { $0.tick >= 24 && $0.tick <= 120 }.map(\.value)).count == 1,
        cppID: automationStrokeGapID,
        message: "A051-A057 Shift locks every pencil sample to one value")
    _ = plain.page.handleEscape()
    _ = locked.page.handleEscape()

    let quantized = drawerAutomationAutomationFixture(
        suite: suite, service: service, division: 24,
        pan: [(0, 20), (192, 20)])
    report.expect(
        automationGapBeginPencil(quantized, parameter: quantized.panLane,
                                 tick: 25, value: 30, modifiers: freehand),
        cppID: automationStrokeGapID,
        message: "A058-A060 Control starts an unsnapped freehand stroke")
    _ = quantized.page.pointerMove(
        x: quantized.x(119), y: quantized.y(quantized.panLane, 90),
        buttons: 1, modifiers: freehand)
    let policy = AutomationSnapPolicy(
        document: quantized.document, timeline: quantized.session.timeline,
        baseFontPx: quantized.page.baseFontPx, devicePixelRatio: 1)
    report.expect(
        !quantized.page.previewPoints.isEmpty
            && quantized.page.previewPoints.allSatisfy { $0.tick % policy.clockTicks == 0 },
        cppID: automationStrokeGapID,
        message: "A061-A063 Control freehand points remain document-clock quantized")
    _ = quantized.page.handleEscape()

    let mixed = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    report.expect(
        automationGapBeginPencil(mixed, parameter: mixed.panLane, tick: 24, value: 30),
        cppID: automationStrokeGapID,
        message: "A064-A066 mixed-modifier stroke starts snapped")
    _ = mixed.page.pointerMove(
        x: mixed.x(72), y: mixed.y(mixed.panLane, 60), buttons: 1)
    _ = mixed.page.pointerMove(
        x: mixed.x(96), y: mixed.y(mixed.panLane, 90),
        buttons: 1, modifiers: freehand)
    _ = mixed.page.pointerMove(
        x: mixed.x(144), y: mixed.y(mixed.panLane, 40), buttons: 1)
    report.expect(
        mixed.page.previewPoints.contains { $0.tick > 72 && $0.tick < 144 }
            && abs((mixed.page.previewPoints.first(where: { $0.tick == 144 })?.value ?? 0) - 40) <= 1,
        cppID: automationStrokeGapID,
        message: "A067-A070 mixed stroke composes freehand interiors with snapped final segment")
    _ = mixed.page.handleEscape()

    let altPlain = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    let altHeld = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (192, 20)])
    report.expect(
        automationGapBeginPencil(altPlain, parameter: altPlain.panLane, tick: 24, value: 30)
            && automationGapBeginPencil(altHeld, parameter: altHeld.panLane,
                                        tick: 24, value: 30,
                                        modifiers: DrawerModifiers.altBit),
        cppID: automationStrokeGapID,
        message: "A071-A073 plain and Alt pencil strokes start")
    _ = altPlain.page.pointerMove(
        x: altPlain.x(120), y: altPlain.y(altPlain.panLane, 90), buttons: 1)
    _ = altHeld.page.pointerMove(
        x: altHeld.x(120), y: altHeld.y(altHeld.panLane, 90),
        buttons: 1, modifiers: DrawerModifiers.altBit)
    report.expectEqual(
        altPlain.page.previewPoints, altHeld.page.previewPoints,
        cppID: automationStrokeGapID,
        what: "A074/A075 Alt is ignored throughout a pencil stroke")
    _ = altPlain.page.handleEscape()
    _ = altHeld.page.handleEscape()
}

@MainActor
func drawerAutomationPencilGapChecks(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let empty = drawerAutomationAutomationFixture(
        suite: suite, service: service, modulation: [])
    let emptyBefore = empty.snapshot
    report.expect(
        automationGapBeginPencil(empty, parameter: empty.modulationLane,
                                 tick: 24, value: 80),
        cppID: automationPencilGapID,
        message: "A001-A007 empty-lane pencil press captures Modulation")
    _ = empty.page.pointerMove(
        x: empty.x(96), y: empty.y(empty.modulationLane, 40), buttons: 1)
    report.expect(
        empty.page.isPainting && empty.page.observation.pointerKind == .pencilStroke,
        cppID: automationPencilGapID,
        message: "A003-A007 empty-lane stroke publishes pencil ownership")
    report.expectEqual(
        emptyBefore, empty.snapshot,
        cppID: automationPencilGapID,
        what: "A007 preview on empty lane changes no document or history state")
    report.expect(
        automationGapFinishPencil(empty, parameter: empty.modulationLane,
                                  tick: 96, value: 40),
        cppID: automationPencilGapID,
        message: "A008-A013 empty-lane release commits")
    report.expectEqual(
        emptyBefore.revision + 1, empty.document.revision,
        cppID: automationPencilGapID,
        what: "A008-A013 empty-lane stroke commits exactly one revision")
    report.expect(
        !empty.values(empty.modulationLane).isEmpty
            && empty.document.history.canUndo,
        cppID: automationPencilGapID,
        message: "A014-A017 empty-lane stroke writes quantized points and a held tail")
    report.expect(
        empty.undo() && empty.values(empty.modulationLane).isEmpty,
        cppID: automationPencilGapID,
        message: "A018-A021 one undo removes the entire empty-lane stroke")

    let preview = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 20), (144, 80)])
    let previewBefore = preview.snapshot
    report.expect(
        automationGapBeginPencil(preview, parameter: preview.panLane,
                                 tick: 24, value: 40),
        cppID: automationPencilGapID,
        message: "A022-A025 preview fixture starts pencil stroke")
    _ = preview.page.pointerMove(
        x: preview.x(96), y: preview.y(preview.panLane, 100), buttons: 1)
    report.expect(
        !preview.page.previewPoints.isEmpty && preview.page.previewLabelVisible,
        cppID: automationPencilGapID,
        message: "A026/A028/A029 pencil preview publishes points and label")
    report.expectEqual(
        previewBefore, preview.snapshot,
        cppID: automationPencilGapID,
        what: "A027 pencil preview does not mutate before release")
    _ = automationGapFinishPencil(preview, parameter: preview.panLane, tick: 96, value: 100)
    report.expectEqual(
        previewBefore.revision + 1, preview.document.revision,
        cppID: automationPencilGapID,
        what: "A030-A034 preview release commits one revision and history entry")

    let held = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 36), (144, 90)])
    let heldBefore = held.snapshot
    _ = automationGapBeginPencil(held, parameter: held.panLane, tick: 24, value: 80)
    _ = held.page.pointerMove(
        x: held.x(96), y: held.y(held.panLane, 50), buttons: 1)
    _ = automationGapFinishPencil(held, parameter: held.panLane, tick: 96, value: 50)
    report.expect(
        held.values(held.panLane).contains("120:36"),
        cppID: automationPencilGapID,
        message: "A035-A040 pencil stroke restores the held endpoint value after its final cell")
    report.expectEqual(
        heldBefore.revision + 1, held.document.revision,
        cppID: automationPencilGapID,
        what: "A040-A043 held-tail restoration commits once")

    let tempo = drawerAutomationAutomationFixture(
        suite: suite, service: service, tempo: [])
    let tempoBefore = tempo.snapshot
    _ = automationGapBeginPencil(tempo, parameter: .tempo, tick: 48, value: 150)
    _ = automationGapFinishPencil(tempo, parameter: .tempo, tick: 48, value: 150)
    report.expect(
        tempo.tempoValues.count == 2
            && tempo.tempoValues.first?.hasSuffix(":150") == true
            && tempo.tempoValues.last?.hasSuffix(":120") == true,
        cppID: automationPencilGapID,
        message: "A044-A050 Tempo single-cell stroke restores default Tempo at cell end")
    report.expectEqual(
        tempoBefore.revision + 1, tempo.document.revision,
        cppID: automationPencilGapID,
        what: "A049/A050 Tempo single-cell stroke is one transaction")

    let bend = drawerAutomationAutomationFixture(suite: suite, service: service)
    let bendBefore = bend.snapshot
    _ = automationGapBeginPencil(bend, parameter: bend.bendLane, tick: 48, value: 3000)
    _ = automationGapFinishPencil(bend, parameter: bend.bendLane, tick: 48, value: 3000)
    let bendPoints = bend.values(bend.bendLane)
    report.expect(
        bendPoints.count == 2
            && bendPoints.first?.hasSuffix(":3000") == true
            && bendPoints.last?.hasSuffix(":0") == true,
        cppID: automationPencilGapID,
        message: "A051-A058 pitch-bend single-cell stroke restores center at cell end")
    report.expectEqual(
        bendBefore.revision + 1, bend.document.revision,
        cppID: automationPencilGapID,
        what: "A057/A058 pitch-bend single-cell stroke commits once")

    let flat = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 64), (144, 64)])
    let flatBefore = flat.snapshot
    _ = automationGapBeginPencil(flat, parameter: flat.panLane, tick: 24, value: 64)
    _ = flat.page.pointerMove(
        x: flat.x(96), y: flat.y(flat.panLane, 64), buttons: 1)
    _ = automationGapFinishPencil(flat, parameter: flat.panLane, tick: 96, value: 64)
    report.expectEqual(
        flatBefore, flat.snapshot,
        cppID: automationPencilGapID,
        what: "A059-A062 flat replacement identical to held value is a no-op")

    let excursion = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(0, 36), (48, 90), (96, 36)])
    let excursionBefore = excursion.snapshot
    _ = automationGapBeginPencil(excursion, parameter: excursion.panLane,
                                 tick: 48, value: 36)
    _ = automationGapFinishPencil(excursion, parameter: excursion.panLane,
                                  tick: 48, value: 36)
    report.expectEqual(
        ["0:36", "96:36"], excursion.values(excursion.panLane),
        cppID: automationPencilGapID,
        what: "A063-A068 pencil click on excursion node removes the excursion")
    report.expectEqual(
        excursionBefore.revision + 1, excursion.document.revision,
        cppID: automationPencilGapID,
        what: "A068-A070 excursion deletion is one undoable transaction")

    let cancellationRows = [
        (name: "A071-escape", escape: true),
        (name: "A071-pointer-ungrab", escape: false),
        (name: "A071-window-deactivate", escape: false),
        (name: "A071-page-hidden", escape: false),
    ]
    for row in cancellationRows {
        let cancelled = drawerAutomationAutomationFixture(
            suite: suite, service: service, pan: [(0, 36), (144, 80)])
        let cancelledBefore = cancelled.snapshot
        report.expect(
            automationGapBeginPencil(cancelled, parameter: cancelled.panLane,
                                     tick: 24, value: 40),
            cppID: automationPencilGapID,
            message: "\(row.name) A071/A072 cancellation fixture starts pencil gesture")
        _ = cancelled.page.pointerMove(
            x: cancelled.x(96), y: cancelled.y(cancelled.panLane, 100), buttons: 1)
        let claimed: Bool
        if row.escape {
            claimed = cancelled.page.handleEscape()
        } else {
            cancelled.page.cancelSectionInteraction()
            claimed = true
        }
        report.expect(
            claimed && !cancelled.page.hasGesture
                && cancelled.page.previewPoints.isEmpty,
            cppID: automationPencilGapID,
            message: "\(row.name) A073 cancellation aborts gesture and clears preview synchronously")
        report.expectEqual(
            cancelledBefore, cancelled.snapshot,
            cppID: automationPencilGapID,
            what: "\(row.name) A073/A074 cancelled pencil gesture commits nothing")
    }
}
