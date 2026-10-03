import Foundation
import PorydawCore

internal func xcmdPairedProjection(_ report: CheckReport) {
    let events = [
        Xcmd.Event(index: 9, tick: 1, stream: 0, controller: 0x1E, value: 0x08),
        Xcmd.Event(index: 2, tick: 2, stream: 0, controller: 0x1D, value: 34),
        Xcmd.Event(index: 7, tick: 3, stream: 0, controller: 0x1F, value: 35),
    ]
    let projection = Xcmd.project(events)
    report.expectEqual(expected: [34, 35], actual: projection.points.map { Int($0.value) },
                       cppID: "xcmdcheck/XcmdTest::sharedSelectorServesTwoCompletions",
                       what: "one selector serves every payload in its epoch")
    report.expectEqual(expected: [2, 7, 9], actual: projection.consumed,
                       cppID: "xcmdcheck/XcmdTest::consumedIsSortedDedupIndexSet",
                       what: "consumed identities are sorted")
    let opaque = Xcmd.project([
        Xcmd.Event(index: 0, tick: 0, stream: 0, controller: 0x1E, value: 0x2A),
        Xcmd.Event(index: 1, tick: 1, stream: 0, controller: 0x1D, value: 99),
    ])
    report.expect(opaque.points.isEmpty && opaque.consumed == [0, 1],
                  cppID: "xcmdcheck/XcmdTest::unknownSelectorEpochStaysOpaque",
                  message: "unknown epoch is consumed but not projected")
}

private func xcmdPairSharedSelectorServesTwoCompletions(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 35)]
    let result = Xcmd.project(events)
    report.expect(result.points.count == 2 && result.points[0].lane == Xcmd.echoVolumeLane &&
                 result.points[0].value == 34 && result.points[0].tick == 2 &&
                 result.points[0].index == 1 && result.points[1].value == 35 &&
                 result.points[1].tick == 3 && result.points[1].index == 2 &&
                 result.consumed == [0, 1, 2],
        cppID: "xcmdcheck/XcmdTest::sharedSelectorServesTwoCompletions",
        message: "shared-selector projection did not expose both points and consumed indices")
}

private func xcmdPairUnknownSelectorEpochStaysOpaque(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x01),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 1),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 2)]
    let result = Xcmd.project(events)
    report.expect(result.points.isEmpty && result.consumed == [0, 1, 2],
        cppID: "xcmdcheck/XcmdTest::unknownSelectorEpochStaysOpaque",
        message: "unknown-selector epoch did not stay opaque with consumed bytes")
}

private func xcmdPairDanglingKnownSelectorProjectsOpaque(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08)]
    let result = Xcmd.project(events)
    report.expect(result.points.isEmpty && result.consumed == [0],
        cppID: "xcmdcheck/XcmdTest::danglingKnownSelectorProjectsOpaque",
        message: "payload-less selector epoch did not project as opaque")
}

private func xcmdPairLeadingStrayPayloadsStayOpaque(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.payloadController, 99),
                                   xcmdPairEvent(1, 2, 0, Xcmd.selectorController, 0x09),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 17)]
    let result = Xcmd.project(events)
    report.expect(result.points.count == 1 && result.points[0].value == 17 &&
                 result.consumed == [0, 1, 2],
        cppID: "xcmdcheck/XcmdTest::leadingStrayPayloadsStayOpaque",
        message: "leading stray payload run was not kept opaque")
}

private func xcmdPairStreamsProjectIndependently(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
        xcmdPairEvent(2, 1, 1, Xcmd.selectorController, 0x09), xcmdPairEvent(3, 2, 1, Xcmd.payloadController, 17)]
    let result = Xcmd.project(events)
    report.expect(result.points.count == 2 && result.points[0].stream == 0 &&
                 result.points[0].lane == Xcmd.echoVolumeLane && result.points[1].stream == 1 &&
                 result.points[1].lane == Xcmd.echoLengthLane && result.points[1].value == 17,
        cppID: "xcmdcheck/XcmdTest::streamsProjectIndependently",
        message: "streams did not project independently")
}

private func xcmdPairConsumedIsSortedDedupIndexSet(_ report: CheckReport) {
    let events = [xcmdPairEvent(9, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(2, 2, 0, Xcmd.payloadController, 34),
                                   xcmdPairEvent(7, 3, 0, Xcmd.alternatePayloadController, 35)]
    let result = Xcmd.project(events)
    report.expect(result.consumed == [2, 7, 9],
        cppID: "xcmdcheck/XcmdTest::consumedIsSortedDedupIndexSet",
        message: "protocol consumption was not a sorted raw-index set")
}

internal func runXcmdProjectionOriginalChecks(_ report: CheckReport) {
    xcmdPairSharedSelectorServesTwoCompletions(report)
    xcmdPairUnknownSelectorEpochStaysOpaque(report)
    xcmdPairDanglingKnownSelectorProjectsOpaque(report)
    xcmdPairLeadingStrayPayloadsStayOpaque(report)
    xcmdPairStreamsProjectIndependently(report)
    xcmdPairConsumedIsSortedDedupIndexSet(report)
}
