import Foundation
@testable import PorydawApp
import PorydawCore

// Point-range replacement scenarios paired with gestures.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationPointRangeAndPencilReplacements(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let metadata = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    let freeze = AutomationLaneFreeze(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan), revision: 7,
        metadata: metadata, songEndTick: 96,
        original: [
            AutomationLanePoint(tick: 0, value: 20),
            AutomationLanePoint(tick: 24, value: 60),
            AutomationLanePoint(tick: 72, value: 90),
        ])
    report.expectEqual(
        expected: 7, actual: freeze.revision, cppID: drawerAutomationPointRangeID,
        what: "the frozen lane carries the revision it was read at")
    let originalPointRange = AutomationLaneFreeze(
        parameter: freeze.parameter, revision: freeze.revision, metadata: metadata,
        songEndTick: 96,
        original: [
            AutomationLanePoint(tick: 24, value: 64),
            AutomationLanePoint(tick: 48, value: 64),
        ])
    report.expect(
        AutomationLaneReplacement.pointRange(
            originalPointRange, begin: 24, end: 48,
            points: [
                AutomationLanePoint(tick: 24, value: 64),
                AutomationLanePoint(tick: 48, value: 64),
            ]
        ).unchanged,
        cppID: drawerAutomationPointRangeID, message: "the original two-point range is unchanged")
    report.expect(
        !AutomationLaneReplacement.pointRange(
            originalPointRange, begin: 24, end: 48,
            points: [AutomationLanePoint(tick: 24, value: 64)]
        ).unchanged,
        cppID: drawerAutomationPointRangeID, message: "dropping the original range endpoint changes it")

    // Swift freezes an implicit lead-in into the held series before replacement.
    // This is the original arbitrary value 20; the page pencil case below also
    // exercises the actual Modulation engine default through production setup.
    let leadIn = AutomationLaneFreeze(
        parameter: freeze.parameter, revision: freeze.revision,
        metadata: metadata, songEndTick: 96,
        original: [AutomationLanePoint(tick: 0, value: 20)])
    let leadInCompletion = AutomationLaneReplacement.heldSpan(
        leadIn, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 80)])
    report.expect(
        !leadInCompletion.unchanged, cppID: drawerAutomationPointRangeID,
        message: "the original implicit lead-in replacement changes the lane")
    report.expectEqual(
        expected: [
            AutomationLanePoint(tick: 24, value: 80),
            AutomationLanePoint(tick: 48, value: 20),
        ], actual: leadInCompletion.points,
        cppID: drawerAutomationPointRangeID,
        what: "the original implicit lead-in is restored at the two-point span end")

    // An identical point range is unchanged.
    let identical = AutomationLaneReplacement.pointRange(
        freeze, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 60)])
    report.expect(
        identical.unchanged, cppID: drawerAutomationPointRangeID,
        message: "an identical point range is unchanged")
    let shortened = AutomationLaneReplacement.pointRange(
        freeze, begin: 24, end: 48,
        points: [
            AutomationLanePoint(tick: 24, value: 64),
            AutomationLanePoint(tick: 48, value: 64),
        ])
    report.expect(
        !shortened.unchanged, cppID: drawerAutomationPointRangeID,
        message: "a range the lane does not hold is a change")

    // A held-span replacement restores the boundary endpoint.
    let restored = AutomationLaneReplacement.heldSpan(
        freeze, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 80)])
    report.expect(
        !restored.unchanged, cppID: drawerAutomationPointRangeID,
        message: "a held-span replacement that differs is a change")
    report.expectEqual(
        expected: ["24:80", "48:60"], actual: restored.points.map { "\($0.tick):\($0.value)" },
        cppID: drawerAutomationPointRangeID,
        what: "the held span closes on the original endpoint's value")
    report.expectEqual(
        expected: Tick(48), actual: restored.tickEnd, cppID: drawerAutomationPointRangeID,
        what: "the replacement names the last tick it covers")

    // A flat replacement is unchanged; an empty one deletes the span.
    let flat = AutomationLaneReplacement.heldSpan(
        freeze, begin: 36, end: 48, points: [AutomationLanePoint(tick: 36, value: 60)])
    report.expect(
        flat.unchanged, cppID: drawerAutomationPointRangeID,
        message: "a replacement the lane already holds is unchanged")
    report.expectEqual(
        expected: 0, actual: flat.points.count, cppID: drawerAutomationPointRangeID,
        what: "an unchanged replacement carries no point")
    let deletion = AutomationLaneReplacement.heldSpan(freeze, begin: 24, end: 96, points: [])
    report.expect(
        !deletion.unchanged, cppID: drawerAutomationPointRangeID,
        message: "an empty replacement over a covered span deletes it")
    report.expectEqual(
        expected: 0, actual: deletion.points.count, cppID: drawerAutomationPointRangeID,
        what: "the deleting replacement carries no point")

    // The canonicalization and held-value rules.
    report.expectEqual(
        expected: ["8:20", "24:40"],
        actual: AutomationLaneReplacement.canonical(
            [
                AutomationLanePoint(tick: 24, value: 30),
                AutomationLanePoint(tick: 8, value: 20),
                AutomationLanePoint(tick: 32, value: 30),
                AutomationLanePoint(tick: 24, value: 40),
            ],
            begin: 0, end: 30, minimum: 0, maximum: 127, priorValue: nil
        )
        .map { "\($0.tick):\($0.value)" },
        cppID: drawerAutomationPointRangeID,
        what: "canonicalization sorts, drops the far tick and keeps the last occupant")
    report.expectEqual(
        expected: ["0:0", "24:9"],
        actual: AutomationLaneReplacement.canonical(
            [
                AutomationLanePoint(tick: 0, value: -4),
                AutomationLanePoint(tick: 9, value: -4),
                AutomationLanePoint(tick: 24, value: 9),
            ],
            begin: 0, end: 96, minimum: 0, maximum: 9, priorValue: nil
        )
        .map { "\($0.tick):\($0.value)" },
        cppID: drawerAutomationPointRangeID,
        what: "canonicalization clamps into the domain and drops repeated values")
    let held = [AutomationLanePoint(tick: 8, value: 20), AutomationLanePoint(tick: 24, value: 30)]
    report.expect(
        AutomationLaneReplacement.held(held, at: 8, inclusive: false) == nil,
        cppID: drawerAutomationPointRangeID,
        message: "the exclusive held lookup skips a point on the tick")
    report.expectEqual(
        expected: 20, actual: AutomationLaneReplacement.held(held, at: 8, inclusive: true) ?? -1,
        cppID: drawerAutomationPointRangeID,
        what: "the inclusive held lookup takes a point on the tick")
    report.expectEqual(
        expected: 30, actual: AutomationLaneReplacement.held(held, at: 40, inclusive: true) ?? -1,
        cppID: drawerAutomationPointRangeID,
        what: "the held lookup walks to the last point before the tick")
    report.expect(
        AutomationLaneReplacement.held(held, at: 4, inclusive: true) == nil,
        cppID: drawerAutomationPointRangeID, message: "the held lookup reports nothing before the first")

    // The pencil stroke on an empty lane with a lead-in.
    let emptyLane = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    let emptyFacts = emptyLane.facts(emptyLane.modulationLane)
    report.expectEqual(
        expected: 0, actual: emptyFacts.snapshot.leadInValue ?? -1, cppID: drawerAutomationPointRangeID,
        what: "an unwritten Modulation lane leads in on its engine default")
    guard
        let stroke = AutomationPencilTransaction(
            facts: emptyFacts,
            firstSample: AutomationPencilTransaction.Sample(
                rawTick: 24, logicalX: 24, logicalY: 40,
                point: AutomationLanePoint(tick: 24, value: 80), continuousValue: 80),
            firstCell: AutomationGridCell(tickBegin: 24, tickEnd: 48), clockTicks: 24)
    else {
        report.fail(drawerAutomationPointRangeID, "the pencil stroke did not start on an empty lane")
        return
    }
    report.expectEqual(
        expected: ["24:80", "48:0"], actual: emptyLane.laneValues(stroke.completion().points),
        cppID: drawerAutomationPointRangeID,
        what: "the stroke writes its point and restores the lane's held value")
    report.expectEqual(
        expected: ["24:80", "48:0"], actual: emptyLane.laneValues(stroke.preview.points),
        cppID: drawerAutomationPointRangeID, what: "the stroke's preview matches its completion")
    report.expect(
        !stroke.completion().unchanged, cppID: drawerAutomationPointRangeID,
        message: "an empty lane's first stroke is a change")

    // A stroke past the last point re-anchors that point's value.
    let pastLast = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [(0, 20)])
    let pastLastFacts = pastLast.facts(pastLast.modulationLane)
    guard
        let pastLastStroke = AutomationPencilTransaction(
            facts: pastLastFacts,
            firstSample: AutomationPencilTransaction.Sample(
                rawTick: 24, logicalX: 24, logicalY: 40,
                point: AutomationLanePoint(tick: 24, value: 80), continuousValue: 80),
            firstCell: AutomationGridCell(tickBegin: 24, tickEnd: 48), clockTicks: 24)
    else {
        report.fail(drawerAutomationPointRangeID, "the pencil stroke did not start past the last point")
        return
    }
    report.expectEqual(
        expected: ["24:80", "48:20"], actual: pastLast.laneValues(pastLastStroke.completion().points),
        cppID: drawerAutomationPointRangeID,
        what: "a stroke past the last point re-anchors that point's value")
    report.expect(
        !pastLastStroke.completion().unchanged, cppID: drawerAutomationPointRangeID,
        message: "a stroke past the last point reports a change")

    // Committed through the page's own press and release: one write, one entry.
    let committed = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [(0, 20)])
    let committedBefore = committed.snapshot
    committed.activate(committed.modulationLane)
    _ = committed.page.openParameterMenu(
        index: committed.page.catalogIndex(of: committed.modulationLane), x: 0, y: 0)
    report.expect(
        committed.page.consumeMenuAction(actionId: AutomationMenuAction.range127.rawValue),
        cppID: drawerAutomationPointRangeID, message: "the stroke fixture selects its intended value range")
    report.expectEqual(
        expected: committedBefore, actual: committed.snapshot, cppID: drawerAutomationPointRangeID,
        what: "preparing the display range leaves document and history unchanged")
    committed.page.isPencilMode = true
    let strokeY = committed.y(committed.modulationLane, 60)
    let cursorBeforeStroke = committed.session.editCursor
    let strokeIndex = committed.document.history.undoIndex
    let strokeCount = committed.document.history.undoCount
    let strokeBytes = try! committed.document.captureSave().bytes
    report.expect(
        committed.page.pointerPress(x: committed.x(24), y: strokeY, surface: 1, button: 1),
        cppID: drawerAutomationPointRangeID,
        message: "the pencil press starts a stroke")
    report.expect(
        committed.page.isPainting, cppID: drawerAutomationPointRangeID,
        message: "the page publishes the painting gesture")
    report.expect(
        !committed.page.bandVisible, cppID: drawerAutomationPointRangeID,
        message: "a pencil press previews no range")
    report.expect(
        committed.page.pointerRelease(x: committed.x(24), y: strokeY, button: 1), cppID: drawerAutomationPointRangeID,
        message: "the pencil release commits")
    report.expectEqual(
        expected: cursorBeforeStroke, actual: committed.session.editCursor,
        cppID: drawerAutomationPointRangeID, what: "a pencil stroke leaves the edit cursor untouched")
    report.expect(
        !committed.page.isPanning, cppID: drawerAutomationPointRangeID,
        message: "the released pencil stroke owns no pan")
    report.expect(
        !committed.page.bandVisible, cppID: drawerAutomationPointRangeID,
        message: "the released pencil stroke leaves no range preview")
    report.expectEqual(
        expected: committedBefore.revision + 1, actual: committed.document.revision,
        cppID: drawerAutomationPointRangeID,
        what: "one pencil press and release is one revision")
    report.expect(
        committed.document.history.undoIndex == strokeIndex + 1
            && committed.document.history.undoCount == strokeCount + 1
            && (try! committed.document.captureSave().bytes) != strokeBytes,
        cppID: drawerAutomationPointRangeID,
        message: "pencil release serializes one full-song history entry")
    report.expect(
        committed.values(committed.modulationLane).contains { $0.hasSuffix(":60") },
        cppID: drawerAutomationPointRangeID,
        message: "the released stroke writes the value under the pointer")
    report.expect(committed.undo(), cppID: drawerAutomationPointRangeID, message: "the stroke is undoable")
    report.expectEqual(
        expected: ["0:20"], actual: committed.values(committed.modulationLane), cppID: drawerAutomationPointRangeID,
        what: "one undo restores the pre-stroke lane")
    report.expect(
        !committed.document.history.canUndo, cppID: drawerAutomationPointRangeID,
        message: "the released stroke recorded exactly one history entry")
    report.expect(
        committed.document.history.undoIndex == strokeIndex
            && (try! committed.document.captureSave().bytes) == strokeBytes,
        cppID: drawerAutomationPointRangeID,
        message: "pencil undo restores exact song bytes and history index")
    let isolated = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(24, 60), (72, 80)], pan: [(24, 60)],
        modulation: [(48, 70)],
        tempo: [(0, 500_000), (96, 400_000)])
    let lfo = AutomationParameter.controlChange(track: 0, controller: 21)
    isolated.document.writeLane(
        track: 0, lane: .controller(21), from: 0,
        through: TimeDefaults.noTick,
        points: [LaneWrite(tick: 48, value: 75)])
    isolated.activate(isolated.panLane)
    let isolationBefore = isolated.snapshot
    report.expect(
        isolated.drag(isolated.panLane, from: (24, 60), to: 90, modifiers: 0),
        cppID: drawerAutomationPointRangeID,
        message: "a cross-lane gesture takes its own lane")
    report.expectEqual(
        expected: ["24:90"], actual: isolated.values(isolated.panLane),
        cppID: drawerAutomationPointRangeID,
        what: "a cross-lane gesture changes the active lane")
    report.expectEqual(
        expected: ["24:60", "72:80"], actual: isolated.values(isolated.volumeLane),
        cppID: drawerAutomationPointRangeID,
        what: "a cross-lane gesture writes nothing outside its lane")
    report.expectEqual(
        expected: ["48:70"], actual: isolated.values(isolated.modulationLane),
        cppID: drawerAutomationPointRangeID,
        what: "the modulation row keeps its original point")
    report.expectEqual(
        expected: ["48:75"], actual: isolated.values(lfo),
        cppID: drawerAutomationPointRangeID,
        what: "tempo, pan and LFO lanes isolate by band")
    report.expectEqual(
        expected: ["0:120", "96:150"], actual: isolated.tempoValues,
        cppID: drawerAutomationPointRangeID,
        what: "tempo, pan and LFO lanes isolate by band")
    report.expect(
        isolated.undo(), cppID: drawerAutomationPointRangeID,
        message: "the isolated gesture is undoable")
    report.expectEqual(
        expected: isolationBefore.identity,
        actual: isolated.snapshot.identity,
        cppID: drawerAutomationPointRangeID,
        what: "the isolated gesture has one undoable edit")
    report.expectEqual(
        expected: ["24:60"], actual: isolated.values(isolated.panLane),
        cppID: drawerAutomationPointRangeID,
        what: "undo restores the isolated lane")
}

@MainActor
func coreEventAutomationGestureCoreSeams(_ report: CheckReport) {
    let replacement = SongDocument(
        file: MidiFile(chunks: [
            MidiChunk(events: [
                .channel(status: 0xC0, data0: 1),
                .channel(tick: 0, status: 0xB0, data0: 7, data1: 20),
                .channel(tick: 24, status: 0xB0, data0: 7, data1: 60),
                .channel(tick: 72, status: 0xB0, data0: 7, data1: 90),
            ])
        ]))
    replacement.writeLane(
        track: 0, lane: .controller(7), from: 24, through: 48,
        points: [
            LaneWrite(tick: 24, value: 80),
            LaneWrite(tick: 48, value: 60),
        ])
    report.expectEqual(
        expected: ["0:20", "24:80", "48:60", "72:90"],
        actual: replacement.lanePoints(track: 0, lane: .controller(7))
            .map { "\($0.tick):\($0.value)" },
        cppID: "automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements",
        what: "core held-span replacement including the trailing held-value seam")

    let emptyLane = SongDocument(
        file: MidiFile(chunks: [
            MidiChunk(events: [.channel(status: 0xC0, data0: 1)])
        ]))
    emptyLane.writeLane(
        track: 0, lane: .controller(7), from: 24, through: 48,
        points: [
            LaneWrite(tick: 24, value: 80),
            LaneWrite(tick: 48, value: 20),
        ])
    report.expectEqual(
        expected: ["24:80", "48:20"],
        actual: emptyLane.lanePoints(track: 0, lane: .controller(7))
            .map { "\($0.tick):\($0.value)" },
        cppID: "automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements",
        what: "core empty-lane replacement stores the pencil value and restored tail")

    let trailingHold = SongDocument(
        file: MidiFile(chunks: [
            MidiChunk(events: [
                .channel(status: 0xC0, data0: 1),
                .channel(tick: 0, status: 0xB0, data0: 7, data1: 85),
            ])
        ]))
    trailingHold.writeLane(
        track: 0, lane: .controller(7), from: 48, through: 168,
        points: [
            LaneWrite(tick: 144, value: 25),
            LaneWrite(tick: 168, value: 85),
        ])
    report.expectEqual(
        expected: ["0:85", "144:25", "168:85"],
        actual: trailingHold.lanePoints(track: 0, lane: .controller(7))
            .map { "\($0.tick):\($0.value)" },
        cppID: "automation-domain/AutomationDomainTest::sweepFinishRestoresTrailingHeldValue",
        what: "core lane write retains the explicit post-sweep held-value seam")
}
let drawerAutomationEmptyPencilID = "swiftcore/AutomationPage::emptyLanePencilCommit"

// The empty-lane pencil stroke commits its own one-edit byte/undo comparison.
// Modulation opens on 0-16, so the stroke first selects the 127 display range.
@MainActor
func drawerAutomationEmptyLanePencilCommit(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let empty = drawerAutomationAutomationFixture(suite: suite, service: service, modulation: [])
    empty.activate(empty.modulationLane)
    _ = empty.page.openParameterMenu(
        index: empty.page.catalogIndex(of: empty.modulationLane), x: 0, y: 0)
    _ = empty.page.consumeMenuAction(actionId: AutomationMenuAction.range127.rawValue)
    empty.page.isPencilMode = true
    let before = DrawerAutomationStagedSnapshot(empty.document)
    let strokeY = empty.y(empty.modulationLane, 60)
    guard empty.page.pointerPress(x: empty.x(24), y: strokeY, surface: 1, button: 1) else {
        report.fail(drawerAutomationEmptyPencilID, "the empty-lane pencil press starts a stroke")
        return
    }
    _ = empty.page.pointerRelease(x: empty.x(24), y: strokeY, button: 1)
    let after = DrawerAutomationStagedSnapshot(empty.document)
    report.expect(
        empty.values(empty.modulationLane).contains { $0.hasSuffix(":60") }
            && after.revision == before.revision + 1
            && after.undoIndex == before.undoIndex + 1
            && after.undoCount == before.undoCount + 1
            && after.bytes != before.bytes,
        cppID: drawerAutomationEmptyPencilID,
        message: "the empty-lane pencil writes its value in one serialized history edit")
}
