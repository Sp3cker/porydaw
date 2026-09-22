import Foundation
import PorydawCore

internal func xcmdPairedRewrite(_ report: CheckReport) {
    let events = [
        Xcmd.Event(index: 0, tick: 1, stream: 0, controller: 0x1E, value: 0x08),
        Xcmd.Event(index: 1, tick: 2, stream: 0, controller: 0x1D, value: 34),
        Xcmd.Event(index: 2, tick: 3, stream: 0, controller: 0x1D, value: 35),
    ]
    let patch = Xcmd.rewrite(events, removing: [1], writing: [])
    report.expectEqual([0, 1, 2], patch?.removeEvents,
                       cppID: "xcmdcheck/XcmdTest::deleteSharedPointRebuildsSurvivorAsPair",
                       what: "touched epoch is wholly removed")
    report.expectEqual([UInt8(0x08), 35], patch?.inserts.map(\.value),
                       cppID: "xcmdcheck/XcmdTest::deleteSharedPointRebuildsSurvivorAsPair",
                       what: "survivor is a canonical pair")
    let duplicate = Xcmd.rewrite([], removing: [], writing: [
        Xcmd.PointWrite(tick: 5, lane: 0xFB, value: 40, stream: 0, channel: 4),
        Xcmd.PointWrite(tick: 5, lane: 0xFB, value: 55, stream: 0, channel: 4),
    ])
    report.expectEqual(UInt8(55), duplicate?.inserts.last?.value,
                       cppID: "xcmdcheck/XcmdTest::unknownLaneRejectedAndDuplicatesCollapse",
                       what: "later duplicate write wins")
    report.expect(Xcmd.rewrite([], removing: [], writing: [
        Xcmd.PointWrite(tick: 5, lane: 0x77, value: 1, stream: 0, channel: 0),
    ]) == nil, cppID: "xcmdcheck/XcmdTest::unknownLaneRejectedAndDuplicatesCollapse",
    message: "unknown lane rejects the rewrite")
    let dangling = [
        Xcmd.Event(index: 0, tick: 4, stream: 0, controller: 0x1E, value: 0x08),
    ]
    report.expect(Xcmd.rewrite(dangling, removing: [], writing: [
        Xcmd.PointWrite(tick: 4, lane: 0xFB, value: 20, stream: 0, channel: 0),
    ]) == nil, cppID: "xcmdcheck/XcmdTest::danglingKnownSelectorProjectsOpaque",
    message: "write inside a dangling selector rejects")
    xcmdPairedStrayWrite(report)
    let inSpan = Xcmd.rewrite(events, removing: [], writing: [
        Xcmd.PointWrite(tick: 2, lane: 0xFB, value: 50, stream: 0, channel: 0),
    ])
    report.expectEqual([UInt8(0x08), 50, 0x08, 35], inSpan?.inserts.map(\.value),
                       cppID: "xcmdcheck/XcmdTest::inSpanWriteRebuildsAffectedEpoch",
                       what: "in-span write rebuilds canonical pairs")
}

private func xcmdPairAddOnEmptyTrackEmitsCanonicalPair(_ report: CheckReport) {
    let writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 5, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 7)]
    let patch = Xcmd.rewrite([], removing: [], writing: writes)
    report.expect(patch != nil && patch!.removeEvents.isEmpty && patch!.inserts.count == 2 &&
                 patch!.inserts[0].tick == 5 &&
                 patch!.inserts[0].controller == Xcmd.selectorController &&
                 patch!.inserts[0].value == 0x08 && patch!.inserts[0].channel == 7 &&
                 patch!.inserts[1].controller == Xcmd.payloadController &&
                 patch!.inserts[1].value == 40,
        cppID: "xcmdcheck/XcmdTest::addOnEmptyTrackEmitsCanonicalPair",
        message: "add did not emit canonical selector+payload")
}

private func xcmdPairAddUnderActiveStateEmitsFullPair(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34)]
    let writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 5, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 7)]
    let patch = Xcmd.rewrite(events, removing: [], writing: writes)
    report.expect(patch != nil && patch!.inserts.count == 2 &&
                 patch!.inserts[0].controller == Xcmd.selectorController &&
                 patch!.inserts[0].value == 0x08 &&
                 patch!.inserts[1].controller == Xcmd.payloadController &&
                 patch!.removeEvents.isEmpty,
        cppID: "xcmdcheck/XcmdTest::addUnderActiveStateEmitsFullPair",
        message: "write did not emit a self-contained pair under active state")
}

private func xcmdPairReplaceRebuildsEpochWithExplicitPair(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34)]
    let writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 2, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 7)]
    let patch = Xcmd.rewrite(events, removing: [], writing: writes)
    report.expect(patch != nil && patch!.removeEvents == [0, 1] &&
                 patch!.inserts.count == 2 && patch!.inserts[0].value == 0x08 &&
                 patch!.inserts[1].value == 40,
        cppID: "xcmdcheck/XcmdTest::replaceRebuildsEpochWithExplicitPair",
        message: "replace did not rebuild the epoch with an explicit pair")
}

private func xcmdPairDeleteSharedPointRebuildsSurvivorAsPair(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 35)]
    let projection = Xcmd.project(events)
    let removeIdentities: [UInt64] = [projection.points[0].index]
    let patch = Xcmd.rewrite(events, removing: removeIdentities, writing: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1, 2] &&
                 patch!.inserts.count == 2 && patch!.inserts[0].tick == 3 &&
                 patch!.inserts[0].value == 0x08 && patch!.inserts[1].value == 35,
        cppID: "xcmdcheck/XcmdTest::deleteSharedPointRebuildsSurvivorAsPair",
        message: "deleting one shared point did not rebuild the survivor as a pair")
}

private func xcmdPairDeleteLastPointRemovesDeadEpoch(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34)]
    let projection = Xcmd.project(events)
    let removeIdentities: [UInt64] = [projection.points[0].index]
    let patch = Xcmd.rewrite(events, removing: removeIdentities, writing: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1] &&
                 patch!.inserts.isEmpty,
        cppID: "xcmdcheck/XcmdTest::deleteLastPointRemovesDeadEpoch",
        message: "deleting the last point left the dead epoch behind")
}

private func xcmdPairInSpanWriteRebuildsAffectedEpoch(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
        xcmdPairEvent(2, 10, 0, Xcmd.selectorController, 0x09), xcmdPairEvent(3, 13, 0, Xcmd.payloadController, 17)]
    let writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 12, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 0)]
    let patch = Xcmd.rewrite(events, removing: [], writing: writes)

    report.expect(patch != nil && patch!.removeEvents == [2, 3] &&
                 patch!.inserts.count == 4 && patch!.inserts[0].tick == 12 &&
                 patch!.inserts[0].value == 0x08 && patch!.inserts[1].value == 40 &&
                 patch!.inserts[2].tick == 13 && patch!.inserts[2].value == 0x09 &&
                 patch!.inserts[3].value == 17,
        cppID: "xcmdcheck/XcmdTest::inSpanWriteRebuildsAffectedEpoch",
        message: "in-span write did not rebuild the epoch canonically")
}

private func xcmdPairLaneWriteClampsToDescriptorMaximum(_ report: CheckReport) {
    let writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 5, lane: Xcmd.echoLengthLane, value: 200, stream: 0, channel: 0)]
    let patch = Xcmd.rewrite([], removing: [], writing: writes)
    report.expect(patch != nil && patch!.inserts[1].value == 127,
        cppID: "xcmdcheck/XcmdTest::laneWriteClampsToDescriptorMaximum",
        message: "lane write did not clamp to the descriptor maximum")
}

private func xcmdPairUnknownLaneRejectedAndDuplicatesCollapse(_ report: CheckReport) {
    let unknownLane: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 5, lane: 0x77, value: 40, stream: 0, channel: 0)]
    report.expect(Xcmd.rewrite([], removing: [], writing: unknownLane) == nil,
        cppID: "xcmdcheck/XcmdTest::unknownLaneRejectedAndDuplicatesCollapse",
        message: "write on an unknown lane was not rejected")
    let duplicates: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 5, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 0),
                                                      Xcmd.PointWrite(tick: 5, lane: Xcmd.echoVolumeLane, value: 55, stream: 0, channel: 0)]
    let patch = Xcmd.rewrite([], removing: [], writing: duplicates)
    report.expect(patch != nil && patch!.inserts.count == 2 && patch!.inserts[1].value == 55,
        cppID: "xcmdcheck/XcmdTest::unknownLaneRejectedAndDuplicatesCollapse",
        message: "duplicate same-slot write did not collapse to the later value")
}

private func xcmdPairSameTickPairsRetainActiveWriteOrder(_ report: CheckReport) {
    let writes: [Xcmd.PointWrite] = [
        Xcmd.PointWrite(tick: 5, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 4),
        Xcmd.PointWrite(tick: 5, lane: Xcmd.echoLengthLane, value: 55, stream: 0, channel: 5),
    ]
    let patch = Xcmd.rewrite([], removing: [], writing: writes)
    report.expect(patch != nil && patch!.inserts.count == 4 && patch!.inserts[0].value == 0x08 &&
                 patch!.inserts[0].channel == 4 && patch!.inserts[1].value == 40 &&
                 patch!.inserts[1].channel == 4 && patch!.inserts[2].value == 0x09 &&
                 patch!.inserts[2].channel == 5 && patch!.inserts[3].value == 55 &&
                 patch!.inserts[3].channel == 5,
        cppID: "xcmdcheck/XcmdTest::sameTickPairsRetainActiveWriteOrder",
        message: "same-tick writes did not retain canonical pair order")
}

internal func runXcmdRewritesOriginalChecks(_ report: CheckReport) {
    xcmdPairAddOnEmptyTrackEmitsCanonicalPair(report)
    xcmdPairAddUnderActiveStateEmitsFullPair(report)
    xcmdPairReplaceRebuildsEpochWithExplicitPair(report)
    xcmdPairDeleteSharedPointRebuildsSurvivorAsPair(report)
    xcmdPairDeleteLastPointRemovesDeadEpoch(report)
    xcmdPairInSpanWriteRebuildsAffectedEpoch(report)
    xcmdPairLaneWriteClampsToDescriptorMaximum(report)
    xcmdPairUnknownLaneRejectedAndDuplicatesCollapse(report)
    xcmdPairSameTickPairsRetainActiveWriteOrder(report)
}
