import Foundation
import PorydawCore

private func isCanonicalPair(_ selectorEvent: Xcmd.Emission, _ payloadEvent: Xcmd.Emission,
                             _ selector: UInt8, _ value: UInt8) -> Bool {
    selectorEvent.controller == Xcmd.selectorController &&
        selectorEvent.value == selector && payloadEvent.controller == Xcmd.payloadController &&
        payloadEvent.value == value && selectorEvent.tick == payloadEvent.tick &&
        selectorEvent.channel == payloadEvent.channel && selectorEvent.sourceIndex == nil &&
        payloadEvent.sourceIndex == nil
}

@MainActor
internal func xcmdPairedExport(_ report: CheckReport) {
    let exported = Xcmd.canonicalizeForExport([
        Xcmd.Event(index: 0, tick: 1, stream: 0, controller: 0x1E, value: 0x08),
        Xcmd.Event(index: 1, tick: 2, stream: 0, controller: 0x1D, value: 10),
        Xcmd.Event(index: 2, tick: 3, stream: 0, controller: 0x1D, value: 20),
    ])
    report.expectEqual(expected: 4, actual: exported.inserts.count,
                       cppID: "xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
                       what: "export expands shared selector on detached values")
    let document = SongDocument(file: MidiFile(chunks: [MidiChunk(events: [
        .channel(tick: 1, status: 0xB0, data0: 0x1E, data1: 0x08),
        .channel(tick: 2, status: 0xB0, data0: 0x1D, data1: 10),
        .channel(tick: 3, status: 0xB0, data0: 0x1D, data1: 20),
    ])]))
    guard let snapshot = try? document.captureSave(),
          let decoded = try? MidiFile.decode(snapshot.bytes) else {
        report.fail("xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
                    "export snapshot did not decode")
        return
    }
    report.expectEqual(expected: 3, actual: document.rawChunks[0].events.count,
                       cppID: "xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
                       what: "export canonicalization does not mutate the document")
    report.expectEqual(expected: 4, actual: decoded.chunks[0].events.filter {
        if case let .channel(status, _, _) = $0.payload { return status >> 4 == 0xB }
        return false
    }.count, cppID: "xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
    what: "saved bytes contain canonical selector-payload pairs")
}

private func xcmdPairSharedSelectorRebuiltAsSameTickPairs(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 4, 0, Xcmd.payloadController, 34, 3),
                                   xcmdPairEvent(2, 9, 0, Xcmd.alternatePayloadController, 35, 3)]
    let patch = Xcmd.canonicalizeForExport(events)
    report.expect(patch.removeEvents == [0, 1, 2] && patch.inserts.count == 4 &&
                 isCanonicalPair(patch.inserts[0], patch.inserts[1], 0x08, 34) &&
                 patch.inserts[0].tick == 4 && patch.inserts[0].channel == 3 &&
                 isCanonicalPair(patch.inserts[2], patch.inserts[3], 0x08, 35) &&
                 patch.inserts[2].tick == 9,
        cppID: "xcmdcheck/XcmdTest::sharedSelectorRebuiltAsSameTickPairs",
        message: "shared selector was not rebuilt as same-tick explicit pairs")
}

private func xcmdPairDanglingKnownSelectorRemoved(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 7, 0, Xcmd.selectorController, 0x09)]
    let patch = Xcmd.canonicalizeForExport(events)
    report.expect(patch.removeEvents == [0] && patch.inserts.isEmpty,
        cppID: "xcmdcheck/XcmdTest::danglingKnownSelectorRemoved",
        message: "payload-less known selector was not removed")
}

private func xcmdPairUnknownEpochAndStrayRunPreservedVerbatim(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.payloadController, 99),
                                   xcmdPairEvent(1, 2, 0, Xcmd.selectorController, 0x03),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 9),
                                   xcmdPairEvent(3, 4, 0, Xcmd.alternatePayloadController, 10)]
    let patch = Xcmd.canonicalizeForExport(events)
    report.expect(patch.removeEvents.isEmpty && patch.inserts.isEmpty,
        cppID: "xcmdcheck/XcmdTest::unknownEpochAndStrayRunPreservedVerbatim",
        message: "unknown epoch or stray payload run was not preserved verbatim")
}

private func xcmdPairExplicitPointsRebuiltInTickOrder(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 20, 0, Xcmd.selectorController, 0x09),
                                   xcmdPairEvent(1, 20, 0, Xcmd.payloadController, 17, 2),
                                   xcmdPairEvent(2, 4, 1, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(3, 4, 1, Xcmd.alternatePayloadController, 65, 6)]
    let patch = Xcmd.canonicalizeForExport(events)
    report.expect(patch.removeEvents == [0, 1, 2, 3] &&
                 patch.inserts.count == 4 &&
                 isCanonicalPair(patch.inserts[0], patch.inserts[1], 0x08, 65) &&
                 patch.inserts[0].tick == 4 && patch.inserts[0].channel == 6 &&
                 isCanonicalPair(patch.inserts[2], patch.inserts[3], 0x09, 17) &&
                 patch.inserts[2].tick == 20 && patch.inserts[2].channel == 2,
        cppID: "xcmdcheck/XcmdTest::explicitPointsRebuiltInTickOrder",
        message: "explicit points were not rebuilt semantically identically in tick order")
}

internal func runXcmdExportOriginalChecks(_ report: CheckReport) {
    xcmdPairSharedSelectorRebuiltAsSameTickPairs(report)
    xcmdPairDanglingKnownSelectorRemoved(report)
    xcmdPairUnknownEpochAndStrayRunPreservedVerbatim(report)
    xcmdPairExplicitPointsRebuiltInTickOrder(report)
}
