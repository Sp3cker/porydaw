import Foundation
import PorydawSample

internal func runSampleChecks(_ report: CheckReport) {
    runDecoderChecks(report)
    runCompressedDecoderChecks(report)
    runSoundFontChecks(report)
    runDspKernelChecks(report)
    runRenderPipelineChecks(report)
    runAnalysisChecks(report)
    runRegistrationChecks(report)
}
