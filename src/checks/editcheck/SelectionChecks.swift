@testable import PorydawApp
import Foundation
import PorydawAppCommands
import PorydawCore
@testable import PorydawDocument

@MainActor
func runClipboardSelectionChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0x90, data0: 60, data1: 90),
                    .channel(tick: 12, status: 0x80, data0: 60),
                    .channel(tick: 24, status: 0x90, data0: 62, data1: 91),
                    .channel(tick: 36, status: 0x80, data0: 62),
                    .channel(tick: 48, status: 0x90, data0: 64, data1: 92),
                    .channel(tick: 60, status: 0x80, data0: 64),
                ], endTick: 96)
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName)
    guard document.notes(in: 0).count == 3 else {
        report.fail(
            "clipboard/SelectionCheckTest::noteSelectionSanitizesAndExcludesTime",
            "selection fixture must contain three distinct notes")
        return
    }
    clipboardLaneSelectionChecks(report, viewport: DocumentViewport(session: session))
    clipboardNoteSelectionChecks(report, session: session)
    clipboardTrackSelectionChecks(report, session: session)
    clipboardUnifiedTimeSelectionChecks(report, suite: suite, service: service)
    clipboardUnifiedModelChecks(report, suite: suite, service: service)
    clipboardSelectionTransitionChecks(report, suite: suite, service: service)
    clipboardRemapBoundaryChecks(report, suite: suite, service: service)
    clipboardEmptyAndReplacementChecks(report, suite: suite, service: service)
}

@MainActor
private func clipboardNoteSelectionChecks(_ report: CheckReport, session: DocumentSession) {
    let sanitize = "clipboard/SelectionCheckTest::noteSelectionSanitizesAndExcludesTime"
    let clear = "clipboard/SelectionCheckTest::clearOperationsPreserveTheOtherSelection"
    let reconcile = "clipboard/SelectionCheckTest::reconciliationPreservesSelectionOrder"
    let document = session.document
    let ids = document.notes(in: 0).map(\.id)
    let invalid = NoteID()
    var changes: [SessionChangeDomains] = []
    session.onChange = { changes.append($0.domains) }
    defer { session.onChange = nil }

    session.setSelectedNotes([invalid, ids[0], ids[0], ids[1]])
    report.expectEqual(
        expected: [ids[0], ids[1]], actual: session.selectedNoteOrder, cppID: sanitize,
        what: "A001 unassigned and duplicate IDs are removed without changing order")
    report.expect(
        session.selectedNotes.contains(ids[0]), cppID: sanitize,
        message: "A002 first selected note is indexed")
    report.expect(
        session.selectedNotes.contains(ids[1]), cppID: sanitize,
        message: "A003 second selected note is indexed")
    report.expect(
        !session.selectedNotes.contains(ids[2]), cppID: sanitize,
        message: "A004 unselected note is not indexed")
    report.expect(
        !session.selectedNotes.contains(invalid), cppID: sanitize,
        message: "A005 unassigned note is not indexed")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: sanitize,
        what: "A006 note selection publishes exactly once")
    changes.removeAll()
    session.setSelectedNotes([invalid, ids[0], ids[1], ids[1]])
    report.expect(
        changes.isEmpty, cppID: sanitize,
        message: "A007 equivalent normalized selection publishes nothing")
    session.clearSelectedNotes()
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: sanitize,
        what: "A020 clearing notes publishes exactly once")
    report.expect(
        session.selectedNoteOrder.isEmpty, cppID: clear,
        message: "A045 clearing populated note selection removes every note")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: clear,
        what: "A046 clearing populated note selection publishes once")
    changes.removeAll()
    session.clearSelectedNotes()
    report.expect(
        changes.isEmpty, cppID: clear,
        message: "A047 repeated empty clear publishes nothing")

    session.setSelectedNotes([ids[2], ids[0], ids[1]])
    changes.removeAll()
    document.deleteNotes([ids[1]])
    report.expectEqual(
        expected: [ids[2], ids[0]], actual: session.selectedNoteOrder, cppID: reconcile,
        what: "A048 reconciliation preserves reverse selection order rather than sorting by document order")
    report.expect(
        changes.count == 1 && changes[0].contains(.selection), cppID: reconcile,
        message: "A049 one selection publication accompanies deletion reconciliation")
    changes.removeAll()
    document.renameTrack(0, to: "selection-reconcile")
    report.expect(
        changes.count == 1 && changes[0] == [.document, .dirty, .history]
            && session.selectedNoteOrder == [ids[2], ids[0]], cppID: reconcile,
        message: "A050 idempotent reconciliation publishes no selection change")
    changes.removeAll()
    document.deleteNotes([ids[0], ids[2]])
    report.expect(
        session.selectedNoteOrder.isEmpty && session.selectedNotes.isEmpty,
        cppID: reconcile, message: "A051 reconciliation to empty removes membership")
    report.expect(
        changes.count == 1 && changes[0].contains(.selection), cppID: reconcile,
        message: "A052 reconciliation to empty publishes once")
}

@MainActor
private func clipboardLaneSelectionChecks(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let emptyID = "clipboard/AutomationCoverageTest::emptySelectionAndEndpointPayload"
    let lanesID = "clipboard/AutomationCoverageTest::laneScopeCoverage"
    let tracksID = "clipboard/AutomationCoverageTest::trackScopeSeparatesLaneAndNodeCoverage"
    let hiddenID = "clipboard/AutomationCoverageTest::hiddenLanesAreNotCovered"
    let factsID = "clipboard/AutomationCoverageTest::documentFactsFollowIdentity"
    let document = session.document
    let pan = AutomationParameter.controlChange(track: 0, controller: 10)
    let volume = AutomationParameter.controlChange(track: 0, controller: 7)
    let modulation = AutomationParameter.controlChange(track: 0, controller: 21)
    func stack(_ selection: AutomationTimeSelection?, ready: Bool = true) -> AutomationRowStack {
        AutomationRowStack.build(
            document: document, primaryTrack: 0, selection: selection,
            ready: ready, songEndTick: 96)
    }
    let empty = stack(nil)
    func visibleSelectedLanes(_ rows: AutomationRowStack) -> [AutomationParameter] {
        rows.visibleRows.filter { !$0.parameter.isTempo && $0.coversLane }.map(\.parameter)
    }
    report.expect(
        empty.activeTickRange == nil, cppID: emptyID,
        message: "A002 empty selection has no active tick range")
    for (site, parameter) in [
        ("A003-A004", AutomationParameter.tempo),
        ("A005-A006", volume),
    ] {
        report.expect(
            empty.row(for: parameter)?.coversLane == false
                && empty.row(for: parameter)?.coversNodes == false,
            cppID: emptyID, message: "\(site) empty selection covers neither lane nor nodes")
    }
    report.expect(
        empty.row(for: .controlChange(track: 0, controller: 99)) == nil,
        cppID: emptyID, message: "A007-A008 unsupported controller covers nothing")
    report.expect(
        visibleSelectedLanes(empty).isEmpty, cppID: emptyID,
        message: "A009 empty selection exposes no selected visible lanes")
    clipboardLaneEndpointAndHitChecks(
        report, viewport: viewport, empty: empty,
        volume: volume, pan: pan)

    let range = TimeRange(startTick: 24, endTick: 48)
    let selection = AutomationTimeSelection(
        range: range, scope: .lanes,
        lanes: [volume, modulation], tempo: true)
    let covered = stack(selection)
    report.expectEqual(
        expected: range, actual: covered.activeTickRange, cppID: lanesID,
        what: "A013 lane-scoped range keeps its tick endpoints")
    for (site, parameter) in [
        ("A014-A015", AutomationParameter.tempo),
        ("A016-A017", volume), ("A018-A019", modulation),
    ] {
        report.expect(
            covered.row(for: parameter)?.coversLane == true
                && covered.row(for: parameter)?.coversNodes == true,
            cppID: lanesID, message: "\(site) selected row covers lane and nodes")
    }
    report.expect(
        covered.row(for: pan)?.coversLane == false
            && covered.row(for: pan)?.coversNodes == false,
        cppID: lanesID, message: "A020-A021 unselected supported controller stays uncovered")
    report.expect(
        covered.row(for: .controlChange(track: 0, controller: 99)) == nil,
        cppID: lanesID, message: "A022-A023 unsupported controller has no row")
    report.expectEqual(
        expected: [volume, modulation], actual: visibleSelectedLanes(covered), cppID: lanesID,
        what: "A024 only selected supported lanes are visible in catalog order")
    let noTempo = stack(
        AutomationTimeSelection(
            range: range, scope: .lanes,
            lanes: [volume], tempo: false))
    report.expect(
        noTempo.row(for: .tempo)?.coversLane == false
            && noTempo.row(for: .tempo)?.coversNodes == false,
        cppID: lanesID, message: "A025-A026 lane scope excludes unselected Tempo")

    let trackSelection = AutomationTimeSelection(range: range, scope: .tracks([0]))
    let trackStack = stack(trackSelection)
    report.expect(
        trackStack.row(for: volume)?.coversLane == false
            && trackStack.row(for: volume)?.coversNodes == true,
        cppID: tracksID, message: "A030-A031 track scope covers CC nodes, not entire lane")
    report.expect(
        trackStack.row(for: .tempo)?.coversLane == true,
        cppID: tracksID, message: "A028 full track scope covers Tempo lane")
    report.expect(
        trackStack.row(for: .tempo)?.coversNodes == true,
        cppID: tracksID, message: "A029 full track scope covers Tempo nodes")
    guard document.addTrack(voice: 0) != nil else {
        report.fail(tracksID, "cannot create the secondary track for partial Tempo coverage")
        return
    }
    let partial = stack(trackSelection)
    report.expect(
        partial.row(for: .tempo)?.coversLane == false,
        cppID: tracksID, message: "A033 partial track scope excludes Tempo lane")
    report.expect(
        partial.row(for: .tempo)?.coversNodes == false,
        cppID: tracksID, message: "A034 partial track scope excludes Tempo nodes")

    let ready = stack(
        AutomationTimeSelection(
            range: range, scope: .lanes,
            lanes: [
                volume,
                .controlChange(
                    track: 0,
                    controller: 99),
            ]))
    report.expect(
        ready.row(for: volume)?.coversLane == true, cppID: hiddenID,
        message: "A036 ready selected CC7 lane is covered")
    report.expect(
        ready.row(for: volume)?.coversNodes == true, cppID: hiddenID,
        message: "A037 ready selected CC7 nodes are covered")
    report.expect(
        ready.row(for: pan)?.coversLane == false, cppID: hiddenID,
        message: "A038 ready unselected CC10 lane is uncovered")
    report.expect(
        ready.row(for: pan)?.coversNodes == false, cppID: hiddenID,
        message: "A039 ready unselected CC10 nodes are uncovered")
    report.expectEqual(
        expected: [volume], actual: visibleSelectedLanes(ready), cppID: hiddenID,
        what: "A042 ready model exposes only selected supported lanes")

    let hidden = stack(
        AutomationTimeSelection(
            range: range, scope: .lanes,
            lanes: [
                volume,
                .controlChange(
                    track: 0,
                    controller: 99),
            ]), ready: false)
    report.expect(
        hidden.row(for: volume) != nil, cppID: hiddenID,
        message: "A043 page-not-ready still carries supported controller row")
    report.expect(
        hidden.row(for: volume)?.coversLane == false
            && hidden.row(for: volume)?.coversNodes == false,
        cppID: hiddenID, message: "A044-A045 hidden row covers nothing")
    report.expect(
        hidden.row(for: .controlChange(track: 0, controller: 99)) == nil,
        cppID: hiddenID, message: "A040-A041 unsupported controller stays absent")
    report.expect(
        visibleSelectedLanes(hidden).isEmpty, cppID: hiddenID,
        message: "A046 page-not-ready exposes no selected visible lanes")
    let prior = stack(selection).row(for: volume)?.eventCount
    document.writeLane(
        track: 0, lane: .controller(7), from: 0,
        through: TimeDefaults.noTick, points: [LaneWrite(tick: 24, value: 64)])
    let after = stack(selection).row(for: volume)?.eventCount
    report.expect(
        prior == 0, cppID: factsID,
        message: "A048 initially empty controller row has zero written events")
    report.expect(
        after == 1, cppID: factsID,
        message: "A049 rebuilding after a write counts its event")
    report.expect(
        stack(selection).row(for: pan) != nil, cppID: factsID,
        message: "A050 supported controller is present without a selection")
    report.expect(
        stack(selection).row(for: .controlChange(track: 0, controller: 99)) == nil,
        cppID: factsID, message: "A051 unsupported controller is absent")
    let copyFixture = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 240)
            ]), trackBudget: document.trackBudget)
    copyFixture.writeLane(
        track: 0, lane: .controller(7), from: 0,
        through: TimeDefaults.noTick,
        points: [
            LaneWrite(tick: 24, value: 100),
            LaneWrite(tick: 72, value: 108),
        ])
    copyFixture.writeLane(
        track: 0, lane: .controller(10), from: 0,
        through: TimeDefaults.noTick, points: [LaneWrite(tick: 48, value: 64)])
    let baselineIndex = copyFixture.history.undoIndex
    let baselineCount = copyFixture.history.undoCount
    let copiedVolume = ClipboardSemantics.extractTimeRange(
        TimeRange(startTick: 24, endTick: 96),
        scope: TimeScope(lanes: [TimeScope.ScopedLane(track: 0, lane: .controller(7))]),
        from: copyFixture, unterminatedDuration: 24)
    report.expect(
        copiedVolume?.lanes == [
            ClipLane(
                track: 0, cc: 7,
                points: [
                    ClipLanePoint(relTick: 0, value: 100),
                    ClipLanePoint(relTick: 48, value: 108),
                ])
        ] && copiedVolume?.tracks.isEmpty == true && copiedVolume?.tempo.isEmpty == true,
        cppID: "clipboard/AutomationCoverageTest::endpointSemantics",
        message: "ordered CC7 copy contains only fixture CC7 events and no CC10 sibling or notes")
    let nativeBytes = copiedVolume.flatMap { ClipboardCodec.encode($0, ticksPerBeat: 24) }
    report.expect(
        nativeBytes
            == Data(
                #"{"format":1,"lanes":[{"cc":7,"points":[[0,100],[48,108]],"track":0}],"span":72,"tempo":[],"ticksPerBeat":24,"tracks":[],"wholeLane":false}"#
                    .utf8),
        cppID: "clipboard/AutomationCoverageTest::endpointSemantics",
        message: "ordered CC7 clipboard MIME bytes match the fixture without CC10 sibling bytes")
    report.expect(
        copyFixture.history.undoIndex == baselineIndex
            && copyFixture.history.undoCount == baselineCount,
        cppID: "clipboard/AutomationCoverageTest::endpointSemantics",
        message: "copying CC7 records no Undo entry")
    copyFixture.writeLane(
        track: 0, lane: .controller(7), from: 0,
        through: TimeDefaults.noTick, points: [])
    report.expect(
        copyFixture.history.undoIndex == baselineIndex + 1
            && copyFixture.history.undoCount == baselineCount + 1,
        cppID: "clipboard/AutomationCoverageTest::endpointSemantics",
        message: "clearing CC7 records exactly one Undo entry")
    let decoded = nativeBytes.flatMap(ClipboardCodec.decode)
    let pasteResult = decoded.flatMap {
        ClipboardSemantics.paste($0.clip, at: 24, selectedTrack: 0, into: copyFixture)
    }
    report.expect(
        pasteResult?.nextCursor == 96
            && copyFixture.lanePoints(track: 0, lane: .controller(7)).map {
                "\($0.tick):\($0.value)"
            } == ["24:100", "72:108"]
            && copyFixture.lanePoints(track: 0, lane: .controller(10)).map {
                "\($0.tick):\($0.value)"
            } == ["48:64"],
        cppID: "clipboard/AutomationCoverageTest::endpointSemantics",
        message: "decoded CC7 paste restores exactly two Volume events and preserves Pan")
    report.expect(
        copyFixture.history.undoIndex == baselineIndex + 2
            && copyFixture.history.undoCount == baselineCount + 2,
        cppID: "clipboard/AutomationCoverageTest::endpointSemantics",
        message: "scoped CC7 paste records exactly one Undo entry")
    let undone = copyFixture.history.undoDocument()
    report.expect(
        undone && copyFixture.history.undoIndex == baselineIndex + 1
            && copyFixture.history.undoCount == baselineCount + 2
            && copyFixture.lanePoints(track: 0, lane: .controller(7)).isEmpty
            && copyFixture.lanePoints(track: 0, lane: .controller(10)).map {
                "\($0.tick):\($0.value)"
            } == ["48:64"],
        cppID: "clipboard/AutomationCoverageTest::endpointSemantics",
        message: "one Undo restores empty CC7 with retained Paste Redo and untouched Pan")
}

@MainActor
private func clipboardLaneEndpointAndHitChecks(
    _ report: CheckReport, viewport: DocumentViewport, empty: AutomationRowStack,
    volume: AutomationParameter, pan: AutomationParameter
) {
    let session = viewport.session
    let endpointID = "clipboard/AutomationCoverageTest::endpointSemantics"
    let emptyID = "clipboard/AutomationCoverageTest::emptySelectionAndEndpointPayload"
    let tempoOnly = empty.laneSet(from: .tempo, through: .tempo)
    report.expect(
        tempoOnly.tempo, cppID: endpointID,
        message: "A061 Tempo-to-Tempo endpoints include Tempo")
    report.expect(
        tempoOnly.lanes.isEmpty, cppID: endpointID,
        message: "A062 Tempo-to-Tempo endpoints contain no CC lanes")
    let ccOnly = empty.laneSet(from: volume, through: volume)
    report.expect(
        !ccOnly.tempo, cppID: endpointID,
        message: "A063 CC7-to-CC7 endpoints exclude Tempo")
    report.expect(
        ccOnly.lanes == [volume], cppID: endpointID,
        message: "A064 CC7-to-CC7 endpoints contain only CC7")
    let mixed = empty.laneSet(from: .tempo, through: pan)
    report.expect(
        mixed.tempo, cppID: endpointID,
        message: "A065 Tempo-to-CC10 endpoints include Tempo")
    report.expect(
        mixed.lanes == [volume, pan], cppID: endpointID,
        message: "A066 Tempo-to-CC10 endpoints order CC7 before CC10")
    report.expect(
        mixed.tempo, cppID: emptyID,
        message: "A010 inactive time selection still resolves Tempo endpoint")
    report.expect(
        mixed.lanes == [volume, pan], cppID: emptyID,
        message: "A011 inactive time selection still resolves ordered CC endpoints")
    let reversed = empty.laneSet(from: pan, through: .tempo)
    report.expect(
        reversed.tempo, cppID: endpointID,
        message: "A067 reversed CC10-to-Tempo endpoints include Tempo")
    report.expect(
        reversed.lanes == [volume, pan], cppID: endpointID,
        message: "A068 reversed CC10-to-Tempo endpoints retain catalog order")
    let missing = empty.laneSet(
        from: .controlChange(track: 0, controller: 99),
        through: volume)
    report.expect(
        !missing.tempo, cppID: endpointID,
        message: "A069 unsupported first endpoint excludes Tempo")
    report.expect(
        missing.lanes.isEmpty, cppID: endpointID,
        message: "A070 unsupported first endpoint excludes CC lanes")

    let hitID = "clipboard/AutomationCoverageTest::hitTest"
    let selected = AutomationTimeSelection(
        range: TimeRange(startTick: 48, endTick: 96),
        scope: .lanes, lanes: [volume])
    let reversedSelection = AutomationTimeSelection(
        range: TimeRange(startTick: 96, endTick: 48), scope: .lanes, lanes: [volume])
    func hitFacts(
        zoom: Double, scroll: Double, dpr: Double,
        selection: AutomationTimeSelection
    ) -> (
        start: Bool, middle: Bool, before: Bool, end: Bool, pan: Bool, tempo: Bool
    ) {
        var camera = EditorCamera(
            ticksPerBeat: 24, lengthTicks: 384, viewportWidth: 480,
            rollHeight: 120, limits: GridCameraPolicy.limits(baseFontPx: 13))
        _ = camera.setTimeZoom(zoom)
        _ = camera.setHScroll(scroll)
        let projection = AutomationProjection(
            camera: camera,
            bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: dpr),
            geometry: AutomationPlotGeometry(baseFontPx: 13),
            snapPolicy: AutomationSnapPolicy(grid: viewport.grid, clockTicks: session.gridClockTicks),
            songEndTick: 384)
        let stack = AutomationRowStack.build(
            document: session.document, primaryTrack: 0,
            selection: selection, ready: true, songEndTick: 384)
        let start = projection.x(48)
        let end = projection.x(96)
        let middle = (start + end) / 2
        return (
            stack.hitTest(parameter: volume, x: start, projection: projection, selection: selection),
            stack.hitTest(parameter: volume, x: middle, projection: projection, selection: selection),
            stack.hitTest(parameter: volume, x: start - 1, projection: projection, selection: selection),
            stack.hitTest(parameter: volume, x: end, projection: projection, selection: selection),
            stack.hitTest(parameter: pan, x: middle, projection: projection, selection: selection),
            stack.hitTest(parameter: .tempo, x: middle, projection: projection, selection: selection)
        )
    }
    let reversedHits = hitFacts(zoom: 96, scroll: 48, dpr: 2, selection: reversedSelection)
    report.expect(
        !reversedHits.middle, cppID: hitID,
        message: "A053 inactive reversed selection refuses CC7 midpoint at zoom96 scroll48 DPR2")

    let unscrolled = hitFacts(zoom: 96, scroll: 0, dpr: 1, selection: selected)
    report.expect(
        unscrolled.start, cppID: hitID,
        message: "A054 CC7 hits displayed start at zoom96 scroll0 DPR1")
    report.expect(
        unscrolled.middle, cppID: hitID,
        message: "A055 CC7 hits displayed midpoint at zoom96 scroll0 DPR1")
    report.expect(
        !unscrolled.before, cppID: hitID,
        message: "A056 CC7 misses one pixel before start at zoom96 scroll0 DPR1")
    report.expect(
        !unscrolled.end, cppID: hitID,
        message: "A057 CC7 misses exclusive end at zoom96 scroll0 DPR1")
    report.expect(
        !unscrolled.pan, cppID: hitID,
        message: "A058 CC10 misses midpoint at zoom96 scroll0 DPR1")
    report.expect(
        !unscrolled.tempo, cppID: hitID,
        message: "A059 Tempo misses midpoint at zoom96 scroll0 DPR1")

    let scrolled = hitFacts(zoom: 64, scroll: 96, dpr: 1, selection: selected)
    report.expect(
        scrolled.start, cppID: hitID,
        message: "A054 CC7 hits displayed start at zoom64 scroll96 DPR1")
    report.expect(
        scrolled.middle, cppID: hitID,
        message: "A055 CC7 hits displayed midpoint at zoom64 scroll96 DPR1")
    report.expect(
        !scrolled.before, cppID: hitID,
        message: "A056 CC7 misses one pixel before start at zoom64 scroll96 DPR1")
    report.expect(
        !scrolled.end, cppID: hitID,
        message: "A057 CC7 misses exclusive end at zoom64 scroll96 DPR1")
    report.expect(
        !scrolled.pan, cppID: hitID,
        message: "A058 CC10 misses midpoint at zoom64 scroll96 DPR1")
    report.expect(
        !scrolled.tempo, cppID: hitID,
        message: "A059 Tempo misses midpoint at zoom64 scroll96 DPR1")

    let highDPR = hitFacts(zoom: 144, scroll: 192, dpr: 2, selection: selected)
    report.expect(
        highDPR.start, cppID: hitID,
        message: "A054 CC7 hits displayed start at zoom144 scroll192 DPR2")
    report.expect(
        highDPR.middle, cppID: hitID,
        message: "A055 CC7 hits displayed midpoint at zoom144 scroll192 DPR2")
    report.expect(
        !highDPR.before, cppID: hitID,
        message: "A056 CC7 misses one pixel before start at zoom144 scroll192 DPR2")
    report.expect(
        !highDPR.end, cppID: hitID,
        message: "A057 CC7 misses exclusive end at zoom144 scroll192 DPR2")
    report.expect(
        !highDPR.pan, cppID: hitID,
        message: "A058 CC10 misses midpoint at zoom144 scroll192 DPR2")
    report.expect(
        !highDPR.tempo, cppID: hitID,
        message: "A059 Tempo misses midpoint at zoom144 scroll192 DPR2")
}

@MainActor
private func clipboardEmptyAndReplacementChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let coverage = "clipboard/SelectionCheckTest::coverageQueriesAndLaneScopeSanitization"
    let replacement = "clipboard/SelectionCheckTest::resetForSongSwapNotifiesExactState"
    let file = MidiFile(division: 24, chunks: [MidiChunk(events: [], endTick: 96)])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let previous = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName)
    previous.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 1, endTick: 2), scope: .tracks([0])))
    report.expect(
        document.engineTracks.usedTrackCount == 0
            && previous.timeSelection?.isActive == true
            && !previous.timeSelectionCoversTempo(),
        cppID: coverage,
        message: "A047 empty used-track document never grants global Tempo track coverage")
    let replacementDocument = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let next = DocumentSession(
        document: replacementDocument, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName)
    report.expect(
        previous.timeSelection?.isActive == true && next.timeSelection == nil,
        cppID: replacement,
        message: "A074 replacing a selected document installs an inactive new-session selection")
}
