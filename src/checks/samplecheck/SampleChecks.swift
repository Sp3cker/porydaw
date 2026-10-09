import Foundation
import PorydawSample
@testable import SwiftCoreCheckLogic

@MainActor
public func runSampleChecks(_ report: CheckReport) {
    runDecoderChecks(report)
    runCompressedDecoderChecks(report)
    runSoundFontChecks(report)
}

public func runSampleProcessingChecks(_ report: CheckReport) {
    runDspKernelChecks(report)
}

public func runSampleStorageChecks(_ report: CheckReport) {
    runRegistrationChecks(report)
    runProvenanceChecks(report)
}

@MainActor
public func runSampleEditorChecks(_ report: CheckReport) {
    runEditorPresenterChecks(report)
    runLoopToolsChecks(report)
    runAuditionStripChecks(report)
    runWaveformChecks(report)
}
