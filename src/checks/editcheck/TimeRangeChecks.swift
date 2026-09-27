import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func runTimeEditsSuite(_ report: CheckReport) {
    rangeEditing(report)
    coreRangeCorpusChecks(report)
    coreTimeCorpusChecks(report)
    rangeMovement(report)
    removalAndSeams(report)
    insertionAndBoundaries(report)
    duplicationAndGlobals(report)
    coreTimeXcmdTimeTraffic(report)
    coreTimeXcmdRangeEdits(report)
    runClipboardEditingSuite(report)
    runClipboardCodecSuite(report)
}
