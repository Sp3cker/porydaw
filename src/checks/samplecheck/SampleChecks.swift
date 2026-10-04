import Foundation
import PorydawSample

@MainActor
internal func runSampleChecks(_ report: CheckReport) {
    runDecoderChecks(report)
    runCompressedDecoderChecks(report)
    runSoundFontChecks(report)
}

internal func runSampleProcessingChecks(_ report: CheckReport) {
    runDspKernelChecks(report)
    runRenderPipelineChecks(report)
    runAnalysisChecks(report)
}

internal func runSampleStorageChecks(_ report: CheckReport) {
    runRegistrationChecks(report)
    runProvenanceChecks(report)
}

@MainActor
internal func runSampleEditorChecks(_ report: CheckReport) {
    runEditorPresenterChecks(report)
    runLoopToolsChecks(report)
    runAuditionStripChecks(report)
    runWaveformChecks(report)
}
