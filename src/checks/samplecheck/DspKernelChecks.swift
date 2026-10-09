import Foundation
import PorydawSample

internal func runDspKernelChecks(_ report: CheckReport) {
    dspResamplePassband(report)
    dspResampleAlias(report)
    dspResampleDc(report)
    dspResampleImpulse(report)
    dspResampleFrequency(report)
    dspResampleIdentity(report)
    dspQuantization(report)
    dspMarkers(report)
    dspNormalization(report)
    dspNormalizationBoundaries(report)
    dspSeam(report)
}

private func dspResamplePassband(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::resamplePassband")
    let ratio = 13379.0 / 44100.0
    var withinBand = true
    for frequency in [100.0, 500, 1000, 2000, 4000, 5000, 5500, 6000] {
        let input = genSineFast(44100, frequency, 0.3, 0.5)
        let length = Int((Double(input.count) * ratio).rounded())
        let output = SampleDsp.resampleSinc(input, ratio: ratio, outCount: length)
        let amplitude = toneAmp(output, 13379, frequency, length / 5, length * 4 / 5)
        withinBand = withinBand && abs(20.0 * log10(amplitude / 0.5)) <= 0.1
    }
    check.expect(withinBand, message: "A001 passband 100–6000 Hz stays within 0.1 dB")
}

private func dspResampleAlias(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::resampleAliasRejection")
    let ratio = 13379.0 / 44100.0
    var rejected = true
    for frequency in [8000.0, 10000.0, 14000.0] {
        let input = genSine(44100, frequency, 0.3, 0.5)
        let length = Int((Double(input.count) * ratio).rounded())
        let output = SampleDsp.resampleSinc(input, ratio: ratio, outCount: length)
        rejected = rejected && rmsOf(output, length / 5, length * 4 / 5) <= 0.5 / sqrt(2.0) * 1e-4
    }
    check.expect(rejected, message: "A002 aliases 8, 10, 14 kHz remain below −80 dB")
}

private func dspResampleDc(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::resampleDcGain")
    let ratio = 13379.0 / 44100.0
    let input = [Float](repeating: 0.25, count: Int(44100 * 0.2))
    let length = Int((Double(input.count) * ratio).rounded())
    let output = SampleDsp.resampleSinc(input, ratio: ratio, outCount: length)
    check.expect(
        (100..<(length - 100)).allSatisfy { (index: Int) -> Bool in abs(Double(output[index]) - 0.25) <= 1e-4 },
        message: "A003 interior DC gain retains 0.25 within 1e-4")
}

private func dspResampleImpulse(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::resampleImpulseSymmetry")
    var input = [Float](repeating: 0, count: 4000)
    input[2000] = 1
    let output = SampleDsp.resampleSinc(input, ratio: 0.5, outCount: 2000)
    check.expect(output[1000] > 0.1, message: "A004 centered impulse survives decimation")
    check.expect(
        (1...500).allSatisfy { (distance: Int) -> Bool in
            abs(Double(output[1000 + distance]) - Double(output[1000 - distance])) <= 2e-6
        }, message: "A005 impulse has symmetric taps within 2e-6")
}

private func dspResampleFrequency(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::resampleFrequencyAccuracy")
    let ratio = 13379.0 / 44100.0
    let input = genSine(44100, 1000, 1.2, 0.5)
    let length = Int((Double(input.count) * ratio).rounded())
    let output = SampleDsp.resampleSinc(input, ratio: ratio, outCount: length)
    var bestFrequency = 0.0
    var bestAmplitude = -1.0
    for step in 0...80 {
        let frequency = 998.0 + Double(step) * 0.05
        let amplitude = toneAmp(output, 13379, frequency, 0, length)
        if amplitude > bestAmplitude {
            bestAmplitude = amplitude
            bestFrequency = frequency
        }
    }
    check.expect(abs(bestFrequency - 1000.0) <= 0.5, message: "A006 resampled 1 kHz stays within 0.5 Hz")
}

private func dspResampleIdentity(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::resampleIdentity")
    var random: UInt32 = 12345
    let input: [Float] = (0..<5000).map { (_: Int) -> Float in
        random = random &* 1_664_525 &+ 1_013_904_223
        return Float(Double(random) / 4_294_967_296.0 - 0.5)
    }
    let output = SampleDsp.resampleSinc(input, ratio: 1, outCount: input.count)
    check.expect(output.count == input.count, message: "A007 identity preserves sample count")
    check.expect(
        zip(input, output).allSatisfy { $0.bitPattern == $1.bitPattern },
        message: "A008 identity preserves every float bit pattern")
}

private func dspQuantization(_ report: CheckReport) {
    let vectors = report.scoped(cppID: "samplecheck/SampleProcessingTest::quantizationVectors")
    let golden: [(Double, Int8)] = [
        (1, 127), (-1, -128), (127.5 / 128, 127), (-127.5 / 128, -128),
        (127.0 / 128, 127), (-127.0 / 128, -127), (0.5, 64), (-0.5, -64),
        (1e-9, 0), (-1e-9, -1), (0, 0),
    ]
    vectors.expect(
        golden.allSatisfy { SampleDsp.quantizeToAgb8($0.0) == $0.1 },
        message: "A009 quantizer matches fork floor/clamp golden vectors")

    let roundtrip = report.scoped(cppID: "samplecheck/SampleProcessingTest::quantizationU8Roundtrip")
    roundtrip.expect(
        (0..<256).allSatisfy { (value: Int) -> Bool in
            Int(SampleDsp.quantizeToAgb8(Double(value - 128) / 128.0)) == value - 128
        }, message: "A010 unsigned PCM roundtrips every byte through signed quantization")

    let dither = report.scoped(cppID: "samplecheck/SampleProcessingTest::quantizationDither")
    var random: UInt32 = 999
    let noise: [Float] = (0..<2000).map { (_: Int) -> Float in
        random = random &* 1_664_525 &+ 1_013_904_223
        return Float(Double(random) / 4_294_967_296.0 - 0.5)
    }
    let dithered = SampleDsp.quantizeBuffer(noise, dither: true)
    dither.expect(
        SampleDsp.quantizeBuffer(noise, dither: true) == dithered,
        message: "A011 fixed-seed TPDF gives byte-identical repeated renders")
    dither.expect(
        SampleDsp.quantizeBuffer(noise, dither: false) != dithered,
        message: "A012 TPDF actually changes the signed PCM")
}

private func dspMarkers(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::markerMapping")
    let samples: [Float] = [0.5, 0.5, 0.5, 0.5, -0.5, -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, 0.5]
    check.expect(SampleDsp.nearestZeroCrossing(samples, 5) == 4, message: "A013 nearest left crossing")
    check.expect(SampleDsp.nearestZeroCrossing(samples, 7) == 8, message: "A014 nearest right crossing")
    check.expect(SampleDsp.nearestZeroCrossing(samples, 0) == 4, message: "A015 nearest edge crossing")
    check.expect(SampleDsp.mapMarker(2000, cropStart: 500, ratio: 0.5) == 750, message: "A016 cropped half-rate marker")
    check.expect(
        SampleDsp.mapMarker(2001, cropStart: 0, ratio: 13379.0 / 44100.0) == 607,
        message: "A017 downsampled inclusive loop marker")
}

private func dspNormalization(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::normalization")
    let tone = genSine(13379, 440, 0.5, 0.11)
    let normalizedTone = SampleDsp.normalizeGain(tone, loopedMode: true, loopStart: 0)
    let rms = sqrt(tone.reduce(0.0) { $0 + pow(Double($1) * normalizedTone.gain, 2) } / Double(tone.count))
    check.expect(
        abs(20.0 * log10(rms / SampleDsp.targetLoopRms)) < 0.1,
        message: "A018 loop-region RMS gain stays within 0.1 dB of target")
    check.expect(normalizedTone.warning == nil, message: "A019 normal looped sample has no warning")

    var crest = genSine(13379, 440, 0.5, 0.05)
    crest[100] = 0.9
    let crestGain = SampleDsp.normalizeGain(crest, loopedMode: true, loopStart: 0).gain
    let peak = crest.reduce(0.0) { max($0, abs(Double($1) * crestGain)) }
    check.expect(peak <= SampleDsp.peakCeiling + 1e-9, message: "A020 looped crest never exceeds peak ceiling")
    check.expect(abs(peak - SampleDsp.peakCeiling) < 1e-6, message: "A021 crest reaches peak ceiling")

    let hit = genSine(13379, 200, 0.1, 0.4)
    let hitGain = SampleDsp.normalizeGain(hit, loopedMode: false, loopStart: 0).gain
    let hitPeak = hit.reduce(0.0) { max($0, abs(Double($1) * hitGain)) }
    check.expect(abs(hitPeak - SampleDsp.peakCeiling) < 1e-6, message: "A022 one-shot reaches peak ceiling")

    let quiet = SampleDsp.normalizeGain([Float](repeating: 0.01, count: 1000), loopedMode: false, loopStart: 0)
    check.expect(quiet.gain == 1.0, message: "A023 near-silent sample is not amplified")
    check.expect(quiet.warning == "silent sample — auto-normalize skipped.", message: "A024 near-silent warning")
}

private func dspNormalizationBoundaries(_ report: CheckReport) {
    let check = report.scoped(cppID: "swiftcore/SampleDsp::normalizationBoundaries")
    var silentLoop = [Float](repeating: 0, count: 32)
    silentLoop[0] = 0.5
    let loopRefusal = SampleDsp.normalizeGain(silentLoop, loopedMode: true, loopStart: 8)
    check.expect(
        loopRefusal.gain == 1 && loopRefusal.warning == "silent loop region — auto-normalize skipped.",
        message: "silent loop refuses normalization despite a loud attack")
    let capped = SampleDsp.normalizeGain([0.04], loopedMode: false, loopStart: 0)
    check.expect(
        capped.gain == SampleDsp.maxAutoGain && capped.warning == "automatic gain capped at +24 dB.",
        message: "automatic gain above +24 dB is capped with warning")
}

private func dspSeam(_ report: CheckReport) {
    let check = report.scoped(cppID: "swiftcore/SampleDsp::seamMetrics")
    let samples: [Int8] = [4, 6, 8, 10, 12, 14, 16, 18, 20, 22]
    let seam = SampleDsp.seamMetrics(samples, loopStart: 4, loopEnd: 7)
    check.expect(
        seam.valid && seam.ampLsb == 8 && seam.derivLsb == 0 && seam.nccValid
            && abs(seam.ncc - 856.0 / sqrt(1464.0 * 504.0)) < 1e-12,
        message: "seam reports signed-eight click and compares real post-loop tail for NCC")
    let fromZero = SampleDsp.seamMetrics(samples, loopStart: 0, loopEnd: 7)
    check.expect(fromZero.valid && !fromZero.nccValid, message: "seam NCC unavailable without pre-loop context")
    let trimmed = SampleDsp.seamMetrics(Array(samples[0...7]), loopStart: 4, loopEnd: 7)
    check.expect(
        trimmed.nccValid && abs(trimmed.ncc - 648.0 / sqrt(920.0 * 504.0)) < 1e-12,
        message: "exported seam wraps the NCC comparison into its loop")
}
