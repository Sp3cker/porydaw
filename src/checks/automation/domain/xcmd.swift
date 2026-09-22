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
