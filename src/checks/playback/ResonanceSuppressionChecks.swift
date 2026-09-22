import Foundation
import PorydawApp

func runResonanceSuppressionChecks(_ report: CheckReport) {
    resonanceLawChecks(report)
    resonanceTimingChecks(report)
    resonanceTransitionChecks(report)
}

private func resonanceTransitionChecks(_ report: CheckReport) {
    typealias P = ResonanceCheckFixture
    let id = "no-row/ResonanceSuppression::enableResetAndChunking"
    var params = ResonanceParameters()
    params.forceMaskOne = true
    let source = P.noise(0.3, 0.7, 123)
    let expected = P.render(source, params)
    let processor = P.processor(params)
    var output = source
    P.feed(&output, processor, chunk: 137)
    report.expect(P.exact(output, expected), cppID: id, message: "arbitrary chunk sizes preserve output")
    processor.reset()
    output = source
    P.feed(&output, processor)
    report.expect(P.exact(output, expected), cppID: id, message: "reset discards history without disabling")
    processor.setEnabled(false)
    var disabled = source
    P.feed(&disabled, processor)
    report.expect(P.exact(disabled, source), cppID: id, message: "disable restores immediate bit-exact identity")
    processor.setEnabled(true)
    output = source
    P.feed(&output, processor)
    report.expect(P.exact(output, expected), cppID: id, message: "reenable primes from silence")
    // Repeated enable requests do not reset an already enabled pipeline.
    let uninterrupted = P.processor(params)
    let repeated = P.processor(params)
    var first = source, second = source
    P.feed(&first, uninterrupted)
    P.feed(&second, repeated, to: 4096)
    repeated.setEnabled(true)
    P.feed(&second, repeated, from: 4096)
    report.expect(P.exact(first, second), cppID: id, message: "same-state generation does not re-prime")
}
