import Foundation
import PorydawApp

// Signal generators and independent probes translated from resonancefixture.cpp.
// Numeric acceptance bounds come from tst_resonancelaw.cpp/tst_resonancetiming.cpp.
private enum ResonanceProbe {
    static let rate = 48_000.0
    static let latency = 2047
    static func frames(_ seconds: Double) -> Int { Int((seconds * rate).rounded()) }
    static func curve(_ depth: Float) -> ResonanceParameters {
        var p = ResonanceParameters()
        p.gDb = depth
        for i in 5...11 { p.knotActive[i] = true }
        return p
    }
    static func fill(_ signal: inout [Float], begin: Int, end: Int, frequency: Double,
                     db: Double, add: Bool = false, rate: Double = ResonanceProbe.rate) {
        let amplitude = Double(Float(pow(10, db / 20)))
        let omega = 2 * Double.pi * frequency / rate
        for frame in begin..<min(end, signal.count / 2) {
            let value = Float(amplitude * sin(omega * Double(frame)))
            for c in 0..<2 {
                if add { signal[2 * frame + c] += value }
                else { signal[2 * frame + c] = value }
            }
        }
    }
    static func sine(_ seconds: Double, _ frequency: Double, _ db: Double,
                     onset: Double = 0, rate: Double = ResonanceProbe.rate) -> [Float] {
        let count = Int((seconds * rate).rounded())
        var signal = [Float](repeating: 0, count: count * 2)
        fill(&signal, begin: Int((onset * rate).rounded()), end: count,
             frequency: frequency, db: db, rate: rate)
        return signal
    }
    static func noise(_ seconds: Double, _ scale: Float, _ seed: UInt32) -> [Float] {
        var state = seed
        return (0..<(frames(seconds) * 2)).map { _ in
            state = state &* 1664525 &+ 1013904223
            return (Float(state >> 8) * (2 / 16777216) - 1) * scale
        }
    }
    static func feed(_ signal: inout [Float], _ processor: ResonanceSuppression,
                     from: Int = 0, to: Int? = nil, chunk: Int = 512) {
        let end = to ?? signal.count / 2
        signal.withUnsafeMutableBufferPointer { buffer in
            for frame in stride(from: from, to: end, by: chunk) {
                processor.process(buffer.baseAddress! + frame * 2, frames: UInt32(min(chunk, end - frame)))
            }
        }
    }
    static func processor(_ p: ResonanceParameters, rate: Float = 48000) -> ResonanceSuppression {
        let result = ResonanceSuppression(sampleRate: rate)
        result.setParameters(p)
        result.setEnabled(true)
        return result
    }
    static func render(_ signal: [Float], _ p: ResonanceParameters = ResonanceParameters(),
                       enabled: Bool = true) -> [Float] {
        let engine = processor(p)
        engine.setEnabled(enabled)
        var result = signal
        feed(&result, engine)
        return result
    }
    static func amplitude(_ signal: [Float], _ begin: Int, _ count: Int, _ frequency: Double) -> Double {
        guard count > 0 && begin + count <= signal.count / 2 else { return -300 }
        let omega = 2 * Double.pi * frequency / rate
        var real = 0.0, imag = 0.0
        for n in 0..<count {
            let sample = Double(signal[(begin + n) * 2])
            real += sample * cos(omega * Double(n))
            imag -= sample * sin(omega * Double(n))
        }
        return 20 * log10(max(2 * hypot(real, imag) / Double(count), 1e-300))
    }
    static func rms(_ signal: [Float], _ begin: Int, _ count: Int) -> Double {
        let end = min(begin + count, signal.count / 2)
        var power = 0.0
        for i in (begin * 2)..<(end * 2) { power += Double(signal[i]) * Double(signal[i]) }
        return 10 * log10(max(power / Double((end - begin) * 2), 1e-300))
    }
    static func exact(_ lhs: [Float], _ rhs: [Float], from: Int = 0) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return (from * 2..<lhs.count).allSatisfy { lhs[$0].bitPattern == rhs[$0].bitPattern }
    }
    static func reduction(_ output: [Float], source: Double, frequency: Double = 1000,
                          db: Double = -15, window: Double = 0.1) -> Double {
        db - amplitude(output, frames(source) + latency, frames(window), frequency)
    }
}

func runResonanceSuppressionChecks(_ report: CheckReport) {
    resonanceLawChecks(report)
    resonanceTimingChecks(report)
    resonanceTransitionChecks(report)
}

private func resonanceLawChecks(_ report: CheckReport) {
    typealias P = ResonanceProbe
    func expect(_ condition: Bool, _ name: String, _ detail: String) {
        report.expect(condition, cppID: "resonancecheck/ResonanceLawTest::" + name, message: detail)
    }
    do {
        let input = P.noise(1, 0.7, 0x13579bdf)
        expect(P.exact(input, P.render(input, enabled: false)), "disabledPathIsBitExact", "disabled noise is bit-exact")
        var params = ResonanceParameters()
        params.forceMaskOne = true
        let source = P.noise(1, 0.7, 0x2468ace0)
        let output = P.render(source, params)
        var error = 0.0, power = 0.0
        for i in (P.latency * 2)..<source.count {
            let sample = Double(source[i - P.latency * 2])
            let delta = Double(output[i]) - sample
            error += delta * delta; power += sample * sample
        }
        let errorDb = 10 * log10(max(error / power, 1e-300))
        expect(errorDb <= -120, "unitMaskReconstructionFloor", "reconstruction \(errorDb) dB <= -120")
    }
    do {
        let input = P.sine(2, 1000, -118)
        let output = P.render(input)
        let delta = P.amplitude(output, P.frames(1.5) + P.latency, P.frames(0.1), 1000)
            - P.amplitude(input, P.frames(1.5), P.frames(0.1), 1000)
        expect(abs(delta) <= 0.1, "belowThresholdTonePasses", "below-threshold change \(delta) dB")
    }
    do {
        let output = P.render(P.sine(4, 3000, -30, onset: 1))
        let reduction = P.reduction(output, source: 3, frequency: 3000, db: -30)
        expect(abs(reduction - 5.9375) <= 1, "shippingDefaultLimitsSaturatedResonance", "shipping ceiling \(reduction) dB")
        let wide = P.render(P.sine(4, 1000, -30, onset: 1), P.curve(3))
        let plateau = P.reduction(wide, source: 3, db: -30)
        expect(abs(plateau - 9.375) <= 1, "testCurvePlateauAboveGuard", "wide curve plateau \(plateau) dB")
        let low = P.render(P.sine(4, 300, -15, onset: 1), P.curve(8))
        expect(abs(P.reduction(low, source: 3, frequency: 300)) <= 0.1,
               "lowBandTonePassesThrough", "300 Hz passes within 0.1 dB")
    }
    do {
        let output = P.render(P.sine(4, 1000, -10, onset: 1), P.curve(3))
        var deepest = -300.0
        for source in stride(from: P.frames(2), to: P.frames(3.5), by: P.frames(0.1)) {
            deepest = max(deepest, -10 - P.amplitude(output, source + P.latency, P.frames(0.1), 1000))
        }
        let final = P.reduction(output, source: 3, db: -10)
        expect(abs(final - 9.375) <= 1 && deepest <= 10.5, "saturationPlateausWithoutOvershoot",
               "final \(final), deepest \(deepest) dB")
    }
    do {
        let levels: [Double] = [-63, -40, -20, -10, -3]
        let warmup = P.frames(2), dwell = P.frames(1.5)
        var input = [Float](repeating: 0, count: 2 * (warmup + dwell * levels.count + P.frames(0.2)))
        P.fill(&input, begin: 0, end: warmup, frequency: 1000, db: levels[0])
        for (index, db) in levels.enumerated() {
            P.fill(&input, begin: warmup + index * dwell, end: warmup + (index + 1) * dwell, frequency: 1000, db: db)
        }
        let output = P.render(input, P.curve(8))
        let reductions = levels.enumerated().map { index, db in
            db - P.amplitude(output, warmup + index * dwell + P.frames(1.25) + P.latency, P.frames(0.1), 1000)
        }
        expect(reductions.allSatisfy { abs($0 - 25) <= 1 } && reductions.max()! - reductions.min()! < 0.5,
               "levelStaircaseHoldsPlateau", "staircase reductions \(reductions)")
    }
    do {
        var input = P.sine(20, 1000, -15)
        P.fill(&input, begin: 0, end: input.count / 2, frequency: 12000, db: -40, add: true)
        let output = P.render(input, P.curve(8))
        let first = P.reduction(output, source: 19)
        let second = P.reduction(output, source: 19, frequency: 12000, db: -40)
        expect(abs(first - 25) <= 1 && abs(second - 25) <= 1, "dualTonesEngageSeparately", "dual reductions \(first), \(second)")
    }
    do {
        let input = P.noise(5, 0.3, 0x0badcafe)
        let output = P.render(input, P.curve(8))
        let delta = abs(P.rms(input, P.frames(4), P.frames(0.5)) - P.rms(output, P.frames(4) + P.latency, P.frames(0.5)))
        expect(delta <= 0.5, "broadbandProgramPasses", "noise RMS change \(delta) dB")
        for loud in [true, false] {
            let db = loud ? -15.0 : -25.0
            var embedded = input
            P.fill(&embedded, begin: P.frames(1), end: embedded.count / 2, frequency: 3000, db: db, add: true)
            let processed = P.render(embedded, P.curve(8))
            let reduction = P.reduction(processed, source: 4, frequency: 3000, db: db)
            let rmsDelta = abs(P.rms(embedded, P.frames(4), P.frames(0.5)) - P.rms(processed, P.frames(4) + P.latency, P.frames(0.5)))
            let name = loud ? "embeddedLoudToneEngagesProgramSurvives" : "embeddedModestToneEngagesGently"
            expect(loud ? reduction >= 10 : (reduction >= 1.5 && reduction <= 8.5), name, "embedded reduction \(reduction) dB")
            expect(rmsDelta <= (loud ? 3.5 : 1.5), name, "program RMS change \(rmsDelta) dB")
        }
    }
    do {
        var input = P.noise(2, 0.8, 0x31415926)
        for frame in 0..<input.count / 2 { input[2 * frame + 1] = input[2 * frame] }
        let output = P.render(input)
        expect((0..<output.count / 2).allSatisfy { output[2 * $0].bitPattern == output[2 * $0 + 1].bitPattern },
               "stereoChannelsStayBitIdentical", "identical channels remain bit-identical")
        let source = P.sine(4, 1000, 0)
        var bypass = source
        let processor = P.processor(ResonanceParameters())
        let disable = 512 * 200
        P.feed(&bypass, processor, to: disable)
        processor.setEnabled(false)
        P.feed(&bypass, processor, from: disable)
        expect(P.exact(source, bypass, from: disable), "midStreamDisableRestoresBypass", "midstream disable is bit-exact")
    }
    do {
        var input = [Float](repeating: 0, count: P.frames(2) * 2)
        for frame in 0..<input.count / 2 {
            let value = Float(0.5 + 0.5 * sin(2 * Double.pi * 12000 / P.rate * Double(frame))
                + 0.178 * sin(2 * Double.pi * 23500 / P.rate * Double(frame)))
            input[2 * frame] = value; input[2 * frame + 1] = value
        }
        let processor = P.processor(P.curve(8))
        P.feed(&input, processor)
        expect(processor.binGainDb(0) == 0 && processor.binGainDb(1024) == 0 && processor.binGainDb(1003) < -1,
               "guardBinsNeverMasked", "DC/Nyquist untouched while neighboring tone engages")
    }
}

private func resonanceTimingChecks(_ report: CheckReport) {
    typealias P = ResonanceProbe
    func expect(_ condition: Bool, _ name: String, _ detail: String) {
        report.expect(condition, cppID: "resonancecheck-timing/ResonanceTimingTest::" + name, message: detail)
    }
    do {
        let second = P.frames(11)
        var output = [Float](repeating: 0, count: P.frames(12.5) * 2)
        P.fill(&output, begin: 0, end: P.frames(3), frequency: 1000, db: -15)
        P.fill(&output, begin: second, end: output.count / 2, frequency: 1000, db: -15)
        let processor = P.processor(P.curve(8))
        P.feed(&output, processor, to: second)
        let recovered42 = processor.binGainDb(42), recovered43 = processor.binGainDb(43)
        P.feed(&output, processor, from: second)
        let old = P.reduction(output, source: 2.5)
        var best = 300.0
        for source in stride(from: second + P.frames(0.01), to: second + P.frames(0.8) - P.frames(0.05), by: P.frames(0.01)) {
            best = min(best, -15 - P.amplitude(output, source + P.latency, P.frames(0.05), 1000))
        }
        expect(recovered42 >= -1 && recovered43 >= -1, "releaseRecoversAcrossGap", "released gains \(recovered42), \(recovered43)")
        expect(old > 10 && best <= old * 0.3, "releaseRecoversAcrossGap", "re-gate \(best), old \(old) dB")
    }
    do {
        var signal = P.sine(60, 1000, -15)
        let processor = P.processor(P.curve(8))
        P.feed(&signal, processor, to: P.frames(8))
        let early = processor.binGainDb(43)
        P.feed(&signal, processor, from: P.frames(8), to: P.frames(59))
        let late = processor.binGainDb(43)
        expect(abs(early - late) <= 0.1, "plateauHoldsSixtySeconds", "early \(early), late \(late) dB")
    }
    do {
        let output = P.render(P.sine(6, 1000, -15, onset: 1), P.curve(8))
        let final = P.reduction(output, source: 4.5)
        var t63 = -1.0
        for source in stride(from: P.frames(1.1), through: P.frames(3), by: P.frames(0.01)) {
            if -15 - P.amplitude(output, source + P.latency, P.frames(0.1), 1000) >= 0.63 * final {
                t63 = Double(source - P.frames(1)) / P.rate
                break
            }
        }
        expect(t63 >= 0.075 && t63 <= 0.225, "attackReachesSixtyThreePercent", "attack t63 \(t63) seconds")
    }
    for rate in [48000.0, 44100.0] {
        let bin = rate == 48000 ? 43 : 46
        var signal = P.sine(4, 1000, -15, onset: rate == 48000 ? 1 : 0, rate: rate)
        let processor = P.processor(P.curve(8), rate: Float(rate))
        var previous = 0.0, largest = 0.0
        var havePrevious = false
        for frame in stride(from: 0, to: signal.count / 2, by: 512) {
            P.feed(&signal, processor, from: frame, to: min(frame + 512, signal.count / 2))
            let current = processor.binGainDb(bin)
            if havePrevious { largest = max(largest, abs(current - previous)) }
            previous = current; havePrevious = true
        }
        let name = rate == 48000 ? "hopStepCapAt48kHz" : "rateParameterizedLawHoldsAt44kHz"
        expect(largest <= 102400 / rate + 1e-3, name, "largest hop step \(largest) dB at \(rate) Hz")
        if rate == 44100 { expect(abs(processor.binGainDb(bin) + 25) <= 1, name, "44.1 kHz -25 dB plateau") }
    }
}

private func resonanceTransitionChecks(_ report: CheckReport) {
    typealias P = ResonanceProbe
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
