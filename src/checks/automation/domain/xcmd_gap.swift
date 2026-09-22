import Foundation
@testable import PorydawApp
import PorydawCore

private let automationXcmdGapID =
    "automation-domain/AutomationDomainTest::xcmdPortableGaps"

@MainActor
func drawerAutomationXcmdPortableGaps(_ report: CheckReport) {
    let events: [Xcmd.Event] = [
        Xcmd.Event(index: 1, tick: 96, stream: 0,
                   controller: Xcmd.selectorController, value: 0x08),
        Xcmd.Event(index: 2, tick: 96, stream: 0,
                   controller: Xcmd.payloadController, value: 34),
        Xcmd.Event(index: 3, tick: 96, stream: 0,
                   controller: Xcmd.selectorController, value: 0x09),
        Xcmd.Event(index: 4, tick: 96, stream: 0,
                   controller: Xcmd.payloadController, value: 17),
    ]
    let projection = Xcmd.project(events)
    report.expectEqual(["251:96:34:2:0:0"],
                       projection.points.filter { $0.lane == Xcmd.echoVolumeLane }.map {
                           "\($0.lane):\($0.tick):\($0.value):\($0.index):\($0.stream):\($0.channel)"
                       },
                       cppID: automationXcmdGapID,
                       what: "A001 echo-volume selector/payload projects as one logical point")
    report.expectEqual(["252:96:17:4:0:0"],
                       projection.points.filter { $0.lane == Xcmd.echoLengthLane }.map {
                           "\($0.lane):\($0.tick):\($0.value):\($0.index):\($0.stream):\($0.channel)"
                       },
                       cppID: automationXcmdGapID,
                       what: "A002 echo-length selector/payload projects as one logical point")
    report.expectEqual([1, 2, 3, 4], projection.consumed,
                       cppID: automationXcmdGapID,
                       what: "A003 both controller-byte pairs are consumed atomically")

    let replacement = Xcmd.rewrite(events, removing: [2], writing: [
        Xcmd.PointWrite(tick: 192, lane: Xcmd.echoVolumeLane, value: 35,
                        stream: 0, channel: 0),
    ])
    report.expectEqual([1, 2], replacement?.removeEvents ?? [],
                       cppID: automationXcmdGapID,
                       what: "A004-A006 rewriting a known payload removes its selector pair")
    report.expectEqual(["192:30:8:1:0", "192:29:35:2:0"],
                       (replacement?.inserts ?? []).map {
                           "\($0.tick):\($0.controller):\($0.value):\($0.sourceIndex ?? 0):\($0.channel)"
                       },
                       cppID: automationXcmdGapID,
                       what: "A005-A006 moved echo volume expands to canonical bytes")

    let unknown: [Xcmd.Event] = [
        Xcmd.Event(index: 10, tick: 40, stream: 0,
                   controller: Xcmd.selectorController, value: 0x2A),
        Xcmd.Event(index: 11, tick: 41, stream: 0,
                   controller: Xcmd.payloadController, value: 99),
        Xcmd.Event(index: 12, tick: 42, stream: 0,
                   controller: Xcmd.payloadController, value: 100),
    ]
    let assessment = Xcmd.assess(unknown)
    report.expect(assessment.blocks.count == 1
        && assessment.blocks[0].kind == .unknownSelectorEpoch
        && assessment.blocks[0].payloadCount == 2,
                  cppID: automationXcmdGapID,
                  message: "A025 opaque selector epoch is classified as one protected block")
    report.expect(Xcmd.rewrite(unknown, removing: [11], writing: []) == nil,
                  cppID: automationXcmdGapID,
                  message: "A025 partial opaque rewrite is rejected byte-exact")
    report.expect(Xcmd.reconcile(unknown, removing: [11], moving: [], copying: []) == nil,
                  cppID: automationXcmdGapID,
                  message: "A028 partial opaque reconciliation is rejected")

    let opaqueDocument = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [
            .channel(tick: 0, status: 0xB0, data0: Xcmd.selectorController, data1: 0x01),
            .channel(tick: 1, status: 0xB0, data0: Xcmd.payloadController, data1: 1),
            .channel(tick: 2, status: 0xB0, data0: Xcmd.payloadController, data1: 2),
        ], endTick: 400),
    ]))
    let opaqueBefore = opaqueDocument.state
    opaqueDocument.writeLane(track: 0, lane: .controller(Xcmd.echoVolumeLane),
                             from: 1, through: 1,
                             points: [LaneWrite(tick: 1, value: 30)])
    report.expectEqual(opaqueBefore, opaqueDocument.state, cppID: automationXcmdGapID,
                       what: "A025 write inside an opaque epoch changes no document state")

    let malformed = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [
            .channel(tick: 4, status: 0xB0, data0: Xcmd.selectorController, data1: 0x01),
            .channel(tick: 5, status: 0xB0, data0: Xcmd.payloadController, data1: 1),
            .channel(tick: 6, status: 0xB0, data0: Xcmd.payloadController, data1: 2),
            .channel(tick: 8, status: 0xB0, data0: Xcmd.selectorController, data1: 0x03),
            .channel(tick: 9, status: 0xB0, data0: Xcmd.payloadController, data1: 99),
        ], endTick: 480),
    ]))
    let malformedBefore = malformed.state
    let malformedRevision = malformed.revision
    malformed.writeLane(track: 0, lane: .controller(Xcmd.echoVolumeLane),
                        from: 400, through: 400,
                        points: [LaneWrite(tick: 400, value: 30)])
    report.expect(malformed.state != malformedBefore
        && malformed.revision == malformedRevision + 1,
                  cppID: automationXcmdGapID,
                  message: "A026 write outside opaque epochs is exactly one document edit")
    let malformedTraffic = malformed.rawChunks[0].events.compactMap { event -> String? in
        guard case let .channel(status, controller, value) = event.payload,
              status >> 4 == 0xB else { return nil }
        return "\(event.tick):\(controller):\(value)"
    }
    report.expectEqual([
        "4:30:1", "5:29:1", "6:29:2", "8:30:3", "9:29:99",
        "400:30:8", "400:29:30",
    ], malformedTraffic, cppID: automationXcmdGapID,
                       what: "A027 opaque traffic is preserved before the canonical append")
    let rejectedBefore = malformed.state
    malformed.writeLane(track: 0, lane: .controller(Xcmd.echoVolumeLane),
                        from: 8, through: 8,
                        points: [LaneWrite(tick: 8, value: 30)])
    report.expectEqual(rejectedBefore, malformed.state, cppID: automationXcmdGapID,
                       what: "A028 write inside a malformed opaque epoch changes no document state")
    let opaqueMove = Xcmd.reconcile(
        unknown, removing: [],
        moving: [
            Xcmd.Relocation(index: 10, tick: 140, channel: 0),
            Xcmd.Relocation(index: 11, tick: 141, channel: 0),
            Xcmd.Relocation(index: 12, tick: 142, channel: 0),
        ], copying: [])
    report.expectEqual([10, 11, 12], opaqueMove?.removeEvents ?? [],
                       cppID: automationXcmdGapID,
                       what: "A026 whole opaque block relocation removes every original member")
    report.expectEqual(["140:30:42:10:0", "141:29:99:11:0", "142:29:100:12:0"],
                       (opaqueMove?.inserts ?? []).map {
                           "\($0.tick):\($0.controller):\($0.value):\($0.sourceIndex ?? 0):\($0.channel)"
                       },
                       cppID: automationXcmdGapID,
                       what: "A027 whole opaque block relocation preserves controller bytes")

    let expansion = SongDocument(file: MidiFile(chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 192),
    ]), trackBudget: 2)
    let rawBefore = expansion.rawChunks
    let before = expansion.revision
    let edit = RangeEdit(minimumEngineTrackCount: 2,
        addPoints: [RangeEdit.LaneInsertion(
            track: 1, lane: .controller(Xcmd.echoVolumeLane),
            points: [LaneWrite(tick: 96, value: 34)])])
    report.expect(expansion.applyRangeEdit(edit), cppID: automationXcmdGapID,
                  message: "A057 expansion edit is accepted")
    report.expectEqual(before + 1, expansion.revision, cppID: automationXcmdGapID,
                       what: "A057 expansion is one document edit")
    report.expectEqual(2, expansion.engineTracks.usedTrackCount,
                       cppID: automationXcmdGapID,
                       what: "A058 expansion creates the requested engine track")
    report.expectEqual(["96:34"],
                       expansion.lanePoints(track: 1,
                           lane: .controller(Xcmd.echoVolumeLane)).map { "\($0.tick):\($0.value)" },
                       cppID: automationXcmdGapID,
                       what: "A059 expanded track projects the XCMD point")
    let traffic = expansion.rawChunks[1].events.compactMap { event -> [UInt8]? in
        guard event.tick == 96,
              case let .channel(status, controller, value) = event.payload,
              status >> 4 == 0xB else { return nil }
        return [controller, value]
    }
    report.expectEqual([[Xcmd.selectorController, 0x08],
                        [Xcmd.payloadController, 34]], traffic,
                       cppID: automationXcmdGapID,
                       what: "A060 expanded track stores canonical selector/payload bytes")
    let rawAfter = expansion.rawChunks
    _ = expansion.history.undoDocument()
    report.expectEqual(rawBefore, expansion.rawChunks, cppID: automationXcmdGapID,
                       what: "A061 expansion undo restores exact raw traffic")
    _ = expansion.history.redoDocument()
    report.expectEqual(rawAfter, expansion.rawChunks, cppID: automationXcmdGapID,
                       what: "A062 expansion redo restores exact raw traffic")
}
