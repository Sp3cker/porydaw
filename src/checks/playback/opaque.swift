import Foundation
import PorydawCore

internal func xcmdPairedStrayWrite(_ report: CheckReport) {
    let stray = [
        Xcmd.Event(index: 0, tick: 4, stream: 0, controller: 0x1D, value: 7),
    ]
    report.expect(Xcmd.rewrite(stray, removing: [], writing: [
        Xcmd.PointWrite(tick: 4, lane: 0xFB, value: 20, stream: 0, channel: 0),
    ]) == nil, cppID: "xcmdcheck/XcmdTest::writeInsideStrayRunSpanRejected",
    message: "write inside a stray payload run rejects")
}

private func xcmdPairWriteAfterOpaqueEpochLeavesItUntouched(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x03), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 9),
        xcmdPairEvent(2, 5, 0, Xcmd.selectorController, 0x08), xcmdPairEvent(3, 6, 0, Xcmd.payloadController, 34)]
    let writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 8, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 0)]
    let patch = Xcmd.rewrite(events, removing: [], writing: writes)
    report.expect(patch != nil && patch!.removeEvents.isEmpty && patch!.inserts.count == 2 &&
                 patch!.inserts[0].tick == 8 && patch!.inserts[1].tick == 8,
        cppID: "xcmdcheck/XcmdTest::writeAfterOpaqueEpochLeavesItUntouched",
        message: "write after an opaque epoch touched the opaque traffic")
}

private func xcmdPairWriteInsideOpaqueEpochRejected(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x03),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 9),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 10)]
    var writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 2, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 0)]
    report.expect(Xcmd.rewrite(events, removing: [], writing: writes) == nil,
        cppID: "xcmdcheck/XcmdTest::writeInsideOpaqueEpochRejected",
        message: "write inside an opaque epoch was not rejected")
    writes[0].tick = 1
    report.expect(Xcmd.rewrite(events, removing: [], writing: writes) == nil,
        cppID: "xcmdcheck/XcmdTest::writeInsideOpaqueEpochRejected",
        message: "write on an opaque epoch's first tick was not rejected")
}

private func xcmdPairWriteInsideStrayRunSpanRejected(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.payloadController, 99),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 98)]
    let writes: [Xcmd.PointWrite] = [Xcmd.PointWrite(tick: 1, lane: Xcmd.echoVolumeLane, value: 40, stream: 0, channel: 0)]
    report.expect(Xcmd.rewrite(events, removing: [], writing: writes) == nil,
        cppID: "xcmdcheck/XcmdTest::writeInsideStrayRunSpanRejected",
        message: "write inside a stray-run span was not rejected")
}

private func xcmdPairUnknownRemoveIdentitiesRejected(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x03), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 9),
        xcmdPairEvent(2, 3, 0, Xcmd.selectorController, 0x08), xcmdPairEvent(3, 4, 0, Xcmd.payloadController, 34)]
    let opaqueMember: [UInt64] = [1]
    report.expect(Xcmd.rewrite(events, removing: opaqueMember, writing: []) == nil,
        cppID: "xcmdcheck/XcmdTest::unknownRemoveIdentitiesRejected",
        message: "removing an opaque member was not rejected")
    let selectorByte: [UInt64] = [2]
    report.expect(Xcmd.rewrite(events, removing: selectorByte, writing: []) == nil,
        cppID: "xcmdcheck/XcmdTest::unknownRemoveIdentitiesRejected",
        message: "removing a known selector was not rejected")
    let staleIdentity: [UInt64] = [999]
    report.expect(Xcmd.rewrite(events, removing: staleIdentity, writing: []) == nil,
        cppID: "xcmdcheck/XcmdTest::unknownRemoveIdentitiesRejected",
        message: "removing a stale identity was not rejected")
}

internal func runXcmdOpaqueOriginalChecks(_ report: CheckReport) {
    xcmdPairWriteAfterOpaqueEpochLeavesItUntouched(report)
    xcmdPairWriteInsideOpaqueEpochRejected(report)
    xcmdPairWriteInsideStrayRunSpanRejected(report)
    xcmdPairUnknownRemoveIdentitiesRejected(report)
}
