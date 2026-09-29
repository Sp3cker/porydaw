import Foundation
import PorydawSample

@MainActor
internal func runSampleChecks(_ report: CheckReport) {
    runDecoderChecks(report)
    runCompressedDecoderChecks(report)
    runSoundFontChecks(report)
    runDspKernelChecks(report)
    runRenderPipelineChecks(report)
    runAnalysisChecks(report)
    runRegistrationChecks(report)
    runProvenanceChecks(report)
    runEditorPresenterChecks(report)
    runLoopToolsChecks(report)
}
