import Foundation
import PorydawSample

internal func runSamplePitchChecks(_ report: CheckReport, key: Int) {
    let matrix = report.scoped(cppID: "samplecheck/SampleProcessingTest::pitchMatrix")
    for rate in [8000.0, 13379.0, 22050.0, 44100.0] {
        let frequency = 440 * pow(2, Double(key - 69) / 12)
        let sine = SampleDsp.detectPitchYin(genSine(rate, frequency, 1.5, 0.4), rate: rate)
        matrix.expect(
            sine.pitched && abs(centsOff(sine.f0, frequency)) <= 5,
            message: "sine key \(key) at \(rate) Hz is within five cents")
        let saw = SampleDsp.detectPitchYin(genSaw(rate, frequency, 1.5, 0.4), rate: rate)
        matrix.expect(
            saw.pitched && abs(centsOff(saw.f0, frequency)) <= 5,
            message: "saw key \(key) at \(rate) Hz is within five cents")
    }
}

internal func runAnalysisChecks(_ report: CheckReport) {
    let negative = report.scoped(cppID: "samplecheck/SampleProcessingTest::pitchNegativeCases")
    var noise = [Float](repeating: 0, count: 13379 * 2)
    var rng: UInt32 = 0xA5A5_A5A5
    for index in noise.indices {
        rng = rng &* 1_664_525 &+ 1_013_904_223
        noise[index] = Float((Double(rng) / 4_294_967_296 - 0.5) * 0.8)
    }
    negative.expect(
        !SampleDsp.detectPitchYin(noise, rate: 13379).pitched,
        message: "white noise reports unpitched")
    let short = Array(genSine(13379, 440, 0.4, 0.4).prefix(4000))
    negative.expect(
        !SampleDsp.detectPitchYin(short, rate: 13379).pitched,
        message: "fewer than three frames reports unpitched")

    let loop = report.scoped(cppID: "samplecheck/SampleProcessingTest::loopAndCrossfade")
    let rate = 13379.0
    let count = Int(rate * 2)
    var tone = [Float](repeating: 0, count: count)
    for index in tone.indices {
        let time = Double(index) / rate
        let envelope = 1 - 0.10 * Double(index) / Double(count)
        tone[index] = Float(0.35 * envelope * sin(2 * .pi * 440 * time + 0.5 * sin(2 * .pi * 5 * time)))
    }
    let pitch = SampleDsp.detectPitchYin(tone, rate: rate)
    loop.expect(
        pitch.pitched && abs(centsOff(pitch.f0, 440)) < 20,
        message: "vibrato tone detects near 440 Hz")
    let period = rate / (pitch.pitched ? pitch.f0 : 440)
    let candidates = SampleDsp.suggestLoop(
        tone, rate: rate, period: period,
        regionA: Int((0.4 * Double(count)).rounded()), regionB: count - 1)
    loop.expect(!candidates.isEmpty, message: "vibrato tone yields loop candidates")
    loop.expect(candidates.first?.passedGates == true, message: "top candidate passes the gates")
    loop.expect(candidates.first.map { $0.ncc >= 0.95 } == true, message: "top candidate NCC >= 0.95")
    let quantized = SampleDsp.quantizeBuffer(tone, dither: false)
    let seam = candidates.first.map { SampleDsp.seamMetrics(quantized, loopStart: $0.loopStart, loopEnd: $0.loopEnd) }
    loop.expect(
        seam.map { $0.valid && $0.ampLsb <= 2 && $0.derivLsb <= 3 } == true,
        message: "top candidate post-quantize seam within click bounds")
    loop.expect(
        candidates.first.map { candidate in
            let length = Double(candidate.loopEnd + 1 - candidate.loopStart)
            let multiple = (length / period).rounded()
            return multiple >= 1 && abs(length - multiple * period) <= 0.01 * length
        } == true, message: "loop length within 1% of an integer period multiple")

    rng = 0xC0FF_EE01
    for index in noise.indices {
        rng = rng &* 1_664_525 &+ 1_013_904_223
        noise[index] = Float((Double(rng) / 4_294_967_296 - 0.5) * 0.8)
    }
    let noisy = SampleDsp.suggestLoop(
        noise, rate: rate, period: 0,
        regionA: Int((0.4 * Double(count)).rounded()), regionB: count - 1)
    loop.expect(noisy.first.map { $0.ncc < 0.5 } == true, message: "white noise yields no clean loop")
    var stepped = [Float](repeating: 0, count: count)
    for index in stepped.indices {
        let amplitude = index < count / 2 ? 0.4 : 0.2
        stepped[index] = Float(amplitude * sin(2 * .pi * 440 * Double(index) / rate))
    }
    let stepCandidates = SampleDsp.suggestLoop(
        stepped, rate: rate, period: rate / 440,
        regionA: Int((0.4 * Double(count)).rounded()), regionB: count - 1)
    loop.expect(
        stepCandidates.first?.passedGates == true,
        message: "amplitude-step tone still finds a clean same-level loop")
    loop.expect(
        !stepCandidates.contains { $0.passedGates && $0.loopStart < count / 2 && $0.loopEnd >= count / 2 },
        message: "no gate-passing candidate spans the amplitude step")
    var refinedWithoutRegression = false
    if let top = candidates.first {
        var start = top.loopStart + 3
        var end = top.loopEnd - 2
        let before = SampleDsp.seamMetrics(quantized, loopStart: start, loopEnd: end).ncc
        SampleDsp.refineLoop(tone, period: period, loopStart: &start, loopEnd: &end)
        let after = SampleDsp.seamMetrics(quantized, loopStart: start, loopEnd: end).ncc
        refinedWithoutRegression = after >= before - 1e-9
    }
    loop.expect(refinedWithoutRegression, message: "refine never worsens the seam correlation")
    let stub = genSine(rate, 440, 300 / rate, 0.4)
    loop.expect(
        SampleDsp.suggestLoop(stub, rate: rate, period: 200, regionA: 0, regionB: stub.count - 1).isEmpty,
        message: "window-starved pitched buffer returns no candidates")
}
