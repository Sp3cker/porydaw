import Foundation
import PorydawCore

@MainActor
internal func xcmdPairedReconciliation(_ report: CheckReport) {
    let opaque = [
        Xcmd.Event(index: 0, tick: 1, stream: 0, controller: 0x1E, value: 0x2A, channel: 3),
        Xcmd.Event(index: 1, tick: 2, stream: 0, controller: 0x1D, value: 0x7F, channel: 3),
    ]
    report.expect(Xcmd.reconcile(opaque, removing: [0], moving: [], copying: []) == nil,
                  cppID: "xcmdcheck/XcmdTest::partialOpaqueOperationsRejected",
                  message: "partial opaque removal rejects")
    let moved = Xcmd.reconcile(opaque, removing: [], moving: [
        Xcmd.Relocation(index: 0, tick: 10, channel: 5),
        Xcmd.Relocation(index: 1, tick: 11, channel: 5),
    ], copying: [])
    report.expectEqual(expected: [UInt64(0), 1], actual: moved?.inserts.compactMap(\.sourceIndex),
                       cppID: "xcmdcheck/XcmdTest::wholeOpaqueRelocationIsByteExact",
                       what: "whole opaque epoch names original bytes")
}

private func xcmdPairWholeOpaqueRelocationIsByteExact(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(9, 1, 0, Xcmd.selectorController, 0x01), xcmdPairEvent(2, 2, 0, Xcmd.payloadController, 1),
        xcmdPairEvent(7, 3, 0, Xcmd.payloadController, 2), xcmdPairEvent(3, 4, 0, Xcmd.payloadController, 3),
        xcmdPairEvent(4, 5, 0, Xcmd.payloadController, 4)]
    let moves: [Xcmd.Relocation] = [
        Xcmd.Relocation(index: 9, tick: 30, channel: 4), Xcmd.Relocation(index: 2, tick: 10, channel: 5), Xcmd.Relocation(index: 2, tick: 10, channel: 5),
        Xcmd.Relocation(index: 7, tick: 10, channel: 6), Xcmd.Relocation(index: 3, tick: 20, channel: 7), Xcmd.Relocation(index: 4, tick: 20, channel: 8),
    ]
    let patch = Xcmd.reconcile(events, removing: [], moving: moves, copying: [])
    report.expect(patch != nil && patch!.removeEvents == [2, 3, 4, 7, 9] &&
                 patch!.inserts.count == 5 && patch!.inserts[0].sourceIndex == 2 &&
                 patch!.inserts[0].tick == 10 && patch!.inserts[0].channel == 5 &&
                 patch!.inserts[1].sourceIndex == 7 && patch!.inserts[1].tick == 10 &&
                 patch!.inserts[1].channel == 6 && patch!.inserts[2].sourceIndex == 3 &&
                 patch!.inserts[2].tick == 20 && patch!.inserts[2].channel == 7 &&
                 patch!.inserts[3].sourceIndex == 4 && patch!.inserts[3].tick == 20 &&
                 patch!.inserts[3].channel == 8 && patch!.inserts[4].sourceIndex == 9 &&
                 patch!.inserts[4].tick == 30 && patch!.inserts[4].channel == 4,
        cppID: "xcmdcheck/XcmdTest::wholeOpaqueRelocationIsByteExact",
        message: "whole opaque relocation did not preserve sorted byte-exact emissions")
}

private func xcmdPairPartialOpaqueOperationsRejected(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x01),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 1),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 2)]
    let partialMoves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: partialMoves, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::partialOpaqueOperationsRejected",
        message: "partial opaque relocation was not rejected")
    let partialCopies: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: [], copying: partialCopies) == nil,
        cppID: "xcmdcheck/XcmdTest::partialOpaqueOperationsRejected",
        message: "partial opaque copy was not rejected")
    let mixedRemovals: [UInt64] = [0]
    let mixedMoves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0),
                                                      Xcmd.Relocation(index: 2, tick: 21, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: mixedRemovals, moving: mixedMoves, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::partialOpaqueOperationsRejected",
        message: "mixed remove/move within one opaque epoch was not rejected")
}

private func xcmdPairConflictingDuplicateRawOpsRejected(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34)]
    let conflicting: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0),
                                                       Xcmd.Relocation(index: 1, tick: 21, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: conflicting, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::conflictingDuplicateRawOpsRejected",
        message: "conflicting duplicate raw destinations were accepted")
    let removals: [UInt64] = [1]
    let moves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: removals, moving: moves, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::conflictingDuplicateRawOpsRejected",
        message: "mixed raw operations on one byte were accepted")
}

private func xcmdPairWholeOpaqueCopyDuplicatesBytes(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x01),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 1),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 2)]
    let copies: [Xcmd.Relocation] = [
        Xcmd.Relocation(index: 0, tick: 20, channel: 0), Xcmd.Relocation(index: 1, tick: 21, channel: 0), Xcmd.Relocation(index: 2, tick: 22, channel: 0)]
    let patch = Xcmd.reconcile(events, removing: [], moving: [], copying: copies)
    report.expect(patch != nil && patch!.removeEvents.isEmpty && patch!.inserts.count == 3 &&
                 patch!.inserts[0].sourceIndex == 0 && patch!.inserts[0].tick == 20 &&
                 patch!.inserts[1].sourceIndex == 1 && patch!.inserts[1].tick == 21 &&
                 patch!.inserts[2].sourceIndex == 2 && patch!.inserts[2].tick == 22,
        cppID: "xcmdcheck/XcmdTest::wholeOpaqueCopyDuplicatesBytes",
        message: "whole opaque copy did not duplicate every byte")
    let mixedMoves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 0, tick: 20, channel: 0),
                                                      Xcmd.Relocation(index: 1, tick: 21, channel: 0)]
    let mixedCopies: [Xcmd.Relocation] = [Xcmd.Relocation(index: 2, tick: 22, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: mixedMoves, copying: mixedCopies) == nil,
        cppID: "xcmdcheck/XcmdTest::wholeOpaqueCopyDuplicatesBytes",
        message: "mixed move/copy in one opaque epoch was not rejected")
}

private func xcmdPairWholeEpochRemovalLeavesNothingBehind(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x01),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 1),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 2)]
    let payloadOnly: [UInt64] = [1, 2]
    report.expect(Xcmd.reconcile(events, removing: payloadOnly, moving: [], copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::wholeEpochRemovalLeavesNothingBehind",
        message: "removing only payload bytes of an opaque epoch was accepted")
    let wholeEpoch: [UInt64] = [0, 1, 2]
    let patch = Xcmd.reconcile(events, removing: wholeEpoch, moving: [], copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1, 2] &&
                 patch!.inserts.isEmpty,
        cppID: "xcmdcheck/XcmdTest::wholeEpochRemovalLeavesNothingBehind",
        message: "whole-epoch removal left bytes behind")
}

private func xcmdPairWholeStrayRunRelocationIsByteExact(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.payloadController, 9),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 10)]
    let partialMoves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 0, tick: 20, channel: 3)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: partialMoves, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::wholeStrayRunRelocationIsByteExact",
        message: "partial stray-run relocation was not rejected")
    let wholeMoves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 0, tick: 20, channel: 3),
                                                      Xcmd.Relocation(index: 1, tick: 21, channel: 3)]
    let patch = Xcmd.reconcile(events, removing: [], moving: wholeMoves, copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1] &&
                 patch!.inserts.count == 2 && patch!.inserts[0].sourceIndex == 0 &&
                 patch!.inserts[1].sourceIndex == 1,
        cppID: "xcmdcheck/XcmdTest::wholeStrayRunRelocationIsByteExact",
        message: "whole stray-run relocation was not byte-exact")
}

private func xcmdPairKnownPointMoveRebuildsEpoch(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 35)]
    let moves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0)]
    let patch = Xcmd.reconcile(events, removing: [], moving: moves, copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1, 2] &&
                 patch!.inserts.count == 4 && patch!.inserts[0].tick == 3 &&
                 patch!.inserts[0].value == 0x08 && patch!.inserts[1].value == 35 &&
                 patch!.inserts[2].tick == 20 && patch!.inserts[2].value == 0x08 &&
                 patch!.inserts[3].value == 34,
        cppID: "xcmdcheck/XcmdTest::knownPointMoveRebuildsEpoch",
        message: "known-point move did not rebuild the epoch canonically")
}

private func xcmdPairKnownPointCopyRebuildsBothCanonically(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 35)]
    let copies: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0)]
    let patch = Xcmd.reconcile(events, removing: [], moving: [], copying: copies)
    report.expect(patch != nil && patch!.removeEvents == [0, 1, 2] &&
                 patch!.inserts.count == 6 && patch!.inserts[0].value == 0x08 &&
                 patch!.inserts[1].value == 34 && patch!.inserts[2].value == 0x08 &&
                 patch!.inserts[3].value == 35 && patch!.inserts[4].value == 0x08 &&
                 patch!.inserts[5].value == 34 && patch!.inserts[0].sourceIndex == nil &&
                 patch!.inserts[1].sourceIndex == nil &&
                 patch!.inserts[2].sourceIndex == nil &&
                 patch!.inserts[3].sourceIndex == nil &&
                 patch!.inserts[4].sourceIndex == nil &&
                 patch!.inserts[5].sourceIndex == nil,
        cppID: "xcmdcheck/XcmdTest::knownPointCopyRebuildsBothCanonically",
        message: "known-point copy did not rebuild both copies canonically")
}

private func xcmdPairMixedKnownEpochOpsRebuildPointByPoint(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
                                   xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 35)]
    let removals: [UInt64] = [2]
    let moves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 1, tick: 20, channel: 0)]
    let patch = Xcmd.reconcile(events, removing: removals, moving: moves, copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1, 2] &&
                 patch!.inserts.count == 2 && patch!.inserts[0].tick == 20 &&
                 patch!.inserts[0].value == 0x08 && patch!.inserts[1].value == 34,
        cppID: "xcmdcheck/XcmdTest::mixedKnownEpochOpsRebuildPointByPoint",
        message: "mixed remove/move within a known epoch was not rebuilt point-by-point")
}

private func xcmdPairRawRemovalOfLonePointKillsEpoch(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34)]
    let removals: [UInt64] = [1]
    let patch = Xcmd.reconcile(events, removing: removals, moving: [], copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1] &&
                 patch!.inserts.isEmpty,
        cppID: "xcmdcheck/XcmdTest::rawRemovalOfLonePointKillsEpoch",
        message: "raw removal of a lone point left the epoch behind")
}

private func xcmdPairStaleAndCrossEpochRawDestinationsRejected(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
        xcmdPairEvent(2, 3, 0, Xcmd.selectorController, 0x03), xcmdPairEvent(3, 4, 0, Xcmd.payloadController, 9)]
    let staleMoves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 7, tick: 20, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: staleMoves, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::staleAndCrossEpochRawDestinationsRejected",
        message: "raw move of a stale identity was not rejected")
    let selectorIntoOtherMoves: [Xcmd.Relocation] = [Xcmd.Relocation(index: 0, tick: 3, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: selectorIntoOtherMoves, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::staleAndCrossEpochRawDestinationsRejected",
        message: "selector glue move inside another epoch's span was not rejected")
    let intoOtherMoves: [Xcmd.Relocation] = [
        Xcmd.Relocation(index: 1, tick: 3, channel: 0)]
    report.expect(Xcmd.reconcile(events, removing: [], moving: intoOtherMoves, copying: []) == nil,
        cppID: "xcmdcheck/XcmdTest::staleAndCrossEpochRawDestinationsRejected",
        message: "raw move inside another epoch's span was not rejected")
}

private func xcmdPairKnownSelectorGlueIgnoredAndOwnEpochMoveRebuilt(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
        xcmdPairEvent(2, 3, 0, Xcmd.selectorController, 0x03), xcmdPairEvent(3, 4, 0, Xcmd.payloadController, 9)]
    let selectorMoves: [Xcmd.Relocation] = [
        Xcmd.Relocation(index: 0, tick: 20, channel: 0)]
    let selectorPatch = Xcmd.reconcile(events, removing: [], moving: selectorMoves, copying: [])
    report.expect(selectorPatch != nil && selectorPatch!.removeEvents.isEmpty && selectorPatch!.inserts.isEmpty,
        cppID: "xcmdcheck/XcmdTest::knownSelectorGlueIgnoredAndOwnEpochMoveRebuilt",
        message: "raw move of known-epoch selector glue was not ignored")
    let ownEpochMoves: [Xcmd.Relocation] = [
        Xcmd.Relocation(index: 1, tick: 2, channel: 0)]
    let patch = Xcmd.reconcile(events, removing: [], moving: ownEpochMoves, copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1] &&
                 patch!.inserts.count == 2,
        cppID: "xcmdcheck/XcmdTest::knownSelectorGlueIgnoredAndOwnEpochMoveRebuilt",
        message: "raw move within its own epoch was not rebuilt")
}

private func xcmdPairCutVacatesSpanForLaterMove(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 96, 0, Xcmd.selectorController, 0x08),
                                   xcmdPairEvent(1, 96, 0, Xcmd.payloadController, 34),
                                   xcmdPairEvent(2, 192, 0, Xcmd.selectorController, 0x09),
                                   xcmdPairEvent(3, 192, 0, Xcmd.payloadController, 17)]
    let removals: [UInt64] = [0, 1]
    let moves: [Xcmd.Relocation] = [
        Xcmd.Relocation(index: 3, tick: 96, channel: 0)]
    let patch = Xcmd.reconcile(events, removing: removals, moving: moves, copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1, 2, 3] &&
                 patch!.inserts.count == 2 && patch!.inserts[0].tick == 96 &&
                 patch!.inserts[0].value == 0x09 && patch!.inserts[1].value == 17,
        cppID: "xcmdcheck/XcmdTest::cutVacatesSpanForLaterMove",
        message: "whole-song cut could not move onto a removed epoch's span")
}

private func xcmdPairRelocatedEpochVacatesItsSpan(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x03), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 9),
        xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 10), xcmdPairEvent(3, 5, 0, Xcmd.selectorController, 0x08),
        xcmdPairEvent(4, 5, 0, Xcmd.payloadController, 34)]
    let moves: [Xcmd.Relocation] = [
        Xcmd.Relocation(index: 0, tick: 40, channel: 0), Xcmd.Relocation(index: 1, tick: 41, channel: 0), Xcmd.Relocation(index: 2, tick: 42, channel: 0),
        Xcmd.Relocation(index: 4, tick: 2, channel: 0)]
    let patch = Xcmd.reconcile(events, removing: [], moving: moves, copying: [])
    report.expect(patch != nil && patch!.removeEvents == [0, 1, 2, 3, 4] &&
                 patch!.inserts.count == 5 && patch!.inserts[0].tick == 2 &&
                 patch!.inserts[0].value == 0x08 && patch!.inserts[1].value == 34 &&
                 patch!.inserts[2].sourceIndex == 0 && patch!.inserts[2].tick == 40 &&
                 patch!.inserts[3].sourceIndex == 1 && patch!.inserts[4].sourceIndex == 2,
        cppID: "xcmdcheck/XcmdTest::relocatedEpochVacatesItsSpan",
        message: "move onto a fully relocated opaque epoch's span was not accepted")
}

internal func runXcmdRawreconciliationOriginalChecks(_ report: CheckReport) {
    xcmdPairWholeOpaqueRelocationIsByteExact(report)
    xcmdPairPartialOpaqueOperationsRejected(report)
    xcmdPairConflictingDuplicateRawOpsRejected(report)
    xcmdPairWholeOpaqueCopyDuplicatesBytes(report)
    xcmdPairWholeEpochRemovalLeavesNothingBehind(report)
    xcmdPairWholeStrayRunRelocationIsByteExact(report)
    xcmdPairKnownPointMoveRebuildsEpoch(report)
    xcmdPairKnownPointCopyRebuildsBothCanonically(report)
    xcmdPairMixedKnownEpochOpsRebuildPointByPoint(report)
    xcmdPairRawRemovalOfLonePointKillsEpoch(report)
    xcmdPairStaleAndCrossEpochRawDestinationsRejected(report)
    xcmdPairKnownSelectorGlueIgnoredAndOwnEpochMoveRebuilt(report)
    xcmdPairCutVacatesSpanForLaterMove(report)
    xcmdPairRelocatedEpochVacatesItsSpan(report)
}
