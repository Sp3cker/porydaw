import Foundation
import PorydawCore

@MainActor
func runEventEditsSuite(_ report: CheckReport) {
    trackEditing(report)
    trackNameRoles(report)
    rawTempoAndSignatureEditing(report)
    runRawEventOriginalChecks(report)
    laneEditing(report)
    coreEventAutomationGestureCoreSeams(report)
    trackCreateDeleteContract(report)
    trackDuplicateContract(report)
    trackMoveContract(report)
    trackMarkerNameContract(report)
    trackDeleteRescueContract(report)
    trackRenameContract(report)
    documentTrackContracts(report)
    coreTrackCorpusChecks(report)
    songTimeSignatureContract(report)
    unsignedTicksAndRawSignaturePrecedence(report)
    loopCfgUndoRedoContract(report)
    formatZeroCoercionContract(report)
    formatZeroGlobalsContract(report)
    formatZeroSaveRoundTripContract(report)
    markerVersusTrackNameContract(report)
    duplicateLaneAndTempoLoadContract(report)
    duplicateCanonicalizationContract(report)
    duplicateReplacementsAndNoOpsContract(report)
    xcmdSaveSnapshotContract(report)
    runEventViewsEditsParityChecks(report)
    runEventViewsRemapBucketsParityChecks(report)
}

@MainActor
func runXcmdEditsSuite(_ report: CheckReport) {
    xcmdPairedProjection(report)
    runXcmdProjectionOriginalChecks(report)
    xcmdPairedRewrite(report)
    runXcmdRewritesOriginalChecks(report)
    runXcmdOpaqueOriginalChecks(report)
    xcmdPairedReconciliation(report)
    xcmdPairedExport(report)
    runXcmdRawreconciliationOriginalChecks(report)
    runXcmdExportOriginalChecks(report)
}

func runMidiImportSuite(_ report: CheckReport) {
    importAnalysis(report)
    importSmfReportRows(report)
    importTransforms(report)
}

func chunksSortedByTick(_ file: MidiFile) -> Bool {
    file.chunks.allSatisfy { chunk in
        zip(chunk.events, chunk.events.dropFirst()).allSatisfy { $0.0.tick <= $0.1.tick }
    }
}

func channelFields(_ event: MidiEvent) -> (data0: UInt8, data1: UInt8)? {
    guard case let .channel(_, data0, data1) = event.payload else { return nil }
    return (data0, data1)
}

internal func bareTrackNameCount(_ chunk: MidiChunk) -> Int {
    var insideChannelPrefixSpan = false
    var count = 0
    for event in chunk.events {
        if case let .meta(type, data) = event.payload, type == 0x20, !data.isEmpty {
            insideChannelPrefixSpan = true
            continue
        }
        if event.isChannel {
            insideChannelPrefixSpan = false
            continue
        }
        if case let .meta(type, _) = event.payload, type == 0x03, !insideChannelPrefixSpan {
            count += 1
        }
    }
    return count
}

