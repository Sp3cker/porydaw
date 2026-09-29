import Foundation
import PorydawSample

internal func runSampleChecks(_ report: CheckReport) {
    runDecoderChecks(report)
    runCompressedDecoderChecks(report)
}
