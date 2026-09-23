import Foundation
import PorydawApp
import PorydawCore
import PorydawProjectService

// Existing scenarios paired with xcmd.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationXcmdParity(_ report: CheckReport, suite: DocumentSession,
                        service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, echo: [(120, 100)])
    let echo = fixture.projection(fixture.echoLane)
    report.expectEqual(["120:100"], fixture.laneValues(echo.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: drawerAutomationProjectionID, what: "an XCMD lane projects through the same lane API")
    report.expectEqual(1, echo.eventCount, cppID: drawerAutomationProjectionID,
                       what: "an XCMD lane counts its written events")
    report.expectEqual("Echo volume (xIECV)", AutomationCatalog.title(fixture.echoLane),
                       cppID: drawerAutomationProjectionID, what: "an XCMD row keeps its descriptor title")
    let metadata = AutomationParameterMetadata(parameter: fixture.echoLane)
    report.expect(metadata.neutral == nil && metadata.defaultValue == nil, cppID: drawerAutomationProjectionID,
                  message: "an XCMD lane has neither a neutral nor an engine default")
    report.expect(echo.leadIn == nil, cppID: drawerAutomationProjectionID,
                  message: "an XCMD lane supplies no lead-in")
    report.expectEqual([AutomationScaleLabel.Role.maximum, .minimum],
                       echo.scaleLabels.map(\.role), cppID: drawerAutomationProjectionID,
                       what: "an XCMD lane labels its extremes with no neutral")
    let before = fixture.snapshot
    let edit = AutomationLaneReplacement.heldSpan(
        fixture.facts(fixture.echoLane).freeze(), begin: 120, end: 144,
        points: [AutomationLanePoint(tick: 120, value: 5)])
    report.expect(AutomationCommit.apply(edit, in: fixture.document), cppID: drawerAutomationProjectionID,
                  message: "an XCMD lane commits through the same lane write")
    report.expectEqual(["120:5", "144:100"], fixture.values(fixture.echoLane), cppID: drawerAutomationProjectionID,
                       what: "the XCMD lane writes its projected replacement")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: drawerAutomationProjectionID,
                       what: "one XCMD replacement is one revision")
}

@MainActor
func coreTimeXcmdTimeTraffic(_ report: CheckReport) {
    let document = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(status: 0xC0, data0: 0),
        .channel(tick: 10, status: 0xB0, data0: Xcmd.selectorController, data1: 0x08),
        .channel(tick: 12, status: 0xB0, data0: Xcmd.payloadController, data1: 40),
        .channel(tick: 30, status: 0xB0, data0: Xcmd.selectorController, data1: 0x2A),
        .channel(tick: 31, status: 0xB0, data0: Xcmd.payloadController, data1: 99),
        .channel(tick: 40, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 44, status: 0x90, data0: 60),
    ], endTick: 60)]))
    let scope = TimeScope(lanes: [TimeScope.ScopedLane(
        track: 0, lane: .controller(Xcmd.echoVolumeLane))])
    report.expect(document.duplicateTime(TimeRange(startTick: 10, endTick: 20), scope: scope),
                  cppID: "automation-domain/AutomationDomainTest::xcmdRangeMoves",
                  message: "XCMD lane duplicate reconciles through epoch planner")
    report.expectEqual(["12:40", "22:40"], document.lanePoints(
        track: 0, lane: .controller(Xcmd.echoVolumeLane)).map(coreTimePointShape),
        cppID: "automation-domain/AutomationDomainTest::xcmdCanonicalEdits",
        what: "known copied points rebuild canonically")
    let assessment = Xcmd.assess(coreTimeXcmdTraffic(document.rawChunks[0]))
    report.expect(assessment.blocks.contains { $0.kind == .unknownSelectorEpoch && $0.payloadCount == 1 },
                  cppID: "automation-domain/AutomationDomainTest::xcmdOccurrencesAndOpaqueProtection",
                  message: "unselected opaque epoch remains byte-exact")
    let beforeCut = coreTimeBytes(document)
    _ = document.removeTime(TimeRange(startTick: 20, endTick: 25), scope: scope)
    report.expect(!document.lanePoints(track: 0, lane: .controller(Xcmd.echoVolumeLane))
        .contains { $0.tick == 22 },
        cppID: "automation-domain/AutomationDomainTest::xcmdRangeRemoveOnly",
        message: "range cut removes copied logical point")
    report.expect(document.notes(in: 0).count == 1,
                  cppID: "automation-domain/AutomationDomainTest::xcmdSweepPreservesNotes",
                  message: "lane-only XCMD sweep preserves notes")
    _ = document.history.undoDocument()
    report.expectEqual(beforeCut, coreTimeBytes(document),
                       cppID: "automation-domain/AutomationDomainTest::xcmdTimeRangeCuts",
                       what: "XCMD cut is one reversible history entry")

    let expansion = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 20),
    ]), trackBudget: 2)
    let xcmdEdit = RangeEdit(minimumEngineTrackCount: 2,
        addPoints: [RangeEdit.LaneInsertion(track: 1,
            lane: .controller(Xcmd.echoLengthLane),
            points: [LaneWrite(tick: 5, value: 64)])])
    report.expect(expansion.applyRangeEdit(xcmdEdit) &&
        expansion.lanePoints(track: 1, lane: .controller(Xcmd.echoLengthLane)).count == 1,
        cppID: "automation-domain/AutomationDomainTest::xcmdExpansionPaste",
        message: "track expansion builds descriptor traffic through the canonical planner")
}

@MainActor
private struct XcmdDomainFixture {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 9216),
    ]))

    struct Snapshot {
        let bytes: [UInt8]
        let revision: UInt64
        let identity: DocumentIdentity
    }

    var snapshot: Snapshot {
        Snapshot(bytes: try! document.captureSave().bytes, revision: document.revision,
                 identity: document.history.currentIdentity)
    }

    func oneEdit(_ before: Snapshot) -> Bool {
        document.revision == before.revision + 1 && document.history.currentIdentity != before.identity
    }

    func setLane(_ controller: UInt8, _ points: [(Tick, Int)]) {
        document.writeLane(track: 0, lane: .controller(controller), from: 0,
                           through: TimeDefaults.noTick,
                           points: points.map { LaneWrite(tick: $0.0, value: $0.1) })
    }

    func insertCc(_ tick: Tick, _ controller: UInt8, _ value: UInt8) {
        document.insertRawEvent(chunk: 0, event: .channel(tick: tick, status: 0xB0,
                                                         data0: controller, data1: value))
    }

    func clearXcmd() {
        setLane(Xcmd.echoVolumeLane, [])
        setLane(Xcmd.echoLengthLane, [])
    }

    func seedBaseline() {
        setLane(10, [(0, 80), (384, 110)])
        setLane(7, [(0, 64), (288, 48)])
    }

    func points(_ controller: UInt8) -> [String] {
        document.lanePoints(track: 0, lane: .controller(controller))
            .map { "\($0.tick):\($0.value)" }
    }

    func xcmdBytes(at tick: Tick) -> [(UInt8, UInt8)] {
        document.rawChunks[0].events.compactMap { event in
            guard event.tick == tick,
                  case let .channel(status, controller, value) = event.payload,
                  status >> 4 == 0xB,
                  controller == Xcmd.selectorController ||
                    controller == Xcmd.payloadController ||
                    controller == Xcmd.alternatePayloadController else { return nil }
            return (controller, value)
        }
    }

    func xcmdBytes() -> [(UInt8, UInt8)] {
        document.rawChunks[0].events.compactMap { event in
            guard case let .channel(status, controller, value) = event.payload,
                  status >> 4 == 0xB,
                  controller == Xcmd.selectorController ||
                    controller == Xcmd.payloadController ||
                    controller == Xcmd.alternatePayloadController else { return nil }
            return (controller, value)
        }
    }

    func ccChain() -> [(Tick, UInt8, UInt8)] {
        document.rawChunks[0].events.compactMap { event in
            guard case let .channel(status, controller, value) = event.payload,
                  status >> 4 == 0xB,
                  controller == 7 || controller == 10 ||
                    controller == Xcmd.selectorController ||
                    controller == Xcmd.payloadController ||
                    controller == Xcmd.alternatePayloadController else { return nil }
            return (event.tick, controller, value)
        }
    }

    func notes() -> [(Tick, UInt8, UInt8, UInt8)] {
        document.notes(in: 0).flatMap { note -> [(Tick, UInt8, UInt8, UInt8)] in
            let events = document.rawChunks[note.chunk].events
            return [note.onIndex, note.endIndex].compactMap { index in
                guard let index,
                      case let .channel(status, key, velocity) = events[index].payload else { return nil }
                return (events[index].tick, status & 0xF0, key, velocity)
            }
        }
    }

    func undoToRoot() -> Bool {
        var undid = false
        while document.history.undoDocument() { undid = true }
        return undid && !document.history.canUndo
    }
}

@MainActor
func drawerAutomationXcmdLaneEdits(_ report: CheckReport) {
    let canonicalID = "automation-domain/AutomationDomainTest::xcmdCanonicalEdits"
    let canonical = XcmdDomainFixture()
    let before = canonical.snapshot
    canonical.setLane(Xcmd.echoVolumeLane, [(96, 34)])
    canonical.setLane(Xcmd.echoLengthLane, [(96, 17)])
    report.expectEqual(["96:34"], canonical.points(Xcmd.echoVolumeLane), cppID: canonicalID,
                       what: "volume lane projects the canonical point")
    report.expectEqual(["96:17"], canonical.points(Xcmd.echoLengthLane), cppID: canonicalID,
                       what: "length lane projects the canonical point")
    let bytesAt96: [(UInt8, UInt8)] = [
        (Xcmd.selectorController, 0x08), (Xcmd.payloadController, 34),
        (Xcmd.selectorController, 0x09), (Xcmd.payloadController, 17),
    ]
    report.expect(canonical.xcmdBytes(at: 96).elementsEqual(bytesAt96, by: { $0 == $1 }),
                  cppID: canonicalID, message: "canonical lanes encode ordered bytes at tick 96")

    let moveBefore = canonical.snapshot
    if let volume = canonical.document.lanePoints(track: 0, lane: .controller(Xcmd.echoVolumeLane)).first {
        canonical.document.moveLanePoints(track: 0, lane: .controller(Xcmd.echoVolumeLane),
                                          moves: [LanePointMove(point: volume, tick: 192, value: 35)])
        report.expect(canonical.oneEdit(moveBefore), cppID: canonicalID,
                      message: "moving the volume point commits one edit")
        report.expectEqual(["192:35"], canonical.points(Xcmd.echoVolumeLane), cppID: canonicalID,
                           what: "moved volume point projects at tick 192")
        let bytesAt192: [(UInt8, UInt8)] = [
            (Xcmd.selectorController, 0x08), (Xcmd.payloadController, 35),
        ]
        report.expect(canonical.xcmdBytes(at: 192).elementsEqual(bytesAt192, by: { $0 == $1 }),
                      cppID: canonicalID, message: "moved point encodes ordered bytes at tick 192")
    } else {
        report.fail(canonicalID, "canonical volume lane has no point identity to move")
    }
    report.expect(canonical.undoToRoot() && canonical.snapshot.bytes == before.bytes,
                  cppID: canonicalID, message: "undoing every edit restores pre-edit MIDI bytes")
    report.expectEqual([String](), canonical.points(Xcmd.echoVolumeLane), cppID: canonicalID,
                       what: "undo leaves volume lane empty")
    report.expectEqual([String](), canonical.points(Xcmd.echoLengthLane), cppID: canonicalID,
                       what: "undo leaves length lane empty")

    let sweepID = "automation-domain/AutomationDomainTest::xcmdSweepPreservesNotes"
    let sweep = XcmdDomainFixture()
    let beforeSweep = sweep.snapshot
    sweep.document.insertRawEvent(chunk: 0, event: .channel(tick: 8772, status: 0x90,
                                                            data0: 60, data1: 100))
    sweep.document.insertRawEvent(chunk: 0, event: .channel(tick: 8808, status: 0x80,
                                                            data0: 60, data1: 0))
    sweep.setLane(Xcmd.echoVolumeLane, [(8844, 48)])
    let notesBeforeSweep = sweep.notes()
    let expectedNotes: [(Tick, UInt8, UInt8, UInt8)] = [(8772, 0x90, 60, 100), (8808, 0x80, 60, 0)]
    report.expect(notesBeforeSweep.elementsEqual(expectedNotes, by: { $0 == $1 }),
                  cppID: sweepID, message: "sweep fixture contains the original note-on and note-off")
    let parameter = AutomationParameter.controlChange(track: 0, controller: Xcmd.echoVolumeLane)
    let lane = AutomationLaneSnapshot(parameter: parameter, in: sweep.document, songEndTick: 9216)
    let freeze = AutomationLaneFreeze(
        parameter: parameter, revision: lane.revision, metadata: lane.metadata, songEndTick: 9216,
        original: lane.displaySeries.map { AutomationLanePoint(tick: $0.tick, value: $0.value) })
    let sweepEdit = AutomationLaneReplacement.heldSpan(
        freeze, begin: 8736, end: 8844,
        points: [AutomationLanePoint(tick: 8736, value: 32),
                 AutomationLanePoint(tick: 8844, value: 48)])
    _ = AutomationCommit.apply(sweepEdit, in: sweep.document)
    report.expect(sweep.notes().elementsEqual(notesBeforeSweep, by: { $0 == $1 }),
                  cppID: sweepID, message: "lane sweep preserves the original note events")
    report.expectEqual(["8736:32", "8844:48"], sweep.points(Xcmd.echoVolumeLane), cppID: sweepID,
                       what: "sweep replaces the lane span with both projected points")
    report.expect(sweep.undoToRoot() && sweep.snapshot.bytes == beforeSweep.bytes,
                  cppID: sweepID, message: "undoing sweep and fixture edits restores original MIDI bytes")
}
